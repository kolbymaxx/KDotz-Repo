#import "Music27.h"

@implementation M27PinnedItem

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.identifier forKey:@"identifier"];
    [coder encodeObject:self.title forKey:@"title"];
    [coder encodeObject:self.subtitle forKey:@"subtitle"];
    [coder encodeInteger:self.type forKey:@"type"];
    [coder encodeObject:self.artworkJPEG forKey:@"artworkJPEG"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if ((self = [super init])) {
        _identifier = [[coder decodeObjectOfClass:NSString.class forKey:@"identifier"] copy];
        _title = [[coder decodeObjectOfClass:NSString.class forKey:@"title"] copy];
        _subtitle = [[coder decodeObjectOfClass:NSString.class forKey:@"subtitle"] copy];
        _type = [coder decodeIntegerForKey:@"type"];
        _artworkJPEG = [coder decodeObjectOfClass:NSData.class forKey:@"artworkJPEG"];
    }
    return self;
}

@end

@implementation M27PinStore {
    NSUserDefaults *_defaults;
    NSMutableArray<M27PinnedItem *> *_mutablePins;
}

+ (instancetype)shared {
    static M27PinStore *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shared = [self new];
    });
    return shared;
}

- (instancetype)init {
    if ((self = [super init])) {
        _defaults = [[NSUserDefaults alloc] initWithSuiteName:M27PrefDomain];
        _mutablePins = [NSMutableArray new];
        [self _load];
    }
    return self;
}

- (void)_load {
    NSData *data = [_defaults objectForKey:@"pins"];
    if (![data isKindOfClass:NSData.class]) return;
    NSSet *classes = [NSSet setWithObjects:NSArray.class, M27PinnedItem.class,
                      NSString.class, NSData.class, nil];
    NSArray *stored = [NSKeyedUnarchiver unarchivedObjectOfClasses:classes fromData:data error:nil];
    if ([stored isKindOfClass:NSArray.class]) {
        [_mutablePins setArray:stored];
    }
}

- (void)_save {
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:_mutablePins
                                         requiringSecureCoding:YES
                                                         error:nil];
    if (data) {
        [_defaults setObject:data forKey:@"pins"];
        [_defaults synchronize];
    }
    [NSNotificationCenter.defaultCenter postNotificationName:M27PinsDidChangeNotification object:nil];
}

- (NSArray<M27PinnedItem *> *)pins {
    return [NSArray arrayWithArray:_mutablePins];
}

- (BOOL)isPinned:(NSString *)identifier {
    if (identifier.length == 0) return NO;
    for (M27PinnedItem *item in _mutablePins) {
        if ([item.identifier isEqualToString:identifier]) return YES;
    }
    return NO;
}

- (BOOL)pinItem:(M27PinnedItem *)item error:(NSError **)error {
    if (item.identifier.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:M27PrefDomain code:1
                                     userInfo:@{ NSLocalizedDescriptionKey: @"Missing identifier" }];
        }
        return NO;
    }
    if ([self isPinned:item.identifier]) return YES;
    if ((NSInteger)_mutablePins.count >= M27MaxPins) {
        if (error) {
            NSString *message = [NSString stringWithFormat:
                @"You can pin up to %ld items. Unpin one first.", (long)M27MaxPins];
            *error = [NSError errorWithDomain:M27PrefDomain code:2
                                     userInfo:@{ NSLocalizedDescriptionKey: message }];
        }
        return NO;
    }
    [_mutablePins insertObject:item atIndex:0];
    [self _save];
    return YES;
}

- (void)unpinIdentifier:(NSString *)identifier {
    if (identifier.length == 0) return;
    NSInteger found = NSNotFound;
    for (NSUInteger i = 0; i < _mutablePins.count; i++) {
        if ([_mutablePins[i].identifier isEqualToString:identifier]) { found = i; break; }
    }
    if (found != NSNotFound) {
        [_mutablePins removeObjectAtIndex:found];
        [self _save];
    }
}

- (void)movePinAtIndex:(NSInteger)from toIndex:(NSInteger)to {
    if (from < 0 || to < 0 || from >= (NSInteger)_mutablePins.count || to >= (NSInteger)_mutablePins.count) return;
    M27PinnedItem *item = _mutablePins[from];
    [_mutablePins removeObjectAtIndex:from];
    [_mutablePins insertObject:item atIndex:to];
    [self _save];
}

- (void)clearAll {
    if (_mutablePins.count == 0) return;
    [_mutablePins removeAllObjects];
    [self _save];
}

@end
