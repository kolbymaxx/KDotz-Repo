#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class AEGlassPanel;

@protocol AEGlassPanelDelegate <NSObject>
- (void)glassPanelDidRequestDismiss:(AEGlassPanel *)panel;
- (void)glassPanelDidEnterSculptMode:(AEGlassPanel *)panel;
- (void)glassPanelDidRequestClearSculpt:(AEGlassPanel *)panel;
@end

@interface AEGlassPanel : UIView
@property (nonatomic, weak, nullable) id<AEGlassPanelDelegate> delegate;
- (void)presentInWindow:(UIWindow *)window;
- (void)dismissAnimated:(BOOL)animated;
- (void)reloadClipboard;
- (void)showLensResult:(NSString *)text;
- (void)showStatus:(NSString *)message;
@end

NS_ASSUME_NONNULL_END
