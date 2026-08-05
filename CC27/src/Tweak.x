#import "CC27.h"
#import <objc/runtime.h>
#import <string.h>

static void CC27ReloadPrefs(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    [CC27Prefs.shared reload];
    [CC27LayoutStore.shared reload];
}

// On iOS 16+, the Lock Screen's flashlight / camera quick actions embed real
// CC module container views — the exact class we hook. CC27 must never style
// or decorate those: mutating lock screen views can wedge the whole cover
// sheet. Only views living inside actual Control Center chrome qualify.
static BOOL CC27ViewIsInControlCenter(UIView *view) {
    UIView *v = view;
    while (v) {
        const char *cls = class_getName(v.class);
        if (cls) {
            if (strstr(cls, "QuickAction") || strstr(cls, "CoverSheet") ||
                strstr(cls, "DashBoard") || strstr(cls, "Dashboard") ||
                strstr(cls, "LockScreen")) {
                return NO;
            }
        }
        v = v.superview;
    }
    return YES;
}

%group CC27

%hook CCUIModularControlCenterOverlayViewController

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    if (!CC27Prefs.shared.enabled) return;
    // Fully inert while locked — CC presented over the lock screen stays stock.
    if ([CC27EditSession deviceUILocked]) return;
    [CC27EditSession.shared setHostVisible:YES host:self];
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (!CC27Prefs.shared.enabled) return;
    if ([CC27EditSession deviceUILocked]) return;
    [CC27EditSession.shared setHostVisible:YES host:self];
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    if (!CC27Prefs.shared.enabled) return;
    [CC27EditSession.shared setHostVisible:NO host:self];
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    if (!CC27Prefs.shared.enabled) return;
    [CC27EditSession.shared setHostVisible:NO host:self];
}

- (void)viewDidLayoutSubviews {
    %orig;
    if (!CC27Prefs.shared.enabled) return;
    // Chrome is created lazily on first presentation (viewWillAppear), not at
    // SpringBoard boot — here we only keep existing chrome positioned.
    if (CC27EditSession.shared.hostVisible) {
        [CC27EditSession.shared layoutChromeOnHost:self];
    }
}

- (void)setPresentationState:(NSInteger)state {
    %orig;
    if (!CC27Prefs.shared.enabled) return;
    if ([CC27EditSession deviceUILocked]) {
        [CC27EditSession.shared setHostVisible:NO host:self];
        return;
    }
    [CC27EditSession.shared updateChromeForPresentationState:state host:self];
}

%end

%hook CCUIContentModuleContentContainerView

- (void)layoutSubviews {
    %orig;
    if (!CC27Prefs.shared.enabled) return;
    // Fully inert while the device UI is locked.
    if ([CC27EditSession deviceUILocked]) return;
    // Never touch module containers hosted outside Control Center (Lock
    // Screen quick actions on iOS 16 use this same class).
    if (!CC27ViewIsInControlCenter(self)) return;
    @try {
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
    } @catch (NSException *e) {
        NSLog(@"[CC27] module styling threw (suppressed): %@", e);
    }
}

%end // CCUIContentModuleContentContainerView

%end // group

%ctor {
    @autoreleasepool {
        // Emergency kill switch: create this file (e.g. via SSH/Filza) and
        // respring to fully disable CC27 without uninstalling:
        //   touch /var/mobile/Library/Preferences/com.kolby.cc27.killswitch
        if ([[NSFileManager defaultManager] fileExistsAtPath:@"/var/mobile/Library/Preferences/com.kolby.cc27.killswitch"]) {
            NSLog(@"[CC27] kill switch present — not loading");
            return;
        }
        [CC27Prefs.shared reload];
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL,
                                        CC27ReloadPrefs,
                                        CFSTR("com.kolby.cc27/ReloadPrefs"),
                                        NULL,
                                        CFNotificationSuspensionBehaviorCoalesce);
        if (CC27Prefs.shared.enabled) {
            %init(CC27);
            NSLog(@"[CC27] 1.0.6 loaded — fully inert while device is locked");
        } else {
            NSLog(@"[CC27] disabled in prefs");
        }
    }
}
