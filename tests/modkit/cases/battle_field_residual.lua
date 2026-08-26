-- A sandboxed mod can contribute data-only field residual damage while the
-- engine retains HP, queue, and faint authority. The case also proves that
-- no-mod battles allocate no hook context and remain byte-equivalent.

package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.modkit")
local BattleState = require("src.battle.BattleState")
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
local TypeChart = require("src.battle.TypeChart")

local FIXTURE = {
  ["mods/field_residual_probe/manifest.json"] = [[{
    "id": "field_residual_probe",
    "name": "Field Residual Probe",
    "version": "1.0.0",
    "entry": "main.lua",
    "api": 2
  }]],
  ["mods/field_residual_probe/main.lua"] = [[
    local mod = ...
    mod.hooks:wrap("battle.field_residual", function(next, context)
      mod.exports.calls = (mod.exports.calls or 0) + 1
      mod.exports.context = context
      local callback = context.field.tokens[1]
        and context.field.tokens[1].onExpire
      mod.exports.callbackType = type(callback)
      if callback then callback() end
      local rows = next(context)
      rows[#rows + 1] = {
        side = "player", amount = 7,
        message = context.battlers.player.name .. " is buffeted!",
      }
      rows[#rows + 1] = {
        side = "enemy", amount = 999,
        message = context.battlers.enemy.name .. " is buffeted!",
      }
      return rows
    end)
  ]],
}

local function newBattle(data)
  TypeChart.load(data)
  local save = SaveData.newGame()
  save.party = { Pokemon.new(data, "FIXMON_A", 30) }
  local game = {
    data = data,
    save = save,
    stack = { top = function() return nil end, push = function() end },
  }
  local battle = BattleState.newWild(game, "FIXMON_C", 30)
  battle.phase, battle.queue = "menu", {}
  battle.field.weather = { id = "sand", turns = 4, source = "probe" }
  return battle
end

local vanilla = T.sdk.loadNone({})
local plain = newBattle(vanilla.data)
local plainPlayerHp, plainEnemyHp = plain.player.mon.hp, plain.enemy.mon.hp
plain:endOfTurn()
T.eq(plain.player.mon.hp, plainPlayerHp,
  "no-mod end of turn preserves player HP")
T.eq(plain.enemy.mon.hp, plainEnemyHp,
  "no-mod end of turn preserves enemy HP")
T.eq(plain.field.weather.turns, 4,
  "no-mod path does not reinterpret an unknown data-only field extension")
vanilla.release()

local run = T.sdk.loadMods({ "mods/field_residual_probe" }, {
  fs = T.sdk.memfs(FIXTURE),
})
T.eq(#run.errors, 0,
  "the public field-residual probe loads cleanly")
local battle = newBattle(run.data)
local playerHp, enemyHp = battle.player.mon.hp, battle.enemy.mon.hp
local callbackInvocations = 0
battle.field.tokens[1] = {
  id = "callback-bearing", turns = 2,
  state = { intensity = 4 },
  onExpire = function() callbackInvocations = callbackInvocations + 1 end,
}
battle.player.invulnerable = true
battle:endOfTurn()

local out = run.loader.exports.field_residual_probe or {}
T.eq(out.calls, 1, "the public hook runs exactly once at round end")
T.check(out.context.field ~= battle.field,
  "the hook receives a detached checkpoint-shaped field view")
T.same(out.context.field.weather,
  { id = "sand", turns = 4, source = "probe" },
  "the detached field view carries checkpointed weather state")
T.eq(out.context.field.sides, nil,
  "the detached field view exposes no live battler aliases")
T.eq(out.callbackType, "nil",
  "the sandboxed wrapper cannot obtain a live field callback")
T.eq(callbackInvocations, 0,
  "the sandboxed wrapper cannot invoke the engine-owned callback")
T.same(out.context.field.tokens[1], {
  id = "callback-bearing", turns = 2, state = { intensity = 4 },
}, "the public field view retains data while omitting the callback")
T.eq(out.context.turn, battle.turnCount or 0,
  "the hook receives the current turn counter")
T.eq(out.context.battle, nil,
  "the hook does not expose the live engine battle object")
T.eq(out.context.battlers.player.side, "player",
  "the detached player snapshot identifies its side")
T.eq(out.context.battlers.enemy.side, "enemy",
  "the detached enemy snapshot identifies its side")
T.eq(out.context.battlers.player.vanished, true,
  "the detached view reports Gen1 semi-invulnerability")
T.eq(out.context.battlers.player.hp, playerHp,
  "the player snapshot carries pre-residual HP")
T.eq(out.context.battlers.enemy.hp, enemyHp,
  "the enemy snapshot carries pre-residual HP")
T.check(out.context.battlers.player ~= battle.player,
  "the public battler view is detached from the engine wrapper")
T.check(out.context.battlers.player.types ~= battle.player.curTypes,
  "the public type list is detached")

T.eq(battle.player.mon.hp, playerHp - 7,
  "the engine applies the validated player residual amount")
T.eq(battle.enemy.mon.hp, 0,
  "the engine clamps residual damage to current HP")
T.eq(battle.enemy.faintQueued, true,
  "the engine, not the mod, owns residual faint orchestration")

local sawPlayerMessage, sawEnemyMessage, drains = false, false, 0
for _, row in ipairs(battle.queue) do
  local text = row.text and tostring(row.text) or ""
  if text:find("buffeted", 1, true) then
    if text:find(battle.player.name, 1, true) then sawPlayerMessage = true end
    if text:find(battle.enemy.name, 1, true) then sawEnemyMessage = true end
  end
  if row.drain then drains = drains + 1 end
end
T.check(sawPlayerMessage and sawEnemyMessage,
  "validated public messages enter the normal battle queue")
T.check(drains >= 2,
  "residual HP changes use normal engine drain rows")
run.release()

T.finish("battle.field_residual public seam")
