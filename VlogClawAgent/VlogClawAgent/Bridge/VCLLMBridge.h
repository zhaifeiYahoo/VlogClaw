#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Swift/ObjC bridge for LLM and Agent functionality.
 * ObjC command handlers call this to invoke Swift LLM services.
 */
@interface VCLLMBridge : NSObject

/// Shared singleton instance
+ (instancetype)shared;

#pragma mark - Local LLM Management

/// Load a local Gemma 4 model by ID (e.g. "gemma-4-e2b-it-4bit")
- (void)loadModel:(nullable NSString *)modelID
       completion:(void (^)(BOOL success, NSError * _Nullable error))completion;

/// Unload the local model and free memory
- (void)unloadModel;

/// Whether a local model is currently loaded
@property (nonatomic, readonly) BOOL isModelLoaded;

/// Get current model status as a dictionary
- (NSDictionary *)modelStatus;

#pragma mark - Screenshot Analysis (Local LLM)

/// Analyze a screenshot and suggest the next action
- (void)analyzeScreenshot:(NSString *)screenshotBase64
                    goal:(NSString *)goal
                 history:(NSString *)historyJSON
              completion:(void (^)(NSString * _Nullable actionJSON, NSError * _Nullable error))completion;

#pragma mark - Remote LLM Configuration

/// Configure remote LLM provider (OpenAI or Claude)
- (void)configureRemoteProvider:(NSString *)provider
                         apiKey:(NSString *)apiKey
                      baseURL:(nullable NSString *)baseURL
                    completion:(void (^)(BOOL success, NSError * _Nullable error))completion;

/// Whether a remote provider is configured
@property (nonatomic, readonly) BOOL isRemoteConfigured;

#pragma mark - Agent Operations

/// Execute a full agent loop: screenshot -> analyze -> act -> repeat
- (void)executeAgentLoop:(NSString *)goal
                maxSteps:(NSInteger)maxSteps
              completion:(void (^)(NSString * _Nullable resultJSON, NSError * _Nullable error))completion;

/// Single agent step: take screenshot, analyze, execute one action
- (void)agentStep:(NSString *)goal
          history:(NSString *)historyJSON
       completion:(void (^)(NSString * _Nullable stepResultJSON, NSError * _Nullable error))completion;

#pragma mark - Remote LLM Operations

/// Generate content (titles, descriptions, tags) via remote LLM
- (void)generateContent:(NSString *)type
                context:(NSString *)context
             completion:(void (^)(NSString * _Nullable contentJSON, NSError * _Nullable error))completion;

/// Plan a complex workflow via remote LLM (e.g. video upload flow)
- (void)planWorkflow:(NSString *)instruction
           completion:(void (^)(NSString * _Nullable planJSON, NSError * _Nullable error))completion;

/// Decompose a natural language instruction into automation steps
- (void)decomposeInstruction:(NSString *)instruction
                   completion:(void (^)(NSString * _Nullable stepsJSON, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
