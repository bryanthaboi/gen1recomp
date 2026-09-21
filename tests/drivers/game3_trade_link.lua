local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_trade_link"

-- pokefirered/data/maps/ViridianCity_PokemonCenter_2F/map.json:1
local CENTER_2F = "FR_VIRIDIAN_CITY_POKEMON_CENTER_2F"
-- pokefirered/include/constants/flags.h:1375 FLAG_SYS_POKEDEX_GET
local FLAG_SYS_POKEDEX_GET = 0x829
local ABRA = 63
local MACHOP = 66
local GROWLITHE = 58

local failures = 0

local function say(line)
  print(line)
  os.execute('mkdir -p "' .. DIR .. '" 2>/dev/null')
  local fh = io.open(DIR .. "/trade_link.log", "a")
  if fh then
    fh:write(line, "\n")
    fh:close()
  end
end

local function result(ok, label)
  say((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    say("PASS trade_link")
    love.event.quit(0)
  else
    say("FAIL trade_link failures=" .. failures)
    love.event.quit(1)
  end
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end

  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Player = require("src.core.game3.player")
  local Party = require("src.core.game3.party")
  local Pokemon = require("src.core.game3.pokemon")
  local Message = require("src.ui.game3.message")
  local TradeScene = require("src.core.game3.trade_scene")
  local Trade = require("src.core.game3.scripting.natives_trade")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local function ctx() return Space.vm and Space.vm.ctx end
  Flags.setFlag(Space.store, ctx(), FLAG_SYS_POKEDEX_GET, true)

  session.party = {}
  Party.giveMon(session, ABRA, 16, "ABRA")
  Party.giveMon(session, MACHOP, 14, "MACHOP")
  result(#session.party == 2 and session.party[1].species == ABRA,
    "the player's party opens with an ABRA to send")

  -- pokefirered/src/trade_scene.c:1239 gEnemyParty[gSelectedTradeMonPositions[TRADE_PARTNER]]
  local peerSave = { party = {}, name = "TRIS", trainerId = 31337, gender = "female" }
  Party.giveMon(peerSave, GROWLITHE, 16, "SPARKY")
  local peerMon = peerSave.party[1]
  result(peerMon ~= nil and peerMon.otName == "TRIS",
    "the peer's mon is owned by TRIS, ot=" .. tostring(peerMon and peerMon.otName))

  Map.load(nil, game, CENTER_2F, { x = 10, y = 4, facing = "up" })
  Player.cellX, Player.cellY = 10, 4
  Player.px, Player.py = 10 * 16, 4 * 16
  Player.targetX, Player.targetY = 10, 4
  Player.facing = "up"
  if game.session then
    game.session.x, game.session.y, game.session.facing = 10, 4, "up"
  end
  U.wait(90)
  result(Space.mapId == CENTER_2F, "standing in the cable club room, map=" .. tostring(Space.mapId))
  U.shot(game, DIR .. "/trade_link_01_cable_club.png")

  -- pokefirered/src/trade.c:2745 CanTradeSelectedMon, run before the scene starts
  local mine = Trade.canTradeSelectedMon(session.party, 0, { nationalDex = false })
  result(mine == Trade.CAN_TRADE_MON,
    "the player's ABRA passes the trade rules, code=" .. tostring(mine))
  local lastOne = Trade.canTradeSelectedMon({ session.party[1] }, 0, { nationalDex = false })
  result(lastOne == Trade.CANT_TRADE_LAST_MON,
    "trading away the only mon is refused: " .. tostring(Trade.refusalText(lastOne)))

  local swapped = false
  local evolving = false
  -- pokefirered/src/trade_scene.c:800 sTradeAnim->isLinkTrade = TRUE
  TradeScene.play(session.party[1], peerMon, nil, {
    peer = { name = peerMon.otName, id = peerMon.otId },
    awaitPeer = true,
    awaitSave = true,
    uiDriven = true,
    -- pokefirered/src/trade.c:1297 CB_FadeToStartTrade
    fadeIn = true,
    -- pokefirered/src/trade_scene.c:2533 CB2_UpdateLinkTrade
    onSwap = function()
      swapped = Trade.tradeMons(session, 0, peerMon) ~= nil
    end,
    -- pokefirered/src/trade_scene.c:2322 CB2_TryLinkTradeEvolution
    onEvolve = function(mon)
      evolving = Trade.tryTradeEvolution(mon, session)
    end,
  })
  if not result(TradeScene.isOpen(), "the link trade cinema opened") then return finish() end
  say("[driver] art from the cache: " .. tostring(TradeScene.hasArt()))

  local shots = {
    { "bye_bye", "02_sent_to_peer", 20 },
    { "delay_for_mon_anim", "03_peer_reveal", 20 },
    { "after_new_mon_delay", "04_take_care", 20 },
    { "link_standby", "05_standby", 20 },
    { "link_save", "06_saving", 20 },
  }
  local shotIdx = 1
  local seen = {}
  local waited = 0
  while waited < 7200 do
    local phase = TradeScene.phase()
    if phase then seen[phase] = true end
    local want = shots[shotIdx]
    if want and phase == want[1] then
      U.wait(want[3])
      U.shot(game, DIR .. "/trade_link_" .. want[2] .. ".png")
      shotIdx = shotIdx + 1
    end
    -- pokefirered/src/trade_scene.c:2344
    if phase == "link_wait_peer" then TradeScene.peerConfirmed() end
    if phase == "link_standby" and shotIdx > 4 then TradeScene.linkTaskDone() end
    if phase == "link_save" and shotIdx > 5 then TradeScene.saveDone() end
    if not TradeScene.isOpen() then break end
    U.wait(4)
    waited = waited + 4
  end

  result(not TradeScene.isOpen(), "the link cinema ended, frames waited=" .. waited)
  result(seen.link_wait_peer, "the scene parked for the peer's finish confirmation")
  result(seen.link_standby and seen.link_save,
    "the link standby and saving windows were drawn")
  result(shotIdx > #shots, "took every planned shot, got " .. (shotIdx - 1))
  result(swapped, "the party exchange ran, at end_link_trade")
  say("[driver] trade evolution scene started: " .. tostring(evolving))

  for _ = 1, 200 do
    if not (Space.vm and Space.vm:isRunning()) and not Message.isOpen() then break end
    if Message.isWaiting and Message.isWaiting() then U.tap(game, "a") end
    U.wait(6)
  end
  U.wait(60)

  local got = session.party[1]
  result(got ~= nil and got.species == GROWLITHE,
    "slot 1 now holds the peer's GROWLITHE, species=" .. tostring(got and got.species))
  result(got ~= nil and tostring(got.otName or got.ot) == "TRIS",
    "the received mon kept TRIS as its OT, got " .. tostring(got and (got.otName or got.ot)))
  result(got ~= nil and tonumber(got.otId) == 31337,
    "and kept TRIS's trainer id, got " .. tostring(got and got.otId))
  -- pokefirered/src/pokemon.c:5965 IsTradedMon
  result(Pokemon.isTradedMon(got, session), "the received mon counts as an outsider")
  -- pokefirered/src/trade_scene.c:1075
  result(got ~= nil and tonumber(got.friendship) == 70,
    "the received mon starts at friendship 70, got " .. tostring(got and got.friendship))
  result(#session.party == 2, "the party is still two mons")
  result(session.party[2] ~= nil and session.party[2].species == MACHOP,
    "the mon left behind is untouched")
  result(session.dex and session.dex.owned and session.dex.owned[GROWLITHE] == true,
    "the received species is registered as owned")
  U.shot(game, DIR .. "/trade_link_07_back_on_the_field.png")

  finish()
end
