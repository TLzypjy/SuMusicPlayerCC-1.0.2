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

/// 选中结果回调：用户选中素材后通知外部（设置页）写回并刷新控制中心。
/// 取消选中（再次点击已选中项）时回调 nil。
typedef void(^SuMusicMaterialSelectionBlock)(SuMusicMaterial *selectedMaterial);

@interface SuMusicMaterialLibraryViewController : UIViewController

/// 选中结果回调（可选）。选中即时回调，无需等待关闭页面。
@property (nonatomic, copy, nullable) SuMusicMaterialSelectionBlock selectionBlock;

/// 初始已选中的素材（用于回显选中圆点，从原插件读取）
@property (nonatomic, strong, nullable) SuMusicMaterial *initialSelectedMaterial;

/// 当前已选中的素材（nil 表示未选中）
@property (nonatomic, strong, readonly) SuMusicMaterial *selectedMaterial;

/// 创建素材库页面
+ (instancetype)materialLibraryViewControllerWithSelected:(nullable SuMusicMaterial *)selected;

@end

NS_ASSUME_NONNULL_END
