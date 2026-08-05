#import <Foundation/Foundation.h>
#import "OmniAICommon.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^OmniAICompletion)(NSString * _Nullable reply, NSError * _Nullable error);

@interface OmniAIManager : NSObject

+ (instancetype)shared;

/// Text-only request: selected text + user prompt.
- (void)sendText:(nullable NSString *)selectedText
          prompt:(NSString *)prompt
        provider:(OmniAIProvider)provider
      completion:(OmniAICompletion)completion;

/// Screen-aware / multimodal: optional selected text + prompt + JPEG bytes.
- (void)sendPrompt:(NSString *)prompt
      selectedText:(nullable NSString *)selectedText
         imageJPEG:(nullable NSData *)imageJPEG
          provider:(OmniAIProvider)provider
        completion:(OmniAICompletion)completion;

/// Convenience: capture screen (if requested) then send.
- (void)sendPrompt:(NSString *)prompt
      selectedText:(nullable NSString *)selectedText
   includeScreen:(BOOL)includeScreen
          provider:(OmniAIProvider)provider
        completion:(OmniAICompletion)completion;

- (BOOL)isSignedInForProvider:(OmniAIProvider)provider;
- (nullable NSString *)accountLabelForProvider:(OmniAIProvider)provider;

/// OpenAI-compatible chat completions with optional tool schemas (used by the
/// iOS MCP agent loop — Grok / xAI bearer session required).
- (void)completeWithMessages:(NSArray<NSDictionary *> *)messages
                       tools:(nullable NSArray<NSDictionary *> *)tools
                  completion:(void (^)(NSDictionary *_Nullable message,
                                       NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
