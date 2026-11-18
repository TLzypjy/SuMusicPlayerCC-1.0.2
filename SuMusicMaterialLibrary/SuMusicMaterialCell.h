//
//  SuMusicMaterialCell.h
//  SuMusicPlayerCC
//
//  素材库网格单元：三列缩略图网格中的单个 Cell。
//  包含缩略图、类型角标、播放键、文件名胶囊、选中圆点。
//  所有新增类均带 SuMusic 前缀。
//

#import <UIKit/UIKit.h>

#import "SuMusicMaterial.h"

NS_ASSUME_NONNULL_BEGIN

@interface SuMusicMaterialCell : UICollectionViewCell

/// 素材对象（由数据源绑定）
@property (nonatomic, strong) SuMusicMaterial *material;

// 说明：selected 由 UICollectionViewCell 继承提供，子类不再重复声明，
// 避免与父类属性声明冲突（-Wproperty-attribute-mismatch / -Wobjc-property-synthesis）。

/// 用素材配置 Cell：加载缩略图、设置文件名、类型角标、播放键
/// @param material 素材对象
/// @param thumbnailSize 缩略图边长（pt）
- (void)configureWithMaterial:(SuMusicMaterial *)material thumbnailSize:(CGFloat)thumbnailSize;

/// 更新选中圆点显示
- (void)updateSelectionDot;

@end

NS_ASSUME_NONNULL_END
