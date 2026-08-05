#import "CC27.h"

#pragma mark - Glass card cell

@interface CC27GalleryListCell : UITableViewCell
- (void)configureWithInfo:(CC27ModuleInfo *)info;
@end

@implementation CC27GalleryListCell {
    UIView *_card;
    UIView *_cardSheen;         // top gradient highlight
    CAGradientLayer *_sheenLayer;
    UIView *_iconTile;
    CAGradientLayer *_iconTileGradient;
    UIImageView *_iconView;
    UILabel *_titleLabel;
    UILabel *_subtitleLabel;
    UILabel *_pill;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier])) {
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        // Floating glass card
        _card = [[UIView alloc] initWithFrame:CGRectZero];
        _card.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
        _card.layer.cornerRadius = 20;
        if (@available(iOS 13.0, *)) _card.layer.cornerCurve = kCACornerCurveContinuous;
        _card.layer.borderWidth = 0.6;
        _card.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.16].CGColor;
        _card.layer.shadowColor = UIColor.blackColor.CGColor;
        _card.layer.shadowOpacity = 0.35;
        _card.layer.shadowRadius = 10;
        _card.layer.shadowOffset = CGSizeMake(0, 5);
        [self.contentView addSubview:_card];

        _cardSheen = [[UIView alloc] initWithFrame:CGRectZero];
        _cardSheen.userInteractionEnabled = NO;
        _cardSheen.layer.cornerRadius = 20;
        if (@available(iOS 13.0, *)) _cardSheen.layer.cornerCurve = kCACornerCurveContinuous;
        _cardSheen.clipsToBounds = YES;
        _sheenLayer = [CAGradientLayer layer];
        _sheenLayer.colors = @[
            (id)[UIColor colorWithWhite:1.0 alpha:0.14].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.02].CGColor,
            (id)UIColor.clearColor.CGColor
        ];
        _sheenLayer.locations = @[ @0.0, @0.45, @1.0 ];
        [_cardSheen.layer addSublayer:_sheenLayer];
        [_card addSubview:_cardSheen];

        // Icon inside a 3-D glass tile
        _iconTile = [[UIView alloc] initWithFrame:CGRectZero];
        _iconTile.layer.cornerRadius = 13;
        if (@available(iOS 13.0, *)) _iconTile.layer.cornerCurve = kCACornerCurveContinuous;
        _iconTile.layer.borderWidth = 0.6;
        _iconTile.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.22].CGColor;
        _iconTile.clipsToBounds = YES;
        _iconTileGradient = [CAGradientLayer layer];
        _iconTileGradient.colors = @[
            (id)[UIColor colorWithWhite:1.0 alpha:0.28].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.08].CGColor
        ];
        [_iconTile.layer addSublayer:_iconTileGradient];
        [_card addSubview:_iconTile];

        _iconView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        _iconView.tintColor = UIColor.whiteColor;
        [_iconTile addSubview:_iconView];

        _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _titleLabel.textColor = UIColor.whiteColor;
        _titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
        _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [_card addSubview:_titleLabel];

        _subtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _subtitleLabel.textColor = [UIColor colorWithWhite:1 alpha:0.55];
        _subtitleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
        [_card addSubview:_subtitleLabel];

        _pill = [[UILabel alloc] initWithFrame:CGRectZero];
        _pill.textAlignment = NSTextAlignmentCenter;
        _pill.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        _pill.layer.cornerRadius = 14;
        _pill.clipsToBounds = YES;
        _pill.layer.borderWidth = 0.6;
        [_card addSubview:_pill];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect b = self.contentView.bounds;
    _card.frame = CGRectMake(16, 5, b.size.width - 32, b.size.height - 10);
    _card.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:_card.bounds cornerRadius:20].CGPath;
    _cardSheen.frame = _card.bounds;
    _sheenLayer.frame = _cardSheen.bounds;

    CGFloat side = 42;
    _iconTile.frame = CGRectMake(14, (_card.bounds.size.height - side) / 2.0, side, side);
    _iconTileGradient.frame = _iconTile.bounds;
    _iconView.frame = CGRectInset(_iconTile.bounds, 9, 9);

    CGFloat pillW = 76;
    _pill.frame = CGRectMake(_card.bounds.size.width - pillW - 14,
                             (_card.bounds.size.height - 28) / 2.0, pillW, 28);

    CGFloat textX = CGRectGetMaxX(_iconTile.frame) + 12;
    CGFloat textW = CGRectGetMinX(_pill.frame) - textX - 10;
    _titleLabel.frame = CGRectMake(textX, _card.bounds.size.height / 2.0 - 19, MAX(40, textW), 21);
    _subtitleLabel.frame = CGRectMake(textX, _card.bounds.size.height / 2.0 + 2, MAX(40, textW), 15);
}

- (void)configureWithInfo:(CC27ModuleInfo *)info {
<<<<<<< HEAD
    _titleLabel.text = info.displayName ?: info.identifier;
    _subtitleLabel.text = info.category ?: @"";
=======
    self.textLabel.text = info.displayName ?: info.identifier;
    self.detailTextLabel.text = info.category ?: @"";
    UIImage *icon = info.icon;
    if (icon) {
        // SF Symbols and most CC glyphs look correct as templates.
        self.imageView.image = [icon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        self.imageView.tintColor = UIColor.whiteColor;
    } else if (@available(iOS 13.0, *)) {
        self.imageView.image = [[UIImage systemImageNamed:@"square.grid.2x2.fill"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        self.imageView.tintColor = UIColor.whiteColor;
    }
>>>>>>> origin/main

    UIImage *icon = info.icon;
    if (!icon) {
        if (@available(iOS 13.0, *)) icon = [UIImage systemImageNamed:@"square.grid.2x2.fill"];
    }
    _iconView.image = [icon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];

    if (info.fixed) {
        _pill.text = @"Built-in";
        _pill.textColor = [UIColor colorWithWhite:1 alpha:0.55];
        _pill.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
        _pill.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.14].CGColor;
        self.alpha = 0.8;
    } else if (info.enabled) {
        _pill.text = @"Remove";
        _pill.textColor = [UIColor systemRedColor];
        _pill.backgroundColor = [[UIColor systemRedColor] colorWithAlphaComponent:0.16];
        _pill.layer.borderColor = [[UIColor systemRedColor] colorWithAlphaComponent:0.35].CGColor;
        self.alpha = 1.0;
    } else {
        _pill.text = @"Add";
        _pill.textColor = UIColor.whiteColor;
        _pill.backgroundColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.55];
        _pill.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.30].CGColor;
        self.alpha = 1.0;
    }
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];
    void (^work)(void) = ^{
        self->_card.transform = highlighted ? CGAffineTransformMakeScale(0.97, 0.97) : CGAffineTransformIdentity;
        self->_card.backgroundColor = [UIColor colorWithWhite:1.0 alpha:highlighted ? 0.14 : 0.08];
    };
    if (animated) [UIView animateWithDuration:0.15 animations:work]; else work();
}

@end

#pragma mark - Gallery

@interface CC27GalleryController () <UITableViewDelegate, UITableViewDataSource, UISearchBarDelegate>
@property (nonatomic, strong) CC27ModuleCatalog *catalog;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UISegmentedControl *filterControl;
@property (nonatomic, copy) NSArray<CC27ModuleInfo *> *items;
@property (nonatomic, copy) NSString *query;
@property (nonatomic, assign) NSInteger filterIndex; // 0 available, 1 all
@end

@implementation CC27GalleryController

- (instancetype)initWithCatalog:(CC27ModuleCatalog *)catalog {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _catalog = catalog;
        _query = @"";
        _filterIndex = 0;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;

    // Liquid glass backdrop: blur + subtle dark wash.
    UIBlurEffect *blur;
    if (@available(iOS 13.0, *)) {
        blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
    } else {
        blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    }
    UIVisualEffectView *backdrop = [[UIVisualEffectView alloc] initWithEffect:blur];
    backdrop.frame = self.view.bounds;
    backdrop.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:backdrop];

    UIView *wash = [[UIView alloc] initWithFrame:self.view.bounds];
    wash.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    wash.backgroundColor = [UIColor colorWithWhite:0.02 alpha:0.45];
    [self.view addSubview:wash];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectZero];
    title.text = @"Add a Control";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont systemFontOfSize:24 weight:UIFontWeightBold];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:title];

    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectZero];
    self.searchBar.placeholder = @"Search Controls";
    self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    self.searchBar.delegate = self;
    self.searchBar.barStyle = UIBarStyleBlack;
    self.searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    if (@available(iOS 13.0, *)) {
        UITextField *field = self.searchBar.searchTextField;
        field.backgroundColor = [UIColor colorWithWhite:1 alpha:0.10];
        field.textColor = UIColor.whiteColor;
        field.layer.cornerRadius = 16;
        field.layer.cornerCurve = kCACornerCurveContinuous;
        field.layer.borderWidth = 0.6;
        field.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.16].CGColor;
        field.clipsToBounds = YES;
    }
    [self.view addSubview:self.searchBar];

    self.filterControl = [[UISegmentedControl alloc] initWithItems:@[ @"Available", @"All" ]];
    self.filterControl.selectedSegmentIndex = 0;
    self.filterControl.translatesAutoresizingMaskIntoConstraints = NO;
    [self.filterControl addTarget:self action:@selector(_filterChanged) forControlEvents:UIControlEventValueChanged];
    if (@available(iOS 13.0, *)) {
        self.filterControl.selectedSegmentTintColor = [UIColor colorWithWhite:1 alpha:0.22];
        self.filterControl.backgroundColor = [UIColor colorWithWhite:1 alpha:0.06];
        [self.filterControl setTitleTextAttributes:@{ NSForegroundColorAttributeName: UIColor.whiteColor } forState:UIControlStateNormal];
        [self.filterControl setTitleTextAttributes:@{ NSForegroundColorAttributeName: UIColor.whiteColor } forState:UIControlStateSelected];
    }
    [self.view addSubview:self.filterControl];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.backgroundColor = UIColor.clearColor;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.rowHeight = 72;
    self.tableView.contentInset = UIEdgeInsetsMake(4, 0, 24, 0);
    [self.tableView registerClass:CC27GalleryListCell.class forCellReuseIdentifier:@"row"];
    [self.view addSubview:self.tableView];

    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:g.topAnchor constant:18],
        [title.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.searchBar.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:4],
        [self.searchBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:8],
        [self.searchBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-8],
        [self.filterControl.topAnchor constraintEqualToAnchor:self.searchBar.bottomAnchor constant:4],
        [self.filterControl.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.filterControl.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.filterControl.heightAnchor constraintEqualToConstant:32],
        [self.tableView.topAnchor constraintEqualToAnchor:self.filterControl.bottomAnchor constant:8],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    [self reloadItems];
}

- (void)_filterChanged {
    self.filterIndex = self.filterControl.selectedSegmentIndex;
    [self reloadItems];
}

- (void)reloadItems {
    [self.catalog reload];
    NSArray<CC27ModuleInfo *> *base = [self.catalog modulesMatchingSearch:self.query ?: @""];
    if (self.filterIndex == 0) {
        NSMutableArray *available = [NSMutableArray array];
        for (CC27ModuleInfo *info in base) {
            if (!info.enabled) [available addObject:info];
        }
        self.items = available;
    } else {
        self.items = [base sortedArrayUsingComparator:^NSComparisonResult(CC27ModuleInfo *a, CC27ModuleInfo *b) {
            if (a.enabled != b.enabled) return a.enabled ? NSOrderedDescending : NSOrderedAscending;
            return [a.displayName localizedStandardCompare:b.displayName];
        }];
    }
    [self.tableView reloadData];
}

- (BOOL)_canShowWhileLocked { return YES; }

#pragma mark - Search

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    self.query = searchText ?: @"";
    [self reloadItems];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    CC27GalleryListCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row" forIndexPath:indexPath];
    [cell configureWithInfo:self.items[indexPath.row]];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    CC27ModuleInfo *info = self.items[indexPath.row];

    if (info.fixed) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:info.displayName
                                                                       message:@"This system control is always part of Control Center and can't be added again or removed."
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    if (info.enabled) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:info.displayName
                                                                       message:@"Remove this control from Control Center?"
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Remove" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *a) {
            [CC27LayoutStore.shared disableModule:info.identifier];
            if (CC27Prefs.shared.hapticFeedback) {
                [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
            }
            [self reloadItems];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    CC27LayoutApplyResult result = [CC27LayoutStore.shared enableModuleWithResult:info.identifier];
    if (CC27Prefs.shared.hapticFeedback && result != CC27LayoutApplyFailed) {
        [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
    }

    if (result == CC27LayoutApplyAlreadyPresent) {
        [CC27EditSession.shared showToast:[NSString stringWithFormat:@"%@ is already in Control Center", info.displayName]];
        [self reloadItems];
        return;
    }

    __weak typeof(self) weakSelf = self;
    void (^finish)(void) = ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        if (result == CC27LayoutApplyVisible) {
            [CC27EditSession.shared showToast:[NSString stringWithFormat:@"Added %@", info.displayName]];
            [self reloadItems];
        } else if (result == CC27LayoutApplyNeedsReopen) {
            [self dismissViewControllerAnimated:YES completion:^{
                [CC27EditSession.shared showToast:@"Control saved — open Control Center again"];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [CC27EditSession.shared dismissControlCenter];
                });
            }];
        } else {
            UIAlertController *fail = [UIAlertController alertControllerWithTitle:@"Couldn't add control"
                                                                          message:@"Make sure CCSupport is installed, then respring and try again."
                                                                   preferredStyle:UIAlertControllerStyleAlert];
            [fail addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:fail animated:YES completion:nil];
        }
    };

    // Small delay so instance rebuild can settle before we check visibility.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), finish);
}

@end
