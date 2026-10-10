package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
love = love or require("tests.love_stub")

local Manifest = require("src.mods.Manifest")
local LauncherMods = require("src.mods.LauncherMods")

local function mf(raw) return Manifest.validate(raw) end

local engine = mf({ id = "g9-battle-engine", name = "G9 Battle Engine",
  version = "1.0.0", entry = "m.lua" })
local scene = mf({ id = "g9-Battle-Scene", name = "G9 Battle Scene",
  version = "1.0.0", entry = "m.lua", dependencies = { "g9-battle-engine" } })
local sprites = mf({ id = "g9-battle-sprites", name = "G9 Battle Sprites",
  version = "1.0.0", entry = "m.lua",
  optional_dependencies = { "national_dex", "g9-battle-engine", "g9-Battle-Scene" } })
local dex = mf({ id = "national_dex", name = "National Dex",
  version = "1.0.0", entry = "m.lua" })

do
  local res = LauncherMods.checkDependencies(sprites, nil, nil, { sprites })
  T.eq(res.hasIssues, false, "optional deps alone never raise the resolver")
  T.eq(#res.deps, 3, "resolver lists every optional dependency")
  for _, d in ipairs(res.deps) do
    T.eq(d.kind, "optional", d.id .. " is marked optional")
    T.eq(d.status, "missing", d.id .. " reports not installed")
  end

  local partial = LauncherMods.checkDependencies(sprites, nil, nil, { sprites, scene })
  T.eq(partial.hasIssues, false, "installed optional dep does not flag the rest")
  local status = {}
  for _, d in ipairs(partial.deps) do status[d.id] = d.status end
  T.eq(status["g9-Battle-Scene"], "satisfied", "installed optional shows satisfied")
  T.eq(status["national_dex"], "missing", "absent optional still listed")

  local hard = LauncherMods.checkDependencies(scene, nil, nil, { scene })
  T.eq(hard.hasIssues, true, "a missing hard dependency still raises the resolver")
  T.eq(hard.deps[1].kind, "dependency", "hard dependency kind kept")
end

do
  local manifests = { engine, scene, sprites, dex }
  local function noteFor(order)
    local rows = LauncherMods.deriveList(manifests, { mods = {}, modOrder = order }, "crystal")
    for _, r in ipairs(rows) do
      if r.id == "g9-battle-sprites" then return r end
    end
  end
  local a = noteFor({ "g9-battle-sprites", "national_dex", "g9-battle-engine", "g9-Battle-Scene" })
  T.check(a.orderNote and a.orderNote:find("(optional)", 1, true) ~= nil,
    "optional ordering note says optional: " .. tostring(a.orderNote))
  T.check(a.orderNote and not a.orderNote:find("dependency", 1, true),
    "optional ordering note never calls it a dependency")
  T.eq(a.orderNoteOptional, true, "optional-only note is not a warning")
  for _, name in ipairs({ "National Dex", "G9 Battle Engine", "G9 Battle Scene" }) do
    T.check(a.orderNote:find(name, 1, true) ~= nil, "note names " .. name)
  end

  local b = noteFor({ "g9-battle-sprites", "g9-Battle-Scene", "g9-battle-engine", "national_dex" })
  T.eq(b.orderNote, a.orderNote, "note text is stable when the later deps reorder")

  local scenes = LauncherMods.deriveList(manifests,
    { mods = {}, modOrder = { "g9-Battle-Scene", "g9-battle-engine" } }, "crystal")
  for _, r in ipairs(scenes) do
    if r.id == "g9-Battle-Scene" then
      T.check(r.orderNote and r.orderNote:find("(required)", 1, true) ~= nil,
        "hard dependency note says required")
      T.check(not r.orderNoteOptional, "hard dependency note stays a warning")
    end
  end
end

T.finish("mod optional dependencies (#2833)")
