//
//  Tweak.xm
//  SuMusicPlayerCC
//
//  设置页改造：
//  - 保留「媒体文件选择」行
//  - 箭头由 chevronDownImage 换成 chevronRightImage
//  - 点击该行 present 素材库页面（全屏 modal），取代原有展开列表
//  - 选中素材后回写并刷新，功能行为沿用现有逻辑
//

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

#import "SuMusicMaterial.h"
#import "SuMusicMaterialLibraryViewController.h"

/// 需要改造的设置行标题
static NSString * const SuMusicMediaRowTitle = @"媒体文件选择";

/// 判断一个 cell 是否对应「媒体文件选择」行
static BOOL SuMusicIsMediaRow(UITableViewCell *cell) {
    if (!cell) {
        return NO;
    }
    // 优先匹配主文本
    if (cell.textLabel && [cell.textLabel.text isEqualToString:SuMusicMediaRowTitle]) {
        return YES;
    }
    // 兼容自定义子视图中的标签
    for (UIView *view in cell.contentView.subviews) {
        if ([view isKindOfClass:[UILabel class]]) {
            UILabel *label = (UILabel *)view;
            if ([label.text isEqualToString:SuMusicMediaRowTitle]) {
                return YES;
            }
        }
    }
    return NO;
}

/// 前向声明被 hook 的插件内类。
/// 该类存在于插件二进制中，不在 iOS SDK 内；编译期需要类型声明，
/// 运行期由 Theos 通过 objc_getClass 定位真实类并挂载 hook。
/// 依据 hook 的 tableView 代理方法，其为 UITableViewController 子类。
@interface SuMusicPlayerCCSettingsListController : UITableViewController
@end

%hook SuMusicPlayerCCSettingsListController

/// 构建 cell 时：对「媒体文件选择」行，把下拉箭头换成右箭头
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = %orig();
    if (SuMusicIsMediaRow(cell)) {
        // 右箭头（chevronRightImage 的等效系统样式）
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        // 若原实现用自定义 accessoryView 展示下拉箭头，移除后交由系统绘制右箭头
        cell.accessoryView = nil;
    }
    return cell;
}

/// 点击行（经典 API）：拦截「媒体文件选择」，改为 present 素材库页面
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    if (SuMusicIsMediaRow(cell)) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];

        // 无已知选择状态时默认不预选
        NSArray<SuMusicMaterial *> *currentSelected = @[];

        SuMusicMaterialLibraryViewController *library =
        [SuMusicMaterialLibraryViewController materialLibraryViewControllerWithSelected:currentSelected];

        // 选中结果回写：刷新设置页（沿用现有刷新逻辑）
        library.selectionBlock = ^(NSArray<SuMusicMaterial *> *selected) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [tableView reloadData];
            });
        };

        library.modalPresentationStyle = UIModalPresentationFullScreen;
        [self presentViewController:library animated:YES completion:nil];
        return;
    }
    %orig();
}

/// 点击行（iOS 14+ API）：同样拦截，覆盖实现了新 API 的情况
- (void)tableView:(UITableView *)tableView didSelectRowAt:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    if (SuMusicIsMediaRow(cell)) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];

        NSArray<SuMusicMaterial *> *currentSelected = @[];
        SuMusicMaterialLibraryViewController *library =
        [SuMusicMaterialLibraryViewController materialLibraryViewControllerWithSelected:currentSelected];
        library.selectionBlock = ^(NSArray<SuMusicMaterial *> *selected) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [tableView reloadData];
            });
        };
        library.modalPresentationStyle = UIModalPresentationFullScreen;
        [self presentViewController:library animated:YES completion:nil];
        return;
    }
    %orig();
}

%end
