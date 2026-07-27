-- Love-free coverage for the pure halves of src/mods/LauncherMods.lua: the
-- status derivation (deriveList) over a synthetic manifest list + options
-- table, and the archive-root location logic (locateRoot).  The discovery and
-- installZip paths need love.filesystem and are exercised by the launcher; the
-- decision logic under them lives here so a bad range/conflict/root call fails
-- one line instead of the app.
--   luajit tests/engine/launcher_mods_tests.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
local Manifest = require("src.mods.Manifest")
local Version = require("src.core.Version")
local LauncherMods = require("src.mods.LauncherMods")

-- validated manifests are the exact shape deriveList/resolveToggle read
local function mf(raw)
  return Manifest.validate(raw)
end

-- index a deriveList result by mod id for assertions
local function byId(list)
  local m = {}
  for _, row in ipairs(list) do m[row.id] = row end
  return m
end

-- ------- badge derivation: category, then profile, then MOD (uppercased)

do
  local list = LauncherMods.deriveList({
    mf({ id = "cat", name = "Cat Mod", version = "1.0.0", entry = "m.lua",
         category = "gameplay" }),
    mf({ id = "prof", name = "Prof Mod", version = "1.0.0", entry = "m.lua",
         profile = "overhaul" }),
    mf({ id = "plain", name = "Plain", version = "1.0.0", entry = "m.lua" }),
  }, { mods = {} })
  local m = byId(list)
  eq(m.cat.badge, "GAMEPLAY", "badge uses the manifest category, uppercased")
  eq(m.prof.badge, "OVERHAUL", "badge falls back to the profile when no category")
  -- no category field, so the fallback reaches the profile default ("content")
  eq(m.plain.badge, "CONTENT", "bare manifest badge falls back to the profile")
  eq(#list, 3, "every discovered manifest yields one row")
  check(m.cat.id < m.plain.id and m.plain.id < m.prof.id,
    "rows come back sorted by id (cat < plain < prof)")
end

-- ------- enabled defaults to true; a false entry disables

do
  local manifests = {
    mf({ id = "aaa", name = "A", version = "1.0.0", entry = "m.lua" }),
    mf({ id = "bbb", name = "B", version = "1.0.0", entry = "m.lua" }),
  }
  local m = byId(LauncherMods.deriveList(manifests, { mods = { bbb = false } }))
  check(m.aaa.enabled, "a mod with no options entry defaults to enabled")
  check(not m.bbb.enabled, "an explicit false disables the mod")
  eq(m.aaa.status, "ok", "a healthy enabled mod is ok")
  eq(m.aaa.statusDetail, "Ready", "ok detail reads Ready")
end

-- ------- conflict: only when this mod is enabled and the other is too

do
  local manifests = {
    mf({ id = "alpha", name = "Alpha", version = "1.0.0", entry = "m.lua",
         conflicts = { "beta" } }),
    mf({ id = "beta", name = "Beta", version = "1.0.0", entry = "m.lua" }),
  }
  -- both enabled: the declaring side (and, symmetrically, the other) conflict
  local both = byId(LauncherMods.deriveList(manifests, { mods = {} }))
  eq(both.alpha.status, "conflict", "enabled mod conflicting with an enabled mod")
  check(both.alpha.statusDetail:find("Beta", 1, true) ~= nil,
    "conflict detail names the other mod")
  eq(both.beta.status, "conflict",
    "resolveToggle conflict is bidirectional: the target is flagged too")

  -- disable beta: alpha no longer conflicts (nothing enabled to conflict with)
  local off = byId(LauncherMods.deriveList(manifests, { mods = { beta = false } }))
  eq(off.alpha.status, "ok", "no conflict once the other side is disabled")
  eq(off.beta.status, "ok", "a disabled mod is never a conflict")
end

-- ------- warn: unsatisfied game_version range against Version.engine

do
  -- a range the -dev engine cannot satisfy (needs a released >=1.0.0)
  local manifests = {
    mf({ id = "future", name = "Future", version = "1.0.0", entry = "m.lua",
         game_version = ">=1.0.0" }),
  }
  local m = byId(LauncherMods.deriveList(manifests, { mods = {} }))
  eq(m.future.status, "warn", "engine outside the game_version range warns")
  check(m.future.statusDetail:find(">=1.0.0", 1, true) ~= nil,
    "version warn detail quotes the required range")
  check(m.future.statusDetail:find(Version.engine, 1, true) ~= nil,
    "version warn detail quotes the engine version")
end

-- ------- warn: hard dependency missing, disabled, or wrong version

do
  local base = { id = "base", name = "Base", version = "1.0.0", entry = "m.lua" }
  local needsMissing = { id = "needy", name = "Needy", version = "1.0.0",
    entry = "m.lua", dependencies = { "ghost" } }
  local m = byId(LauncherMods.deriveList({ mf(needsMissing) }, { mods = {} }))
  eq(m.needy.status, "warn", "a missing hard dependency warns")
  check(m.needy.statusDetail:find("not installed", 1, true) ~= nil,
    "missing-dep detail says not installed")

  -- present but disabled
  local m2 = byId(LauncherMods.deriveList(
    { mf(base), mf({ id = "needy", name = "Needy", version = "1.0.0",
      entry = "m.lua", dependencies = { "base" } }) },
    { mods = { base = false } }))
  eq(m2.needy.status, "warn", "a disabled hard dependency warns")
  check(m2.needy.statusDetail:find("disabled", 1, true) ~= nil,
    "disabled-dep detail says disabled")

  -- present, enabled, but the version is out of range
  local m3 = byId(LauncherMods.deriveList(
    { mf(base), mf({ id = "needy", name = "Needy", version = "1.0.0",
      entry = "m.lua", dependencies = { "base@>=2.0.0" } }) },
    { mods = {} }))
  eq(m3.needy.status, "warn", "a dependency below the required range warns")
  eq(m3.base.status, "ok", "the satisfied dependency itself stays ok")

  -- the same dep satisfied: needy is ok
  local m4 = byId(LauncherMods.deriveList(
    { mf(base), mf({ id = "needy", name = "Needy", version = "1.0.0",
      entry = "m.lua", dependencies = { "base@>=1.0.0" } }) },
    { mods = {} }))
  eq(m4.needy.status, "ok", "a satisfied dependency clears the warn")
end

-- ------- conflict outranks warn when a mod trips both

do
  local manifests = {
    mf({ id = "alpha", name = "Alpha", version = "1.0.0", entry = "m.lua",
         conflicts = { "beta" }, game_version = ">=1.0.0" }),
    mf({ id = "beta", name = "Beta", version = "1.0.0", entry = "m.lua" }),
  }
  local m = byId(LauncherMods.deriveList(manifests, { mods = {} }))
  eq(m.alpha.status, "conflict",
    "conflict is reported ahead of a version warn on the same mod")
end

-- ------- locateRoot: manifest at the archive root

do
  local root, err = LauncherMods.locateRoot({ "manifest.json", "main.lua" })
  eq(root, "", "a root-level manifest.json resolves to the empty prefix")
  eq(err, nil, "no error for a root-level manifest")
end

-- ------- locateRoot: manifest inside a single top-level folder

do
  local root = LauncherMods.locateRoot({
    "mymod/manifest.json", "mymod/main.lua", "mymod/assets/x.png" })
  eq(root, "mymod", "a single wrapping folder resolves to that folder name")
end

-- ------- locateRoot: no manifest anywhere

do
  local root, err = LauncherMods.locateRoot({ "readme.txt", "stuff/x.lua" })
  eq(root, nil, "an archive with no manifest.json resolves to nil")
  check(err:find("no manifest.json", 1, true) ~= nil,
    "the no-manifest reason is user-presentable")
end

-- ------- locateRoot: multiple top-level folders is ambiguous

do
  local root, err = LauncherMods.locateRoot({
    "one/manifest.json", "two/manifest.json" })
  eq(root, nil, "two candidate mod folders resolves to nil")
  check(err:find("single mod folder", 1, true) ~= nil,
    "the ambiguous reason asks for a single mod folder")
end

-- ------- locateRoot: a lone folder without a manifest is not a root

do
  local root, err = LauncherMods.locateRoot({ "assets/x.png" })
  eq(root, nil, "a single folder with no manifest is not a mod root")
  check(err ~= nil, "the no-root case carries a reason")
end

-- ------- uninstall: rejects bad ids without needing a real mods tree

do
  local ok, err = LauncherMods.uninstall("")
  eq(ok, nil, "empty id is rejected")
  check(tostring(err):find("missing", 1, true) ~= nil, "empty-id reason")

  ok, err = LauncherMods.uninstall("../escape")
  eq(ok, nil, "path-like ids are rejected")
  check(tostring(err):find("invalid", 1, true) ~= nil, "path-id reason")

  ok, err = LauncherMods.uninstall("ghost")
  -- Without a mods/ghost tree (and with the love stub's getInfo), uninstall
  -- either needs LOVE or reports not installed -- never silently succeeds.
  eq(ok, nil, "a missing mod does not uninstall")
  check(err ~= nil, "missing-mod uninstall carries a reason")
end

T.finish("launcher_mods")
