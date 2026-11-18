//
//  SuMusicMaterialLibraryViewController.h
//  SuMusicPlayerCC
//
//  素材库页面：三列缩略图网格，顶部为「关闭 / 素材库 (N) / 导入」。
//  功能行为（选中素材、导入、刷新控制中心）沿用现有逻辑，仅替换界面。
//  所有新增类均带 SuMusic 前缀。
//

#import <UIKit/UIKit.h>

#import "SuMusicMaterial.h"

NS_ASSUME_NONNULL_BEGIN

/// 选中结果回调：用户完成选择后通知外部（设置页）刷新控制中心
typedef void(^SuMusicMaterialSelectionBlock)(NSArray<SuMusicMaterial *> *selectedMaterials);

@interface SuMusicMaterialLibraryViewController : UIViewController

/// 选中结果回调（可选）
@property (nonatomic, copy, nullable) SuMusicMaterialSelectionBlock selectionBlock;

/// 初始已选中的素材（用于回显选中圆点）
@property (nonatomic, strong) NSArray<SuMusicMaterial *> *initialSelectedMaterials;

/// 当前已选中的素材集合
@property (nonatomic, strong, readonly) NSMutableArray<SuMusicMaterial *> *selectedMaterials;

/// 创建素材库页面
+ (instancetype)materialLibraryViewControllerWithSelected:(NSArray<SuMusicMaterial *> *)selected;

@end

NS_ASSUME_NONNULL_END
