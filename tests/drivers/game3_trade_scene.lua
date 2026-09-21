local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_trade_scene"

-- pokefirered/data/maps/Route2_House/map.json:1
local HOUSE = "FR_ROUTE_2_HOUSE"
local REYLEY_X, REYLEY_Y = 7, 2
-- pokefirered/src/data/ingame_trades.h:1 INGAME_TRADE_MR_MIME
local ABRA = 63
local MR_MIME = 122

local failures = 0

local function say(line)
  print(line)
  os.execute('mkdir -p "' .. DIR .. '" 2>/dev/null')
  local fh = io.open(DIR .. "/trade_scene.log", "a")
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
    say("PASS trade_scene")
    love.event.quit(0)
  else
    say("FAIL trade_scene failures=" .. failures)
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
  local Player = require("src.core.game3.player")
  local Party = require("src.core.game3.party")
  local PartyMenu = require("src.ui.game3.party_menu")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")
  local TradeScene = require("src.core.game3.trade_scene")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  session.party = {}
  Party.giveMon(session, ABRA, 12)
  Party.giveMon(session, 25, 9)
  result(#session.party == 2 and session.party[1].species == ABRA,
    "the party opens with an ABRA to trade")

  Map.load(nil, game, HOUSE, { x = REYLEY_X, y = REYLEY_Y + 1, facing = "up" })
  Player.cellX, Player.cellY = REYLEY_X, REYLEY_Y + 1
  Player.px, Player.py = REYLEY_X * 16, (REYLEY_Y + 1) * 16
  Player.targetX, Player.targetY = REYLEY_X, REYLEY_Y + 1
  Player.facing = "up"
  if game.session then
    game.session.x, game.session.y, game.session.facing = REYLEY_X, REYLEY_Y + 1, "up"
  end
  U.wait(90)
  result(Space.mapId == HOUSE, "standing in Route 2 House, map=" .. tostring(Space.mapId))

  local Audio = require("src.core.game3.audio")
  local songBefore = Audio._currentSong and Audio._currentSong.id
  say("[driver] map music before the trade: " .. tostring(songBefore))

  say("[driver] talking to Reyley")
  U.tap(game, "a")
  U.wait(30)

  local opened = false
  for _ = 1, 120 do
    if PartyMenu.isOpen and PartyMenu.isOpen() then
      opened = true
      break
    end
    if Choice.active or (Message.isWaiting and Message.isWaiting()) then
      U.tap(game, "a")
    end
    U.wait(6)
  end
  if not result(opened, "the trade offer reached the party picker") then return finish() end

  say("[driver] handing over the ABRA in slot 1")
  U.tap(game, "a")
  U.wait(40)

  local started = false
  for _ = 1, 200 do
    if TradeScene.isOpen() then
      started = true
      break
    end
    if Choice.active or (Message.isWaiting and Message.isWaiting()) then
      U.tap(game, "a")
    end
    U.wait(6)
  end
  if not result(started, "the trade cinema started") then return finish() end
  say("[driver] art from the cache: " .. tostring(TradeScene.hasArt()))

  local shots = {
    { "mon_slide_in", "01_mon_slide_in" },
    { "bye_bye", "02_bye_bye" },
    { "pokeball_depart_wait", "03_ball_leaves" },
    -- pokefirered/src/trade_scene.c:1433 STATE_GBA_FLASH_SEND
    { "gba_stop_flash_send", "04_gba_flash" },
    { "take_care_of_mon", "05_reveal" },
  }
  local shotIdx = 1
  local seenPhases = {}
  local waited = 0
  while waited < 5400 do
    local phase = TradeScene.phase()
    if phase then seenPhases[phase] = true end
    local want = shots[shotIdx]
    if want and phase == want[1] then
      U.wait(20)
      U.shot(game, DIR .. "/trade_scene_" .. want[2] .. ".png")
      shotIdx = shotIdx + 1
    end
    if phase == "end_link_trade" then
      U.tap(game, "a")
    end
    if not TradeScene.isOpen() then break end
    U.wait(4)
    waited = waited + 4
  end
  result(not TradeScene.isOpen(), "the cinema ended, frames waited=" .. waited)
  result(seenPhases.mon_slide_in and seenPhases.bye_bye and seenPhases.take_care_of_mon,
    "the cinema played the slide-in, the send-off and the reveal")
  result(shotIdx > #shots, "took every planned shot, got " .. (shotIdx - 1))

  for _ = 1, 200 do
    if not (Space.vm and Space.vm:isRunning()) and not Message.isOpen() then break end
    if Message.isWaiting and Message.isWaiting() then U.tap(game, "a") end
    U.wait(6)
  end
  U.wait(60)

  local songAfter = Audio._currentSong and Audio._currentSong.id
  -- pokefirered/src/trade_scene.c:1790
  result(songAfter == songBefore,
    "the map music came back, before=" .. tostring(songBefore) .. " after=" .. tostring(songAfter))

  local got = session.party[1]
  result(got ~= nil and got.species == MR_MIME,
    "slot 1 now holds MR. MIME, species=" .. tostring(got and got.species))
  result(got ~= nil and tostring(got.otName or got.ot) == "REYLEY",
    "the received mon kept REYLEY as its OT, got " .. tostring(got and (got.otName or got.ot)))
  result(#session.party == 2, "the party is still two mons")
  U.shot(game, DIR .. "/trade_scene_06_back_on_the_field.png")

  finish()
end
