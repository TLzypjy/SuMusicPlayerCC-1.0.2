//
//  SuMusicMaterialLibraryViewController.m
//  SuMusicPlayerCC
//
//  素材库页面（严格按指令 3.1 / 3.2 / 3.4）：
//  - 顶部自绘导航条 56pt（安全区下方）：关闭 / 素材库 (N) / 导入，下方 8pt 处
//    0.5pt 分隔线（#E5E5EA）
//  - 三列网格：左右 16pt、列间距 12pt，列宽 = (屏宽-16*2-12*2)/3 ≈ 124.7pt
//    （430pt 基准，按屏宽比例动态计算）；缩略图正方形 = 列宽；
//    单元格高度 = 列宽 + 8 + 20 + 8 + 8；行间距 18pt，sectionInset top 10 / bottom 24
//  - 数据源：Video + Image 目录，顺序沿用 loadMediaFromDirectory（目录枚举原始顺序）
//  - 空目录时标题「素材库 (0)」+ 居中提示「暂无素材，点右上角导入」
//  - 选中：点击卡片写回原插件 selectedMediaItem / selectedMediaType 并走原刷新链路，
//    不关闭页面；进入页面按当前选中回显蓝点
//

#import "SuMusicMaterialLibraryViewController.h"
#import "SuMusicMaterial.h"
#import "SuMusicMaterialCell.h"
#import "SuMusicThumbnailLoader.h"
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

// 布局常量（iPhone 14 Pro Max 430pt 基准，全部按屏宽比例动态计算，不写死坐标）
static CGFloat const SuMusicGridSideMargin = 16;    // 左右边距
static CGFloat const SuMusicGridColumnGap = 12;     // 列间距
static CGFloat const SuMusicGridLineGap = 18;       // 行间距
static CGFloat const SuMusicGridTopInset = 10;      // 顶部 inset
static CGFloat const SuMusicGridBottomInset = 24;   // 底部 inset
static NSUInteger const SuMusicGridColumns = 3;     // 三列

static CGFloat const SuMusicHeaderHeight = 56;      // 导航条高度
static CGFloat const SuMusicHeaderSeperatorGap = 8; // 分隔线与导航条的间距
static CGFloat const SuMusicHeaderSeperatorHeight = 0.5;
static CGFloat const SuMusicSideButtonWidth = 90;   // 左右按钮宽度（含 16pt 内边距）

static NSString * const SuMusicCellReuseIdentifier = @"SuMusicMaterialCell";

// 颜色辅助
static UIColor *SuMusicTintColor(void) {
    return [UIColor colorWithRed:0.0 green:0.478 blue:1.0 alpha:1.0]; // #007AFF
}
static UIColor *SuMusicSeparatorColor(void) {
    return [UIColor colorWithRed:0.898 green:0.898 blue:0.918 alpha:1.0]; // #E5E5EA
}
static UIColor *SuMusicPlaceholderTextColor(void) {
    return [UIColor colorWithRed:0.557 green:0.557 blue:0.576 alpha:1.0]; // #8E8E93
}

// 视频扩展名（导入路由与指令 3.4 一致）
static NSArray<NSString *> *SuMusicImportVideoExtensions(void) {
    return @[@"mp4", @"mov", @"m4v"];
}

@interface SuMusicMaterialLibraryViewController () <UICollectionViewDataSource,
                                                    UICollectionViewDelegate,
                                                    UIDocumentPickerDelegate>

// 头文件中 selectedMaterial 对外为 readonly，内部需要直接赋值，
// 这里在实现文件内重新声明为 readwrite（对外接口仍保持 readonly）。
@property (nonatomic, strong, readwrite) SuMusicMaterial *selectedMaterial;

@property (nonatomic, strong) UIView *headerView;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIButton *importButton;
@property (nonatomic, strong) UIView *separatorView;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) UICollectionViewFlowLayout *flowLayout;
@property (nonatomic, strong) NSArray<SuMusicMaterial *> *materials;
@property (nonatomic, assign) CGFloat itemWidth; // 当前列宽（pt）

@end

@implementation SuMusicMaterialLibraryViewController

#pragma mark - 生命周期

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    [self buildHeader];
    [self buildCollectionView];
    [self buildEmptyLabel];

    // 载入素材（顺序沿用原插件 loadMediaFromDirectory，不排序）
    self.materials = [SuMusicMaterial allMaterials];
    [self.collectionView reloadData];
    [self updateTitleCount];

    // 预取缩略图：先首屏（前 9 个），0.6s 后再排队其余，全部走加载器的
    // 专用串行队列，不在 viewDidLoad 同步遍历抽帧
    [self prefetchThumbnailsForFirstScreenThenRest];
}

#pragma mark - 头部（关闭 / 素材库 (N) / 导入）

- (void)buildHeader {
    UIView *header = [[UIView alloc] init];
    header.backgroundColor = [UIColor systemBackgroundColor];

    // 左：关闭（#007AFF，17pt regular，左边距 16pt）
    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *closeConfig = [UIButtonConfiguration plainButtonConfiguration];
    closeConfig.contentInsets = NSDirectionalEdgeInsetsMake(0, 16, 0, 0);
    closeConfig.title = @"关闭";
    closeConfig.baseForegroundColor = SuMusicTintColor();
    closeConfig.titleFont = [UIFont systemFontOfSize:17];
    close.configuration = closeConfig;
    [close addTarget:self action:@selector(handleClose:) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:close];

    // 中：素材库 (N)（labelColor，17pt semibold，绝对居中）
    UILabel *title = [[UILabel alloc] init];
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    title.textColor = [UIColor labelColor];
    [header addSubview:title];

    // 右：导入（#007AFF，17pt regular，右边距 16pt）
    UIButton *import = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *importConfig = [UIButtonConfiguration plainButtonConfiguration];
    importConfig.contentInsets = NSDirectionalEdgeInsetsMake(0, 0, 0, 16);
    importConfig.title = @"导入";
    importConfig.baseForegroundColor = SuMusicTintColor();
    importConfig.titleFont = [UIFont systemFontOfSize:17];
    import.configuration = importConfig;
    [import addTarget:self action:@selector(handleImport:) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:import];

    self.headerView = header;
    self.closeButton = close;
    self.titleLabel = title;
    self.importButton = import;
    [self.view addSubview:header];

    // 分隔线：导航条下方 8pt，0.5pt，#E5E5EA
    UIView *separator = [[UIView alloc] init];
    separator.backgroundColor = SuMusicSeparatorColor();
    self.separatorView = separator;
    [self.view addSubview:separator];
}

- (void)updateTitleCount {
    self.titleLabel.text = [NSString stringWithFormat:@"素材库 (%lu)", (unsigned long)self.materials.count];
    self.emptyLabel.hidden = (self.materials.count > 0);
}

- (void)buildEmptyLabel {
    UILabel *label = [[UILabel alloc] init];
    label.text = @"暂无素材，点右上角导入";
    label.textColor = SuMusicPlaceholderTextColor();
    label.font = [UIFont systemFontOfSize:15];
    label.textAlignment = NSTextAlignmentCenter;
    label.hidden = YES;
    self.emptyLabel = label;
    [self.view addSubview:label];
}

#pragma mark - 布局（按屏宽比例动态计算）

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGFloat width = self.view.bounds.size.width;
    CGFloat safeTop = self.view.safeAreaInsets.top;

    // 导航条：安全区下方，高 56pt
    self.headerView.frame = CGRectMake(0, safeTop, width, SuMusicHeaderHeight);
    self.closeButton.frame = CGRectMake(0, 0, SuMusicSideButtonWidth, SuMusicHeaderHeight);
    self.titleLabel.frame = CGRectMake(width / 2 - 80, 0, 160, SuMusicHeaderHeight);
    self.importButton.frame = CGRectMake(width - SuMusicSideButtonWidth, 0, SuMusicSideButtonWidth, SuMusicHeaderHeight);

    // 分隔线：导航条下方 8pt，0.5pt
    CGFloat separatorY = safeTop + SuMusicHeaderHeight + SuMusicHeaderSeperatorGap;
    self.separatorView.frame = CGRectMake(0, separatorY, width, SuMusicHeaderSeperatorHeight);

    // 集合视图：分隔线之下
    CGFloat contentTop = separatorY + SuMusicHeaderSeperatorHeight;
    self.collectionView.frame = CGRectMake(0, contentTop, width, self.view.bounds.size.height - contentTop);

    // 三列网格：列宽 = (屏宽 - 16*2 - 12*2) / 3
    CGFloat sideMargin = SuMusicGridSideMargin;
    CGFloat colGap = SuMusicGridColumnGap;
    CGFloat itemWidth = (width - sideMargin * 2 - colGap * (SuMusicGridColumns - 1)) / SuMusicGridColumns;
    self.itemWidth = itemWidth;

    // 单元格高度 = 列宽 + 8（缩略图与胶囊） + 20（胶囊） + 8（胶囊与圆点） + 8（圆点）
    self.flowLayout.itemSize = CGSizeMake(itemWidth, itemWidth + 44);
    self.flowLayout.sectionInset = UIEdgeInsetsMake(SuMusicGridTopInset, sideMargin,
                                                    SuMusicGridBottomInset, sideMargin);
    self.flowLayout.minimumInteritemSpacing = colGap;
    self.flowLayout.minimumLineSpacing = SuMusicGridLineGap;

    // 空目录提示：居中
    self.emptyLabel.frame = CGRectMake(0, contentTop, width, self.view.bounds.size.height - contentTop);
}

#pragma mark - 集合视图

- (void)buildCollectionView {
    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.scrollDirection = UICollectionViewScrollDirectionVertical;

    UICollectionView *cv = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    cv.backgroundColor = [UIColor systemBackgroundColor];
    cv.delegate = self;
    cv.dataSource = self;
    cv.alwaysBounceVertical = YES;
    cv.allowsMultipleSelection = NO;
    [cv registerClass:[SuMusicMaterialCell class] forCellWithReuseIdentifier:SuMusicCellReuseIdentifier];

    self.flowLayout = layout;
    self.collectionView = cv;
    [self.view addSubview:cv];
}

#pragma mark - DataSource

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.materials.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    SuMusicMaterialCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:SuMusicCellReuseIdentifier forIndexPath:indexPath];
    SuMusicMaterial *material = self.materials[indexPath.row];

    // 回显选中状态（进入页面按当前 selectedMediaItem 回显蓝点）
    cell.selected = [self isMaterialSelected:material];
    [cell configureWithMaterial:material thumbnailSize:self.itemWidth];
    return cell;
}

#pragma mark - Delegate

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    SuMusicMaterial *material = self.materials[indexPath.row];
    [self selectMaterial:material];
}

#pragma mark - 选择逻辑（单选，选中即时写回，不关闭页面）

- (BOOL)isMaterialSelected:(SuMusicMaterial *)material {
    return self.selectedMaterial &&
           [self.selectedMaterial.filePath isEqualToString:material.filePath];
}

/// 单选：点击其他项切换选中；已选中项保持选中（原插件始终有选中素材，
/// 不提供取消选中）。选中即时回调 selectionBlock，让控制中心立刻换素材。
- (void)selectMaterial:(SuMusicMaterial *)material {
    if ([self isMaterialSelected:material]) {
        return; // 已选中，保持不变
    }
    self.selectedMaterial = material;
    [self refreshSelectionIndicators];
    [self finishSelection];
}

/// 刷新所有可见 cell 的选中圆点（单选切换后，原选中项需恢复未选状态；
/// 只更新可见 cell，不做全量 reload）
- (void)refreshSelectionIndicators {
    for (SuMusicMaterialCell *cell in self.collectionView.visibleCells) {
        if (!cell.material) {
            continue;
        }
        cell.selected = [self isMaterialSelected:cell.material];
    }
}

/// 完成选择并回调（选中即时回调，无需等待关闭页面）
- (void)finishSelection {
    if (self.selectionBlock) {
        self.selectionBlock(self.selectedMaterial);
    }
}

#pragma mark - 导入（UIDocumentPickerViewController）

- (void)handleImport:(id)sender {
    // UIDocumentPicker 导入：复制一份进 Video / Image 目录（asCopy:YES 保持
    // 「导入即复制」的原有行为）。原插件的 documentPicker 链路用于配置导入，
    // 这里按指令 3.6 用同一委托方法名 documentPicker:didPickDocumentsAtURLs:。
    UIDocumentPickerViewController *picker =
    [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[
        UTTypeImage,
        UTTypeMovie,
    ] asCopy:YES];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    [controller dismissViewControllerAnimated:YES completion:nil];

    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray<NSString *> *importedPaths = [NSMutableArray array];
    for (NSURL *url in urls) {
        // 判断类型并拷进对应素材目录（视频扩展名 mp4/mov/m4v，其余进 Image）
        NSString *ext = url.pathExtension.lowercaseString;
        NSString *destDir;
        if ([SuMusicImportVideoExtensions() containsObject:ext]) {
            destDir = @"/var/mobile/Library/SuMusicCC/Video";
        } else {
            destDir = @"/var/mobile/Library/SuMusicCC/Image";
        }

        NSString *filename = [self uniqueFilenameInDirectory:destDir forSourceURL:url];
        NSString *destPath = [destDir stringByAppendingPathComponent:filename];
        NSError *error = nil;
        BOOL ok = [fm copyItemAtPath:url.path toPath:destPath error:&error];
        if (!ok) {
            // 复制失败时尝试移动
            [fm moveItemAtPath:url.path toPath:destPath error:&error];
        }
        if ([fm fileExistsAtPath:destPath]) {
            [importedPaths addObject:destPath];
        }
    }

    // 刷新数据源：N 加一；新条目排在最前并立即生成缩略图
    [self reloadMaterialsWithImportedFirst:importedPaths];
    [self.collectionView reloadData];
    [self updateTitleCount];
    [self prefetchThumbnailsForFirstScreenThenRest];
}

/// 重建素材数组，导入的新条目排在最前，其余保持原有顺序
- (void)reloadMaterialsWithImportedFirst:(NSArray<NSString *> *)importedPaths {
    NSArray<SuMusicMaterial *> *all = [SuMusicMaterial allMaterials];
    if (importedPaths.count == 0) {
        self.materials = all;
        return;
    }
    NSMutableArray<SuMusicMaterial *> *imported = [NSMutableArray array];
    NSMutableArray<SuMusicMaterial *> *rest = [NSMutableArray array];
    for (SuMusicMaterial *material in all) {
        if ([importedPaths containsObject:material.filePath]) {
            [imported addObject:material];
        } else {
            [rest addObject:material];
        }
    }
    NSMutableArray<SuMusicMaterial *> *ordered = [NSMutableArray array];
    [ordered addObjectsFromArray:imported];
    [ordered addObjectsFromArray:rest];
    self.materials = ordered;
}

/// 在目录内生成唯一文件名，避免覆盖
- (NSString *)uniqueFilenameInDirectory:(NSString *)directory forSourceURL:(NSURL *)sourceURL {
    NSString *baseName = sourceURL.lastPathComponent ?: @"imported";
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *candidate = baseName;
    NSUInteger counter = 1;
    while ([fm fileExistsAtPath:[directory stringByAppendingPathComponent:candidate]]) {
        NSString *ext = baseName.pathExtension;
        candidate = ext.length > 0
            ? [NSString stringWithFormat:@"%@_%lu.%@", [baseName stringByDeletingPathExtension], (unsigned long)counter, ext]
            : [NSString stringWithFormat:@"%@_%lu", baseName, (unsigned long)counter];
        counter++;
    }
    return candidate;
}

#pragma mark - 缩略图预取（后台串行队列）

/// 先预取首屏（前 9 个），其余延迟排队，均走 SuMusicThumbnailLoader 的
/// 专用串行队列；不在 viewDidLoad 同步遍历抽帧。
- (void)prefetchThumbnailsForFirstScreenThenRest {
    if (self.materials.count == 0) {
        return;
    }
    CGFloat size = self.itemWidth > 0 ? self.itemWidth : 124.7;
    SuMusicThumbnailLoader *loader = SuMusicThumbnailLoader.sharedLoader;
    NSUInteger firstScreenCount = MIN((NSUInteger)9, self.materials.count);
    NSArray<SuMusicMaterial *> *firstScreen = [self.materials subarrayWithRange:NSMakeRange(0, firstScreenCount)];
    [loader prefetchMaterials:firstScreen thumbnailSize:size];

    // 首屏之后，0.6s 再排队其余缩略图
    if (self.materials.count > firstScreenCount) {
        NSArray<SuMusicMaterial *> *rest = [self.materials subarrayWithRange:NSMakeRange(firstScreenCount, self.materials.count - firstScreenCount)];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [loader prefetchMaterials:rest thumbnailSize:size];
        });
    }
}

#pragma mark - 关闭

/// 关闭仅 dismiss：选中已即时回调写回，此处无需重复回调
- (void)handleClose:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - 初始化

+ (instancetype)materialLibraryViewControllerWithSelected:(SuMusicMaterial *)selected {
    SuMusicMaterialLibraryViewController *vc = [[SuMusicMaterialLibraryViewController alloc] init];
    vc.initialSelectedMaterial = selected;
    vc.selectedMaterial = selected;
    return vc;
}

- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (void)commonInit {
    self.selectedMaterial = self.initialSelectedMaterial;
}

@end
