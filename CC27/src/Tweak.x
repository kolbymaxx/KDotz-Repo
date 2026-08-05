#import "CC27.h"

static void CC27ReloadPrefs(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    [CC27Prefs.shared reload];
    [CC27LayoutStore.shared reload];
}

%group CC27

%hook CCUIModularControlCenterOverlayViewController

- (void)viewDidLoad {
    %orig;
    if (!CC27Prefs.shared.enabled) return;
    [CC27EditSession.shared attachChromeToHost:self];
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    if (!CC27Prefs.shared.enabled) return;
    [CC27EditSession.shared setHostVisible:YES host:self];
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (!CC27Prefs.shared.enabled) return;
    [CC27EditSession.shared setHostVisible:YES host:self];
    [CC27EditSession.shared layoutChromeOnHost:self];
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    if (!CC27Prefs.shared.enabled) return;
    // Don't hide chrome just because a sheet is presenting over CC.
    if (self.presentedViewController) return;
    [CC27EditSession.shared setHostVisible:NO host:self];
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    if (!CC27Prefs.shared.enabled) return;
    if (self.presentedViewController) return;
    if (self.view.window != nil) return;
    [CC27EditSession.shared setHostVisible:NO host:self];
}

- (void)viewDidLayoutSubviews {
    %orig;
    if (!CC27Prefs.shared.enabled) return;
    [CC27EditSession.shared attachChromeToHost:self];
    if (self.view.window != nil) {
        [CC27EditSession.shared setHostVisible:YES host:self];
    }
    [CC27EditSession.shared layoutChromeOnHost:self];
}

- (void)setPresentationState:(NSInteger)state {
    %orig;
    if (!CC27Prefs.shared.enabled) return;
    [CC27EditSession.shared updateChromeForPresentationState:state host:self];
}

%end

%hook CCUIContentModuleContentContainerView

- (void)layoutSubviews {
    %orig;
    if (!CC27Prefs.shared.enabled) return;
    if (CC27Prefs.shared.glassChrome) {
        [CC27Glass applyToModuleContainer:self];
    }
    if (CC27EditSession.shared.editing) {
        NSString *identifier = nil;
        UIView *v = self;
        while (v) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            SEL sel = NSSelectorFromString(@"_viewControllerForAncestor");
            UIViewController *vc = [v respondsToSelector:sel] ? [v performSelector:sel] : nil;
#pragma clang diagnostic pop
            if ([vc isKindOfClass:NSClassFromString(@"CCUIContentModuleContainerViewController")]) {
                @try { identifier = [vc valueForKey:@"moduleIdentifier"]; } @catch (__unused NSException *e) {}
                break;
            }
            v = v.superview;
        }
        if (identifier.length) {
            [CC27EditSession.shared decorateModuleContainer:self identifier:identifier];
        }
    }
}

%end // CCUIContentModuleContentContainerView

%end // group

%ctor {
    @autoreleasepool {
        [CC27Prefs.shared reload];
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL,
                                        CC27ReloadPrefs,
                                        CFSTR("com.kolby.cc27/ReloadPrefs"),
                                        NULL,
                                        CFNotificationSuspensionBehaviorCoalesce);
        if (CC27Prefs.shared.enabled) {
            %init(CC27);
            NSLog(@"[CC27] 1.0.3 loaded — safe add (no live rebuild), sticky chrome, softer glass");
        } else {
            NSLog(@"[CC27] disabled in prefs");
        }
    }
}
