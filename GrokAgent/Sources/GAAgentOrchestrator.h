#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, GAAgentState) {
    GAAgentStateIdle,
    GAAgentStateThinking,
    GAAgentStateActing,
    GAAgentStateSpeaking,
};

NS_ASSUME_NONNULL_BEGIN

@protocol GAAgentObserver <NSObject>
@optional
- (void)agentDidChangeState:(GAAgentState)state;
- (void)agentDidPerformStep:(NSString *)description;   // for the HUD / debug log
- (void)agentDidFinishWithReply:(NSString *_Nullable)reply error:(NSError *_Nullable)error;
@end

/// The agent loop: prompt → reason → act → observe → repeat until the model
/// stops asking for tools or we hit the step budget.
@interface GAAgentOrchestrator : NSObject

+ (instancetype)shared;

@property (nonatomic, weak) id<GAAgentObserver> observer;
@property (nonatomic, readonly) GAAgentState state;
@property (nonatomic, readonly) BOOL isRunning;

- (void)runWithPrompt:(NSString *)prompt;
- (void)cancel;

@end

NS_ASSUME_NONNULL_END
