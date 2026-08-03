#import <Foundation/Foundation.h>

/// Device Control Layer.
///
/// v0.1 talks to witchan's iOS MCP server (com.witchan.ios-mcp, MIT) over
/// localhost:8090 using MCP streamable HTTP (JSON-RPC 2.0). This gets us ~46
/// working tools on day one. Later we can swap the transport for in-process
/// Manager classes extracted from that project without touching the agent loop —
/// everything above this class only sees -callTool:arguments:completion:.
NS_ASSUME_NONNULL_BEGIN

@interface GADeviceControl : NSObject

+ (instancetype)shared;

/// GET /health — confirms the MCP server is up. Cheap; call before a session.
- (void)checkHealth:(void (^)(BOOL ok, NSString *_Nullable version))completion;

/// One-time MCP `initialize` handshake. Safe to call repeatedly; no-ops if done.
- (void)ensureInitialized:(void (^)(BOOL ok, NSError *_Nullable error))completion;

/// Calls an MCP tool by name. `result` is the flattened text content of the
/// tool result, suitable for handing straight back to the model.
- (void)callTool:(NSString *)name
       arguments:(NSDictionary *_Nullable)arguments
      completion:(void (^)(NSString *_Nullable result, NSError *_Nullable error))completion;

/// tools/list — useful for verifying names against the installed server version.
- (void)listToolsWithCompletion:(void (^)(NSArray<NSDictionary *> *_Nullable tools,
                                          NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
