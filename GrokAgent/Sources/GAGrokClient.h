#import <Foundation/Foundation.h>

/// LLM client. xAI's API is OpenAI-compatible, so this class is really a
/// generic chat-completions client — pointing GABaseURL somewhere else is
/// enough to swap brains later.
NS_ASSUME_NONNULL_BEGIN

@interface GAGrokClient : NSObject

+ (instancetype)shared;

/// One turn of chat completion with tool calling.
/// `messages` is the full conversation so far (the API is stateless).
/// `message` in the callback is the raw assistant message dict: it may contain
/// "content", "tool_calls", or both.
- (void)completeWithMessages:(NSArray<NSDictionary *> *)messages
                       tools:(NSArray<NSDictionary *> *_Nullable)tools
                  completion:(void (^)(NSDictionary *_Nullable message,
                                       NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
