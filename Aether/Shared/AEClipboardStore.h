#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface AEClipboardItem : NSObject <NSSecureCoding>
@property (nonatomic, copy) NSString *uuid;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, strong, nullable) NSDate *date;
@property (nonatomic, copy, nullable) NSString *sourceBundle;
@property (nonatomic, assign) BOOL pinned;
@end

@interface AEClipboardStore : NSObject
+ (instancetype)shared;
- (void)startObserving;
- (void)stopObserving;
- (NSArray<AEClipboardItem *> *)items;
- (void)pasteItem:(AEClipboardItem *)item;
- (void)deleteItem:(AEClipboardItem *)item;
- (void)togglePin:(AEClipboardItem *)item;
- (void)clearUnpinned;
- (void)reload;
@end

NS_ASSUME_NONNULL_END
