#import "AEGestureHost.h"
#import "AEPrefs.h"
#import "AESculptStore.h"

@interface AESculptOverlay : UIView
@property (nonatomic, copy, nullable) void (^onPick)(UIView *target);
@property (nonatomic, copy, nullable) void (^onCancel)(void);
@end

@implementation AESculptOverlay

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithRed:0.05 green:0.12 blue:0.16 alpha:0.35];
        self.accessibilityLabel = @"Aether Sculpt Mode";
        UILabel *hint = [UILabel new];
        hint.text = @"Sculpt — tap a view to hide it · two-finger tap to cancel";
        hint.textAlignment = NSTextAlignmentCenter;
        hint.textColor = UIColor.whiteColor;
        hint.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        hint.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
        hint.layer.cornerRadius = 12;
        hint.clipsToBounds = YES;
        hint.tag = 9001;
        [self addSubview:hint];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    UIView *hint = [self viewWithTag:9001];
    hint.frame = CGRectMake(20, self.safeAreaInsets.top + 12, self.bounds.size.width - 40, 36);
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    (void)event;
    // Never claim the hint chrome for picking
    UIView *hint = [self viewWithTag:9001];
    if (CGRectContainsPoint(hint.frame, point)) return self;
    return self; // we handle all taps
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    (void)event;
    UITouch *t = touches.anyObject;
    if (t.tapCount >= 1 && touches.count >= 2) {
        if (self.onCancel) self.onCancel();
        return;
    }
    CGPoint p = [t locationInView:self];
    UIView *hint = [self viewWithTag:9001];
    if (CGRectContainsPoint(hint.frame, p)) return;

    self.hidden = YES; // allow hit-testing through
    UIWindow *win = self.window;
    UIView *hit = [win hitTest:[t locationInView:win] withEvent:nil];
    self.hidden = NO;
    if (!hit || hit == win || hit == self) return;
    // Prefer a meaningful ancestor (avoid tiny labels inside buttons)
    UIView *target = hit;
    while (target.superview && target.bounds.size.width * target.bounds.size.height < 40 * 40) {
        target = target.superview;
    }
    if (self.onPick) self.onPick(target);
}

@end

@interface AEGestureHost () <UIGestureRecognizerDelegate>
@property (nonatomic, strong) NSMapTable<UIWindow *, NSHashTable<UIGestureRecognizer *> *> *gesturesByWindow;
@property (nonatomic, strong, nullable) AESculptOverlay *sculptOverlay;
@property (nonatomic, weak, nullable) UIWindow *sculptWindow;
@end

@implementation AEGestureHost

+ (instancetype)shared {
    static AEGestureHost *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [AEGestureHost new]; });
    return s;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _gesturesByWindow = [NSMapTable weakToStrongObjectsMapTable];
    }
    return self;
}

- (void)attachToWindow:(UIWindow *)window {
    if (!window || window == self.sculptOverlay.window) return;
    // Skip our own panel host if tagged
    if ([window.accessibilityIdentifier isEqualToString:@"AetherInternal"]) return;

    NSHashTable *set = [self.gesturesByWindow objectForKey:window];
    if (set) return;
    set = [NSHashTable weakObjectsHashTable];

    NSString *mode = AEPrefString(@"summonGesture", @"twoFingerDoubleTap");

    if ([mode isEqualToString:@"twoFingerDoubleTap"] || [mode isEqualToString:@"both"]) {
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(summon:)];
        tap.numberOfTapsRequired = 2;
        tap.numberOfTouchesRequired = 2;
        tap.delegate = self;
        tap.cancelsTouchesInView = NO;
        [window addGestureRecognizer:tap];
        [set addObject:tap];
    }

    if ([mode isEqualToString:@"threeFingerSwipeDown"] || [mode isEqualToString:@"both"]) {
        UISwipeGestureRecognizer *swipe = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(summon:)];
        swipe.direction = UISwipeGestureRecognizerDirectionDown;
        swipe.numberOfTouchesRequired = 3;
        swipe.delegate = self;
        swipe.cancelsTouchesInView = NO;
        [window addGestureRecognizer:swipe];
        [set addObject:swipe];
    }

    [self.gesturesByWindow setObject:set forKey:window];
}

- (void)detachFromWindow:(UIWindow *)window {
    NSHashTable *set = [self.gesturesByWindow objectForKey:window];
    for (UIGestureRecognizer *g in set) {
        [window removeGestureRecognizer:g];
    }
    [self.gesturesByWindow removeObjectForKey:window];
}

- (void)summon:(UIGestureRecognizer *)gr {
    (void)gr;
    if (!AEPrefBool(@"enabled", YES)) return;
    if (self.sculptModeActive) {
        [self endSculpt];
        [self.delegate gestureHostDidCancelSculpt];
        return;
    }
    [self.delegate gestureHostDidSummon];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    (void)gestureRecognizer; (void)other;
    return YES;
}

- (void)beginSculptInWindow:(UIWindow *)window {
    [self endSculpt];
    self.sculptModeActive = YES;
    self.sculptWindow = window;
    AESculptOverlay *overlay = [[AESculptOverlay alloc] initWithFrame:window.bounds];
    overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    __weak typeof(self) weakSelf = self;
    overlay.onCancel = ^{
        [weakSelf endSculpt];
        [weakSelf.delegate gestureHostDidCancelSculpt];
    };
    overlay.onPick = ^(UIView *target) {
        NSString *fp = AEViewFingerprint(target);
        NSString *bid = AECurrentBundleID();
        if (!fp) return;
        [[AESculptStore shared] hideFingerprint:fp forBundle:bid];
        target.hidden = YES;
        target.userInteractionEnabled = NO;
        UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [gen impactOccurred];
    };
    [window addSubview:overlay];
    self.sculptOverlay = overlay;
}

- (void)endSculpt {
    self.sculptModeActive = NO;
    [self.sculptOverlay removeFromSuperview];
    self.sculptOverlay = nil;
    self.sculptWindow = nil;
}

@end
