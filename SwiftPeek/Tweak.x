#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "src/SPPrefs.h"
#import "src/SPSwiftMeta.h"
#import "src/SPDumpWriter.h"

// -----------------------------------------------------------------------------
// SwiftPeek — read-only SwiftUI inspector (Phase 1 / milestone 1: Attach)
//
// Hook _UIHostingView layoutSubviews (and UIHostingController as backup),
// recover a Swift type name for the hosting view, log + JSON dump.
// Mutation is out of scope.
// -----------------------------------------------------------------------------

@interface _UIHostingView : UIView
@end

@interface UIHostingController : UIViewController
@end

// Rate-limit attach logs so layoutSubviews doesn't flood.
static NSMutableSet *gSPLoggedHosts;
static NSInteger gSPAttachCount = 0;
static const NSInteger kSPMaxAttachLogs = 32;

static void SPPrefsChangedCallback(CFNotificationCenterRef center, void *observer,
                                   CFStringRef name, const void *object,
                                   CFDictionaryRef userInfo) {
    SPPrefsInvalidate();
}

static void SPLogAttach(UIView *host) {
    if (!host) return;
    if (!SPPrefBool(@"logAttach", YES)) return;

    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gSPLoggedHosts = [NSMutableSet set];
    });

    NSValue *key = [NSValue valueWithNonretainedObject:host];
    if ([gSPLoggedHosts containsObject:key]) return;
    if (gSPAttachCount >= kSPMaxAttachLogs) return;
    [gSPLoggedHosts addObject:key];
    gSPAttachCount++;

    NSString *typeName = SPSwiftTypeNameFromObject(host) ?: @"<unknown>";
    uintptr_t addr = (uintptr_t)(__bridge void *)host;
    NSString *proc = NSProcessInfo.processInfo.processName ?: @"?";

    NSLog(@"[SwiftPeek] attach process=%@ type=%@ addr=0x%lx class=%s",
          proc, typeName, (unsigned long)addr, object_getClassName(host));

    // Milestone 1 artifact: tiny JSON dump so SSH can confirm without log stream.
    // Write off the layout path — never block UI on disk I/O.
    NSDictionary *node = @{
        @"address": [NSString stringWithFormat:@"0x%lx", (unsigned long)addr],
        @"objc_class": @(object_getClassName(host) ?: "?"),
        @"type": typeName,
    };
    NSDictionary *payload = @{
        @"milestone": @1,
        @"nodes": @[node],
    };
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSString *path = SPWriteJSONDump(payload);
        if (path) {
            NSLog(@"[SwiftPeek] dump written %@", path);
        }
    });
}

%group SPHostingViewAttach
%hook _UIHostingView
- (void)layoutSubviews {
    %orig;
    @try {
        SPLogAttach((UIView *)self);
    } @catch (__unused id e) {
    }
}
%end
%end

%group SPHostingControllerAttach
%hook UIHostingController
- (void)viewDidLayoutSubviews {
    %orig;
    @try {
        SPLogAttach(self.view);
    } @catch (__unused id e) {
    }
}
%end
%end

%ctor {
    @autoreleasepool {
        // Kill switch — default OFF.
        if (!SPPrefBool(@"enabled", NO)) {
            return;
        }

        NSString *proc = NSProcessInfo.processInfo.processName ?: @"?";
        NSString *jb = SPJailbreakRootPrefix() ?: @"";
        NSLog(@"[SwiftPeek] loaded in %@ jbroot='%@'", proc, jb);

        BOOL inited = NO;
        if (NSClassFromString(@"_UIHostingView")) {
            %init(SPHostingViewAttach);
            inited = YES;
            NSLog(@"[SwiftPeek] hooked _UIHostingView");
        }
        if (NSClassFromString(@"UIHostingController")) {
            %init(SPHostingControllerAttach);
            inited = YES;
            NSLog(@"[SwiftPeek] hooked UIHostingController");
        }
        if (NSClassFromString(@"_UIGraphicsView")) {
            NSLog(@"[SwiftPeek] noted _UIGraphicsView present (no hook in m1)");
        }
        if (!inited) {
            NSLog(@"[SwiftPeek] no hosting class in %@ — idle", proc);
        }

        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL,
                                        SPPrefsChangedCallback,
                                        CFSTR("com.kolby.swiftpeek/prefschanged"),
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
    }
}
