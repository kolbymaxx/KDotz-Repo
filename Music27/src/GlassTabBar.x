#import "Music27.h"
#import <objc/runtime.h>

// Floating Liquid Glass tab bar + rounded mini-player.
// Inspired by the visual language of LiquidGlass-style materials: continuous
// corner curves, soft white border, light blur, and a translucent tint wash.

static const NSInteger kM27GlassTag = 0x4D323747;      // 'M27G'
static const NSInteger kM27GlassHighlightTag = 0x4D323748;
static const CGFloat kM27GlassRadius = 28.0;
static const CGFloat kM27GlassSideInset = 16.0;
static const CGFloat kM27GlassBottomInset = 8.0;
static const CGFloat kM27MiniPlayerRadius = 22.0;

// Ultra-thin material reads closest to Liquid Glass on iOS 16/17.
// (True Liquid Glass APIs are private / iOS 26+ and not in this SDK.)
static UIBlurEffectStyle M27PreferredBlurStyle(void) {
    return UIBlurEffectStyleSystemUltraThinMaterial;
}

static UIVisualEffectView *M27FindOrCreateGlass(UITabBar *tabBar) {
    UIView *existing = [tabBar viewWithTag:kM27GlassTag];
    if ([existing isKindOfClass:UIVisualEffectView.class]) {
        return (UIVisualEffectView *)existing;
    }

    UIBlurEffect *effect = [UIBlurEffect effectWithStyle:M27PreferredBlurStyle()];
    UIVisualEffectView *glass = [[UIVisualEffectView alloc] initWithEffect:effect];
    glass.tag = kM27GlassTag;
    glass.userInteractionEnabled = NO;
    glass.clipsToBounds = YES;
    glass.layer.cornerRadius = kM27GlassRadius;
    glass.layer.cornerCurve = kCACornerCurveContinuous;
    glass.layer.borderWidth = 0.5;
    glass.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.28].CGColor;

    // Soft top highlight — approximates LiquidGlass specular edge.
    UIView *highlight = [[UIView alloc] initWithFrame:CGRectZero];
    highlight.tag = kM27GlassHighlightTag;
    highlight.userInteractionEnabled = NO;
    highlight.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.18];
    [glass.contentView addSubview:highlight];

    [tabBar insertSubview:glass atIndex:0];
    return glass;
}

static void M27LayoutGlass(UIVisualEffectView *glass, UITabBar *tabBar) {
    CGFloat bottomPad = tabBar.safeAreaInsets.bottom;
    if (bottomPad <= 0) bottomPad = kM27GlassBottomInset;
    else bottomPad = MAX(kM27GlassBottomInset, bottomPad * 0.35);

    CGFloat height = MIN(MAX(tabBar.bounds.size.height - bottomPad - 2.0, 49.0), 64.0);
    CGFloat y = tabBar.bounds.size.height - height - bottomPad;
    CGFloat x = kM27GlassSideInset;
    CGFloat width = tabBar.bounds.size.width - (kM27GlassSideInset * 2.0);
    glass.frame = CGRectMake(x, y, width, height);

    UIView *highlight = [glass viewWithTag:kM27GlassHighlightTag];
    if (highlight) {
        highlight.frame = CGRectMake(1, 1, width - 2, MAX(1.0, height * 0.5));
        highlight.layer.cornerRadius = kM27GlassRadius - 1;
        highlight.layer.cornerCurve = kCACornerCurveContinuous;
        highlight.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
        highlight.clipsToBounds = YES;
    }

    // Tint the glass with the active artwork palette when available.
    M27ColorPalette *palette = M27ColorTheme.shared.activePalette;
    if (palette.glassTint) {
        glass.contentView.backgroundColor = palette.glassTint;
    } else {
        glass.contentView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
    }
}

// Marks a tab bar so we only strip its chrome once. Re-applying chrome on
// every layoutSubviews (the original bug) forced an endless relayout loop.
static const void *kM27ChromeKey = &kM27ChromeKey;

static void M27StripTabBarChromeOnce(UITabBar *tabBar) {
    if (objc_getAssociatedObject(tabBar, kM27ChromeKey)) return;
    objc_setAssociatedObject(tabBar, kM27ChromeKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    [tabBar setBackgroundImage:[UIImage new]];
    [tabBar setShadowImage:[UIImage new]];
    tabBar.translucent = YES;
    tabBar.backgroundColor = UIColor.clearColor;

    if (@available(iOS 13.0, *)) {
        UITabBarAppearance *appearance = [UITabBarAppearance new];
        [appearance configureWithTransparentBackground];
        tabBar.standardAppearance = appearance;
        tabBar.scrollEdgeAppearance = appearance;
    }
}

static void M27RestoreTabBarChrome(UITabBar *tabBar) {
    if (!objc_getAssociatedObject(tabBar, kM27ChromeKey)) return;
    objc_setAssociatedObject(tabBar, kM27ChromeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    [tabBar setBackgroundImage:nil];
    [tabBar setShadowImage:nil];
    tabBar.backgroundColor = nil;

    UIView *glass = [tabBar viewWithTag:kM27GlassTag];
    [glass removeFromSuperview];

    if (@available(iOS 13.0, *)) {
        UITabBarAppearance *appearance = [UITabBarAppearance new];
        [appearance configureWithDefaultBackground];
        tabBar.standardAppearance = appearance;
        tabBar.scrollEdgeAppearance = appearance;
    }
}

static void M27StyleMiniPlayerIfPresent(UIView *container) {
    if (!container) return;
    // Only walk immediate siblings + one level — Music's view tree is huge.
    NSMutableArray<UIView *> *candidates = [NSMutableArray arrayWithArray:container.subviews];
    for (UIView *child in container.subviews) {
        [candidates addObjectsFromArray:child.subviews];
    }

    static NSArray<NSString *> *needles;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        needles = @[ @"miniplayer", @"nowplayingbar", @"playerbar", @"transport", @"nowplayingmini" ];
    });

    for (UIView *view in candidates) {
        if (!M27ClassNameContains(view, needles)) continue;

        view.layer.cornerRadius = kM27MiniPlayerRadius;
        view.layer.cornerCurve = kCACornerCurveContinuous;
        view.clipsToBounds = YES;
        view.layer.borderWidth = 0.5;
        view.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.22].CGColor;

        M27ColorPalette *palette = M27ColorTheme.shared.activePalette;
        if (palette.background) {
            view.backgroundColor = [palette.background colorWithAlphaComponent:0.55];
        } else if (!view.backgroundColor || CGColorGetAlpha(view.backgroundColor.CGColor) < 0.05) {
            // Leave Apple's material alone when we don't have a theme.
        }
        break;
    }
}

static void M27ApplyGlassToTabBar(UITabBar *tabBar) {
    M27Prefs *prefs = M27Prefs.shared;
    if (!(prefs.enabled && prefs.glassTabBarEnabled)) {
        M27RestoreTabBarChrome(tabBar);
        return;
    }
    M27StripTabBarChromeOnce(tabBar);
    UIVisualEffectView *glass = M27FindOrCreateGlass(tabBar);
    M27LayoutGlass(glass, tabBar);
    [tabBar sendSubviewToBack:glass];
    M27StyleMiniPlayerIfPresent(tabBar.superview);
}

%hook UITabBar

- (void)layoutSubviews {
    %orig;
    M27ApplyGlassToTabBar(self);
}

- (void)didMoveToWindow {
    %orig;
    if (self.window) {
        M27ApplyGlassToTabBar(self);
    }
}

%end

%hook UITabBarController

- (void)viewDidLayoutSubviews {
    %orig;
    M27Prefs *prefs = M27Prefs.shared;
    if (!(prefs.enabled && prefs.glassTabBarEnabled)) return;
    UITabBar *tabBar = self.tabBar;
    if (tabBar) {
        M27ApplyGlassToTabBar(tabBar);
        M27StyleMiniPlayerIfPresent(self.view);
    }
}

%end
