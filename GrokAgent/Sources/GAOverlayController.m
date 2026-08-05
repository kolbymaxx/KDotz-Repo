#import "GAOverlayController.h"
#import "GAVoiceManager.h"
#import "GAPreferences.h"
#import "GACommon.h"

@interface GAOverlayController ()
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UITextField *inputField;
@property (nonatomic, strong) UIView *card;
@end

@implementation GAOverlayController

+ (instancetype)shared {
    static GAOverlayController *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[self alloc] init]; });
    return s;
}

- (void)present {
    if (self.window) { [self.inputField becomeFirstResponder]; return; }

    // Failsafe. We put a window above UIWindowLevelAlert inside SpringBoard;
    // if that ever wedges the UI, the device is unusable without SSH. So we
    // drop a breadcrumb before creating the window and clear it once we have
    // survived. A breadcrumb found still present at %ctor means the last
    // attempt did not come back — the overlay stays disabled until the user
    // re-enables it in Settings.
    if ([GAPreferences shared].overlaySafeMode) {
        GAErr(@"overlay suppressed — safe mode is on (re-enable in Settings)");
        return;
    }
    [GAOverlayController armBreadcrumb];

    [GAAgentOrchestrator shared].observer = self;

    UIWindowScene *scene = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]] && s.activationState == UISceneActivationStateForegroundActive) {
            scene = (UIWindowScene *)s; break;
        }
    }
    self.window = scene ? [[UIWindow alloc] initWithWindowScene:scene]
                        : [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.windowLevel = UIWindowLevelAlert + 100;
    self.window.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35];
    self.window.rootViewController = [UIViewController new];

    UIView *root = self.window.rootViewController.view;

    UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:
        [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThickMaterialDark]];
    blur.translatesAutoresizingMaskIntoConstraints = NO;
    blur.layer.cornerRadius = 22;
    blur.layer.cornerCurve = kCACornerCurveContinuous;
    blur.clipsToBounds = YES;
    [root addSubview:blur];
    self.card = blur;

    self.statusLabel = [UILabel new];
    self.statusLabel.text = @"Ask GrokAgent";
    self.statusLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    self.statusLabel.textColor = [UIColor secondaryLabelColor];
    self.statusLabel.numberOfLines = 3;
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;

    self.inputField = [UITextField new];
    self.inputField.placeholder = @"What should I do?";
    self.inputField.font = [UIFont systemFontOfSize:18];
    self.inputField.textColor = [UIColor labelColor];
    self.inputField.returnKeyType = UIReturnKeyGo;
    self.inputField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.inputField.translatesAutoresizingMaskIntoConstraints = NO;
    [self.inputField addTarget:self action:@selector(submit)
              forControlEvents:UIControlEventEditingDidEndOnExit];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeClose];
    close.translatesAutoresizingMaskIntoConstraints = NO;
    [close addTarget:self action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];

    UIView *content = blur.contentView;
    [content addSubview:self.statusLabel];
    [content addSubview:self.inputField];
    [content addSubview:close];

    [NSLayoutConstraint activateConstraints:@[
        [blur.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:16],
        [blur.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-16],
        [blur.bottomAnchor constraintEqualToAnchor:root.safeAreaLayoutGuide.bottomAnchor constant:-24],

        [self.statusLabel.topAnchor constraintEqualToAnchor:content.topAnchor constant:14],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:18],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:close.leadingAnchor constant:-10],

        [close.topAnchor constraintEqualToAnchor:content.topAnchor constant:12],
        [close.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-14],

        [self.inputField.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:8],
        [self.inputField.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:18],
        [self.inputField.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-18],
        [self.inputField.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-16],
    ]];

    self.window.hidden = NO;
    [self.window makeKeyAndVisible];
    [self.inputField becomeFirstResponder];
    [GAOverlayController clearBreadcrumb];
    GALog(@"overlay presented");
}

#pragma mark - Crash breadcrumb

+ (NSString *)breadcrumbPath {
    return [NSTemporaryDirectory() stringByAppendingPathComponent:@"grokagent-overlay.lock"];
}

+ (void)armBreadcrumb {
    [@"1" writeToFile:[self breadcrumbPath] atomically:YES
             encoding:NSUTF8StringEncoding error:nil];
}

+ (void)clearBreadcrumb {
    [[NSFileManager defaultManager] removeItemAtPath:[self breadcrumbPath] error:nil];
}

/// Called once from %ctor. YES means the previous overlay attempt never
/// finished presenting.
+ (BOOL)consumeStaleBreadcrumb {
    NSString *path = [self breadcrumbPath];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return NO;
    [self clearBreadcrumb];
    return YES;
}

- (void)submit {
    NSString *prompt = [self.inputField.text stringByTrimmingCharactersInSet:
                        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!prompt.length) { [self dismiss]; return; }
    self.inputField.text = @"";
    [self.inputField resignFirstResponder];
    [[GAAgentOrchestrator shared] runWithPrompt:prompt];
}

- (void)dismiss {
    [self.inputField resignFirstResponder];
    self.window.hidden = YES;
    self.window = nil;
    GALog(@"overlay dismissed");
}

#pragma mark - GAAgentObserver

- (void)agentDidChangeState:(GAAgentState)state {
    NSString *text = @"Ask GrokAgent";
    switch (state) {
        case GAAgentStateThinking: text = @"Thinking…"; break;
        case GAAgentStateActing:   text = @"Working…";  break;
        case GAAgentStateSpeaking: text = @"Speaking…"; break;
        case GAAgentStateIdle:     text = @"Ask GrokAgent"; break;
    }
    self.statusLabel.text = text;
}

- (void)agentDidPerformStep:(NSString *)description {
    if ([GAPreferences shared].debugLogging) self.statusLabel.text = description;
}

- (void)agentDidFinishWithReply:(NSString *)reply error:(NSError *)error {
    self.statusLabel.text = error ? error.localizedDescription : reply;
    if (!error && reply.length && [GAPreferences shared].speakReplies) {
        [[GAVoiceManager shared] speak:reply];
    }
}

@end
