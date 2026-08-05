#import "AESculptStore.h"
#import "AEPrefs.h"

NSString *AEViewFingerprint(UIView *view) {
    if (!view) return nil;
    NSMutableArray *parts = [NSMutableArray array];
    UIView *v = view;
    while (v) {
        NSString *cls = NSStringFromClass(v.class);
        NSString *aid = v.accessibilityIdentifier ?: @"";
        NSInteger idx = 0;
        if (v.superview) {
            idx = [v.superview.subviews indexOfObjectIdenticalTo:v];
            if (idx == NSNotFound) idx = 0;
        }
        [parts insertObject:[NSString stringWithFormat:@"%@#%ld@%@", cls, (long)idx, aid] atIndex:0];
        v = v.superview;
        // Cap depth so fingerprints stay stable-ish
        if (parts.count > 12) break;
    }
    return [parts componentsJoinedByString:@"/"];
}

@interface AESculptStore ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *map;
@end

@implementation AESculptStore

+ (instancetype)shared {
    static AESculptStore *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [AESculptStore new]; });
    return s;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _map = [NSMutableDictionary dictionary];
        [self load];
    }
    return self;
}

- (NSString *)path {
    return [AEDataDirectory() stringByAppendingPathComponent:@"sculpt.plist"];
}

- (void)load {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:self.path];
    if (![d isKindOfClass:[NSDictionary class]]) return;
    for (NSString *key in d) {
        id val = d[key];
        if ([val isKindOfClass:[NSArray class]]) {
            self.map[key] = [val mutableCopy];
        }
    }
}

- (void)persist {
    [self.map writeToFile:self.path atomically:YES];
}

- (NSSet<NSString *> *)hiddenFingerprintsForBundle:(NSString *)bundleID {
    NSArray *arr = self.map[bundleID] ?: @[];
    return [NSSet setWithArray:arr];
}

- (void)hideFingerprint:(NSString *)fp forBundle:(NSString *)bundleID {
    if (!fp.length || !bundleID.length) return;
    NSMutableArray *arr = self.map[bundleID];
    if (!arr) {
        arr = [NSMutableArray array];
        self.map[bundleID] = arr;
    }
    if (![arr containsObject:fp]) {
        [arr addObject:fp];
        [self persist];
    }
}

- (void)unhideFingerprint:(NSString *)fp forBundle:(NSString *)bundleID {
    NSMutableArray *arr = self.map[bundleID];
    if (!arr) return;
    [arr removeObject:fp];
    if (arr.count == 0) [self.map removeObjectForKey:bundleID];
    [self persist];
}

- (void)clearBundle:(NSString *)bundleID {
    [self.map removeObjectForKey:bundleID];
    [self persist];
}

- (NSInteger)countForBundle:(NSString *)bundleID {
    return (NSInteger)(self.map[bundleID].count);
}

- (void)applyToWindow:(UIWindow *)window bundleID:(NSString *)bundleID {
    if (!AEPrefBool(@"sculptEnabled", YES)) return;
    NSSet *hidden = [self hiddenFingerprintsForBundle:bundleID];
    if (hidden.count == 0) return;
    [self walk:window hide:hidden];
}

- (void)walk:(UIView *)view hide:(NSSet<NSString *> *)hidden {
    NSString *fp = AEViewFingerprint(view);
    if (fp && [hidden containsObject:fp]) {
        view.hidden = YES;
        view.userInteractionEnabled = NO;
    }
    for (UIView *sub in view.subviews) {
        [self walk:sub hide:hidden];
    }
}

@end
