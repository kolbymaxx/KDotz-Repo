#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface OmniAIOverlay : NSObject

+ (instancetype)shared;

/// Present the floating OmniAI panel. Optionally seed with selected text.
- (void)presentWithSelectedText:(nullable NSString *)selectedText
                 textInputTarget:(nullable id)textInputTarget;

- (void)present;
- (void)dismiss;

+ (BOOL)consumeStaleBreadcrumb;

@end

NS_ASSUME_NONNULL_END
