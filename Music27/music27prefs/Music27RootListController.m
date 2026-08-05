#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <notify.h>

@interface Music27RootListController : PSListController
@end

@implementation Music27RootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

- (void)clearPins {
    notify_post("com.music27.tweak/ClearPins");
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"Music27"
                                            message:@"All pins cleared. Relaunch Music to refresh the Library header."
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
