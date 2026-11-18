//
//  SuMusicThumbnailLoader.h
//  SuMusicPlayerCC
//
//  缩略图加载器：负责素材缩略图的生成与多级缓存。
//  - 内存缓存：NSCache（countLimit 200 / totalCostLimit 60MB，key = 文件路径 + 修改时间）
//  - 磁盘缓存：/var/mobile/Library/SuMusicCC/Cache/Thumb/<文件名>_<修改时间戳>.jpg
//  - 视频首帧：AVAssetImageGenerator（appliesPreferredTrackTransform、0.1s 容差、取 0.1s）
//  - 生成在专用串行后台队列进行（并发 ≤ 2），主线程只负责赋值
//  所有新增类均带 SuMusic 前缀。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "SuMusicMaterial.h"

NS_ASSUME_NONNULL_BEGIN

@interface SuMusicThumbnailLoader : NSObject

/// 单例
+ (instancetype)sharedLoader;

/// 缩略图生成的固定像素边长（3x 下的 124pt 列宽）
+ (CGFloat)thumbnailPixelSize;

/// 磁盘缓存目录：/var/mobile/Library/SuMusicCC/Cache/Thumb/
- (NSString *)diskCacheDirectory;

/// 获取（必要时生成）缩略图，同步返回。优先命中内存缓存，其次磁盘缓存，
/// 最后现场生成并回写缓存；磁盘缓存读取失败时自动降级重抽一次。
/// 必须在后台队列调用（内部不做线程切换）。
/// @param material 素材对象
/// @param size 目标缩略图边长（pt，按 3x 生成像素）
- (nullable UIImage *)thumbnailForMaterial:(SuMusicMaterial *)material size:(CGFloat)size;

/// 异步加载缩略图到指定 UIImageView：立即置占位图，生成完成后仅当该 imageView
/// 的请求令牌未失效时回填，防止 Cell 复用错图。
/// @param material 素材对象
/// @param imageView 目标 imageView
/// @param size 目标缩略图边长（pt）
- (void)loadThumbnailIntoImageView:(UIImageView *)imageView
                        forMaterial:(SuMusicMaterial *)material
                             size:(CGFloat)size;

/// 取消指定 imageView 的未完成加载请求（Cell 复用时调用，配合置回占位图）
- (void)cancelLoadForImageView:(UIImageView *)imageView;

/// 预取一批素材缩略图（在内部专用串行后台队列生成并写入缓存，主线程只发起）
/// @param materials 素材列表
/// @param size 目标缩略图边长（pt，按 3x 生成像素）
- (void)prefetchMaterials:(NSArray<SuMusicMaterial *> *)materials thumbnailSize:(CGFloat)size;

/// 清空内存与磁盘缓存
- (void)clearCaches;

@end

NS_ASSUME_NONNULL_END
