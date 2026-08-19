#!/usr/bin/env python3
"""Generate tools/rom_manifest_gold.json from pret/pokegold + pokegold.sym.

Phase 1 Gen 2 (Pokemon Gold) counterpart to tools/make_rom_manifest.py.  It
deliberately does not reuse tools/extract/* (that package is pokered-shaped:
ASM_DEFINES pins _RED, and several helpers assume Gen 1's flat map order and
Kanto dex numbering), so this file carries its own small RGBDS constant
parser instead.

Differences from Gen 1 that shape this file:
  - Species order IS dex order: BaseData's rows are declared in
    constants/pokemon_constants.asm order, and each row's own first byte is
    that same dex number (data/pokemon/base_stats/*.asm `db <SPECIES>`).
    There is no separate dexOrder/gen1_order remap to carry.
  - Maps are grouped (MAPGROUP_*/MAP_*, constants/map_constants.asm's
    `newgroup`/`map_const`/`endgroup`), not one flat table.
  - Pokemon pics and tileset graphics are lz3-compressed
    (home/decompress.asm), not pkmncompress'd -- see Rom.decompressLz3.

Usage: python3 tools/make_gold_manifest.py
Default paths: pokegold at ../pokegold (relative to the repo) or
/Users/bryanbassett/Documents/development/pokegold; symbols at
/Users/bryanbassett/Documents/development/pokegold-symbols/pokegold.sym.
"""

from __future__ import annotations

import argparse
import json
import os
import sys

# Reuse Gen 1's fontCharmap parser (seq→code for Font.encode); Gold's
# constants/charmap.asm is the same shape for the $60-$FF draw range.
sys.path.insert(0, os.path.join(os.path.dirname(__file__)))
from extract import font as font_extract  # noqa: E402
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from rom_data import CANONICAL_GOLD_SHA1, SymbolTable  # noqa: E402

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_POKEGOLD_CANDIDATES = [
    os.path.join(os.path.dirname(REPO_ROOT), "pokegold"),
    "/Users/bryanbassett/Documents/development/pokegold",
]
DEFAULT_SYMBOLS = (
    "/Users/bryanbassett/Documents/development/pokegold-symbols/pokegold.sym")

# pokegold builds Gold with _GOLD defined (rgbdscheck.asm / the Makefile's
# `gold` target); none of the constants files this script reads are
# actually gated on it today, but resolving IF DEF(_GOLD)/_SILVER here
# (rather than skipping IF entirely, like tools/extract/util.py does for
# unmodeled conditions) keeps this future-proof if that ever changes.
ASM_DEFINES = {"_GOLD"}


def strip_comment(line):
    out = []
    in_str = False
    for ch in line:
        if ch == '"':
            in_str = not in_str
        elif ch == ";" and not in_str:
            break
        out.append(ch)
    return "".join(out).rstrip()


def read_asm(path):
    """Read an asm file as (lineno, text), comments stripped, IF resolved."""
    lines = []
    stack = []  # stack of [taking, condition_known]
    with open(path, encoding="utf-8") as f:
        for lineno, raw in enumerate(f, 1):
            line = strip_comment(raw.rstrip("\n"))
            s = line.strip()
            m = re.match(r"IF\s+(!)?DEF\((\w+)\)\s*$", s, re.IGNORECASE)
            if m:
                defined = m.group(2) in ASM_DEFINES
                taking = (not defined) if m.group(1) else defined
                stack.append([taking, True])
                continue
            if re.match(r"IF\b", s):
                stack.append([True, False])  # unmodeled condition: keep body
                continue
            if re.match(r"ELSE\s*$", s, re.IGNORECASE) and stack:
                if stack[-1][1]:
                    stack[-1][0] = not stack[-1][0]
                continue
            if re.match(r"ENDC\s*$", s, re.IGNORECASE) and stack:
                stack.pop()
                continue
            if any(not fr[0] for fr in stack):
                continue
            lines.append((lineno, line))
    return lines


def parse_number(tok):
    tok = tok.strip()
    neg = tok.startswith("-")
    if neg:
        tok = tok[1:].strip()
    if tok.startswith("$"):
        val = int(tok[1:], 16)
    elif tok.startswith("%"):
        val = int(tok[1:], 2)
    elif tok.isdigit():
        val = int(tok)
    else:
        raise ValueError(f"not a number: {tok!r}")
    return -val if neg else val


def parse_const_block(path, stop_at=None):
    """Parse a linear const_def/const/const_skip block into an ordered list.

    Index i of the returned list is the constant's value (None for a gap);
    the same shape tools/extract/util.parse_const_block returns for Gen 1.
    """
    names = []
    value = None
    for _, line in read_asm(path):
        s = line.strip()
        if not s:
            continue
        if stop_at and re.match(rf"DEF\s+{stop_at}\b", s):
            break
        m = re.match(r"const_def(?:\s+(\$?\w+))?$", s)
        if m:
            value = parse_number(m.group(1)) if m.group(1) else 0
            continue
        m = re.match(r"const_next\s+(\$?\w+)$", s)
        if m:
            value = parse_number(m.group(1))
            continue
        m = re.match(r"const\s+(\w+)", s)
        if m and value is not None:
            while len(names) < value:
                names.append(None)
            names.append(m.group(1))
            value += 1
            continue
        m = re.match(r"const_skip(?:\s+(\d+))?$", s)
        if m and value is not None:
            n = int(m.group(1)) if m.group(1) else 1
            for _ in range(n):
                names.append(None)
            value += n
    return names


def parse_const_block_at(path, first_const, stop_at=None):
    """Parse the one const_def block whose first `const` is `first_const`.

    parse_const_block walks a file linearly and a second `const_def` in the
    same file rewinds its counter without rewinding the list, so it can only
    read a file's FIRST block.  phone_constants.asm stacks two (PHONE_* then
    SPECIALCALL_*) and script_constants.asm stacks a dozen, so anything past
    the first needs to be found by name.  Holes are kept as None: PHONE_* has
    four `const_skip`s in the middle and they are real PhoneContacts rows.
    """
    names = []
    value = None
    started = False
    for _, line in read_asm(path):
        s = line.strip()
        if not s:
            continue
        m = re.match(r"const_def(?:\s+(\$?\w+))?$", s)
        if m:
            if started:
                break
            value = parse_number(m.group(1)) if m.group(1) else 0
            names = []
            continue
        if started and stop_at and re.match(rf"DEF\s+{stop_at}\b", s):
            break
        m = re.match(r"const\s+(\w+)", s)
        if m and value is not None:
            if not started:
                if m.group(1) != first_const:
                    continue
                started = True
            while len(names) < value:
                names.append(None)
            names.append(m.group(1))
            value += 1
            continue
        m = re.match(r"const_skip(?:\s+(\d+))?$", s)
        if m and started and value is not None:
            n = int(m.group(1)) if m.group(1) else 1
            for _ in range(n):
                names.append(None)
            value += n
    if not started:
        raise SystemExit(f"{path}: no const block starting at {first_const}")
    return names


def parse_prefixed_consts(path, prefixes, exact=()):
    """Ordered const names from a file, filtered by prefix (mixed blocks).

    map_data_constants.asm and friends stack several unrelated const_def
    blocks in one file, so scraping by prefix is the only way to pull one
    of them out without the neighbours bleeding in.  `exact` names are kept
    even when they carry no shared prefix (TOWN, BALL, ...).
    """
    out = []
    for _, line in read_asm(path):
        m = re.match(r"const\s+(\w+)", line.strip())
        if not m:
            continue
        name = m.group(1)
        if name in exact or any(name.startswith(p) for p in prefixes):
            out.append(name)
    return out


def parse_sparse_consts(path, prefixes):
    """Ordered const names where index IS the const value (sparse blocks).

    parse_prefixed_consts packs a block densely, which is wrong for a block
    that jumps: constants/item_data_constants.asm's HELD_* run uses
    const_skip holes and const_next jumps to 10/20/30/40/50/70, so a dense
    scrape shifts every value after the first hole (HELD_HEAL_POISON is 10,
    not 7 -- and QUICK_CLAW at 74 fell off the end of the list entirely).
    Holes carry placeholder names because the manifest's JSON round trip
    collapses nulls out of an array.
    """
    out = []
    value = None
    for _, line in read_asm(path):
        s = line.strip()
        m = re.match(r"const_def(?:\s+(\d+))?\s*$", s)
        if m:
            value = int(m.group(1) or 0)
            continue
        m = re.match(r"const_next\s+(\d+)\s*$", s)
        if m and value is not None:
            value = int(m.group(1))
            continue
        m = re.match(r"const_skip(?:\s+(\d+))?\s*$", s)
        if m and value is not None:
            value += int(m.group(1) or 1)
            continue
        m = re.match(r"const\s+(\w+)", s)
        if not m or value is None:
            continue
        name = m.group(1)
        if any(name.startswith(p) for p in prefixes):
            while len(out) < value:
                out.append("%sUNUSED_%d" % (prefixes[0], len(out)))
            out.append(name)
        value += 1
    return out


def extract_trainer_classes(pokegold):
    """Ordered trainer class names (constants/trainer_constants.asm).

    `trainerclass NAME` bumps its own counter and resets the const_def used
    for that class's individual trainer ids, so parse_const_block cannot see
    them -- the two interleaved sequences need separate passes.  Index in the
    returned list IS the class id (TRAINER_NONE = 0).
    """
    path = os.path.join(pokegold, "constants/trainer_constants.asm")
    classes = []
    members = {}
    current = None
    for _, line in read_asm(path):
        s = line.strip()
        m = re.match(r"trainerclass\s+(\w+)", s)
        if m:
            current = m.group(1)
            classes.append(current)
            members[current] = []
            continue
        m = re.match(r"const\s+(\w+)", s)
        if m and current and not m.group(1).startswith("PHONECONTACT_"):
            members[current].append(m.group(1))
    if not classes or classes[0] != "TRAINER_NONE" or classes[1] != "FALKNER":
        raise ValueError("trainer_constants.asm did not parse as expected")
    return classes, members


def extract_items(pokegold):
    """Ordered item ids, and how many of them ItemNames actually covers.

    parse_const_block cannot do this file: after NUM_ITEMS the TM and HM items
    are declared through `add_tm DYNAMICPUNCH` / `add_hm CUT` macros that expand
    to `const TM_DYNAMICPUNCH` / `const HM_CUT`, and two plain `const ITEM_C3` /
    `ITEM_DC` sit *inside* that run consuming ids without being TMs.  Stopping
    at NUM_ITEMS (as a linear parse must) loses all 57 TM/HM items; ignoring it
    loses the boundary where ItemNames stops having rows.

    Returns (order, name_count) where order[i - 1] is item id i; NO_ITEM (0) is
    dropped so the list is 1-based on the id, matching ItemNames' rows.
    """
    path = os.path.join(pokegold, "constants/item_constants.asm")
    order = []
    name_count = None
    in_macro = False
    for _, line in read_asm(path):
        s = line.strip()
        # The add_tm / add_hm macro bodies contain `const TM_\1` themselves;
        # counting those would insert a phantom "TM_" item before the real run.
        if re.match(r"MACRO\b", s):
            in_macro = True
            continue
        if re.match(r"ENDM\b", s):
            in_macro = False
            continue
        if in_macro:
            continue
        if re.match(r"DEF\s+NUM_ITEMS\b", s):
            # NUM_ITEMS is const_value - 1, i.e. however many ids came before.
            name_count = len(order)
            continue
        m = re.match(r"const\s+(\w+)", s)
        if m:
            order.append(m.group(1))
            continue
        m = re.match(r"add_tm\s+(\w+)", s)
        if m:
            order.append("TM_" + m.group(1))
            continue
        m = re.match(r"add_hm\s+(\w+)", s)
        if m:
            order.append("HM_" + m.group(1))
            continue
    if not order or order[0] != "NO_ITEM":
        raise ValueError("item_constants.asm did not parse as expected")
    if not name_count:
        raise ValueError("item_constants.asm: NUM_ITEMS not found")
    # Drop NO_ITEM and the count that included it.
    return order[1:], name_count - 1


def extract_specials(pokegold):
    """Ordered SpecialsPointers labels (data/events/special_pointers.asm).

    The `special` script command carries an index into this table, not a name,
    so without the order a disassembled `special 27` says nothing.  Index in the
    returned list IS the id.
    """
    path = os.path.join(pokegold, "data/events/special_pointers.asm")
    names = []
    in_macro = False
    for _, line in read_asm(path):
        s = line.strip()
        if re.match(r"MACRO\b", s):
            in_macro = True
            continue
        if re.match(r"ENDM\b", s):
            in_macro = False
            continue
        if in_macro:
            continue
        m = re.match(r"add_special\s+(\w+)", s)
        if m:
            names.append(m.group(1))
    if not names or names[0] != "WarpToSpawnPoint":
        raise ValueError("special_pointers.asm did not parse as expected")
    return names


def extract_std_scripts(pokegold):
    """Ordered StdScripts labels (engine/events/std_scripts.asm)."""
    path = os.path.join(pokegold, "engine/events/std_scripts.asm")
    names = []
    for _, line in read_asm(path):
        m = re.match(r"add_stdscript\s+(\w+)", line.strip())
        if m:
            names.append(m.group(1))
    if not names or names[0] != "PokecenterNurseScript":
        raise ValueError("std_scripts.asm did not parse as expected")
    return names


def extract_map_groups(pokegold):
    """Parse constants/map_constants.asm's newgroup/map_const/endgroup."""
    path = os.path.join(pokegold, "constants/map_constants.asm")
    order = []
    groups = {}
    group = 0
    map_index = 0
    for _, line in read_asm(path):
        s = line.strip()
        if re.match(r"newgroup\s+\w+", s):
            group += 1
            map_index = 0
            continue
        m = re.match(r"map_const\s+(\w+),\s*([\d$%-]+),\s*([\d$%-]+)", s)
        if m:
            map_index += 1
            name = m.group(1)
            order.append(name)
            groups[name] = {
                "name": name,
                "group": group,
                "map": map_index,
                "width": parse_number(m.group(2)),
                "height": parse_number(m.group(3)),
            }
    if not order or order[0] != "OLIVINE_POKECENTER_1F":
        raise ValueError("map_constants.asm did not parse as expected")
    return order, groups


def extract_types(pokegold):
    """Type constants are physical IDs, a gap, then special IDs (Gen 1-style)."""
    path = os.path.join(pokegold, "constants/type_constants.asm")
    types = {}
    value = None
    for _, line in read_asm(path):
        s = line.strip()
        m = re.match(r"const_def(?:\s+(\$?\w+))?$", s)
        if m:
            value = parse_number(m.group(1)) if m.group(1) else 0
            continue
        m = re.match(r"const_next\s+(\$?\w+)$", s)
        if m:
            value = parse_number(m.group(1))
            continue
        m = re.match(r"const\s+(\w+)", s)
        if m and value is not None:
            types[m.group(1)] = value
            value += 1
    if types.get("NORMAL") != 0 or "DARK" not in types:
        raise ValueError("type_constants.asm did not parse as expected")
    return types


def charmap(pokegold):
    """Byte -> text charmap, same shape as make_rom_manifest.charmap."""
    expansions = {
        "<DOT>": ".",
        "<LV>": "{LV}",
        "<ID>": "{ID}",
        # Compression bytes: the cart stores one byte and PlaceString expands
        # it into several glyphs.  The font sheet only starts at $60, so these
        # three have no tile of their own and MUST be expanded here or the
        # decoded text asks the font for a glyph that cannot exist -- which is
        # what turns "#DEX" into "DEX" and "<POKE>GEAR" into "<POKE>GEAR".
        # The comments in charmap.asm name each expansion.
        "#": "POKé",           # $54
        "<POKE>": "<PO><KE>",  # $24
        "<PKMN>": "<PK><MN>",  # $4a
    }
    out = {}
    path = os.path.join(pokegold, "constants/charmap.asm")
    for _, line in read_asm(path):
        m = re.match(
            r'charmap\s+"((?:[^"\\]|\\.)*)",\s*(\$[0-9a-fA-F]+)',
            line.strip())
        if not m:
            continue
        value = int(m.group(2)[1:], 16)
        if str(value) in out:
            continue
        seq = m.group(1).replace('\\"', '"')
        out[str(value)] = expansions.get(seq, seq)
    return out


def species_label(species_id):
    """SPECIES_CONST_NAME -> the SpeciesConstName label pics use.

    Matches every dba_pics entry in data/pokemon/pic_pointers.asm: strip
    underscores (NIDORAN_F -> NidoranF, MR__MIME -> MrMime,
    FARFETCH_D -> FarfetchD, HO_OH -> HoOh) and title-case what remains.
    """
    parts = [part for part in species_id.split("_") if part]
    return "".join(part.capitalize() for part in parts)


def pokemon_names(pokegold):
    """PokemonNames dname entries, in declared (dex) order."""
    names = []
    path = os.path.join(pokegold, "data/pokemon/names.asm")
    for _, line in read_asm(path):
        m = re.match(r'dname\s+"([^"]*)"', line.strip())
        if m:
            names.append(m.group(1))
    return names


def music_order(pokegold):
    """Music_* labels in MUSIC_* id order from audio/music_pointers.asm."""
    path = os.path.join(pokegold, "audio/music_pointers.asm")
    order = []
    for _, line in read_asm(path):
        m = re.match(r"dba\s+(Music_\w+)\s*$", line.strip())
        if m:
            order.append(m.group(1))
    if not order:
        raise ValueError("no Music_* dba rows in audio/music_pointers.asm")
    return order


def sfx_order(pokegold):
    """Sfx_* labels in SFX_* id order from audio/sfx_pointers.asm."""
    path = os.path.join(pokegold, "audio/sfx_pointers.asm")
    order = []
    for _, line in read_asm(path):
        m = re.match(r"dba\s+(Sfx_\w+)\s*$", line.strip())
        if m:
            order.append(m.group(1))
    if not order:
        raise ValueError("no Sfx_* dba rows in audio/sfx_pointers.asm")
    return order


def pokemon_assets(pokegold, species_order, symbols):
    """{species: {id, name, front, back, frontLabel, backLabel}}.

    Unown shares one pic per letter through UnownPicPointers (its
    dba_pics row in pic_pointers.asm is deliberately blank) rather than a
    per-species Frontpic/Backpic label, so its front/back/labels are left
    null; the extractor's own Unown handling (if any) goes through
    UnownPicPointers directly instead of this table.
    """
    names = pokemon_names(pokegold)
    assets = {}
    for index, species in enumerate(species_order):
        name = names[index] if index < len(names) else species
        if species == "UNOWN":
            # No per-species pic, but it does have a dex entry like anything
            # else, so the #DEX screen can still read it.
            assets[species] = {
                "id": species, "name": name,
                "front": None, "back": None,
                "frontLabel": None, "backLabel": None,
                "dexLabel": "UnownPokedexEntry",
            }
            continue
        base = species_label(species)
        front_label, back_label = base + "Frontpic", base + "Backpic"
        if front_label not in symbols.by_name or back_label not in symbols.by_name:
            raise ValueError(
                f"{species}: expected pic symbols {front_label}/{back_label} "
                "are missing from pokegold.sym")
        # Pokedex entry symbol, resolved here for the same reason the pic
        # labels are: the entries live in four different banks and the game
        # derives the bank from the species id arithmetically.
        dex_label = base + "PokedexEntry"
        assets[species] = {
            "id": species, "name": name,
            "front": base.lower(), "back": base.lower() + "_back",
            "frontLabel": front_label, "backLabel": back_label,
            "dexLabel": dex_label if dex_label in symbols.by_name else None,
        }
    return assets


REQUIRED_SYMBOLS = {
    "BaseData", "PokemonNames", "PokemonPicPointers", "UnownPicPointers",
    "EggPic",
    # gfx/evo/egg_hatch.2bpp, the two OBJ tiles EggHatch_AnimationSequence
    # copies to vTiles0 tile $00 for the shell crack and the ten fragments
    # (engine/pokemon/breeding.asm:777).
    "EggHatchGFX",
    "Font", "FontExtra", "FontBattleExtra", "Frames",
    # The extra font page is NOT FontExtra laid down from $60: _LoadFontsExtra
    # (engine/gfx/load_font.asm:7-20) builds it from three sources, and the
    # first three tiles come from the other two.  gfx/font.asm keeps them well
    # away from FontExtra, so each needs its own symbol:
    #   $60-$61  FontsExtra_SolidBlackAndUpArrowGFX, 2 tiles, 1bpp
    #            (gfx/font/black.1bpp + gfx/font/up_arrow.1bpp)
    #   $62      PokegearPhoneIconGFX, 1 tile, 2bpp (gfx/font/phone_icon.2bpp)
    #   $63+     FontExtra + 3 tiles, 22 tiles, 2bpp
    # Loading FontExtra from $60 instead puts its unused <BOLD_A>/<BOLD_B>/
    # <BOLD_C> in those three cells -- constants/charmap.asm:41 marks that
    # $62 mapping "unused" and :88 gives $62 to "☎" -- which is why the
    # Pokegear caller box drew a bold C where the phone icon belongs.
    "PokegearPhoneIconGFX", "FontsExtra_SolidBlackAndUpArrowGFX",
    # gfx/font/unown_font.2bpp (gfx/font.asm UnownFont): the 26 Unown letters
    # plus the diamond cursor, loaded at vTiles2 tile FIRST_UNOWN_CHAR ($40)
    # by Pokedex_LoadUnownFont for the #DEX's UNOWN MODE.
    "UnownFont",
    "TitleScreenGFX1", "TitleScreenGFX2", "TitleScreenGFX3",
    "TitleScreenGFX4", "TitleScreenTilemap",
    "CopyrightGFX", "Tilesets", "MapGroupPointers", "Music", "Cries",
    # _AnimateTileset's `dw arg / dw function` programs (data/tileset_anims.asm)
    # and the two shared frame strips (engine/tilesets/tileset_anims.asm:194,
    # :225): the extractor resolves a tileset's Anim pointer against these.
    "DoneTileAnimation", "WaitTileAnimation",
    "StandingTileFrame", "StandingTileFrame8",
    "AnimateWaterTile", "AnimateFlowerTile", "AnimateWaterPalette",
    "ReadTileToAnimBuffer", "WriteTileFromAnimBuffer",
    "ScrollTileRightLeft", "ScrollTileDown", "ScrollTileUp",
    "ScrollTileLeft", "ScrollTileRight", "AnimateWhirlpoolTile",
    "AnimateLavaBubbleTile1", "AnimateLavaBubbleTile2",
    "AnimateTowerPillarTile", "FlickeringCaveEntrancePalette",
    "AnimateWaterTile.WaterTileFrames", "AnimateFlowerTile.FlowerTileFrames",
    # AnimateLavaBubbleTile1/2 hardcode their source (tileset_anims.asm:251,
    # :276); the whirlpool and tower-pillar strips come off the pointer pairs
    # their own tileframe arguments name, so they need no symbol here.
    "LavaBubbleTileFrames",
    # data/sprites/emotes.asm:22 `emote GrassRustleGFX, 1, $fe`, the one tile
    # ShakeGrass' SPRITEMOVEDATA_GRASS object draws.
    "GrassRustleGFX",
    "PokemonCries", "SFX",
    "OverworldSprites", "ChrisSpriteGFX", "Moves", "EvosAttacksPointers",
    # data/sprites/sprite_mons.asm: one species byte per SPRITE_POKEMON id,
    # which GetMonSprite's .Icon arm feeds to LoadOverworldMonIcon
    "SpriteMons",
    # Phase 2: roofs overlay outdoor Johto towns (engine/tilesets/mapgroup_roofs.asm)
    "MapGroupRoofs", "Roofs",
    # New-game object visibility (engine/events/std_scripts.asm InitializeEventsScript)
    "InitializeEventsScript",
    # Gen 2 audio driver: wave RAM patterns + drum kit pointer table
    "WaveSamples", "Drumkits",
    # Oak speech intro (engine/menus/intro_menu.asm OakSpeech)
    "PokemonProfPic", "CalPic",
    "_OakText1", "_OakText2", "_OakText3", "_OakText4",
    "_OakText5", "_OakText6", "_OakText7",
    # Boot cinema (splash.asm / ShrinkPlayer).  GameFreakLogoGFX is two
    # INCBINs run together -- gamefreak_presents.1bpp (13 tiles) then
    # gamefreak_logo.1bpp (15) -- and GameFreakLogoStarsGFX is another two,
    # logo_star.2bpp (2) then logo_sparkle.2bpp (3).
    "GameFreakLogoGFX", "GameFreakLogoStarsGFX", "Shrink1Pic", "Shrink2Pic",
    # Credits roll graphics (engine/movie/credits.asm).  CreditsBorderGFX is
    # the 9-tile strip on rows 4 and 13; the four mon labels are 4x4-tile
    # frames stacked (3 frames each, Sentret 4); TheEndGFX lives in its own
    # "The End" section in gfx/misc.asm; CreditsPalettes is gfx/credits/
    # credits.pal, six four-colour sets.
    "CreditsBorderGFX", "CreditsBellossomGFX", "CreditsTogepiGFX",
    "CreditsElekidGFX", "CreditsSentretGFX", "TheEndGFX", "CreditsPalettes",
    # The #DEX diploma (engine/events/diploma.asm PlaceDiplomaOnScreen).
    # DiplomaGFX is gfx/diploma/diploma.2bpp.lz, 112 tiles into vTiles2;
    # DiplomaPage1Tilemap is gfx/diploma/page1.tilemap, a whole SCREEN_AREA
    # copied straight over the background; DiplomaPalettes is gfx/diploma/
    # diploma.pal (engine/gfx/color.asm), which _CGB_Diploma loads before
    # WipeAttrmap puts every tile on set 0.
    "DiplomaGFX", "DiplomaPage1Tilemap", "DiplomaPalettes",
    # The trade animation's art (engine/movie/trade_animation.asm, gfx/trade/).
    # TradeGameBoyLZ is game_boy_cable.2bpp.lz, 49 tiles into vTiles2 tile $31,
    # which both tilemaps and the jumptable's loose cable ids index; the rest
    # are the OAM objects -- the ball, the poof, the tube bulge (gfx/trade/
    # cable.png) and the mon icon's bubble -- plus the two one-tile arrows
    # TradeAnim_PlaceTrademonStatsOnTubeAnim fills across the window.
    "TradeGameBoyLZ", "TradeGameBoyTilemap", "TradeLinkTubeTilemap",
    "TradeBallGFX", "TradePoofGFX", "TradeCableGFX", "TradeBubbleGFX",
    "TradeArrowRightGFX", "TradeArrowLeftGFX",
    # Item names (data/items/names.asm) for giveitem / verbosegiveitem
    "ItemNames",
    # Mart shelves (data/items/marts.asm): Marts is the NUM_MARTS pointer
    # table `pokemart` indexes, each list `db count, items..., -1`.
    # BargainShopData (data/items/bargain_shop.asm) is the Goldenrod
    # Underground shop's own `dbw item, price` rows -- the one shop whose
    # prices do not come from ItemAttributes.
    "Marts", "BargainShopData",
    # GBC colour (engine/gfx/color.asm LoadMapPals).  TilesetBGPalette is the
    # shared pool of $2a four-colour palettes; EnvironmentColorsPointers picks
    # 8 of them per environment per time of day; MapObjectPals recolours OW
    # sprites; RoofPals overrides PAL_BG_ROOF colours 1-2 per map group.
    "TilesetBGPalette", "EnvironmentColorsPointers", "MapObjectPals",
    "RoofPals", "PokemonPalettes", "TrainerPalettes",
    "HPBarPals", "ExpBarPalette", "PartyMenuOBPals",
    # Battle + pokemon runtime data
    "MoveNames", "TypeNames", "TypeMatchups", "TMHMMoves", "GrowthRates",
    "ItemAttributes", "MoveDescriptions", "ItemDescriptions",
    # Wild encounters (data/wild/*)
    "JohtoGrassWildMons", "JohtoWaterWildMons",
    "KantoGrassWildMons", "KantoWaterWildMons",
    "FishGroups", "TimeFishGroups", "TreeMons", "TreeMonMaps",
    # data/wild/treemon_maps.asm RockMonMaps: the four maps whose smashable
    # rocks roll TREEMON_SET_ROCK, read by RockMonEncounter.
    "RockMonMaps",
    # data/wild/swarm_grass.asm + swarm_water.asm, searched by
    # _SwarmWildmonCheck BEFORE the Johto/Kanto tables while the player stands
    # on wSwarmMapGroup/Number, and data/wild/roammon_maps.asm RoamMaps, the
    # graph UpdateRoamMons and JumpRoamMon walk the beasts along.
    "SwarmGrassWildMons", "SwarmWaterWildMons", "RoamMaps",
    # data/wild/bug_contest_mons.asm, which is NOT a grass table: its rows are
    # `db %, species, min, max` with no map key and no time of day, and
    # ChooseWildEncounter_BugContest (engine/overworld/events.asm) walks them
    # with `ld de, 4`.
    "ContestMons",
    # data/events/bug_contest_flags.asm: the ten
    # EVENT_BUG_CATCHING_CONTESTANT_*A words
    # SelectRandomBugContestContestants (engine/events/bug_contest/
    # contest_2.asm) resets and then sets five of, a set flag being what keeps
    # that trainer off NationalParkBugContest.
    "BugCatchingContestantEventFlagTable",
    # Trainers (data/trainers/*)
    "Trainers", "TrainerGroups", "TrainerClassNames",
    "TrainerClassAttributes", "TrainerPicPointers",
    "TrainerEncounterMusic",
    # Menus: party icons, dex ordering + entries, Pokegear landmarks.  The two
    # held-item marker tiles ride on the party icons: GetIconGFX uploads
    # HeldItemIcons straight after each icon's eight tiles
    # (engine/gfx/mon_icons.asm:218-228), so the party list cannot draw the
    # marker without this symbol.
    "MonMenuIcons", "Icons", "IconPointers", "HeldItemIcons",
    "PokedexDataPointerTable",
    # New-game / Pokecenter respawn table (data/maps/spawn_points.asm)
    "SpawnPoints",
    "NewPokedexOrder", "AlphabeticalPokedexOrder", "Landmarks",
    # GoldSilverIntro (engine/movie/intro.asm): three acts of BG art, each a
    # compressed tile sheet plus a 2x2 metatile table and a metatile grid, and
    # the OBJ sheets the mons animate from
    "Intro_WaterGFX1", "Intro_WaterTilemap", "Intro_WaterMeta",
    "Intro_WaterGFX2",
    "Intro_GrassGFX1", "Intro_GrassTilemap", "Intro_GrassMeta",
    "Intro_GrassGFX2",
    "Intro_FireGFX1", "Intro_FireGFX2", "Intro_FireGFX3",
    # ...and its palettes.  _CGB_GSIntro carries the water act's inline, takes
    # the grass and starter ones out of PredefPals, and reaches the fire act's
    # through the four PREDEFPAL_* indices inside PalPacket_Pack.
    "PredefPals", "PalPacket_Pack",
    "_CGB_GSIntro.ShellderLaprasBGPalette", "_CGB_GSIntro.ShellderLaprasOBPals",
    "Intro_LoadMagikarpPalettes.MagikarpBGPal",
    "Intro_LoadMagikarpPalettes.MagikarpOBPal",
    # Battle animations (data/moves/animations.asm + data/battle_anims/*).
    # BattleAnimations is a 278-entry pointer table indexed by the animation
    # id, which for a move IS its move id; the four tables under it are the
    # object rows an animation spawns, their framesets, the OAM sets those
    # framesets step through, and the compressed sheets the tiles come from.
    "BattleAnimations", "BattleAnimObjects", "BattleAnimFrameData",
    "BattleAnimOAMData", "AnimObjGFX",
    # gfx/battle_anims/battle_anims.pal: the six OBJ palettes an animation
    # object names by PAL_BATTLE_OB_GRAY..PAL_BATTLE_OB_BROWN.  The routine
    # that copies them (CGBCopyBattleObjectPals) is dummied out on the cart --
    # _CGB_BattleColors loads the same block -- but the label is still in the
    # ROM, so the colours are read rather than transcribed.
    "BattleObjectPals",
    # Battle HUD tiles (engine/gfx/load_font.asm LoadHPBar): the L-shaped
    # frame tiles the enemy and player HUDs are built from, and the exp bar's
    # nine fill cells.  "HP:" and the ten HP-bar cells come from
    # FontBattleExtra, which is already extracted.
    "EnemyHPBarBorderGFX", "HPExpBarBorderGFX", "ExpBarGFX",
    # The player's own battle back-pic (gfx/player/chris_back.2bpp.lz).  It is
    # what stands in the player's pic box for the whole battle intro, before
    # SendOutPlayerMon swaps in the mon's backpic.
    "ChrisBackpic",
    # UnownPicPointers: 26 rows of `dba_pics front, back`, one per letter.
    # PokemonPicPointers' UNOWN row is only the A form, so the other 25 are
    # unreachable without this table.
    "UnownPicPointers",
    # Naming screen chrome (gfx/naming_screen/*): the patterned tile that
    # fills the backdrop, the 2-tile cursor, and the middle/under lines that
    # mark the name-entry field
    "NamingScreenGFX_Border", "NamingScreenGFX_Cursor",
    "NamingScreenGFX_MiddleLine", "NamingScreenGFX_UnderLine",
    # PACK chrome (engine/items/pack.asm): the screen's own $60-tile sheet,
    # the four 15-tile pack pictures DrawPackGFX swaps per pocket, the 5x12
    # pocket-name tilemap, and the six BG palettes _CGB_PackPals loads.
    "PackMenuGFX", "PackGFX", "DrawPocketName.tilemap",
    "_CGB_PackPals.PackPals",
    # #DEX chrome (engine/pokedex/pokedex.asm): Pokedex_LoadGFX decompresses
    # PokedexLZ over vTiles2 tile $31, and every frame, divider and label tile
    # the dex screens name comes out of that one sheet.
    # PokedexSlowpokeLZ is the dex's OBJ sheet: the search screen's Slowpoke
    # animation, and behind it the $30-$33 bracket tiles the listing cursor is
    # built from plus the $0f scrollbar thumb.
    "PokedexLZ", "PokedexSlowpokeLZ", "PokedexCursorPalette",
    "LoadQuestionMarkPic.QuestionMarkLZ", "PokedexQuestionMarkPalette",
    "Footprints",
    # POKeGEAR (engine/pokegear/pokegear.asm): TownMapGFX at $00 and
    # PokegearGFX at $30 are the card sheets; the three cards are RLE
    # tilemaps; JohtoMap/KantoMap are the painted town maps; TownMapPals.PalMap
    # is the tile-id -> BG palette nybble table that colours them.
    "TownMapGFX", "PokegearGFX", "PokegearSpritesGFX",
    "ClockTilemapRLE", "PhoneTilemapRLE", "RadioTilemapRLE",
    "JohtoMap", "KantoMap", "TownMapPals.PalMap", "PokegearPals",
    # Trainer card (engine/menus/trainer_card.asm): the player's portrait and
    # the card frame share one sheet at $00, the status/leader sheets both
    # load at $29, and the badges are OBJs with their own OAM template table.
    "ChrisPicAndTrainerCardGFX", "CardStatusGFX", "LeaderGFX", "BadgeGFX",
    "TrainerCard_JohtoBadgesOAM",
    # Unown puzzle (engine/games/unown_puzzle.asm): the four pictures the Ruins
    # of Alph chambers slice into sixteen panels, the START>CANCEL box and
    # caption sheet that lands at vTiles0 $ed, the four cursor OBJ tiles at
    # $e0, and the eight border tiles UnownPuzzle_AddPuzzlePieceBorders ORs
    # onto every panel once the picture has been doubled in size.
    "KabutoPuzzleLZ", "OmanytePuzzleLZ", "AerodactylPuzzleLZ", "HoOhPuzzleLZ",
    "UnownPuzzleStartCancelLZ", "UnownPuzzleCursorGFX",
    "PuzzlePieceBorderData.TileBordersGFX",
    # Emote bubbles (data/sprites/emotes.asm): showemote's ! over a trainer
    # who just spotted the player, and the other faces scripts use.
    "ShockEmote", "QuestionEmote", "HappyEmote", "SadEmote",
    "HeartEmote", "BoltEmote", "SleepEmote", "FishEmote",
    # The Pokecenter heal machine's OBJ art (engine/events/
    # heal_machine_anim.asm): two tiles -- the machine's light ($7c) and the
    # ball ($7d) -- plus the CGB palette .LoadPalettes copies over
    # PAL_OW_TREE for the duration of the light show.
    "HealMachineAnim.HealMachineGFX", "HealMachineAnim.palettes",
    # Magnet Train (engine/events/magnet_train.asm).  Two uncompressed
    # tilemaps: a 2x18 strip DrawMagnetTrain repeats across the background,
    # and the 20x4 train laid over rows 6-9.  The cutscene loads no tiles of
    # its own -- both index TILESET_TRAIN_STATION, already in VRAM.
    "MagnetTrainBGTiles", "MagnetTrainTilemap",
    # callstd / jumpstd targets (engine/events/std_scripts.asm)
    "StdScripts",
    # The phone (data/phone/*.asm).  PhoneContacts is a row per PHONE_*
    # constant carrying two `dba` script pointers -- the callee half (you rang
    # them) and the caller half (they rang you) -- and SpecialPhoneCallList a
    # row per SPECIALCALL_* carrying one more.  Every one of those pointers
    # lands in bank $41, which no map script points at, so without these two
    # symbols the whole bank stays unreachable and a queued call has no body.
    "PhoneContacts", "SpecialPhoneCallList",
    # The three little scripts the phone engine runs WITHOUT a contact row
    # (engine/phone/phone.asm): the wrong-number arm LoadCallerScript falls to,
    # the no-signal / wrong-hour arm, and "they are on this very map, go talk
    # to them".  Nothing points at any of them either.
    "WrongNumber.script", "PhoneOutOfAreaScript", "PhoneScript_JustTalkToThem",
    # Egg moves (data/pokemon/egg_moves.asm): 251 `dw` into bank 8, each a
    # $ff-terminated move list.  Breeding.canInheritMove reads def.eggMoves.
    "EggMovePointers",
    # In-game trades (data/events/npc_trades.asm), the `trade` command's table,
    # and the 5x3 text table PrintTradeText indexes by dialog then dialog SET
    # (engine/events/npc_trade.asm).  NPCTradeCableText is the "cable" line
    # between the yes and the animation; TradedForText is the one after it.
    "NPCTrades", "TradeTexts", "NPCTradeCableText", "TradedForText",
    # The six lines the trade ANIMATION prints around the swap
    # (engine/movie/trade_animation.asm, strings in data/text/common_1.asm).
    # They are printed by asm, not by a writetext, so the text walker only
    # reaches them by name -- and their {STRBUF} markers are the trademon
    # name buffers, which is the only thing that tells "MACHOP was sent to
    # MIKE" from the same line with the two names the other way round.
    # _MonNameSentToText is deliberately absent: it is empty.
    "_MonWasSentToText", "_ForYourMonSendsText", "_OTSendsText",
    "_BidsFarewellToMonText", "_MonNameBidsFarewellText",
    "_TakeGoodCareOfMonText",
    # Elevator floor labels (data/events/elevator_floors.asm).  The floor LIST
    # an `elevator` names lives in the script's own bank; this is the shared
    # FLOOR_* -> "B1F@" name table the ride menu prints.
    "ElevatorFloorNames",
    # describedecoration's five DECODESC_* arms (engine/overworld/decorations.asm).
    # Each arm is asm that picks a SCRIPT off what is installed in the player's
    # room, so the scripts are what the extractor wants, not the arms:
    # DecorationDesc_PosterPointers is the poster table (`dbw deco, script`
    # rows, `db -1` end) with NullPoster as its miss; the two ornaments and the
    # console all share .OrnamentConsoleScript, and the giant ornament has
    # .BigDollScript to itself.
    "DecorationDesc_PosterPointers", "DecorationDesc_NullPoster",
    "DecorationDesc_OrnamentOrConsole.OrnamentConsoleScript",
    "DecorationDesc_GiantOrnament.BigDollScript",
    # Text an ENGINE routine prints rather than a script (RomExtractorGen2's
    # NAMED_TEXT).  The text walker only follows a writetext pointer, so
    # without these labels the Day-Care and breeding block of common_1.asm /
    # common_2.asm, the whole POKeMART conversation, and the Hall of Fame's
    # three flavour strings never reach the cache at all.
    "_DaycareDummyText",
    "_DayCareManIntroText", "_DayCareManIntroEggText",
    "_DayCareLadyIntroText", "_DayCareLadyIntroEggText",
    "_WhatShouldIRaiseText", "_OnlyOneMonText", "_CantAcceptEggText",
    "_RemoveMailText", "_LastHealthyMonText", "_IllRaiseYourMonText",
    "_ComeBackLaterText", "_AreWeGeniusesText", "_YourMonHasGrownText",
    "_PerfectHeresYourMonText", "_GotBackMonText", "_BackAlreadyText",
    "_HaveNoRoomText", "_NotEnoughMoneyText", "_OhFineThenText",
    "_ComeAgainText", "_NotYetText", "_FoundAnEggText", "_ReceivedEggText",
    "_TakeGoodCareOfEggText", "_IllKeepItThanksText", "_NoRoomForEggText",
    "Text_BreedHuh", "_BreedClearboxText", "_BreedEggHatchText",
    "_BreedAskNicknameText",
    "_LeftWithDayCareManText", "_LeftWithDayCareLadyText",
    "_BreedBrimmingWithEnergyText", "_BreedNoInterestText",
    "_BreedAppearsToCareForText", "_BreedFriendlyText",
    "_BreedShowsInterestText",
    "_MartWelcomeText", "_MartAskMoreText", "_MartComeAgainText",
    "_MartHowManyText", "_MartFinalPriceText", "_MartThanksText",
    "_MartNoMoneyText", "_MartPackFullText",
    "_HerbShopLadyIntroText", "_HerbalLadyHowManyText",
    "_HerbalLadyFinalPriceText", "_HerbalLadyThanksText",
    "_HerbalLadyPackFullText", "_HerbalLadyNoMoneyText",
    "_HerbalLadyComeAgainText",
    "_BargainShopIntroText", "_BargainShopFinalPriceText",
    "_BargainShopThanksText", "_BargainShopPackFullText",
    "_BargainShopSoldOutText", "_BargainShopNoFundsText",
    "_BargainShopComeAgainText",
    "_PharmacyIntroText", "_PharmacyHowManyText", "_PharmacyFinalPriceText",
    "_PharmacyThanksText", "_PharmacyPackFullText", "_PharmacyNoMoneyText",
    "_PharmacyComeAgainText",
    "_NothingToSellText", "_MartSellHowManyText", "_MartSellPriceText",
    "_MartCantBuyText", "_MartBoughtText",
    "AnimateHallOfFame.String_NewHallOfFamer",
    "_HallOfFamePC.TimeFamer", "_HallOfFamePC.HOFMaster",
    # The MAIL block of data/text/common_2.asm, printed by engine/pokemon/
    # mail.asm's MailboxPC and engine/pokemon/mon_menu.asm's MonMailAction.
    # Same shape as the Day-Care block: asm prints these, so no bytecode
    # points at them and the walker has to be seeded by name.
    "_EmptyMailboxText", "_MailClearedPutAwayText", "_MailPackFullText",
    "_MailMessageLostText", "_MailAlreadyHoldingItemText", "_MailEggText",
    "_MailMovedFromBoxText", "_MailLoseMessageText", "_MailDetachedText",
    "_MailNoSpaceText", "_MailAskSendToPCText", "_MailboxFullText",
    "_MailSentToPCText", "_PCMonHoldingMailText", "_PokemonRemoveMailText",
}


def embedded_symbols(symbols, pokemon_labels, song_labels=()):
    """Resolve REQUIRED_SYMBOLS + pic labels + Music_* song headers."""
    names = set(REQUIRED_SYMBOLS) | set(pokemon_labels) | set(song_labels)
    for symbol_name in symbols.by_name:
        # Pokedex entries are split across four banks and the game derives the
        # bank arithmetically from the species id (radio.asm's rlca/maskbits
        # dance).  Taking each entry's own symbol instead means the extractor
        # never has to reproduce that, and a repointed entry still resolves.
        if symbol_name.endswith("PokedexEntry") and "." not in symbol_name:
            names.add(symbol_name)
        if symbol_name.endswith("Frontpic") or symbol_name.endswith("Backpic"):
            # Skip qualified locals (e.g. "Foo.BarBackpic") -- those belong
            # to unrelated engine routines, not a Pic Pointers table entry.
            if "." not in symbol_name:
                names.add(symbol_name)

    missing = sorted(name for name in names if name not in symbols.by_name)
    if missing:
        raise ValueError("required symbols are missing: " + ", ".join(missing))
    return {
        name: [symbols[name].bank, symbols[name].address]
        for name in sorted(names)
    }


def generate(pokegold, symbols_path):
    symbols = SymbolTable(symbols_path)

    species = parse_const_block(
        os.path.join(pokegold, "constants/pokemon_constants.asm"),
        stop_at="NUM_POKEMON")
    species_order = [n or "UNUSED" for n in species[1:]]

    map_order, map_groups = extract_map_groups(pokegold)

    tilesets = [n for n in parse_const_block(
        os.path.join(pokegold, "constants/tileset_constants.asm"),
        stop_at="NUM_TILESETS") if n]

    moves = parse_const_block(
        os.path.join(pokegold, "constants/move_constants.asm"),
        stop_at="NUM_ATTACKS")
    move_order = [n or "UNUSED" for n in moves[1:]]

    # sprite_constants.asm stacks the ids of two different tables.  $01..
    # NUM_OVERWORLD_SPRITES are OverworldSprites rows (data/sprites/
    # sprites.asm); then `const_next $80` restarts at SPRITE_POKEMON and the
    # names from there are SpriteMons rows (data/sprites/sprite_mons.asm),
    # which GetMonSprite turns into a mon's menu icon instead of a sheet.
    # Both blocks are read into one id-indexed list, because a byte in
    # wVariableSprites -- what a doll or a Sudowoodo stands on -- is a raw
    # sprite id and the port names it through this list.
    #
    # It stops at SPRITE_HO_OH on purpose.  SPRITE_DAY_CARE_MON_1/_2 ($e0) and
    # the SPRITE_VARS block ($f0) past it are not sprites at all: the first
    # pair reads a breedmon species and the second is a slot INTO
    # wVariableSprites, so naming them here would let World:resolveSprite hand
    # a slot id back as though it were something that could be drawn.
    sprite_path = os.path.join(pokegold, "constants/sprite_constants.asm")
    sprites = parse_const_block(sprite_path, stop_at="NUM_POKEMON_SPRITES")
    sprite_order = [n or "UNUSED" for n in sprites[1:]]
    # The two DEFs the block itself ends its halves on.  The $60..$7f hole
    # between them stays in sprite_order as UNUSED rows so the ids line up.
    num_overworld_sprites = len(
        parse_const_block(sprite_path, stop_at="NUM_OVERWORLD_SPRITES")) - 1
    sprite_pokemon = sprites.index("SPRITE_UNOWN")
    if len(sprites) - sprite_pokemon != 35:
        raise SystemExit(
            f"{sprite_path}: expected 35 SpriteMons ids, got "
            f"{len(sprites) - sprite_pokemon}")

    types = extract_types(pokegold)

    # Environment (1-based), palette (0-based), fish-group (0-based) name
    # tables -- scraped by prefix so the mixed const_def blocks in
    # map_data_constants.asm cannot collide with each other.
    environments, palettes, fish_groups, spawns = [], [], [], []
    path = os.path.join(pokegold, "constants/map_data_constants.asm")
    for _, line in read_asm(path):
        s = line.strip()
        m = re.match(r"const\s+(\w+)", s)
        if not m:
            continue
        name = m.group(1)
        if name in (
            "TOWN", "ROUTE", "INDOOR", "CAVE", "ENVIRONMENT_5", "GATE",
            "DUNGEON",
        ) or name.startswith("ENVIRONMENT_"):
            environments.append(name)
        elif name.startswith("PALETTE_"):
            palettes.append(name)
        elif name.startswith("FISHGROUP_"):
            fish_groups.append(name)
        elif name.startswith("SPAWN_"):
            spawns.append(name)

    # Move effects (EFFECT_*) index the effect jumptable; the extractor turns
    # Moves' effect byte into one of these names so the battle engine can
    # switch on a readable id instead of a raw number.
    move_effects = parse_const_block(
        os.path.join(pokegold, "constants/move_effect_constants.asm"))
    move_effect_order = [n or "EFFECT_UNUSED" for n in move_effects]

    # Battle animations.  constants/battle_anim_constants.asm stacks nine
    # unrelated const_def blocks in one file, so each list is scraped by its
    # own prefix -- parse_const_block would run them together.  These name the
    # rows of the five tables the extractor reads (objects, functions,
    # framesets, OAM sets, GFX sheets) plus the BG-effect and palette enums a
    # disassembled animation refers to by number.
    battle_anim = os.path.join(pokegold, "constants/battle_anim_constants.asm")
    battle_anim_objects = parse_prefixed_consts(battle_anim, ("BATTLE_ANIM_OBJ_",))
    battle_anim_funcs = parse_prefixed_consts(battle_anim, ("BATTLE_ANIM_FUNC_",))
    battle_anim_framesets = parse_prefixed_consts(
        battle_anim, ("BATTLE_ANIM_FRAMESET_",))
    battle_anim_oamsets = parse_prefixed_consts(battle_anim, ("BATTLE_ANIM_OAMSET_",))
    # BATTLE_ANIM_GFX_* is the one block here that does not start at zero
    # (`const_def 1`, because AnimObjGFX row 0 is the empty AnimObj00GFX).
    # A placeholder in front keeps every list in this group indexable as
    # value + 1, so the extractor never has to remember which is which.
    battle_anim_gfx = ["BATTLE_ANIM_GFX_NONE"] + parse_prefixed_consts(
        battle_anim, ("BATTLE_ANIM_GFX_",))
    battle_bg_effects = parse_prefixed_consts(battle_anim, ("BATTLE_BG_EFFECT_",))
    # Two separate blocks, each starting at zero: a BG palette 4 and an OBJ
    # palette 4 are different colours, so they cannot share one list.
    battle_anim_bg_pals = parse_prefixed_consts(battle_anim, ("PAL_BATTLE_BG_",))
    battle_anim_ob_pals = parse_prefixed_consts(battle_anim, ("PAL_BATTLE_OB_",))

    item_data = os.path.join(pokegold, "constants/item_data_constants.asm")
    # Pocket ids are 0-based (ITEM, KEY_ITEM, BALL, TM_HM); the ITEM_* /
    # ITEMMENU_* / HELD_* blocks share the file, hence the prefix scrape.
    pocket_order = parse_prefixed_consts(
        item_data, (), exact=("ITEM", "KEY_ITEM", "BALL", "TM_HM"))
    item_menu_order = parse_prefixed_consts(item_data, ("ITEMMENU_",))
    # The HELD_* block is sparse (const_skip / const_next), so the index of
    # this list must BE the ItemAttributes effect byte or every held effect
    # past HELD_CLEANSE_TAG lands on the wrong item.
    held_effect_order = parse_sparse_consts(item_data, ("HELD_",))

    mon_data = os.path.join(pokegold, "constants/pokemon_data_constants.asm")
    growth_order = parse_prefixed_consts(mon_data, ("GROWTH_",))
    egg_group_order = parse_prefixed_consts(mon_data, ("EGG_",))
    evolve_order = parse_prefixed_consts(mon_data, ("EVOLVE_",))

    # Map callbacks (constants/map_setup_constants.asm).  That block is
    # `const_def 1`, so MAPCALLBACK_TILES is 1 and index 0 of this list is a
    # placeholder -- the same "value + 1" indexing BATTLE_ANIM_GFX_* uses.
    map_setup = os.path.join(pokegold, "constants/map_setup_constants.asm")
    map_callback_order = ["MAPCALLBACK_NONE"] + parse_prefixed_consts(
        map_setup, ("MAPCALLBACK_",))

    # constants/script_constants.asm stacks a dozen unrelated blocks, so each
    # of these is found by the name its own block opens with.
    script_consts = os.path.join(pokegold, "constants/script_constants.asm")
    cmd_queue_order = parse_const_block_at(
        script_consts, "CMDQUEUE_NULL", stop_at="NUM_CMDQUEUE_TYPES")
    floor_order = parse_const_block_at(
        script_consts, "FLOOR_B4F", stop_at="NUM_FLOORS")
    deco_desc_order = parse_const_block_at(
        script_consts, "DECODESC_POSTER", stop_at="NUM_DECODESCS")

    # The phone.  PHONE_* doubles as the PhoneContacts row index and carries
    # four const_skip holes that are real rows (the wrong-number fillers), so
    # the gaps have to survive into the list.
    phone_consts = os.path.join(pokegold, "constants/phone_constants.asm")
    # The holes are named rather than left null: the JSON decoder the importer
    # runs on this file collapses nulls out of an array, which would slide
    # every contact past a hole four rows down its own table.
    phone_contact_order = [
        n or "PHONE_UNUSED" for n in parse_const_block_at(
            phone_consts, "PHONE_00", stop_at="NUM_PHONE_CONTACTS")]
    special_call_order = parse_const_block_at(
        phone_consts, "SPECIALCALL_NONE", stop_at="NUM_SPECIALCALLS")

    npc_trade = os.path.join(pokegold, "constants/npc_trade_constants.asm")
    trade_gender_order = parse_prefixed_consts(npc_trade, ("TRADE_GENDER_",))
    trade_dialog_order = parse_prefixed_consts(npc_trade, ("TRADE_DIALOGSET_",))

    trainer_classes, trainer_members = extract_trainer_classes(pokegold)
    trainer_types = parse_prefixed_consts(
        os.path.join(pokegold, "constants/trainer_data_constants.asm"),
        ("TRAINERTYPE_",))

    landmarks = parse_const_block(
        os.path.join(pokegold, "constants/landmark_constants.asm"),
        stop_at="NUM_LANDMARKS")
    landmark_order = [n or "UNUSED" for n in landmarks]

    icons = parse_prefixed_consts(
        os.path.join(pokegold, "constants/icon_constants.asm"), ("ICON_",))

    tree_sets = parse_prefixed_consts(mon_data, ("TREEMON_SET_",))

    std_scripts = extract_std_scripts(pokegold)
    specials = extract_specials(pokegold)

    assets = pokemon_assets(pokegold, species_order, symbols)
    pokemon_labels = []
    for asset in assets.values():
        if asset["frontLabel"]:
            pokemon_labels.append(asset["frontLabel"])
        if asset["backLabel"]:
            pokemon_labels.append(asset["backLabel"])

    songs = music_order(pokegold)
    sfx = sfx_order(pokegold)

    # Index 0 is NO_ITEM, so the parsed list is already 1-based on item id.
    # ItemNames only has rows for the first `item_name_count` of them; the TM
    # and HM items past that are named from their TM number instead.
    item_order, item_name_count = extract_items(pokegold)

    data = {
        "format": 3,
        "generation": 2,
        "romSha1": CANONICAL_GOLD_SHA1,
        "constants": {
            "source": "pret/pokegold constants/*.asm",
            "speciesOrder": species_order,
            "mapGroups": [map_groups[name] for name in map_order],
            "mapOrder": map_order,
            "tilesetOrder": tilesets,
            "moveOrder": move_order,
            "types": types,
            "spriteOrder": sprite_order,
            # NUM_OVERWORLD_SPRITES: how many leading spriteOrder rows are real
            # OverworldSprites rows.  Everything from spritePokemon on names a
            # SpriteMons row and has no sheet of its own.
            "numOverworldSprites": num_overworld_sprites,
            # SPRITE_POKEMON ($80): the first mon-icon id, and the base
            # GetMonSprite subtracts to index SpriteMons.
            "spritePokemon": sprite_pokemon,
            "environmentOrder": environments,
            "paletteOrder": palettes,
            "fishGroupOrder": fish_groups,
            # SPAWN_* order; SPAWN_HOME is a new game's start (intro_menu.asm)
            "spawnOrder": spawns,
            # MUSIC_* id → Music_* label (audio/music_pointers.asm order)
            "musicOrder": songs,
            # SFX_* id → Sfx_* label (audio/sfx_pointers.asm order)
            "sfxOrder": sfx,
            # Item id → constant name (MASTER_BALL=1 …); used by extractItems
            "itemOrder": item_order,
            # How many leading item ids ItemNames has rows for; TM/HM items
            # past this point carry no name of their own.
            "itemNameCount": item_name_count,
            # Battle / pokemon runtime orders
            "moveEffectOrder": move_effect_order,
            "growthRateOrder": growth_order,
            "eggGroupOrder": egg_group_order,
            "evolveMethodOrder": evolve_order,
            # Bag pockets + item attribute enums (data/items/attributes.asm).
            # `property` is a bitfield, not an enum (shift_const CANT_SELECT
            # = bit 6, CANT_TOSS = bit 7), so the extractor decodes it
            # directly rather than naming it from a list here.
            "pocketOrder": pocket_order,
            "itemMenuOrder": item_menu_order,
            "heldEffectOrder": held_effect_order,
            # Trainers: class id → name, class → its own trainer ids
            "trainerClassOrder": trainer_classes,
            "trainerClassMembers": trainer_members,
            "trainerTypeOrder": trainer_types,
            # Pokegear town map + wild encounter side tables
            "landmarkOrder": landmark_order,
            "iconOrder": icons,
            "treeMonSetOrder": tree_sets,
            # callstd / jumpstd id → StdScripts label
            "stdScriptOrder": std_scripts,
            # Map script header: callback type id → MAPCALLBACK_* name (1-based,
            # index 0 is a placeholder) and the cmdqueue entry's own type enum.
            "mapCallbackOrder": map_callback_order,
            "cmdQueueOrder": cmd_queue_order,
            # `elevator` floor ids and `describedecoration`'s five arms
            "floorOrder": floor_order,
            "decoDescOrder": deco_desc_order,
            # PhoneContacts row → PHONE_* name (holes kept: they are rows),
            # and SpecialPhoneCallList row → SPECIALCALL_* name
            "phoneContactOrder": phone_contact_order,
            "specialCallOrder": special_call_order,
            # `trade` row enums (data/events/npc_trades.asm)
            "tradeGenderOrder": trade_gender_order,
            "tradeDialogOrder": trade_dialog_order,
            # `special` id → SpecialsPointers label
            "specialOrder": specials,
            # Battle animations: the row names of BattleAnimObjects,
            # BattleAnimFrameData, BattleAnimOAMData and AnimObjGFX, plus the
            # BG-effect and OBJ/BG palette enums an animation names by number.
            "battleAnimObjectOrder": battle_anim_objects,
            "battleAnimFuncOrder": battle_anim_funcs,
            "battleAnimFramesetOrder": battle_anim_framesets,
            "battleAnimOamsetOrder": battle_anim_oamsets,
            "battleAnimGfxOrder": battle_anim_gfx,
            "battleBgEffectOrder": battle_bg_effects,
            "battleAnimBgPaletteOrder": battle_anim_bg_pals,
            "battleAnimObPaletteOrder": battle_anim_ob_pals,
        },
        "charmap": charmap(pokegold),
        "fontCharmap": font_extract.parse_charmap(pokegold),
        "pokemonAssets": assets,
        # Per-map metadata (group/map/width/height/name).  RomExtractorGen2
        # resolves ROM headers via MapGroupPointers + these ids.
        "maps": {name: map_groups[name] for name in map_order},
        "tilesets": {name: {} for name in tilesets},
    }
    data["symbols"] = embedded_symbols(symbols, pokemon_labels, songs)
    return data


def find_pokegold():
    for candidate in DEFAULT_POKEGOLD_CANDIDATES:
        if os.path.isfile(os.path.join(candidate, "main.asm")):
            return candidate
    return DEFAULT_POKEGOLD_CANDIDATES[-1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pokegold", default=find_pokegold())
    parser.add_argument("--symbols", default=DEFAULT_SYMBOLS)
    parser.add_argument(
        "--out",
        default=os.path.join(
            os.path.dirname(__file__), "rom_manifest_gold.json"))
    args = parser.parse_args()

    pokegold = os.path.abspath(args.pokegold)
    if not os.path.isfile(os.path.join(pokegold, "main.asm")):
        raise SystemExit(f"{pokegold} is not a pokegold checkout")
    data = generate(pokegold, os.path.abspath(args.symbols))
    with open(args.out, "w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, ensure_ascii=False, indent=2, sort_keys=True)
        f.write("\n")
    print(f"wrote {args.out}")


if __name__ == "__main__":
    main()
