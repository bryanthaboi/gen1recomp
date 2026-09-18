#!/usr/bin/env python3
import argparse
import json
import os
import re
import sys

ROM_BASE = 0x08000000
DEFAULT_PRET = os.path.expanduser("~/Documents/development/pokefirered")
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VERSIONS = os.path.join(REPO, "src", "import", "gba", "versions.lua")
MOVES_TABLE = 0x1C68F4

OPCODES = {
    "loadspritegfx": 0x00, "unloadspritegfx": 0x01, "createsprite": 0x02,
    "createvisualtask": 0x03, "delay": 0x04, "waitforvisualfinish": 0x05,
    "nop": 0x06, "nop2": 0x07, "end": 0x08, "playse": 0x09, "monbg": 0x0A,
    "clearmonbg": 0x0B, "setalpha": 0x0C, "blendoff": 0x0D, "call": 0x0E,
    "return": 0x0F, "setarg": 0x10, "choosetwoturnanim": 0x11,
    "jumpifmoveturn": 0x12, "goto": 0x13, "fadetobg": 0x14, "restorebg": 0x15,
    "waitbgfadeout": 0x16, "waitbgfadein": 0x17, "changebg": 0x18,
    "playsewithpan": 0x19, "setpan": 0x1A, "panse": 0x1B,
    "loopsewithpan": 0x1C, "waitplaysewithpan": 0x1D, "setbldcnt": 0x1E,
    "createsoundtask": 0x1F, "waitsound": 0x20, "jumpargeq": 0x21,
    "monbg_static": 0x22, "clearmonbg_static": 0x23, "jumpifcontest": 0x24,
    "fadetobgfromset": 0x25, "panse_adjustnone": 0x26, "panse_adjustall": 0x27,
    "splitbgprio": 0x28, "splitbgprio_all": 0x29, "splitbgprio_foes": 0x2A,
    "invisible": 0x2B, "visible": 0x2C, "teamattack_moveback": 0x2D,
    "teamattack_movefwd": 0x2E, "stopsound": 0x2F,
}

FIXED = {
    0x00: 3, 0x01: 3, 0x04: 2, 0x05: 1, 0x06: 1, 0x07: 1, 0x08: 1, 0x09: 3,
    0x0A: 2, 0x0B: 2, 0x0C: 3, 0x0D: 1, 0x0E: 5, 0x0F: 1, 0x10: 4, 0x11: 9,
    0x12: 6, 0x13: 5, 0x14: 2, 0x15: 1, 0x16: 1, 0x17: 1, 0x18: 2, 0x19: 4,
    0x1A: 2, 0x1B: 7, 0x1C: 6, 0x1D: 5, 0x1E: 3, 0x20: 1, 0x21: 8, 0x22: 2,
    0x23: 2, 0x24: 5, 0x25: 4, 0x26: 7, 0x27: 7, 0x28: 2, 0x29: 1, 0x2A: 2,
    0x2B: 2, 0x2C: 2, 0x2D: 2, 0x2E: 2, 0x2F: 1,
}

TABLES = [
    ("moves", "gBattleAnims_Moves"),
    ("status", "gBattleAnims_StatusConditions"),
    ("general", "gBattleAnims_General"),
    ("special", "gBattleAnims_Special"),
]


def split_args(s):
    out, depth, cur = [], 0, ""
    for ch in s:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
        if ch == "," and depth == 0:
            out.append(cur.strip())
            cur = ""
        else:
            cur += ch
    if cur.strip():
        out.append(cur.strip())
    return out


def parse_scripts(path, revision=0):
    stream, labels, tables = [], {}, {}
    cur_table = None
    cond = []
    with open(path) as f:
        lines = f.readlines()
    for lineno, raw in enumerate(lines, 1):
        line = raw.split("@", 1)[0].rstrip()
        comment = raw.split("@", 1)[1].strip() if "@" in raw else ""
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        m = re.match(r"^\.if\s+REVISION\s*>=\s*(\S+)$", s)
        if m:
            cond.append(revision >= int(m.group(1), 0))
            continue
        if s == ".else":
            cond[-1] = not cond[-1]
            continue
        if s == ".endif":
            cond.pop()
            continue
        if cond and not all(cond):
            continue
        m = re.match(r"^(\w+)\s*::?\s*$", s)
        if m:
            name = m.group(1)
            if name.startswith("gBattleAnims_"):
                cur_table = name
                tables[name] = []
            else:
                cur_table = None
                labels[name] = len(stream)
            continue
        if s.startswith("."):
            if s.startswith(".4byte") and cur_table:
                tables[cur_table].append((s.split(None, 1)[1].strip(), comment))
            elif s.startswith(".align") or s.startswith(".2byte") or s.startswith(".include") or s.startswith(".section"):
                pass
            else:
                raise SystemExit("unhandled directive %s:%d %s" % (path, lineno, s))
            continue
        parts = s.split(None, 1)
        mnem = parts[0]
        args = split_args(parts[1]) if len(parts) > 1 else []
        if mnem == "jumpreteq":
            mnem, args = "jumpargeq", ["ARG_RET_ID", args[0], args[1]]
        elif mnem == "jumprettrue":
            mnem, args = "jumpargeq", ["ARG_RET_ID", "TRUE", args[0]]
        elif mnem == "jumpretfalse":
            mnem, args = "jumpargeq", ["ARG_RET_ID", "FALSE", args[0]]
        if mnem not in OPCODES:
            raise SystemExit("unknown mnemonic %s:%d %s" % (path, lineno, mnem))
        stream.append({"m": mnem, "a": args, "line": lineno})
    return stream, labels, tables


class Rom:
    def __init__(self, path):
        with open(path, "rb") as f:
            self.b = f.read()

    def u8(self, o):
        return self.b[o]

    def u16(self, o):
        return self.b[o] | (self.b[o + 1] << 8)

    def u32(self, o):
        return self.u16(o) | (self.u16(o + 2) << 16)

    def off(self, ptr):
        o = ptr - ROM_BASE
        if 0 <= o < len(self.b):
            return o
        return None


def rom_len(rom, o):
    op = rom.u8(o)
    if op in (0x02, 0x03):
        return 7 + rom.u8(o + 6) * 2
    if op == 0x1F:
        return 6 + rom.u8(o + 5) * 2
    if op not in FIXED:
        raise ValueError("bad opcode 0x%02X at 0x%X" % (op, o))
    return FIXED[op]


def align(rom, stream, labels, tables, table_addrs):
    templates, tasks, soundtasks, errors = {}, {}, {}, []
    seen = {}
    work = []
    seg = {}
    roots = []
    for key, tname in TABLES:
        base = table_addrs[key]
        for i, (lab, _) in enumerate(tables[tname]):
            ptr = rom.u32(base + i * 4)
            o = rom.off(ptr)
            if o is None:
                errors.append("%s[%d] bad ptr 0x%08X" % (tname, i, ptr))
                continue
            if lab not in labels:
                if lab == "Move_COUNT":
                    continue
                errors.append("missing label %s" % lab)
                continue
            work.append((o, labels[lab], "%s:%d" % (key, i), lab))
            roots.append(("%s:%d" % (key, i), o))

    def pair(store, addr, name, where):
        prev = store.get(addr)
        if prev and prev != name:
            errors.append("addr 0x%08X named %s and %s (%s)" % (addr, prev, name, where))
        store[addr] = name

    def branch(ptr, lab, owner, where, src):
        o = rom.off(ptr)
        if o is None or lab not in labels:
            errors.append("bad branch %s -> %s at %s" % (lab, hex(ptr), where))
            return
        seg[src]["succ"].append(o)
        work.append((o, labels[lab], owner, lab))

    while work:
        o, idx, owner, lab = work.pop()
        key = o
        if key in seen:
            if seen[key][0] != idx:
                errors.append("rom 0x%X reached as %s and stream %d" % (o, lab, seen[key][0]))
            seen[key][1].add(owner)
            continue
        seen[key] = (idx, {owner})
        seg[o] = {"t": set(), "k": set(), "succ": []}
        pos = o
        while True:
            if idx >= len(stream):
                errors.append("ran off stream from %s" % lab)
                break
            cmd = stream[idx]
            want = OPCODES[cmd["m"]]
            op = rom.u8(pos)
            where = "%s line %d rom 0x%X" % (lab, cmd["line"], pos)
            if op != want:
                errors.append("opcode mismatch %s: rom 0x%02X pret %s" % (where, op, cmd["m"]))
                break
            a = cmd["a"]
            if op == 0x02:
                if rom.u8(pos + 6) != len(a) - 3:
                    errors.append("argc mismatch %s" % where)
                pair(templates, rom.u32(pos + 1), a[0], where)
                seg[o]["t"].add(a[0])
            elif op == 0x03:
                if rom.u8(pos + 6) != len(a) - 2:
                    errors.append("argc mismatch %s" % where)
                pair(tasks, rom.u32(pos + 1), a[0], where)
                seg[o]["k"].add(a[0])
            elif op == 0x1F:
                if rom.u8(pos + 5) != len(a) - 1:
                    errors.append("argc mismatch %s" % where)
                pair(soundtasks, rom.u32(pos + 1), a[0], where)
                seg[o]["k"].add(a[0])
            elif op == 0x04 and re.match(r"^-?\d+$", a[0]):
                if rom.u8(pos + 1) != int(a[0]) & 0xFF:
                    errors.append("delay mismatch %s" % where)
            elif op in (0x0E, 0x13, 0x24):
                branch(rom.u32(pos + 1), a[0], owner, where, o)
            elif op == 0x21:
                branch(rom.u32(pos + 4), a[2], owner, where, o)
            elif op == 0x12:
                branch(rom.u32(pos + 2), a[1], owner, where, o)
            elif op == 0x11:
                branch(rom.u32(pos + 1), a[0], owner, where, o)
                branch(rom.u32(pos + 5), a[1], owner, where, o)
            if op in (0x08, 0x0F, 0x13):
                break
            pos += rom_len(rom, pos)
            idx += 1
    usage_t, usage_k = {}, {}
    for owner, r in roots:
        stack, vis = [r], set()
        while stack:
            x = stack.pop()
            if x in vis or x not in seg:
                continue
            vis.add(x)
            for t in seg[x]["t"]:
                usage_t.setdefault(t, set()).add(owner)
            for k in seg[x]["k"]:
                usage_k.setdefault(k, set()).add(owner)
            stack.extend(seg[x]["succ"])
    return templates, tasks, soundtasks, errors, seen, usage_t, usage_k


def find_template_defs(pret):
    defs = {}
    srcdir = os.path.join(pret, "src")
    for fn in sorted(os.listdir(srcdir)):
        if not fn.endswith(".c"):
            continue
        text = open(os.path.join(srcdir, fn)).read()
        for m in re.finditer(r"SpriteTemplate\s+(\w+)\s*=\s*\{(.*?)\};", text, re.S):
            body = m.group(2)
            cb = re.search(r"\.callback\s*=\s*(\w+)", body)
            tile = re.search(r"\.tileTag\s*=\s*(\w+)", body)
            if not cb:
                fields = split_args(re.sub(r"/\*.*?\*/|//[^\n]*", "", body, flags=re.S))
                cbname = fields[6].strip() if len(fields) >= 7 else None
                tilename = fields[0].strip() if fields else None
            else:
                cbname = cb.group(1)
                tilename = tile.group(1) if tile else None
            line = text.count("\n", 0, m.start()) + 1
            defs[m.group(1)] = {"callback": cbname, "tileTag": tilename, "file": "src/" + fn, "line": line}
    return defs


def find_func_defs(pret, names):
    out = {}
    srcdir = os.path.join(pret, "src")
    want = set(names)
    for fn in sorted(os.listdir(srcdir)):
        if not fn.endswith(".c"):
            continue
        lines = open(os.path.join(srcdir, fn)).read().split("\n")
        for i, l in enumerate(lines):
            m = re.match(r"^(?:static\s+)?(?:void|u8|bool8|u16|s16)\s+(\w+)\s*\(([^;]*)$", l)
            if m and m.group(1) in want and m.group(1) not in out:
                nxt = lines[i + 1].strip() if i + 1 < len(lines) else ""
                if l.rstrip().endswith("{") or nxt.startswith("{"):
                    out[m.group(1)] = "src/%s:%d" % (fn, i + 1)
    return out


def tag_values(pret):
    vals = {}
    for l in open(os.path.join(pret, "include", "constants", "battle_anim.h")):
        m = re.match(r"#define\s+(ANIM_TAG_\w+)\s+\(ANIM_SPRITES_START\s*\+\s*(\d+)\)", l)
        if m:
            vals[m.group(1)] = 10000 + int(m.group(2))
    vals["ANIM_TAG_NONE"] = 0
    vals["TAG_NONE"] = 0xFFFF
    return vals


def short_cb(n):
    if re.match(r"^Anim[A-Z]", n):
        return n[4:]
    return n


def short_task(n):
    if n.startswith("AnimTask_"):
        return n[len("AnimTask_"):]
    return n


def lua_table(name, d):
    rows = ["Versions.%s = {" % name]
    for k in sorted(d):
        rows.append('  [0x%08X] = "%s",' % (k, d[k]))
    rows.append("}")
    return "\n".join(rows)


def lua_names(name, lst):
    rows = ["Versions.%s = {" % name]
    for i, n in enumerate(lst):
        rows.append('  [%d] = "%s",' % (i, n))
    rows.append("}")
    return "\n".join(rows)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rom", required=True)
    ap.add_argument("--pret", default=DEFAULT_PRET)
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--json")
    args = ap.parse_args()

    rom = Rom(args.rom)
    stream, labels, tables = parse_scripts(os.path.join(args.pret, "data", "battle_anim_scripts.s"))

    addrs = {"moves": MOVES_TABLE}
    cur = MOVES_TABLE
    for key, tname in TABLES:
        addrs[key] = cur
        cur += 4 * len(tables[tname])

    templates, tasks, soundtasks, errors, seen, usage_t, usage_k = align(rom, stream, labels, tables, addrs)

    defs = find_template_defs(args.pret)
    tagv = tag_values(args.pret)
    callbacks = {}
    tmpl_info = {}
    for addr, tname in templates.items():
        d = defs.get(tname)
        if not d:
            errors.append("no C definition for %s" % tname)
            continue
        o = rom.off(addr)
        cbptr = rom.u32(o + 20)
        tile = rom.u16(o)
        if d["tileTag"] in tagv and tagv[d["tileTag"]] != tile:
            errors.append("tileTag mismatch %s rom %d pret %s" % (tname, tile, d["tileTag"]))
        prev = callbacks.get(cbptr)
        if prev and prev != d["callback"]:
            errors.append("callback 0x%08X named %s and %s" % (cbptr, prev, d["callback"]))
        callbacks[cbptr] = d["callback"]
        tmpl_info[tname] = {"addr": addr, "callback": d["callback"], "file": d["file"], "line": d["line"]}

    alltasks = dict(tasks)
    for k, v in soundtasks.items():
        if k in alltasks and alltasks[k] != v:
            errors.append("task/sound clash 0x%08X" % k)
        alltasks[k] = v

    def check_injective(d, fn, label):
        rev = {}
        for k, v in d.items():
            s = fn(v)
            if s in rev and rev[s] != v:
                errors.append("%s short-name collision %s: %s / %s" % (label, s, rev[s], v))
            rev[s] = v

    for lbl, d in (("template", templates), ("callback", callbacks), ("task", alltasks)):
        rev = {}
        for k, v in d.items():
            if v in rev and rev[v] != k:
                errors.append("%s %s at two addresses 0x%08X 0x%08X" % (lbl, v, rev[v], k))
            rev[v] = k
    check_injective(callbacks, short_cb, "callback")
    check_injective(alltasks, short_task, "task")

    for addr in list(callbacks) + list(alltasks):
        if addr & 1 == 0 or rom.off(addr) is None:
            errors.append("non-thumb/non-rom fn 0x%08X" % addr)

    names = {}
    for key, tname in TABLES:
        if key == "moves":
            continue
        lst = []
        for lab, comment in tables[tname]:
            m = re.match(r"B_ANIM_(\w+)", comment)
            if not m:
                errors.append("no B_ANIM_ comment for %s" % lab)
                lst.append(lab)
            else:
                lst.append(m.group(1))
        names[key] = lst

    funcs = find_func_defs(args.pret, list(callbacks.values()) + list(alltasks.values()))
    unnamed_cb = [a for a in callbacks if not callbacks[a]]
    missing_src = sorted(set(n for n in list(callbacks.values()) + list(alltasks.values()) if n not in funcs))

    print("tables: moves=0x%X status=0x%X general=0x%X special=0x%X" % (
        addrs["moves"], addrs["status"], addrs["general"], addrs["special"]))
    print("counts: moves=%d status=%d general=%d special=%d" % tuple(
        len(tables[t]) for _, t in TABLES))
    print("script entry points aligned: %d" % len(seen))
    print("templates=%d callbacks=%d tasks=%d soundtasks=%d" % (
        len(templates), len(callbacks), len(tasks), len(soundtasks)))
    print("unnamed: templates=0 callbacks=%d tasks=0" % len(unnamed_cb))
    if missing_src:
        print("no C definition line found for: %s" % ", ".join(missing_src))
    if errors:
        print("ERRORS (%d):" % len(errors))
        for e in errors[:80]:
            print("  " + e)
        sys.exit(1)
    print("alignment OK, 0 errors")

    if args.json:
        owners_t = {k: sorted(v) for k, v in usage_t.items()}
        owners_k = {k: sorted(v) for k, v in usage_k.items()}
        with open(args.json, "w") as f:
            json.dump({
                "tables": addrs, "names": names, "templates": tmpl_info,
                "templateUsage": owners_t, "taskUsage": owners_k,
                "tasks": {("0x%08X" % k): v for k, v in alltasks.items()},
                "callbacks": {("0x%08X" % k): v for k, v in callbacks.items()},
                "funcDefs": funcs,
                "moveLabels": [lab for lab, _ in tables["gBattleAnims_Moves"]],
            }, f, indent=1, sort_keys=True)

    block = "\n\n".join([
        lua_table("ANIM_TEMPLATE_NAMES", templates),
        lua_table("ANIM_CALLBACK_NAMES", {k: short_cb(v) for k, v in callbacks.items()}),
        lua_table("ANIM_TASK_NAMES", {k: short_task(v) for k, v in alltasks.items()}),
        lua_names("BATTLE_ANIM_STATUS_NAMES", names["status"]),
        lua_names("BATTLE_ANIM_GENERAL_NAMES", names["general"]),
        lua_names("BATTLE_ANIM_SPECIAL_NAMES", names["special"]),
    ]) + "\n"

    if args.write:
        src = open(VERSIONS).read()
        start_marks = ["Versions.ANIM_TEMPLATE_NAMES = {\n", "Versions.ANIM_CALLBACK_NAMES = {\n"]
        start = -1
        for sm in start_marks:
            start = src.find(sm)
            if start >= 0:
                break
        end_mark = "\n-- Wild encounters (FireRed USA 1.0)"
        end = src.find(end_mark)
        assert start >= 0 and end > start, "versions.lua anchors not found"
        assert src.count(end_mark) == 1
        new = src[:start] + block + src[end:]
        with open(VERSIONS, "w") as f:
            f.write(new)
        print("wrote %s" % VERSIONS)
    else:
        sys.stdout.write(block)


if __name__ == "__main__":
    main()
