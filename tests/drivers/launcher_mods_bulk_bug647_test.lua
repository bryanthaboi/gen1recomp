-- Manual check for the launcher's Enable all / Disable all chips (#647).
-- POKEPORT_DRIVER skips the launcher (main.lua boots straight into the game),
-- so this stands a second launcher up on the MODS tab and hands the mouse over.
-- No pokered cite applies: this is launcher chrome, nothing in the ROM-side
-- game is involved, and there is no map position to derive.
--   POKEPORT_DRIVER=tests/drivers/launcher_mods_bulk_bug647_test.lua POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .
-- Do not set POKEPORT_SPEED: it multiplies the act+step loop per rendered
-- frame, so the driver would run several steps between two launcher draws and
-- read rects from a frame that was never on screen (and it desyncs audio too).
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local RomImporter = require("src.import.RomImporter")
  local LauncherMods = require("src.mods.LauncherMods")
  local SaveData = require("src.core.SaveData")

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- Left-click the middle of a launcher rect.  The button argument is load
  -- bearing: the confirm modal's dispatch returns early on anything but 1.
  local function click(importer, r)
    importer:mousepressed(r.x + r.width / 2, r.y + r.height / 2, 1)
  end

  -- ---- preconditions, before anything is drawn or written

  check("LauncherMods.setAllEnabled is the one-write bulk path",
        type(LauncherMods.setAllEnabled) == "function")
  check("RomImporter:_setAllMods exists for the chips to call",
        type(RomImporter._setAllMods) == "function")
  check("a window is up to draw the launcher into",
        love.window and love.window.isOpen and love.window.isOpen()
        and love.graphics.getWidth() > 0)

  -- The panel reads the same options.mods the loader writes, so a read-only or
  -- quarantined options file would make every click look like it did nothing.
  local options = SaveData.loadOptions()
  local savedMods = {}
  for id, v in pairs(options.mods or {}) do savedMods[id] = v end
  check("options.lua round-trips (the chips persist through it)",
        SaveData.saveOptions(options) ~= nil)

  local mods = LauncherMods.list()
  check("at least two mods are installed to act on (found "
          .. #mods .. ")", #mods >= 2)
  if #mods < 2 then
    U.log("mods/ in the save dir (or the repo's mods/ on a source run) is what")
    U.log("gets scanned one level deep; drop two mod folders there and rerun.")
  end
  local names = {}
  for _, m in ipairs(mods) do names[#names + 1] = m.id end
  U.log("installed mods:", table.concat(names, ", "))

  -- The experimental confirm is half of what #647 has to get right, and none of
  -- the bundled example mods are flagged, so plant one rather than let that
  -- branch go unseen.  Manifest.validate is pure (no filesystem), but the real
  -- loader wants the entry chunk to exist if the human later presses Play.
  local SEED = "driver_experimental_647"
  local seeded = false
  local haveExperimental = false
  for _, m in ipairs(mods) do
    if m.experimental then haveExperimental = true end
  end
  if not haveExperimental then
    love.filesystem.createDirectory("mods")
    love.filesystem.createDirectory("mods/" .. SEED)
    local manifest = ([[{
  "id": "%s",
  "name": "Driver Experimental Mod",
  "version": "1.0.0",
  "entry": "main.lua",
  "experimental": true,
  "description": "Planted by the #647 driver so the Enable all confirm has something to warn about."
}
]]):format(SEED)
    local okM = love.filesystem.write("mods/" .. SEED .. "/manifest.json", manifest)
    love.filesystem.write("mods/" .. SEED .. "/main.lua", "return {}\n")
    seeded = okM and true or false
    check("planted an experimental mod so the confirm can fire", seeded)
    U.log("it lives in " .. love.filesystem.getSaveDirectory() .. "/mods/" .. SEED)
    U.log("remove it with: rm -rf '" .. love.filesystem.getSaveDirectory()
          .. "/mods/" .. SEED .. "'")
    mods = LauncherMods.list()
  end

  -- ---- stand the launcher up and take the callbacks off main.lua

  local co = coroutine.running()
  local CALLBACKS = {
    "update", "draw", "mousepressed", "mousereleased", "mousemoved",
    "keypressed", "keyreleased", "textinput", "wheelmoved", "filedropped",
    "focus",
  }
  local prev = {}
  for _, name in ipairs(CALLBACKS) do prev[name] = love[name] end
  local function restoreHost()
    for name, fn in pairs(prev) do love[name] = fn end
  end

  -- Play hands back to the game main.lua already booted (POKEPORT_VERSION), not
  -- to whichever column was clicked: the driver cannot reach main.lua's local
  -- bootGame, and only one cache is mounted.
  local importer = RomImporter.new(function()
    restoreHost()
    U.log("launcher closed, the already-booted game takes the window back")
  end, { launcher = true })
  importer.tab = "mods"

  love.update = function(dt)
    importer:update(dt)
    if coroutine.status(co) == "suspended" then
      local ok, err = coroutine.resume(co, game)
      if not ok then print("driver error: " .. tostring(err)) end
    end
  end
  love.draw = function() importer:draw() end
  love.mousepressed = function(x, y, button) importer:mousepressed(x, y, button) end
  love.mousereleased = function() end
  love.mousemoved = function() end
  love.keypressed = function(key) importer:keypressed(key) end
  love.keyreleased = function() end
  love.textinput = function(text) importer:textinput(text) end
  -- RomImporter.new already chained the previous handler onto love.wheelmoved;
  -- point it straight at the launcher so a scroll cannot also reach the game.
  love.wheelmoved = function(dx, dy) importer:wheelmoved(dx, dy) end
  love.filedropped = function(file) importer:filedropped(file) end
  love.focus = function(f) importer:focus(f) end

  -- rects are built inside draw(), so every read below needs a rendered frame
  -- between the change and the check
  U.wait(3)

  local ena, dis = importer.modEnableAllRect, importer.modDisableAllRect
  local imp = importer.modImportRect
  check("Enable all / Disable all have rects on the MODS tab",
        ena ~= nil and dis ~= nil)
  if ena and dis and imp then
    check("both sit left of Import mod .zip",
          ena.x + ena.width <= imp.x and dis.x + dis.width <= imp.x)
    check("Enable all is left of Disable all and they do not overlap",
          ena.x + ena.width <= dis.x)
    check("they are on the header row, centred against the import button",
          math.abs((ena.y + ena.height / 2) - (imp.y + imp.height / 2)) <= 2)
  end

  -- Disable all: one write, count to zero, and a notice that names the number.
  if dis then
    click(importer, dis)
    U.wait(2)
    local after = LauncherMods.list()
    local on = 0
    for _, m in ipairs(after) do if m.enabled then on = on + 1 end end
    check("Disable all switched every mod off", on == 0)
    check("the notice counts what it did (" ..
            tostring(importer.modNotice and importer.modNotice.text) .. ")",
          importer.modNotice ~= nil
          and importer.modNotice.text:match("^Disabled %d+ mods%.$") ~= nil)
  end

  -- Enable all with an experimental mod in the list must stop at the confirm,
  -- and Cancel must leave the list exactly as it was.
  if ena then
    click(importer, ena)
    U.wait(2)
    local c = importer._modConfirm
    check("Enable all armed the experimental confirm instead of enabling",
          c ~= nil and c.kind == "enableAll")
    local stillOff = 0
    for _, m in ipairs(LauncherMods.list()) do
      if not m.enabled then stillOff = stillOff + 1 end
    end
    check("nothing was enabled while the confirm is up",
          stillOff == #LauncherMods.list())
    if c and importer._modConfirmNo then
      click(importer, importer._modConfirmNo)
      U.wait(2)
      local on = 0
      for _, m in ipairs(LauncherMods.list()) do if m.enabled then on = on + 1 end end
      check("Cancel closed the confirm and left the list untouched",
            importer._modConfirm == nil and on == 0)
    end
  end

  -- #433 shape: a rect that outlives its panel stays clickable over the next
  -- tab.  _resetFrameRects has to nil both chips every frame.
  importer.tab = "red"
  U.wait(3)
  check("switching to the RED tab drops both chip rects",
        importer.modEnableAllRect == nil and importer.modDisableAllRect == nil)
  importer.tab = "mods"
  U.wait(3)

  -- Narrow column: the chips are dropped, never squeezed onto the count.
  local ww, wh, flags = love.window.getMode()
  love.window.setMode(480, wh, flags)
  U.wait(4)
  check("at minimum window width the chips vanish rather than overlap the count",
        importer.modEnableAllRect == nil and importer.modDisableAllRect == nil)
  love.window.setMode(ww, wh, flags)
  U.wait(4)
  check("the chips come back when the window is wide again",
        importer.modEnableAllRect ~= nil and importer.modDisableAllRect ~= nil)

  -- put the enable-state back the way the human found it
  local restore = SaveData.loadOptions()
  restore.mods = savedMods
  SaveData.saveOptions(restore)
  importer:_refreshMods()
  importer.modNotice = nil
  U.wait(2)

  U.log("The MODS tab is up with the enable-state back as you left it. Enable all")
  U.log("and Disable all are the two chips immediately left of Import mod .zip;")
  U.log("clicking one should flip every switch at once, move the \"N of M enabled\"")
  U.log("count, and print \"Disabled N mods.\" underneath, with Enable all stopping")
  U.log("at an Experimental mods confirm first. Watch for the chips crowding or")
  U.log("overlapping that count as you drag the window narrower (they should just")
  U.log("disappear), and for a click on empty space in the RED tab, where the chips")
  U.log("used to be, doing something anyway. Quit and rerun to check it persisted.")

  while true do
    coroutine.yield()
  end
end
