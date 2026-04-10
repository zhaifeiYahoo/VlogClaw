/**
 * VlogClawAgent Runner
 * UI Test Bundle entry point - starts the WDA HTTP server with LLM capabilities
 */

#import <XCTest/XCTest.h>
#import <WebDriverAgentLib/FBWebServer.h>
#import <WebDriverAgentLib/FBConfiguration.h>
#import <WebDriverAgentLib/FBDebugLogDelegateDecorator.h>
#import <WebDriverAgentLib/FBFailureProofTestCase.h>

@interface UITestingUITests : FBFailureProofTestCase <FBWebServerDelegate>
@end

@implementation UITestingUITests

+ (void)setUp
{
  [FBDebugLogDelegateDecorator decorateXCTestLogger];
  [FBConfiguration disableRemoteQueryEvaluation];
  [FBConfiguration configureDefaultKeyboardPreferences];
  [FBConfiguration disableApplicationUIInterruptionsHandling];
  if (NSProcessInfo.processInfo.environment[@"ENABLE_AUTOMATIC_SCREEN_RECORDINGS"]) {
    [FBConfiguration enableScreenRecordings];
  }
  if (NSProcessInfo.processInfo.environment[@"ENABLE_AUTOMATIC_SCREENSHOTS"]) {
    [FBConfiguration enableAutomaticScreenshots];
  }
  NSNumber *mjpegScalingFactor = [NSProcessInfo.processInfo.environment[@"MJPEG_SCALING_FACTOR"] integerValue] > 0
    ? @( [NSProcessInfo.processInfo.environment[@"MJPEG_SCALING_FACTOR"] integerValue] )
    : nil;
  if (mjpegScalingFactor) {
    [FBConfiguration setMjpegServerScalingFactor:mjpegScalingFactor];
  }
}

- (void)testRunner
{
  FBWebServer *webServer = [[FBWebServer alloc] init];
  webServer.delegate = self;
  [webServer startServing];
}

- (void)webServerDidRequestShutdown:(FBWebServer *)webServer
{
  [webServer stopServing];
}

@end
