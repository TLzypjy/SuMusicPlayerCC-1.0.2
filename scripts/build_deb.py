#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
build_deb.py — 将 staged 目录打包为 iOS 越狱 deb 包。

deb 本质是 ar(1) 归档，内含三个成员（顺序固定）：
    debian-binary        -> "2.0\n"（LF，必须）
    control.tar.xz       -> control 元数据
    data.tar.xz          -> 实际安装的文件树

本脚本不依赖任何编译器，可在 Windows / macOS / Linux 上直接运行，
用于把 Theos 构建产物或手工 staged 的安装文件打包成 deb。

用法：
    python build_deb.py --control control --staged <dir> --output out.deb

其中 <dir> 的目录结构应模拟安装后的根路径，例如：
    <dir>/var/jb/Library/ControlCenter/Bundles/SuMusicPlayerCC.bundle/...
    <dir>/var/jb/Library/MobileSubstrate/DynamicLibraries/...
"""

import argparse
import io
import os
import sys
import tarfile

# 标准库自带 lzma（XZ 压缩），直接复用
import lzma

# ---------- ar 归档写入 ----------

def _ar_header(name: str, size: int) -> bytes:
    """生成 BSD/GNU 通用的 ar 成员头（60 字节）。

    deb 使用 "BSD/GNU" 风格：前 60 字节头部 + 数据，成员以 '`\n'(0x60 0x0a) 结束。
    头部字段：name(16) + mtime(12) + uid(6) + gid(6) + mode(8) + size(10) + magic(2)
    """
    if len(name) > 16:
        # 长名需要 #// 扩展，deb 实际不出现，这里直接截断并报错更稳妥
        raise ValueError(f"ar member name too long: {name}")
    field = name.encode("ascii").ljust(16, b" ")
    mtime = b"0".ljust(12, b" ")
    uid = b"0".ljust(6, b" ")
    gid = b"0".ljust(6, b" ")
    mode = b"100644".ljust(8, b" ")
    size_field = str(size).encode("ascii").ljust(10, b" ")
    magic = b"`\n"
    return field + mtime + uid + gid + mode + size_field + magic


def build_ar(members: list) -> bytes:
    """members: [(name, bytes_data), ...]，按 deb 要求顺序写入。

    deb 归档以 ar 全局魔数 '!<arch>\\n' 开头，成员顺序固定为
    debian-binary / control.tar.xz / data.tar.xz，结尾为 '`\\n'。
    """
    out = io.BytesIO()
    # ar 全局魔数
    out.write(b"!<arch>\n")
    for name, data in members:
        out.write(_ar_header(name, len(data)))
        out.write(data)
        # 与原始 deb 一致：成员之间不做 8 字节对齐填充
    # 结束标记
    out.write(b"`\n")
    return out.getvalue()


# ---------- tar.xz 写入 ----------

def _make_tar_xz(staged_dir: str, root: str) -> bytes:
    """把 staged_dir 下 root 对应的目录树打包成 tar.xz（数据）。"""
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w", format=tarfile.GNU_FORMAT) as tar:
        # 逐个添加文件，保留相对路径与权限
        base = os.path.join(staged_dir, root) if root else staged_dir
        if not os.path.exists(base):
            raise FileNotFoundError(f"staged 根不存在: {base}")

        # 目录条目（与原始 deb 一致：data.tar 内含各级目录，mode 0755）
        seen_dirs = set()
        for dirpath, dirnames, filenames in os.walk(base):
            rel_dir = os.path.relpath(dirpath, staged_dir)
            rel_dir_posix = rel_dir.replace(os.sep, "/")
            if rel_dir_posix not in seen_dirs:
                seen_dirs.add(rel_dir_posix)
                di = tarfile.TarInfo(rel_dir_posix)
                di.type = tarfile.DIRTYPE
                di.mode = 0o755
                di.uid = 0
                di.gid = 0
                di.mtime = os.stat(dirpath).st_mtime
                tar.addfile(di)

        for dirpath, dirnames, filenames in os.walk(base):
            dirnames.sort()
            for fn in sorted(filenames):
                full = os.path.join(dirpath, fn)
                rel = os.path.relpath(full, staged_dir)
                # 规范化为 POSIX 风格路径（deb 内路径用 /）
                rel_posix = rel.replace(os.sep, "/")
                ti = tarfile.TarInfo(rel_posix)
                st = os.stat(full)
                ti.size = st.st_size
                ti.mtime = st.st_mtime
                # 权限：dylib 与无扩展名的可执行（如 bundle 主二进制）必须 0755，
                # 否则安装后 dlopen/加载失败；其余（plist 等）保持 0644。
                # 与原始 deb 一致：binary mode=755，plist mode=644。
                is_executable = fn.endswith(".dylib") or ("." not in fn)
                ti.mode = 0o755 if is_executable else 0o644
                ti.uid = 0
                ti.gid = 0
                ti.type = tarfile.REGTYPE
                with open(full, "rb") as f:
                    tar.addfile(ti, f)
    # XZ 压缩（deb 使用 .tar.xz）
    return lzma.compress(buf.getvalue(), format=lzma.FORMAT_XZ, check=lzma.CHECK_CRC64)


def _make_control_tar_xz(control_path: str) -> bytes:
    """control 元数据打包成 tar.xz（含 control 文件）。"""
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w", format=tarfile.GNU_FORMAT) as tar:
        control_text = open(control_path, "r", encoding="utf-8").read()
        data = control_text.encode("utf-8")
        ti = tarfile.TarInfo("./control")
        ti.size = len(data)
        ti.mtime = 0
        ti.mode = 0o644
        ti.uid = 0
        ti.gid = 0
        ti.type = tarfile.REGTYPE
        tar.addfile(ti, io.BytesIO(data))
    return lzma.compress(buf.getvalue(), format=lzma.FORMAT_XZ, check=lzma.CHECK_CRC64)


# ---------- 主流程 ----------

def main():
    ap = argparse.ArgumentParser(description="打包 iOS 越狱 deb")
    ap.add_argument("--control", required=True, help="control 文件路径")
    ap.add_argument("--staged", required=True, help="staged 目录（模拟安装根）")
    ap.add_argument("--output", required=True, help="输出 deb 路径")
    ap.add_argument("--root", default="",
                    help="staged 中数据所在的子目录（默认 staged 本身即根）")
    args = ap.parse_args()

    if not os.path.isfile(args.control):
        sys.exit(f"control 文件不存在: {args.control}")
    if not os.path.isdir(args.staged):
        sys.exit(f"staged 目录不存在: {args.staged}")

    # debian-binary：必须是 "2.0" + LF
    debian_binary = b"2.0\n"

    control_xz = _make_control_tar_xz(args.control)
    data_xz = _make_tar_xz(args.staged, args.root)

    members = [
        ("debian-binary", debian_binary),
        ("control.tar.xz", control_xz),
        ("data.tar.xz", data_xz),
    ]
    payload = build_ar(members)

    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
    with open(args.output, "wb") as f:
        f.write(payload)

    print(f"[ok] 已生成 deb: {args.output}")
    print(f"     大小: {len(payload)} 字节")
    print(f"     debian-binary: {debian_binary!r}")


if __name__ == "__main__":
    main()
