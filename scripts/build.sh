#!/usr/bin/env bash
#
#  build.sh — SuMusicPlayerCC 1.0.2 构建 + 打包
#
#  需要在装有 Theos 的环境（macOS / Linux / 越狱设备）中运行。
#  本脚本先调用 Theos 编译生成 tweak 与依赖，再统一打包为 deb。
#
#  用法：  bash scripts/build.sh
#

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

echo "[1/2] 使用 Theos 编译（CONFIG=release）..."
make CONFIG=release

echo ""
echo "[2/2] 打包 deb..."
# Theos 默认会在 packages/ 下生成 .deb，文件名形如
#   com.susu.sumusicplayercc_1.0.2_iphoneos-arm64.deb
# 若需要用 build_deb.py 重新打包（例如替换了 control 或 staged 内容），
# 可手动指定 --staged 与 --control：
#
#   python scripts/build_deb.py \
#     --control control \
#     --staged <staged_dir> \
#     --output packages/com.susu.sumusicplayercc_1.0.2_iphoneos-arm64.deb

DEB=$(ls -1 packages/com.susu.sumusicplayercc_1.0.2_*.deb 2>/dev/null | head -1 || true)
if [ -n "$DEB" ]; then
    echo "[ok] 构建完成："
    ls -lh "$DEB"
else
    echo "[warn] 未在 packages/ 找到 1.0.2 deb，请检查 Theos 输出。"
fi
