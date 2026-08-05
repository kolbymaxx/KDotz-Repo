#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Best-effort Swift type name for a live object / metadata pointer.
/// Fail-closed: returns nil on anything unexpected (never guesses).
NSString * _Nullable SPSwiftTypeNameFromObject(id _Nullable object);
NSString * _Nullable SPSwiftTypeNameFromMetadata(const void * _Nullable metadata);

/// Demangle a Swift mangled name when the runtime helper is available.
NSString * _Nullable SPSwiftDemangle(NSString *mangled);

NS_ASSUME_NONNULL_END
