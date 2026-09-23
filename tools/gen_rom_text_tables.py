"""Generate src/import/gba/versions_text.lua from matching pret ELF symbols and sources."""
import os, re, subprocess, sys
from pathlib import Path

B = 0x8000000
ROOT = Path(__file__).resolve().parents[1]
pret = Path(sys.argv[1] if len(sys.argv) > 1 else ROOT.parent / "pokefirered")


def symbols(path):
    out = {}
    obj = ""
    for line in subprocess.check_output(["arm-none-eabi-readelf", "-sW", str(path)], text=True).splitlines():
        p = line.split()
        if len(p) < 8 or not p[0][:-1].isdigit():
            continue
        _, v, size, typ, bind, _vis, _ndx, name = p[:8]
        if typ == "FILE":
            obj = name
            continue
        a = int(v, 16)
        if typ in ("OBJECT", "NOTYPE") and not name.startswith(("$", ".")) and B <= a < B + 0x1000000:
            out.setdefault(name, []).append((obj if bind == "LOCAL" else "", a, int(size)))
    return out


fr = symbols(pret / "pokefirered.elf")
lg = symbols(pret / "pokeleafgreen.elf")


def unique(name):
    rows = fr.get(name) or []
    if len(rows) != 1:
        return None
    obj = rows[0][0]
    if not any(r[0] == obj for r in lg.get(name) or []):
        return None
    return rows[0]


STRLIT = r'"(?:[^"\\\n]|\\.)*"'
C_TEXT = re.compile(r"(?:const\s+u8|static\s+const\s+u8|u8\s+const)\s+(?:ALIGNED\(\d\)\s+)?(\w+)\s*\[\s*\]\s*=\s*_\(")
DENY = (
    "data/maps/", "src/data/pokemon/", "src/move_descriptions.c", "src/data/easy_chat/",
    "src/data/text/abilities.h", "src/data/text/nature_names.h", "src/data/items.h",
    "src/data/decoration/", "src/data/region_map/", "src/berry.c", "src/data/trainers.h",
    "src/trainer_tower_sets.c", "src/data/text/species_names.h", "src/data/text/move_names.h",
    "src/data/text/trainer_class_names.h",
)

sources = {}
for root, _dirs, files in os.walk(pret):
    if "/.git" in root or "/tools" in root or "/build" in root:
        continue
    for f in files:
        path = os.path.join(root, f)
        rel = os.path.relpath(path, pret)
        if rel.startswith(DENY):
            continue
        if f.endswith((".c", ".h")) and rel.startswith("src"):
            body = open(path, encoding="utf-8", errors="replace").read()
            for m in C_TEXT.finditer(body):
                sources.setdefault(m.group(1), set()).add(rel)
        elif f.endswith((".inc", ".s")) and rel.startswith("data"):
            label = None
            for line in open(path, encoding="utf-8", errors="replace"):
                lm = re.match(r"^\s*(\w+)::?\s*$", line)
                if lm:
                    label = lm.group(1)
                    continue
                if label and re.match(r"^\s*\.string\s+" + STRLIT, line):
                    sources.setdefault(label, set()).add(rel)
                    label = None
                elif not re.match(r"^\s*$", line):
                    label = None

battle_names = set()
for rel in ("src/battle_message.c",):
    body = (pret / rel).read_text(encoding="utf-8", errors="replace")
    for m in C_TEXT.finditer(body):
        text = re.match(r"((?:\s*" + STRLIT + r")+)", body[m.end():])
        if text and "{B_" in text.group(1):
            battle_names.add(m.group(1))


def uses_battle_codes(name):
    return name in battle_names


named, battle, skipped = {}, {}, []
for name in sorted(sources):
    row = unique(name)
    if not row:
        skipped.append(name)
        continue
    target = battle if uses_battle_codes(name) else named
    target[name] = row[1] - B

POINTER_TABLE = re.compile(r"(?:static\s+)?const\s+u8\s*\*\s*const\s+(\w+)\s*\[[^\]\n]*\]\s*(\[[^\]\n]*\])?\s*=")
TABLE_DENY = {
    "gMonFootprintTable", "gItemEffectTable", "gMonIconTable", "gMoveDescriptionPointers",
    "gAbilityDescriptionPointers", "sMapNames", "gRegionMapEntries", "sPartyMenuActions",
    "sAcceptedActivityIds", "sKeyboardTextColors", "sTimeColonTextColors", "sMoveEffectBS_Ptrs",
    "sPlaceholderPlayerNames",
}
TABLE_SOURCES = []
for root, _dirs, files in os.walk(pret / "src"):
    for f in sorted(files):
        if f.endswith((".c", ".h")):
            TABLE_SOURCES.append(Path(root) / f)

tables = []
seen_tables = set()


def add_table(name, stride=4, inner=None, battle_table=False, inline=False):
    if name in seen_tables or name in TABLE_DENY:
        return
    row = unique(name)
    if not row or row[2] == 0:
        skipped.append(name)
        return
    seen_tables.add(name)
    size = row[2]
    if inner:
        count = size // (4 * inner)
        dims = (count, inner)
    else:
        count = size // stride
        dims = None
    tables.append({"name": name, "addr": row[1] - B, "count": count, "stride": stride,
                   "dims": dims, "battle": battle_table, "inline": inline})


for path in sorted(TABLE_SOURCES):
    rel = str(path.relative_to(pret))
    if rel.startswith(("src/data/pokemon", "src/data/region_map", "src/help_system")):
        continue
    body = path.read_text(encoding="utf-8", errors="replace")
    for m in POINTER_TABLE.finditer(body):
        inner = None
        if m.group(2):
            inner_txt = m.group(2).strip("[] ")
            if not inner_txt.isdigit():
                continue
            inner = int(inner_txt)
        add_table(m.group(1), inner=inner, battle_table=rel == "src/battle_message.c")

STRUCT_TABLES = [
    "sStartMenuActionTable", "sCursorOptions", "sMenuActions_TopMenu", "sMenuActions_ItemPc",
    "sMenuActions_MailSubmenu", "sItemPcSubmenuOptions", "sShopMenuActions_BuySellQuit",
    "sListMenuItems_KantoDexModeSelect", "sListMenuItems_NatDexModeSelect", "sLevelMenuItems",
    "sListMenuItems", "sListMenuItems_NoTMCase", "sKeyboardSwapTexts", "sMenuActions",
    "sItemMenuContextActions", "sListMenuItems_CardsOrNews", "sListMenuItems_WirelessOrFriend",
    "sListMenuItems_ReceiveSendToss", "sListMenuItems_ReceiveToss", "sListMenuItems_ReceiveSend",
    "sListMenuItems_Receive", "sContextMenuActions", "sMenuAction_SummaryTrade",
    "sListMenuItems_PossibleGroupMembers", "sListMenuItems_UnionRoomGroups",
    "sListMenuItems_InviteToActivity", "sListMenuItems_RegisterForTrade",
    "sListMenuItems_TypeNames", "sListMenuItems_TradeBoard",
]
for name in STRUCT_TABLES:
    add_table(name, stride=8)
add_table("gTrainerClassNames", stride=13, inline=True)
add_table("gTypeNames", stride=7, inline=True)

ids = {}
for line in (pret / "include/constants/battle_string_ids.h").read_text().splitlines():
    m = re.match(r"#define\s+(STRINGID_\w+)\s+(\d+)\s*$", line)
    if m and int(m.group(2)) < 386:
        ids.setdefault(int(m.group(2)), m.group(1))
for t in tables:
    if t["name"] == "gBattleStringsTable":
        t["ids"] = 12

lines = ["-- Generated by tools/gen_rom_text_tables.py from matching pret ELF symbols.",
         "return {"]


def block(title, table):
    lines.append(f"  {title} = {{")
    for name in sorted(table):
        lines.append(f"    {name} = 0x{table[name]:X},")
    lines.append("  },")


block("NAMED_TEXTS", named)
block("NAMED_BATTLE_TEXTS", battle)
lines.append("  TEXT_TABLES = {")
for t in sorted(tables, key=lambda r: r["name"]):
    parts = [f'name = "{t["name"]}"', f'addr = 0x{t["addr"]:X}', f'count = {t["count"]}',
             f'stride = {t["stride"]}']
    if t["dims"]:
        parts.append(f'inner = {t["dims"][1]}')
    if t["battle"]:
        parts.append("battle = true")
    if t["inline"]:
        parts.append("inline = true")
    if t.get("ids"):
        parts.append(f'ids = {t["ids"]}')
    lines.append("    { " + ", ".join(parts) + " },")
lines.append("  },")
lines.append("  BATTLE_STRING_IDS = {")
for i in sorted(ids):
    lines.append(f'    [{i}] = "{ids[i]}",')
lines.append("  },")
lines.append("}")
out = ROOT / "src/import/gba/versions_text.lua"
out.write_text("\n".join(lines) + "\n")
print(f"Wrote {len(named)} named, {len(battle)} battle, {len(tables)} tables, "
      f"{len(ids)} string ids to {out}; skipped {len(skipped)}")
if "-v" in sys.argv:
    print("skipped:", " ".join(sorted(set(skipped))))
