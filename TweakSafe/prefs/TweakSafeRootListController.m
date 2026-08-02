#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#include <roothide.h>
#include <stdlib.h>

@interface TweakSafeRootListController : PSListController
@end

@implementation TweakSafeRootListController {
    NSArray<NSDictionary *> *_tweaks; // @{ name, dir, enabled }
}

#pragma mark - Paths

- (NSArray<NSString *> *)tweakDirs {
    NSMutableArray *dirs = [NSMutableArray array];
    for (NSString *r in @[ @"/Library/MobileSubstrate/DynamicLibraries", @"/usr/lib/TweakInject" ]) {
        NSString *mapped = jbroot(r);
        if (mapped.length && [[NSFileManager defaultManager] fileExistsAtPath:mapped]) {
            [dirs addObject:mapped];
        }
    }
    return dirs;
}

- (NSString *)jbrootDisplay {
    NSString *root = jbroot(@"/");
    if (!root.length || [root isEqualToString:@"/"]) return @"(unavailable)";
    if (root.length > 48) {
        return [NSString stringWithFormat:@"…%@", [root substringFromIndex:root.length - 40]];
    }
    return root;
}

- (BOOL)isProtectedName:(NSString *)name {
    static NSSet *protected;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        protected = [NSSet setWithArray:@[
            @"MobileSubstrate", @"Substrate", @"SubstrateBootstrap",
            @"ElleKit", @"ellekit", @"libhooker", @"libblackjack",
            @"TweakInject", @"PreferenceLoader",
            @"libsandy", @"libSandy",
            @"AutoPatches", @"PatchLoader", @"systemhook",
            @"TweakSafe", @"TweakSafePrefs", @"000RHCompat", @"RHCompat",
        ]];
    });
    return [protected containsObject:name];
}

- (NSArray<NSDictionary *> *)scanTweaks {
    NSMutableDictionary<NSString *, NSMutableDictionary *> *byName = [NSMutableDictionary dictionary];
    NSFileManager *fm = [NSFileManager defaultManager];

    for (NSString *dir in [self tweakDirs]) {
        NSArray *files = [fm contentsOfDirectoryAtPath:dir error:nil] ?: @[];
        for (NSString *file in files) {
            BOOL enabled = YES;
            NSString *base = nil;
            if ([file hasSuffix:@".plist.disabled"]) {
                enabled = NO;
                base = [file substringToIndex:file.length - @".plist.disabled".length];
            } else if ([file hasSuffix:@".plist"]) {
                base = [file substringToIndex:file.length - @".plist".length];
            } else {
                continue;
            }

            if (base.length == 0 || [self isProtectedName:base]) continue;

            NSMutableDictionary *entry = byName[base];
            if (!entry) {
                byName[base] = [@{
                    @"name": base,
                    @"dir": dir,
                    @"enabled": @(enabled),
                } mutableCopy];
            } else if (enabled) {
                entry[@"enabled"] = @YES;
                entry[@"dir"] = dir;
            }
        }
    }

    NSArray *names = [[byName allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:names.count];
    for (NSString *n in names) [out addObject:byName[n]];
    return out;
}

#pragma mark - Specifiers

- (NSArray *)specifiers {
    if (!_specifiers) {
        _tweaks = [self scanTweaks];
        NSMutableArray *specs = [NSMutableArray array];

        PSSpecifier *statusGroup = [PSSpecifier groupSpecifierWithName:@"TweakSafe"];
        [statusGroup setProperty:
            [NSString stringWithFormat:@"RootHide tweak safety panel (Settings only — no SpringBoard hooks). jbroot %@", [self jbrootDisplay]]
                          forKey:@"footerText"];
        [specs addObject:statusGroup];

        [specs addObject:[PSSpecifier preferenceSpecifierNamed:
            [NSString stringWithFormat:@"%lu tweak filter(s)", (unsigned long)_tweaks.count]
            target:nil set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil]];

        PSSpecifier *actions = [PSSpecifier groupSpecifierWithName:@"Actions"];
        [specs addObject:actions];

        [specs addObject:[self button:@"Refresh list" action:@selector(reloadTweakList)]];
        [specs addObject:[self button:@"Disable all tweaks" action:@selector(disableAllTweaks)]];
        [specs addObject:[self button:@"Enable all tweaks" action:@selector(enableAllTweaks)]];
        [specs addObject:[self button:@"Disable recently modified (24h)" action:@selector(disableRecentTweaks)]];

        PSSpecifier *respringGroup = [PSSpecifier groupSpecifierWithName:nil];
        [respringGroup setProperty:@"Respring after changing toggles so Substrate/ElleKit reloads filters."
                            forKey:@"footerText"];
        [specs addObject:respringGroup];
        [specs addObject:[self button:@"Respring" action:@selector(respring)]];

        PSSpecifier *listGroup = [PSSpecifier groupSpecifierWithName:@"Installed tweaks"];
        [listGroup setProperty:@"Off renames the filter to .plist.disabled (standard loaders ignore it)."
                        forKey:@"footerText"];
        [specs addObject:listGroup];

        if (_tweaks.count == 0) {
            [specs addObject:[PSSpecifier preferenceSpecifierNamed:@"No user tweak filters found"
                target:nil set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil]];
        } else {
            for (NSDictionary *t in _tweaks) {
                NSString *name = t[@"name"];
                PSSpecifier *sw = [PSSpecifier preferenceSpecifierNamed:name
                    target:self
                    set:@selector(setTweakEnabled:specifier:)
                    get:@selector(tweakEnabled:)
                    detail:nil
                    cell:PSSwitchCell
                    edit:nil];
                [sw setProperty:name forKey:@"tweakName"];
                [sw setProperty:t[@"dir"] forKey:@"tweakDir"];
                [sw setProperty:@YES forKey:@"enabled"];
                [specs addObject:sw];
            }
        }

        _specifiers = specs;
    }
    return _specifiers;
}

- (PSSpecifier *)button:(NSString *)label action:(SEL)action {
    PSSpecifier *s = [PSSpecifier preferenceSpecifierNamed:label
        target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    s->action = action;
    return s;
}

- (id)tweakEnabled:(PSSpecifier *)specifier {
    NSString *name = [specifier propertyForKey:@"tweakName"];
    for (NSDictionary *t in _tweaks) {
        if ([t[@"name"] isEqualToString:name]) return t[@"enabled"];
    }
    return @YES;
}

- (void)setTweakEnabled:(id)value specifier:(PSSpecifier *)specifier {
    NSString *name = [specifier propertyForKey:@"tweakName"];
    NSString *dir = [specifier propertyForKey:@"tweakDir"];
    if (![self setEnabled:[value boolValue] name:name dir:dir]) {
        [self showAlert:@"Couldn't update tweak" message:@"Filter plist may not be writable under jbroot."];
    }
    // Refresh cached enabled flags
    _tweaks = [self scanTweaks];
}

- (BOOL)setEnabled:(BOOL)enabled name:(NSString *)name dir:(NSString *)dir {
    if (name.length == 0 || dir.length == 0 || [self isProtectedName:name]) return NO;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *active = [dir stringByAppendingPathComponent:[name stringByAppendingString:@".plist"]];
    NSString *disabled = [dir stringByAppendingPathComponent:[name stringByAppendingString:@".plist.disabled"]];

    if (enabled) {
        if ([fm fileExistsAtPath:disabled]) {
            if ([fm fileExistsAtPath:active]) [fm removeItemAtPath:active error:nil];
            return [fm moveItemAtPath:disabled toPath:active error:nil];
        }
        return [fm fileExistsAtPath:active];
    }

    if ([fm fileExistsAtPath:active]) {
        if ([fm fileExistsAtPath:disabled]) [fm removeItemAtPath:disabled error:nil];
        return [fm moveItemAtPath:active toPath:disabled error:nil];
    }
    return [fm fileExistsAtPath:disabled];
}

#pragma mark - Actions

- (void)reloadTweakList {
    [self reloadSpecifiersFresh];
}

- (void)reloadSpecifiersFresh {
    _specifiers = nil;
    _tweaks = nil;
    [self reloadSpecifiers];
}

- (void)disableAllTweaks {
    for (NSDictionary *t in [self scanTweaks]) {
        [self setEnabled:NO name:t[@"name"] dir:t[@"dir"]];
    }
    [self reloadSpecifiersFresh];
    [self showAlert:@"Tweaks disabled" message:@"Respring for changes to take effect."];
}

- (void)enableAllTweaks {
    // Include currently-disabled filters from disk
    for (NSDictionary *t in [self scanTweaks]) {
        [self setEnabled:YES name:t[@"name"] dir:t[@"dir"]];
    }
    [self reloadSpecifiersFresh];
    [self showAlert:@"Tweaks enabled" message:@"Respring for changes to take effect."];
}

- (void)disableRecentTweaks {
    NSTimeInterval cutoff = [[NSDate date] timeIntervalSince1970] - 24 * 60 * 60;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableSet *disabledNames = [NSMutableSet set];

    for (NSString *dir in [self tweakDirs]) {
        for (NSString *file in ([fm contentsOfDirectoryAtPath:dir error:nil] ?: @[])) {
            BOOL isPlist = [file hasSuffix:@".plist"];
            BOOL isDylib = [file hasSuffix:@".dylib"];
            if (!isPlist && !isDylib) continue;

            NSString *path = [dir stringByAppendingPathComponent:file];
            NSDate *mod = [fm attributesOfItemAtPath:path error:nil][NSFileModificationDate];
            if (mod.timeIntervalSince1970 < cutoff) continue;

            NSString *name = isPlist
                ? [file substringToIndex:file.length - 6]
                : [file substringToIndex:file.length - 6];
            if ([self isProtectedName:name]) continue;
            if ([self setEnabled:NO name:name dir:dir]) {
                [disabledNames addObject:name];
            }
        }
    }

    [self reloadSpecifiersFresh];
    [self showAlert:@"Recent tweaks disabled"
            message:[NSString stringWithFormat:@"Disabled %lu tweak(s) touched in the last 24 hours. Respring to apply.",
                                               (unsigned long)disabledNames.count]];
}

- (void)respring {
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"Respring?"
                                            message:@"SpringBoard will restart."
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Respring" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        (void)a;
        const char *sbreload = jbroot("/usr/bin/sbreload");
        if (sbreload && access(sbreload, X_OK) == 0) {
            pid_t pid = 0;
            char *argv[] = { "sbreload", NULL };
            posix_spawn(&pid, sbreload, NULL, NULL, argv, environ);
        } else {
            pid_t pid = 0;
            char *argv[] = { "killall", "-9", "SpringBoard", NULL };
            const char *killall = jbroot("/usr/bin/killall");
            if (!(killall && access(killall, X_OK) == 0)) killall = "/usr/bin/killall";
            posix_spawn(&pid, killall, NULL, NULL, argv, environ);
        }
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showAlert:(NSString *)title message:(NSString *)message {
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:title
                                            message:message
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
