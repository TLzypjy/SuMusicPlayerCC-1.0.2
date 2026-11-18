//
//  SuMusicMaterialCell.h
//  SuMusicPlayerCC
//
//  素材库网格单元：三列缩略图网格中的单个 Cell。
//  包含缩略图、类型角标、播放键、文件名胶囊、选中圆点。
//  所有新增类均带 SuMusic 前缀。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SuMusicMaterialCell : UICollectionViewCell

/// 素材对象（由数据源绑定）
@property (nonatomic, strong) SuMusicMaterial *material;

/// 是否处于选中状态（控制底部选中圆点颜色）
@property (nonatomic, assign) BOOL selected;

/// 用素材配置 Cell：加载缩略图、设置文件名、类型角标、播放键
/// @param material 素材对象
/// @param thumbnailSize 缩略图边长（pt）
- (void)configureWithMaterial:(SuMusicMaterial *)material thumbnailSize:(CGFloat)thumbnailSize;

/// 更新选中圆点显示
- (void)updateSelectionDot;

@end

NS_ASSUME_NONNULL_END
