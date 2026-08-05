#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

/// Resolves jailbreak root for rootful / rootless (/var/jb) / roothide (jbroot).
FOUNDATION_EXPORT NSString *AEJailbreakRootPrefix(void);

FOUNDATION_EXPORT NSDictionary *AEPrefs(void);
FOUNDATION_EXPORT void AEPrefsInvalidate(void);

FOUNDATION_EXPORT BOOL AEPrefBool(NSString *key, BOOL fallback);
FOUNDATION_EXPORT NSInteger AEPrefInt(NSString *key, NSInteger fallback);
FOUNDATION_EXPORT CGFloat AEPrefFloat(NSString *key, CGFloat fallback);
FOUNDATION_EXPORT NSString *AEPrefString(NSString *key, NSString *fallback);

/// Bundle id of the current process (SpringBoard → com.apple.springboard).
FOUNDATION_EXPORT NSString *AECurrentBundleID(void);

/// Sandboxed writable dir under jbroot or /var/mobile for Aether data.
FOUNDATION_EXPORT NSString *AEDataDirectory(void);

NS_ASSUME_NONNULL_END
