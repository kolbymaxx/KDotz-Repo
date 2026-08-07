#import "Music27.h"
#import "M27FloatingDock.h"
#import "M27GlassChrome.h"
#import <MediaPlayer/MediaPlayer.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <dlfcn.h>

// Floating Liquid Glass dock for Music.
//
// 1.1.13 (visual floating dock on top of 1.1.12 safety):
// - Keep dedicated passthrough UIWindow (never Music's key window).
// - Soft-hide stock UITabBar + MiniPlayerViewController.view with alpha only
//   so the glass pills read as the real dock (not double chrome).
// - Never additionalSafeAreaInsets, never hidden=YES on hosts, never fade
//   Library*/UIHosting* / oversized views.
// - Scroll-collapse restored (dock overlay only).

static const NSInteger kM27DockTag = 0x4D323744; // 'M27D'
static const CGFloat kM27ScrollCollapseY = 48.0;
static const void *kM27DockControllerKey = &kM27DockControllerKey;
static const void *kM27DockViewKey = &kM27DockViewKey;
static const void *kM27DockWindowKey = &kM27DockWindowKey;
static const void *kM27LayoutGuardKey = &kM27LayoutGuardKey;

#pragma mark - Passthrough overlay window

@interface M27PassthroughView : UIView
@end

@implementation M27PassthroughView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    // Empty chrome must not eat Library taps — only the dock pills should.
    return (hit == self) ? nil : hit;
}
@end

@interface M27DockOverlayWindow : UIWindow
@end

@implementation M27DockOverlayWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit == self || hit == self.rootViewController.view) return nil;
    return hit;
}
@end

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
        send(2, NULL);
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
        send(4, NULL);
        return;
    }
    [MPMusicPlayerController.systemMusicPlayer skipToNextItem];
}

#pragma mark - Dock controller bridge

@class M27DockController;

static void M27LayoutDock(UITabBarController *tbc, M27FloatingDock *dock);
static UIViewController *M27FindMiniPlayerViewController(UITabBarController *tbc);

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
    UIViewController *miniVC = M27FindMiniPlayerViewController(self.tabBarController);
    UIView *mini = miniVC.view;
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

#pragma mark - MiniPlayerViewController (SwiftPeek name, read-only)

static UIViewController *M27FindMiniPlayerInController(UIViewController *vc, NSInteger depth) {
    if (!vc || depth > 6) return nil;
    if (M27ClassNameHasSuffix(vc, @"MiniPlayerViewController")) return vc;
    for (UIViewController *child in vc.childViewControllers) {
        UIViewController *hit = M27FindMiniPlayerInController(child, depth + 1);
        if (hit) return hit;
    }
    return nil;
}

static UIViewController *M27FindMiniPlayerViewController(UITabBarController *tbc) {
    if (!tbc) return nil;
    UIViewController *hit = M27FindMiniPlayerInController(tbc, 0);
    if (hit) return hit;
    if (tbc.parentViewController) {
        hit = M27FindMiniPlayerInController(tbc.parentViewController, 0);
        if (hit) return hit;
    }
    return nil;
}

#pragma mark - Dock install / layout (dedicated overlay window)

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
    return objc_getAssociatedObject(tbc, kM27DockViewKey);
}

static UIWindowScene *M27SceneForTabBarController(UITabBarController *tbc) {
    if (@available(iOS 13.0, *)) {
        UIWindow *host = tbc.view.window;
        if (host.windowScene) return host.windowScene;
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            UIWindowScene *ws = (UIWindowScene *)scene;
            if (ws.activationState == UISceneActivationStateForegroundActive) return ws;
        }
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if ([scene isKindOfClass:UIWindowScene.class]) return (UIWindowScene *)scene;
        }
    }
    return nil;
}

static UITabBarController *M27MusicTabBarController(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            // Skip our own overlay.
            if ([window isKindOfClass:M27DockOverlayWindow.class]) continue;
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

static void M27SweepLegacyDockSubviews(void) {
    // Remove any dock that older builds left on Music's own windows / tbc.view.
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if ([window isKindOfClass:M27DockOverlayWindow.class]) continue;
            for (UIView *sub in window.subviews.copy) {
                if (sub.tag == kM27DockTag) [sub removeFromSuperview];
            }
            UIViewController *root = window.rootViewController;
            if (root.isViewLoaded) {
                for (UIView *sub in root.view.subviews.copy) {
                    if (sub.tag == kM27DockTag) [sub removeFromSuperview];
                }
            }
            if ([root isKindOfClass:UITabBarController.class]) {
                UITabBarController *tbc = (UITabBarController *)root;
                tbc.tabBar.alpha = 1.0;
                tbc.tabBar.userInteractionEnabled = YES;
                tbc.tabBar.hidden = NO;
            }
        }
    }
}

/// Soft-hide stock bottom chrome so the glass dock is the visible UI.
/// Alpha / interaction only — never hidden=YES, never safe-area mutation.
static void M27ApplyStockChromeVisibility(UITabBarController *tbc, BOOL glassOn) {
    if (!tbc || !tbc.isViewLoaded) return;

    UITabBar *bar = tbc.tabBar;
    if (glassOn) {
        bar.alpha = 0.01; // keep in compositing tree; effectively invisible
        bar.userInteractionEnabled = NO;
        bar.hidden = NO;
        if (@available(iOS 15.0, *)) {
            UITabBarAppearance *clear = [UITabBarAppearance new];
            [clear configureWithTransparentBackground];
            bar.standardAppearance = clear;
            bar.scrollEdgeAppearance = clear;
        }
    } else {
        bar.alpha = 1.0;
        bar.userInteractionEnabled = YES;
        bar.hidden = NO;
    }

    UIViewController *miniVC = M27FindMiniPlayerViewController(tbc);
    if (!miniVC || !miniVC.isViewLoaded) return;
    // Exact SwiftPeek type only — never climb to parents / Library hosts.
    if (!M27ClassNameHasSuffix(miniVC, @"MiniPlayerViewController")) return;
    UIView *mini = miniVC.view;
    if (!mini) return;
    // Safety: refuse to fade anything that looks like a full content host.
    CGFloat h = CGRectGetHeight(mini.bounds);
    CGFloat hostH = mini.window ? CGRectGetHeight(mini.window.bounds) : 0;
    if (h > 160.0 || (hostH > 0 && h > hostH * 0.35)) {
        if (!glassOn) {
            mini.alpha = 1.0;
            mini.userInteractionEnabled = YES;
        }
        return;
    }
    if (glassOn) {
        mini.alpha = 0.01;
        mini.userInteractionEnabled = NO;
    } else {
        mini.alpha = 1.0;
        mini.userInteractionEnabled = YES;
    }
}

static M27DockOverlayWindow *M27EnsureOverlayWindow(UITabBarController *tbc) {
    M27DockOverlayWindow *overlay = objc_getAssociatedObject(tbc, kM27DockWindowKey);
    if (overlay) return overlay;

    UIWindowScene *scene = M27SceneForTabBarController(tbc);
    if (scene) {
        overlay = [[M27DockOverlayWindow alloc] initWithWindowScene:scene];
        overlay.frame = scene.coordinateSpace.bounds;
    } else {
        overlay = [[M27DockOverlayWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    }
    overlay.windowLevel = UIWindowLevelNormal + 2.0;
    overlay.backgroundColor = UIColor.clearColor;
    overlay.opaque = NO;
    overlay.userInteractionEnabled = YES;
    overlay.hidden = NO;

    UIViewController *root = [UIViewController new];
    M27PassthroughView *pass = [[M27PassthroughView alloc] initWithFrame:overlay.bounds];
    pass.backgroundColor = UIColor.clearColor;
    pass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    root.view = pass;
    overlay.rootViewController = root;

    objc_setAssociatedObject(tbc, kM27DockWindowKey, overlay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return overlay;
}

static void M27LayoutDock(UITabBarController *tbc, M27FloatingDock *dock) {
    if (!tbc || !dock) return;
    if (objc_getAssociatedObject(tbc, kM27LayoutGuardKey)) return;
    objc_setAssociatedObject(tbc, kM27LayoutGuardKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    @try {
        M27DockOverlayWindow *overlay = M27EnsureOverlayWindow(tbc);
        if (!overlay) return;

        // Keep overlay bounds synced to the scene / screen.
        CGRect targetBounds = overlay.windowScene
            ? overlay.windowScene.coordinateSpace.bounds
            : UIScreen.mainScreen.bounds;
        if (!CGRectEqualToRect(overlay.frame, targetBounds)) {
            overlay.frame = targetBounds;
        }
        overlay.hidden = NO;

        CGFloat width = overlay.bounds.size.width;
        CGFloat hostH = overlay.bounds.size.height;
        if (width < 10 || hostH < 10) return;

        CGFloat height = dock.preferredHeight;
        // Hard cap — a full-screen dock frame would cover Library hosts.
        if (height < 10 || height > 160.0) return;

        UIView *host = overlay.rootViewController.view;
        if (dock.superview != host) {
            [host addSubview:dock];
        }

        // Float above the home indicator — reads as a dock, not a tab-bar strip.
        CGFloat safeBottom = overlay.safeAreaInsets.bottom;
        CGFloat bottomPad = safeBottom > 0 ? MIN(safeBottom * 0.40, 18.0) : 14.0;
        CGFloat y = hostH - height - bottomPad;
        CGRect frame = CGRectMake(0, y, width, height);
        if (!CGRectEqualToRect(dock.frame, frame)) {
            dock.frame = frame;
        }
        dock.hidden = NO;
        dock.alpha = 1.0;
        dock.userInteractionEnabled = YES;
        dock.backgroundColor = UIColor.clearColor;

        M27ApplyStockChromeVisibility(tbc, YES);
    } @finally {
        objc_setAssociatedObject(tbc, kM27LayoutGuardKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void M27RemoveDock(UITabBarController *tbc) {
    M27FloatingDock *dock = M27DockForTabBarController(tbc);
    [dock removeFromSuperview];
    objc_setAssociatedObject(tbc, kM27DockViewKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    M27ApplyStockChromeVisibility(tbc, NO);

    M27DockOverlayWindow *overlay = objc_getAssociatedObject(tbc, kM27DockWindowKey);
    if (overlay) {
        overlay.hidden = YES;
        overlay.rootViewController = nil;
        objc_setAssociatedObject(tbc, kM27DockWindowKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    M27SweepLegacyDockSubviews();

    // Tear down any leftover overlay windows from prior installs.
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows.copy) {
            if ([window isKindOfClass:M27DockOverlayWindow.class]) {
                window.hidden = YES;
                window.rootViewController = nil;
            }
        }
    }
}

static void M27InstallDockIfNeeded(UITabBarController *tbc) {
    if (!tbc || !tbc.isViewLoaded) return;
    M27Prefs *prefs = M27Prefs.shared;

    if (!(prefs.enabled && prefs.glassTabBarEnabled)) {
        M27RemoveDock(tbc);
        return;
    }

    @try {
        // Never touch Music's key window / safe-area / Library hosts.
        // Soft-hide stock tab bar + MiniPlayer view only (alpha), via layout.
        M27SweepLegacyDockSubviews();

        M27DockController *controller = M27ControllerForTabBarController(tbc);
        M27FloatingDock *dock = M27DockForTabBarController(tbc);
        if (!dock) {
            dock = [[M27FloatingDock alloc] initWithFrame:CGRectZero];
            dock.tag = kM27DockTag;
            dock.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
            dock.backgroundColor = UIColor.clearColor;
            objc_setAssociatedObject(tbc, kM27DockViewKey, dock, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [dock reloadTabs];
            [dock setMode:M27DockModeExpanded animated:NO];
        }
        dock.delegate = controller;
        controller.dock = dock;
        dock.selectedTabIndex = (NSInteger)tbc.selectedIndex;
        [controller syncNowPlaying];
        M27LayoutDock(tbc, dock);
    } @catch (__unused NSException *ex) {
        M27RemoveDock(tbc);
    }
}

static void M27HandleScrollOffset(UIScrollView *scrollView) {
    if (!scrollView.isDragging && !scrollView.isDecelerating) return;
    if (fabs(scrollView.contentOffset.x) > fabs(scrollView.contentOffset.y)) return;
    if (scrollView.contentOffset.y < kM27ScrollCollapseY) return;

    // Collapse the overlay dock only — never mutate scroll hosts / Library.
    UITabBarController *tbc = M27MusicTabBarController();
    if (!tbc) return;
    M27Prefs *prefs = M27Prefs.shared;
    if (!(prefs.enabled && prefs.glassTabBarEnabled)) return;
    M27FloatingDock *dock = M27DockForTabBarController(tbc);
    if (!dock || dock.mode == M27DockModeCollapsed) return;
    [dock collapseFromScroll];
}

void M27ApplyChromeForCurrentPrefs(void) {
    [M27Prefs.shared reload];
    UITabBarController *tbc = M27MusicTabBarController();
    if (tbc) {
        M27InstallDockIfNeeded(tbc);
    } else {
        M27SweepLegacyDockSubviews();
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows.copy) {
                if ([window isKindOfClass:M27DockOverlayWindow.class]) {
                    window.hidden = YES;
                    window.rootViewController = nil;
                }
                for (UIView *sub in window.subviews.copy) {
                    if (sub.tag == kM27DockTag) [sub removeFromSuperview];
                }
            }
        }
    }

    M27Prefs *prefs = M27Prefs.shared;
    BOOL stripAll = !prefs.enabled;
    BOOL stripPins = stripAll || !prefs.libraryPinsEnabled;
    BOOL stripAlbum = stripAll || !prefs.glassTabBarEnabled;
    BOOL stripTheme = stripAll || !prefs.colorThemeEnabled;

    if (!(stripAll || stripPins || stripAlbum || stripTheme)) return;

    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if ([window isKindOfClass:M27DockOverlayWindow.class]) {
                if (stripAll || !prefs.glassTabBarEnabled) {
                    window.hidden = YES;
                }
                continue;
            }
            NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:window];
            while (stack.count) {
                UIView *view = stack.lastObject;
                [stack removeLastObject];
                if (stripAll && view.tag == kM27DockTag) {
                    [view removeFromSuperview];
                    continue;
                }
                if (stripAlbum && view.tag == 0x4D324143) { // M2AC
                    [view removeFromSuperview];
                    continue;
                }
                if (stripPins && view.tag == 0x4D323750) { // M27P
                    [view removeFromSuperview];
                    continue;
                }
                if (stripTheme) {
                    for (CALayer *layer in view.layer.sublayers.copy) {
                        if ([layer.name isEqualToString:@"M27Wash"]) {
                            [layer removeFromSuperlayer];
                        }
                    }
                }
                [stack addObjectsFromArray:view.subviews];
            }
        }
    }
}

#pragma mark - Hooks

%hook UITabBarController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    __weak UITabBarController *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        M27InstallDockIfNeeded(weakSelf);
    });
}

- (void)viewDidLayoutSubviews {
    %orig;
    M27Prefs *prefs = M27Prefs.shared;
    if (!(prefs.enabled && prefs.glassTabBarEnabled)) return;
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
    M27Prefs *prefs = M27Prefs.shared;
    if (!(prefs.enabled && prefs.glassTabBarEnabled)) return;
    if (!self.isDragging && !self.isDecelerating) return;
    static NSTimeInterval last = 0;
    NSTimeInterval now = CACurrentMediaTime();
    if (now - last < 0.15) return;
    last = now;
    M27HandleScrollOffset(self);
}

%end

%hook MPNowPlayingInfoCenter

- (void)setNowPlayingInfo:(NSDictionary *)info {
    %orig;
    M27Prefs *prefs = M27Prefs.shared;
    if (!(prefs.enabled && prefs.glassTabBarEnabled)) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        UITabBarController *tbc = M27MusicTabBarController();
        if (!tbc) return;
        M27DockController *controller = objc_getAssociatedObject(tbc, kM27DockControllerKey);
        [controller syncNowPlaying];
    });
}

%end
