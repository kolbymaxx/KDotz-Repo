#import "PathShim.h"

#include <pthread.h>
#include <string.h>
#include <unistd.h>
#include <roothide.h>
#import <notify.h>

static NSString *const kEnabledKey = @"enabled";
static const char *kPrefsNotify = "com.kolby.rhcompat/ReloadPrefs";

// Per-thread recursion guard so our own open/stat calls are not rewritten again.
static pthread_key_t sBypassKey;
static pthread_once_t sBypassOnce = PTHREAD_ONCE_INIT;

static BOOL sEnabledCached = YES;
static CFAbsoluteTime sEnabledLast = 0;
static BOOL sNotifyRegistered = NO;

static void RHCompatBypassKeyInit(void) {
    pthread_key_create(&sBypassKey, NULL);
}

void RHCompatEnterBypass(void) {
    pthread_once(&sBypassOnce, RHCompatBypassKeyInit);
    uintptr_t depth = (uintptr_t)pthread_getspecific(sBypassKey);
    pthread_setspecific(sBypassKey, (void *)(depth + 1));
}

void RHCompatLeaveBypass(void) {
    pthread_once(&sBypassOnce, RHCompatBypassKeyInit);
    uintptr_t depth = (uintptr_t)pthread_getspecific(sBypassKey);
    if (depth > 0) {
        pthread_setspecific(sBypassKey, (void *)(depth - 1));
    }
}

bool RHCompatInBypass(void) {
    pthread_once(&sBypassOnce, RHCompatBypassKeyInit);
    return (uintptr_t)pthread_getspecific(sBypassKey) > 0;
}

NSString *RHCompatJBRootPrefix(void) {
    static NSString *prefix = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        const char *root = jbroot("/");
        if (!root || root[0] == '\0') {
            prefix = nil;
            return;
        }
        NSString *p = [[NSString stringWithUTF8String:root] stringByStandardizingPath];
        // RootHide jbroot("/") is a randomized path, never bare "/".
        if (p.length <= 1 || [p isEqualToString:@"/"]) {
            prefix = nil;
            return;
        }
        // Prefer the recognizable .jbroot marker; still accept other non-root prefixes.
        if ([p containsString:@".jbroot"] || [p hasPrefix:@"/var/containers/"]) {
            prefix = p;
            return;
        }
        // Last resort: any real prefix distinct from "/" and "/var/jb".
        if (![p isEqualToString:@"/var/jb"] && ![p isEqualToString:@"/private/var/jb"]) {
            prefix = p;
        }
    });
    return prefix;
}

static void RHCompatRegisterPrefsNotify(void) {
    if (sNotifyRegistered) return;
    sNotifyRegistered = YES;
    int token = 0;
    notify_register_dispatch(kPrefsNotify, &token, dispatch_get_main_queue(), ^(int t) {
        (void)t;
        sEnabledLast = 0; // force re-read
    });
}

bool RHCompatEnabled(void) {
    if (!RHCompatJBRootPrefix()) return false;
    if (RHCompatInBypass()) return false;

    RHCompatRegisterPrefsNotify();

    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (now - sEnabledLast < 1.0) return sEnabledCached;

    // Read the plist via file I/O under bypass — never CFPreferences here,
    // or hooked_CFPreferencesCopyAppValue can recurse into RHCompatEnabled.
    NSString *rel = @"/var/mobile/Library/Preferences/com.kolby.rhcompat.plist";
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    const char *jb = jbroot(rel.fileSystemRepresentation);
    if (jb && jb[0] != '\0') [paths addObject:@(jb)];
    [paths addObject:rel];

    id enabledValue = nil;
    RHCompatEnterBypass();
    for (NSString *p in paths) {
        NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:p];
        if ([d isKindOfClass:[NSDictionary class]] && d[kEnabledKey] != nil) {
            enabledValue = d[kEnabledKey];
            break;
        }
    }
    RHCompatLeaveBypass();

    sEnabledCached = (enabledValue != nil) ? [enabledValue boolValue] : YES; // default ON
    sEnabledLast = now;
    return sEnabledCached;
}

// ---- path classification (intentionally narrow) ----

static bool HasPrefix(const char *path, const char *prefix) {
    size_t n = strlen(prefix);
    return strncmp(path, prefix, n) == 0;
}

static bool IsVarJBPath(const char *path, const char **outSuffix) {
    // /var/jb  or  /var/jb/...
    if (HasPrefix(path, "/var/jb")) {
        const char *s = path + strlen("/var/jb");
        if (*s == '\0' || *s == '/') {
            *outSuffix = (*s == '\0') ? "/" : s;
            return true;
        }
    }
    if (HasPrefix(path, "/private/var/jb")) {
        const char *s = path + strlen("/private/var/jb");
        if (*s == '\0' || *s == '/') {
            *outSuffix = (*s == '\0') ? "/" : s;
            return true;
        }
    }
    return false;
}

static bool IsClassicPreferenceLoaderPath(const char *path) {
    return HasPrefix(path, "/Library/PreferenceLoader")
        || HasPrefix(path, "/Library/PreferenceBundles");
}

static bool IsClassicPrefsDataPath(const char *path, const char **outCanonical) {
    // Canonicalize /private/var/... → /var/...
    if (HasPrefix(path, "/private/var/mobile/Library/Preferences")) {
        *outCanonical = path + strlen("/private");
        return true;
    }
    if (HasPrefix(path, "/var/mobile/Library/Preferences")) {
        *outCanonical = path;
        return true;
    }
    return false;
}

static bool IsSystemPrefsFile(const char *canonicalPrefsPath) {
    const char *base = strrchr(canonicalPrefsPath, '/');
    base = base ? base + 1 : canonicalPrefsPath;
    if (base[0] == '\0') return true;
    if (HasPrefix(base, "com.apple.")) return true;
    if (strcmp(base, ".GlobalPreferences.plist") == 0) return true;
    if (strcmp(base, ".GlobalPreferences_m.plist") == 0) return true;
    if (HasPrefix(base, "systemgroup.com.apple.")) return true;
    return false;
}

const char *RHCompatRewritePath(const char *path) {
    if (!path || path[0] != '/') return NULL;
    if (!RHCompatEnabled()) return NULL;

    NSString *jbPrefix = RHCompatJBRootPrefix();
    if (!jbPrefix) return NULL;

    // Already inside jbroot — never rewrite.
    const char *prefixUTF8 = jbPrefix.UTF8String;
    if (prefixUTF8 && HasPrefix(path, prefixUTF8)) return NULL;

    const char *suffix = NULL;

    // 1) Legacy rootless prefix → jbroot(suffix)
    if (IsVarJBPath(path, &suffix)) {
        const char *mapped = jbroot(suffix);
        if (mapped && mapped[0] != '\0' && strcmp(mapped, path) != 0) {
            return mapped;
        }
        return NULL;
    }

    // 2) Classic PreferenceLoader / PreferenceBundles (no /var/jb prefix)
    if (IsClassicPreferenceLoaderPath(path)) {
        const char *mapped = jbroot(path);
        if (mapped && mapped[0] != '\0' && strcmp(mapped, path) != 0) {
            return mapped;
        }
        return NULL;
    }

    // 3) Classic prefs data dir — only when jbroot copy exists, or for
    //    non-system domains (so PreferenceLoader-backed tweak plists land
    //    in jbroot without touching Apple system prefs).
    const char *canonical = NULL;
    if (IsClassicPrefsDataPath(path, &canonical)) {
        if (IsSystemPrefsFile(canonical)) return NULL;

        const char *mapped = jbroot(canonical);
        if (!mapped || mapped[0] == '\0' || strcmp(mapped, path) == 0) return NULL;

        RHCompatEnterBypass();
        int jbExists = access(mapped, F_OK);
        int rootExists = access(canonical, F_OK);
        RHCompatLeaveBypass();

        // Prefer jbroot when it already has the file.
        if (jbExists == 0) return mapped;

        // If neither exists yet, send non-system prefs into jbroot (create path).
        if (rootExists != 0) return mapped;

        // Rootfs file exists and jbroot does not — leave alone (avoid
        // surprising migrations / detection crumbs from copying).
        return NULL;
    }

    return NULL;
}

NSString *RHCompatRewritePathNS(NSString *path) {
    if (![path isKindOfClass:[NSString class]] || path.length == 0) return nil;
    const char *rewritten = RHCompatRewritePath(path.fileSystemRepresentation);
    if (!rewritten) return nil;
    return [NSString stringWithUTF8String:rewritten];
}
