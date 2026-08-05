#import "GADeviceControl.h"
#import "GAPreferences.h"
#import "GACommon.h"

static NSString *const kGAMCPProtocolVersion = @"2025-11-25";

@interface GADeviceControl ()
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, copy)   NSString *sessionID;   // Mcp-Session-Id, if the server issues one
@property (nonatomic)         BOOL initialized;
@property (nonatomic)         NSInteger nextID;
@end

@implementation GADeviceControl

+ (instancetype)shared {
    static GADeviceControl *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[self alloc] init]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        cfg.timeoutIntervalForRequest = 30;
        cfg.timeoutIntervalForResource = 60;
        _session = [NSURLSession sessionWithConfiguration:cfg];
        _nextID = 1;
    }
    return self;
}

#pragma mark - Health

- (void)checkHealth:(void (^)(BOOL, NSString *))completion {
    GAPreferences *p = [GAPreferences shared];
    NSString *urlStr = [NSString stringWithFormat:@"http://%@:%ld/health", p.mcpHost, (long)p.mcpPort];
    NSURL *url = [NSURL URLWithString:urlStr];
    [[self.session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (err || !data) {
            GAErr(@"MCP health check failed: %@", err.localizedDescription);
            if (completion) completion(NO, nil);
            return;
        }
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        BOOL ok = [json[@"status"] isEqualToString:@"ok"];
        GALog(@"MCP health: %@ (v%@)", ok ? @"ok" : @"bad", json[@"version"]);
        if (completion) completion(ok, json[@"version"]);
    }] resume];
}

#pragma mark - JSON-RPC plumbing

- (NSMutableURLRequest *)requestWithBody:(NSDictionary *)body {
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[GAPreferences shared].mcpURL];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [req setValue:@"application/json, text/event-stream" forHTTPHeaderField:@"Accept"];
    [req setValue:kGAMCPProtocolVersion forHTTPHeaderField:@"MCP-Protocol-Version"];
    if (self.sessionID) [req setValue:self.sessionID forHTTPHeaderField:@"Mcp-Session-Id"];
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    return req;
}

/// The server may answer with plain JSON or an SSE frame. Handle both.
- (NSDictionary *)parseResponseData:(NSData *)data response:(NSURLResponse *)response {
    if (!data.length) return nil;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (json) return json;

    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        if (![line hasPrefix:@"data:"]) continue;
        NSString *payload = [[line substringFromIndex:5]
                             stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSDictionary *frame = [NSJSONSerialization JSONObjectWithData:
                               [payload dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        if (frame) return frame;
    }
    return nil;
}

- (void)sendMethod:(NSString *)method
            params:(NSDictionary *)params
        completion:(void (^)(NSDictionary *result, NSError *error))completion {

    NSMutableDictionary *body = [@{
        @"jsonrpc": @"2.0",
        @"id": @(self.nextID++),
        @"method": method,
    } mutableCopy];
    if (params) body[@"params"] = params;

    GALog(@"MCP → %@ %@", method, params[@"name"] ?: @"");

    [[self.session dataTaskWithRequest:[self requestWithBody:body]
                     completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) { if (completion) completion(nil, error); return; }

        if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
            NSString *sid = [(NSHTTPURLResponse *)response allHeaderFields][@"Mcp-Session-Id"];
            if (sid.length) self.sessionID = sid;
        }

        NSDictionary *json = [self parseResponseData:data response:response];
        if (!json) {
            if (completion) completion(nil, [NSError errorWithDomain:kGAIdentifier code:-1
                userInfo:@{NSLocalizedDescriptionKey: @"Unparseable MCP response"}]);
            return;
        }
        if (json[@"error"]) {
            NSString *msg = json[@"error"][@"message"] ?: @"MCP error";
            if (completion) completion(nil, [NSError errorWithDomain:kGAIdentifier code:-2
                userInfo:@{NSLocalizedDescriptionKey: msg}]);
            return;
        }
        if (completion) completion(json[@"result"], nil);
    }] resume];
}

#pragma mark - Handshake

- (void)ensureInitialized:(void (^)(BOOL, NSError *))completion {
    if (self.initialized) { if (completion) completion(YES, nil); return; }

    NSDictionary *params = @{
        @"protocolVersion": kGAMCPProtocolVersion,
        @"capabilities": @{},
        @"clientInfo": @{@"name": @"GrokAgent", @"version": @"0.1.0"},
    };
    [self sendMethod:@"initialize" params:params completion:^(NSDictionary *result, NSError *error) {
        if (error) {
            GAErr(@"MCP initialize failed: %@", error.localizedDescription);
            if (completion) completion(NO, error);
            return;
        }
        self.initialized = YES;
        GALog(@"MCP initialized: %@", result[@"serverInfo"]);
        // Best-effort notification; server does not reply to it.
        [self sendMethod:@"notifications/initialized" params:nil completion:nil];
        if (completion) completion(YES, nil);
    }];
}

#pragma mark - Tools

- (void)listToolsWithCompletion:(void (^)(NSArray<NSDictionary *> *, NSError *))completion {
    [self ensureInitialized:^(BOOL ok, NSError *error) {
        if (!ok) { if (completion) completion(nil, error); return; }
        [self sendMethod:@"tools/list" params:nil completion:^(NSDictionary *result, NSError *err) {
            if (completion) completion(result[@"tools"], err);
        }];
    }];
}

- (void)callTool:(NSString *)name
       arguments:(NSDictionary *)arguments
      completion:(void (^)(NSString *, NSError *))completion {

    [self ensureInitialized:^(BOOL ok, NSError *error) {
        if (!ok) { if (completion) completion(nil, error); return; }

        NSDictionary *params = @{ @"name": name, @"arguments": arguments ?: @{} };
        [self sendMethod:@"tools/call" params:params completion:^(NSDictionary *result, NSError *err) {
            if (err) { if (completion) completion(nil, err); return; }
            if (completion) completion([self flattenToolResult:result], nil);
        }];
    }];
}

/// MCP tool results are an array of content blocks. Collapse them to a string the
/// model can read. Image blocks are summarised rather than inlined — feeding raw
/// base64 screenshots back through the text channel would blow the context window.
- (NSString *)flattenToolResult:(NSDictionary *)result {
    NSArray *content = result[@"content"];
    if (![content isKindOfClass:[NSArray class]]) {
        NSData *d = [NSJSONSerialization dataWithJSONObject:result ?: @{} options:0 error:nil];
        return [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
    }

    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSDictionary *block in content) {
        NSString *type = block[@"type"];
        if ([type isEqualToString:@"text"]) {
            [parts addObject:block[@"text"] ?: @""];
        } else if ([type isEqualToString:@"image"]) {
            NSString *b64 = block[@"data"] ?: @"";
            [parts addObject:[NSString stringWithFormat:@"[image: %@, %lu bytes base64]",
                              block[@"mimeType"] ?: @"image", (unsigned long)b64.length]];
        }
    }
    return [parts componentsJoinedByString:@"\n"];
}

@end
