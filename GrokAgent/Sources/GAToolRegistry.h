#import <Foundation/Foundation.h>

/// Curated set of device-control tools exposed to the model, in OpenAI/xAI
/// function-calling schema form.
///
/// Deliberately a subset of iOS MCP's ~46 tools. Every tool costs context on
/// every turn, and the destructive ones (run_command, write_file, uninstall_app)
/// stay out unless explicitly enabled in preferences.
@interface GAToolRegistry : NSObject

/// Array of {"type":"function","function":{...}} dictionaries for the request body.
+ (NSArray<NSDictionary *> *)toolSchemas;

/// Whitelist check before dispatching anything the model asked for.
+ (BOOL)isToolAllowed:(NSString *)name;

@end
