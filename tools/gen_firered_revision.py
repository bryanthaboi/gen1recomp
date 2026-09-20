"""Usage: tools/gen_firered_revision.py ../pokefirered (after make compare_firered compare_firered_rev1)."""

from __future__ import annotations

import base64
import bisect
import hashlib
import struct
import subprocess
import sys
from pathlib import Path

ROM_BASE = 0x08000000
ROM_END = 0x09000000
OUT = Path(__file__).resolve().parent.parent / "src/import/gba/revisions/firered_1_1.lua"
REV1_ONLY = {"GFScene_CreatePresentsSprite"}


def symbols(elf: Path) -> list[tuple[int, str]]:
    out = subprocess.run(
        ["arm-none-eabi-nm", "-n", str(elf)], capture_output=True, text=True, check=True
    ).stdout
    rows = []
    for line in out.splitlines():
        parts = line.split()
        if len(parts) != 3 or parts[2][0] in "$.":
            continue
        addr = int(parts[0], 16)
        if ROM_BASE <= addr < ROM_END:
            rows.append((addr - ROM_BASE, parts[2]))
    return rows


def segments(base: Path, rev: Path) -> list[tuple[int, int]]:
    a = symbols(base)
    b = [row for row in symbols(rev) if row[1] not in REV1_ONLY]
    if [n for _, n in a] != [n for _, n in b]:
        raise SystemExit("symbol order differs between builds")
    segs: list[tuple[int, int]] = []
    for (x, _), (y, _) in zip(a, b):
        if not segs or segs[-1][1] != y - x:
            segs.append((x, y - x))
    return segs


def varint(n: int) -> bytes:
    out = bytearray()
    while n >= 0x80:
        out.append((n & 0x7F) | 0x80)
        n >>= 7
    out.append(n)
    return bytes(out)


def main() -> None:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else "../pokefirered")
    a = (root / "pokefirered.gba").read_bytes()
    b = (root / "pokefirered_rev1.gba").read_bytes()
    segs = segments(root / "pokefirered.elf", root / "pokefirered_rev1.elf")
    starts = [s for s, _ in segs]

    def fwd(off: int) -> int:
        return off + segs[bisect.bisect_right(starts, off) - 1][1]

    size = len(a)
    view = bytearray(size)
    for i, (start, delta) in enumerate(segs):
        end = segs[i + 1][0] if i + 1 < len(segs) else size
        view[start:end] = b[start + delta:end + delta]

    sites = []
    off = 0
    while off < size - 3:
        if a[off] == view[off]:
            off += 1
            continue
        for s in range(max(0, off - 3), off + 1):
            w = struct.unpack_from("<I", a, s)[0]
            if ROM_BASE <= w < ROM_END and struct.unpack_from("<I", view, s)[0] == fwd(w - ROM_BASE) + ROM_BASE:
                sites.append(s)
                off = s + 4
                break
        else:
            off += 1

    for s in sites:
        view[s:s + 4] = a[s:s + 4]
    residual = sum(1 for x, y in zip(a, view) if x != y)

    blob = bytearray()
    prev = 0
    for s in sites:
        blob += varint(s - prev)
        prev = s
    text = base64.b64encode(bytes(blob)).decode()

    lines = [
        "return {",
        '  base = "%s",' % hashlib.sha1(a).hexdigest(),
        '  sha1 = "%s",' % hashlib.sha1(b).hexdigest(),
        "  segments = {",
    ]
    lines += ["    { 0x%06X, %d }," % seg for seg in segs]
    lines += ["  },", "  siteCount = %d," % len(sites), "  sites = table.concat({"]
    lines += ['    "%s",' % text[i:i + 100] for i in range(0, len(text), 100)]
    lines += ["  }),", "}", ""]
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(lines))
    print("segments %d, sites %d, residual bytes %d, wrote %s" % (len(segs), len(sites), residual, OUT))


if __name__ == "__main__":
    main()
