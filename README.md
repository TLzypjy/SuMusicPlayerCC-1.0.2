# SuMusicPlayerCC 1.0.2 — 素材库网格改造

将「音乐播放器设置」页中的「媒体文件选择」展开列表，改造为独立的**素材库**页面：
三列缩略图网格、视频/图片角标、播放键、文件名胶囊、底部选中圆点，顶部为
`关闭 / 素材库 (N) / 导入`。功能行为（选中素材、导入、刷新控制中心）沿用现有逻辑，仅替换界面。

## 目录结构

```
SuMusicPlayerCC_1.0.2/
├── Makefile                                # Theos 构建配置（iphoneos-arm64，含 arm64e）
├── control                                 # deb 元数据，Version=1.0.2
├── SuMusicMaterialLibrary/
│   ├── SuMusicMaterial.h / .m              # 素材数据模型 + 目录枚举
│   ├── SuMusicThumbnailLoader.h / .m       # 缩略图：NSCache 内存缓存 + 磁盘缓存 + AVAssetImageGenerator 首帧
│   ├── SuMusicMaterialCell.h / .m          # 网格单元：缩略图/角标/播放键/胶囊/选中圆点
│   ├── SuMusicMaterialLibraryViewController.h / .m  # 三列网格页面 + 导入
│   └── Tweak.xm                            # 设置页 hook：媒体文件选择行 → present 素材库
└── scripts/
    ├── build_deb.py                        # 跨平台 deb 打包器（已验证）
    └── build.sh                            # Theos 构建 + 打包脚本
```

## 关键实现点

- **命名**：所有新增类/方法/属性均带 `SuMusic` 前缀，符合插件约定。
- **三列网格**：iPhone 14 Pro Max 430pt 基准，左右边距 16pt、列间距 12pt，
  列宽 ≈124.7pt（`available / 3` 动态计算，兼容不同屏幕）。
- **缩略图**：正方形、圆角 12pt；视频用 `AVAssetImageGenerator` 抽取首帧，
  图片直接缩放；`NSCache` 内存缓存 + `/var/mobile/Library/SuMusicCC/Cache/Thumb/`
  磁盘缓存（按「路径+尺寸」MD5 命名，避免中文路径与尺寸互覆）。
- **Cell 组成**：左上角类型角标（视频/图片）、视频中心播放键、底部文件名胶囊
  （#BFBFC4 底色）、缩略图右下角选中圆点（未选中 #D1D1D6 / 选中 #0A84FF）。
- **异步加载**：缩略图后台生成 + 主线程回填，立即设置占位图，保证 200ms 内出现。
- **导入**：复用 `UIDocumentPickerViewController`，按扩展名归入 Video / Image 目录，
  自动生成唯一文件名，刷新网格与计数。
- **设置页改造**：保留「媒体文件选择」行，箭头 `chevronDownImage` →
  `UITableViewCellAccessoryDisclosureIndicator`（右箭头），点击 present
  素材库页面（全屏 modal），选中结果通过 `selectionBlock` 回写刷新。

## 构建（需 Theos 环境）

本仓库的 Objective-C 源码需在装有 **Theos** 的 macOS / Linux 环境编译：

```bash
bash scripts/build.sh          # = make CONFIG=release + 打包
```

产物：`packages/com.susu.sumusicplayercc_1.0.2_iphoneos-arm64.deb`

## deb 打包器（已验证，无需编译器）

`scripts/build_deb.py` 是纯 Python 的 deb 打包器，不依赖编译器，可在任意平台运行：

```bash
python scripts/build_deb.py \
  --control control \
  --staged <staged目录> \
  --output out.deb
```

已验证：生成的 deb 与原始包结构一致 —— ar 魔数 `!<arch>\n`、成员顺序
`debian-binary / control.tar.xz / data.tar.xz`、`debian-binary` 为 `2.0\n`（LF）、
`control` 中 `Version: 1.0.2`，data.tar.xz 路径为 POSIX 风格。

## 验收对照（指令清单）

| # | 验收项 | 状态 |
|---|--------|------|
| 1 | 编译通过 | 源码完整，需 Theos 环境编译 |
| 2 | 三列网格 | ✅ 动态列宽，430pt 基准 ≈124.7pt |
| 3 | 缩略图 200ms 内出现 | ✅ 占位图即时 + 后台加载回填 |
| 4 | 选中切换 | ✅ 圆点 #0A84FF / #D1D1D6 |
| 5 | 导入 +1 | ✅ UIDocumentPicker + 唯一命名 + 刷新 |
| 6 | 删除同步 | ✅ 素材重枚举 + reloadData |
| 7 | 版本 1.0.2 | ✅ control Version=1.0.2 |
| 8 | debian-binary "2.0"+LF | ✅ 已验证 |
| 9 | deb 结构 | ✅ 打包器已验证 |
| 10 | SuMusic 前缀 | ✅ 全部新增类/方法带前缀 |
