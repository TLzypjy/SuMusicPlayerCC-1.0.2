//
//  SuMusicMaterial.h
//  SuMusicPlayerCC
//
//  素材数据模型：封装一个媒体素材（视频 / 图片）的基本信息与缩略图。
//  所有新增类均带 SuMusic 前缀，遵循插件命名约定。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 素材类型
typedef NS_ENUM(NSInteger, SuMusicMaterialType) {
    SuMusicMaterialTypeImage = 0,
    SuMusicMaterialTypeVideo,
};

/// 素材数据模型
@interface SuMusicMaterial : NSObject

/// 素材文件的本地 URL（file:// URL）
@property (nonatomic, strong, readonly) NSURL *fileURL;

/// 素材文件名（含扩展名）
@property (nonatomic, strong, readonly) NSString *fileName;

/// 素材类型（视频 / 图片）
@property (nonatomic, assign) SuMusicMaterialType materialType;

/// 缩略图（由 SuMusicThumbnailLoader 填充，可能为 nil 表示尚未加载）
@property (nonatomic, strong, nullable) UIImage *thumbnail;

/// 素材绝对路径（便捷访问）
@property (nonatomic, strong, readonly) NSString *filePath;

/// 以指定类型创建一个素材对象
+ (instancetype)materialWithURL:(NSURL *)url type:(SuMusicMaterialType)type;

/// 从指定目录枚举指定类型的素材（顺序沿用原插件 loadMediaFromDirectory，
/// 即目录枚举原始顺序，不做额外排序）
+ (NSArray<SuMusicMaterial *> *)materialsInDirectory:(NSString *)directory
                                                 type:(SuMusicMaterialType)type;

/// 枚举插件全部素材（Video 目录 + Image 目录，Video 在前）
+ (NSArray<SuMusicMaterial *> *)allMaterials;

@end

NS_ASSUME_NONNULL_END
