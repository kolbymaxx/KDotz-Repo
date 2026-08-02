#import "PrefsBridge.h"
#import "PathShim.h"

#include <substrate.h>
#include <roothide.h>

static NSString *RHCompatJBPrefsPathForDomain(NSString *domain) {
    if (domain.length == 0) return nil;
    if ([domain hasPrefix:@"com.apple."]) return nil;
    if ([domain isEqualToString:@"Apple Global Domain"]) return nil;

    NSString *rel = [NSString stringWithFormat:
        @"/var/mobile/Library/Preferences/%@.plist", domain];
    const char *mapped = jbroot(rel.fileSystemRepresentation);
    if (!mapped || mapped[0] == '\0') return nil;
    return [NSString stringWithUTF8String:mapped];
}

static id RHCompatReadKeyFromJBPlist(NSString *domain, NSString *key) {
    if (!RHCompatEnabled() || RHCompatInBypass()) return nil;
    NSString *path = RHCompatJBPrefsPathForDomain(domain);
    if (!path) return nil;

    RHCompatEnterBypass();
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:path];
    RHCompatLeaveBypass();

    if (![dict isKindOfClass:[NSDictionary class]]) return nil;
    return key ? dict[key] : nil;
}

static CFPropertyListRef (*orig_CFPreferencesCopyAppValue)(CFStringRef key, CFStringRef appID);
static CFPropertyListRef hooked_CFPreferencesCopyAppValue(CFStringRef key, CFStringRef appID) {
    CFPropertyListRef value = orig_CFPreferencesCopyAppValue(key, appID);
    if (value != NULL) return value;
    if (!key || !appID) return value;
    if (RHCompatInBypass() || !RHCompatEnabled()) return value;

    NSString *domain = (__bridge NSString *)appID;
    // Never bridge our own domain through the fallback (avoid re-entrancy).
    if ([domain isEqualToString:@"com.kolby.rhcompat"]) return value;

    NSString *keyStr = (__bridge NSString *)key;
    id fallback = RHCompatReadKeyFromJBPlist(domain, keyStr);
    if (!fallback) return value;
    return CFBridgingRetain(fallback);
}

static void (*orig_CFPreferencesSetAppValue)(CFStringRef key, CFPropertyListRef value, CFStringRef appID);
static void hooked_CFPreferencesSetAppValue(CFStringRef key, CFPropertyListRef value, CFStringRef appID) {
    orig_CFPreferencesSetAppValue(key, value, appID);
    if (!key || !appID || !RHCompatEnabled() || RHCompatInBypass()) return;

    NSString *domain = (__bridge NSString *)appID;
    if ([domain hasPrefix:@"com.apple."]) return;
    if ([domain isEqualToString:@"com.kolby.rhcompat"]) return;

    NSString *path = RHCompatJBPrefsPathForDomain(domain);
    if (!path) return;

    RHCompatEnterBypass();
    NSMutableDictionary *dict = [[NSDictionary dictionaryWithContentsOfFile:path] mutableCopy]
        ?: [NSMutableDictionary dictionary];
    NSString *keyStr = (__bridge NSString *)key;
    if (value) {
        dict[keyStr] = (__bridge id)value;
    } else {
        [dict removeObjectForKey:keyStr];
    }
    [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent]
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    [dict writeToFile:path atomically:YES];
    RHCompatLeaveBypass();
}

void RHCompatInstallPrefsBridge(void) {
    MSHookFunction((void *)CFPreferencesCopyAppValue,
                   (void *)hooked_CFPreferencesCopyAppValue,
                   (void **)&orig_CFPreferencesCopyAppValue);
    MSHookFunction((void *)CFPreferencesSetAppValue,
                   (void *)hooked_CFPreferencesSetAppValue,
                   (void **)&orig_CFPreferencesSetAppValue);
}
