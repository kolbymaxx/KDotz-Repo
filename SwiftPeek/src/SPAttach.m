#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import "SPPrefs.h"
#import "SPSwiftMeta.h"
#import "SPDumpWriter.h"

// -----------------------------------------------------------------------------
// SwiftPeek — read-only SwiftUI inspector (Phase 1 / milestone 1: Attach)
// -----------------------------------------------------------------------------

static NSMutableSet *gSPLoggedHosts;
static NSInteger gSPAttachCount = 0;
static const NSInteger kSPMaxAttachLogs = 32;
static BOOL gSPHookedHostingView = NO;
static BOOL gSPHookedHostingController = NO;
static NSString *gSPHookedViewClassName;
static NSString *gSPHookedControllerClassName;
static NSMutableSet *gSPSwizzledKeys;

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
        if (!dlopen("/System/Library/Frameworks/SwiftUI.framework/SwiftUI",
                    RTLD_LAZY | RTLD_NOLOAD)) {
            dlopen("/System/Library/Frameworks/SwiftUI.framework/SwiftUI", RTLD_LAZY);
        }
        NSBundle *b = [NSBundle bundleWithPath:@"/System/Library/Frameworks/SwiftUI.framework"];
        if (b && !b.isLoaded) [b load];
    });
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

    if (SPPrefBool(@"logAttach", YES)) {
        NSLog(@"[SwiftPeek] attach process=%@ type=%@ addr=0x%lx class=%s",
              NSProcessInfo.processInfo.processName ?: @"?",
              typeName, (unsigned long)addr, object_getClassName(host));
    }

    NSDictionary *payload = @{
        @"milestone": @1,
        @"nodes": @[
            @{
                @"address": [NSString stringWithFormat:@"0x%lx", (unsigned long)addr],
                @"objc_class": @(object_getClassName(host) ?: "?"),
                @"type": typeName,
            }
        ],
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
    @try { SPLogAttach(self); } @catch (__unused id e) {}
}

static void SPHookedViewDidLayout(UIViewController *self, SEL _cmd) {
    if (gSPOrigViewDidLayout) gSPOrigViewDidLayout(self, _cmd);
    @try { SPLogAttach(self.view); } @catch (__unused id e) {}
}

static BOOL SPSwizzle(Class cls, SEL sel, IMP replacement, IMP *origOut) {
    if (!cls || !sel || !replacement || !origOut) return NO;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return NO;

    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gSPSwizzledKeys = [NSMutableSet set];
    });
    NSString *key = [NSString stringWithFormat:@"%s|%s", class_getName(cls), sel_getName(sel)];
    if ([gSPSwizzledKeys containsObject:key]) return YES;

    IMP current = method_getImplementation(m);
    if (current == replacement) {
        [gSPSwizzledKeys addObject:key];
        return YES;
    }
    if (*origOut != NULL && current == (IMP)(*origOut)) {
        method_setImplementation(m, replacement);
        [gSPSwizzledKeys addObject:key];
        return YES;
    }

    IMP prev = method_setImplementation(m, replacement);
    if (!prev) return NO;
    if (*origOut == NULL) *origOut = prev;
    [gSPSwizzledKeys addObject:key];
    return YES;
}

static void SPTryInstallHooks(void) {
    SPEnsureSwiftUILoaded();

    NSMutableArray *viewClasses = [NSMutableArray array];
    NSMutableArray *viewNames = [NSMutableArray array];
    NSMutableArray *vcClasses = [NSMutableArray array];
    NSMutableArray *vcNames = [NSMutableArray array];

    Class directView = NSClassFromString(@"_UIHostingView");
    if (directView && [directView isSubclassOfClass:[UIView class]]) {
        [viewNames addObject:@"_UIHostingView"];
        [viewClasses addObject:[NSValue valueWithPointer:(__bridge void *)directView]];
    }

    Class directVC = NSClassFromString(@"UIHostingController");
    if (directVC && [directVC isSubclassOfClass:[UIViewController class]]) {
        [vcNames addObject:@"UIHostingController"];
        [vcClasses addObject:[NSValue valueWithPointer:(__bridge void *)directVC]];
    }

    unsigned int n = 0;
    Class *list = objc_copyClassList(&n);
    if (list) {
        for (unsigned int i = 0; i < n; i++) {
            const char *name = class_getName(list[i]);
            if (!name) continue;

            BOOL looksView = (strcmp(name, "_UIHostingView") == 0) ||
                             (strstr(name, "_UIHostingView") != NULL) ||
                             (strstr(name, "UIHostingView") != NULL);
            if (looksView) {
                [viewNames addObject:@(name)];
                if ([list[i] isSubclassOfClass:[UIView class]]) {
                    [viewClasses addObject:[NSValue valueWithPointer:(__bridge void *)list[i]]];
                }
            }

            BOOL looksVC = (strcmp(name, "UIHostingController") == 0) ||
                           (strstr(name, "UIHostingController") != NULL);
            if (looksVC &&
                strstr(name, "SecureHosting") == NULL &&
                strstr(name, "DocumentHosting") == NULL) {
                [vcNames addObject:@(name)];
                if ([list[i] isSubclassOfClass:[UIViewController class]]) {
                    [vcClasses addObject:[NSValue valueWithPointer:(__bridge void *)list[i]]];
                }
            }
        }
        free(list);
    }

    NSInteger viewHooks = 0;
    for (NSValue *v in viewClasses) {
        Class cls = (Class)v.pointerValue;
        if (SPSwizzle(cls, @selector(layoutSubviews),
                      (IMP)SPHookedLayoutSubviews,
                      (IMP *)&gSPOrigLayoutSubviews)) {
            viewHooks++;
            if (!gSPHookedViewClassName) {
                gSPHookedViewClassName = @(class_getName(cls));
            }
        }
    }
    if (viewHooks > 0) gSPHookedHostingView = YES;

    // Pick shortest UIHostingController-like name.
    Class bestVC = Nil;
    NSUInteger bestLen = NSUIntegerMax;
    for (NSValue *v in vcClasses) {
        Class cls = (Class)v.pointerValue;
        const char *cn = class_getName(cls);
        NSUInteger len = cn ? strlen(cn) : NSUIntegerMax;
        if (len < bestLen) {
            bestVC = cls;
            bestLen = len;
        }
    }
    if (bestVC && SPSwizzle(bestVC, @selector(viewDidLayoutSubviews),
                            (IMP)SPHookedViewDidLayout,
                            (IMP *)&gSPOrigViewDidLayout)) {
        gSPHookedHostingController = YES;
        gSPHookedControllerClassName = @(class_getName(bestVC));
    }

    BOOL hooked = gSPHookedHostingView || gSPHookedHostingController;
    if (hooked) {
        NSString *msg = [NSString stringWithFormat:@"hooks installed (views=%ld)", (long)viewHooks];
        SPWriteHeartbeat(msg, YES, viewNames, vcNames);
        NSLog(@"[SwiftPeek] %@", msg);
    } else if (viewNames.count || vcNames.count) {
        SPWriteHeartbeat(@"found candidate classes but swizzle failed", NO, viewNames, vcNames);
    } else {
        SPWriteHeartbeat(@"enabled but no hosting classes visible yet", NO, viewNames, vcNames);
    }
}

static void SPOnImageAdded(const struct mach_header *mh, intptr_t slide) {
    (void)slide;
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

__attribute__((constructor)) static void SPConstructor(void) {
    @autoreleasepool {
        BOOL enabled = SPPrefBool(@"enabled", NO);
        SPWriteHeartbeat(enabled ? @"ctor enabled" : @"ctor disabled (kill switch)",
                         NO, @[], @[]);
        if (!enabled) {
            NSLog(@"[SwiftPeek] disabled — idle");
            return;
        }

        NSLog(@"[SwiftPeek] loaded in %@ jbroot='%@'",
              NSProcessInfo.processInfo.processName ?: @"?",
              SPJailbreakRootPrefix() ?: @"");

        SPTryInstallHooks();
        _dyld_register_func_for_add_image(SPOnImageAdded);

        NSArray *delays = @[ @0.5, @1.5, @3.0, @6.0, @12.0 ];
        for (NSNumber *sec in delays) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                         (int64_t)(sec.doubleValue * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                if (!gSPHookedHostingView) SPTryInstallHooks();
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
