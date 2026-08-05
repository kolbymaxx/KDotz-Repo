#import "OmniAIRootListController.h"
#import "OmniAILoginController.h"
#import "OmniAIKeychain.h"
#import "OmniAICommon.h"
#import <Preferences/PSSpecifier.h>
#import <notify.h>

@implementation OmniAIRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadSpecifiers];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:kOAIdentifier];
    [d setObject:value forKey:specifier.properties[@"key"]];
    [d synchronize];
    notify_post(kOANotifyPrefsChanged);
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:kOAIdentifier];
    id value = [d objectForKey:specifier.properties[@"key"]];
    return value ?: specifier.properties[@"default"];
}

#pragma mark - Account status footers

- (NSString *)grokStatus {
    return [self statusForAccount:kOAKeychainGrok label:@"Grok"];
}

- (NSString *)claudeStatus {
    return [self statusForAccount:kOAKeychainClaude label:@"Claude"];
}

- (NSString *)geminiStatus {
    return [self statusForAccount:kOAKeychainGemini label:@"Gemini"];
}

- (NSString *)statusForAccount:(NSString *)account label:(NSString *)label {
    NSDictionary *session = [OmniAIKeychain dictionaryForAccount:account];
    if (!session.count) return [NSString stringWithFormat:@"%@ · Not signed in", label];
    NSString *email = session[@"email"];
    if ([email isKindOfClass:NSString.class] && email.length) {
        return [NSString stringWithFormat:@"%@ · %@", label, email];
    }
    if ([(NSString *)session[@"accessToken"] length] ||
        [(NSString *)session[@"sessionKey"] length] ||
        [(NSString *)session[@"cookieHeader"] length] ||
        [(NSString *)session[@"apiKey"] length]) {
        return [NSString stringWithFormat:@"%@ · Signed in", label];
    }
    return [NSString stringWithFormat:@"%@ · Not signed in", label];
}

#pragma mark - Login actions

- (void)loginGrok:(PSSpecifier *)specifier {
    [self presentLogin:OmniAILoginProviderGrok];
}

- (void)loginClaude:(PSSpecifier *)specifier {
    [self presentLogin:OmniAILoginProviderClaude];
}

- (void)loginGemini:(PSSpecifier *)specifier {
    [self presentLogin:OmniAILoginProviderGemini];
}

- (void)presentLogin:(OmniAILoginProvider)provider {
    OmniAILoginController *login = [[OmniAILoginController alloc] initWithProvider:provider];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:login];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)logoutGrok:(PSSpecifier *)specifier {
    [OmniAIKeychain deleteAccount:kOAKeychainGrok];
    [self reloadSpecifiers];
}

- (void)logoutClaude:(PSSpecifier *)specifier {
    [OmniAIKeychain deleteAccount:kOAKeychainClaude];
    [self reloadSpecifiers];
}

- (void)logoutGemini:(PSSpecifier *)specifier {
    [OmniAIKeychain deleteAccount:kOAKeychainGemini];
    [self reloadSpecifiers];
}

- (void)pasteGeminiAPIKey:(PSSpecifier *)specifier {
    [self promptForAPIKeyAccount:kOAKeychainGemini title:@"Gemini API Key"
                     placeholder:@"AIza…"];
}

- (void)pasteGrokAPIKey:(PSSpecifier *)specifier {
    [self promptForAPIKeyAccount:kOAKeychainGrok title:@"xAI / Grok API Key"
                     placeholder:@"xai-…"];
}

- (void)promptForAPIKeyAccount:(NSString *)account
                         title:(NSString *)title
                   placeholder:(NSString *)placeholder {
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:title
                                            message:@"Stored in the Keychain (AfterFirstUnlock). Optional fallback if web login does not yield a bearer token."
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = placeholder;
        tf.secureTextEntry = YES;
        tf.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *key = alert.textFields.firstObject.text;
        key = [key stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!key.length) return;
        NSMutableDictionary *session = [[OmniAIKeychain dictionaryForAccount:account] mutableCopy]
            ?: [NSMutableDictionary dictionary];
        if ([account isEqualToString:kOAKeychainGrok]) {
            session[@"accessToken"] = key;
        } else {
            session[@"apiKey"] = key;
        }
        session[@"capturedAt"] = @([[NSDate date] timeIntervalSince1970]);
        [OmniAIKeychain setDictionary:session forAccount:account];
        [self reloadSpecifiers];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - iOS MCP

- (void)testMCP:(PSSpecifier *)specifier {
    NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:kOAIdentifier];
    NSString *host = [d stringForKey:kOAPrefMCPHost] ?: @"127.0.0.1";
    NSInteger port = [d integerForKey:kOAPrefMCPPort] ?: 8090;
    if (port == 0) {
        id raw = [d objectForKey:kOAPrefMCPPort];
        if ([raw respondsToSelector:@selector(integerValue)]) port = [raw integerValue];
        if (port == 0) port = 8090;
    }

    NSURL *url = [NSURL URLWithString:
                  [NSString stringWithFormat:@"http://%@:%ld/health", host, (long)port]];

    [[[NSURLSession sharedSession] dataTaskWithURL:url
                                 completionHandler:^(NSData *data, NSURLResponse *r, NSError *e) {
        NSDictionary *json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        NSString *message = [json[@"status"] isEqualToString:@"ok"]
            ? [NSString stringWithFormat:@"Connected to iOS MCP%@%@.",
               json[@"server"] ? [NSString stringWithFormat:@" (%@)", json[@"server"]] : @"",
               json[@"version"] ? [NSString stringWithFormat:@" v%@", json[@"version"]] : @""]
            : (e.localizedDescription ?: @"No response. Install witchan's iOS MCP and start its service.");

        dispatch_async(dispatch_get_main_queue(), ^{
            UIAlertController *alert =
                [UIAlertController alertControllerWithTitle:@"Device Control"
                                                    message:message
                                             preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        });
    }] resume];
}

- (void)respring:(PSSpecifier *)specifier {
    [[NSFileManager defaultManager] createFileAtPath:@"/var/mobile/.respring" contents:nil attributes:nil];
    notify_post("com.apple.language.changed");
}

@end
