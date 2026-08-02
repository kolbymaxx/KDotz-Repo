#import "Music27.h"

// Constructor + preference observers. Logos %ctor runs once when Music loads.

static void M27ForceTabBarRelayout(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            UIViewController *root = window.rootViewController;
            if (!root) continue;
            if ([root isKindOfClass:UITabBarController.class]) {
                [root.view setNeedsLayout];
                [root.view layoutIfNeeded];
            }
            NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:root.view];
            while (stack.count) {
                UIView *view = stack.lastObject;
                [stack removeLastObject];
                if ([view isKindOfClass:UITabBar.class] || view.tag == 0x4D323744) {
                    [view setNeedsLayout];
                    [view layoutIfNeeded];
                }
                [stack addObjectsFromArray:view.subviews];
            }
        }
    }
}

static void M27ReloadPrefsCallback(CFNotificationCenterRef center, void *observer,
                                   CFStringRef name, const void *object,
                                   CFDictionaryRef userInfo) {
    [M27Prefs.shared reload];
    dispatch_async(dispatch_get_main_queue(), ^{
        M27ForceTabBarRelayout();
    });
}

static void M27ClearPinsCallback(CFNotificationCenterRef center, void *observer,
                                 CFStringRef name, const void *object,
                                 CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [M27PinStore.shared clearAll];
    });
}

%ctor {
    @autoreleasepool {
        [M27Prefs.shared reload];
        (void)M27PinStore.shared;
        (void)M27ColorTheme.shared;

        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            M27ReloadPrefsCallback,
            CFSTR("com.music27.tweak/ReloadPrefs"),
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);

        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            M27ClearPinsCallback,
            CFSTR("com.music27.tweak/ClearPins"),
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);
    }
}
