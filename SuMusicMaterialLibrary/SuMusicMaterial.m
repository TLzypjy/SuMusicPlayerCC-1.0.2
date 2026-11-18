//
//  SuMusicMaterial.m
//  SuMusicPlayerCC
//

#import "SuMusicMaterial.h"

// 素材根目录（与插件现有素材目录保持一致）
static NSString * const SuMusicMaterialRootDirectory = @"/var/mobile/Library/SuMusicCC";
static NSString * const SuMusicVideoDirectoryName = @"Video";
static NSString * const SuMusicImageDirectoryName = @"Image";

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

    // 按文件名排序，保证网格展示顺序稳定
    NSArray<NSString *> *sorted = [items sortedArrayUsingComparator:^(NSString *a, NSString *b) {
        return [a compare:b options:NSAnchoredSearch];
    }];

    for (NSString *name in sorted) {
        NSString *fullPath = [directory stringByAppendingPathComponent:name];
        NSURL *url = [NSURL fileURLWithPath:fullPath];

        // 简单扩展名判断，过滤非媒体文件
        NSString *ext = name.pathExtension.lowercaseString;
        BOOL looksLikeMedia = YES;
        if (type == SuMusicMaterialTypeVideo) {
            looksLikeMedia = [@[@"mp4", @"mov", @"m4v", @"mkv", @"avi", @"3gp", @"webm", @"caf"] containsObject:ext];
        } else {
            looksLikeMedia = [@[@"png", @"jpg", @"jpeg", @"gif", @"heic", @"heif", @"bmp", @"webp"] containsObject:ext];
        }
        if (!looksLikeMedia) {
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
