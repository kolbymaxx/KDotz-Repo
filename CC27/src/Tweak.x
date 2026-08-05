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

- (void)viewDidLayoutSubviews {
    %orig;
    if (!CC27Prefs.shared.enabled) return;
    [CC27EditSession.shared attachChromeToHost:self];
    if (CC27EditSession.shared.editing) {
        // Keep Add a Control pinned while rotating / resizing.
        UIView *add = [self.view viewWithTag:0x43323741];
        if (add) {
            CGFloat w = MIN(220, self.view.bounds.size.width - 48);
            CGFloat y = self.view.bounds.size.height - self.view.safeAreaInsets.bottom - 56;
            add.frame = CGRectMake((self.view.bounds.size.width - w) / 2.0, y, w, 44);
            [self.view bringSubviewToFront:add];
        }
    }
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
        // Best-effort identifier resolution for decorations after layout.
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

%end

%hook CCUIModuleCollectionViewController

- (NSArray *)_sizesForModuleIdentifiers:(NSArray *)moduleIdentifiers moduleInstanceByIdentifier:(NSDictionary *)moduleInstanceByIdentifier interfaceOrientation:(long long)interfaceOrientation {
    NSArray *sizes = %orig;
    if (!CC27Prefs.shared.enabled || !CC27Prefs.shared.allowResize) return sizes;
    if (![sizes isKindOfClass:NSArray.class] || sizes.count != moduleIdentifiers.count) return sizes;

    NSMutableArray *mutable = sizes.mutableCopy;
    BOOL changed = NO;
    for (NSUInteger i = 0; i < moduleIdentifiers.count; i++) {
        NSString *identifier = moduleIdentifiers[i];
        NSValue *currentValue = mutable[i];
        CCUILayoutSize fallback = {1, 1};
        if ([currentValue respondsToSelector:@selector(ccui_sizeValue)]) {
            fallback = [currentValue ccui_sizeValue];
        } else if (strcmp(currentValue.objCType, @encode(CCUILayoutSize)) == 0) {
            [currentValue getValue:&fallback];
        }
        CCUILayoutSize override = [CC27LayoutStore.shared sizeForModule:identifier fallback:fallback];
        if (override.width == fallback.width && override.height == fallback.height) continue;

        NSValue *newValue = nil;
        if ([NSValue respondsToSelector:@selector(ccui_valueWithLayoutSize:)]) {
            newValue = [NSValue ccui_valueWithLayoutSize:override];
        } else {
            newValue = [NSValue valueWithBytes:&override objCType:@encode(CCUILayoutSize)];
        }
        if (newValue) {
            mutable[i] = newValue;
            changed = YES;
        }
    }
    return changed ? mutable : sizes;
}

%end

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
            NSLog(@"[CC27] loaded — glass + edit mode + gallery");
        } else {
            NSLog(@"[CC27] disabled in prefs");
        }
    }
}
