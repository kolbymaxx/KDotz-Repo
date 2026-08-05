#import "GAPreferences.h"
#import <notify.h>
#import <dlfcn.h>

static GAPreferences *sShared = nil;

BOOL GADebugLoggingEnabled(void) {
    return sShared ? sShared.debugLogging : NO;
}

#pragma mark - Jailbreak root resolution

// Resolve the jailbreak root so we read the same plist PreferenceLoader writes.
//
// This matters most on RootHide, where the prefs bundle writes under a
// randomized jbroot. NSUserDefaults/CFPreferences alone read the rootfs copy,
// so every toggle reads as its default forever — the switch looks ON in
// Settings and the tweak behaves as if it were OFF. Pattern taken from Siri27
// and Music27, which both hit this.
//
// Prefer roothide's own resolver when it is loaded in this process; otherwise
// derive the root from where our dylib was injected from, so we never have to
// guess the packaging scheme.
static NSString *GAJailbreakRootPrefix(void) {
    static NSString *prefix = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        prefix = @"";

        const char *(*jbrootFn)(const char *) =
            (const char *(*)(const char *))dlsym(RTLD_DEFAULT, "jbroot");
        if (jbrootFn) {
            const char *p = jbrootFn("/");
            if (p && strlen(p) > 1) {
                prefix = [[NSString stringWithUTF8String:p] stringByStandardizingPath];
                return;
            }
        }

        Dl_info info = {0};
        if (dladdr((const void *)GAJailbreakRootPrefix, &info) && info.dli_fname) {
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

// jbroot first, then rootless, then rootful.
static NSArray<NSString *> *GAPrefsCandidatePaths(void) {
    NSString *rel = @"/var/mobile/Library/Preferences/" kGAIdentifier @".plist";
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    NSString *jb = GAJailbreakRootPrefix();
    if (jb.length > 0) [paths addObject:[jb stringByAppendingString:rel]];
    [paths addObject:[@"/var/jb" stringByAppendingString:rel]];
    [paths addObject:rel];
    return paths;
}

static NSDictionary *GAReadPrefsDictionary(void) {
    for (NSString *path in GAPrefsCandidatePaths()) {
        NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:path];
        if ([dict isKindOfClass:NSDictionary.class] && dict.count > 0) return dict;
    }
    return @{};
}

@interface GAPreferences ()
@property (nonatomic, strong) NSDictionary *plist;
@property (nonatomic, readwrite) BOOL enabled;
@property (nonatomic, readwrite) BOOL debugLogging;
@property (nonatomic, readwrite) BOOL speakReplies;
@property (nonatomic, readwrite) BOOL allowShell;
@property (nonatomic, readwrite) BOOL overlaySafeMode;
@property (nonatomic, readwrite, copy) NSString *apiKey;
@property (nonatomic, readwrite, copy) NSString *model;
@property (nonatomic, readwrite, copy) NSString *baseURL;
@property (nonatomic, readwrite) GAActivationMethod activationMethod;
@property (nonatomic, readwrite, copy) NSString *mcpHost;
@property (nonatomic, readwrite) NSInteger mcpPort;
@property (nonatomic, readwrite, copy) NSString *mcpPath;
@property (nonatomic, readwrite) NSInteger maxSteps;
@end

@implementation GAPreferences

+ (instancetype)shared {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ sShared = [[self alloc] init]; });
    return sShared;
}

- (instancetype)init {
    if ((self = [super init])) {
        [self reload];
        [self observeChanges];
    }
    return self;
}

- (void)observeChanges {
    int token;
    notify_register_dispatch(kGANotifyPrefsChanged, &token, dispatch_get_main_queue(), ^(int t) {
        [self reload];
        GALog(@"preferences reloaded");
    });
}

#pragma mark - Typed reads with CFPreferences fallback

- (id)valueForPrefKey:(NSString *)key {
    id value = self.plist[key];
    if (value != nil) return value;

    // Rootless / rootful path: the plist read above may have missed because the
    // file has not been written yet, but CFPreferences has the value cached.
    CFPropertyListRef cf = CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                     (__bridge CFStringRef)kGAIdentifier);
    if (cf == NULL) return nil;
    return (__bridge_transfer id)cf;
}

- (BOOL)boolForKey:(NSString *)key fallback:(BOOL)fallback {
    id v = [self valueForPrefKey:key];
    return v ? [v boolValue] : fallback;
}

- (NSInteger)integerForKey:(NSString *)key fallback:(NSInteger)fallback {
    id v = [self valueForPrefKey:key];
    return v ? [v integerValue] : fallback;
}

- (NSString *)stringForKey:(NSString *)key fallback:(NSString *)fallback {
    id v = [self valueForPrefKey:key];
    return [v isKindOfClass:NSString.class] && [v length] ? v : fallback;
}

#pragma mark - Reload

- (void)reload {
    CFPreferencesAppSynchronize((__bridge CFStringRef)kGAIdentifier);
    self.plist = GAReadPrefsDictionary();

    self.enabled          = [self boolForKey:kGAPrefEnabled fallback:YES];
    self.debugLogging     = [self boolForKey:kGAPrefDebugLogging fallback:YES];
    self.speakReplies     = [self boolForKey:kGAPrefSpeakReplies fallback:NO];
    self.allowShell       = [self boolForKey:kGAPrefAllowShell fallback:NO];
    self.overlaySafeMode  = [self boolForKey:kGAPrefOverlaySafeMode fallback:NO];
    self.apiKey           = [self stringForKey:kGAPrefAPIKey fallback:@""];
    self.model            = [self stringForKey:kGAPrefModel fallback:@"grok-4.5"];
    self.baseURL          = [self stringForKey:kGAPrefBaseURL fallback:@"https://api.x.ai/v1"];
    self.activationMethod = (GAActivationMethod)[self integerForKey:kGAPrefActivationMethod fallback:0];
    self.mcpHost          = [self stringForKey:kGAPrefMCPHost fallback:@"127.0.0.1"];
    self.mcpPort          = [self integerForKey:kGAPrefMCPPort fallback:8090];
    self.mcpPath          = [self stringForKey:kGAPrefMCPPath fallback:@"/mcp"];
    self.maxSteps         = MAX(1, [self integerForKey:kGAPrefMaxSteps fallback:12]);
}

- (NSString *)resolvedPrefsPath {
    for (NSString *path in GAPrefsCandidatePaths()) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) return path;
    }
    return [GAPrefsCandidatePaths() firstObject];
}

- (NSURL *)mcpURL {
    NSString *path = self.mcpPath;
    if (![path hasPrefix:@"/"]) path = [@"/" stringByAppendingString:path];
    return [NSURL URLWithString:[NSString stringWithFormat:@"http://%@:%ld%@",
                                 self.mcpHost, (long)self.mcpPort, path]];
}

@end
