#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import "src/SPPrefs.h"
#import "src/SPSwiftMeta.h"
#import "src/SPDumpWriter.h"

// -----------------------------------------------------------------------------
// SwiftPeek — read-only SwiftUI inspector (Phase 1 / milestone 1: Attach)
// -----------------------------------------------------------------------------

@interface _UIHostingView : UIView
@end

@interface UIHostingController : UIViewController
@end

static NSMutableSet *gSPLoggedHosts;
static NSInteger gSPAttachCount = 0;
static const NSInteger kSPMaxAttachLogs = 32;
static BOOL gSPHookedHostingView = NO;
static BOOL gSPHookedHostingController = NO;

static void SPPrefsChangedCallback(CFNotificationCenterRef center, void *observer,
                                   CFStringRef name, const void *object,
                                   CFDictionaryRef userInfo) {
    SPPrefsInvalidate();
}

static void SPWriteHeartbeat(NSString *message, BOOL hooked) {
    NSMutableArray *prefsInfo = [NSMutableArray array];
    for (NSString *p in SPPrefsCandidatePaths()) {
        BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:p];
        [prefsInfo addObject:@{ @"path": p, @"exists": @(exists) }];
    }
    SPWriteStatus(@{
        @"status": hooked ? @"hooked" : @"loaded",
        @"enabled": @(SPPrefBool(@"enabled", NO)),
        @"jbroot": SPJailbreakRootPrefix() ?: @"",
        @"prefs_paths": prefsInfo,
        @"hosting_view": @(NSClassFromString(@"_UIHostingView") != nil),
        @"hosting_controller": @(NSClassFromString(@"UIHostingController") != nil),
        @"hooked": @(hooked),
        @"message": message ?: @"",
    });
}

static void SPLogAttach(UIView *host) {
    if (!host) return;

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

    if (SPPrefBool(@"logAttach", YES)) {
        NSLog(@"[SwiftPeek] attach process=%@ type=%@ addr=0x%lx class=%s",
              proc, typeName, (unsigned long)addr, object_getClassName(host));
    }

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
            SPWriteHeartbeat(@"attach dump written", YES);
        } else {
            SPWriteHeartbeat(@"attach seen but dump write failed", YES);
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

static void SPTryInstallHooks(void) {
    if (!gSPHookedHostingView && NSClassFromString(@"_UIHostingView")) {
        %init(SPHostingViewAttach);
        gSPHookedHostingView = YES;
        NSLog(@"[SwiftPeek] hooked _UIHostingView");
    }
    if (!gSPHookedHostingController && NSClassFromString(@"UIHostingController")) {
        %init(SPHostingControllerAttach);
        gSPHookedHostingController = YES;
        NSLog(@"[SwiftPeek] hooked UIHostingController");
    }
    BOOL hooked = gSPHookedHostingView || gSPHookedHostingController;
    if (hooked) {
        SPWriteHeartbeat(@"hooks installed", YES);
    } else {
        SPWriteHeartbeat(@"enabled but hosting classes not loaded yet", NO);
    }
}

static void SPOnImageAdded(const struct mach_header *mh, intptr_t slide) {
    (void)slide;
    Dl_info info = {0};
    if (!dladdr(mh, &info) || !info.dli_fname) return;
    if (!strstr(info.dli_fname, "SwiftUI")) return;
    // SwiftUI just mapped — install hooks on the main queue.
    dispatch_async(dispatch_get_main_queue(), ^{
        SPTryInstallHooks();
    });
}

%ctor {
    @autoreleasepool {
        // Always leave a Filza breadcrumb so we can see the dylib loaded,
        // even when the kill switch is off.
        BOOL enabled = SPPrefBool(@"enabled", NO);
        SPWriteHeartbeat(enabled ? @"ctor enabled" : @"ctor disabled (kill switch)", NO);

        if (!enabled) {
            NSLog(@"[SwiftPeek] disabled — idle");
            return;
        }

        NSString *proc = NSProcessInfo.processInfo.processName ?: @"?";
        NSString *jb = SPJailbreakRootPrefix() ?: @"";
        NSLog(@"[SwiftPeek] loaded in %@ jbroot='%@'", proc, jb);

        // Immediate attempt (works if SwiftUI already loaded).
        SPTryInstallHooks();

        // SwiftUI is often loaded after tweak ctors in Music — retry.
        _dyld_register_func_for_add_image(SPOnImageAdded);

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            SPTryInstallHooks();
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            SPTryInstallHooks();
        });

        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL,
                                        SPPrefsChangedCallback,
                                        CFSTR("com.kolby.swiftpeek/prefschanged"),
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
    }
}
