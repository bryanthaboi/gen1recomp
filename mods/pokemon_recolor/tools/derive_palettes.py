#!/usr/bin/env python3
"""Derive a four-shade Gen 3 colour ramp per species. Ships no pixels.

The Game Boy battle pic is already the right size, the right silhouette,
and already on the player's disk. All it lacks is colour. So rather than
importing Gen 3 sprites, import Gen 3 *palettes* -- four RGB triples per
species -- and let transforms.lua repaint the player's own art with them.

What ships is a Lua table of integers. No sprite, no byte of anybody's
cartridge art.

Two matchers, chosen per species in ramps.lua after reviewing all 151
by eye:

  histogram  walks the GB and Gen 3 cumulative colour distributions in
             step, so each GB tone lands on the Gen 3 colour holding the
             same tonal position, weighted by area.
  kmeans     clusters the Gen 3 colours by luminance and takes each
             cluster's most-used colour, which keeps two strong separated
             colours apart instead of averaging across their boundary.

Both then pass through separate() (four distinct steps) and stretch()
(rescaled onto the engine's near-white/near-black anchors, which is what
the hand-tuned GBC palettes rely on for readability at 40px).

Usage:
  derive_palettes.py GEN3_ROOT [--version red|blue|yellow] [--reset]

The game's data directory and the imported version are both found
automatically; --cache and --version override either.
"""

import argparse
import os
import re
import shutil
import subprocess
import sys

try:
    from PIL import Image
except ImportError:
    sys.exit("needs Pillow: python3 -m pip install --user Pillow")

MOD_ID = "pokemon_recolor"


def game_data_dir(repo_root=None):
    """Where this game keeps its imported cache and saves, on any desktop.

    Three cases, in order:

    * `--cache` / POKEPORT_SAVE_DIR wins, for an unusual layout or a second
      install.
    * Portable mode: a `portable.txt` beside main.lua makes the game keep
      everything next to itself instead of in the per-user location, so a
      USB copy carries its own data (see SaveData.lua).
    * Otherwise LOVE's per-user directory, whose shape differs per OS --
      hardcoding the macOS one would silently look in the wrong place on
      Windows and Linux and report "no imported cache found".

    The identity comes from conf.lua, which honours POKEPORT_IDENTITY, so
    this follows a renamed install too.
    """
    override = os.environ.get("POKEPORT_SAVE_DIR")
    if override:
        return os.path.expanduser(override)

    if repo_root and os.path.isfile(os.path.join(repo_root, "portable.txt")):
        return repo_root

    identity = os.environ.get("POKEPORT_IDENTITY", "pokemon-love2d")
    if sys.platform == "darwin":
        base = os.path.expanduser("~/Library/Application Support")
        folder = "LOVE"
    elif sys.platform == "win32":
        base = (os.environ.get("APPDATA")
                or os.path.expanduser("~/AppData/Roaming"))
        folder = "LOVE"
    else:                                   # Linux, BSD, anything XDG
        base = (os.environ.get("XDG_DATA_HOME")
                or os.path.expanduser("~/.local/share"))
        folder = "love"                     # lowercase on these platforms
    return os.path.join(base, folder, identity)
# the cache root the transform sandbox is scoped to
GENERATED_ROOT = os.path.join("assets", "generated")

# Every hand-tuned species palette in the engine's GBC pack runs from
# near-white to near-black and spends its two middle steps on hue. A ramp
# matched straight off Gen 3 art has no such head- or foot-room, because
# Gen 3 sprites carry contrast in extra colours instead.
ANCHOR_HI, ANCHOR_LO = 246, 19

# variant number -> matcher. 1 means "leave this species alone": it is
# recorded with no ramp, so nothing repaints it and the engine
# goes on colouring it exactly as it always did.
VARIANT_MATCHER = {2: "kmeans", 3: "histogram", 4: "kmeans"}


def luminance(rgb):
    return (0.299 * rgb[0] + 0.587 * rgb[1] + 0.114 * rgb[2]) / 255.0


def opaque_histogram(path):
    """[(rgb, count)] over the opaque pixels, brightest first."""
    counts = {}
    for r, g, b, a in Image.open(path).convert("RGBA").getdata():
        if a:
            counts[(r, g, b)] = counts.get((r, g, b), 0) + 1
    return sorted(counts.items(), key=lambda kv: -luminance(kv[0]))


# ------------------------------------------------------------- matchers

def match_histogram(gb, g3):
    gb_total = sum(n for _, n in gb)
    g3_total = sum(n for _, n in g3)
    targets, seen = [], 0
    for _colour, n in gb:
        targets.append((seen + n / 2) / gb_total)
        seen += n
    ramp, cursor, idx = [], 0, 0
    for want in targets:
        while idx < len(g3) - 1 and (cursor + g3[idx][1]) / g3_total < want:
            cursor += g3[idx][1]
            idx += 1
        ramp.append(g3[idx][0])
    return ramp


def match_kmeans(gb, g3, iterations=12):
    points = [(luminance(c), c, n) for c, n in g3]
    lo = min(p[0] for p in points)
    hi = max(p[0] for p in points)
    centres = [lo + (hi - lo) * t for t in (0.125, 0.375, 0.625, 0.875)]
    groups = [[] for _ in centres]
    for _ in range(iterations):
        groups = [[] for _ in centres]
        for lum, colour, n in points:
            k = min(range(4), key=lambda i: abs(lum - centres[i]))
            groups[k].append((lum, colour, n))
        for i, group in enumerate(groups):
            if group:
                centres[i] = (sum(l * n for l, _c, n in group)
                              / sum(n for _l, _c, n in group))
    ramp = []
    for group in groups:
        if group:
            ramp.append(max(group, key=lambda t: t[2])[1])
        elif ramp:
            ramp.append(ramp[-1])
    return sorted(ramp, key=lambda c: -luminance(c))


MATCHERS = {"histogram": match_histogram, "kmeans": match_kmeans}


# ------------------------------------------------------------- shaping

def separate(ramp, step=0.78):
    """Four visually distinct shades; a repeat is pushed darker.

    A species whose Gen 3 art is mostly one flat colour matches two GB
    tones onto the same RGB, which flattens its shading and can erase an
    outline.
    """
    out = []
    for colour in ramp:
        while any(colour == seen for seen in out):
            darker = tuple(max(0, int(v * step)) for v in colour)
            colour = (darker if darker != colour
                      else tuple(min(255, v + 8) for v in colour))
        out.append(colour)
    return out


def stretch(ramp, hi=ANCHOR_HI, lo=ANCHOR_LO):
    """Rescale luminance onto the vanilla range, keeping hue.

    Lightening blends toward white (multiplying would oversaturate);
    darkening scales the channels, which holds hue. The middle steps keep
    their relative spacing, so the Gen 3 character survives.
    """
    lums = [luminance(c) * 255 for c in ramp]
    cur_hi, cur_lo = lums[0], lums[-1]
    if cur_hi - cur_lo < 1:
        return ramp
    out = []
    for colour, lum in zip(ramp, lums):
        target = lo + (lum - cur_lo) / (cur_hi - cur_lo) * (hi - lo)
        if target > lum:
            k = (target - lum) / (255 - lum) if lum < 255 else 0
            out.append(tuple(min(255, round(v + (255 - v) * k))
                             for v in colour))
        else:
            k = target / lum if lum else 0
            out.append(tuple(max(0, round(v * k)) for v in colour))
    return out


def build_ramp(gb_path, gen3_path, matcher):
    gb = opaque_histogram(gb_path)
    g3 = opaque_histogram(gen3_path)
    if not gb or not g3:
        return None
    ramp = MATCHERS[matcher](gb, g3)
    while len(ramp) < 4:
        ramp.append(ramp[-1] if ramp else (0, 0, 0))
    return separate(stretch(separate(ramp[:4])))


# ------------------------------------------------------------- inputs

def read_choices(path):
    """-> {SPECIES: variant}, read back out of a previous ramps.lua.

    The choices live in the same file as their result rather than in a
    sidecar: one artefact to read, edit and version, and no way for the two
    to drift apart.  Regenerating preserves them because this runs first --
    so editing `variant = 4` to `variant = 1` and re-running is the whole
    workflow for putting a species back on its vanilla palette.
    """
    if not os.path.isfile(path):
        return {}
    script = (
        'local ok, t = pcall(dofile, %r) '
        'if not ok or type(t) ~= "table" then return end '
        'for _, e in ipairs(t) do if e.id and e.variant then '
        'print(e.id .. "\\t" .. tostring(e.variant)) end end' % path
    )
    try:
        out = subprocess.run(["luajit", "-e", script], capture_output=True,
                             text=True, timeout=30).stdout
    except (FileNotFoundError, subprocess.SubprocessError):
        return {}
    choices = {}
    for line in out.splitlines():
        parts = line.split("\t")
        if len(parts) == 2 and parts[1].isdigit():
            choices[parts[0]] = int(parts[1])
    return choices


# Red keeps the historical root; Blue and Yellow sit in a subdirectory
# (CacheFs.prefix, see src/import/CacheFs.lua). So a version's cache root
# is not simply <data>/<version>.
VERSION_DIR = {"red": "", "blue": "blue", "yellow": "yellow"}


def version_root(cache, version):
    return os.path.join(cache, VERSION_DIR.get(version, version))


def imported_versions(cache):
    """Which versions have a usable cache, in dex-ish order.

    Both the completeness marker the importer writes and the data module
    this tool actually reads must be present: a half-finished import would
    otherwise be offered and then fail three steps later.
    """
    found = []
    for version in ("red", "blue", "yellow"):
        root = version_root(cache, version)
        if (os.path.isfile(os.path.join(root, "rom-cache.complete"))
                and os.path.isfile(os.path.join(
                    root, "data", "generated", "pokemon.lua"))):
            found.append(version)
    return found


def cache_species(cache, version):
    """species -> (front, back, dex), paths relative to the cache root."""
    data = os.path.join(version_root(cache, version),
                        "data", "generated", "pokemon.lua")
    if not os.path.isfile(data):
        return {}
    script = (
        'local f = assert(io.open(%r)) local s = f:read("*a") f:close() '
        'local t = assert(loadstring(s))() '
        'for k, v in pairs(t) do if type(v) == "table" and v.spriteFront '
        'and v.spriteBack then print(k .. "\\t" .. v.spriteFront .. "\\t" '
        '.. v.spriteBack .. "\\t" .. tostring(v.dex)) end end' % data
    )
    try:
        out = subprocess.run(["luajit", "-e", script], capture_output=True,
                             text=True, timeout=60).stdout
    except (FileNotFoundError, subprocess.SubprocessError):
        return {}
    prefix = GENERATED_ROOT + "/"
    table = {}
    for line in out.splitlines():
        parts = line.split("\t")
        if len(parts) != 4:
            continue
        rel = [p[len(prefix):] if p.startswith(prefix) else p
               for p in parts[1:3]]
        table[parts[0]] = (rel[0], rel[1],
                           int(parts[3]) if parts[3].isdigit() else None)
    return table


# ------------------------------------------------------------- output

def write_table(path, ramps, vanilla):
    """Write every species: painted ones with a ramp, the rest with just
    their variant, so one file is both the record of what was chosen and
    the input that preserves it on the next run.

    Returns only the painted rows -- transforms.lua has no use for a
    species it never repaints.
    """
    painted, all_rows = [], []
    for species in sorted(set(ramps) | set(vanilla)):
        if species in ramps:
            ramp, front, back, variant = ramps[species]
            trip = ", ".join("{%d,%d,%d}" % tuple(c) for c in ramp)
            row = ('  { id = %-14s variant = %d,\n'
                   '    ramp = { %s },\n'
                   '    front = %-34s back = %s },'
                   % ('"%s",' % species, variant, trip,
                      '"%s",' % front, '"%s"' % back))
            painted.append(row)
            all_rows.append(row)
        else:
            all_rows.append('  { id = %-14s variant = 1 },'
                            % ('"%s",' % species))
    header = (
        "-- Generated by tools/derive_palettes.py -- and read back by it.\n"
        "--\n"
        "-- `variant` is the choice; the ramp is what that choice produced.\n"
        "-- Editing a variant and re-running the tool is the whole workflow:\n"
        "--   1  leave this species on its vanilla palette\n"
        "--   2, 4  kmeans      cluster the Gen 3 colours by luminance\n"
        "--   3     histogram   match the two distributions in step\n"
        "--\n"
        "-- Ramps are four RGB triples, lightest first. Numbers and cache\n"
        "-- relative paths only: no pixels from any cartridge.\n")
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(header + "return {\n" + "\n".join(all_rows) + "\n}\n")
    return painted


def inject(path, rows):
    """Replace the generated block in transforms.lua, keeping the rest."""
    block = ("-- BEGIN GENERATED\nlocal SPECIES = {\n" + "\n".join(rows)
             + "\n}\n-- END GENERATED")
    source = open(path, encoding="utf-8").read()
    start = source.find("-- BEGIN GENERATED")
    end = source.find("-- END GENERATED")
    if start < 0 or end < 0:
        print(f"WARNING {path} has no generated block; left untouched")
        return False
    end += len("-- END GENERATED")
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(source[:start] + block + source[end:])
    return True


def main(argv=None):
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("gen3_root", help="pokeemerald graphics/pokemon")
    ap.add_argument("--version", choices=("red", "blue", "yellow"),
                    help="which imported game to read; detected "
                         "automatically when only one is present")
    ap.add_argument("--cache",
                    help="the game's data directory, if it is not where "
                         "this platform normally puts it (also settable "
                         "with POKEPORT_SAVE_DIR)")
    ap.add_argument("--matcher", choices=tuple(MATCHERS), default="kmeans",
                    help="matcher for a species with no variant recorded yet")
    ap.add_argument("--reset", action="store_true",
                    help="ignore the variants recorded in ramps.lua and "
                         "rebuild every species with --matcher")
    ap.add_argument("--keep-derived", action="store_true",
                    help="do NOT clear save/mod-derived. Stale files there "
                         "shadow species this run dropped, and the engine "
                         "then re-quantises them into four greys")
    args = ap.parse_args(argv)

    repo_root = os.path.dirname(os.path.dirname(here))
    cache = (os.path.expanduser(args.cache) if args.cache
             else game_data_dir(repo_root))

    # Which game to read. Guessing wrong is worse than asking: the pics
    # differ between versions, so a ramp derived against the wrong cache
    # would be silently mismatched art rather than a visible failure.
    available = imported_versions(cache)
    version = args.version
    if version is None:
        if len(available) == 1:
            version = available[0]
            print(f"version  {version} (only one imported)")
        elif not available:
            print(f"no imported cache under {cache}\n"
                  "  this needs one to know which species exist and where "
                  "their pics are.\n"
                  "  Import a ROM by playing once, or point --cache at the "
                  "right place.")
            return 1
        else:
            print(f"several games imported ({', '.join(available)}) -- "
                  "pass --version to say which one")
            return 1
    elif version not in available:
        print(f"{version} is not imported under {cache}"
              + (f" (found: {', '.join(available)})" if available else ""))
        return 1

    species_table = cache_species(cache, version)
    if not species_table:
        print(f"could not read the {version} species table under {cache}")
        return 1

    table_path = os.path.join(here, "ramps.lua")
    choices = {} if args.reset else read_choices(table_path)
    default_variant = next(v for v, m in sorted(VARIANT_MATCHER.items())
                           if m == args.matcher)

    root = version_root(cache, version)
    ramps, vanilla, missing, used = {}, {}, [], {}
    for species, (front_rel, back_rel, _dex) in sorted(species_table.items()):
        variant = choices.get(species, default_variant)
        if variant == 1:
            vanilla[species] = 1
            continue
        matcher = VARIANT_MATCHER.get(variant, args.matcher)

        # the table holds paths relative to the generated root, which is
        # the only thing transforms.lua may address; reading them here
        # needs that root put back
        front = os.path.join(root, GENERATED_ROOT, front_rel)
        gen3 = os.path.join(args.gen3_root, species.lower(), "front.png")
        if not (os.path.isfile(front) and os.path.isfile(gen3)):
            missing.append(species)
            continue
        ramp = build_ramp(front, gen3, matcher)
        if ramp is None:
            missing.append(species)
            continue
        ramps[species] = (ramp, front_rel, back_rel, variant)
        used[matcher] = used.get(matcher, 0) + 1

    rows = write_table(table_path, ramps, vanilla)
    inject(os.path.join(here, "transforms.lua"), rows)

    if choices:
        print(f"kept     {len(choices)} variants from ramps.lua")
    print(f"derived  {len(ramps)} ramps")
    for matcher in sorted(used):
        print(f"  {matcher:10} {used[matcher]:3}")
    if vanilla:
        print(f"vanilla  {len(vanilla)} species left untouched")
    if missing:
        print(f"MISSING  {len(missing)}: {', '.join(missing[:6])}"
              + (" ..." if len(missing) > 6 else ""))

    # AssetTransform only writes: it has no notion of a file it used to
    # produce and no longer does. A species dropped from the table would
    # otherwise keep its old repaint on disk, the resolver would go on
    # finding it, and -- with trueColor now off -- the engine would
    # re-quantise that coloured sprite into four greys.
    if not args.keep_derived:
        derived = os.path.join(cache, "save", "mod-derived", MOD_ID)
        if os.path.isdir(derived):
            shutil.rmtree(derived)
            print(f"cleared  save/mod-derived/{MOD_ID} "
                  "(rebuilt on next launch)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
