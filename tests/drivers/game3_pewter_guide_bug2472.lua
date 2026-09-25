local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/bug2472"

local PEWTER = "FR_PEWTER_CITY"
local GYM_GUIDE, GYM_X, GYM_Y = 5, 42, 20
local MUSEUM_GUIDE, MUSEUM_X, MUSEUM_Y = 2, 33, 17

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS game3_pewter_guide_bug2472")
    love.event.quit(0)
  else
    print("FAIL game3_pewter_guide_bug2472 failures=" .. failures)
    love.event.quit(1)
  end
end

return function(game)
  for _ = 1, 600 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(180)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Space = require("src.core.game3.scripting.space")
  local Party = require("src.core.game3.party")
  local Objects = require("src.core.game3.objects")
  local Player = require("src.core.game3.player")
  local Field = require("src.core.game3.field")
  local Message = package.loaded["src.ui.game3.message"] or require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the field") then return finish() end
  session.party = {}
  Party.giveMon(session, 4, 12)

  local function vmBusy()
    return Space.vm and Space.vm.isRunning and Space.vm:isRunning()
  end
  local function msgOpen()
    return Message.isOpen and Message.isOpen()
  end

  Map.load(nil, game, PEWTER, { x = GYM_X - 1, y = GYM_Y, facing = "right" })
  game.session.x, game.session.y, game.session.facing = GYM_X - 1, GYM_Y, "right"
  U.wait(30)

  local bounds = Objects._bounds
  if not result(bounds and bounds.w > 0 and bounds.h > 0, "Pewter layout bounds known") then return finish() end
  local function inBounds(x, y)
    return x >= 0 and y >= 0 and x < bounds.w and y < bounds.h
  end

  local function escort(lid, label, answerNo)
    local worst, lastPage
    local started = false
    for _ = 1, 3000 do
      local eo = Objects.find(lid)
      if eo and not eo.hidden and not inBounds(eo.cellX, eo.cellY) then
        worst = worst or string.format("guide (%d,%d)", eo.cellX, eo.cellY)
      end
      if not inBounds(Player.cellX, Player.cellY) then
        worst = worst or string.format("player (%d,%d)", Player.cellX, Player.cellY)
      end
      if vmBusy() or Field.locked then started = true end
      if started and not vmBusy() and not msgOpen() and not Field.locked then break end
      if Choice.isOpen and Choice.isOpen() then
        print("[2472] yes/no open, answering " .. (answerNo and "NO" or "YES"))
        if answerNo then Choice.cursor = 2 end
        U.tap(game, "a")
      elseif msgOpen() then
        local page = Message.currentPage and Message.currentPage()
        if page and page ~= lastPage then
          print("[2472] " .. label .. " text: " .. tostring(page):gsub("\n", " "))
          lastPage = page
        end
        if answerNo and tostring(page):find("MUSEUM?", 1, true) then
          for _ = 1, 120 do
            if Choice.isOpen() then break end
            U.wait(1)
          end
        end
        if not Choice.isOpen() then U.tap(game, "a") end
      end
      U.wait(2)
    end
    result(started, label .. ": script ran")
    result(not vmBusy() and not Field.locked, label .. ": script finished and field unlocked")
    result(worst == nil, label .. ": guide and player stayed inside the map" .. (worst and (" (left at " .. worst .. ")") or ""))
    return Player.cellX, Player.cellY
  end

  local function atTemplate(lid, x, y, label, before, face)
    local eo = Objects.find(lid)
    result(eo ~= nil and eo.visible and not eo.hidden, label .. ": guide visible again")
    result(eo ~= nil and eo.cellX == x and eo.cellY == y,
      string.format("%s: guide back on template (%d,%d), got (%s,%s)", label, x, y,
        tostring(eo and eo.cellX), tostring(eo and eo.cellY)))
    if face then
      result(eo ~= nil and eo.facing == face, label .. ": template facing " .. face .. ", got " .. tostring(eo and eo.facing))
    end
    result(eo ~= before, label .. ": guide is a respawned object")
    return eo
  end

  local guide = Objects.find(GYM_GUIDE)
  if not result(guide ~= nil and guide.cellX == GYM_X and guide.cellY == GYM_Y and not guide.hidden,
    "gym guide spawned at (42,20)") then return finish() end
  U.still(game, DIR .. "/2472_01_gym_guide_at_spawn.png")

  U.tap(game, "a")
  local px1, py1 = escort(GYM_GUIDE, "gym escort 1", false)
  print(string.format("[2472] escort 1 left the player at (%d,%d)", px1, py1))
  result(px1 < 20, "gym escort 1 brought the player to the gym side of town")
  local after = Objects.find(GYM_GUIDE)
  result(not (after and not after.hidden and after.cellX == 7 and after.cellY == 19),
    "no stale gym guide left standing at the exit cell (7,19)")
  U.still(game, DIR .. "/2472_02_gym_escort_done_guide_gone.png")
  guide = atTemplate(GYM_GUIDE, GYM_X, GYM_Y, "gym guide", guide, "down")

  Player.reset(GYM_X - 1, GYM_Y, "right")
  U.wait(20)
  U.still(game, DIR .. "/2472_03_gym_guide_back_at_spawn.png")
  U.tap(game, "a")
  local px2, py2 = escort(GYM_GUIDE, "gym escort 2", false)
  result(px2 == px1 and py2 == py1,
    string.format("gym escort 2 ends where escort 1 did (%d,%d vs %d,%d)", px2, py2, px1, py1))
  atTemplate(GYM_GUIDE, GYM_X, GYM_Y, "gym guide after replay", guide, "down")

  Player.reset(MUSEUM_X, MUSEUM_Y + 1, "up")
  U.wait(20)
  local museum = Objects.find(MUSEUM_GUIDE)
  if not result(museum ~= nil and museum.cellX == MUSEUM_X and museum.cellY == MUSEUM_Y and not museum.hidden,
    "museum guide spawned at (33,17)") then return finish() end
  U.tap(game, "a")
  local mx1, my1 = escort(MUSEUM_GUIDE, "museum escort 1", true)
  print(string.format("[2472] museum escort 1 left the player at (%d,%d)", mx1, my1))
  result(mx1 ~= MUSEUM_X or my1 ~= MUSEUM_Y + 1, "museum escort 1 moved the player")
  museum = atTemplate(MUSEUM_GUIDE, MUSEUM_X, MUSEUM_Y, "museum guide", museum, nil)
  U.still(game, DIR .. "/2472_04_museum_escort_done.png")

  Player.reset(MUSEUM_X, MUSEUM_Y + 1, "up")
  U.wait(20)
  local m = Objects.find(MUSEUM_GUIDE)
  if m then m.facing = "down" end
  U.tap(game, "a")
  local mx2, my2 = escort(MUSEUM_GUIDE, "museum escort 2", true)
  result(mx2 == mx1 and my2 == my1,
    string.format("museum escort 2 ends where escort 1 did (%d,%d vs %d,%d)", mx2, my2, mx1, my1))
  atTemplate(MUSEUM_GUIDE, MUSEUM_X, MUSEUM_Y, "museum guide after replay", museum, nil)

  return finish()
end
