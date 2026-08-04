-- Manual check that launcher actions no longer flash console windows (#606).
-- src/core/HostShell.lua claims one hidden console at boot so every curl /
-- PowerShell child inherits it instead of allocating (and showing) its own.
-- No pokered counterpart: this is desktop launcher plumbing, so the standing
-- spot below is only to give the window something to be (pokered
-- data/maps/objects/PalletTown.asm: (10, 8) is clear of the three
-- object_events and the three warps).
--   POKEPORT_DRIVER=tests/drivers/host_console_bug606_test.lua POKEPORT_IDENTITY=bug606 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .
-- Leave POKEPORT_SPEED unset: fast-forward desyncs audio and logic ordering,
-- and it would also step this driver several times per rendered frame while a
-- blocking fetch is in flight.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local HostShell = require("src.core.HostShell")
  local RomImporter = require("src.import.RomImporter")

  local isWin = love.system.getOS() == "Windows"
  local passed, failed = 0, 0
  local report = {}

  -- On Windows the packaged game is love.exe, which has no console, so print()
  -- goes nowhere a reporter can read -- exactly the platform this bug lives on.
  -- Mirror every line into the save dir and put the count on screen so the
  -- PASS/FAIL block is still legible there.
  local REPORT = "bug606_report.txt"
  pcall(love.filesystem.write, REPORT, "")
  local function say(...)
    U.log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    local line = table.concat(parts, " ")
    report[#report + 1] = line
    pcall(love.filesystem.append, REPORT, line .. "\n")
  end

  local function check(label, ok)
    if ok then passed = passed + 1 else failed = failed + 1 end
    say(ok and "PASS" or "FAIL", label)
    return ok
  end

  local function fileHas(path, needle)
    local ok, body = pcall(love.filesystem.read, path)
    return ok and type(body) == "string" and body:find(needle, 1, true) ~= nil
  end

  check("HostShell exposes hideHostConsole", type(HostShell.hideHostConsole) == "function")

  -- Wiring: an unwired helper fixes nothing, and it has to run before the
  -- self-updater boot shell, which is the first thing that can shell out.
  local okMain, mainSrc = pcall(love.filesystem.read, "main.lua")
  local atCall = okMain and type(mainSrc) == "string"
    and mainSrc:find("hideHostConsole", 1, true) or nil
  local atBoot = okMain and type(mainSrc) == "string"
    and mainSrc:find("Boot.run", 1, true) or nil
  check("love.load claims the console before anything shells out",
        atCall ~= nil and atBoot ~= nil and atCall < atBoot)

  local hid = HostShell.hideHostConsole()
  check("calling it twice answers the same (memoized, so no second console)",
        HostShell.hideHostConsole() == hid)
  if not isWin then
    check("no console is allocated off Windows", hid == false)
  end
  say("host:", love.system.getOS(), "-- console claimed:", tostring(hid),
      "-- POKEPORT_CONSOLE:", tostring(os.getenv("POKEPORT_CONSOLE")))

  -- The ROM picker answers by writing the chosen path to stdout and letting
  -- commandOutput read it back through HostShell.popen; if that write ever
  -- breaks the launcher just silently refuses every ROM, which is the second
  -- way this fix can go wrong.
  check("the Windows ROM picker still writes its pick to stdout",
        fileHas("src/import/RomImporter.lua", "[Console]::Write($d.FileName)"))

  local okFfi, ffi = pcall(require, "ffi")
  if isWin and okFfi then
    -- HostShell already declared GetConsoleWindow if it got that far; a repeat
    -- cdef raises, so each one gets its own pcall.
    pcall(ffi.cdef, "void *GetConsoleWindow(void);")
    pcall(ffi.cdef, "int IsWindowVisible(void *hWnd);")
    local okCall, hwnd = pcall(function() return ffi.C.GetConsoleWindow() end)
    if hid then
      check("the process owns a console for its children to inherit",
            okCall and hwnd ~= nil)
      -- The near-miss: AllocConsole worked but ShowWindow did not resolve, so
      -- the console exists and sits on screen for the whole session.
      local okVis, visible = pcall(function() return ffi.C.IsWindowVisible(hwnd) end)
      check("and that console window is hidden", okVis and visible == 0)
    else
      say("This run did not claim a console: either POKEPORT_CONSOLE=1 is set,")
      say("or it was started from a terminal (lovec.exe, what scripts\\run.ps1")
      say("prefers), which already had one. Re-run under love.exe to judge #606.")
    end
  end

  -- Fire the three host tools the launcher actually spawns, through the same
  -- funnel they use (src/core/HostShell.lua:popen).  Each of these was one
  -- console flash before the fix.
  local probes = isWin and {
    { "curl, the update and mod-index fetch", "curl --version", "curl" },
    { "powershell, the ROM and mod pickers",
      'powershell -NoProfile -Command "[Console]::Write(\'pokeport-ok\')"', "pokeport-ok" },
    { "cmd, the update downloader's start /b", "cmd /c echo pokeport-ok", "pokeport-ok" },
  } or {
    { "curl, the update and mod-index fetch", "curl --version", "curl" },
    { "the shell the pickers run under", "echo pokeport-ok", "pokeport-ok" },
  }

  local function runProbes(quiet)
    for _, p in ipairs(probes) do
      local out
      local pipe = HostShell.popen(p[2])
      if pipe then
        out = pipe:read("*a")
        pipe:close()
      end
      local ok = type(out) == "string" and out:find(p[3], 1, true) ~= nil
      if quiet then
        say(ok and "PASS" or "FAIL", p[1] .. " still answers")
      else
        check(p[1] .. " still answers", ok)
      end
      U.wait(20) -- space them out so a flash is countable by eye
    end
  end
  runProbes(false)

  -- The launcher's boot release check is skipped under POKEPORT_DRIVER
  -- (RomImporter's updaterAllowed), so start it by hand: it is a love.thread
  -- whose curl calls popped their own consoles too, and the hidden one is
  -- process-wide, so the thread is covered without touching check_worker.lua.
  local okCheck, Check = pcall(require, "src.update.Check")
  if okCheck and Check then
    pcall(Check.start)
    for _ = 1, 240 do
      local st = Check.state()
      if st.status ~= "checking" then break end
      U.wait(1)
    end
    local st = Check.state()
    check("the update check ran and reached a verdict",
          st.status ~= "checking" and st.status ~= "idle")
    say("update check says:", st.status, st.error and ("(" .. tostring(st.error) .. ")") or "")
  end

  -- Prove the window is rendering before the launcher takes the frame over.
  local MAP, STAND = "PALLET_TOWN", { x = 10, y = 8, facing = "down" }
  U.teleport(game, MAP, STAND.x, STAND.y, STAND.facing)
  U.wait(10)
  local ow = game.overworld
  if ow and ow.map and not ow.map:isWalkableCell(STAND.x, STAND.y) then
    -- a map edit moved the ground under us; any free neighbour will do
    for _, d in ipairs({ { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 } }) do
      local cx, cy = STAND.x + d[1], STAND.y + d[2]
      if ow.map:isWalkableCell(cx, cy) and not ow:npcAtCell(cx, cy) then
        U.teleport(game, MAP, cx, cy, "down")
        U.wait(10)
        break
      end
    end
  end
  local SHOT_DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  check("the window rendered", U.shot(game, SHOT_DIR .. "/bug606_console.png"))

  -- A driver run boots straight past the launcher (main.lua: POKEPORT_DRIVER is
  -- a scripted run), so bring a real interactive one up and take over the
  -- handlers it normally owns.  This is the panel the reporter needs: Mods >
  -- Find mods adds a repo and installs, and a column that is not imported yet
  -- shows Choose ROM.
  local imp = RomImporter.new(function() end, { launcher = true })
  imp.play = function() U.log("Play is inert here: the game is already booted.") end
  if okCheck and Check then imp.Check = Check end -- so the update banner draws
  if os.getenv("POKEPORT_PICKER") == "1" then
    -- every column offers Choose ROM again, so the picker can be opened even on
    -- a machine where all three games are already imported.  Cancelling the
    -- dialog is enough; only picking a file would re-extract.
    imp.forceImport = true
    imp.ready = {}
  end

  love.draw = function()
    imp:update(love.timer.getDelta())
    imp:draw()
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()
    love.graphics.setColor(0, 0, 0, 0.72)
    love.graphics.rectangle("fill", 0, h - 54, w, 54)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(("#606 checks: %d passed, %d failed"):format(passed, failed), 10, h - 48)
    love.graphics.print("F9 runs curl / powershell / the update check again", 10, h - 34)
    love.graphics.print("full log: " .. love.filesystem.getSaveDirectory() .. "/" .. REPORT,
                        10, h - 20)
  end
  love.mousepressed = function(x, y, button) imp:mousepressed(x, y, button or 1) end
  love.textinput = function(t) imp:textinput(t) end
  -- backspace and enter in the "add an index" field arrive here, not through
  -- textinput; f9 is kept for the loop below so the launcher never sees it
  love.keypressed = function(key)
    if key ~= "f9" then imp:keypressed(key) end
  end

  say("The launcher on screen is the real one. Open Mods > Find mods, add an")
  say("index, install something, and click Choose ROM on a column that is not")
  say("imported yet (POKEPORT_PICKER=1 brings that button back on every column).")
  say("Right: not one black console window appears or blinks, at any point,")
  say("while the file dialog still opens normally and the fetches still land.")
  say("Near-miss one: a single console sits there permanently instead of many")
  say("flashes, which means it was allocated but ShowWindow never resolved.")
  say("Near-miss two: the picker dialog opens, you choose a ROM, and the")
  say("launcher just carries on as if you had cancelled -- that is the")
  say("PowerShell stdout write, not the console.")

  local held = false
  while true do
    -- keep F9 for the reporter and hand every other key to the launcher
    local down = love.keyboard and love.keyboard.isDown("f9")
    if down and not held then
      say("re-running the host tools; watch the desktop, not the window")
      runProbes(true)
      if okCheck and Check then pcall(Check.start) end
    end
    held = down
    coroutine.yield()
  end
end
