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

static void M27FadeStockBottomChrome(UITabBarController *tbc, CGRect dockFrame) {
    if (!tbc) return;
    UITabBar *tabBar = tbc.tabBar;
    tabBar.alpha = 0.0;
    tabBar.userInteractionEnabled = NO;

    CGRect cover = CGRectInset(dockFrame, 0, -12.0);
    for (UIView *sub in tbc.view.subviews) {
        if (sub == tabBar) continue;
        if (sub.tag == kM27DockTag) continue;
        // Never fade tall content hosts.
        if (sub.bounds.size.height > 120.0) continue;
        if (!CGRectIntersectsRect(sub.frame, cover)) continue;
        sub.alpha = 0.0;
        sub.userInteractionEnabled = NO;
    }

    // Also fade a geometry-matched mini player even if slightly outside cover.
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
    return (M27FloatingDock *)[tbc.view viewWithTag:kM27DockTag];
}

static void M27LayoutDock(UITabBarController *tbc, M27FloatingDock *dock) {
    if (!tbc || !dock) return;
    if (objc_getAssociatedObject(tbc, kM27LayoutGuardKey)) return;
    objc_setAssociatedObject(tbc, kM27LayoutGuardKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    @try {
        CGFloat safeBottom = tbc.view.safeAreaInsets.bottom;
        CGFloat bottomPad = MAX(safeBottom > 0 ? MIN(safeBottom * 0.35, 14.0) : 8.0, 8.0);
        CGFloat height = dock.preferredHeight;
        CGFloat width = tbc.view.bounds.size.width;
        CGFloat hostH = tbc.view.bounds.size.height;
        if (width < 1 || hostH < 1) return;

        // Prefer covering the stock mini-player slot when present, otherwise sit
        // just above the (invisible) tab bar / home indicator.
        CGFloat y = hostH - height - bottomPad;
        UIView *mini = M27FindStockMiniPlayer(tbc);
        if (mini) {
            CGRect miniFrame = [mini convertRect:mini.bounds toView:tbc.view];
            CGFloat coverTop = CGRectGetMinY(miniFrame);
            // Keep dock height, but shift up so we fully cover stock mini chrome.
            y = MIN(y, coverTop);
        } else {
            CGRect tabFrame = [tbc.tabBar convertRect:tbc.tabBar.bounds toView:tbc.view];
            if (dock.mode == M27DockModeExpanded) {
                y = MIN(y, CGRectGetMinY(tabFrame) - (height - CGRectGetHeight(tabFrame)));
            }
        }

        CGRect dockFrame = CGRectMake(0, y, width, height);
        dock.frame = dockFrame;
        [dock refreshChrome];
        [tbc.view bringSubviewToFront:dock];
        M27FadeStockBottomChrome(tbc, dockFrame);

        // Extra bottom inset so list content clears the floating dock.
        CGFloat needed = (hostH - y) + 4.0;
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
        tbc.additionalSafeAreaInsets = UIEdgeInsetsZero;
        M27RestoreTabBarChrome(tbc.tabBar);
        // Restore any faded sibling chrome we may have dimmed.
        for (UIView *sub in tbc.view.subviews) {
            if (sub.tag == kM27DockTag) continue;
            if (sub.alpha < 0.05 && sub.bounds.size.height <= 120.0) {
                sub.alpha = 1.0;
                sub.userInteractionEnabled = YES;
            }
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
        [tbc.view addSubview:dock];
    }
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

- (void)layoutSubviews {
    %orig;
    M27Prefs *prefs = M27Prefs.shared;
    if (!(prefs.enabled && prefs.glassTabBarEnabled)) return;
    if (!objc_getAssociatedObject(self, kM27ChromeKey)) return;
    // Keep stock icons invisible if UIKit rebuilds them.
    for (UIView *sub in self.subviews) {
        if (sub.tag == kM27DockTag) continue;
        NSString *name = NSStringFromClass(sub.class);
        if ([name containsString:@"Button"] || [name containsString:@"TabBarButton"] ||
            [name containsString:@"UITabBar"]) {
            sub.alpha = 0.0;
        }
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
