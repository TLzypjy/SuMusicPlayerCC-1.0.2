//
//  SuMusicThumbnailLoader.m
//  SuMusicPlayerCC
//

#import "SuMusicThumbnailLoader.h"
#import "SuMusicMaterial.h"
#import <AVFoundation/AVFoundation.h>
#import <CommonCrypto/CommonDigest.h>
#import <objc/runtime.h>

// 磁盘缓存根目录（与素材目录同级，指令指定路径）
static NSString * const SuMusicCacheRoot = @"/var/mobile/Library/SuMusicCC/Cache";
static NSString * const SuMusicThumbDirName = @"Thumb";

/// 缩略图固定生成像素边长：3x 下的 124pt 列宽 ≈ 372px
static CGFloat const SuMusicThumbPixelSize = 372;

/// imageView 关联对象 key：请求令牌（复用取消）
static void *SuMusicThumbTokenKey = &SuMusicThumbTokenKey;

/// 请求令牌自增计数（全局唯一，跨 imageView 递增）
static NSInteger SuMusicThumbTokenCounter = 0;

/// 磁盘缓存名：文件名过长时截断，并用全路径短哈希保证唯一
static NSString *SuMusicShortPathHash(NSString *path) {
    const char *bytes = [path UTF8String];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(bytes, (CC_LONG)strlen(bytes), digest);
    return [NSString stringWithFormat:@"%02x%02x%02x%02x", digest[0], digest[1], digest[2], digest[3]];
}

@interface SuMusicThumbnailLoader ()

/// 内存缓存（key = 文件路径 + 修改时间）
@property (nonatomic, strong) NSCache<NSString *, UIImage *> *memoryCache;

/// 缩略图生成专用串行队列（并发 1，满足指令「串行队列或并发数 ≤ 2」）
@property (nonatomic, strong) dispatch_queue_t generateQueue;

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

+ (CGFloat)thumbnailPixelSize {
    return SuMusicThumbPixelSize;
}

- (instancetype)init {
    if ((self = [super init])) {
        _memoryCache = [[NSCache alloc] init];
        _memoryCache.name = @"SuMusicThumbnailMemoryCache";
        _memoryCache.countLimit = 200;
        _memoryCache.totalCostLimit = 60 * 1024 * 1024; // 60MB
        _generateQueue = dispatch_queue_create("com.susu.sumusicplayercc.thumbgen", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (NSString *)diskCacheDirectory {
    return [SuMusicCacheRoot stringByAppendingPathComponent:SuMusicThumbDirName];
}

#pragma mark - 素材元信息

/// 文件修改时间戳（秒），读取失败返回 0
- (unsigned long long)modificationTimestampForMaterial:(SuMusicMaterial *)material {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDictionary *attributes = [fm attributesOfItemAtPath:material.filePath error:nil];
    NSDate *date = attributes[NSFileModificationDate];
    if (!date) {
        return 0;
    }
    return (unsigned long long)[date timeIntervalSince1970];
}

/// 内存缓存键：文件路径 + 修改时间（不新增 NSUserDefaults，仅内存键）
- (NSString *)cacheKeyForMaterial:(SuMusicMaterial *)material {
    return [NSString stringWithFormat:@"%@|%llu",
            material.filePath,
            [self modificationTimestampForMaterial:material]];
}

/// 磁盘缓存文件名：<文件名>_<修改时间戳>.jpg
/// 文件名超长时截断并附加全路径短哈希，保证唯一性与 255 字节文件名上限内。
- (NSString *)diskCacheNameForMaterial:(SuMusicMaterial *)material {
    NSString *name = material.fileName ?: @"material";
    if (name.length > 64) {
        name = [name substringToIndex:64];
    }
    return [NSString stringWithFormat:@"%@_%llu_%@.jpg",
            name,
            [self modificationTimestampForMaterial:material],
            SuMusicShortPathHash(material.filePath)];
}

#pragma mark - 同步获取（后台队列调用）

- (UIImage *)thumbnailForMaterial:(SuMusicMaterial *)material size:(CGFloat)size {
    if (!material || !material.fileURL) {
        return nil;
    }
    NSString *cacheKey = [self cacheKeyForMaterial:material];

    // 1) 内存缓存
    UIImage *cached = [self.memoryCache objectForKey:cacheKey];
    if (cached) {
        return cached;
    }

    // 2) 磁盘缓存（首次使用时确保目录存在）
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *diskPath = [[self diskCacheDirectory] stringByAppendingPathComponent:
                          [self diskCacheNameForMaterial:material]];
    if ([fm fileExistsAtPath:diskPath]) {
        UIImage *fromDisk = [UIImage imageWithContentsOfFile:diskPath];
        if (fromDisk) {
            [self rememberInMemoryCache:fromDisk forKey:cacheKey];
            return fromDisk;
        }
        // 磁盘缓存读取失败（损坏）：删除后降级重抽一次
        [fm removeItemAtPath:diskPath error:nil];
    }

    // 3) 现场生成并回写缓存
    UIImage *generated = [self generateThumbnailForMaterial:material size:size];
    if (generated) {
        [self rememberInMemoryCache:generated forKey:cacheKey];
        [self writeToDisk:generated atPath:diskPath];
    }
    return generated;
}

- (void)rememberInMemoryCache:(UIImage *)image forKey:(NSString *)key {
    CGFloat pixels = image.size.width * image.scale * image.size.height * image.scale;
    [self.memoryCache setObject:image forKey:key cost:(NSInteger)pixels * 4];
}

#pragma mark - 生成缩略图

- (UIImage *)generateThumbnailForMaterial:(SuMusicMaterial *)material size:(CGFloat)size {
    if (material.materialType == SuMusicMaterialTypeVideo) {
        return [self generateVideoThumbnail:material size:size];
    }
    return [self generateImageThumbnail:material size:size];
}

/// 图片：直接读取并缩到最长边 372px（保持宽高比，小图不放大）
- (UIImage *)generateImageThumbnail:(SuMusicMaterial *)material size:(CGFloat)size {
    UIImage *source = [UIImage imageWithContentsOfFile:material.filePath];
    if (!source) {
        return nil;
    }
    CGFloat maxPixel = size * 3.0; // 3x 下的目标像素
    CGFloat srcWidth = source.size.width * source.scale;
    CGFloat srcHeight = source.size.height * source.scale;
    CGFloat longest = MAX(srcWidth, srcHeight);
    if (longest <= 0) {
        return nil;
    }
    if (longest <= maxPixel) {
        return source;
    }
    CGFloat ratio = maxPixel / longest;
    CGSize target = CGSizeMake(round(srcWidth * ratio), round(srcHeight * ratio));
    return [self suDrawImage:source intoSize:target];
}

/// 视频：AVAssetImageGenerator 抽取首帧
/// - appliesPreferredTrackTransform = YES（修正旋转方向）
/// - maximumSize = 372×372
/// - requestedTimeToleranceBefore/After = 0.1s
/// - 取第 0.1s；时长为 0 或失败则取 0
- (UIImage *)generateVideoThumbnail:(SuMusicMaterial *)material size:(CGFloat)size {
    NSURL *url = material.fileURL;
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
    double durationSeconds = CMTimeGetSeconds(asset.duration);
    if (!(durationSeconds > 0.0)) {
        durationSeconds = 0.0;
    }

    AVAssetImageGenerator *generator = [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
    generator.appliesPreferredTrackTransform = YES;
    CGFloat maxPixel = size * 3.0;
    generator.maximumSize = CGSizeMake(maxPixel, maxPixel);
    generator.requestedTimeToleranceBefore = CMTimeMakeWithSeconds(0.1, 600);
    generator.requestedTimeToleranceAfter = CMTimeMakeWithSeconds(0.1, 600);

    // 目标时间：0.1s（时长为 0 或失败则取 0）
    CMTime requestedTime = CMTimeMakeWithSeconds(durationSeconds >= 0.1 ? 0.1 : 0.0, 600);
    NSError *error = nil;
    CGImageRef cgImage = [generator copyCGImageAtTime:requestedTime actualTime:NULL error:&error];
    if (!cgImage) {
        // 降级：取第 0s 再试一次
        cgImage = [generator copyCGImageAtTime:CMTimeMake(0, 1) actualTime:NULL error:&error];
    }
    if (!cgImage) {
        return nil;
    }
    UIImage *frame = [UIImage imageWithCGImage:cgImage];
    CGImageRelease(cgImage);
    if (!frame) {
        return nil;
    }
    // 归一化为正方形（aspect fill），与网格缩略图一致
    CGFloat pixel = size * 3.0;
    return [self suDrawImage:frame intoSize:CGSizeMake(pixel, pixel)];
}

/// 把图片等比铺满并裁剪到目标尺寸（aspect fill），背景线程安全的图像绘制
- (UIImage *)suDrawImage:(UIImage *)image intoSize:(CGSize)target {
    if (target.width <= 0 || target.height <= 0) {
        return nil;
    }
    CGFloat srcWidth = image.size.width * image.scale;
    CGFloat srcHeight = image.size.height * image.scale;
    if (srcWidth <= 0 || srcHeight <= 0) {
        return nil;
    }
    CGFloat ratio = MAX(target.width / srcWidth, target.height / srcHeight);
    CGSize drawSize = CGSizeMake(srcWidth * ratio, srcHeight * ratio);

    UIGraphicsBeginImageContextWithOptions(target, NO, 1.0);
    [image drawInRect:CGRectMake((target.width - drawSize.width) / 2.0,
                                 (target.height - drawSize.height) / 2.0,
                                 drawSize.width, drawSize.height)];
    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

- (void)writeToDisk:(UIImage *)image atPath:(NSString *)path {
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:[self diskCacheDirectory]
  withIntermediateDirectories:YES
                   attributes:nil
                        error:nil];
    NSData *jpeg = UIImageJPEGRepresentation(image, 0.85);
    if (jpeg) {
        [jpeg writeToFile:path atomically:YES];
    }
}

#pragma mark - 异步加载（Cell 复用场景）

- (void)loadThumbnailIntoImageView:(UIImageView *)imageView
                        forMaterial:(SuMusicMaterial *)material
                             size:(CGFloat)size {
    if (!imageView) {
        return;
    }

    // 请求令牌：每次新请求递增；复用/取消后旧请求的回填被令牌过滤
    NSInteger token = ++SuMusicThumbTokenCounter;
    objc_setAssociatedObject(imageView, SuMusicThumbTokenKey, @(token), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    // 立即置占位图（#F2F2F7），保证 200ms 内有内容
    imageView.image = [self placeholderImage];

    if (!material) {
        return;
    }

    dispatch_async(self.generateQueue, ^{
        UIImage *thumb = [self thumbnailForMaterial:material size:size];
        dispatch_async(dispatch_get_main_queue(), ^{
            // 仅当 imageView 的请求令牌仍是本次请求时才回填，防止复用错图
            NSNumber *currentToken = objc_getAssociatedObject(imageView, SuMusicThumbTokenKey);
            if (currentToken && [currentToken integerValue] == token) {
                imageView.image = thumb ?: [self placeholderImage];
            }
        });
    });
}

/// 复用取消：令牌置 nil，旧请求回填被跳过
- (void)cancelLoadForImageView:(UIImageView *)imageView {
    if (!imageView) {
        return;
    }
    objc_setAssociatedObject(imageView, SuMusicThumbTokenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

#pragma mark - 预取（后台串行队列）

- (void)prefetchMaterials:(NSArray<SuMusicMaterial *> *)materials thumbnailSize:(CGFloat)size {
    if (materials.count == 0) {
        return;
    }
    dispatch_async(self.generateQueue, ^{
        for (SuMusicMaterial *material in materials) {
            [self thumbnailForMaterial:material size:size];
        }
    });
}

/// 占位图：#F2F2F7 纯色
- (UIImage *)placeholderImage {
    static UIImage *placeholder;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(8, 8), NO, 0);
        [[UIColor colorWithRed:0.949 green:0.949 blue:0.969 alpha:1.0] setFill]; // #F2F2F7
        UIRectFill(CGRectMake(0, 0, 8, 8));
        placeholder = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        placeholder = [placeholder imageWithRenderingMode:UIImageRenderingModeDefault];
    });
    return placeholder;
}

#pragma mark - 清理

- (void)clearCaches {
    [self.memoryCache removeAllObjects];
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:[self diskCacheDirectory] error:nil];
}

@end
