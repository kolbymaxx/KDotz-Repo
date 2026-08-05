#import "CC27.h"
#import <objc/message.h>

static const NSInteger kCC27PlusTag = 0x4332372B;      // C27+
static const NSInteger kCC27PowerTag = 0x43323750;     // C27P
static const NSInteger kCC27AddControlTag = 0x43323741; // C27A
static const NSInteger kCC27MinusTag = 0x4332372D;      // C27-
static const NSInteger kCC27ResizeTag = 0x43323752;     // C27R (legacy cleanup)
static const NSInteger kCC27ToastTag = 0x43323754;      // C27T

static char kCC27DragKey;
static char kCC27IdKey;

@interface CC27EditSession ()
@property (nonatomic, assign, readwrite, getter=isEditing) BOOL editing;
@property (nonatomic, assign, readwrite, getter=isHostVisible) BOOL hostVisible;
@property (nonatomic, strong) UILongPressGestureRecognizer *backgroundLongPress;
@property (nonatomic, copy) NSString *draggingIdentifier;
@property (nonatomic, weak) UIView *draggingView;

// Live-reflow drag state (home-screen style). The real CC-owned views are
// never repositioned: a snapshot follows the finger and neighbours preview
// with transforms, which survive CC layout passes and can't corrupt them.
@property (nonatomic, strong) UIView *dragSnapshot;
@property (nonatomic, strong) NSArray<UIView *> *dragSlotViews;      // original reading order
@property (nonatomic, strong) NSArray<NSValue *> *dragSlotCenters;   // original slot centers (host coords)
@property (nonatomic, strong) NSArray<NSString *> *dragSlotIds;
@property (nonatomic, assign) NSInteger dragOriginalIndex;
@property (nonatomic, assign) NSInteger dragProposedIndex;
@end

@implementation CC27EditSession

+ (instancetype)shared {
    static CC27EditSession *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shared = [self new];
    });
    return shared;
}

- (void)_haptic:(UIImpactFeedbackStyle)style {
    if (!CC27Prefs.shared.hapticFeedback) return;
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:style] impactOccurred];
}

#pragma mark - Glass chrome construction

// Adds a blur backing + hairline highlight + drop shadow to any control,
// giving it the layered "liquid glass" depth.
- (void)_glassifyView:(UIView *)view cornerRadius:(CGFloat)radius {
    view.backgroundColor = UIColor.clearColor;
    view.clipsToBounds = NO;
    view.layer.masksToBounds = NO;
    view.layer.shadowColor = UIColor.blackColor.CGColor;
    view.layer.shadowOpacity = 0.4;
    view.layer.shadowRadius = 9;
    view.layer.shadowOffset = CGSizeMake(0, 5);

    const NSInteger glassTag = 0x43323767; // 'C27g'
    if (![view viewWithTag:glassTag]) {
        UIBlurEffect *blur;
        if (@available(iOS 13.0, *)) {
            blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
        } else {
            blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
        }
        UIVisualEffectView *glass = [[UIVisualEffectView alloc] initWithEffect:blur];
        glass.tag = glassTag;
        glass.userInteractionEnabled = NO;
        glass.frame = view.bounds;
        glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        glass.layer.cornerRadius = radius;
        if (@available(iOS 13.0, *)) glass.layer.cornerCurve = kCACornerCurveContinuous;
        glass.clipsToBounds = YES;
        glass.layer.borderWidth = 0.6;
        glass.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.25].CGColor;

        // Top sheen for the 3-D pop.
        CAGradientLayer *sheen = [CAGradientLayer layer];
        sheen.colors = @[
            (id)[UIColor colorWithWhite:1.0 alpha:0.20].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.03].CGColor,
            (id)UIColor.clearColor.CGColor
        ];
        sheen.locations = @[ @0.0, @0.5, @1.0 ];
        sheen.frame = glass.bounds;
        [glass.contentView.layer addSublayer:sheen];

        [view insertSubview:glass atIndex:0];
    } else {
        UIView *glass = [view viewWithTag:glassTag];
        glass.layer.cornerRadius = radius;
    }
}

- (UIButton *)_circleButtonWithSymbol:(NSString *)symbol tag:(NSInteger)tag {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.tag = tag;
    if (@available(iOS 13.0, *)) {
        UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightSemibold];
        [btn setImage:[[UIImage systemImageNamed:symbol] imageByApplyingSymbolConfiguration:config] forState:UIControlStateNormal];
    }
    btn.tintColor = UIColor.whiteColor;
    [self _glassifyView:btn cornerRadius:18];
    btn.alpha = 0;
    return btn;
}

- (void)attachChromeToHost:(UIViewController *)host {
    if (!host || !CC27Prefs.shared.enabled) return;
    self.hostController = host;
    UIView *view = host.view;

    if (CC27Prefs.shared.showTopButtons) {
        if (![view viewWithTag:kCC27PlusTag]) {
            UIButton *plus = [self _circleButtonWithSymbol:@"plus" tag:kCC27PlusTag];
            [plus addTarget:self action:@selector(_plusTapped) forControlEvents:UIControlEventTouchUpInside];
            [view addSubview:plus];
        }
        if (![view viewWithTag:kCC27PowerTag]) {
            UIButton *power = [self _circleButtonWithSymbol:@"power" tag:kCC27PowerTag];
            if (@available(iOS 14.0, *)) {
                UIAction *respring = [UIAction actionWithTitle:@"Respring" image:[UIImage systemImageNamed:@"arrow.clockwise"] identifier:nil handler:^(__unused UIAction *a) {
                    [self _spawn:@[ @"/usr/bin/sbreload" ]];
                }];
                UIAction *uicache = [UIAction actionWithTitle:@"UICache" image:[UIImage systemImageNamed:@"paintbrush.fill"] identifier:nil handler:^(__unused UIAction *a) {
                    [self _spawn:@[ @"/usr/bin/uicache", @"-a" ]];
                }];
                UIAction *userspace = [UIAction actionWithTitle:@"Userspace Reboot" image:[UIImage systemImageNamed:@"bolt.fill"] identifier:nil handler:^(__unused UIAction *a) {
                    [self _spawn:@[ @"/bin/launchctl", @"reboot", @"userspace" ]];
                }];
                power.menu = [UIMenu menuWithTitle:@"" children:@[ respring, uicache, userspace ]];
                power.showsMenuAsPrimaryAction = YES;
            }
            [view addSubview:power];
        }
    }

    if (!self.backgroundLongPress && CC27Prefs.shared.editModeEnabled) {
        self.backgroundLongPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(_backgroundLongPressed:)];
        self.backgroundLongPress.minimumPressDuration = 0.45;
        [view addGestureRecognizer:self.backgroundLongPress];
    }

    if (self.hostVisible) {
        [self layoutChromeOnHost:host];
    }
}

- (void)_spawn:(NSArray<NSString *> *)args {
    if (args.count == 0) return;
    NSMutableArray<NSString *> *candidates = [NSMutableArray arrayWithObject:args.firstObject];
    NSString *leaf = args.firstObject.lastPathComponent;
    [candidates addObject:[@"/var/jb/usr/bin/" stringByAppendingString:leaf]];
    [candidates addObject:[@"/var/jb/bin/" stringByAppendingString:leaf]];
    const char *(*jbrootFn)(const char *) = (const char *(*)(const char *))dlsym(RTLD_DEFAULT, "jbroot");
    if (jbrootFn) {
        const char *p1 = jbrootFn([[@"/usr/bin/" stringByAppendingString:leaf] UTF8String]);
        const char *p2 = jbrootFn([[@"/bin/" stringByAppendingString:leaf] UTF8String]);
        if (p1) [candidates insertObject:[NSString stringWithUTF8String:p1] atIndex:0];
        if (p2) [candidates insertObject:[NSString stringWithUTF8String:p2] atIndex:0];
    }

    NSString *binary = nil;
    for (NSString *c in candidates) {
        if ([[NSFileManager defaultManager] isExecutableFileAtPath:c]) { binary = c; break; }
    }
    if (!binary) binary = args.firstObject;

    NSUInteger argc = args.count;
    char **argv = calloc(argc + 1, sizeof(char *));
    argv[0] = strdup(binary.UTF8String);
    for (NSUInteger i = 1; i < argc; i++) argv[i] = strdup(args[i].UTF8String);
    pid_t pid = 0;
    posix_spawn(&pid, argv[0], NULL, NULL, argv, environ);
    for (NSUInteger i = 0; i < argc; i++) free(argv[i]);
    free(argv);
}

- (void)setHostVisible:(BOOL)visible host:(UIViewController *)host {
    self.hostVisible = visible;
    if (host) self.hostController = host;
    if (visible) {
        [self attachChromeToHost:host ?: self.hostController];
        [self layoutChromeOnHost:host ?: self.hostController];
    } else {
        if (self.editing) [self exitEditModeAnimated:NO];
        UIView *view = (host ?: self.hostController).view;
        UIButton *plus = [view viewWithTag:kCC27PlusTag];
        UIButton *power = [view viewWithTag:kCC27PowerTag];
        plus.alpha = 0;
        power.alpha = 0;
    }
}

- (void)layoutChromeOnHost:(UIViewController *)host {
    if (!host) return;
    UIView *view = host.view;
    CGFloat safeTop = view.safeAreaInsets.top > 0 ? view.safeAreaInsets.top : 20;
    CGFloat safeLeft = view.safeAreaInsets.left > 0 ? view.safeAreaInsets.left : 16;
    CGFloat safeRight = view.safeAreaInsets.right > 0 ? view.safeAreaInsets.right : 16;

    UIButton *plus = [view viewWithTag:kCC27PlusTag];
    UIButton *power = [view viewWithTag:kCC27PowerTag];
    plus.frame = CGRectMake(safeLeft + 4, safeTop + 2, 36, 36);
    power.frame = CGRectMake(view.bounds.size.width - safeRight - 40, safeTop + 2, 36, 36);

    BOOL show = self.hostVisible && CC27Prefs.shared.showTopButtons;
    // No fade-out on intermediate presentation states — keep them up while CC is open.
    plus.alpha = show ? 1.0 : 0.0;
    power.alpha = show ? 1.0 : 0.0;
    plus.transform = CGAffineTransformIdentity;
    power.transform = CGAffineTransformIdentity;
    if (show) {
        [view bringSubviewToFront:plus];
        [view bringSubviewToFront:power];
    }

    if (self.editing) {
        [self _ensureAddControlButton];
        UIView *add = [view viewWithTag:kCC27AddControlTag];
        [view bringSubviewToFront:add];
    }
}

- (void)updateChromeForPresentationState:(NSInteger)state host:(UIViewController *)host {
    if (!host) return;
    // Known dismissed / dismissing values on iOS 15–17 modular CC.
    // Anything else while the overlay is up should keep chrome visible.
    BOOL dismissed = (state == 0 || state == 3 || state == 4);
    if (dismissed) {
        [self setHostVisible:NO host:host];
    } else {
        [self setHostVisible:YES host:host];
    }
}

- (void)_plusTapped {
    [self _haptic:UIImpactFeedbackStyleMedium];
    if (!self.editing) {
        [self enterEditModeAnimated:YES];
    } else {
        [self presentGalleryFrom:self.hostController];
    }
}

- (void)_backgroundLongPressed:(UILongPressGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateBegan) return;
    UIView *hit = [self.hostController.view hitTest:[gr locationInView:self.hostController.view] withEvent:nil];
    UIView *v = hit;
    while (v) {
        if ([v isKindOfClass:NSClassFromString(@"CCUIContentModuleContentContainerView")]) return;
        v = v.superview;
    }
    [self _haptic:UIImpactFeedbackStyleMedium];
    [self toggleEditMode];
}

- (void)toggleEditMode {
    if (self.editing) [self exitEditModeAnimated:YES];
    else [self enterEditModeAnimated:YES];
}

- (void)enterEditModeAnimated:(BOOL)animated {
    if (!CC27Prefs.shared.editModeEnabled || self.editing) return;
    self.editing = YES;
    [self _ensureAddControlButton];
    [self _decorateVisibleModules];
    UIView *add = [self.hostController.view viewWithTag:kCC27AddControlTag];
    void (^work)(void) = ^{
        add.alpha = 1;
        add.transform = CGAffineTransformIdentity;
    };
    if (animated) {
        add.transform = CGAffineTransformMakeTranslation(0, 20);
        [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.85 initialSpringVelocity:0.4 options:0 animations:work completion:nil];
    } else {
        work();
    }
    [self layoutChromeOnHost:self.hostController];
}

- (void)exitEditModeAnimated:(BOOL)animated {
    if (!self.editing) return;
    self.editing = NO;
    UIView *add = [self.hostController.view viewWithTag:kCC27AddControlTag];
    void (^work)(void) = ^{
        add.alpha = 0;
        add.transform = CGAffineTransformMakeTranslation(0, 16);
    };
    if (animated) {
        [UIView animateWithDuration:0.2 animations:work completion:^(__unused BOOL finished) {
            [self undecorateAll];
        }];
    } else {
        work();
        [self undecorateAll];
    }
}

- (void)_ensureAddControlButton {
    UIView *host = self.hostController.view;
    UIButton *add = [host viewWithTag:kCC27AddControlTag];
    if (!add) {
        add = [UIButton buttonWithType:UIButtonTypeSystem];
        add.tag = kCC27AddControlTag;
        add.tintColor = UIColor.whiteColor;
        [add setTitle:@"  Add a Control" forState:UIControlStateNormal];
        add.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
        if (@available(iOS 13.0, *)) {
            [add setImage:[UIImage systemImageNamed:@"plus"] forState:UIControlStateNormal];
        }
        [self _glassifyView:add cornerRadius:22];
        add.alpha = 0;
        [add addTarget:self action:@selector(_addControlTapped) forControlEvents:UIControlEventTouchUpInside];
        [host addSubview:add];
    }
    CGFloat w = MIN(220, host.bounds.size.width - 48);
    CGFloat y = host.bounds.size.height - host.safeAreaInsets.bottom - 56;
    add.frame = CGRectMake((host.bounds.size.width - w) / 2.0, y, w, 44);
    [host bringSubviewToFront:add];
}

- (void)_addControlTapped {
    [self _haptic:UIImpactFeedbackStyleLight];
    [self presentGalleryFrom:self.hostController];
}

- (void)presentGalleryFrom:(UIViewController *)presenter {
    if (!presenter) return;
    [CC27ModuleCatalog.shared reload];
    CC27GalleryController *gallery = [[CC27GalleryController alloc] initWithCatalog:CC27ModuleCatalog.shared];
    if (@available(iOS 15.0, *)) {
        gallery.modalPresentationStyle = UIModalPresentationPageSheet;
        UISheetPresentationController *sheet = gallery.sheetPresentationController;
        sheet.detents = @[ [UISheetPresentationControllerDetent mediumDetent],
                           [UISheetPresentationControllerDetent largeDetent] ];
        sheet.selectedDetentIdentifier = UISheetPresentationControllerDetentIdentifierLarge;
        sheet.prefersGrabberVisible = YES;
        sheet.preferredCornerRadius = 34;
    } else {
        gallery.modalPresentationStyle = UIModalPresentationFormSheet;
    }
    [presenter presentViewController:gallery animated:YES completion:nil];
}

- (void)dismissControlCenter {
    UIViewController *host = self.hostController;
    if (!host) return;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    for (NSString *name in @[ @"dismissAnimated:", @"_dismissAnimated:", @"dismissControlCenter" ]) {
        SEL sel = NSSelectorFromString(name);
        if (![host respondsToSelector:sel]) continue;
        if ([name hasSuffix:@":"]) {
            ((void (*)(id, SEL, BOOL))objc_msgSend)(host, sel, YES);
        } else {
            [host performSelector:sel];
        }
        break;
    }
#pragma clang diagnostic pop
}

- (void)showToast:(NSString *)message {
    UIView *host = self.hostController.view;
    if (!host || message.length == 0) return;
    [[host viewWithTag:kCC27ToastTag] removeFromSuperview];

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.text = message;
    label.textColor = UIColor.whiteColor;
    label.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 2;

    CGSize fit = [label sizeThatFits:CGSizeMake(host.bounds.size.width - 48, 80)];
    CGFloat w = MIN(host.bounds.size.width - 40, MAX(180, fit.width + 32));
    CGFloat h = MAX(42, fit.height + 18);

    UIView *toast = [[UIView alloc] initWithFrame:CGRectMake((host.bounds.size.width - w) / 2.0,
                                                             host.safeAreaInsets.top + 52, w, h)];
    toast.tag = kCC27ToastTag;
    [self _glassifyView:toast cornerRadius:h / 2.0];
    label.frame = toast.bounds;
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [toast addSubview:label];
    toast.alpha = 0;
    toast.transform = CGAffineTransformMakeTranslation(0, -8);
    [host addSubview:toast];
    [host bringSubviewToFront:toast];

    [UIView animateWithDuration:0.25 delay:0 usingSpringWithDamping:0.85 initialSpringVelocity:0.3 options:0 animations:^{
        toast.alpha = 1;
        toast.transform = CGAffineTransformIdentity;
    } completion:^(__unused BOOL f) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.7 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [UIView animateWithDuration:0.25 animations:^{
                toast.alpha = 0;
                toast.transform = CGAffineTransformMakeTranslation(0, -8);
            } completion:^(__unused BOOL f2) {
                [toast removeFromSuperview];
            }];
        });
    }];
}

#pragma mark - Module decoration

- (NSString *)_identifierForContainer:(UIView *)container {
    UIView *v = container;
    while (v) {
        UIViewController *vc = nil;
        @try { vc = [v valueForKey:@"_viewDelegate"]; } @catch (__unused NSException *e) {}
        if (!vc) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            SEL sel = NSSelectorFromString(@"_viewControllerForAncestor");
            if ([v respondsToSelector:sel]) vc = [v performSelector:sel];
#pragma clang diagnostic pop
        }
        if ([vc isKindOfClass:NSClassFromString(@"CCUIContentModuleContainerViewController")]) {
            NSString *identifier = nil;
            @try { identifier = [vc valueForKey:@"moduleIdentifier"]; } @catch (__unused NSException *e) {}
            if (identifier.length) return identifier;
        }
        v = v.superview;
    }
    return nil;
}

- (void)_decorateVisibleModules {
    UIView *root = self.hostController.view;
    if (!root) return;
    NSMutableArray<UIView *> *containers = [NSMutableArray array];
    [self _collectContainers:root into:containers];
    for (UIView *container in containers) {
        NSString *identifier = [self _identifierForContainer:container];
        if (identifier.length) [self decorateModuleContainer:container identifier:identifier];
    }
}

- (void)_collectContainers:(UIView *)view into:(NSMutableArray *)out {
    if ([view isKindOfClass:NSClassFromString(@"CCUIContentModuleContentContainerView")]) {
        [out addObject:view];
    }
    for (UIView *sub in view.subviews) [self _collectContainers:sub into:out];
}

- (void)decorateModuleContainer:(UIView *)container identifier:(NSString *)identifier {
    if (!container || !self.editing) return;

    // Skip decorating expanded popovers.
    if (container.bounds.size.width > 220.0 || container.bounds.size.height > 220.0) {
        [[container viewWithTag:kCC27MinusTag] removeFromSuperview];
        [[container viewWithTag:kCC27ResizeTag] removeFromSuperview];
        [container.layer removeAnimationForKey:@"cc27.jiggle"];
        return;
    }

    // Fixed system modules can't be removed, so no minus badge on them.
    BOOL isFixed = [CC27LayoutStore.shared isModuleFixed:identifier] &&
                   ![CC27LayoutStore.shared.enabledIdentifiers containsObject:identifier];

<<<<<<< HEAD
    UIButton *minus = [container viewWithTag:kCC27MinusTag];
    if (isFixed) {
        [minus removeFromSuperview];
    } else {
        if (!minus) {
            minus = [UIButton buttonWithType:UIButtonTypeSystem];
            minus.tag = kCC27MinusTag;
            minus.backgroundColor = [UIColor colorWithWhite:0.16 alpha:0.94];
            minus.tintColor = UIColor.whiteColor;
            minus.layer.cornerRadius = 11;
            minus.clipsToBounds = YES;
            minus.layer.borderWidth = 0.6;
            minus.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.3].CGColor;
            if (@available(iOS 13.0, *)) {
                UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:11 weight:UIImageSymbolWeightBold];
                [minus setImage:[[UIImage systemImageNamed:@"minus"] imageByApplyingSymbolConfiguration:config] forState:UIControlStateNormal];
            }
            [minus addTarget:self action:@selector(_minusTapped:) forControlEvents:UIControlEventTouchUpInside];
            [container addSubview:minus];
        }
        minus.frame = CGRectMake(-4, -4, 22, 22);
        [container bringSubviewToFront:minus];
    }
=======
    // Resize is disabled in 1.0.2 — previous size overrides crashed SpringBoard.
    [[container viewWithTag:kCC27ResizeTag] removeFromSuperview];
>>>>>>> origin/main

    // Resize stays disabled — size overrides crashed SpringBoard (1.0.2).
    [[container viewWithTag:kCC27ResizeTag] removeFromSuperview];

    if (![container.layer animationForKey:@"cc27.jiggle"]) {
        CAKeyframeAnimation *anim = [CAKeyframeAnimation animationWithKeyPath:@"transform.rotation.z"];
        anim.values = @[ @(-0.015), @(0.015), @(-0.015) ];
        anim.duration = 0.25;
        anim.repeatCount = HUGE_VALF;
        anim.removedOnCompletion = NO;
        anim.beginTime = CACurrentMediaTime() + ((uintptr_t)container % 7) * 0.02;
        [container.layer addAnimation:anim forKey:@"cc27.jiggle"];
    }

    if (![objc_getAssociatedObject(container, &kCC27DragKey) boolValue]) {
        UILongPressGestureRecognizer *drag = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(_dragModule:)];
        drag.minimumPressDuration = 0.15;
        [container addGestureRecognizer:drag];
        objc_setAssociatedObject(container, &kCC27DragKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(container, &kCC27IdKey, identifier, OBJC_ASSOCIATION_COPY_NONATOMIC);
    } else {
        objc_setAssociatedObject(container, &kCC27IdKey, identifier, OBJC_ASSOCIATION_COPY_NONATOMIC);
    }
}

- (void)undecorateAll {
    UIView *root = self.hostController.view;
    if (!root) return;
    NSMutableArray *containers = [NSMutableArray array];
    [self _collectContainers:root into:containers];
    for (UIView *container in containers) {
        [[container viewWithTag:kCC27MinusTag] removeFromSuperview];
        [[container viewWithTag:kCC27ResizeTag] removeFromSuperview];
        [container.layer removeAnimationForKey:@"cc27.jiggle"];
        container.transform = CGAffineTransformIdentity;
    }
}

- (void)_minusTapped:(UIButton *)sender {
    UIView *container = sender.superview;
    NSString *identifier = objc_getAssociatedObject(container, &kCC27IdKey) ?: [self _identifierForContainer:container];
    if (!identifier) return;
    [self _haptic:UIImpactFeedbackStyleMedium];
    [CC27LayoutStore.shared disableModule:identifier];
    [self performSelector:@selector(_decorateVisibleModules) withObject:nil afterDelay:0.35];
}

<<<<<<< HEAD
#pragma mark - Home-screen style drag with live reflow

// Reading-order slots: all small module containers sorted top-to-bottom, left-to-right.
- (void)_captureDragSlotsExcludingNone {
    UIView *host = self.hostController.view;
    NSMutableArray<UIView *> *containers = [NSMutableArray array];
    [self _collectContainers:host into:containers];

    NSMutableArray<UIView *> *cells = [NSMutableArray array];
    for (UIView *c in containers) {
        if (c.bounds.size.width > 220.0 || c.bounds.size.height > 220.0) continue;
        [cells addObject:c];
    }
    [cells sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        CGPoint pa = [a.superview convertPoint:a.center toView:host];
        CGPoint pb = [b.superview convertPoint:b.center toView:host];
        if (fabs(pa.y - pb.y) > 20.0) return pa.y < pb.y ? NSOrderedAscending : NSOrderedDescending;
        if (pa.x == pb.x) return NSOrderedSame;
        return pa.x < pb.x ? NSOrderedAscending : NSOrderedDescending;
    }];

    NSMutableArray<NSValue *> *centers = [NSMutableArray array];
    NSMutableArray<NSString *> *ids = [NSMutableArray array];
    for (UIView *c in cells) {
        CGPoint p = [c.superview convertPoint:c.center toView:host];
        [centers addObject:[NSValue valueWithCGPoint:p]];
        NSString *identifier = objc_getAssociatedObject(c, &kCC27IdKey) ?: [self _identifierForContainer:c] ?: @"";
        [ids addObject:identifier];
    }
    self.dragSlotViews = cells;
    self.dragSlotCenters = centers;
    self.dragSlotIds = ids;
}

- (NSInteger)_slotIndexNearestToPoint:(CGPoint)p {
    NSInteger best = NSNotFound;
    CGFloat bestDist = CGFLOAT_MAX;
    for (NSUInteger i = 0; i < self.dragSlotCenters.count; i++) {
        CGPoint c = [self.dragSlotCenters[i] CGPointValue];
        CGFloat d = hypot(c.x - p.x, c.y - p.y);
        if (d < bestDist) { bestDist = d; best = (NSInteger)i; }
    }
    return best;
}

// Animate every non-dragged module toward the slot it would occupy if the
// dragged module were dropped at `proposedIndex` — the home-screen reflow.
// Uses transforms only: CC's layout passes overwrite frames/centers, but they
// leave `transform` alone, so the preview is stable and fully reversible.
- (void)_previewReflowToIndex:(NSInteger)proposedIndex {
    if (proposedIndex == NSNotFound || !self.dragSlotViews.count) return;
    UIView *dragged = self.draggingView;

    NSMutableArray<UIView *> *order = self.dragSlotViews.mutableCopy;
    if (dragged) [order removeObject:dragged];
    NSInteger clamped = MAX(0, MIN(proposedIndex, (NSInteger)order.count));
    if (dragged) [order insertObject:dragged atIndex:clamped];

    [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.3
                        options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        for (NSUInteger slot = 0; slot < order.count && slot < self.dragSlotCenters.count; slot++) {
            UIView *v = order[slot];
            if (v == dragged) continue; // the snapshot follows the finger instead
            NSUInteger home = [self.dragSlotViews indexOfObject:v];
            if (home == NSNotFound) continue;
            CGPoint from = [self.dragSlotCenters[home] CGPointValue];
            CGPoint to = [self.dragSlotCenters[slot] CGPointValue];
            v.transform = CGAffineTransformMakeTranslation(to.x - from.x, to.y - from.y);
        }
    } completion:nil];
}

- (void)_endDragCommitting:(BOOL)commit {
    UIView *container = self.draggingView;
    NSString *identifier = self.draggingIdentifier;
    NSInteger proposed = self.dragProposedIndex;
    NSInteger original = self.dragOriginalIndex;
    UIView *snapshot = self.dragSnapshot;
    NSArray<UIView *> *slotViews = self.dragSlotViews;
    NSArray<NSValue *> *centers = self.dragSlotCenters;
    NSArray<NSString *> *slotIds = self.dragSlotIds;

    BOOL wantsMove = commit && identifier.length &&
                     proposed != NSNotFound && proposed != original;

    // Land the snapshot on its slot, then reveal the real module again.
    CGPoint landing = (proposed != NSNotFound && proposed < (NSInteger)centers.count)
        ? [centers[proposed] CGPointValue]
        : (original != NSNotFound && original < (NSInteger)centers.count
            ? [centers[original] CGPointValue] : snapshot.center);

    [UIView animateWithDuration:0.25 delay:0 usingSpringWithDamping:0.85 initialSpringVelocity:0.3 options:0 animations:^{
        snapshot.center = landing;
        snapshot.transform = CGAffineTransformIdentity;
    } completion:^(__unused BOOL done) {
        [snapshot removeFromSuperview];
        container.alpha = 1.0;
        for (UIView *v in slotViews) v.transform = CGAffineTransformIdentity;

        if (wantsMove) {
            // Convert the visual slot index into an index in the persisted
            // user-enabled list: count enabled modules occupying slots before
            // the proposed slot (fixed modules aren't reorderable).
            @try {
                NSArray *enabledOrder = CC27LayoutStore.shared.enabledIdentifiers;
                NSUInteger target = 0;
                for (NSInteger i = 0; i < proposed && i < (NSInteger)slotIds.count; i++) {
                    NSString *slotId = slotIds[i];
                    if ([slotId isEqualToString:identifier]) continue;
                    if ([enabledOrder containsObject:slotId]) target++;
                }
                if ([CC27LayoutStore.shared moveModule:identifier toIndex:target]) {
                    [self _haptic:UIImpactFeedbackStyleMedium];
                }
            } @catch (NSException *e) {
                NSLog(@"[CC27] drag commit threw: %@", e);
            }
        }

        [self performSelector:@selector(_decorateVisibleModules) withObject:nil afterDelay:0.4];
    }];

    self.draggingIdentifier = nil;
    self.draggingView = nil;
    self.dragSnapshot = nil;
    self.dragSlotViews = nil;
    self.dragSlotCenters = nil;
    self.dragSlotIds = nil;
=======
- (void)_resizeTapped:(UIButton *)sender {
    (void)sender;
    // Intentionally disabled — resizing via CCUILayoutSize overrides caused SpringBoard safe mode.
>>>>>>> origin/main
}

- (void)_dragModule:(UILongPressGestureRecognizer *)gr {
    if (!self.editing) return;
    UIView *container = gr.view;
    NSString *identifier = objc_getAssociatedObject(container, &kCC27IdKey) ?: [self _identifierForContainer:container];
    if (!identifier) return;
    UIView *host = self.hostController.view;

    switch (gr.state) {
        case UIGestureRecognizerStateBegan: {
            self.draggingIdentifier = identifier;
            self.draggingView = container;
            [self _captureDragSlotsExcludingNone];
            self.dragOriginalIndex = (NSInteger)[self.dragSlotViews indexOfObject:container];
            self.dragProposedIndex = self.dragOriginalIndex;

            // Freeze the module into a snapshot the finger can move freely —
            // CC keeps owning the real view, so its layout can't fight us and
            // we can't corrupt it.
            [container.layer removeAnimationForKey:@"cc27.jiggle"];
            UIView *snapshot = [container snapshotViewAfterScreenUpdates:NO];
            if (!snapshot) {
                self.draggingIdentifier = nil;
                self.draggingView = nil;
                self.dragSlotViews = nil;
                self.dragSlotCenters = nil;
                self.dragSlotIds = nil;
                return;
            }
            CGRect frame = [container.superview convertRect:container.frame toView:host];
            snapshot.frame = frame;
            snapshot.layer.zPosition = 2000;
            snapshot.layer.shadowColor = UIColor.blackColor.CGColor;
            snapshot.layer.shadowOpacity = 0.45;
            snapshot.layer.shadowRadius = 16;
            snapshot.layer.shadowOffset = CGSizeMake(0, 10);
            snapshot.userInteractionEnabled = NO;
            [host addSubview:snapshot];
            self.dragSnapshot = snapshot;
            container.alpha = 0.06; // leave a faint ghost in the vacated slot

            [self _haptic:UIImpactFeedbackStyleMedium];
            [UIView animateWithDuration:0.15 animations:^{
                snapshot.transform = CGAffineTransformMakeScale(1.08, 1.08);
            }];
            break;
        }
        case UIGestureRecognizerStateChanged: {
            CGPoint p = [gr locationInView:host];
            self.dragSnapshot.center = p;

            NSInteger proposed = [self _slotIndexNearestToPoint:p];
            if (proposed != NSNotFound && proposed != self.dragProposedIndex) {
                self.dragProposedIndex = proposed;
                [self _haptic:UIImpactFeedbackStyleLight];
                [self _previewReflowToIndex:proposed];
            }
            break;
        }
        case UIGestureRecognizerStateEnded: {
            [self _endDragCommitting:YES];
            break;
        }
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed: {
            [self _endDragCommitting:NO];
            break;
        }
        default:
            break;
    }
}

@end
