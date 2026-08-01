#!/usr/bin/env python3
"""Derive the EUR (Spain) import manifests from the shipped US manifests.

The Spanish releases -- "Pokemon - Edicion Roja/Azul (Spain) (SGB Enhanced)"
-- are rebuilds of the US ROMs from the same source tree with translated
strings.  Every data bank (stats, pics, audio, tilesets) keeps its US layout;
the far-text banks and any bank that carries translated bytes are re-laid-out,
so their symbol addresses move.  einstein95/pokered-es is a shift-matching
disassembly of both Spanish ROMs (its builds are byte-identical to the
retail dumps), which gives us exactly what make_blue_manifest.py gets from
pokeblue.sym: the same pret symbol names at the Spanish addresses.

Like make_blue_manifest.py, we start from the shipped US manifest -- NOT a
fresh make_rom_manifest.py run -- so the derived manifest cannot drift from
the one the runtime is actually tested against.  Only the language-dependent
pieces are overridden:

  * romSha1        -- the Spanish ROM hash.
  * symbols        -- every referenced symbol re-resolved from the Spanish
                      .sym (text banks moved wholesale; TypeEffects and other
                      code-bank tables shift a few bytes).
  * audio          -- music/SFX/cry header addresses re-resolved the same way
                      (they live inline in the audio block, not in symbols).
  * charmap / fontCharmap -- the Spanish character set assigns codepoints to
                      accented glyphs (e mapped at $BC, a at $CF, n-tilde at
                      $D2, inverted punctuation at $E4/$E5, ...).
  * text.dynamic / pointers / trainerHeaders -- re-parsed from the Spanish
                      tree; translations reorder a couple of text_ram/
                      text_decimal substitutions (_ExpPointsText).
  * field.presetNames / credits / trades / townMap / title -- translated
                      preset names (ROJO/ASH/JAIME), the EDICION ROJA
                      credits reel, the renamed in-game trade nicknames,
                      localized town-map location names, and the title
                      ribbon metrics (the EDICION ROJA graphic is a
                      different size than RED VERSION).

Everything else -- maps, trainer parties, tileset dimensions, battle
animations, sprite metadata -- is byte-for-byte the US game and is inherited
unchanged.  text.labels is also inherited: the Spanish tree parses a few
extra labels the runtime never reads, and keeping the US list means the
extracted cache carries exactly the keys the engine expects.
"""

from __future__ import annotations

import argparse
import copy
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from extract import font, pokemon, util  # noqa: E402
import make_rom_manifest  # noqa: E402
from rom_data import (CANONICAL_BLUE_ES_SHA1, CANONICAL_RED_ES_SHA1,  # noqa: E402
                      SymbolTable)

HERE = os.path.dirname(os.path.abspath(__file__))

VERSIONS = {
    "red": {
        "base": os.path.join(HERE, "rom_manifest.json"),
        "out": os.path.join(HERE, "rom_manifest_red_es.json"),
        "sha1": CANONICAL_RED_ES_SHA1,
        "sym": "pokered.sym",
        "define": "_RED",
        "playerPreset": "ROJO",
        "creditsBanner": "EDICIÓN ROJA",
    },
    "blue": {
        "base": os.path.join(HERE, "rom_manifest_blue.json"),
        "out": os.path.join(HERE, "rom_manifest_blue_es.json"),
        "sha1": CANONICAL_BLUE_ES_SHA1,
        "sym": "pokeblue.sym",
        "define": "_BLUE",
        "playerPreset": "AZUL",
        "creditsBanner": "EDICIÓN AZUL",
    },
}


# field keys whose content is language-dependent: preset names
# (ROJO/ASH/JAIME), the credits reel (EDICION ROJA banner, translator
# screens, the localized THE END art), the renamed in-game trade nicknames,
# the town-map location names, and the title-screen ribbon (the EDICION
# ROJA/AZUL graphic is a different size than RED/BLUE VERSION).  Everything
# else in field is hand-authored wiring inherited from the US manifest.
FIELD_OVERRIDES = ("presetNames", "credits", "trades", "townMap", "title")


def derive(base, pokered_es, symbols_path, spec):
    manifest = copy.deepcopy(base)
    manifest["romSha1"] = spec["sha1"]

    # European localizations store Pokedex height/weight in metric: one byte
    # of decimeters plus a word of hectograms, one byte shorter than the US
    # feet/inches/tenths-of-a-pound layout.  The dex screen captions ("AL"
    # and "PE" in Spanish) come from the tree's own HeightWeightText.
    manifest["dexUnits"] = "metric"
    manifest["dexUnitLabels"] = pokemon.parse_dex_unit_labels(pokered_es)
    if not manifest["dexUnitLabels"]:
        raise SystemExit("could not parse the metric dex screen captions")

    # Every symbol the US manifest references, re-resolved at its Spanish
    # address.  The name set is identical (the disassembly follows pret
    # naming), so a missing name means the checkout is wrong -- fail loudly.
    symbols = SymbolTable(symbols_path)
    resolved, missing = {}, []
    for name in base["symbols"]:
        symbol = symbols.by_name.get(name)
        if symbol is None:
            missing.append(name)
            continue
        resolved[name] = [symbol.bank, symbol.address]
    if missing:
        raise SystemExit(
            f"{os.path.basename(symbols_path)} is missing symbols the "
            "manifest needs: " + ", ".join(sorted(missing)[:10])
            + (" ..." if len(missing) > 10 else ""))
    manifest["symbols"] = resolved

    # Audio header addresses live inline in the audio block; re-derive the
    # whole block from the Spanish tree + .sym, keeping the US block as a
    # structural cross-check (same header names, same engines).
    audio = make_rom_manifest.audio_metadata(
        pokered_es, symbols, base["constants"]["mapOrder"])
    for key in ("musicHeaders", "sfxHeaders", "cryHeaders", "noiseHeaders"):
        if set(audio[key]) != set(base["audio"][key]):
            raise SystemExit(f"audio.{key} names differ from the US manifest")
    if audio["mapSongs"] != base["audio"]["mapSongs"]:
        raise SystemExit("audio.mapSongs differ from the US manifest")
    manifest["audio"] = audio
    manifest["sfxKeys"] = make_rom_manifest.sfx_keys(pokered_es, symbols)

    # The Spanish character set: accented vowels, n-tilde and inverted
    # punctuation replace codepoints the US charmap spends elsewhere.
    manifest["charmap"] = make_rom_manifest.charmap(pokered_es)
    manifest["fontCharmap"] = font.parse_charmap(pokered_es)

    # Text metadata: keep the US label list (exactly the keys the runtime
    # reads), but take dynamic-substitution commands, script text pointers
    # and trainer headers from the Spanish tree -- translation reorders a
    # couple of substitutions.
    texts = make_rom_manifest.text_metadata(pokered_es)
    es_labels = set(texts["labels"])
    missing_labels = [n for n in base["text"]["labels"] if n not in es_labels]
    if missing_labels:
        raise SystemExit(
            "Spanish tree is missing text labels: "
            + ", ".join(missing_labels[:10]))
    manifest["text"] = {
        "labels": base["text"]["labels"],
        "dynamic": {
            label: commands
            for label, commands in texts["dynamic"].items()
            if label in set(base["text"]["labels"])
        },
        "pointers": texts["pointers"],
        "trainerHeaders": texts["trainerHeaders"],
    }

    # Version- and language-gated field bits (same pattern as
    # make_blue_manifest.py, but a wider override set -- see FIELD_OVERRIDES).
    # field_metadata runs the full field extraction against the Spanish tree
    # so composite blocks (credits + THE END art, town map + background)
    # arrive assembled exactly as make_rom_manifest would build them.
    saved = util.ASM_DEFINES
    util.ASM_DEFINES = {spec["define"]}
    try:
        es_field = make_rom_manifest.field_metadata(pokered_es)
    finally:
        util.ASM_DEFINES = saved
    for key in FIELD_OVERRIDES:
        manifest["field"][key] = es_field[key]
    presets = manifest["field"]["presetNames"]

    # Sanity: the presets must be the Spanish set for this version, and the
    # credits banner must name the Spanish edition.  A silent US-through
    # here would be a hard-to-spot bug.
    if spec["playerPreset"] not in presets["player"]:
        raise SystemExit(
            f"preset-name parse did not yield {spec['playerPreset']}")
    banner = manifest["field"]["credits"]["screens"][0]["lines"][1]["text"]
    if banner != spec["creditsBanner"]:
        raise SystemExit(
            f"credits banner is {banner!r}, expected {spec['creditsBanner']!r}")
    if "ñ" not in manifest["charmap"].values():
        raise SystemExit("Spanish charmap is missing accented characters")

    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pokered-es", required=True,
                        help="einstein95/pokered-es checkout, built so "
                             "pokered.sym / pokeblue.sym exist")
    parser.add_argument("--versions", nargs="+", default=["red", "blue"],
                        choices=sorted(VERSIONS))
    args = parser.parse_args()

    pokered_es = os.path.abspath(args.pokered_es)
    if not os.path.isfile(os.path.join(pokered_es, "main.asm")):
        raise SystemExit(f"{pokered_es} is not a pokered-es checkout")

    for version in args.versions:
        spec = VERSIONS[version]
        with open(spec["base"], encoding="utf-8") as f:
            base = json.load(f)
        symbols_path = os.path.join(pokered_es, spec["sym"])
        if not os.path.isfile(symbols_path):
            raise SystemExit(
                f"{symbols_path} is missing; build pokered-es first "
                "(make red blue)")
        manifest = derive(base, pokered_es, symbols_path, spec)
        with open(spec["out"], "w", encoding="utf-8", newline="\n") as f:
            json.dump(manifest, f, ensure_ascii=False, indent=2,
                      sort_keys=True)
            f.write("\n")
        print(f"wrote {spec['out']}")


if __name__ == "__main__":
    main()
