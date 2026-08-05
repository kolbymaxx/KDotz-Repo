#import "CC27.h"

@interface CC27GalleryListCell : UITableViewCell
- (void)configureWithInfo:(CC27ModuleInfo *)info;
@end

@implementation CC27GalleryListCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseIdentifier])) {
        self.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleDefault;
        self.textLabel.textColor = UIColor.whiteColor;
        self.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
        self.textLabel.numberOfLines = 1;
        self.textLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        self.detailTextLabel.textColor = [UIColor colorWithWhite:1 alpha:0.55];
        self.detailTextLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
        self.detailTextLabel.numberOfLines = 1;
        self.imageView.contentMode = UIViewContentModeScaleAspectFit;
        self.imageView.tintColor = UIColor.whiteColor;
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    // Keep icon in a fixed square so SF Symbols / settings icons align.
    CGFloat side = 28.0;
    CGFloat y = (self.contentView.bounds.size.height - side) / 2.0;
    self.imageView.frame = CGRectMake(16, y, side, side);
    CGFloat textX = 56;
    CGFloat trailing = 88;
    CGFloat textW = self.contentView.bounds.size.width - textX - trailing;
    self.textLabel.frame = CGRectMake(textX, 10, MAX(40, textW), 22);
    self.detailTextLabel.frame = CGRectMake(textX, 32, MAX(40, textW), 16);
}

- (void)configureWithInfo:(CC27ModuleInfo *)info {
    self.textLabel.text = info.displayName ?: info.identifier;
    self.detailTextLabel.text = info.category ?: @"";
    UIImage *icon = info.icon;
    if (icon) {
        self.imageView.image = [icon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    } else if (@available(iOS 13.0, *)) {
        self.imageView.image = [UIImage systemImageNamed:@"switch.2"];
    }

    UILabel *trailing = (UILabel *)self.accessoryView;
    if (![trailing isKindOfClass:UILabel.class]) {
        trailing = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 72, 24)];
        trailing.textAlignment = NSTextAlignmentRight;
        trailing.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        self.accessoryView = trailing;
    }
    if (info.enabled) {
        trailing.text = @"Added";
        trailing.textColor = [UIColor colorWithWhite:1 alpha:0.45];
        self.alpha = 0.72;
    } else {
        trailing.text = @"Add";
        trailing.textColor = [UIColor systemBlueColor];
        self.alpha = 1.0;
    }
}

@end

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
    self.view.backgroundColor = [UIColor colorWithWhite:0.06 alpha:0.96];

    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectZero];
    self.searchBar.placeholder = @"Search Controls";
    self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    self.searchBar.delegate = self;
    self.searchBar.barStyle = UIBarStyleBlack;
    self.searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.searchBar];

    self.filterControl = [[UISegmentedControl alloc] initWithItems:@[ @"Available", @"All" ]];
    self.filterControl.selectedSegmentIndex = 0;
    self.filterControl.translatesAutoresizingMaskIntoConstraints = NO;
    [self.filterControl addTarget:self action:@selector(_filterChanged) forControlEvents:UIControlEventValueChanged];
    if (@available(iOS 13.0, *)) {
        self.filterControl.selectedSegmentTintColor = [UIColor colorWithWhite:1 alpha:0.18];
        [self.filterControl setTitleTextAttributes:@{ NSForegroundColorAttributeName: UIColor.whiteColor } forState:UIControlStateNormal];
    }
    [self.view addSubview:self.filterControl];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.backgroundColor = UIColor.clearColor;
    self.tableView.separatorColor = [UIColor colorWithWhite:1 alpha:0.12];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.rowHeight = 58;
    [self.tableView registerClass:CC27GalleryListCell.class forCellReuseIdentifier:@"row"];
    [self.view addSubview:self.tableView];

    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.searchBar.topAnchor constraintEqualToAnchor:g.topAnchor constant:8],
        [self.searchBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:4],
        [self.searchBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-4],
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
