#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Builds an approximate Liquid Glass pill: ultra-thin material, continuous
/// corners, soft specular edge, optional tint wash from the artwork palette.
@interface M27GlassChrome : NSObject

+ (UIVisualEffectView *)pillWithCornerRadius:(CGFloat)radius;
+ (void)applySpecularBorderToView:(UIView *)view;
+ (void)applyPaletteTintToGlass:(UIVisualEffectView *)glass;
+ (void)addSoftShadowToHost:(UIView *)host;

@end

NS_ASSUME_NONNULL_END
