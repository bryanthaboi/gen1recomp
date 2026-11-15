-- pokered/constants/text_constants.asm:3
-- pokefirered/include/constants/global.h:63
package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.modkit")
local Commands = require("src.script.Commands")
local SaveData = require("src.core.SaveData")

local E, MALE = "\195\169", "\226\153\130"
local CASES = {
  { "SPIKE", "SPIKE", "a short name is kept" },
  { "TOOLONGFORTHEGRID", "TOOLONGFOR", "a long name is clipped to ten" },
  { "A" .. E:rep(12), "A" .. E:rep(9), "the clip counts characters, not bytes" },
  { "NIDO" .. MALE .. "KING" .. MALE .. "X", "NIDO" .. MALE .. "KING" .. MALE,
    "a grid-legal ten with two signs" },
  { "SPI\nKE", "SPIKE", "control characters never reach the name" },
}

local Data = T.fixtures.load()
local function gen1Gift(nickname)
  local game = { data = Data, save = SaveData.newGame(),
    stack = { push = function() end },
    mods = { events = { emit = function(_, name, gift)
      if name == "pokemon.before_give" then gift.nickname = nickname end
    end } } }
  local ctx = { game = game, save = game.save }
  Commands.give_pokemon(ctx, "FIXMON_A", 5)
  return game.save.party[1] and game.save.party[1].nickname
end

for _, case in ipairs(CASES) do
  T.eq(gen1Gift(case[1]), case[2], "gen 1 gift: " .. case[3])
end
T.eq(gen1Gift("\n"), nil, "gen 1 gift: a name of only control characters names nothing")

require("src.core.GameVersion").set("firered")
local Ops = require("src.core.game3.scripting.ops_a")
local Ctx = require("src.core.game3.scripting.ctx")
local Flags = require("src.core.game3.scripting.flags")
require("src.core.game3.pokemon")._names = {}

local FIXTURE = {
  ["mods/gift_probe/manifest.json"] = [[{"id":"gift_probe","name":"Gift Probe","version":"1.0.0",
    "api":2,"games":["all"],"entry":"main.lua"}]],
  ["mods/gift_probe/main.lua"] = [[
    local mod = ...
    mod.events:on("pokemon.before_give", function(gift)
      gift.nickname = mod.exports.nickname
    end)
  ]],
}
local run = T.sdk.loadMods({ "mods/gift_probe" }, { fs = T.sdk.memfs(FIXTURE), generation = 3 })
T.eq(#run.errors, 0, "the gift probe loads clean (" .. tostring(run.errors[1]) .. ")")
local probe = run.loader.exports.gift_probe

local store = Flags.newStore()
local function gen3Gift(nickname)
  probe.nickname = nickname
  local given
  local ctx = Ctx.new({})
  local vm = { ctx = ctx, store = store, setPc = function() end, adapters = {
    log = function() end,
    giveMonToPlayer = function(_, _, _, nick) given = nick return 0 end,
  } }
  Ops.dispatchUnhooked(vm, { op = "givemon", [1] = 4, [2] = 5, [3] = 0 })
  return given
end

for _, case in ipairs(CASES) do
  T.eq(gen3Gift(case[1]), case[2], "gen 3 gift: " .. case[3])
end
T.eq(gen3Gift(("<PK><MN>"):rep(6)), "<PK><MN><P", "gen 3 gift: angle brackets are plain characters")
T.eq(gen3Gift(("{PK}{MN}"):rep(6)), ("{PK}{MN}"):rep(5), "gen 3 gift: a {PK} ligature is one cell")
T.eq(gen3Gift("A" .. ("\128"):rep(30)), "A" .. ("\128"):rep(9), "gen 3 gift: stray continuation bytes are one cell each")
T.eq(gen3Gift("\n"), nil, "gen 3 gift: a name of only control characters names nothing")

run.release()
T.finish("gift nickname clip")
