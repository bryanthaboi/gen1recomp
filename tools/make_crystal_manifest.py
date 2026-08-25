#!/usr/bin/env python3
"""Generate tools/rom_manifest_crystal.json from pret/pokecrystal.

Crystal is its own pret tree, but the manifest SHAPE is Gold's: same constant
blocks, same charmap parser, same symbol resolution.  So this drives
make_gold_manifest.generate() over ../pokecrystal instead of forking it, the
way make_yellow_manifest.py drives make_rom_manifest's helpers over
pokeyellow.  Three things are passed in:

  * defines  -- the EMPTY set.  ../pokecrystal/Makefile:129 builds the retail
                international v1.0 object with no -D at all (:130-134 add
                _CRYSTAL11 / _CRYSTAL_AU / _DEBUG / _CRYSTAL11_VC for the four
                other targets).  Leaving Gold's {"_GOLD"} in place would take
                an `IF DEF(_GOLD)` arm that Crystal never assembles.
  * required -- crystal_symbol_deltas.crystal_required(), the Gold symbol set
                with the 25 Gold-only names swapped for their Crystal
                replacements plus crystal_movie_symbols.MOVIE_SYMBOLS.
  * sha1     -- the Crystal cart hash.

`anim_labels` is on: Crystal has per-species pic-animation tables
(../pokecrystal/main.asm:425-448) and Gold has none.

Crystal also declares two extra RGBDS charmaps that Gold has not got at all
(../pokecrystal/constants/charmap.asm:422-442): `unown`, used by the Ruins of
Alph wall words, and `ascii`, used only by the Mobile System GB code.  Neither
is more rows of the main charmap -- the same byte means a different thing in
each -- so make_gold_manifest.charmap deliberately STOPS at the first
`newcharmap`, and that guard has to keep protecting the main table.  The Unown
one is carried here instead, as its own top-level `unownCharmap` key: that is
where `charmap` and `fontCharmap` already live, so a consumer picks the map it
wants by name and no reader of the main table can see these bytes.  The `ascii`
map is not emitted, because nothing outside the Mobile System reads it.

The manifest also carries `symbolRevisions`, a map of ROM sha1 -> symbol name
-> [bank, address] for the retail revisions this port accepts besides the 1.0
hash in `romSha1`.  Crystal has one, v1.1, where `Stadium2N64Attrmap` sits 13
bytes later than on 1.0 because the Stadium 2 tilemap in front of it is longer
(../pokecrystal/mobile/mobile_5c.asm:869).  `crystal11_symbol_revisions` diffs
the v1.1 symbol table against the resolved 1.0 `symbols` and keeps only the
names that appear in both and moved.

Usage: python3 tools/make_crystal_manifest.py
Default paths: pokecrystal at ../pokecrystal (relative to the repo) or
/Users/bryanbassett/Documents/development/pokecrystal; symbols at
/Users/bryanbassett/Documents/development/pokecrystal-symbols/pokecrystal.sym
and /Users/bryanbassett/Documents/development/pokecrystal-symbols/pokecrystal11.sym.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import make_gold_manifest as gold  # noqa: E402
from crystal_symbol_deltas import crystal_required  # noqa: E402
from rom_data import (  # noqa: E402
    CANONICAL_CRYSTAL_SHA1, CANONICAL_CRYSTAL11_SHA1, SymbolTable,
)

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEV = "/Users/bryanbassett/Documents/development"
DEFAULT_POKECRYSTAL_CANDIDATES = [
    os.path.join(os.path.dirname(REPO_ROOT), "pokecrystal"),
    os.path.join(DEV, "pokecrystal"),
]
DEFAULT_SYMBOLS = os.path.join(DEV, "pokecrystal-symbols/pokecrystal.sym")
DEFAULT_SYMBOLS11 = os.path.join(
    DEV, "pokecrystal-symbols/pokecrystal11.sym")
DEFAULT_OUT = os.path.join(
    os.path.dirname(__file__), "rom_manifest_crystal.json")

# ../pokecrystal/Makefile:129
CRYSTAL_ASM_DEFINES = frozenset()

CRYSTAL_REQUIRED_SYMBOLS = crystal_required(gold.REQUIRED_SYMBOLS)


def _rgbds_int(expr, i):
    """Evaluate one `charmap` value expression for loop counter `i`.

    RGBDS `$xx` is hex and `/` is integer division; nothing else in the block
    needs modelling.  The whitelist is what keeps this from being eval() on
    arbitrary asm.
    """
    text = re.sub(r"\$([0-9a-fA-F]+)", lambda m: str(int(m.group(1), 16)), expr)
    text = text.replace("/", "//")
    if not re.fullmatch(r"[0-9i()+\-*/ ]+", text):
        raise ValueError(f"unsupported charmap expression: {expr}")
    return int(eval(text, {"__builtins__": {}}, {"i": i}))  # noqa: S307


def unown_charmap(pokecrystal, defines=None):
    """The `unown` charmap: byte -> letter, same shape as gold.charmap.

    ../pokecrystal/constants/charmap.asm:422-431 is a `pushc` block that names
    the map, DEFs a string of every printable character, and emits one
    `charmap STRSLICE(...)` per character inside a `for`.  So the parse has to
    follow the loop rather than read literal rows -- but it still reads the
    letter set and the tile arithmetic out of the asm, not out of a copy here.
    """
    path = os.path.join(pokecrystal, "constants", "charmap.asm")
    out, strings, inside, loop = {}, {}, False, None
    for _, line in gold.read_asm(path, defines):
        s = line.strip()
        if re.match(r"newcharmap\s+unown\b", s):
            inside = True
            continue
        if not inside:
            continue
        if re.match(r"(popc|newcharmap)\b", s):
            break
        m = re.match(r'DEF\s+(\w+)\s+EQUS\s+"(.*)"$', s)
        if m:
            strings[m.group(1)] = m.group(2)
            continue
        m = re.match(r"for\s+(\w+),\s*STRLEN\(#(\w+)\)\s*$", s)
        if m:
            loop = (m.group(1), strings[m.group(2)])
            continue
        if re.match(r"endr\s*$", s):
            loop = None
            continue
        m = re.match(
            r"charmap\s+STRSLICE\(#(\w+),\s*\w+,\s*\w+\s*\+\s*1\),\s*(.+)$", s)
        if m and loop:
            for index, char in enumerate(strings[m.group(1)]):
                out[str(_rgbds_int(m.group(2), index))] = char
            continue
        m = re.match(r'charmap\s+"(.*)",\s*(\$[0-9a-fA-F]+)$', s)
        if m:
            out[str(int(m.group(2)[1:], 16))] = m.group(1)
    if not out:
        raise SystemExit("charmap.asm has no `unown` charmap")
    return out


def crystal11_symbol_revisions(symbols11_path, base_symbols):
    """Diff the v1.1 symbol table against the manifest's resolved 1.0 symbols.

    Returns only the entries whose [bank, address] differs, restricted to
    names the 1.0 manifest actually carries -- a v1.1-only symbol with no
    1.0 counterpart is nothing an extractor built against `symbols` could
    ever look up, so it is not this table's business to report.
    """
    if not os.path.isfile(symbols11_path):
        raise SystemExit(
            f"Crystal v1.1 symbol file not found: {symbols11_path} "
            "(pass --symbols11 or install it at the default path)")
    symbols11 = SymbolTable(symbols11_path)
    revisions = {}
    for name, location in base_symbols.items():
        symbol11 = symbols11.by_name.get(name)
        if symbol11 is None:
            continue
        location11 = [symbol11.bank, symbol11.address]
        if location11 != location:
            revisions[name] = location11
    return revisions


def generate(pokecrystal, symbols_path, symbols11_path=DEFAULT_SYMBOLS11):
    data = gold.generate(
        pokecrystal, symbols_path,
        defines=CRYSTAL_ASM_DEFINES,
        required=CRYSTAL_REQUIRED_SYMBOLS,
        sha1=CANONICAL_CRYSTAL_SHA1,
        anim_labels=True)
    # Crystal renumbers the block: 162 flags to Gold's 93, so a consumer that
    # hardcodes Gold's indices reads the wrong flag.
    data["constants"]["engineFlagOrder"] = gold.parse_const_block(
        os.path.join(pokecrystal, "constants", "engine_flags.asm"),
        defines=CRYSTAL_ASM_DEFINES)
    data["unownCharmap"] = unown_charmap(pokecrystal, CRYSTAL_ASM_DEFINES)
    data["symbolRevisions"] = {
        CANONICAL_CRYSTAL11_SHA1: crystal11_symbol_revisions(
            symbols11_path, data["symbols"]),
    }
    return data


def find_pokecrystal():
    for candidate in DEFAULT_POKECRYSTAL_CANDIDATES:
        if os.path.isfile(os.path.join(candidate, "main.asm")):
            return candidate
    return DEFAULT_POKECRYSTAL_CANDIDATES[-1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pokecrystal", default=find_pokecrystal())
    parser.add_argument("--symbols", default=DEFAULT_SYMBOLS)
    parser.add_argument("--symbols11", default=DEFAULT_SYMBOLS11)
    parser.add_argument("--out", default=DEFAULT_OUT)
    args = parser.parse_args()

    pokecrystal = os.path.abspath(args.pokecrystal)
    if not os.path.isfile(os.path.join(pokecrystal, "main.asm")):
        raise SystemExit(f"{pokecrystal} is not a pokecrystal checkout")
    data = generate(
        pokecrystal, os.path.abspath(args.symbols),
        os.path.abspath(args.symbols11))
    with open(args.out, "w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, ensure_ascii=False, indent=2, sort_keys=True)
        f.write("\n")
    print(f"wrote {args.out}")


if __name__ == "__main__":
    main()
