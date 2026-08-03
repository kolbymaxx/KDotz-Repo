#import <Foundation/Foundation.h>
#import "GACommon.h"

/// Thin, cached wrapper over the tweak's NSUserDefaults suite.
/// Reloads automatically when the prefs bundle posts kGANotifyPrefsChanged.
@interface GAPreferences : NSObject

+ (instancetype)shared;

@property (nonatomic, readonly) BOOL enabled;
@property (nonatomic, readonly) BOOL debugLogging;
@property (nonatomic, readonly) BOOL speakReplies;
@property (nonatomic, readonly) BOOL allowShell;
/// One-shot failsafe: suppresses the overlay window after a bad boot.
@property (nonatomic, readonly) BOOL overlaySafeMode;

@property (nonatomic, readonly, copy) NSString *apiKey;
@property (nonatomic, readonly, copy) NSString *model;
@property (nonatomic, readonly, copy) NSString *baseURL;

@property (nonatomic, readonly) GAActivationMethod activationMethod;

@property (nonatomic, readonly, copy) NSString *mcpHost;
@property (nonatomic, readonly) NSInteger mcpPort;
@property (nonatomic, readonly, copy) NSString *mcpPath;
@property (nonatomic, readonly) NSInteger maxSteps;

/// Convenience: fully-formed MCP endpoint, e.g. http://127.0.0.1:8090/mcp
@property (nonatomic, readonly) NSURL *mcpURL;

/// Which candidate path we actually read from. Log this at boot — on
/// RootHide it is the difference between working and silently defaulted.
@property (nonatomic, readonly) NSString *resolvedPrefsPath;

- (void)reload;

@end
