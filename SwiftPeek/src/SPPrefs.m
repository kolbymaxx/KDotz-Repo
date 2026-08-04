#import "SPPrefs.h"
#import <dlfcn.h>

static NSString * const kSPPrefsDomain = @"com.kolby.swiftpeek";

static NSDictionary *gSPPrefsCache = nil;
static CFAbsoluteTime gSPPrefsLastLoad = 0;

NSString *SPJailbreakRootPrefix(void) {
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
        if (dladdr((const void *)SPJailbreakRootPrefix, &info) && info.dli_fname) {
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

static NSArray<NSString *> *SPPrefsCandidatePaths(void) {
    NSString *rel = [NSString stringWithFormat:@"/var/mobile/Library/Preferences/%@.plist", kSPPrefsDomain];
    NSMutableArray *paths = [NSMutableArray array];
    NSString *jbPrefix = SPJailbreakRootPrefix();
    if (jbPrefix.length) [paths addObject:[jbPrefix stringByAppendingString:rel]];
    [paths addObject:[@"/var/jb" stringByAppendingString:rel]];
    [paths addObject:rel];
    return paths;
}

NSDictionary *SPPrefs(void) {
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (gSPPrefsCache && (now - gSPPrefsLastLoad) < 0.5) return gSPPrefsCache;

    for (NSString *p in SPPrefsCandidatePaths()) {
        NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:p];
        if (d) {
            gSPPrefsCache = d;
            gSPPrefsLastLoad = now;
            return gSPPrefsCache;
        }
    }
    gSPPrefsCache = @{};
    gSPPrefsLastLoad = now;
    return gSPPrefsCache;
}

BOOL SPPrefBool(NSString *key, BOOL fallback) {
    id v = SPPrefs()[key];
    return v ? [v boolValue] : fallback;
}

void SPPrefsInvalidate(void) {
    gSPPrefsCache = nil;
    gSPPrefsLastLoad = 0;
}
