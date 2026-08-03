#import "GAGrokClient.h"
#import "GAPreferences.h"
#import "GACommon.h"

@interface GAGrokClient ()
@property (nonatomic, strong) NSURLSession *session;
@end

@implementation GAGrokClient

+ (instancetype)shared {
    static GAGrokClient *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[self alloc] init]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        cfg.timeoutIntervalForRequest = 120;   // reasoning models are not fast
        cfg.timeoutIntervalForResource = 180;
        _session = [NSURLSession sessionWithConfiguration:cfg];
    }
    return self;
}

- (void)completeWithMessages:(NSArray<NSDictionary *> *)messages
                       tools:(NSArray<NSDictionary *> *)tools
                  completion:(void (^)(NSDictionary *, NSError *))completion {

    GAPreferences *prefs = [GAPreferences shared];

    if (prefs.apiKey.length == 0) {
        completion(nil, [NSError errorWithDomain:kGAIdentifier code:401
            userInfo:@{NSLocalizedDescriptionKey: @"No xAI API key set. Add one in Settings → GrokAgent."}]);
        return;
    }

    NSURL *url = [NSURL URLWithString:
                  [prefs.baseURL stringByAppendingPathComponent:@"chat/completions"]];

    NSMutableDictionary *body = [@{
        @"model": prefs.model,
        @"messages": messages,
        @"temperature": @0.2,
    } mutableCopy];
    if (tools.count) {
        body[@"tools"] = tools;
        body[@"tool_choice"] = @"auto";
    }

    NSError *encodeError = nil;
    NSData *payload = [NSJSONSerialization dataWithJSONObject:body options:0 error:&encodeError];
    if (!payload) { completion(nil, encodeError); return; }

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [req setValue:[NSString stringWithFormat:@"Bearer %@", prefs.apiKey]
        forHTTPHeaderField:@"Authorization"];
    req.HTTPBody = payload;

    GALog(@"LLM → %@ (%lu messages, %lu tools)",
          prefs.model, (unsigned long)messages.count, (unsigned long)tools.count);

    [[self.session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) { completion(nil, error); return; }

        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![json isKindOfClass:[NSDictionary class]]) {
            completion(nil, [NSError errorWithDomain:kGAIdentifier code:-3
                userInfo:@{NSLocalizedDescriptionKey: @"Malformed response from the API."}]);
            return;
        }

        if (json[@"error"]) {
            NSString *msg = json[@"error"][@"message"] ?: @"API error";
            GAErr(@"LLM error: %@", msg);
            completion(nil, [NSError errorWithDomain:kGAIdentifier code:-4
                userInfo:@{NSLocalizedDescriptionKey: msg}]);
            return;
        }

        NSDictionary *message = [json[@"choices"] firstObject][@"message"];
        if (!message) {
            completion(nil, [NSError errorWithDomain:kGAIdentifier code:-5
                userInfo:@{NSLocalizedDescriptionKey: @"No choices returned."}]);
            return;
        }

        GALog(@"LLM ← content=%lu chars, tool_calls=%lu",
              (unsigned long)[message[@"content"] length],
              (unsigned long)[message[@"tool_calls"] count]);
        completion(message, nil);
    }] resume];
}

@end
