#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^AEScreenLensCompletion)(NSString * _Nullable text, NSError * _Nullable error);

@interface AEScreenLens : NSObject
+ (void)recognizeTextInWindow:(UIWindow *)window completion:(AEScreenLensCompletion)completion;
+ (void)recognizeTextInImage:(UIImage *)image completion:(AEScreenLensCompletion)completion;
@end

NS_ASSUME_NONNULL_END
