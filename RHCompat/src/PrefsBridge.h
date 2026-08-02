#import <Foundation/Foundation.h>

/// Install CFPreferences fallbacks that read tweak domains from jbroot
/// when the stock lookup returns nothing.
void RHCompatInstallPrefsBridge(void);
