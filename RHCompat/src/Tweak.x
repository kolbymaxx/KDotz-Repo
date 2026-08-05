/**
 * RHCompat — RootHide companion path shim (safe profile)
 *
 * 1.0.2+: Preferences-only. No SpringBoard / UIKit injection.
 * No process-wide open/stat/posix_spawn hooks (those crash-looped SB in 1.0.1).
 *
 * Remains: Foundation path helpers + CFPreferences bridge for
 * PreferenceLoader / prefs-data under jbroot.
 */

#import <Foundation/Foundation.h>

#import "PathShim.h"
#import "PrefsBridge.h"

// -----------------------------------------------------------------------------
// Foundation helpers PreferenceLoader uses inside Preferences.app
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
// Late-ish ctor — CFPreferences bridge only (no POSIX hooks)
// -----------------------------------------------------------------------------

%ctor {
    if (!RHCompatJBRootPrefix()) {
        return;
    }
    // Only run inside Preferences — belt-and-suspenders with the filter plist.
    NSString *proc = [NSProcessInfo processInfo].processName ?: @"";
    if (![proc isEqualToString:@"Preferences"]) {
        NSLog(@"[RHCompat] skip non-Preferences process: %@", proc);
        return;
    }

    RHCompatInstallPrefsBridge();
    NSLog(@"[RHCompat] loaded in Preferences jbroot=%@", RHCompatJBRootPrefix());
}
