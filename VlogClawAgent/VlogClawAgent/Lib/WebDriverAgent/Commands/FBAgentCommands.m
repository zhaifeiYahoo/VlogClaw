/**
 * VlogClawAgent - LLM-powered Agent Commands
 *
 * Registers /llm/* and /agent/* routes on the WDA HTTP server.
 * Delegates to VCLLMBridge (Swift) for all LLM operations.
 */

#import "FBAgentCommands.h"
#import <WebDriverAgentLib/VlogClawAgentLib-Swift.h>
#import "FBResponsePayload.h"
#import "FBRoute.h"
#import "FBRouteRequest.h"
#import "FBCommandStatus.h"
#import "FBSession.h"
#import "FBScreenshot.h"
#import "FBScreen.h"

@implementation FBAgentCommands

+ (NSArray *)routes
{
  return @[
    // Local LLM management
    [[FBRoute POST:@"/llm/load"] respondWithTarget:self action:@selector(handleLLMLoad:)],
    [[FBRoute DELETE:@"/llm/unload"] respondWithTarget:self action:@selector(handleLLMUnload:)],
    [[FBRoute GET:@"/llm/status"] respondWithTarget:self action:@selector(handleLLMStatus:)],

    // Remote LLM configuration
    [[FBRoute POST:@"/llm/remote/configure"] respondWithTarget:self action:@selector(handleRemoteConfigure:)],

    // Agent operations
    [[FBRoute POST:@"/agent/analyze"] respondWithTarget:self action:@selector(handleAgentAnalyze:)],
    [[FBRoute POST:@"/agent/execute"] respondWithTarget:self action:@selector(handleAgentExecute:)],
    [[FBRoute POST:@"/agent/step"] respondWithTarget:self action:@selector(handleAgentStep:)],

    // Remote agent operations
    [[FBRoute POST:@"/agent/plan"] respondWithTarget:self action:@selector(handleAgentPlan:)],
    [[FBRoute POST:@"/agent/generate_content"] respondWithTarget:self action:@selector(handleGenerateContent:)],
    [[FBRoute POST:@"/agent/decompose"] respondWithTarget:self action:@selector(handleDecompose:)],
  ];
}

#pragma mark - Local LLM Management

+ (id<FBResponsePayload>)handleLLMLoad:(FBRouteRequest *)request
{
  NSString *modelId = request.arguments[@"modelId"];
  __block BOOL success = NO;
  __block NSError *error = nil;
  dispatch_semaphore_t sem = dispatch_semaphore_create(0);

  [[VCLLMBridge shared] loadModel:modelId completion:^(BOOL ok, NSError * _Nullable err) {
    success = ok;
    error = err;
    dispatch_semaphore_signal(sem);
  }];

  dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_SEC));

  if (!success) {
    return FBResponseWithStatus([FBCommandStatus unknownErrorWithMessage:
      error.localizedDescription ?: @"Failed to load model" traceback:nil]);
  }
  return FBResponseWithOK();
}

+ (id<FBResponsePayload>)handleLLMUnload:(FBRouteRequest *)request
{
  [[VCLLMBridge shared] unloadModel];
  return FBResponseWithOK();
}

+ (id<FBResponsePayload>)handleLLMStatus:(FBRouteRequest *)request
{
  NSDictionary *status = [[VCLLMBridge shared] modelStatus];
  return FBResponseWithObject(status);
}

#pragma mark - Remote LLM Configuration

+ (id<FBResponsePayload>)handleRemoteConfigure:(FBRouteRequest *)request
{
  NSString *provider = request.arguments[@"provider"];
  NSString *apiKey = request.arguments[@"apiKey"];
  NSString *baseURL = request.arguments[@"baseURL"];

  if (!provider || !apiKey) {
    return FBResponseWithStatus([FBCommandStatus invalidArgumentErrorWithMessage:
      @"'provider' and 'apiKey' are required" traceback:nil]);
  }

  __block BOOL success = NO;
  __block NSError *error = nil;
  dispatch_semaphore_t sem = dispatch_semaphore_create(0);

  [[VCLLMBridge shared] configureRemoteProvider:provider
                                         apiKey:apiKey
                                        baseURL:baseURL
                                     completion:^(BOOL ok, NSError * _Nullable err) {
    success = ok;
    error = err;
    dispatch_semaphore_signal(sem);
  }];

  dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC));

  if (!success) {
    return FBResponseWithStatus([FBCommandStatus unknownErrorWithMessage:
      error.localizedDescription ?: @"Failed to configure remote provider" traceback:nil]);
  }
  return FBResponseWithOK();
}

#pragma mark - Agent Operations

+ (id<FBResponsePayload>)handleAgentAnalyze:(FBRouteRequest *)request
{
  NSString *goal = request.arguments[@"goal"];
  if (!goal) {
    return FBResponseWithStatus([FBCommandStatus invalidArgumentErrorWithMessage:
      @"'goal' is required" traceback:nil]);
  }

  // Get screenshot
  NSString *screenshotBase64 = request.arguments[@"screenshot"];
  if (!screenshotBase64) {
    // Take screenshot using WDA infrastructure
    screenshotBase64 = [self takeScreenshotBase64];
  }
  if (!screenshotBase64) {
    return FBResponseWithStatus([FBCommandStatus unknownErrorWithMessage:
      @"Failed to capture screenshot" traceback:nil]);
  }

  NSString *history = request.arguments[@"history"] ?: @"[]";

  __block NSString *resultJSON = nil;
  __block NSError *error = nil;
  dispatch_semaphore_t sem = dispatch_semaphore_create(0);

  [[VCLLMBridge shared] analyzeScreenshot:screenshotBase64
                                     goal:goal
                                  history:history
                               completion:^(NSString * _Nullable json, NSError * _Nullable err) {
    resultJSON = json;
    error = err;
    dispatch_semaphore_signal(sem);
  }];

  dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_SEC));

  if (error || !resultJSON) {
    return FBResponseWithStatus([FBCommandStatus unknownErrorWithMessage:
      error.localizedDescription ?: @"Analysis failed" traceback:nil]);
  }

  NSData *jsonData = [resultJSON dataUsingEncoding:NSUTF8StringEncoding];
  NSDictionary *result = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
  return FBResponseWithObject(result ?: @{@"raw": resultJSON});
}

+ (id<FBResponsePayload>)handleAgentExecute:(FBRouteRequest *)request
{
  NSString *goal = request.arguments[@"goal"];
  if (!goal) {
    return FBResponseWithStatus([FBCommandStatus invalidArgumentErrorWithMessage:
      @"'goal' is required" traceback:nil]);
  }

  NSNumber *maxSteps = request.arguments[@"maxSteps"] ?: @10;

  __block NSString *resultJSON = nil;
  __block NSError *error = nil;
  dispatch_semaphore_t sem = dispatch_semaphore_create(0);

  [[VCLLMBridge shared] executeAgentLoop:goal
                                 maxSteps:[maxSteps integerValue]
                              completion:^(NSString * _Nullable json, NSError * _Nullable err) {
    resultJSON = json;
    error = err;
    dispatch_semaphore_signal(sem);
  }];

  // Longer timeout for agent loops (up to 10 minutes)
  dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 600 * NSEC_PER_SEC));

  if (error || !resultJSON) {
    return FBResponseWithStatus([FBCommandStatus unknownErrorWithMessage:
      error.localizedDescription ?: @"Agent loop failed" traceback:nil]);
  }

  NSData *jsonData = [resultJSON dataUsingEncoding:NSUTF8StringEncoding];
  NSDictionary *result = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
  return FBResponseWithObject(result ?: @{@"raw": resultJSON});
}

+ (id<FBResponsePayload>)handleAgentStep:(FBRouteRequest *)request
{
  NSString *goal = request.arguments[@"goal"];
  if (!goal) {
    return FBResponseWithStatus([FBCommandStatus invalidArgumentErrorWithMessage:
      @"'goal' is required" traceback:nil]);
  }

  NSString *history = request.arguments[@"history"] ?: @"[]";

  __block NSString *resultJSON = nil;
  __block NSError *error = nil;
  dispatch_semaphore_t sem = dispatch_semaphore_create(0);

  [[VCLLMBridge shared] agentStep:goal
                           history:history
                        completion:^(NSString * _Nullable json, NSError * _Nullable err) {
    resultJSON = json;
    error = err;
    dispatch_semaphore_signal(sem);
  }];

  dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_SEC));

  if (error || !resultJSON) {
    return FBResponseWithStatus([FBCommandStatus unknownErrorWithMessage:
      error.localizedDescription ?: @"Agent step failed" traceback:nil]);
  }

  NSData *jsonData = [resultJSON dataUsingEncoding:NSUTF8StringEncoding];
  NSDictionary *result = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
  return FBResponseWithObject(result ?: @{@"raw": resultJSON});
}

#pragma mark - Remote Agent Operations

+ (id<FBResponsePayload>)handleAgentPlan:(FBRouteRequest *)request
{
  NSString *instruction = request.arguments[@"instruction"];
  if (!instruction) {
    return FBResponseWithStatus([FBCommandStatus invalidArgumentErrorWithMessage:
      @"'instruction' is required" traceback:nil]);
  }

  __block NSString *resultJSON = nil;
  __block NSError *error = nil;
  dispatch_semaphore_t sem = dispatch_semaphore_create(0);

  [[VCLLMBridge shared] planWorkflow:instruction
                           completion:^(NSString * _Nullable json, NSError * _Nullable err) {
    resultJSON = json;
    error = err;
    dispatch_semaphore_signal(sem);
  }];

  dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_SEC));

  if (error || !resultJSON) {
    return FBResponseWithStatus([FBCommandStatus unknownErrorWithMessage:
      error.localizedDescription ?: @"Planning failed" traceback:nil]);
  }

  NSData *jsonData = [resultJSON dataUsingEncoding:NSUTF8StringEncoding];
  NSDictionary *result = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
  return FBResponseWithObject(result ?: @{@"raw": resultJSON});
}

+ (id<FBResponsePayload>)handleGenerateContent:(FBRouteRequest *)request
{
  NSString *type = request.arguments[@"type"] ?: @"full";
  NSString *context = request.arguments[@"context"];

  if (!context) {
    return FBResponseWithStatus([FBCommandStatus invalidArgumentErrorWithMessage:
      @"'context' is required" traceback:nil]);
  }

  __block NSString *resultJSON = nil;
  __block NSError *error = nil;
  dispatch_semaphore_t sem = dispatch_semaphore_create(0);

  [[VCLLMBridge shared] generateContent:type
                                 context:context
                              completion:^(NSString * _Nullable json, NSError * _Nullable err) {
    resultJSON = json;
    error = err;
    dispatch_semaphore_signal(sem);
  }];

  dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC));

  if (error || !resultJSON) {
    return FBResponseWithStatus([FBCommandStatus unknownErrorWithMessage:
      error.localizedDescription ?: @"Content generation failed" traceback:nil]);
  }

  NSData *jsonData = [resultJSON dataUsingEncoding:NSUTF8StringEncoding];
  NSDictionary *result = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
  return FBResponseWithObject(result ?: @{@"raw": resultJSON});
}

+ (id<FBResponsePayload>)handleDecompose:(FBRouteRequest *)request
{
  NSString *instruction = request.arguments[@"instruction"];
  if (!instruction) {
    return FBResponseWithStatus([FBCommandStatus invalidArgumentErrorWithMessage:
      @"'instruction' is required" traceback:nil]);
  }

  __block NSString *resultJSON = nil;
  __block NSError *error = nil;
  dispatch_semaphore_t sem = dispatch_semaphore_create(0);

  [[VCLLMBridge shared] decomposeInstruction:instruction
                                   completion:^(NSString * _Nullable json, NSError * _Nullable err) {
    resultJSON = json;
    error = err;
    dispatch_semaphore_signal(sem);
  }];

  dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC));

  if (error || !resultJSON) {
    return FBResponseWithStatus([FBCommandStatus unknownErrorWithMessage:
      error.localizedDescription ?: @"Instruction decomposition failed" traceback:nil]);
  }

  NSData *jsonData = [resultJSON dataUsingEncoding:NSUTF8StringEncoding];
  NSDictionary *result = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
  return FBResponseWithObject(result ?: @{@"raw": resultJSON});
}

#pragma mark - Helpers

+ (NSString *)takeScreenshotBase64
{
  @try {
    XCUIDevice *device = [XCUIDevice sharedDevice];
    XCUIScreenshot *screenshot = [device screenshot];
    if (screenshot) {
      NSData *pngData = screenshot.image.PNGData;
      if (pngData) {
        return [pngData base64EncodedStringWithOptions:0];
      }
    }
  } @catch (NSException *exception) {
    // Screenshot capture failed
  }
  return nil;
}

@end
