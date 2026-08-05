#import "CC27.h"

@interface CC27GalleryCell : UICollectionViewCell
@property (nonatomic, strong) UIVisualEffectView *glass;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
- (void)configureWithInfo:(CC27ModuleInfo *)info;
@end

@implementation CC27GalleryCell

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.glass = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterialDark]];
        self.glass.frame = self.contentView.bounds;
        self.glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.glass.layer.cornerRadius = 22.0;
        if (@available(iOS 13.0, *)) self.glass.layer.cornerCurve = kCACornerCurveContinuous;
        self.glass.clipsToBounds = YES;
        self.glass.layer.borderWidth = 0.55;
        self.glass.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.22].CGColor;
        [self.contentView addSubview:self.glass];

        self.iconView = [[UIImageView alloc] initWithFrame:CGRectZero];
        self.iconView.tintColor = UIColor.whiteColor;
        self.iconView.contentMode = UIViewContentModeScaleAspectFit;
        [self.glass.contentView addSubview:self.iconView];

        self.titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        self.titleLabel.textColor = UIColor.whiteColor;
        self.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        self.titleLabel.textAlignment = NSTextAlignmentCenter;
        self.titleLabel.numberOfLines = 2;
        [self.glass.contentView addSubview:self.titleLabel];

        self.subtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        self.subtitleLabel.textColor = [UIColor colorWithWhite:1 alpha:0.55];
        self.subtitleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
        self.subtitleLabel.textAlignment = NSTextAlignmentCenter;
        [self.glass.contentView addSubview:self.subtitleLabel];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.contentView.bounds.size.width;
    CGFloat h = self.contentView.bounds.size.height;
    self.iconView.frame = CGRectMake((w - 28) / 2.0, 16, 28, 28);
    self.titleLabel.frame = CGRectMake(8, 50, w - 16, 34);
    self.subtitleLabel.frame = CGRectMake(8, h - 22, w - 16, 14);
}

- (void)configureWithInfo:(CC27ModuleInfo *)info {
    self.titleLabel.text = info.displayName;
    self.subtitleLabel.text = info.enabled ? @"Added" : info.category;
    self.iconView.image = [info.icon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] ?: info.icon;
    self.glass.alpha = info.enabled ? 0.55 : 1.0;
}

@end

@interface CC27GalleryController () <UICollectionViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UISearchBarDelegate>
@property (nonatomic, strong) CC27ModuleCatalog *catalog;
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, copy) NSArray<CC27ModuleInfo *> *items;
@property (nonatomic, copy) NSString *query;
@end

@implementation CC27GalleryController

- (instancetype)initWithCatalog:(CC27ModuleCatalog *)catalog {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _catalog = catalog;
        _query = @"";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0.05 alpha:0.92];

    UIView *grabber = [[UIView alloc] initWithFrame:CGRectMake(0, 10, 36, 5)];
    grabber.backgroundColor = [UIColor colorWithWhite:1 alpha:0.35];
    grabber.layer.cornerRadius = 2.5;
    grabber.center = CGPointMake(self.view.bounds.size.width / 2.0, 12);
    grabber.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    [self.view addSubview:grabber];

    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectZero];
    self.searchBar.placeholder = @"Search Controls";
    self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    self.searchBar.delegate = self;
    self.searchBar.barStyle = UIBarStyleBlack;
    self.searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.searchBar];

    UICollectionViewFlowLayout *layout = [UICollectionViewFlowLayout new];
    layout.minimumInteritemSpacing = 12;
    layout.minimumLineSpacing = 12;
    layout.sectionInset = UIEdgeInsetsMake(8, 16, 24, 16);

    self.collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    self.collectionView.backgroundColor = UIColor.clearColor;
    self.collectionView.delegate = self;
    self.collectionView.dataSource = self;
    self.collectionView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.collectionView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.collectionView registerClass:CC27GalleryCell.class forCellWithReuseIdentifier:@"cell"];
    [self.view addSubview:self.collectionView];

    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.searchBar.topAnchor constraintEqualToAnchor:g.topAnchor constant:18],
        [self.searchBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:8],
        [self.searchBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-8],
        [self.collectionView.topAnchor constraintEqualToAnchor:self.searchBar.bottomAnchor constant:4],
        [self.collectionView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.collectionView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.collectionView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    [self reloadItems];
}

- (void)reloadItems {
    [self.catalog reload];
    self.items = [self.catalog modulesMatchingSearch:self.query ?: @""];
    // Prefer showing modules that are not yet enabled first.
    self.items = [self.items sortedArrayUsingComparator:^NSComparisonResult(CC27ModuleInfo *a, CC27ModuleInfo *b) {
        if (a.enabled != b.enabled) return a.enabled ? NSOrderedDescending : NSOrderedAscending;
        return [a.displayName localizedStandardCompare:b.displayName];
    }];
    [self.collectionView reloadData];
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

#pragma mark - Collection

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.items.count;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    CC27GalleryCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"cell" forIndexPath:indexPath];
    [cell configureWithInfo:self.items[indexPath.item]];
    return cell;
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    CGFloat width = collectionView.bounds.size.width;
    CGFloat cell = floor((width - 16 * 2 - 12 * 3) / 4.0);
    return CGSizeMake(cell, cell + 8);
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    CC27ModuleInfo *info = self.items[indexPath.item];
    if (info.enabled) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:info.displayName
                                                                       message:@"This control is already in Control Center. Remove it?"
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

    BOOL ok = [CC27LayoutStore.shared enableModule:info.identifier];
    if (ok && CC27Prefs.shared.hapticFeedback) {
        [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
    }
    [self reloadItems];
    // Keep gallery open so users can add several controls, like iOS 26.
}

@end
