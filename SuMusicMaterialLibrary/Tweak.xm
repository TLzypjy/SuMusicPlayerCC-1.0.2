//
//  Tweak.xm
//  SuMusicPlayerCC
//
//  设置页改造（PSListController 结构，原类 SuMusicPlayerCCSettingsListController）：
//  - 保留「媒体文件选择」入口行，去掉其可展开分组的子行（展开永不成立）
//  - 点击入口行 present 素材库页面（全屏 modal），取代原有展开列表
//  - 选中素材后写回原插件的选中状态并触发其刷新链路，功能行为沿用现有逻辑
//
//  与原插件的对接（均从原 1.0.1 二进制核实）：
//  - NSUserDefaults 域：initWithSuiteName:@"com.susu.sumusicplayercc"（原插件跨进程
//    共享配置一律走该 suite，不能写 standardUserDefaults，否则控制中心读不到）
//  - 键：selectedMediaItem（文件名）/ selectedMediaType（"video" / "image"）
//  - 刷新：原插件以 Darwin 通知 com.susu.sumusicplayercc/SettingsChanged 触发
//    模块重载（CFNotificationCenter + DarwinNotifyCenter），NSCenter 同步补发一份
//    以覆盖同进程观察者。不新增键、不新增通知名。
//

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>

#import "SuMusicMaterial.h"
#import "SuMusicMaterialLibraryViewController.h"

/// 需要改造的设置行标题（原插件「媒体文件选择」分组头）
static NSString * const SuMusicMediaRowTitle = @"媒体文件选择";

/// 原插件 NSUserDefaults suite 与键（沿用原键，不新增）
static NSString * const SuMusicDefaultsSuite = @"com.susu.sumusicplayercc";
static NSString * const SuMusicSelectedMediaItemKey = @"selectedMediaItem";
static NSString * const SuMusicSelectedMediaTypeKey = @"selectedMediaType";

/// 原插件已有通知名（沿用原通知，不新增），用于触发控制中心刷新
static NSString * const SuMusicSettingsChangedNotification = @"com.susu.sumusicplayercc/SettingsChanged";

#pragma mark - 原插件读写（suite 域）

/// 原插件的 NSUserDefaults 实例：与原插件一致的 suite 域
static NSUserDefaults *SuMusicPluginDefaults(void) {
    static NSUserDefaults *defaults;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        defaults = [[NSUserDefaults alloc] initWithSuiteName:SuMusicDefaultsSuite];
    });
    return defaults;
}

/// 从原插件读取当前选中：selectedMediaItem（文件名）与 selectedMediaType（video/image），
/// 映射为素材对象做初始蓝点。沿用原键，不新增 NSUserDefaults 键。
static SuMusicMaterial *SuMusicCurrentSelectedMaterial(void) {
    NSUserDefaults *defaults = SuMusicPluginDefaults();
    NSString *selectedItem = [defaults stringForKey:SuMusicSelectedMediaItemKey];
    if (selectedItem.length == 0) {
        return nil;
    }
    NSString *selectedType = [defaults stringForKey:SuMusicSelectedMediaTypeKey];
    SuMusicMaterialType type = SuMusicMaterialTypeImage;
    if ([selectedType isEqualToString:@"video"]) {
        type = SuMusicMaterialTypeVideo;
    }

    // 在素材库中按文件名 + 类型匹配当前选中
    NSArray<SuMusicMaterial *> *materials = [SuMusicMaterial allMaterials];
    for (SuMusicMaterial *material in materials) {
        if ([material.fileName isEqualToString:selectedItem] && material.materialType == type) {
            return material;
        }
    }
    // 类型不匹配时按文件名兜底
    for (SuMusicMaterial *material in materials) {
        if ([material.fileName isEqualToString:selectedItem]) {
            return material;
        }
    }
    return nil;
}

/// 写回原插件选中状态并触发刷新：
/// 写 selectedMediaItem / selectedMediaType（suite 域），再发送原插件已有的
/// com.susu.sumusicplayercc/SettingsChanged —— 原插件经 CFNotificationCenter
/// （DarwinNotifyCenter）跨进程观察该通知触发 loadSelectedImage / refreshMediaList /
/// updateMediaDisplay 刷新链路；NSNotificationCenter 同步补发覆盖同进程观察者。
/// 不新增 NSUserDefaults 键，不新增跨进程通知名。
static void SuMusicWriteBackSelection(SuMusicMaterial *material) {
    NSUserDefaults *defaults = SuMusicPluginDefaults();
    if (material) {
        [defaults setObject:material.fileName forKey:SuMusicSelectedMediaItemKey];
        [defaults setObject:(material.materialType == SuMusicMaterialTypeVideo ? @"video" : @"image")
                     forKey:SuMusicSelectedMediaTypeKey];
    } else {
        [defaults removeObjectForKey:SuMusicSelectedMediaItemKey];
        [defaults removeObjectForKey:SuMusicSelectedMediaTypeKey];
    }
    [defaults synchronize];

    // Darwin 跨进程通知（原插件观察方式）
    CFNotificationCenterRef darwinCenter = CFNotificationCenterGetDarwinNotifyCenter();
    if (darwinCenter) {
        CFNotificationCenterPostNotification(darwinCenter,
                                             (__bridge CFStringRef)SuMusicSettingsChangedNotification,
                                             NULL, NULL, YES);
    }
    // 同进程观察者（Settings.app / ControlCenter 内）兜底
    [[NSNotificationCenter defaultCenter] postNotificationName:SuMusicSettingsChangedNotification
                                                        object:nil];
}

#pragma mark - specifier / cell 识别

/// specifier 需要读取的属性签名（PSSpecifier 及原插件自定义分组头属性）。
/// 通过协议固定返回类型，避免 id 接收者按错误签名解读（BOOL 返回值被当作指针），
/// 同时消除「no known instance method for selector」编译警告。
@protocol SuMusicSpecifierInfo <NSObject>
- (NSString *)name;
- (NSString *)identifier;
- (SEL)buttonAction;
- (void)setButtonAction:(SEL)action;
- (NSString *)cell;
- (BOOL)isGroupHeader;
@end

/// 判断一个 specifier 是否对应「媒体文件选择」入口。
/// 优先按动作匹配：该分组头的目标动作是原插件的 toggleMediaGroup（唯一、稳定，
/// 不受文案混淆影响）；再退回 name / identifier 文本匹配。
static BOOL SuMusicIsMediaSpecifier(id specifier) {
    if (!specifier) {
        return NO;
    }
    id<SuMusicSpecifierInfo> info = specifier;
    // 1) 动作匹配：分组头的 buttonAction == toggleMediaGroup
    if ([info respondsToSelector:@selector(buttonAction)]) {
        SEL action = [info buttonAction];
        if (action && action == @selector(toggleMediaGroup)) {
            return YES;
        }
    }
    // 2) 文本匹配（name / identifier）
    if ([info respondsToSelector:@selector(name)] &&
        [[info name] isEqualToString:SuMusicMediaRowTitle]) {
        return YES;
    }
    if ([info respondsToSelector:@selector(identifier)] &&
        [[info identifier] isEqualToString:SuMusicMediaRowTitle]) {
        return YES;
    }
    return NO;
}

/// 判断一个 specifier 是否为分组头（用于圈定「媒体文件选择」分组的子行范围）
static BOOL SuMusicIsGroupSpecifier(id specifier) {
    if (!specifier) {
        return NO;
    }
    id<SuMusicSpecifierInfo> info = specifier;
    if ([info respondsToSelector:@selector(isGroupHeader)] &&
        [info isGroupHeader]) {
        return YES;
    }
    if ([info respondsToSelector:@selector(cell)] &&
        [[info cell] hasPrefix:@"PSGroup"]) {
        return YES;
    }
    return NO;
}

/// 判断一个 cell 是否对应「媒体文件选择」行（specifier 匹配失败时的兜底）
static BOOL SuMusicIsMediaRow(UITableViewCell *cell) {
    if (!cell) {
        return NO;
    }
    if (cell.textLabel && [cell.textLabel.text isEqualToString:SuMusicMediaRowTitle]) {
        return YES;
    }
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

#pragma mark - 素材库呈现

/// 从设置页 present 素材库（didSelect 拦截与 buttonAction 替换共用）
static void SuMusicPresentMaterialLibraryFromController(id controller) {
    if (!controller || ![controller respondsToSelector:@selector(presentViewController:animated:completion:)]) {
        return;
    }
    // 从原插件读取当前选中，做初始蓝点
    SuMusicMaterial *currentSelected = SuMusicCurrentSelectedMaterial();

    SuMusicMaterialLibraryViewController *library =
    [SuMusicMaterialLibraryViewController materialLibraryViewControllerWithSelected:currentSelected];

    // 选中结果回写：写回原插件选中状态并触发刷新（选中即时回调，无需等待关闭）
    library.selectionBlock = ^(SuMusicMaterial *selected) {
        dispatch_async(dispatch_get_main_queue(), ^{
            SuMusicWriteBackSelection(selected);
        });
    };

    library.modalPresentationStyle = UIModalPresentationFullScreen;
    [controller presentViewController:library animated:YES completion:nil];
}

#pragma mark - 设置页 hook

/// 前向声明被 hook 的插件内类。
/// 实际类 SuMusicPlayerCCSettingsListController 是 PSListController 子类
/// （iOS 私有类，不在 SDK 内），编译期需要类型声明，运行期由 Logos 定位真实类。
@interface PSListController : UITableViewController
@end

@interface SuMusicPlayerCCSettingsListController : PSListController
@end

%hook SuMusicPlayerCCSettingsListController

/// 构建 specifiers 时：把「媒体文件选择」分组的子行去掉，只留入口行。
/// 原插件的展开分组：入口行（分组头）之后、下一个分组头之前的都是子行。
/// 配合下方 toggleMediaGroup 展开永不成立，双保险保证子行永不出现。
- (NSArray *)specifiers {
    NSArray *original = %orig();
    if (!original || original.count == 0) {
        return original;
    }

    // 找到「媒体文件选择」入口在数组中的位置
    NSUInteger mediaIndex = NSNotFound;
    for (NSUInteger i = 0; i < original.count; i++) {
        if (SuMusicIsMediaSpecifier(original[i])) {
            mediaIndex = i;
            break;
        }
    }
    if (mediaIndex == NSNotFound) {
        return original;
    }

    // 找到入口行之后的下一个分组头，两者之间的非分组行都是该分组子行
    NSMutableArray *filtered = [original mutableCopy];
    NSUInteger nextGroupIndex = NSNotFound;
    for (NSUInteger i = mediaIndex + 1; i < filtered.count; i++) {
        if (SuMusicIsGroupSpecifier(filtered[i])) {
            nextGroupIndex = i;
            break;
        }
    }

    // 入口行动作替换：把原插件 toggleMediaGroup 换成素材库呈现。
    // 原插件分组头动作无参调用（v16@0:8），%new 方法 suMusicPresentMediaLibrary 签名一致；
    // 这样即使点击链路不走 tableView:didSelectRowAtIndexPath:，点击也直接进素材库。
    {
        id<SuMusicSpecifierInfo> mediaSpecifier = filtered[mediaIndex];
        if ([mediaSpecifier respondsToSelector:@selector(setButtonAction:)]) {
            [mediaSpecifier setButtonAction:@selector(suMusicPresentMediaLibrary)];
        }
    }

    NSRange removalRange;
    if (nextGroupIndex != NSNotFound) {
        removalRange = NSMakeRange(mediaIndex + 1, nextGroupIndex - mediaIndex - 1);
    } else {
        removalRange = NSMakeRange(mediaIndex + 1, filtered.count - mediaIndex - 1);
    }
    if (removalRange.length > 0) {
        [filtered removeObjectsInRange:removalRange];
    }
    return filtered;
}

/// 让「媒体文件选择」分组的展开状态永远不成立：
/// 无论外部如何调用，展开标志始终为 NO，子行永不显示。
- (BOOL)mediaGroupExpanded {
    return NO;
}

- (void)setMediaGroupExpanded:(BOOL)expanded {
    // 忽略外部设置，保持展开永不成立
}

- (void)toggleMediaGroup {
    // 原「展开子行」动作被整体替换为素材库呈现：无论点击链路走
    // didSelect 拦截、buttonAction 替换还是原动作本身，都收敛到素材库；
    // 展开永不发生（配合 mediaGroupExpanded 恒 NO 与 specifiers 过滤）。
    SuMusicPresentMaterialLibraryFromController(self);
}

/// 构建 cell 时：对「媒体文件选择」入口行，把下拉箭头换成右箭头。
/// 说明：PSListController 基类必然实现 cellForRowAtIndexPath；若原类未覆写，
/// hook 会落在基类实现上，非匹配行原样返回，功能无副作用。
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = %orig();
    if (SuMusicIsMediaRow(cell)) {
        // 右箭头（等效原插件 chevronRightImage 的系统样式）
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        // 若原实现用自定义 accessoryView 展示下拉箭头，移除后交由系统绘制右箭头
        cell.accessoryView = nil;
    }
    return cell;
}

/// 点击行：拦截「媒体文件选择」，改为 present 素材库页面。
/// 优先按 indexPath 取 specifier 匹配（PSListController 的 specifierAtIndexPath:），
/// 兜底按 cell 文本匹配。PSListController 使用经典
/// tableView:didSelectRowAtIndexPath:（不写 didSelectRowAt:，PSListController 无此实现）。
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    id specifier = nil;
    if ([self respondsToSelector:@selector(specifierAtIndexPath:)]) {
        specifier = [self performSelector:@selector(specifierAtIndexPath:) withObject:indexPath];
    }
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];

    if (SuMusicIsMediaSpecifier(specifier) || SuMusicIsMediaRow(cell)) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        SuMusicPresentMaterialLibraryFromController(self);
        return;
    }
    %orig();
}

/// 素材库呈现（经 specifier 的 buttonAction 调用，无参签名与原 toggleMediaGroup 一致）
%new - (void)suMusicPresentMediaLibrary {
    SuMusicPresentMaterialLibraryFromController(self);
}

%end

#pragma mark - hook 初始化

/// hook 是否已初始化（防重复 %init）
static BOOL SuMusicHooksInitialized = NO;
/// 轮询定时器（类注册后挂起置空）
static dispatch_source_t SuMusicHookInitTimer;

%ctor {
    // CC 模块 bundle 由 CCSupport 按需加载：在设置里点开模块页时才把
    // SuMusicPlayerCC.bundle 载入宿主进程（Settings.app）。dylib 构造阶段该类
    // 尚未注册，直接 %init 会落空；轮询等待类出现后立即初始化。
    // 放全局队列而非主队列：建页期间主线程繁忙会把主队列任务挤后，导致
    // 首次进页面时 hook 仍未生效；MSHook/ObjC 运行时调用线程安全。
    // 类已存在的进程（如 ControlCenter）首轮即初始化。
    SuMusicHookInitTimer = dispatch_source_create(
        DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0));
    dispatch_source_set_timer(SuMusicHookInitTimer, DISPATCH_TIME_NOW, 0.05 * NSEC_PER_SEC, 0.01 * NSEC_PER_SEC);
    dispatch_source_set_event_handler(SuMusicHookInitTimer, ^{
        if (SuMusicHooksInitialized) {
            return; // 已初始化，等挂起生效
        }
        if (objc_getClass("SuMusicPlayerCCSettingsListController") != nil) {
            %init();
            SuMusicHooksInitialized = YES;
            dispatch_suspend(SuMusicHookInitTimer);
            SuMusicHookInitTimer = nil;
        }
    });
    dispatch_resume(SuMusicHookInitTimer);
}
