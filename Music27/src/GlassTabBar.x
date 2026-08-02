#import "Music27.h"
#import "M27FloatingDock.h"
#import "M27GlassChrome.h"
#import <MediaPlayer/MediaPlayer.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <dlfcn.h>

// Hosts the iOS 27 floating Liquid Glass dock on Music's UITabBarController.
//
// 1.1.1 safety fixes vs blank Music launch:
// - No layout loop: do NOT mutate additionalSafeAreaInsets / tabBar.hidden from
//   inside every viewDidLayoutSubviews.
// - Never hide arbitrary views in the tab controller hierarchy (the old
//   mini-player heuristic could hide real content → white screen).
// - Install the dock once; layout only repositions the overlay.
// - Keep the stock tab bar in the hierarchy (transparent) so Music's own
//   geometry stays stable.

static const NSInteger kM27DockTag = 0x4D323744; // 'M27D'
static const CGFloat kM27ScrollCollapseY = 40.0;
static const void *kM27DockControllerKey = &kM27DockControllerKey;
static const void *kM27DockInstalledKey = &kM27DockInstalledKey;
static const void *kM27ChromeKey = &kM27ChromeKey;
static const void *kM27LayoutGuardKey = &kM27LayoutGuardKey;

#pragma mark - MediaRemote (soft-linked)

typedef void (*M27MRSendCommandFunc)(unsigned int command, CFDictionaryRef options);

static M27MRSendCommandFunc M27MRSendCommand(void) {
    static M27MRSendCommandFunc fn;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY);
        if (handle) {
            fn = (M27MRSendCommandFunc)dlsym(handle, "MRMediaRemoteSendCommand");
        }
    });
    return fn;
}

static void M27TogglePlayPause(void) {
    M27MRSendCommandFunc send = M27MRSendCommand();
    if (send) {
        send(2, NULL); // kMRTogglePlayPause
        return;
    }
    MPMusicPlayerController *player = MPMusicPlayerController.systemMusicPlayer;
    if (player.playbackState == MPMusicPlaybackStatePlaying) {
        [player pause];
    } else {
        [player play];
    }
}

static void M27NextTrack(void) {
    M27MRSendCommandFunc send = M27MRSendCommand();
    if (send) {
        send(4, NULL); // kMRNextTrack
        return;
    }
    [MPMusicPlayerController.systemMusicPlayer skipToNextItem];
}

#pragma mark - Stock chrome (tab bar only — never hide content views)

static void M27StripTabBarChromeOnce(UITabBar *tabBar) {
    if (!tabBar) return;
    if (objc_getAssociatedObject(tabBar, kM27ChromeKey)) return;
    objc_setAssociatedObject(tabBar, kM27ChromeKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    tabBar.backgroundColor = UIColor.clearColor;
    [tabBar setBackgroundImage:[UIImage new]];
    [tabBar setShadowImage:[UIImage new]];
    tabBar.translucent = YES;
    // Keep in-hierarchy for Music layout, but fully invisible + non-interactive.
    tabBar.alpha = 0.0;
    tabBar.userInteractionEnabled = NO;

    if (@available(iOS 13.0, *)) {
        UITabBarAppearance *appearance = [UITabBarAppearance new];
        [appearance configureWithTransparentBackground];
        appearance.backgroundEffect = nil;
        appearance.backgroundColor = UIColor.clearColor;
        appearance.shadowColor = UIColor.clearColor;
        tabBar.standardAppearance = appearance;
        tabBar.scrollEdgeAppearance = appearance;
    }
}

static void M27RestoreTabBarChrome(UITabBar *tabBar) {
    if (!tabBar || !objc_getAssociatedObject(tabBar, kM27ChromeKey)) return;
    objc_setAssociatedObject(tabBar, kM27ChromeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    tabBar.alpha = 1.0;
    tabBar.userInteractionEnabled = YES;
    tabBar.hidden = NO;
    [tabBar setBackgroundImage:nil];
    [tabBar setShadowImage:nil];
    tabBar.backgroundColor = nil;
    if (@available(iOS 13.0, *)) {
        UITabBarAppearance *appearance = [UITabBarAppearance new];
        [appearance configureWithDefaultBackground];
        tabBar.standardAppearance = appearance;
        tabBar.scrollEdgeAppearance = appearance;
    }
}

#pragma mark - Dock controller bridge

@class M27DockController;

static void M27LayoutDock(UITabBarController *tbc, M27FloatingDock *dock);
static UIView *M27FindStockMiniPlayer(UITabBarController *tbc);

@interface M27DockController : NSObject <M27FloatingDockDelegate>
@property (nonatomic, weak) UITabBarController *tabBarController;
@property (nonatomic, weak) M27FloatingDock *dock;
@end

@implementation M27DockController

- (NSInteger)numberOfTabsForFloatingDock:(M27FloatingDock *)dock {
    (void)dock;
    return (NSInteger)self.tabBarController.viewControllers.count;
}

- (NSString *)floatingDock:(M27FloatingDock *)dock titleForTabIndex:(NSInteger)index {
    (void)dock;
    NSArray<__kindof UIViewController *> *vcs = self.tabBarController.viewControllers;
    if (index < 0 || index >= (NSInteger)vcs.count) return nil;
    return vcs[index].tabBarItem.title;
}

- (UIImage *)floatingDock:(M27FloatingDock *)dock iconForTabIndex:(NSInteger)index selected:(BOOL)selected {
    (void)dock;
    NSArray<__kindof UIViewController *> *vcs = self.tabBarController.viewControllers;
    if (index < 0 || index >= (NSInteger)vcs.count) return nil;
    UITabBarItem *item = vcs[index].tabBarItem;
    return selected && item.selectedImage ? item.selectedImage : item.image;
}

- (void)floatingDock:(M27FloatingDock *)dock didSelectTabIndex:(NSInteger)index {
    (void)dock;
    if (index < 0 || index >= (NSInteger)self.tabBarController.viewControllers.count) return;
    self.tabBarController.selectedIndex = (NSUInteger)index;
}

- (void)floatingDockDidTapSearch:(M27FloatingDock *)dock {
    (void)dock;
    NSInteger searchIndex = NSNotFound;
    NSArray<__kindof UIViewController *> *vcs = self.tabBarController.viewControllers;
    for (NSInteger i = 0; i < (NSInteger)vcs.count; i++) {
        NSString *title = vcs[i].tabBarItem.title.lowercaseString ?: @"";
        if ([title containsString:@"search"]) {
            searchIndex = i;
            break;
        }
    }
    if (searchIndex == NSNotFound && vcs.count > 0) {
        searchIndex = (NSInteger)vcs.count - 1;
    }
    if (searchIndex != NSNotFound) {
        self.tabBarController.selectedIndex = (NSUInteger)searchIndex;
        self.dock.selectedTabIndex = searchIndex;
    }
}

- (void)floatingDockDidTapPlayPause:(M27FloatingDock *)dock {
    (void)dock;
    M27TogglePlayPause();
}

- (void)floatingDockDidTapNext:(M27FloatingDock *)dock {
    (void)dock;
    M27NextTrack();
}

- (void)floatingDockDidTapNowPlaying:(M27FloatingDock *)dock {
    (void)dock;
    // Soft open: briefly re-enable the stock mini player and tap it.
    UIView *mini = M27FindStockMiniPlayer(self.tabBarController);
    if (!mini) return;
    CGFloat prevAlpha = mini.alpha;
    BOOL prevInteraction = mini.userInteractionEnabled;
    mini.alpha = 0.02;
    mini.userInteractionEnabled = YES;
    CGPoint point = CGPointMake(CGRectGetMidX(mini.bounds), CGRectGetMidY(mini.bounds));
    UIView *target = [mini hitTest:point withEvent:nil] ?: mini;
    if ([target isKindOfClass:UIControl.class]) {
        [(UIControl *)target sendActionsForControlEvents:UIControlEventTouchUpInside];
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        mini.alpha = prevAlpha;
        mini.userInteractionEnabled = prevInteraction;
    });
}

- (void)floatingDockDidChangeMode:(M27FloatingDock *)dock {
    M27LayoutDock(self.tabBarController, dock);
}

- (void)syncNowPlaying {
    NSDictionary *info = MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo;
    NSString *title = info[MPMediaItemPropertyTitle];
    NSString *artist = info[MPMediaItemPropertyArtist];
    UIImage *art = nil;
    id artwork = info[MPMediaItemPropertyArtwork];
    if ([artwork isKindOfClass:MPMediaItemArtwork.class]) {
        art = [(MPMediaItemArtwork *)artwork imageWithSize:CGSizeMake(120, 120)];
    }
    self.dock.trackTitle = title;
    self.dock.artistName = artist;
    self.dock.artwork = art;

    BOOL playing = (MPMusicPlayerController.systemMusicPlayer.playbackState == MPMusicPlaybackStatePlaying);
    id rate = info[@"playbackRate"];
    if ([rate respondsToSelector:@selector(doubleValue)]) {
        playing = [rate doubleValue] > 0.01;
    }
    self.dock.playing = playing;
    self.dock.selectedTabIndex = (NSInteger)self.tabBarController.selectedIndex;
    [self.dock refreshChrome];
}

@end

#pragma mark - Mini player discovery (frame-based, safe)

static UIView *M27FindStockMiniPlayer(UITabBarController *tbc) {
    if (!tbc) return nil;
    UITabBar *tabBar = tbc.tabBar;
    UIView *parent = tbc.view;
    if (!parent) return nil;

    CGRect tabFrame = [tabBar convertRect:tabBar.bounds toView:parent];
    static NSArray<NSString *> *strongNeedles;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        strongNeedles = @[ @"miniplayer", @"nowplayingbar", @"nowplayingmini", @"playerbar" ];
    });

    UIView *best = nil;
    CGFloat bestArea = 0;

    // Only direct subviews of the tab controller's view — never descend into
    // the selected page content (that caused the white-screen bug).
    for (UIView *sub in parent.subviews) {
        if (sub == tabBar) continue;
        if (sub.tag == kM27DockTag) continue;
        if (sub.hidden) continue;

        CGRect frame = sub.frame;
        CGFloat h = frame.size.height;
        CGFloat w = frame.size.width;
        if (h < 40.0 || h > 110.0) continue;
        if (w < parent.bounds.size.width * 0.70) continue;

        // Must sit immediately above (or overlapping) the tab bar.
        CGFloat maxY = CGRectGetMaxY(frame);
        CGFloat tabMinY = CGRectGetMinY(tabFrame);
        if (maxY < tabMinY - 24.0) continue;
        if (CGRectGetMinY(frame) > tabMinY + 10.0) continue;

        BOOL nameMatch = M27ClassNameContains(sub, strongNeedles);
        CGFloat area = w * h;
        if (nameMatch) area *= 2.0;
        if (area > bestArea) {
            bestArea = area;
            best = sub;
        }
    }
    return best;
}

static const void *kM27DockObjectKey = &kM27DockObjectKey;

static void M27FadeStockBottomChrome(UITabBarController *tbc) {
    if (!tbc) return;
    UITabBar *tabBar = tbc.tabBar;
    // Re-assert every layout — Music restores tab bar chrome frequently.
    tabBar.alpha = 0.0;
    tabBar.userInteractionEnabled = NO;

    UIView *mini = M27FindStockMiniPlayer(tbc);
    if (mini && mini.tag != kM27DockTag) {
        mini.alpha = 0.0;
        mini.userInteractionEnabled = NO;
    }
}

#pragma mark - Dock install / layout

static M27DockController *M27ControllerForTabBarController(UITabBarController *tbc) {
    M27DockController *controller = objc_getAssociatedObject(tbc, kM27DockControllerKey);
    if (!controller) {
        controller = [M27DockController new];
        controller.tabBarController = tbc;
        objc_setAssociatedObject(tbc, kM27DockControllerKey, controller, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return controller;
}

static M27FloatingDock *M27DockForTabBarController(UITabBarController *tbc) {
    if (!tbc) return nil;
    M27FloatingDock *dock = objc_getAssociatedObject(tbc, kM27DockObjectKey);
    if (dock) return dock;
    // Legacy fallback (1.1.2 attached to tbc.view).
    return (M27FloatingDock *)[tbc.view viewWithTag:kM27DockTag];
}

static UIView *M27DockHostView(UITabBarController *tbc) {
    // Prefer the window so Music's tab-bar layout cannot bury the dock.
    UIView *host = tbc.view.window;
    if (!host) host = tbc.view;
    return host;
}

static void M27LayoutDock(UITabBarController *tbc, M27FloatingDock *dock) {
    if (!tbc || !dock) return;
    if (objc_getAssociatedObject(tbc, kM27LayoutGuardKey)) return;
    objc_setAssociatedObject(tbc, kM27LayoutGuardKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    @try {
        UIView *host = M27DockHostView(tbc);
        if (dock.superview != host) {
            [host addSubview:dock];
        }

        CGFloat safeBottom = host.safeAreaInsets.bottom;
        if (safeBottom <= 0) safeBottom = tbc.view.safeAreaInsets.bottom;
        CGFloat bottomPad = MAX(MIN(safeBottom > 0 ? safeBottom * 0.30 : 8.0, 12.0), 8.0);
        CGFloat height = dock.preferredHeight;
        CGFloat width = host.bounds.size.width;
        CGFloat hostH = host.bounds.size.height;
        if (width < 1 || hostH < 1 || height < 1) return;

        // Always pin to the bottom. Do NOT chase arbitrary mini-player frames —
        // that previously computed a near-zero Y and crushed Library content via
        // a huge additionalSafeAreaInsets.bottom (blank white Library).
        CGFloat y = hostH - height - bottomPad;
        CGFloat minY = hostH * 0.55; // hard floor: stay in bottom half
        if (y < minY) y = minY;

        dock.frame = CGRectMake(0, y, width, height);
        dock.alpha = 1.0;
        dock.hidden = NO;
        dock.layer.zPosition = 9999;
        [dock refreshChrome];
        [host bringSubviewToFront:dock];

        M27FadeStockBottomChrome(tbc);

        // Modest inset only — never more than the dock stack itself.
        CGFloat needed = MIN(height + 12.0, 170.0);
        UIEdgeInsets insets = tbc.additionalSafeAreaInsets;
        if (fabs(insets.bottom - needed) > 1.0) {
            insets.bottom = needed;
            tbc.additionalSafeAreaInsets = insets;
        }
    } @finally {
        objc_setAssociatedObject(tbc, kM27LayoutGuardKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void M27InstallDockIfNeeded(UITabBarController *tbc) {
    if (!tbc) return;
    M27Prefs *prefs = M27Prefs.shared;
    M27FloatingDock *existing = M27DockForTabBarController(tbc);

    if (!(prefs.enabled && prefs.glassTabBarEnabled)) {
        if (existing) [existing removeFromSuperview];
        objc_setAssociatedObject(tbc, kM27DockObjectKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(tbc, kM27DockInstalledKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        tbc.additionalSafeAreaInsets = UIEdgeInsetsZero;
        M27RestoreTabBarChrome(tbc.tabBar);
        UIView *mini = M27FindStockMiniPlayer(tbc);
        if (mini) {
            mini.alpha = 1.0;
            mini.userInteractionEnabled = YES;
        }
        return;
    }

    M27StripTabBarChromeOnce(tbc.tabBar);

    if (objc_getAssociatedObject(tbc, kM27DockInstalledKey) && existing) {
        M27LayoutDock(tbc, existing);
        return;
    }

    M27DockController *controller = M27ControllerForTabBarController(tbc);
    M27FloatingDock *dock = existing;
    if (!dock) {
        dock = [[M27FloatingDock alloc] initWithFrame:CGRectZero];
        dock.tag = kM27DockTag;
        dock.delegate = controller;
        dock.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    }
    UIView *host = M27DockHostView(tbc);
    if (dock.superview != host) {
        [host addSubview:dock];
    }
    objc_setAssociatedObject(tbc, kM27DockObjectKey, dock, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    controller.dock = dock;
    dock.delegate = controller;
    [dock reloadTabs];
    [dock setMode:M27DockModeExpanded animated:NO];
    [controller syncNowPlaying];
    objc_setAssociatedObject(tbc, kM27DockInstalledKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    M27LayoutDock(tbc, dock);
}

static UITabBarController *M27MusicTabBarController(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            UIViewController *root = window.rootViewController;
            if ([root isKindOfClass:UITabBarController.class]) {
                return (UITabBarController *)root;
            }
            if (root.tabBarController) return root.tabBarController;
            // Music sometimes wraps the tab controller.
            for (UIViewController *child in root.childViewControllers) {
                if ([child isKindOfClass:UITabBarController.class]) {
                    return (UITabBarController *)child;
                }
            }
        }
    }
    return nil;
}

static void M27HandleScrollOffset(UIScrollView *scrollView) {
    if (!scrollView.isDragging && !scrollView.isDecelerating) return;
    if (fabs(scrollView.contentOffset.x) > fabs(scrollView.contentOffset.y)) return;
    if (scrollView.contentOffset.y < kM27ScrollCollapseY) return;

    UITabBarController *tbc = scrollView.window.rootViewController.tabBarController;
    if (![tbc isKindOfClass:UITabBarController.class]) {
        tbc = M27MusicTabBarController();
    }
    if (!tbc) return;

    M27Prefs *prefs = M27Prefs.shared;
    if (!(prefs.enabled && prefs.glassTabBarEnabled)) return;

    M27FloatingDock *dock = M27DockForTabBarController(tbc);
    if (!dock || dock.mode == M27DockModeCollapsed) return;
    [dock collapseFromScroll];
}

#pragma mark - Hooks

%hook UITabBarController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    // Defer one runloop so Music finishes its own first layout.
    dispatch_async(dispatch_get_main_queue(), ^{
        M27InstallDockIfNeeded(self);
    });
}

- (void)viewDidLayoutSubviews {
    %orig;
    M27Prefs *prefs = M27Prefs.shared;
    if (!(prefs.enabled && prefs.glassTabBarEnabled)) return;
    // Layout-only path: never reinstall / never hide tall content hosts.
    M27FloatingDock *dock = M27DockForTabBarController(self);
    if (dock) {
        M27LayoutDock(self, dock);
    }
}

- (void)setSelectedIndex:(NSUInteger)selectedIndex {
    %orig;
    M27FloatingDock *dock = M27DockForTabBarController(self);
    if (dock) dock.selectedTabIndex = (NSInteger)selectedIndex;
}

- (void)setSelectedViewController:(UIViewController *)selectedViewController {
    %orig;
    M27FloatingDock *dock = M27DockForTabBarController(self);
    if (dock) dock.selectedTabIndex = (NSInteger)self.selectedIndex;
}

%end

%hook UITabBar

- (void)didMoveToWindow {
    %orig;
    M27Prefs *prefs = M27Prefs.shared;
    if (!(prefs.enabled && prefs.glassTabBarEnabled)) return;
    UITabBarController *tbc = nil;
    UIResponder *r = self.nextResponder;
    while (r) {
        if ([r isKindOfClass:UITabBarController.class]) {
            tbc = (UITabBarController *)r;
            break;
        }
        r = r.nextResponder;
    }
    if (!tbc) tbc = M27MusicTabBarController();
    if (!tbc) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        M27InstallDockIfNeeded(tbc);
    });
}

- (void)layoutSubviews {
    %orig;
    M27Prefs *prefs = M27Prefs.shared;
    if (!(prefs.enabled && prefs.glassTabBarEnabled)) return;
    // Keep stock tab bar invisible even when Music rebuilds it.
    if (objc_getAssociatedObject(self, kM27ChromeKey)) {
        self.alpha = 0.0;
        self.userInteractionEnabled = NO;
    }
    UITabBarController *tbc = nil;
    UIResponder *r = self.nextResponder;
    while (r) {
        if ([r isKindOfClass:UITabBarController.class]) {
            tbc = (UITabBarController *)r;
            break;
        }
        r = r.nextResponder;
    }
    M27FloatingDock *dock = M27DockForTabBarController(tbc ?: M27MusicTabBarController());
    if (dock) {
        UIView *host = dock.superview;
        [host bringSubviewToFront:dock];
        dock.layer.zPosition = 9999;
    }
}

%end

%hook UIScrollView

- (void)setContentOffset:(CGPoint)contentOffset {
    %orig;
    if (!self.isDragging && !self.isDecelerating) return;
    static NSTimeInterval last = 0;
    NSTimeInterval now = CACurrentMediaTime();
    if (now - last < 0.12) return;
    last = now;
    M27HandleScrollOffset(self);
}

%end

%hook MPNowPlayingInfoCenter

- (void)setNowPlayingInfo:(NSDictionary *)info {
    %orig;
    dispatch_async(dispatch_get_main_queue(), ^{
        UITabBarController *tbc = M27MusicTabBarController();
        if (!tbc) return;
        M27DockController *controller = objc_getAssociatedObject(tbc, kM27DockControllerKey);
        [controller syncNowPlaying];
    });
}

%end
