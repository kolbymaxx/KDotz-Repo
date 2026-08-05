#import "CC27.h"

NSString * const CC27PrefDomain = @"com.kolby.cc27";
NSString * const CC27ReloadPrefsNotification = @"com.kolby.cc27/ReloadPrefs";
NSString * const CC27LayoutDidChangeNotification = @"com.kolby.cc27/LayoutDidChange";

static NSString *CC27JailbreakRootPrefix(void) {
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
        if (dladdr((const void *)CC27JailbreakRootPrefix, &info) && info.dli_fname) {
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

static NSArray<NSString *> *CC27PrefsCandidatePaths(void) {
    NSString *rel = @"/var/mobile/Library/Preferences/com.kolby.cc27.plist";
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    NSString *jb = CC27JailbreakRootPrefix();
    if (jb.length > 0) {
        [paths addObject:[jb stringByAppendingString:rel]];
    }
    [paths addObject:[@"/var/jb" stringByAppendingString:rel]];
    [paths addObject:rel];
    return paths;
}

static NSDictionary *CC27ReadPrefsDictionary(void) {
    for (NSString *path in CC27PrefsCandidatePaths()) {
        NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:path];
        if ([dict isKindOfClass:NSDictionary.class] && dict.count > 0) {
            return dict;
        }
    }
    return @{};
}

@implementation CC27Prefs {
    NSDictionary *_plist;
}

+ (instancetype)shared {
    static CC27Prefs *shared;
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
    _plist = CC27ReadPrefsDictionary() ?: @{};
}

- (BOOL)_bool:(NSString *)key default:(BOOL)fallback {
    id v = _plist[key];
    if (!v) {
        CFPropertyListRef cf = CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)CC27PrefDomain);
        if (cf) {
            v = CFBridgingRelease(cf);
        }
    }
    if ([v isKindOfClass:NSNumber.class]) return [v boolValue];
    return fallback;
}

- (BOOL)enabled { return [self _bool:@"enabled" default:YES]; }
- (BOOL)glassChrome { return [self _bool:@"glassChrome" default:YES]; }
- (BOOL)editModeEnabled { return [self _bool:@"editModeEnabled" default:YES]; }
- (BOOL)allowResize { return [self _bool:@"allowResize" default:NO]; }
- (BOOL)showTopButtons { return [self _bool:@"showTopButtons" default:YES]; }
- (BOOL)hapticFeedback { return [self _bool:@"hapticFeedback" default:YES]; }

@end
