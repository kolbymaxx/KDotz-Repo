#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@protocol AEGestureHostDelegate <NSObject>
- (void)gestureHostDidSummon;
- (void)gestureHostDidCancelSculpt;
@end

@interface AEGestureHost : NSObject
@property (nonatomic, weak, nullable) id<AEGestureHostDelegate> delegate;
@property (nonatomic, assign) BOOL sculptModeActive;
+ (instancetype)shared;
- (void)attachToWindow:(UIWindow *)window;
- (void)detachFromWindow:(UIWindow *)window;
- (void)beginSculptInWindow:(UIWindow *)window;
- (void)endSculpt;
@end

NS_ASSUME_NONNULL_END
