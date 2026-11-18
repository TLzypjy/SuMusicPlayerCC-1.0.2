//
//  SuMusicThumbnailLoader.m
//  SuMusicPlayerCC
//

#import "SuMusicThumbnailLoader.h"
#import "SuMusicMaterial.h"
#import <AVFoundation/AVFoundation.h>
#import <CommonCrypto/CommonDigest.h>

static NSString * const SuMusicCacheRoot = @"/var/mobile/Library/SuMusicCC/Cache";
static NSString * const SuMusicThumbDirName = @"Thumb";

/// 缩略图缓存键：文件路径 + 目标尺寸，避免不同尺寸互相覆盖
static NSString * SuMusicThumbCacheKey(NSString *path, CGFloat size) {
    return [NSString stringWithFormat:@"%@_%04.0f", path, size];
}

/// 将文件路径哈希成稳定的磁盘文件名（避免中文 / 特殊字符路径问题）
static NSString * SuMusicThumbDiskName(NSString *path, CGFloat size) {
    NSString *key = SuMusicThumbCacheKey(path, size);
    const char *bytes = [key UTF8String];
    unsigned char digest[CC_MD5_DIGEST_LENGTH];
    CC_MD5(bytes, (CC_LONG)strlen(bytes), digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_MD5_DIGEST_LENGTH; i++) {
        [hex appendFormat:@"%02x", digest[i]];
    }
    return [hex stringByAppendingString:@".jpg"];
}

@interface SuMusicThumbnailLoader ()

/// 内存缓存
@property (nonatomic, strong) NSCache<NSString *, UIImage *> *memoryCache;

@end

@implementation SuMusicThumbnailLoader

+ (instancetype)sharedLoader {
    static SuMusicThumbnailLoader *shared;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[SuMusicThumbnailLoader alloc] init];
    });
    return shared;
}

- (instancetype)init {
    if ((self = [super init])) {
        _memoryCache = [[NSCache alloc] init];
        _memoryCache.name = @"SuMusicThumbnailMemoryCache";
        _memoryCache.countLimit = 200;
        _memoryCache.totalCostLimit = 64 * 1024 * 1024; // 64MB
    }
    return self;
}

- (NSString *)diskCacheDirectory {
    return [SuMusicCacheRoot stringByAppendingPathComponent:SuMusicThumbDirName];
}

#pragma mark - 同步获取

- (UIImage *)thumbnailForMaterial:(SuMusicMaterial *)material size:(CGFloat)size {
    if (!material || !material.fileURL) {
        return nil;
    }
    NSString *path = material.filePath;
    NSString *cacheKey = SuMusicThumbCacheKey(path, size);

    // 1) 内存缓存
    UIImage *cached = [self.memoryCache objectForKey:cacheKey];
    if (cached) {
        return cached;
    }

    // 2) 磁盘缓存
    NSString *diskDir = self.diskCacheDirectory;
    NSString *diskName = SuMusicThumbDiskName(path, size);
    NSString *diskPath = [diskDir stringByAppendingPathComponent:diskName];
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:diskPath]) {
        UIImage *fromDisk = [UIImage imageWithContentsOfFile:diskPath];
        if (fromDisk) {
            [self.memoryCache setObject:fromDisk forKey:cacheKey];
            return fromDisk;
        }
    }

    // 3) 现场生成
    UIImage *generated = [self generateThumbnailForMaterial:material size:size];
    if (generated) {
        [self.memoryCache setObject:generated forKey:cacheKey];
        [self writeToDisk:generated atPath:diskPath];
    }
    return generated;
}

#pragma mark - 异步加载（用于 Cell 复用场景）

- (void)loadThumbnailIntoImageView:(UIImageView *)imageView
                         forMaterial:(SuMusicMaterial *)material
                              size:(CGFloat)size {
    // 弱引用，避免 Cell 复用导致的引用残留
    __weak UIImageView *weakView = imageView;

    // 立即设置占位，保证 200ms 内出现
    UIImage *placeholder = [self placeholderForMaterial:material size:size];
    weakView.image = placeholder;

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        UIImage *thumb = [self thumbnailForMaterial:material size:size];
        dispatch_async(dispatch_get_main_queue(), ^{
            // 仅当 imageView 仍绑定同一素材时才更新，防止复用串图
            if (weakView && ![weakView isKindOfClass:[NSNull class]]) {
                weakView.image = thumb ?: placeholder;
            }
        });
    });
}

- (UIImage *)placeholderForMaterial:(SuMusicMaterial *)material size:(CGFloat)size {
    CGFloat pixel = size * [UIScreen mainScreen].scale;
    CGRect rect = CGRectMake(0, 0, pixel, pixel);
    UIGraphicsBeginImageContextWithOptions(rect.size, NO, 0);
    [[UIColor colorWithRed:0.86 green:0.86 blue:0.87 alpha:1.0] setFill]; // #DCDCE0 中性灰
    UIRectFill(rect);
    UIImage *placeholder = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return placeholder;
}

#pragma mark - 生成缩略图

- (UIImage *)generateThumbnailForMaterial:(SuMusicMaterial *)material size:(CGFloat)size {
    if (material.materialType == SuMusicMaterialTypeVideo) {
        return [self generateVideoThumbnail:material size:size];
    }
    return [self generateImageThumbnail:material size:size];
}

/// 图片：直接读取并缩放到目标尺寸
- (UIImage *)generateImageThumbnail:(SuMusicMaterial *)material size:(CGFloat)size {
    UIImage *source = [UIImage imageWithContentsOfFile:material.filePath];
    if (!source) {
        return nil;
    }
    CGFloat pixel = size * [UIScreen mainScreen].scale;
    CGSize target = CGSizeMake(pixel, pixel);
    return [self scaledImage:source toSize:target];
}

/// 视频：AVAssetImageGenerator 抽取首帧
- (UIImage *)generateVideoThumbnail:(SuMusicMaterial *)material size:(CGFloat)size {
    NSURL *url = material.fileURL;
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
    if (!asset || CMTimeGetSeconds(asset.duration) <= 0.0) {
        // 时长为 0 或无效的视频无法取帧
        return nil;
    }

    AVAssetImageGenerator *generator = [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
    generator.requestedTimeDataType = AVAssetImageGeneratorSeconds;
    // 取靠近 0s 的关键帧作为首帧
    generator.requestedFrameAtTime = CMTimeMake(0, 1);
    generator.maximumSize = CGSizeMake(size * [UIScreen mainScreen].scale, size * [UIScreen mainScreen].scale);

    NSError *error = nil;
    CGImageRef cgImage = [generator copyCGImageAtTime:CMTimeMake(0, 1) actualTime:NULL error:&error];
    if (!cgImage) {
        return nil;
    }
    UIImage *frame = [UIImage imageWithCGImage:cgImage];
    CGImageRelease(cgImage);
    if (!frame) {
        return nil;
    }
    CGFloat pixel = size * [UIScreen mainScreen].scale;
    return [self scaledImage:frame toSize:CGSizeMake(pixel, pixel)];
}

/// 缩放并保持填充到目标正方形
- (UIImage *)scaledImage:(UIImage *)image toSize:(CGSize)size {
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    CGRect rect = CGRectMake(0, 0, size.width, size.height);
    [image drawInRect:rect];
    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

- (void)writeToDisk:(UIImage *)image atPath:(NSString *)path {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *error = nil;
    [fm createDirectoryAtPath:self.diskCacheDirectory withIntermediateDirectories:YES attributes:nil error:&error];
    NSData *jpeg = UIImageJPEGRepresentation(image, 0.85);
    [fm createFileAtPath:path contents:jpeg attributes:nil error:&error];
}

- (void)clearCaches {
    [self.memoryCache removeAllObjects];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *error = nil;
    [fm removeItemAtPath:self.diskCacheDirectory error:&error];
}

@end
