local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_link_continue_warp"

local CENTER_2F = "FR_VIRIDIAN_CITY_POKEMON_CENTER_2F"
local TRADE_CENTER = "FR_TRADE_CENTER"
-- pokefirered/data/specials.inc:5 SetCableClubWarp
local SET_CABLE_CLUB_WARP = 0x01
-- pokefirered/include/constants/vars.h:163
local VAR_CABLE_CLUB_STATE = 0x406F
local VAR_0x8004 = 0x8004

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " link_continue_warp failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
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
  local Natives = require("src.core.game3.scripting.natives")
  local Link = require("src.core.game3.link")
  local Game3Link = require("src.link.Game3Link")
  local Message = require("src.ui.game3.message")
  local SaveData = require("src.core.SaveData")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local function ctx() return Space.vm and Space.vm.ctx end
  local function getVar(id) return tonumber(Flags.getVar(Space.store, ctx(), id)) or 0 end
  local function setVar(id, v) Flags.setVar(Space.store, ctx(), id, v) end
  local function place(x, y, facing)
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing
    if game.session then
      game.session.x, game.session.y, game.session.facing = x, y, facing
    end
  end

  session.party = {}
  Party.giveMon(session, 6, 50)
  Party.giveMon(session, 1, 48)

  Map.load(nil, game, CENTER_2F, { x = 9, y = 2, facing = "up" })
  place(9, 2, "up")
  U.wait(60)
  place(9, 1, "up")
  U.wait(10)
  -- pokefirered/data/scripts/cable_club.inc:408
  Natives.special(ctx(), SET_CABLE_CLUB_WARP, Space.vm and Space.vm.adapters)
  local dw = session.dynamicWarp or {}
  result(dw.map == CENTER_2F and tonumber(dw.x) == 9 and tonumber(dw.y) == 1,
    "SetCableClubWarp recorded the trade center door as the dynamic warp")

  local host, peer = Game3Link.loopback({ game = game })
  host:update(0)
  peer:update(0)
  Link.attach(host)

  -- pokefirered/data/scripts/cable_club.inc:388
  setVar(VAR_0x8004, Link.USING.TRADE_CENTER)
  setVar(VAR_CABLE_CLUB_STATE, Link.USING.TRADE_CENTER)
  Map.load(nil, game, TRADE_CENTER, { x = 5, y = 8, facing = "up" })
  place(5, 8, "up")
  U.wait(90)
  local s1 = Runtime.getSession()
  if not result(s1 and s1.map == TRADE_CENTER, "the player is inside the trade center") then
    Link.reset()
    return finish()
  end
  U.shot(game, DIR .. "/link_continue_01_trade_center.png")

  -- pokefirered/src/trade_scene.c:2610
  local wrote = game:saveGame()
  result(wrote ~= false, "the link-room save was written")
  local okL, save = pcall(SaveData.load)
  save = okL and save or {}
  local w = type(save.continueGameWarp) == "table" and save.continueGameWarp or {}
  print(string.format("SAVED map=%s x=%s y=%s flags=%s warp=%s %s,%s", tostring(save.map),
    tostring(save.x), tostring(save.y), tostring(save.specialSaveWarpFlags),
    tostring(w.map), tostring(w.x), tostring(w.y)))
  result(save.map == TRADE_CENTER, "the save was taken inside the trade center")
  result((tonumber(save.specialSaveWarpFlags) or 0) % 2 == 1, "save carries CONTINUE_GAME_WARP")
  result(w.map == CENTER_2F and w.x == 9 and w.y == 1, "continue warp is the cable club door 9,1")

  Link.reset()
  game.softResetRequested = true
  U.wait(60)
  game:_handleBootAction({ action = "continue" })
  local s2
  for _ = 1, 900 do
    s2 = Runtime.getSession()
    if s2 and game.phase ~= "quest_log" then break end
    if game.phase == "quest_log" then U.tap(game, "b") end
    U.wait(4)
  end
  print(string.format("CONTINUE map=%s x=%s y=%s", tostring(s2 and s2.map),
    tostring(s2 and s2.x), tostring(s2 and s2.y)))
  result(s2 and s2.map == CENTER_2F and s2.x == 9 and s2.y == 1,
    "continue lands outside the trade center at the dynamic warp 9,1")

  local cleared = false
  for _ = 1, 600 do
    if Message.isOpen() and Message.isTyping() then Message.skipReveal() end
    if Message.isOpen() and Message.isWaiting() then U.tap(game, "a") end
    if Runtime.getSession() and getVar(VAR_CABLE_CLUB_STATE) == 0 and not Player.moving then
      cleared = true
      break
    end
    U.wait(2)
  end
  U.wait(30)
  local s3 = Runtime.getSession()
  print(string.format("AFTER map=%s cell=%s,%s var=%s", tostring(s3 and s3.map),
    tostring(Player.cellX), tostring(Player.cellY), tostring(getVar(VAR_CABLE_CLUB_STATE))))
  U.shot(game, DIR .. "/link_continue_02_outside_cable_club.png")
  result(cleared, "the cable club exit script cleared VAR_CABLE_CLUB_STATE")
  result(Space.mapId == CENTER_2F, "the player stays in the pokemon center 2F")
  finish()
end
