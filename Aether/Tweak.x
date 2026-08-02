/**
 * Aether — Universal Context Glass
 *
 * A RootHide-native (and rootless-compatible) UIKit-wide layer that summons a
 * liquid-glass panel inside any app:
 *   • Clipboard timeline — the request jailbreakers have had for a decade
 *   • Screen Lens — Vision OCR of whatever is on screen → copy
 *   • Sculpt — tap any UI element to hide it forever in that app (Flex for humans)
 *
 * Designed around RootHide Bootstrap's per-app injection model: filter on
 * com.apple.UIKit so enabling an app in Bootstrap App List is enough. Also
 * works on Dopamine / other rootless jails, and on SpringBoard when SB
 * injection is available (Bootstrap 2.0+, Dopamine).
 */

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <notify.h>
#import "Shared/AEPrefs.h"
#import "Shared/AEClipboardStore.h"
#import "Shared/AESculptStore.h"
#import "Shared/AEGlassPanel.h"
#import "Shared/AEGestureHost.h"

static NSString * const kAEPrefsChanged = @"com.kolby.aether/prefschanged";

@interface AEController : NSObject <AEGlassPanelDelegate, AEGestureHostDelegate>
@property (nonatomic, strong, nullable) AEGlassPanel *panel;
@property (nonatomic, weak, nullable) UIWindow *activeWindow;
@end

@implementation AEController

+ (instancetype)shared {
    static AEController *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [AEController new]; });
    return s;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [AEGestureHost shared].delegate = self;
        [[AEClipboardStore shared] startObserving];
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        (__bridge const void *)self,
                                        AEPrefsChangedCallback,
                                        (__bridge CFStringRef)kAEPrefsChanged,
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
    }
    return self;
}

static void AEPrefsChangedCallback(CFNotificationCenterRef center, void *observer,
                                   CFStringRef name, const void *object,
                                   CFDictionaryRef userInfo) {
    (void)center; (void)observer; (void)name; (void)object; (void)userInfo;
    AEPrefsInvalidate();
}

- (UIWindow *)keyWindowCandidate {
    if (self.activeWindow && self.activeWindow.isKeyWindow) return self.activeWindow;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        UIWindowScene *ws = (UIWindowScene *)scene;
        for (UIWindow *w in ws.windows) {
            if (w.isKeyWindow && !w.hidden && w.alpha > 0.01) return w;
        }
        for (UIWindow *w in ws.windows) {
            if (!w.hidden && w.alpha > 0.01) return w;
        }
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return UIApplication.sharedApplication.keyWindow;
#pragma clang diagnostic pop
}

- (void)registerWindow:(UIWindow *)window {
    if (!AEPrefBool(@"enabled", YES)) return;
    // Avoid private/alert edge cases
    if (window.windowLevel > UIWindowLevelAlert) return;
    self.activeWindow = window;
    [[AEGestureHost shared] attachToWindow:window];
    [[AESculptStore shared] applyToWindow:window bundleID:AECurrentBundleID()];
}

- (void)gestureHostDidSummon {
    [self presentPanel];
}

- (void)gestureHostDidCancelSculpt {
    // no-op toast opportunity
}

- (void)presentPanel {
    if (self.panel.superview) {
        [self.panel dismissAnimated:YES];
        return;
    }
    UIWindow *window = [self keyWindowCandidate];
    if (!window) return;
    AEGlassPanel *panel = [[AEGlassPanel alloc] initWithFrame:window.bounds];
    panel.delegate = self;
    self.panel = panel;
    [panel presentInWindow:window];
}

- (void)glassPanelDidRequestDismiss:(AEGlassPanel *)panel {
    if (self.panel == panel) self.panel = nil;
}

- (void)glassPanelDidEnterSculptMode:(AEGlassPanel *)panel {
    (void)panel;
    UIWindow *window = [self keyWindowCandidate];
    if (!window) return;
    [[AEGestureHost shared] beginSculptInWindow:window];
}

- (void)glassPanelDidRequestClearSculpt:(AEGlassPanel *)panel {
    (void)panel;
    [[AESculptStore shared] clearBundle:AECurrentBundleID()];
}

@end

// -----------------------------------------------------------------------------
// Hooks — catch windows as they become key / finish layout
// -----------------------------------------------------------------------------

%hook UIWindow

- (void)makeKeyAndVisible {
    %orig;
    if (!AEPrefBool(@"enabled", YES)) return;
    [[AEController shared] registerWindow:(UIWindow *)self];
}

- (void)becomeKeyWindow {
    %orig;
    if (!AEPrefBool(@"enabled", YES)) return;
    [[AEController shared] registerWindow:(UIWindow *)self];
}

- (void)didAddSubview:(UIView *)subview {
    %orig;
    // Re-apply sculpt when UI rebuilds (common in social apps)
    if (!AEPrefBool(@"sculptEnabled", YES)) return;
    if (!AEPrefBool(@"enabled", YES)) return;
    static CFAbsoluteTime last = 0;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (now - last < 0.75) return;
    last = now;
    UIWindow *win = (UIWindow *)self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [[AESculptStore shared] applyToWindow:win bundleID:AECurrentBundleID()];
    });
}

%end

%ctor {
    @autoreleasepool {
        if (!AEPrefBool(@"enabled", YES)) return;

        NSString *bid = AECurrentBundleID();
        NSString *process = [NSProcessInfo processInfo].processName ?: @"";
        // Skip WebKit content/network processes and app extensions
        if ([process containsString:@"WebContent"] ||
            [process containsString:@"Networking"] ||
            [process containsString:@"GPU"] ||
            [bid hasSuffix:@"appex"] ||
            [bid containsString:@".appex"]) {
            return;
        }

        (void)[AEController shared];

        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationDidFinishLaunchingNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(__unused NSNotification *note) {
            UIWindow *w = [[AEController shared] keyWindowCandidate];
            if (w) [[AEController shared] registerWindow:w];
        }];
    }
}
