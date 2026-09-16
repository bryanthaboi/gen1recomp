#!/usr/bin/env python3
"""Emit src/save_convert/Gen2Layout.lua from a pret build's symbol files.

Gen 2 saves a contiguous WRAM block into SRAM bank 1, so every field's file
offset inside the 32768-byte battery image is

    sPlayerData_offset + (wField - wPlayerData)

with sPlayerData_offset = sPlayerData - $A000 + $2000.  That relation is
asserted below against sPokemonData, which appears on both sides.

Nothing here is transcribed.  Build pret/pokegold and pret/pokecrystal, then:

    python3 tools/gen2_sram_offsets.py \
        --gold  path/to/pokegold.sym \
        --crystal path/to/pokecrystal.sym \
        --charmap path/to/pokegold/constants/charmap.asm \
        --gold-scenes path/to/pokegold/data/maps/scenes.asm \
        --crystal-scenes path/to/pokecrystal/data/maps/scenes.asm \
        > src/save_convert/Gen2Layout.lua

Gold and Silver share a layout (pokesilver.sym agrees byte-exact); Crystal does
not, and that is the whole reason this file emits two tables.
"""
import argparse, re, sys

FIELDS = [
    "wPlayerName", "wPlayerID", "wMoney", "wCoins", "wBadges", "wKantoBadges",
    "wRivalName", "wMomsName", "wPartyCount", "wPartySpecies", "wPartyMons",
    "wPartyMonNicknames", "wPartyMonOTs", "wNumItems", "wItems", "wNumKeyItems",
    "wKeyItems", "wNumBalls", "wBalls", "wTMsHMs", "wPokedexCaught",
    "wPokedexSeen", "wCurBox", "wBoxNames", "wMapGroup", "wMapNumber",
    "wXCoord", "wYCoord", "wEventFlags", "wPlayerState",
    "wStatusFlags", "wStatusFlags2", "wPokegearFlags", "wVisitedSpawns",
    "wVariableSprites", "wGameTimeHours", "wGameTimeMinutes",
    # engine/menus/intro_menu.asm:28 _ResetWRAM, engine/overworld/player_object.asm:19
    "wRedsName", "wGreensName", "wSavedAtLeastOnce", "wSpawnAfterChampion",
    "wCenteredObject", "wPlayerStruct", "wMapObjects", "wNumPCItems",
    "wMomItemTriggerBalance", "wRoamMon1MapGroup", "wRoamMon2MapGroup",
    "wRoamMon3MapGroup", "wBestMagikarpLengthFeet", "wBestMagikarpLengthInches",
    "wMagikarpRecordHoldersName", "wDecoBed", "wDecoPoster", "wScreenSave",
]
GUARDS = ["sCheckValue1", "sCheckValue2", "sChecksum", "sGameData", "sGameDataEnd"]

# ram/sram.asm -- bank 0 labels, outside the copied WRAM block: file offset is
# bank * 0x2000 + (addr - $A000).
RAW_SRAM = ["sOptions", "sMysteryGiftUnlocked"]

# ram/sram.asm:138-144
SRAM_FIELDS = [("wPlayerGender", "sCrystalData", "wCrystalData")]

# The 14 archived PC boxes. Emitted as real per-box offsets, never a stride:
# boxes 1-7 live in SRAM bank 2 and 8-14 in bank 3, so the step from box 7 to
# box 8 is 0x620 rather than the 0x450 every other pair uses. Computing them
# from a uniform stride puts boxes 8-14 in the wrong place, and a real save
# then reports box counts like 243 and 196.
BOX_COUNT = 14


def load(path):
    out = {}
    for line in open(path):
        m = re.match(r"^(\w\w):(\w{4})\s+(\S+)\s*$", line)
        if m:
            out.setdefault(m.group(3), (int(m.group(1), 16), int(m.group(2), 16)))
    return out


# The backup copy the game falls back to when the primary checksum fails
# (TryLoadSaveFile -> VerifyBackupChecksum). Crystal's is contiguous and laid
# out exactly like the primary, so it is the same table shifted. Gold and
# Silver split theirs across three sections and are not derivable this way,
# which is why only Crystal gets one.
BACKUP_NEED = ["sBackupGameData", "sBackupGameDataEnd", "sBackupCheckValue1",
               "sBackupCheckValue2", "sBackupChecksum", "sGameData"]


def backup_delta(sym):
    if any(n not in sym for n in BACKUP_NEED):
        return None
    off = lambda n: sym[n][0] * 0x2000 + (sym[n][1] - 0xA000)
    return off("sBackupGameData") - off("sGameData")


def backup_table(sym, rows, label):
    if any(n not in sym for n in BACKUP_NEED):
        return None
    off = lambda n: sym[n][0] * 0x2000 + (sym[n][1] - 0xA000)
    # File offsets, not raw addresses: the backup lives in SRAM bank 0 and the
    # primary in bank 1, so an address-only delta is off by a bank.
    delta = backup_delta(sym)
    guards = {"sCheckValue1": off("sBackupCheckValue1"),
              "sCheckValue2": off("sBackupCheckValue2"),
              "sChecksum": off("sBackupChecksum"),
              "sGameData": off("sBackupGameData"),
              "sGameDataEnd": off("sBackupGameDataEnd")}
    absolute = {n for n, _, _ in SRAM_FIELDS} | set(RAW_SRAM)
    out = []
    for name, value in rows:
        if name in guards:
            out.append((name, guards[name]))
        elif name in absolute:
            out.append((name, value))
        else:
            out.append((name, value + delta))
    return out


def table(sym, label):
    need = ["sPlayerData", "wPlayerData", "sPokemonData", "wPokemonData"] + GUARDS
    missing = [n for n in need if n not in sym]
    if missing:
        sys.exit(f"{label}: symbol file is missing {missing}")
    base = sym["sPlayerData"][1] - 0xA000 + 0x2000
    anchor = sym["wPlayerData"][1]
    # The block relation, asserted rather than assumed.
    if sym["sPokemonData"][1] - sym["sPlayerData"][1] != \
       sym["wPokemonData"][1] - sym["wPlayerData"][1]:
        sys.exit(f"{label}: the WRAM block is not copied contiguously; "
                 "the offset relation this generator rests on does not hold")
    lo, hi = sym["sGameData"][1], sym["sGameDataEnd"][1]
    rows, skipped = [], []
    for g in GUARDS:
        rows.append((g, sym[g][1] - 0xA000 + 0x2000))
    for f in FIELDS:
        w = sym.get(f)
        if not w:
            skipped.append(f + " (absent)")
            continue
        # Only fields INSIDE the saved block are addressable this way. Crystal's
        # wPlayerGender sits before wPlayerData and belongs to sCrystalData, and
        # the naive subtraction gives a confident wrong answer for it.
        if not (lo <= w[1] - anchor + sym["sPlayerData"][1] < hi):
            skipped.append(f + " (outside sGameData..sGameDataEnd)")
            continue
        rows.append((f, base + (w[1] - anchor)))
    for name, sbase, wbase in SRAM_FIELDS:
        if name in sym and sbase in sym and wbase in sym:
            at = sym[sbase][0] * 0x2000 + (sym[sbase][1] - 0xA000)
            rows.append((name, at + (sym[name][1] - sym[wbase][1])))
    for name in RAW_SRAM:
        s = sym.get(name)
        if not s:
            sys.exit(f"{label}: {name} is missing from the symbol file")
        rows.append((name, s[0] * 0x2000 + (s[1] - 0xA000)))
    boxes = []
    for i in range(1, BOX_COUNT + 1):
        b = sym.get("sBox%d" % i)
        if not b:
            sys.exit("%s: sBox%d is missing" % (label, i))
        # General SRAM form, which the bank-1 arithmetic above is a case of:
        # file offset = bank * 0x2000 + (addr - $A000).
        boxes.append(b[0] * 0x2000 + (b[1] - 0xA000))
    return rows, skipped, boxes


SCENE_RE = re.compile(r"^\s*scene_var\s+(\w+),\s*(\w+)")


def scene_rows(sym, path, label):
    base = sym["sPlayerData"][1] - 0xA000 + 0x2000
    anchor = sym["wPlayerData"][1]
    lo, hi = sym["sGameData"][1], sym["sGameDataEnd"][1]
    out = []
    for line in open(path):
        m = SCENE_RE.match(line)
        if not m:
            continue
        mapId, var = m.group(1), m.group(2)
        w = sym.get(var)
        if not w:
            sys.exit(f"{label}: {var} for {mapId} is missing from the symbol file")
        if not (lo <= w[1] - anchor + sym["sPlayerData"][1] < hi):
            sys.exit(f"{label}: {var} is outside sGameData..sGameDataEnd")
        out.append((mapId, base + (w[1] - anchor)))
    if not out:
        sys.exit(f"{label}: no scene_var rows in {path}")
    return out


def print_scenes(rows, indent):
    print(f"{indent}sceneVars = {{")
    for mapId, off in rows:
        print(f"{indent}  {mapId} = 0x{off:04X},")
    print(f"{indent}}},")


# The cart's own text table, so a name with an apostrophe, an accent or the PK
# glyph in it survives the round trip. Hand-keeping this list is how a player
# called "Mattia<PK>" comes back as "Mattia?".
CHARMAP_RE = re.compile(r'^\s*charmap\s+"(.+?)",\s*\$([0-9a-fA-F]{2})\s*(?:;.*)?$')


def emit_charmap(path):
    rows = {}
    for line in open(path, encoding="utf-8"):
        m = CHARMAP_RE.match(line)
        if not m:
            continue
        glyph, code = m.group(1), int(m.group(2), 16)
        # Control tokens are not text; the name fields never contain them.
        if glyph.startswith("<") and glyph.endswith(">"):
            inner = glyph[1:-1]
            if inner in ("PK", "MN", "PO", "KE"):
                rows.setdefault(code, inner)
            continue
        rows.setdefault(code, glyph)
    print("Gen2Layout.charmap = {")
    for code in sorted(rows):
        glyph = rows[code].replace("\\", "\\\\").replace('"', '\\"')
        print(f'  [0x{code:02X}] = "{glyph}",')
    print("}")
    print()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--gold", required=True)
    ap.add_argument("--crystal", required=True)
    ap.add_argument("--charmap", required=False,
                    help="path to pokegold constants/charmap.asm; emits the "
                         "text table too when given")
    ap.add_argument("--gold-scenes", required=False,
                    help="path to pokegold data/maps/scenes.asm; emits the "
                         "w<Map>SceneID offsets when given")
    ap.add_argument("--crystal-scenes", required=False,
                    help="path to pokecrystal data/maps/scenes.asm")
    a = ap.parse_args()
    print("-- GENERATED by tools/gen2_sram_offsets.py. Do not edit by hand.")
    print("-- Regenerate from a pret/pokegold + pret/pokecrystal build; see that")
    print("-- script's header for the derivation and the assertion behind it.")
    print("local Gen2Layout = {}\n")
    for key, path, scenesPath in (("goldSilver", a.gold, a.gold_scenes),
                                  ("crystal", a.crystal, a.crystal_scenes)):
        sym = load(path)
        rows, skipped, boxes = table(sym, key)
        backup = backup_table(sym, rows, key)
        scenes = scene_rows(sym, scenesPath, key) if scenesPath else None
        print(f"Gen2Layout.{key} = {{")
        for n, off in rows:
            print(f"  {n} = 0x{off:04X},")
        print("  -- The 14 archived boxes, listed rather than strided (see BOX_COUNT).")
        print("  boxes = { " + ", ".join("0x%04X" % b for b in boxes) + " },")
        if scenes:
            print_scenes(scenes, "  ")
        if backup:
            print("  -- The backup copy the game falls back to when the primary")
            print("  -- checksum fails. Same shape, shifted.")
            print("  backup = {")
            for n, off in backup:
                print(f"    {n} = 0x{off:04X},")
            print("    boxes = { " + ", ".join("0x%04X" % b for b in boxes) + " },")
            if scenes:
                delta = backup_delta(sym)
                print_scenes([(m, off + delta) for m, off in scenes], "    ")
            print("  },")
        print("}")
        for s2 in skipped:
            print(f"-- not addressable via the block: {s2}")
        print()
    if a.charmap:
        emit_charmap(a.charmap)
    print("return Gen2Layout")


main()
