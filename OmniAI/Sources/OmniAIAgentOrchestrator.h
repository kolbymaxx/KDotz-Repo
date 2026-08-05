#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, OmniAIAgentState) {
    OmniAIAgentStateIdle,
    OmniAIAgentStateThinking,
    OmniAIAgentStateActing,
};

NS_ASSUME_NONNULL_BEGIN

@protocol OmniAIAgentObserver <NSObject>
@optional
- (void)agentDidChangeState:(OmniAIAgentState)state;
- (void)agentDidPerformStep:(NSString *)description;
- (void)agentDidFinishWithReply:(NSString *_Nullable)reply error:(NSError *_Nullable)error;
@end

/// Agent loop backed by iOS MCP tools + an OpenAI-compatible provider (Grok).
@interface OmniAIAgentOrchestrator : NSObject

+ (instancetype)shared;

@property (nonatomic, weak) id<OmniAIAgentObserver> observer;
@property (nonatomic, readonly) OmniAIAgentState state;
@property (nonatomic, readonly) BOOL isRunning;

- (void)runWithPrompt:(NSString *)prompt;
- (void)cancel;

@end

NS_ASSUME_NONNULL_END
