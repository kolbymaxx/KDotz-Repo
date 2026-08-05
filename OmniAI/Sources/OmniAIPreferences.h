#import <Foundation/Foundation.h>
#import "OmniAICommon.h"

NS_ASSUME_NONNULL_BEGIN

@interface OmniAIPreferences : NSObject

+ (instancetype)shared;

@property (nonatomic, readonly) BOOL enabled;
@property (nonatomic, readonly) BOOL debugLogging;
@property (nonatomic, readonly) BOOL overlaySafeMode;
@property (nonatomic, readonly) BOOL includeScreenByDefault;
@property (nonatomic, readonly) BOOL statusBarActivate;
@property (nonatomic, readonly) BOOL deviceAgentByDefault;
@property (nonatomic, readonly) BOOL allowShell;
@property (nonatomic, readonly) OmniAIProvider defaultProvider;
@property (nonatomic, readonly) OmniAIActivationMethod activationMethod;
@property (nonatomic, readonly, copy) NSString *mcpHost;
@property (nonatomic, readonly) NSInteger mcpPort;
@property (nonatomic, readonly, copy) NSString *mcpPath;
@property (nonatomic, readonly) NSInteger maxSteps;
@property (nonatomic, readonly, copy) NSString *resolvedPrefsPath;
@property (nonatomic, readonly) NSURL *mcpURL;

- (void)reload;

@end

NS_ASSUME_NONNULL_END
