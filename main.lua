-- Native LÖVE2D port of Pokemon Red. A packaged build creates its private
-- game-data cache from a user-provided ROM on first boot.
--
-- The save editor (tools/save-editor/) ships inside every build and is
-- reachable two ways:
--   * standalone: POKEPORT_EDITOR=1 or `love . --editor`, its own window
--   * from the launcher: Edit on a save row, which suspends the launcher,
--     opens the editor on that slot's file, and restores the launcher when
--     the editor's Close button is pressed (openEditor / closeEditor below)

local editorMode = os.getenv("POKEPORT_EDITOR") == "1" or POKEPORT_EDITOR_MODE == true

local Game, EditorApp, Importer, TouchEditor

local autopilot -- optional scripted-input dev tool (tests/autopilot.lua)
local driverCo  -- optional frame-driver (POKEPORT_DRIVER=file.lua): a
                -- coroutine that receives `Game` and yields once per
                -- frame; used headless (xvfb) for scripted screenshots

-- --speed N / POKEPORT_SPEED=N: run the logic clock N times faster without
-- touching audio (src/core/GameSpeed.lua).  Overrides the saved option so a
-- bot or screenshot run is not at the mercy of the player's last choice.
local speedOverride = tonumber(os.getenv("POKEPORT_SPEED"))

-- POKEPORT_TOUCH=1 forces the mobile on-screen controls on and lets the
-- mouse stand in for a finger, so the overlay can be exercised on desktop
-- (see src/core/TouchControls.lua).
local mouseTouch = os.getenv("POKEPORT_TOUCH") == "1"

-- How many times to run a scripted act+step loop per rendered frame.  Only
-- scripted runs use this; interactive play fast-forwards through
-- Game.speedOverride / the GAME SPEED option instead.
local function scriptedIterations()
  if not (autopilot or driverCo) then return 1 end
  return math.max(1, math.floor(require("src.core.GameSpeed").clamp(speedOverride)))
end

-- ------------------------------------------------------------ save editor
-- The launcher instance parked while the editor is up, plus the version whose
-- cache the editor mounted (so closing can put the read path back).
local editorHost, editorVersion, editorWindow
local closeEditor  -- forward declaration: openEditor hands it to the editor

-- The editor's modules use flat names (require("Kit"), require("Party")), so
-- their directories have to be on the require path.  It must be
-- love.filesystem's path, not package.path: in a packaged build these files
-- live inside the .love archive, which the stock Lua searcher cannot open.
local function addEditorRequirePath()
  local fs = love.filesystem
  if not (fs.setRequirePath and fs.getRequirePath) then
    -- very old LOVE: a source checkout still resolves through package.path
    package.path = fs.getSource() .. "/tools/save-editor/?.lua;"
                .. fs.getSource() .. "/tools/save-editor/panels/?.lua;"
                .. package.path
    return
  end
  local current = fs.getRequirePath()
  if current:find("tools/save%-editor") then return end
  fs.setRequirePath("tools/save-editor/?.lua;tools/save-editor/panels/?.lua;"
    .. current)
end

-- Desktop only: the launcher window (1024x768) is tighter than the editor's
-- design size, so grow it while editing and put it back on Close.  Never
-- shrinks, never touches a fullscreen or mobile window.
local function resizeForEditor()
  if not (love.window and love.window.getMode and love.window.setMode) then return end
  local osName = love.system.getOS()
  if osName ~= "OS X" and osName ~= "Windows" and osName ~= "Linux" then return end
  local w, h, flags = love.window.getMode()
  if flags.fullscreen then return end
  local dw, dh = love.window.getDesktopDimensions()
  local wantW = math.max(w, math.min(1360, math.floor((dw or w) * 0.92)))
  local wantH = math.max(h, math.min(860, math.floor((dh or h) * 0.88)))
  if wantW <= w and wantH <= h then return end
  editorWindow = { w = w, h = h }
  love.window.setMode(wantW, wantH, flags)
end

local function restoreWindow()
  if not editorWindow then return end
  local _, _, flags = love.window.getMode()
  love.window.setMode(editorWindow.w, editorWindow.h, flags)
  editorWindow = nil
end

-- Open the editor on a launcher save row.  The version's cache has to be
-- mounted before the editor's Data:load runs, or a Blue save would be edited
-- against Red's species/item tables.
local function openEditor(version, slotId)
  local SaveData = require("src.core.SaveData")
  local path = SaveData.slotDiskPath(version, slotId)
  if not path then
    if Importer then
      Importer.saveNotice = Importer.saveNotice or {}
      Importer.saveNotice[version] =
        { ok = false, text = "Could not resolve that save slot on disk." }
    end
    return
  end
  local GameVersion = require("src.core.GameVersion")
  GameVersion.set(version)
  require("src.import.CacheFs").mountVersion(version)
  editorVersion = version
  editorHost = Importer
  Importer = nil
  editorMode = true
  resizeForEditor()
  addEditorRequirePath()
  EditorApp = require("App")
  EditorApp.load(path, { version = version, slotId = slotId, embedded = true,
                         onClose = function() closeEditor() end })
end

-- Back to the launcher.  Everything the editor mounted or cached has to come
-- back out: the version overlay (CacheFs) and the generated modules require
-- cached behind it (Data), or pressing Play on the OTHER game would boot it
-- with this one's data.
function closeEditor()
  local version = editorVersion
  editorMode = false
  if EditorApp and EditorApp.unload then EditorApp.unload() end
  EditorApp = nil
  if version then
    require("src.import.CacheFs").unmountVersion(version)
    require("src.core.Data"):unloadGenerated()
  end
  editorVersion = nil
  restoreWindow()
  Importer = editorHost
  editorHost = nil
  if Importer and version and Importer.savesChanged then
    Importer:savesChanged(version)
  end
end

-- ------------------------------------------------------------ touch controls editor
-- Suspends the launcher while the player drags on-screen buttons / toggles
-- the overlay off (#327).  No ROM cache needed -- options.lua only.
local touchEditorHost
local closeTouchControlsEditor  -- forward declaration

local function openTouchControlsEditor()
  touchEditorHost = Importer
  Importer = nil
  TouchEditor = require("src.ui.TouchControlsEditor")
  TouchEditor.load({ onClose = function() closeTouchControlsEditor() end })
end

function closeTouchControlsEditor()
  if TouchEditor and TouchEditor.unload then TouchEditor.unload() end
  TouchEditor = nil
  Importer = touchEditorHost
  touchEditorHost = nil
end

local function bootGame(version)
  -- The launcher hands us the chosen game (Red / Blue / Yellow); scripted and
  -- headless runs fall back to POKEPORT_VERSION, then Red.  Set the active
  -- version and overlay its extracted cache BEFORE anything requires generated
  -- data, so data/generated + assets/generated resolve to that version's files.
  local GameVersion = require("src.core.GameVersion")
  GameVersion.set(version or os.getenv("POKEPORT_VERSION") or "red")
  require("src.import.CacheFs").mountVersion(GameVersion.get())
  if love.window and love.window.setTitle then
    local Version = require("src.core.Version")
    love.window.setTitle(Version.title(
      GameVersion.info().displayName .. " (Gen 1 Recompilation Project)"))
  end
  Game = require("src.core.Game")
  Game:load()
  if os.getenv("POKEPORT_AUTOPILOT") then
    autopilot = require("tests.autopilot")
  end
  local driverPath = os.getenv("POKEPORT_DRIVER")
  if driverPath then
    local fn = assert(loadfile(driverPath))()
    driverCo = coroutine.create(fn)
  end
  -- After the two above are known: a scripted run drives the multiplier
  -- from love.update's loop, so the in-engine one must stay at 1 or the
  -- two would compound (10x10 = 100 steps per observation).
  Game.speedOverride = (autopilot or driverCo) and 1 or speedOverride
end

function love.load(args)
  -- Before anything can shell out (update check, mod index, ROM picker),
  -- claim one hidden console on Windows so those children inherit it instead
  -- of each flashing their own cmd.exe window (#606).  No-op elsewhere.
  require("src.core.HostShell").hideHostConsole()

  -- Self-updater boot shell: a fused build may mount and chainload a newer
  -- downloaded payload here.  True means it took over, so we must stop.  A
  -- dev / source checkout no-ops (see src/update/Boot.lua).
  local Boot = require("src.update.Boot")
  if Boot.run(args) then return end

  local savePath
  for i, a in ipairs(args or {}) do
    if a == "--editor" then
      editorMode = true
    elseif a == "--developer" then
      _G.POKEPORT_DEV_MODE = true
    elseif a == "--save" and args[i + 1] and args[i + 1] ~= "" then
      savePath = args[i + 1]
    elseif a == "--speed" and tonumber(args[i + 1]) then
      speedOverride = tonumber(args[i + 1])
    end
  end
  love.graphics.setDefaultFilter("nearest", "nearest")

  -- Standalone editor.  A bare `--editor` run has no launcher behind it, so
  -- Close quits; --save points it at a specific file, otherwise it opens the
  -- default save path for POKEPORT_VERSION (Red unless overridden), whose
  -- cache has to be mounted before the editor's Data:load.
  if editorMode then
    local version = os.getenv("POKEPORT_VERSION") or "red"
    require("src.core.GameVersion").set(version)
    require("src.import.CacheFs").mountVersion(version)
    addEditorRequirePath()
    EditorApp = require("App")
    EditorApp.load(savePath, { version = version })
    return
  end

  local RomImporter = require("src.import.RomImporter")
  local forceImport = os.getenv("POKEPORT_FORCE_IMPORT") == "1"
  local importPath = os.getenv("POKEPORT_IMPORT_ROM")
  -- Scripted / headless runs pick their game from POKEPORT_VERSION (default
  -- Red); the launcher's per-column choice does not apply to them.
  local scriptedVersion = os.getenv("POKEPORT_VERSION") or "red"
  local ready = RomImporter.isReady(scriptedVersion)
  -- Scripted / headless runs have to reach the game with no human pressing
  -- Play: an autopilot, a frame driver, an import-only build step, or an
  -- explicit ROM path all bypass the interactive launcher and keep today's
  -- import-then-boot (or boot-straight-in) behavior.
  local scripted = os.getenv("POKEPORT_AUTOPILOT") or os.getenv("POKEPORT_DRIVER")
    or os.getenv("POKEPORT_IMPORT_ONLY") == "1" or importPath ~= nil

  if scripted then
    if forceImport or not ready then
      -- The importer detects the dropped/loaded ROM's version by SHA-1 and
      -- passes it to onComplete; boot that version.
      Importer = RomImporter.new(function(version)
        if os.getenv("POKEPORT_IMPORT_ONLY") == "1" then
          love.event.quit()
          return
        end
        Importer = nil
        bootGame(version or scriptedVersion)
      end)
      if importPath then Importer:startPath(importPath) end
      return
    end
    bootGame(scriptedVersion)
    return
  end

  -- Interactive: the launcher always runs.  Red, Blue, and Yellow are each
  -- live: a column shows Play when that game's ROM is already imported, or
  -- Choose ROM / drag-drop when it is not.  Any dropped .gb is routed by its
  -- SHA-1 (GameVersion.forSha1); pressing Play boots that game.  Edit on a
  -- save row opens the bundled editor on that slot (openEditor).
  Importer = RomImporter.new(function(version)
    Importer = nil
    bootGame(version)
  end, {
    launcher = true,
    forceImport = forceImport,
    onEditSave = openEditor,
    onEditTouchControls = openTouchControlsEditor,
  })
end

function love.update(dt)
  if editorMode then return EditorApp.update(dt) end
  if TouchEditor then return TouchEditor.update(dt) end
  if Importer then return Importer:update(dt) end

  -- Scripted runs (autopilot / POKEPORT_DRIVER) observe and act exactly
  -- once per Game:update, so they must keep a 1:1 relationship with the
  -- logic step.  Fast-forwarding them by scaling the step inside
  -- Game:update would run N steps per observation: a held direction walks
  -- through all N, the player slides past the waypoint, and the script
  -- re-plans from an overshot cell.  So iterate the whole act+step loop
  -- instead -- same script, just more of it per rendered frame.
  local iterations = scriptedIterations()

  if autopilot then
    for _ = 1, iterations do
      autopilot.update()
      Game:update(1 / 60) -- deterministic stepping for the autopilot
    end
    return
  end
  if driverCo then
    for _ = 1, iterations do
      local ok, err = coroutine.resume(driverCo, Game)
      if not ok then
        print("driver error: " .. tostring(err))
        love.event.quit(1)
        return
      end
      if coroutine.status(driverCo) == "dead" then
        love.event.quit()
        return
      end
      Game:update(1 / 60)
    end
    return
  end
  Game:update(dt)
end

function love.draw()
  if editorMode then return EditorApp.draw() end
  if TouchEditor then return TouchEditor.draw() end
  if Importer then return Importer:draw() end

  Game:draw()
  -- frame capture requested by a driver
  if Game.capturePath then
    local path = Game.capturePath
    Game.capturePath = nil
    love.graphics.captureScreenshot(function(imagedata)
      local fd = imagedata:encode("png")
      local f = io.open(path, "wb")
      if f then
        f:write(fd:getString())
        f:close()
      end
    end)
  end
end

function love.keypressed(key, scancode, isrepeat)
  if editorMode then return EditorApp.keypressed(key) end
  if TouchEditor then return TouchEditor.keypressed(key) end
  if Importer then return Importer:keypressed(key) end
  Game:keypressed(key)
end

function love.keyreleased(key)
  if editorMode or TouchEditor then return end
  if Importer then return end
  Game:keyreleased(key)
end

function love.gamepadpressed(joystick, button)
  if editorMode or TouchEditor then return end
  if Importer then return Importer:gamepadpressed(joystick, button) end
  Game:gamepadpressed(joystick, button)
end

function love.gamepadreleased(joystick, button)
  if editorMode or TouchEditor then return end
  if Importer then return Importer:gamepadreleased(joystick, button) end
  Game:gamepadreleased(joystick, button)
end

function love.gamepadaxis(joystick, axis, value)
  if editorMode or TouchEditor then return end
  if Importer then return Importer:gamepadaxis(joystick, axis, value) end
  Game:gamepadaxis(joystick, axis, value)
end

function love.joystickpressed(joystick, button)
  if editorMode or TouchEditor then return end
  if Importer then return Importer:joystickpressed(joystick, button) end
  Game:joystickpressed(joystick, button)
end

function love.joystickreleased(joystick, button)
  if editorMode or TouchEditor then return end
  if Importer then return Importer:joystickreleased(joystick, button) end
  Game:joystickreleased(joystick, button)
end

function love.joystickaxis(joystick, axis, value)
  if editorMode or TouchEditor then return end
  if Importer then return Importer:joystickaxis(joystick, axis, value) end
  Game:joystickaxis(joystick, axis, value)
end

function love.joystickhat(joystick, hat, direction)
  if editorMode or TouchEditor then return end
  if Importer then return Importer:joystickhat(joystick, hat, direction) end
  Game:joystickhat(joystick, hat, direction)
end

function love.joystickremoved(joystick)
  if editorMode or TouchEditor then return end
  if Importer then return end
  Game:joystickremoved(joystick)
end

-- f is true on focus gained, false on focus lost (e.g. alt-tab). A held
-- direction's key-up can be delivered to the OS instead of the game while
-- unfocused, so reset input on either transition rather than trust it.
function love.focus(f)
  if editorMode or TouchEditor then return end
  if Importer then
    if Importer.focus then Importer:focus(f) end
    return
  end
  Game:focus(f)
end

-- v is true when the window becomes visible again, false on minimize.
function love.visible(v)
  if editorMode or TouchEditor then return end
  if Importer then return end
  Game:visible(v)
end

function love.touchpressed(id, x, y, dx, dy, pressure)
  if editorMode then return end
  if TouchEditor then
    -- iOS synthesizes mousepressed for the primary touch (same as the
    -- launcher); Android drives the editor through love.touch directly.
    if love.system.getOS() == "iOS" then return end
    return TouchEditor.touchpressed(id, x, y)
  end
  if Importer then
    -- iOS: LÖVE already synthesizes a mousepressed for the primary touch,
    -- and love.mousepressed below forwards that to the Importer, so
    -- forwarding here too fires every launcher button twice per tap.  The
    -- resulting double-present was fatal for the document picker: the
    -- second sheet stole the first one's weakly-held delegate, so picking
    -- a file silently did nothing.  Android keeps the forward for upstream
    -- parity (its SAF picker is a separate activity and tolerates the
    -- re-launch).
    if love.system.getOS() == "iOS" then return end
    return Importer:mousepressed(x, y, 1)
  end
  Game:touchpressed(id, x, y)
end

function love.touchmoved(id, x, y, dx, dy, pressure)
  if editorMode then return end
  if TouchEditor then
    if love.system.getOS() == "iOS" then return end
    return TouchEditor.touchmoved(id, x, y)
  end
  if Importer then return end
  Game:touchmoved(id, x, y)
end

function love.touchreleased(id, x, y, dx, dy, pressure)
  if editorMode then return end
  if TouchEditor then
    if love.system.getOS() == "iOS" then return end
    return TouchEditor.touchreleased(id, x, y)
  end
  if Importer then return end
  Game:touchreleased(id, x, y)
end

function love.wheelmoved(x, y)
  if editorMode then
    if EditorApp.wheelmoved then return EditorApp.wheelmoved(x, y) end
    return
  end
  if TouchEditor then return end
  if Importer then return end
  Game:wheelmoved(x, y)
end

function love.mousepressed(x, y, button, istouch)
  if TouchEditor then
    -- Android primary touch already arrived via love.touchpressed; a second
    -- mouse path would double-fire Done / begin a second drag.
    if love.system.getOS() == "Android" then return end
    return TouchEditor.mousepressed(x, y, button)
  end
  if Importer then
    -- The same double-fire TouchEditor guards against, which the launcher was
    -- missing: love.touchpressed above forwards the primary touch to the
    -- Importer on Android, and LÖVE ALSO synthesizes a mouse press for that
    -- same touch, so one tap ran every launcher button twice.  On Import that
    -- meant two choose() calls and two stacked SAF picker activities: the
    -- player picked their ROM, the top picker closed, and the second was still
    -- underneath asking for it again, which is the "import the file twice"
    -- in #553.  Filtering on istouch keeps a real mouse (DeX, a Chromebook, a
    -- USB mouse) working, which an Android-wide return would have broken.
    --
    -- ANDROID ONLY, and the OS test is load bearing: love.touchpressed above
    -- returns early on iOS and never forwards, so there the synthesized mouse
    -- press is the ONLY event the launcher gets.  Filtering istouch on both
    -- killed every tap on iOS outright.
    if istouch and love.system.getOS() == "Android" then return end
    return Importer:mousepressed(x, y, button)
  end
  if editorMode and EditorApp.mousepressed then
    return EditorApp.mousepressed(x, y, button)
  end
  if mouseTouch and Game and button == 1 then
    Game:touchpressed("mouse", x, y)
  end
end

function love.mousereleased(x, y, button)
  if TouchEditor then
    if love.system.getOS() == "Android" then return end
    return TouchEditor.mousereleased(x, y, button)
  end
  if Importer then return end
  if editorMode and EditorApp.mousereleased then
    return EditorApp.mousereleased(x, y, button)
  end
  if mouseTouch and Game and button == 1 then
    Game:touchreleased("mouse", x, y)
  end
end

function love.mousemoved(x, y)
  if TouchEditor then
    if love.system.getOS() == "Android" then return end
    return TouchEditor.mousemoved(x, y)
  end
  if editorMode or Importer then return end
  if mouseTouch and Game and love.mouse.isDown(1) then
    Game:touchmoved("mouse", x, y)
  end
end

function love.textinput(text)
  if TouchEditor then return end
  if Importer then return Importer:textinput(text) end
  if editorMode and EditorApp.textinput then
    return EditorApp.textinput(text)
  end
end

function love.quit()
  if editorMode and EditorApp.quit then
    return EditorApp.quit() -- return true to abort quit
  end
  pcall(function()
    require("src.core.DiscordPresence").shutdown()
  end)
  -- LOVE waits for every live love.thread before the process exits, and both
  -- background workers idle in a loop that only a "quit" command breaks, so
  -- without this the process outlived the window and the next launch re-entered
  -- the dead one instead of starting fresh (#339)
  if package.loaded["src.core.ChipAudio"] then
    pcall(package.loaded["src.core.ChipAudio"].shutdown)
  end
  if package.loaded["src.update.Check"] then
    pcall(package.loaded["src.update.Check"].shutdown)
  end
end

function love.filedropped(file)
  if editorMode and EditorApp and EditorApp.filedropped then
    return EditorApp.filedropped(file)
  end
  if Importer then Importer:filedropped(file) end
end

local function pacingEnabled()
  if os.getenv("POKEPORT_AUTOPILOT") then return false end
  if os.getenv("POKEPORT_DRIVER") then return false end
  if os.getenv("POKEPORT_IMPORT_ONLY") == "1" then return false end
  return true
end

function love.run()
  if love.load then love.load(love.arg.parseGameArguments(arg), arg) end

  -- don't let love.load's cost land in the first frame's dt
  if love.timer then love.timer.step() end

  local FrameCap = require("src.core.FrameCap")
  local paced = pacingEnabled()
  -- The deadline the next present() should not beat.  Carried forward one
  -- budget per frame so pacing stays even instead of drifting with the
  -- per-frame sleep-granularity jitter.
  local nextFrame = love.timer and love.timer.getTime() or 0
  local dt = 0

  return function()
    -- process events
    if love.event then
      love.event.pump()
      for name, a, b, c, d, e, f in love.event.poll() do
        if name == "quit" then
          if not love.quit or not love.quit() then
            -- Android keeps the process and its task alive after LOVE's own
            -- teardown, so the relaunched task re-enters an activity whose
            -- native main already returned; end the process outright once the
            -- love.quit hook has run (#339)
            if love.system and love.system.getOS() == "Android" then
              os.exit(a or 0)
            end
            return a or 0
          end
        end
        love.handlers[name](a, b, c, d, e, f)
      end
    end

    -- update dt
    if love.timer then dt = love.timer.step() end

    -- call update and draw
    if love.update then love.update(dt) end

    if love.graphics and love.graphics.isActive() then
      love.graphics.origin()
      love.graphics.clear(love.graphics.getBackgroundColor())
      if love.draw then love.draw() end
      love.graphics.present()
    end

    if love.timer then
      if paced then
        -- Sleep out the remainder of the frame budget, measured from the
        -- carried deadline, in small chunks so the OS timer stays
        -- responsive.  vsync is untouched: when it already paces slower
        -- than the cap the remainder is <= 0 and this rounds to a no-op.
        local budget = 1 / FrameCap.current
        nextFrame = nextFrame + budget
        local now = love.timer.getTime()
        -- A stall (alt-tab, a GC pause, a blocked import) can leave the
        -- deadline more than a full budget in the past; re-anchor to now so
        -- we pace the next frame rather than burst uncapped to catch up.
        if now - nextFrame > budget then
          nextFrame = now
        end
        while true do
          local remaining = nextFrame - love.timer.getTime()
          if remaining <= 0 then break end
          love.timer.sleep(remaining < 0.001 and remaining or 0.001)
        end
      else
        love.timer.sleep(0.001)
      end
    end
  end
end
