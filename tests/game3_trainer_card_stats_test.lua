#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function eq(a, b, msg)
  check(a == b, string.format("%s (%s == %s)", msg, tostring(a), tostring(b)))
end

local TrainerCard = require("src.ui.game3.trainer_card")
local Link = require("src.core.game3.link")
local Trade = require("src.core.game3.scripting.natives_trade")

print("[test] 1. The player's card reads the game stats pret reads")
local session = { name = "RED", gameStats = { [Trade.GAME_STAT_POKEMON_TRADES] = 2 } }
-- pokefirered/src/trainer_card.c:824
local c = TrainerCard.cardData(session)
eq(c.pokemonTrades, 2, "two link trades show as POKéMON TRADES 2")
check(c.hasTrades, "and the TRADES line is shown")

session.gameStats[21] = 0x12345
eq(TrainerCard.cardData(session).pokemonTrades, 0xFFFF, "GetCappedGameStat caps trades at 0xFFFF")

-- pokefirered/src/trainer_card.c:822
session.gameStats.linkBattleWins = 12000
session.gameStats.linkBattleLosses = 4
c = TrainerCard.cardData(session)
eq(c.linkBattleWins, 9999, "link wins come from GAME_STAT_LINK_BATTLE_WINS capped at 9999")
eq(c.linkBattleLosses, 4, "link losses come from GAME_STAT_LINK_BATTLE_LOSSES")

-- pokefirered/src/trainer_card.c:877
session.gameStats[50] = 6
eq(TrainerCard.cardData(session).unionRoomNum, 6, "union room count comes from GAME_STAT_NUM_UNION_ROOM_BATTLES")

print("[test] 2. A link partner's card keeps the numbers it was sent")
local peer = TrainerCard.cardData({ name = "BLUE", pokemonTrades = 9, linkBattleWins = 3, unionRoomNum = 2 })
eq(peer.pokemonTrades, 9, "partner trades")
eq(peer.linkBattleWins, 3, "partner link wins")
eq(peer.unionRoomNum, 2, "partner union room count")

print("[test] 3. The card sent over the link carries the trade stat")
local real = Link.session
Link.session = function()
  return { name = "RED", gameStats = { [21] = 5, [50] = 1 }, trainerCard = {} }
end
local sent = Link.localTrainerCard()
Link.session = real
eq(sent.pokemonTrades, 5, "Link.localTrainerCard sends GAME_STAT_POKEMON_TRADES")
eq(sent.unionRoomNum, 1, "and GAME_STAT_NUM_UNION_ROOM_BATTLES")
eq(TrainerCard.cardData(sent).pokemonTrades, 5, "which the card shows")

if failed > 0 then
  print(string.format("[test] %d FAILED", failed))
  os.exit(1)
end
print("[test] all passed")
