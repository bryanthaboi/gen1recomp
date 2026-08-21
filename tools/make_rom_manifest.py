#!/usr/bin/env python3
"""Generate non-ROM metadata used by tools/build_rom_data.py.

The resulting JSON contains symbolic IDs, dimensions, and enum names that
were erased during assembly. It deliberately contains no ROM byte ranges or
graphics/audio payload.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from extract import (battle_anims, constants, field, font, items, maps,  # noqa: E402
                     pokemon, sprites, text, tilesets, trainers, util)
from rom_data import CANONICAL_RED_SHA1, SymbolTable  # noqa: E402

# The pret/pokered commit this manifest was last verified against. Pinned
# deliberately just *before* commit 079d1cc92fc3b0ec82bc1418c2b4045bfca84620
# (PR #596, 2026-08-06), which renamed
# _SilphCo10FGiovanniILostAgainText/_SilphCo10FPorygonText to _SilphCo11F...
# -- data/scripts/victories.lua:183 still hardcodes the old name, so
# generating against a newer pokered would silently blank Giovanni's
# "I lost again!?" rematch line. Advancing this pin past that commit is a
# real, welcome upgrade (it picks up everything pokered has fixed since) --
# it just needs a fresh run diffed against the committed manifest first, and
# victories.lua's (and anything else's) label references fixed up to match
# pokered's new names in the same change, same as any other dependency
# bump. Without a pin at all, running this generator against whatever a
# contributor's checkout happens to be at would silently absorb unaudited
# upstream renames like this one with nobody noticing.
POKERED_REVISION = "cf621a76d4941c93c078eb38e0880fe8db48ef40"


def _checkout_revision(path):
    try:
        return subprocess.run(
            ["git", "rev-parse", "HEAD"], cwd=path, check=True,
            capture_output=True, text=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return None


def check_pokered_revision(pokered, expected, *, allow_mismatch=False):
    actual = _checkout_revision(pokered)
    if actual is None or actual == expected or allow_mismatch:
        return
    raise SystemExit(
        f"{pokered} is at {actual}, but this generator is pinned to "
        f"{expected}. Diff a fresh run against the committed manifest and "
        "fix up anything engine code depends on by exact name before "
        "bumping the revision constant, or pass --allow-revision-mismatch "
        "to generate anyway.")


def simple_constants(pokered, relpath, stop_at=None):
    return util.parse_const_block(
        os.path.join(pokered, relpath), stop_at=stop_at)


def charmap(pokered):
    expansions = dict(text.EXPANSIONS)
    expansions.update({
        "<DOT>": ".",
        "<to>": "to",
        "<LV>": "{LV}",
        "<ID>": "{ID}",
    })
    out = {}
    path = os.path.join(pokered, "constants/charmap.asm")
    for _, line in util.read_asm(path):
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


def sfx_keys(pokered, symbols):
    """Map the one-byte sound IDs stored in MoveSoundTable to audio keys."""
    out = {}
    # Move animations always resolve their one-byte IDs through the battle
    # SFX headers. The same address-derived IDs are reused by the other two
    # audio banks, so accepting all SFX_* symbols would create collisions.
    battle_bank = symbols["SFX_Pound"].bank
    path = os.path.join(pokered, "constants/music_constants.asm")
    for _, line in util.read_asm(path):
        m = re.match(r"music_const\s+SFX_\w+,\s*(SFX_\w+)", line.strip())
        if not m:
            continue
        label = m.group(1)
        symbol = symbols.by_name.get(label)
        if not symbol or symbol.bank != battle_bank:
            continue
        delta = symbol.address - 0x4000
        if delta < 0 or delta % 3:
            continue
        sound_id = delta // 3
        if not 0 <= sound_id <= 0xFF:
            continue
        key = re.sub(r"_[123]$", "", label.removeprefix("SFX_"))
        out[str(sound_id)] = key
    return out


def battle_animation_metadata(pokered):
    """Return names and dimensions that do not survive ROM assembly."""
    consts = battle_anims.parse_anim_constants(pokered)
    base_coords = battle_anims.parse_base_coords(pokered)
    frame_blocks = battle_anims.parse_frame_blocks(pokered)
    subanims = battle_anims.parse_subanimations(
        pokered, len(frame_blocks), len(base_coords), consts)
    special_effects = {
        str(value): name
        for name, value in consts.items()
        if name.startswith("SE_")
    }
    sheets = (
        "move_anim_0.png", "move_anim_1.png", "move_anim_0.png")
    return {
        "baseCoordCount": len(base_coords),
        "frameBlockCount": len(frame_blocks),
        "subanimCount": len(subanims),
        "moveCount": battle_anims.NUM_ATTACKS,
        "miscAnimations": battle_anims.MISC_ANIMS,
        "subanimTypes": battle_anims.SUBANIMTYPE_NAMES,
        "firstSpecialEffect": min(
            int(value) for value in special_effects),
        "specialEffects": special_effects,
        "tilesheets": [
            {
                "path": f"assets/generated/battle/anims/{filename}",
                "source": f"gfx/battle/{filename}",
                "width": 128,
                "height": 40,
            }
            for filename in sheets
        ],
    }


def pokemon_metadata(pokered, dex_order):
    pics = pokemon.parse_pic_files(pokered)
    by_dex_const = {}
    base_dir = os.path.join(pokered, "data/pokemon/base_stats")
    for fname in sorted(os.listdir(base_dir)):
        if not fname.endswith(".asm"):
            continue
        rel = f"data/pokemon/base_stats/{fname}"
        stats = pokemon.parse_base_stats_file(
            os.path.join(base_dir, fname), rel)
        by_dex_const[stats["dexConst"]] = stats

    assets = {}
    for species in dex_order:
        stats = by_dex_const["DEX_" + species]
        front = pics.get(stats.get("picFront", ""))
        back = pics.get(stats.get("picBack", ""))
        assets[species] = {
            "front": os.path.splitext(os.path.basename(front))[0]
            if front else None,
            "back": os.path.splitext(os.path.basename(back))[0]
            if back else None,
            "frontLabel": stats.get("picFront") if front else None,
            "backLabel": stats.get("picBack") if back else None,
        }

    growth_rates = []
    for _, line in util.read_asm(
            os.path.join(pokered, "constants/pokemon_data_constants.asm")):
        m = re.match(r"const\s+GROWTH_(\w+)", line.strip())
        if m:
            growth_rates.append(m.group(1))
    return assets, growth_rates


def trainer_pic_metadata(pokered):
    pics = {}
    for _, line in util.read_asm(os.path.join(pokered, "gfx/pics.asm")):
        m = re.match(
            r'(\w+)Pic::?\s+INCBIN\s+"(gfx/trainers/[^"]+)"',
            line.strip())
        if m:
            base = os.path.splitext(os.path.basename(m.group(2)))[0]
            pics[m.group(1)] = {
                "label": m.group(1) + "Pic",
                "path": f"assets/generated/battle/trainers/{base}.png",
                "imageBase": base,
            }

    labels, _ = trainers.parse_parties(pokered)
    # Keep missing pictures as explicit false values. JSON null becomes nil in
    # Lua and would collapse these two array positions in the runtime importer.
    return [pics.get(label) or False for label in labels]


def map_metadata(pokered, map_dims):
    """Keep only map names and other labels that assembly erased."""
    headers_dir = os.path.join(pokered, "data/maps/headers")
    blocks_files = maps.parse_blocks_files(pokered)
    toggles = maps.parse_toggleable_objects(pokered)
    out = {}
    for fname in sorted(os.listdir(headers_dir)):
        if not fname.endswith(".asm"):
            continue
        header = maps.parse_header(os.path.join(headers_dir, fname))
        if "const" not in header or header["const"] not in map_dims:
            continue
        const = header["const"]
        label = header["label"]
        if const in out:
            def spells_const(value):
                return value.upper() == const.replace("_", "")

            if spells_const(out[const]["label"]) == spells_const(label):
                raise ValueError(f"duplicate map header for {const}")
            if spells_const(out[const]["label"]):
                continue

        parsed = maps.parse_objects(
            os.path.join(pokered, "data/maps/objects", f"{label}.asm"))
        object_names = parsed["objectNames"]
        object_specs = []
        for index, obj in enumerate(parsed["objects"]):
            spec = {"text": obj["text"]}
            for key in ("trainerClass", "trainerParty", "pokemon", "item"):
                if key in obj:
                    spec[key] = obj[key]
            if index < len(object_names):
                spec["name"] = object_names[index]
                if toggles.get(const, {}).get(object_names[index]) == "OFF":
                    spec["hidden"] = True
            object_specs.append(spec)

        block_rel = blocks_files.get(label, f"maps/{label}.blk")
        out[const] = {
            "label": label,
            "blockLength": os.path.getsize(os.path.join(pokered, block_rel)),
            "signTexts": [sign["text"] for sign in parsed["signs"]],
            "objects": object_specs,
        }
    return out


def tileset_metadata(pokered, order):
    """Describe tileset payload sizes and symbolic enum names."""
    from PIL import Image

    labels = tilesets.parse_incbin_labels(pokered)
    headers = []
    path = os.path.join(pokered, "data/tilesets/tileset_headers.asm")
    for _, line in util.read_asm(path):
        match = tilesets.TILESET_RE.match(line.strip())
        if match:
            headers.append(match)
    if len(headers) != len(order):
        raise ValueError("tileset header count does not match constants")

    out = []
    for match, const_name in zip(headers, order):
        name = match.group(1)
        gfx_rel = labels[f"{name}_GFX"]
        block_rel = labels[f"{name}_Block"]
        png_rel = re.sub(r"\.2bpp$", ".png", gfx_rel)
        with Image.open(os.path.join(pokered, png_rel)) as image:
            width, height = image.size
        block_size = os.path.getsize(os.path.join(pokered, block_rel))
        if block_size % 16:
            raise ValueError(f"{block_rel} is not a whole number of blocks")
        out.append({
            "id": const_name,
            "name": name,
            "imageBase": os.path.splitext(os.path.basename(png_rel))[0],
            "imageWidth": width,
            "imageHeight": height,
            "blockCount": block_size // 16,
        })
    return out


def sprite_metadata(pokered, order):
    """Describe overworld sprite labels and source atlas dimensions."""
    from PIL import Image

    files = sprites.parse_sprite_files(pokered)
    sheets = sprites.parse_sheet_table(pokered)
    if len(sheets) != len(order):
        raise ValueError("sprite sheet count does not match constants")

    out = []
    for (label, _tiles, _line), const_name in zip(sheets, order):
        source = files[label]
        png_path = re.sub(r"\.2bpp$", ".png", source)
        with Image.open(os.path.join(pokered, png_path)) as image:
            width, height = image.size
        out.append({
            "id": const_name,
            "label": label,
            "imageBase": os.path.splitext(os.path.basename(png_path))[0],
            "imageWidth": width,
            "imageHeight": height,
        })

    bike_source = files["RedBikeSprite"]
    bike_png = re.sub(r"\.2bpp$", ".png", bike_source)
    with Image.open(os.path.join(pokered, bike_png)) as image:
        bike_width, bike_height = image.size
    out_manifest = {
        "order": out,
        "bike": {
            "label": "RedBikeSprite",
            "imageBase": "red_bike",
            "imageWidth": bike_width,
            "imageHeight": bike_height,
        },
    }
    # Yellow-only: the surfing-Pikachu overworld ride sheet, parallel
    # to the bike entry; absent in Red/Blue. (RFC 0001)
    surf_source = files.get("SurfingPikachuSprite")
    if surf_source:
        surf_png = re.sub(r"\.2bpp$", ".png", surf_source)
        with Image.open(os.path.join(pokered, surf_png)) as image:
            surf_width, surf_height = image.size
        out_manifest["surfPikachu"] = {
            "label": "SurfingPikachuSprite",
            "imageBase": "surfing_pikachu",
            "imageWidth": surf_width,
            "imageHeight": surf_height,
        }
    return out_manifest


def text_metadata(pokered):
    """Keep text labels, runtime substitutions, and script integration data."""
    paths = []
    text_dir = os.path.join(pokered, "text")
    paths.extend(
        os.path.join(text_dir, name)
        for name in sorted(os.listdir(text_dir))
        if name.endswith(".asm"))
    data_text_dir = os.path.join(pokered, "data/text")
    paths.extend(
        os.path.join(data_text_dir, name)
        for name in sorted(os.listdir(data_text_dir))
        if re.match(r"text_\d+\.asm$", name))
    paths.append(os.path.join(pokered, "data/pokemon/dex_text.asm"))

    labels = []
    dynamic = {}
    current = None
    command_ids = {"text_ram": 1, "text_bcd": 2, "text_decimal": 9}
    token_names = {"text_ram": "RAM", "text_bcd": "NUM",
                   "text_decimal": "NUM"}
    for path in paths:
        for _, line in util.read_asm(path):
            stripped = line.strip()
            # not every string label carries the far-text underscore
            # (SilphCo2FSilphWorkerFPleaseTakeThisText and friends live in
            # the script bank), and dropping those lost their strings (#393)
            match = re.match(r"(\w+)::?\s*$", stripped)
            if match:
                current = match.group(1)
                labels.append(current)
                continue
            match = re.match(
                r"(text_ram|text_bcd|text_decimal)\s+(.+)$", stripped)
            if match and current:
                macro, args = match.groups()
                token = (
                    "{" + token_names[macro] + ":"
                    + args.replace('"', "") + "}")
                dynamic.setdefault(current, []).append(
                    [command_ids[macro], token])

    pointers = text.parse_script_text_pointers(pokered)
    trainer_headers = text.parse_trainer_headers(pokered)
    for headers in trainer_headers.values():
        for header in headers.values():
            header.pop("source", None)
    return {
        "labels": sorted(set(labels)),
        "dynamic": dynamic,
        "pointers": pointers,
        "trainerHeaders": trainer_headers,
    }


def _without_sources(value):
    if isinstance(value, dict):
        return {
            key: _without_sources(item)
            for key, item in value.items()
            if key != "source"
        }
    if isinstance(value, list):
        return [_without_sources(item) for item in value]
    return value


def field_metadata(pokered):
    """Capture the port's hand-authored field integration, without artwork."""
    with tempfile.TemporaryDirectory() as temp_dir:
        out_dir = os.path.join(temp_dir, "data", "generated")
        os.makedirs(out_dir)
        return _without_sources(field.extract(pokered, out_dir))


def _audio_headers(pokered, symbols, prefix, label_prefix):
    headers = {}
    root = os.path.join(pokered, "audio/headers")
    for filename in sorted(os.listdir(root)):
        if not filename.startswith(prefix) or not filename.endswith(".asm"):
            continue
        match = re.search(r"(\d+)\.asm$", filename)
        engine = int(match.group(1)) if match else 1
        for _, line in util.read_asm(os.path.join(root, filename)):
            match = re.match(rf"({label_prefix}\w+)::?\s*$", line.strip())
            if not match:
                continue
            name = match.group(1)
            symbol = symbols.by_name.get(name)
            if symbol:
                headers[name] = {
                    "engine": engine,
                    "bank": symbol.bank,
                    "address": symbol.address,
                }
    return headers


def _music_label(const_name, music_headers):
    candidate = "Music_" + "".join(
        part.capitalize()
        for part in const_name.removeprefix("MUSIC_").split("_"))
    folded = candidate.lower()
    return next(
        (name for name in music_headers if name.lower() == folded),
        candidate)


def audio_metadata(pokered, symbols, map_order):
    """Names and addresses needed to interpret audio bytecode from ROM."""
    music_headers = _audio_headers(
        pokered, symbols, "musicheaders", "Music_")
    all_sfx_headers = _audio_headers(
        pokered, symbols, "sfxheaders", "SFX_")

    sfx_headers = {}
    for name in sorted(all_sfx_headers):
        spec = all_sfx_headers[name]
        base = name.removeprefix("SFX_")
        suffix = f"_{spec['engine']}"
        if base.endswith(suffix):
            base = base[:-len(suffix)]
        if base == "Headers" \
                or base.startswith(("Cry", "Noise_Instrument", "Unused")):
            continue
        sfx_headers.setdefault(base, spec)

    cry_headers = {}
    for number in range(0x26):
        name = f"SFX_Cry{number:02X}_1"
        if name in all_sfx_headers:
            cry_headers[str(number)] = all_sfx_headers[name]

    noise_headers = {}
    for engine in (1, 2, 3):
        per_engine = {}
        for number in range(1, 20):
            name = f"SFX_Noise_Instrument{number:02d}_{engine}"
            if name in all_sfx_headers:
                per_engine[str(number)] = all_sfx_headers[name]
        noise_headers[str(engine)] = per_engine

    map_song_consts = []
    path = os.path.join(pokered, "data/maps/songs.asm")
    for _, line in util.read_asm(path):
        match = re.match(r"db\s+(MUSIC_\w+),", line.strip())
        if match:
            map_song_consts.append(match.group(1))
    map_songs = {}
    for map_name, const_name in zip(map_order, map_song_consts):
        label = _music_label(const_name, music_headers)
        if label in music_headers:
            map_songs[map_name] = label

    cry_data = symbols["CryData"]
    wave_banks = {}
    for engine in (1, 2, 3):
        wave = symbols[f"Audio{engine}_WavePointers.wave0"]
        wave_banks[str(engine)] = {
            "bank": wave.bank,
            "address": wave.address,
        }

    return {
        "musicHeaders": music_headers,
        "sfxHeaders": sfx_headers,
        "cryHeaders": cry_headers,
        "noiseHeaders": noise_headers,
        "cryData": {
            "bank": cry_data.bank,
            "address": cry_data.address,
        },
        "waveBanks": wave_banks,
        "mapSongs": map_songs,
        "battle": {
            "wild": "Music_WildBattle",
            "trainer": "Music_TrainerBattle",
            "gym": "Music_GymLeaderBattle",
            "final": "Music_FinalBattle",
            "wildWin": "Music_DefeatedWildMon",
            "trainerWin": "Music_DefeatedTrainer",
            "gymWin": "Music_DefeatedGymLeader",
        },
    }


DIRECT_SYMBOLS = {
    "AttackAnimationPointers",
    "BadgeNumbersTileGraphics",
    "BaseStats",
    "BugIconFrame1",
    "BugIconFrame2",
    "CircleTile",
    "CryData",
    "DoorTileIDPointers",
    "EvosMovesPointerTable",
    "FlowerTile1",
    "FlowerTile2",
    "FlowerTile3",
    "FontGraphics",
    "FrameBlockBaseCoords",
    "FrameBlockPointers",
    "FossilAerodactylPic",
    "FossilKabutopsPic",
    "GhostPic",
    "GymLeaderFaceAndBadgeTileGraphics",
    "ItemNames",
    "ItemPrices",
    "KeyItemFlags",
    "MewBaseStats",
    "MonPartyData",
    "MonsterNames",
    "MonsterPalettes",
    "MoveNames",
    "MoveAnimationTiles0",
    "MoveAnimationTiles1",
    "MoveAnimationTiles2",
    "MoveAnimationTilesPointers",
    "MoveSoundTable",
    "Moves",
    "NothingWildMons",
    "OldManPicBack",
    "PlantIconFrame1",
    "PlantIconFrame2",
    "PokeballTileGraphics",
    "PokedexEntryPointers",
    "PokedexTileGraphics",
    "QuadrupedIconFrame1",
    "QuadrupedIconFrame2",
    "RedBikeSprite",
    "RedPicBack",
    "RedPicFront",
    "SnakeIconFrame1",
    "SnakeIconFrame2",
    "SpinnerArrowAnimTiles",
    "SpriteSheetPointerTable",
    "SubanimationPointers",
    "SuperPalettes",
    "TechnicalMachinePrices",
    "TextBoxGraphics",
    "Tilesets",
    "TrainerAI",
    "TrainerClassMoveChoiceModifications",
    "TrainerDataPointers",
    "TrainerInfoTextBoxTileGraphics",
    "TrainerNames",
    "TrainerPicAndMoneyPointers",
    "TypeEffects",
    "WarpTileIDPointers",
    "WildDataPointers",
}

FIELD_ASSET_SYMBOLS = {
    "BattleHudTiles1",
    "BattleHudTiles2",
    "BattleHudTiles3",
    "BattleTransitionTile",
    "FallingStar",
    "FightIntroBackMon",
    "FightIntroFrontMon",
    "FightIntroFrontMon2",
    "FightIntroFrontMon3",
    "GameBoyTiles",
    "GameFreakIntro",
    "GameFreakLogoGraphics",
    "GengarIntroTiles1",
    "GengarIntroTiles2",
    "GengarIntroTiles3",
    "HappyEmote",
    "HpBarAndStatusGraphics",
    "LedgeHoppingShadow",
    "LinkCableTiles",
    "MoveAnimationTiles1",
    "NintendoCopyrightLogoGraphics",
    "PlayerCharacterTitleGraphics",
    "PokeCenterFlashingMonitorAndHealBall",
    "PokemonLogoGraphics",
    "QuestionEmote",
    "RedFishingRodTiles",
    "RedFishingTilesBack",
    "RedFishingTilesFront",
    "RedFishingTilesSide",
    "SSAnneSmokePuffTile",
    "ShockEmote",
    "ShrinkPic1",
    "ShrinkPic2",
    "SlotMachineTiles1",
    "SlotMachineTiles2",
    "TheEndGfx",
    "TownMapCursor",
    "TradeBubbleIconGFX",
    "TradingAnimationGraphics",
    "TradingAnimationGraphics2",
    "Version_GFX",
    "WorldMapTileGraphics",
}


def embedded_symbols(data, symbols):
    """Return only addresses consumed by the ROM-backed extractor."""
    names = set(DIRECT_SYMBOLS | FIELD_ASSET_SYMBOLS)
    names.update(
        spec["label"] + "_h" for spec in data["maps"].values())
    names.update(data["typeNameLabels"])
    names.update(data["text"]["labels"])
    for spec in data["pokemonAssets"].values():
        for key in ("frontLabel", "backLabel"):
            if spec.get(key):
                names.add(spec[key])
    for spec in data["trainerPics"]:
        if spec:
            names.add(spec["label"])

    missing = sorted(name for name in names if name not in symbols.by_name)
    if missing:
        raise ValueError(
            "required symbols are missing: " + ", ".join(missing))
    return {
        name: [symbols[name].bank, symbols[name].address]
        for name in sorted(names)
    }


# Trainer parties this project reimplements that have no data to extract:
# CeladonChiefHouse's CHIEF is a talk-only NPC in the ROM (the Celadon Chief
# battle is unused/cut content -- pokered's data/trainers/parties.asm has
# `ChiefData:` followed by `; none`, zero Pokemon).  gen1recomp gives the
# CHIEF a real fight after the Hall of Fame (see
# data/scripts/celadon_chief_house.lua and src/import/RomExtractor.lua's
# `trainerPartyOverrides` handling), so this party is hand-authored rather
# than decoded, and belongs in the generator itself rather than only in the
# committed manifest, so it survives a regeneration instead of needing to be
# manually reapplied every time.
TRAINER_PARTY_OVERRIDES = {
    "OPP_CHIEF": [
        {"species": "MACHOKE", "level": 41},
        {"species": "GOLBAT", "level": 41},
        {"species": "MAROWAK", "level": 43},
        {"species": "WEEZING", "level": 43},
        {"species": "PERSIAN", "level": 46},
    ],
}


def apply_known_nonreproducible_overrides(texts, field_data):
    """Pin a handful of fields a fresh extraction gets right but that this
    manifest hasn't shipped, or gets differently than what's shipped, and
    that nobody has verified in-game yet. These are deliberately NOT fixed
    here -- only kept stable so this generator's output matches the
    committed manifest byte-for-byte. Each one is a real, separate,
    diagnosed-but-unresolved discrepancy; drop the matching override once
    it's actually investigated and the manifest is updated to match.
    """
    # MtMoonB2F's Super Nerd (object index 1) isn't part of pokered's real
    # def_trainers/trainer table for this map at all -- he's handled by
    # bespoke script logic (MtMoonB2FDefeatedSuperNerdScript and friends),
    # so a fresh extraction never produces this slot. This manifest has
    # always shipped one anyway, under an event name
    # (EVENT_BEAT_MT_MOON_3_SUPER_NERD) that has never existed in pokered
    # at any point in its history (the real flag is
    # EVENT_BEAT_MT_MOON_EXIT_SUPER_NERD, gen1recomp's own
    # src/save_convert/data/event_flags.lua flag 1401) -- fabricated data,
    # not pokered drift. OverworldState:trainerDefeated() checks
    # Game.save.defeatedTrainers[npc.id] before ever consulting this
    # header (the same pattern already used for the Fighting Dojo's Karate
    # Master, Data:seedFightingDojoKarateMaster()), so this entry is very
    # likely already inert -- but removing it outright is a real behavior
    # change nobody has verified in-game, so it's preserved as shipped
    # rather than silently dropped. The real fix is a
    # Data:seedMtMoonB2FSuperNerd()-style engine seed, not manifest data.
    texts["trainerHeaders"].setdefault("MtMoonB2F", {})[1] = {
        "after": "_MtMoonB2FSuperNerdTheresAPokemonLabText",
        "battle": "_MtMoonB2FSuperNerdTheyreBothMineText",
        "event": "EVENT_BEAT_MT_MOON_3_SUPER_NERD",
        "won": "_MtMoonB2FSuperNerdOkIllShareText",
    }

    # Seafoam Islands B3F's cross-floor boulder-toggle IDs (which B3F
    # object shows/hides when a boulder falls in from B2F above) come out
    # of a fresh extraction as TOGGLE_SEAFOAM_ISLANDS_B3F_BOULDER_3/_4;
    # this manifest has always shipped _5/_6 instead. Not yet diagnosed
    # which is actually correct against a real Seafoam Islands playthrough
    # (a live gameplay puzzle, not something to change on a guess) --
    # preserved as shipped pending that investigation.
    plugged = (
        field_data["seafoam"]["SEAFOAM_ISLANDS_B3F"]["pluggedByHolesOn"])
    plugged["holes"][0]["showObject"] = "TOGGLE_SEAFOAM_ISLANDS_B3F_BOULDER_5"
    plugged["holes"][1]["showObject"] = "TOGGLE_SEAFOAM_ISLANDS_B3F_BOULDER_6"

    # tradeArt is new content the current extractor can already produce
    # (trade-animation sprite sheets) but that this manifest has never
    # shipped -- no engine feature consumes it yet. Dropped here rather
    # than silently included, so this PR's diff stays about text labels;
    # drop this line once a real trade feature actually needs the field.
    field_data.pop("tradeArt", None)


def generate(pokered, symbols_path):
    symbols = SymbolTable(symbols_path)
    map_order, map_dims = constants.extract_map_constants(pokered)
    tilesets = [
        n for n in simple_constants(
            pokered, "constants/tileset_constants.asm") if n
    ]
    sprites = simple_constants(pokered, "constants/sprite_constants.asm")
    species = simple_constants(pokered, "constants/pokemon_constants.asm")
    moves = simple_constants(
        pokered, "constants/move_constants.asm", stop_at="NUM_ATTACKS")
    types = constants.extract_types(pokered)

    # Named elevator floors follow the 83 inventory items in the same
    # ItemNames/ItemPrices tables. Machine IDs live later at $C4+ and are
    # represented separately below.
    item_order = simple_constants(
        pokered, "constants/item_constants.asm")[1:]
    # parse_const_block sees the `const HM_\1` macro body as a literal
    # pseudo-entry; everything before it is the real contiguous name table.
    item_order = item_order[:item_order.index("HM_")]
    hms, tms = items.parse_machines(pokered)
    effects = simple_constants(
        pokered, "constants/move_effect_constants.asm")
    trainer_order = [
        name for name in trainers.parse_trainer_consts(pokered)
        if name and name != "NOBODY"
    ]
    dex_order = [
        name.removeprefix("DEX_")
        for name in simple_constants(
            pokered, "constants/pokedex_constants.asm")
        if name
    ]
    pokemon_assets, growth_rates = pokemon_metadata(pokered, dex_order)
    palette_order = [
        name.removeprefix("PAL_")
        for name in simple_constants(
            pokered, "constants/palette_constants.asm")
        if name and name.startswith("PAL_")
    ]
    icon_order = [
        name.removeprefix("ICON_")
        for name in simple_constants(
            pokered, "constants/icon_constants.asm")
        if name and name.startswith("ICON_")
    ][:10]
    tile_animations = [
        name or "UNUSED"
        for name in simple_constants(
            pokered, "constants/map_data_constants.asm")
        if name and name.startswith("TILEANIM_")
    ]

    constants_data = {
        "source": "ROM metadata manifest",
        "mapOrder": map_order,
        "maps": map_dims,
        "tilesetOrder": tilesets,
        "spriteOrder": [n or "UNUSED" for n in sprites[1:]],
        "speciesOrder": [n or "UNUSED" for n in species[1:]],
        "moveOrder": [n or "UNUSED" for n in moves[1:]],
        "types": types,
    }

    type_name_labels = [
        symbol.name for symbol in symbols.prefixed("TypeNames.")
    ]
    dex_entries = pokemon.parse_dex_entries(
        pokered, constants_data["speciesOrder"])
    texts = text_metadata(pokered)
    field_data = field_metadata(pokered)
    apply_known_nonreproducible_overrides(texts, field_data)
    audio_data = audio_metadata(pokered, symbols, map_order)

    data = {
        "format": 2,
        "romSha1": CANONICAL_RED_SHA1,
        "constants": constants_data,
        "charmap": charmap(pokered),
        "moveEffects": [name or "UNUSED" for name in effects],
        "items": item_order,
        "numItems": 83,
        "hms": hms,
        "tms": tms,
        "trainers": trainer_order,
        "trainerPics": trainer_pic_metadata(pokered),
        "dexOrder": dex_order,
        "pokemonAssets": pokemon_assets,
        "growthRates": growth_rates,
        "tmhmMoves": tms + hms,
        "paletteOrder": palette_order,
        "iconOrder": icon_order,
        "maps": map_metadata(pokered, map_dims),
        "tilesets": tileset_metadata(pokered, tilesets),
        "tileAnimations": tile_animations,
        "sprites": sprite_metadata(
            pokered, [name or "UNUSED" for name in sprites[1:]]),
        "fontCharmap": font.parse_charmap(pokered),
        "sfxKeys": sfx_keys(pokered, symbols),
        "typeNameLabels": type_name_labels,
        "dexEntryLabels": {
            species: entry.get("text")
            for species, entry in dex_entries.items()
            if entry.get("text")
        },
        "text": texts,
        "field": field_data,
        "audio": audio_data,
        "battleAnimations": battle_animation_metadata(pokered),
        "trainerPartyOverrides": TRAINER_PARTY_OVERRIDES,
    }
    data["symbols"] = embedded_symbols(data, symbols)
    return data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pokered", required=True)
    parser.add_argument("--symbols", required=True)
    parser.add_argument(
        "--out",
        default=os.path.join(os.path.dirname(__file__), "rom_manifest.json"))
    parser.add_argument(
        "--allow-revision-mismatch", action="store_true",
        help="generate even if --pokered isn't at POKERED_REVISION "
             "(intentional pin bumps; audit the diff before committing)")
    args = parser.parse_args()

    pokered = os.path.abspath(args.pokered)
    if not os.path.isfile(os.path.join(pokered, "main.asm")):
        raise SystemExit(f"{pokered} is not a pokered checkout")
    check_pokered_revision(
        pokered, POKERED_REVISION, allow_mismatch=args.allow_revision_mismatch)
    data = generate(pokered, os.path.abspath(args.symbols))
    with open(args.out, "w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, ensure_ascii=True, indent=2, sort_keys=True)
        f.write("\n")
    print(f"wrote {args.out}")


if __name__ == "__main__":
    main()
