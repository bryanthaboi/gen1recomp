local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_surf_pose_2771"

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " em_surf_pose_2771 failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not check(game.boot ~= nil, "boot reached") then return finish() end
  game:_handleBootAction({ action = "new_game", name = "BRENDAN", gender = 0 })
  U.wait(60)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")
  local Party = require("src.core.game3.party")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Collision = require("src.core.game3.collision")
  local Field = require("src.core.game3.field")
  local OwSprites = require("src.core.game3.ow_sprites")
  local ShowMon = require("src.core.game3.field_move_show_mon")
  local C = require("src.core.game3.constants").of("emerald")
  local session = Runtime.getSession()
  if not check(session ~= nil, "field session exists") then return finish() end
  local IDS = Flags.forVersion("emerald").IDS

  session.party = {}
  Party.giveMon(session, C.species.byName.SPECIES_PELIPPER, 50, "PELIPPER")
  session.party[1].moves = { C.moves.byName.MOVE_SURF }
  for i = 1, 8 do Flags.setFlag(Space.store, nil, IDS[string.format("FLAG_BADGE0%d_GET", i)], true) end

  Map.load(nil, game, "EM_ROUTE119", { x = 1, y = 1, facing = "up" })
  local sx, sy
  for y = 1, 138 do
    for x = 1, 38 do
      if not sx and Collision.isWalkable(x, y) and not Collision.isWater(x, y) and Collision.isWater(x, y - 1)
          and Collision.isSurfable(Collision.behavior(x, y - 1)) then
        sx, sy = x, y
      end
    end
  end
  if not check(sx ~= nil, "found a shore cell facing water") then return finish() end
  Map.load(nil, game, "EM_ROUTE119", { x = sx, y = sy, facing = "up" })
  session.x, session.y, session.facing = sx, sy, "up"
  Player.surfing = false
  Field.unlock()
  U.wait(20)

  U.tap(game, "a")
  local poseFrames, poseFacing = {}, {}
  local hopYs, hopFrames, hopGfx = {}, 0, {}
  local sawShowMon, maxPoseFrame = false, -1
  local surfGfx = OwSprites.avatarGraphicsId("SURFING", false)
  for _ = 1, 1500 do
    if Choice.isOpen and Choice.isOpen() or Message._choice then
      U.tap(game, "a")
    elseif Message.isOpen and Message.isOpen() and not ShowMon.isActive() and not Player.surfHopping then
      U.tap(game, "a")
      U.wait(3)
    else
      U.wait(1)
    end
    if Player.fieldMoveAnim and Player.fieldMoveAnim > 0 then
      local f = OwSprites.fieldMoveFrame((Player.fieldMoveTotal or Player.fieldMoveAnim) - Player.fieldMoveAnim)
      if poseFrames[#poseFrames] ~= f then
        poseFrames[#poseFrames + 1] = f
        poseFacing[#poseFacing + 1] = Player.facing
        if f > maxPoseFrame then
          maxPoseFrame = f
          U.still(game, string.format("%s/2771_pose_frame_%d.png", DIR, f))
        end
      end
    end
    if ShowMon.isActive() then sawShowMon = true end
    if Player.surfHopping then
      hopFrames = hopFrames + 1
      hopYs[#hopYs + 1] = Player.jumpSpriteY()
      hopGfx[OwSprites.playerGraphicsId(game) or -1] = true
      if hopFrames == 8 then U.still(game, DIR .. "/2771_hop_midair.png") end
    end
    if Player.surfing and not Player.surfHopping and not Field.locked and not ShowMon.isActive() then break end
  end
  print("[driver] pose frames " .. table.concat(poseFrames, ","))
  print("[driver] pose facing " .. table.concat(poseFacing, ","))
  print("[driver] hop frames " .. hopFrames .. " ys " .. table.concat(hopYs, ","))
  check(sawShowMon, "surf runs the field move show-mon banner")
  check(table.concat(poseFrames, ",") == "0,1,2,3,4", "field move pose plays frames 0..4 (" .. table.concat(poseFrames, ",") .. ")")
  local poseGfx = OwSprites.avatarGraphicsId("FIELD_MOVE", false)
  local poseSpr = OwSprites.get(poseGfx)
  local drawn = {}
  for f = 0, 4 do
    drawn[#drawn + 1] = poseSpr and OwSprites.pose(poseSpr, "up", 0, false, { fieldMove = true, fieldMoveFrame = f }) or -1
  end
  check(table.concat(drawn, ",") == "0,1,2,3,4", "field move sheet draws frames 0..4 (" .. table.concat(drawn, ",") .. ")")
  -- pokeemerald/src/event_object_movement.c:8424
  local HIGH = { -4, -6, -8, -10, -11, -12, -12, -12, -11, -10, -9, -8, -6, -4, 0, 0 }
  local want = { 0 }
  for t = 0, 30 do want[#want + 1] = HIGH[math.floor(t / 2) + 1] end
  check(hopFrames == 32, "surf mount is a 32-frame special jump (" .. hopFrames .. ")")
  check(table.concat(hopYs, ",") == table.concat(want, ","), "surf mount jump follows sJumpY_High at half rate")
  check(hopGfx[surfGfx] == true, "player uses the surfing graphics during the mount jump")
  check(Player.surfing, "player ends surfing")
  U.shot(game, DIR .. "/2771_surfing_done.png")
  finish()
end
