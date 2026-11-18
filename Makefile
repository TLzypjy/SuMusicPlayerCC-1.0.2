#
#  Makefile — SuMusicPlayerCC 素材库改造
#  使用 Theos 构建，目标为 iphoneos-arm64（含 arm64e）。
#
#  构建：  make CONFIG=release
#  产物：  packages/com.susu.sumusicplayercc_1.0.2_iphoneos-arm64.deb
#

TARGET := iphone:clang:latest:16.0
ARCHS = arm64 arm64e
INSTALL_PREFIX = /var/jb

TWEAK_NAME = SuMusicPlayerCC

SuMusicPlayerCC_FILES = \
    SuMusicMaterialLibrary/SuMusicMaterial.m \
    SuMusicMaterialLibrary/SuMusicThumbnailLoader.m \
    SuMusicMaterialLibrary/SuMusicMaterialCell.m \
    SuMusicMaterialLibrary/SuMusicMaterialLibraryViewController.m \
    SuMusicMaterialLibrary/Tweak.xm

SuMusicPlayerCC_CFLAGS = -fobjc-arc -Wno-unused-variable
SuMusicPlayerCC_FRAMEWORKS = UIKit AVFoundation QuartzCore UniformTypeIdentifiers
SuMusicPlayerCC_PRIVATE_FRAMEWORKS =
SuMusicPlayerCC_RESOURCE_NAMES =

# 依赖（与原始 deb 一致）
SuMusicPlayerCC_DEPENDENT_PACKAGES = com.opa334.ccsupport

# 固定 deb 版本号为纯净的 1.0.2。
# 注意：必须在 include common.mk 之前设置——Theos 的 package.mk 是在 common.mk
# 加载时解析的，此时会通过 $(value PACKAGE_VERSION) 把版本值固定下来。
# 写在 include 之后不会被捕获，版本会回退为默认的「基础版本-构建号+构建名」格式
# （如 1.0.2-1+debug，其中 +debug 来自 PACKAGE_BUILDNAME 的默认值）。
PACKAGE_VERSION = 1.0.2

include $(THEOS)/makefiles/common.mk

# 引入 tweak 构建规则。这是 Theos tweak 项目的必需步骤：
# 它会加载 master/tweak.mk，把 internal-all 与 $(TWEAK_NAME).all.tweak.variables
# 绑定，从而让 `make all` 真正触发 Tweak.xm 的编译。
# 缺失这一行会导致 "make: Nothing to be done for 'all'"（无任何编译发生）。
include $(THEOS_MAKE_PATH)/tweak.mk

# 打包为 deb
SuMusicPlayerCC_PACKAGE_TYPE = deb

after-install::
	@echo "SuMusicPlayerCC 1.0.2 installed."
