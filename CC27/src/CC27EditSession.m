#import "CC27.h"

static const NSInteger kCC27PlusTag = 0x4332372B;      // C27+
static const NSInteger kCC27PowerTag = 0x43323750;     // C27P
static const NSInteger kCC27AddControlTag = 0x43323741; // C27A
static const NSInteger kCC27MinusTag = 0x4332372D;      // C27-
static const NSInteger kCC27ResizeTag = 0x43323752;     // C27R

static char kCC27DragKey;
static char kCC27IdKey;

@interface CC27EditSession ()
@property (nonatomic, assign, readwrite, getter=isEditing) BOOL editing;
@property (nonatomic, strong) UILongPressGestureRecognizer *backgroundLongPress;
@property (nonatomic, copy) NSString *draggingIdentifier;
@property (nonatomic, weak) UIView *draggingView;
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

- (UIButton *)_circleButtonWithSymbol:(NSString *)symbol tag:(NSInteger)tag {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.tag = tag;
    if (@available(iOS 13.0, *)) {
        UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightSemibold];
        [btn setImage:[[UIImage systemImageNamed:symbol] imageByApplyingSymbolConfiguration:config] forState:UIControlStateNormal];
    }
    btn.tintColor = UIColor.whiteColor;
    btn.backgroundColor = [UIColor colorWithWhite:1 alpha:0.14];
    btn.layer.cornerRadius = 18;
    btn.clipsToBounds = YES;
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

- (void)updateChromeForPresentationState:(NSInteger)state host:(UIViewController *)host {
    if (!host) return;
    [self attachChromeToHost:host];
    UIView *view = host.view;
    CGFloat safeTop = view.safeAreaInsets.top > 0 ? view.safeAreaInsets.top : 20;
    CGFloat safeLeft = view.safeAreaInsets.left > 0 ? view.safeAreaInsets.left : 16;
    CGFloat safeRight = view.safeAreaInsets.right > 0 ? view.safeAreaInsets.right : 16;
    UIButton *plus = [view viewWithTag:kCC27PlusTag];
    UIButton *power = [view viewWithTag:kCC27PowerTag];
    plus.frame = CGRectMake(safeLeft + 4, safeTop + 2, 36, 36);
    power.frame = CGRectMake(view.bounds.size.width - safeRight - 40, safeTop + 2, 36, 36);

    BOOL presented = (state == 1); // presented
    [UIView animateWithDuration:presented ? 0.4 : 0.2 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.4 options:0 animations:^{
        plus.alpha = presented && CC27Prefs.shared.showTopButtons ? 1 : 0;
        power.alpha = presented && CC27Prefs.shared.showTopButtons ? 1 : 0;
        plus.transform = presented ? CGAffineTransformIdentity : CGAffineTransformMakeScale(0.7, 0.7);
        power.transform = presented ? CGAffineTransformIdentity : CGAffineTransformMakeScale(0.7, 0.7);
    } completion:nil];

    if (!presented && self.editing) {
        [self exitEditModeAnimated:NO];
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
    // Ignore presses that begin on a module container — those are for drag/reorder.
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
        add.backgroundColor = [UIColor colorWithWhite:1 alpha:0.16];
        add.layer.cornerRadius = 18;
        if (@available(iOS 13.0, *)) add.layer.cornerCurve = kCACornerCurveContinuous;
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
        sheet.prefersGrabberVisible = YES;
        sheet.preferredCornerRadius = 28;
    } else {
        gallery.modalPresentationStyle = UIModalPresentationFormSheet;
    }
    [presenter presentViewController:gallery animated:YES completion:nil];
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

    UIButton *minus = [container viewWithTag:kCC27MinusTag];
    if (!minus) {
        minus = [UIButton buttonWithType:UIButtonTypeSystem];
        minus.tag = kCC27MinusTag;
        minus.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.92];
        minus.tintColor = UIColor.whiteColor;
        minus.layer.cornerRadius = 11;
        minus.clipsToBounds = YES;
        if (@available(iOS 13.0, *)) {
            UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:11 weight:UIImageSymbolWeightBold];
            [minus setImage:[[UIImage systemImageNamed:@"minus"] imageByApplyingSymbolConfiguration:config] forState:UIControlStateNormal];
        }
        [minus addTarget:self action:@selector(_minusTapped:) forControlEvents:UIControlEventTouchUpInside];
        [container addSubview:minus];
    }
    minus.frame = CGRectMake(-4, -4, 22, 22);
    [container bringSubviewToFront:minus];

    if (CC27Prefs.shared.allowResize) {
        UIButton *resize = [container viewWithTag:kCC27ResizeTag];
        if (!resize) {
            resize = [UIButton buttonWithType:UIButtonTypeSystem];
            resize.tag = kCC27ResizeTag;
            resize.tintColor = [UIColor colorWithWhite:1 alpha:0.9];
            if (@available(iOS 13.0, *)) {
                UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightBold];
                [resize setImage:[[UIImage systemImageNamed:@"arrow.up.left.and.arrow.down.right"] imageByApplyingSymbolConfiguration:config] forState:UIControlStateNormal];
            }
            [resize addTarget:self action:@selector(_resizeTapped:) forControlEvents:UIControlEventTouchUpInside];
            [container addSubview:resize];
        }
        resize.frame = CGRectMake(container.bounds.size.width - 22, container.bounds.size.height - 22, 24, 24);
        [container bringSubviewToFront:resize];
    }

    // Jiggle
    if (![container.layer animationForKey:@"cc27.jiggle"]) {
        CAKeyframeAnimation *anim = [CAKeyframeAnimation animationWithKeyPath:@"transform.rotation.z"];
        anim.values = @[ @(-0.02), @(0.02), @(-0.02) ];
        anim.duration = 0.22;
        anim.repeatCount = HUGE_VALF;
        anim.removedOnCompletion = NO;
        // Slight per-view phase so they don't sync perfectly.
        anim.beginTime = CACurrentMediaTime() + ((uintptr_t)container % 7) * 0.02;
        [container.layer addAnimation:anim forKey:@"cc27.jiggle"];
    }

    // Drag to reorder
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

- (void)_resizeTapped:(UIButton *)sender {
    UIView *container = sender.superview;
    NSString *identifier = objc_getAssociatedObject(container, &kCC27IdKey) ?: [self _identifierForContainer:container];
    if (!identifier) return;
    CCUILayoutSize current = {1, 1};
    CGSize px = container.bounds.size;
    // Heuristic from pixel size → grid size before cycling.
    if (px.width > 200 && px.height > 100) { current.width = 2; current.height = 2; }
    else if (px.width > 200) { current.width = 2; current.height = 1; }
    else if (px.height > 160) { current.width = 1; current.height = 2; }
    current = [CC27LayoutStore.shared sizeForModule:identifier fallback:current];
    [self _haptic:UIImpactFeedbackStyleLight];
    [CC27LayoutStore.shared cycleSizeForModule:identifier current:current];
    [self performSelector:@selector(_decorateVisibleModules) withObject:nil afterDelay:0.4];
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
            [self _haptic:UIImpactFeedbackStyleMedium];
            [UIView animateWithDuration:0.15 animations:^{
                container.alpha = 0.85;
                container.transform = CGAffineTransformMakeScale(1.06, 1.06);
                container.layer.zPosition = 1000;
            }];
            break;
        }
        case UIGestureRecognizerStateChanged: {
            CGPoint p = [gr locationInView:host];
            container.center = p;
            break;
        }
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled: {
            // Drop onto nearest sibling module → swap / move before that index.
            NSMutableArray *containers = [NSMutableArray array];
            [self _collectContainers:host into:containers];
            UIView *nearest = nil;
            CGFloat best = CGFLOAT_MAX;
            CGPoint p = [gr locationInView:host];
            for (UIView *other in containers) {
                if (other == container) continue;
                CGFloat d = hypot(other.center.x - p.x, other.center.y - p.y);
                if (d < best) { best = d; nearest = other; }
            }
            if (nearest && best < 120) {
                NSString *targetId = objc_getAssociatedObject(nearest, &kCC27IdKey) ?: [self _identifierForContainer:nearest];
                NSArray *ordered = CC27LayoutStore.shared.enabledIdentifiers;
                NSUInteger to = [ordered indexOfObject:targetId];
                if (to != NSNotFound) {
                    [CC27LayoutStore.shared moveModule:identifier toIndex:to];
                }
            }
            self.draggingIdentifier = nil;
            self.draggingView = nil;
            container.layer.zPosition = 0;
            container.transform = CGAffineTransformIdentity;
            container.alpha = 1;
            [self performSelector:@selector(_decorateVisibleModules) withObject:nil afterDelay:0.35];
            break;
        }
        default:
            break;
    }
}

@end
