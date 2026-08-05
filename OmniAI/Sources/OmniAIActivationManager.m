#import "OmniAIActivationManager.h"
#import "OmniAIOverlay.h"
#import "OmniAIPreferences.h"
#import "OmniAICommon.h"
#import <notify.h>

static const NSTimeInterval kOADoublePressWindow = 0.35;

@interface OmniAIActivationManager ()
@property (nonatomic) NSTimeInterval lastVolumeUpPress;
@property (nonatomic) BOOL started;
@end

@implementation OmniAIActivationManager

+ (instancetype)shared {
    static OmniAIActivationManager *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[self alloc] init]; });
    return s;
}

- (void)start {
    if (self.started) return;
    self.started = YES;

    int token;
    notify_register_dispatch(kOANotifyActivate, &token, dispatch_get_main_queue(), ^(int t) {
        OALog(@"activation: darwin notification");
        [self activate];
    });

    OALog(@"activation manager started (method=%ld)",
          (long)[OmniAIPreferences shared].activationMethod);
}

- (void)activate {
    [self activateWithSelectedText:nil textInputTarget:nil];
}

- (void)activateWithSelectedText:(NSString *)selectedText textInputTarget:(id)textInputTarget {
    if (![OmniAIPreferences shared].enabled) {
        OALog(@"activation ignored — tweak disabled");
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [[OmniAIOverlay shared] presentWithSelectedText:selectedText
                                         textInputTarget:textInputTarget];
    });
}

- (BOOL)handleVolumeUpPress {
    if ([OmniAIPreferences shared].activationMethod != OmniAIActivationMethodVolumeDouble) {
        return NO;
    }

    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    BOOL isDouble = (now - self.lastVolumeUpPress) < kOADoublePressWindow;
    self.lastVolumeUpPress = now;

    if (isDouble) {
        self.lastVolumeUpPress = 0;
        OALog(@"activation: volume-up double press");
        [self activate];
        return YES;
    }
    return NO;
}

@end
