#import "Music27.h"
#import "M27FloatingDock.h"
#import "M27GlassChrome.h"
#import <MediaPlayer/MediaPlayer.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <dlfcn.h>

// Hosts the iOS 27 floating Liquid Glass dock on Music's UITabBarController,
// hides the stock tab bar + mini-player chrome, collapses on scroll-down, and
// expands again when the red Music button is tapped.

static const NSInteger kM27DockTag = 0x4D323744; // 'M27D'
static const CGFloat kM27ScrollCollapseY = 28.0;
static const void *kM27StockMiniKey = &kM27StockMiniKey;
static const void *kM27DockInstalledKey = &kM27DockInstalledKey;

#pragma mark - MediaRemote (soft-linked)

typedef void (*M27MRSendCommandFunc)(unsigned int command, CFDictionaryRef options);
typedef void (*M27MRGetInfoFunc)(dispatch_queue_t queue, void (^handler)(CFDictionaryRef info));

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
        // 2 = kMRTogglePlayPause
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

#pragma mark - Hierarchy helpers

static BOOL M27ViewLooksLikeMiniPlayer(UIView *view) {
    if (!view) return NO;
    static NSArray<NSString *> *needles;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        needles = @[
            @"miniplayer", @"nowplayingbar", @"playerbar", @"nowplayingmini",
            @"minipayer", @"transportbar", @"nowplayingcontent"
        ];
    });
    if (M27ClassNameContains(view, needles)) return YES;
    // Fallback: floating bar sitting just above the tab bar with artwork + title.
    if (view.bounds.size.height >= 48 && view.bounds.size.height <= 78 &&
        view.bounds.size.width > 200) {
        BOOL hasImage = NO, hasLabel = NO;
        for (UIView *sub in view.subviews) {
            if ([sub isKindOfClass:UIImageView.class]) hasImage = YES;
            if ([sub isKindOfClass:UILabel.class]) hasLabel = YES;
            if (M27ClassNameContains(sub, needles)) return YES;
        }
        if (hasImage && hasLabel && view.superview) {
            // Likely the floating mini player if near the bottom of its superview.
            CGFloat midY = CGRectGetMidY(view.frame);
            CGFloat parentH = view.superview.bounds.size.height;
            if (midY > parentH * 0.55) return YES;
        }
    }
    return NO;
}

static UIView *M27FindMiniPlayerNearTabBar(UITabBar *tabBar) {
    UIView *container = tabBar.superview ?: tabBar;
    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:container];
    NSInteger visited = 0;
    UIView *best = nil;
    while (stack.count && visited < 120) {
        UIView *view = stack.lastObject;
        [stack removeLastObject];
        visited++;
        if (view == tabBar) continue;
        if (view.tag == kM27DockTag) continue;
        if (M27ViewLooksLikeMiniPlayer(view)) {
            best = view;
            break;
        }
        for (UIView *sub in view.subviews) {
            [stack addObject:sub];
        }
    }
    return best;
}

static void M27HideStockChrome(UITabBar *tabBar, UIView *miniPlayer) {
    tabBar.backgroundColor = UIColor.clearColor;
    tabBar.tintColor = UIColor.clearColor;
    tabBar.unselectedItemTintColor = UIColor.clearColor;
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
    for (UIView *sub in tabBar.subviews) {
        if (sub.tag == kM27DockTag) continue;
        sub.alpha = 0.0;
        sub.userInteractionEnabled = NO;
    }
    // Keep the tab bar's layout slot but make it non-interactive; the dock handles taps.
    tabBar.userInteractionEnabled = NO;

    if (miniPlayer) {
        objc_setAssociatedObject(tabBar, kM27StockMiniKey, miniPlayer, OBJC_ASSOCIATION_ASSIGN);
        miniPlayer.alpha = 0.0;
        miniPlayer.userInteractionEnabled = NO;
        // Prefer hidden so Music drops its layout reservation when possible.
        miniPlayer.hidden = YES;
    }
}

static void M27RestoreStockChrome(UITabBar *tabBar) {
    tabBar.userInteractionEnabled = YES;
    tabBar.tintColor = nil;
    tabBar.unselectedItemTintColor = nil;
    [tabBar setBackgroundImage:nil];
    [tabBar setShadowImage:nil];
    for (UIView *sub in tabBar.subviews) {
        if (sub.tag == kM27DockTag) continue;
        sub.alpha = 1.0;
        sub.userInteractionEnabled = YES;
    }
    UIView *mini = objc_getAssociatedObject(tabBar, kM27StockMiniKey);
    if (mini) {
        mini.hidden = NO;
        mini.alpha = 1.0;
        mini.userInteractionEnabled = YES;
    }
    if (@available(iOS 13.0, *)) {
        UITabBarAppearance *appearance = [UITabBarAppearance new];
        [appearance configureWithDefaultBackground];
        tabBar.standardAppearance = appearance;
        tabBar.scrollEdgeAppearance = appearance;
    }
}

static void M27ForwardTapToStockMiniPlayer(UITabBar *tabBar) {
    UIView *mini = objc_getAssociatedObject(tabBar, kM27StockMiniKey);
    if (!mini) mini = M27FindMiniPlayerNearTabBar(tabBar);
    if (!mini) return;

    // Temporarily reveal and synthesize a tap on the stock mini player so Music
    // presents its real Now Playing UI.
    CGFloat previousAlpha = mini.alpha;
    BOOL previousInteraction = mini.userInteractionEnabled;
    BOOL previousHidden = mini.hidden;
    mini.hidden = NO;
    mini.alpha = 0.02;
    mini.userInteractionEnabled = YES;

    CGPoint point = CGPointMake(CGRectGetMidX(mini.bounds), CGRectGetMidY(mini.bounds));
    UIView *target = [mini hitTest:point withEvent:nil] ?: mini;
    if ([target isKindOfClass:UIControl.class]) {
        [(UIControl *)target sendActionsForControlEvents:UIControlEventTouchUpInside];
    } else {
        for (UIGestureRecognizer *gr in target.gestureRecognizers) {
            if (!gr.enabled) continue;
            if (![gr isKindOfClass:UITapGestureRecognizer.class]) continue;
            @try {
                NSArray *targets = [gr valueForKey:@"targets"];
                for (id token in targets) {
                    id tgt = [token valueForKey:@"target"];
                    SEL sel = NSSelectorFromString([[token valueForKey:@"action"] description] ?: @"");
                    if (tgt && sel && [tgt respondsToSelector:sel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                        [tgt performSelector:sel withObject:gr];
#pragma clang diagnostic pop
                    }
                }
            } @catch (__unused NSException *ex) {}
            break;
        }
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        mini.hidden = previousHidden;
        mini.alpha = previousAlpha;
        mini.userInteractionEnabled = previousInteraction;
    });
}

#pragma mark - Dock controller bridge

static void M27LayoutDock(UITabBarController *tbc, M27FloatingDock *dock);

@interface M27DockController : NSObject <M27FloatingDockDelegate>
@property (nonatomic, weak) UITabBarController *tabBarController;
@property (nonatomic, weak) M27FloatingDock *dock;
@property (nonatomic, assign) CGFloat lastCollapseOffset;
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
        NSString *cls = NSStringFromClass(vcs[i].class).lowercaseString;
        if ([title containsString:@"search"] || [cls containsString:@"search"]) {
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

- (void)floatingDockDidTapNowPlaying:(M27FloatingDock *)dock {
    (void)dock;
    M27ForwardTapToStockMiniPlayer(self.tabBarController.tabBar);
}

- (void)floatingDockDidChangeMode:(M27FloatingDock *)dock {
    UITabBarController *tbc = self.tabBarController;
    if (!tbc || !dock) return;
    M27LayoutDock(tbc, dock);
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

    BOOL playing = NO;
    M27MRGetInfoFunc getInfo = NULL;
    // Playback state from application music player as a soft fallback.
    playing = (MPMusicPlayerController.systemMusicPlayer.playbackState == MPMusicPlaybackStatePlaying);
    // If title exists and rate key says so:
    id rate = info[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"] ?: info[@"playbackRate"];
    if ([rate respondsToSelector:@selector(doubleValue)]) {
        playing = [rate doubleValue] > 0.01;
    }
    (void)getInfo;
    self.dock.playing = playing;
    self.dock.selectedTabIndex = (NSInteger)self.tabBarController.selectedIndex;
    [self.dock refreshChrome];
}

@end

static const void *kM27DockControllerKey = &kM27DockControllerKey;

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

static void M27UpdateSafeAreaForDock(UITabBarController *tbc, M27FloatingDock *dock) {
    if (!tbc || !dock) return;
    CGFloat bottomPad = MAX(tbc.view.safeAreaInsets.bottom, 8.0);
    CGFloat height = dock.preferredHeight + bottomPad + 6.0;
    // Zero the stock tab bar's contribution; our dock replaces it visually.
    tbc.tabBar.hidden = YES;
    UIEdgeInsets insets = tbc.additionalSafeAreaInsets;
    if (fabs(insets.bottom - height) > 0.5) {
        insets.bottom = height;
        tbc.additionalSafeAreaInsets = insets;
    }
}

static void M27LayoutDock(UITabBarController *tbc, M27FloatingDock *dock) {
    if (!tbc || !dock) return;
    CGFloat bottomPad = MAX(tbc.view.safeAreaInsets.bottom * 0.35, 8.0);
    CGFloat height = dock.preferredHeight;
    CGFloat y = tbc.view.bounds.size.height - height - bottomPad;
    dock.frame = CGRectMake(0, y, tbc.view.bounds.size.width, height);
    [dock refreshChrome];
    M27UpdateSafeAreaForDock(tbc, dock);
    [tbc.view bringSubviewToFront:dock];
}

static void M27InstallOrUpdateDock(UITabBarController *tbc) {
    M27Prefs *prefs = M27Prefs.shared;
    M27FloatingDock *existing = M27DockForTabBarController(tbc);

    if (!(prefs.enabled && prefs.glassTabBarEnabled)) {
        if (existing) [existing removeFromSuperview];
        tbc.tabBar.hidden = NO;
        tbc.additionalSafeAreaInsets = UIEdgeInsetsZero;
        M27RestoreStockChrome(tbc.tabBar);
        return;
    }

    UIView *mini = M27FindMiniPlayerNearTabBar(tbc.tabBar);
    M27HideStockChrome(tbc.tabBar, mini);

    M27DockController *controller = M27ControllerForTabBarController(tbc);
    M27FloatingDock *dock = existing;
    if (!dock) {
        dock = [[M27FloatingDock alloc] initWithFrame:CGRectZero];
        dock.tag = kM27DockTag;
        dock.delegate = controller;
        dock.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
        [tbc.view addSubview:dock];
        controller.dock = dock;
        [dock reloadTabs];
        // Start expanded so the 5 tabs are discoverable; first scroll collapses.
        [dock setMode:M27DockModeExpanded animated:NO];
        objc_setAssociatedObject(tbc, kM27DockInstalledKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else {
        controller.dock = dock;
        dock.delegate = controller;
        [dock reloadTabs];
    }

    [controller syncNowPlaying];
    M27LayoutDock(tbc, dock);
}

static void M27HandleScrollOffset(UIScrollView *scrollView) {
    if (!scrollView.isDragging && !scrollView.isDecelerating) return;
    if (fabs(scrollView.contentOffset.x) > fabs(scrollView.contentOffset.y) &&
        fabs(scrollView.contentOffset.x) > 8.0) {
        return; // ignore horizontal carousels
    }
    if (scrollView.contentOffset.y < kM27ScrollCollapseY) return;

    UIViewController *top = M27TopViewController();
    UITabBarController *tbc = top.tabBarController ?: (UITabBarController *)top;
    while (top && ![tbc isKindOfClass:UITabBarController.class]) {
        if ([top isKindOfClass:UITabBarController.class]) {
            tbc = (UITabBarController *)top;
            break;
        }
        top = top.parentViewController;
        tbc = top.tabBarController;
    }
    if (![tbc isKindOfClass:UITabBarController.class]) {
        // Walk windows for the Music tab controller.
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                UIViewController *root = window.rootViewController;
                if ([root isKindOfClass:UITabBarController.class]) {
                    tbc = (UITabBarController *)root;
                    break;
                }
                if (root.tabBarController) {
                    tbc = root.tabBarController;
                    break;
                }
            }
        }
    }
    if (![tbc isKindOfClass:UITabBarController.class]) return;

    M27Prefs *prefs = M27Prefs.shared;
    if (!(prefs.enabled && prefs.glassTabBarEnabled)) return;

    M27FloatingDock *dock = M27DockForTabBarController(tbc);
    if (!dock) return;
    if (dock.mode == M27DockModeCollapsed) return;

    [dock collapseFromScroll];
    M27LayoutDock(tbc, dock);
}

#pragma mark - Hooks

%hook UITabBarController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    M27InstallOrUpdateDock(self);
}

- (void)viewDidLayoutSubviews {
    %orig;
    M27Prefs *prefs = M27Prefs.shared;
    if (!(prefs.enabled && prefs.glassTabBarEnabled)) return;
    M27InstallOrUpdateDock(self);
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

%hook UITabBar

- (void)layoutSubviews {
    %orig;
    M27Prefs *prefs = M27Prefs.shared;
    if (!(prefs.enabled && prefs.glassTabBarEnabled)) return;
    // Keep stock item chrome suppressed if Music rebuilds it.
    for (UIView *sub in self.subviews) {
        if (sub.tag == kM27DockTag) continue;
        if (sub.alpha > 0.01) {
            sub.alpha = 0.0;
            sub.userInteractionEnabled = NO;
        }
    }
}

%end

%hook UIScrollView

- (void)setContentOffset:(CGPoint)contentOffset {
    %orig;
    static NSTimeInterval last = 0;
    NSTimeInterval now = CACurrentMediaTime();
    if (now - last < 0.05) return; // throttle
    last = now;
    M27HandleScrollOffset(self);
}

%end

%hook MPNowPlayingInfoCenter

- (void)setNowPlayingInfo:(NSDictionary *)info {
    %orig;
    dispatch_async(dispatch_get_main_queue(), ^{
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                UIViewController *root = window.rootViewController;
                UITabBarController *tbc = nil;
                if ([root isKindOfClass:UITabBarController.class]) tbc = (UITabBarController *)root;
                else tbc = root.tabBarController;
                if (!tbc) continue;
                M27DockController *controller = objc_getAssociatedObject(tbc, kM27DockControllerKey);
                [controller syncNowPlaying];
            }
        }
    });
}

%end
