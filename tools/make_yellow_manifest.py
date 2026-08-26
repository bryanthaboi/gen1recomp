#!/usr/bin/env python3
"""Derive the Pokemon Yellow import manifest from the shipped Red manifest.

Yellow is a separate pret tree (pokeyellow), not a `_YELLOW` flip of pokered.
Most of the ~3268 Red manifest symbols still exist under the same names in
pokeyellow.sym (~3123 with shifted addresses).  The remainder need aliases,
synthetic addresses (Mew in BaseStats), or omission (FightIntro* -- Yellow's
intro movie is different; RomExtractor must skip those).

Map/object/sprite/tileset/text metadata diverge enough that those sections are
rebuilt from pokeyellow source (same helpers as make_rom_manifest.py), while
ROM-address tables and other Red-shaped sections keep the derive-and-remap
path.

Usage mirrors make_blue_manifest.py: deep-copy Red, remap symbols, override
version-gated field bits, write tools/rom_manifest_yellow.json.
"""

from __future__ import annotations

import argparse
import copy
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from extract import constants, field, util  # noqa: E402
from make_rom_manifest import (  # noqa: E402
    _music_label,
    check_pokered_revision,
    map_metadata,
    simple_constants,
    sprite_metadata,
    text_metadata,
    tileset_metadata,
)
import re  # noqa: E402

# See make_rom_manifest.py's POKERED_REVISION comment for why this pin
# matters -- pokeyellow can drift the same way pokered did for the Silph Co
# 10F/11F rename. Verified against this commit: symbols/text/trainerHeaders/
# trainerPartyOverrides all come out byte-for-byte identical to the
# committed rom_manifest_yellow.json (field.oldManBattle does not -- a
# separate, pre-existing, undiagnosed discrepancy unrelated to text labels,
# left alone the same way field.seafoam/tradeArt were for Red/Blue).
POKEYELLOW_REVISION = "e6ba56989b0f2694f393e6924820be11dcc1fbb8"
from rom_data import SymbolTable  # noqa: E402
from yellow_symbol_aliases import (  # noqa: E402
    FAN_CLUB_ID_RENAMES,
    GAME_CORNER_ID_RENAMES,
    MAP_CONST_RENAMES,
    MAP_LABEL_RENAMES,
    OMIT_INTRO_SYMBOLS,
    SYMBOL_ALIASES,
)

try:
    from rom_data import CANONICAL_YELLOW_SHA1
except ImportError:  # pragma: no cover -- constant lands with GameVersion work
    CANONICAL_YELLOW_SHA1 = "cc7d03262ebfaf2f06772c1a480c7d9d5f4a38e1"

DEV = "/Users/bryanbassett/Documents/development"
DEFAULT_RED = os.path.join(os.path.dirname(__file__), "rom_manifest.json")
DEFAULT_OUT = os.path.join(os.path.dirname(__file__), "rom_manifest_yellow.json")
DEFAULT_POKEYELLOW = os.path.join(DEV, "pokeyellow")
DEFAULT_SYMBOLS = os.path.join(DEV, "pokeyellow-symbols/pokeyellow.sym")

BASE_STATS_ENTRY_SIZE = 28
MEW_DEX_NUMBER = 151

# Yellow-only symbols Red never referenced.  Title / intro / CGB tables must
# be injected so RomExtractor can rip them (make_yellow_manifest only remaps
# Red's name set by default).
YELLOW_EXTRA_SYMBOLS = (
    "TitlePikachuBGGraphics",
    "TitlePikachuOBGraphics",
    "TitleScreenPikachuTilemap",
    "TitleScreenPikaBubbleTilemap",
    "TitleScreenPokemonLogoTilemap",
    "PokemonLogoCornerGraphics",
    "YellowIntroGraphics1",
    "YellowIntroGraphics2",
    "YellowIntroCloudGFX",
    "PikachuCriesPointerTable",
    "CGBBasePalettes",
    # Jessie & James share the ROCKET trainer class but battle behind their
    # own pic (home/trainers2.asm IsFightingJessieJames) (#439)
    "JessieJamesPic",
    # the five Pikachu-only emotion bubbles (emotion_bubbles.asm)
    "SkullEmote",
    "HeartEmote",
    "BoltEmote",
    "ZzzEmote",
    "FishEmote",
    # Surfing Pikachu minigame sheets (gfx/surfing_pikachu.asm)
    "SurfingPikachu1Graphics1",
    "SurfingPikachu1Graphics2",
    "SurfingPikachu1Graphics3",
    # Surfing Pikachu title screen tilemaps
    # (engine/minigame/surfing_pikachu.asm DrawSurfingPikachuMinigameIntroBackground)
    "SurfingMinigame_BeachIntroTilemap",
    "SurfingMinigame_TitleTilemap",
    "SurfingMinigame_ToSurfRadTilemap",
    "SurfingMinigame_UseControlPadTilemap",
    # Oak's own battle back pic.  LoadPlayerBackPic (engine/battle/core.asm)
    # picks OldManPicBack for BATTLE_TYPE_OLD_MAN but ProfOakPicBack for
    # BATTLE_TYPE_PIKACHU, the Pallet Town catch scene (#557).
    "ProfOakPicBack",
    # Base frames for the framed portrait TalkToPikachu draws, one per
    # PikaPicAnimScript (data/pikachu/pikachu_pic_animation.asm).  These are
    # raw address labels because the pikapic blobs carry no named symbols;
    # RomExtractor's PIKAPIC_BASE table indexes them positionally, so the
    # order here is not load bearing but every entry must resolve (#561).
    "Pic_e4000", "Pic_e411c", "Pic_e4272", "Pic_e4383", "Pic_e458b",
    "Pic_e467b", "Pic_e476e", "Pic_e49d1", "Pic_e4b39", "Pic_e4c3e",
    "Pic_e5000", "Pic_e523f", "Pic_e548e", "Pic_e56d1", "Pic_e5924",
    "Pic_e5b7d", "Pic_e5ddd", "GFX_e6020", "Pic_e6340", "Pic_e6587",
    "Pic_e67d6", "GFX_e6e6f", "GFX_e718f", "GFX_e74af", "Pic_e77cf",
    "Pic_f0abf", "Pic_f0cf4",
    # Yellow-only overworld player surf sprite, loaded outside
    # SpriteSheetPointerTable (LoadSurfingPlayerSpriteGraphics2) --
    # needs its own extract like RedBikeSprite. (RFC 0001)
    "SurfingPikachuSprite",
)

# Yellow-only dialogue whose bank labels carry no leading underscore, so
# the text-label scan misses them (scripts/CeruleanMelaniesHouse.asm --
# the Bulbasaur gift and the pet flavor lines).
YELLOW_EXTRA_TEXT_LABELS = (
    "MelanieText1", "MelanieText2", "MelanieText3",
    "MelanieText4", "MelanieText5",
    "MelanieBulbasaurText", "MelanieOddishText", "MelanieSandshrewText",
)

YELLOW_EXTRA_PALETTES = (
    "PIKACHUS_BEACH",
    "PIKACHU_PORTRAIT",
    "PIKACHUS_BEACH_TITLE",
)


def _rename_keys(obj, renames):
    """Recursively rename dict keys (and rewrite matching string values)."""
    if isinstance(obj, dict):
        out = {}
        for key, value in obj.items():
            new_key = renames.get(key, key)
            out[new_key] = _rename_keys(value, renames)
        return out
    if isinstance(obj, list):
        return [_rename_keys(item, renames) for item in obj]
    if isinstance(obj, str):
        return renames.get(obj, obj)
    return obj


def _replace_strings(obj, renames):
    """Recursively replace string values (and list entries) via renames."""
    if isinstance(obj, dict):
        return {k: _replace_strings(v, renames) for k, v in obj.items()}
    if isinstance(obj, list):
        return [_replace_strings(item, renames) for item in obj]
    if isinstance(obj, str):
        return renames.get(obj, obj)
    return obj


def _drop_strings(obj, dropped):
    """Remove dropped names from lists and as dict keys / string values."""
    if isinstance(obj, dict):
        out = {}
        for key, value in obj.items():
            if key in dropped:
                continue
            if isinstance(value, str) and value in dropped:
                continue
            out[key] = _drop_strings(value, dropped)
        return out
    if isinstance(obj, list):
        result = []
        for item in obj:
            if isinstance(item, str) and item in dropped:
                continue
            result.append(_drop_strings(item, dropped))
        return result
    return obj


def _resolve_mew_base_stats(yellow_symbols):
    base = yellow_symbols.by_name.get("BaseStats")
    if base is None:
        raise SystemExit("pokeyellow.sym missing BaseStats (needed for Mew)")
    return [base.bank, base.address + (MEW_DEX_NUMBER - 1) * BASE_STATS_ENTRY_SIZE]


def _rebuild_map_songs(pokeyellow, map_order, music_headers):
    """Zip pokeyellow data/maps/songs.asm onto the Yellow mapOrder."""
    map_song_consts = []
    path = os.path.join(pokeyellow, "data/maps/songs.asm")
    for _, line in util.read_asm(path):
        match = re.match(r"db\s+(MUSIC_\w+),", line.strip())
        if match:
            map_song_consts.append(match.group(1))
    if len(map_song_consts) != len(map_order):
        raise SystemExit(
            f"Yellow songs.asm has {len(map_song_consts)} entries but "
            f"mapOrder has {len(map_order)}")

    out = {}
    missing = []
    for map_name, const_name in zip(map_order, map_song_consts):
        label = _music_label(const_name, music_headers)
        if label not in music_headers:
            missing.append(f"{map_name}:{const_name}->{label}")
            continue
        out[map_name] = label
    if missing:
        raise SystemExit(
            "Yellow map songs could not resolve music headers: "
            + ", ".join(missing[:12])
            + (" ..." if len(missing) > 12 else ""))
    return out


def _rebuild_yellow_sourced(yellow, pokeyellow):
    """Replace sections that Yellow authors differently from Red."""
    map_order, map_dims = constants.extract_map_constants(pokeyellow)
    tileset_order = [
        n for n in simple_constants(
            pokeyellow, "constants/tileset_constants.asm") if n
    ]
    sprite_consts = simple_constants(
        pokeyellow, "constants/sprite_constants.asm")
    sprite_order = [n or "UNUSED" for n in sprite_consts[1:]]
    tile_animations = [
        name or "UNUSED"
        for name in simple_constants(
            pokeyellow, "constants/map_data_constants.asm")
        if name and name.startswith("TILEANIM_")
    ]

    yellow["constants"]["mapOrder"] = map_order
    yellow["constants"]["maps"] = map_dims
    yellow["constants"]["tilesetOrder"] = tileset_order
    yellow["constants"]["spriteOrder"] = sprite_order

    yellow["maps"] = map_metadata(pokeyellow, map_dims)
    yellow["tilesets"] = tileset_metadata(pokeyellow, tileset_order)
    yellow["sprites"] = sprite_metadata(pokeyellow, sprite_order)
    yellow["text"] = text_metadata(pokeyellow)
    yellow["tileAnimations"] = tile_animations

    yellow["audio"]["mapSongs"] = _rebuild_map_songs(
        pokeyellow, map_order, yellow["audio"]["musicHeaders"])
    # Red's positional header mapping lands Yellow's intro song
    # (pokeyellow Music_YellowIntro, 1f:4294) under the name
    # Music_IntroBattle; expose it under its own name too so the Yellow
    # intro movie state can ask for the right label.
    headers = yellow["audio"]["musicHeaders"]
    if "Music_YellowIntro" not in headers and "Music_IntroBattle" in headers:
        headers["Music_YellowIntro"] = dict(headers["Music_IntroBattle"])
    return {
        "mapCount": len(map_order),
        "mapMeta": len(yellow["maps"]),
        "tilesets": len(tileset_order),
        "sprites": len(sprite_order),
        "textLabels": len(yellow["text"]["labels"]),
    }


def _remap_audio(yellow, yellow_symbols):
    """Re-anchor the Red-copied audio section on pokeyellow.sym (#522).

    Yellow's music bank $1f shifts after 1f:4294: Music_YellowIntro is a
    3-channel header (pokeyellow audio/headers/musicheaders3.asm) where
    Red's Music_IntroBattle had 4, so Red's addresses for every later
    header land on a channel-2 row (one voice, and no tempo command --
    Viridian Forest slow and hollow).  Yellow also has a single
    wave-sample table at Audio1_WavePointers (audio.asm "Music 1"), not
    Red's per-engine 0x4373 copies, and CryData moved to 0e:5462.  Names
    absent from the sym (Music_IntroBattle, which Yellow only knows as
    Music_YellowIntro) keep their positional mapping.
    """
    for name, header in yellow["audio"]["musicHeaders"].items():
        symbol = yellow_symbols.by_name.get(name)
        if symbol is not None:
            header["bank"] = symbol.bank
            header["address"] = symbol.address
    wave = yellow_symbols.by_name.get("Audio1_WavePointers.wave0")
    if wave is None:
        raise SystemExit("pokeyellow.sym missing Audio1_WavePointers.wave0")
    for engine in yellow["audio"]["waveBanks"]:
        yellow["audio"]["waveBanks"][engine] = {
            "bank": wave.bank, "address": wave.address,
        }
    cry = yellow_symbols.by_name.get("CryData")
    if cry is None:
        raise SystemExit("pokeyellow.sym missing CryData")
    yellow["audio"]["cryData"] = {"bank": cry.bank, "address": cry.address}


def derive(red, pokeyellow, symbols_path):
    """Return the Yellow manifest derived from the Red manifest dict."""
    yellow = copy.deepcopy(red)
    yellow["romSha1"] = CANONICAL_YELLOW_SHA1
    yellow_symbols = SymbolTable(symbols_path)

    omit = set(OMIT_INTRO_SYMBOLS)
    dropped = {name for name, alias in SYMBOL_ALIASES.items() if alias is None}
    dropped |= omit
    symbol_renames = {
        name: alias for name, alias in SYMBOL_ALIASES.items() if alias
    }

    # Structural renames for Red-shaped leftovers (field townMap, etc.) before
    # Yellow-sourced sections overwrite maps/text/sprites/tilesets.
    structural = {}
    structural.update(MAP_CONST_RENAMES)
    structural.update(MAP_LABEL_RENAMES)
    structural.update(GAME_CORNER_ID_RENAMES)
    structural.update(FAN_CLUB_ID_RENAMES)
    structural.update(symbol_renames)
    yellow = _rename_keys(yellow, structural)
    yellow = _replace_strings(yellow, structural)
    yellow = _drop_strings(yellow, dropped)

    rebuilt = _rebuild_yellow_sourced(yellow, pokeyellow)
    _remap_audio(yellow, yellow_symbols)  # #522

    for label in YELLOW_EXTRA_TEXT_LABELS:
        if label not in yellow["text"]["labels"]:
            yellow["text"]["labels"].append(label)

    # Rebuild symbols from Red's name set with Yellow addresses / aliases,
    # then ensure every Yellow-sourced label/header is present.
    resolved = {}
    missing = []
    alias_hits = 0
    for name in red["symbols"]:
        if name in omit or name in dropped:
            continue
        if name == "MewBaseStats":
            resolved["MewBaseStats"] = _resolve_mew_base_stats(yellow_symbols)
            alias_hits += 1
            continue
        target = symbol_renames.get(name, name)
        if name in symbol_renames:
            alias_hits += 1
        # Structural map-header rename may already have changed the key.
        target = MAP_LABEL_RENAMES.get(target, target)
        if target.endswith("_h"):
            base = target[:-2]
            target = MAP_LABEL_RENAMES.get(base, base) + "_h" \
                if base in MAP_LABEL_RENAMES else target
        symbol = yellow_symbols.by_name.get(target)
        if symbol is None:
            # Drop Red-only symbols that Yellow-sourced sections no longer need.
            continue
        resolved[target] = [symbol.bank, symbol.address]

    print(
        "warning: omitting Yellow-incompatible intro symbols "
        f"(RomExtractor must skip): {', '.join(OMIT_INTRO_SYMBOLS)}"
    )

    for label in yellow["text"]["labels"]:
        if label in resolved:
            continue
        symbol = yellow_symbols.by_name.get(label)
        if symbol is None:
            missing.append(label)
            continue
        resolved[label] = [symbol.bank, symbol.address]
    for spec in yellow["maps"].values():
        header = spec["label"] + "_h"
        if header in resolved:
            continue
        symbol = yellow_symbols.by_name.get(header)
        if symbol is None:
            missing.append(header)
            continue
        resolved[header] = [symbol.bank, symbol.address]

    # Pointer asm labels (ViridianPokeCenterChanseyText etc.) also need symbols
    # when extract_text resolves through them.
    for pointers in yellow["text"]["pointers"].values():
        for spec in pointers.values():
            for key in ("label", "text"):
                name = spec.get(key)
                if not name or name in resolved:
                    continue
                symbol = yellow_symbols.by_name.get(name)
                if symbol is not None:
                    resolved[name] = [symbol.bank, symbol.address]

    yellow["symbols"] = resolved

    for name in YELLOW_EXTRA_SYMBOLS:
        symbol = yellow_symbols.by_name.get(name)
        if symbol is None:
            raise SystemExit(f"pokeyellow.sym missing Yellow extra symbol {name}")
        yellow["symbols"][name] = [symbol.bank, symbol.address]

    # Yellow-only songs live in music bank $20, which Red's engine never
    # had; ship the bank in the audio pack and add their headers.
    yellow["audio"]["programBanks"] = [2, 8, 31, 32]
    for name in ("Music_MeetJessieJames", "Music_SurfingPikachu",
                 "Music_GBPrinter"):
        symbol = yellow_symbols.by_name.get(name)
        if symbol is None:
            raise SystemExit(f"pokeyellow.sym missing Yellow song {name}")
        yellow["audio"]["musicHeaders"][name] = {
            "bank": symbol.bank, "address": symbol.address, "engine": 3,
        }

    # SuperPalettes grows by three Yellow-only SGB entries after GAMEFREAK.
    order = list(yellow.get("paletteOrder") or [])
    for name in YELLOW_EXTRA_PALETTES:
        if name not in order:
            order.append(name)
    yellow["paletteOrder"] = order

    # Yellow appends ICON_PIKACHU ($a) after Red's ten party icons
    # (constants/icon_constants.asm); MonPartyData nybble $a resolves to
    # it, drawn from the overworld PikachuSprite sheet.
    icons = list(yellow.get("iconOrder") or [])
    if "PIKACHU" not in icons:
        icons.append("PIKACHU")
    yellow["iconOrder"] = icons

    still_missing = []
    for name in yellow["symbols"]:
        if name == "MewBaseStats":
            continue
        if name not in yellow_symbols.by_name:
            still_missing.append(name)
    if still_missing or missing:
        raise SystemExit(
            "pokeyellow.sym is missing symbols the manifest needs: "
            + ", ".join(sorted(set(still_missing + missing))[:20])
            + (" ..." if len(set(still_missing + missing)) > 20 else ""))

    # Version-gated field bits from pokeyellow.
    saved = util.ASM_DEFINES
    util.ASM_DEFINES = set()
    try:
        yellow["field"]["presetNames"] = field.parse_preset_names(pokeyellow)
        try:
            yellow["field"]["credits"] = field.parse_credits(pokeyellow)
        except SystemExit as exc:
            print(f"warning: parse_credits failed ({exc}); keeping Red credits")
            # TODO: hand-author a Yellow credits banner if pret layout drifts.
        yellow["field"]["trades"] = field.parse_trades(pokeyellow)
    finally:
        util.ASM_DEFINES = saved

    presets = yellow["field"]["presetNames"]
    if "YELLOW" not in presets["player"] or "BLUE" not in presets["rival"]:
        raise SystemExit(
            f"Yellow preset-name parse unexpected: {presets!r}")

    # Fixed Pikachu title (no TitleMons cycle); extractor fills image paths.
    title = yellow["field"].setdefault("title", {})
    title["layout"] = "yellow_pikachu"
    title["cycleSpecies"] = []
    title["music"] = title.get("music") or "Music_TitleScreen"
    title["pikachuBg"] = {
        "path": "assets/generated/title/pikachu_bg.png",
        "width": 128, "height": 32,
    }
    title["pikachuOb"] = {
        "path": "assets/generated/title/pikachu_ob.png",
        "width": 96, "height": 8,
    }
    title["pikachu"] = {
        "path": "assets/generated/title/pikachu.png",
        "width": 96, "height": 72,
    }
    title["pikaBubble"] = {
        "path": "assets/generated/title/pika_bubble.png",
        "width": 56, "height": 32,
    }

    # Yellow's emote sheet grows the five Pikachu-only bubbles
    # (engine/overworld/emotion_bubbles.asm Skull/Heart/Bolt/Zzz/FishEmote,
    # constants/script_constants.asm order); RomExtractor rips whatever
    # this bubble list names.
    yellow_bubbles = ["EXCLAMATION_BUBBLE", "QUESTION_BUBBLE", "SMILE_BUBBLE",
                      "SKULL_BUBBLE", "HEART_BUBBLE", "BOLT_BUBBLE",
                      "ZZZ_BUBBLE", "FISH_BUBBLE"]
    yellow["field"]["emotionBubbles"] = {
        "path": "assets/generated/emotes.png",
        "width": 16 * len(yellow_bubbles), "height": 16,
        "bubbles": [{"name": name, "x": i * 16, "y": 0, "w": 16, "h": 16}
                    for i, name in enumerate(yellow_bubbles)],
    }

    # The Oak-speech show-off mon is the player's Pikachu in Yellow
    # (engine/battle/core.asm BATTLE_TYPE_PIKACHU / the ProfOak demo);
    # the deep-copied Red field.oakSpeech has no demoSpecies, so stamp
    # it or the import falls back to NIDORINO (#915).
    yellow["field"]["oakSpeech"]["demoSpecies"] = "PIKACHU"

    # Ensure Melanie / Summer Beach town-map entries exist after rebuild.
    locations = yellow["field"]["townMap"]["locations"]
    if "CERULEAN_MELANIES_HOUSE" not in locations \
            and "CERULEAN_CITY" in locations:
        locations["CERULEAN_MELANIES_HOUSE"] = dict(locations["CERULEAN_CITY"])
    if "SUMMER_BEACH_HOUSE" not in locations and "ROUTE_19" in locations:
        locations["SUMMER_BEACH_HOUSE"] = dict(locations["ROUTE_19"])

    # Surfing Pikachu minigame asset index (src/ui/SurfingMinigame.lua).
    yellow["field"]["surfingPikachu"] = {
        "music": "Music_SurfingPikachu",
        "sheets": {
            "bg": {
                "path": "assets/generated/minigame/surf_1a.png",
                "width": 40, "height": 104,
            },
            "oam": {
                "path": "assets/generated/minigame/surf_1b.png",
                "width": 128, "height": 128,
            },
            "intro": {
                "path": "assets/generated/minigame/surf_1c.png",
                "width": 96, "height": 96,
                "introPikaFrames": [
                    "assets/generated/minigame/intro_pika_0.png",
                    "assets/generated/minigame/intro_pika_1.png",
                    "assets/generated/minigame/intro_pika_2.png",
                    "assets/generated/minigame/intro_pika_3.png",
                ],
                "source": "data/sprite_anims/surfing_pikachu_oam.asm .IntroPikachu",
            },
            "titleBg": {
                "path": "assets/generated/minigame/title_bg.png",
                "width": 160, "height": 144,
            },
        },
        "source": (
            "engine/minigame/surfing_pikachu.asm "
            "(DrawSurfingPikachuMinigameIntroBackground), "
            "gfx/surfing_pikachu.asm"
        ),
    }

    meta = {
        "aliasCount": alias_hits,
        "omittedIntro": list(OMIT_INTRO_SYMBOLS),
        "droppedSymbols": sorted(dropped - omit),
        "rebuilt": rebuilt,
    }
    return yellow, meta


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--red", default=DEFAULT_RED,
                        help="shipped Red manifest to derive from")
    parser.add_argument("--pokeyellow", default=DEFAULT_POKEYELLOW,
                        help="pokeyellow source checkout")
    parser.add_argument("--symbols", default=DEFAULT_SYMBOLS,
                        help="pokeyellow.sym symbol file")
    parser.add_argument("--out", default=DEFAULT_OUT)
    parser.add_argument(
        "--allow-revision-mismatch", action="store_true",
        help="generate even if --pokeyellow isn't at POKEYELLOW_REVISION")
    args = parser.parse_args()

    pokeyellow = os.path.abspath(args.pokeyellow)
    if not os.path.isfile(os.path.join(pokeyellow, "main.asm")):
        raise SystemExit(f"{pokeyellow} is not a pokeyellow checkout")
    if POKEYELLOW_REVISION is not None:
        check_pokered_revision(
            pokeyellow, POKEYELLOW_REVISION,
            allow_mismatch=args.allow_revision_mismatch)
    with open(args.red, encoding="utf-8") as f:
        red = json.load(f)

    yellow, meta = derive(red, pokeyellow, os.path.abspath(args.symbols))
    with open(args.out, "w", encoding="utf-8", newline="\n") as f:
        json.dump(yellow, f, ensure_ascii=True, indent=2, sort_keys=True)
        f.write("\n")

    print(f"wrote {args.out}")
    print(f"symbols: {len(yellow['symbols'])}")
    print(f"aliases applied: {meta['aliasCount']}")
    print(f"omitted intro: {meta['omittedIntro']}")
    print(f"dropped: {len(meta['droppedSymbols'])} "
          f"({', '.join(meta['droppedSymbols'][:8])}...)")
    print(f"rebuilt: {meta['rebuilt']}")


if __name__ == "__main__":
    main()
