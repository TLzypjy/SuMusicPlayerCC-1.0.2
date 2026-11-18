//
//  SuMusicThumbnailLoader.h
//  SuMusicPlayerCC
//
//  缩略图加载器：负责素材缩略图的生成与多级缓存。
//  - 内存缓存：NSCache
//  - 磁盘缓存：/var/mobile/Library/SuMusicCC/Cache/Thumb/
//  - 视频首帧：AVAssetImageGenerator 抽取
//  所有新增类均带 SuMusic 前缀。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "SuMusicMaterial.h"

NS_ASSUME_NONNULL_BEGIN

@interface SuMusicThumbnailLoader : NSObject

/// 单例
+ (instancetype)sharedLoader;

/// 磁盘缓存目录：/var/mobile/Library/SuMusicCC/Cache/Thumb/
- (NSString *)diskCacheDirectory;

/// 获取（必要时生成）缩略图，同步返回。优先命中内存缓存，其次磁盘缓存，最后现场生成并回写缓存。
/// @param material 素材对象
/// @param size 目标缩略图边长（pt，按 3x 生成像素）
- (UIImage *)thumbnailForMaterial:(SuMusicMaterial *)material size:(CGFloat)size;

/// 异步加载缩略图到指定 UIImageView，带占位图，避免界面卡顿（保证 200ms 内出现占位）。
/// 使用 weak 引用 imageView，自动处理复用与释放。
/// @param material 素材对象
/// @param imageView 目标 imageView
/// @param size 目标缩略图边长（pt）
- (void)loadThumbnailIntoImageView:(UIImageView *)imageView
                         forMaterial:(SuMusicMaterial *)material
                              size:(CGFloat)size;

/// 清空内存与磁盘缓存
- (void)clearCaches;

@end

NS_ASSUME_NONNULL_END
