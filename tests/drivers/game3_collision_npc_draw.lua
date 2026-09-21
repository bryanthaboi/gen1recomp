local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_collision_npc_draw"

local TUNNEL = "FR_ROCK_TUNNEL_B1F"
local CINNABAR = "FR_CINNABAR_ISLAND"
local TUTOR, BILL = 9, 3

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS collision_npc_draw")
    love.event.quit(0)
  else
    print("FAIL collision_npc_draw failures=" .. failures)
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
  local Player = require("src.core.game3.player")
  local Objects = require("src.core.game3.objects")
  local OwSprites = require("src.core.game3.ow_sprites")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local FlagsTable = require("src.core.game3.scripting.flags_table")
  local Message = require("src.ui.game3.message")

  if not result(Runtime.getSession() ~= nil, "new game reached the game3 field") then
    return finish()
  end

  local function settle(limit)
    for _ = 1, (limit or 240) do
      local busy = (Space.vm and Space.vm:isRunning())
        or (Message.isOpen and Message.isOpen())
      if not busy then return true end
      if Message.isOpen and Message.isOpen() then U.tap(game, "a") end
      U.wait(4)
    end
    return false
  end

  local function place(x, y, facing)
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.moving = false
    Player.progress = 0
    Player.facing = facing or "down"
    if game.session then
      game.session.x, game.session.y, game.session.facing = x, y, facing or "down"
    end
  end

  local function goTo(mapId, x, y, facing)
    Map.load(nil, game, mapId, { x = x, y = y, facing = facing or "down" })
    place(x, y, facing)
    U.wait(90)
    settle(600)
    place(x, y, facing)
    U.wait(30)
  end

  local function drawn(localId)
    for _, eo in ipairs(Objects.forDraw()) do
      if eo.localId == localId then return eo end
    end
    return nil
  end

  result(OwSprites.ready() == true, "the FRLG overworld sprite sheets are mounted")

  print("[driver] 1. the Rock Tunnel B1F move tutor")
  goTo(TUNNEL, 3, 29, "left")
  local tutor = drawn(TUTOR)
  if result(tutor ~= nil, "the tutor is in the draw list") then
    result(tutor.cellX == 2 and tutor.cellY == 29,
      string.format("and stands at (%d,%d)", tutor.cellX, tutor.cellY))
    result(OwSprites.get(tutor.graphicsId) ~= nil,
      "OBJ_EVENT_GFX " .. tostring(tutor.graphicsId) .. " has a loaded sheet")
    result(tutor.px == 2 * 16 and tutor.py == 29 * 16,
      string.format("his draw origin is (%s,%s)",
        tostring(tutor.px), tostring(tutor.py)))
  end
  U.shot(game, DIR .. "/collision_npc_draw_01_rock_tunnel_tutor.png")

  print("[driver] 2. Bill on Cinnabar Island")
  local billFlag = FlagsTable.FLAGS.FLAG_HIDE_CINNABAR_BILL
  result(billFlag ~= nil, "FLAG_HIDE_CINNABAR_BILL is in the flag table")
  if billFlag and Space.store and Space.vm then
    Flags.setFlag(Space.store, Space.vm.ctx, billFlag, false)
  end
  goTo(CINNABAR, 21, 8, "left")
  result(Flags.getFlag(Space.store, Space.vm.ctx, billFlag) == false,
    "FLAG_HIDE_CINNABAR_BILL is clear on arrival")
  local bill = drawn(BILL)
  if result(bill ~= nil, "Bill is in the draw list") then
    result(bill.cellX == 20 and bill.cellY == 7,
      string.format("and stands at (%d,%d)", bill.cellX, bill.cellY))
    result(OwSprites.get(bill.graphicsId) ~= nil,
      "OBJ_EVENT_GFX " .. tostring(bill.graphicsId) .. " has a loaded sheet")
    result(bill.px == 20 * 16 and bill.py == 7 * 16,
      string.format("his draw origin is (%s,%s)",
        tostring(bill.px), tostring(bill.py)))
  end
  U.shot(game, DIR .. "/collision_npc_draw_02_cinnabar_bill.png")

  print("[driver] 3. standing due south of an NPC covers its legs, not the NPC")
  goTo(TUNNEL, 2, 30, "up")
  local under = drawn(TUTOR)
  result(under ~= nil, "the tutor is still drawn with the player one cell south")
  result(under ~= nil and (under.py or 0) < (Player.py or 0),
    "and sorts before the player, whose 16x32 sprite covers his lower half")
  U.shot(game, DIR .. "/collision_npc_draw_03_tutor_overlapped.png")

  finish()
end
