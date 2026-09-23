local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_ops_icefall_hole"

local CAVE_1F = "FR_FOUR_ISLAND_ICEFALL_CAVE_1F"
local CAVE_B1F = "FR_FOUR_ISLAND_ICEFALL_CAVE_B1F"
-- pokefirered/include/constants/vars.h:9
local VAR_TEMP_1 = 0x4001

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS ops_icefall_hole")
    love.event.quit(0)
  else
    print("FAIL ops_icefall_hole failures=" .. failures)
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
  local Ctx = require("src.core.game3.scripting.ctx")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local function ctx() return Space.vm and Space.vm.ctx end

  local function goTo(mapId, x, y, facing)
    Map.load(nil, game, mapId, { x = x, y = y, facing = facing or "down" })
    if game.session then
      game.session.x, game.session.y, game.session.facing = x, y, facing or "down"
    end
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing or "down"
    U.wait(90)
  end

  local function step(dir)
    local bx, by = Player.cellX, Player.cellY
    for _ = 1, 4 do
      U.hold(game, dir, 8)
      if Player.cellX ~= bx or Player.cellY ~= by then
        while Player.moving do U.wait(1) end
        return true
      end
    end
    return false
  end

  goTo(CAVE_1F, 8, 12, "down")
  result(Runtime.getSession().map == CAVE_1F, "entered Icefall Cave 1F")

  -- pokefirered/data/maps/FourIsland_IcefallCave_1F/scripts.inc:8
  result(Ctx.stepCallback(CAVE_1F) == "ice",
    "ON_RESUME armed STEP_CB_ICE, callback=" .. tostring(Ctx.stepCallback(CAVE_1F)))

  -- pokefirered/src/field_tasks.c:51 sIcefallCaveIceCoords
  while Player.cellY < 14 do
    if not step("down") then break end
  end
  print("[driver] on the ice at (" .. Player.cellX .. "," .. Player.cellY .. ")")
  result(Player.cellX == 8 and Player.cellY == 14,
    "standing on the crackable ice at (" .. Player.cellX .. "," .. Player.cellY .. ")")

  local Field = require("src.core.game3.field")
  -- pokefirered/include/constants/metatile_labels.h:188
  local CRACKED, HOLE = 0x35A, 0x35B
  local function iceAt(x, y)
    local b = Field.metatileOverrides[CAVE_1F]
    local o = b and b[y * 1024 + x]
    return o and o.metatile
  end

  U.wait(12)
  result(iceAt(8, 14) == CRACKED,
    "the first step cracked the thin ice, metatile=" .. string.format("0x%X", iceAt(8, 14) or 0))
  -- pokefirered/src/field_tasks.c:139
  result(Flags.getFlag(Space.store, ctx(), 9) == true, "FLAG_TEMP_9 marks (8,14) visited")
  result((tonumber(Flags.getVar(Space.store, ctx(), VAR_TEMP_1)) or 0) == 0,
    "VAR_TEMP_1 is still 0 after the crack")
  U.shot(game, DIR .. "/2418_ice_cracked.png")

  local Audio = require("src.core.game3.audio")
  local SE = require("src.core.game3.se_ids")
  local seCount = {}
  local realPlaySe = Audio.playSe
  Audio.playSe = function(id, ...)
    seCount[id] = (seCount[id] or 0) + 1
    return realPlaySe(id, ...)
  end

  while Player.cellY > 13 do
    if not step("up") then break end
  end
  result(Player.cellY < 14, "stepped back off the cracked ice")
  U.wait(8)
  while Player.cellY < 14 do
    if not step("down") then break end
  end
  result(Player.cellX == 8 and Player.cellY == 14, "stepped onto the cracked ice again")

  local broke = false
  for _ = 1, 30 do
    U.wait(1)
    if iceAt(8, 14) == HOLE then broke = true break end
  end
  result(broke, "the second step broke the ice into a hole")
  U.shot(game, DIR .. "/2418_ice_broken.png")

  local started = false
  for _ = 1, 120 do
    if Space.vm and Space.vm:isRunning() then
      started = true
      break
    end
    U.wait(1)
  end
  result(started, "the OnFrame fall script started by itself")

  -- data/maps/FourIsland_IcefallCave_1F/scripts.inc:17
  for _ = 1, 60 do
    if not Player.isVisible() then break end
    U.wait(1)
  end
  result(not Player.isVisible(), "set_invisible hid the player over the hole")
  U.wait(2)
  U.shot(game, DIR .. "/2418_fall_vanished.png")

  local pendingSeen = false
  local landed = false
  for _ = 1, 900 do
    U.wait(1)
    if ctx() and ctx().warpPending then pendingSeen = true end
    if Runtime.getSession().map == CAVE_B1F then
      landed = true
      break
    end
  end
  -- pokefirered/src/field_effect.c:1215 FallWarpEffect_4
  local dropping = false
  for _ = 1, 300 do
    local y2 = Player.spriteYOffset or 0
    if Player.isVisible() and y2 < -16 and y2 > -64 then dropping = true break end
    U.wait(1)
  end
  result(dropping, "the player drops in from above on B1F")
  U.shot(game, DIR .. "/2418_fall_dropping.png")
  result(pendingSeen, "warphole marked the warp pending while the fall ran")
  result(landed, "warphole landed the player on Icefall Cave B1F, map="
    .. tostring(Runtime.getSession().map))

  for _ = 1, 600 do
    U.wait(1)
    if not (Space.vm and Space.vm:isRunning()) then break end
  end
  result(not (Space.vm and Space.vm:isRunning()),
    "waitstate released once the fall finished")
  result(ctx() == nil or ctx().warpPending ~= true, "the pending flag was cleared")
  print("[driver] landed at (" .. Player.cellX .. "," .. Player.cellY .. ")")
  result(Player.cellX == 8 and Player.cellY == 14,
    "landed under the hole at (" .. Player.cellX .. "," .. Player.cellY .. ")")
  U.wait(60)
  U.shot(game, DIR .. "/2418_fell_to_b1f.png")
  Audio.playSe = realPlaySe
  -- pokefirered/src/field_tasks.c:236, src/field_effect.c:1210
  result((seCount[SE.SE_ICE_BREAK] or 0) == 1, "SE_ICE_BREAK played once, n=" .. tostring(seCount[SE.SE_ICE_BREAK]))
  result((seCount[SE.SE_FALL] or 0) == 2,
    "SE_FALL played once on each side of the warp, n=" .. tostring(seCount[SE.SE_FALL]))

  result(step("down") or step("left") or step("up"),
    "control came back to the player on B1F")

  finish()
end
