#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface OmniAIActivationManager : NSObject

+ (instancetype)shared;

- (void)start;
- (void)activate;
- (void)activateWithSelectedText:(nullable NSString *)selectedText
                  textInputTarget:(nullable id)textInputTarget;

/// Returns YES if the press was consumed as a double-press activation.
- (BOOL)handleVolumeUpPress;

@end

NS_ASSUME_NONNULL_END
