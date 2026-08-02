#import "Music27.h"

NSString *const M27PrefDomain = @"com.music27.tweak";
NSString *const M27ThemeDidChangeNotification = @"M27ThemeDidChangeNotification";
NSString *const M27PinsDidChangeNotification = @"M27PinsDidChangeNotification";
const NSInteger M27MaxPins = 12;

@implementation M27Prefs {
    NSUserDefaults *_defaults;
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
        _defaults = [[NSUserDefaults alloc] initWithSuiteName:M27PrefDomain];
        [self reload];
    }
    return self;
}

- (BOOL)boolForKey:(NSString *)key defaultValue:(BOOL)fallback {
    // Prefer the suite, then the preference plist path used by PreferenceLoader,
    // then the fallback. This avoids "toggles look on but Music reads off".
    id value = [_defaults objectForKey:key];
    if (value != nil) return [value boolValue];

    CFStringRef domain = (__bridge CFStringRef)M27PrefDomain;
    CFPropertyListRef cfVal = CFPreferencesCopyAppValue((__bridge CFStringRef)key, domain);
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

- (void)reload {
    // NSUserDefaults caches aggressively inside a single process, so pick up
    // external writes from the preference bundle before re-reading.
    [_defaults synchronize];
    CFPreferencesAppSynchronize((__bridge CFStringRef)M27PrefDomain);
    _enabled = [self boolForKey:@"enabled" defaultValue:YES];
    _glassTabBarEnabled = [self boolForKey:@"glassTabBar" defaultValue:YES];
    _colorThemeEnabled = [self boolForKey:@"colorTheme" defaultValue:YES];
    // Pins default OFF — overlay is optional and was contributing to Library confusion.
    _libraryPinsEnabled = [self boolForKey:@"libraryPins" defaultValue:NO];
}

@end
