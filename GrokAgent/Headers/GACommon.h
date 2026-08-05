// GACommon.h — shared constants, logging, preference keys.
#import <Foundation/Foundation.h>

#define kGAIdentifier @"com.kolby.grokagent"

// Darwin notifications
#define kGANotifyPrefsChanged "com.kolby.grokagent/prefsChanged"
#define kGANotifyActivate     "com.kolby.grokagent/activate"   // notifyutil -p <this> to trigger

// Preference keys (NSUserDefaults suite: kGAIdentifier)
#define kGAPrefEnabled          @"GAEnabled"
#define kGAPrefAPIKey           @"GAAPIKey"
#define kGAPrefModel            @"GAModel"
#define kGAPrefBaseURL          @"GABaseURL"
#define kGAPrefActivationMethod @"GAActivationMethod"
#define kGAPrefDebugLogging     @"GADebugLogging"
#define kGAPrefMCPHost          @"GAMCPHost"
#define kGAPrefMCPPort          @"GAMCPPort"
#define kGAPrefMCPPath          @"GAMCPPath"
#define kGAPrefMaxSteps         @"GAMaxSteps"
#define kGAPrefAllowShell       @"GAAllowShell"
#define kGAPrefSpeakReplies     @"GASpeakReplies"
#define kGAPrefOverlaySafeMode  @"GAOverlaySafeMode"

typedef NS_ENUM(NSInteger, GAActivationMethod) {
    GAActivationMethodDarwinOnly    = 0,  // notifyutil only — always available, good for testing
    GAActivationMethodVolumeDouble  = 1,  // double-press volume up
    GAActivationMethodSiriIntercept = 2,  // replace the Siri invocation path
};

// Logging. Verbose lines are gated behind the debug pref; errors always log.
BOOL GADebugLoggingEnabled(void);

#define GALog(fmt, ...) \
    do { if (GADebugLoggingEnabled()) NSLog(@"[GrokAgent] " fmt, ##__VA_ARGS__); } while (0)

#define GAErr(fmt, ...) NSLog(@"[GrokAgent][error] " fmt, ##__VA_ARGS__)
