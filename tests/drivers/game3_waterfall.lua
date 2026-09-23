local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_waterfall"

local CAVE = "FR_FOUR_ISLAND_ICEFALL_CAVE_ENTRANCE"
local START_X, START_Y = 10, 21

-- pokefirered/include/constants/flags.h:1364
local FLAG_BADGE05_GET = 0x824
local FLAG_BADGE07_GET = 0x826
local SPECIES_GYARADOS = 130
local MOVE_SURF, MOVE_WATERFALL = 57, 127
local MB_WATERFALL = 0x13

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS waterfall")
    love.event.quit(0)
  else
    print("FAIL waterfall failures=" .. failures)
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
  local Field = require("src.core.game3.field")
  local Player = require("src.core.game3.player")
  local Party = require("src.core.game3.party")
  local Collision = require("src.core.game3.collision")
  local FieldMoves = require("src.core.game3.field_moves")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local function ctx() return Space.vm and Space.vm.ctx end
  Flags.setFlag(Space.store, ctx(), FLAG_BADGE05_GET, true)
  Flags.setFlag(Space.store, ctx(), FLAG_BADGE07_GET, true)

  session.party = {}
  Party.giveMon(session, SPECIES_GYARADOS, 70)
  local lead = session.party[1]
  lead.moves = { MOVE_SURF, MOVE_WATERFALL }
  lead.pp, lead.maxPp = { 15, 15 }, { 15, 15 }

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

  goTo(CAVE, START_X, START_Y, "down")
  local w = Collision._widthCells or 0
  local h = Collision._heightCells or 0
  print(string.format("[driver] %s grid %dx%d", CAVE, w, h))

  local falls = {}
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      if Collision.behavior(x, y) == MB_WATERFALL then
        falls[#falls + 1] = { x = x, y = y }
      end
    end
  end
  print("[driver] MB_WATERFALL cells: " .. #falls)
  for _, c in ipairs(falls) do print(string.format("[driver]   (%d,%d)", c.x, c.y)) end
  if not result(#falls > 0, "Icefall Cave 1F has MB_WATERFALL tiles") then return finish() end

  local foot = falls[1]
  for _, c in ipairs(falls) do
    if c.y > foot.y or (c.y == foot.y and c.x < foot.x) then foot = c end
  end
  local baseX, baseY = foot.x, foot.y + 1
  print(string.format("[driver] waterfall foot (%d,%d), climb from (%d,%d)", foot.x, foot.y, baseX, baseY))
  result(Collision.isWater(baseX, baseY), "the tile below the waterfall is water")

  local shore = nil
  for sy = baseY, baseY + 6 do
    for sx = baseX, baseX - 8, -1 do
      if Collision.isWalkable(sx, sy) and not Collision.isWater(sx, sy)
        and Collision.isWater(sx + 1, sy) then
        shore = { x = sx, y = sy, dx = 1, dy = 0 }
        break
      end
    end
    if shore then break end
  end

  local function faceFrom(sx, sy, tx, ty)
    if ty < sy then return "up" elseif ty > sy then return "down"
    elseif tx < sx then return "left" else return "right" end
  end

  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")
  local function answerYes(limit)
    local sawPrompt = false
    for _ = 1, (limit or 90) do
      local open = Message and Message.isOpen and Message.isOpen()
      local choosing = Choice and Choice.active == true
      if open or choosing then sawPrompt = true end
      if not open and not choosing then break end
      U.tap(game, "a")
      U.wait(10)
    end
    return sawPrompt
  end

  if shore then
    local sx, sy = shore.x, shore.y
    local nx, ny = sx + shore.dx, sy + shore.dy
    print(string.format("[driver] mounting Surf from shore (%d,%d) facing water (%d,%d)", sx, sy, nx, ny))
    goTo(CAVE, sx, sy, faceFrom(sx, sy, nx, ny))
    U.shot(game, DIR .. "/waterfall_01_shore.png")
    U.tap(game, "a")
    U.wait(20)
    answerYes(60)
    for _ = 1, 120 do
      if Player.surfing then break end
      U.wait(4)
    end
    answerYes(60)
  else
    print("[driver] no shore tile adjacent to the pool; starting already on the water")
  end

  if not result(Player.surfing == true, "the player is surfing (EventScript_UseSurf)") then
    U.shot(game, DIR .. "/waterfall_02_no_surf.png")
    return finish()
  end
  U.shot(game, DIR .. "/waterfall_02_surfing.png")

  for _ = 1, 60 do
    if Player.cellX == baseX and Player.cellY == baseY then break end
    if Player.cellX < baseX then U.hold(game, "right", 24)
    elseif Player.cellX > baseX then U.hold(game, "left", 24)
    elseif Player.cellY > baseY then U.hold(game, "up", 24)
    elseif Player.cellY < baseY then U.hold(game, "down", 24)
    end
    U.wait(10)
    if Message.isOpen and Message.isOpen() then answerYes(40) end
  end
  print(string.format("[driver] at (%d,%d) facing %s", Player.cellX, Player.cellY, Player.facing))
  if not result(Player.cellX == baseX and Player.cellY == baseY,
    "swam to the foot of the waterfall") then
    U.shot(game, DIR .. "/waterfall_03_lost.png")
    return finish()
  end

  -- pokefirered/src/field_player_avatar.c:147
  local gateStart = Player.cellY
  local gateMinY = Player.cellY
  for _ = 1, 20 do
    U.hold(game, "up", 8)
    if Player.cellY < gateMinY then gateMinY = Player.cellY end
  end
  U.wait(60)
  print(string.format("[driver] after holding UP with no HM use: (%d,%d), lowest y reached %d",
    Player.cellX, Player.cellY, gateMinY))
  result(gateMinY >= foot.y,
    "holding UP alone never lifts the player past the bottom waterfall tile, y "
      .. gateStart .. " -> " .. gateMinY)
  result(Field._waterfall == nil, "the D-pad alone never started FLDEFF_USE_WATERFALL")
  U.shot(game, DIR .. "/waterfall_03_gate.png")

  for _ = 1, 60 do
    if Player.cellY == baseY and not Player.moving then break end
    U.wait(4)
  end
  if Player.facing ~= "up" then
    U.hold(game, "up", 2)
    U.wait(20)
  end
  print(string.format("[driver] before the A press: (%d,%d) facing %s stack=%s",
    Player.cellX, Player.cellY, Player.facing,
    tostring(game.stack and game.stack:top() and (game.stack:top().name or "?"))))
  result(Player.facing == "up", "the swim north left the player facing the waterfall")
  result(FieldMoves.isWaterfallBehavior(Collision.behavior(Player.cellX, Player.cellY - 1)),
    "facing an MB_WATERFALL tile")
  U.shot(game, DIR .. "/waterfall_03_at_foot.png")

  local startY = Player.cellY
  U.tap(game, "a")
  U.wait(20)
  local asked = answerYes(90)
  result(asked, "EventScript_Waterfall opened its prompt")

  local climbStarted = false
  for _ = 1, 4000 do
    if Field._waterfall ~= nil then climbStarted = true end
    if climbStarted and Field._waterfall == nil and not Player.moving and not Field.locked then break end
    if Message.isOpen() or Choice.active == true then U.tap(game, "a") end
    U.wait(4)
  end
  U.wait(40)
  print(string.format("[driver] after the climb: (%d,%d) surfing=%s locked=%s",
    Player.cellX, Player.cellY, tostring(Player.surfing), tostring(Field.locked)))
  result(Player.cellY < startY, "the player climbed the waterfall, y " .. startY .. " -> " .. Player.cellY)
  result(not FieldMoves.isWaterfallBehavior(Collision.behavior(Player.cellX, Player.cellY)),
    "the climb ended above the waterfall, not on it")
  result(Field.locked == false, "player control came back after the climb")
  result(Player.surfing == true, "the player is still surfing at the top")
  U.shot(game, DIR .. "/waterfall_04_top.png")

  -- pokefirered/src/field_player_avatar.c:246
  local topY = Player.cellY
  result(FieldMoves.isWaterfallBehavior(Collision.behavior(Player.cellX, topY + 1)),
    "the tile south of the landing is the waterfall's head")
  U.hold(game, "down", 24)
  for _ = 1, 500 do
    if not Player.moving and Player.cellY >= baseY then break end
    U.wait(4)
  end
  U.wait(40)
  print(string.format("[driver] after going down: (%d,%d)", Player.cellX, Player.cellY))
  result(Player.cellY >= baseY,
    "the current washed the player from y=" .. topY .. " back to the foot, y=" .. Player.cellY)
  result(not FieldMoves.isWaterfallBehavior(Collision.behavior(Player.cellX, Player.cellY)),
    "the player does not rest on a waterfall tile")
  U.shot(game, DIR .. "/waterfall_05_washed_down.png")

  -- pokefirered/src/field_control_avatar.c:613
  Flags.setFlag(Space.store, ctx(), FLAG_BADGE07_GET, false)
  if Player.facing ~= "up" then
    U.hold(game, "up", 2)
    U.wait(20)
  end
  local beforeY = Player.cellY
  U.tap(game, "a")
  U.wait(30)
  answerYes(60)
  U.wait(30)
  print(string.format("[driver] after the refusal: (%d,%d) surfing=%s",
    Player.cellX, Player.cellY, tostring(Player.surfing)))
  result(Player.cellY == beforeY, "without the Volcano Badge the climb is refused")
  result(Player.surfing == true, "the refusal leaves the player surfing at the foot")
  U.wait(60)
  U.shot(game, DIR .. "/waterfall_06_no_badge.png")

  finish()
end
