// GrokAgent — SpringBoard injection point.
//
// Design note: the hooks below target private classes whose selectors drift
// between iOS releases. Rather than hard-failing (or worse, crashing SpringBoard)
// on a version where a selector moved, each optional hook lives in its own
// %group and is only initialised after we confirm the class and selector exist
// at runtime. Verify the real names on your 17.3 device with:
//
//     dpkg -l | grep -i classdump    # or use a class-dump of SpringBoard
//     GADumpSelectors is called for you when debug logging is on.

#import <UIKit/UIKit.h>
#import "GACommon.h"
#import "GAPreferences.h"
#import "GAActivationManager.h"
#import "GADeviceControl.h"
#import "GAOverlayController.h"
#import <objc/runtime.h>

#pragma mark - Runtime probing helpers

static BOOL GAClassHasSelector(NSString *className, SEL selector) {
    Class cls = NSClassFromString(className);
    if (!cls) return NO;
    return class_getInstanceMethod(cls, selector) != NULL;
}

static void GADumpSelectors(NSString *className, NSString *filter) {
    if (!GADebugLoggingEnabled()) return;
    Class cls = NSClassFromString(className);
    if (!cls) { GALog(@"probe: class %@ not found", className); return; }

    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    NSMutableArray *matches = [NSMutableArray array];
    for (unsigned int i = 0; i < count; i++) {
        NSString *name = NSStringFromSelector(method_getName(methods[i]));
        if (!filter.length || [name localizedCaseInsensitiveContainsString:filter]) {
            [matches addObject:name];
        }
    }
    free(methods);
    GALog(@"probe %@ (~%@): %@", className, filter ?: @"all",
          [matches componentsJoinedByString:@", "]);
}

#pragma mark - Volume button activation

%group VolumeButtons

%hook SBVolumeHardwareButtonActions

- (void)performSinglePressUpAction {
    if ([[GAActivationManager shared] handleVolumeUpPress]) return;   // swallow it
    %orig;
}

%end

%end // VolumeButtons

#pragma mark - Siri interception

%group SiriIntercept

%hook SBAssistantController

- (void)handleSiriButtonDown {
    if ([GAPreferences shared].enabled &&
        [GAPreferences shared].activationMethod == GAActivationMethodSiriIntercept) {
        GALog(@"activation: intercepted Siri button");
        [[GAActivationManager shared] activate];
        return;   // do not let Siri come up
    }
    %orig;
}

%end

%end // SiriIntercept

#pragma mark - Bootstrap

%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)application {
    %orig;

    GAPreferences *prefs = [GAPreferences shared];
    GALog(@"GrokAgent 0.1.1 loaded — enabled=%d model=%@ activation=%ld",
          prefs.enabled, prefs.model, (long)prefs.activationMethod);
    // Log which plist we actually read. On RootHide this is the single most
    // useful line in the log: if it is not the jbroot copy, every toggle in
    // Settings is being ignored.
    GALog(@"prefs resolved to: %@", prefs.resolvedPrefsPath);

    [[GAActivationManager shared] start];

    // Probe the backend early so a missing iOS MCP shows up in the log at boot
    // rather than mid-conversation.
    [[GADeviceControl shared] checkHealth:^(BOOL ok, NSString *version) {
        GALog(@"device control backend: %@", ok ? version : @"unavailable");
    }];

    // Selector reconnaissance for the hooks we could not initialise.
    GADumpSelectors(@"SBVolumeHardwareButtonActions", @"press");
    GADumpSelectors(@"SBAssistantController", @"siri");
}

%end

#pragma mark - Constructor

%ctor {
    @autoreleasepool {
        if (![GAPreferences shared].enabled) {
            NSLog(@"[GrokAgent] disabled in preferences — not hooking");
            return;
        }

        if ([GAOverlayController consumeStaleBreadcrumb]) {
            NSLog(@"[GrokAgent] previous overlay attempt did not complete — "
                   "consider enabling Overlay Safe Mode in Settings");
        }

        %init;   // ungrouped hooks (SpringBoard)

        if (GAClassHasSelector(@"SBVolumeHardwareButtonActions", @selector(performSinglePressUpAction))) {
            %init(VolumeButtons);
            NSLog(@"[GrokAgent] volume button hooks active");
        } else {
            NSLog(@"[GrokAgent] volume button selector not found on this iOS — skipping group");
        }

        if (GAClassHasSelector(@"SBAssistantController", @selector(handleSiriButtonDown))) {
            %init(SiriIntercept);
            NSLog(@"[GrokAgent] Siri intercept hooks active");
        } else {
            NSLog(@"[GrokAgent] Siri intercept selector not found on this iOS — skipping group");
        }
    }
}
