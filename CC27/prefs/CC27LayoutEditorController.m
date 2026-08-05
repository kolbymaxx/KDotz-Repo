// CC27 Layout Editor — a Control Center mirror inside Settings.
// Reorder modules here with drag & drop (UICollectionView interactive
// movement, so reflow is native and crash-free), then Apply & Respring
// commits the order to the real Control Center configuration.

#import <Preferences/PSViewController.h>
#import <spawn.h>
#import <dlfcn.h>

static NSString *const kCC27ModuleConfigPath = @"/var/mobile/Library/ControlCenter/ModuleConfiguration.plist";
static NSString *const kCC27ModuleOrderKey = @"module-identifiers";

static NSString *CC27FindBinary(NSString *leaf) {
    NSMutableArray<NSString *> *candidates = [NSMutableArray array];
    const char *(*jbrootFn)(const char *) = (const char *(*)(const char *))dlsym(RTLD_DEFAULT, "jbroot");
    if (jbrootFn) {
        for (NSString *prefix in @[ @"/usr/bin/", @"/bin/", @"/usr/local/bin/" ]) {
            const char *p = jbrootFn([[prefix stringByAppendingString:leaf] UTF8String]);
            if (p && p[0]) [candidates addObject:[NSString stringWithUTF8String:p]];
        }
    }
    [candidates addObject:[@"/var/jb/usr/bin/" stringByAppendingString:leaf]];
    [candidates addObject:[@"/var/jb/bin/" stringByAppendingString:leaf]];
    [candidates addObject:[@"/usr/bin/" stringByAppendingString:leaf]];
    [candidates addObject:[@"/bin/" stringByAppendingString:leaf]];
    for (NSString *c in candidates) {
        if ([[NSFileManager defaultManager] isExecutableFileAtPath:c]) return c;
    }
    return nil;
}

#pragma mark - Module metadata (names / symbols / grid sizes)

static NSDictionary<NSString *, NSString *> *CC27NameMap(void) {
    static NSDictionary *map;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        map = @{
            @"com.apple.control-center.ConnectivityModule": @"Connectivity",
            @"com.apple.control-center.DisplayModule": @"Brightness",
            @"com.apple.control-center.AudioModule": @"Volume",
            @"com.apple.mediaremote.controlcenter.audio": @"Volume",
            @"com.apple.mediaremote.controlcenter.nowplaying": @"Now Playing",
            @"com.apple.control-center.FlashlightModule": @"Flashlight",
            @"com.apple.control-center.CameraModule": @"Camera",
            @"com.apple.control-center.CalculatorModule": @"Calculator",
            @"com.apple.control-center.OrientationLockModule": @"Rotation Lock",
            @"com.apple.control-center.LowPowerModule": @"Low Power",
            @"com.apple.control-center.AppleTVRemoteModule": @"TV Remote",
            @"com.apple.control-center.CarModeModule": @"Driving",
            @"com.apple.donotdisturb.DoNotDisturbModule": @"Do Not Disturb",
            @"com.apple.FocusUIModule": @"Focus",
            @"com.apple.Home.ControlCenter": @"Home",
            @"com.apple.mobiletimer.controlcenter.timer": @"Timer",
            @"com.apple.MobileSMS.SilenceModule": @"Mute",
            @"com.apple.mediaremote.controlcenter.airplaymirroring": @"Mirroring",
            @"com.apple.replaykit.RecentsControlCenterModule": @"Record",
            @"com.apple.control-center.HearingAidsModule": @"Hearing",
            @"com.apple.control-center.QRCodeModule": @"Scan Code",
            @"com.apple.control-center.MagnifierModule": @"Magnifier",
            @"com.apple.control-center.QuickNoteModule": @"Quick Note",
            @"com.apple.control-center.DarkModeModule": @"Dark Mode",
            @"com.apple.ShazamKit.ShazamModule": @"Music Rec.",
            @"com.kolby.cc27.respring": @"Respring",
            @"com.kolby.cc27.safemode": @"Safe Mode",
            @"com.kolby.cc27.uicache": @"UICache",
            @"com.kolby.cc27.userspace": @"Userspace",
        };
    });
    return map;
}

static NSString *CC27DisplayName(NSString *identifier) {
    NSString *mapped = CC27NameMap()[identifier];
    if (mapped) return mapped;
    NSString *last = identifier.pathExtension.length ? identifier.pathExtension : identifier.lastPathComponent;
    if ([last hasSuffix:@"Module"] && last.length > 6) last = [last substringToIndex:last.length - 6];
    return last.length ? last : identifier;
}

static NSString *CC27SymbolName(NSString *identifier) {
    static NSDictionary *exact;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        exact = @{
            @"com.apple.control-center.ConnectivityModule": @"wifi",
            @"com.apple.control-center.DisplayModule": @"sun.max.fill",
            @"com.apple.control-center.AudioModule": @"speaker.wave.3.fill",
            @"com.apple.mediaremote.controlcenter.audio": @"speaker.wave.3.fill",
            @"com.apple.mediaremote.controlcenter.nowplaying": @"music.note.list",
            @"com.apple.control-center.FlashlightModule": @"flashlight.on.fill",
            @"com.apple.control-center.CameraModule": @"camera.fill",
            @"com.apple.control-center.CalculatorModule": @"plus.forwardslash.minus",
            @"com.apple.control-center.OrientationLockModule": @"lock.rotation",
            @"com.apple.control-center.LowPowerModule": @"battery.25",
            @"com.apple.control-center.DarkModeModule": @"circle.lefthalf.filled",
            @"com.apple.control-center.QRCodeModule": @"qrcode.viewfinder",
            @"com.apple.control-center.MagnifierModule": @"plus.magnifyingglass",
            @"com.apple.control-center.QuickNoteModule": @"note.text",
            @"com.apple.control-center.HearingAidsModule": @"ear",
            @"com.apple.control-center.AppleTVRemoteModule": @"appletvremote.gen4.fill",
            @"com.apple.control-center.CarModeModule": @"car.fill",
            @"com.apple.donotdisturb.DoNotDisturbModule": @"moon.fill",
            @"com.apple.FocusUIModule": @"moon.fill",
            @"com.apple.Home.ControlCenter": @"house.fill",
            @"com.apple.mobiletimer.controlcenter.timer": @"timer",
            @"com.apple.MobileSMS.SilenceModule": @"bell.slash.fill",
            @"com.apple.mediaremote.controlcenter.airplaymirroring": @"airplayvideo",
            @"com.apple.replaykit.RecentsControlCenterModule": @"record.circle",
            @"com.apple.ShazamKit.ShazamModule": @"waveform",
            @"com.kolby.cc27.respring": @"arrow.clockwise.circle.fill",
            @"com.kolby.cc27.safemode": @"exclamationmark.shield.fill",
            @"com.kolby.cc27.uicache": @"paintbrush.fill",
            @"com.kolby.cc27.userspace": @"bolt.circle.fill",
        };
    });
    NSString *hit = exact[identifier];
    if (hit) return hit;

    NSString *hay = identifier.lowercaseString;
    NSDictionary *rules = @{
        @"flashlight": @"flashlight.on.fill", @"camera": @"camera.fill",
        @"volume": @"speaker.wave.3.fill", @"audio": @"speaker.wave.3.fill",
        @"bright": @"sun.max.fill", @"display": @"sun.max.fill",
        @"timer": @"timer", @"alarm": @"alarm.fill", @"record": @"record.circle",
        @"home": @"house.fill", @"focus": @"moon.fill", @"dark": @"circle.lefthalf.filled",
        @"wallet": @"wallet.pass.fill", @"translate": @"character.bubble.fill",
        @"battery": @"battery.100", @"lowpower": @"battery.25",
        @"wifi": @"wifi", @"bluetooth": @"bolt.horizontal.fill",
        @"music": @"music.note", @"shazam": @"waveform",
    };
    for (NSString *needle in rules) {
        if ([hay containsString:needle]) return rules[needle];
    }
    NSArray *palette = @[ @"square.grid.2x2.fill", @"slider.horizontal.3", @"switch.2",
                          @"dial.max.fill", @"circle.grid.cross.fill", @"puzzlepiece.extension.fill", @"sparkles" ];
    return palette[identifier.hash % palette.count];
}

// Grid footprint (in cells) mirroring the real CC layout.
static CGSize CC27GridSize(NSString *identifier) {
    static NSDictionary *sizes;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sizes = @{
            @"com.apple.control-center.ConnectivityModule": [NSValue valueWithCGSize:CGSizeMake(2, 2)],
            @"com.apple.mediaremote.controlcenter.nowplaying": [NSValue valueWithCGSize:CGSizeMake(2, 2)],
            @"com.apple.control-center.DisplayModule": [NSValue valueWithCGSize:CGSizeMake(1, 2)],
            @"com.apple.control-center.AudioModule": [NSValue valueWithCGSize:CGSizeMake(1, 2)],
            @"com.apple.mediaremote.controlcenter.audio": [NSValue valueWithCGSize:CGSizeMake(1, 2)],
        };
    });
    NSValue *v = sizes[identifier];
    return v ? v.CGSizeValue : CGSizeMake(1, 1);
}

#pragma mark - Mosaic layout (CC-style occupancy grid)

@protocol CC27MiniGridLayoutDelegate <NSObject>
- (CGSize)gridSizeForItemAtIndexPath:(NSIndexPath *)indexPath;
@end

@interface CC27MiniGridLayout : UICollectionViewLayout
@property (nonatomic, weak) id<CC27MiniGridLayoutDelegate> gridDelegate;
@end

@implementation CC27MiniGridLayout {
    NSMutableArray<UICollectionViewLayoutAttributes *> *_attributes;
    CGSize _contentSize;
    CGFloat _unit;
}

static const NSInteger kCC27GridColumns = 4;
static const CGFloat kCC27GridSpacing = 12.0;

- (void)prepareLayout {
    [super prepareLayout];
    _attributes = [NSMutableArray array];

    UICollectionView *cv = self.collectionView;
    CGFloat width = cv.bounds.size.width - cv.contentInset.left - cv.contentInset.right - 2 * kCC27GridSpacing;
    _unit = (width - (kCC27GridColumns - 1) * kCC27GridSpacing) / kCC27GridColumns;
    if (_unit < 10) { _contentSize = CGSizeZero; return; }

    // Row-major occupancy map, grown as needed.
    NSMutableArray<NSMutableArray<NSNumber *> *> *rows = [NSMutableArray array];
    NSMutableArray<NSMutableArray<NSNumber *> *> *(^ensureRows)(NSInteger) = ^(NSInteger count) {
        while ((NSInteger)rows.count < count) {
            NSMutableArray *row = [NSMutableArray array];
            for (NSInteger c = 0; c < kCC27GridColumns; c++) [row addObject:@NO];
            [rows addObject:row];
        }
        return rows;
    };

    NSInteger maxRowUsed = 0;
    for (NSInteger section = 0; section < cv.numberOfSections; section++) {
        for (NSInteger item = 0; item < [cv numberOfItemsInSection:section]; item++) {
            NSIndexPath *ip = [NSIndexPath indexPathForItem:item inSection:section];
            CGSize grid = [self.gridDelegate gridSizeForItemAtIndexPath:ip];
            NSInteger w = MAX(1, MIN(kCC27GridColumns, (NSInteger)grid.width));
            NSInteger h = MAX(1, (NSInteger)grid.height);

            // First-fit scan.
            NSInteger placedRow = -1, placedCol = -1;
            for (NSInteger r = 0; placedRow < 0; r++) {
                ensureRows(r + h);
                for (NSInteger c = 0; c + w <= kCC27GridColumns; c++) {
                    BOOL free = YES;
                    for (NSInteger dr = 0; dr < h && free; dr++) {
                        for (NSInteger dc = 0; dc < w && free; dc++) {
                            if ([rows[r + dr][c + dc] boolValue]) free = NO;
                        }
                    }
                    if (free) { placedRow = r; placedCol = c; break; }
                }
            }
            for (NSInteger dr = 0; dr < h; dr++) {
                for (NSInteger dc = 0; dc < w; dc++) {
                    rows[placedRow + dr][placedCol + dc] = @YES;
                }
            }
            maxRowUsed = MAX(maxRowUsed, placedRow + h);

            UICollectionViewLayoutAttributes *attr = [UICollectionViewLayoutAttributes layoutAttributesForCellWithIndexPath:ip];
            CGFloat x = kCC27GridSpacing + placedCol * (_unit + kCC27GridSpacing);
            CGFloat y = kCC27GridSpacing + placedRow * (_unit + kCC27GridSpacing);
            attr.frame = CGRectMake(x, y,
                                    w * _unit + (w - 1) * kCC27GridSpacing,
                                    h * _unit + (h - 1) * kCC27GridSpacing);
            [_attributes addObject:attr];
        }
    }
    _contentSize = CGSizeMake(cv.bounds.size.width,
                              kCC27GridSpacing + maxRowUsed * (_unit + kCC27GridSpacing) + 40);
}

- (CGSize)collectionViewContentSize { return _contentSize; }

- (NSArray *)layoutAttributesForElementsInRect:(CGRect)rect {
    NSMutableArray *out = [NSMutableArray array];
    for (UICollectionViewLayoutAttributes *attr in _attributes) {
        if (CGRectIntersectsRect(attr.frame, rect)) [out addObject:attr];
    }
    return out;
}

- (UICollectionViewLayoutAttributes *)layoutAttributesForItemAtIndexPath:(NSIndexPath *)indexPath {
    for (UICollectionViewLayoutAttributes *attr in _attributes) {
        if ([attr.indexPath isEqual:indexPath]) return attr;
    }
    return nil;
}

- (BOOL)shouldInvalidateLayoutForBoundsChange:(CGRect)newBounds {
    return newBounds.size.width != self.collectionView.bounds.size.width;
}

- (UICollectionViewLayoutAttributes *)layoutAttributesForInteractivelyMovingItemAtIndexPath:(NSIndexPath *)indexPath
                                                                          withTargetPosition:(CGPoint)position {
    UICollectionViewLayoutAttributes *attr = [[super layoutAttributesForInteractivelyMovingItemAtIndexPath:indexPath
                                                                                        withTargetPosition:position] copy];
    attr.transform = CGAffineTransformMakeScale(1.08, 1.08);
    attr.alpha = 0.92;
    attr.zIndex = 1000;
    return attr;
}

@end

#pragma mark - Tile cell

@interface CC27MiniTileCell : UICollectionViewCell
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) CAGradientLayer *sheen;
- (void)configureWithIdentifier:(NSString *)identifier fixed:(BOOL)fixed;
@end

@implementation CC27MiniTileCell

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.contentView.backgroundColor = [UIColor colorWithWhite:1 alpha:0.10];
        self.contentView.layer.cornerRadius = 18;
        if (@available(iOS 13.0, *)) self.contentView.layer.cornerCurve = kCACornerCurveContinuous;
        self.contentView.layer.borderWidth = 0.6;
        self.contentView.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.18].CGColor;
        self.contentView.clipsToBounds = YES;

        _sheen = [CAGradientLayer layer];
        _sheen.colors = @[
            (id)[UIColor colorWithWhite:1.0 alpha:0.16].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.03].CGColor,
            (id)UIColor.clearColor.CGColor
        ];
        _sheen.locations = @[ @0.0, @0.5, @1.0 ];
        [self.contentView.layer addSublayer:_sheen];

        _iconView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        _iconView.tintColor = UIColor.whiteColor;
        [self.contentView addSubview:_iconView];

        _nameLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _nameLabel.textColor = [UIColor colorWithWhite:1 alpha:0.85];
        _nameLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightSemibold];
        _nameLabel.textAlignment = NSTextAlignmentCenter;
        _nameLabel.numberOfLines = 2;
        [self.contentView addSubview:_nameLabel];

        self.layer.shadowColor = UIColor.blackColor.CGColor;
        self.layer.shadowOpacity = 0.30;
        self.layer.shadowRadius = 7;
        self.layer.shadowOffset = CGSizeMake(0, 4);
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect b = self.contentView.bounds;
    _sheen.frame = b;
    CGFloat iconSide = MIN(30, b.size.height * 0.34);
    _iconView.frame = CGRectMake((b.size.width - iconSide) / 2.0,
                                 b.size.height / 2.0 - iconSide + 4,
                                 iconSide, iconSide);
    _nameLabel.frame = CGRectMake(4, CGRectGetMaxY(_iconView.frame) + 3, b.size.width - 8, 26);
    self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:18].CGPath;
}

- (void)configureWithIdentifier:(NSString *)identifier fixed:(BOOL)fixed {
    _nameLabel.text = CC27DisplayName(identifier);
    if (@available(iOS 13.0, *)) {
        _iconView.image = [[UIImage systemImageNamed:CC27SymbolName(identifier)]
                           imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    }
    self.contentView.alpha = fixed ? 0.45 : 1.0;
}

@end

#pragma mark - Editor controller

@interface CC27LayoutEditorController : PSViewController
    <UICollectionViewDataSource, UICollectionViewDelegate, CC27MiniGridLayoutDelegate>
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) NSMutableArray<NSString *> *fixedIds;
@property (nonatomic, strong) NSMutableArray<NSString *> *userIds;
@property (nonatomic, copy) NSArray<NSString *> *savedUserIds;
@end

@implementation CC27LayoutEditorController

- (NSArray<NSString *> *)_knownFixedIdentifiers {
    return @[
        @"com.apple.control-center.ConnectivityModule",
        @"com.apple.mediaremote.controlcenter.nowplaying",
        @"com.apple.control-center.OrientationLockModule",
        @"com.apple.donotdisturb.DoNotDisturbModule",
        @"com.apple.FocusUIModule",
        @"com.apple.control-center.DisplayModule",
        @"com.apple.control-center.AudioModule",
    ];
}

- (void)_loadConfiguration {
    NSDictionary *config = [NSDictionary dictionaryWithContentsOfFile:kCC27ModuleConfigPath];
    NSArray *order = config[kCC27ModuleOrderKey];
    if (![order isKindOfClass:NSArray.class] || order.count == 0) {
        order = @[
            @"com.apple.control-center.FlashlightModule",
            @"com.apple.mobiletimer.controlcenter.timer",
            @"com.apple.control-center.CalculatorModule",
            @"com.apple.control-center.CameraModule",
        ];
    }
    self.userIds = [order mutableCopy];
    self.savedUserIds = order;

    // Fixed modules mirror the untouchable CC top area. Hide any that ended
    // up in the user list (e.g. via CCSupport) to avoid duplicates.
    NSMutableArray *fixed = [[self _knownFixedIdentifiers] mutableCopy];
    [fixed removeObjectsInArray:self.userIds];
    self.fixedIds = fixed;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.title = @"Layout";
    self.view.backgroundColor = [UIColor colorWithRed:0.05 green:0.05 blue:0.09 alpha:1.0];

    [self _loadConfiguration];

    CC27MiniGridLayout *layout = [CC27MiniGridLayout new];
    layout.gridDelegate = self;

    self.collectionView = [[UICollectionView alloc] initWithFrame:self.view.bounds collectionViewLayout:layout];
    self.collectionView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.collectionView.backgroundColor = UIColor.clearColor;
    self.collectionView.dataSource = self;
    self.collectionView.delegate = self;
    self.collectionView.alwaysBounceVertical = YES;
    [self.collectionView registerClass:CC27MiniTileCell.class forCellWithReuseIdentifier:@"tile"];
    [self.view addSubview:self.collectionView];

    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(_handleDrag:)];
    lp.minimumPressDuration = 0.2;
    [self.collectionView addGestureRecognizer:lp];

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"Apply"
                                         style:UIBarButtonItemStyleDone
                                        target:self
                                        action:@selector(_applyTapped)];
    self.navigationItem.rightBarButtonItem.enabled = NO;

    UILabel *hint = [[UILabel alloc] initWithFrame:CGRectZero];
    hint.text = @"Hold & drag a tile to rearrange. Dimmed tiles are fixed by iOS. Apply resprings to commit.";
    hint.textColor = [UIColor colorWithWhite:1 alpha:0.45];
    hint.font = [UIFont systemFontOfSize:12];
    hint.numberOfLines = 0;
    hint.textAlignment = NSTextAlignmentCenter;
    hint.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:hint];
    [NSLayoutConstraint activateConstraints:@[
        [hint.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:24],
        [hint.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-24],
        [hint.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-10],
    ]];
    self.collectionView.contentInset = UIEdgeInsetsMake(0, 0, 60, 0);
}

#pragma mark Drag

- (void)_handleDrag:(UILongPressGestureRecognizer *)gr {
    CGPoint p = [gr locationInView:self.collectionView];
    switch (gr.state) {
        case UIGestureRecognizerStateBegan: {
            NSIndexPath *ip = [self.collectionView indexPathForItemAtPoint:p];
            if (!ip || ip.section != 1) return; // only user modules move
            [self.collectionView beginInteractiveMovementForItemAtIndexPath:ip];
            if (@available(iOS 13.0, *)) {
                [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
            }
            break;
        }
        case UIGestureRecognizerStateChanged:
            [self.collectionView updateInteractiveMovementTargetPosition:p];
            break;
        case UIGestureRecognizerStateEnded:
            [self.collectionView endInteractiveMovement];
            break;
        default:
            [self.collectionView cancelInteractiveMovement];
            break;
    }
}

#pragma mark Collection

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView { return 2; }

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return section == 0 ? (NSInteger)self.fixedIds.count : (NSInteger)self.userIds.count;
}

- (NSString *)_identifierAtIndexPath:(NSIndexPath *)ip {
    NSArray *list = ip.section == 0 ? self.fixedIds : self.userIds;
    return (ip.item >= 0 && ip.item < (NSInteger)list.count) ? list[ip.item] : @"";
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    CC27MiniTileCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"tile" forIndexPath:indexPath];
    [cell configureWithIdentifier:[self _identifierAtIndexPath:indexPath] fixed:indexPath.section == 0];
    return cell;
}

- (CGSize)gridSizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    return CC27GridSize([self _identifierAtIndexPath:indexPath]);
}

- (BOOL)collectionView:(UICollectionView *)collectionView canMoveItemAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == 1;
}

- (NSIndexPath *)collectionView:(UICollectionView *)collectionView
targetIndexPathForMoveFromItemAtIndexPath:(NSIndexPath *)original
                     toProposedIndexPath:(NSIndexPath *)proposed {
    if (proposed.section != 1) {
        return [NSIndexPath indexPathForItem:0 inSection:1];
    }
    return proposed;
}

- (void)collectionView:(UICollectionView *)collectionView
   moveItemAtIndexPath:(NSIndexPath *)source
           toIndexPath:(NSIndexPath *)destination {
    if (source.section != 1 || destination.section != 1) return;
    if (source.item < 0 || source.item >= (NSInteger)self.userIds.count) return;
    NSString *identifier = self.userIds[source.item];
    [self.userIds removeObjectAtIndex:source.item];
    NSInteger to = MIN(MAX(0, destination.item), (NSInteger)self.userIds.count);
    [self.userIds insertObject:identifier atIndex:to];
    self.navigationItem.rightBarButtonItem.enabled = ![self.userIds isEqualToArray:self.savedUserIds];
}

#pragma mark Apply

- (void)_applyTapped {
    NSMutableDictionary *config = [[NSDictionary dictionaryWithContentsOfFile:kCC27ModuleConfigPath] mutableCopy]
                                  ?: [NSMutableDictionary dictionary];
    config[kCC27ModuleOrderKey] = self.userIds.copy;

    NSString *dir = kCC27ModuleConfigPath.stringByDeletingLastPathComponent;
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    BOOL ok = [config writeToFile:kCC27ModuleConfigPath atomically:YES];

    if (!ok) {
        UIAlertController *fail = [UIAlertController alertControllerWithTitle:@"Couldn't Save"
                                                                      message:@"Failed writing the Control Center configuration."
                                                               preferredStyle:UIAlertControllerStyleAlert];
        [fail addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:fail animated:YES completion:nil];
        return;
    }

    self.savedUserIds = self.userIds.copy;
    self.navigationItem.rightBarButtonItem.enabled = NO;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Layout Saved"
                                                                   message:@"Respring now to apply the new Control Center order?"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Respring" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *a) {
        NSString *sbreload = CC27FindBinary(@"sbreload");
        NSString *binary = sbreload ?: CC27FindBinary(@"killall");
        if (!binary) return;
        pid_t pid = 0;
        if (sbreload) {
            const char *args[] = { binary.fileSystemRepresentation, NULL };
            posix_spawn(&pid, args[0], NULL, NULL, (char *const *)args, NULL);
        } else {
            const char *args[] = { binary.fileSystemRepresentation, "SpringBoard", NULL };
            posix_spawn(&pid, args[0], NULL, NULL, (char *const *)args, NULL);
        }
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Later" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
