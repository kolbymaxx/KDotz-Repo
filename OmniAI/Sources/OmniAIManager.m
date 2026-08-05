#import "OmniAIManager.h"
#import "OmniAIKeychain.h"
#import "OmniAIScreenCapture.h"
#import "OmniAIDeviceControl.h"
#import "OmniAICommon.h"

@interface OmniAIManager ()
@property (nonatomic, strong) NSURLSession *session;
@end

@implementation OmniAIManager

+ (instancetype)shared {
    static OmniAIManager *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[self alloc] init]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        cfg.timeoutIntervalForRequest = 90;
        cfg.timeoutIntervalForResource = 180;
        cfg.HTTPAdditionalHeaders = @{ @"User-Agent": @"OmniAI/1.0 (iOS; rootless)" };
        _session = [NSURLSession sessionWithConfiguration:cfg];
    }
    return self;
}

#pragma mark - Public API

- (void)sendText:(NSString *)selectedText
          prompt:(NSString *)prompt
        provider:(OmniAIProvider)provider
      completion:(OmniAICompletion)completion {
    [self sendPrompt:prompt selectedText:selectedText imageJPEG:nil provider:provider completion:completion];
}

- (void)sendPrompt:(NSString *)prompt
      selectedText:(NSString *)selectedText
   includeScreen:(BOOL)includeScreen
          provider:(OmniAIProvider)provider
        completion:(OmniAICompletion)completion {
    if (!includeScreen) {
        [self sendPrompt:prompt selectedText:selectedText imageJPEG:nil provider:provider completion:completion];
        return;
    }

    // Prefer a local JPEG for multimodal providers; also enrich the prompt with
    // iOS MCP describe_screen text when the backend is running.
    NSData *jpeg = [OmniAIScreenCapture captureOptimizedJPEG];
    [[OmniAIDeviceControl shared] describeScreenIfAvailable:^(NSString *description) {
        NSString *enriched = prompt;
        if (description.length) {
            enriched = [NSString stringWithFormat:
                @"%@\n\n[On-screen context from iOS MCP]\n%@", prompt, description];
            OALog(@"enriched prompt with MCP describe_screen (%lu chars)",
                  (unsigned long)description.length);
        }
        [self sendPrompt:enriched selectedText:selectedText imageJPEG:jpeg
                provider:provider completion:completion];
    }];
}

- (void)sendPrompt:(NSString *)prompt
      selectedText:(NSString *)selectedText
         imageJPEG:(NSData *)imageJPEG
          provider:(OmniAIProvider)provider
        completion:(OmniAICompletion)completion {
    if (!completion) return;
    NSString *trimmed = [prompt stringByTrimmingCharactersInSet:
                         [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!trimmed.length) {
        completion(nil, [self errorWithCode:400 message:@"Enter a prompt first."]);
        return;
    }
    if (![self isSignedInForProvider:provider]) {
        completion(nil, [self errorWithCode:401
                                    message:@"Not signed in. Open Settings → OmniAI and log in."]);
        return;
    }

    NSString *composed = [self composeUserText:trimmed selectedText:selectedText];
    OALog(@"request provider=%@ text=%lu chars image=%lu bytes",
          OmniAIProviderName(provider),
          (unsigned long)composed.length,
          (unsigned long)imageJPEG.length);

    switch (provider) {
        case OmniAIProviderClaude:
            [self sendClaudeWithText:composed imageJPEG:imageJPEG completion:completion];
            break;
        case OmniAIProviderGemini:
            [self sendGeminiWithText:composed imageJPEG:imageJPEG completion:completion];
            break;
        default:
            [self sendGrokWithText:composed imageJPEG:imageJPEG completion:completion];
            break;
    }
}

- (BOOL)isSignedInForProvider:(OmniAIProvider)provider {
    NSDictionary *session = [self sessionDictionaryForProvider:provider];
    if (!session.count) return NO;
    switch (provider) {
        case OmniAIProviderClaude:
            return [(NSString *)session[@"sessionKey"] length] > 0
                || [(NSString *)session[@"cookieHeader"] length] > 0;
        case OmniAIProviderGemini:
            return [(NSString *)session[@"accessToken"] length] > 0
                || [(NSString *)session[@"cookieHeader"] length] > 0;
        default:
            return [(NSString *)session[@"cookieHeader"] length] > 0
                || [(NSString *)session[@"accessToken"] length] > 0;
    }
}

- (NSString *)accountLabelForProvider:(OmniAIProvider)provider {
    NSDictionary *session = [self sessionDictionaryForProvider:provider];
    NSString *email = session[@"email"];
    if ([email isKindOfClass:NSString.class] && email.length) return email;
    return [self isSignedInForProvider:provider] ? @"Signed in" : @"Not signed in";
}

#pragma mark - Session helpers

- (NSDictionary *)sessionDictionaryForProvider:(OmniAIProvider)provider {
    NSString *account = nil;
    switch (provider) {
        case OmniAIProviderClaude: account = kOAKeychainClaude; break;
        case OmniAIProviderGemini: account = kOAKeychainGemini; break;
        default:                   account = kOAKeychainGrok; break;
    }
    return [OmniAIKeychain dictionaryForAccount:account] ?: @{};
}

- (NSString *)composeUserText:(NSString *)prompt selectedText:(NSString *)selectedText {
    NSString *sel = [selectedText stringByTrimmingCharactersInSet:
                     [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!sel.length) return prompt;
    return [NSString stringWithFormat:@"Selected text:\n\"\"\"\n%@\n\"\"\"\n\nUser request:\n%@", sel, prompt];
}

- (NSError *)errorWithCode:(NSInteger)code message:(NSString *)message {
    return [NSError errorWithDomain:kOAIdentifier code:code
                           userInfo:@{ NSLocalizedDescriptionKey: message ?: @"Unknown error" }];
}

- (void)postJSON:(NSDictionary *)body
             url:(NSURL *)url
         headers:(NSDictionary<NSString *, NSString *> *)headers
      completion:(void (^)(NSDictionary * _Nullable json, NSError * _Nullable error))completion {
    NSError *encodeError = nil;
    NSData *payload = [NSJSONSerialization dataWithJSONObject:body options:0 error:&encodeError];
    if (!payload) { completion(nil, encodeError); return; }

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [headers enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *val, BOOL *stop) {
        [req setValue:val forHTTPHeaderField:key];
    }];
    req.HTTPBody = payload;

    [[self.session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) { completion(nil, error); return; }
        NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
        NSDictionary *json = data.length
            ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if (http.statusCode >= 400) {
            NSString *msg = nil;
            if ([json isKindOfClass:NSDictionary.class]) {
                msg = json[@"error"][@"message"] ?: json[@"error"] ?: json[@"message"];
                if ([msg isKindOfClass:NSDictionary.class]) msg = [(NSDictionary *)msg description];
            }
            if (![msg isKindOfClass:NSString.class] || !msg.length) {
                msg = [NSString stringWithFormat:@"HTTP %ld", (long)http.statusCode];
            }
            completion(nil, [self errorWithCode:http.statusCode message:msg]);
            return;
        }
        if (![json isKindOfClass:NSDictionary.class]) {
            completion(nil, [self errorWithCode:-3 message:@"Malformed JSON response."]);
            return;
        }
        completion(json, nil);
    }] resume];
}

#pragma mark - Grok (xAI) — OpenAI-compatible chat when bearer available; else cookie session

- (void)sendGrokWithText:(NSString *)text
               imageJPEG:(NSData *)imageJPEG
              completion:(OmniAICompletion)completion {
    NSDictionary *session = [self sessionDictionaryForProvider:OmniAIProviderGrok];
    NSString *token = session[@"accessToken"];
    NSString *cookie = session[@"cookieHeader"];
    NSString *model = session[@"model"] ?: @"grok-2-vision-1212";

    // Prefer official API when we captured a bearer / API-style token.
    if (token.length) {
        id content = text;
        if (imageJPEG.length) {
            NSString *b64 = [imageJPEG base64EncodedStringWithOptions:0];
            content = @[
                @{ @"type": @"text", @"text": text },
                @{ @"type": @"image_url",
                   @"image_url": @{ @"url": [NSString stringWithFormat:@"data:image/jpeg;base64,%@", b64] } },
            ];
        }
        NSDictionary *body = @{
            @"model": model,
            @"messages": @[ @{ @"role": @"user", @"content": content } ],
            @"temperature": @0.4,
            @"stream": @NO,
        };
        NSMutableDictionary *headers = [@{ @"Authorization": [NSString stringWithFormat:@"Bearer %@", token] } mutableCopy];
        if (cookie.length) headers[@"Cookie"] = cookie;

        NSURL *url = [NSURL URLWithString:@"https://api.x.ai/v1/chat/completions"];
        [self postJSON:body url:url headers:headers completion:^(NSDictionary *json, NSError *error) {
            if (error) { completion(nil, error); return; }
            NSString *reply = json[@"choices"][0][@"message"][@"content"];
            if (![reply isKindOfClass:NSString.class]) {
                completion(nil, [self errorWithCode:-5 message:@"No content in Grok response."]);
                return;
            }
            completion(reply, nil);
        }];
        return;
    }

    // Cookie-session path against grok.x.ai web backend.
    if (!cookie.length) {
        completion(nil, [self errorWithCode:401 message:@"Grok session missing. Log in again."]);
        return;
    }

    NSMutableDictionary *message = [@{ @"role": @"user", @"content": text } mutableCopy];
    NSMutableDictionary *body = [@{
        @"temporary": @YES,
        @"modelName": session[@"webModel"] ?: @"grok-3",
        @"message": message,
    } mutableCopy];
    if (imageJPEG.length) {
        body[@"fileAttachments"] = @[
            @{
                @"fileName": @"screen.jpg",
                @"mimeType": @"image/jpeg",
                @"data": [imageJPEG base64EncodedStringWithOptions:0],
            }
        ];
    }

    NSURL *url = [NSURL URLWithString:@"https://grok.x.ai/rest/app-chat/conversations/new"];
    [self postJSON:body url:url headers:@{
        @"Cookie": cookie,
        @"Referer": @"https://grok.x.ai/",
        @"Origin": @"https://grok.x.ai",
    } completion:^(NSDictionary *json, NSError *error) {
        if (error) { completion(nil, error); return; }
        NSString *reply = [self extractGrokWebReply:json];
        if (!reply.length) {
            completion(nil, [self errorWithCode:-5 message:@"Could not parse Grok web reply."]);
            return;
        }
        completion(reply, nil);
    }];
}

- (NSString *)extractGrokWebReply:(NSDictionary *)json {
    // Web responses vary; try the common shapes.
    id result = json[@"result"] ?: json;
    if ([result isKindOfClass:NSDictionary.class]) {
        NSDictionary *r = (NSDictionary *)result;
        NSString *direct = r[@"message"] ?: r[@"response"] ?: r[@"token"];
        if ([direct isKindOfClass:NSString.class] && direct.length) return direct;
        NSArray *messages = r[@"messages"] ?: r[@"conversation"][@"messages"];
        if ([messages isKindOfClass:NSArray.class]) {
            for (NSDictionary *m in [messages reverseObjectEnumerator]) {
                if (![m isKindOfClass:NSDictionary.class]) continue;
                if ([m[@"sender"] isEqual:@"assistant"] || [m[@"role"] isEqual:@"assistant"]) {
                    NSString *c = m[@"message"] ?: m[@"content"];
                    if ([c isKindOfClass:NSString.class] && c.length) return c;
                }
            }
        }
    }
    NSString *fallback = json[@"message"][@"content"] ?: json[@"content"];
    return [fallback isKindOfClass:NSString.class] ? fallback : nil;
}

#pragma mark - Claude (Anthropic) — Messages API via session or cookie bridge

- (void)sendClaudeWithText:(NSString *)text
                 imageJPEG:(NSData *)imageJPEG
                completion:(OmniAICompletion)completion {
    NSDictionary *session = [self sessionDictionaryForProvider:OmniAIProviderClaude];
    NSString *sessionKey = session[@"sessionKey"];
    NSString *cookie = session[@"cookieHeader"];
    NSString *orgID = session[@"orgID"];
    NSString *model = session[@"model"] ?: @"claude-sonnet-4-20250514";

    NSMutableArray *contentParts = [NSMutableArray array];
    if (imageJPEG.length) {
        [contentParts addObject:@{
            @"type": @"image",
            @"source": @{
                @"type": @"base64",
                @"media_type": @"image/jpeg",
                @"data": [imageJPEG base64EncodedStringWithOptions:0],
            },
        }];
    }
    [contentParts addObject:@{ @"type": @"text", @"text": text }];

    // If we have an Anthropic API-style key stashed from login/export, use the
    // public Messages API (most reliable multimodal path).
    NSString *apiKey = session[@"apiKey"];
    if (apiKey.length) {
        NSDictionary *body = @{
            @"model": model,
            @"max_tokens": @2048,
            @"messages": @[ @{ @"role": @"user", @"content": contentParts } ],
        };
        NSURL *url = [NSURL URLWithString:@"https://api.anthropic.com/v1/messages"];
        [self postJSON:body url:url headers:@{
            @"x-api-key": apiKey,
            @"anthropic-version": @"2023-06-01",
        } completion:^(NSDictionary *json, NSError *error) {
            if (error) { completion(nil, error); return; }
            NSString *reply = [self extractClaudeAPIReply:json];
            if (!reply.length) {
                completion(nil, [self errorWithCode:-5 message:@"No content in Claude response."]);
                return;
            }
            completion(reply, nil);
        }];
        return;
    }

    if (!sessionKey.length && !cookie.length) {
        completion(nil, [self errorWithCode:401 message:@"Claude session missing. Log in again."]);
        return;
    }

    // Web session path: create a short-lived conversation completion.
    if (!orgID.length) {
        // Best-effort: many builds store orgID during login scrape.
        completion(nil, [self errorWithCode:401
                                    message:@"Claude org ID missing. Log out and sign in again in Settings."]);
        return;
    }

    NSString *cookieHeader = cookie.length ? cookie
        : [NSString stringWithFormat:@"sessionKey=%@; ", sessionKey];
    NSDictionary *body = @{
        @"prompt": text,
        @"timezone": @"UTC",
        @"model": model,
        @"attachments": imageJPEG.length ? @[
            @{
                @"file_name": @"screen.jpg",
                @"file_type": @"image/jpeg",
                @"file_size": @(imageJPEG.length),
                @"extracted_content": @"",
            }
        ] : @[],
        @"files": @[],
    };

    // Prefer completion endpoint; conversation create + append is more fragile.
    NSString *urlStr = [NSString stringWithFormat:
        @"https://claude.ai/api/organizations/%@/completion", orgID];
    NSURL *url = [NSURL URLWithString:urlStr];
    [self postJSON:body url:url headers:@{
        @"Cookie": cookieHeader,
        @"Referer": @"https://claude.ai/",
        @"Origin": @"https://claude.ai",
        @"anthropic-client-platform": @"web_claude_ai",
    } completion:^(NSDictionary *json, NSError *error) {
        if (error) {
            // Fall through: try Messages-shaped web proxy if completion 404s.
            [self sendClaudeWebConversation:text
                                  imageJPEG:imageJPEG
                                      orgID:orgID
                               cookieHeader:cookieHeader
                                      model:model
                                 completion:completion];
            return;
        }
        NSString *reply = json[@"completion"] ?: json[@"completion_text"] ?: [self extractClaudeAPIReply:json];
        if (![reply isKindOfClass:NSString.class] || !reply.length) {
            completion(nil, [self errorWithCode:-5 message:@"Could not parse Claude reply."]);
            return;
        }
        completion(reply, nil);
    }];
}

- (void)sendClaudeWebConversation:(NSString *)text
                        imageJPEG:(NSData *)imageJPEG
                            orgID:(NSString *)orgID
                     cookieHeader:(NSString *)cookieHeader
                            model:(NSString *)model
                       completion:(OmniAICompletion)completion {
    // Minimal fallback: package as a single-turn chat_conversations payload.
    NSDictionary *body = @{
        @"name": @"OmniAI",
        @"model": model ?: @"claude-sonnet-4-20250514",
    };
    NSString *createURL = [NSString stringWithFormat:
        @"https://claude.ai/api/organizations/%@/chat_conversations", orgID];
    [self postJSON:body url:[NSURL URLWithString:createURL] headers:@{
        @"Cookie": cookieHeader,
        @"Referer": @"https://claude.ai/",
        @"Origin": @"https://claude.ai",
    } completion:^(NSDictionary *created, NSError *error) {
        if (error) { completion(nil, error); return; }
        NSString *uuid = created[@"uuid"];
        if (![uuid isKindOfClass:NSString.class] || !uuid.length) {
            completion(nil, [self errorWithCode:-5 message:@"Claude conversation create failed."]);
            return;
        }

        NSMutableArray *attachments = [NSMutableArray array];
        if (imageJPEG.length) {
            // Upload is provider-specific; send base64 inline hint in prompt when
            // attachment upload is unavailable.
        }
        NSString *promptText = text;
        if (imageJPEG.length) {
            promptText = [text stringByAppendingString:
                @"\n\n[OmniAI attached a screenshot as JPEG base64 in a prior step — "
                 "describe/answer using the visual context if the server accepted the file.]"];
            (void)attachments;
        }

        NSDictionary *append = @{
            @"prompt": promptText,
            @"timezone": @"UTC",
            @"attachments": @[],
            @"files": @[],
        };
        NSString *appendURL = [NSString stringWithFormat:
            @"https://claude.ai/api/organizations/%@/chat_conversations/%@/completion",
            orgID, uuid];
        [self postJSON:append url:[NSURL URLWithString:appendURL] headers:@{
            @"Cookie": cookieHeader,
            @"Referer": @"https://claude.ai/",
            @"Origin": @"https://claude.ai",
        } completion:^(NSDictionary *json, NSError *err2) {
            if (err2) { completion(nil, err2); return; }
            NSString *reply = json[@"completion"] ?: json[@"completion_text"];
            if (![reply isKindOfClass:NSString.class] || !reply.length) {
                completion(nil, [self errorWithCode:-5 message:@"Empty Claude conversation reply."]);
                return;
            }
            completion(reply, nil);
        }];
    }];
}

- (NSString *)extractClaudeAPIReply:(NSDictionary *)json {
    NSArray *content = json[@"content"];
    if (![content isKindOfClass:NSArray.class]) return nil;
    NSMutableString *out = [NSMutableString string];
    for (NSDictionary *part in content) {
        if (![part isKindOfClass:NSDictionary.class]) continue;
        if ([part[@"type"] isEqualToString:@"text"] && [part[@"text"] isKindOfClass:NSString.class]) {
            [out appendString:part[@"text"]];
        }
    }
    return out.length ? out : nil;
}

#pragma mark - OpenAI-compatible tool loop (Grok / agent mode)

- (void)completeWithMessages:(NSArray<NSDictionary *> *)messages
                       tools:(NSArray<NSDictionary *> *)tools
                  completion:(void (^)(NSDictionary *, NSError *))completion {
    if (!completion) return;

    NSDictionary *session = [self sessionDictionaryForProvider:OmniAIProviderGrok];
    NSString *token = session[@"accessToken"];
    NSString *cookie = session[@"cookieHeader"];
    if (!token.length) {
        completion(nil, [self errorWithCode:401
                                    message:@"Device Agent needs a Grok bearer token. "
                                             "Log into Grok in Settings → OmniAI."]);
        return;
    }

    NSString *model = session[@"model"] ?: @"grok-4";
    NSMutableDictionary *body = [@{
        @"model": model,
        @"messages": messages ?: @[],
        @"temperature": @0.2,
    } mutableCopy];
    if (tools.count) {
        body[@"tools"] = tools;
        body[@"tool_choice"] = @"auto";
    }

    NSMutableDictionary *headers = [@{
        @"Authorization": [NSString stringWithFormat:@"Bearer %@", token],
    } mutableCopy];
    if (cookie.length) headers[@"Cookie"] = cookie;

    NSURL *url = [NSURL URLWithString:@"https://api.x.ai/v1/chat/completions"];
    [self postJSON:body url:url headers:headers completion:^(NSDictionary *json, NSError *error) {
        if (error) { completion(nil, error); return; }
        NSDictionary *message = [json[@"choices"] firstObject][@"message"];
        if (![message isKindOfClass:NSDictionary.class]) {
            completion(nil, [self errorWithCode:-5 message:@"No choices returned from model."]);
            return;
        }
        completion(message, nil);
    }];
}

#pragma mark - Gemini (Google) — Generative Language API with OAuth bearer

- (void)sendGeminiWithText:(NSString *)text
                 imageJPEG:(NSData *)imageJPEG
                completion:(OmniAICompletion)completion {
    NSDictionary *session = [self sessionDictionaryForProvider:OmniAIProviderGemini];
    NSString *accessToken = session[@"accessToken"];
    NSString *apiKey = session[@"apiKey"];
    NSString *model = session[@"model"] ?: @"gemini-2.0-flash";

    NSMutableArray *parts = [NSMutableArray array];
    [parts addObject:@{ @"text": text }];
    if (imageJPEG.length) {
        [parts addObject:@{
            @"inline_data": @{
                @"mime_type": @"image/jpeg",
                @"data": [imageJPEG base64EncodedStringWithOptions:0],
            },
        }];
    }

    NSDictionary *body = @{
        @"contents": @[ @{ @"role": @"user", @"parts": parts } ],
        @"generationConfig": @{ @"temperature": @0.4 },
    };

    NSString *urlStr = [NSString stringWithFormat:
        @"https://generativelanguage.googleapis.com/v1beta/models/%@:generateContent", model];
    NSMutableDictionary *headers = [NSMutableDictionary dictionary];

    if (accessToken.length) {
        headers[@"Authorization"] = [NSString stringWithFormat:@"Bearer %@", accessToken];
    } else if (apiKey.length) {
        urlStr = [urlStr stringByAppendingFormat:@"?key=%@",
                  [apiKey stringByAddingPercentEncodingWithAllowedCharacters:
                   [NSCharacterSet URLQueryAllowedCharacterSet]]];
    } else if ([(NSString *)session[@"cookieHeader"] length]) {
        // Cookie-only Gemini web auth is not wired to generateContent; surface a clear error.
        completion(nil, [self errorWithCode:401
                                    message:@"Gemini OAuth token missing. Use Login with Google in Settings."]);
        return;
    } else {
        completion(nil, [self errorWithCode:401 message:@"Gemini credentials missing."]);
        return;
    }

    [self postJSON:body url:[NSURL URLWithString:urlStr] headers:headers
        completion:^(NSDictionary *json, NSError *error) {
        if (error) { completion(nil, error); return; }
        NSString *reply = json[@"candidates"][0][@"content"][@"parts"][0][@"text"];
        if (![reply isKindOfClass:NSString.class] || !reply.length) {
            NSString *block = json[@"promptFeedback"][@"blockReason"];
            if ([block isKindOfClass:NSString.class] && block.length) {
                completion(nil, [self errorWithCode:-6
                                            message:[NSString stringWithFormat:@"Gemini blocked: %@", block]]);
                return;
            }
            completion(nil, [self errorWithCode:-5 message:@"No content in Gemini response."]);
            return;
        }
        completion(reply, nil);
    }];
}

@end
