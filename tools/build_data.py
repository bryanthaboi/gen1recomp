#!/usr/bin/env python3
"""Build the port's generated data and graphics from Pokemon Gen-1/2 ROMs.

This thin wrapper extends the upstream builder with the Spanish Red and Blue
ROMs while preserving the newer upstream builder.
"""

import os
import sys

import build_rom_data as builder
from rom_data import CANONICAL_ROJO_SHA1, CANONICAL_AZUL_SHA1

_TOOLS_DIR = os.path.dirname(os.path.abspath(__file__))

# Keep upstream versions and add the Spanish regional variants.
builder.VERSION_MANIFESTS = dict(getattr(builder, "VERSION_MANIFESTS", {}))
builder.VERSION_MANIFESTS.update({
    "rojo": os.path.join(_TOOLS_DIR, "rom_manifest_red_es.json"),
    "azul": os.path.join(_TOOLS_DIR, "rom_manifest_blue_es.json"),
})

builder.VERSION_SHA1 = dict(getattr(builder, "VERSION_SHA1", {}))
builder.VERSION_SHA1.update({
    "rojo": CANONICAL_ROJO_SHA1,
    "azul": CANONICAL_AZUL_SHA1,
})

builder.SHA1_TO_VERSION = {
    sha1: version for version, sha1 in builder.VERSION_SHA1.items()
}

# Spanish ROMs use $BC for the visible é glyph. Keep the normal text charmap
# untouched and override only the font charmap for the Spanish manifests.
_original_load_manifest = builder.load_manifest


def _load_manifest(path):
    manifest = _original_load_manifest(path)
    if os.path.basename(path).lower() in {"rom_manifest_red_es.json", "rom_manifest_blue_es.json"}:
        charmap = manifest.get("fontCharmap")
        if isinstance(charmap, list):
            charmap[:] = [entry for entry in charmap if entry.get("seq") != "é"]
            charmap.append({"code": 0xBC, "seq": "é"})
    return manifest


builder.load_manifest = _load_manifest


def _argv_with_spanish_root_paths(argv=None):
    """Force Spanish Red's generated data/assets to the project root."""
    args = list(sys.argv[1:] if argv is None else argv)
    rom_path = None
    for index, value in enumerate(args):
        if value == "--rom" and index + 1 < len(args):
            rom_path = args[index + 1]
            break
    if rom_path:
        try:
            rom = builder.RomImage(rom_path, None)
        except (OSError, ValueError):
            rom = None
        if rom is not None and rom.sha1 in {CANONICAL_ROJO_SHA1, CANONICAL_AZUL_SHA1}:
            if "--out" not in args:
                args.extend(("--out", "data/generated"))
            if "--assets" not in args:
                args.extend(("--assets", "assets/generated"))
    return args


if __name__ == "__main__":
    raise SystemExit(builder.main(_argv_with_spanish_root_paths()))
