//
//  SuMusicMaterialCell.m
//  SuMusicPlayerCC
//

#import "SuMusicMaterialCell.h"
#import "SuMusicMaterial.h"
#import "SuMusicThumbnailLoader.h"

// 颜色常量（与素材库目标样式一致）
static UIColor * const SuMusicCaptionBackground = [UIColor colorWithRed:0.749 green:0.749 blue:0.769 alpha:1.0]; // #BFBFC4
static UIColor * const SuMusicDotUnselected = [UIColor colorWithRed:0.820 green:0.820 blue:0.839 alpha:1.0]; // #D1D1D6
static UIColor * const SuMusicDotSelected = [UIColor colorWithRed:0.039 green:0.518 blue:1.000 alpha:1.0]; // #0A84FF

@interface SuMusicMaterialCell ()

@property (nonatomic, strong) UIImageView *thumbnailView;
@property (nonatomic, strong) UIView *typeBadge;
@property (nonatomic, strong) UILabel *typeBadgeLabel;
@property (nonatomic, strong) UIButton *playButton;
@property (nonatomic, strong) UIView *captionView;
@property (nonatomic, strong) UILabel *captionLabel;
@property (nonatomic, strong) UIView *selectionDot;

@end

@implementation SuMusicMaterialCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupSubviews];
    }
    return self;
}

- (void)awakeFromNib {
    [super awakeFromNib];
}

#pragma mark - 布局

- (void)setupSubviews {
    self.backgroundColor = [UIColor whiteColor];
    self.contentView.backgroundColor = [UIColor whiteColor];

    // 缩略图
    self.thumbnailView = [[UIImageView alloc] init];
    self.thumbnailView.contentMode = UIViewContentModeScaleAspectFill;
    self.thumbnailView.clipsToBounds = YES;
    self.thumbnailView.backgroundColor = [UIColor colorWithRed:0.86 green:0.86 blue:0.87 alpha:1.0];
    [self.contentView addSubview:self.thumbnailView];

    // 类型角标（左上角）
    self.typeBadge = [[UIView alloc] init];
    self.typeBadge.backgroundColor = [UIColor colorWithRed:0.0 green:0.0 blue:0.0 alpha:0.45];
    self.typeBadge.layer.cornerRadius = 4;
    self.typeBadge.layer.masksToBounds = YES;
    self.typeBadge.hidden = YES;
    [self.contentView addSubview:self.typeBadge];

    self.typeBadgeLabel = [[UILabel alloc] init];
    self.typeBadgeLabel.textColor = [UIColor whiteColor];
    self.typeBadgeLabel.font = [UIFont systemFontOfSize:9 weight:UIFontWeightMedium];
    self.typeBadgeLabel.textAlignment = NSTextAlignmentCenter;
    [self.typeBadge addSubview:self.typeBadgeLabel];

    // 播放键（视频中心）
    self.playButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.playButton.hidden = YES;
    [self.playButton setImage:[self suPlayImage] forState:UIControlStateNormal];
    [self.contentView addSubview:self.playButton];

    // 文件名胶囊（底部）
    self.captionView = [[UIView alloc] init];
    self.captionView.backgroundColor = SuMusicCaptionBackground;
    self.captionView.layer.cornerRadius = 8;
    self.captionView.layer.masksToBounds = YES;
    [self.contentView addSubview:self.captionView];

    self.captionLabel = [[UILabel alloc] init];
    self.captionLabel.textColor = [UIColor whiteColor];
    self.captionLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightRegular];
    self.captionLabel.numberOfLines = 1;
    self.captionLabel.lineBreakMode = NSLineBreakModeByTruncatingTail;
    [self.captionView addSubview:self.captionLabel];

    // 选中圆点（缩略图右下角）
    self.selectionDot = [[UIView alloc] init];
    self.selectionDot.layer.cornerRadius = 6;
    self.selectionDot.layer.masksToBounds = YES;
    self.selectionDot.backgroundColor = SuMusicDotUnselected;
    [self.contentView addSubview:self.selectionDot];
}

/// 生成播放图标（白色三角形，避免依赖图片资源）
- (UIImage *)suPlayImage {
    CGFloat size = 22;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0);
    UIBezierPath *path = [UIBezierPath bezierPath];
    [path moveToPoint:CGPointMake(size * 0.34, size * 0.22)];
    [path addLineToPoint:CGPointMake(size * 0.34, size * 0.78)];
    [path addLineToPoint:CGPointMake(size * 0.80, size * 0.50)];
    [path closePath];
    [[UIColor whiteColor] setFill];
    [path fill];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGRect bounds = self.contentView.bounds;
    CGFloat margin = 2;
    CGFloat badgeHeight = 16;
    CGFloat badgeWidth = 34;
    CGFloat captionHeight = 18;
    CGFloat dotSize = 12;
    CGFloat playSize = 30;

    // 缩略图正方形，顶部留出胶囊空间
    CGFloat side = CGRectGetWidth(bounds) - margin * 2;
    CGFloat topInset = captionHeight + 4;
    CGRect thumbRect = CGRectMake(margin, topInset, side, side);
    self.thumbnailView.frame = thumbRect;
    self.thumbnailView.layer.cornerRadius = 12;

    // 角标
    CGRect badgeRect = CGRectMake(thumbRect.origin.x + 4, thumbRect.origin.y + 4, badgeWidth, badgeHeight);
    self.typeBadge.frame = badgeRect;
    CGRect labelRect = CGRectInset(badgeRect, 3, 0);
    self.typeBadgeLabel.frame = labelRect;

    // 播放键居中
    CGRect playRect = CGRectMake(CGRectGetMidX(thumbRect) - playSize / 2,
                                 CGRectGetMidY(thumbRect) - playSize / 2,
                                 playSize, playSize);
    self.playButton.frame = playRect;

    // 文件名胶囊（底部）
    CGRect captionRect = CGRectMake(margin, 2, CGRectGetWidth(bounds) - margin * 2, captionHeight);
    self.captionView.frame = captionRect;
    CGRect capLabelRect = CGRectInset(captionRect, 6, 0);
    self.captionLabel.frame = capLabelRect;

    // 选中圆点（缩略图右下角）
    CGRect dotRect = CGRectMake(thumbRect.origin.x + thumbRect.size.width - dotSize - 4,
                                thumbRect.origin.y + thumbRect.size.height - dotSize - 4,
                                dotSize, dotSize);
    self.selectionDot.frame = dotRect;
}

#pragma mark - 配置

- (void)configureWithMaterial:(SuMusicMaterial *)material thumbnailSize:(CGFloat)thumbnailSize {
    self.material = material;

    if (!material) {
        self.captionLabel.text = @"";
        self.typeBadge.hidden = YES;
        self.playButton.hidden = YES;
        self.thumbnailView.image = nil;
        return;
    }

    // 文件名胶囊
    self.captionLabel.text = material.fileName;

    // 类型角标
    self.typeBadge.hidden = NO;
    if (material.materialType == SuMusicMaterialTypeVideo) {
        self.typeBadgeLabel.text = @"视频";
        self.playButton.hidden = NO;
    } else {
        self.typeBadgeLabel.text = @"图片";
        self.playButton.hidden = YES;
    }

    // 缩略图异步加载（带占位，保证快速出现）
    [SuMusicThumbnailLoader.sharedLoader loadThumbnailIntoImageView:self.thumbnailView
                                                        forMaterial:material
                                                             size:thumbnailSize];
}

- (void)setSelected:(BOOL)selected {
    [super setSelected:selected];
    [self updateSelectionDot];
}

- (void)updateSelectionDot {
    self.selectionDot.backgroundColor = self.selected ? SuMusicDotSelected : SuMusicDotUnselected;
}

@end
