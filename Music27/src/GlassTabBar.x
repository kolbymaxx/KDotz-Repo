#import "Music27.h"
#import "M27FloatingDock.h"
#import "M27GlassChrome.h"
#import <MediaPlayer/MediaPlayer.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <dlfcn.h>

// Hosts the iOS 27 floating Liquid Glass dock on Music's UITabBarController.
//
// 1.1.9 blank-screen fix (iPhone X / Dopamine rootless):
// - NEVER mutate additionalSafeAreaInsets (Music uses them for mini-player;
//   clearing them every layout thrash-crushed the root hosting view).
// - Install once from UITabBarController viewDidAppear only.
// - No UIWindow / UITabBar.layoutSubviews install paths.
// - Overlay dock only; leave stock tab bar interactive as fallback.
// - Fade stock mini-player once at install — never from every layout pass.
// - Prefs default dock OFF (see M27Prefs blankScreenFix119).

static const NSInteger kM27DockTag = 0x4D323744; // 'M27D'
static const CGFloat kM27ScrollCollapseY = 40.0;
static const void *kM27DockControllerKey = &kM27DockControllerKey;
static const void *kM27DockInstalledKey = &kM27DockInstalledKey;
static const void *kM27ChromeKey = &kM27ChromeKey;
static const void *kM27LayoutGuardKey = &kM27LayoutGuardKey;
static const void *kM27MiniFadedKey = &kM27MiniFadedKey;

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

#pragma mark - Stock chrome (visual only — keep interaction as fallback)

static void M27StripTabBarChromeOnce(UITabBar *tabBar) {
    if (!tabBar) return;
    if (objc_getAssociatedObject(tabBar, kM27ChromeKey)) return;
    objc_setAssociatedObject(tabBar, kM27ChromeKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    tabBar.backgroundColor = UIColor.clearColor;
    [tabBar setBackgroundImage:[UIImage new]];
    [tabBar setShadowImage:[UIImage new]];
    tabBar.translucent = YES;
    // Keep userInteractionEnabled = YES so stock tabs remain a fallback if the
    // overlay dock fails to receive hits. Dock sits above and takes hits first.

    if (@available(iOS 13.0, *)) {
        UITabBarAppearance *appearance = [UITabBarAppearance new];
        [appearance configureWithTransparentBackground];
        appearance.backgroundEffect = nil;
        appearance.backgroundColor = UIColor.clearColor;
        appearance.shadowColor = UIColor.clearColor;
        appearance.stackedLayoutAppearance.normal.iconColor = UIColor.clearColor;
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = @{
            NSForegroundColorAttributeName: UIColor.clearColor
        };
        appearance.stackedLayoutAppearance.selected.iconColor = UIColor.clearColor;
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = @{
            NSForegroundColorAttributeName: UIColor.clearColor
        };
        tabBar.standardAppearance = appearance;
        tabBar.scrollEdgeAppearance = appearance;
    }
}

static void M27RestoreTabBarChrome(UITabBar *tabBar) {
    if (!tabBar || !objc_getAssociatedObject(tabBar, kM27ChromeKey)) return;
    objc_setAssociatedObject(tabBar, kM27ChromeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

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
    UIView *mini = M27FindStockMiniPlayer(self.tabBarController);
    if (!mini) return;
    CGPoint point = CGPointMake(CGRectGetMidX(mini.bounds), CGRectGetMidY(mini.bounds));
    UIView *target = [mini hitTest:point withEvent:nil] ?: mini;
    if ([target isKindOfClass:UIControl.class]) {
        [(UIControl *)target sendActionsForControlEvents:UIControlEventTouchUpInside];
    }
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

#pragma mark - Mini player discovery (strict)

static UIView *M27FindStockMiniPlayer(UITabBarController *tbc) {
    if (!tbc) return nil;
    UITabBar *tabBar = tbc.tabBar;
    UIView *parent = tabBar.superview;
    if (!parent) return nil;

    // Only inspect direct siblings of the tab bar — never walk the selected
    // view controller's content tree (that caused the white-screen bug).
    static NSArray<NSString *> *strongNeedles;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        strongNeedles = @[ @"miniplayer", @"nowplayingbar", @"nowplayingmini" ];
    });

    for (UIView *sibling in parent.subviews) {
        if (sibling == tabBar) continue;
        if (sibling.tag == kM27DockTag) continue;
        if (sibling.bounds.size.height > 120.0) continue;
        if (M27ClassNameContains(sibling, strongNeedles)) {
            return sibling;
        }
        for (UIView *child in sibling.subviews) {
            if (child.bounds.size.height > 120.0) continue;
            if (M27ClassNameContains(child, strongNeedles)) {
                return child;
            }
        }
    }
    return nil;
}

static void M27FadeStockMiniPlayerOnce(UITabBarController *tbc) {
    if (!tbc) return;
    if (objc_getAssociatedObject(tbc, kM27MiniFadedKey)) return;
    UIView *mini = M27FindStockMiniPlayer(tbc);
    if (!mini) return;
    // Fade only — never .hidden / removeFromSuperview.
    mini.alpha = 0.0;
    mini.userInteractionEnabled = NO;
    objc_setAssociatedObject(tbc, kM27MiniFadedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void M27UnfadeStockMiniPlayer(UITabBarController *tbc) {
    if (!tbc) return;
    if (!objc_getAssociatedObject(tbc, kM27MiniFadedKey)) return;
    objc_setAssociatedObject(tbc, kM27MiniFadedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIView *mini = M27FindStockMiniPlayer(tbc);
    if (!mini) return;
    mini.alpha = 1.0;
    mini.userInteractionEnabled = YES;
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
    // Direct children only — avoid recursive viewWithTag walks into content hosts.
    for (UIView *sub in tbc.view.subviews) {
        if (sub.tag == kM27DockTag && [sub isKindOfClass:M27FloatingDock.class]) {
            return (M27FloatingDock *)sub;
        }
    }
    return nil;
}

static void M27LayoutDock(UITabBarController *tbc, M27FloatingDock *dock) {
    if (!tbc || !dock) return;
    if (objc_getAssociatedObject(tbc, kM27LayoutGuardKey)) return;
    objc_setAssociatedObject(tbc, kM27LayoutGuardKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    @try {
        // Overlay only. Do NOT touch additionalSafeAreaInsets — ever.
        UIView *host = tbc.view;
        if (!host || host.bounds.size.width < 10 || host.bounds.size.height < 10) return;
        if (dock.superview != host) [host addSubview:dock];

        CGFloat safeBottom = host.safeAreaInsets.bottom;
        CGFloat bottomPad = safeBottom > 0 ? MIN(safeBottom * 0.22, 10.0) : 8.0;
        CGFloat height = dock.preferredHeight;
        if (height < 10) return;

        CGFloat width = host.bounds.size.width;
        CGFloat hostH = host.bounds.size.height;
        CGFloat y = hostH - height - bottomPad;
        dock.hidden = NO;
        dock.alpha = 1.0;
        dock.userInteractionEnabled = YES;
        dock.frame = CGRectMake(0, y, width, height);
        dock.layer.zPosition = 100000;
        [dock refreshChrome];
        [host bringSubviewToFront:dock];
    } @finally {
        objc_setAssociatedObject(tbc, kM27LayoutGuardKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void M27InstallDockIfNeeded(UITabBarController *tbc) {
    if (!tbc || !tbc.isViewLoaded) return;
    [M27Prefs.shared reload];
    M27Prefs *prefs = M27Prefs.shared;
    M27FloatingDock *existing = M27DockForTabBarController(tbc);

    if (!(prefs.enabled && prefs.glassTabBarEnabled)) {
        if (existing) [existing removeFromSuperview];
        M27RestoreTabBarChrome(tbc.tabBar);
        M27UnfadeStockMiniPlayer(tbc);
        objc_setAssociatedObject(tbc, kM27DockInstalledKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }

    @try {
        M27StripTabBarChromeOnce(tbc.tabBar);
        M27FadeStockMiniPlayerOnce(tbc);

        M27DockController *controller = M27ControllerForTabBarController(tbc);
        M27FloatingDock *dock = existing;
        if (!dock) {
            dock = [[M27FloatingDock alloc] initWithFrame:CGRectZero];
            dock.tag = kM27DockTag;
            dock.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
            [tbc.view addSubview:dock];
            [dock reloadTabs];
            [dock setMode:M27DockModeExpanded animated:NO];
            objc_setAssociatedObject(tbc, kM27DockInstalledKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        dock.delegate = controller;
        controller.dock = dock;
        dock.selectedTabIndex = (NSInteger)tbc.selectedIndex;
        [controller syncNowPlaying];
        M27LayoutDock(tbc, dock);
    } @catch (__unused NSException *ex) {
        [existing removeFromSuperview];
        M27RestoreTabBarChrome(tbc.tabBar);
        M27UnfadeStockMiniPlayer(tbc);
    }
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

    UIResponder *r = scrollView;
    UITabBarController *tbc = nil;
    while (r) {
        if ([r isKindOfClass:UITabBarController.class]) {
            tbc = (UITabBarController *)r;
            break;
        }
        r = r.nextResponder;
    }
    if (!tbc) tbc = M27MusicTabBarController();
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
    // Sole install path. Defer one runloop so Music finishes first layout.
    __weak UITabBarController *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        M27InstallDockIfNeeded(weakSelf);
    });
}

- (void)viewDidLayoutSubviews {
    %orig;
    M27Prefs *prefs = M27Prefs.shared;
    if (!(prefs.enabled && prefs.glassTabBarEnabled)) return;
    // Layout-only: reposition overlay. Never reinstall / never touch safe area /
    // never fade mini-player here.
    M27FloatingDock *dock = M27DockForTabBarController(self);
    if (dock) M27LayoutDock(self, dock);
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
