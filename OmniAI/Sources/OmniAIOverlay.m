#import "OmniAIOverlay.h"
#import "OmniAIManager.h"
#import "OmniAIAgentOrchestrator.h"
#import "OmniAIPreferences.h"
#import "OmniAICommon.h"

@interface OmniAIOverlay () <OmniAIAgentObserver>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) UIVisualEffectView *card;
@property (nonatomic, strong) UISegmentedControl *providerControl;
@property (nonatomic, strong) UISwitch *screenSwitch;
@property (nonatomic, strong) UISwitch *agentSwitch;
@property (nonatomic, strong) UITextField *promptField;
@property (nonatomic, strong) UITextView *outputView;
@property (nonatomic, strong) UIButton *sendButton;
@property (nonatomic, strong) UIButton *actionButton;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, copy) NSString *selectedText;
@property (nonatomic, weak) id textInputTarget;
@property (nonatomic, assign) BOOL busy;
@end

@implementation OmniAIOverlay

+ (instancetype)shared {
    static OmniAIOverlay *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[self alloc] init]; });
    return s;
}

#pragma mark - Breadcrumb failsafe

+ (NSString *)breadcrumbPath {
    return [NSTemporaryDirectory() stringByAppendingPathComponent:@"omniai-overlay.lock"];
}

+ (void)armBreadcrumb {
    [@"1" writeToFile:[self breadcrumbPath] atomically:YES
             encoding:NSUTF8StringEncoding error:nil];
}

+ (void)clearBreadcrumb {
    [[NSFileManager defaultManager] removeItemAtPath:[self breadcrumbPath] error:nil];
}

+ (BOOL)consumeStaleBreadcrumb {
    NSString *path = [self breadcrumbPath];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return NO;
    [self clearBreadcrumb];
    return YES;
}

#pragma mark - Present / dismiss

- (void)present {
    [self presentWithSelectedText:nil textInputTarget:nil];
}

- (void)presentWithSelectedText:(NSString *)selectedText textInputTarget:(id)textInputTarget {
    if (self.window) {
        self.selectedText = selectedText;
        self.textInputTarget = textInputTarget;
        [self.promptField becomeFirstResponder];
        return;
    }

    if ([OmniAIPreferences shared].overlaySafeMode) {
        OAErr(@"overlay suppressed — safe mode is on");
        return;
    }

    [OmniAIOverlay armBreadcrumb];
    self.selectedText = selectedText;
    self.textInputTarget = textInputTarget;

    UIWindowScene *scene = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if ([s isKindOfClass:UIWindowScene.class] &&
            s.activationState == UISceneActivationStateForegroundActive) {
            scene = (UIWindowScene *)s;
            break;
        }
    }

    self.window = scene ? [[UIWindow alloc] initWithWindowScene:scene]
                        : [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.windowLevel = UIWindowLevelAlert + 1;
    self.window.backgroundColor = [UIColor colorWithWhite:0 alpha:0.28];
    self.window.rootViewController = [UIViewController new];

    UITapGestureRecognizer *dimTap =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismiss)];
    dimTap.cancelsTouchesInView = NO;
    [self.window.rootViewController.view addGestureRecognizer:dimTap];

    [self buildCardIn:self.window.rootViewController.view];

    OmniAIProvider def = [OmniAIPreferences shared].defaultProvider;
    self.providerControl.selectedSegmentIndex = (NSInteger)def;
    self.screenSwitch.on = [OmniAIPreferences shared].includeScreenByDefault;
    self.agentSwitch.on = [OmniAIPreferences shared].deviceAgentByDefault;
    [OmniAIAgentOrchestrator shared].observer = self;

    if (selectedText.length) {
        self.promptField.placeholder = @"Ask about the selection…";
        self.statusLabel.text = [NSString stringWithFormat:@"Selection · %lu chars",
                                 (unsigned long)selectedText.length];
    } else {
        self.promptField.placeholder = @"Ask OmniAI…";
        self.statusLabel.text = @"Ready";
    }

    self.window.hidden = NO;
    [self.window makeKeyAndVisible];
    [self.promptField becomeFirstResponder];
    [OmniAIOverlay clearBreadcrumb];
    OALog(@"overlay presented");
}

- (void)dismiss {
    [[OmniAIAgentOrchestrator shared] cancel];
    [OmniAIAgentOrchestrator shared].observer = nil;
    [self.promptField resignFirstResponder];
    [self.outputView resignFirstResponder];
    self.window.hidden = YES;
    self.window = nil;
    self.card = nil;
    self.selectedText = nil;
    self.textInputTarget = nil;
    self.busy = NO;
    OALog(@"overlay dismissed");
}

#pragma mark - UI construction

- (void)buildCardIn:(UIView *)root {
    UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:
        [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterial]];
    blur.translatesAutoresizingMaskIntoConstraints = NO;
    blur.layer.cornerRadius = 20;
    blur.layer.cornerCurve = kCACornerCurveContinuous;
    blur.clipsToBounds = YES;
    [root addSubview:blur];
    self.card = blur;

    UIView *content = blur.contentView;

    UILabel *title = [UILabel new];
    title.text = @"OmniAI";
    title.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    title.textColor = UIColor.labelColor;
    title.translatesAutoresizingMaskIntoConstraints = NO;

    UIButton *close = [UIButton buttonWithType:UIButtonTypeClose];
    close.translatesAutoresizingMaskIntoConstraints = NO;
    [close addTarget:self action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];

    self.providerControl = [[UISegmentedControl alloc] initWithItems:@[ @"Grok", @"Claude", @"Gemini" ]];
    self.providerControl.selectedSegmentIndex = 0;
    self.providerControl.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *screenLabel = [UILabel new];
    screenLabel.text = @"Include Screen Context";
    screenLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    screenLabel.textColor = UIColor.secondaryLabelColor;
    screenLabel.translatesAutoresizingMaskIntoConstraints = NO;

    self.screenSwitch = [UISwitch new];
    self.screenSwitch.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *agentLabel = [UILabel new];
    agentLabel.text = @"Device Agent (iOS MCP)";
    agentLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    agentLabel.textColor = UIColor.secondaryLabelColor;
    agentLabel.translatesAutoresizingMaskIntoConstraints = NO;

    self.agentSwitch = [UISwitch new];
    self.agentSwitch.translatesAutoresizingMaskIntoConstraints = NO;

    self.promptField = [UITextField new];
    self.promptField.borderStyle = UITextBorderStyleRoundedRect;
    self.promptField.font = [UIFont systemFontOfSize:16];
    self.promptField.returnKeyType = UIReturnKeyGo;
    self.promptField.autocorrectionType = UITextAutocorrectionTypeYes;
    self.promptField.translatesAutoresizingMaskIntoConstraints = NO;
    [self.promptField addTarget:self action:@selector(send)
               forControlEvents:UIControlEventEditingDidEndOnExit];

    self.outputView = [UITextView new];
    self.outputView.editable = NO;
    self.outputView.font = [UIFont systemFontOfSize:15];
    self.outputView.backgroundColor = [UIColor.secondarySystemBackgroundColor colorWithAlphaComponent:0.65];
    self.outputView.layer.cornerRadius = 12;
    self.outputView.layer.cornerCurve = kCACornerCurveContinuous;
    self.outputView.textContainerInset = UIEdgeInsetsMake(10, 8, 10, 8);
    self.outputView.translatesAutoresizingMaskIntoConstraints = NO;
    self.outputView.text = @"";

    self.statusLabel = [UILabel new];
    self.statusLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    self.statusLabel.textColor = UIColor.tertiaryLabelColor;
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;

    self.sendButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.sendButton setTitle:@"Send" forState:UIControlStateNormal];
    self.sendButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    self.sendButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.sendButton addTarget:self action:@selector(send) forControlEvents:UIControlEventTouchUpInside];

    self.actionButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.actionButton setTitle:@"Copy" forState:UIControlStateNormal];
    self.actionButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    self.actionButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.actionButton addTarget:self action:@selector(replaceOrCopy)
                forControlEvents:UIControlEventTouchUpInside];

    [content addSubview:title];
    [content addSubview:close];
    [content addSubview:self.providerControl];
    [content addSubview:screenLabel];
    [content addSubview:self.screenSwitch];
    [content addSubview:agentLabel];
    [content addSubview:self.agentSwitch];
    [content addSubview:self.promptField];
    [content addSubview:self.outputView];
    [content addSubview:self.statusLabel];
    [content addSubview:self.sendButton];
    [content addSubview:self.actionButton];

    CGFloat maxHeight = MIN(UIScreen.mainScreen.bounds.size.height * 0.68, 560);

    [NSLayoutConstraint activateConstraints:@[
        [blur.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:14],
        [blur.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-14],
        [blur.bottomAnchor constraintEqualToAnchor:root.safeAreaLayoutGuide.bottomAnchor constant:-12],
        [blur.heightAnchor constraintLessThanOrEqualToConstant:maxHeight],

        [title.topAnchor constraintEqualToAnchor:content.topAnchor constant:14],
        [title.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:16],

        [close.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],
        [close.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-12],

        [self.providerControl.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:12],
        [self.providerControl.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:16],
        [self.providerControl.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-16],

        [screenLabel.topAnchor constraintEqualToAnchor:self.providerControl.bottomAnchor constant:12],
        [screenLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:16],

        [self.screenSwitch.centerYAnchor constraintEqualToAnchor:screenLabel.centerYAnchor],
        [self.screenSwitch.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-16],

        [agentLabel.topAnchor constraintEqualToAnchor:screenLabel.bottomAnchor constant:10],
        [agentLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:16],

        [self.agentSwitch.centerYAnchor constraintEqualToAnchor:agentLabel.centerYAnchor],
        [self.agentSwitch.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-16],

        [self.promptField.topAnchor constraintEqualToAnchor:agentLabel.bottomAnchor constant:12],
        [self.promptField.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:16],
        [self.promptField.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-16],
        [self.promptField.heightAnchor constraintEqualToConstant:40],

        [self.outputView.topAnchor constraintEqualToAnchor:self.promptField.bottomAnchor constant:10],
        [self.outputView.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:16],
        [self.outputView.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-16],
        [self.outputView.heightAnchor constraintGreaterThanOrEqualToConstant:120],

        [self.statusLabel.topAnchor constraintEqualToAnchor:self.outputView.bottomAnchor constant:8],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:16],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-16],

        [self.sendButton.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:8],
        [self.sendButton.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-16],
        [self.sendButton.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-14],

        [self.actionButton.centerYAnchor constraintEqualToAnchor:self.sendButton.centerYAnchor],
        [self.actionButton.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:16],
    ]];

    [self refreshActionTitle];
}

- (void)refreshActionTitle {
    BOOL canReplace = self.textInputTarget != nil && self.selectedText.length > 0;
    [self.actionButton setTitle:(canReplace ? @"Replace Selected Text" : @"Copy")
                       forState:UIControlStateNormal];
}

#pragma mark - Actions

- (OmniAIProvider)selectedProvider {
    return (OmniAIProvider)self.providerControl.selectedSegmentIndex;
}

- (void)send {
    if (self.busy) return;
    NSString *prompt = [self.promptField.text stringByTrimmingCharactersInSet:
                        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!prompt.length) return;

    self.busy = YES;
    self.sendButton.enabled = NO;
    self.statusLabel.text = @"Thinking…";
    self.outputView.text = @"";
    [self.promptField resignFirstResponder];

    // Device Agent mode: Grok + iOS MCP tool loop (see / operate the phone).
    if (self.agentSwitch.isOn) {
        NSString *full = prompt;
        if (self.selectedText.length) {
            full = [NSString stringWithFormat:@"Selected text:\n\"\"\"\n%@\n\"\"\"\n\n%@",
                    self.selectedText, prompt];
        }
        self.statusLabel.text = @"Agent · checking iOS MCP…";
        [[OmniAIAgentOrchestrator shared] runWithPrompt:full];
        return;
    }

    OmniAIProvider provider = [self selectedProvider];
    BOOL includeScreen = self.screenSwitch.isOn;
    NSString *selection = [self.selectedText copy];

    __weak typeof(self) weakSelf = self;
    [[OmniAIManager shared] sendPrompt:prompt
                          selectedText:selection
                         includeScreen:includeScreen
                              provider:provider
                            completion:^(NSString *reply, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            self.busy = NO;
            self.sendButton.enabled = YES;
            if (error) {
                self.statusLabel.text = error.localizedDescription;
                self.outputView.text = @"";
                return;
            }
            self.outputView.text = reply ?: @"";
            self.statusLabel.text = @"Done";
            [self refreshActionTitle];
        });
    }];
}

#pragma mark - OmniAIAgentObserver

- (void)agentDidChangeState:(OmniAIAgentState)state {
    switch (state) {
        case OmniAIAgentStateThinking: self.statusLabel.text = @"Agent · thinking…"; break;
        case OmniAIAgentStateActing:   self.statusLabel.text = @"Agent · acting…"; break;
        default: break;
    }
}

- (void)agentDidPerformStep:(NSString *)description {
    if (description.length) self.statusLabel.text = description;
}

- (void)agentDidFinishWithReply:(NSString *)reply error:(NSError *)error {
    self.busy = NO;
    self.sendButton.enabled = YES;
    if (error) {
        self.statusLabel.text = error.localizedDescription;
        self.outputView.text = @"";
        return;
    }
    self.outputView.text = reply ?: @"";
    self.statusLabel.text = @"Agent · done";
    [self refreshActionTitle];
}

- (void)replaceOrCopy {
    NSString *text = self.outputView.text ?: @"";
    if (!text.length) return;

    id target = self.textInputTarget;
    if (target && self.selectedText.length && [target conformsToProtocol:@protocol(UITextInput)]) {
        id<UITextInput> input = (id<UITextInput>)target;
        UITextRange *selected = input.selectedTextRange;
        if (selected && !selected.empty) {
            [input replaceRange:selected withText:text];
            self.statusLabel.text = @"Replaced selection";
            return;
        }
        // Fallback: if selection was lost, try marked / full document replace of prior string.
        UITextRange *full = [input textRangeFromPosition:input.beginningOfDocument
                                              toPosition:input.endOfDocument];
        NSString *all = [input textInRange:full];
        NSRange range = [all rangeOfString:self.selectedText];
        if (range.location != NSNotFound) {
            UITextPosition *start = [input positionFromPosition:input.beginningOfDocument
                                                         offset:(NSInteger)range.location];
            UITextPosition *end = [input positionFromPosition:start
                                                      offset:(NSInteger)range.length];
            UITextRange *tr = [input textRangeFromPosition:start toPosition:end];
            if (tr) {
                [input replaceRange:tr withText:text];
                self.statusLabel.text = @"Replaced selection";
                return;
            }
        }
    }

    UIPasteboard.generalPasteboard.string = text;
    self.statusLabel.text = @"Copied";
}

@end
