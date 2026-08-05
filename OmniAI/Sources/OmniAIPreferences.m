#import "OmniAIPreferences.h"
#import <notify.h>
#import <dlfcn.h>

static OmniAIPreferences *sShared = nil;

BOOL OADebugLoggingEnabled(void) {
    return sShared ? sShared.debugLogging : NO;
}

static NSString *OAJailbreakRootPrefix(void) {
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
        if (dladdr((const void *)OAJailbreakRootPrefix, &info) && info.dli_fname) {
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

static NSArray<NSString *> *OAPrefsCandidatePaths(void) {
    NSString *rel = @"/var/mobile/Library/Preferences/" kOAIdentifier @".plist";
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    NSString *jb = OAJailbreakRootPrefix();
    if (jb.length > 0) [paths addObject:[jb stringByAppendingString:rel]];
    [paths addObject:[@"/var/jb" stringByAppendingString:rel]];
    [paths addObject:rel];
    return paths;
}

static NSDictionary *OAReadPrefsDictionary(void) {
    for (NSString *path in OAPrefsCandidatePaths()) {
        NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:path];
        if ([dict isKindOfClass:NSDictionary.class] && dict.count > 0) return dict;
    }
    return @{};
}

@interface OmniAIPreferences ()
@property (nonatomic, strong) NSDictionary *plist;
@property (nonatomic, readwrite) BOOL enabled;
@property (nonatomic, readwrite) BOOL debugLogging;
@property (nonatomic, readwrite) BOOL overlaySafeMode;
@property (nonatomic, readwrite) BOOL includeScreenByDefault;
@property (nonatomic, readwrite) BOOL statusBarActivate;
@property (nonatomic, readwrite) BOOL deviceAgentByDefault;
@property (nonatomic, readwrite) BOOL allowShell;
@property (nonatomic, readwrite) OmniAIProvider defaultProvider;
@property (nonatomic, readwrite) OmniAIActivationMethod activationMethod;
@property (nonatomic, readwrite, copy) NSString *mcpHost;
@property (nonatomic, readwrite) NSInteger mcpPort;
@property (nonatomic, readwrite, copy) NSString *mcpPath;
@property (nonatomic, readwrite) NSInteger maxSteps;
@end

@implementation OmniAIPreferences

+ (instancetype)shared {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ sShared = [[self alloc] init]; });
    return sShared;
}

- (instancetype)init {
    if ((self = [super init])) {
        [self reload];
        int token;
        notify_register_dispatch(kOANotifyPrefsChanged, &token, dispatch_get_main_queue(), ^(int t) {
            [self reload];
            OALog(@"preferences reloaded");
        });
    }
    return self;
}

- (id)valueForPrefKey:(NSString *)key {
    id value = self.plist[key];
    if (value != nil) return value;
    CFPropertyListRef cf = CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                     (__bridge CFStringRef)kOAIdentifier);
    if (cf == NULL) return nil;
    return (__bridge_transfer id)cf;
}

- (BOOL)boolForKey:(NSString *)key fallback:(BOOL)fallback {
    id v = [self valueForPrefKey:key];
    return v ? [v boolValue] : fallback;
}

- (NSString *)stringForKey:(NSString *)key fallback:(NSString *)fallback {
    id v = [self valueForPrefKey:key];
    return [v isKindOfClass:NSString.class] && [v length] ? v : fallback;
}

- (NSInteger)integerForKey:(NSString *)key fallback:(NSInteger)fallback {
    id v = [self valueForPrefKey:key];
    return v ? [v integerValue] : fallback;
}

- (void)reload {
    CFPreferencesAppSynchronize((__bridge CFStringRef)kOAIdentifier);
    self.plist = OAReadPrefsDictionary();

    self.enabled                = [self boolForKey:kOAPrefEnabled fallback:YES];
    self.debugLogging           = [self boolForKey:kOAPrefDebugLogging fallback:YES];
    self.overlaySafeMode        = [self boolForKey:kOAPrefOverlaySafeMode fallback:NO];
    self.includeScreenByDefault = [self boolForKey:kOAPrefIncludeScreen fallback:NO];
    self.statusBarActivate      = [self boolForKey:kOAPrefStatusBarActivate fallback:YES];
    self.deviceAgentByDefault   = [self boolForKey:kOAPrefDeviceAgentDefault fallback:NO];
    self.allowShell             = [self boolForKey:kOAPrefAllowShell fallback:NO];
    self.defaultProvider        = OmniAIProviderFromName(
        [self stringForKey:kOAPrefDefaultProvider fallback:@"grok"]);
    self.activationMethod       = (OmniAIActivationMethod)[self integerForKey:kOAPrefActivationMethod fallback:0];
    self.mcpHost                = [self stringForKey:kOAPrefMCPHost fallback:@"127.0.0.1"];
    self.mcpPort                = [self integerForKey:kOAPrefMCPPort fallback:8090];
    self.mcpPath                = [self stringForKey:kOAPrefMCPPath fallback:@"/mcp"];
    self.maxSteps               = MAX(1, [self integerForKey:kOAPrefMaxSteps fallback:12]);
}

- (NSString *)resolvedPrefsPath {
    for (NSString *path in OAPrefsCandidatePaths()) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) return path;
    }
    return [OAPrefsCandidatePaths() firstObject];
}

- (NSURL *)mcpURL {
    NSString *path = self.mcpPath;
    if (![path hasPrefix:@"/"]) path = [@"/" stringByAppendingString:path];
    return [NSURL URLWithString:[NSString stringWithFormat:@"http://%@:%ld%@",
                                 self.mcpHost, (long)self.mcpPort, path]];
}

@end
