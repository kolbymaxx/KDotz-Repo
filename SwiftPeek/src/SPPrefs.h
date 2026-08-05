#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Jailbreak root prefix ("" / "/var/jb" / roothide jbroot). Same pattern as Siri27/Music27.
NSString *SPJailbreakRootPrefix(void);

/// Preference domain: com.kolby.swiftpeek
NSDictionary *SPPrefs(void);
BOOL SPPrefBool(NSString *key, BOOL fallback);
void SPPrefsInvalidate(void);

/// Candidate prefs file paths (jbroot → /var/jb → rootfs), for diagnostics.
NSArray<NSString *> *SPPrefsCandidatePaths(void);

NS_ASSUME_NONNULL_END
