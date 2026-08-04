#import "SPDumpWriter.h"
#import "SPPrefs.h"
#import <notify.h>
#import <sys/utsname.h>
#import <UIKit/UIKit.h>

static NSString * const kSPDumpNotify = @"com.kolby.swiftpeek/dump";

NSDictionary *SPDumpHeader(void) {
    NSString *iosVersion = UIDevice.currentDevice.systemVersion ?: @"unknown";
    struct utsname u;
    NSString *machine = @"unknown";
    if (uname(&u) == 0) {
        machine = [NSString stringWithUTF8String:u.machine] ?: @"unknown";
    }
    NSString *proc = NSProcessInfo.processInfo.processName ?: @"unknown";
    // ISO-8601 UTC
    NSISO8601DateFormatter *fmt = [[NSISO8601DateFormatter alloc] init];
    fmt.formatOptions = NSISO8601DateFormatWithInternetDateTime |
                        NSISO8601DateFormatWithFractionalSeconds;
    fmt.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
    NSString *ts = [fmt stringFromDate:[NSDate date]] ?: @"";

    // Stable key order: use ordered array of pairs when serializing; dictionary
    // insertion order is preserved for NSDictionary literal / mutable builds
    // on modern Foundation when enumerated via NSJSONSerialization only if we
    // build via an ordered structure. We serialize manually for stable keys.
    return @{
        @"device_model": machine,
        @"ios_version": iosVersion,
        @"process": proc,
        @"timestamp": ts,
        @"tool": @"SwiftPeek",
        @"tool_version": @"0.1.0",
    };
}

static NSString *SPDumpDirectory(void) {
    NSString *rel = @"/var/mobile/Library/SwiftPeek/dumps";
    NSString *jb = SPJailbreakRootPrefix();
    if (jb.length) return [jb stringByAppendingString:rel];
    // Prefer /var/jb when present, else rootfs.
    NSString *rootless = [@"/var/jb" stringByAppendingString:rel];
    BOOL isDir = NO;
    if ([[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb" isDirectory:&isDir] && isDir) {
        return rootless;
    }
    return rel;
}

static NSData *SPStableJSONData(NSDictionary *root, NSError **outError) {
    // NSJSONSerialization does not guarantee key order. Build JSON by hand for
    // the top-level object using a fixed key sequence, embedding nested objects
    // via NSJSONSerialization (order within nested trees is less critical for
    // diffing than a stable header).
    NSArray *keyOrder = @[
        @"device_model", @"ios_version", @"process", @"timestamp",
        @"tool", @"tool_version", @"milestone", @"nodes"
    ];
    NSMutableString *json = [NSMutableString stringWithString:@"{\n"];
    BOOL first = YES;
    NSMutableSet *seen = [NSMutableSet set];
    for (NSString *key in keyOrder) {
        id value = root[key];
        if (!value) continue;
        [seen addObject:key];
        NSData *chunk = [NSJSONSerialization dataWithJSONObject:@{key: value}
                                                        options:0
                                                          error:outError];
        if (!chunk) return nil;
        // chunk is {"key":value} — strip braces and splice.
        NSString *s = [[NSString alloc] initWithData:chunk encoding:NSUTF8StringEncoding];
        if (s.length < 2) return nil;
        NSString *inner = [s substringWithRange:NSMakeRange(1, s.length - 2)];
        if (!first) [json appendString:@",\n"];
        first = NO;
        [json appendFormat:@"  %@", [inner stringByTrimmingCharactersInSet:
                                     [NSCharacterSet whitespaceAndNewlineCharacterSet]]];
    }
    // Any remaining keys (future-proof), sorted for stability.
    NSArray *extra = [[root.allKeys filteredArrayUsingPredicate:
                       [NSPredicate predicateWithBlock:^BOOL(NSString *k, id _) {
        return ![seen containsObject:k];
    }]] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *key in extra) {
        id value = root[key];
        if (!value) continue;
        NSData *chunk = [NSJSONSerialization dataWithJSONObject:@{key: value}
                                                        options:0
                                                          error:outError];
        if (!chunk) return nil;
        NSString *s = [[NSString alloc] initWithData:chunk encoding:NSUTF8StringEncoding];
        if (s.length < 2) return nil;
        NSString *inner = [s substringWithRange:NSMakeRange(1, s.length - 2)];
        if (!first) [json appendString:@",\n"];
        first = NO;
        [json appendFormat:@"  %@", [inner stringByTrimmingCharactersInSet:
                                     [NSCharacterSet whitespaceAndNewlineCharacterSet]]];
    }
    [json appendString:@"\n}\n"];
    return [json dataUsingEncoding:NSUTF8StringEncoding];
}

NSString *SPWriteJSONDump(NSDictionary *payload) {
    if (![NSJSONSerialization isValidJSONObject:payload]) return nil;

    NSMutableDictionary *root = [SPDumpHeader() mutableCopy];
    [payload enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        root[key] = obj;
    }];

    NSError *err = nil;
    NSData *data = SPStableJSONData(root, &err);
    if (!data) return nil;

    NSString *dir = SPDumpDirectory();
    NSError *mkErr = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:dir
                                   withIntermediateDirectories:YES
                                                    attributes:nil
                                                         error:&mkErr]) {
        return nil;
    }

    NSString *ts = root[@"timestamp"] ?: @"unknown";
    NSString *safeTs = [[ts stringByReplacingOccurrencesOfString:@":" withString:@"-"]
                        stringByReplacingOccurrencesOfString:@"." withString:@"-"];
    NSString *proc = root[@"process"] ?: @"proc";
    NSString *name = [NSString stringWithFormat:@"%@_%@.json", proc, safeTs];
    NSString *path = [dir stringByAppendingPathComponent:name];

    if (![data writeToFile:path options:NSDataWritingAtomic error:&err]) {
        return nil;
    }

    notify_post(kSPDumpNotify.UTF8String);
    return path;
}
