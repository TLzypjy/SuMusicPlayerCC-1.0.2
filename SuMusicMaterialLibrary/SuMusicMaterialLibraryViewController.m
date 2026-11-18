//
//  SuMusicMaterialLibraryViewController.m
//  SuMusicPlayerCC
//

#import "SuMusicMaterialLibraryViewController.h"
#import "SuMusicMaterial.h"
#import "SuMusicMaterialCell.h"
#import "SuMusicThumbnailLoader.h"
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

// 布局常量（iPhone 14 Pro Max 430pt 基准）
static CGFloat const SuMusicGridSideMargin = 16;    // 左右边距
static CGFloat const SuMusicGridColumnGap = 12;     // 列间距
static CGFloat const SuMusicGridLineGap = 12;       // 行间距
static NSUInteger const SuMusicGridColumns = 3;      // 三列
static CGFloat const SuMusicThumbnailSize = 104;    // 缩略图边长（pt）

static NSString * const SuMusicCellReuseIdentifier = @"SuMusicMaterialCell";

@interface SuMusicMaterialLibraryViewController () <UICollectionViewDataSource,
                                                    UICollectionViewDelegate,
                                                    UIDocumentPickerDelegate>

// 头文件中 selectedMaterials 对外为 readonly，内部需要直接赋值，
// 这里在实现文件内重新声明为 readwrite（对外接口仍保持 readonly）。
@property (nonatomic, strong, readwrite) NSMutableArray<SuMusicMaterial *> *selectedMaterials;

@property (nonatomic, strong) UIView *headerView;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIButton *importButton;
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) UICollectionViewFlowLayout *flowLayout;
@property (nonatomic, strong) NSArray<SuMusicMaterial *> *materials;

// 内部辅助方法（在实现文件内使用，显式声明以确保选择器可见性）
- (void)buildHeader;
- (void)buildCollectionView;
- (void)updateTitleCount;
- (BOOL)isMaterialSelected:(SuMusicMaterial *)material;
- (void)toggleSelection:(SuMusicMaterial *)material;
- (void)finishSelection;
- (NSString *)uniqueFilenameInDirectory:(NSString *)directory forSourceURL:(NSURL *)sourceURL;
- (void)handleClose:(id)sender;
- (void)handleImport:(id)sender;

@end

@implementation SuMusicMaterialLibraryViewController

#pragma mark - 生命周期

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    [self buildHeader];
    [self buildCollectionView];

    // 载入素材
    self.materials = [SuMusicMaterial allMaterials];
    [self.collectionView reloadData];
    [self updateTitleCount];

    // 预取缩略图（在后台生成并写入缓存，加速首屏）
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        for (SuMusicMaterial *m in self.materials) {
            [SuMusicThumbnailLoader.sharedLoader thumbnailForMaterial:m size:SuMusicThumbnailSize];
        }
    });
}

#pragma mark - 头部

- (void)buildHeader {
    UIView *header = [[UIView alloc] init];
    header.backgroundColor = [UIColor systemBackgroundColor];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    [close setTitle:@"关闭" forState:UIControlStateNormal];
    [close addTarget:self action:@selector(handleClose:) forControlEvents:UIControlEventTouchUpInside];

    UILabel *title = [[UILabel alloc] init];
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];

    UIButton *import = [UIButton buttonWithType:UIButtonTypeSystem];
    [import setTitle:@"导入" forState:UIControlStateNormal];
    [import addTarget:self action:@selector(handleImport:) forControlEvents:UIControlEventTouchUpInside];

    [header addSubview:close];
    [header addSubview:title];
    [header addSubview:import];

    self.headerView = header;
    self.closeButton = close;
    self.titleLabel = title;
    self.importButton = import;

    [self.view addSubview:header];
}

- (void)updateTitleCount {
    self.titleLabel.text = [NSString stringWithFormat:@"素材库 (%lu)", (unsigned long)self.materials.count];
}

#pragma mark - 布局

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGFloat width = self.view.bounds.size.width;

    // 头部
    CGFloat headerHeight = 44;
    self.headerView.frame = CGRectMake(0, 0, width, headerHeight);
    self.closeButton.frame = CGRectMake(0, 0, 70, headerHeight);
    self.titleLabel.frame = CGRectMake(width / 2 - 80, 0, 160, headerHeight);
    self.importButton.frame = CGRectMake(width - 70, 0, 70, headerHeight);

    // 集合视图
    self.collectionView.frame = CGRectMake(0, headerHeight, width, self.view.bounds.size.height - headerHeight);

    // 三列网格布局
    CGFloat sideMargin = SuMusicGridSideMargin;
    CGFloat colGap = SuMusicGridColumnGap;
    CGFloat available = width - sideMargin * 2 - colGap * (SuMusicGridColumns - 1);
    CGFloat itemWidth = available / SuMusicGridColumns;

    self.flowLayout.itemSize = CGSizeMake(itemWidth, itemWidth + 24); // 缩略图 + 文件名胶囊高度
    self.flowLayout.sectionInset = UIEdgeInsetsMake(12, sideMargin, 12, sideMargin);
    self.flowLayout.minimumInteritemSpacing = colGap;
    self.flowLayout.minimumLineSpacing = SuMusicGridLineGap;
}

#pragma mark - 集合视图

- (void)buildCollectionView {
    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.scrollDirection = UICollectionViewScrollDirectionVertical;

    UICollectionView *cv = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    cv.backgroundColor = [UIColor systemBackgroundColor];
    cv.delegate = self;
    cv.dataSource = self;
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

    // 回显选中状态
    cell.selected = [self.isMaterialSelected:material];
    [cell configureWithMaterial:material thumbnailSize:SuMusicThumbnailSize];
    return cell;
}

#pragma mark - Delegate

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    SuMusicMaterial *material = self.materials[indexPath.row];
    [self toggleSelection:material];

    SuMusicMaterialCell *cell = [collectionView cellForItemAtIndexPath:indexPath];
    if (cell) {
        cell.selected = [self isMaterialSelected:material];
    }
}

#pragma mark - 选择逻辑

- (BOOL)isMaterialSelected:(SuMusicMaterial *)material {
    for (SuMusicMaterial *m in self.selectedMaterials) {
        if ([m.filePath isEqualToString:material.filePath]) {
            return YES;
        }
    }
    return NO;
}

- (void)toggleSelection:(SuMusicMaterial *)material {
    NSMutableArray<SuMusicMaterial *> *selected = self.selectedMaterials;
    NSUInteger index = NSNotFound;
    for (NSUInteger i = 0; i < selected.count; i++) {
        if ([[selected[i] filePath] isEqualToString:material.filePath]) {
            index = i;
            break;
        }
    }
    if (index != NSNotFound) {
        [selected removeObjectAtIndex:index];
    } else {
        [selected addObject:material];
    }
}

/// 完成选择并回调
- (void)finishSelection {
    if (self.selectionBlock) {
        self.selectionBlock([self.selectedMaterials copy]);
    }
}

#pragma mark - 导入

- (void)handleImport:(id)sender {
    // 复用现有 UIDocumentPickerViewController 流程，允许导入图片与视频
    UIDocumentPickerViewController *picker =
    [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[
        UTTypeImage.identifier,
        UTTypeMovie.identifier,
    ] inMode:UIDocumentPickerModeImport];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    [controller dismissViewControllerAnimated:YES completion:nil];

    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSURL *url in urls) {
        // 判断类型并移动到对应素材目录
        NSString *ext = url.pathExtension.lowercaseString;
        NSString *destDir;
        if ([@[@"mp4", @"mov", @"m4v", @"mkv", @"avi", @"3gp", @"webm", @"caf"] containsObject:ext]) {
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
    }

    // 刷新素材并重载网格
    self.materials = [SuMusicMaterial allMaterials];
    [self.collectionView reloadData];
    [self updateTitleCount];
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

#pragma mark - 关闭

- (void)handleClose:(id)sender {
    [self finishSelection];
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - 初始化

+ (instancetype)materialLibraryViewControllerWithSelected:(NSArray<SuMusicMaterial *> *)selected {
    SuMusicMaterialLibraryViewController *vc = [[SuMusicMaterialLibraryViewController alloc] init];
    vc.initialSelectedMaterials = selected ?: @[];
    vc.selectedMaterials = [NSMutableArray arrayWithArray:selected ?: @[]];
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
    self.selectedMaterials = [NSMutableArray array];
    [self.selectedMaterials addObjectsFromArray:self.initialSelectedMaterials ?: @[]];
}

@end
