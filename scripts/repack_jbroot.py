#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
repack_jbroot.py — 重打 deb：把 data 包里 var/jb/private/... 条目的 var/jb 前缀剥掉。

背景：目标设备为 roothide 越狱。两类路径行为差异：
  - var/jb/Library/...（模块 bundle / hook dylib）：设备 dpkg 解压正常；
  - var/jb/usr/lib/TweakInject/...：dpkg 解压失败（roothide 路径转换剥掉
    /var/jb 前缀后落盘 ENOENT）。
roothide 的 TweakLoader 只扫描 <jbroot>/usr/lib/TweakInject/，而该 jbroot 的
物理路径为 /private/var/containers/Bundle/Application/.jbroot-<UUID>/（数据分区，
可写）。Makefile 的 after-all 已把 dylib/plist 复制进 layout/private/var/...，
rootless scheme 会统一加 var/jb 前缀，因此本脚本把 var/jb/private/... 条目剥成
private/...，直达 jbroot 物理路径。输出 member 统一改写为 xz 压缩。

用法：python3 repack_jbroot.py <deb路径> [更多deb路径...]
"""

import io
import lzma
import sys
import tarfile

JBROOT_STRIP_PREFIX = "var/jb/private/"


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


def decompress_data(name: str, data: bytes) -> bytes:
    if name.endswith(".xz"):
        return lzma.decompress(data)
    if name.endswith(".gz"):
        import gzip
        return gzip.decompress(data)
    if name.endswith(".lzma"):
        return lzma.decompress(data, format=lzma.FORMAT_ALONE)
    raise ValueError("unsupported data member: " + name)


def restrip_tar(raw: bytes) -> bytes:
    src = tarfile.open(fileobj=io.BytesIO(raw))
    outbuf = io.BytesIO()
    out = tarfile.open(fileobj=outbuf, mode="w")
    for entry in src:
        name = entry.name
        if name.startswith("./"):
            name = name[2:]
        if name.startswith(JBROOT_STRIP_PREFIX):
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


def repack(path: str) -> None:
    with open(path, "rb") as f:
        buf = f.read()
    members = parse_ar(buf)
    debian_binary = dict(members)["debian-binary"]
    control = dict(members)[next(n for n, _ in members if n.startswith("control.tar"))]
    data_name, data = next((n, d) for n, d in members if n.startswith("data.tar"))

    raw = decompress_data(data_name, data)
    restripped = restrip_tar(raw)
    data_xz = lzma.compress(restripped, format=lzma.FORMAT_XZ)

    out = b"!<arch>\n"
    out += ar_member("debian-binary", debian_binary)
    out += ar_member("control.tar.gz", control) if b"\x1f\x8b" in control[:2] else ar_member("control.tar.xz", control)
    out += ar_member("data.tar.xz", data_xz)

    with open(path, "wb") as f:
        f.write(out)
    print(f"[ok] {path}: {len(buf)}B -> {len(out)}B（data 条目 var/jb/private/ 前缀已剥除）")


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: repack_jbroot.py <deb> [deb...]")
    for path in sys.argv[1:]:
        repack(path)


if __name__ == "__main__":
    main()
