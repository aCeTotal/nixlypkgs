#!/usr/bin/env python3
"""Extract image assets from a PyInstaller one-file binary.

Usage: extract_pyinstaller_assets.py <binary> <out_dir>

Pulls every entry whose name lives under `assets/icons/` in the embedded
PyInstaller archive and writes the raw bytes (transparently zlib-decompressed)
to `<out_dir>/<basename>`. Tolerant of truncation: a single bad entry does not
abort the whole extraction.
"""
import os
import struct
import sys
import zlib

COOKIE_MAGIC = b"MEI\x0c\x0b\x0a\x0b\x0e"
COOKIE_LEN = 88  # magic(8) + 4xI + pylib(64)


def parse(data: bytes):
    k = data.rfind(COOKIE_MAGIC)
    if k < 0:
        raise SystemExit("PyInstaller cookie not found")
    _, pkg_len, toc, toc_len, _ = struct.unpack("!8sIIII", data[k:k + 24])
    pkg_start = (k + COOKIE_LEN) - pkg_len
    toc_start = pkg_start + toc
    toc_end = toc_start + toc_len

    p = toc_start
    while p < toc_end:
        (entry_size,) = struct.unpack("!I", data[p:p + 4])
        if entry_size <= 0 or p + entry_size > toc_end:
            break
        entry_pos, csz, usz, cflag, _ctype = struct.unpack("!IIIBB", data[p + 4:p + 18])
        name = data[p + 18:p + entry_size].rstrip(b"\x00").decode("utf-8", "replace")
        yield name, pkg_start + entry_pos, csz, usz, cflag
        p += entry_size


def main() -> int:
    binary, out_dir = sys.argv[1], sys.argv[2]
    os.makedirs(out_dir, exist_ok=True)
    with open(binary, "rb") as f:
        data = f.read()

    extracted = 0
    for name, off, csz, _usz, cflag in parse(data):
        if not name.startswith("assets/icons/"):
            continue
        blob = data[off:off + csz]
        if cflag == 1:
            try:
                blob = zlib.decompress(blob)
            except zlib.error as e:
                print(f"  skip {name}: {e}", file=sys.stderr)
                continue
        dst = os.path.join(out_dir, os.path.basename(name))
        with open(dst, "wb") as g:
            g.write(blob)
        extracted += 1

    if extracted == 0:
        raise SystemExit("no assets/icons/* entries extracted")
    print(f"extracted {extracted} icon(s) to {out_dir}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
