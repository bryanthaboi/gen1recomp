local U = require("tests.drivers.util")
return function(game)
  local failures = 0
  local function check(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then failures = failures + 1 end
    return ok
  end
  local function finish()
    print("RESULT 2764 failures=" .. failures)
    love.event.quit(failures == 0 and 0 or 1)
  end
  for _ = 1, 600 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not check(game.phase == "boot", "2764 boot ready") then return finish() end
  game:_handleBootAction({ action = "new_game", name = "TIMING" })
  U.wait(180)
  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Objects = require("src.core.game3.objects")
  local Space = require("src.core.game3.scripting.space")
  local Field = require("src.core.game3.field")
  local Message = require("src.ui.game3.message")
  local shots = os.getenv("POKEPORT_SHOT_DIR")
  require("src.core.game3.encounters").onStep = function() return nil end
  require("src.core.game3.trainer_sight").check = function() return false end
  local function enter(mapId, x, y)
    if Space.vm and Space.vm:isRunning() then Space.vm:halt(false) end
    Message.reset()
    Map.load(Runtime._mod, game, mapId, { x = x, y = y, facing = "left" })
    U.wait(90)
    if Space.vm and Space.vm:isRunning() then Space.vm:halt(false) end
    Message.reset()
    Player.reset(x, y, "left")
    Field.locked = true
  end
  local function shot(name)
    return shots and U.still(game, shots .. "/" .. name)
  end
  enter("EM_ROUTE119_WEATHER_INSTITUTE_2F", 5, 6)
  local grunt, scientist = assert(Objects.find(7)), assert(Objects.find(5))
  scientist.cellX, scientist.cellY, scientist.px, scientist.py = 1, 6, 16, 96
  check(Space.vm:start("g3:0826ffc8"), "2764 cached Shelly continuation starts")
  local shove, contact, dialogue = false, false, false
  for _ = 1, 1800 do
    grunt, scientist = assert(Objects.find(7)), assert(Objects.find(5))
    if not shove and Player.cellY == 5 and grunt.moving then
      shove = check(true, "2764 Weather north shove precedes grunt completion")
      check(shot("2764_01_weather_north_shove.png"), "2764 Weather shove frame captured")
    end
    if not contact and grunt.cellX == 5 then
      contact = true
      check(Player.cellY == 5, "2764 Weather player vacates grunt destination")
    end
    if scientist.cellX == 4 and not scientist.moving and Message.isOpen() then
      dialogue = true
      check(Player.cellX == 5 and Player.cellY == 6 and scientist.cellY == 6,
        "2764 Weather dialogue player5,6 scientist4,6")
      if Message.isTyping() then Message.skipReveal() end
      check(shot("2764_02_weather_dialogue_positions.png"), "2764 Weather dialogue frame captured")
      break
    end
    if Message.isTyping() then Message.skipReveal() end
    if Message.isWaiting() then U.tap(game, "a") end
    U.wait(1)
  end
  check(shove and contact and dialogue, "2764 Weather cached continuation reaches dialogue")
  enter("EM_SLATEPORT_CITY_OCEANIC_MUSEUM_2F", 12, 6)
  Objects.addObject(2)
  Objects.addObject(4)
  local archie, other = assert(Objects.find(2)), assert(Objects.find(4))
  other.cellX, other.cellY, other.px, other.py = 10, 6, 160, 96
  archie.hidden, other.hidden = false, false
  local tail
  for _, rows in pairs(Space.bundle.scripts) do
    if type(rows) == "table" then
      for i, row in ipairs(rows) do
        if row.op == "applymovement" and row[1] == 2 and row[2] == "g3:0820bcd8" then
          tail = {}
          for j = i, #rows do tail[#tail + 1] = rows[j] end
          break
        end
      end
    end
    if tail then break end
  end
  if not check(tail ~= nil, "2764 Museum cached Archie arrival found") then return finish() end
  Space.vm.scripts["2764_museum_tail"] = tail
  check(Space.vm:start("2764_museum_tail"), "2764 Museum cached continuation starts")
  local vacates, arrived = false, false
  for _ = 1, 600 do
    if not vacates and archie.moving and other.moving and other.py > 96 then
      vacates = check(true, "2764 Museum grunt vacates during Archie approach")
      check(shot("2764_03_museum_grunt_shove.png"), "2764 Museum shove frame captured")
    end
    if archie.cellX == 10 and archie.cellY == 6 and not archie.moving and Message.isOpen() then
      arrived = true
      check(other.cellX == 10 and other.cellY == 7, "2764 Museum grunt destination10,7")
      check(Player.cellX == 12 and Player.cellY == 6, "2764 Museum player remains12,6")
      if Message.isTyping() then Message.skipReveal() end
      check(shot("2764_04_museum_dialogue_positions.png"), "2764 Museum dialogue frame captured")
      break
    end
    U.wait(1)
  end
  check(vacates and arrived, "2764 Museum cached continuation reaches dialogue")
  finish()
end
