#import "AEClipboardStore.h"
#import "AEPrefs.h"

@implementation AEClipboardItem

+ (BOOL)supportsSecureCoding { return YES; }

- (instancetype)init {
    self = [super init];
    if (self) {
        _uuid = [[NSUUID UUID] UUIDString];
        _date = [NSDate date];
        _text = @"";
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.uuid forKey:@"uuid"];
    [coder encodeObject:self.text forKey:@"text"];
    [coder encodeObject:self.date forKey:@"date"];
    [coder encodeObject:self.sourceBundle forKey:@"source"];
    [coder encodeBool:self.pinned forKey:@"pinned"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        _uuid = [coder decodeObjectOfClass:[NSString class] forKey:@"uuid"] ?: [[NSUUID UUID] UUIDString];
        _text = [coder decodeObjectOfClass:[NSString class] forKey:@"text"] ?: @"";
        _date = [coder decodeObjectOfClass:[NSDate class] forKey:@"date"];
        _sourceBundle = [coder decodeObjectOfClass:[NSString class] forKey:@"source"];
        _pinned = [coder decodeBoolForKey:@"pinned"];
    }
    return self;
}

@end

@interface AEClipboardStore ()
@property (nonatomic, strong) NSMutableArray<AEClipboardItem *> *storage;
@property (nonatomic, copy) NSString *lastSeen;
@property (nonatomic, assign) BOOL observing;
@end

@implementation AEClipboardStore

+ (instancetype)shared {
    static AEClipboardStore *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [AEClipboardStore new]; });
    return s;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _storage = [NSMutableArray array];
        [self reload];
    }
    return self;
}

- (NSString *)storePath {
    return [AEDataDirectory() stringByAppendingPathComponent:@"clipboard.plist"];
}

- (void)reload {
    NSData *data = [NSData dataWithContentsOfFile:self.storePath];
    if (!data) return;
    NSError *err = nil;
    NSSet *classes = [NSSet setWithObjects:[NSArray class], [AEClipboardItem class], [NSString class], [NSDate class], nil];
    NSArray *decoded = [NSKeyedUnarchiver unarchivedObjectOfClasses:classes fromData:data error:&err];
    if ([decoded isKindOfClass:[NSArray class]]) {
        self.storage = [decoded mutableCopy];
    }
}

- (void)persist {
    NSError *err = nil;
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:self.storage requiringSecureCoding:YES error:&err];
    if (data) [data writeToFile:self.storePath atomically:YES];
}

- (NSInteger)maxItems {
    return MAX(10, AEPrefInt(@"clipboardLimit", 50));
}

- (void)startObserving {
    if (self.observing) return;
    self.observing = YES;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(pasteboardChanged:)
                                                 name:UIPasteboardChangedNotification
                                               object:nil];
    // Capture current board once
    [self ingestCurrentPasteboard];
}

- (void)stopObserving {
    if (!self.observing) return;
    self.observing = NO;
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIPasteboardChangedNotification object:nil];
}

- (void)pasteboardChanged:(NSNotification *)note {
    (void)note;
    [self ingestCurrentPasteboard];
}

- (void)ingestCurrentPasteboard {
    if (!AEPrefBool(@"clipboardEnabled", YES)) return;
    UIPasteboard *pb = [UIPasteboard generalPasteboard];
    NSString *text = pb.string;
    if (text.length == 0) return;
    if ([text isEqualToString:self.lastSeen]) return;
    // Dedupe against newest
    if (self.storage.count && [self.storage.firstObject.text isEqualToString:text]) {
        self.lastSeen = text;
        return;
    }
    self.lastSeen = text;
    AEClipboardItem *item = [AEClipboardItem new];
    item.text = text;
    item.sourceBundle = AECurrentBundleID();
    [self.storage insertObject:item atIndex:0];
    while ((NSInteger)self.storage.count > self.maxItems) {
        // Drop oldest unpinned
        NSInteger dropIdx = -1;
        for (NSInteger i = (NSInteger)self.storage.count - 1; i >= 0; i--) {
            if (!self.storage[i].pinned) { dropIdx = i; break; }
        }
        if (dropIdx < 0) break;
        [self.storage removeObjectAtIndex:dropIdx];
    }
    [self persist];
}

- (NSArray<AEClipboardItem *> *)items {
    return [self.storage copy];
}

- (void)pasteItem:(AEClipboardItem *)item {
    if (!item.text.length) return;
    [UIPasteboard generalPasteboard].string = item.text;
    self.lastSeen = item.text;
}

- (void)deleteItem:(AEClipboardItem *)item {
    NSUInteger idx = [self.storage indexOfObjectPassingTest:^BOOL(AEClipboardItem *obj, NSUInteger i, BOOL *stop) {
        (void)i; (void)stop;
        return [obj.uuid isEqualToString:item.uuid];
    }];
    if (idx != NSNotFound) {
        [self.storage removeObjectAtIndex:idx];
        [self persist];
    }
}

- (void)togglePin:(AEClipboardItem *)item {
    item.pinned = !item.pinned;
    [self persist];
}

- (void)clearUnpinned {
    NSIndexSet *keep = [self.storage indexesOfObjectsPassingTest:^BOOL(AEClipboardItem *obj, NSUInteger i, BOOL *stop) {
        (void)i; (void)stop;
        return obj.pinned;
    }];
    self.storage = [[self.storage objectsAtIndexes:keep] mutableCopy];
    [self persist];
}

@end
