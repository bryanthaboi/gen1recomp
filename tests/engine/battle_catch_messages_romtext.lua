-- BattleState:storeCaughtMon() queues up to two plain-Lua-literal
-- messages: the new-Pokedex-data line (_ItemUseBallText06) and, when the
-- party is full, the box-transfer line (_ItemUseBallText07/08, keyed on
-- EVENT_MET_BILL -- two full, independently-translated ROM strings, not
-- one template with a substituted PC name). This test fakes all three
-- labels and checks the queued messages use them, not the English
-- literals.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
require("src.render.Font").load(Data)

local BattleState = require("src.battle.BattleState")
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")

local function findText(battle, needle)
  for _, entry in ipairs(battle.queue) do
    if entry.text and entry.text:find(needle, 1, true) then return entry.text end
  end
  return nil
end

local function mkbattle(partySize, metBill)
  local save = SaveData.newGame()
  save.party = {}
  for i = 1, partySize do
    save.party[i] = Pokemon.new(Data, "FIXMON_A", 5)
  end
  save.flags = save.flags or {}
  save.flags.EVENT_MET_BILL = metBill
  local game = { data = Data, save = save,
                 stack = { top = function() return nil end, push = function() end } }
  return BattleState.newWild(game, "FIXMON_C", 8)
end

-- empty party: Party.add succeeds, only the new-Pokedex-data message fires
do
  local battle = mkbattle(0, false)
  Data.text._ItemUseBallText06 = "FAKE-DEX {RAM:wEnemyMonNick} FAKE!"
  battle:storeCaughtMon()
  T.eq(findText(battle, "FAKE-DEX"), "FAKE-DEX " .. battle.enemy.name .. " FAKE!",
    "a translated _ItemUseBallText06 reaches the new-Pokedex-data message")
  Data.text._ItemUseBallText06 = nil
end

-- full party, EVENT_MET_BILL true: box transfer via _ItemUseBallText07
do
  local battle = mkbattle(6, true)
  Data.text._ItemUseBallText07 = "FAKE-BILL {RAM:wBoxMonNicks} FAKE!"
  battle:storeCaughtMon()
  T.eq(findText(battle, "FAKE-BILL"), "FAKE-BILL " .. battle.enemy.name .. " FAKE!",
    "EVENT_MET_BILL true routes through the translated _ItemUseBallText07")
  Data.text._ItemUseBallText07 = nil
end

-- full party, EVENT_MET_BILL false: box transfer via _ItemUseBallText08
do
  local battle = mkbattle(6, false)
  Data.text._ItemUseBallText08 = "FAKE-SOMEONE {RAM:wBoxMonNicks} FAKE!"
  battle:storeCaughtMon()
  T.eq(findText(battle, "FAKE-SOMEONE"), "FAKE-SOMEONE " .. battle.enemy.name .. " FAKE!",
    "EVENT_MET_BILL false routes through the translated _ItemUseBallText08")
  Data.text._ItemUseBallText08 = nil
end

-- vanilla, full party, EVENT_MET_BILL true: English literal, BILL's PC
do
  local battle = mkbattle(6, true)
  battle:storeCaughtMon()
  T.eq(findText(battle, "transferred"),
    battle.enemy.name .. " was\ntransferred to\nBILL's PC!",
    "no catalog entry falls back to the English BILL's-PC literal")
end

T.finish("battle_catch_messages_romtext")
