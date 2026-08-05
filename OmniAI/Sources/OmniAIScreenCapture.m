#import "OmniAIScreenCapture.h"
#import "OmniAICommon.h"

@implementation OmniAIScreenCapture

+ (UIWindow *)frontmostWindow {
    UIApplication *app = UIApplication.sharedApplication;
    UIWindow *key = nil;

    if (@available(iOS 15.0, *)) {
        for (UIScene *scene in app.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            UIWindowScene *ws = (UIWindowScene *)scene;
            if (ws.activationState != UISceneActivationStateForegroundActive) continue;
            for (UIWindow *w in ws.windows) {
                if (w.isKeyWindow && !w.isHidden && w.alpha > 0.01) {
                    key = w;
                    break;
                }
            }
            if (!key) {
                for (UIWindow *w in ws.windows) {
                    if (!w.isHidden && w.alpha > 0.01 && w.windowLevel <= UIWindowLevelNormal) {
                        key = w;
                        break;
                    }
                }
            }
            if (key) break;
        }
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    if (!key) key = app.keyWindow;
#pragma clang diagnostic pop

    if (!key) {
        for (UIWindow *w in app.windows) {
            if (w.isKeyWindow) { key = w; break; }
        }
    }
    return key;
}

+ (UIImage *)downscaleImage:(UIImage *)image maxDimension:(CGFloat)maxDimension {
    CGSize size = image.size;
    CGFloat longest = MAX(size.width, size.height);
    if (longest <= maxDimension || longest < 1.0) return image;

    CGFloat scale = maxDimension / longest;
    CGSize target = CGSizeMake(floor(size.width * scale), floor(size.height * scale));
    if (target.width < 1 || target.height < 1) return image;

    UIGraphicsBeginImageContextWithOptions(target, YES, 1.0);
    [image drawInRect:CGRectMake(0, 0, target.width, target.height)];
    UIImage *out = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return out ?: image;
}

+ (NSData *)captureJPEGWithMaxDimension:(CGFloat)maxDimension quality:(CGFloat)quality {
    __block NSData *result = nil;

    void (^work)(void) = ^{
        @autoreleasepool {
            UIWindow *window = [self frontmostWindow];
            if (!window) {
                OAErr(@"screen capture: no frontmost window");
                return;
            }

            // Cap render scale — full 3x retina of a large phone is expensive
            // in SpringBoard and short-lived app processes alike.
            CGFloat scale = MIN(UIScreen.mainScreen.scale, 2.0);
            CGSize boundsSize = window.bounds.size;
            if (boundsSize.width < 1 || boundsSize.height < 1) return;

            UIGraphicsBeginImageContextWithOptions(boundsSize, YES, scale);
            BOOL drawn = [window drawViewHierarchyInRect:window.bounds afterScreenUpdates:NO];
            UIImage *raw = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();

            if (!drawn || !raw) {
                OAErr(@"screen capture: drawViewHierarchy failed");
                return;
            }

            UIImage *scaled = [self downscaleImage:raw maxDimension:maxDimension];
            // Drop the full-res buffer ASAP.
            raw = nil;

            CGFloat q = MIN(MAX(quality, 0.2), 0.95);
            result = UIImageJPEGRepresentation(scaled, q);
            OALog(@"screen capture: %lu bytes (maxEdge=%.0f q=%.2f)",
                  (unsigned long)result.length, maxDimension, q);
        }
    };

    if ([NSThread isMainThread]) {
        work();
    } else {
        dispatch_sync(dispatch_get_main_queue(), work);
    }
    return result;
}

+ (NSData *)captureOptimizedJPEG {
    return [self captureJPEGWithMaxDimension:1280 quality:0.55];
}

+ (NSString *)captureOptimizedBase64 {
    NSData *jpeg = [self captureOptimizedJPEG];
    if (!jpeg.length) return nil;
    return [jpeg base64EncodedStringWithOptions:0];
}

@end
