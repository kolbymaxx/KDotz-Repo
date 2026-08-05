#import "OmniAIKeychain.h"
#import "OmniAICommon.h"
#import <Security/Security.h>

@implementation OmniAIKeychain

+ (NSMutableDictionary *)baseQueryForAccount:(NSString *)account {
    return [@{
        (__bridge id)kSecClass:       (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kOAKeychainService,
        (__bridge id)kSecAttrAccount: account ?: @"",
    } mutableCopy];
}

+ (BOOL)setData:(NSData *)data forAccount:(NSString *)account {
    if (!account.length || !data) return NO;
    NSMutableDictionary *query = [self baseQueryForAccount:account];
    SecItemDelete((__bridge CFDictionaryRef)query);

    query[(__bridge id)kSecValueData] = data;
    query[(__bridge id)kSecAttrAccessible] =
        (__bridge id)kSecAttrAccessibleAfterFirstUnlock;
    OSStatus status = SecItemAdd((__bridge CFDictionaryRef)query, NULL);
    if (status != errSecSuccess) {
        OAErr(@"keychain set failed (%d) for %@", (int)status, account);
        return NO;
    }
    return YES;
}

+ (NSData *)dataForAccount:(NSString *)account {
    if (!account.length) return nil;
    NSMutableDictionary *query = [self baseQueryForAccount:account];
    query[(__bridge id)kSecReturnData] = @YES;
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;

    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status != errSecSuccess || !result) return nil;
    return (__bridge_transfer NSData *)result;
}

+ (BOOL)setString:(NSString *)string forAccount:(NSString *)account {
    if (!string) return [self deleteAccount:account];
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    return [self setData:data forAccount:account];
}

+ (NSString *)stringForAccount:(NSString *)account {
    NSData *data = [self dataForAccount:account];
    if (!data.length) return nil;
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

+ (BOOL)setDictionary:(NSDictionary *)dictionary forAccount:(NSString *)account {
    if (!dictionary) return [self deleteAccount:account];
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:dictionary options:0 error:&error];
    if (!data) {
        OAErr(@"keychain encode failed: %@", error);
        return NO;
    }
    return [self setData:data forAccount:account];
}

+ (NSDictionary *)dictionaryForAccount:(NSString *)account {
    NSData *data = [self dataForAccount:account];
    if (!data.length) return nil;
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [obj isKindOfClass:NSDictionary.class] ? obj : nil;
}

+ (BOOL)deleteAccount:(NSString *)account {
    if (!account.length) return NO;
    NSMutableDictionary *query = [self baseQueryForAccount:account];
    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);
    return status == errSecSuccess || status == errSecItemNotFound;
}

@end
