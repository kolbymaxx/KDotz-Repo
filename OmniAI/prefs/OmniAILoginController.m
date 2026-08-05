#import "OmniAILoginController.h"
#import "OmniAIKeychain.h"
#import "OmniAICommon.h"
#import <WebKit/WebKit.h>

@interface OmniAILoginController ()
@property (nonatomic) OmniAILoginProvider provider;
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@end

@implementation OmniAILoginController

- (instancetype)initWithProvider:(OmniAILoginProvider)provider {
    if ((self = [super init])) {
        _provider = provider;
    }
    return self;
}

- (NSString *)titleForProvider {
    switch (self.provider) {
        case OmniAILoginProviderClaude: return @"Sign in to Claude";
        case OmniAILoginProviderGemini: return @"Sign in to Google";
        default: return @"Sign in to Grok";
    }
}

- (NSURL *)startURL {
    switch (self.provider) {
        case OmniAILoginProviderClaude:
            return [NSURL URLWithString:@"https://claude.ai/login"];
        case OmniAILoginProviderGemini:
            // Consumer Gemini first; OAuth token scrape runs after cookies land.
            return [NSURL URLWithString:@"https://gemini.google.com/app"];
        default:
            return [NSURL URLWithString:@"https://grok.x.ai/"];
    }
}

- (NSString *)keychainAccount {
    switch (self.provider) {
        case OmniAILoginProviderClaude: return kOAKeychainClaude;
        case OmniAILoginProviderGemini: return kOAKeychainGemini;
        default: return kOAKeychainGrok;
    }
}

- (NSArray<NSString *> *)cookieDomains {
    switch (self.provider) {
        case OmniAILoginProviderClaude:
            return @[ @"claude.ai", @".claude.ai", @"anthropic.com" ];
        case OmniAILoginProviderGemini:
            return @[ @"google.com", @".google.com", @"gemini.google.com",
                      @"accounts.google.com", @"googleapis.com" ];
        default:
            return @[ @"grok.x.ai", @".x.ai", @"x.ai", @"x.com", @".x.com", @"accounts.x.ai" ];
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = [self titleForProvider];
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                      target:self
                                                      action:@selector(cancel)];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"Done"
                                         style:UIBarButtonItemStyleDone
                                        target:self
                                        action:@selector(finishLogin)];

    WKWebViewConfiguration *cfg = [WKWebViewConfiguration new];
    cfg.processPool = [WKProcessPool new];
    cfg.websiteDataStore = [WKWebsiteDataStore defaultDataStore];

    self.webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:cfg];
    self.webView.navigationDelegate = self;
    self.webView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.webView];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.spinner.hidesWhenStopped = YES;
    [self.view addSubview:self.spinner];

    [NSLayoutConstraint activateConstraints:@[
        [self.webView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.webView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.webView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.webView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.spinner.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
    ]];

    [self.spinner startAnimating];
    [self.webView loadRequest:[NSURLRequest requestWithURL:[self startURL]]];
}

- (void)cancel {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)finishLogin {
    [self.spinner startAnimating];
    [self captureSessionWithCompletion:^(BOOL ok, NSString *detail) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.spinner stopAnimating];
            if (!ok) {
                UIAlertController *alert =
                    [UIAlertController alertControllerWithTitle:@"Login incomplete"
                                                        message:detail ?: @"Could not capture a session. Stay signed in, then tap Done."
                                                 preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
                return;
            }
            if (detail.length) {
                UIAlertController *alert =
                    [UIAlertController alertControllerWithTitle:@"Signed in"
                                                        message:detail
                                                 preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
                    [self dismissViewControllerAnimated:YES completion:nil];
                }]];
                [self presentViewController:alert animated:YES completion:nil];
                return;
            }
            [self dismissViewControllerAnimated:YES completion:nil];
        });
    }];
}

#pragma mark - Cookie / token capture

- (void)captureSessionWithCompletion:(void (^)(BOOL ok, NSString *detail))completion {
    WKHTTPCookieStore *store = self.webView.configuration.websiteDataStore.httpCookieStore;
    [store getAllCookies:^(NSArray<NSHTTPCookie *> *cookies) {
        NSMutableArray<NSString *> *parts = [NSMutableArray array];
        NSMutableDictionary *named = [NSMutableDictionary dictionary];
        NSArray *domains = [self cookieDomains];

        for (NSHTTPCookie *c in cookies) {
            BOOL match = NO;
            for (NSString *d in domains) {
                if ([c.domain isEqualToString:d] || [c.domain hasSuffix:d] ||
                    [d hasSuffix:c.domain]) {
                    match = YES;
                    break;
                }
            }
            if (!match) continue;
            [parts addObject:[NSString stringWithFormat:@"%@=%@", c.name, c.value]];
            named[c.name] = c.value;
        }

        NSString *cookieHeader = [parts componentsJoinedByString:@"; "];
        if (!cookieHeader.length) {
            if (completion) completion(NO, @"No session cookies found yet.");
            return;
        }

        NSMutableDictionary *session = [@{
            @"cookieHeader": cookieHeader,
            @"capturedAt": @([[NSDate date] timeIntervalSince1970]),
        } mutableCopy];

        switch (self.provider) {
            case OmniAILoginProviderClaude: {
                NSString *sessionKey = named[@"sessionKey"];
                if (sessionKey.length) session[@"sessionKey"] = sessionKey;
                [self enrichClaudeSession:session completion:completion];
                return;
            }
            case OmniAILoginProviderGemini: {
                [self enrichGeminiSession:session completion:completion];
                return;
            }
            default: {
                // Try to pull a bearer-like token from the page if present.
                [self.webView evaluateJavaScript:
                 @"(function(){try{return localStorage.getItem('accessToken')||localStorage.getItem('token')||'';}catch(e){return '';}})()"
                               completionHandler:^(id result, NSError *error) {
                    if ([result isKindOfClass:NSString.class] && [result length]) {
                        session[@"accessToken"] = result;
                    }
                    // Also accept xAI API keys pasted into the page URL query later.
                    BOOL ok = [OmniAIKeychain setDictionary:session forAccount:[self keychainAccount]];
                    if (completion) completion(ok, ok ? nil : @"Keychain write failed.");
                }];
                return;
            }
        }
    }];
}

- (void)enrichClaudeSession:(NSMutableDictionary *)session
                 completion:(void (^)(BOOL, NSString *))completion {
    NSString *cookie = session[@"cookieHeader"];
    NSMutableURLRequest *req = [NSMutableURLRequest
        requestWithURL:[NSURL URLWithString:@"https://claude.ai/api/organizations"]];
    [req setValue:cookie forHTTPHeaderField:@"Cookie"];
    [req setValue:@"https://claude.ai/" forHTTPHeaderField:@"Referer"];

    [[[NSURLSession sharedSession] dataTaskWithRequest:req
                                     completionHandler:^(NSData *data, NSURLResponse *r, NSError *e) {
        if (data.length) {
            id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            NSDictionary *org = nil;
            if ([json isKindOfClass:NSArray.class] && [json count]) {
                org = json[0];
            } else if ([json isKindOfClass:NSDictionary.class]) {
                NSArray *arr = json[@"organizations"] ?: json[@"data"];
                if ([arr isKindOfClass:NSArray.class] && arr.count) org = arr[0];
            }
            if ([org isKindOfClass:NSDictionary.class]) {
                NSString *orgID = org[@"uuid"] ?: org[@"id"];
                if ([orgID isKindOfClass:NSString.class] && orgID.length) {
                    session[@"orgID"] = orgID;
                }
                NSString *email = org[@"organization_name"] ?: org[@"name"];
                if ([email isKindOfClass:NSString.class]) session[@"email"] = email;
            }
        }

        if (!session[@"sessionKey"] && !session[@"orgID"]) {
            // Still persist cookies — org scrape can fail while session is valid.
        }
        BOOL ok = [OmniAIKeychain setDictionary:session forAccount:kOAKeychainClaude];
        NSString *detail = ok ? nil : @"Keychain write failed.";
        if (ok && !session[@"orgID"]) {
            detail = @"Signed in, but org ID was not found. Some Claude features may need a re-login.";
        }
        if (completion) completion(ok, detail);
    }] resume];
}

- (void)enrichGeminiSession:(NSMutableDictionary *)session
                 completion:(void (^)(BOOL, NSString *))completion {
    // Pull OAuth access token from the Gemini/Google page when available.
    NSString *js =
        @"(function(){"
         "try{"
           "var keys=['access_token','accessToken','oauthToken'];"
           "for (var i=0;i<localStorage.length;i++){"
             "var k=localStorage.key(i);"
             "var v=localStorage.getItem(k)||'';"
             "if (/access_token|ya29\\./i.test(k+' '+v)) return v.match(/ya29\\.[\\w\\-.]+/) ? v.match(/ya29\\.[\\w\\-.]+/)[0] : v;"
           "}"
           "var m=document.cookie.match(/ya29\\.[\\w\\-.]+/); if(m) return m[0];"
           "return '';"
         "}catch(e){return '';}"
         "})()";

    [self.webView evaluateJavaScript:js completionHandler:^(id result, NSError *error) {
        if ([result isKindOfClass:NSString.class] && [result length] > 10) {
            session[@"accessToken"] = result;
        }

        // Fallback: Google OAuth embedded token endpoint via gapi-ish patterns is
        // unreliable. If we only have cookies, still store them and note that
        // generateContent needs a bearer or API key.
        if (!session[@"accessToken"]) {
            // Offer a soft path: user can paste a Google AI Studio key later via
            // the "Paste API key" button in RootListController. Cookies alone
            // mark "signed in" for UI, but Manager requires accessToken/apiKey.
            session[@"email"] = @"Google session";
        }

        BOOL ok = [OmniAIKeychain setDictionary:session forAccount:kOAKeychainGemini];
        if (completion) {
            if (ok && !session[@"accessToken"]) {
                completion(YES, @"Google cookies saved. For Gemini API calls, also paste an AI Studio API key in Settings (or complete OAuth so an access token is captured).");
            } else {
                completion(ok, ok ? nil : @"Keychain write failed.");
            }
        }
    }];
}

#pragma mark - WKNavigationDelegate

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    [self.spinner stopAnimating];

    // Gemini: if redirected to a URL with access_token fragment, capture it.
    NSURL *url = webView.URL;
    NSString *frag = url.fragment;
    if (self.provider == OmniAILoginProviderGemini && frag.length) {
        NSURLComponents *comp = [NSURLComponents new];
        comp.query = frag;
        for (NSURLQueryItem *item in comp.queryItems) {
            if ([item.name isEqualToString:@"access_token"] && item.value.length) {
                NSMutableDictionary *session = [[OmniAIKeychain dictionaryForAccount:kOAKeychainGemini] mutableCopy]
                    ?: [NSMutableDictionary dictionary];
                session[@"accessToken"] = item.value;
                session[@"capturedAt"] = @([[NSDate date] timeIntervalSince1970]);
                [OmniAIKeychain setDictionary:session forAccount:kOAKeychainGemini];
            }
        }
    }
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self.spinner stopAnimating];
}

@end
