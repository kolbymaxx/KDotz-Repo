#import <UIKit/UIKit.h>
#import "GAAgentOrchestrator.h"

/// Minimal on-screen HUD so you can see what the agent is doing without
/// tailing syslog. Also the temporary text-entry path until the voice
/// pipeline lands.
@interface GAOverlayController : NSObject <GAAgentObserver>

+ (instancetype)shared;

- (void)present;     // shows the HUD and prompts for input
- (void)dismiss;

/// Boot-time check: did the last present attempt fail to complete?
+ (BOOL)consumeStaleBreadcrumb;
+ (void)armBreadcrumb;
+ (void)clearBreadcrumb;

@end
