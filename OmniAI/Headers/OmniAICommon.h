// OmniAICommon.h — shared constants, logging, preference keys.
#import <Foundation/Foundation.h>

#define kOAIdentifier @"com.kolby.omniai"

// Darwin notifications
#define kOANotifyPrefsChanged "com.kolby.omniai/prefsChanged"
#define kOANotifyActivate     "com.kolby.omniai/activate"

// Preference keys (NSUserDefaults suite: kOAIdentifier)
#define kOAPrefEnabled            @"OAEnabled"
#define kOAPrefDebugLogging       @"OADebugLogging"
#define kOAPrefOverlaySafeMode    @"OAOverlaySafeMode"
#define kOAPrefDefaultProvider    @"OADefaultProvider"   // grok | claude | gemini
#define kOAPrefIncludeScreen      @"OAIncludeScreenByDefault"
#define kOAPrefStatusBarActivate  @"OAStatusBarActivate"
#define kOAPrefDeviceAgentDefault @"OADeviceAgentByDefault"
#define kOAPrefActivationMethod   @"OAActivationMethod"
#define kOAPrefMCPHost            @"OAMCPHost"
#define kOAPrefMCPPort            @"OAMCPPort"
#define kOAPrefMCPPath            @"OAMCPPath"
#define kOAPrefMaxSteps           @"OAMaxSteps"
#define kOAPrefAllowShell         @"OAAllowShell"

typedef NS_ENUM(NSInteger, OmniAIActivationMethod) {
    OmniAIActivationMethodStatusBar  = 0,  // status-bar tap (default)
    OmniAIActivationMethodVolumeDouble = 1,
    OmniAIActivationMethodDarwinOnly = 2,  // notifyutil -p com.kolby.omniai/activate
};

// Keychain account names
#define kOAKeychainService        @"com.kolby.omniai.tokens"
#define kOAKeychainGrok           @"grok.session"
#define kOAKeychainClaude         @"claude.session"
#define kOAKeychainGemini         @"gemini.oauth"

typedef NS_ENUM(NSInteger, OmniAIProvider) {
    OmniAIProviderGrok   = 0,
    OmniAIProviderClaude = 1,
    OmniAIProviderGemini = 2,
};

static inline NSString *OmniAIProviderName(OmniAIProvider p) {
    switch (p) {
        case OmniAIProviderClaude: return @"claude";
        case OmniAIProviderGemini: return @"gemini";
        default:                   return @"grok";
    }
}

static inline OmniAIProvider OmniAIProviderFromName(NSString *name) {
    NSString *n = name.lowercaseString;
    if ([n isEqualToString:@"claude"]) return OmniAIProviderClaude;
    if ([n isEqualToString:@"gemini"]) return OmniAIProviderGemini;
    return OmniAIProviderGrok;
}

BOOL OADebugLoggingEnabled(void);

#define OALog(fmt, ...) \
    do { if (OADebugLoggingEnabled()) NSLog(@"[OmniAI] " fmt, ##__VA_ARGS__); } while (0)

#define OAErr(fmt, ...) NSLog(@"[OmniAI][error] " fmt, ##__VA_ARGS__)
