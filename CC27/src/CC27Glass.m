#import "CC27.h"
#import <objc/message.h>

@implementation CC27Glass

+ (CGFloat)cornerRadiusForSize:(CGSize)size {
    CGFloat w = size.width;
    CGFloat h = size.height;
    if (w < 1 || h < 1) return 19.0;

    // Expanded / popup-sized containers: soft continuous radius only.
    // Never force a full circle — that clips Camera / Connectivity menus.
    CGFloat minSide = fmin(w, h);
    CGFloat maxSide = fmax(w, h);
    if (maxSide > 220.0 || (w > 160.0 && h > 160.0 && fabs(w - h) > 40.0)) {
        return 28.0;
    }

    // Compact 1x1-ish modules: near-pill / circle look without over-clipping.
    if (fabs(w - h) < 10.0 && minSide < 120.0) {
        return minSide * 0.42;
    }
    // Tall/wide pills (sliders, 2x1)
    if (fabs(w - h) >= 10.0) {
        return minSide * 0.42;
    }
    return minSide * 0.28;
}

+ (BOOL)_looksExpanded:(UIView *)view {
    if (!view) return NO;
    CGSize size = view.bounds.size;
    if (size.width > 240.0 || size.height > 240.0) return YES;
    // Expanded modules often grow far beyond the compact grid cell.
    if (size.width > 180.0 && size.height > 180.0) return YES;

    // Walk up for an expanded-state flag when present.
    UIView *v = view;
    while (v) {
        @try {
            id expanded = [v valueForKey:@"expanded"];
            if ([expanded respondsToSelector:@selector(boolValue)] && [expanded boolValue]) return YES;
        } @catch (__unused NSException *e) {}
        @try {
            id expanded = [v valueForKey:@"isExpanded"];
            if ([expanded respondsToSelector:@selector(boolValue)] && [expanded boolValue]) return YES;
        } @catch (__unused NSException *e) {}
        v = v.superview;
    }
    return NO;
}

+ (void)applyContinuousCorners:(UIView *)view radius:(CGFloat)radius {
    if (!view) return;
    view.layer.cornerRadius = radius;
    // Critical: never clip module containers — expanded menus draw outside
    // the collapsed bounds and get cut into circles otherwise.
    view.clipsToBounds = NO;
    view.layer.masksToBounds = NO;
    if (@available(iOS 13.0, *)) {
        view.layer.cornerCurve = kCACornerCurveContinuous;
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"
    if ([view.layer respondsToSelector:@selector(setContinuousCorners:)]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(view.layer, @selector(setContinuousCorners:), YES);
    }
#pragma clang diagnostic pop
    view.layer.borderWidth = 0.55;
    view.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.26].CGColor;
}

+ (void)applyToModuleContainer:(UIView *)view {
    if (!view || !CC27Prefs.shared.glassChrome) return;

    // Expanded popovers / long-press menus: leave stock chrome alone.
    if ([self _looksExpanded:view]) {
        view.clipsToBounds = NO;
        view.layer.masksToBounds = NO;
        view.layer.borderWidth = 0;
        UIView *highlight = [view viewWithTag:0x43323747];
        highlight.hidden = YES;
        return;
    }

    CGFloat radius = [self cornerRadiusForSize:view.bounds.size];
    [self applyContinuousCorners:view radius:radius];

    const NSInteger tag = 0x43323747; // 'C27G'
    UIView *highlight = [view viewWithTag:tag];
    if (!highlight) {
        highlight = [[UIView alloc] initWithFrame:CGRectZero];
        highlight.tag = tag;
        highlight.userInteractionEnabled = NO;
        highlight.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.10];
        [view insertSubview:highlight atIndex:0];
    }
    highlight.hidden = NO;
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
