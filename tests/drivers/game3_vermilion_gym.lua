local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_vermilion_gym"

local CITY = "FR_VERMILION_CITY"
local GYM = "FR_VERMILION_CITY_GYM"

-- pokefirered/data/maps/VermilionCity_Gym/scripts.inc:1-4
local VAR_TEMP_0, VAR_TEMP_1 = 0x4000, 0x4001
local FLAG_TEMP_1 = 0x01
local FLAG_FOUND_BOTH = 0x264
local FLAG_BADGE01_GET = 0x820
local FLAG_GOT_SS_TICKET = 0x234
local FLAG_DEFEATED_LT_SURGE = 0x4B3

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS vermilion_gym")
    love.event.quit(0)
  else
    print("FAIL vermilion_gym failures=" .. failures)
    love.event.quit(1)
  end
end

local function canCell(id)
  local i = id - 1
  return 1 + 2 * (i % 5), 10 + 2 * math.floor(i / 5)
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

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local function ctx() return Space.vm and Space.vm.ctx end
  local function setFlag(id, on)
    Flags.setFlag(Space.store, ctx(), id, on ~= false)
  end
  local function getFlag(id)
    return Flags.getFlag(Space.store, ctx(), id) and true or false
  end
  local function getVar(id)
    return Flags.getVar(Space.store, ctx(), id)
  end

  local function goTo(mapId, x, y, facing)
    Map.load(nil, game, mapId, { x = x, y = y, facing = facing or "up" })
    if game.session then
      game.session.x, game.session.y, game.session.facing = x, y, facing or "up"
    end
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing or "up"
    U.wait(90)
  end

  local function beamCells()
    local hit, n = {}, 0
    for y = 6, 7 do
      for x = 3, 7 do
        local o = Field.metatileOverrideAt and Field.metatileOverrideAt(GYM, x, y)
        if o then
          hit[x .. "," .. y] = o
          n = n + 1
        end
      end
    end
    return n, hit
  end

  local NativeTileset = require("src.core.game3.tileset_native")
  local function unpackedCells(x0, y0, x1, y1)
    local def = Map._def
    local layout = def and def.midLayout
    local pair = def and (def.pair or (layout and layout.pair))
    local missing = 0
    for y = y0, y1 do
      for x = x0, x1 do
        if not NativeTileset.hasMid(pair, layout:midAt(x, y)) then missing = missing + 1 end
      end
    end
    return missing
  end

  local function talkTo(x, y, facing, maxSteps)
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing
    U.wait(10)
    U.tap(game, "a")
    U.wait(30)
    local Message = package.loaded["src.ui.game3.message"]
    local saw = false
    local deadline = love.timer.getTime() + 8
    local steps = 0
    while love.timer.getTime() < deadline and steps < (maxSteps or math.huge) do
      steps = steps + 1
      local open = Message and Message.isOpen and Message.isOpen()
      local running = Space.vm and Space.vm:isRunning()
      if open or running then saw = true end
      if not open and not running then break end
      if open then U.tap(game, "a") end
      U.wait(12)
    end
    U.wait(20)
    return saw
  end

  setFlag(FLAG_BADGE01_GET)
  setFlag(FLAG_GOT_SS_TICKET)
  goTo(CITY, 12, 20, "down")
  U.shot(game, DIR .. "/vermilion_01_city.png")

  goTo(GYM, 5, 18, "up")
  local s1, s2 = getVar(VAR_TEMP_0), getVar(VAR_TEMP_1)
  print(string.format("[driver] switch cans = %s / %s", tostring(s1), tostring(s2)))
  result(s1 >= 1 and s1 <= 15, "ON_TRANSITION rolled switch can 1, got " .. tostring(s1))
  result(s2 >= 1 and s2 <= 15, "ON_TRANSITION rolled switch can 2, got " .. tostring(s2))
  result(s1 ~= s2, "the two switch cans are different cans")
  local beforeN = beamCells()
  result(beforeN == 0, "the beams are sealed on first entry, overrides=" .. beforeN)
  U.shot(game, DIR .. "/vermilion_02_beams_sealed.png")

  if s1 < 1 or s1 > 15 or s2 < 1 or s2 > 15 then
    print("[driver] no switch cans: special 347 never ran, the gym is unclearable")
    return finish()
  end

  local Collision = require("src.core.game3.collision")
  local sealedMid = Map._def.midLayout:midAt(5, 6)
  local cx, cy = canCell(s1)
  print(string.format("[driver] first switch can %d at (%d,%d)", s1, cx, cy))
  talkTo(cx, cy + 1, "up")
  result(getFlag(FLAG_TEMP_1), "FOUND_FIRST_SWITCH set after the first switch can")
  local halfN = beamCells()
  result(halfN == 10, "the first lock rewrote all 10 beam cells, got " .. halfN)
  result(Collision.canEnter(game, 5, 6, {}) == false, "one lock leaves the beam solid at (5,6)")

  -- pokefirered/data/maps/VermilionCity_Gym/scripts.inc:165
  local wrong = 1
  while wrong == s1 or wrong == getVar(VAR_TEMP_1) do wrong = wrong + 1 end
  cx, cy = canCell(wrong)
  print(string.format("[driver] wrong second can %d at (%d,%d)", wrong, cx, cy))
  talkTo(cx, cy + 1, "up")
  result(not getFlag(FLAG_TEMP_1), "a wrong second can cleared FOUND_FIRST_SWITCH")
  result(not getFlag(FLAG_FOUND_BOTH), "a wrong second can did not open the locks")
  result(Map._def.midLayout:midAt(5, 6) == sealedMid, "SetBeamsOn restored the full beam at (5,6)")
  result(Collision.canEnter(game, 5, 6, {}) == false, "the reset beam is solid at (5,6)")
  s1, s2 = getVar(VAR_TEMP_0), getVar(VAR_TEMP_1)
  result(s1 >= 1 and s1 <= 15 and s2 >= 1 and s2 <= 15 and s1 ~= s2,
    string.format("the cans were re-rolled, got %s / %s", tostring(s1), tostring(s2)))

  cx, cy = canCell(s1)
  print(string.format("[driver] re-rolled first switch can %d at (%d,%d)", s1, cx, cy))
  talkTo(cx, cy + 1, "up")
  result(getFlag(FLAG_TEMP_1), "FOUND_FIRST_SWITCH set again after the re-rolled first can")
  U.shot(game, DIR .. "/vermilion_03_first_switch.png")

  s2 = getVar(VAR_TEMP_1)
  cx, cy = canCell(s2)
  print(string.format("[driver] second switch can %d at (%d,%d)", s2, cx, cy))
  talkTo(cx, cy + 1, "up")
  result(getFlag(FLAG_FOUND_BOTH), "FLAG_FOUND_BOTH_VERMILION_GYM_SWITCHES set")
  local openN, open = beamCells()
  result(openN == 10, "the second lock rewrote all 10 beam cells, got " .. openN)
  result(open["5,6"] ~= nil and open["5,6"].impassable ~= true,
    "the middle beam cell (5,6) is walkable")
  result(open["5,7"] ~= nil and open["5,7"].impassable ~= true,
    "the middle beam cell (5,7) is walkable")
  result(open["5,6"] ~= nil and open["5,6"].impassable == false,
    "the open write superseded the solid half-on entry at (5,6)")
  local beamMissing = unpackedCells(3, 6, 7, 7)
  result(beamMissing == 0, "every off-beam metatile is in the native atlas, missing=" .. beamMissing)
  Player.cellX, Player.cellY = 5, 9
  Player.px, Player.py = 5 * 16, 9 * 16
  Player.targetX, Player.targetY = 5, 9
  Player.facing = "up"
  U.wait(20)
  U.shot(game, DIR .. "/vermilion_04_beams_open.png")

  for _, tid in ipairs({ 141, 220, 423 }) do
    Flags.setTrainerDefeated(Space.store, session, tid, true)
  end
  result(Collision.canEnter(game, 5, 7, {}) ~= false, "collision opens the beam gap at (5,7)")
  result(Collision.canEnter(game, 5, 6, {}) ~= false, "collision opens the beam gap at (5,6)")
  Player.cellX, Player.cellY = 5, 9
  Player.px, Player.py = 5 * 16, 9 * 16
  Player.targetX, Player.targetY = 5, 9
  Player.facing = "up"
  U.wait(20)
  for _ = 1, 10 do
    U.hold(game, "up", 24)
    U.wait(8)
    if Player.cellY <= 3 then break end
  end
  print(string.format("[driver] after walking north: (%d,%d)", Player.cellX, Player.cellY))
  result(Player.cellY <= 5,
    string.format("walked north past the beams, y=%d", Player.cellY))
  U.shot(game, DIR .. "/vermilion_05_past_beams.png")

  result(Player.cellY <= 3 and Player.cellX == 5, "standing in front of Lt. Surge at (5,3)")
  local spoke = talkTo(5, 3, "up", 60)
  local top = game.stack and game.stack:top()
  print("[driver] stack top after talking to Lt. Surge: " .. tostring(top and top.name or top))
  U.shot(game, DIR .. "/vermilion_06_lt_surge.png")
  result(spoke or getFlag(FLAG_DEFEATED_LT_SURGE),
    "Lt. Surge answers: his battle script ran")

  local ROUTE = "FR_ROUTE_1"
  goTo(ROUTE, 12, 20, "down")
  local leaked = 0
  for y = 6, 7 do
    for x = 3, 7 do
      local ok, why = Collision.canEnter(game, x, y, {})
      if not ok and why == "tile" and Collision.isWalkable(x, y) then leaked = leaked + 1 end
    end
  end
  result(leaked == 0, "the gym's beam cells do not block Route 1, leaked=" .. leaked)
  result(beamCells() == 0, "leaving the gym dropped its script-written cells")

  -- pokefirered/src/fieldmap.c:93
  goTo(CITY, 12, 20, "down")
  U.wait(30)
  goTo(GYM, 5, 18, "up")
  local reN, re = beamCells()
  result(reN == 10, "ON_LOAD re-applied the beams-off metatiles on re-entry, got " .. reN)
  result(re["5,6"] ~= nil and re["5,6"].impassable ~= true,
    "the middle beam cell (5,6) is still walkable after re-entry")
  result(getFlag(FLAG_FOUND_BOTH), "the both-switches flag survived the round trip")
  U.shot(game, DIR .. "/vermilion_07_reentry_open.png")

  Player.cellX, Player.cellY = 5, 9
  Player.px, Player.py = 5 * 16, 9 * 16
  Player.targetX, Player.targetY = 5, 9
  Player.facing = "up"
  U.wait(20)
  for _ = 1, 10 do
    U.hold(game, "up", 24)
    U.wait(8)
    if Player.cellY <= 3 then break end
  end
  result(Player.cellY <= 5,
    string.format("still walkable north after re-entry, y=%d", Player.cellY))
  U.shot(game, DIR .. "/vermilion_08_reentry_walk.png")

  -- pokefirered/data/maps/PokemonMansion_1F/scripts.inc:6
  local MANSION = "FR_POKEMON_MANSION_1F"
  local FLAG_POKEMON_MANSION_SWITCH_STATE = 0x26C
  goTo(MANSION, 5, 6, "up")
  local restMid = Map._def.midLayout:midAt(5, 4)
  goTo(CITY, 12, 20, "down")
  setFlag(FLAG_POKEMON_MANSION_SWITCH_STATE)
  goTo(MANSION, 5, 6, "up")
  result(Map._def.midLayout:midAt(5, 4) ~= restMid, "ON_LOAD swapped the Mansion statue at (5,4)")
  local statueMissing = unpackedCells(0, 0, Map._def.midLayout.width - 1, Map._def.midLayout.height - 1)
  result(statueMissing == 0,
    "every Mansion 1F metatile, script-placed ones included, is in the native atlas, missing=" .. statueMissing)
  U.shot(game, DIR .. "/vermilion_09_mansion_statue.png")

  finish()
end
