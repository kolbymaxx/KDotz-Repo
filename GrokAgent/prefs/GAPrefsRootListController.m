#import "GAPrefsRootListController.h"
#import <Preferences/PSSpecifier.h>
#import <notify.h>

#define kGAIdentifier @"com.kolby.grokagent"
#define kGANotifyPrefsChanged "com.kolby.grokagent/prefsChanged"

@implementation GAPrefsRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:kGAIdentifier];
    [d setObject:value forKey:specifier.properties[@"key"]];
    notify_post(kGANotifyPrefsChanged);
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:kGAIdentifier];
    id value = [d objectForKey:specifier.properties[@"key"]];
    return value ?: specifier.properties[@"default"];
}

- (void)testConnection:(PSSpecifier *)specifier {
    NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:kGAIdentifier];
    NSString *host = [d stringForKey:@"GAMCPHost"] ?: @"127.0.0.1";
    NSInteger port = [d integerForKey:@"GAMCPPort"] ?: 8090;
    NSURL *url = [NSURL URLWithString:
                  [NSString stringWithFormat:@"http://%@:%ld/health", host, (long)port]];

    [[[NSURLSession sharedSession] dataTaskWithURL:url
                                 completionHandler:^(NSData *data, NSURLResponse *r, NSError *e) {
        NSDictionary *json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        NSString *message = json[@"version"]
            ? [NSString stringWithFormat:@"Connected to %@ v%@", json[@"server"], json[@"version"]]
            : (e.localizedDescription ?: @"No response from the device control backend.");

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
