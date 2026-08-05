#import "Music27.h"
#import <dlfcn.h>

NSString *const M27PrefDomain = @"com.music27.tweak";
NSString *const M27ThemeDidChangeNotification = @"M27ThemeDidChangeNotification";
NSString *const M27PinsDidChangeNotification = @"M27PinsDidChangeNotification";
const NSInteger M27MaxPins = 12;

// Resolve jailbreak root the same way Siri27 does — RootHide jbroot, then
// /var/jb, then rootful. PreferenceLoader on RootHide writes under jbroot;
// reading only NSUserDefaults/CFPreferences from Music misses those values
// (toggles look ON in Settings, dock stays OFF in Music).
static NSString *M27JailbreakRootPrefix(void) {
    static NSString *prefix;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        prefix = @"";
        const char *(*jbrootFn)(const char *) = (const char *(*)(const char *))dlsym(RTLD_DEFAULT, "jbroot");
        if (jbrootFn) {
            const char *p = jbrootFn("/");
            if (p && p[0] != '\0' && strcmp(p, "/") != 0) {
                prefix = [[NSString stringWithUTF8String:p] stringByStandardizingPath];
                return;
            }
        }
        Dl_info info = {0};
        if (dladdr((const void *)M27JailbreakRootPrefix, &info) && info.dli_fname) {
            NSString *dylibPath = [NSString stringWithUTF8String:info.dli_fname];
            for (NSString *marker in @[ @"/Library/MobileSubstrate/DynamicLibraries/",
                                       @"/usr/lib/TweakInject/" ]) {
                NSRange r = [dylibPath rangeOfString:marker];
                if (r.location != NSNotFound && r.location > 0) {
                    prefix = [dylibPath substringToIndex:r.location];
                    return;
                }
            }
        }
    });
    return prefix;
}

static NSArray<NSString *> *M27PrefsCandidatePaths(void) {
    NSString *rel = @"/var/mobile/Library/Preferences/com.music27.tweak.plist";
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    NSString *jb = M27JailbreakRootPrefix();
    if (jb.length > 0) {
        [paths addObject:[jb stringByAppendingString:rel]];
    }
    [paths addObject:[@"/var/jb" stringByAppendingString:rel]];
    [paths addObject:rel];
    return paths;
}

static NSDictionary *M27ReadPrefsDictionary(void) {
    for (NSString *path in M27PrefsCandidatePaths()) {
        NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:path];
        if ([dict isKindOfClass:NSDictionary.class] && dict.count > 0) {
            return dict;
        }
    }
    return @{};
}

static void M27WritePrefsDictionary(NSDictionary *dict) {
    if (![dict isKindOfClass:NSDictionary.class]) return;
    NSArray<NSString *> *paths = M27PrefsCandidatePaths();
    // Prefer jbroot / first candidate that already exists; else first path.
    NSString *target = paths.firstObject;
    for (NSString *path in paths) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            target = path;
            break;
        }
    }
    if (!target) return;
    NSString *dir = [target stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    [dict writeToFile:target atomically:YES];
}

@implementation M27Prefs {
    NSDictionary *_plist;
}

+ (instancetype)shared {
    static M27Prefs *shared;
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

- (BOOL)boolForKey:(NSString *)key defaultValue:(BOOL)fallback {
    id value = _plist[key];
    if (value == nil) {
        // CFPreferences fallback (rootless / rootful).
        CFPropertyListRef cfVal = CFPreferencesCopyAppValue(
            (__bridge CFStringRef)key, (__bridge CFStringRef)M27PrefDomain);
        if (cfVal != NULL) {
            BOOL result = fallback;
            if (CFGetTypeID(cfVal) == CFBooleanGetTypeID()) {
                result = CFBooleanGetValue((CFBooleanRef)cfVal);
            } else if (CFGetTypeID(cfVal) == CFNumberGetTypeID()) {
                int n = 0;
                CFNumberGetValue((CFNumberRef)cfVal, kCFNumberIntType, &n);
                result = n != 0;
            }
            CFRelease(cfVal);
            return result;
        }
        return fallback;
    }
    return [value boolValue];
}

- (void)reload {
    CFPreferencesAppSynchronize((__bridge CFStringRef)M27PrefDomain);
    _plist = M27ReadPrefsDictionary();

    // One-time: do NOT force the dock off anymore on RootHide — that wrote to
    // the wrong plist and fought Settings. Only seed dockSafeBoot115 marker.
    if (_plist[@"dockSafeBoot115"] == nil && _plist[@"glassTabBar"] == nil) {
        // Fresh install: default dock ON so RootHide users see an effect.
        NSMutableDictionary *seed = [_plist mutableCopy] ?: [NSMutableDictionary dictionary];
        seed[@"dockSafeBoot115"] = @YES;
        seed[@"enabled"] = @YES;
        seed[@"glassTabBar"] = @YES;
        seed[@"colorTheme"] = @YES;
        seed[@"libraryPins"] = @NO;
        M27WritePrefsDictionary(seed);
        _plist = [seed copy];
        CFPreferencesSetAppValue(CFSTR("glassTabBar"), kCFBooleanTrue,
                                 (__bridge CFStringRef)M27PrefDomain);
        CFPreferencesSetAppValue(CFSTR("enabled"), kCFBooleanTrue,
                                 (__bridge CFStringRef)M27PrefDomain);
        CFPreferencesSetAppValue(CFSTR("dockSafeBoot115"), kCFBooleanTrue,
                                 (__bridge CFStringRef)M27PrefDomain);
        CFPreferencesAppSynchronize((__bridge CFStringRef)M27PrefDomain);
    }

    _enabled = [self boolForKey:@"enabled" defaultValue:YES];
    _glassTabBarEnabled = [self boolForKey:@"glassTabBar" defaultValue:YES];
    _colorThemeEnabled = [self boolForKey:@"colorTheme" defaultValue:YES];
    _libraryPinsEnabled = [self boolForKey:@"libraryPins" defaultValue:NO];
}

@end
