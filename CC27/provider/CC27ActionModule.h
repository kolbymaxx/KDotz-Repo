#import <UIKit/UIKit.h>
#import "CC27Headers.h"

NS_ASSUME_NONNULL_BEGIN

@interface CC27ActionContentViewController : UIViewController <CCUIContentModuleContentViewController>
@property (nonatomic, copy) NSString *symbolName;
@property (nonatomic, copy) NSString *titleText;
@property (nonatomic, copy) void (^action)(void);
@end

@interface CC27ActionModule : NSObject <CCUIContentModule>
- (instancetype)initWithIdentifier:(NSString *)identifier
                        symbolName:(NSString *)symbolName
                             title:(NSString *)title
                            action:(void (^)(void))action;
@property (nonatomic, copy, readonly) NSString *moduleIdentifier;
@property (nonatomic, strong, readonly) CC27ActionContentViewController *contentViewController;
@end

FOUNDATION_EXPORT void CC27Spawn(NSArray<NSString *> *args);

NS_ASSUME_NONNULL_END
