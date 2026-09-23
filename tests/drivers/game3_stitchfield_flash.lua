local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_stitchfield_flash"

local ROCK_TUNNEL = "FR_ROCK_TUNNEL_1F"
-- pokefirered/include/constants/flags.h:1364 FLAG_BADGE01_GET
local FLAG_BADGE01_GET = 0x820

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS stitchfield_flash")
    love.event.quit(0)
  else
    print("FAIL stitchfield_flash failures=" .. failures)
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
  local Party = require("src.core.game3.party")
  local Player = require("src.core.game3.player")
  local Field = require("src.core.game3.field")
  local FieldMoves = require("src.core.game3.field_moves")
  local FieldView = require("src.core.game3.field_view")
  local Message = require("src.ui.game3.message")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  session.party = {}
  Party.giveMon(session, 25, 20)
  Flags.setFlag(Space.store, Space.vm and Space.vm.ctx, FLAG_BADGE01_GET, true)

  Map.load(nil, game, ROCK_TUNNEL, { x = 6, y = 7, facing = "down" })
  Player.cellX, Player.cellY = 6, 7
  Player.px, Player.py = 6 * 16, 7 * 16
  Player.targetX, Player.targetY = 6, 7
  if game.session then game.session.x, game.session.y = 6, 7 end
  U.wait(120)

  local mapDef = Map.currentDef()
  result(mapDef ~= nil and tonumber(mapDef.cave) == 1, "Rock Tunnel 1F is a cave map")
  print("[driver] on " .. tostring(Space.mapId) .. " flashLevel="
    .. tostring(FieldView.getFlashLevel and FieldView.getFlashLevel()))
  U.shot(game, DIR .. "/stitchfield_flash_01_dark_cave.png")

  -- pokefirered/src/fldeff_flash.c:164 SetUpFieldMove_Flash
  local ctx = {
    party = session.party,
    mon = session.party[1],
    store = Space.store,
    session = session,
    facing = Player.facing,
    mapType = mapDef and mapDef.mapType,
    isCave = tonumber(mapDef and mapDef.cave) == 1,
  }
  local res = FieldMoves.fromMenu(FieldMoves.MOVES.FLASH, ctx)
  if not result(res ~= nil and res.ok == true and res.action == "flash",
    "the party menu FLASH entry is usable here, text=" .. tostring(res and res.text)) then
    return finish()
  end

  -- pokefirered/src/fldeff_flash.c:177 FieldCallback_Flash
  Field.executeFieldMove(res)
  result(res.text == nil, "FLASH carries no field text")
  result(Field.locked == true, "the field is locked for the show-mon animation")
  U.wait(6)
  result(Message.isOpen() == false, "no message box while the animation runs")
  U.shot(game, DIR .. "/stitchfield_flash_02_show_mon.png")

  for _ = 1, 300 do
    if not Field.locked then break end
    U.wait(1)
  end
  result(Field.locked == false, "the animation finished and released the field")
  -- pokefirered/data/scripts/flash.inc:1 EventScript_FldEffFlash
  result(Message.isOpen() == false, "and no message followed it")
  result(Flags.getFlag(Space.store, Space.vm and Space.vm.ctx, FieldMoves.SYS_FLAGS.FLASH_ACTIVE) == true,
    "FLAG_SYS_FLASH_ACTIVE is set")
  print("[driver] after the animation flashLevel="
    .. tostring(FieldView.getFlashLevel and FieldView.getFlashLevel()))
  U.shot(game, DIR .. "/stitchfield_flash_03_lit_cave.png")

  finish()
end
