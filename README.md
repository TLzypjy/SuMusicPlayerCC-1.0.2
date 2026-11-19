# SuMusicPlayerCC 1.0.2 — 素材库网格改造

将「音乐播放器设置」页中的「媒体文件选择」展开列表，改造为独立的**素材库**页面：
三列缩略图网格、视频/图片角标、播放键、文件名胶囊、底部选中圆点，顶部为
`关闭 / 素材库 (N) / 导入`。功能行为（选中素材、导入、刷新控制中心）沿用现有逻辑，仅替换界面。

## 目录结构

```
SuMusicPlayerCC_1.0.2/
├── Makefile                                # Theos 构建配置（iphoneos-arm64，含 arm64e）
├── control                                 # deb 元数据，Version=1.0.2
├── SuMusicPlayerCC.plist                   # 新 dylib 过滤器（ControlCenter + Preferences）
├── layout/                                 # 原 1.0.1 包文件原样保留（bundle + 两个 hook dylib）
│   └── Library/...                         # 按未加前缀路径组织，rootless scheme 统一加 var/jb
├── SuMusicMaterialLibrary/
│   ├── SuMusicMaterial.h / .m              # 素材数据模型 + 目录枚举（不排序，沿用原顺序）
│   ├── SuMusicThumbnailLoader.h / .m       # 缩略图：串行队列生成 + NSCache + 磁盘缓存（mtime 键）
│   ├── SuMusicMaterialCell.h / .m          # 网格单元：缩略图/角标/播放键/胶囊/选中圆点
│   ├── SuMusicMaterialLibraryViewController.h / .m  # 三列网格页面 + 导入
│   └── Tweak.xm                            # 设置页 hook：媒体文件选择行 → present 素材库
└── scripts/
    ├── build_deb.py                        # 跨平台 deb 打包器（含 0755 权限处理）
    └── build.sh                            # Theos 构建 + 打包脚本
```

## 与原插件 1.0.1 的对接（均从原包二进制核实）

- **NSUserDefaults 域**：原插件跨进程共享配置一律走
  `initWithSuiteName:@"com.susu.sumusicplayercc"`。选中回写沿用同 suite 的
  `selectedMediaItem`（文件名）/ `selectedMediaType`（`video` / `image`）键，
  不写 `standardUserDefaults`（否则控制中心进程读不到）。
- **刷新链路**：原插件经 `CFNotificationCenter`（DarwinNotifyCenter）观察
  `com.susu.sumusicplayercc/SettingsChanged` 触发模块重载。选中后 Darwin 发一份、
  NSNotificationCenter 补发一份，覆盖跨进程与同进程两种观察者。
  不新增键、不新增通知名。
- **设置页类**：`SuMusicPlayerCCSettingsListController`（PSListController 子类，
  由 bundle Info.plist 的 `CCSPreferencesRootListController` 指定）。分组头
  specifier 的动作是 `toggleMediaGroup` —— 识别入口行优先匹配该动作，退回
  name/identifier 文本匹配；`toggleMediaGroup` 本体改为呈现素材库，并把动作
  替换为 `%new` 的 `suMusicPresentMediaLibrary`——didSelect 拦截、buttonAction
  替换、原动作三条点击链路全部收敛到素材库，展开永不发生。
- **hook 初始化时机**：模块 bundle 由 CCSupport 在设置里点开模块页时才懒加载，
  dylib 构造阶段目标类尚未注册——`%ctor` 用 0.5s 主队列定时器轮询
  `objc_getClass`，类出现后立即 `%init`（类已存在的进程首轮即初始化）。
  无显式等待的 `%init` 在 Settings.app 进程内会整体落空。
- **注入范围与 scheme**：目标设备为 roothide 越狱（TweakLoader 只扫
  `usr/lib/TweakInject/`，rootless 的 DynamicLibraries 目录不会被扫描），
  Makefile 用 `THEOS_PACKAGE_SCHEME = roothide`，dylib 落到
  `var/jb/usr/lib/TweakInject/`。模块设置页可能宿主在 SpringBoard
  （kongzhimeihua/CCSupport 的模块编辑）或 Settings.app，filter 覆盖
  `com.apple.springboard` + `com.apple.ControlCenter` + `com.apple.Preferences`。
- **素材顺序**：原 `loadMediaFromDirectory` 对目录枚举结果不排序，素材库沿用
  `contentsOfDirectoryAtPath:` 原始顺序（指令 3.4：与改造前列表顺序一致）。

## 关键实现点

- **命名**：所有新增类/方法/属性均带 `SuMusic` 前缀，符合插件约定。
- **三列网格**：430pt 基准，左右边距 16pt、列间距 12pt，列宽 =（屏宽-32-24）/3
  ≈124.7pt（动态计算，兼容不同屏幕）；行间距 18pt，sectionInset top 10 / bottom 24；
  单元格高度 = 列宽 + 8 + 20 + 8 + 8。
- **导航条**：56pt，安全区下方；关闭/导入 #007AFF 17pt regular（左右各 16pt 内边距），
  标题 labelColor 17pt semibold 绝对居中；下方 8pt 处 0.5pt #E5E5EA 分隔线。
- **缩略图**：正方形、圆角 12pt、aspectFill；视频用 `AVAssetImageGenerator`
  （appliesPreferredTrackTransform、0.1s 容差、取 0.1s、失败降级取 0s），
  图片按最长边缩到 372px；专用串行后台队列生成，主线程只赋值；
  `NSCache`（countLimit 200 / 60MB，key = 路径+修改时间）+
  `/var/mobile/Library/SuMusicCC/Cache/Thumb/<文件名>_<修改时间戳>.jpg` 磁盘缓存，
  读取失败自动降级重抽。
- **Cell 复用**：`prepareForReuse` 取消未完成请求（请求令牌过滤回填）并置回
  占位图 #F2F2F7，防止快速滚动错图。
- **Cell 组成**：左上角类型角标（视频/图片，白字 10pt medium，rgba(0,0,0,0.45)，
  高 18，圆角 4，距左上 6）、视频中心播放键（28pt 圆 rgba(0,0,0,0.40) +
  白色 play.fill 11pt）、文件名胶囊（宽列宽-12、高 20、圆角 10、#BFBFC4、
  白字 12pt medium、middle truncation）、胶囊下方 8pt 水平居中选中圆点
  （直径 8，#D1D1D6 / #0A84FF）。
- **选中**：点击卡片单选切换（已选中项保持选中，不提供取消——原插件始终有
  选中素材），只刷新可见 cell 圆点；进入页面按当前选中回显蓝点；
  选中即时写回并刷新，不关闭页面。
- **导入**：`UIDocumentPickerViewController`（UTTypeImage / UTTypeMovie，
  asCopy:YES）→ 按扩展名归入 Video（mp4/mov/m4v）/ Image → 唯一文件名 →
  新条目排在最前 → 刷新网格与计数并排队生成缩略图。
- **空目录**：标题「素材库 (0)」+ 居中「暂无素材，点右上角导入」（#8E8E93，15pt）。

## 与指令的偏差说明（有意为之）

1. **导入类型**：指令 3.6 要求「完全复用现有 UIDocumentPickerViewController
   流程与 supported types」。核实原包二进制后确认：原插件的 documentPicker
   链路（`documentPicker:didPickDocumentsAtURLs:`）是**配置/授权码导入**
   （public.text），并不支持选择视频/图片。为满足验收 #7（导入视频成功），
   采用同一委托方法名 + 媒体类型（UTTypeImage/UTTypeMovie）实现媒体导入。
2. **取消选中**：指令未定义"再次点击已选中项"的行为；原插件始终持有选中素材
   （selectedMediaItem），故不提供取消选中，避免控制中心陷入无素材状态。

## 构建（GitHub Actions）

推送到 main 后 CI 自动构建：`make CONFIG=release package`（Theos，macOS runner，
arm64 + arm64e）。Makefile 显式 `export THEOS_PACKAGE_SCHEME = roothide`——
roothide 设备只从 `usr/lib/TweakInject/` 注入；layout/ 按未加前缀路径组织，
由 scheme 统一加 `var/jb`，data.tar 内所有文件必须都在 `var/jb/` 之下
（出现过两类历史事故：缺 scheme 时 dylib 落到根路径导致安装报只读；
rootless scheme 下 layout 带前缀导致 `var/jb/var/jb` 双重前缀）。
产物 artifact：`com.susu.sumusicplayercc_1.0.2_iphoneos-arm`（packages/*.deb）。

本地若有 Theos 环境可执行：

```bash
bash scripts/build.sh          # = make CONFIG=release + 打包
```

## deb 打包器（本地备用，无需编译器）

`scripts/build_deb.py` 是纯 Python 的 deb 打包器（ar + tar.xz，debian-binary
为 `2.0\n`），可执行文件（dylib / bundle 主二进制）按 0755、其余按 0644 写入：

```bash
python scripts/build_deb.py --control control --staged <staged目录> --output out.deb
```

## 验收对照（指令清单）

| # | 验收项 | 状态 |
|---|--------|------|
| 1 | Theos 编译（arm64+rootless） | 由 GitHub Actions 完成，见最新 run |
| 2 | 设置页其余分区不变 | ✅ 仅改造「媒体文件选择」行与其子行 |
| 3 | 点「媒体文件选择」直接弹素材库 | ✅ hook didSelect（specifierAtIndexPath: 匹配） |
| 4 | 三列网格按 03 图 | ✅ 缩略图/角标/播放键/胶囊/圆点均按规格 |
| 5 | 缩略图 200ms 占位、滚动无错图 | ✅ 占位即时 + 令牌过滤 + 复用取消 |
| 6 | 点素材蓝点切换并刷新控制中心 | ✅ suite 写回 + SettingsChanged（Darwin+NS） |
| 7 | 导入后 N+1、新条目最前 | ✅ 导入链路 + 置顶排序 + 预取缩略图 |
| 8 | 删除文件重进列表同步 | ✅ 每次进入重新枚举 |
| 9 | 空目录/损坏文件/超长文件名 | ✅ 空提示 / 占位图降级 / 磁盘名截断+哈希 |
| 10 | 关闭后内存释放 | ✅ NSCache 有上限，页面 dismiss 无常驻引用 |
| 11 | debian-binary "2.0"+LF | ✅ 打包器与 Theos 均符合 |
| 12 | data.tar 含原包 6 文件 + 新 dylib/plist | ✅ layout/ 回填（见纠偏指令方案 A） |
| 13 | SuMusic 前缀 | ✅ 全部新增类/方法带前缀 |

编译与真机行为以 GitHub Actions 最新 run 与设备实测为准。
