package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.modkit")
local UI = require("src.ui.gen2.BattleState")

local function newState(style, opts)
  opts = opts or {}
  local save = { version = "crystal", party = {}, player = { name = "KRIS", id = 4242 } }
  return setmetatable({
    save = save, queue = {}, link = opts.link,
    battle = { trainer = { name = "JOEY" }, player = { hp = opts.hp or 10 },
      party = opts.party or { {}, {} }, inBattleTowerBattle = opts.tower },
    game = { save = save, data = {}, options = { battleStyle = style } },
  }, { __index = UI })
end

local vanilla = T.sdk.loadNone({ generation = 2 })
T.eq(newState("SHIFT"):shiftOfferAllowed(), true, "no mod: SHIFT offers the switch")
T.eq(newState("SET"):shiftOfferAllowed(), false, "no mod: SET offers nothing")
T.eq(newState(nil):shiftOfferAllowed(), true, "no mod: an unset option is SHIFT")
T.eq(type(UI.battleStyle), "function", "the Gen 2 screen has a battleStyle method")
T.eq(newState("SHIFT"):battleStyle(), "shift", "no mod: SHIFT reads as lowercase shift")
T.eq(newState("SET"):battleStyle(), "set", "no mod: SET reads as lowercase set")
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

local run = T.sdk.loadMods({ "mods/style_probe" }, { fs = T.sdk.memfs(FIXTURE), generation = 2 })
T.eq(#run.errors, 0, "the probe loads clean (" .. tostring(run.errors[1]) .. ")")
local probe = run.loader.exports.style_probe

probe.answer = "set"
local state = newState("SHIFT")
T.eq(state:shiftOfferAllowed(), false, "set on SHIFT: no switch is offered")
T.eq(probe.calls, 1, "set on SHIFT: the hook ran once")
T.check(probe.battle == state, "the hook's argument is the battle screen")
T.eq(probe.vanilla, "shift", "the vanilla link answers in lowercase")

probe.answer = "shift"
T.eq(newState("SET"):shiftOfferAllowed(), true, "shift on SET: the switch is offered")

probe.answer = "SHIFT"
T.eq(newState("SET"):shiftOfferAllowed(), false, "an unknown answer reads as the option")
probe.answer = 7
T.eq(newState("SHIFT"):shiftOfferAllowed(), true, "a non-string answer reads as the option")

probe.answer = nil
T.eq(newState("SET"):shiftOfferAllowed(), false, "falling through keeps SET")
T.eq(newState("SHIFT"):shiftOfferAllowed(), true, "falling through keeps SHIFT")

probe.answer, probe.calls = "shift", 0
T.eq(newState("SHIFT", { link = true }):shiftOfferAllowed(), false, "a link battle never offers")
T.eq(newState("SHIFT", { party = { {} } }):shiftOfferAllowed(), false, "a one-mon party never offers")
T.eq(newState("SHIFT", { hp = 0 }):shiftOfferAllowed(), false, "a fainted active mon never offers")
T.eq(newState("SHIFT", { tower = true }):shiftOfferAllowed(), false, "the Battle Tower never offers")
T.eq(probe.calls, 0, "the cart's earlier gates answer before the option is read")
run.release()

local API3 = {
  ["mods/style_probe3/manifest.json"] = [[{"id":"style_probe3","name":"Style Probe 3","version":"1.0.0",
    "api":3,"games":["all"],"entry":"main.lua"}]],
  ["mods/style_probe3/main.lua"] = [[
    local mod = ...
    mod.exports.supported = mod:supports("hooks", "battle.style")
    mod.hooks:wrap("battle.style", function() return "set" end)
  ]],
}
local loader = require("src.mods.Loader").new({ fs = T.sdk.memfs(API3), generation = 2, version = "crystal" })
T.sdk.captureRuntime()
local api3 = newState("SHIFT")
loader.game = api3.game
loader:load(require("tests.modkit.fixtures").fresh())
T.eq(#loader.errors, 0, "API 3 probe loads clean (" .. tostring(loader.errors[1]) .. ")")
T.eq(loader.exports.style_probe3.supported, true, "API 3: mod:supports is true on Gen 2")
T.eq(api3:shiftOfferAllowed(), false, "API 3: set holds on Gen 2")
T.sdk.restoreRuntime()

T.finish("battle.style Gen 2")
