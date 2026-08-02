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
    id value = [_defaults objectForKey:key];
    return value ? [value boolValue] : fallback;
}

- (void)reload {
    // NSUserDefaults caches aggressively inside a single process, so pick up
    // external writes from the preference bundle before re-reading.
    [_defaults synchronize];
    _enabled = [self boolForKey:@"enabled" defaultValue:YES];
    _glassTabBarEnabled = [self boolForKey:@"glassTabBar" defaultValue:YES];
    _colorThemeEnabled = [self boolForKey:@"colorTheme" defaultValue:YES];
    _libraryPinsEnabled = [self boolForKey:@"libraryPins" defaultValue:YES];
}

@end
