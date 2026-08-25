-- T4: a mod may not reach a Gen 2 engine module from a Gen 1 game.
--
-- src/battle/gen2/Mon.lua returns { hp, attack, defense, speed, specialAttack,
-- specialDefense }; a Gen 1 party mon carries `special` instead.  A Yellow mod
-- that required that module and ran refreshStats over save.party wrote the Gen
-- 2 block onto Gen 1 mons, and every reader of stats.special raised from then
-- on (#1517).  The require shim refuses it now, whatever the manifest declares:
-- engine_internals is a disclosure, not a generation gate.

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

local PROBE = [[
  local mod = ...
  local out = mod.exports
  local function attempt(name)
    local ok, result = pcall(require, name)
    if ok then return nil, type(result) end
    return tostring(result), nil
  end
  out.attempt = attempt
  out.monErr, out.monType = attempt("src.battle.gen2.Mon")
  out.saveErr = attempt("src.core.gen2.Save")
  out.worldErr = attempt("src.ui.gen2.Chrome")
  out.game2Err = attempt("src.core.Game2")
  out.semverErr, out.semverType = attempt("src.mods.Semver")
  out.statsErr, out.statsType = attempt("src.pokemon.Stats")
  out.compatErr, out.compatType = attempt("src.mods.Gen2Compat")
  out.loggerErr, out.loggerType = attempt("src.core.Logger")
]]

local function manifest(id, permissions)
  return ('{"id":"%s","name":"%s","version":"1.0.0","entry":"main.lua",'
    .. '"api":2,"games":["all"]%s}'):format(id, id, permissions or "")
end

-- ------- Gen 1 boot: refused, and the permission does not unlock it

local FILES = {
  ["mods/gen2_declared/manifest.json"] =
    manifest("gen2_declared", ',"permissions":["engine_internals"]'),
  ["mods/gen2_declared/main.lua"] = PROBE,
  ["mods/gen2_undeclared/manifest.json"] = manifest("gen2_undeclared"),
  ["mods/gen2_undeclared/main.lua"] = PROBE,
}

T.eq(package.loaded["src.battle.gen2.Mon"], nil,
  "the Gen 2 mon module is not loaded before the Gen 1 boot")

local run = T.sdk.loadMods({ "mods/gen2_declared", "mods/gen2_undeclared" },
  { fs = T.sdk.memfs(FILES), data = {}, generation = 1 })
T.eq(#run.errors, 0,
  "a mod that only probes still loads clean (" .. tostring(run.errors[1]) .. ")")

local declared = run.loader.exports.gen2_declared or {}
local undeclared = run.loader.exports.gen2_undeclared or {}

T.check(declared.monErr, "src.battle.gen2.Mon is refused on a Gen 1 game")
T.check(declared.monErr and declared.monErr:find("src.battle.gen2.Mon", 1, true),
  "the refusal names the module: " .. tostring(declared.monErr))
T.check(declared.monErr and declared.monErr:find("gen2_declared", 1, true),
  "and the mod that asked for it")
T.check(declared.monErr and declared.monErr:find("mod.game", 1, true),
  "and the surface to use instead")
T.eq(declared.monType, nil, "nothing came back for the mod to call")
T.eq(package.loaded["src.battle.gen2.Mon"], nil,
  "and the module was never loaded at all")

T.check(declared.saveErr, "src.core.gen2.Save is refused the same way")
T.check(declared.worldErr, "so is src.ui.gen2.Chrome")
T.check(declared.game2Err and declared.game2Err:find("src.core.Game2", 1, true),
  "and src.core.Game2, the Gen 2 service owner: " .. tostring(declared.game2Err))

T.check(undeclared.monErr,
  "a mod with no permissions is refused for the same reason")
T.eq(declared.monErr and declared.monErr:gsub("gen2_declared", "X"),
  undeclared.monErr and undeclared.monErr:gsub("gen2_undeclared", "X"),
  "engine_internals is a disclosure, not a generation gate: same refusal")

-- ------- what the gate does NOT touch

T.eq(declared.semverErr, nil, "the supported requires still resolve")
T.eq(declared.semverType, "table", "and hand back the module")
T.eq(declared.statsErr, nil, "src.pokemon.Stats is still published to mods")
T.eq(declared.compatErr, nil,
  "src.mods.Gen2Compat is not a Gen 2 engine module: it is the adapter table")
T.eq(declared.compatType, "table", "so it still answers")
T.eq(declared.loggerErr, nil,
  "an undeclared engine require is still a warning, not a block")
T.eq(declared.loggerType, "table", "and still resolves")
T.eq(undeclared.loggerErr, nil,
  "including for a mod that declared no permissions at all")

-- a lazy require made long after the entry chunk ran is gated too: the mod's
-- own require is what the shim identifies, not the load phase
do
  local err = declared.attempt and declared.attempt("src.world.gen2.World")
  T.check(err and err:find("src.world.gen2.World", 1, true),
    "a require made after load is refused too: " .. tostring(err))
end

-- the shim only judges a mod's own require; engine and harness callers keep
-- the module they asked for
do
  local ok, module = pcall(require, "src.world.gen2.WorldAPI")
  T.check(ok, "a non-mod caller still reaches a Gen 2 module: " .. tostring(module))
  T.eq(type(module), "table", "and gets the real one")
end

run.release()

-- ------- an unguarded reach fails the whole mod, on the boot error feed

local HARD = {
  ["mods/gen2_hard/manifest.json"] = manifest("gen2_hard",
    ',"permissions":["engine_internals"]'),
  ["mods/gen2_hard/main.lua"] = [[
    local mod = ...
    local Mon = require("src.battle.gen2.Mon")
    mod.exports.reached = Mon ~= nil
  ]],
}
local hard = T.sdk.loadMods({ "mods/gen2_hard" },
  { fs = T.sdk.memfs(HARD), data = {}, generation = 1 })
T.eq(hard.loader.mods.gen2_hard.state, "failed",
  "a mod that reaches across the generation does not load")
T.eq(hard.loader.exports.gen2_hard, nil, "and publishes nothing")
T.check(hard.errors[1] and hard.errors[1]:find("src.battle.gen2.Mon", 1, true),
  "the boot error feed names the module: " .. tostring(hard.errors[1]))
hard.release()

-- ------- Gen 2 boot: the same require is the mod's own generation

local gen2 = T.sdk.loadMods({ "mods/gen2_declared" },
  { fs = T.sdk.memfs(FILES), data = {}, generation = 2 })
local onGold = gen2.loader.exports.gen2_declared or {}
T.eq(onGold.monErr, nil,
  "on a Gen 2 game the same require is answered: " .. tostring(onGold.monErr))
T.eq(onGold.monType, "table", "with the real Gen 2 mon module")
T.eq(onGold.game2Err, nil, "and src.core.Game2 is this game's service owner")
gen2.release()

T.finish("cross_generation_require")
