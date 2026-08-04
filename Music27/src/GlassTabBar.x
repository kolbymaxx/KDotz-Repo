#import "Music27.h"
#import "M27FloatingDock.h"
#import "M27GlassChrome.h"
#import <MediaPlayer/MediaPlayer.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <dlfcn.h>

// Floating Liquid Glass dock for Music.
//
// 1.1.11 (SwiftPeek-guided):
// - Library/MiniPlayer hosts stay alive while Music looks black — we were
//   covering/crushing them, not killing the process.
// - Window-hosted overlay only. Never touch additionalSafeAreaInsets.
// - Never fade MiniPlayerViewController or any protected MusicApplication host.
// - Leave stock UITabBar fully intact (no alpha/appearance hacks) so Music's
//   geometry and SwiftUI Library hosts keep compositing.
// - Kill switch (enabled=NO / glassTabBar=NO) removes the dock completely.

static const NSInteger kM27DockTag = 0x4D323744; // 'M27D'
static const CGFloat kM27ScrollCollapseY = 40.0;
static const void *kM27DockControllerKey = &kM27DockControllerKey;
static const void *kM27DockViewKey = &kM27DockViewKey;
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
    // Tap the real MiniPlayerViewController view — never fade/hide it.
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
    // Some Music builds attach the mini player beside the tab controller.
    if (tbc.parentViewController) {
        hit = M27FindMiniPlayerInController(tbc.parentViewController, 0);
        if (hit) return hit;
    }
    return nil;
}

#pragma mark - Dock install / layout (window-hosted)

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

static UIWindow *M27HostWindowForTabBarController(UITabBarController *tbc) {
    if (tbc.view.window) return tbc.view.window;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.isKeyWindow) return window;
        }
    }
    return nil;
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

static void M27LayoutDock(UITabBarController *tbc, M27FloatingDock *dock) {
    if (!tbc || !dock) return;
    if (objc_getAssociatedObject(tbc, kM27LayoutGuardKey)) return;
    objc_setAssociatedObject(tbc, kM27LayoutGuardKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    @try {
        UIWindow *window = M27HostWindowForTabBarController(tbc);
        if (!window) return;

        CGFloat width = window.bounds.size.width;
        CGFloat hostH = window.bounds.size.height;
        if (width < 10 || hostH < 10) return;

        CGFloat height = dock.preferredHeight;
        // Hard cap — a full-screen dock frame would cover Library hosts.
        if (height < 10 || height > 160.0) return;

        if (dock.superview != window) {
            [window addSubview:dock];
        }

        CGFloat safeBottom = window.safeAreaInsets.bottom;
        CGFloat bottomPad = safeBottom > 0 ? MIN(safeBottom * 0.22, 10.0) : 8.0;
        CGFloat y = hostH - height - bottomPad;
        CGRect frame = CGRectMake(0, y, width, height);
        if (!CGRectEqualToRect(dock.frame, frame)) {
            dock.frame = frame;
        }
        dock.hidden = NO;
        dock.alpha = 1.0;
        dock.userInteractionEnabled = YES;
        dock.backgroundColor = UIColor.clearColor;
    } @finally {
        objc_setAssociatedObject(tbc, kM27LayoutGuardKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void M27RemoveDock(UITabBarController *tbc) {
    M27FloatingDock *dock = M27DockForTabBarController(tbc);
    [dock removeFromSuperview];
    objc_setAssociatedObject(tbc, kM27DockViewKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    // Also sweep any leftover tagged docks on the window (older builds).
    UIWindow *window = M27HostWindowForTabBarController(tbc);
    for (UIView *sub in window.subviews.copy) {
        if (sub.tag == kM27DockTag) [sub removeFromSuperview];
    }
    if (tbc.isViewLoaded) {
        for (UIView *sub in tbc.view.subviews.copy) {
            if (sub.tag == kM27DockTag) [sub removeFromSuperview];
        }
        // Ensure stock tab bar is fully restored after older alpha-hide builds.
        tbc.tabBar.alpha = 1.0;
        tbc.tabBar.userInteractionEnabled = YES;
        tbc.tabBar.hidden = NO;
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
        // Do NOT mutate tabBar chrome / mini-player / safe-area / content hosts.
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

void M27ApplyChromeForCurrentPrefs(void) {
    [M27Prefs.shared reload];
    UITabBarController *tbc = M27MusicTabBarController();
    if (tbc) {
        M27InstallDockIfNeeded(tbc);
    } else {
        // Still sweep orphan docks from windows when Music isn't ready.
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                for (UIView *sub in window.subviews.copy) {
                    if (sub.tag == kM27DockTag) [sub removeFromSuperview];
                }
            }
        }
    }

    // Kill switch / feature-off: strip other Music27 overlays by tag.
    M27Prefs *prefs = M27Prefs.shared;
    BOOL stripAll = !prefs.enabled;
    BOOL stripPins = stripAll || !prefs.libraryPinsEnabled;
    BOOL stripAlbum = stripAll || !prefs.glassTabBarEnabled;
    BOOL stripTheme = stripAll || !prefs.colorThemeEnabled;

    if (!(stripAll || stripPins || stripAlbum || stripTheme)) return;

    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
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

static void M27HandleScrollOffset(UIScrollView *scrollView) {
    if (!scrollView.isDragging && !scrollView.isDecelerating) return;
    if (fabs(scrollView.contentOffset.x) > fabs(scrollView.contentOffset.y)) return;
    if (scrollView.contentOffset.y < kM27ScrollCollapseY) return;

    // Never drive dock collapse from Library/protected hosts' scroll views in a
    // way that walks their trees — only collapse the dock overlay.
    UIResponder *r = scrollView;
    UITabBarController *tbc = nil;
    while (r) {
        if ([r isKindOfClass:UIViewController.class] && M27IsProtectedMusicHost(r)) {
            // Still allow collapse; just don't touch the host.
            break;
        }
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
    if (now - last < 0.12) return;
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
