#import <Foundation/Foundation.h>

/// Device Control Layer — talks to witchan's iOS MCP server
/// (com.witchan.ios-mcp) over localhost using MCP streamable HTTP (JSON-RPC 2.0).
/// Gives OmniAI screen OCR, UI tree, taps, typing, app launch, etc.
NS_ASSUME_NONNULL_BEGIN

@interface OmniAIDeviceControl : NSObject

+ (instancetype)shared;

- (void)checkHealth:(void (^)(BOOL ok, NSString *_Nullable version))completion;

- (void)ensureInitialized:(void (^)(BOOL ok, NSError *_Nullable error))completion;

- (void)callTool:(NSString *)name
       arguments:(NSDictionary *_Nullable)arguments
      completion:(void (^)(NSString *_Nullable result, NSError *_Nullable error))completion;

- (void)listToolsWithCompletion:(void (^)(NSArray<NSDictionary *> *_Nullable tools,
                                          NSError *_Nullable error))completion;

/// Convenience: MCP describe_screen when the backend is up; nil otherwise.
- (void)describeScreenIfAvailable:(void (^)(NSString *_Nullable description))completion;

@end

NS_ASSUME_NONNULL_END
