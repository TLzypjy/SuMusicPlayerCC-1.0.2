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

include $(THEOS)/makefiles/common.mk

# 打包为 deb
SuMusicPlayerCC_PACKAGE_TYPE = deb

after-install::
	@echo "SuMusicPlayerCC 1.0.2 installed."
