-- A sandboxed mod can take custody of a catch the party cannot hold
-- (catch.party_full): the mon goes to the mod instead of a PC box, which is
-- the difference between "choose who to release" and a catch that vanishes
-- into storage the mode has locked away.

package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.modkit")
local BattleState = require("src.battle.BattleState")
local Boxes = require("src.pokemon.Boxes")

local FIXTURE = {
  ["mods/catch_probe/manifest.json"] = [[{
    "id": "catch_probe",
    "name": "Catch Probe",
    "version": "1.0.0",
    "entry": "main.lua",
    "api": 2
  }]],
  ["mods/catch_probe/main.lua"] = [[
    local mod = ...
    mod.exports.answer = nil
    mod.exports.ctx = nil
    mod.hooks:wrap("catch.party_full", function(next, ctx)
      mod.exports.ctx = ctx
      if mod.exports.answer == nil then return next(ctx) end
      return mod.exports.answer
    end)
  ]],
}

local function fullBattle(species)
  local data = { pokemon = {}, text = {} }
  local party = {}
  for _ = 1, 6 do party[#party + 1] = { species = "RATTATA", moves = {} } end
  local save = {
    party = party,
    player = { name = "RED" },
    options = { battleStyle = "shift" },
    flags = {},
  }
  return setmetatable({
    game = { save = save, stack = { push = function() end }, data = data },
    data = data,
    queue = {}, nextInsert = 0,
    enemy = { mon = { species = species or "PIDGEY", level = 5, moves = {} },
              name = species or "PIDGEY" },
  }, { __index = BattleState })
end

local function boxTotal(save)
  local n = 0
  for _, box in ipairs(Boxes.ensure(save)) do n = n + #box end
  return n
end

-- ------- no mod: the cart's silence, reproduced

local vanilla = T.sdk.loadNone({})
local battle = fullBattle()
battle:storeCaughtMon()
T.eq(battle.result, "caught", "no mod: the catch still lands")
T.eq(#battle.game.save.party, 6, "no mod: the party is untouched")
T.eq(boxTotal(battle.game.save), 1, "no mod: the mon was deposited")
T.eq(battle.queue[#battle.queue].text, "PIDGEY was\ntransferred to\nsomeone's PC!",
  "no mod: with the transfer text")
vanilla.release()

-- ------- a mod claims custody

local run = T.sdk.loadMods({ "mods/catch_probe" }, { fs = T.sdk.memfs(FIXTURE) })
T.eq(#run.errors, 0, "the catch probe loads clean (" .. tostring(run.errors[1]) .. ")")
local probe = run.loader.exports.catch_probe

probe.answer = true
local claimed = fullBattle()
claimed:storeCaughtMon()
T.eq(claimed.result, "caught", "claimed: the catch still lands")
T.eq(#claimed.game.save.party, 6, "claimed: the party is untouched")
T.eq(boxTotal(claimed.game.save), 0, "claimed: nothing reached a box")
T.eq(probe.ctx and probe.ctx.name, "PIDGEY", "the hook was handed the display name")
T.check(probe.ctx and probe.ctx.battle == claimed, "and the battle")
T.check(probe.ctx and probe.ctx.mon == claimed.enemy.mon, "and the caught mon")
T.check(probe.ctx and probe.ctx.game == claimed.game, "and the game")

probe.answer = false
local declined = fullBattle()
declined:storeCaughtMon()
T.eq(boxTotal(declined.game.save), 1, "declined: the box path runs as always")

probe.answer = nil
local fell = fullBattle()
fell:storeCaughtMon()
T.eq(boxTotal(fell.game.save), 1, "falling through deposits, as today")

run.release()
T.finish("catch party full")
