#!/usr/bin/env python3
"""modkit: the mod-author CLI (20-developer-tooling.md, D12).

    python3 tools/modkit.py <subcommand> [args]

Subcommands:
    scaffold  <id> [--profile content|overhaul|total_conversion] [--api 2]
              [--github owner/repo] [--experimental] [--dest DIR] [--force]
    translation <id> [--language NAME] [--base auto|fixture|imported]
              [--refresh] [--dest DIR] [--pixel-font]
    validate  <id|path> [--strict] [--base auto|fixture|imported]
    gen2check <id|path> [<id|path>...] [--strict] [--notes]
    lint      <id|path>
    pack      <mod-dir> [-o out.modpkg]
    bounce    <song-id|--all> [--seconds N] [--out DIR]
    docs      [--out DIR]
    set-github <id|path> <url>     add/update manifest "github" (auto-update)
    add-release-workflow <id|path> copy GitHub Actions release.yml into the mod

Global flags: --repo PATH, --json, --quiet.
Exit codes: 0 success, 1 validation/lint failure, 2 usage error.

validate drives the real engine loader headlessly (luajit, injected fs) so
a mod that passes here will not surface load errors in-game.  --base auto
folds over the player's imported dataset when there is one and falls back
to the ROM-free fixture in tests/fixture_data/ otherwise, which is what
keeps the tool runnable on a CI box with no ROM.  Which base ran matters to
MK103: only the imported dataset owns the real vanilla id space, so over the
fixture that rule is reported as skipped rather than guessed at.

lint is the no-ROM-content distribution gate (MK3xx); pack runs both at
--strict, so any finding -- warning included -- refuses the package.

gen2check (MK4xx) answers whether a mod runs on a Gen 2 game and how far it
gets: the manifest gate, then a static read of the mod's Lua against what
src/mods/Gen2Compat.lua actually backs, member by member.  It is a scan, not
an interpreter -- what it could not follow is listed as unresolved rather
than guessed at -- and it exits non-zero on a finding it calls fatal.  Mods
named together are read as one install set, so a mod and its dependencies
answer each other; --notes adds the adapter's own line for every backed
member the mod touches.
"""

import argparse
import hashlib
import io
import json
import os
import re
import subprocess
import sys
import unicodedata
import tempfile
import zipfile
from datetime import datetime, timezone

MODKIT_VERSION = "1.0.0"

LUAJIT = os.environ.get("MODKIT_LUAJIT", "luajit")

IMAGE_EXTS = {".png"}
ASSET_EXTS = {".png", ".wav", ".bin"}
ROM_PATCH_EXTS = {".gb", ".gbc", ".ips", ".bps"}
SKIP_DIRS = {".git", ".modkit", "__pycache__", ".vscode"}

GENERATED_MODULES = [
    "constants", "maps", "tilesets", "text", "text_pointers",
    "trainer_headers", "font", "sprites", "pokemon", "moves", "items",
    "type_chart", "trainers", "encounters", "field", "battle_anims",
    "audio", "palettes", "icons",
]


# ---------------------------------------------------------------- findings

class Finding:
    def __init__(self, rule, severity, message, path=None):
        self.rule = rule
        self.severity = severity  # "error" | "warn"
        self.message = message
        self.path = path

    def as_dict(self):
        return {"rule": self.rule, "severity": self.severity,
                "message": self.message, "path": self.path}

    def line(self):
        where = f"{self.path}: " if self.path else ""
        return f"{self.rule} {self.severity.upper():5} {where}{self.message}"


def report(findings, args, summary_ok, summary_fail, notes=None):
    """notes are rules that could not run, not findings against the mod, so
    --strict never promotes them and they never change the exit code."""
    notes = notes or []
    errors = [f for f in findings if f.severity == "error"]
    warns = [f for f in findings if f.severity == "warn"]
    if getattr(args, "strict", False):
        errors, warns = errors + warns, []
    if args.json:
        print(json.dumps({"ok": not errors,
                          "findings": [f.as_dict() for f in findings],
                          "notes": notes}))
    else:
        for f in findings:
            print(f.line())
        if not args.quiet:
            for note in notes:
                print(f"modkit: {note}")
            print(summary_fail if errors else summary_ok)
    return 1 if errors else 0


# ---------------------------------------------------------------- repo/root

def find_repo(start):
    node = os.path.abspath(start)
    while True:
        if os.path.isfile(os.path.join(node, "tools", "rom_manifest.json")):
            return node
        parent = os.path.dirname(node)
        if parent == node:
            return None
        node = parent


def engine_version(repo):
    src = open(os.path.join(repo, "src", "core", "Version.lua"),
               encoding="utf-8").read()
    match = re.search(r'engine\s*=\s*"([^"]+)"', src)
    return match.group(1) if match else "0.0.0-dev"


def known_permissions(repo):
    """The vocabulary the engine itself enforces (Manifest.PERMISSIONS), read
    from the source so a lint rule can never disagree with the loader."""
    try:
        src = open(os.path.join(repo, "src", "mods", "Manifest.lua"),
                   encoding="utf-8").read()
    except OSError:
        return {"network", "filesystem", "engine_internals"}
    block = re.search(r"Manifest\.PERMISSIONS\s*=\s*\{([^}]*)\}", src)
    names = set(re.findall(r"(\w+)\s*=\s*true", block.group(1))) \
        if block else set()
    return names or {"network", "filesystem", "engine_internals"}


def supported_requires(repo):
    """The src.* modules the mod surface points authors at; requiring one of
    these is not reaching past the API (Loader.lua SUPPORTED_REQUIRES)."""
    try:
        src = open(os.path.join(repo, "src", "mods", "Loader.lua"),
                   encoding="utf-8").read()
    except OSError:
        return {"src.mods.Semver", "src.audio.ChipAsm"}
    block = re.search(r"SUPPORTED_REQUIRES\s*=\s*\{(.*?)\}", src, re.S)
    names = set(re.findall(r'\["([^"]+)"\]', block.group(1))) \
        if block else set()
    return names or {"src.mods.Semver", "src.audio.ChipAsm"}


def resolve_mod_dir(repo, arg):
    if os.path.isdir(arg):
        return os.path.abspath(arg)
    candidate = os.path.join(repo, "mods", arg)
    if os.path.isdir(candidate):
        return candidate
    return None


def mod_files(mod_dir):
    """Sorted relative paths of everything a package would carry."""
    ignored = set()
    ignore_file = os.path.join(mod_dir, ".modkitignore")
    if os.path.isfile(ignore_file):
        for line in open(ignore_file, encoding="utf-8"):
            line = line.strip()
            if line and not line.startswith("#"):
                ignored.add(line)
    out = []
    for base, dirs, files in os.walk(mod_dir):
        dirs[:] = [d for d in dirs
                   if d not in SKIP_DIRS and not d.startswith(".")]
        for name in files:
            if name.startswith(".") and name != ".luarc.json":
                continue
            rel = os.path.relpath(os.path.join(base, name), mod_dir)
            rel = rel.replace(os.sep, "/")
            if rel in ignored or rel == ".modkitignore":
                continue
            out.append(rel)
    return sorted(out)


def read_manifest(mod_dir):
    path = os.path.join(mod_dir, "manifest.json")
    if not os.path.isfile(path):
        return None, Finding("MK001", "error", "manifest.json missing",
                             "manifest.json")
    try:
        manifest = json.load(open(path, encoding="utf-8"))
    except ValueError as err:
        return None, Finding("MK001", "error",
                             f"manifest.json unparseable: {err}",
                             "manifest.json")
    mod_id = manifest.get("id")
    if not isinstance(mod_id, str) or not re.fullmatch(r"[\w\-]+", mod_id):
        return None, Finding("MK001", "error",
                             "manifest id must match ^[%w_-]+$",
                             "manifest.json")
    return manifest, None


# ------------------------------------------------- permissions (MK005/MK006)

def check_permissions(repo, manifest):
    """MK005: every declared permission is from the engine's known set.  The
    loader turns this into a hard load failure for api 2 and a warning for
    api 1, so naming it here is what makes the finding readable either way."""
    findings = []
    declared = manifest.get("permissions", [])
    if declared is None:
        return findings
    if not isinstance(declared, list):
        return [Finding("MK005", "error",
                        "permissions must be an array of strings",
                        "manifest.json")]
    known = known_permissions(repo)
    for name in declared:
        if not isinstance(name, str) or name not in known:
            findings.append(Finding(
                "MK005", "error",
                f"unknown permission {name!r}; the known set is "
                + ", ".join(sorted(known)), "manifest.json"))
    return findings


def strip_lua(body):
    """Blanks comments so a commented-out example never trips a scan, keeping
    line numbers intact.  A string literal is stepped over rather than blanked
    -- the module name a require scan is after IS a string -- so a `--` inside
    a path is not read as a comment; the keyword itself is masked inside the
    literal so prose quoting a require call cannot look like one."""
    out, index, size = [], 0, len(body)
    long_open = re.compile(r"\[(=*)\[")

    def literal(text):
        return text.replace("require", " " * len("require"))

    while index < size:
        char = body[index]
        if char in "\"'":
            quote = char
            start = index
            index += 1
            while index < size:
                if body[index] == "\\" and index + 1 < size:
                    index += 2
                    continue
                index += 1
                if body[index - 1] == quote:
                    break
            out.append(literal(body[start:index]))
            continue
        comment = body.startswith("--", index)
        opener = long_open.match(body, index + 2 if comment else index)
        if comment:
            if opener:
                close = "]" + opener.group(1) + "]"
                end = body.find(close, opener.end())
                chunk = (body[index:] if end < 0
                         else body[index:end + len(close)])
            else:
                end = body.find("\n", index)
                chunk = body[index:] if end < 0 else body[index:end]
            out.append("\n" * chunk.count("\n"))
            index += len(chunk)
            continue
        if opener and opener.start() == index:
            close = "]" + opener.group(1) + "]"
            end = body.find(close, opener.end())
            chunk = body[index:] if end < 0 else body[index:end + len(close)]
            out.append(literal(chunk))
            index += len(chunk)
            continue
        out.append(char)
        index += 1
    return "".join(out)


REQUIRE_CALL = re.compile(r"""\brequire\s*\(?\s*["']([^"']+)["']""")


def check_requires(repo, mod_dir, manifest):
    """MK006: a private require of an engine module the mod has no permission
    for.  Static rather than runtime because the loader's dev tripwire only
    sees the requires that actually execute during the entry chunk, and a
    require sitting inside a function body is the same reach past the API."""
    declared = manifest.get("permissions") or []
    granted = set(name for name in declared if isinstance(name, str)) \
        if isinstance(declared, list) else set()
    supported = supported_requires(repo)
    findings = []
    for rel in mod_files(mod_dir):
        if os.path.splitext(rel)[1].lower() != ".lua":
            continue
        body = strip_lua(open(os.path.join(mod_dir, rel), encoding="utf-8",
                              errors="replace").read())
        for match in REQUIRE_CALL.finditer(body):
            name = match.group(1).replace("/", ".")
            # the link modules are the one place a mod reaches the wire, so
            # network governs them; everything else under src. is internals
            if name.startswith("src.link."):
                needed = "network"
            elif name.startswith("src.") and name not in supported:
                needed = "engine_internals"
            else:
                continue
            if needed in granted:
                continue
            line = body.count("\n", 0, match.start()) + 1
            findings.append(Finding(
                "MK006", "warn",
                f"private require of {name} without the {needed} permission; "
                f"declare it in manifest.json or use the mod API instead",
                f"{rel}:{line}"))
    return findings


# ---------------------------------------------------------------- scaffold

MANIFEST_TEMPLATE = """{
  "id": "{{id}}",
  "name": "{{name}}",
  "version": "0.1.0",
  "api": 2,
  "entry": "main.lua",
  "profile": "{{profile}}",
  "game_version": ">={{game_version}} <{{next_major}}.0.0",
  "category": "GAMEPLAY",
  "priority": 100,
  "dependencies": [],
  "optional_dependencies": [],
  "conflicts": [],
  "incompatible": [],
  "games": [{{games}}],
  "experimental": {{experimental}},{{github_line}}
  "description": "TODO: one line about {{id}}"{{extra}}
}
"""

# owner/repo or https://github.com/owner/repo(.git)
GITHUB_RE = re.compile(
    r"^(?:https?://github\.com/)?([\w.\-]+)/([\w.\-]+?)(?:\.git)?/?$"
)


def normalize_github(value):
    """Return 'owner/repo' or None for empty; raise ValueError if malformed."""
    if value is None:
        return None
    text = str(value).strip()
    if not text:
        return None
    match = GITHUB_RE.fullmatch(text)
    if not match:
        raise ValueError(
            "github must be owner/repo or a github.com URL "
            f"(got {value!r})")
    owner, repo = match.group(1), match.group(2)
    if repo.endswith(".git"):
        repo = repo[:-4]
    return f"{owner}/{repo}"


def check_github_field(manifest):
    """Optional github field: absent is fine (note), present must parse."""
    findings, notes = [], []
    raw = manifest.get("github")
    if raw is None or raw == "":
        notes.append(
            'optional tip: set "github": "owner/repo" in manifest.json '
            "to enable launcher auto-update and Other versions")
        return findings, notes
    try:
        normalize_github(raw)
    except ValueError as err:
        findings.append(Finding(
            "MK001", "error", str(err), "manifest.json"))
    return findings, notes

MAIN_CONTENT = """-- {{id}}: a content-profile mod (api 2).
-- The 10-minute loop: edit, save, F5 in a POKEPORT_DEV=1 game, repeat.
return function(mod)
  -- patch, not override: every field you do not name keeps its base value
  -- (learnset, sprites, evolutions all survive this speed change)
  mod.content.pokemon:patch("MEW", { baseStats = { speed = 110 } })

  -- mod.events:on("pokemon.caught", function(e)
  --   mod.log:info("caught %s at L%d", e.species, e.level)
  -- end)
end
"""

MAIN_OVERHAUL = """-- {{id}}: an overhaul-profile mod (api 2).
return function(mod)
  mod.options:define({
    { key = "difficulty", label = "DIFFICULTY", kind = "choice",
      choices = { "normal", "hard" }, default = "normal" },
  })

  -- register into content registries here; patch beats override for
  -- anything you want to coexist with other mods
  -- mod.content.moves:patch("BLIZZARD", { accuracy = 70 })

  -- mod.hooks:wrap("battle.damage", function(next, ctx, damage)
  --   return next(ctx, damage)
  -- end)
  -- mod.hooks:wrap("catch.rate", function(next, ctx, rate)
  --   return next(ctx, rate)
  -- end)
end
"""

MAIN_TC = """-- {{id}}: a total-conversion-profile mod (api 2).
return function(mod)
  -- the new game itself: spawn, names, money (field.boot, D11)
  -- mod.content.field:patch("boot", {
  --   startMap = "MY_TOWN", startX = 5, startY = 6,
  --   playerName = "HERO", rivalName = "FOE", startMoney = 5000,
  -- })

  -- own the boot screens (Title/Intro) through the screens registry
  -- mod.content.screens:register("MyTitle", { new = function(game) ... end })
end
"""

TRANSFORMS_TEMPLATE = """-- Asset transforms ({{id}}): derive art from the PLAYER'S own imported
-- cache at install time.  Ship the recipe, never ROM-derived pixels --
-- this file is the only sanctioned way to base art on vanilla assets.
return function(ctx)
  -- local img = ctx.readImage("battle/front/mew.png")
  -- ctx.recolor(img, { [2] = 3, [3] = 2 })
  -- ctx.writeImage(img, "battle/front/mew.png")
end
"""

LUARC_TEMPLATE = """{
  "runtime.version": "LuaJIT",
  "diagnostics.globals": ["love"]
}
"""

README_TEMPLATE = """# {{name}}

A `{{profile}}` mod for the LOVE2D Pokemon Red engine (mod api 2).

## Layout

- `manifest.json` - identity, version range, load order
- `main.lua` - the entry chunk; receives the `mod` object
{{layout_extra}}
## Loop

1. `POKEPORT_DEV=1 love .` once, leave it running
2. edit, press F5 to hot-reload, backtick for the dev console
3. `python3 tools/modkit.py validate {{id}}` before sharing
4. `python3 tools/modkit.py pack mods/{{id}}` to ship
"""


# manifest "games": the version ids / gen tokens a mod declares
# (src/mods/ModTargets.lua).  Emitted as a JSON array body.
def games_list(value):
    tokens = [t.strip().lower() for t in str(value or "").split(",")]
    tokens = [t for t in tokens if t]
    return ", ".join('"%s"' % t for t in (tokens or ["gen1"]))


def cmd_scaffold(args, repo):
    profile = args.profile
    dest_root = args.dest or os.path.join(repo, "mods")
    dest = os.path.join(dest_root, args.id)
    if not re.fullmatch(r"[\w\-]+", args.id):
        print(f"modkit: bad id {args.id!r} (letters, numbers, _ or -)")
        return 2
    if os.path.exists(dest) and not args.force:
        print(f"modkit: {dest} exists (use --force to overwrite)")
        return 2
    engine = engine_version(repo)
    next_major = int(engine.split(".")[0]) + 1
    name = args.id.replace("_", " ").replace("-", " ").title()

    github = ""
    if getattr(args, "github", None):
        try:
            github = normalize_github(args.github) or ""
        except ValueError as err:
            print(f"modkit: {err}")
            return 2

    extra = ""
    if profile == "total_conversion":
        extra = ',\n  "assets_transforms": "transforms.lua"'
    github_line = f'\n  "github": "{github}",' if github else ""
    subst = {
        "{{id}}": args.id, "{{name}}": name, "{{profile}}": profile,
        "{{game_version}}": engine, "{{next_major}}": str(next_major),
        "{{extra}}": extra,
        "{{github_line}}": github_line,
        "{{experimental}}": "true" if getattr(args, "experimental", False)
        else "false",
        "{{games}}": games_list(getattr(args, "games", "gen1")),
    }

    def emit(rel, template):
        path = os.path.join(dest, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        body = template
        for key, value in subst.items():
            body = body.replace(key, value)
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(body)

    main = {"content": MAIN_CONTENT, "overhaul": MAIN_OVERHAUL,
            "total_conversion": MAIN_TC}[profile]
    layout_extra = ""
    if profile == "total_conversion":
        layout_extra = "- `transforms.lua` - asset transforms over the player's cache\n"
    subst["{{layout_extra}}"] = layout_extra

    emit("manifest.json", MANIFEST_TEMPLATE)
    emit("main.lua", main)
    emit("README.md", README_TEMPLATE)
    emit(".luarc.json", LUARC_TEMPLATE)
    os.makedirs(os.path.join(dest, "assets"), exist_ok=True)
    open(os.path.join(dest, "assets", ".gitkeep"), "w").close()
    if profile == "total_conversion":
        emit("transforms.lua", TRANSFORMS_TEMPLATE)

    if not args.quiet:
        print(f"created {dest} ({profile} profile, api 2)")
        print(f"next: python3 tools/modkit.py validate {args.id}")
    return 0


# ---------------------------------------------------------------- validate

DRIVER_TEMPLATE = """-- generated by tools/modkit.py; drives the real loader headlessly
package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")
local data = %s
local FILES = %s
local overlay = {}
local function readDisk(path)
  local disk = FILES[path]
  if not disk then return nil end
  local handle = io.open(disk, "rb")
  if not handle then return nil end
  local body = handle:read("*a")
  handle:close()
  return body
end
local fs = {
  read = function(path) return overlay[path] or readDisk(path) end,
  write = function(path, body) overlay[path] = body return true end,
  createDirectory = function() return true end,
  getInfo = function(path)
    if overlay[path] or FILES[path] then return { type = "file" } end
    local prefix = path .. "/"
    for key in pairs(FILES) do
      if key:sub(1, #prefix) == prefix then return { type = "directory" } end
    end
    return nil
  end,
  load = function(path)
    local body = overlay[path] or readDisk(path)
    if not body then return nil, "no file: " .. path end
    return loadstring(body, path)
  end,
  getDirectoryItems = function(path)
    local seen, items = {}, {}
    local prefix = path .. "/"
    for key in pairs(FILES) do
      if key:sub(1, #prefix) == prefix then
        local child = key:sub(#prefix + 1):match("^[^/]+")
        if child and not seen[child] then
          seen[child] = true
          items[#items + 1] = child
        end
      end
    end
    table.sort(items)
    return items
  end,
}
local Loader = require("src.mods.Loader")
local Schemas = require("src.mods.Schemas")
-- MK103 needs the id space as it stood BEFORE the merge: a patch against a
-- missing id still folds to a value and lands in the target, so the merged
-- view cannot tell an orphan from a real record
local function resolvePath(root, path)
  local node = root
  for key in path:gmatch("[^%%.]+") do
    if type(node) ~= "table" then return nil end
    node = node[key]
  end
  return node
end
local baseIds = {}
for name, spec in pairs(Schemas.REGISTRIES) do
  local set = {}
  local target = spec.target and resolvePath(data, spec.target)
  if type(target) == "table" then
    if spec.baseIds then
      for _, id in ipairs(spec.baseIds(target)) do set[id] = true end
    else
      for id in pairs(target) do set[id] = true end
    end
  end
  baseIds[name] = set
end
local loader = Loader.new({ fs = fs })
local ok, err = pcall(loader.load, loader, data)
-- one tab-separated record per finding; each field is scrubbed on its own so
-- the separators survive (a field that carried its own tab used to collapse
-- the whole row into one column)
local function row(kind, ...)
  local parts = { kind }
  for index = 1, select("#", ...) do
    local field = tostring((select(index, ...)))
    parts[#parts + 1] = (field:gsub("[\\t\\r\\n]", " "))
  end
  print(table.concat(parts, "\\t"))
end
if not ok then row("ERR", err) end
-- record registries only: deep ones treat patch as register (a new key is
-- the point) and compose ones reject patch outright
for name, registry in pairs(loader.content) do
  if registry.spec.semantics == "record" then
    local known = baseIds[name] or {}
    for id, list in pairs(registry.ops) do
      local defined, patcher = known[id], nil
      for _, entry in ipairs(list) do
        if entry.op == "register" or entry.op == "override" then
          defined = true
        elseif entry.op == "patch" and entry.owner ~= Schemas.ENGINE then
          patcher = patcher or entry.owner
        end
      end
      if patcher and not defined then
        local gen2Routed = Schemas.targetFor(name, registry.spec, 2)
          ~= registry.spec.target
        row("ORPHAN", name, id, patcher, tostring(gen2Routed))
      end
    end
  end
end
local Logger = require("src.core.Logger")
for _, line in ipairs(Logger.history or {}) do
  if line:find("ignored:", 1, true) then
    row("IGN", line)
  elseif line:find("^%%[warn%%]") then
    row("WARN", line)
  end
end
local status = loader:status()
for _, mod in ipairs(status.available) do
  row("MOD", mod.id, mod.version, mod.state, mod.error or "")
end
for _, message in ipairs(status.errors) do
  row("ERR", message)
end
"""


def classify_error(message, fallback="MK100"):
    msg = message.lower()
    # a reference stranded by a tombstone is its own rule; the generic
    # dangling-ref test below would otherwise swallow it as MK102
    if "unresolved reference to removed" in msg:
        return "MK104"
    if "unresolved reference" in msg:
        return "MK102"
    if "unknown permission" in msg:
        return "MK005"
    if ("unknown field" in msg or "missing required field" in msg
            or "expected" in msg):
        return "MK101"
    if "game version" in msg:
        return "MK002"
    if ("dependency" in msg or "circular" in msg):
        return "MK003"
    if "conflicts with" in msg:
        return "MK004"
    if "map_scripts" in msg:
        return "MK201"
    return fallback


def _generated_data_dir_ok(path):
    # 'true' when path looks like rom-derived generated data
    # pokemon.lua preserves the existing imported-dataset probe;
    # data:load is authority for the rest, including optional namespaces e.g. audio
    return bool(path) and os.path.isfile(os.path.join(path, "pokemon.lua"))


def _love_user_data_root():
    # get desktop save root
    identity = os.environ.get("POKEPORT_IDENTITY") or "pokemon-love2d"

    if sys.platform == "win32":
        appdata = os.environ.get("APPDATA")
        return os.path.join(appdata, "LOVE", identity) if appdata else None

    if sys.platform == "darwin":
        return os.path.join(
            os.path.expanduser("~"),
            "Library", "Application Support", "LOVE", identity)

    if sys.platform.startswith(("linux", "freebsd")):
        data_home = os.environ.get("XDG_DATA_HOME")
        if not data_home:
            data_home = os.path.join(os.path.expanduser("~"), ".local", "share")
        return os.path.join(data_home, "love", identity)

    return None


def imported_data_dir(repo):
    # locate datasets that would be used at runtime
    # priority:
    # 1 explicit POKEPORT_DATA_DIR
    # 2 versioned portable/source-adjacent cache
    # 3 versioned LOVE user cache
    # 4 historical source-tree/generated dev dataset
    # POKEPORT_VERSION defaults to red
    explicit = os.environ.get("POKEPORT_DATA_DIR")
    if explicit:
        path = os.path.abspath(os.path.expanduser(explicit))
        return path if _generated_data_dir_ok(path) else None

    version = (os.environ.get("POKEPORT_VERSION") or "red").lower()
    if version not in ("red", "blue", "yellow", "gold", "silver"):
        version = "red"

    candidates = [
        os.path.join(repo, version, "data", "generated"),
    ]

    user_root = _love_user_data_root()
    if user_root:
        candidates.append(os.path.join(
            user_root, version, "data", "generated"))

    # preserve old source-tree developer data as final fallback
    # we prefer the real versioned cache first
    # because a checkout may have a partially generated dataset
    candidates.append(os.path.join(repo, "data", "generated"))

    seen = set()
    for path in candidates:
        path = os.path.abspath(path)
        if path in seen:
            continue
        seen.add(path)
        if _generated_data_dir_ok(path):
            return path
    return None


FIXTURE_BASE = 'require("tests.fixture_data").load()'
IMPORTED_BASE = ('(function() local D = require("src.core.Data") '
                 'D:load() return D end)()')


def resolve_base(repo, choice):
    """--base auto prefers the player's imported dataset and falls back to the
    ROM-free fixture.  Which one ran matters to MK103: the fixture is a
    three-species stand-in, so a missing id there proves nothing and the rule
    is skipped instead of reported."""
    if choice != "auto":
        return choice
    return "imported" if imported_data_dir(repo) else "fixture"


def run_loader(repo, mod_dir, findings, base="fixture", notes=None,
               manifest=None):
    """Drive the engine loader headlessly with the mod mounted; the base
    dataset is the ROM-free fixture, or the imported cache with
    --base imported (for mods that reference vanilla Red content).

    Rules that only the imported dataset can decide are skipped rather than
    downgraded when the fixture stands in, and each one names itself in
    notes so a skip is visible instead of silent."""
    mount = "mods/" + os.path.basename(mod_dir)
    files = {}
    for rel in mod_files(mod_dir):
        files[f"{mount}/{rel}"] = os.path.join(mod_dir, rel)
    entries = "".join(
        "  [%s] = %s,\n" % (lua_quote(k), lua_quote(v))
        for k, v in sorted(files.items()))
    base = resolve_base(repo, base)
    source = IMPORTED_BASE if base == "imported" else FIXTURE_BASE
    driver = DRIVER_TEMPLATE % (source, "{\n" + entries + "}")
    with tempfile.NamedTemporaryFile("w", suffix=".lua", delete=False,
                                     encoding="utf-8") as handle:
        handle.write(driver)
        driver_path = handle.name
    try:
        proc = subprocess.run([LUAJIT, driver_path], cwd=repo,
                              capture_output=True, text=True, encoding="utf-8", timeout=120)
    except FileNotFoundError:
        findings.append(Finding("MK100", "error",
                                f"cannot run {LUAJIT} (install luajit or "
                                "set MODKIT_LUAJIT)"))
        return
    finally:
        os.unlink(driver_path)
    if proc.returncode != 0:
        findings.append(Finding("MK100", "error",
                                "loader driver crashed: "
                                + (proc.stderr or proc.stdout).strip()[-400:]))
        return
    # a failed mod reports the same message twice -- once in the error feed and
    # once as its own state -- so the same rule/text pair is emitted once
    seen = set()
    skipped = set()

    def add(finding):
        key = (finding.rule, finding.severity, finding.message)
        if key in seen:
            return
        seen.add(key)
        findings.append(finding)

    for line in proc.stdout.splitlines():
        parts = line.split("\t")
        kind = parts[0]
        if kind == "ERR" and len(parts) > 1:
            message = parts[1]
            # check_permissions already named this one against manifest.json,
            # with the known set spelled out; the loader's echo adds nothing
            if "unknown permission" in message:
                continue
            add(Finding(classify_error(message), "error", message))
        elif kind == "IGN" and len(parts) > 1:
            if "unknown permission" in parts[1]:
                continue
            add(Finding(classify_error(parts[1], "MK001"), "error", parts[1]))
        elif kind == "ORPHAN" and len(parts) >= 5:
            registry, target, owner = parts[1], parts[2], parts[3]
            gen2_routed = parts[4] == "true"
            # only the imported dataset owns the real vanilla id space.  The
            # fixture stands in for three species, so "not in base data" there
            # is a fact about the fixture, not about the mod -- MK103 has no
            # evidence either way and does not get to speak.  Emitting it as a
            # warning instead would still refuse the package, because pack and
            # --strict promote every warning to fatal.
            if base != "imported":
                skipped.add("MK103")
                continue
            if gen2_routed and declares_gen2(repo, manifest):
                # tools/build_data.py never writes a Gen 2 cache, so the
                # imported dataset has no Gold/Crystal ground truth either.
                skipped.add("MK103")
                continue
            add(Finding(
                "MK103", "error",
                f"{owner}: patch target {target!r} exists in neither "
                f"{registry} base data nor a dependency's registrations; "
                f"check the id spelling or depend on the mod that "
                f"registers it"))
        elif kind == "WARN" and len(parts) > 1:
            message = parts[1]
            if "unresolved reference" in message:
                # api 1 keeps cross-ref breakage at warning level; the rule id
                # still has to distinguish a tombstone from a plain typo
                add(Finding(classify_error(message), "warn", message))
            elif "did you mean" in message or "schema" in message:
                add(Finding("MK101", "warn", message))
        elif kind == "MOD" and len(parts) >= 4:
            mod_id, _version, state, error = (parts[1], parts[2], parts[3],
                                              "\t".join(parts[4:]))
            if state not in ("loaded", "disabled") and error:
                add(Finding(classify_error(error), "error",
                            f"{mod_id}: {error}"))
    if skipped and notes is not None:
        notes.append(
            "%s not checked: the ROM-free fixture base only stands in for "
            "vanilla content, so it cannot tell a typo from a real id -- "
            "re-run with --base imported to check %s"
            % (", ".join(sorted(skipped)),
               "them" if len(skipped) > 1 else "it"))


def lua_quote(text):
    return '"' + (text.replace("\\", "\\\\").replace('"', '\\"')) + '"'


def cmd_validate(args, repo):
    mod_dir = resolve_mod_dir(repo, args.mod)
    if not mod_dir:
        print(f"modkit: no mod at {args.mod!r}")
        return 2
    findings = []
    notes = []
    manifest, problem = read_manifest(mod_dir)
    if problem:
        findings.append(problem)
    else:
        gh_findings, gh_notes = check_github_field(manifest)
        findings.extend(gh_findings)
        notes.extend(gh_notes)
        findings.extend(check_permissions(repo, manifest))
        run_loader(repo, mod_dir, findings, args.base, notes, manifest)
        findings.extend(check_requires(repo, mod_dir, manifest))
        findings.extend(lint_dir(repo, mod_dir, manifest))
    name = manifest.get("id") if manifest else os.path.basename(mod_dir)
    return report(findings, args, f"ok {name} valid", f"FAIL {name} invalid",
                  notes)


def write_manifest(mod_dir, manifest):
    path = os.path.join(mod_dir, "manifest.json")
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, indent=2, ensure_ascii=False)
        handle.write("\n")


def cmd_set_github(args, repo):
    """Add or update the optional github field on an existing manifest."""
    mod_dir = resolve_mod_dir(repo, args.mod)
    if not mod_dir:
        print(f"modkit: no mod at {args.mod!r}")
        return 2
    manifest, problem = read_manifest(mod_dir)
    if problem:
        print(problem.line())
        return 1
    try:
        repo_slug = normalize_github(args.url)
    except ValueError as err:
        print(f"modkit: {err}")
        return 2
    if not repo_slug:
        print("modkit: github url is empty")
        return 2
    manifest["github"] = repo_slug
    write_manifest(mod_dir, manifest)
    if not args.quiet:
        print(f"set github to {repo_slug!r} in {mod_dir}/manifest.json")
        print("launcher auto-update / Other versions will use this repo")
    return 0


def cmd_add_release_workflow(args, repo):
    """Copy the standard GitHub Actions release workflow into a mod folder."""
    mod_dir = resolve_mod_dir(repo, args.mod)
    if not mod_dir:
        print(f"modkit: no mod at {args.mod!r}")
        return 2
    manifest, problem = read_manifest(mod_dir)
    if problem:
        print(problem.line())
        return 1
    mod_id = manifest.get("id") or os.path.basename(mod_dir)
    template = os.path.join(repo, "tools", "mod_release_workflow.yml")
    if not os.path.isfile(template):
        print(f"modkit: missing template {template}")
        return 2
    dest_dir = os.path.join(mod_dir, ".github", "workflows")
    dest = os.path.join(dest_dir, "release.yml")
    if os.path.exists(dest) and not args.force:
        print(f"modkit: {dest} exists (use --force to overwrite)")
        return 2
    body = open(template, encoding="utf-8").read().replace("{{MOD_ID}}", mod_id)
    os.makedirs(dest_dir, exist_ok=True)
    with open(dest, "w", encoding="utf-8") as handle:
        handle.write(body)
    if not args.quiet:
        print(f"wrote {dest}")
        print("push this mod as its own GitHub repo (with manifest github set) "
              "to publish installable .zip releases on every main push")
    return 0


# ---------------------------------------------------------------- lint

def ahash(image):
    """Ink-mask hash over the 8x8 downscale: background vs ink, split at
    THIS image's own average brightness rather than a fixed shade.  Swapping
    the three ink shades -- the classic recolor -- leaves the mask intact,
    which is exactly what MK302 wants to catch.

    A fixed cutoff (e.g. "<=200 is ink") only makes sense for sprites with a
    light background to split against; a mostly-opaque 16x16 icon has almost
    no pixel above that cutoff, so every such icon collapsed onto the same
    "all ink" hash and was flagged as a near-duplicate of anything else that
    also collapsed -- which was most of them, boulder.png included.
    Thresholding against the image's own mean keeps the split meaningful
    (and roughly balanced) no matter how light or dark the source is."""
    from PIL import Image
    small = image.convert("L").resize((8, 8), Image.LANCZOS)
    raw = (small.get_flattened_data() if hasattr(small, "get_flattened_data")
           else small.getdata())
    raw = list(raw)
    average = sum(raw) / len(raw)
    return sum((1 << i) for i, p in enumerate(raw) if p <= average)


def hamming(a, b):
    return bin(a ^ b).count("1")


class CacheIndex:
    """Hashes of the player's ROM-derived cache (assets/generated)."""

    def __init__(self, repo):
        self.sha = {}
        self.perceptual = []
        root = os.path.join(repo, "assets", "generated")
        if not os.path.isdir(root):
            return
        try:
            from PIL import Image
        except ImportError:
            Image = None
        for base, _dirs, files in os.walk(root):
            for name in files:
                path = os.path.join(base, name)
                rel = os.path.relpath(path, repo).replace(os.sep, "/")
                body = open(path, "rb").read()
                self.sha[hashlib.sha256(body).hexdigest()] = rel
                if Image and os.path.splitext(name)[1].lower() in IMAGE_EXTS:
                    try:
                        with Image.open(io.BytesIO(body)) as img:
                            self.perceptual.append(
                                (rel, img.size, ahash(img)))
                    except Exception:
                        pass


def lint_dir(repo, mod_dir, manifest):
    """MK3xx: the no-ROM-content gate (22-distribution-and-packaging.md)."""
    findings = []
    manifest = manifest or {}
    transforms_rel = manifest.get("assets_transforms")
    has_transforms = bool(transforms_rel)
    cache = CacheIndex(repo)
    try:
        from PIL import Image
    except ImportError:
        Image = None

    for rel in mod_files(mod_dir):
        path = os.path.join(mod_dir, rel)
        ext = os.path.splitext(rel)[1].lower()
        # MK307: required_imports are user-owned installation state. Keeping
        # baseroms in the walk without an explicit gate would let `pack`
        # silently bundle exactly the ROM this feature exists not to ship.
        if rel.startswith("baseroms/"):
            findings.append(Finding(
                "MK307", "error",
                "user-supplied baseroms must not be distributed", rel))
            continue
        # MK301: nothing may live in (or point into) the generated trees
        if rel.startswith(("data/generated/", "assets/generated/")):
            findings.append(Finding(
                "MK301", "error",
                "path shadows the player's ROM-derived cache", rel))
            continue
        if ext in (".lua", ".json") and rel != transforms_rel:
            body = open(path, encoding="utf-8", errors="replace").read()
            if "assets/generated/" in body or "data/generated/" in body:
                findings.append(Finding(
                    "MK301", "error",
                    "references the ROM-derived cache; ship your own asset "
                    "under assets/ or derive it via assets_transforms", rel))
        # MK303: ROM images and ROM-hack patch formats never ship
        if ext in ROM_PATCH_EXTS:
            findings.append(Finding(
                "MK303", "error", "ROM/ROM-hack patch file", rel))
            continue
        # MK304: raw chip-audio banks are ROM-derived
        base = os.path.basename(rel)
        if base == "programs.bin":
            findings.append(Finding(
                "MK304", "error",
                "raw audio bank blob (author chip programs instead)", rel))
            continue
        if ext == ".bin":
            size = os.path.getsize(path)
            if size >= 0x4000 and size % 0x4000 == 0:
                findings.append(Finding(
                    "MK304", "error",
                    "bank-sized binary blob looks ROM-derived", rel))
                continue
        # MK302: byte-identity and perceptual near-duplicates vs the cache
        if ext in ASSET_EXTS:
            body = open(path, "rb").read()
            digest = hashlib.sha256(body).hexdigest()
            twin = cache.sha.get(digest)
            if twin:
                findings.append(Finding(
                    "MK302", "error",
                    f"byte-identical to ROM-derived {twin}", rel))
                continue
            if Image and ext in IMAGE_EXTS and cache.perceptual:
                try:
                    with Image.open(io.BytesIO(body)) as img:
                        size, digest = img.size, ahash(img)
                except Exception:
                    continue
                for twin_rel, twin_size, twin_hash in cache.perceptual:
                    if size == twin_size and hamming(digest, twin_hash) <= 4:
                        severity = "warn" if has_transforms else "error"
                        remedy = ("allowed (ships assets_transforms)"
                                  if has_transforms else
                                  "ship it as an assets_transforms step "
                                  "instead of a file")
                        findings.append(Finding(
                            "MK302", severity,
                            f"near-duplicate of ROM-derived {twin_rel} -- "
                            f"{remedy}", rel))
                        break
        # MK305: bulk dump of an imported data table
        if (ext == ".lua"
                and os.path.splitext(base)[0] in GENERATED_MODULES
                and rel != transforms_rel and rel != "main.lua"):
            finding = check_data_dump(repo, path, base, rel)
            if finding:
                findings.append(finding)
    return findings


DUMP_DRIVER = """local function keysOf(path)
  local handle = io.open(path, "rb")
  if not handle then return nil end
  local body = handle:read("*a")
  handle:close()
  local chunk = loadstring(body, path)
  if not chunk then return nil end
  setfenv(chunk, {})
  local ok, result = pcall(chunk)
  if not ok or type(result) ~= "table" then return nil end
  local keys = {}
  for key in pairs(result) do
    if type(key) == "string" then keys[#keys + 1] = key end
  end
  return keys
end
local shipped = keysOf(%s)
local vanilla = keysOf(%s)
if not shipped or not vanilla or #vanilla < 10 then return print("SKIP") end
local set = {}
for _, key in ipairs(shipped) do set[key] = true end
local hits = 0
for _, key in ipairs(vanilla) do
  if set[key] then hits = hits + 1 end
end
print(hits >= #vanilla * 0.8 and "DUMP" or "OK")
"""


def check_data_dump(repo, path, base, rel):
    vanilla = os.path.join(repo, "data", "generated", base)
    if not os.path.isfile(vanilla):
        # no imported dataset to diff against; say so rather than pass
        # silently, so a green run never implies this rule actually ran
        return Finding("MK305", "warn",
                       f"dump check skipped: no imported data/generated/{base} "
                       "to diff against", rel)
    driver = DUMP_DRIVER % (lua_quote(path), lua_quote(vanilla))
    try:
        proc = subprocess.run([LUAJIT, "-e", driver], cwd=repo,
                              capture_output=True, text=True, encoding="utf-8", timeout=60)
    except FileNotFoundError:
        # the gate must fail closed: a missing interpreter is a broken
        # environment, not a clean mod
        return Finding("MK100", "error",
                       f"cannot run {LUAJIT} for the dump check (install "
                       "luajit or set MODKIT_LUAJIT)", rel)
    if proc.stdout.strip() == "DUMP":
        return Finding("MK305", "error",
                       "bulk dump of an imported data table; register "
                       "individual records through the mod API", rel)
    return None


def cmd_lint(args, repo):
    mod_dir = resolve_mod_dir(repo, args.mod)
    if not mod_dir:
        print(f"modkit: no mod at {args.mod!r}")
        return 2
    manifest, problem = read_manifest(mod_dir)
    findings = [problem] if problem else []
    findings.extend(lint_dir(repo, mod_dir, manifest))
    name = os.path.basename(mod_dir)
    return report(findings, args, f"ok {name}: no ROM-derived content",
                  f"FAIL {name}: ROM-content gate")


# ---------------------------------------------------------------- pack

def pack_timestamp():
    raw = os.environ.get("SOURCE_DATE_EPOCH")
    if raw is None:
        return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"), None
    try:
        epoch = int(raw, 10)
        if epoch < 0:
            raise ValueError("negative epoch")
        stamp = datetime.fromtimestamp(epoch, timezone.utc)
    except (ValueError, OverflowError, OSError):
        return None, "SOURCE_DATE_EPOCH must be a nonnegative Unix timestamp"
    return stamp.strftime("%Y-%m-%dT%H:%M:%SZ"), None


def cmd_pack(args, repo):
    mod_dir = resolve_mod_dir(repo, args.mod)
    if not mod_dir:
        print(f"modkit: no mod at {args.mod!r}")
        return 2
    manifest, problem = read_manifest(mod_dir)
    if problem:
        print(problem.line())
        return 1
    findings = list(check_permissions(repo, manifest))
    notes = []
    run_loader(repo, mod_dir, findings, args.base, notes, manifest)
    findings.extend(check_requires(repo, mod_dir, manifest))
    findings.extend(lint_dir(repo, mod_dir, manifest))
    # pack runs validate --strict (20-developer-tooling.md 5), so a warning
    # blocks distribution too: MK006 and the MK3xx gate are documented as
    # unbypassable by the packaging path, which only holds if warnings bite
    # here even though they are advisory under a bare validate.  Notes are not
    # findings -- a rule the fixture base could not run has nothing to say
    # about the mod, so packing ROM-free stays possible (M13 criterion 4)
    for f in findings:
        print(f.line())
    if not args.quiet:
        for note in notes:
            print(f"modkit: {note}")
    if findings:
        if not args.quiet:
            print("modkit: pack refused (pack runs validate --strict, so the "
                  "warnings above are fatal too)")
        return 1

    mod_id = manifest["id"]
    version = manifest.get("version", "0.0.0")
    out = args.output or f"{mod_id}-{version}.modpkg"
    packed_at, timestamp_problem = pack_timestamp()
    if timestamp_problem:
        print(f"modkit: {timestamp_problem}")
        return 2
    files = mod_files(mod_dir)
    records = []
    for rel in files:
        body = open(os.path.join(mod_dir, rel), "rb").read()
        records.append({"path": rel, "bytes": len(body),
                        "sha256": hashlib.sha256(body).hexdigest()})
    pack_meta = {
        "modkit": MODKIT_VERSION,
        "packed_at": packed_at,
        "id": mod_id,
        "version": version,
        "api": manifest.get("api", 1),
        "engine_range": manifest.get("game_version", ""),
        "files": records,
        "lint": {"no_rom_content": "pass", "schema": "pass",
                 "cross_refs": "pass"},
    }
    # normalized entry order + a fixed timestamp = reproducible archives
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as archive:
        for rel in files:
            info = zipfile.ZipInfo(rel, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            archive.writestr(info,
                             open(os.path.join(mod_dir, rel), "rb").read())
        info = zipfile.ZipInfo(".modkit/pack.json",
                               date_time=(1980, 1, 1, 0, 0, 0))
        info.compress_type = zipfile.ZIP_DEFLATED
        info.external_attr = 0o644 << 16
        archive.writestr(info, json.dumps(pack_meta, indent=2))
    if not args.quiet:
        print(f"wrote {out} (reproducible, {len(files)} files "
              "+ .modkit/pack.json)")
    return 0


# ---------------------------------------------------------------- bounce

BOUNCE_DRIVER = """-- generated by tools/modkit.py bounce
package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")
-- the render seam reads programs.bin through love.filesystem; back it
-- with the real disk for this offline run
love.filesystem.read = function(path)
  local handle = io.open(path, "rb")
  if not handle then return nil, "no file: " .. path end
  local body = handle:read("*a")
  handle:close()
  return body
end
love.filesystem.getInfo = function(path)
  local handle = io.open(path, "rb")
  if handle then handle:close() return { type = "file" } end
  return nil
end
local Data = require("src.core.Data")
local ok, err = pcall(Data.load, Data)
if not ok then
  io.stderr:write("bounce needs an imported dataset: " .. tostring(err) .. "\\n")
  os.exit(3)
end
local ChipAudio = require("src.core.ChipAudio")
local songs = Data.audio and Data.audio.songs or {}
local WANTED = %s
local SECONDS = %d
local OUT = %s
local function isChip(def)
  return type(def) == "table"
    and (def.chip ~= nil or (def.address and def.bank) or def.program)
end
local function writeWav(path, sd)
  local samples = sd:getSampleCount()
  local channels = sd:getChannelCount()
  local rate = sd:getSampleRate()
  local dataBytes = samples * channels * 2
  local function u32(n)
    return string.char(n %% 256, math.floor(n / 256) %% 256,
      math.floor(n / 65536) %% 256, math.floor(n / 16777216) %% 256)
  end
  local function u16(n)
    return string.char(n %% 256, math.floor(n / 256) %% 256)
  end
  local handle = assert(io.open(path, "wb"))
  handle:write("RIFF", u32(36 + dataBytes), "WAVE")
  handle:write("fmt ", u32(16), u16(1), u16(channels), u32(rate),
    u32(rate * channels * 2), u16(channels * 2), u16(16))
  handle:write("data", u32(dataBytes))
  local chunk = {}
  for index = 0, samples - 1 do
    for channel = 1, channels do
      local value = sd:getSample(index, channel)
      local int = math.floor(value * 32767 + 0.5)
      if int < -32768 then int = -32768 end
      if int > 32767 then int = 32767 end
      if int < 0 then int = int + 65536 end
      chunk[#chunk + 1] = u16(int)
    end
    if #chunk >= 8192 then
      handle:write(table.concat(chunk))
      chunk = {}
    end
  end
  handle:write(table.concat(chunk))
  handle:close()
end
local ids = {}
if WANTED then
  ids[1] = WANTED
else
  for id in pairs(songs) do ids[#ids + 1] = id end
  table.sort(ids)
end
local rendered, skipped = 0, 0
for _, id in ipairs(ids) do
  local def = songs[id]
  if not def then
    io.stderr:write("no such song: " .. id .. "\\n")
    os.exit(1)
  end
  if isChip(def) then
    local okRender, sd = pcall(ChipAudio._renderMusicForTest, Data, def, SECONDS)
    if okRender and sd then
      writeWav(OUT .. "/" .. id .. ".wav", sd)
      print("wrote " .. OUT .. "/" .. id .. ".wav")
      rendered = rendered + 1
    else
      io.stderr:write("render failed for " .. id .. ": " .. tostring(sd) .. "\\n")
    end
  else
    skipped = skipped + 1
  end
end
print(("bounced %%d songs (%%d file-based skipped)"):format(rendered, skipped))
"""


def cmd_bounce(args, repo):
    out_dir = args.out or os.path.join(repo, "bounce")
    os.makedirs(out_dir, exist_ok=True)
    wanted = "nil" if args.all else lua_quote(args.song)
    driver = BOUNCE_DRIVER % (wanted, args.seconds, lua_quote(out_dir))
    with tempfile.NamedTemporaryFile("w", suffix=".lua", delete=False,
                                     encoding="utf-8") as handle:
        handle.write(driver)
        driver_path = handle.name
    try:
        proc = subprocess.run([LUAJIT, driver_path], cwd=repo)
    finally:
        os.unlink(driver_path)
    return 0 if proc.returncode == 0 else 1


# ----------------------------------------------------------- translation

# Dumps the player-facing tables out of a loaded dataset as TSV, both fields
# already Lua-quoted so the generator can paste them straight into the
# catalogs without a second round of escaping.
TRANSLATION_DUMP = """-- generated by tools/modkit.py; dumps translatable data as TSV
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local D = {{BASE}}

-- Not %q: that escapes a newline as a backslash followed by a real line
-- break, which would split every dex entry across several TSV rows and
-- silently truncate it.  Escape by hand so a value is always one line, and
-- keep the readable spellings (\\n, not \\10) because these land in the
-- comment a translator reads.
local ESCAPES = { ["\\\\"] = "\\\\\\\\", ['"'] = '\\\\"',
                  ["\\n"] = "\\\\n", ["\\r"] = "\\\\r", ["\\t"] = "\\\\t" }
local function esc(s)
  local body = s:gsub('[%c\\\\"]', function(c)
    return ESCAPES[c] or ("\\\\%d"):format(c:byte())
  end)
  return '"' .. body .. '"'
end

local function emit(kind, key, value)
  if type(value) ~= "string" or value == "" then return end
  io.write(kind, "\\t", esc(key), "\\t", esc(value), "\\n")
end

for id, text in pairs(D.text or {}) do emit("dialogue", id, text) end
for id, def in pairs(D.pokemon or {}) do emit("species", id, def.name) end
for id, def in pairs(D.moves or {}) do emit("move", id, def.name) end
for id, def in pairs(D.items or {}) do emit("item", id, def.name) end
for id, def in pairs(D.trainers or {}) do emit("trainer", id, def.name) end
-- Data.statuses only exists once the mod merge has run, so fall back to the
-- engine's own records: they are what a mod-free boot puts there anyway.
local statuses = D.statuses
if not statuses or next(statuses) == nil then
  statuses = require("src.battle.Status").RECORDS
end
for id, def in pairs(statuses or {}) do
  emit("status", id, def.label)
  if def.hudLabel and def.hudLabel ~= def.label then
    emit("status_hud", id, def.hudLabel)
  end
end
-- dex entries carry their own prose (species flavour text)
for id, def in pairs(D.pokemon or {}) do
  if type(def.dexEntry) == "table" then
    emit("dex", id, def.dexEntry.kind)
    emit("dex_text", id, def.dexEntry.text)
  end
end
"""

# The engine's own literals, harvested from the Strings(...) call sites.
# Matches Strings("...") and Strings('...'), single line, which is how the
# sweep writes them; a call whose source string is built at runtime cannot
# be translated and is not meant to match here.
STRINGS_CALL = re.compile(
    r'\bStrings(?:\.source)?\('
    r'\s*("(?:[^"\\]|\\.)*"|\'(?:[^\'\\]|\\.)*\')\s*(?:,|\))')


def _fold_ascii(text):
    folded = unicodedata.normalize("NFKD", text or "")
    folded = "".join(c for c in folded if not unicodedata.combining(c))
    folded = re.sub(r"[^A-Za-z0-9_-]+", "_", folded).strip("_-")
    return folded.lower()


def ascii_mod_id(name, language=None):
    r"""An engine-legal manifest id derived from what the author called it.

    src/mods/Manifest.lua matches `^[%w_%-]+$`, and Lua's %w is ASCII where
    Python's \w is not, so "VersaoVermelha" with a tilde loads fine by
    Python's rules and is rejected by the engine's.  The directory keeps the
    author's name (the loader keys on manifest.id, not the folder); this is
    only the id.

    Accented Latin folds cleanly.  A name written entirely in a non-Latin
    script does not, and those are precisely the translations worth
    supporting, so fall back to the --language name and then to a stable
    digest rather than refusing to scaffold."""
    for candidate in (_fold_ascii(name), _fold_ascii(language)):
        if candidate:
            return candidate
    digest = hashlib.sha1((name or "").encode("utf-8")).hexdigest()[:8]
    return f"translation_{digest}"


def harvest_engine_strings(repo):
    """Every literal the engine passes through src/core/Strings.lua, in
    source order per file. Returns [(lua_literal, "path:line"), ...]."""
    out, seen = [], set()
    src = os.path.join(repo, "src")
    for root, _dirs, names in os.walk(src):
        for name in sorted(names):
            if not name.endswith(".lua"):
                continue
            path = os.path.join(root, name)
            rel = os.path.relpath(path, repo)
            with open(path, encoding="utf-8") as handle:
                body = handle.read()
            for match in STRINGS_CALL.finditer(body):
                literal = match.group(1)
                if literal.startswith("'"):
                    # normalise to the double-quoted form the catalog uses
                    literal = '"' + literal[1:-1].replace('"', '\\"') + '"'
                line = body.count("\n", 0, match.start()) + 1
                if literal in seen:
                    continue
                seen.add(literal)
                out.append((literal, f"{rel}:{line}"))
    return out


def dump_dataset(repo, base):
    """Run the dumper under luajit against the fixture or imported cache."""
    source = IMPORTED_BASE if base == "imported" else FIXTURE_BASE
    body = TRANSLATION_DUMP.replace("{{BASE}}", source)
    handle = tempfile.NamedTemporaryFile("w", suffix=".lua", delete=False,
                                         dir=repo, encoding="utf-8")
    handle.write(body)
    handle.close()
    try:
        proc = subprocess.run([os.environ.get("LUA", "luajit"), handle.name],
                              cwd=repo, capture_output=True, text=True, encoding="utf-8")
    finally:
        os.unlink(handle.name)
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.strip() or "dataset dump failed")
    rows = []
    for line in proc.stdout.splitlines():
        parts = line.split("\t")
        if len(parts) == 3:
            rows.append(tuple(parts))
    return rows


def _catalog_file(title, note, entries, keyed_by_source=False):
    """One lang/*.lua table: every value starts empty, and main.lua skips
    empties so an unfinished catalog falls through to English.

    The English is deliberately NOT written alongside the ROM-derived keys.
    Extracted script text and vanilla names are ROM content, and a mod that
    shipped 2500 lines of them in comments would be redistributing the ROM
    however good the intent. Those go to worksheet/, which is gitignored and
    never packed. Engine-authored sources (lang/strings.lua) are this repo's
    own Lua, so there the key IS the English and nothing is leaked."""
    out = [f"-- {title}", "--"]
    out += ["-- " + line for line in note.strip().splitlines()]
    out += ["", "return {"]
    if not entries:
        out.append("  -- nothing to translate here yet")
    for key, _english in entries:
        out.append(f"  [{key}] = \"\",")
    out += ["}", ""]
    return "\n".join(out)


TRANSLATION_MAIN = '''-- {{name}}: a translation of the game into {{lang}}.
--
-- Nothing here is translated yet.  Every table under lang/ starts with
-- empty strings; fill one in and it takes effect on the next boot, and
-- anything still empty keeps rendering in English.  That means a
-- half-finished translation is always playable, so you can ship early and
-- fill the long tail in later.
--
-- Read TRANSLATING.md before the first edit; the font is the part people
-- get wrong.
return function(mod)
  -- mod:read is the supported way into your own directory; the catalogs are
  -- plain Lua tables, so read and run them rather than require()ing them.
  local function catalog(name)
    local rel = "lang/" .. name .. ".lua"
    local body = mod:read(rel)
    if not body then return {} end
    local chunk, err = loadstring(body, rel)
    if not chunk then
      mod.log:warn("%s has a syntax error: %s", rel, tostring(err))
      return {}
    end
    local ok, table_ = pcall(chunk)
    if not ok or type(table_) ~= "table" then
      mod.log:warn("%s did not return a table: %s", rel, tostring(table_))
      return {}
    end
    return table_
  end

  -- An empty value means "not translated yet", never "translate to blank".
  local function each(name, apply)
    local n = 0
    for key, value in pairs(catalog(name)) do
      if type(value) == "string" and value ~= "" then
        apply(key, value)
        n = n + 1
      end
    end
    return n
  end

  -- ---- glyphs -------------------------------------------------------
  -- Text rendering through the bundled Plain Pixel TTF ("Plain Pixel
  -- Font" by Douglas Vautour (Burpy Fresh), CC-BY 4.0 -- see
  -- assets/fonts/plainpixel/README.md).  Registered, it replaces the tile
  -- font for ordinary characters, so a translation needs no glyph sheet
  -- at all; box borders and <PK>-style macros keep their tiles.  Options:
  -- { file = mod.assets:path("myfont.ttf"), size = 15, spacing = 0,
  --   yOffset = -6, bold = true } -- size is the font's design em (Plain
  -- Pixel only rasterizes cleanly at multiples of 15), bold thickens a
  -- 1px-stroke font that reads too light.
  {{ttf_register}}mod.content.font:register("ttf", {})

  -- Register the sheet BEFORE anything asks for a glyph on it.  base is
  -- the first code the page owns; 0x100 and up is free space above the
  -- vanilla pages, so a new alphabet never collides with them.
  for id, page in pairs(catalog("font")) do
    mod.content.font:register(id, page)
  end
  -- charmap: which byte sequence draws which code
  for seq, code in pairs(catalog("charmap")) do
    mod.content.font:register("charmap:" .. seq, { seq = seq, code = code })
  end

  -- ---- text ---------------------------------------------------------
  local counts = {}
  counts.dialogue = each("dialogue", function(id, value)
    mod.content.text:override(id, value)
  end)
  counts.strings = each("strings", function(source, value)
    mod.content.strings:override(source, value)
  end)
  counts.species = each("species_names", function(id, value)
    mod.content.pokemon:patch(id, { name = value })
  end)
  counts.moves = each("move_names", function(id, value)
    mod.content.moves:patch(id, { name = value })
  end)
  counts.items = each("item_names", function(id, value)
    mod.content.items:patch(id, { name = value })
  end)
  counts.trainers = each("trainer_names", function(id, value)
    mod.content.trainers:patch(id, { name = value })
  end)
  counts.statuses = each("status_labels", function(id, value)
    mod.content.statuses:patch(id, { label = value })
  end)

  -- ---- name entry ---------------------------------------------------
  -- The naming screen's letter grid.  Leave lang/naming.lua returning nil
  -- to keep the English alphabet.
  local grid = catalog("naming")
  if grid.upper then
    mod.hooks:on("ui.naming.grid", function(base, ctx)
      local want = ctx.lower and grid.lower or grid.upper
      return want or base
    end)
  end

  mod.events:on("game.ready", function()
    local total = 0
    for _, n in pairs(counts) do total = total + n end
    mod.log:info("{{lang}}: %d strings translated", total)
  end)
end
'''

TRANSLATING_MD = '''# Translating into {{lang}}

Everything the player can read is one of two kinds of string, and they live
in different places for a reason.

| lang/ file | What it is | Key |
|---|---|---|
| `dialogue.lua` | Every line of extracted script text | the original label, e.g. `_PalletTownText1` |
| `strings.lua` | Text the engine itself writes: battle messages, menus, link play | the English source string |
| `species.lua` `moves.lua` `items.lua` `trainers.lua` | Names | the vanilla id |
| `statuses.lua` | `PSN`, `BRN`, ... as they appear in the HUD | the status id |
| `font.lua` `charmap.lua` | Your glyph sheet and what draws what | see below |
| `naming.lua` | The letter grid for entering names | - |

Fill in a value and it takes effect. Leave it `""` and that string stays in
English, so the game is playable at every point along the way.

## Where the English is

The catalogs hold keys and *your* text, never the original English. The
English lives next door, in `{{id}}-worksheet/`, one tab-separated file per
catalog:

```
"_AbandonLearningText"\t"Abandon learning\\n{RAM:wStringBuffer}?"
```

That directory is deliberately outside the mod. Extracted script text and
the vanilla names are ROM content, and `modkit pack` zips everything under
the mod directory, so a worksheet kept inside would end up in your release
whatever a `.gitignore` said. Keep it beside the mod, never in it.

`lang/strings.lua` is the exception: those sources are the engine's own Lua
rather than anything out of the ROM, so there the key *is* the English and
you can translate straight from it.

## Start with the font, not the text

The fast path: scaffold with `--pixel-font` (or uncomment the
`mod.content.font:register("ttf", {})` line in `main.lua`) and the game
renders text through the engine's bundled Plain Pixel TTF, which already
covers Latin with diacritics, Cyrillic, kana and CJK.  No glyph sheet, no
charmap; `lang/font.lua` and `lang/charmap.lua` can stay empty.  The rest
of this section is for translations that want the hand-drawn tile look
instead.

The engine draws from **glyph pages**: an image of 8x8 cells plus a charmap
saying which byte sequence draws which cell. The vanilla pages sit at `$60`
and `$80`. Anything from `0x100` up is free, so a new alphabet is added
rather than swapped in:

```lua
-- lang/font.lua
return {
  {{lang_id}} = {
    image = "assets/font/{{lang_id}}.png",
    base = 0x100,        -- first code this page owns
    glyphsPerRow = 16,
    -- advance = 8,      -- set this if your glyphs are not 8px wide
  },
}
```

```lua
-- lang/charmap.lua: sequence -> code, in the same order as the sheet
return {
  ["A"] = 0x100,
  ["B"] = 0x101,
}
```

The sheet is a plain PNG, 16 glyphs to a row by default, each cell 8x8,
black on white like `assets/generated/font.png`. Codes run left to right,
top to bottom from `base`.

Sequences are matched **longest first**, so a multi-byte character and a
multi-character ligature both work and neither shadows the other:

```lua
["\\u{3042}"] = 0x120,   -- one 3-byte character, one glyph
["ch"] = 0x121,          -- two ASCII letters, one glyph
```

## Line length is counted in glyphs

The dialogue box fits 18 glyphs a line, not 18 bytes. A 3-byte character
costs one column, and the engine will never cut a character in half. Your
own `\\n` line breaks are respected exactly as written, so break lines where
they read best rather than where they fit English.

If your glyphs are not 8px wide, set `advance` on the page and the box
re-measures.

## Format directives must survive

Some sources carry `%s` or `%d`:

```lua
["Wild %s\\nappeared!"] = "...",
```

Keep every directive, in a count that matches. Word order is yours to
change; the engine substitutes in the order the directives appear, so if
your language needs the name last, write the sentence with the `%s` last.
A translation whose directive count does not match the English is refused
at runtime and the English is drawn instead, with a line in the log saying
so - it will not crash a battle.

## Checking your work

```sh
python3 tools/modkit.py validate {{id}} --base imported
python3 tools/modkit.py translation {{id}} --refresh   # pick up new engine strings
POKEPORT_DEV=1 scripts/run.sh                          # F5 hot-reloads lang/
```

`--refresh` rewrites the catalogs from the current engine, keeping every
translation you have already written and reporting what changed. Run it
after pulling a new engine version.
'''

TRANSLATION_README = '''# {{name}}

A {{lang}} translation of the game.

Generated with `python3 tools/modkit.py translation {{id}}`. See
`TRANSLATING.md` for how to work on it.

## Status

Nothing is translated yet: {{total}} strings are waiting in `lang/`.

| Catalog | Entries |
|---|---|
{{table}}

## Layout

- `manifest.json` - identity and the engine version range
- `main.lua` - registers whatever is filled in and skips whatever is not
- `lang/` - the catalogs; this is the whole job
- `assets/font/` - your glyph sheet
'''

FONT_README = '''You may not need this directory at all: scaffold with
`--pixel-font` (or uncomment the `register("ttf", {})` line in main.lua)
and text renders through the engine's bundled Plain Pixel TTF, which
covers Latin, kana and CJK out of the box.  A glyph sheet is only for a
translation that wants the hand-drawn GB look.

Put your glyph sheet here.

A page is a PNG of 8x8 cells, 16 per row by default, black on white. Codes
run left to right and top to bottom starting at the page's `base`, so the
first cell is `base`, the second `base + 1`, and so on.

`assets/generated/font.png` in the player's cache is the vanilla sheet at
the same scale; open it alongside yours to match weight and baseline.

Declare the sheet in `lang/font.lua` and map sequences to codes in
`lang/charmap.lua`.
'''


def cmd_translation(args, repo):
    """Scaffold (or refresh) a translation mod: every player-visible string
    the engine and the dataset know about, as empty catalogs to fill in."""
    dest = os.path.join(args.dest or os.path.join(repo, "mods"), args.id)
    # Translations get named in the language they translate into
    # ("VersaoVermelha", with the tilde), but the engine's manifest rule is
    # Lua's `^[%w_%-]+$`, and Lua's %w is ASCII-only where Python's \w is not.
    # A directory named in the target language is fine -- the loader keys on
    # manifest.id, not the folder -- so keep the name the author asked for and
    # derive an ASCII id for the manifest.
    mod_id = ascii_mod_id(args.id, args.language)
    exists = os.path.exists(dest)
    if exists and not (args.refresh or args.force):
        print(f"modkit: {dest} exists (use --refresh to update the catalogs)")
        return 2

    base = resolve_base(repo, args.base)
    try:
        rows = dump_dataset(repo, base)
    except RuntimeError as err:
        print(f"modkit: could not read the dataset ({err})")
        return 1

    grouped = {}
    for kind, key, value in rows:
        grouped.setdefault(kind, []).append((key, value))
    for entries in grouped.values():
        entries.sort()

    engine = harvest_engine_strings(repo)

    catalogs = [
        ("dialogue", "Script text", grouped.get("dialogue", []), False,
         "Keyed by the original text label. The English is in the comment."),
        ("strings", "Engine text", [(lit, where) for lit, where in engine], True,
         "Keyed by the English source, which is also what draws if you leave\n"
         "an entry empty. Keep any %s / %d directives."),
        ("species_names", "Species names", grouped.get("species", []), False, ""),
        ("move_names", "Move names", grouped.get("move", []), False, ""),
        ("item_names", "Item names", grouped.get("item", []), False, ""),
        ("trainer_names", "Trainer class names", grouped.get("trainer", []), False, ""),
        ("status_labels", "Status labels", grouped.get("status", []), False,
         "Short enough for the battle HUD: the vanilla ones are three glyphs."),
    ]

    # keep existing translations across a --refresh
    previous = {}
    if exists:
        for name, *_ in catalogs:
            path = os.path.join(dest, "lang", f"{name}.lua")
            previous[name] = _read_existing_catalog(path)

    os.makedirs(os.path.join(dest, "lang"), exist_ok=True)
    os.makedirs(os.path.join(dest, "assets", "font"), exist_ok=True)

    lang_name = args.language or args.id.replace("_", " ").title()
    counts, changed, kept = {}, {}, {}
    for name, title, entries, by_source, note in catalogs:
        done = previous.get(name, {})
        body = _catalog_file(title, note or f"{title} for {lang_name}.",
                             entries, by_source)
        if done:
            body = _merge_catalog(body, done)
        path = os.path.join(dest, "lang", f"{name}.lua")
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(body)
        counts[name] = len(entries)
        kept[name] = sum(1 for key in done if any(key == k for k, _ in entries))
        changed[name] = len(done) - kept[name]

    engine_version_ = engine_version(repo)
    subst = {
        "{{id}}": mod_id,
        "{{name}}": args.id,
        "{{lang}}": lang_name,
        "{{lang_id}}": re.sub(r"\W+", "_", args.id).lower(),
        "{{game_version}}": engine_version_,
        "{{next_major}}": str(int(engine_version_.split(".")[0]) + 1),
        "{{profile}}": "content",
        "{{extra}}": "",
        "{{github_line}}": "",
        "{{experimental}}": "false",
        "{{ttf_register}}": "" if args.pixel_font else "-- ",
        "{{total}}": str(sum(counts.values())),
        "{{table}}": "\n".join(
            f"| `lang/{name}.lua` | {counts[name]} |" for name, *_ in catalogs),
    }

    def emit(rel, template, overwrite=True):
        path = os.path.join(dest, rel)
        if os.path.exists(path) and not overwrite:
            return
        os.makedirs(os.path.dirname(path), exist_ok=True)
        body = template
        for key, value in subst.items():
            body = body.replace(key, value)
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(body)

    # A refresh must never clobber hand-edited prose or a tuned manifest.
    emit("manifest.json", MANIFEST_TEMPLATE, overwrite=not exists)
    emit("main.lua", TRANSLATION_MAIN, overwrite=not exists)
    emit("README.md", TRANSLATION_README, overwrite=not exists)
    emit("TRANSLATING.md", TRANSLATING_MD)
    emit("assets/font/README.md", FONT_README)
    emit(".luarc.json", LUARC_TEMPLATE, overwrite=not exists)
    for stub, body in (("font", FONT_STUB), ("charmap", CHARMAP_STUB),
                       ("naming", NAMING_STUB)):
        emit(f"lang/{stub}.lua", body, overwrite=not exists)

    # The English reference, written as a SIBLING of the mod rather than
    # inside it.  Extracted text is ROM content: it can sit on the
    # translator's disk, but `modkit pack` zips the whole mod directory, so
    # anything under dest/ would end up in the distributable no matter what
    # a .gitignore said.  Keeping it outside is the only version of this
    # that cannot leak.
    work = dest + "-worksheet"
    os.makedirs(work, exist_ok=True)
    for name, title, entries, by_source, _note in catalogs:
        if by_source:
            continue  # engine strings are our own source, already readable
        lines = [f"# {title}: the English behind each key in lang/{name}.lua.",
                 "# Reference only, and deliberately outside the mod: this",
                 "# text comes out of the ROM, so it must not be shipped.", ""]
        for key, english in entries:
            lines.append(f"{key}\t{english}")
        with open(os.path.join(work, f"{name}.txt"), "w",
                  encoding="utf-8") as handle:
            handle.write("\n".join(lines) + "\n")

    if args.json:
        print(json.dumps({"dest": dest, "base": base, "counts": counts,
                          "kept": kept, "orphaned": changed}, indent=2))
    elif not args.quiet:
        verb = "refreshed" if exists else "created"
        print(f"{verb} {dest} ({base} dataset)")
        for name, *_ in catalogs:
            line = f"  lang/{name}.lua  {counts[name]:5} entries"
            if exists:
                line += f"  ({kept[name]} translated"
                if changed[name]:
                    line += f", {changed[name]} orphaned"
                line += ")"
            print(line)
        if base == "fixture":
            print("\nnote: no imported dataset found, so the name and dialogue")
            print("catalogs came from the three-species test fixture.")
            print("Import a ROM and re-run with --refresh for the real set.")
        print(f"\nnext: read {os.path.join(dest, 'TRANSLATING.md')}")
    return 0


FONT_STUB = '''-- Glyph pages this translation adds.  Delete the entry if the vanilla
-- alphabet already covers your language.
--
-- base is the first glyph code the page owns.  0x100 and up is free space
-- above the vanilla $60/$80 pages, so this adds an alphabet rather than
-- replacing one.  Set `advance` if your glyphs are not 8px wide.
return {
  -- {{lang_id}} = {
  --   image = "assets/font/{{lang_id}}.png",
  --   base = 0x100,
  --   glyphsPerRow = 16,
  -- },
}
'''

CHARMAP_STUB = '''-- Which byte sequence draws which glyph code.
--
-- Sequences are matched longest-first, so a multi-byte character and a
-- multi-character ligature both work: "ch" can be one glyph even though
-- "c" is also mapped.  Codes here must land inside a page declared in
-- lang/font.lua.
return {
  -- ["A"] = 0x100,
  -- ["B"] = 0x101,
}
'''

NAMING_STUB = '''-- The naming screen's letter grid.  Return an empty table to keep the
-- English alphabet.
--
-- Each entry is a row of cells; a cell is whatever sequence your charmap
-- maps, so a multi-byte character is one cell.  The row holding a single
-- "lower case" / "UPPER CASE" cell is the case switch, and the cell
-- spelled "ED" is the confirm.
return {
  -- upper = {
  --   { "A", "B", "C", "D", "E", "F", "G", "H", "I" },
  --   { "J", "K", "L", "M", "N", "O", "P", "Q", "R" },
  --   { "S", "T", "U", "V", "W", "X", "Y", "Z", " " },
  --   { "-", "?", "!", "/", ".", ",", "<PK>", "<MN>", "ED" },
  --   { "lower case" },
  -- },
  -- lower = { ... },
}
'''


def _read_existing_catalog(path):
    """Pull the filled-in values out of a catalog we wrote earlier, so a
    refresh keeps the work. Deliberately a line scan rather than a Lua
    parse: it has to survive a half-edited file."""
    done = {}
    if not os.path.isfile(path):
        return done
    entry = re.compile(r'^\s*\[(.+?)\]\s*=\s*("(?:[^"\\]|\\.)*")\s*,')
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            match = entry.match(line)
            if match and match.group(2) != '""':
                done[match.group(1)] = match.group(2)
    return done


def _merge_catalog(body, done):
    """Re-apply saved translations to a freshly generated catalog, and park
    anything whose key the engine no longer has in an ORPHANED block rather
    than dropping the work on the floor."""
    used = set()
    out = []
    entry = re.compile(r'^(\s*\[)(.+?)(\]\s*=\s*)""(,.*)$')
    for line in body.splitlines():
        match = entry.match(line)
        if match and match.group(2) in done:
            key = match.group(2)
            used.add(key)
            line = f"{match.group(1)}{key}{match.group(3)}{done[key]}{match.group(4)}"
        out.append(line)
    orphans = [k for k in done if k not in used]
    if orphans:
        out += ["", "-- ORPHANED: these keys are no longer in the engine or the",
                "-- dataset, most likely because the English changed. Move the",
                "-- translation onto the new key above and delete the entry."]
        out.append("-- {")
        for key in sorted(orphans):
            out.append(f"--   [{key}] = {done[key]},")
        out.append("-- }")
    return "\n".join(out) + "\n"


# ---------------------------------------------------------------- docs

def cmd_docs(args, repo):
    """Regenerates the registry reference by driving the Schemas-backed
    generator, so the docs cannot drift from the engine."""
    proc = subprocess.run(
        [LUAJIT, os.path.join("tools", "gen_registry_docs.lua")], cwd=repo)
    if proc.returncode != 0:
        return 1
    generated = os.path.join(repo, "docs", "modding", "reference",
                             "registries.md")
    if args.out:
        os.makedirs(args.out, exist_ok=True)
        target = os.path.join(args.out, "registries.md")
        with open(generated, encoding="utf-8") as src_handle, \
                open(target, "w", encoding="utf-8") as dst_handle:
            dst_handle.write(src_handle.read())
        if not args.quiet:
            print(f"copied to {target}")
    return 0


# ------------------------------------------------ gen2 compatibility (MK4xx)
#
# What the adapter backs is read out of the engine, never restated here:
# src/mods/Gen2Compat.lua's coverage API is the source of truth and
# docs/mod-api-gen2-compat.md is its prose.  The contract this consumes is
# Gen2Compat.coverage(name) -> { kind = "facade"|"alias", target = <module>,
# members = { [member] = "backed"|"warned"|"absent" }, notes = { [member] =
# "one line" } }, with COVERAGE_VERSION naming the vocabulary.  Nothing below
# hardcodes a module, a member or a status, so the tool cannot drift from the
# adapter; when the accessor is missing the fallback says so in the notes and
# reports what it could not decide instead of guessing.
#
#   MK400 claims no Gen 2 game           MK405 member degrades, and says so
#   MK401 a dependency claims none       MK406 the signature moved under it
#   MK402 no adapter for the module      MK407 upvalue surgery with no target
#   MK403 Gold runs a different module   MK408 upvalue surgery, unresolved
#   MK404 member has no Gen 2 backing    MK409 a mod-side edit no adapter can
#                                              make for it
#                                        MK410 the entry chunk holding a
#                                              member of a game not up yet

COVERAGE_DUMP = '''\
package.path = "./?.lua;./?/init.lua;" .. package.path
local G = require("src.mods.Gen2Compat")
local function emit(...)
  local row = {}
  for i = 1, select("#", ...) do
    row[i] = tostring((select(i, ...))):gsub("%s+", " ")
  end
  print(table.concat(row, "\\t"))
end
emit("VERSION", G.COVERAGE_VERSION or 0)
for name, spec in pairs(G.ADAPTERS or {}) do
  emit("ADAPTER", name, type(spec) == "string" and spec or "")
  local row = G.coverage and G.coverage(name)
  if row then
    emit("COVER", name, row.kind or "", row.target or "")
    for member, status in pairs(row.members or {}) do
      emit("MEMBER", name, member, status)
    end
    for member, note in pairs(row.notes or {}) do
      emit("NOTE", name, member, note)
    end
  end
end
'''

# the one status that is a hard stop; the others are named by the adapter
ABSENT = "absent"


def module_path(repo, name):
    return os.path.join(repo, *name.split(".")) + ".lua"


def _module_exists(repo, name):
    """Is there a file behind this module name, either way package.path spells
    it (conf.lua sets ?.lua and ?/init.lua)."""
    return os.path.isfile(module_path(repo, name)) \
        or os.path.isfile(os.path.join(repo, *name.split("."), "init.lua"))


def _lua_close(text, index):
    """Index of the bracket closing the one at `index`, honouring literals;
    None when the file does not balance (a scan limit, not a finding)."""
    depth, i = 0, index
    while i < len(text):
        char = text[i]
        if char in "\"'":
            quote, i = char, i + 1
            while i < len(text):
                if text[i] == "\\":
                    i += 2
                    continue
                if text[i] == quote:
                    break
                i += 1
        elif char in "([{":
            depth += 1
        elif char in ")]}":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return None


def _lua_args(text, index):
    """(count, varargs) for the call whose '(' is at index; (None, False) when
    the parentheses do not balance."""
    close = _lua_close(text, index)
    if close is None:
        return None, False
    inner = text[index + 1:close]
    if not inner.strip():
        return 0, False
    depth, count, i = 0, 1, 0
    while i < len(inner):
        char = inner[i]
        if char in "\"'":
            quote, i = char, i + 1
            while i < len(inner):
                if inner[i] == "\\":
                    i += 2
                    continue
                if inner[i] == quote:
                    break
                i += 1
        elif char in "([{":
            depth += 1
        elif char in ")]}":
            depth -= 1
        elif char == "," and depth == 0:
            count += 1
        i += 1
    return count, inner.rstrip().endswith("...")


LUA_API_CACHE = {}


def lua_api(path):
    """member -> {"params": [...] or None, "line": n} for a module file: what
    it hangs off its own table, plus the fields its constructor writes onto
    `self`.  Regex over source, so a name assembled at runtime is missed --
    which is why the adapter's own coverage table decides what is backed and
    this only ever answers "under what parameters"."""
    if path in LUA_API_CACHE:
        return LUA_API_CACHE[path]
    try:
        text = strip_lua(open(path, encoding="utf-8", errors="replace").read())
    except OSError:
        LUA_API_CACHE[path] = None
        return None
    returns = re.findall(r"^return\s+([A-Za-z_]\w*)\s*$", text, re.M)
    module = returns[-1] if returns else None
    if not module:
        counts = {}
        for name in re.findall(r"^function\s+([A-Z]\w*)[.:]", text, re.M):
            counts[name] = counts.get(name, 0) + 1
        module = max(counts, key=counts.get) if counts else None
    api = {}
    if module:
        def put(member, params, offset, kind):
            api.setdefault(member, {"params": params, "kind": kind,
                                    "line": text.count("\n", 0, offset) + 1})

        for match in re.finditer(
                r"^function\s+%s([.:])(\w+)\s*\(([^)]*)\)" % module, text,
                re.M):
            params = [p.strip() for p in match.group(3).split(",") if p.strip()]
            if match.group(1) == ":":
                params.insert(0, "self")
            put(match.group(2), params, match.start(), "function")
        for match in re.finditer(
                r"^\s*%s\.(\w+)\s*=\s*(function\s*\(([^)]*)\))?" % module,
                text, re.M):
            params = None
            if match.group(2):
                params = [p.strip() for p in match.group(3).split(",")
                          if p.strip()]
            put(match.group(1), params, match.start(),
                "function" if params is not None else "value")
        # written onto the instance, never onto the module table: the members
        # that only exist once a game is running
        for match in re.finditer(r"\bself\.(\w+)\s*=(?!=)", text):
            put(match.group(1), None, match.start(), "field")
    LUA_API_CACHE[path] = api
    return api


def gen1_only_modules(repo):
    """The Gen 1 modules a Gold boot never instantiates, read from the loader
    so this tool and the require shim cannot disagree (Loader.lua)."""
    try:
        src = open(os.path.join(repo, "src", "mods", "Loader.lua"),
                   encoding="utf-8").read()
    except OSError:
        return set()
    block = re.search(r"GEN1_ONLY_MODULES\s*=\s*\{(.*?)\n\}", src, re.S)
    return set(re.findall(r'\["([^"]+)"\]', block.group(1))) if block else set()


def _adapters_from_source(repo):
    """ADAPTERS as name -> alias target ("" for a built facade), for the
    checkout where the coverage accessor cannot be run."""
    try:
        src = strip_lua(open(os.path.join(repo, "src", "mods",
                                          "Gen2Compat.lua"),
                             encoding="utf-8").read())
    except OSError:
        return {}
    block = re.search(r"ADAPTERS\s*=\s*\{(.*?)\n\}", src, re.S)
    if not block:
        return {}
    return {m.group(1): m.group(2) or "" for m in re.finditer(
        r'\["([^"]+)"\]\s*=\s*(?:"([^"]+)"|\w+)', block.group(1))}


def gen2_coverage(repo, notes):
    """name -> {kind, target, members, notes, declared}, straight off
    Gen2Compat.coverage.  `members` is None where nothing could answer, which
    every check below treats as "unknown", never as "backed"."""
    rows = []
    with tempfile.NamedTemporaryFile("w", suffix=".lua", delete=False,
                                     encoding="utf-8") as handle:
        handle.write(COVERAGE_DUMP)
        dump_path = handle.name
    try:
        proc = subprocess.run([LUAJIT, dump_path], cwd=repo,
                              capture_output=True, text=True, timeout=60)
        if proc.returncode == 0:
            rows = proc.stdout.splitlines()
        else:
            notes.append("could not read the adapter table through %s (%s)"
                         % (LUAJIT, (proc.stderr or "").strip()[-120:]))
    except (OSError, subprocess.SubprocessError):
        notes.append("could not run %s, so the adapter table was read from "
                     "the Lua source instead" % LUAJIT)
    finally:
        os.unlink(dump_path)

    coverage = {}
    for row in rows:
        parts = row.split("\t")
        if parts[0] == "ADAPTER" and len(parts) >= 3:
            coverage.setdefault(parts[1], {
                "kind": "alias" if parts[2] else "facade",
                "target": parts[2], "members": None, "notes": {},
                "declared": False})
        elif parts[0] == "COVER" and len(parts) >= 4:
            record = coverage.setdefault(parts[1], {"notes": {}})
            record.update({"kind": parts[2], "target": parts[3],
                           "members": {}, "declared": True})
        elif parts[0] == "MEMBER" and len(parts) >= 4:
            coverage[parts[1]]["members"][parts[2]] = parts[3]
        elif parts[0] == "NOTE" and len(parts) >= 4:
            coverage[parts[1]]["notes"][parts[2]] = "\t".join(parts[3:])
    if not coverage:
        for name, alias in _adapters_from_source(repo).items():
            coverage[name] = {"kind": "alias" if alias else "facade",
                              "target": alias, "members": None, "notes": {},
                              "declared": False}
    undeclared = sorted(n for n, r in coverage.items() if not r["declared"])
    if undeclared:
        notes.append("no coverage row for %s: this scan can say the adapter "
                     "serves the name and nothing about its members"
                     % ", ".join(undeclared))
    return coverage


# ------------------------------------------------------------ mod use scan

class Use:
    def __init__(self, rel, line, module, ident, chain, kind, argc, varargs,
                 guarded, top):
        self.rel, self.line, self.module = rel, line, module
        self.ident, self.chain = ident, chain    # chain: ["data", "field"]
        self.kind = kind                         # "call" | "read" | "write"
        self.argc, self.varargs = argc, varargs
        # `X.y and X.y(...)` is feature detection, not a nil call
        self.guarded = guarded
        # at file scope, so it runs while the entry chunk does
        self.top = top

    @property
    def member(self):
        return ".".join(self.chain)

    def where(self):
        return f"{self.rel}:{self.line}"


# every engine module name the mod spells, however it reaches for it: each one
# is either resolved below or comes back as an unresolved note
MODULE_LITERAL = re.compile(r"""["'](src[./][\w./]+)["']""")
HEAD_PCALL = re.compile(r"""\bpcall\s*\(\s*require\s*,\s*$""")
HEAD_REQUIRE = re.compile(r"""\brequire\s*\(?\s*$""")
HEAD_CALL = re.compile(r"""\b([A-Za-z_][\w.:]*)\s*\(\s*$""")
# the name at the tail of one slot of an assignment's name list
BIND_NAME = re.compile(
    r"""(?:^|[\s=({,;])(?:local\s+)?([A-Za-z_]\w*)\s*$""")
# require("src.world.Map").waterTiles(1) and its bracket twin
TAIL_MEMBER = re.compile(r"""^\s*\)?\s*([.:])\s*(\w+)""")
TAIL_INDEX = re.compile(r"""^\s*\)?\s*\[\s*["'](\w+)["']\s*\]""")
# local F = Follower: a module carried on through a second name
ALIAS_BIND = re.compile(
    r"""(?:^|[\s;])(?:local\s+)?([A-Za-z_]\w*)\s*=\s*([A-Za-z_]\w*)\s*"""
    r"""(?=[\r\n;]|$)""", re.M)
# local function tryRequire(path) return require(path) end: a mod's own wrapper,
# which the call sites below are followed through
WRAPPER_DEF = re.compile(
    r"""\blocal\s+(?:function\s+([A-Za-z_]\w*)\s*\(\s*([A-Za-z_]\w*)"""
    r"""|([A-Za-z_]\w*)\s*=\s*function\s*\(\s*([A-Za-z_]\w*))""")
# patchUpvalue(Follower.update, "shouldSpawn", fn): the shape a mod reaches an
# engine file-local through, and the only place the upvalue is named
UPVALUE_CALL = re.compile(
    r"\bdebug\s*\.\s*(?:setupvalue|getupvalue|upvaluejoin)\b")
UPVALUE_ARGS = re.compile(
    r"""^\s*([A-Za-z_]\w*)\s*\.\s*(\w+)\s*,\s*["'](\w+)["']""")
VERSION_MATCH = re.compile(
    r"""[=~]=\s*["'](red|blue|yellow|gold|silver)["']"""
    r"""|["'](red|blue|yellow|gold|silver)["']\s*[=~]=""")


def _line_of(body, offset):
    return body.count("\n", 0, offset) + 1


BLOCK_WORD = re.compile(r"\b(function|do|if|repeat|end|until)\b")


def _blank_strings(text):
    """The same text with literal bodies blanked, positions intact: a string
    holding the word `end` must not close a block."""
    out, index, size = [], 0, len(text)
    while index < size:
        char = text[index]
        if char in "\"'":
            quote, start = char, index
            index += 1
            while index < size:
                if text[index] == "\\":
                    index += 2
                    continue
                index += 1
                if text[index - 1] == quote:
                    break
            chunk = text[start:index]
            out.append(quote + " " * (len(chunk) - 2) + quote
                       if len(chunk) > 1 else chunk)
            continue
        out.append(char)
        index += 1
    return "".join(out)


def _function_spans(text):
    """Byte ranges a function body covers, so a use inside one can be told
    from a use at file scope.  Keyword counting rather than parsing: every
    `function` / `do` / `if` / `repeat` is closed by exactly one `end` or
    `until`, which is all this has to get right."""
    stack, spans = [], []
    for match in BLOCK_WORD.finditer(_blank_strings(text)):
        word = match.group(1)
        if word in ("end", "until"):
            if stack:
                kind, start = stack.pop()
                if kind == "function":
                    spans.append((start, match.end()))
        else:
            stack.append(("function" if word == "function" else "block",
                          match.start()))
    return spans


def _local_functions(body, spans):
    """(name, parameters, body) for every `local function f(x, y)` and `local f
    = function(x, y)` in the file, the body bounded by the function's own span
    so a call further down the file is never read as part of it."""
    ends = dict(spans)
    out = []
    for match in WRAPPER_DEF.finditer(body):
        keyword = body.find("function", match.start(), match.end())
        stop = ends.get(keyword)
        inner = body[match.end():stop] if stop else ""
        params = [match.group(2) or match.group(4)]
        close = inner.find(")")
        if close >= 0:
            params += [p.strip() for p in inner[:close].split(",") if p.strip()]
        out.append((match.group(1) or match.group(3), params, inner))
    return out


def _require_wrappers(files):
    """The names a mod gives its own require wrapper (`local function
    tryRequire(p) return require(p) end`), read across the whole mod so a
    wrapper declared in one file is followed at call sites in another."""
    names = set()
    for body, spans in files:
        for name, params, inner in _local_functions(body, spans):
            if re.search(r"\brequire\s*[(,]\s*%s\b" % re.escape(params[0]),
                         inner):
                names.add(name)
    return names


def _call_args(text, start):
    """The arguments of the call whose name ends at `start`, split at depth 0;
    None when the parentheses do not balance."""
    paren = text.find("(", start)
    if paren < 0 or text[start:paren].strip():
        return None
    close = _lua_close(text, paren)
    if close is None:
        return None
    args = text[paren + 1:close]
    cuts = _depth_commas(_blank_strings(args))
    return [args[a + 1:b].strip()
            for a, b in zip([-1] + cuts, cuts + [len(args)])]


def _forwards_upvalue_name(inner, params):
    """Does this helper's second parameter really reach the debug call as an
    upvalue NAME: handed straight to the name slot, or matched against what
    getupvalue answers to find the index.  A parameter that only ever lands in
    the value slot names nothing, so its call sites are not upvalue surgery."""
    if len(params) < 2:
        return False
    name, taken = params[1], False
    for match in UPVALUE_CALL.finditer(inner):
        args = _call_args(inner, match.end())
        if not args or args[0] != params[0]:
            continue
        if len(args) >= 2 and args[1] == name:
            return True
        taken = True
    return taken and bool(re.search(r"\bdebug\s*\.\s*getupvalue\b", inner)) \
        and bool(re.search(r"(?:[=~]=\s*%s|%s\s*[=~]=)\b"
                           % (re.escape(name), re.escape(name)), inner))


def _upvalue_helpers(files):
    """(confirmed, suspect) helper names.  Confirmed is a local function that
    forwards its own (function, name) parameters into a debug upvalue call, so
    its call sites really do name an engine local; anything else that touches
    the debug library is a suspect, whose call sites come back unresolved
    rather than being read as named upvalue surgery."""
    names, suspects = set(), set()
    for body, spans in files:
        for name, params, inner in _local_functions(body, spans):
            if not (UPVALUE_CALL.search(inner) or "upvalue" in name.lower()):
                continue
            (names if _forwards_upvalue_name(inner, params)
             else suspects).add(name)
    return names, suspects - names


def _upvalue_calls(body, helpers, suspects=()):
    """(offset, argument text, confirmed) for every call that reaches an
    upvalue: the debug library itself and the mod's own helpers around it.
    Only these sites name a local of an engine module, so no other `X.y, "z"`
    shape is read as upvalue surgery."""
    calls = []
    names = [r"debug\s*\.\s*(?:setupvalue|getupvalue|upvaluejoin)"] + \
        [re.escape(name) for name in sorted(set(helpers) | set(suspects))]
    for match in re.finditer(r"\b(%s)\s*\(" % "|".join(names), body):
        if re.search(r"\bfunction\s+$", body[:match.start()]):
            continue    # the helper's own definition, not a call of it
        close = _lua_close(body, match.end() - 1)
        if close is None:
            continue
        calls.append((match.start(), body[match.end():close],
                      match.group(1) not in suspects))
    return calls


def _depth_commas(text):
    """Offsets of the commas at bracket depth 0 in already-blanked text."""
    depth, out = 0, []
    for index, char in enumerate(text):
        if char in "([{":
            depth += 1
        elif char in ")]}":
            depth -= 1
        elif char == "," and depth == 0:
            out.append(index)
    return out


def _name_list(head):
    """(names left to right, truncated) for the assignment whose `=` this text
    ends before.  Read straight back as tokens, so `a, b, c =` is three names
    and the walk stops the moment a name slot holds anything else (`t.x`,
    `t[1]`, a table field left of the one being written)."""
    names, text = [], head
    while True:
        match = BIND_NAME.search(text)
        if not match:
            return list(reversed(names)), True
        before = text[:match.start(1)].rstrip()
        if before[-1:] in (".", ":", "]", ")"):
            return list(reversed(names)), True    # t.x and friends: not a name
        names.append(match.group(1))
        if not before.endswith(","):
            return list(reversed(names)), False
        text = before[:-1]


def _bind_target(pre, slot=0):
    """The name a require's result takes, paired positionally so
    `local A, B = require(X), require(Y)` gives X to A and Y to B.  `slot` is
    where the value sits among its own call's returns (1 for the module a
    pcall hands back).  (name, None), or (None, why) when no pair can be made,
    which the caller turns into an unresolved note rather than a guess."""
    blank = _blank_strings(pre).rstrip()
    # the value sits in an assignment only if it follows that `=` or a comma
    # in its value list; anything else (`return require(...)`) binds nothing
    if not (blank.endswith(",")
            or (blank.endswith("=") and blank[-2:-1] not in ("=", "~", "<",
                                                             ">"))):
        return None, "unbound"
    depth, eq, index = 0, None, len(blank) - 1
    while index >= 0:
        char = blank[index]
        if char in ")]}":
            depth += 1
        elif char in "([{":
            depth -= 1
            if depth < 0:
                return None, "unbound"
        elif (char == "=" and depth == 0
              and blank[index - 1:index] not in ("=", "~", "<", ">")
              and blank[index + 1:index + 2] != "="):
            eq = index
            break
        index -= 1
    if eq is None:
        return None, "unbound"
    position = slot + len(_depth_commas(blank[eq + 1:]))
    names, truncated = _name_list(blank[:eq])
    if truncated and (position or len(names) != 1):
        return None, "unpaired"
    if position >= len(names):
        return None, "unpaired"
    return names[position], None


def _module_literals(body, wrappers):
    """Split every `src.` module name this file spells into what the scan can
    attach to a name (binds), what it can attach straight to a member (inline)
    and what it cannot follow at all (unfollowed), so no reach falls out
    silently.  Returns binds, inline, unfollowed."""
    binds, inline, unfollowed = {}, [], []
    for match in MODULE_LITERAL.finditer(body):
        module = match.group(1).replace("/", ".")
        head, after = body[:match.start()], body[match.end():]
        pcall_head = HEAD_PCALL.search(head)
        require_head = None if pcall_head else HEAD_REQUIRE.search(head)
        call_head = None
        if pcall_head:
            pre = head[:pcall_head.start()]
        elif require_head:
            pre = head[:require_head.start()]
        else:
            call_head = HEAD_CALL.search(head)
            callee = re.split(r"[.:]", call_head.group(1))[-1] \
                if call_head else None
            if callee in wrappers:
                pre = head[:call_head.start()]
            elif call_head:
                unfollowed.append((match.start(), "engine module names "
                                   "handed to a call this scan does not "
                                   "follow"))
                continue
            else:
                unfollowed.append((match.start(), "engine module names "
                                   "spelled in a literal this scan cannot tie "
                                   "to a require"))
                continue
        colon, member, consumed = False, None, 0
        tail = TAIL_MEMBER.match(after)
        index = None if tail else TAIL_INDEX.match(after)
        if tail:
            colon, member, consumed = tail.group(1) == ":", tail.group(2), \
                tail.end()
        elif index:
            member, consumed = index.group(1), index.end()
        if pcall_head:
            # only the last value of a list keeps its second return
            paren = head.find("(", pcall_head.start())
            close = _lua_close(body, paren) if paren >= 0 else None
            bind, why = (None, "unpaired") \
                if close is None or body[close + 1:close + 64].lstrip()[:1] == "," \
                else _bind_target(pre, 1)
        else:
            bind, why = _bind_target(pre)
        if member:
            inline.append((len(pre), module, colon, member,
                           match.end() + consumed))
            # only worth saying when something later reaches off that name
            if bind and re.search(r"\b%s\s*[.:]" % re.escape(bind),
                                  after[consumed:]):
                unfollowed.append((match.start(), "names bound to a member "
                                   "of an engine module and not the module, "
                                   "so reaches off them are not followed"))
        elif bind:
            binds.setdefault(bind, []).append((match.start(), module, True))
        elif why == "unpaired":
            unfollowed.append((match.start(), "requires in a multiple "
                               "assignment whose value this scan cannot pair "
                               "to a name"))
        else:
            unfollowed.append((match.start(), "requires whose result is "
                               "neither bound to a name nor indexed here, so "
                               "where the module goes is not followed"))
    return binds, inline, unfollowed


def _alias_binds(body, binds):
    """`local F = Follower` carries a module on to a second name.  Repeated to
    a fixpoint so a chain of hops resolves, and only ever backwards: a name is
    bound at the point the alias is written."""
    while True:
        added = False
        for match in ALIAS_BIND.finditer(body):
            ident, source = match.group(1), match.group(2)
            if ident == source or source not in binds:
                continue
            module = module_at(binds[source], match.start(2))
            site = (match.start(1), module)
            if module and site not in binds.get(ident, []):
                binds.setdefault(ident, []).append(site)
                added = True
        if not added:
            break
    for sites in binds.values():
        sites.sort()
    return binds


def _member_use(body, spans, rel, module, ident, start, end, member, colon):
    """One Use from a reach: `start`..`end` covers the name and the member
    taken off it, whether that name is a local, a bracket index or the require
    call itself."""
    rest = body[end:]
    head = body[:start].rstrip()
    chain = [member]
    tail = re.match(r"((?:\.\w+){1,2})", rest)
    if tail:
        chain += tail.group(1).lstrip(".").split(".")
        rest = rest[tail.end():]
    argc, varargs = None, False
    if head.endswith("function") or re.match(r"\s*=(?!=)", rest):
        kind = "write"
    elif re.match(r"\s*\(", rest):
        kind = "call"
        argc, varargs = _lua_args(body,
                                  len(body) - len(rest) + rest.index("("))
        if colon and argc is not None:
            argc += 1
    elif re.match(r"""\s*["'{]""", rest):
        kind, argc = "call", 1 + (1 if colon else 0)
    else:
        kind = "read"
    guarded = bool(re.match(r"\s*(and|or|then|\)|~=|==)", rest)) \
        or bool(re.search(r"\b(if|and|or|not)\s*$", head))
    top = not any(begin <= start < stop for begin, stop in spans)
    return Use(rel, _line_of(body, start), module, ident, chain, kind, argc,
               varargs, guarded, top)


def _dynamic_requires(body):
    """Offsets of the requires whose name this scan cannot take whole: one
    handed in as a value, and any argument list that concatenates, however it
    starts (`require("src" .. tail)` is as unfollowable as `require(name)`)."""
    out = []
    for match in re.finditer(r"\brequire\s*\(", body):
        close = _lua_close(body, match.end() - 1)
        if close is None:
            out.append(match.start())
            continue
        args = _blank_strings(body[match.end():close])
        if ".." in args or not re.match(r"""\s*["']""", args):
            out.append(match.start())
    return out


RAW_ACCESS = "engine modules reached with %s, which goes straight to the " \
    "table the require shim hands back: where a Gen 2 boot serves the module " \
    "through a Gen2Compat facade, that %s the facade and not the module " \
    "behind it"


def _raw_access(body, ident, sites):
    """rawget/rawset on a bound module: the one reach that skips the facade's
    metatable, so it never sees the Gen 2 module the adapter stands in for."""
    out = []
    for match in re.finditer(r"\braw(get|set)\s*\(\s*%s\s*[,)]"
                             % re.escape(ident), body):
        if module_at(sites, match.start()):
            out.append((match.start(), RAW_ACCESS % (
                "rawset", "is where the write lands, on")
                if match.group(1) == "set" else RAW_ACCESS % (
                "rawget", "is all the read sees,")))
    return out


def _value_reads(body, ident, sites, followed):
    """Occurrences of a bound module name in none of the shapes this scan
    follows: parked on a table, passed to a call, delegated to through a
    metatable.  The module escapes there, so what is reached off it later is
    not this scan's to see."""
    out, blank = [], _blank_strings(body)
    aliased = {match.start(2) for match in ALIAS_BIND.finditer(body)
               if match.group(2) == ident}
    for match in re.finditer(r"(?<![\w.:])%s\b" % re.escape(ident), blank):
        start, rest = match.start(), blank[match.end():]
        if start in followed or start in aliased \
                or not module_at(sites, start):
            continue
        if re.match(r"\s*[.:\[]", rest) or re.match(r"\s*=(?!=)", rest) \
                or re.search(r"\braw(?:get|set)\s*\(\s*$", blank[:start]):
            continue    # followed above, rebound here, or noted as a raw reach
        line = blank.rfind("\n", 0, start) + 1
        before = blank[line:start]
        while line > 0 and re.match(r"\s*(and|or|not)\b", before):
            line = blank.rfind("\n", 0, line - 1) + 1
            before = blank[line:start]    # a condition carried over a line
        if re.search(r"(?<![\w.:])%s\s*(?:[.:]\s*\w+|\[[^\]\n]*\])\s*\(\s*$"
                     % re.escape(ident), before):
            continue    # M.f(M): the explicit self of a reach already followed
        if re.search(r"\bfunction\b[^()\n]*\([^)\n]*$", before):
            continue    # a parameter of that name shadowing the module here
        test = re.search(r"\b(if|elseif|while|until)\b", before)
        if test and not re.search(r"[^=~<>]=(?!=)|\breturn\b",
                                  before[test.end():]):
            continue    # a presence test: nothing escapes a condition
        out.append((start, "engine modules read as a value rather than "
                    "indexed, so where the module goes from there (a table "
                    "field, a call argument, a metatable's __index) is not "
                    "followed"))
    return out


def scan_module_uses(mod_dir):
    """Every reach the mod makes at an engine module, every member it then
    touches, and every upvalue it names beside one.

    This is a regex over source, not an interpreter.  It follows a require
    bound to a name (by position, so one statement may bind several), a
    require the mod wraps in its own helper, a require indexed on the spot, a
    bracket index with a literal name and a module carried on through a second
    local.  What it cannot follow -- a name built at runtime or concatenated,
    a value it cannot pair to a name, a module read as a value, a raw index
    past the facade, an index whose key is computed, a helper it cannot
    confirm names an upvalue -- comes back as an unresolved note, so silence
    over a reach is never this tool's approval of it."""
    requires, uses, upvalues, notes = [], [], [], []
    dynamic, blind, unsure, unfollowed = [], [], [], []
    files = [rel for rel in mod_files(mod_dir)
             if os.path.splitext(rel)[1].lower() == ".lua"]
    bodies = {}
    for rel in files:
        body = strip_lua(open(os.path.join(mod_dir, rel), encoding="utf-8",
                              errors="replace").read())
        bodies[rel] = (body, _function_spans(body))
    wrappers = _require_wrappers(bodies.values())
    helpers, suspects = _upvalue_helpers(bodies.values())
    for rel in files:
        body, spans = bodies[rel]
        binds, inline, unresolved = _module_literals(body, wrappers)
        for offset, why in unresolved:
            unfollowed.append((why, "%s:%d" % (rel, _line_of(body, offset))))
        for offset, module, colon, member, end in inline:
            if not module.startswith("src."):
                continue
            requires.append((rel, _line_of(body, offset), module))
            uses.append(_member_use(body, spans, rel, module,
                                    module.split(".")[-1], offset, end,
                                    member, colon))
        for ident, sites in binds.items():
            for offset, module, literal in sites:
                if literal and module.startswith("src."):
                    requires.append((rel, _line_of(body, offset), module))
        binds = {ident: [(offset, module) for offset, module, _ in sites
                         if module.startswith("src.")]
                 for ident, sites in binds.items()}
        binds = {ident: sites for ident, sites in binds.items() if sites}
        binds = _alias_binds(body, binds)
        for offset in _dynamic_requires(body):
            dynamic.append("%s:%d" % (rel, _line_of(body, offset)))
        for ident, sites in binds.items():
            followed = []
            for match in re.finditer(
                    r"\b%s\s*(?:([.:])\s*(\w+)|\[\s*[\"'](\w+)[\"']\s*\])"
                    % re.escape(ident), body):
                module = module_at(sites, match.start())
                if not module:
                    continue
                followed.append(match.start())
                uses.append(_member_use(
                    body, spans, rel, module, ident, match.start(),
                    match.end(), match.group(2) or match.group(3),
                    match.group(1) == ":"))
            for match in re.finditer(r"\b%s\s*\[\s*(?![\"'])" % re.escape(ident),
                                     body):
                if module_at(sites, match.start()):
                    followed.append(match.start())
                    unfollowed.append((
                        "engine modules indexed with a key this scan cannot "
                        "read",
                        "%s:%d" % (rel, _line_of(body, match.start()))))
            for offset, why in _raw_access(body, ident, sites) \
                    + _value_reads(body, ident, sites, followed):
                unfollowed.append((why, "%s:%d" % (rel, _line_of(body, offset))))
        for offset, args, confirmed in _upvalue_calls(body, helpers, suspects):
            pair = UPVALUE_ARGS.match(args) if confirmed else None
            module = module_at(binds.get(pair.group(1), []), offset) \
                if pair else None
            if module:
                upvalues.append((rel, _line_of(body, offset), module,
                                 pair.group(2), pair.group(3)))
            elif confirmed:
                blind.append("%s:%d" % (rel, _line_of(body, offset)))
            else:
                unsure.append("%s:%d" % (rel, _line_of(body, offset)))
    if dynamic:
        notes.append("unresolved: %s building a require name at runtime, "
                     "which this scan cannot follow (%s)"
                     % (_count(len(dynamic), "site"), _places(dynamic)))
    for why in sorted({why for why, _ in unfollowed}):
        places = [place for reason, place in unfollowed if reason == why]
        notes.append("unresolved: %s: %s (%s)"
                     % (_count(len(places), "site"), why, _places(places)))
    if blind:
        notes.append("unresolved: %s whose target function this scan could "
                     "not tie to an engine module, so the local they reach "
                     "could not be resolved (%s)"
                     % (_count(len(blind), "debug upvalue call"),
                        _places(blind)))
    if unsure:
        notes.append("unresolved: %s through a mod helper this scan could not "
                     "confirm carries an upvalue name through to the debug "
                     "call, so what they patch is unknown (%s)"
                     % (_count(len(unsure), "call"), _places(unsure)))
    return requires, uses, upvalues, notes


def _places(items, limit=4):
    """A file:line list that stays one line however many there are."""
    shown = ", ".join(items[:limit])
    return shown if len(items) <= limit else \
        "%s and %d more" % (shown, len(items) - limit)


def module_at(sites, offset):
    """The module the name was bound to at this point in the file."""
    module = None
    for start, name in sites:
        if start <= offset:
            module = name
    return module


# ------------------------------------------------------------- the checks

GEN2_IDS_DUMP = '''\
package.path = "./?.lua;./?/init.lua;" .. package.path
print(table.concat(require("src.mods.ModTargets").generationVersions(2), " "))
'''

_GEN2_IDS = None


def gen2_version_ids(repo):
    """The Gen 2 version ids, read out of the engine (src/mods/ModTargets.lua)
    rather than restated here.  Empty when luajit cannot answer, which leaves
    the "gen2"/"all" tokens to decide alone."""
    global _GEN2_IDS
    if _GEN2_IDS is None:
        _GEN2_IDS = []
        try:
            proc = subprocess.run([LUAJIT, "-e", GEN2_IDS_DUMP], cwd=repo,
                                  capture_output=True, text=True, timeout=30)
            if proc.returncode == 0:
                _GEN2_IDS = proc.stdout.split()
        except (OSError, subprocess.SubprocessError):
            pass
    return _GEN2_IDS


def declares_gen2(repo, manifest):
    """Does this manifest claim a Gen 2 game: the `games` list, or the legacy
    gen2compat flag it is derived from (src/mods/Manifest.lua)."""
    if not manifest:
        return False
    if manifest.get("gen2compat"):
        return True
    games = manifest.get("games")
    if not isinstance(games, list):
        return False
    ids = set(gen2_version_ids(repo))
    for token in games:
        if isinstance(token, str) and (
                token.strip().lower() in ("gen2", "all")
                or token.strip().lower() in ids):
            return True
    return False


def check_gen2_manifest(repo, mod_dir, manifest, named):
    """MK400/MK401: what the loader decides before a line of the mod runs
    (src/mods/Loader.lua's generation gate).  `named` is every mod on this
    command line, so checking a mod together with its dependencies reads them
    as one install set."""
    findings, notes = [], []
    if not declares_gen2(repo, manifest):
        findings.append(Finding(
            "MK400", "error",
            "no Gen 2 game in \"games\" (and no gen2compat), so a Gen 2 boot "
            "skips this mod; the rest of this report is what it would hit "
            "once it claims one",
            "manifest.json"))
    deps = manifest.get("dependencies") or []
    for dep in deps if isinstance(deps, list) else []:
        dep_id = dep if isinstance(dep, str) else dep.get("id") if isinstance(dep, dict) else None
        if not dep_id:
            continue
        if isinstance(dep, dict) and "games" in dep:
            g_list = dep.get("games")
            if isinstance(g_list, str):
                g_list = [g_list]
            if isinstance(g_list, list) and not any(g in ["gen2", "gold", "silver", "crystal", "all"] for g in g_list):
                continue
        found = named.get(dep_id) or find_mod_by_id(repo, mod_dir, dep_id)
        if found is None:
            notes.append("unresolved: dependency %s is not installed beside "
                         "this mod, so its games list could not be read" % dep_id)
        elif not declares_gen2(repo, found):
            findings.append(Finding(
                "MK401", "error",
                f"depends on {dep_id}, which claims no Gen 2 game; the "
                f"loader disables a mod whose dependency a Gen 2 boot skipped",
                "manifest.json"))
    return findings, notes


def find_mod_by_id(repo, mod_dir, mod_id):
    """The manifest of another installed mod, or None.  An install root is
    one directory of <id>/manifest.json, which is all the loader itself walks,
    so this looks beside the mod and in the repo's mods/ and no deeper: a
    second copy under some build tree is not what would load."""
    roots = [os.path.dirname(os.path.abspath(mod_dir)),
             os.path.join(repo, "mods")]
    seen = set()
    for root in roots:
        if not os.path.isdir(root) or root in seen:
            continue
        seen.add(root)
        for name in sorted(os.listdir(root)):
            path = os.path.join(root, name, "manifest.json")
            if name in SKIP_DIRS or not os.path.isfile(path):
                continue
            try:
                found = json.load(open(path, encoding="utf-8"))
            except (OSError, ValueError):
                continue
            if found.get("id") == mod_id:
                return found
    return None


def check_gen2_requires(repo, coverage, requires):
    """MK402: a Gen 1 module a Gen 2 boot never instantiates and no adapter
    backs -- the require succeeds, the patch lands on dead code, and the
    loader says so in the manager's error feed.  MK403: the same silence
    without the loader's warning, spotted from the gen2/ sibling that runs
    instead."""
    findings, notes = [], []
    gen1_only = gen1_only_modules(repo)
    seen = set()
    for rel, line, module in requires:
        if module in coverage or (rel, module) in seen:
            continue
        seen.add((rel, module))
        if module not in gen1_only and not _module_exists(repo, module):
            notes.append("unresolved: %s:%d names %s, which is neither an "
                         "adapter nor a module in this checkout, so nothing "
                         "reached off it was checked" % (rel, line, module))
            continue
        if module in gen1_only:
            findings.append(Finding(
                "MK402", "error",
                f"requires {module}, which a Gen 2 boot never runs and "
                f"src/mods/Gen2Compat.lua has no adapter for; take the game "
                f"from the game.ready payload and mod.world instead",
                f"{rel}:{line}"))
            continue
        parts = module.split(".")
        if len(parts) < 3:
            continue
        sibling = ".".join(parts[:-1] + ["gen2", parts[-1]])
        if os.path.isfile(module_path(repo, sibling)):
            findings.append(Finding(
                "MK403", "warn",
                f"requires {module}, but a Gen 2 game runs {sibling}; the "
                f"require succeeds and hands back a module nothing "
                f"instantiates",
                f"{rel}:{line}"))
    return findings, notes


def check_gen2_members(repo, coverage, uses, advise=False):
    """MK404: a member the adapter says has no Gen 2 backing, so the read is
    nil and the call raises.  MK405: one that is there and degrades, in the
    adapter's own words.  MK406: one whose parameters moved under it -- the
    trap an alias sets, because it runs and means something else."""
    findings, notes = [], []
    owned = {(use.module, use.member) for use in uses if use.kind == "write"}
    for use in uses:
        record = coverage.get(use.module)
        if not record:
            continue    # a shared module, or one the requires pass noted

        members = record["members"]
        if members is None:
            notes.append("unresolved: no coverage row for %s, so %s.%s could "
                         "not be checked" % (use.module, use.ident,
                                             use.member))
            continue
        member, status = _resolve_member(members, use.chain)
        note = _plain_note(record["notes"].get(member)) if member else None
        target = record["target"] or "the adapter"
        if status is None:
            gen1 = lua_api(module_path(repo, use.module)) or {}
            api = lua_api(module_path(repo, record["target"])) or {} \
                if record["target"] else {}
            if use.chain[0] in api or (use.module, use.chain[0]) in owned:
                continue    # the Gen 2 module carries it, or the mod put it there
            if use.chain[0] not in gen1:
                continue    # the mod's own field on a table it did not declare
            notes.append("unresolved: %s.%s is a Gen 1 member the coverage "
                         "table does not classify" % (use.ident, use.member))
            continue
        if status == ABSENT:
            findings.append(Finding(
                "MK404", "warn" if use.guarded else "error",
                "%s.%s has no Gen 2 backing: %s"
                % (use.ident, use.member, note or "%s has no %s"
                   % (target, member))
                + ("; the guarded branch never runs" if use.guarded
                   else "; nothing on a Gen 2 boot reads this write"
                   if use.kind == "write" else "; this reads nil"
                   + (" and the call raises" if use.kind == "call" else "")),
                use.where()))
            continue
        if status != "backed":
            findings.append(Finding(
                "MK405", "warn",
                "%s.%s is %s on a Gen 2 boot: %s"
                % (use.ident, use.member, status,
                   note or "it answers nil and names itself once in the log"),
                use.where()))
            continue
        held = _held_at_file_scope(repo, record, use)
        if held:
            findings.append(held)
            continue
        shapes = _signature_diff(repo, record, use)
        if shapes:
            # an alias hands the mod the Gen 2 module itself: no shim stands
            # between this call and the parameters that moved under it
            findings.append(Finding(
                "MK406", "warn",
                shapes + ("; " + note if note else ""), use.where()))
        elif advise and note:
            notes.append("%s.%s: %s" % (use.ident, use.member, note))
    return findings, notes


def _held_at_file_scope(repo, record, use):
    """MK410: the entry chunk reading a member the Gen 1 module only ever
    writes onto the running game.  A facade resolves against the live instance
    at read time and there is none yet while the mod is loading, so the value
    captured is nil for the life of the process; the same read from inside a
    hook or an event is correct (docs/mod-api-gen2-compat.md, "live, never a
    snapshot")."""
    if not use.top or use.kind == "write" or record["kind"] != "facade":
        return None
    entry = (lua_api(module_path(repo, use.module)) or {}).get(use.chain[0])
    if not entry or entry["kind"] != "field":
        return None
    return Finding(
        "MK410", "warn",
        f"reads {use.ident}.{use.member} at file scope, where a Gen 2 boot "
        f"has no game yet: the facade answers nil until one exists, so take "
        f"this from the game.ready payload instead of the entry chunk",
        use.where())


def _plain_note(note):
    """The adapter writes a status word in front of some of its notes; the
    finding already carries the status, so it is not said twice."""
    if not note:
        return None
    return re.sub(r"^(ABSENT|WARNED|BACKED)\b[:.]?\s*", "", note.strip())


def _resolve_member(members, chain):
    """Longest dotted path the coverage table classifies: Game.save.money is a
    row of its own where Game.save is another."""
    for size in range(len(chain), 0, -1):
        name = ".".join(chain[:size])
        if name in members:
            return name, members[name]
    return None, None


def _signature_diff(repo, record, use):
    """The sentence for a call whose parameters moved: the Gen 2 module spells
    them in an order the Gen 1 call site cannot survive, or takes a different
    number of them.  Equal shape with different names is a rename as often as
    a change, and this tool does not guess between the two.

    An alias only: a facade is free to override the member with the Gen 1
    shape (src/mods/Gen2Compat.lua's Boxes.deposit does exactly that), so the
    Gen 2 module's parameters are not what the mod would be calling."""
    if (use.kind != "call" or record["kind"] != "alias"
            or not record["target"] or len(use.chain) != 1):
        return None
    want = (lua_api(module_path(repo, record["target"])) or {}).get(
        use.member, {}).get("params")
    have = (lua_api(module_path(repo, use.module)) or {}).get(
        use.member, {}).get("params")
    if want is None or have is None or want == have:
        return None
    shapes = ("%s.%s is (%s) on a Gen 2 boot and (%s) on Gen 1"
              % (use.ident, use.member, ", ".join(want), ", ".join(have)))
    if _reordered(want, have):
        return shapes + "; the shared parameters sit in different places"
    if (use.argc is not None and not use.varargs
            and use.argc == len(have) and use.argc != len(want)):
        return shapes + "; this call passes the Gen 1 argument list"
    return None


def _reordered(want, have):
    """True when the two parameter lists share names sitting in different
    places."""
    shared = [name for name in want if name in have and name != "self"]
    return any(want.index(name) != have.index(name) for name in shared)


UPVALUE_DUMP = '''\
package.path = "./?.lua;./?/init.lua;" .. package.path
local ok, G = pcall(require, "src.mods.Gen2Compat")
if not ok then os.exit(3) end
for line in io.lines() do
  local module, member = line:match("^(%S+)\\t(%S+)$")
  if module then
    local status, names = "nomodule", {}
    local got, adapter = pcall(G.resolve, module)
    if got and type(adapter) == "table" then
      local read, value = pcall(function() return adapter[member] end)
      if not read then status = "nomember"
      elseif value == nil then status = "nomember"
      elseif type(value) ~= "function" then status = "notfunction"
      else
        status = "ok"
        local i = 1
        while true do
          local name = debug.getupvalue(value, i)
          if not name then break end
          names[#names + 1] = name
          i = i + 1
        end
      end
    end
    print(module .. "\\t" .. member .. "\\t" .. status .. "\\t"
      .. table.concat(names, " "))
  end
end
'''

_UPVALUE_CACHE = {}


def gen2_upvalues(repo, queries):
    """(status, upvalue names) for each (module, member) a mod reaches, taken
    by resolving the adapter the way src/mods/Loader.lua does and enumerating
    the function's real upvalues.  A pair luajit could not answer for stays out
    of the table, which the caller reports as unknown and never as landing."""
    wanted = sorted({pair for pair in queries
                     if pair[0] and pair not in _UPVALUE_CACHE})
    if not wanted:
        return _UPVALUE_CACHE
    with tempfile.NamedTemporaryFile("w", suffix=".lua", delete=False,
                                     encoding="utf-8") as handle:
        handle.write(UPVALUE_DUMP)
        dump_path = handle.name
    try:
        proc = subprocess.run(
            [LUAJIT, dump_path], cwd=repo, capture_output=True, text=True,
            timeout=60,
            input="".join("%s\t%s\n" % pair for pair in wanted))
        if proc.returncode == 0:
            for row in proc.stdout.splitlines():
                parts = row.split("\t")
                if len(parts) >= 4:
                    _UPVALUE_CACHE[(parts[0], parts[1])] = (
                        parts[2], parts[3].split())
    except (OSError, subprocess.SubprocessError):
        pass
    finally:
        os.unlink(dump_path)
    return _UPVALUE_CACHE


def check_gen2_upvalues(repo, coverage, upvalues):
    """MK407/MK408: reaching an engine function's file-local with
    debug.setupvalue.  The function is resolved through the adapter and its
    upvalues enumerated, so a member the Gen 2 arm does not carry is the error
    it is at runtime and a local that is not an upvalue of it never reads as
    landing."""
    findings, notes = [], []
    table = gen2_upvalues(repo, [(module, member) for _, _, module, member, _
                                 in upvalues if module in coverage])
    lands = {}
    for rel, line, module, member, upvalue in upvalues:
        record = coverage.get(module)
        if not record:
            continue    # a shared module, or one the requires pass noted

        target = record["target"] or "the adapter"
        status, names = table.get((module, member), (None, []))
        if status in (None, "nomodule"):
            findings.append(Finding(
                "MK408", "warn",
                f"reaches the upvalue {upvalue!r} on {member}; this scan could "
                f"not resolve {module}.{member} on a Gen 2 boot, so whether "
                f"the surgery lands is unknown",
                f"{rel}:{line}"))
            continue
        if status != "ok":
            findings.append(Finding(
                "MK407", "error",
                f"reaches the upvalue {upvalue!r} on {member}, but a Gen 2 "
                f"boot resolves {module}.{member} to "
                + ("nil" if status == "nomember" else "a value that is not a "
                   "function")
                + f" ({target} carries no such function), so the "
                f"debug.setupvalue call raises",
                f"{rel}:{line}"))
            continue
        if upvalue in names:
            lands.setdefault((upvalue, module, member), []).append(
                "%s:%d" % (rel, line))
            continue
        setter = "set" + upvalue[:1].upper() + upvalue[1:]
        api = lua_api(module_path(repo, record["target"])) or {} \
            if record["target"] else {}
        findings.append(Finding(
            "MK407", "error",
            f"reaches the upvalue {upvalue!r} on {member}, but on a Gen 2 boot "
            f"{module}.{member} closes over "
            + (", ".join(sorted(names)[:6]) if names else "nothing")
            + ", so the surgery lands on nothing"
            + (f"; {target.split('.')[-1]}.{setter} is the supported route"
               if setter in api else ""),
            f"{rel}:{line}"))
    for (upvalue, module, member), places in sorted(lands.items()):
        notes.append("%s.%s closes over %r on a Gen 2 boot, so the upvalue "
                     "surgery at %s lands as it does on Gen 1"
                     % (module, member, upvalue, _places(places)))
    return findings, notes


def check_gen2_patterns(repo, mod_dir):
    """MK409: the two shapes no adapter is allowed to fix, because the mod
    decided something about the game and a Gen 2 boot answers differently
    (docs/mod-api-gen2-compat.md, "what the facades cannot fix")."""
    findings = []
    twins = gen2_screen_twins(repo)
    for rel in mod_files(mod_dir):
        if os.path.splitext(rel)[1].lower() != ".lua":
            continue
        body = strip_lua(open(os.path.join(mod_dir, rel), encoding="utf-8",
                              errors="replace").read())
        for match in VERSION_MATCH.finditer(body):
            findings.append(Finding(
                "MK409", "warn",
                "allow-lists a Gen 1 version string, which excludes this mod "
                "from a Gen 2 game by construction; test for the capability "
                "the code needs instead of the version",
                "%s:%d" % (rel, _line_of(body, match.start()))))
        # the id itself, not a word in the line around it: `if id == "BoxMenu"`
        # carries no screen-shaped word and is the shape the docs warn about
        for match in re.finditer(r"""["'](\w+)["']""", body):
            name = match.group(1)
            if name not in twins:
                continue
            line = _line_of(body, match.start())
            findings.append(Finding(
                "MK409", "warn",
                f"{name!r} is a Gen 1 screen id; a Gen 2 boot builds "
                f"'Gen2{name}' (Screens.GEN2_IDS in src/ui/Screens.lua), so a "
                f"screen compared or opened by this literal matches nothing "
                f"there",
                "%s:%d" % (rel, line)))
    return findings


def gen2_screen_twins(repo):
    """Screen ids that exist in both generations, where Gen 2's carries the
    Gen2 prefix (src/ui/Screens.lua)."""
    try:
        src = open(os.path.join(repo, "src", "ui", "Screens.lua"),
                   encoding="utf-8").read()
    except OSError:
        return set()
    block = re.search(r"^local GEN2 = \{(.*?)\n\}", src, re.S | re.M)
    if not block:
        return set()
    return {name for name in re.findall(r'"(\w+)"', block.group(1))
            if os.path.isfile(os.path.join(repo, "src", "ui", name + ".lua"))}


# ------------------------------------------------------------- the command

def _count(total, word):
    return "" if not total else "%d %s%s" % (total, word,
                                             "" if total == 1 else "s")


def gen2_verdict(findings):
    if any(f.severity == "error" for f in findings):
        return "will not work"
    return "will load but degrade" if findings else "will load"


def report_gen2(results, args):
    """report()'s shape plus the per-mod verdict this command exists to give.
    One JSON document covers every mod named, so a CI step reads one object
    however many it gated on."""
    payload, ok = [], True
    for mod_id, findings, notes, facts in results:
        errors = findings if args.strict else \
            [f for f in findings if f.severity == "error"]
        if errors:
            ok = False
        payload.append({"id": mod_id, "verdict": gen2_verdict(findings),
                        "errors": len(errors), "manifest": facts,
                        "findings": [f.as_dict() for f in findings],
                        "notes": notes})
    if args.json:
        print(json.dumps({"ok": ok, "mods": payload}))
        return 0 if ok else 1
    for index, (mod_id, findings, notes, facts) in enumerate(results):
        if not args.quiet:
            print(("" if index == 0 else "\n") + f"-- {mod_id}: {facts}")
        for finding in findings:
            print(finding.line())
        if args.quiet:
            continue
        for note in notes:
            print(f"modkit: {note}")
        warns = sum(1 for f in findings if f.severity == "warn")
        counts = ", ".join(part for part in (
            _count(len(findings) - warns, "error"), _count(warns, "warning"))
            if part)
        print("%s %s on gen 2: %s%s"
              % ("FAIL" if payload[index]["errors"] else "ok", mod_id,
                 payload[index]["verdict"], " (%s)" % counts if counts else ""))
    return 0 if ok else 1


def cmd_gen2check(args, repo):
    shared = []
    coverage = gen2_coverage(repo, shared)
    results = []
    dirs, named = [], {}
    for target in args.mod:
        mod_dir = resolve_mod_dir(repo, target)
        if not mod_dir:
            print(f"modkit: no mod at {target!r}")
            return 2
        manifest, problem = read_manifest(mod_dir)
        dirs.append((mod_dir, manifest, problem))
        if manifest:
            named[manifest["id"]] = manifest
    for mod_dir, manifest, problem in dirs:
        findings, notes = [], list(shared)
        if problem:
            findings.append(problem)
        else:
            manifest_findings, manifest_notes = check_gen2_manifest(
                repo, mod_dir, manifest, named)
            findings.extend(manifest_findings)
            notes.extend(manifest_notes)
            requires, uses, upvalues, scan_notes = scan_module_uses(mod_dir)
            require_findings, require_notes = check_gen2_requires(
                repo, coverage, requires)
            findings.extend(require_findings)
            member_findings, member_notes = check_gen2_members(
                repo, coverage, uses, args.notes)
            findings.extend(member_findings)
            upvalue_findings, upvalue_notes = check_gen2_upvalues(
                repo, coverage, upvalues)
            findings.extend(upvalue_findings)
            findings.extend(check_gen2_patterns(repo, mod_dir))
            notes.extend(scan_notes + require_notes + member_notes
                         + upvalue_notes)
        mod_id = manifest.get("id") if manifest else os.path.basename(mod_dir)
        results.append((mod_id, _order(_dedupe(findings)),
                        _dedupe_notes(notes), _facts(manifest)))
    return report_gen2(results, args)


def _dedupe(findings):
    """One line per fact: the same rule against the same place says the same
    thing however many times the source repeats the shape."""
    seen, out = set(), []
    for finding in findings:
        key = (finding.rule, finding.path, finding.message)
        if key not in seen:
            seen.add(key)
            out.append(finding)
    return out


def _dedupe_notes(notes):
    seen, out = set(), []
    for note in notes:
        if note not in seen:
            seen.add(note)
            out.append(note)
    return out


def _order(findings):
    def key(finding):
        path, _, line = (finding.path or "").rpartition(":")
        return (finding.rule, path or finding.path or "",
                int(line) if line.isdigit() else 0)
    return sorted(findings, key=key)


def _facts(manifest):
    """The manifest fields a Gen 2 boot reads, echoed so the verdict says what
    it was decided from rather than leaving the author to guess."""
    if not manifest:
        return ""
    permissions = manifest.get("permissions") or []
    deps = manifest.get("dependencies") or []
    games = "+".join(g for g in (manifest.get("games") or [])
                     if isinstance(g, str))
    return ("api %s, profile %s, %s, permissions %s, %d dependencies, "
            "game_version %s"
            % (manifest.get("api", 1), manifest.get("profile", "content"),
               ("games " + games) if games
               else ("gen2compat" if manifest.get("gen2compat")
                     else "no games declared"),
               "+".join(p for p in permissions if isinstance(p, str)) or "none",
               len(deps) if isinstance(deps, list) else 0,
               manifest.get("game_version", "unset")))


# ---------------------------------------------------------------- main

def main(argv):
    # global flags ride a parent parser so they work on either side of the
    # subcommand (modkit --json validate x / modkit validate x --json);
    # SUPPRESS keeps the subparser pass from clobbering a value the main
    # parser already set (set_defaults would write the fallback back onto
    # the shared actions and re-clobber, so absentees are filled post-parse)
    shared = argparse.ArgumentParser(add_help=False)
    shared.add_argument("--repo", default=argparse.SUPPRESS,
                        help="repo root override")
    shared.add_argument("--json", action="store_true",
                        default=argparse.SUPPRESS)
    shared.add_argument("--quiet", action="store_true",
                        default=argparse.SUPPRESS)

    parser = argparse.ArgumentParser(prog="modkit", parents=[shared])
    sub = parser.add_subparsers(dest="command")

    p = sub.add_parser("scaffold", parents=[shared])
    p.add_argument("id")
    p.add_argument("--profile", default="content",
                   choices=["content", "overhaul", "total_conversion"])
    p.add_argument("--api", type=int, default=2)
    p.add_argument("--github", default="",
                   help="optional owner/repo (enables launcher auto-update)")
    p.add_argument("--experimental", action="store_true",
                   help="mark the mod experimental (off until confirmed)")
    p.add_argument("--games", default="gen1",
                   help="games this mod is for: gen1, gen2, all, or a "
                        "comma-separated list of version ids (red,gold,...)")
    p.add_argument("--dest")
    p.add_argument("--force", action="store_true")

    p = sub.add_parser("validate", parents=[shared])
    p.add_argument("mod")
    p.add_argument("--strict", action="store_true")
    p.add_argument("--base", default="auto",
                   choices=["auto", "fixture", "imported"])

    p = sub.add_parser("gen2check", parents=[shared],
                       help="will this mod run on a Gen 2 game, and how far")
    p.add_argument("mod", nargs="+")
    p.add_argument("--strict", action="store_true")
    p.add_argument("--notes", action="store_true",
                   help="also print the adapter's note for every backed "
                        "member the mod touches")

    p = sub.add_parser("lint", parents=[shared])
    p.add_argument("mod")

    p = sub.add_parser("pack", parents=[shared])
    p.add_argument("mod")
    p.add_argument("-o", "--output")
    p.add_argument("--base", default="auto",
                   choices=["auto", "fixture", "imported"])

    p = sub.add_parser("bounce", parents=[shared])
    p.add_argument("song", nargs="?")
    p.add_argument("--all", action="store_true")
    p.add_argument("--seconds", type=int, default=10)
    p.add_argument("--out")

    p = sub.add_parser("translation", parents=[shared])
    p.add_argument("id")
    p.add_argument("--language", help="display name, e.g. \"Francais\"")
    p.add_argument("--dest")
    p.add_argument("--base", default="auto",
                   choices=["auto", "fixture", "imported"])
    p.add_argument("--pixel-font", action="store_true",
                   help="render text through the bundled Plain Pixel TTF "
                        "instead of the tile font (no glyph sheet needed)")
    p.add_argument("--refresh", action="store_true",
                   help="re-harvest the catalogs, keeping existing work")
    p.add_argument("--force", action="store_true")

    p = sub.add_parser("docs", parents=[shared])
    p.add_argument("--out")

    p = sub.add_parser("set-github", parents=[shared],
                       help="add github field to an existing mod manifest")
    p.add_argument("mod")
    p.add_argument("url", help="owner/repo or https://github.com/owner/repo")

    p = sub.add_parser("add-release-workflow", parents=[shared],
                       help="copy GitHub Actions release.yml into the mod")
    p.add_argument("mod")
    p.add_argument("--force", action="store_true")

    args = parser.parse_args(argv)
    for dest, fallback in (("repo", None), ("json", False),
                           ("quiet", False)):
        if not hasattr(args, dest):
            setattr(args, dest, fallback)
    if not args.command:
        parser.print_help()
        return 2
    if args.command == "bounce" and not (args.song or args.all):
        print("modkit: bounce needs a song id or --all")
        return 2

    repo = args.repo or find_repo(os.getcwd()) or find_repo(
        os.path.dirname(os.path.abspath(__file__)))
    if not repo:
        print("modkit: cannot find the repo root "
              "(looked for tools/rom_manifest.json)")
        return 2
    repo = os.path.abspath(repo)

    # Normal game boot mounts the selected version's private ROM cache before
    # Data:load(). modkit runs outside LÖVE, so reproduce that dataset
    # selection through Data.lua's existing POKEPORT_DATA_DIR override.
    #
    # Setting it once here means validate, pack, and translation all inherit
    # the same imported dataset in their LuaJIT child processes.
    if hasattr(args, "base") and resolve_base(repo, args.base) == "imported":
        data_dir = imported_data_dir(repo)
        if data_dir:
            os.environ["POKEPORT_DATA_DIR"] = data_dir

    handler = {
        "scaffold": cmd_scaffold,
        "validate": cmd_validate,
        "gen2check": cmd_gen2check,
        "lint": cmd_lint,
        "pack": cmd_pack,
        "bounce": cmd_bounce,
        "translation": cmd_translation,
        "docs": cmd_docs,
        "set-github": cmd_set_github,
        "add-release-workflow": cmd_add_release_workflow,
    }[args.command]
    return handler(args, repo)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
