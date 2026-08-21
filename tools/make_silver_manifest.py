#!/usr/bin/env python3
"""Derive the Pokemon Silver import manifest from the shipped Gold manifest.

Gold and Silver are assembled from one pokegold source tree; every constant
block, charmap entry, map id, and symbol NAME is identical between the two
builds, and the edition differences (wild encounter tables, the alternate
front pics in gfx/pics_silver.asm, the title screen art, preset player
names, a handful of map texts) are all ROM data that the importer decodes
from the Silver cart at import time.  So rather than re-parsing pokegold
from scratch like tools/make_gold_manifest.py does, this takes the shipped
Gold manifest verbatim and overrides only what genuinely differs:

  * romSha1  -- Silver's ROM hash (pret/pokegold's byte-exact build).
  * symbols  -- every symbol re-resolved from pokesilver.sym, because the
                edition-selected data blocks have different sizes and shift
                their neighbours (e.g. the compressed front pics).

Usage: python3 tools/make_silver_manifest.py
Default paths: Gold manifest beside this script; symbols at
/Users/bryanbassett/Documents/development/pokegold-symbols/pokesilver.sym
(a pokegold checkout's own `make silver` build emits an identical one).
"""

from __future__ import annotations

import argparse
import copy
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from rom_data import CANONICAL_SILVER_SHA1, SymbolTable  # noqa: E402

DEV = "/Users/bryanbassett/Documents/development"
DEFAULT_GOLD = os.path.join(os.path.dirname(__file__), "rom_manifest_gold.json")
DEFAULT_OUT = os.path.join(
    os.path.dirname(__file__), "rom_manifest_silver.json")
DEFAULT_SYMBOLS = os.path.join(DEV, "pokegold-symbols/pokesilver.sym")


def derive(gold, symbols_path):
    """Return the Silver manifest derived from the Gold manifest dict."""
    silver = copy.deepcopy(gold)
    silver["romSha1"] = CANONICAL_SILVER_SHA1

    silver_symbols = SymbolTable(symbols_path)
    resolved, missing = {}, []
    for name in gold["symbols"]:
        symbol = silver_symbols.by_name.get(name)
        if symbol is None:
            missing.append(name)
            continue
        resolved[name] = [symbol.bank, symbol.address]
    if missing:
        raise SystemExit(
            "pokesilver.sym is missing symbols the manifest needs: "
            + ", ".join(sorted(missing)[:10])
            + (" ..." if len(missing) > 10 else ""))
    silver["symbols"] = resolved

    # Sanity: the edition pic banks must actually have moved something.  If
    # every address matches Gold's, the --symbols file is almost certainly
    # pokegold.sym, and the import would decode Gold data out of a Silver ROM.
    if all(resolved[n] == gold["symbols"][n] for n in resolved):
        raise SystemExit(
            f"{symbols_path} resolves every symbol to Gold's address; "
            "is it really pokesilver.sym?")

    return silver


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--gold", default=DEFAULT_GOLD,
                        help="shipped Gold manifest to derive from")
    parser.add_argument("--symbols", default=DEFAULT_SYMBOLS,
                        help="pokesilver.sym symbol file")
    parser.add_argument("--out", default=DEFAULT_OUT)
    args = parser.parse_args()

    with open(args.gold, encoding="utf-8") as f:
        gold = json.load(f)

    silver = derive(gold, os.path.abspath(args.symbols))
    with open(args.out, "w", encoding="utf-8", newline="\n") as f:
        json.dump(silver, f, ensure_ascii=False, indent=2, sort_keys=True)
        f.write("\n")
    print(f"wrote {args.out}")


if __name__ == "__main__":
    main()
