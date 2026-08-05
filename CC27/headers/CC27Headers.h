#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <spawn.h>

#ifdef __cplusplus
extern "C" {
#endif
extern char **environ;
#ifdef __cplusplus
}
#endif

typedef struct CCUILayoutSize {
    NSUInteger width;
    NSUInteger height;
} CCUILayoutSize;

@interface NSValue (CC27Layout)
+ (NSValue *)ccui_valueWithLayoutSize:(CCUILayoutSize)layoutSize;
- (CCUILayoutSize)ccui_sizeValue;
@end

@interface CCSModuleMetadata : NSObject
@property (nonatomic, copy, readonly) NSString *moduleIdentifier;
@property (nonatomic, copy, readonly) NSURL *moduleBundleURL;
@end

@interface CCSModuleRepository : NSObject
+ (instancetype)repositoryWithDirectories:(NSArray *)directories;
- (NSSet *)loadableModuleIdentifiers;
- (CCSModuleMetadata *)moduleMetadataForModuleIdentifier:(NSString *)identifier;
- (void)_updateAllModuleMetadata;
- (void)_queue_updateAllModuleMetadata;
@end

@interface CCSModuleSettingsProvider : NSObject
+ (instancetype)sharedProvider;
+ (NSURL *)_configurationFileURL;
+ (NSArray *)_defaultUserEnabledModuleIdentifiers;
@property (nonatomic, copy, readonly) NSArray *orderedUserEnabledModuleIdentifiers;
- (void)setAndSaveOrderedUserEnabledModuleIdentifiers:(NSArray *)identifiers;
@end

@interface CCUIModuleInstance : NSObject
@property (nonatomic, strong, readonly) CCSModuleMetadata *metadata;
@property (nonatomic, strong, readonly) id module;
@property (nonatomic, assign, readonly) CCUILayoutSize prototypeModuleSize;
@end

@interface CCUIModuleInstanceManager : NSObject
+ (instancetype)sharedInstance;
- (CCUIModuleInstance *)instanceForModuleIdentifier:(NSString *)moduleIdentifier;
@end

@interface CCUIModuleSettings : NSObject
@end

@interface CCUIModuleSettingsManager : NSObject
- (CCUIModuleSettings *)moduleSettingsForModuleIdentifier:(NSString *)identifier prototypeSize:(CCUILayoutSize)size;
@end

@interface CCUIModuleCollectionViewController : UIViewController
+ (instancetype)_sharedCollectionViewController;
- (void)_refreshPositionProviders;
- (NSArray *)_sizesForModuleIdentifiers:(NSArray *)identifiers moduleInstanceByIdentifier:(NSDictionary *)map interfaceOrientation:(long long)orientation;
@end

@interface CCUIContentModuleContainerViewController : UIViewController
@property (nonatomic, copy, readonly) NSString *moduleIdentifier;
@end

@interface CCUIContentModuleContentContainerView : UIView
@end

@interface CCUIModularControlCenterViewController : UIViewController
+ (CCUIModuleCollectionViewController *)_sharedCollectionViewController;
@end

@interface CCUIModularControlCenterOverlayViewController : UIViewController
- (void)setPresentationState:(NSInteger)state;
@end

@interface MTMaterialView : UIView
@end

@interface SpringBoard : UIApplication
+ (id)sharedApplication;
- (void)applicationOpenURL:(NSURL *)url;
@end

@protocol CCUIContentModuleContentViewController <NSObject>
@property (nonatomic, readonly) CGFloat preferredExpandedContentHeight;
@optional
@property (nonatomic, readonly) CGFloat preferredExpandedContentWidth;
@property (nonatomic, readonly) BOOL providesOwnPlatter;
- (void)controlCenterWillPresent;
- (void)controlCenterDidDismiss;
@end

@protocol CCUIContentModule <NSObject>
@property (nonatomic, readonly) UIViewController<CCUIContentModuleContentViewController> *contentViewController;
@optional
@property (nonatomic, readonly) UIViewController *backgroundViewController;
- (void)setContentModuleContext:(id)context;
- (CCUILayoutSize)moduleSizeForOrientation:(int)orientation;
@end

@interface CCUIToggleModule : NSObject <CCUIContentModule>
@property (nonatomic, assign, getter=isSelected) BOOL selected;
@property (nonatomic, copy, readonly) UIImage *iconGlyph;
@property (nonatomic, copy, readonly) UIImage *selectedIconGlyph;
@property (nonatomic, copy, readonly) UIColor *selectedColor;
- (void)refreshState;
@end
