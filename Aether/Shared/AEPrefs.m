#import "AEPrefs.h"
#import <dlfcn.h>
#import <objc/runtime.h>
#import <UIKit/UIKit.h>

static NSString * const kAEPrefsDomain = @"com.kolby.aether";
static NSDictionary *sAEPrefsCache = nil;
static CFAbsoluteTime sAEPrefsLastLoad = 0;

NSString *AEJailbreakRootPrefix(void) {
    static NSString *prefix = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        prefix = @"";
        const char *(*jbrootFn)(const char *) = (const char *(*)(const char *))dlsym(RTLD_DEFAULT, "jbroot");
        if (jbrootFn) {
            const char *p = jbrootFn("/");
            if (p && strlen(p) > 1) {
                prefix = [[NSString stringWithUTF8String:p] stringByStandardizingPath];
                return;
            }
        }
        Dl_info info = {0};
        if (dladdr((const void *)AEJailbreakRootPrefix, &info) && info.dli_fname) {
            NSString *dylibPath = [NSString stringWithUTF8String:info.dli_fname];
            for (NSString *marker in @[@"/Library/MobileSubstrate/DynamicLibraries/",
                                       @"/usr/lib/TweakInject/"]) {
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

void AEPrefsInvalidate(void) {
    sAEPrefsCache = nil;
    sAEPrefsLastLoad = 0;
}

NSDictionary *AEPrefs(void) {
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (sAEPrefsCache && (now - sAEPrefsLastLoad) < 0.4) return sAEPrefsCache;

    NSString *rel = [NSString stringWithFormat:@"/var/mobile/Library/Preferences/%@.plist", kAEPrefsDomain];
    NSMutableArray *paths = [NSMutableArray array];
    NSString *jbPrefix = AEJailbreakRootPrefix();
    if (jbPrefix.length) [paths addObject:[jbPrefix stringByAppendingString:rel]];
    [paths addObject:[@"/var/jb" stringByAppendingString:rel]];
    [paths addObject:rel];
    for (NSString *p in paths) {
        NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:p];
        if (d) {
            sAEPrefsCache = d;
            sAEPrefsLastLoad = now;
            return sAEPrefsCache;
        }
    }
    sAEPrefsCache = @{};
    sAEPrefsLastLoad = now;
    return sAEPrefsCache;
}

BOOL AEPrefBool(NSString *key, BOOL fallback) {
    id v = AEPrefs()[key];
    return v ? [v boolValue] : fallback;
}

NSInteger AEPrefInt(NSString *key, NSInteger fallback) {
    id v = AEPrefs()[key];
    return v ? [v integerValue] : fallback;
}

CGFloat AEPrefFloat(NSString *key, CGFloat fallback) {
    id v = AEPrefs()[key];
    return v ? [v doubleValue] : fallback;
}

NSString *AEPrefString(NSString *key, NSString *fallback) {
    id v = AEPrefs()[key];
    return [v isKindOfClass:[NSString class]] ? v : fallback;
}

NSString *AECurrentBundleID(void) {
    NSString *bid = [NSBundle mainBundle].bundleIdentifier;
    if (bid.length) return bid;
    NSString *exe = [NSProcessInfo processInfo].processName;
    if ([exe isEqualToString:@"SpringBoard"]) return @"com.apple.springboard";
    return exe ?: @"unknown";
}

NSString *AEDataDirectory(void) {
    static NSString *dir = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *rel = @"/var/mobile/Library/Aether";
        NSString *jb = AEJailbreakRootPrefix();
        NSArray *candidates = jb.length
            ? @[ [jb stringByAppendingString:rel], [@"/var/jb" stringByAppendingString:rel], rel ]
            : @[ [@"/var/jb" stringByAppendingString:rel], rel ];
        for (NSString *c in candidates) {
            NSError *err = nil;
            if ([[NSFileManager defaultManager] createDirectoryAtPath:c
                                          withIntermediateDirectories:YES
                                                           attributes:nil
                                                                error:&err] ||
                [[NSFileManager defaultManager] fileExistsAtPath:c]) {
                dir = c;
                break;
            }
        }
        if (!dir) dir = NSTemporaryDirectory();
    });
    return dir;
}
