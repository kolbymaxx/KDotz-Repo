#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Stable fingerprint for a view in the hierarchy (class + a11y id + sibling index path).
FOUNDATION_EXPORT NSString * _Nullable AEViewFingerprint(UIView *view);

@interface AESculptStore : NSObject
+ (instancetype)shared;
- (NSSet<NSString *> *)hiddenFingerprintsForBundle:(NSString *)bundleID;
- (void)hideFingerprint:(NSString *)fp forBundle:(NSString *)bundleID;
- (void)unhideFingerprint:(NSString *)fp forBundle:(NSString *)bundleID;
- (void)clearBundle:(NSString *)bundleID;
- (void)applyToWindow:(UIWindow *)window bundleID:(NSString *)bundleID;
- (NSInteger)countForBundle:(NSString *)bundleID;
@end

NS_ASSUME_NONNULL_END
