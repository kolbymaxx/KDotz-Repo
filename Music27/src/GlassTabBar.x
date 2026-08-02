#import "Music27.h"
#import "M27FloatingDock.h"
#import "M27GlassChrome.h"
#import <MediaPlayer/MediaPlayer.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <dlfcn.h>

// Music27 floating Liquid Glass dock.
//
// 1.1.4: restore the 1.1.1 attach path (dock on UITabBarController.view) which
// actually appeared on device, keep safe-area caps so Library cannot be crushed,
// and re-hide the stock UITabBar every layout pass.

static const NSInteger kM27DockTag = 0x4D323744; // 'M27D'
static const CGFloat kM27ScrollCollapseY = 40.0;
static const CGFloat kM27MaxBottomInset = 160.0;
static const void *kM27DockControllerKey = &kM27DockControllerKey;
static const void *kM27DockObjectKey = &kM27DockObjectKey;
static const void *kM27LayoutGuardKey = &kM27LayoutGuardKey;

#pragma mark - MediaRemote

typedef void (*M27MRSendCommandFunc)(unsigned int command, CFDictionaryRef options);

static M27MRSendCommandFunc M27MRSendCommand(void) {
    static M27MRSendCommandFunc fn;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY);
        if (handle) fn = (M27MRSendCommandFunc)dlsym(handle, "MRMediaRemoteSendCommand");
    });
    return fn;
}

static void M27TogglePlayPause(void) {
    M27MRSendCommandFunc send = M27MRSendCommand();
    if (send) { send(2, NULL); return; }
    MPMusicPlayerController *player = MPMusicPlayerController.systemMusicPlayer;
    if (player.playbackState == MPMusicPlaybackStatePlaying) [player pause];
    else [player play];
}

static void M27NextTrack(void) {
    M27MRSendCommandFunc send = M27MRSendCommand();
    if (send) { send(4, NULL); return; }
    [MPMusicPlayerController.systemMusicPlayer skipToNextItem];
}

#pragma mark - Forward decls

@class M27DockController;
static void M27LayoutDock(UITabBarController *tbc, M27FloatingDock *dock);
static void M27InstallDockIfNeeded(UITabBarController *tbc);
static UITabBarController *M27MusicTabBarController(void);
static UITabBarController *M27TabBarControllerFromView(UIView *view);

#pragma mark - Stock chrome

static void M27HideStockTabBar(UITabBar *tabBar) {
    if (!tabBar) return;
    tabBar.alpha = 0.0;
    tabBar.userInteractionEnabled = NO;
    tabBar.backgroundColor = UIColor.clearColor;
    [tabBar setBackgroundImage:[UIImage new]];
    [tabBar setShadowImage:[UIImage new]];
    tabBar.translucent = YES;
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

static void M27ShowStockTabBar(UITabBar *tabBar) {
    if (!tabBar) return;
    tabBar.alpha = 1.0;
    tabBar.userInteractionEnabled = YES;
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

static UIView *M27FindStockMiniPlayer(UITabBarController *tbc) {
    if (!tbc) return nil;
    UITabBar *tabBar = tbc.tabBar;
    UIView *parent = tbc.view;
    CGRect tabFrame = [tabBar convertRect:tabBar.bounds toView:parent];
    if (CGRectGetHeight(tabFrame) < 1.0) return nil;

    static NSArray<NSString *> *needles;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        needles = @[ @"miniplayer", @"nowplayingbar", @"nowplayingmini" ];
    });

    UIView *best = nil;
    CGFloat bestScore = -1;
    for (UIView *sub in parent.subviews) {
        if (sub == tabBar || sub.tag == kM27DockTag) continue;
        CGFloat h = sub.bounds.size.height;
        CGFloat w = sub.bounds.size.width;
        if (h < 44.0 || h > 100.0) continue;
        if (w < parent.bounds.size.width * 0.8) continue;
        // Must be in the bottom 45% of the screen.
        if (CGRectGetMinY(sub.frame) < parent.bounds.size.height * 0.55) continue;
        CGFloat gap = fabs(CGRectGetMinY(tabFrame) - CGRectGetMaxY(sub.frame));
        if (gap > 40.0) continue;
        CGFloat score = w * h;
        if (M27ClassNameContains(sub, needles)) score += 100000;
        if (score > bestScore) {
            bestScore = score;
            best = sub;
        }
    }
    return best;
}

static void M27HideStockMiniPlayer(UITabBarController *tbc) {
    UIView *mini = M27FindStockMiniPlayer(tbc);
    if (!mini) return;
    mini.alpha = 0.0;
    mini.userInteractionEnabled = NO;
}

#pragma mark - Dock controller

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
    NSArray *vcs = self.tabBarController.viewControllers;
    if (index < 0 || index >= (NSInteger)vcs.count) return nil;
    return [vcs[index] tabBarItem].title;
}

- (UIImage *)floatingDock:(M27FloatingDock *)dock iconForTabIndex:(NSInteger)index selected:(BOOL)selected {
    (void)dock;
    NSArray *vcs = self.tabBarController.viewControllers;
    if (index < 0 || index >= (NSInteger)vcs.count) return nil;
    UITabBarItem *item = [vcs[index] tabBarItem];
    return selected && item.selectedImage ? item.selectedImage : item.image;
}

- (void)floatingDock:(M27FloatingDock *)dock didSelectTabIndex:(NSInteger)index {
    (void)dock;
    if (index < 0 || index >= (NSInteger)self.tabBarController.viewControllers.count) return;
    self.tabBarController.selectedIndex = (NSUInteger)index;
}

- (void)floatingDockDidTapSearch:(M27FloatingDock *)dock {
    (void)dock;
    NSArray *vcs = self.tabBarController.viewControllers;
    NSInteger searchIndex = (NSInteger)vcs.count - 1;
    for (NSInteger i = 0; i < (NSInteger)vcs.count; i++) {
        NSString *title = [[vcs[i] tabBarItem].title lowercaseString] ?: @"";
        if ([title containsString:@"search"]) { searchIndex = i; break; }
    }
    if (searchIndex >= 0) {
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
    CGFloat prev = mini.alpha;
    BOOL prevUI = mini.userInteractionEnabled;
    mini.alpha = 0.02;
    mini.userInteractionEnabled = YES;
    UIView *target = [mini hitTest:CGPointMake(CGRectGetMidX(mini.bounds), CGRectGetMidY(mini.bounds))
                         withEvent:nil] ?: mini;
    if ([target isKindOfClass:UIControl.class]) {
        [(UIControl *)target sendActionsForControlEvents:UIControlEventTouchUpInside];
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        mini.alpha = prev;
        mini.userInteractionEnabled = prevUI;
    });
}

- (void)floatingDockDidChangeMode:(M27FloatingDock *)dock {
    M27LayoutDock(self.tabBarController, dock);
}

- (void)syncNowPlaying {
    NSDictionary *info = MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo;
    self.dock.trackTitle = info[MPMediaItemPropertyTitle];
    self.dock.artistName = info[MPMediaItemPropertyArtist];
    UIImage *art = nil;
    id artwork = info[MPMediaItemPropertyArtwork];
    if ([artwork isKindOfClass:MPMediaItemArtwork.class]) {
        art = [(MPMediaItemArtwork *)artwork imageWithSize:CGSizeMake(120, 120)];
    }
    self.dock.artwork = art;
    BOOL playing = NO;
    id rate = info[@"playbackRate"];
    if ([rate respondsToSelector:@selector(doubleValue)]) playing = [rate doubleValue] > 0.01;
    else playing = MPMusicPlayerController.systemMusicPlayer.playbackState == MPMusicPlaybackStatePlaying;
    self.dock.playing = playing;
    self.dock.selectedTabIndex = (NSInteger)self.tabBarController.selectedIndex;
    [self.dock refreshChrome];
}

@end

#pragma mark - Install / layout

static M27DockController *M27ControllerFor(UITabBarController *tbc) {
    M27DockController *c = objc_getAssociatedObject(tbc, kM27DockControllerKey);
    if (!c) {
        c = [M27DockController new];
        c.tabBarController = tbc;
        objc_setAssociatedObject(tbc, kM27DockControllerKey, c, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return c;
}

static M27FloatingDock *M27DockFor(UITabBarController *tbc) {
    if (!tbc) return nil;
    M27FloatingDock *dock = objc_getAssociatedObject(tbc, kM27DockObjectKey);
    if (dock) return dock;
    return (M27FloatingDock *)[tbc.view viewWithTag:kM27DockTag];
}

static void M27LayoutDock(UITabBarController *tbc, M27FloatingDock *dock) {
    if (!tbc || !dock) return;
    if (objc_getAssociatedObject(tbc, kM27LayoutGuardKey)) return;
    objc_setAssociatedObject(tbc, kM27LayoutGuardKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    @try {
        UIView *host = tbc.view;
        if (dock.superview != host) [host addSubview:dock];

        CGFloat width = host.bounds.size.width;
        CGFloat hostH = host.bounds.size.height;
        CGFloat height = dock.preferredHeight;
        if (width < 10 || hostH < 10 || height < 10) return;

        CGFloat safeBottom = host.safeAreaInsets.bottom;
        CGFloat bottomPad = safeBottom > 0 ? MIN(safeBottom * 0.28, 10.0) : 8.0;
        CGFloat y = hostH - height - bottomPad;
        // Stay in the bottom half — never crush Library content.
        y = MAX(y, hostH * 0.60);

        dock.hidden = NO;
        dock.alpha = 1.0;
        dock.frame = CGRectMake(0, y, width, height);
        dock.layer.zPosition = 100000;
        [host bringSubviewToFront:dock];
        [dock refreshChrome];

        M27HideStockTabBar(tbc.tabBar);
        M27HideStockMiniPlayer(tbc);

        // Cap inset — the blank Library bug was an uncapped value near the screen height.
        CGFloat needed = MIN(height + 10.0, kM27MaxBottomInset);
        UIEdgeInsets insets = tbc.additionalSafeAreaInsets;
        // Repair any previously crushed inset from 1.1.2.
        if (insets.bottom > kM27MaxBottomInset + 1.0 || fabs(insets.bottom - needed) > 1.0) {
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

    // Always repair a crushed inset first, even if glass is off.
    if (tbc.additionalSafeAreaInsets.bottom > kM27MaxBottomInset) {
        UIEdgeInsets insets = tbc.additionalSafeAreaInsets;
        insets.bottom = 0;
        tbc.additionalSafeAreaInsets = insets;
    }

    M27FloatingDock *existing = M27DockFor(tbc);
    if (!(prefs.enabled && prefs.glassTabBarEnabled)) {
        if (existing) [existing removeFromSuperview];
        objc_setAssociatedObject(tbc, kM27DockObjectKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        tbc.additionalSafeAreaInsets = UIEdgeInsetsZero;
        M27ShowStockTabBar(tbc.tabBar);
        UIView *mini = M27FindStockMiniPlayer(tbc);
        if (mini) { mini.alpha = 1.0; mini.userInteractionEnabled = YES; }
        return;
    }

    M27DockController *controller = M27ControllerFor(tbc);
    M27FloatingDock *dock = existing;
    if (!dock) {
        dock = [[M27FloatingDock alloc] initWithFrame:CGRectZero];
        dock.tag = kM27DockTag;
        dock.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
        [tbc.view addSubview:dock];
        [dock reloadTabs];
        [dock setMode:M27DockModeExpanded animated:NO];
    }
    dock.delegate = controller;
    controller.dock = dock;
    objc_setAssociatedObject(tbc, kM27DockObjectKey, dock, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    dock.selectedTabIndex = (NSInteger)tbc.selectedIndex;
    [controller syncNowPlaying];
    M27LayoutDock(tbc, dock);
}

static UITabBarController *M27TabBarControllerFromView(UIView *view) {
    for (UIResponder *r = view; r; r = r.nextResponder) {
        if ([r isKindOfClass:UITabBarController.class]) return (UITabBarController *)r;
    }
    return nil;
}

static UITabBarController *M27MusicTabBarController(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            UIViewController *root = window.rootViewController;
            if ([root isKindOfClass:UITabBarController.class]) return (UITabBarController *)root;
            if (root.tabBarController) return root.tabBarController;
            for (UIViewController *child in root.childViewControllers) {
                if ([child isKindOfClass:UITabBarController.class]) return (UITabBarController *)child;
                if (child.tabBarController) return child.tabBarController;
            }
        }
    }
    return nil;
}

static void M27HandleScrollOffset(UIScrollView *scrollView) {
    if (!scrollView.isDragging && !scrollView.isDecelerating) return;
    if (fabs(scrollView.contentOffset.x) > fabs(scrollView.contentOffset.y)) return;
    if (scrollView.contentOffset.y < kM27ScrollCollapseY) return;
    UITabBarController *tbc = M27TabBarControllerFromView(scrollView) ?: M27MusicTabBarController();
    if (!tbc) return;
    if (!(M27Prefs.shared.enabled && M27Prefs.shared.glassTabBarEnabled)) return;
    M27FloatingDock *dock = M27DockFor(tbc);
    if (dock && dock.mode != M27DockModeCollapsed) [dock collapseFromScroll];
}

#pragma mark - Hooks

%hook UITabBarController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    dispatch_async(dispatch_get_main_queue(), ^{ M27InstallDockIfNeeded(self); });
}

- (void)viewDidLayoutSubviews {
    %orig;
    if (!(M27Prefs.shared.enabled && M27Prefs.shared.glassTabBarEnabled)) return;
    M27FloatingDock *dock = M27DockFor(self);
    if (dock) M27LayoutDock(self, dock);
    else M27InstallDockIfNeeded(self);
}

- (void)setSelectedIndex:(NSUInteger)selectedIndex {
    %orig;
    M27DockFor(self).selectedTabIndex = (NSInteger)selectedIndex;
}

- (void)setSelectedViewController:(UIViewController *)selectedViewController {
    %orig;
    M27DockFor(self).selectedTabIndex = (NSInteger)self.selectedIndex;
}

%end

%hook UITabBar

- (void)didMoveToWindow {
    %orig;
    if (!self.window) return;
    if (!(M27Prefs.shared.enabled && M27Prefs.shared.glassTabBarEnabled)) return;
    UITabBarController *tbc = M27TabBarControllerFromView(self) ?: M27MusicTabBarController();
    dispatch_async(dispatch_get_main_queue(), ^{ M27InstallDockIfNeeded(tbc); });
}

- (void)layoutSubviews {
    %orig;
    if (!(M27Prefs.shared.enabled && M27Prefs.shared.glassTabBarEnabled)) return;
    // Critical: Music rebuilds tab chrome constantly — hide it every pass.
    M27HideStockTabBar(self);
    UITabBarController *tbc = M27TabBarControllerFromView(self) ?: M27MusicTabBarController();
    if (!tbc) return;
    M27FloatingDock *dock = M27DockFor(tbc);
    if (dock) {
        [tbc.view bringSubviewToFront:dock];
        dock.layer.zPosition = 100000;
    } else {
        M27InstallDockIfNeeded(tbc);
    }
}

%end

%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (!(M27Prefs.shared.enabled && M27Prefs.shared.glassTabBarEnabled)) return;
    UITabBarController *tbc = self.tabBarController ?: M27MusicTabBarController();
    if (!tbc) return;
    dispatch_async(dispatch_get_main_queue(), ^{ M27InstallDockIfNeeded(tbc); });
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
        M27DockController *controller = tbc ? objc_getAssociatedObject(tbc, kM27DockControllerKey) : nil;
        [controller syncNowPlaying];
    });
}

%end
