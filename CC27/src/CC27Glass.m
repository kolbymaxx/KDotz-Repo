#import "CC27.h"
#import <objc/message.h>

@implementation CC27Glass

+ (CGFloat)cornerRadiusForSize:(CGSize)size {
    CGFloat w = size.width;
    CGFloat h = size.height;
    if (w < 1 || h < 1) return 19.0;

    CGFloat minSide = fmin(w, h);
    // Compact near-square → circle (iOS 26 1x1 look)
    if (fabs(w - h) < 12.0 && minSide <= 120.0) {
        return minSide * 0.5;
    }
    // Pills / sliders → half of the short side
    if (fabs(w - h) >= 12.0) {
        return minSide * 0.5;
    }
    // Larger squares (2x2 connectivity / media)
    return minSide * 0.28;
}

+ (BOOL)_looksExpanded:(UIView *)view {
    if (!view) return NO;
    CGSize size = view.bounds.size;
    // Expanded long-press menus are much larger than grid cells.
    if (size.width > 260.0 || size.height > 260.0) return YES;
    if (size.width > 200.0 && size.height > 200.0 && fabs(size.width - size.height) > 30.0) return YES;

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

+ (void)_roundView:(UIView *)view radius:(CGFloat)radius clip:(BOOL)clip {
    if (!view) return;
    view.layer.cornerRadius = radius;
    view.clipsToBounds = clip;
    view.layer.masksToBounds = clip;
    if (@available(iOS 13.0, *)) {
        view.layer.cornerCurve = kCACornerCurveContinuous;
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"
    if ([view.layer respondsToSelector:@selector(setContinuousCorners:)]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(view.layer, @selector(setContinuousCorners:), YES);
    }
#pragma clang diagnostic pop
}

+ (void)applyContinuousCorners:(UIView *)view radius:(CGFloat)radius {
    // Collapsed modules: clip so materials actually look round.
    [self _roundView:view radius:radius clip:YES];
    view.layer.borderWidth = 0.55;
    view.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.28].CGColor;
}

+ (void)_roundMaterialSubviews:(UIView *)view radius:(CGFloat)radius {
    Class mat = NSClassFromString(@"MTMaterialView");
    Class platter = NSClassFromString(@"CCUIContentModuleContentContainerView");
    for (UIView *sub in view.subviews) {
        if (mat && [sub isKindOfClass:mat]) {
            [self _roundView:sub radius:radius clip:YES];
        }
        // Don't recurse into nested module containers.
        if (platter && [sub isKindOfClass:platter]) continue;
        if (sub.subviews.count) [self _roundMaterialSubviews:sub radius:radius];
    }
}

+ (void)applyToModuleContainer:(UIView *)view {
    if (!view || !CC27Prefs.shared.glassChrome) return;

    // Expanded popovers: do not clip — that cut Camera / Connectivity menus.
    if ([self _looksExpanded:view]) {
        view.clipsToBounds = NO;
        view.layer.masksToBounds = NO;
        view.layer.cornerRadius = 28.0;
        view.layer.borderWidth = 0;
        UIView *highlight = [view viewWithTag:0x43323747];
        highlight.hidden = YES;
        return;
    }

    CGFloat radius = [self cornerRadiusForSize:view.bounds.size];
    [self applyContinuousCorners:view radius:radius];
    [self _roundMaterialSubviews:view radius:radius];

    const NSInteger tag = 0x43323747; // 'C27G'
    UIView *highlight = [view viewWithTag:tag];
    if (!highlight) {
        highlight = [[UIView alloc] initWithFrame:CGRectZero];
        highlight.tag = tag;
        highlight.userInteractionEnabled = NO;
        highlight.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.12];
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
