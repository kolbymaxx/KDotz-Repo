#import "Music27.h"

static NSString *const kM27PinCellIdentifier = @"M27PinCell";

@interface M27PinnedCell : UICollectionViewCell
@property (nonatomic, strong) UIImageView *artworkView;
@property (nonatomic, strong) UILabel *titleLabel;
@end

@implementation M27PinnedCell

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _artworkView = [UIImageView new];
        _artworkView.contentMode = UIViewContentModeScaleAspectFill;
        _artworkView.clipsToBounds = YES;
        _artworkView.layer.cornerRadius = 14;
        _artworkView.layer.cornerCurve = kCACornerCurveContinuous;
        _artworkView.backgroundColor = UIColor.tertiarySystemFillColor;
        [self.contentView addSubview:_artworkView];

        _titleLabel = [UILabel new];
        _titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
        _titleLabel.textColor = UIColor.labelColor;
        _titleLabel.textAlignment = NSTextAlignmentCenter;
        _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self.contentView addSubview:_titleLabel];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat side = self.contentView.bounds.size.width;
    self.artworkView.frame = CGRectMake(0, 0, side, side);
    self.titleLabel.frame = CGRectMake(0, side + 2, side, 14);
}

@end

@interface M27PinnedHeaderView () <UICollectionViewDataSource, UICollectionViewDelegate>
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UICollectionView *collectionView;
@end

@implementation M27PinnedHeaderView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;

        _titleLabel = [UILabel new];
        _titleLabel.text = @"Pinned";
        _titleLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
        _titleLabel.textColor = UIColor.labelColor;
        [self addSubview:_titleLabel];

        UICollectionViewFlowLayout *layout = [UICollectionViewFlowLayout new];
        layout.scrollDirection = UICollectionViewScrollDirectionHorizontal;
        layout.itemSize = CGSizeMake(72, 92);
        layout.minimumLineSpacing = 12;
        layout.sectionInset = UIEdgeInsetsMake(0, 20, 0, 20);

        _collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
        _collectionView.backgroundColor = UIColor.clearColor;
        _collectionView.showsHorizontalScrollIndicator = NO;
        _collectionView.dataSource = self;
        _collectionView.delegate = self;
        [_collectionView registerClass:M27PinnedCell.class forCellWithReuseIdentifier:kM27PinCellIdentifier];
        [self addSubview:_collectionView];

        [NSNotificationCenter.defaultCenter addObserver:self
                                               selector:@selector(reload)
                                                   name:M27PinsDidChangeNotification
                                                 object:nil];
    }
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.titleLabel.frame = CGRectMake(20, 0, self.bounds.size.width - 40, 24);
    self.collectionView.frame = CGRectMake(0, 28, self.bounds.size.width, self.bounds.size.height - 28);
}

- (void)reload {
    BOOL empty = M27PinStore.shared.pins.count == 0;
    self.hidden = empty;
    [self.collectionView reloadData];
}

#pragma mark UICollectionViewDataSource

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return (NSInteger)M27PinStore.shared.pins.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView
                  cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    M27PinnedCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:kM27PinCellIdentifier
                                                                    forIndexPath:indexPath];
    NSArray<M27PinnedItem *> *pins = M27PinStore.shared.pins;
    if (indexPath.item < (NSInteger)pins.count) {
        M27PinnedItem *item = pins[indexPath.item];
        cell.titleLabel.text = item.title ?: @"";
        cell.artworkView.image = item.artworkJPEG ? [UIImage imageWithData:item.artworkJPEG] : nil;
    }
    return cell;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    NSArray<M27PinnedItem *> *pins = M27PinStore.shared.pins;
    if (indexPath.item < (NSInteger)pins.count && self.onSelect) {
        self.onSelect(pins[indexPath.item]);
    }
}

@end
