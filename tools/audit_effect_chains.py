#!/usr/bin/env python3
# data/moves/effects.asm, data/moves/effects_pointers.asm,
# constants/move_effect_constants.asm

import argparse
import os
import re
import sys

CONST_RE = re.compile(r"^\s*const\s+(EFFECT_[A-Z0-9_]+)")
POINTER_RE = re.compile(r"^\s*dw\s+([A-Za-z_][A-Za-z0-9_]*)")
LABEL_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*):")
CMD_RE = re.compile(r"^\s+([a-z][a-z0-9_]*)\b")


def read_lines(path):
    with open(path, encoding="utf-8") as handle:
        return handle.read().splitlines()


def effect_constants(pret):
    names = []
    for line in read_lines(os.path.join(pret, "constants", "move_effect_constants.asm")):
        match = CONST_RE.match(line)
        if match:
            names.append(match.group(1))
    return names


def effect_pointers(pret):
    labels = []
    for line in read_lines(os.path.join(pret, "data", "moves", "effects_pointers.asm")):
        match = POINTER_RE.match(line)
        if match:
            labels.append(match.group(1))
    return labels


def effect_chains(pret):
    chains = {}
    lines = {}
    current = []
    for number, raw in enumerate(read_lines(os.path.join(pret, "data", "moves", "effects.asm")), 1):
        line = raw.split(";", 1)[0].rstrip()
        if not line.strip():
            continue
        label = LABEL_RE.match(line)
        if label:
            name = label.group(1)
            if current and chains[current[-1]]:
                current = []
            current.append(name)
            chains.setdefault(name, [])
            lines.setdefault(name, number)
            continue
        cmd = CMD_RE.match(line)
        if cmd and current:
            for name in current:
                chains[name].append(cmd.group(1))
    return chains, lines


def audit(pret):
    consts = effect_constants(pret)
    pointers = effect_pointers(pret)
    chains, lines = effect_chains(pret)
    if len(consts) != len(pointers):
        sys.exit("%s: %d constants vs %d pointers" % (pret, len(consts), len(pointers)))
    rows = []
    for effect, label in zip(consts, pointers):
        commands = chains.get(label)
        if commands is None:
            sys.exit("%s: no chain for %s" % (pret, label))
        rows.append((effect, label, commands, lines[label]))
    return rows


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("pret", nargs="*", default=["../pokecrystal", "../pokegold"])
    parser.add_argument("--lua", action="store_true")
    parser.add_argument("--all", action="store_true")
    args = parser.parse_args()

    per_tree = {}
    for pret in args.pret:
        per_tree[pret] = audit(pret)

    trees = list(per_tree)
    first = per_tree[trees[0]]
    no_checkhit = [row for row in first if "checkhit" not in row[2]]

    for pret in trees[1:]:
        other = {row[0]: row[2] for row in per_tree[pret]}
        for effect, _, commands, _ in first:
            if effect not in other:
                print("%s lacks %s" % (pret, effect), file=sys.stderr)
            elif ("checkhit" in commands) != ("checkhit" in other[effect]):
                print("%s disagrees on checkhit for %s" % (pret, effect), file=sys.stderr)

    if args.lua:
        print("{")
        for effect, _, _, line in no_checkhit:
            print("  %s = true, -- data/moves/effects.asm:%d" % (effect, line))
        print("}")
        return

    rows = first if args.all else no_checkhit
    for effect, label, commands, line in rows:
        gate = "checkhit" if "checkhit" in commands else "NO_CHECKHIT"
        print("%-32s %-28s %5d %s" % (effect, label, line, gate))
    print("%d of %d effect chains have no checkhit" % (len(no_checkhit), len(first)),
          file=sys.stderr)


if __name__ == "__main__":
    main()
