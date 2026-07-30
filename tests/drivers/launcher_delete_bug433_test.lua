-- Manual check of the launcher's Delete labels (#433): a stale hit rect let a
-- click on the Mods tab delete a save slot, and Delete never asked first.
-- No pokered counterpart: src/import/RomImporter.lua is this port's own desktop
-- launcher, so hit-rect coords here come from the panel that draws them.
--   POKEPORT_DRIVER=tests/drivers/launcher_delete_bug433_test.lua POKEPORT_IDENTITY=bug433 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .
-- Leave POKEPORT_SPEED unset: this one is clicked by hand, at real time.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local RomImporter = require("src.import.RomImporter")
  local SaveData = require("src.core.SaveData")
  local GameVersion = require("src.core.GameVersion")

  local version = GameVersion.get()

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- A driver run boots straight past the launcher (main.lua: POKEPORT_DRIVER is
  -- a scripted run), so bring a real interactive launcher up ourselves and take
  -- over the frame + click handlers the launcher normally owns.
  local imp = RomImporter.new(function() end, { launcher = true })
  imp.play = function() U.log("Play is inert here: the game is already booted.") end

  local prevDraw, prevPressed = love.draw, love.mousepressed
  local prevKey, prevText = love.keypressed, love.textinput
  love.draw = function()
    imp:update(love.timer.getDelta())
    imp:draw()
  end
  love.mousepressed = function(x, y, button) imp:mousepressed(x, y, button or 1) end
  love.keypressed = function(key) imp:keypressed(key) end
  love.textinput = function(t) imp:textinput(t) end
  local function restore()
    love.draw, love.mousepressed = prevDraw, prevPressed
    love.keypressed, love.textinput = prevKey, prevText
  end

  local function slotCount()
    return #(SaveData.listSlots(version) or {})
  end

  -- Two throwaway rows to click on, in this identity's save dir only.
  while slotCount() < 2 do imp:_newSlot(version) end
  imp.tab = version
  imp.pageScroll = 0
  U.wait(4)

  -- The Delete rects exist only after the panel that owns them has drawn.
  local del = (imp.slotDeleteRects or {})[1]
  if not check("the save panel drew a Delete rect for a slot row", del ~= nil) then
    U.log("Nothing to click: the", version, "tab drew no slot rows.")
    restore()
    while true do coroutine.yield() end
  end
  local spot = { x = del.x + del.width / 2, y = del.y + del.height / 2, id = del.id }
  U.log(("Delete for %s sits at (%d, %d)."):format(spot.id, spot.x, spot.y))

  imp.tab = "mods"
  U.wait(4)
  check("a Mods frame leaves no save Delete rect live",
    imp.slotDeleteRects == nil)
  local before = slotCount()
  imp:mousepressed(spot.x, spot.y, 1)
  U.wait(4)
  check("the reporter's click on that spot from Mods deletes nothing",
    slotCount() == before and imp._confirmDelete == nil)

  imp.tab = version
  U.wait(4)
  imp:mousepressed(spot.x, spot.y, 1)
  U.wait(2)
  check("one click on Delete arms instead of deleting",
    slotCount() == before and imp._confirmDelete ~= nil
      and imp._confirmDelete.id == spot.id)
  imp:mousepressed(4, 4, 1)   -- a press anywhere else
  U.wait(2)
  check("a press elsewhere takes the arm back off", imp._confirmDelete == nil)
  check("the slot survived the whole sequence", slotCount() == before)

  U.log("The launcher on screen is live; the", version, "tab is up, disarmed.")
  U.log("Clicking Delete once should turn that label red and read \"Sure?\"")
  U.log("without the row moving, and go back to \"Delete\" after ~4 seconds or")
  U.log("on any other click.  A second click on \"Sure?\" removes the slot.")

  while true do
    coroutine.yield()
  end
end
