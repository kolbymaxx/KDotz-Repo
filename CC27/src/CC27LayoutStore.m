#import "CC27.h"

static NSString *CC27SizeOverridesPath(void) {
    static NSString *path;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *rel = @"/var/mobile/Library/Preferences/com.kolby.cc27.sizes.plist";
        const char *(*jbrootFn)(const char *) = (const char *(*)(const char *))dlsym(RTLD_DEFAULT, "jbroot");
        if (jbrootFn) {
            const char *p = jbrootFn([rel UTF8String]);
            if (p && p[0]) {
                path = [NSString stringWithUTF8String:p];
                return;
            }
        }
        if ([[NSFileManager defaultManager] fileExistsAtPath:[@"/var/jb" stringByAppendingString:rel]]) {
            path = [@"/var/jb" stringByAppendingString:rel];
        } else {
            path = rel;
        }
    });
    return path;
}

@implementation CC27LayoutStore {
    NSMutableDictionary *_sizes; // id -> @{w,h}
}

+ (instancetype)shared {
    static CC27LayoutStore *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shared = [self new];
    });
    return shared;
}

- (instancetype)init {
    if ((self = [super init])) {
        [self reload];
    }
    return self;
}

- (void)reload {
    NSDictionary *disk = [NSDictionary dictionaryWithContentsOfFile:CC27SizeOverridesPath()];
    _sizes = disk.mutableCopy ?: [NSMutableDictionary new];
}

- (void)_saveSizes {
    NSString *path = CC27SizeOverridesPath();
    [[NSFileManager defaultManager] createDirectoryAtPath:path.stringByDeletingLastPathComponent
                              withIntermediateDirectories:YES attributes:nil error:nil];
    [_sizes writeToFile:path atomically:YES];
}

- (CCSModuleSettingsProvider *)_provider {
    Class cls = NSClassFromString(@"CCSModuleSettingsProvider");
    if (!cls) return nil;
    return [cls sharedProvider];
}

- (NSArray<NSString *> *)enabledIdentifiers {
    NSArray *ids = self._provider.orderedUserEnabledModuleIdentifiers;
    return ids ?: @[];
}

- (NSArray<NSString *> *)disabledIdentifiers {
    NSMutableSet *all = [NSMutableSet set];
    for (CC27ModuleInfo *info in CC27ModuleCatalog.shared.allModules) {
        if (info.identifier) [all addObject:info.identifier];
    }
    [all minusSet:[NSSet setWithArray:self.enabledIdentifiers]];
    return all.allObjects;
}

- (BOOL)enableModule:(NSString *)identifier {
    if (identifier.length == 0) return NO;
    CCSModuleSettingsProvider *provider = self._provider;
    if (!provider) return NO;
    NSMutableArray *ordered = self.enabledIdentifiers.mutableCopy ?: [NSMutableArray new];
    if ([ordered containsObject:identifier]) return YES;
    [ordered addObject:identifier];
    [provider setAndSaveOrderedUserEnabledModuleIdentifiers:ordered];
    [self refreshControlCenterLayout];
    [[NSNotificationCenter defaultCenter] postNotificationName:CC27LayoutDidChangeNotification object:nil];
    return YES;
}

- (BOOL)disableModule:(NSString *)identifier {
    if (identifier.length == 0) return NO;
    CCSModuleSettingsProvider *provider = self._provider;
    if (!provider) return NO;
    NSMutableArray *ordered = self.enabledIdentifiers.mutableCopy ?: [NSMutableArray new];
    [ordered removeObject:identifier];
    [provider setAndSaveOrderedUserEnabledModuleIdentifiers:ordered];
    [self refreshControlCenterLayout];
    [[NSNotificationCenter defaultCenter] postNotificationName:CC27LayoutDidChangeNotification object:nil];
    return YES;
}

- (BOOL)moveModule:(NSString *)identifier toIndex:(NSUInteger)index {
    if (identifier.length == 0) return NO;
    CCSModuleSettingsProvider *provider = self._provider;
    if (!provider) return NO;
    NSMutableArray *ordered = self.enabledIdentifiers.mutableCopy ?: [NSMutableArray new];
    NSUInteger from = [ordered indexOfObject:identifier];
    if (from == NSNotFound) return NO;
    [ordered removeObjectAtIndex:from];
    NSUInteger to = MIN(index, ordered.count);
    [ordered insertObject:identifier atIndex:to];
    [provider setAndSaveOrderedUserEnabledModuleIdentifiers:ordered];
    [self refreshControlCenterLayout];
    [[NSNotificationCenter defaultCenter] postNotificationName:CC27LayoutDidChangeNotification object:nil];
    return YES;
}

- (CCUILayoutSize)sizeForModule:(NSString *)identifier fallback:(CCUILayoutSize)fallback {
    NSDictionary *entry = _sizes[identifier];
    if (![entry isKindOfClass:NSDictionary.class]) return fallback;
    NSNumber *w = entry[@"w"];
    NSNumber *h = entry[@"h"];
    if (!w || !h) return fallback;
    CCUILayoutSize size;
    size.width = MAX(1, w.unsignedIntegerValue);
    size.height = MAX(1, h.unsignedIntegerValue);
    return size;
}

- (void)setSize:(CCUILayoutSize)size forModule:(NSString *)identifier {
    if (identifier.length == 0) return;
    _sizes[identifier] = @{ @"w": @(MAX(1, size.width)), @"h": @(MAX(1, size.height)) };
    [self _saveSizes];
    [self refreshControlCenterLayout];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         CFSTR("com.opa334.ccsupport/ReloadSizes"),
                                         NULL, NULL, TRUE);
    [[NSNotificationCenter defaultCenter] postNotificationName:CC27LayoutDidChangeNotification object:nil];
}

- (NSArray<NSValue *> *)_allowedSizesForModule:(NSString *)identifier current:(CCUILayoutSize)current {
    // Connectivity / media tend to break if forced tiny; keep a sensible allow-list.
    NSSet *preferLarge = [NSSet setWithArray:@[
        @"com.apple.control-center.ConnectivityModule",
        @"com.apple.mediaremote.controlcenter.nowplaying",
        @"com.apple.Home.ControlCenter",
    ]];
    NSSet *sliders = [NSSet setWithArray:@[
        @"com.apple.control-center.DisplayModule",
        @"com.apple.control-center.AudioModule",
        @"com.apple.mediaremote.controlcenter.audio",
    ]];

    NSMutableArray *options = [NSMutableArray array];
    void (^add)(NSUInteger, NSUInteger) = ^(NSUInteger w, NSUInteger h) {
        CCUILayoutSize s = { .width = w, .height = h };
        [options addObject:[NSValue valueWithBytes:&s objCType:@encode(CCUILayoutSize)]];
    };

    if ([sliders containsObject:identifier]) {
        add(1, 2); add(1, 4); add(2, 2);
    } else if ([preferLarge containsObject:identifier]) {
        add(2, 2); add(4, 2); add(2, 1); add(1, 1);
    } else {
        add(1, 1); add(2, 1); add(1, 2); add(2, 2);
    }

    // Ensure current size is represented.
    BOOL hasCurrent = NO;
    for (NSValue *v in options) {
        CCUILayoutSize s; [v getValue:&s];
        if (s.width == current.width && s.height == current.height) { hasCurrent = YES; break; }
    }
    if (!hasCurrent && current.width > 0 && current.height > 0) {
        [options insertObject:[NSValue valueWithBytes:&current objCType:@encode(CCUILayoutSize)] atIndex:0];
    }
    return options;
}

- (CCUILayoutSize)cycleSizeForModule:(NSString *)identifier current:(CCUILayoutSize)current {
    NSArray *options = [self _allowedSizesForModule:identifier current:current];
    NSUInteger idx = 0;
    for (NSUInteger i = 0; i < options.count; i++) {
        CCUILayoutSize s; [options[i] getValue:&s];
        if (s.width == current.width && s.height == current.height) { idx = i; break; }
    }
    NSUInteger next = (idx + 1) % options.count;
    CCUILayoutSize result; [options[next] getValue:&result];
    [self setSize:result forModule:identifier];
    return result;
}

- (void)refreshControlCenterLayout {
    Class coll = NSClassFromString(@"CCUIModuleCollectionViewController");
    Class mod = NSClassFromString(@"CCUIModularControlCenterViewController");
    Class overlay = NSClassFromString(@"CCUIModularControlCenterOverlayViewController");

    CCUIModuleCollectionViewController *vc = nil;
    if ([mod respondsToSelector:@selector(_sharedCollectionViewController)]) {
        vc = [mod _sharedCollectionViewController];
    } else if ([overlay respondsToSelector:@selector(_sharedCollectionViewController)]) {
        vc = [overlay _sharedCollectionViewController];
    } else if ([coll respondsToSelector:@selector(_sharedCollectionViewController)]) {
        vc = [coll _sharedCollectionViewController];
    }
    if ([vc respondsToSelector:@selector(_refreshPositionProviders)]) {
        [vc _refreshPositionProviders];
    }

    // Ask module instance manager to poke layout when available.
    Class mgrCls = NSClassFromString(@"CCUIModuleInstanceManager");
    id mgr = [mgrCls respondsToSelector:@selector(sharedInstance)] ? [mgrCls sharedInstance] : nil;
    if (mgr) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        SEL sel = NSSelectorFromString(@"_updateModuleInstances");
        if ([mgr respondsToSelector:sel]) [mgr performSelector:sel];
#pragma clang diagnostic pop
    }
}

@end
