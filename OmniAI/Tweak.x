// OmniAI — system-wide AI for iOS 16–18 (rootless).
// Injects into UIKit (text menus) + SpringBoard (status bar / volume).

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "OmniAICommon.h"
#import "OmniAIPreferences.h"
#import "OmniAIActivationManager.h"
#import "OmniAIOverlay.h"
#import "OmniAIDeviceControl.h"

#pragma mark - Runtime helpers

static BOOL OAClassHasSelector(NSString *className, SEL selector) {
    Class cls = NSClassFromString(className);
    if (!cls) return NO;
    return class_getInstanceMethod(cls, selector) != NULL;
}

static NSString *OASelectedTextFromResponder(id<UITextInput> input) {
    if (!input) return nil;
    UITextRange *range = input.selectedTextRange;
    if (!range || range.isEmpty) return nil;
    return [input textInRange:range];
}

/// UIWindow has no public firstResponder property — walk the hierarchy instead.
static UIView *OAFindFirstResponderInView(UIView *view) {
    if (!view) return nil;
    if (view.isFirstResponder) return view;
    for (UIView *sub in view.subviews) {
        UIView *found = OAFindFirstResponderInView(sub);
        if (found) return found;
    }
    return nil;
}

static UIResponder *OACurrentFirstResponder(void) {
    UIApplication *app = UIApplication.sharedApplication;
    if (@available(iOS 15.0, *)) {
        for (UIScene *scene in app.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            UIWindowScene *ws = (UIWindowScene *)scene;
            for (UIWindow *window in ws.windows) {
                UIView *found = OAFindFirstResponderInView(window);
                if (found) return found;
            }
        }
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    for (UIWindow *window in app.windows) {
        UIView *found = OAFindFirstResponderInView(window);
        if (found) return found;
    }
#pragma clang diagnostic pop
    return nil;
}

static void OAInsertOmniAIMenu(id<UIMenuBuilder> builder, id textInput) {
    if (![OmniAIPreferences shared].enabled) return;
    if (@available(iOS 16.0, *)) {
        __weak id weakInput = textInput;
        UIAction *action = [UIAction actionWithTitle:@"OmniAI"
                                               image:[UIImage systemImageNamed:@"sparkles"]
                                          identifier:@"com.kolby.omniai.menu"
                                             handler:^(__kindof UIAction *a) {
            id strong = weakInput;
            NSString *selected = nil;
            if ([strong conformsToProtocol:@protocol(UITextInput)]) {
                selected = OASelectedTextFromResponder((id<UITextInput>)strong);
            }
            [[OmniAIActivationManager shared] activateWithSelectedText:selected
                                                        textInputTarget:strong];
        }];
        UIMenu *menu = [UIMenu menuWithTitle:@""
                                       image:nil
                                  identifier:@"com.kolby.omniai"
                                     options:UIMenuOptionsDisplayInline
                                    children:@[ action ]];
        [builder insertChildMenu:menu atStartOfMenuForIdentifier:UIMenuRoot];
    }
}

#pragma mark - UIEditMenuInteraction / text menus (iOS 16+)

%group EditMenu

%hook UITextView

- (void)buildMenuWithBuilder:(id<UIMenuBuilder>)builder {
    %orig;
    OAInsertOmniAIMenu(builder, self);
}

%end

%hook UITextField

- (void)buildMenuWithBuilder:(id<UIMenuBuilder>)builder {
    %orig;
    OAInsertOmniAIMenu(builder, self);
}

%end

%end // EditMenu

%group EditMenuPrivate

%hook UIEditMenuInteraction

- (NSArray *)_editMenuActionsForConfiguration:(id)configuration {
    NSArray *actions = %orig;
    if (![OmniAIPreferences shared].enabled) return actions;
    if (@available(iOS 16.0, *)) {
        UIAction *omniai = [UIAction actionWithTitle:@"OmniAI"
                                               image:[UIImage systemImageNamed:@"sparkles"]
                                          identifier:@"com.kolby.omniai.editmenu"
                                             handler:^(__kindof UIAction *action) {
            id<UITextInput> input = nil;
            UIResponder *r = OACurrentFirstResponder();
            if ([r conformsToProtocol:@protocol(UITextInput)]) input = (id<UITextInput>)r;
            NSString *selected = OASelectedTextFromResponder(input);
            [[OmniAIActivationManager shared] activateWithSelectedText:selected
                                                        textInputTarget:input];
        }];
        NSMutableArray *mutable = [actions isKindOfClass:NSArray.class]
            ? [actions mutableCopy] : [NSMutableArray array];
        [mutable insertObject:omniai atIndex:0];
        return mutable;
    }
    return actions;
}

%end

%end // EditMenuPrivate

#pragma mark - Status bar activation

%group StatusBarActivate

%hook UIStatusBarWindow

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    if ([OmniAIPreferences shared].enabled &&
        [OmniAIPreferences shared].statusBarActivate &&
        [OmniAIPreferences shared].activationMethod == OmniAIActivationMethodStatusBar) {
        UITouch *touch = [touches anyObject];
        if (touch.tapCount >= 1) {
            OALog(@"activation: status bar tap");
            [[OmniAIActivationManager shared] activate];
        }
    }
    %orig;
}

%end

%hook UIWindow

- (BOOL)_scrollToTopFromTouchAtScreenLocation:(CGPoint)location {
    if ([OmniAIPreferences shared].enabled &&
        [OmniAIPreferences shared].statusBarActivate &&
        [OmniAIPreferences shared].activationMethod == OmniAIActivationMethodStatusBar) {
        static NSTimeInterval last = 0;
        NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
        if (now - last > 0.4) {
            last = now;
            OALog(@"activation: status bar scroll-to-top");
            [[OmniAIActivationManager shared] activate];
        }
    }
    return %orig;
}

%end

%end // StatusBarActivate

#pragma mark - Volume double-press (SpringBoard)

%group VolumeButtons

%hook SBVolumeHardwareButtonActions

- (void)performSinglePressUpAction {
    if ([[OmniAIActivationManager shared] handleVolumeUpPress]) return;
    %orig;
}

%end

%end // VolumeButtons

#pragma mark - SpringBoard bootstrap

%group SpringBoardBoot

%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)application {
    %orig;

    OmniAIPreferences *prefs = [OmniAIPreferences shared];
    OALog(@"OmniAI 1.0.0 loaded — enabled=%d provider=%@ mcp=%@:%ld",
          prefs.enabled, OmniAIProviderName(prefs.defaultProvider),
          prefs.mcpHost, (long)prefs.mcpPort);
    OALog(@"prefs resolved to: %@", prefs.resolvedPrefsPath);

    [[OmniAIActivationManager shared] start];

    [[OmniAIDeviceControl shared] checkHealth:^(BOOL ok, NSString *version) {
        OALog(@"iOS MCP: %@", ok ? ([NSString stringWithFormat:@"ready v%@", version ?: @"?"])
                                 : @"unavailable (install witchan ios-mcp for Device Agent)");
    }];
}

%end

%end // SpringBoardBoot

#pragma mark - Constructor

%ctor {
    @autoreleasepool {
        if (![OmniAIPreferences shared].enabled) {
            NSLog(@"[OmniAI] disabled in preferences — not hooking");
            return;
        }

        if ([OmniAIOverlay consumeStaleBreadcrumb]) {
            NSLog(@"[OmniAI] previous overlay attempt did not complete — "
                   "consider enabling Overlay Safe Mode in Settings");
        }

        NSString *bundle = [NSBundle mainBundle].bundleIdentifier ?: @"";
        BOOL isSpringBoard = [bundle isEqualToString:@"com.apple.springboard"];

        %init(EditMenu);

        if (OAClassHasSelector(@"UIEditMenuInteraction",
                               @selector(_editMenuActionsForConfiguration:))) {
            %init(EditMenuPrivate);
        }

        if (OAClassHasSelector(@"UIStatusBarWindow", @selector(touchesEnded:withEvent:)) ||
            OAClassHasSelector(@"UIWindow", @selector(_scrollToTopFromTouchAtScreenLocation:))) {
            %init(StatusBarActivate);
        }

        if (isSpringBoard) {
            %init(SpringBoardBoot);
            [[OmniAIActivationManager shared] start];

            if (OAClassHasSelector(@"SBVolumeHardwareButtonActions",
                                   @selector(performSinglePressUpAction))) {
                %init(VolumeButtons);
                NSLog(@"[OmniAI] volume button hooks active");
            }
        } else {
            [[OmniAIActivationManager shared] start];
        }

        NSLog(@"[OmniAI] loaded in %@", bundle.length ? bundle : @"?");
    }
}
