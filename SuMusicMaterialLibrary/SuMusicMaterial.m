//
//  SuMusicMaterial.m
//  SuMusicPlayerCC
//

#import "SuMusicMaterial.h"

// 素材根目录（与插件现有素材目录保持一致）
static NSString * const SuMusicMaterialRootDirectory = @"/var/mobile/Library/SuMusicCC";
static NSString * const SuMusicVideoDirectoryName = @"Video";
static NSString * const SuMusicImageDirectoryName = @"Image";

// 视频扩展名 / 图片扩展名（与指令一致）
static NSArray<NSString *> *SuMusicVideoExtensions(void) {
    return @[@"mp4", @"mov", @"m4v"];
}
static NSArray<NSString *> *SuMusicImageExtensions(void) {
    return @[@"jpg", @"jpeg", @"png", @"heic"];
}

// 类扩展：头文件中 fileURL 对外为 readonly，工厂方法内部需要赋值，
// 这里在实现文件内重新声明为 readwrite（对外接口仍保持 readonly）。
@interface SuMusicMaterial ()
@property (nonatomic, strong, readwrite) NSURL *fileURL;
@end

@implementation SuMusicMaterial

+ (instancetype)materialWithURL:(NSURL *)url type:(SuMusicMaterialType)type {
    SuMusicMaterial *material = [[SuMusicMaterial alloc] init];
    material.fileURL = url;
    material.materialType = type;
    return material;
}

- (NSString *)filePath {
    return [self.fileURL path];
}

- (NSString *)fileName {
    return self.fileURL.lastPathComponent ?: @"";
}

+ (NSArray<SuMusicMaterial *> *)materialsInDirectory:(NSString *)directory
                                                 type:(SuMusicMaterialType)type {
    NSMutableArray<SuMusicMaterial *> *result = [NSMutableArray array];

    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *items = [fm contentsOfDirectoryAtPath:directory error:nil];
    if (!items) {
        return @[];
    }

    // 排序沿用原插件 loadMediaFromDirectory 的现有顺序：
    // 原实现对目录枚举结果不排序，直接按 contentsOfDirectoryAtPath:error: 返回
    // 的顺序使用，这里保持一致，保证网格展示顺序与改造前的列表顺序一致。
    NSArray<NSString *> *allowedExtensions = (type == SuMusicMaterialTypeVideo)
        ? SuMusicVideoExtensions()
        : SuMusicImageExtensions();

    for (NSString *name in items) {
        NSString *fullPath = [directory stringByAppendingPathComponent:name];
        NSURL *url = [NSURL fileURLWithPath:fullPath];

        // 扩展名过滤（与指令一致）
        NSString *ext = name.pathExtension.lowercaseString;
        if (![allowedExtensions containsObject:ext]) {
            continue;
        }

        SuMusicMaterial *material = [SuMusicMaterial materialWithURL:url type:type];
        [result addObject:material];
    }

    return result;
}

+ (NSArray<SuMusicMaterial *> *)allMaterials {
    NSString *videoDir = [SuMusicMaterialRootDirectory stringByAppendingPathComponent:SuMusicVideoDirectoryName];
    NSString *imageDir = [SuMusicMaterialRootDirectory stringByAppendingPathComponent:SuMusicImageDirectoryName];

    NSMutableArray<SuMusicMaterial *> *all = [NSMutableArray array];
    [all addObjectsFromArray:[SuMusicMaterial materialsInDirectory:videoDir type:SuMusicMaterialTypeVideo]];
    [all addObjectsFromArray:[SuMusicMaterial materialsInDirectory:imageDir type:SuMusicMaterialTypeImage]];
    return all;
}

@end
