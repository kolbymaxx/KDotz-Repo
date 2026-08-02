/**
 * RHCompat — RootHide companion path shim
 *
 * Early-load (000RHCompat) narrow rewrite of:
 *   - /var/jb and /private/var/jb  → jbroot(suffix)
 *   - /Library/PreferenceLoader|PreferenceBundles → jbroot(path)
 *   - /var/mobile/Library/Preferences (non-Apple) when jbroot has the file
 *     or the rootfs file is absent
 *
 * Plus light CFPreferences fallbacks so PreferenceLoader-backed domains
 * resolve across schemes without a broad filesystem virtualization layer.
 */

#import <Foundation/Foundation.h>
#import <fcntl.h>
#import <sys/stat.h>
#import <stdio.h>
#import <stdarg.h>
#import <substrate.h>

#import "PathShim.h"
#import "PrefsBridge.h"

// -----------------------------------------------------------------------------
// POSIX path hooks (MSHookFunction — safe for variadic open/openat)
// -----------------------------------------------------------------------------

static int (*orig_open)(const char *path, int flags, ...);
static int hooked_open(const char *path, int flags, ...) {
    mode_t mode = 0;
    if (flags & O_CREAT) {
        va_list ap;
        va_start(ap, flags);
        mode = (mode_t)va_arg(ap, int);
        va_end(ap);
    }

    const char *rewritten = RHCompatRewritePath(path);
    if (rewritten) path = rewritten;

    if (flags & O_CREAT) {
        return orig_open(path, flags, mode);
    }
    return orig_open(path, flags);
}

static int (*orig_openat)(int fd, const char *path, int flags, ...);
static int hooked_openat(int fd, const char *path, int flags, ...) {
    mode_t mode = 0;
    if (flags & O_CREAT) {
        va_list ap;
        va_start(ap, flags);
        mode = (mode_t)va_arg(ap, int);
        va_end(ap);
    }

    if (path && path[0] == '/') {
        const char *rewritten = RHCompatRewritePath(path);
        if (rewritten) path = rewritten;
    }

    if (flags & O_CREAT) {
        return orig_openat(fd, path, flags, mode);
    }
    return orig_openat(fd, path, flags);
}

static int (*orig_stat)(const char *path, struct stat *buf);
static int hooked_stat(const char *path, struct stat *buf) {
    const char *rewritten = RHCompatRewritePath(path);
    if (rewritten) path = rewritten;
    return orig_stat(path, buf);
}

static int (*orig_lstat)(const char *path, struct stat *buf);
static int hooked_lstat(const char *path, struct stat *buf) {
    const char *rewritten = RHCompatRewritePath(path);
    if (rewritten) path = rewritten;
    return orig_lstat(path, buf);
}

static int (*orig_access)(const char *path, int amode);
static int hooked_access(const char *path, int amode) {
    const char *rewritten = RHCompatRewritePath(path);
    if (rewritten) path = rewritten;
    return orig_access(path, amode);
}

static FILE *(*orig_fopen)(const char *path, const char *mode);
static FILE *hooked_fopen(const char *path, const char *mode) {
    const char *rewritten = RHCompatRewritePath(path);
    if (rewritten) path = rewritten;
    return orig_fopen(path, mode);
}

static void RHCompatInstallPOSIXHooks(void) {
    MSHookFunction((void *)open, (void *)hooked_open, (void **)&orig_open);
    MSHookFunction((void *)openat, (void *)hooked_openat, (void **)&orig_openat);
    MSHookFunction((void *)stat, (void *)hooked_stat, (void **)&orig_stat);
    MSHookFunction((void *)lstat, (void *)hooked_lstat, (void **)&orig_lstat);
    MSHookFunction((void *)access, (void *)hooked_access, (void **)&orig_access);
    MSHookFunction((void *)fopen, (void *)hooked_fopen, (void **)&orig_fopen);
}

// -----------------------------------------------------------------------------
// Foundation helpers PreferenceLoader / tweaks commonly use
// -----------------------------------------------------------------------------

%hook NSFileManager

- (BOOL)fileExistsAtPath:(NSString *)path {
    NSString *rewritten = RHCompatRewritePathNS(path);
    if (rewritten) path = rewritten;
    return %orig(path);
}

- (BOOL)fileExistsAtPath:(NSString *)path isDirectory:(BOOL *)isDirectory {
    NSString *rewritten = RHCompatRewritePathNS(path);
    if (rewritten) path = rewritten;
    return %orig(path, isDirectory);
}

- (NSArray<NSString *> *)contentsOfDirectoryAtPath:(NSString *)path error:(NSError **)error {
    NSString *rewritten = RHCompatRewritePathNS(path);
    if (rewritten) path = rewritten;
    return %orig(path, error);
}

- (BOOL)createDirectoryAtPath:(NSString *)path
  withIntermediateDirectories:(BOOL)createIntermediates
                   attributes:(NSDictionary *)attributes
                        error:(NSError **)error {
    NSString *rewritten = RHCompatRewritePathNS(path);
    if (rewritten) path = rewritten;
    return %orig(path, createIntermediates, attributes, error);
}

%end

%hook NSDictionary

+ (instancetype)dictionaryWithContentsOfFile:(NSString *)path {
    NSString *rewritten = RHCompatRewritePathNS(path);
    if (rewritten) {
        id result = %orig(rewritten);
        if (result) return result;
    }
    return %orig(path);
}

%end

%hook NSMutableDictionary

+ (instancetype)dictionaryWithContentsOfFile:(NSString *)path {
    NSString *rewritten = RHCompatRewritePathNS(path);
    if (rewritten) {
        id result = %orig(rewritten);
        if (result) return result;
    }
    return %orig(path);
}

%end

%hook NSString

+ (instancetype)stringWithContentsOfFile:(NSString *)path
                                encoding:(NSStringEncoding)enc
                                   error:(NSError **)error {
    NSString *rewritten = RHCompatRewritePathNS(path);
    if (rewritten) path = rewritten;
    return %orig(path, enc, error);
}

%end

// -----------------------------------------------------------------------------
// Early constructor — POSIX + CFPreferences before most tweak ctors
// -----------------------------------------------------------------------------

__attribute__((constructor(101)))
static void RHCompatEarlyInit(void) {
    if (!RHCompatJBRootPrefix()) {
        return;
    }

    RHCompatInstallPOSIXHooks();
    RHCompatInstallPrefsBridge();

    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *proc = [NSProcessInfo processInfo].processName ?: @"?";
        NSLog(@"[RHCompat] early-load in %@ jbroot=%@", proc, RHCompatJBRootPrefix());
    });
}
