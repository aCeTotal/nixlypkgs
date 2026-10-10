import json
import mmap
import os
import sys
import xml.etree.ElementTree as ET
from collections import defaultdict

# Foreign platform path components.
EXCLUDED = frozenset({
    "win32", "win64", "win-x64", "win-arm64", "hololens",
    "mac", "osx-x64", "osx-arm64", "ios", "tvos", "visionos",
    "linuxarm64", "linux-arm64",
})
# C# inputs for every platform.
CSHARP_ROOTS = ("Engine/Binaries/DotNET/", "Engine/Binaries/ThirdParty/IOS/")
CSHARP_SOURCES = "/Source/Programs/"
STATE = ".ue5deps"


def wanted(name, prefixes):
    dirs = name.lower().split("/")[:-1]
    csharp = name.startswith(CSHARP_ROOTS) or CSHARP_SOURCES in name
    portable = csharp or EXCLUDED.isdisjoint(dirs)
    return portable and name.startswith(prefixes)


def load(manifest, prefixes):
    root = ET.parse(manifest).getroot()
    prefixes = tuple(prefixes) or ""
    files = {f.get("Name"): f for f in root.iter("File") if wanted(f.get("Name"), prefixes)}
    blobs = {b.get("Hash"): b for b in root.iter("Blob")}
    return root, files, blobs


def packs(manifest, prefixes):
    root, files, blobs = load(manifest, prefixes)
    needed = {blobs[f.get("Hash")].get("PackHash") for f in files.values()}
    json.dump({
        "base": root.get("BaseUrl"),
        "packs": [
            {"hash": p.get("Hash"), "remote": p.get("RemotePath")}
            for p in root.iter("Pack") if p.get("Hash") in needed
        ],
    }, sys.stdout)


def read_state(path):
    try:
        with open(path) as fh:
            return dict(line.rstrip("\n").split("\t", 1)[::-1] for line in fh)
    except FileNotFoundError:
        return {}


def write_blob(path, view, executable):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    try:
        os.unlink(path)
    except FileNotFoundError:
        pass
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o775 if executable else 0o664)
    with os.fdopen(fd, "wb") as fh:
        fh.write(view)


def extract(manifest, pack_dir, dest, prefixes):
    _, files, blobs = load(manifest, prefixes)
    state_path = os.path.join(dest, STATE)
    old = read_state(state_path)

    for name in old.keys() - files.keys():
        try:
            os.unlink(os.path.join(dest, name))
        except FileNotFoundError:
            pass

    by_pack = defaultdict(list)
    for name, f in files.items():
        if old.get(name) == f.get("Hash") and os.path.lexists(os.path.join(dest, name)):
            continue
        blob = blobs[f.get("Hash")]
        by_pack[blob.get("PackHash")].append(
            (int(blob.get("PackOffset")), int(blob.get("Size")), name, f.get("IsExecutable") == "true"))

    for pack, items in by_pack.items():
        with open(os.path.join(pack_dir, pack), "rb") as fh, \
                mmap.mmap(fh.fileno(), 0, access=mmap.ACCESS_READ) as view:
            for offset, size, name, executable in sorted(items):
                write_blob(os.path.join(dest, name), view[offset:offset + size], executable)

    with open(state_path + ".tmp", "w") as fh:
        fh.writelines(f"{f.get('Hash')}\t{name}\n" for name, f in files.items())
    os.replace(state_path + ".tmp", state_path)
    print(f"gitdeps: {sum(map(len, by_pack.values()))} written, {len(files)} tracked", file=sys.stderr)


if __name__ == "__main__":
    if sys.argv[1] == "packs":
        packs(sys.argv[2], sys.argv[3:])
    else:
        extract(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5:])
