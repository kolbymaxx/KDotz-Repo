#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import "src/SPPrefs.h"
#import "src/SPSwiftMeta.h"
#import "src/SPDumpWriter.h"

// Substrate / ElleKit — provided at link time by Theos tweak.mk
FOUNDATION_EXTERN void MSHookMessageEx(Class _class, SEL sel, IMP imp, IMP *result);

// -----------------------------------------------------------------------------
// SwiftPeek — read-only SwiftUI inspector (Phase 1 / milestone 1: Attach)
//
// On iOS 16+, _UIHostingView is often only visible as a Swift-mangled class
// name, so Logos %hook _UIHostingView never binds. We discover the class and
// MSHookMessageEx layoutSubviews instead.
// -----------------------------------------------------------------------------

static NSMutableSet *gSPLoggedHosts;
static NSInteger gSPAttachCount = 0;
static const NSInteger kSPMaxAttachLogs = 32;
static BOOL gSPHookedHostingView = NO;
static BOOL gSPHookedHostingController = NO;
static NSString *gSPHookedViewClassName;
static NSString *gSPHookedControllerClassName;

static void (*gSPOrigLayoutSubviews)(UIView *, SEL) = NULL;
static void (*gSPOrigViewDidLayout)(UIViewController *, SEL) = NULL;

static void SPPrefsChangedCallback(CFNotificationCenterRef center, void *observer,
                                   CFStringRef name, const void *object,
                                   CFDictionaryRef userInfo) {
    SPPrefsInvalidate();
}

static void SPEnsureSwiftUILoaded(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // Force the framework in if Music hasn't opened it yet.
        void *h = dlopen("/System/Library/Frameworks/SwiftUI.framework/SwiftUI",
                         RTLD_LAZY | RTLD_NOLOAD);
        if (!h) {
            h = dlopen("/System/Library/Frameworks/SwiftUI.framework/SwiftUI",
                       RTLD_LAZY);
        }
        (void)h;
        NSBundle *b = [NSBundle bundleWithPath:@"/System/Library/Frameworks/SwiftUI.framework"];
        if (b && !b.isLoaded) [b load];
    });
}

static BOOL SPNameLooksLikeHostingView(const char *name) {
    if (!name) return NO;
    // Exact ObjC name, or Swift mangled containing UIHostingView / _UIHostingView.
    if (strcmp(name, "_UIHostingView") == 0) return YES;
    if (strstr(name, "_UIHostingView") != NULL) return YES;
    if (strstr(name, "UIHostingView") != NULL) return YES;
    return NO;
}

static BOOL SPNameLooksLikeHostingController(const char *name) {
    if (!name) return NO;
    if (strcmp(name, "UIHostingController") == 0) return YES;
    if (strstr(name, "UIHostingController") != NULL) return YES;
    // Skip secure / document variants for the first hook — root Music hosts matter most.
    if (strstr(name, "SecureHosting") != NULL) return NO;
    if (strstr(name, "DocumentHosting") != NULL) return NO;
    return NO;
}

/// Prefer shorter / less-specialized names when multiple candidates exist.
static Class SPPickBestClass(NSArray<NSValue *> *classes) {
    Class best = Nil;
    NSUInteger bestLen = NSUIntegerMax;
    for (NSValue *v in classes) {
        Class c = v.pointerValue;
        if (!c) continue;
        const char *n = class_getName(c);
        NSUInteger len = n ? strlen(n) : NSUIntegerMax;
        if (len < bestLen) {
            best = c;
            bestLen = len;
        }
    }
    return best;
}

static Class SPFindHostingViewClass(NSMutableArray *outNames) {
    Class direct = NSClassFromString(@"_UIHostingView");
    if (direct) {
        [outNames addObject:@"_UIHostingView"];
        return direct;
    }

    unsigned int n = 0;
    Class *list = objc_copyClassList(&n);
    if (!list) return Nil;

    NSMutableArray<NSValue *> *candidates = [NSMutableArray array];
    for (unsigned int i = 0; i < n; i++) {
        const char *name = class_getName(list[i]);
        if (!SPNameLooksLikeHostingView(name)) continue;
        [outNames addObject:@(name)];
        // Prefer UIView subclasses only.
        if (![list[i] isSubclassOfClass:[UIView class]]) continue;
        [candidates addObject:[NSValue valueWithPointer:(__bridge void *)list[i]]];
    }
    free(list);
    return SPPickBestClass(candidates);
}

static Class SPFindHostingControllerClass(NSMutableArray *outNames) {
    Class direct = NSClassFromString(@"UIHostingController");
    if (direct) {
        [outNames addObject:@"UIHostingController"];
        return direct;
    }

    unsigned int n = 0;
    Class *list = objc_copyClassList(&n);
    if (!list) return Nil;

    NSMutableArray<NSValue *> *candidates = [NSMutableArray array];
    for (unsigned int i = 0; i < n; i++) {
        const char *name = class_getName(list[i]);
        if (!SPNameLooksLikeHostingController(name)) continue;
        [outNames addObject:@(name)];
        if (![list[i] isSubclassOfClass:[UIViewController class]]) continue;
        [candidates addObject:[NSValue valueWithPointer:(__bridge void *)list[i]]];
    }
    free(list);
    return SPPickBestClass(candidates);
}

static void SPWriteHeartbeat(NSString *message, BOOL hooked,
                             NSArray *viewNames, NSArray *controllerNames) {
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
        @"hosting_view": @((viewNames.count > 0) || gSPHookedHostingView),
        @"hosting_controller": @((controllerNames.count > 0) || gSPHookedHostingController),
        @"hosting_view_names": viewNames ?: @[],
        @"hosting_controller_names": controllerNames ?: @[],
        @"hooked_view_class": gSPHookedViewClassName ?: [NSNull null],
        @"hooked_controller_class": gSPHookedControllerClassName ?: [NSNull null],
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
        SPWriteHeartbeat(path ? @"attach dump written" : @"attach seen but dump write failed",
                         YES, @[], @[]);
        if (path) NSLog(@"[SwiftPeek] dump written %@", path);
    });
}

static void SPHookedLayoutSubviews(UIView *self, SEL _cmd) {
    if (gSPOrigLayoutSubviews) gSPOrigLayoutSubviews(self, _cmd);
    @try {
        SPLogAttach(self);
    } @catch (__unused id e) {
    }
}

static void SPHookedViewDidLayout(UIViewController *self, SEL _cmd) {
    if (gSPOrigViewDidLayout) gSPOrigViewDidLayout(self, _cmd);
    @try {
        SPLogAttach(self.view);
    } @catch (__unused id e) {
    }
}

static void SPTryInstallHooks(void) {
    SPEnsureSwiftUILoaded();

    NSMutableArray *viewNames = [NSMutableArray array];
    NSMutableArray *controllerNames = [NSMutableArray array];

    if (!gSPHookedHostingView) {
        Class viewCls = SPFindHostingViewClass(viewNames);
        if (viewCls && class_getInstanceMethod(viewCls, @selector(layoutSubviews))) {
            MSHookMessageEx(viewCls,
                            @selector(layoutSubviews),
                            (IMP)SPHookedLayoutSubviews,
                            (IMP *)&gSPOrigLayoutSubviews);
            gSPHookedHostingView = YES;
            gSPHookedViewClassName = @(class_getName(viewCls));
            NSLog(@"[SwiftPeek] hooked layoutSubviews on %s", class_getName(viewCls));
        }
    }

    if (!gSPHookedHostingController) {
        Class vcCls = SPFindHostingControllerClass(controllerNames);
        if (vcCls && class_getInstanceMethod(vcCls, @selector(viewDidLayoutSubviews))) {
            MSHookMessageEx(vcCls,
                            @selector(viewDidLayoutSubviews),
                            (IMP)SPHookedViewDidLayout,
                            (IMP *)&gSPOrigViewDidLayout);
            gSPHookedHostingController = YES;
            gSPHookedControllerClassName = @(class_getName(vcCls));
            NSLog(@"[SwiftPeek] hooked viewDidLayoutSubviews on %s", class_getName(vcCls));
        }
    }

    BOOL hooked = gSPHookedHostingView || gSPHookedHostingController;
    if (hooked) {
        SPWriteHeartbeat(@"hooks installed via MSHookMessageEx", YES, viewNames, controllerNames);
    } else if (viewNames.count || controllerNames.count) {
        SPWriteHeartbeat(@"found candidate classes but hook failed", NO, viewNames, controllerNames);
    } else {
        SPWriteHeartbeat(@"enabled but no hosting classes visible yet", NO, viewNames, controllerNames);
    }
}

static void SPOnImageAdded(const struct mach_header *mh, intptr_t slide) {
    (void)slide;
    // Resolve image name reliably (dladdr on cache headers is flaky).
    const char *imageName = NULL;
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        if (_dyld_get_image_header(i) == mh) {
            imageName = _dyld_get_image_name(i);
            break;
        }
    }
    if (!imageName || !strstr(imageName, "SwiftUI")) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        SPTryInstallHooks();
    });
}

%ctor {
    @autoreleasepool {
        BOOL enabled = SPPrefBool(@"enabled", NO);
        SPWriteHeartbeat(enabled ? @"ctor enabled" : @"ctor disabled (kill switch)",
                         NO, @[], @[]);

        if (!enabled) {
            NSLog(@"[SwiftPeek] disabled — idle");
            return;
        }

        NSString *proc = NSProcessInfo.processInfo.processName ?: @"?";
        NSString *jb = SPJailbreakRootPrefix() ?: @"";
        NSLog(@"[SwiftPeek] loaded in %@ jbroot='%@'", proc, jb);

        SPTryInstallHooks();
        _dyld_register_func_for_add_image(SPOnImageAdded);

        for (NSNumber *sec in @[ @0.5, @1.5, @3.0, @6.0, @12.0 ]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                         (int64_t)(sec.doubleValue * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                if (!gSPHookedHostingView && !gSPHookedHostingController) {
                    SPTryInstallHooks();
                }
            });
        }

        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL,
                                        SPPrefsChangedCallback,
                                        CFSTR("com.kolby.swiftpeek/prefschanged"),
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
    }
}
