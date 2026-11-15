-- engine/items/item_effects.asm:561-566
-- engine/items/item_effects.asm:624-629
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
  local saved06 = Data.text._ItemUseBallText06
  Data.text._ItemUseBallText06 = "FAKE-DEX {RAM:wEnemyMonNick} FAKE!"
  battle:storeCaughtMon()
  T.eq(findText(battle, "FAKE-DEX"), "FAKE-DEX " .. battle.enemy.name .. " FAKE!",
    "a translated _ItemUseBallText06 reaches the new-Pokedex-data message")
  Data.text._ItemUseBallText06 = saved06
end

-- full party, EVENT_MET_BILL true: box transfer via _ItemUseBallText07
do
  local battle = mkbattle(6, true)
  local saved07 = Data.text._ItemUseBallText07
  Data.text._ItemUseBallText07 = "FAKE-BILL {RAM:wBoxMonNicks} FAKE!"
  battle:storeCaughtMon()
  T.eq(findText(battle, "FAKE-BILL"), "FAKE-BILL " .. battle.enemy.name .. " FAKE!",
    "EVENT_MET_BILL true routes through the translated _ItemUseBallText07")
  Data.text._ItemUseBallText07 = saved07
end

-- full party, EVENT_MET_BILL false: box transfer via _ItemUseBallText08
do
  local battle = mkbattle(6, false)
  local saved08 = Data.text._ItemUseBallText08
  Data.text._ItemUseBallText08 = "FAKE-SOMEONE {RAM:wBoxMonNicks} FAKE!"
  battle:storeCaughtMon()
  T.eq(findText(battle, "FAKE-SOMEONE"), "FAKE-SOMEONE " .. battle.enemy.name .. " FAKE!",
    "EVENT_MET_BILL false routes through the translated _ItemUseBallText08")
  Data.text._ItemUseBallText08 = saved08
end

do
  local battle = mkbattle(6, true)
  local saved = Data.text._ItemUseBallText07
  Data.text._ItemUseBallText07 = nil
  T.check(not pcall(battle.storeCaughtMon, battle),
    "a cache without _ItemUseBallText07 is an error, not an English literal")
  Data.text._ItemUseBallText07 = saved
end

-- engine/menus/pokedex.asm:581-582 (#2069)
do
  local battle = mkbattle(6, true)
  battle:storeCaughtMon()
  local dexAt, clearAt, transferAt
  for i, entry in ipairs(battle.queue) do
    if entry.ui and not dexAt then dexAt = i end
    if entry.fn and dexAt and not clearAt then
      entry.fn()
      if battle.fieldCleared then clearAt = i end
    end
    if entry.text and not transferAt and entry.text:find("transferred", 1, true) then
      transferAt = i
    end
  end
  T.check(dexAt and clearAt and transferAt,
    "the new-species catch queues the dex page, a clear and the transfer line")
  T.check(dexAt < clearAt and clearAt < transferAt,
    "the field is marked cleared after the dex page and before the transfer line")
  T.eq(battle.fieldCleared, true, "the dex page leaves the battle field cleared")
end

-- engine/items/item_effects.asm:559-566 (#2069)
do
  local battle = mkbattle(6, true)
  battle.game.save.pokedex.owned[battle.enemy.mon.species] = true
  battle:storeCaughtMon()
  for _, entry in ipairs(battle.queue) do
    if entry.fn then entry.fn() end
  end
  T.eq(battle.fieldCleared, nil,
    "an already-owned catch leaves the battle field drawn")
  T.check(findText(battle, "transferred") ~= nil,
    "the already-owned full-party catch still prints the transfer line")
end

T.finish("battle_catch_messages_romtext")
