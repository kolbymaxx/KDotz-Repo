#import "AEGlassPanel.h"
#import "AEClipboardStore.h"
#import "AEPrefs.h"
#import "AEScreenLens.h"
#import "AESculptStore.h"

@interface AEGlassPanel () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UIVisualEffectView *blur;
@property (nonatomic, strong) UIView *chrome;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UISegmentedControl *segments;
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UITextView *lensView;
@property (nonatomic, strong) UIStackView *actionRow;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) NSArray<AEClipboardItem *> *items;
@property (nonatomic, weak) UIWindow *hostWindow;
@property (nonatomic, strong) UIButton *closeBtn;
@end

@implementation AEGlassPanel

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.28];
        self.accessibilityViewIsModal = YES;

        UITapGestureRecognizer *dimTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dimTapped:)];
        [self addGestureRecognizer:dimTap];

        _chrome = [[UIView alloc] initWithFrame:CGRectZero];
        _chrome.layer.cornerRadius = 28;
        _chrome.layer.cornerCurve = kCACornerCurveContinuous;
        _chrome.clipsToBounds = YES;
        _chrome.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
        _chrome.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.22].CGColor;
        [self addSubview:_chrome];

        UIBlurEffect *effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterialDark];
        _blur = [[UIVisualEffectView alloc] initWithEffect:effect];
        _blur.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [_chrome addSubview:_blur];

        // Soft top sheen (liquid glass hint without purple glow)
        CAGradientLayer *sheen = [CAGradientLayer layer];
        sheen.colors = @[
            (id)[UIColor colorWithWhite:1 alpha:0.18].CGColor,
            (id)[UIColor colorWithWhite:1 alpha:0.02].CGColor,
            (id)[UIColor colorWithWhite:0 alpha:0.15].CGColor
        ];
        sheen.locations = @[@0, @0.35, @1];
        sheen.name = @"aether.sheen";
        [_chrome.layer insertSublayer:sheen atIndex:0];
        self.accessibilityIdentifier = @"AetherGlassPanel";

        _titleLabel = [UILabel new];
        _titleLabel.text = @"Aether";
        _titleLabel.font = [UIFont systemFontOfSize:22 weight:UIFontWeightSemibold];
        _titleLabel.textColor = UIColor.whiteColor;
        [_chrome addSubview:_titleLabel];

        _subtitleLabel = [UILabel new];
        _subtitleLabel.text = @"Context glass";
        _subtitleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        _subtitleLabel.textColor = [UIColor colorWithWhite:1 alpha:0.55];
        [_chrome addSubview:_subtitleLabel];

        _closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        [_closeBtn setTitle:@"Done" forState:UIControlStateNormal];
        _closeBtn.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
        [_closeBtn setTitleColor:[UIColor colorWithRed:0.70 green:0.85 blue:0.95 alpha:1] forState:UIControlStateNormal];
        [_closeBtn addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
        [_chrome addSubview:_closeBtn];

        _segments = [[UISegmentedControl alloc] initWithItems:@[@"Clipboard", @"Lens", @"Sculpt"]];
        _segments.selectedSegmentIndex = 0;
        [_segments addTarget:self action:@selector(segmentChanged) forControlEvents:UIControlEventValueChanged];
        if (@available(iOS 13.0, *)) {
            _segments.selectedSegmentTintColor = [UIColor colorWithWhite:1 alpha:0.18];
        }
        [_chrome addSubview:_segments];

        _table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
        _table.dataSource = self;
        _table.delegate = self;
        _table.backgroundColor = UIColor.clearColor;
        _table.separatorColor = [UIColor colorWithWhite:1 alpha:0.12];
        [_table registerClass:[UITableViewCell class] forCellReuseIdentifier:@"clip"];
        [_chrome addSubview:_table];

        _lensView = [UITextView new];
        _lensView.editable = NO;
        _lensView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.25];
        _lensView.textColor = UIColor.whiteColor;
        _lensView.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
        _lensView.layer.cornerRadius = 14;
        _lensView.hidden = YES;
        _lensView.textContainerInset = UIEdgeInsetsMake(12, 10, 12, 10);
        [_chrome addSubview:_lensView];

        _actionRow = [[UIStackView alloc] initWithFrame:CGRectZero];
        _actionRow.axis = UILayoutConstraintAxisHorizontal;
        _actionRow.spacing = 10;
        _actionRow.distribution = UIStackViewDistributionFillEqually;
        [_chrome addSubview:_actionRow];

        _statusLabel = [UILabel new];
        _statusLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
        _statusLabel.textColor = [UIColor colorWithWhite:1 alpha:0.5];
        _statusLabel.numberOfLines = 2;
        [_chrome addSubview:_statusLabel];

        [self rebuildActions];
        [self reloadClipboard];
    }
    return self;
}

- (UIButton *)pill:(NSString *)title action:(SEL)sel {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    b.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12];
    b.layer.cornerRadius = 14;
    b.layer.cornerCurve = kCACornerCurveContinuous;
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    b.contentEdgeInsets = UIEdgeInsetsMake(10, 8, 10, 8);
    return b;
}

- (void)rebuildActions {
    for (UIView *v in self.actionRow.arrangedSubviews) {
        [self.actionRow removeArrangedSubview:v];
        [v removeFromSuperview];
    }
    NSInteger seg = self.segments.selectedSegmentIndex;
    if (seg == 0) {
        [self.actionRow addArrangedSubview:[self pill:@"Clear" action:@selector(clearClipboard)]];
        [self.actionRow addArrangedSubview:[self pill:@"Refresh" action:@selector(reloadClipboard)]];
    } else if (seg == 1) {
        [self.actionRow addArrangedSubview:[self pill:@"Scan Screen" action:@selector(runLens)]];
        [self.actionRow addArrangedSubview:[self pill:@"Copy All" action:@selector(copyLens)]];
    } else {
        [self.actionRow addArrangedSubview:[self pill:@"Enter Sculpt" action:@selector(enterSculpt)]];
        [self.actionRow addArrangedSubview:[self pill:@"Reset App" action:@selector(clearSculpt)]];
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat inset = 16;
    CGFloat maxW = MIN(self.bounds.size.width - inset * 2, 420);
    CGFloat h = MIN(self.bounds.size.height * 0.72, 560);
    CGFloat x = (self.bounds.size.width - maxW) / 2.0;
    CGFloat y = (self.bounds.size.height - h) / 2.0;
    self.chrome.frame = CGRectMake(x, y, maxW, h);
    self.blur.frame = self.chrome.bounds;

    for (CALayer *layer in self.chrome.layer.sublayers) {
        if ([layer.name isEqualToString:@"aether.sheen"]) {
            layer.frame = self.chrome.bounds;
        }
    }

    CGFloat pad = 18;
    self.titleLabel.frame = CGRectMake(pad, 16, maxW - 100, 28);
    self.subtitleLabel.frame = CGRectMake(pad, 42, maxW - 100, 18);
    self.closeBtn.frame = CGRectMake(maxW - 78, 18, 60, 32);
    self.segments.frame = CGRectMake(pad, 72, maxW - pad * 2, 32);
    self.actionRow.frame = CGRectMake(pad, 116, maxW - pad * 2, 40);
    self.statusLabel.frame = CGRectMake(pad, h - 40, maxW - pad * 2, 28);

    CGFloat bodyY = 168;
    CGFloat bodyH = h - bodyY - 48;
    self.table.frame = CGRectMake(0, bodyY, maxW, bodyH);
    self.lensView.frame = CGRectMake(pad, bodyY, maxW - pad * 2, bodyH);
}

- (void)presentInWindow:(UIWindow *)window {
    self.hostWindow = window;
    self.frame = window.bounds;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.alpha = 0;
    self.chrome.transform = CGAffineTransformMakeScale(0.92, 0.92);
    [window addSubview:self];
    [self reloadClipboard];
    NSString *bid = AECurrentBundleID();
    NSInteger sculptCount = [[AESculptStore shared] countForBundle:bid];
    self.subtitleLabel.text = [NSString stringWithFormat:@"%@ · %ld sculpted", bid, (long)sculptCount];
    [UIView animateWithDuration:0.38 delay:0 usingSpringWithDamping:0.86 initialSpringVelocity:0.4 options:0 animations:^{
        self.alpha = 1;
        self.chrome.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)dismissAnimated:(BOOL)animated {
    void (^done)(BOOL) = ^(BOOL finished) {
        (void)finished;
        [self removeFromSuperview];
        [self.delegate glassPanelDidRequestDismiss:self];
    };
    if (!animated) { done(YES); return; }
    [UIView animateWithDuration:0.22 animations:^{
        self.alpha = 0;
        self.chrome.transform = CGAffineTransformMakeScale(0.94, 0.94);
    } completion:done];
}

- (void)dimTapped:(UITapGestureRecognizer *)gr {
    CGPoint p = [gr locationInView:self];
    if (!CGRectContainsPoint(self.chrome.frame, p)) {
        [self dismissAnimated:YES];
    }
}

- (void)closeTapped { [self dismissAnimated:YES]; }

- (void)segmentChanged {
    BOOL lens = self.segments.selectedSegmentIndex == 1;
    self.table.hidden = lens;
    self.lensView.hidden = !lens;
    [self rebuildActions];
    if (!lens) [self reloadClipboard];
    if (self.segments.selectedSegmentIndex == 2) {
        self.statusLabel.text = @"Sculpt: hide any UI chrome that wastes your attention. Persists per app.";
    } else if (lens) {
        self.statusLabel.text = @"Lens reads text from the live screen via Vision OCR.";
    } else {
        self.statusLabel.text = @"Clipboard timeline follows you across apps.";
    }
}

- (void)reloadClipboard {
    self.items = [[AEClipboardStore shared] items];
    [self.table reloadData];
    self.statusLabel.text = [NSString stringWithFormat:@"%lu clips stored", (unsigned long)self.items.count];
}

- (void)clearClipboard {
    [[AEClipboardStore shared] clearUnpinned];
    [self reloadClipboard];
}

- (void)runLens {
    self.statusLabel.text = @"Scanning…";
    UIWindow *w = self.hostWindow;
    // Hide ourselves so OCR doesn't read the panel
    self.hidden = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.08 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [AEScreenLens recognizeTextInWindow:w completion:^(NSString *text, NSError *error) {
            self.hidden = NO;
            if (error || !text.length) {
                self.lensView.text = error.localizedDescription ?: @"No text found.";
                self.statusLabel.text = @"Lens found nothing readable.";
            } else {
                [self showLensResult:text];
            }
            self.segments.selectedSegmentIndex = 1;
            [self segmentChanged];
        }];
    });
}

- (void)showLensResult:(NSString *)text {
    self.lensView.text = text;
    self.statusLabel.text = [NSString stringWithFormat:@"%lu characters captured", (unsigned long)text.length];
}

- (void)copyLens {
    if (!self.lensView.text.length) return;
    [UIPasteboard generalPasteboard].string = self.lensView.text;
    self.statusLabel.text = @"Copied lens text to clipboard.";
}

- (void)enterSculpt {
    [self.delegate glassPanelDidEnterSculptMode:self];
    [self dismissAnimated:YES];
}

- (void)clearSculpt {
    [self.delegate glassPanelDidRequestClearSculpt:self];
    NSString *bid = AECurrentBundleID();
    self.subtitleLabel.text = [NSString stringWithFormat:@"%@ · 0 sculpted", bid];
    self.statusLabel.text = @"Cleared sculpt rules for this app.";
}

- (void)showStatus:(NSString *)message {
    self.statusLabel.text = message;
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return self.items.count ?: 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"clip" forIndexPath:indexPath];
    cell.backgroundColor = [UIColor colorWithWhite:1 alpha:0.06];
    cell.textLabel.textColor = UIColor.whiteColor;
    cell.textLabel.numberOfLines = 3;
    cell.textLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightRegular];
    cell.detailTextLabel.textColor = [UIColor colorWithWhite:1 alpha:0.45];
    if (self.items.count == 0) {
        cell.textLabel.text = @"Nothing copied yet — copy text anywhere and it appears here.";
        cell.accessoryType = UITableViewCellAccessoryNone;
        return cell;
    }
    AEClipboardItem *item = self.items[indexPath.row];
    cell.textLabel.text = item.text;
    cell.accessoryType = item.pinned ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.items.count == 0) return;
    AEClipboardItem *item = self.items[indexPath.row];
    [[AEClipboardStore shared] pasteItem:item];
    self.statusLabel.text = @"Ready to paste — switch fields and paste.";
    UINotificationFeedbackGenerator *gen = [UINotificationFeedbackGenerator new];
    [gen notificationOccurred:UINotificationFeedbackTypeSuccess];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    if (self.items.count == 0) return nil;
    AEClipboardItem *item = self.items[indexPath.row];
    UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"Delete" handler:^(__kindof UIContextualAction *action, __kindof UIView *sourceView, void (^completionHandler)(BOOL)) {
        (void)action; (void)sourceView;
        [[AEClipboardStore shared] deleteItem:item];
        [self reloadClipboard];
        completionHandler(YES);
    }];
    UIContextualAction *pin = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:item.pinned ? @"Unpin" : @"Pin" handler:^(__kindof UIContextualAction *action, __kindof UIView *sourceView, void (^completionHandler)(BOOL)) {
        (void)action; (void)sourceView;
        [[AEClipboardStore shared] togglePin:item];
        [self reloadClipboard];
        completionHandler(YES);
    }];
    pin.backgroundColor = [UIColor colorWithRed:0.25 green:0.45 blue:0.55 alpha:1];
    return [UISwipeActionsConfiguration configurationWithActions:@[del, pin]];
}

@end
