-- Manual check that EXIT GAME actually ends the process (#339): the two
-- background workers are now told to quit from love.quit and Android exits
-- outright, so the app reopens without swiping it out of Recents.
-- Port lifecycle only, no pokered analogue (the GB has no process).
--   POKEPORT_DRIVER=tests/drivers/quit_process_bug339_test.lua POKEPORT_IDENTITY=bug339 POKEPORT_TOUCH=0 love .
-- Do not set POKEPORT_SPEED: fast-forward desynchronizes the title music.
return function(game)
  local U = dofile("tests/drivers/util.lua")

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- No map setup: the quit path is the title's EXIT GAME row
  -- (src/ui/TitleState.lua:368), reachable straight from boot.  The START
  -- menu QUIT is not a process quit, it power-cycles to the title
  -- (src/core/Game.lua:165), so it cannot verify this.
  U.wait(5)
  U.tap(game, "start") -- past the copyright splash / attract movie
  U.wait(30)

  local title = game.stack:top()
  check("the title screen is on top",
        title ~= nil and title.screenId == "TitleState")

  -- love.quit reaches both workers through package.loaded, so what matters is
  -- that the module this session loaded is the one carrying shutdown
  local chip = package.loaded["src.core.ChipAudio"]
  check("ChipAudio is loaded in this session", chip ~= nil)
  check("ChipAudio.shutdown exists",
        chip ~= nil and type(chip.shutdown) == "function")
  check("love.thread is available, so the chip worker is the live one",
        love.thread ~= nil and love.thread.newThread ~= nil)

  -- src/update/Check's worker is started by the launcher
  -- (src/import/RomImporter.lua:594), not by a driver run
  local upd = package.loaded["src.update.Check"]
  if upd then
    check("Check.shutdown exists", type(upd.shutdown) == "function")
  else
    local ok, mod = pcall(require, "src.update.Check")
    check("Check.shutdown exists (module not started this run)",
          ok and type(mod.shutdown) == "function")
  end

  check("love.event.quit is reachable",
        love.event ~= nil and love.event.quit ~= nil)

  local opts = game.save.options
  if (opts and opts.sfxVol or 0) == 0 then
    U.log("WARNING sfx volume is 0: the menu presses will make no sound.")
  end
  if (opts and opts.musicVol or 0) == 0 then
    U.log("WARNING music volume is 0: with the title theme silent the chip")
    U.log("worker may never have started, which is the thread this fix joins.")
  end

  -- park the cursor on EXIT GAME and stop there; pressing it is the human's
  -- job, since the press ends the process
  U.tap(game, "a")
  U.wait(20)
  local menu = game.stack:top()
  local wanted, labels = nil, {}
  for i, item in ipairs(menu and menu.items or {}) do
    labels[#labels + 1] = tostring(item.label)
    if tostring(item.label):find("EXIT", 1, true) then wanted = i end
  end
  check("the title menu is open", menu ~= nil and menu.items ~= nil)
  check("it has an EXIT GAME row", wanted ~= nil)
  U.log("menu rows:", table.concat(labels, ", "))

  if wanted then
    for _ = 1, #menu.items do
      if menu.index == wanted then break end
      U.tap(game, "down")
      U.wait(6)
    end
    check("the cursor is parked on EXIT GAME", menu.index == wanted)
  end

  U.log("The cursor sits on EXIT GAME; press A and the window should close.")
  U.log("A few seconds later `pgrep -fl love` must print nothing at all: before")
  U.log("this fix a headless love process stayed resident burning a core.")
  U.log("On Android, reopening from the launcher without swiping the app out of")
  U.log("Recents should cold boot normally instead of flashing black.")

  while true do
    coroutine.yield()
  end
end
