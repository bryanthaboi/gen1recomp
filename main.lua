-- Native LÖVE2D port of Pokemon Red. A packaged build creates its private
-- game-data cache from a user-provided ROM on first boot.
--
-- The save editor (tools/save-editor/) ships inside every build and is
-- reachable two ways:
--   * standalone: POKEPORT_EDITOR=1 or `love . --editor`, its own window
--   * from the launcher: Edit on a save row, which suspends the launcher,
--     opens the editor on that slot's file, and restores the launcher when
--     the editor's Close button is pressed (openEditor / closeEditor below)

if POKEPORT_DISPLAY_COMPANION then
  return require("src.render.DesktopCompanion").install(
    POKEPORT_DISPLAY_COMPANION)
end

local editorMode = os.getenv("POKEPORT_EDITOR") == "1" or POKEPORT_EDITOR_MODE == true

local SwitchDiagnostics = require("src.debug.SwitchDiagnostics")
local LaunchOptions = require("src.core.LaunchOptions")
local NxDisplay = require("src.core.NxDisplay")
local PlatformHooks = require("src.core.PlatformHooks")
local HostDisplay = require("src.core.HostDisplay")
local GameViewport = require("src.render.GameViewport")

-- Lua errors: persist a redacted trace in the save dir and surface a hint.
do
  local defaultErrorHandler = love.errorhandler
  function love.errorhandler(msg)
    local hint = SwitchDiagnostics.logLuaError(msg)
    if hint and type(msg) == "string" then
      msg = msg .. "\n\n" .. hint
    end
    if defaultErrorHandler then
      return defaultErrorHandler(msg)
    end
  end
end

local Game, EditorApp, Importer, TouchEditor, Studio

-- #887: quit-to-launcher state, shared by love.load and love.quit (both need
-- it, so it is declared here rather than next to love.quit).
--   * launchedIntoGame -- a --game / POKEPORT_GAME shortcut booted this
--     session straight into a game, so there is no launcher behind it and a
--     window close must exit.  Restarting instead re-read the same shortcut
--     and came right back into the game, and the next close did it again:
--     the app could not be closed at all (macOS feels this worst, where the
--     red X, Cmd+Q and the Dock's Quit are all the same quit event).
--   * RELAUNCH_MARKER -- written in the save dir just before the #785
--     restart, so the fresh boot ignores any boot-straight-into-a-game
--     option exactly once and keeps #785's promise of landing in the
--     launcher, whatever put the game on screen this time.
local launchedIntoGame = false
local RELAUNCH_MARKER = "relaunch_to_launcher.txt"

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
  local function refuse(text)
    if not Importer then return end
    Importer.saveNotice = Importer.saveNotice or {}
    Importer.saveNotice[version] = { ok = false, text = text }
  end
  local SaveData = require("src.core.SaveData")
  local path = SaveData.slotDiskPath(version, slotId)
  if not path then
    refuse("Could not resolve that save slot on disk.")
    return
  end
  local GameVersion = require("src.core.GameVersion")
  GameVersion.set(version)
  require("src.import.CacheFs").mountVersion(version)
  editorVersion = version
  editorHost = Importer
  -- Drop launcher pad/FlexLove so the save editor owns input (NX shim +
  -- virtual cursor + system hand cursor). Desktop park is a light no-op.
  if Importer and Importer.prepareOverlayHandoff then
    Importer:prepareOverlayHandoff()
  end
  Importer = nil
  editorMode = true
  resizeForEditor()
  addEditorRequirePath()
  local okReq, appOrErr = pcall(require, "App")
  if not okReq then
    editorMode = false
    if version then
      require("src.import.CacheFs").unmountVersion(version)
    end
    restoreWindow()
    Importer = editorHost
    editorHost = nil
    editorVersion = nil
    if Importer and Importer.resumeAfterOverlay then
      Importer:resumeAfterOverlay()
    end
    refuse("Could not open the save editor (" .. tostring(appOrErr) .. ").")
    return
  end
  EditorApp = appOrErr
  local okLoad, loadErr = pcall(EditorApp.load, path, {
    version = version, slotId = slotId, embedded = true,
    onClose = function() closeEditor() end,
  })
  if not okLoad then
    editorMode = false
    if EditorApp.unload then pcall(EditorApp.unload) end
    EditorApp = nil
    if version then
      require("src.import.CacheFs").unmountVersion(version)
      require("src.core.Data"):unloadGenerated()
    end
    restoreWindow()
    Importer = editorHost
    editorHost = nil
    editorVersion = nil
    if Importer and Importer.resumeAfterOverlay then
      Importer:resumeAfterOverlay()
    end
    refuse("Could not open the save editor (" .. tostring(loadErr) .. ").")
  end
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
  for k in pairs(package.loaded) do
    if type(k) == "string" and (k:find("save%-editor") or k == "App" or k == "Kit" or k == "State" or k == "Catalog" or k == "SaveIO" or k == "Ops" or k == "MonOps" or k == "ItemOps" or k == "PadInput" or k == "Gen" or k == "Theme") then
      package.loaded[k] = nil
    end
  end
  editorVersion = nil
  restoreWindow()
  Importer = editorHost
  editorHost = nil
  if Importer and Importer.resumeAfterOverlay then
    Importer:resumeAfterOverlay()
  end
  if Importer and version and Importer.savesChanged then
    Importer:savesChanged(version)
  end
end

-- ------------------------------------------------------------ touch controls editor
-- Suspends the launcher while the player drags on-screen buttons / toggles
-- the overlay off (#327).  No ROM cache needed -- options.lua only.
local touchEditorHost
local closeTouchControlsEditor  -- forward declaration

-- `version` is the launcher tab the gear was opened on, and it decides which
-- option block the layout lands in (src/ui/TouchControlsEditor.lua persist).
local function openTouchControlsEditor(version)
  touchEditorHost = Importer
  if Importer and Importer.prepareOverlayHandoff then
    Importer:prepareOverlayHandoff()
  end
  Importer = nil
  TouchEditor = require("src.ui.TouchControlsEditor")
  TouchEditor.load({
    version = version,
    onClose = function() closeTouchControlsEditor() end,
  })
end

function closeTouchControlsEditor()
  if TouchEditor and TouchEditor.unload then TouchEditor.unload() end
  TouchEditor = nil
  Importer = touchEditorHost
  touchEditorHost = nil
  if Importer and Importer.resumeAfterOverlay then
    Importer:resumeAfterOverlay()
  end
end

-- ------------------------------------------------------------ skin studio
local studioHost
local closeSkinStudio
local bootGame

local function openSkinStudio(version, skinId)
  local SkinStudio = require("src.ui.SkinStudio")
  if not SkinStudio.available_desktop() then return end
  studioHost = Importer
  if Importer and Importer.prepareOverlayHandoff then
    Importer:prepareOverlayHandoff()
  end
  Importer = nil
  Studio = SkinStudio
  Studio.load({
    version = version,
    skinId = skinId,
    onClose = function() closeSkinStudio() end,
    onPlay = function(v)
      closeSkinStudio()
      Importer = nil
      bootGame(v or version)
    end,
  })
end

function closeSkinStudio()
  if Studio and Studio.unload then Studio.unload() end
  Studio = nil
  Importer = studioHost
  studioHost = nil
  if Importer and Importer.resumeAfterOverlay then
    Importer:resumeAfterOverlay()
  end
end

local function makeLauncher()
  local RomImporter = require("src.import.RomImporter")
  local forceImport = os.getenv("POKEPORT_FORCE_IMPORT") == "1"
  return RomImporter.new(function(version)
    Importer = nil
    bootGame(version)
  end, {
    launcher = true,
    forceImport = forceImport,
    onEditSave = openEditor,
    onEditTouchControls = openTouchControlsEditor,
    onOpenSkinStudio = require("src.ui.SkinStudio").available_desktop()
      and openSkinStudio or nil,
  })
end

local function returnToLauncher()
  if not Game then return end

  pcall(function() require("src.core.Music").stop() end)
  pcall(function() require("src.core.Sound").stop() end)
  if package.loaded["src.core.ChipAudio"] then
    pcall(package.loaded["src.core.ChipAudio"].shutdown)
  end
  if package.loaded["src.core.DiscordPresence"] then
    pcall(package.loaded["src.core.DiscordPresence"].shutdown)
  end
  if package.loaded["src.core.gen2.Clock"] then
    pcall(package.loaded["src.core.gen2.Clock"].shutdown)
  end
  if package.loaded["src.net.Gen1Tls"] then
    pcall(package.loaded["src.net.Gen1Tls"].shutdown)
  end
  if love.audio and love.audio.stop then
    pcall(love.audio.stop)
  end
  pcall(function() require("src.render.SecondScreen").setEnabled(false) end)

  local GameVersion = require("src.core.GameVersion")
  local currentVersion = GameVersion.get()
  if currentVersion then
    require("src.import.CacheFs").unmountVersion(currentVersion)
  end
  require("src.core.Data"):unloadGenerated()

  local Runtime = require("src.mods.Runtime")
  if Runtime.reset then
    Runtime.reset()
  end

  Game = nil
  autopilot = nil
  driverCo = nil

  local Input = require("src.core.Input")
  local TouchControls = require("src.core.TouchControls")
  Input:reset()
  TouchControls:reset()

  require("src.core.Orientation").applyOptions(
    require("src.core.SaveData").loadOptions())

  local preload = require("src.mods.LauncherMods").translationStrings()
  if preload then require("src.core.Strings").load({ strings = preload }) end

  if love.window and love.window.setTitle then
    local Version = require("src.core.Version")
    love.window.setTitle(Version.title("Gen 1 Recompilation Project"))
  end

  Importer = makeLauncher()
end

function bootGame(version)
  -- The launcher hands us the chosen game (Red / Blue / Yellow / Gold);
  -- scripted and headless runs fall back to POKEPORT_VERSION, then Red.
  -- Set the active version and overlay its extracted cache BEFORE anything
  -- requires generated data, so data/generated + assets/generated resolve
  -- to that version's files.
  local GameVersion = require("src.core.GameVersion")
  GameVersion.set(version or os.getenv("POKEPORT_VERSION") or "red")
  local CacheFs = require("src.import.CacheFs")
  -- Keep CacheFs.prefix aligned for any CacheFs.read fallback during Data:load
  -- (Blue/Yellow/Gold caches live under blue/ / yellow/ / gold/).
  CacheFs.prefix = GameVersion.cachePrefix()
  CacheFs.mountVersion(GameVersion.get())
  -- NX: always write nx-asset-probe.log so Yellow/Blue art failures are
  -- diagnosable from the SD without enabling switch-debug.txt.
  pcall(function()
    require("src.debug.SwitchDiagnostics").probeAssets(GameVersion.get())
  end)
  if love.window and love.window.setTitle then
    local Version = require("src.core.Version")
    love.window.setTitle(Version.title(
      GameVersion.info().displayName .. " (Gen 1 Recompilation Project)"))
  end
  -- Gen 2: Gen 1 Game:load cannot consume a Gen 2 cache -- different generated
  -- tables, save shape and screen registry -- so Gold and Silver boot their
  -- own service owner, which mounts src/world/gen2 (walk / warps /
  -- connections) and the Gen 2 screens instead of src/core/Game.lua's Gen 1
  -- wiring.
  if GameVersion.generation() == 2 then
    Game = require("src.core.Game2").new()
    Game:load()
  else
    Game = require("src.core.Game")
    Game:load()
    if os.getenv("POKEPORT_AUTOPILOT") then
      autopilot = require("tests.autopilot")
    end
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

  -- Hang gen1tls on love.system before mods boot.  Android already has tls*
  -- from JNI; this is the desktop half.  No DLL / no FFI is fine -- ws://
  -- rooms still work, wss:// just won't.
  pcall(function() require("src.net.Gen1Tls").install() end)

  -- NX fused mounts are unreliable for the blue|yellow cache overlay: wrap
  -- the love loaders once so every generated-asset read falls back to the
  -- versioned save-dir copy.  Never installed on desktop/Android/iOS.
  if require("src.core.Platform").isNX() then
    require("src.core.NxAssetOverlay").install()
  end

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
  -- NX: handheld 720p / docked 1080p. Runs for every boot path (launcher,
  -- editor, scripted); no-op on desktop/mobile.
  NxDisplay.sync()

  -- Apply the persisted Android orientation lock (#592) before the launcher
  -- shows: SDL created the window with no orientation hint, so without this
  -- the launcher would rotate freely until options are applied at boot.
  -- No-op on desktop / iOS / when options.lua does not exist yet.
  require("src.core.Orientation").applyOptions(
    require("src.core.SaveData").loadOptions())

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
  -- Scripted / headless runs pick their game from POKEPORT_VERSION, then
  -- POKEPORT_GAME / --game= (LaunchOptions), then Red.  Drivers for Gold
  -- must honor POKEPORT_GAME=gold the same way a desktop shortcut does.
  local scriptedVersion = os.getenv("POKEPORT_VERSION")
    or LaunchOptions.resolve(arg)
    or "red"
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

  -- The launcher draws before any game boots, so the mod loader has not run
  -- and Strings has no catalog.  Routing the launcher's text through Strings
  -- (#767) only pays off if something fills that catalog this early, and no
  -- restart could: the ordering is the same on every launch.  Read the
  -- enabled mods' string catalogs -- data only, no entry chunk -- so a
  -- translation reaches the launcher too.  The active game's loader replaces
  -- this with the real merged catalog once a version boots.
  do
    local preload = require("src.mods.LauncherMods").translationStrings()
    if preload then require("src.core.Strings").load({ strings = preload }) end
  end

  -- LAUNCH OPTIONS: skip the launcher and boot a game directly.
  --   --game red|blue|yellow|gold  (or POKEPORT_GAME / POKEPORT_LAUNCH)
  --   --slot <id>             optional; picks the save slot to load
  --   --launcher              force the launcher even if a game is set
  -- This is what a desktop shortcut, a Steam entry, or a frontend like
  -- EmulationStation needs: one click into the game the player wants, with no
  -- menu in between.  A game that is not imported falls through to the
  -- launcher on its tab rather than booting into nothing.
  -- A window close that restarted us into the launcher (#785) leaves the
  -- marker behind: consume it and stay on the launcher, or the shortcut below
  -- would boot the same game again and that close would restart again,
  -- forever (#887).  Consumed on read, so the very next launch is normal.
  local relaunched = love.filesystem.getInfo(RELAUNCH_MARKER) ~= nil
  if relaunched then pcall(love.filesystem.remove, RELAUNCH_MARKER) end

  local launchGame, launchSlot = LaunchOptions.resolve(arg)
  if launchGame and not relaunched and not LaunchOptions.forceLauncher(arg) then
    if RomImporter.isReady(launchGame) then
      if launchSlot then LaunchOptions.selectSlot(launchGame, launchSlot) end
      -- No launcher behind this session: love.quit must exit, not restart.
      launchedIntoGame = true
      bootGame(launchGame)
      return
    end
    -- Not importable yet: open the launcher already showing that game, so the
    -- shortcut still lands the player where they meant to go.
    LaunchOptions.pendingTab = launchGame
  end

  -- Interactive: the launcher always runs.  Red, Blue, Yellow, and Gold are
  -- each live: a column shows Play when that game's ROM is already imported,
  -- or Choose ROM / drag-drop when it is not.  Any dropped .gb/.gbc is routed
  -- by its SHA-1 (GameVersion.forSha1); pressing Play boots that game (Gold
  -- goes to its own service owner, src/core/Game2.lua -- docs/gold-phase1.md).
  -- Edit on a save row opens the bundled editor on that slot (openEditor).
  Importer = makeLauncher()
end

function love.update(dt)
  HostDisplay.update(dt)
  SwitchDiagnostics.maybeFlush(false)
  -- NX only (no-op elsewhere): follow dock/undock without waiting for SDL.
  NxDisplay.sync()
  if editorMode then return EditorApp.update(dt) end
  if TouchEditor then return TouchEditor.update(dt) end
  if Studio then return Studio.update(dt) end
  if Importer then return Importer:update(dt) end
  if not Game then return end

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
  -- Mods may wrap or veto the per-frame simulation step (pause it, react
  -- to external platform state, etc.) -- see docs/modding.md's core.update
  -- entry. Vanilla behavior (used when no mod claims the hook) is just
  -- Game:update(dt), unconditionally, exactly as before this hook existed.
  PlatformHooks.update(Game, dt)
end

function love.draw()
  if editorMode then
    GameViewport.reset()
    HostDisplay.beginFrame("editor", EditorApp)
    local result = EditorApp.draw()
    HostDisplay.endFrame("editor", EditorApp)
    return result
  end
  if TouchEditor then
    GameViewport.reset()
    HostDisplay.beginFrame("touch_editor", TouchEditor)
    local result = TouchEditor.draw()
    HostDisplay.endFrame("touch_editor", TouchEditor)
    return result
  end
  if Studio then
    HostDisplay.beginFrame("skin_studio", Studio)
    local result = Studio.draw()
    HostDisplay.endFrame("skin_studio", Studio)
    return result
  end
  if Importer then
    GameViewport.reset()
    HostDisplay.beginFrame("launcher", Importer)
    local result = Importer:draw()
    HostDisplay.endFrame("launcher", Importer)
    return result
  end
  if not Game then
    GameViewport.reset()
    return
  end

  HostDisplay.beginFrame("game", Game)
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
  HostDisplay.endFrame("game", Game)
end

function love.keypressed(key, scancode, isrepeat)
  if editorMode then return EditorApp.keypressed(key) end
  if TouchEditor then return TouchEditor.keypressed(key) end
  if Studio then return Studio.keypressed(key) end
  if Importer then return Importer:keypressed(key) end
  if not Game then return end
  Game:keypressed(key)
end

function love.keyreleased(key)
  if editorMode or TouchEditor or Studio then return end
  if Importer then return end
  if not Game then return end
  Game:keyreleased(key)
end

function love.gamepadpressed(joystick, button)
  SwitchDiagnostics.onJoystickEvent("gamepadpressed", joystick, button)
  if editorMode then
    if EditorApp and EditorApp.gamepadpressed then
      return EditorApp.gamepadpressed(joystick, button)
    end
    return
  end
  if TouchEditor then
    if TouchEditor.gamepadpressed then
      return TouchEditor.gamepadpressed(joystick, button)
    end
    return
  end
  if Studio then return end
  if Importer then return Importer:gamepadpressed(joystick, button) end
  if not Game then return end
  Game:gamepadpressed(joystick, button)
end

function love.gamepadreleased(joystick, button)
  SwitchDiagnostics.onJoystickEvent("gamepadreleased", joystick, button)
  if editorMode then
    if EditorApp and EditorApp.gamepadreleased then
      return EditorApp.gamepadreleased(joystick, button)
    end
    return
  end
  if TouchEditor then
    if TouchEditor.gamepadreleased then
      return TouchEditor.gamepadreleased(joystick, button)
    end
    return
  end
  if Studio then return end
  if Importer then return Importer:gamepadreleased(joystick, button) end
  if not Game then return end
  Game:gamepadreleased(joystick, button)
end

function love.gamepadaxis(joystick, axis, value)
  SwitchDiagnostics.onJoystickEvent("gamepadaxis", joystick, axis, { value = value })
  if editorMode then
    if EditorApp and EditorApp.gamepadaxis then
      return EditorApp.gamepadaxis(joystick, axis, value)
    end
    return
  end
  if TouchEditor then
    if TouchEditor.gamepadaxis then
      return TouchEditor.gamepadaxis(joystick, axis, value)
    end
    return
  end
  if Studio then return end
  if Importer then return Importer:gamepadaxis(joystick, axis, value) end
  if not Game then return end
  Game:gamepadaxis(joystick, axis, value)
end

function love.joystickpressed(joystick, button)
  SwitchDiagnostics.onJoystickEvent("joystickpressed", joystick, button)
  if editorMode then
    if EditorApp and EditorApp.joystickpressed then
      return EditorApp.joystickpressed(joystick, button)
    end
    return
  end
  if TouchEditor then
    if TouchEditor.joystickpressed then
      return TouchEditor.joystickpressed(joystick, button)
    end
    return
  end
  if Studio then return end
  if Importer then return Importer:joystickpressed(joystick, button) end
  if not Game then return end
  Game:joystickpressed(joystick, button)
end

function love.joystickreleased(joystick, button)
  SwitchDiagnostics.onJoystickEvent("joystickreleased", joystick, button)
  if editorMode then
    if EditorApp and EditorApp.joystickreleased then
      return EditorApp.joystickreleased(joystick, button)
    end
    return
  end
  if TouchEditor then
    if TouchEditor.joystickreleased then
      return TouchEditor.joystickreleased(joystick, button)
    end
    return
  end
  if Studio then return end
  if Importer then return Importer:joystickreleased(joystick, button) end
  if not Game then return end
  Game:joystickreleased(joystick, button)
end

function love.joystickaxis(joystick, axis, value)
  SwitchDiagnostics.onJoystickEvent("joystickaxis", joystick, axis, { value = value })
  if editorMode then
    if EditorApp and EditorApp.joystickaxis then
      return EditorApp.joystickaxis(joystick, axis, value)
    end
    return
  end
  if TouchEditor then
    if TouchEditor.joystickaxis then
      return TouchEditor.joystickaxis(joystick, axis, value)
    end
    return
  end
  if Studio then return end
  if Importer then return Importer:joystickaxis(joystick, axis, value) end
  if not Game then return end
  Game:joystickaxis(joystick, axis, value)
end

function love.joystickhat(joystick, hat, direction)
  SwitchDiagnostics.onJoystickEvent("joystickhat", joystick, hat, { direction = direction })
  if editorMode then
    if EditorApp and EditorApp.joystickhat then
      return EditorApp.joystickhat(joystick, hat, direction)
    end
    return
  end
  if TouchEditor then
    if TouchEditor.joystickhat then
      return TouchEditor.joystickhat(joystick, hat, direction)
    end
    return
  end
  if Studio then return end
  if Importer then return Importer:joystickhat(joystick, hat, direction) end
  if not Game then return end
  Game:joystickhat(joystick, hat, direction)
end

function love.joystickadded(joystick)
  SwitchDiagnostics.onJoystickEvent("joystickadded", joystick)
  if editorMode or TouchEditor or Studio then return end
  if Importer then return end
  if not Game then return end
  Game:joystickadded(joystick)
end

function love.joystickremoved(joystick)
  SwitchDiagnostics.onJoystickEvent("joystickremoved", joystick)
  if editorMode or TouchEditor or Studio then return end
  if Importer then return end
  if not Game then return end
  Game:joystickremoved(joystick)
end

-- f is true on focus gained, false on focus lost (e.g. alt-tab). A held
-- direction's key-up can be delivered to the OS instead of the game while
-- unfocused, so reset input on either transition rather than trust it.
function love.focus(f)
  if editorMode or TouchEditor then return end
  if Studio then
    if Studio.focus then Studio.focus(f) end
    return
  end
  if Importer then
    require("src.core.Input"):reset()
    if Importer.focus then Importer:focus(f) end
    return
  end
  if not Game then return end
  Game:focus(f)
end

-- v is true when the window becomes visible again, false on minimize.
function love.visible(v)
  if editorMode or TouchEditor then return end
  if Studio then
    if Studio.visible then Studio.visible(v) end
    return
  end
  if Importer then
    require("src.core.Input"):reset()
    return
  end
  if not Game then return end
  Game:visible(v)
end

function love.lowmemory()
  if editorMode or TouchEditor or Studio or Importer then return end
  if Game then Game:onResume() end
end

love.handlers = love.handlers or {}

function love.handlers.audiosuspend()
  local ChipAudio = package.loaded["src.core.ChipAudio"]
  if ChipAudio then pcall(ChipAudio.setSuspended, true) end
  local Sound = package.loaded["src.core.Sound"]
  if Sound then pcall(Sound.onDeviceReset) end
end

function love.handlers.audioreset()
  local ChipAudio = package.loaded["src.core.ChipAudio"]
  if ChipAudio then
    pcall(ChipAudio.setSuspended, false)
    pcall(ChipAudio.rebuildPlayback)
  end
  local Music = package.loaded["src.core.Music"]
  if Music then pcall(Music.onDeviceReset) end
  local Sound = package.loaded["src.core.Sound"]
  if Sound then pcall(Sound.onDeviceReset) end
end

function love.handlers.intent_game(version)
  if type(version) ~= "string" or version == "" then return end
  version = version:lower():gsub("^%s+", ""):gsub("%s+$", "")
  local GameVersion = require("src.core.GameVersion")
  if GameVersion.VERSIONS and not GameVersion.VERSIONS[version] then return end

  local RomImporter = require("src.import.RomImporter")
  if not RomImporter.isReady(version) then return end

  local currentVersion = GameVersion.get()
  if Game and currentVersion == version then
    return
  end

  if Game then
    returnToLauncher()
  end
  Importer = nil
  bootGame(version)
end

function love.touchpressed(id, x, y, dx, dy, pressure)
  if editorMode then
    -- iOS synthesizes mousepressed for the primary touch; forwarding here
    -- would double-fire.  Android / NX need the explicit touch → click path
    -- (love-nx does not synthesize mouse for the editor the way desktop does).
    if love.system.getOS() == "iOS" then return end
    if EditorApp and EditorApp.mousepressed then
      return EditorApp.mousepressed(x, y, 1)
    end
    return
  end
  if TouchEditor then
    -- iOS synthesizes mousepressed for the primary touch (same as the
    -- launcher); Android drives the editor through love.touch directly.
    if love.system.getOS() == "iOS" then return end
    return TouchEditor.touchpressed(id, x, y)
  end
  if Studio then return end
  if Importer then
    -- Both mobiles: FlexLove scroll needs the real touch stream. Clicks are
    -- polled inside the view; the istouch filter on mousepressed still drops
    -- Android's synthesized mouse twin so Import cannot double-fire (#553).
    return Importer:touchpressed(id, x, y, dx, dy, pressure)
  end
  if not Game then return end
  Game:touchpressed(id, x, y, dx, dy, pressure)
end

function love.touchmoved(id, x, y, dx, dy, pressure)
  if editorMode then return end
  if TouchEditor then
    if love.system.getOS() == "iOS" then return end
    return TouchEditor.touchmoved(id, x, y)
  end
  if Studio then return end
  if Importer then
    return Importer:touchmoved(id, x, y, dx, dy, pressure)
  end
  if not Game then return end
  Game:touchmoved(id, x, y, dx, dy, pressure)
end

function love.touchreleased(id, x, y, dx, dy, pressure)
  if editorMode then return end
  if TouchEditor then
    if love.system.getOS() == "iOS" then return end
    return TouchEditor.touchreleased(id, x, y)
  end
  if Studio then return end
  if Importer then
    return Importer:touchreleased(id, x, y, dx, dy, pressure)
  end
  if not Game then return end
  Game:touchreleased(id, x, y, dx, dy, pressure)
end

function love.wheelmoved(x, y)
  if editorMode then
    if EditorApp.wheelmoved then return EditorApp.wheelmoved(x, y) end
    return
  end
  if TouchEditor then return end
  if Studio then return Studio.wheelmoved(x, y) end
  if Importer then return end
  if not Game then return end
  Game:wheelmoved(x, y)
end

-- #781: Linux X11 multi-monitor with the primary display away from desktop
-- (0,0): SDL's polled mouse state can come back in desktop-virtual
-- coordinates while the event stream stays window-relative, which strands
-- every polled consumer (launcher Kit rising-edge clicks, the pad-cursor
-- motion yield, PadCursor) on coordinates no hit test can match.  Sanitize
-- the poll once here: remember the last window-relative event coordinates
-- and substitute them whenever the polled value falls outside the window.
-- Linux only -- macOS / Windows / mobile keep the stock function, and the
-- NX launcher shim still composes because it captures whatever
-- love.mouse.getPosition is at bridge time (_ensureNxPointerBridge).
local eventMouseX, eventMouseY
if love.system and love.system.getOS() == "Linux"
    and love.mouse and love.mouse.getPosition then
  local polledGetPosition = love.mouse.getPosition
  love.mouse.getPosition = function()
    local x, y = polledGetPosition()
    local w, h = love.graphics.getDimensions()
    if x < 0 or y < 0 or x > w or y > h then
      if eventMouseX then return eventMouseX, eventMouseY end
      return math.max(0, math.min(x, w)), math.max(0, math.min(y, h))
    end
    return x, y
  end
end

function love.mousepressed(x, y, button, istouch)
  if not istouch then eventMouseX, eventMouseY = x, y end
  if TouchEditor then
    -- Android primary touch already arrived via love.touchpressed; a second
    -- mouse path would double-fire Done / begin a second drag.
    if love.system.getOS() == "Android" then return end
    return TouchEditor.mousepressed(x, y, button)
  end
  if Studio then return Studio.mousepressed(x, y, button) end
  if Importer then
    -- love.touchpressed already forwards the primary touch into FlexLove for
    -- scroll. LÖVE ALSO synthesizes a mouse press for that same touch; if both
    -- reached a press handler, one tap ran every launcher button twice and
    -- stacked two SAF pickers (#553). Clicks are polled inside FlexLove from
    -- love.touch / mouse.isDown, so dropping the synthesized istouch press is
    -- safe. A real mouse (DeX, Chromebook, USB) still reaches mousepressed.
    if istouch and (love.system.getOS() == "Android"
        or love.system.getOS() == "iOS") then return end
    return Importer:mousepressed(x, y, button)
  end
  if editorMode and EditorApp.mousepressed then
    -- Same Android double-fire guard: touchpressed already clicked for the
    -- save editor; a synthesized mouse press must not fire again.
    if istouch and love.system.getOS() == "Android" then return end
    return EditorApp.mousepressed(x, y, button)
  end
  if mouseTouch then
    -- the mouse is standing in for a finger: the touch path owns it, and
    -- feeding the same press back in as a mouse pointer would double it
    if Game and button == 1 then Game:touchpressed("mouse", x, y) end
    return
  end
  -- #807: a real mouse reaches gameplay as a pointer event for mods; Game
  -- drops synthesized istouch twins so a mobile touch that already arrived
  -- through love.touchpressed cannot fire twice
  if Game then Game:mousepressed(x, y, button, istouch) end
end

function love.mousereleased(x, y, button, istouch)
  if TouchEditor then
    if love.system.getOS() == "Android" then return end
    return TouchEditor.mousereleased(x, y, button)
  end
  if Studio then return Studio.mousereleased(x, y, button) end
  if Importer then return end
  if editorMode and EditorApp.mousereleased then
    return EditorApp.mousereleased(x, y, button)
  end
  if mouseTouch then
    if Game and button == 1 then Game:touchreleased("mouse", x, y) end
    return
  end
  if Game then Game:mousereleased(x, y, button, istouch) end
end

function love.mousemoved(x, y, dx, dy, istouch)
  if not istouch then eventMouseX, eventMouseY = x, y end
  if TouchEditor then
    if love.system.getOS() == "Android" then return end
    return TouchEditor.mousemoved(x, y)
  end
  if Studio then return Studio.mousemoved(x, y) end
  if editorMode or Importer then return end
  if mouseTouch then
    if Game and love.mouse.isDown(1) then Game:touchmoved("mouse", x, y) end
    return
  end
  if Game then Game:mousemoved(x, y, dx, dy, istouch) end
end

function love.textinput(text)
  if TouchEditor then return end
  if Studio then return Studio.textinput(text) end
  if Importer then return Importer:textinput(text) end
  if editorMode and EditorApp.textinput then
    return EditorApp.textinput(text)
  end
end

-- #785: set once love.quit has routed a window close into HostShell.restart,
-- so the follow-up quit event the restart itself raises (quit("restart") on
-- desktop; AppImage and Android relaunch the process instead, #575) falls
-- through to the normal shutdown below instead of restarting forever.
local quitToLauncher = false

function love.quit()
  if editorMode and EditorApp.quit then
    -- true blocks the quit (unsaved-changes prompt).  A quit that proceeds
    -- must fall through to the worker shutdowns below instead of returning:
    -- the bundled editor opens from a live launcher whose update-check and
    -- fetch-pool workers are still parked in Channel:demand(), and returning
    -- here skipped their "quit" push, so the process outlived the closed
    -- window and kept the install folder locked on Windows (#727).
    if EditorApp.quit() then return true end
  end
  -- Closing the window of a running game returns to the launcher instead of
  -- exiting the app, so testing a mod does not need a relaunch every time
  -- (#785).  Game is only non-nil once bootGame ran; Importer non-nil means
  -- the launcher (or its import) owns the window and its close still quits.
  -- Scripted and headless runs (autopilot, frame driver, import-only, ROM
  -- path import) keep the plain exit so they terminate as before.  Nothing
  -- is saved here on purpose: a window close never wrote the save, and the
  -- restart path must be no worse than that, not quietly better.
  local scripted = os.getenv("POKEPORT_AUTOPILOT") or os.getenv("POKEPORT_DRIVER")
    or os.getenv("POKEPORT_IMPORT_ONLY") == "1" or os.getenv("POKEPORT_IMPORT_ROM")
  -- #887: a shortcut session (--game / POKEPORT_GAME) has no launcher to go
  -- back to and the restart would re-read the shortcut, so it exits instead.
  --
  -- A platform launcher that owns "return to launcher" itself (see
  -- docs/modding.md's core.quit_to_launcher entry) may veto returning to
  -- this Lua launcher via that hook. Vanilla behavior (used when no mod
  -- claims the hook) is exactly the condition below.
  local isAndroid = (love.system and love.system.getOS and love.system.getOS() == "Android")
  local wouldReturnToLauncher = PlatformHooks.quitToLauncher(function()
    return Game and not Importer and not quitToLauncher and not scripted
      and (isAndroid or not launchedIntoGame)
  end)
  if wouldReturnToLauncher then
    if isAndroid then
      returnToLauncher()
      return true -- abort this quit; the restart lands back in the launcher
    end
    quitToLauncher = true
    -- Tell the fresh boot to ignore any boot-straight-into-a-game option this
    -- once, so the restart really does land in the launcher (#887).  A failed
    -- write only costs that suppression, so it must never block the restart.
    pcall(love.filesystem.write, RELAUNCH_MARKER, "1")
    require("src.core.HostShell").restart()
    return true -- abort this quit; the restart lands back in the launcher
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
  -- The launcher's fetch pool is the same story: its workers idle in
  -- Channel:demand(), which never returns on its own, so a launcher that ever
  -- touched the network would hang the process on exit (#339's shape again).
  if package.loaded["src.net.Fetch"] then
    pcall(package.loaded["src.net.Fetch"].shutdown)
  end
end

function love.filedropped(file)
  if editorMode and EditorApp and EditorApp.filedropped then
    return EditorApp.filedropped(file)
  end
  if Studio then return Studio.filedropped(file) end
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
