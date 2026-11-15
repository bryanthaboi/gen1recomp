package.path = "./?.lua;./?/init.lua;" .. package.path
_G.love = _G.love or require("tests.love_stub")

local T = require("tests.modkit")
local Battle = require("src.core.game3.battle.init")
local UnifiedCallbacks = require("src.mods.UnifiedCallbacks")

local session = { version = "firered", options = { battleStyle = 0 } }
package.loaded["src.core.game3.runtime"] = { getSession = function() return session end }
local st = { session = session }

local function style(value)
  session.options = { battleStyle = value }
  return Battle.battleStyle(st)
end

T.eq(UnifiedCallbacks.supports("hooks", "battle.style", 3), true, "battle.style is supported in Gen 3")
T.eq(type(Battle.battleStyle), "function", "the Gen 3 battle has a battleStyle reader")

local vanilla = T.sdk.loadNone({ generation = 3, data = T.sdk.gen3Data() })
T.eq(style(0), "shift", "no mod: SHIFT")
T.eq(style(1), "set", "no mod: SET")
vanilla.release()

local FIXTURE = {
  ["mods/style_probe/manifest.json"] = [[{"id":"style_probe","name":"Style Probe","version":"1.0.0",
    "api":2,"games":["all"],"entry":"main.lua"}]],
  ["mods/style_probe/main.lua"] = [[
    local mod = ...
    mod.exports.calls = 0
    mod.hooks:wrap("battle.style", function(next, battle)
      mod.exports.calls = mod.exports.calls + 1
      mod.exports.battle = battle
      mod.exports.vanilla = next(battle)
      if mod.exports.answer == nil then return mod.exports.vanilla end
      return mod.exports.answer
    end)
  ]],
}

for _, version in ipairs({ "firered", "emerald" }) do
  session.version = version
  local run = T.sdk.loadMods({ "mods/style_probe" },
    { fs = T.sdk.memfs(FIXTURE), generation = 3, data = T.sdk.gen3Data() })
  T.eq(#run.errors, 0, version .. " probe loads clean (" .. tostring(run.errors[1]) .. ")")
  local probe = run.loader.exports.style_probe

  probe.answer = "set"
  T.eq(style(0), "set", version .. " set on SHIFT wins")
  T.eq(probe.calls, 1, version .. " the hook ran once")
  T.check(probe.battle == st, version .. " the hook's argument is the battle")
  T.eq(probe.vanilla, "shift", version .. " the vanilla link reads the option")
  T.eq(session.options.battleStyle, 0, version .. " the saved option is untouched")
  probe.answer = "shift"
  T.eq(style(1), "shift", version .. " shift on SET wins")
  probe.answer = "SET"
  T.eq(style(0), "shift", version .. " an unknown answer reads as the option")
  probe.answer = nil
  T.eq(style(1), "set", version .. " falling through keeps SET")
  run.release()
end

local API3 = {
  ["mods/style_probe3/manifest.json"] = [[{"id":"style_probe3","name":"Style Probe 3","version":"1.0.0",
    "api":3,"games":["all"],"entry":"main.lua"}]],
  ["mods/style_probe3/main.lua"] = [[
    local mod = ...
    mod.exports.supported = mod:supports("hooks", "battle.style")
    mod.hooks:wrap("battle.style", function() return "set" end)
  ]],
}
for _, version in ipairs({ "firered", "emerald" }) do
  session.version = version
  T.sdk.captureRuntime()
  local data = T.sdk.gen3Data()
  local loader = require("src.mods.Loader").new({ fs = T.sdk.memfs(API3), generation = 3, version = version })
  loader.game = { data = data }
  loader:load(data)
  T.eq(#loader.errors, 0, version .. " API 3 probe loads clean (" .. tostring(loader.errors[1]) .. ")")
  T.eq(loader.exports.style_probe3.supported, true, version .. " API 3: mod:supports is true")
  T.eq(style(0), "set", version .. " API 3: set holds")
  T.sdk.restoreRuntime()
end

T.finish("battle.style Gen 3")
