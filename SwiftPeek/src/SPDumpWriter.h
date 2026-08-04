#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Writes a JSON dump with a stable header. Returns the path written, or nil.
/// Darwin notification: com.kolby.swiftpeek/dump
NSString * _Nullable SPWriteJSONDump(NSDictionary *payload);

/// Header fields included in every dump (stable key order when serialized).
NSDictionary *SPDumpHeader(void);

NS_ASSUME_NONNULL_END
