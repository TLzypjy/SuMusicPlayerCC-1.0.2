//
//  SuMusicMaterialCell.m
//  SuMusicPlayerCC
//
//  素材库网格单元（严格按目标样式 03 图）：
//  - 缩略图：正方形（列宽），圆角 12pt，aspectFill，占位 #F2F2F7
//  - 左上角类型角标：白字 10pt medium，底色 rgba(0,0,0,0.45)，高 18pt，
//    左右 padding 6pt，圆角 4pt，距卡片左上各 6pt
//  - 视频中心播放键：直径 28pt 圆，底色 rgba(0,0,0,0.40)，白色 play.fill 11pt 居中
//  - 文件名胶囊：缩略图下方 8pt，高 20pt，宽 = 列宽 - 12pt，水平居中，
//    底色 #BFBFC4，白字 12pt medium，单行 middle truncation，圆角 10pt
//  - 选中圆点：胶囊下方 8pt，直径 8pt，水平居中，未选中 #D1D1D6 / 选中 #0A84FF
//  单元格高度 = 列宽 + 8 + 20 + 8 + 8
//

#import "SuMusicMaterialCell.h"
#import "SuMusicMaterial.h"
#import "SuMusicThumbnailLoader.h"

// 颜色（与素材库目标样式一致）。UIColor 为运行时对象，无法作为编译期常量，
// 用函数惰性创建，避免 'initializer element is not a compile-time constant'。
static UIColor *SuMusicCaptionBackground(void) {
    return [UIColor colorWithRed:0.749 green:0.749 blue:0.769 alpha:1.0]; // #BFBFC4
}
static UIColor *SuMusicDotUnselected(void) {
    return [UIColor colorWithRed:0.820 green:0.820 blue:0.839 alpha:1.0]; // #D1D1D6
}
static UIColor *SuMusicDotSelected(void) {
    return [UIColor colorWithRed:0.039 green:0.518 blue:1.000 alpha:1.0]; // #0A84FF
}
static UIColor *SuMusicThumbnailPlaceholder(void) {
    return [UIColor colorWithRed:0.949 green:0.949 blue:0.969 alpha:1.0]; // #F2F2F7
}

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

#pragma mark - 构建

- (void)setupSubviews {
    self.backgroundColor = [UIColor systemBackgroundColor];
    self.contentView.backgroundColor = [UIColor systemBackgroundColor];

    // 缩略图（正方形，占满列宽）
    self.thumbnailView = [[UIImageView alloc] init];
    self.thumbnailView.contentMode = UIViewContentModeScaleAspectFill;
    self.thumbnailView.clipsToBounds = YES;
    self.thumbnailView.backgroundColor = SuMusicThumbnailPlaceholder();
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
    self.typeBadgeLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightMedium];
    self.typeBadgeLabel.textAlignment = NSTextAlignmentCenter;
    [self.typeBadge addSubview:self.typeBadgeLabel];

    // 播放键（视频中心）：28pt 圆底 + 白色 play.fill 11pt
    self.playButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.playButton.hidden = YES;
    self.playButton.userInteractionEnabled = NO; // 点击整张卡片由 collectionView 处理
    self.playButton.tintColor = [UIColor whiteColor];
    UIImage *playSymbol = [UIImage systemImageNamed:@"play.fill"];
    if (playSymbol) {
        playSymbol = [playSymbol imageWithConfiguration:
                      [UIImageSymbolConfiguration configurationWithPointSize:11]];
        [self.playButton setImage:playSymbol forState:UIControlStateNormal];
    }
    [self.playButton setBackgroundImage:[self suPlayCircleImage] forState:UIControlStateNormal];
    [self.contentView addSubview:self.playButton];

    // 文件名胶囊（缩略图下方 8pt）：高 20、圆角 10、白字 12pt medium、底色 #BFBFC4
    self.captionView = [[UIView alloc] init];
    self.captionView.backgroundColor = SuMusicCaptionBackground();
    self.captionView.layer.cornerRadius = 10;
    self.captionView.layer.masksToBounds = YES;
    [self.contentView addSubview:self.captionView];

    self.captionLabel = [[UILabel alloc] init];
    self.captionLabel.textColor = [UIColor whiteColor];
    self.captionLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    self.captionLabel.textAlignment = NSTextAlignmentCenter;
    self.captionLabel.numberOfLines = 1;
    self.captionLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [self.captionView addSubview:self.captionLabel];

    // 选中圆点（文件名胶囊下方 8pt、水平居中、直径 8pt）
    self.selectionDot = [[UIView alloc] init];
    self.selectionDot.layer.cornerRadius = 4;
    self.selectionDot.layer.masksToBounds = YES;
    self.selectionDot.backgroundColor = SuMusicDotUnselected();
    [self.contentView addSubview:self.selectionDot];
}

/// 生成播放键的圆形底图（直径 28pt，rgba(0,0,0,0.40)）
- (UIImage *)suPlayCircleImage {
    CGFloat size = 28;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0);
    UIBezierPath *path = [UIBezierPath bezierPathWithArcCenter:CGPointMake(size / 2, size / 2)
                                                        radius:size / 2
                                                    startAngle:0
                                                      endAngle:M_PI * 2
                                                     clockwise:YES];
    [[UIColor colorWithRed:0 green:0 blue:0 alpha:0.40] setFill];
    [path fill];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

#pragma mark - 布局

- (void)layoutSubviews {
    [super layoutSubviews];

    CGRect bounds = self.contentView.bounds;
    CGFloat side = CGRectGetWidth(bounds); // 缩略图边长 = 列宽
    if (side <= 0) {
        return;
    }

    // 缩略图（正方形，占满列宽，圆角 12）
    CGRect thumbRect = CGRectMake(0, 0, side, side);
    self.thumbnailView.frame = thumbRect;
    self.thumbnailView.layer.cornerRadius = 12;

    // 类型角标：距左上各 6pt，高 18pt，宽按文字 + 左右 padding 6pt
    CGSize badgeTextSize = [self.typeBadgeLabel sizeThatFits:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)];
    CGFloat badgeHeight = 18;
    CGFloat badgeWidth = MIN(ceil(badgeTextSize.width) + 12, side - 12);
    CGRect badgeRect = CGRectMake(6, 6, MAX(badgeWidth, 0), badgeHeight);
    self.typeBadge.frame = badgeRect;
    self.typeBadgeLabel.frame = CGRectMake(6, 0, badgeRect.size.width - 12, badgeHeight);

    // 播放键居中（直径 28pt）
    CGFloat playSize = 28;
    self.playButton.frame = CGRectMake(CGRectGetMidX(thumbRect) - playSize / 2,
                                       CGRectGetMidY(thumbRect) - playSize / 2,
                                       playSize, playSize);

    // 文件名胶囊：缩略图下方 8pt，高 20pt，宽 = 列宽 - 12pt，水平居中
    CGFloat captionHeight = 20;
    CGFloat captionWidth = side - 12;
    CGRect captionRect = CGRectMake((side - captionWidth) / 2,
                                    CGRectGetMaxY(thumbRect) + 8,
                                    captionWidth, captionHeight);
    self.captionView.frame = captionRect;
    self.captionLabel.frame = CGRectMake(6, 0, captionWidth - 12, captionHeight);

    // 选中圆点：文件名胶囊下方 8pt、水平居中、直径 8pt
    CGFloat dotSize = 8;
    self.selectionDot.frame = CGRectMake(CGRectGetMidX(bounds) - dotSize / 2,
                                         CGRectGetMaxY(captionRect) + 8,
                                         dotSize, dotSize);
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
    [self setNeedsLayout];

    // 缩略图异步加载（立即占位 + 回填过滤复用错图）
    [SuMusicThumbnailLoader.sharedLoader loadThumbnailIntoImageView:self.thumbnailView
                                                        forMaterial:material
                                                             size:thumbnailSize];
}

#pragma mark - 复用与选中

- (void)prepareForReuse {
    [super prepareForReuse];
    // 取消上一次未完成的生成请求并立刻置回占位图，防止错图
    [SuMusicThumbnailLoader.sharedLoader cancelLoadForImageView:self.thumbnailView];
    self.thumbnailView.image = nil;
    self.material = nil;
    self.captionLabel.text = @"";
    self.selectionDot.backgroundColor = SuMusicDotUnselected();
}

- (void)setSelected:(BOOL)selected {
    [super setSelected:selected];
    [self updateSelectionDot];
}

- (void)updateSelectionDot {
    self.selectionDot.backgroundColor = self.selected ? SuMusicDotSelected() : SuMusicDotUnselected();
}

@end
