#!/usr/bin/env python3
"""Compare two Game Boy ROMs bank by bank, and say where they disagree.

Written for the problem of bringing a localised Gen 1 release into a
disassembly.  The European Pokemon releases are rebuilds of their US
counterparts: most banks are byte-identical, the text banks are wholly
different, and a handful of code banks are the US code with shifted
pointers.  Knowing WHICH is which is the first thing you need and the
last thing anyone writes down.

The loop this is built for:

    1. build the disassembly
    2. diff the build against the retail ROM
    3. fix the banks that disagree
    4. go to 1, until nothing disagrees

Step 2 is this script.  With a .sym file it also names the symbols that
live inside each differing region, which turns "bank 0x1C differs at
0x4A31" into "bank 0x1C differs, starting inside TextPredef".

Usage:

    gbromdiff.py A.gb B.gb                      bank-by-bank summary
    gbromdiff.py A.gb B.gb --regions            contiguous differing runs
    gbromdiff.py A.gb B.gb --sym pokeyellow.sym name the symbols involved
    gbromdiff.py A.gb B.gb --json               machine-readable

Exit status is 0 when the ROMs are identical, 1 when they differ, 2 on a
usage error -- so it can drive a build loop directly.
"""

import argparse
import json
import os
import sys

BANK_SIZE = 0x4000


def load(path):
    with open(path, "rb") as fh:
        return fh.read()


def header(rom):
    """Title, CGB flag and global checksum, straight out of the cartridge
    header.  Useful for saying WHICH releases are being compared without
    the caller having to know the hashes."""
    if len(rom) < 0x150:
        return {}
    title = rom[0x134:0x143].split(b"\x00")[0]
    try:
        title = title.decode("ascii", "replace").strip()
    except Exception:
        title = repr(title)
    return {
        "title": title,
        "cgb": rom[0x143],
        "rom_size_code": rom[0x148],
        "global_checksum": (rom[0x14E] << 8) | rom[0x14F],
    }


def banks(rom):
    return (len(rom) + BANK_SIZE - 1) // BANK_SIZE


def bank_report(a, b):
    """Per-bank identical / differs / missing, with a byte count."""
    out = []
    for i in range(max(banks(a), banks(b))):
        lo, hi = i * BANK_SIZE, (i + 1) * BANK_SIZE
        ba, bb = a[lo:hi], b[lo:hi]
        if not ba or not bb:
            out.append({"bank": i, "state": "missing",
                        "in_a": bool(ba), "in_b": bool(bb)})
            continue
        if ba == bb:
            out.append({"bank": i, "state": "identical", "differing": 0})
            continue
        n = sum(1 for x, y in zip(ba, bb) if x != y)
        # A bank that differs in nearly every byte is a different payload
        # (translated text); one that differs in a scatter of bytes is the
        # same code with pointers moved.  That distinction is the whole
        # reason to look at a percentage rather than a boolean.
        pct = 100.0 * n / min(len(ba), len(bb))
        out.append({"bank": i, "state": "differs", "differing": n,
                    "percent": round(pct, 2),
                    "shape": "replaced" if pct > 60 else
                             ("patched" if pct < 5 else "mixed")})
    return out


def regions(a, b, gap=16):
    """Contiguous runs of differing bytes, merging runs separated by fewer
    than `gap` matching bytes -- otherwise a shifted pointer table reads as
    hundreds of one-byte findings instead of one region."""
    out = []
    n = min(len(a), len(b))
    start = None
    last = None
    for i in range(n):
        if a[i] != b[i]:
            if start is None:
                start = i
            elif last is not None and i - last > gap:
                out.append((start, last))
                start = i
            last = i
    if start is not None:
        out.append((start, last))
    if len(a) != len(b):
        out.append((n, max(len(a), len(b)) - 1))
    return out


def load_symbols(path):
    """An rgbds .sym file: `BB:AAAA Name` per line.  Returned as a list of
    (absolute_offset, bank, addr, name), sorted, so a region can be mapped
    to whatever symbol most recently preceded it."""
    syms = []
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.split(";")[0].strip()
            if not line or ":" not in line:
                continue
            try:
                where, name = line.split(None, 1)
                bank_s, addr_s = where.split(":")
                bank, addr = int(bank_s, 16), int(addr_s, 16)
            except ValueError:
                continue
            # bank 0 is 0000-3FFF; every other bank is paged in at 4000
            offset = addr if bank == 0 else bank * BANK_SIZE + (addr - 0x4000)
            syms.append((offset, bank, addr, name.strip()))
    syms.sort()
    return syms


def symbol_before(syms, offset):
    """The last symbol at or before `offset` -- i.e. the thing this byte is
    most likely part of.  Binary search over the sorted table."""
    lo, hi = 0, len(syms) - 1
    best = None
    while lo <= hi:
        mid = (lo + hi) // 2
        if syms[mid][0] <= offset:
            best = syms[mid]
            lo = mid + 1
        else:
            hi = mid - 1
    return best


def main():
    ap = argparse.ArgumentParser(
        description="Compare two Game Boy ROMs bank by bank.")
    ap.add_argument("rom_a")
    ap.add_argument("rom_b")
    ap.add_argument("--regions", action="store_true",
                    help="list contiguous differing runs, not just banks")
    ap.add_argument("--sym", help="rgbds .sym file, to name the symbols "
                                  "each differing region falls inside")
    ap.add_argument("--gap", type=int, default=16,
                    help="matching bytes tolerated inside one region "
                         "(default 16)")
    ap.add_argument("--limit", type=int, default=40,
                    help="max regions to print (default 40)")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    for p in (args.rom_a, args.rom_b):
        if not os.path.isfile(p):
            print(f"error: no such file: {p}", file=sys.stderr)
            return 2

    a, b = load(args.rom_a), load(args.rom_b)
    rep = bank_report(a, b)
    same = [r for r in rep if r["state"] == "identical"]
    diff = [r for r in rep if r["state"] == "differs"]

    result = {
        "a": {"path": args.rom_a, "bytes": len(a), **header(a)},
        "b": {"path": args.rom_b, "bytes": len(b), **header(b)},
        "banks_total": len(rep),
        "banks_identical": len(same),
        "banks_differing": len(diff),
        "banks": rep,
    }

    if args.regions or args.sym:
        regs = regions(a, b, args.gap)
        syms = load_symbols(args.sym) if args.sym else None
        listed = []
        for start, end in regs[: args.limit]:
            item = {"start": start, "end": end, "length": end - start + 1,
                    "bank": start // BANK_SIZE}
            if syms:
                s = symbol_before(syms, start)
                if s:
                    item["symbol"] = s[3]
                    item["symbol_offset"] = start - s[0]
            listed.append(item)
        result["regions_total"] = len(regs)
        result["regions"] = listed

    if args.json:
        print(json.dumps(result, indent=2))
        return 0 if not diff and len(a) == len(b) else 1

    ha, hb = result["a"], result["b"]
    print(f"A  {ha.get('title','?'):<16} {len(a):>8} bytes  {args.rom_a}")
    print(f"B  {hb.get('title','?'):<16} {len(b):>8} bytes  {args.rom_b}")
    print()
    if not diff and len(a) == len(b):
        print(f"IDENTICAL — all {len(rep)} banks match")
        return 0

    print(f"{len(same)}/{len(rep)} banks identical, {len(diff)} differ")
    print()
    print("  bank   differing bytes            shape")
    for r in diff:
        if r["state"] != "differs":
            continue
        print(f"  0x{r['bank']:02X}   {r['differing']:>6} "
              f"({r['percent']:>5.1f}%)   {r['shape']}")
    print()
    print("  replaced = a different payload (translated text)")
    print("  patched  = the same code with a few values moved")

    if "regions" in result:
        print()
        print(f"{result['regions_total']} differing regions "
              f"(showing {len(result['regions'])}):")
        for item in result["regions"]:
            line = (f"  0x{item['start']:06X}-0x{item['end']:06X}  "
                    f"bank 0x{item['bank']:02X}  {item['length']:>6} bytes")
            if "symbol" in item:
                line += f"  {item['symbol']}+0x{item['symbol_offset']:X}"
            print(line)
    return 1


if __name__ == "__main__":
    sys.exit(main())
