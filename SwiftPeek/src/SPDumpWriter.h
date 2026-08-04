#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Writes a JSON dump with a stable header. Returns the path written, or nil.
/// Darwin notification: com.kolby.swiftpeek/dump
NSString * _Nullable SPWriteJSONDump(NSDictionary *payload);

/// Header fields included in every dump.
NSDictionary *SPDumpHeader(void);

/// Directory used for dumps / status (jbroot-aware).
NSString *SPDumpDirectory(void);

/// Always-on Filza breadcrumb: Library/SwiftPeek/status.json
NSString * _Nullable SPWriteStatus(NSDictionary *payload);

NS_ASSUME_NONNULL_END
