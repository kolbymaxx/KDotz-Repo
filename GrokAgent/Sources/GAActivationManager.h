#import <Foundation/Foundation.h>

/// Activation Layer.
///
/// The Darwin notification trigger is always live, whatever the preference —
/// it costs nothing and gives you a reliable way in over SSH:
///     notifyutil -p com.kolby.grokagent/activate
NS_ASSUME_NONNULL_BEGIN

@interface GAActivationManager : NSObject

+ (instancetype)shared;

- (void)start;

/// Called by whichever trigger fired. Safe to call from any thread.
- (void)activate;

/// Volume-button trigger, driven from Tweak.x. Returns YES if the press was
/// consumed by GrokAgent and should not reach the system.
- (BOOL)handleVolumeUpPress;

@end

NS_ASSUME_NONNULL_END
