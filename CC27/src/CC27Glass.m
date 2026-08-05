#import "CC27.h"
#import <objc/message.h>

@implementation CC27Glass

+ (CGFloat)cornerRadiusForSize:(CGSize)size {
    CGFloat w = size.width;
    CGFloat h = size.height;
    if (w < 1 || h < 1) return 19.0;
    // 1x1 → circle; tall/wide pills → half min side; large squares → softer continuous radius
    if (fabs(w - h) < 8.0 && w < 110.0) return w * 0.5;
    if (fabs(w - h) >= 8.0) return fmin(w, h) * 0.5;
    return fmin(w, h) * 0.28;
}

+ (void)applyContinuousCorners:(UIView *)view radius:(CGFloat)radius {
    if (!view) return;
    view.layer.cornerRadius = radius;
    view.clipsToBounds = YES;
    if (@available(iOS 13.0, *)) {
        view.layer.cornerCurve = kCACornerCurveContinuous;
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"
    if ([view.layer respondsToSelector:@selector(setContinuousCorners:)]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(view.layer, @selector(setContinuousCorners:), YES);
    }
#pragma clang diagnostic pop
    view.layer.borderWidth = 0.6;
    view.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.28].CGColor;
}

+ (void)applyToModuleContainer:(UIView *)view {
    if (!view || !CC27Prefs.shared.glassChrome) return;
    CGFloat radius = [self cornerRadiusForSize:view.bounds.size];
    [self applyContinuousCorners:view radius:radius];

    // Soft inner highlight — Liquid Glass edge light without fighting MTMaterialView.
    const NSInteger tag = 0x43323747; // 'C27G'
    UIView *highlight = [view viewWithTag:tag];
    if (!highlight) {
        highlight = [[UIView alloc] initWithFrame:CGRectZero];
        highlight.tag = tag;
        highlight.userInteractionEnabled = NO;
        highlight.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.12];
        [view insertSubview:highlight atIndex:0];
    }
    CGFloat w = view.bounds.size.width;
    CGFloat h = view.bounds.size.height;
    highlight.frame = CGRectMake(1.0, 1.0, MAX(0, w - 2.0), MAX(1.0, h * 0.42));
    highlight.layer.cornerRadius = MAX(0, radius - 1.0);
    if (@available(iOS 13.0, *)) {
        highlight.layer.cornerCurve = kCACornerCurveContinuous;
        highlight.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    }
    highlight.clipsToBounds = YES;
}

@end
