#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import "SPPrefs.h"
#import "SPSwiftMeta.h"
#import "SPDumpWriter.h"
#import "SPFieldWalk.h"

// -----------------------------------------------------------------------------
// SwiftPeek — read-only SwiftUI inspector (Phase 1 / milestones 1–2)
// -----------------------------------------------------------------------------

static NSMutableSet *gSPLoggedHosts;
static NSInteger gSPAttachCount = 0;
static const NSInteger kSPMaxAttachLogs = 48;
static BOOL gSPHookedHostingView = NO;
static BOOL gSPHookedHostingController = NO;
static NSString *gSPHookedViewClassName;
static NSString *gSPHookedControllerClassName;
static NSMutableSet *gSPSwizzledKeys;

// Per-class originals — NEVER share one global IMP across classes (UI freezes / crashes).
static NSMutableDictionary<NSString *, NSValue *> *gSPOrigLayoutByClass;    // class name -> IMP
static NSMutableDictionary<NSString *, NSValue *> *gSPOrigDidLayoutByClass;

static void SPStartIfEnabled(void);
static void SPWriteHeartbeat(NSString *message, BOOL hooked,
                             NSArray *viewNames, NSArray *controllerNames);
static void SPHookedLayoutSubviews(UIView *self, SEL _cmd);
static void SPHookedViewDidLayout(UIViewController *self, SEL _cmd);

static void SPEnsureOrigMaps(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gSPOrigLayoutByClass = [NSMutableDictionary dictionary];
        gSPOrigDidLayoutByClass = [NSMutableDictionary dictionary];
        gSPSwizzledKeys = [NSMutableSet set];
    });
}

/// True only when `sel` is implemented on `cls` itself (not inherited).
static BOOL SPClassOwnsInstanceMethod(Class cls, SEL sel) {
    if (!cls || !sel) return NO;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return NO;
    Class superCls = class_getSuperclass(cls);
    if (!superCls) return YES;
    Method sm = class_getInstanceMethod(superCls, sel);
    if (m != sm) return YES;
    // Belt-and-suspenders: some runtimes alias Method pointers oddly.
    unsigned int n = 0;
    Method *list = class_copyMethodList(cls, &n);
    if (!list) return NO;
    BOOL owns = NO;
    for (unsigned int i = 0; i < n; i++) {
        if (method_getName(list[i]) == sel) { owns = YES; break; }
    }
    free(list);
    return owns;
}

/// Walk to the class in `cls`'s hierarchy that actually implements `sel`.
static Class SPClassProvidingInstanceMethod(Class cls, SEL sel) {
    for (Class c = cls; c; c = class_getSuperclass(c)) {
        if (SPClassOwnsInstanceMethod(c, sel)) return c;
    }
    return Nil;
}

static IMP SPLookupOrigIMP(NSDictionary<NSString *, NSValue *> *map, Class start) {
    if (!map || !start) return NULL;
    for (Class cls = start; cls; cls = class_getSuperclass(cls)) {
        const char *name = class_getName(cls);
        if (!name) continue;
        NSValue *boxed = map[@(name)];
        if (boxed) return (IMP)boxed.pointerValue;
    }
    return NULL;
}

static void SPCallOrigLayoutSubviews(UIView *self, SEL _cmd) {
    IMP imp = SPLookupOrigIMP(gSPOrigLayoutByClass, object_getClass(self));
    if (!imp) {
        // Fail-open without super (super can re-enter our hook on subclasses).
        imp = class_getMethodImplementation([UIView class], _cmd);
    }
    if (imp && imp != (IMP)SPHookedLayoutSubviews) {
        ((void (*)(id, SEL))imp)(self, _cmd);
    }
}

static void SPCallOrigViewDidLayout(UIViewController *self, SEL _cmd) {
    IMP imp = SPLookupOrigIMP(gSPOrigDidLayoutByClass, object_getClass(self));
    if (!imp) {
        imp = class_getMethodImplementation([UIViewController class], _cmd);
    }
    if (imp && imp != (IMP)SPHookedViewDidLayout) {
        ((void (*)(id, SEL))imp)(self, _cmd);
    }
}

static void SPPrefsChangedCallback(CFNotificationCenterRef center, void *observer,
                                   CFStringRef name, const void *object,
                                   CFDictionaryRef userInfo) {
    (void)center; (void)observer; (void)name; (void)object; (void)userInfo;
    SPPrefsInvalidate();
    // Stay off the main queue — Music's UI thread is sacred.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        @try {
            if (SPPrefBool(@"enabled", NO)) {
                dispatch_async(dispatch_get_main_queue(), ^{ SPStartIfEnabled(); });
            } else {
                SPWriteHeartbeat(@"disabled via prefs", NO, @[], @[]);
            }
        } @catch (__unused id e) {}
    });
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

static BOOL SPIsBoringTypeName(NSString *name) {
    if (name.length == 0) return YES;
    static NSSet *boring;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        boring = [NSSet setWithArray:@[
            @"UIView", @"UIViewController", @"UIWindow", @"UIWindowController",
            @"UILayoutContainerView", @"UITransitionView", @"UIDropShadowView",
            @"UINavigationController", @"UITabBarController", @"UIApplicationRotationFollowingController",
            @"<unknown>",
        ]];
    });
    if ([boring containsObject:name]) return YES;
    // Still boring if it's a plain UIKit class with no SwiftUI / app module signal.
    if ([name hasPrefix:@"UI"] && [name rangeOfString:@"Hosting"].location == NSNotFound) {
        return YES;
    }
    return NO;
}

static BOOL SPClassNameLooksLikeHostingView(const char *name) {
    if (!name) return NO;
    if (strcmp(name, "_UIHostingView") == 0) return YES;
    if (strstr(name, "_UIHostingView") != NULL) return YES;
    if (strstr(name, "UIHostingView") != NULL) return YES;
    return NO;
}

static BOOL SPClassNameLooksLikeHostingController(const char *name) {
    if (!name) return NO;
    // Narrow: real SwiftUI hosting only. Bare "*HostingController*" matched Music
    // helpers that inherit viewDidLayoutSubviews from UIViewController — 0.2.4
    // then walked up and swizzled UIViewController itself (Music crash).
    if (strcmp(name, "UIHostingController") == 0) return YES;
    if (strstr(name, "UIHostingController") != NULL) return YES;
    return NO;
}

static BOOL SPIsForbiddenHookTarget(Class cls) {
    if (!cls) return YES;
    if (cls == [UIView class] || cls == [UIViewController class]) return YES;
    if (cls == [UIResponder class] || cls == [NSObject class]) return YES;
    const char *name = class_getName(cls);
    if (!name) return YES;
    if (strcmp(name, "UIView") == 0 || strcmp(name, "UIViewController") == 0) return YES;
    if (strcmp(name, "UIResponder") == 0 || strcmp(name, "NSObject") == 0) return YES;
    return NO;
}

static NSInteger SPHostingControllerRank(const char *name) {
    if (!name) return 0;
    if (strcmp(name, "UIHostingController") == 0) return 100;
    if (strstr(name, "SwiftUI") && strstr(name, "UIHostingController")) return 90;
    if (strstr(name, "UIHostingController") != NULL) return 80;
    if (strstr(name, "HostingController") != NULL) return 40;
    return 10;
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

static UIView *SPFindHostingViewBFS(UIView *root, NSInteger maxNodes) {
    if (!root) return nil;
    NSMutableArray *q = [NSMutableArray arrayWithObject:root];
    NSInteger seen = 0;
    while (q.count && seen < maxNodes) {
        UIView *v = q.firstObject;
        [q removeObjectAtIndex:0];
        seen++;
        const char *cn = object_getClassName(v);
        if (SPClassNameLooksLikeHostingView(cn)) return v;
        for (UIView *sub in v.subviews) {
            [q addObject:sub];
        }
    }
    return nil;
}

/// Visible UIKit strings under a view — pixel correspondence for milestone 2.
static NSArray<NSString *> *SPScreenStrings(UIView *root) {
    if (!root) return @[];
    NSMutableArray *out = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    NSMutableArray *q = [NSMutableArray arrayWithObject:root];
    NSInteger budget = 80;
    while (q.count && budget-- > 0) {
        UIView *v = q.firstObject;
        [q removeObjectAtIndex:0];
        if ([v isKindOfClass:[UILabel class]]) {
            NSString *t = [[(UILabel *)v text] ?: @"" stringByTrimmingCharactersInSet:
                           [NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (t.length >= 2 && t.length <= 80 && ![seen containsObject:t]) {
                [seen addObject:t];
                [out addObject:t];
            }
        }
        if ([v isKindOfClass:[UIButton class]]) {
            NSString *t = [[(UIButton *)v titleForState:UIControlStateNormal] ?: @""
                           stringByTrimmingCharactersInSet:
                           [NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (t.length >= 2 && t.length <= 80 && ![seen containsObject:t]) {
                [seen addObject:t];
                [out addObject:t];
            }
        }
        NSString *acc = v.accessibilityLabel;
        if (acc.length >= 2 && acc.length <= 80 && ![seen containsObject:acc]) {
            [seen addObject:acc];
            [out addObject:acc];
        }
        for (UIView *sub in v.subviews) [q addObject:sub];
        if (out.count >= 24) break;
    }
    return out;
}

static void SPLogAttachObject(id object, NSString *role) {
    if (!object) return;

    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gSPLoggedHosts = [NSMutableSet set];
    });

    NSValue *key = [NSValue valueWithNonretainedObject:object];
    if ([gSPLoggedHosts containsObject:key]) return;
    if (gSPAttachCount >= kSPMaxAttachLogs) return;

    NSString *objcName = @(object_getClassName(object) ?: "?");
    NSString *typeName = SPSwiftTypeNameFromObject(object) ?: objcName;

    // Milestone 1 proof needs a real SwiftUI / app type — skip plain UIKit noise.
    if (SPIsBoringTypeName(typeName) && SPIsBoringTypeName(objcName)) {
        return;
    }

    [gSPLoggedHosts addObject:key];
    gSPAttachCount++;

    uintptr_t addr = (uintptr_t)(__bridge void *)object;
    if (SPPrefBool(@"logAttach", YES)) {
        NSLog(@"[SwiftPeek] attach process=%@ role=%@ type=%@ objc=%@ addr=0x%lx",
              NSProcessInfo.processInfo.processName ?: @"?",
              role, typeName, objcName, (unsigned long)addr);
    }

    // Heavy field / mirror work off the layout path.
    id obj = object;
    NSString *roleCopy = [role copy] ?: @"";
    NSString *objcCopy = objcName;
    NSString *typeCopy = typeName;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSMutableDictionary *node = [@{
            @"address": [NSString stringWithFormat:@"0x%lx", (unsigned long)addr],
            @"objc_class": objcCopy,
            @"role": roleCopy,
            @"type": typeCopy,
        } mutableCopy];

        NSInteger milestone = 1;
        // Screen strings are relatively safe. Metadata field walks are opt-in
        // via dumpFieldMeta — walking Music UIViewControllers SIGSEGV'd on 0.3.0.
        if (SPPrefBool(@"dumpFields", NO)) {
            @try {
                UIView *view = nil;
                if ([obj isKindOfClass:[UIView class]]) {
                    view = (UIView *)obj;
                } else if ([obj isKindOfClass:[UIViewController class]]) {
                    UIViewController *vc = (UIViewController *)obj;
                    if (vc.isViewLoaded) view = vc.view;
                }
                if (view) {
                    NSArray *screen = SPScreenStrings(view);
                    if (screen.count) {
                        node[@"screen_strings"] = screen;
                        milestone = 2;
                    }
                }
            } @catch (__unused id e) {}
        }
        if (SPPrefBool(@"dumpFieldMeta", NO)) {
            @try {
                // Prefer hosting views; skip plain UIViewControllers (crashy on Music).
                BOOL allow = [obj isKindOfClass:[UIView class]];
                if (!allow && [obj isKindOfClass:[UIViewController class]]) {
                    const char *cn = object_getClassName(obj);
                    allow = SPClassNameLooksLikeHostingController(cn);
                }
                if (allow) {
                    NSArray *fields = SPWalkFields(obj, 1, 16);
                    if (fields.count) {
                        node[@"fields"] = fields;
                        milestone = 2;
                    }
                }
            } @catch (__unused id e) {}
        }

        NSDictionary *payload = @{
            @"milestone": @(milestone),
            @"nodes": @[node],
        };
        NSString *path = SPWriteJSONDump(payload);
        SPWriteHeartbeat(path ? @"attach dump written" : @"attach seen but dump write failed",
                         YES, @[], @[]);
        if (path) NSLog(@"[SwiftPeek] dump written %@ milestone=%ld", path, (long)milestone);
    });
}

static void SPHookedLayoutSubviews(UIView *self, SEL _cmd) {
    SPCallOrigLayoutSubviews(self, _cmd);
    // Never do attach work synchronously on the layout path.
    UIView *view = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        @try { SPLogAttachObject(view, @"hosting_view"); } @catch (__unused id e) {}
    });
}

static void SPHookedViewDidLayout(UIViewController *self, SEL _cmd) {
    SPCallOrigViewDidLayout(self, _cmd);
    UIViewController *vc = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            SPLogAttachObject(vc, @"hosting_controller");
            UIView *hosting = SPFindHostingViewBFS(vc.view, 64);
            if (hosting) SPLogAttachObject(hosting, @"hosting_view");
        } @catch (__unused id e) {}
    });
}

/// Swizzle only methods owned by `cls`. Store original IMP in per-class map.
static BOOL SPSwizzleOwned(Class cls, SEL sel, IMP replacement,
                           NSMutableDictionary<NSString *, NSValue *> *origMap) {
    if (!cls || !sel || !replacement || !origMap) return NO;
    SPEnsureOrigMaps();

    const char *cname = class_getName(cls);
    if (!cname) return NO;
    NSString *classKey = @(cname);
    NSString *key = [NSString stringWithFormat:@"%@|%s", classKey, sel_getName(sel)];
    if ([gSPSwizzledKeys containsObject:key]) return YES;

    // Critical: do not touch inherited Method slots (would rewrite the superclass).
    if (!SPClassOwnsInstanceMethod(cls, sel)) return NO;

    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return NO;

    IMP current = method_getImplementation(m);
    if (current == replacement) {
        [gSPSwizzledKeys addObject:key];
        return YES;
    }

    IMP prev = method_setImplementation(m, replacement);
    if (!prev) return NO;
    origMap[classKey] = [NSValue valueWithPointer:(const void *)prev];
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

            if (SPClassNameLooksLikeHostingView(name)) {
                [viewNames addObject:@(name)];
                if ([list[i] isSubclassOfClass:[UIView class]]) {
                    [viewClasses addObject:[NSValue valueWithPointer:(__bridge void *)list[i]]];
                }
            }
            if (SPClassNameLooksLikeHostingController(name)) {
                [vcNames addObject:@(name)];
                if ([list[i] isSubclassOfClass:[UIViewController class]]) {
                    [vcClasses addObject:[NSValue valueWithPointer:(__bridge void *)list[i]]];
                }
            }
        }
        free(list);
    }

    SPEnsureOrigMaps();

    // Only swizzle an owner that (1) owns the method, (2) still looks like a
    // hosting type, (3) is never a UIKit base class. Walking to UIViewController
    // in 0.2.4 crashed Music on first layout.
    NSMutableArray *hookedViewOwners = [NSMutableArray array];
    NSMutableSet *viewTargets = [NSMutableSet set];
    NSInteger viewHooks = 0;
    for (NSValue *v in viewClasses) {
        Class cand = (Class)v.pointerValue;
        Class owner = SPClassProvidingInstanceMethod(cand, @selector(layoutSubviews));
        if (!owner || SPIsForbiddenHookTarget(owner)) continue;
        const char *oname = class_getName(owner);
        if (!SPClassNameLooksLikeHostingView(oname)) continue;
        NSString *name = @(oname);
        if ([viewTargets containsObject:name]) continue;
        [viewTargets addObject:name];
        if (SPSwizzleOwned(owner, @selector(layoutSubviews),
                           (IMP)SPHookedLayoutSubviews,
                           gSPOrigLayoutByClass)) {
            viewHooks++;
            [hookedViewOwners addObject:name];
            if (!gSPHookedViewClassName) gSPHookedViewClassName = name;
        }
    }
    if (viewHooks > 0) gSPHookedHostingView = YES;

    NSArray *sorted = [vcClasses sortedArrayUsingComparator:^NSComparisonResult(NSValue *a, NSValue *b) {
        const char *an = class_getName((Class)a.pointerValue);
        const char *bn = class_getName((Class)b.pointerValue);
        NSInteger ar = SPHostingControllerRank(an);
        NSInteger br = SPHostingControllerRank(bn);
        if (ar != br) return ar > br ? NSOrderedAscending : NSOrderedDescending;
        size_t al = an ? strlen(an) : 9999;
        size_t bl = bn ? strlen(bn) : 9999;
        if (al == bl) return NSOrderedSame;
        return al < bl ? NSOrderedAscending : NSOrderedDescending;
    }];
    NSMutableArray *hookedVCOwners = [NSMutableArray array];
    NSMutableSet *vcTargets = [NSMutableSet set];
    NSInteger vcHooks = 0;
    for (NSValue *v in sorted) {
        if (vcHooks >= 4) break;
        Class cand = (Class)v.pointerValue;
        Class owner = SPClassProvidingInstanceMethod(cand, @selector(viewDidLayoutSubviews));
        if (!owner || SPIsForbiddenHookTarget(owner)) continue;
        const char *oname = class_getName(owner);
        if (!SPClassNameLooksLikeHostingController(oname)) continue;
        NSString *name = @(oname);
        if ([vcTargets containsObject:name]) continue;
        [vcTargets addObject:name];
        if (SPSwizzleOwned(owner, @selector(viewDidLayoutSubviews),
                           (IMP)SPHookedViewDidLayout,
                           gSPOrigDidLayoutByClass)) {
            vcHooks++;
            [hookedVCOwners addObject:name];
            if (!gSPHookedControllerClassName) gSPHookedControllerClassName = name;
        }
    }
    if (vcHooks > 0) gSPHookedHostingController = YES;

    BOOL hooked = gSPHookedHostingView || gSPHookedHostingController;
    NSString *msg = nil;
    if (hooked) {
        msg = [NSString stringWithFormat:
               @"hooks installed (views=%ld controllers=%ld) viewOwners=%@ vcOwners=%@",
               (long)viewHooks, (long)vcHooks, hookedViewOwners, hookedVCOwners];
    } else if (viewNames.count || vcNames.count) {
        msg = [NSString stringWithFormat:
               @"candidates but no safe owners (views=%lu controllers=%lu)",
               (unsigned long)viewNames.count, (unsigned long)vcNames.count];
    } else {
        msg = @"enabled but no hosting classes visible yet";
    }
    SPWriteHeartbeat(msg, hooked, viewNames, vcNames);
    NSLog(@"[SwiftPeek] %@", msg);

    static NSInteger sSPHookProbeCount = 0;
    if (sSPHookProbeCount < 3) {
        sSPHookProbeCount++;
        SPWriteJSONDump(@{
            @"milestone": hooked ? @1 : @0,
            @"probe": @YES,
            @"message": msg ?: @"",
            @"hooked": @(hooked),
            @"hooked_view_owners": hookedViewOwners,
            @"hooked_controller_owners": hookedVCOwners,
            @"nodes": @[],
        });
    }
}

static void SPOnImageAdded(const struct mach_header *mh, intptr_t slide) {
    (void)slide;
    if (!SPPrefBool(@"installHooks", NO)) return;
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
        if (SPPrefBool(@"installHooks", NO)) SPTryInstallHooks();
    });
}

static BOOL SPIsAllowedProcess(void) {
    NSString *name = NSProcessInfo.processInfo.processName ?: @"";
    NSString *bundle = NSBundle.mainBundle.bundleIdentifier ?: @"";
    // Music only — never touch SpringBoard (Swift-linked dylib + SB = Safe Mode).
    if ([name isEqualToString:@"Music"]) return YES;
    if ([bundle isEqualToString:@"com.apple.Music"]) return YES;
    return NO;
}

static BOOL gSPDyldWatchInstalled = NO;

/// Lightweight, hook-free attach: walk already-loaded VC tree only.
/// Never force `vc.view` (that blanked Music Library content) and never
/// call objc_copyClassList here (that froze the UI on main).
/// Writes one coalesced dump; optional M2 field/screen enrichment off-main.
static void SPScanWindowsForHosts(void) {
    if (!SPPrefBool(@"enabled", NO)) return;
    @try {
        NSMutableArray *captured = [NSMutableArray array]; // @{obj, role, ...}
        NSArray *windows = [UIApplication sharedApplication].windows;
        for (UIWindow *w in windows) {
            UIViewController *root = w.rootViewController;
            NSMutableArray *stack = [NSMutableArray array];
            if (root) [stack addObject:root];
            NSInteger budget = 24;
            while (stack.count && budget-- > 0) {
                UIViewController *vc = stack.lastObject;
                [stack removeLastObject];
                NSString *objcName = @(object_getClassName(vc) ?: "?");
                NSString *typeName = SPSwiftTypeNameFromObject(vc) ?: objcName;
                if (!SPIsBoringTypeName(typeName) || !SPIsBoringTypeName(objcName)) {
                    NSMutableDictionary *entry = [@{
                        @"object": vc,
                        @"role": @"scan_controller",
                        @"objc_class": objcName,
                        @"type": typeName,
                        @"address": [NSString stringWithFormat:@"0x%lx",
                                     (unsigned long)(uintptr_t)(__bridge void *)vc],
                        @"view_loaded": @(vc.isViewLoaded),
                    } mutableCopy];
                    // Screen strings only on main, only if view already loaded.
                    if (SPPrefBool(@"dumpFields", NO) && vc.isViewLoaded) {
                        @try {
                            NSArray *screen = SPScreenStrings(vc.view);
                            if (screen.count) entry[@"screen_strings"] = screen;
                        } @catch (__unused id e) {}
                    }
                    [captured addObject:entry];
                    if (SPPrefBool(@"logAttach", YES)) {
                        NSLog(@"[SwiftPeek] scan type=%@ addr=%@", typeName,
                              entry[@"address"]);
                    }
                }
                if (vc.isViewLoaded) {
                    UIView *host = SPFindHostingViewBFS(vc.view, 24);
                    if (host) {
                        NSString *hObjc = @(object_getClassName(host) ?: "?");
                        NSString *hType = SPSwiftTypeNameFromObject(host) ?: hObjc;
                        NSMutableDictionary *entry = [@{
                            @"object": host,
                            @"role": @"scan_view",
                            @"objc_class": hObjc,
                            @"type": hType,
                            @"address": [NSString stringWithFormat:@"0x%lx",
                                         (unsigned long)(uintptr_t)(__bridge void *)host],
                            @"view_loaded": @YES,
                        } mutableCopy];
                        if (SPPrefBool(@"dumpFields", NO)) {
                            @try {
                                NSArray *screen = SPScreenStrings(host);
                                if (screen.count) entry[@"screen_strings"] = screen;
                            } @catch (__unused id e) {}
                        }
                        [captured addObject:entry];
                    }
                }
                for (UIViewController *child in vc.childViewControllers) {
                    [stack addObject:child];
                }
                if (vc.presentedViewController) {
                    [stack addObject:vc.presentedViewController];
                }
            }
        }

        if (captured.count == 0) {
            SPWriteHeartbeat(@"window scan found no interesting controllers", NO, @[], @[]);
            return;
        }

        BOOL enrichScreen = SPPrefBool(@"dumpFields", NO);
        BOOL enrichMeta = SPPrefBool(@"dumpFieldMeta", NO);
        NSArray *snapshot = [captured copy];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            NSMutableArray *nodes = [NSMutableArray array];
            NSInteger milestone = 1;
            NSInteger metaBudget = 4; // very small — Music VC meta walks crash
            for (NSDictionary *item in snapshot) {
                NSMutableDictionary *node = [@{
                    @"address": item[@"address"] ?: @"",
                    @"objc_class": item[@"objc_class"] ?: @"",
                    @"role": item[@"role"] ?: @"",
                    @"type": item[@"type"] ?: @"",
                } mutableCopy];

                if (item[@"screen_strings"]) {
                    node[@"screen_strings"] = item[@"screen_strings"];
                    milestone = 2;
                }

                if (enrichMeta && metaBudget > 0) {
                    NSString *role = item[@"role"] ?: @"";
                    // Only metadata-walk hosting views for now — not Music VCs.
                    if ([role isEqualToString:@"scan_view"]) {
                        metaBudget--;
                        id obj = item[@"object"];
                        @try {
                            NSArray *fields = SPWalkFields(obj, 1, 16);
                            if (fields.count) {
                                node[@"fields"] = fields;
                                milestone = 2;
                            }
                        } @catch (__unused id e) {}
                    }
                }
                [nodes addObject:node];
            }

            NSString *msg = [NSString stringWithFormat:
                @"window scan nodes=%lu milestone=%ld screen=%d meta=%d",
                (unsigned long)nodes.count, (long)milestone,
                enrichScreen ? 1 : 0, enrichMeta ? 1 : 0];
            NSString *path = SPWriteJSONDump(@{
                @"milestone": @(milestone),
                @"scan": @YES,
                @"message": msg,
                @"nodes": nodes,
            });
            SPWriteHeartbeat(path ? msg : @"window scan dump write failed", NO, @[], @[]);
            if (path) NSLog(@"[SwiftPeek] %@", msg);
        });
    } @catch (__unused id e) {
        SPWriteHeartbeat(@"window scan failed closed", NO, @[], @[]);
    }
}

static void SPStartIfEnabled(void) {
    if (!SPPrefBool(@"enabled", NO)) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            SPWriteHeartbeat(@"ctor disabled (kill switch)", NO, @[], @[]);
        });
        NSLog(@"[SwiftPeek] disabled — idle");
        return;
    }

    NSLog(@"[SwiftPeek] loaded in %@ jbroot='%@'",
          NSProcessInfo.processInfo.processName ?: @"?",
          SPJailbreakRootPrefix() ?: @"");

    BOOL scanOn = SPPrefBool(@"scanWindows", NO);
    BOOL hooksOn = SPPrefBool(@"installHooks", NO);
    BOOL fieldsOn = SPPrefBool(@"dumpFields", NO);
    BOOL metaOn = SPPrefBool(@"dumpFieldMeta", NO);

    static dispatch_once_t launchOnce;
    dispatch_once(&launchOnce, ^{
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            NSString *msg = [NSString stringWithFormat:
                @"Music launch probe (0.3.1) scanWindows=%d installHooks=%d dumpFields=%d dumpFieldMeta=%d",
                scanOn ? 1 : 0, hooksOn ? 1 : 0, fieldsOn ? 1 : 0, metaOn ? 1 : 0];
            SPWriteHeartbeat(msg, NO, @[], @[]);
            SPWriteJSONDump(@{
                @"milestone": @0,
                @"probe": @YES,
                @"launch": @YES,
                @"message": msg,
                @"prefs": @{
                    @"enabled": @YES,
                    @"scanWindows": @(scanOn),
                    @"installHooks": @(hooksOn),
                    @"dumpFields": @(fieldsOn),
                    @"dumpFieldMeta": @(metaOn),
                },
                @"nodes": @[],
            });
        });
    });

    // Window scan is opt-in — schedule every Music launch when enabled.
    if (scanOn) {
        static dispatch_once_t scanScheduleOnce;
        dispatch_once(&scanScheduleOnce, ^{
            NSLog(@"[SwiftPeek] scanWindows on — scheduling scans");
            for (NSNumber *sec in @[ @5.0, @12.0 ]) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                             (int64_t)(sec.doubleValue * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    if (!SPPrefBool(@"enabled", NO) || !SPPrefBool(@"scanWindows", NO)) return;
                    SPScanWindowsForHosts();
                });
            }
        });
    }

    if (hooksOn) {
        static dispatch_once_t hooksOnce;
        dispatch_once(&hooksOnce, ^{
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(20.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                if (!SPPrefBool(@"installHooks", NO)) return;
                SPTryInstallHooks();
            });
            if (!gSPDyldWatchInstalled) {
                gSPDyldWatchInstalled = YES;
                _dyld_register_func_for_add_image(SPOnImageAdded);
            }
        });
    }
}

__attribute__((constructor)) static void SPConstructor(void) {
    @autoreleasepool {
        if (!SPIsAllowedProcess()) {
            return;
        }

        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL,
                                        SPPrefsChangedCallback,
                                        CFSTR("com.kolby.swiftpeek/prefschanged"),
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);

        // Never touch main in the constructor. Schedule from a utility queue.
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            @try {
                if (!SPPrefBool(@"enabled", NO)) {
                    SPWriteHeartbeat(@"ctor disabled (kill switch)", NO, @[], @[]);
                    return;
                }
                // Bounce to main only to kick opt-in timers (UIApplication-safe).
                dispatch_async(dispatch_get_main_queue(), ^{
                    @try { SPStartIfEnabled(); } @catch (__unused id e) {}
                });
            } @catch (__unused id e) {
                NSLog(@"[SwiftPeek] ctor failed closed");
            }
        });
    }
}
