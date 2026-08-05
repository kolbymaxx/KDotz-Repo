#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface OmniAIScreenCapture : NSObject

/// Capture the frontmost key window hierarchy, downscale, and JPEG-compress.
/// Returns nil on failure. Heavy work runs under an autorelease pool; the
/// caller owns the returned NSData only.
+ (nullable NSData *)captureJPEGWithMaxDimension:(CGFloat)maxDimension
                                         quality:(CGFloat)quality;

/// Convenience: max edge 1280px, JPEG quality 0.55 — good multimodal budget.
+ (nullable NSData *)captureOptimizedJPEG;

/// Base64 of optimized capture, or nil.
+ (nullable NSString *)captureOptimizedBase64;

@end

NS_ASSUME_NONNULL_END
