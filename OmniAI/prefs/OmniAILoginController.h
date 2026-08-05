#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

typedef NS_ENUM(NSInteger, OmniAILoginProvider) {
    OmniAILoginProviderGrok = 0,
    OmniAILoginProviderClaude = 1,
    OmniAILoginProviderGemini = 2,
};

/// In-prefs WKWebView login that captures cookies / OAuth tokens into the Keychain.
@interface OmniAILoginController : UIViewController <WKNavigationDelegate>

- (instancetype)initWithProvider:(OmniAILoginProvider)provider;

@end
