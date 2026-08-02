#import "Music27.h"

UIViewController *M27TopViewController(void) {
    UIWindow *keyWindow = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState != UISceneActivationStateForegroundActive) continue;
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.isKeyWindow) { keyWindow = window; break; }
        }
        if (keyWindow) break;
    }
    UIViewController *top = keyWindow.rootViewController;
    while (top) {
        if (top.presentedViewController) { top = top.presentedViewController; continue; }
        if ([top isKindOfClass:UITabBarController.class]) {
            UIViewController *selected = ((UITabBarController *)top).selectedViewController;
            if (selected) { top = selected; continue; }
        }
        if ([top isKindOfClass:UINavigationController.class]) {
            UIViewController *visible = ((UINavigationController *)top).visibleViewController;
            if (visible && visible != top) { top = visible; continue; }
        }
        break;
    }
    return top;
}

// Finds the largest UIImageView image in a hierarchy. Depth/child limits keep
// this cheap: Music's SwiftUI hierarchies can be enormous and this used to be
// an unbounded recursive walk on the main thread.
static UIImage *M27LargestImageInViewDepth(UIView *view, NSInteger depth) {
    if (!view || depth > 6) return nil;
    UIImage *best = nil;
    CGFloat bestArea = 0;
    if ([view isKindOfClass:UIImageView.class]) {
        UIImage *image = ((UIImageView *)view).image;
        CGFloat area = image.size.width * image.size.height;
        // Ignore icons/glyphs; require something that looks like artwork.
        if (image && image.size.width >= 80 && image.size.height >= 80 && area > bestArea) {
            best = image;
            bestArea = area;
        }
    }
    NSArray<UIView *> *subviews = view.subviews;
    NSInteger count = MIN((NSInteger)subviews.count, 40);
    for (NSInteger i = 0; i < count; i++) {
        UIImage *candidate = M27LargestImageInViewDepth(subviews[i], depth + 1);
        CGFloat area = candidate.size.width * candidate.size.height;
        if (candidate && area > bestArea) {
            best = candidate;
            bestArea = area;
        }
    }
    return best;
}

UIImage *M27LargestImageInView(UIView *view) {
    return M27LargestImageInViewDepth(view, 0);
}

BOOL M27ClassNameContains(NSObject *obj, NSArray<NSString *> *needles) {
    if (!obj) return NO;
    NSString *name = NSStringFromClass(obj.class).lowercaseString;
    for (NSString *needle in needles) {
        if ([name containsString:needle]) return YES;
    }
    return NO;
}
