#import <Foundation/Foundation.h>

/// Curated OpenAI/xAI function-calling schemas backed by iOS MCP tools.
NS_ASSUME_NONNULL_BEGIN

@interface OmniAIToolRegistry : NSObject

+ (NSArray<NSDictionary *> *)toolSchemas;
+ (BOOL)isToolAllowed:(NSString *)name;

@end

NS_ASSUME_NONNULL_END
