#import <Preferences/PSListController.h>
#import <spawn.h>
#import <dlfcn.h>

@interface CC27RootListController : PSListController
@end

@implementation CC27RootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

static NSString *CC27FindBinary(NSString *leaf) {
    NSMutableArray<NSString *> *candidates = [NSMutableArray array];
    const char *(*jbrootFn)(const char *) = (const char *(*)(const char *))dlsym(RTLD_DEFAULT, "jbroot");
    if (jbrootFn) {
        for (NSString *prefix in @[ @"/usr/bin/", @"/bin/", @"/usr/local/bin/" ]) {
            const char *p = jbrootFn([[prefix stringByAppendingString:leaf] UTF8String]);
            if (p && p[0]) [candidates addObject:[NSString stringWithUTF8String:p]];
        }
    }
    [candidates addObject:[@"/var/jb/usr/bin/" stringByAppendingString:leaf]];
    [candidates addObject:[@"/var/jb/bin/" stringByAppendingString:leaf]];
    [candidates addObject:[@"/usr/bin/" stringByAppendingString:leaf]];
    [candidates addObject:[@"/bin/" stringByAppendingString:leaf]];
    for (NSString *c in candidates) {
        if ([[NSFileManager defaultManager] isExecutableFileAtPath:c]) return c;
    }
    return nil;
}

- (void)respring {
    [self respring:nil];
}

- (void)respring:(id)sender {
    (void)sender;
    NSString *sbreload = CC27FindBinary(@"sbreload");
    if (sbreload) {
        pid_t pid = 0;
        const char *args[] = { sbreload.fileSystemRepresentation, NULL };
        posix_spawn(&pid, args[0], NULL, NULL, (char *const *)args, NULL);
        return;
    }

    // Fallback: kill SpringBoard (device will respawn it).
    NSString *killall = CC27FindBinary(@"killall");
    if (killall) {
        pid_t pid = 0;
        const char *args[] = { killall.fileSystemRepresentation, "SpringBoard", NULL };
        posix_spawn(&pid, args[0], NULL, NULL, (char *const *)args, NULL);
        return;
    }

    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"CC27"
                                            message:@"Couldn't find sbreload. Respring manually from your jailbreak app."
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
