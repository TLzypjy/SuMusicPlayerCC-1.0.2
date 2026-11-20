#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
repack_jbroot.py — 把 Theos rootless 产出的 deb 重打为 roothide 格式。

背景：目标设备为 roothide 越狱，其 dpkg 为 roothide 补丁版，包格式与
roothide 官方源一致（以 FiveIconDock.deb 实测为准）：
  - control: Architecture: iphoneos-arm64e；Depends 含 oldabi
    （roothide 用它标记「本包使用旧根路径，安装时自动转换进 jbroot」）
  - data.tar: 根级旧路径 ./Library/...（无 var/jb 前缀），安装时由 roothide
    dpkg 转换为 <jbroot>/Library/...

Theos rootless scheme 产出的是 var/jb/... 路径 + iphoneos-arm64 架构，
在该设备上：var/jb/Library/... 可装（但 hook 目录 Library/MobileSubstrate/
DynamicLibraries 不会被 roothide TweakLoader 扫描），var/jb/usr/... 与
jbroot 字面路径解压直接失败。因此本脚本：
  1. data 包全部条目剥掉 var/jb/ 前缀，改为根级旧路径；
  2. control 的 Architecture 改为 iphoneos-arm64e、Depends 追加 oldabi；
  3. member 统一改写为 xz 压缩。

用法：python3 repack_jbroot.py <deb路径> [更多deb路径...]
"""

import io
import lzma
import sys
import tarfile


def parse_ar(buf: bytes):
    members = []
    off = 8
    if buf[:8] != b"!<arch>\n":
        raise ValueError("not an ar archive")
    while off + 60 <= len(buf):
        name = buf[off:off + 16].decode("ascii").strip()
        size = int(buf[off + 48:off + 58].decode("ascii").strip())
        off += 60
        members.append((name, buf[off:off + size]))
        off += size + (size & 1)
    return members


def ar_member(name: str, data: bytes) -> bytes:
    head = (
        name.encode("ascii").ljust(16, b" ")
        + b"0".ljust(12, b" ")
        + b"0".ljust(6, b" ")
        + b"0".ljust(6, b" ")
        + b"100644".ljust(8, b" ")
        + str(len(data)).encode("ascii").ljust(10, b" ")
        + b"`\n"
    )
    out = head + data
    if len(data) & 1:
        out += b"\n"
    return out


def decompress_member(name: str, data: bytes) -> bytes:
    if name.endswith(".xz"):
        return lzma.decompress(data)
    if name.endswith(".gz"):
        import gzip
        return gzip.decompress(data)
    if name.endswith(".lzma"):
        return lzma.decompress(data, format=lzma.FORMAT_ALONE)
    raise ValueError("unsupported member: " + name)


def restrip_tar(raw: bytes) -> bytes:
    """data 包全部条目剥掉 var/jb/ 前缀（rootless 路径 → roothide 旧根路径）。"""
    src = tarfile.open(fileobj=io.BytesIO(raw))
    outbuf = io.BytesIO()
    out = tarfile.open(fileobj=outbuf, mode="w")
    for entry in src:
        name = entry.name
        if name.startswith("./"):
            name = name[2:]
        if name.startswith("var/jb/"):
            name = name[len("var/jb/"):]
        ti = tarfile.TarInfo(name)
        ti.mode = entry.mode
        ti.uid = entry.uid
        ti.gid = entry.gid
        ti.uname = entry.uname
        ti.gname = entry.gname
        ti.mtime = entry.mtime
        if entry.isdir():
            ti.type = tarfile.DIRTYPE
            ti.size = 0
            out.addfile(ti)
        elif entry.isfile():
            ti.type = tarfile.REGTYPE
            ti.size = entry.size
            out.addfile(ti, src.extractfile(entry))
        else:
            ti.type = entry.type
            ti.size = entry.size
            out.addfile(ti, src.extractfile(entry) if entry.isfile() else None)
    out.close()
    src.close()
    return outbuf.getvalue()


def rewrite_control(text: str) -> str:
    lines = []
    for line in text.splitlines():
        if line.startswith("Architecture:"):
            lines.append("Architecture: iphoneos-arm64e")
        elif line.startswith("Depends:"):
            deps = line[len("Depends:"):].strip()
            if "oldabi" not in deps:
                deps = ("mobilesubstrate (>= 0.9.5000), oldabi, " + deps).strip(", ")
            lines.append("Depends: " + deps)
        else:
            lines.append(line)
    return "\n".join(lines) + "\n"


def repack(path: str) -> None:
    with open(path, "rb") as f:
        buf = f.read()
    members = dict(parse_ar(buf))
    debian_binary = members["debian-binary"]
    control_name = next(n for n in members if n.startswith("control.tar"))
    data_name = next(n for n in members if n.startswith("data.tar"))

    control_raw = decompress_member(control_name, members[control_name])
    control_text = None
    src = tarfile.open(fileobj=io.BytesIO(control_raw))
    for entry in src:
        if entry.name.lstrip("./") == "control":
            control_text = src.extractfile(entry).read().decode("utf-8")
    src.close()
    if control_text is None:
        raise ValueError("control member missing")

    new_control = rewrite_control(control_text)
    cbuf = io.BytesIO()
    ct = tarfile.open(fileobj=cbuf, mode="w")
    ti = tarfile.TarInfo("./control")
    ti.size = len(new_control.encode("utf-8"))
    ti.mode = 0o644
    ct.addfile(ti, io.BytesIO(new_control.encode("utf-8")))
    ct.close()
    control_xz = lzma.compress(cbuf.getvalue(), format=lzma.FORMAT_XZ)

    data_raw = decompress_member(data_name, members[data_name])
    restripped = restrip_tar(data_raw)
    data_xz = lzma.compress(restripped, format=lzma.FORMAT_XZ)

    out = b"!<arch>\n"
    out += ar_member("debian-binary", debian_binary)
    out += ar_member("control.tar.xz", control_xz)
    out += ar_member("data.tar.xz", data_xz)
    with open(path, "wb") as f:
        f.write(out)
    print(f"[ok] {path}: {len(buf)}B -> {len(out)}B（roothide 格式：根级路径 + arm64e + oldabi）")


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: repack_jbroot.py <deb> [deb...]")
    for path in sys.argv[1:]:
        repack(path)


if __name__ == "__main__":
    main()
