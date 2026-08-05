#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Thin Keychain wrapper. Tokens are stored with
/// kSecAttrAccessibleAfterFirstUnlock so SpringBoard / apps can read them
/// after the device unlocks once.
@interface OmniAIKeychain : NSObject

+ (BOOL)setData:(NSData *)data forAccount:(NSString *)account;
+ (nullable NSData *)dataForAccount:(NSString *)account;
+ (BOOL)setString:(NSString *)string forAccount:(NSString *)account;
+ (nullable NSString *)stringForAccount:(NSString *)account;
+ (BOOL)setDictionary:(NSDictionary *)dictionary forAccount:(NSString *)account;
+ (nullable NSDictionary *)dictionaryForAccount:(NSString *)account;
+ (BOOL)deleteAccount:(NSString *)account;

@end

NS_ASSUME_NONNULL_END
