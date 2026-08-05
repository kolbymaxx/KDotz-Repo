#import "GAActivationManager.h"
#import "GAOverlayController.h"
#import "GAPreferences.h"
#import "GACommon.h"
#import <notify.h>

static const NSTimeInterval kGADoublePressWindow = 0.35;

@interface GAActivationManager ()
@property (nonatomic) NSTimeInterval lastVolumeUpPress;
@property (nonatomic) BOOL started;
@end

@implementation GAActivationManager

+ (instancetype)shared {
    static GAActivationManager *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[self alloc] init]; });
    return s;
}

- (void)start {
    if (self.started) return;
    self.started = YES;

    int token;
    notify_register_dispatch(kGANotifyActivate, &token, dispatch_get_main_queue(), ^(int t) {
        GALog(@"activation: darwin notification");
        [self activate];
    });

    GALog(@"activation manager started (method=%ld)",
          (long)[GAPreferences shared].activationMethod);
}

- (void)activate {
    if (![GAPreferences shared].enabled) {
        GALog(@"activation ignored — tweak disabled");
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [[GAOverlayController shared] present];
    });
}

- (BOOL)handleVolumeUpPress {
    if ([GAPreferences shared].activationMethod != GAActivationMethodVolumeDouble) return NO;

    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    BOOL isDouble = (now - self.lastVolumeUpPress) < kGADoublePressWindow;
    self.lastVolumeUpPress = now;

    if (isDouble) {
        self.lastVolumeUpPress = 0;
        GALog(@"activation: volume-up double press");
        [self activate];
        return YES;
    }
    return NO;
}

@end
