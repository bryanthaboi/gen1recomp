-- Native LÖVE2D port of Pokemon Red. A packaged build creates its private
-- game-data cache from a user-provided ROM on first boot.
--
-- The save editor (tools/save-editor/) ships inside every build and is
-- reachable two ways:
--   * standalone: POKEPORT_EDITOR=1 or `love . --editor`, its own window
--   * from the launcher: Edit on a save row, which suspends the launcher,
--     opens the editor on that slot's file, and restores the launcher when
--     the editor's Close button is pressed (openEditor / closeEditor below)

local SwitchDiagnostics = require("src.debug.SwitchDiagnostics")

-- Global emergency quit: holding Start + Select for 5 seconds forcefully terminates LOVE.
local emergencyQuitTimer = 0
-- getJoysticks() allocates a fresh table every call; this runs once per
-- frame (from love.run, before love.update), so cache the list and refresh
-- it once a second instead.  The 5s hold requirement makes a 1s hotplug
-- delay irrelevant.
local cachedJoysticks = nil
local joystickCacheAge = 1

local function checkEmergencyQuit(dt)
  local held = false
  joystickCacheAge = joystickCacheAge + (dt or 0.016)
  if love.joystick and love.joystick.getJoysticks then
    if not cachedJoysticks or joystickCacheAge >= 1 then
      cachedJoysticks = love.joystick.getJoysticks()
      joystickCacheAge = 0
    end
    for _, j in ipairs(cachedJoysticks) do
      if j:isGamepad() then
        local start = j:isGamepadDown("start")
        local selectBtn = j:isGamepadDown("back") or j:isGamepadDown("guide")
        if start and selectBtn then
          held = true
          break
        end
      else
        local bCount = j:getButtonCount()
        local s1 = (bCount >= 7 and j:isDown(7)) or (bCount >= 9 and j:isDown(9))
        local s2 = (bCount >= 8 and j:isDown(8)) or (bCount >= 10 and j:isDown(10))
        if s1 and s2 then
          held = true
          break
        end
      end
    end
  end

  if love.keyboard and love.keyboard.isDown then
    if (love.keyboard.isDown("escape") and love.keyboard.isDown("return"))
        or (love.keyboard.isDown("lalt") and love.keyboard.isDown("f4")) then
      held = true
    end
  end

  if held then
    emergencyQuitTimer = emergencyQuitTimer + (dt or 0.016)
    if emergencyQuitTimer >= 5.0 then
      print("[FORCE QUIT] Start + Select held for 5 seconds. Exiting forcefully.")
      pcall(function()
        if love.audio and love.audio.stop then love.audio.stop() end
        if love.window and love.window.close then love.window.close() end
      end)
      local exitFn = os["exit"]
      exitFn(0)
    end
  else
    emergencyQuitTimer = 0
  end
end

-- Install before the rest of the engine loads so startup failures also get
-- the crash report when the game's regular renderer is unavailable.
do
  local defaultErrorHandler = love.errorhandler or love.errhand
  function love.errorhandler(msg)
    local traceback = debug.traceback()
    if os.getenv("POKEPORT_DRIVER") then
      io.stdout:write("LUA ERROR: " .. tostring(msg) .. "\n" .. traceback .. "\n")
      io.stdout:flush()
      os.exit(3)
    end
    local ok, hint, source, report = pcall(SwitchDiagnostics.logLuaError, msg, traceback)
    local nativeMsg = tostring(msg)
    if ok then
      if source then nativeMsg = source .. "\n\n" .. nativeMsg end
      if hint then nativeMsg = nativeMsg .. "\n\n" .. hint end
    end

    local okScreen, CrashScreen = pcall(require, "src.debug.CrashScreen")
    if okScreen and report then
      local summaryOk, summary = pcall(CrashScreen.fallbackText, report)
      if summaryOk then nativeMsg = summary end
      if love.window and love.graphics and love.event then
        local function ready()
          local openOk, open = pcall(love.window.isOpen)
          local activeOk, active = pcall(love.graphics.isActive)
          return openOk and open and activeOk and active
        end
        local variant
        if ready() then
          variant = "red"
        elseif love.window.setMode then
          -- Match LÖVE's native fallback: open a usable window after a
          -- startup failure, using the same plain-language layout.
          local modeOk, opened = pcall(love.window.setMode, 800, 600)
          if modeOk and opened and ready() then variant = "blue" end
        end
        if variant then
          local prepared, screen = pcall(CrashScreen.new, report, variant)
          if prepared and screen then
            local fallbackLoop
            return function()
              if fallbackLoop then return fallbackLoop() end
              local drawn, result = pcall(function()
                love.event.pump()
                for e, a, b, c, d, touchMouse in love.event.poll() do
                  if e == "quit" or (e == "keypressed" and a == "escape") then
                    return 1
                  elseif e == "gamepadpressed" and (b == "start" or b == "back") then
                    return 1
                  elseif e == "mousepressed" and c == 1 and not d
                      and CrashScreen.hitClose(screen, a, b) then
                    return 1
                  elseif e == "touchpressed" and CrashScreen.hitClose(screen, b, c) then
                    return 1
                  elseif e == "mousepressed" and c == 1 and not d then
                    CrashScreen.pointerPressed(screen, "mouse", a, b)
                  elseif e == "mousereleased" and c == 1 and not d then
                    CrashScreen.pointerReleased(screen, "mouse")
                  elseif e == "mousemoved" and not touchMouse then
                    CrashScreen.pointerMoved(screen, "mouse", a, b)
                  elseif e == "touchpressed" then
                    CrashScreen.pointerPressed(screen, a, b, c)
                  elseif e == "touchmoved" then
                    CrashScreen.pointerMoved(screen, a, b, c)
                  elseif e == "touchreleased" then
                    CrashScreen.pointerReleased(screen, a)
                  elseif e == "wheelmoved" then
                    CrashScreen.scroll(screen, -b * 3 * (screen.lineHeight or 16))
                  elseif e == "keypressed" and (a == "up" or a == "down") then
                    CrashScreen.scroll(screen,
                      (a == "down" and 1 or -1) * (screen.lineHeight or 16))
                  elseif e == "keypressed" and (a == "pageup" or a == "pagedown") then
                    CrashScreen.scroll(screen, (a == "pagedown" and 1 or -1)
                      * ((screen.detailArea and screen.detailArea.h) or 64))
                  elseif e == "keypressed" and (a == "home" or a == "end") then
                    CrashScreen.scrollTo(screen, a == "end")
                  elseif e == "gamepadpressed" and (b == "dpup" or b == "dpdown") then
                    CrashScreen.scroll(screen,
                      (b == "dpdown" and 1 or -1) * 3 * (screen.lineHeight or 16))
                  elseif e == "keypressed" and a == "c" and screen.canCopy
                      and love.keyboard.isDown("lctrl", "rctrl") then
                    local copyOk, copied = pcall(love.system.setClipboardText,
                      report.logPath)
                    if copyOk and copied ~= false then screen.copied = true end
                  end
                end
                checkEmergencyQuit(0.016)
                CrashScreen.draw(screen)
                love.graphics.present()
                if love.timer then love.timer.sleep(0.016) end
              end)
              if drawn then return result end
              if defaultErrorHandler then
                local fallbackOk, loop = pcall(defaultErrorHandler, nativeMsg)
                if fallbackOk and type(loop) == "function" then
                  fallbackLoop = loop
                  return fallbackLoop()
                end
              end
              return 1
            end
          end
        end
      end
    end

    if defaultErrorHandler then
      return defaultErrorHandler(nativeMsg)
    end
  end
  love.errhand = love.errorhandler
end

if POKEPORT_DISPLAY_COMPANION then
  return require("src.render.DesktopCompanion").install(
    POKEPORT_DISPLAY_COMPANION)
end

local editorMode = os.getenv("POKEPORT_EDITOR") == "1" or POKEPORT_EDITOR_MODE == true

local PadHints = require("src.core.PadHints")
local LaunchOptions = require("src.core.LaunchOptions")
local NxDisplay = require("src.core.NxDisplay")
local PlatformHooks = require("src.core.PlatformHooks")
local HostDisplay = require("src.core.HostDisplay")
local GameViewport = require("src.render.GameViewport")

local function applySavedOrientation()
  local ok, savedOptions = pcall(function()
    return require("src.core.SaveData").loadOptions()
  end)
  if not ok or type(savedOptions) ~= "table" then savedOptions = {} end
  pcall(function()
    require("src.core.Orientation").applyOptions(savedOptions)
  end)
end

local function applySavedAudioMode()
  local ok, savedOptions = pcall(function()
    return require("src.core.SaveData").loadOptions()
  end)
  if not ok or type(savedOptions) ~= "table" then savedOptions = {} end
  local mode = savedOptions.audioMode or "both"
  if love and love.audio and love.audio.setMixWithSystem then
    pcall(love.audio.setMixWithSystem, mode ~= "game_only")
  end
end

local Game, EditorApp, Importer, TouchEditor, Studio, Prelaunch
local launcherSplash

local function splashBlocksInput()
  return launcherSplash ~= nil and launcherSplash:blocksInput()
end

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
local launchOptionsSuppressed = false
local quitToLauncher = false
local processEnded = false

local function endProcessOnce()
  if processEnded then return end
  processEnded = true
  pcall(function()
    require("src.core.DiscordPresence").shutdown()
  end)
  require("src.core.SessionLifecycle").endProcess()
end

local function readRelaunchHandoff()
  if not love.filesystem.getInfo(RELAUNCH_MARKER) then return nil end
  local raw = love.filesystem.read(RELAUNCH_MARKER)
  pcall(love.filesystem.remove, RELAUNCH_MARKER)
  local data = require("src.core.SaveSerializer").decode(raw or "",
    { maxBytes = 65536 })
  return type(data) == "table" and data or {}
end

local onlineClient, onlineClientResolved
local function onlineClientModule()
  if onlineClientResolved then return onlineClient end
  onlineClientResolved = true
  local ok, mod = pcall(require, "src.online.Client")
  if ok and type(mod) == "table" and type(mod.update) == "function" then
    onlineClient = mod
  end
  return onlineClient
end

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
  local speed = Game and Game.driverSpeed or speedOverride
  return math.max(1, math.floor(require("src.core.GameSpeed").clamp(speed)))
end

-- ------------------------------------------------------------ save editor
-- The launcher instance parked while the editor is up, plus the version whose
-- cache the editor mounted (so closing can put the read path back).
local editorHost, editorVersion, editorWindow
local closeEditor  -- forward declaration: openEditor hands it to the editor

-- Drop CacheFs / Data / mod Runtime / Assets / LegacyCompat for one mounted
-- version session (save editor or game).  closeEditor and returnToLauncher
-- both go through SessionLifecycle so neither path forgets a singleton.
local SessionLifecycle = require("src.core.SessionLifecycle")

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
  local recovered, recoveryError, recoveryNotice = require("src.box.Transaction").recover(SaveData.persistenceFs())
  if not recovered then refuse(recoveryError); return end
  if recoveryNotice then
    require("src.core.Logger").warn("%s", recoveryNotice)
    if Importer and Importer._boxState then Importer._boxState.notice = recoveryNotice end
  end
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
    SessionLifecycle.endEditorSession({ version = version, app = nil })
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
    SessionLifecycle.endEditorSession({ version = version, app = nil })
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
-- with this one's data.  Also reset Runtime / Assets / LegacyCompat so the
-- next Edit or Play does not inherit the editor's dead mod loader.
function closeEditor()
  local version = editorVersion
  local app = EditorApp
  editorMode = false
  EditorApp = nil
  SessionLifecycle.endEditorSession({ version = version, app = app })
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

local function makeLauncher(launcherOpts)
  require("src.import.LauncherWindow").activate()
  local RomImporter = require("src.import.RomImporter")
  local forceImport = os.getenv("POKEPORT_FORCE_IMPORT") == "1"
  return RomImporter.new(function(version, cartId, opts)
    require("src.import.LauncherWindow").observe(0)
    require("src.import.LauncherWindow").flush()
    Importer = nil
    local onBoot = launcherOpts and launcherOpts.onBoot
    if onBoot and onBoot(version, cartId, opts) then return end
    bootGame(version, cartId, opts)
  end, {
    launcher = true,
    forceImport = forceImport,
    initialTab = launcherOpts and launcherOpts.initialTab or nil,
    invite = launcherOpts and launcherOpts.invite or nil,
    onEditSave = openEditor,
    onEditTouchControls = openTouchControlsEditor,
    -- Skin Studio owns a touch-first layout as well as the desktop workspace.
    -- Keep the compatibility predicate so external hosts using it still work.
    onOpenSkinStudio = require("src.ui.SkinStudio").available_desktop()
      and openSkinStudio or nil,
  })
end

local deferredLaunchRequest

local function rebuildLauncherInProcess(opts)
  if require("src.core.RequireGuard").repair() then
    print("boot: restored love.filesystem searcher (see #2001)")
  end

  local currentVersion = require("src.core.GameVersion").get()
  SessionLifecycle.endGameSession(Game)
  Game = nil
  pcall(function() require("src.online.Trade").hostIsLive = nil end)
  local syncEngine = package.loaded["src.sync.SyncEngine"]
  if type(syncEngine) == "table" and type(syncEngine._shared) == "table" then
    pcall(syncEngine._shared.protectPlaythrough, syncEngine._shared, nil, nil)
  end
  autopilot = nil
  driverCo = nil
  local SaveData = require("src.core.SaveData")
  local cartId = SaveData.getCart()
  SaveData.setCart(nil)
  require("src.core.GameSpeed").setAllowed(nil)

  SessionLifecycle.endMountedSession(currentVersion)
  SaveData.refreshSlotResolution(currentVersion)
  if cartId then SaveData.refreshSlotResolution("cart_" .. cartId) end

  applySavedOrientation()

  local preload = require("src.mods.LauncherMods").translationStrings()
  if preload then require("src.core.Strings").load({ strings = preload }) end

  if love.window and love.window.setTitle then
    local Version = require("src.core.Version")
    love.window.setTitle(Version.title("Gen 1 Recompilation Project"))
  end

  Importer = makeLauncher({ initialTab = opts.tab, invite = opts.invite })
  if Importer.ignoreReturningPointer then
    Importer:ignoreReturningPointer()
  end
  if type(opts.request) == "table" then deferredLaunchRequest = opts.request end
end

local function returnToLauncher(opts)
  if not Game or quitToLauncher then return end
  opts = opts or {}
  if not require("src.core.HostShell").canRestart() then
    return rebuildLauncherInProcess(opts)
  end
  quitToLauncher = true
  local handoff = { tab = opts.tab, invite = opts.invite, request = opts.request }
  local okEncode, body = pcall(require("src.core.SaveSerializer").encode, handoff)
  pcall(love.filesystem.write, RELAUNCH_MARKER, okEncode and body or "return {}\n")

  SessionLifecycle.endGameSession(Game)
  Game = nil
  autopilot = nil
  driverCo = nil
  endProcessOnce()
  if opts.restarting then return end
  require("src.core.HostShell").restart()
end

local pendingLauncherReturn
local driverHost = {
  returnToLauncher = function(o) pendingLauncherReturn = o or {} end,
}

function bootGame(version, cartId, opts)
  opts = opts or {}
  if require("src.core.RequireGuard").repair() then
    print("boot: restored love.filesystem searcher (see #2001)")
  end
  local recovered, recoveryError, recoveryNotice = require("src.box.Transaction").recover(
    require("src.core.SaveData").persistenceFs())
  if recoveryNotice then require("src.core.Logger").warn("%s", recoveryNotice) end
  if not recovered then
    Importer = makeLauncher({ initialTab = "box" })
    Importer._boxState = nil
    require("src.import.BoxPanel").refresh(Importer).notice = recoveryError
    return
  end
  pcall(function()
    require("src.online.Trade").hostIsLive = function() return true end
  end)
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
  local cartHash, cartSpeeds, cartOptions
  if cartId then
    local ok, cart, hash = pcall(function()
      return require("src.carts.CartStore").get(cartId)
    end)
    if ok and cart then
      cartHash, cartSpeeds, cartOptions = hash, cart.speeds, cart.options
    else
      cartId = nil
    end
  end
  local SaveData = require("src.core.SaveData")
  SaveData.setCart(cartId, cartHash)
  -- The author's settings land in the cart's own scope the first time only;
  -- after that the player owns them.
  if cartOptions then SaveData.seedCartOptions(cartOptions) end
  -- A cart may narrow or pin the speed ladder; nil restores the full one.
  require("src.core.GameSpeed").setAllowed(cartSpeeds)
  if cartId then SaveData.adoptCartSeal(cartId) end
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
  local arena = opts.arena
  local loadOpts = { arena = arena, cartId = cartId, onExit = opts.onExit }
  if GameVersion.generation() == 3 then
    Game = require("src.core.Game3").new()
    Game.returnToLauncher = function(o) pendingLauncherReturn = o or {} end
    Game:load(loadOpts)
  elseif GameVersion.generation() == 2 then
    Game = require("src.core.Game2").new()
    if arena then
      Game.returnToLauncher = function(o) pendingLauncherReturn = o or {} end
    end
    Game:load(loadOpts)
  else
    -- Gen1 Game is a module singleton.  Always re-require after in-process
    -- EXIT GAME so a prior session cannot leave a table whose rawget(load)
    -- is nil (release Android: bootGame then dies with load-a-nil-value).
    -- rawget: type(mod.load) can lie via __index and skip a rebuild.
    package.loaded["src.core.Game"] = nil
    local gameMod = require("src.core.Game")
    if type(rawget(gameMod, "load")) ~= "function" then
      error("src.core.Game missing load after reload")
    end
    Game = gameMod
    if arena then
      Game.returnToLauncher = function(o) pendingLauncherReturn = o or {} end
    end
    Game:load(loadOpts)
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

local function showLauncher(version)
  LaunchOptions.pendingTab = version
  if not Importer then
    Importer = makeLauncher({ initialTab = version })
  end
end

local function wantsModUpdate(request)
  if type(request) ~= "table" then return false end
  if type(request.tasks) == "table" and request.tasks.mods ~= nil then
    return request.tasks.mods == true
  end
  return request.updateMods == true
end

local function autoUpdateMods(request, tab)
  if not wantsModUpdate(request) then return end
  if Importer and Importer.autoUpdateAll then
    Importer:autoUpdateAll(function() end, { tab = tab })
  end
end

local function launcherBusy()
  return launcherSplash ~= nil or Importer ~= nil and (Importer._updateAll ~= nil
    or Importer._modInstall ~= nil or Importer._cartInstall ~= nil
    or Importer._autoUpdateAll ~= nil)
end

local function startLaunchRequest(request)
  if type(request) ~= "table" then return false end
  if launcherBusy() then
    deferredLaunchRequest = request
    return true
  end

  if Game then
    returnToLauncher({ request = request })
    return true
  end

  local version = request.game
  if request.launcher or not version then
    showLauncher(version)
    autoUpdateMods(request, not version and "mods" or nil)
    return true
  end

  local RomImporter = require("src.import.RomImporter")
  Importer = nil
  if Prelaunch then return true end

  local cartId
  if request.cartSpecified then
    local ok, cart = pcall(function()
      return require("src.carts.CartStore").get(request.cart)
    end)
    if not ok or type(cart) ~= "table" or cart.base ~= version then
      showLauncher(version)
      autoUpdateMods(request)
      return true
    end
    cartId = request.cart
  end

  if not RomImporter.isReady(version) then
    showLauncher(version)
    autoUpdateMods(request)
    return true
  end

  local function bootShortcut()
    if request.slot then LaunchOptions.selectSlot(version, request.slot) end
    launchedIntoGame = true
    bootGame(version, cartId)
  end

  local function bootAfterMods()
    if not wantsModUpdate(request) then return bootShortcut() end
    Importer = makeLauncher({ initialTab = "mods",
      onBoot = function(v, c, opts)
        if v ~= version or c ~= cartId or opts ~= nil then return false end
        bootShortcut()
        return true
      end })
    Importer:autoUpdateAll(function(result)
      if not (result.ok or result.cancelled or result.skipped) then return end
      require("src.import.LauncherWindow").observe(0)
      require("src.import.LauncherWindow").flush()
      Importer = nil
      bootShortcut()
    end)
  end

  Prelaunch = require("src.core.Prelaunch").new({
    version = version,
    tasks = request.tasks or {},
    done = function(outcome)
      if outcome == "restart" then return end
      Prelaunch = nil
      if outcome == "launcher" then
        showLauncher(version)
        return
      end
      bootAfterMods()
    end,
  })
  if not Prelaunch then bootAfterMods() end
  return true
end

function love.load(args)
  if os.getenv("POKEPORT_BACKGROUND") == "1" and love.audio then
    love.audio.setVolume(0)
    love.audio.setVolume = function() end
  end
  -- Before anything can shell out (update check, mod index, ROM picker),
  -- claim one hidden console on Windows so those children inherit it instead
  -- of each flashing their own cmd.exe window (#606).  No-op elsewhere.
  require("src.core.HostShell").hideHostConsole()

  require("src.core.RequireGuard").capture()

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
  pcall(function() require("src.core.GamepadMap").initGamepadMappings() end)
  -- NX: handheld 720p / docked 1080p. Runs for every boot path (launcher,
  -- editor, scripted); no-op on desktop/mobile.
  NxDisplay.sync()

  -- Apply the persisted Android orientation lock (#592) before the launcher
  -- shows: SDL created the window with no orientation hint, so without this
  -- the launcher would rotate freely until options are applied at boot.
  -- No-op on desktop / iOS / when options.lua does not exist yet.
  applySavedOrientation()
  applySavedAudioMode()

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
  local resolvedLaunch = LaunchOptions.resolveRequest(arg, args)
  local forceImport = os.getenv("POKEPORT_FORCE_IMPORT") == "1"
  local importPath = os.getenv("POKEPORT_IMPORT_ROM")
  -- Scripted / headless runs pick their game from POKEPORT_VERSION, then
  -- POKEPORT_GAME / --game= (LaunchOptions), then Red.  Drivers for Gold
  -- must honor POKEPORT_GAME=gold the same way a desktop shortcut does.
  local scriptedVersion = os.getenv("POKEPORT_VERSION")
    or resolvedLaunch.game
    or "red"
  local ready = RomImporter.isReady(scriptedVersion)
  -- Scripted / headless runs have to reach the game with no human pressing
  -- Play: an autopilot, a frame driver, an import-only build step, or an
  -- explicit ROM path all bypass the interactive launcher and keep today's
  -- import-then-boot (or boot-straight-in) behavior.
  local scripted = os.getenv("POKEPORT_AUTOPILOT") or os.getenv("POKEPORT_DRIVER")
    or os.getenv("POKEPORT_IMPORT_ONLY") == "1" or importPath ~= nil

  local scriptedOpts = nil
  local specPath = os.getenv("POKEPORT_ARENA_SPEC")
  if specPath and os.getenv("POKEPORT_DRIVER") then
    local chunk, chunkErr = loadfile(specPath)
    if not chunk then error("POKEPORT_ARENA_SPEC: " .. tostring(chunkErr)) end
    local spec = chunk()
    if type(spec) ~= "table" then
      error("POKEPORT_ARENA_SPEC must return an ArenaSpec table")
    end
    scriptedOpts = { arena = spec }
  end

  local handoff = readRelaunchHandoff()
  local relaunched = handoff ~= nil
  if relaunched and os.getenv("POKEPORT_DRIVER") then scripted = nil end

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
        bootGame(version or scriptedVersion, nil, scriptedOpts)
      end)
      if importPath then Importer:startPath(importPath) end
      return
    end
    local scriptedCart = os.getenv("POKEPORT_CART")
    bootGame(scriptedVersion, scriptedCart ~= "" and scriptedCart or nil, scriptedOpts)
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
  if relaunched then launchOptionsSuppressed = true end

  if not relaunched and resolvedLaunch.game and not resolvedLaunch.launcher
      and startLaunchRequest(resolvedLaunch) then
    return
  end
  if not relaunched and resolvedLaunch.launcher and resolvedLaunch.game then
    LaunchOptions.pendingTab = resolvedLaunch.game
  end

  -- Interactive: the launcher always runs.  Red, Blue, Yellow, and Gold are
  -- each live: a column shows Play when that game's ROM is already imported,
  -- or Choose ROM / drag-drop when it is not.  Any dropped .gb/.gbc is routed
  -- by its SHA-1 (GameVersion.forSha1); pressing Play boots that game (Gold
  -- goes to its own service owner, src/core/Game2.lua -- docs/gold-phase1.md).
  -- Edit on a save row opens the bundled editor on that slot (openEditor).
  if not relaunched then
    Importer = makeLauncher()
    launcherSplash = require("src.import.LauncherSplash").new()
    autoUpdateMods(resolvedLaunch,
      not resolvedLaunch.game and "mods" or nil)
    return
  end
  Importer = makeLauncher({
    initialTab = type(handoff.tab) == "string" and handoff.tab or nil,
    invite = type(handoff.invite) == "string" and handoff.invite or nil,
  })
  if Importer.ignoreReturningPointer then Importer:ignoreReturningPointer() end
  local driverPath = os.getenv("POKEPORT_DRIVER")
  if driverPath then
    driverCo = coroutine.create(assert(loadfile(driverPath))())
  end
  if type(handoff.request) == "table" then startLaunchRequest(handoff.request) end
end

function love.update(dt)
  -- checkEmergencyQuit runs from love.run each frame; calling it here too
  -- would double-count dt and fire the 5s hold after 2.5s.
  HostDisplay.update(dt)
  SwitchDiagnostics.maybeFlush(false)
  -- NX only (no-op elsewhere): follow dock/undock without waiting for SDL.
  NxDisplay.sync()
  if launcherSplash then
    if not launcherSplash.inputResumed and not launcherSplash:blocksInput() then
      launcherSplash.inputResumed = true
      if Importer and Importer.resumeAfterOverlay then Importer:resumeAfterOverlay() end
    end
    if launcherSplash:update(dt) then
      launcherSplash:release()
      launcherSplash = nil
    end
  end
  if editorMode then return EditorApp.update(dt) end
  if TouchEditor then return TouchEditor.update(dt) end
  if Studio then return Studio.update(dt) end
  local launchURI = LaunchOptions.pollURI()
  if launchURI then love.handlers.intent_uri(launchURI) end
  if deferredLaunchRequest and not launcherBusy() then
    local request = deferredLaunchRequest
    deferredLaunchRequest = nil
    startLaunchRequest(request)
  end
  if Prelaunch then return Prelaunch:update(dt) end
  local connect = package.loaded["src.online.Connect"]
  if connect then pcall(connect.update, dt) end
  local client = onlineClientModule()
  if client then pcall(client.update, dt) end
  if pendingLauncherReturn then
    local opts = pendingLauncherReturn
    pendingLauncherReturn = nil
    returnToLauncher(opts)
    return
  end
  if Importer then
    require("src.import.LauncherWindow").observe(dt)
    Importer._inputBlocked = splashBlocksInput()
    if driverCo and not Game then
      local ok, err = coroutine.resume(driverCo, Importer)
      if not ok then
        print("driver error: " .. tostring(err))
        love.event.quit(1)
        return
      end
      if coroutine.status(driverCo) == "dead" then
        love.event.quit()
        return
      end
    end
    return Importer:update(dt)
  end
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
    local i = 0
    while i < iterations do
      i = i + 1
      local ok, err = coroutine.resume(driverCo, Game, driverHost)
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
      iterations = math.min(iterations, scriptedIterations())
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
  if Prelaunch then
    GameViewport.reset()
    return Prelaunch:draw()
  end
  if Importer then
    GameViewport.reset()
    HostDisplay.beginFrame("launcher", Importer)
    local result = Importer:draw()
    if launcherSplash then launcherSplash:draw() end
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
  if splashBlocksInput() then return end
  if editorMode then return EditorApp.keypressed(key) end
  if TouchEditor then return TouchEditor.keypressed(key) end
  if Studio then return Studio.keypressed(key) end
  if Prelaunch then return Prelaunch:cancel() end
  if Importer then return Importer:keypressed(key) end
  if not Game then return end
  Game:keypressed(key)
end

function love.keyreleased(key)
  if splashBlocksInput() then return end
  if editorMode or TouchEditor or Studio then return end
  if Importer then return end
  if not Game then return end
  Game:keyreleased(key)
end

function love.gamepadpressed(joystick, button)
  if splashBlocksInput() then return end
  SwitchDiagnostics.onJoystickEvent("gamepadpressed", joystick, button)
  if PadHints.windowMinimized() then return end
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
  if Studio then return Studio.gamepadpressed(joystick, button) end
  if Prelaunch then return Prelaunch:cancel() end
  if Importer then return Importer:gamepadpressed(joystick, button) end
  if not Game then return end
  Game:gamepadpressed(joystick, button)
end

function love.gamepadreleased(joystick, button)
  if splashBlocksInput() then return end
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
  if Studio then return Studio.gamepadreleased(joystick, button) end
  if Importer then return Importer:gamepadreleased(joystick, button) end
  if not Game then return end
  Game:gamepadreleased(joystick, button)
end

function love.gamepadaxis(joystick, axis, value)
  if splashBlocksInput() then return end
  SwitchDiagnostics.onJoystickEvent("gamepadaxis", joystick, axis, { value = value })
  if PadHints.windowMinimized() then value = 0 end
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
  if Studio then return Studio.gamepadaxis(joystick, axis, value) end
  if Importer then return Importer:gamepadaxis(joystick, axis, value) end
  if not Game then return end
  Game:gamepadaxis(joystick, axis, value)
end

function love.joystickpressed(joystick, button)
  if splashBlocksInput() then return end
  SwitchDiagnostics.onJoystickEvent("joystickpressed", joystick, button)
  if PadHints.windowMinimized() then return end
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
  if Studio then return Studio.joystickpressed(joystick, button) end
  if Importer then return Importer:joystickpressed(joystick, button) end
  if not Game then return end
  Game:joystickpressed(joystick, button)
end

function love.joystickreleased(joystick, button)
  if splashBlocksInput() then return end
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
  if Studio then return Studio.joystickreleased(joystick, button) end
  if Importer then return Importer:joystickreleased(joystick, button) end
  if not Game then return end
  Game:joystickreleased(joystick, button)
end

function love.joystickaxis(joystick, axis, value)
  if splashBlocksInput() then return end
  SwitchDiagnostics.onJoystickEvent("joystickaxis", joystick, axis, { value = value })
  if PadHints.windowMinimized() then value = 0 end
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
  if Studio then return Studio.joystickaxis(joystick, axis, value) end
  if Importer then return Importer:joystickaxis(joystick, axis, value) end
  if not Game then return end
  Game:joystickaxis(joystick, axis, value)
end

function love.joystickhat(joystick, hat, direction)
  if splashBlocksInput() then return end
  SwitchDiagnostics.onJoystickEvent("joystickhat", joystick, hat, { direction = direction })
  if PadHints.windowMinimized() then direction = "c" end
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
  if Studio then return Studio.joystickhat(joystick, hat, direction) end
  if Importer then return Importer:joystickhat(joystick, hat, direction) end
  if not Game then return end
  Game:joystickhat(joystick, hat, direction)
end

-- The joystick lists cached for polling (checkEmergencyQuit's, Input's
-- pollPads) are only refreshed on a count change or a timer otherwise, which
-- a controller swapped for another can slip past.
local function noteJoysticksChanged()
  cachedJoysticks = nil
  local input = Game and Game.input
  if type(input) == "table" and input.joysticksChanged then
    input:joysticksChanged()
  end
end

function love.joystickadded(joystick)
  SwitchDiagnostics.onJoystickEvent("joystickadded", joystick)
  noteJoysticksChanged()
  if editorMode or TouchEditor or Studio then return end
  if Importer then return end
  if not Game then return end
  Game:joystickadded(joystick)
end

function love.joystickremoved(joystick)
  SwitchDiagnostics.onJoystickEvent("joystickremoved", joystick)
  noteJoysticksChanged()
  if editorMode or TouchEditor or Studio then return end
  if Importer then return end
  if not Game then return end
  Game:joystickremoved(joystick)
end

-- f is true on focus gained, false on focus lost (e.g. alt-tab). A held
-- direction's key-up can be delivered to the OS instead of the game while
-- unfocused, so reset input on either transition rather than trust it.
function love.focus(f)
  SwitchDiagnostics.onFocus(f)
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
  local BoxCry = package.loaded["src.box.Cry"]
  if BoxCry then pcall(BoxCry.setSuspended, true) end
  local ChipAudio = package.loaded["src.core.ChipAudio"]
  if ChipAudio then pcall(ChipAudio.setSuspended, true) end
  local Sound = package.loaded["src.core.Sound"]
  if Sound then pcall(Sound.onDeviceReset) end
  local Game3Audio = package.loaded["src.core.game3.audio"]
  if Game3Audio then pcall(Game3Audio.setSuspended, true) end
end

function love.handlers.audioreset()
  local BoxCry = package.loaded["src.box.Cry"]
  if BoxCry then pcall(BoxCry.setSuspended, false) end
  local ChipAudio = package.loaded["src.core.ChipAudio"]
  if ChipAudio then
    pcall(ChipAudio.setSuspended, false)
    pcall(ChipAudio.rebuildPlayback)
  end
  local Music = package.loaded["src.core.Music"]
  if Music then pcall(Music.onDeviceReset) end
  local Sound = package.loaded["src.core.Sound"]
  if Sound then pcall(Sound.onDeviceReset) end
  local Game3Audio = package.loaded["src.core.game3.audio"]
  if Game3Audio then
    pcall(Game3Audio.setSuspended, false)
    pcall(Game3Audio.rebuildPlayback)
  end
end

function love.handlers.intent_game(version)
  local request = LaunchOptions.fromGame(version)
  if request then startLaunchRequest(request) end
end

function love.handlers.intent_uri(uri)
  local request = LaunchOptions.parseURI(uri)
  if request then
    startLaunchRequest(request)
  elseif LaunchOptions.isLaunchURI(uri) then
    startLaunchRequest({})
  end
end

function love.touchpressed(id, x, y, dx, dy, pressure)
  if splashBlocksInput() then return end
  if editorMode then
    if EditorApp and EditorApp.touchpressed then return EditorApp.touchpressed(id,x,y) end
    return
  end
  if TouchEditor then
    -- iOS synthesizes mousepressed for the primary touch (same as the
    -- launcher); Android drives the editor through love.touch directly.
    if love.system.getOS() == "iOS" then return end
    return TouchEditor.touchpressed(id, x, y)
  end
  if Studio then return Studio.touchpressed(id, x, y) end
  if Prelaunch then return Prelaunch:cancel() end
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
  if splashBlocksInput() then return end
  if editorMode then return EditorApp.touchmoved(id,x,y) end
  if TouchEditor then
    if love.system.getOS() == "iOS" then return end
    return TouchEditor.touchmoved(id, x, y)
  end
  if Studio then return Studio.touchmoved(id, x, y) end
  if Importer then
    return Importer:touchmoved(id, x, y, dx, dy, pressure)
  end
  if not Game then return end
  Game:touchmoved(id, x, y, dx, dy, pressure)
end

function love.touchreleased(id, x, y, dx, dy, pressure)
  if splashBlocksInput() then return end
  if editorMode then return EditorApp.touchreleased(id,x,y) end
  if TouchEditor then
    if love.system.getOS() == "iOS" then return end
    return TouchEditor.touchreleased(id, x, y)
  end
  if Studio then return Studio.touchreleased(id, x, y) end
  if Importer then
    return Importer:touchreleased(id, x, y, dx, dy, pressure)
  end
  if not Game then return end
  Game:touchreleased(id, x, y, dx, dy, pressure)
end

function love.wheelmoved(x, y)
  if splashBlocksInput() then return end
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
  if splashBlocksInput() then return end
  if not istouch then eventMouseX, eventMouseY = x, y end
  if TouchEditor then
    -- Android primary touch already arrived via love.touchpressed; a second
    -- mouse path would double-fire Done / begin a second drag.
    if love.system.getOS() == "Android" then return end
    return TouchEditor.mousepressed(x, y, button)
  end
  if Studio then
    -- Mobile LÖVE sends both a touch event and an `istouch` mouse twin.
    -- Studio consumes the real finger stream above, so discard the twin.
    if istouch and (love.system.getOS() == "Android" or love.system.getOS() == "iOS") then return end
    return Studio.mousepressed(x, y, button)
  end
  if Prelaunch then
    if istouch then return end
    return Prelaunch:cancel()
  end
  if Importer then
    -- love.touchpressed already forwards the primary touch into FlexLove for
    -- scroll. LÖVE ALSO synthesizes a mouse press for that same touch; if both
    -- reached a press handler, one tap ran every launcher button twice and
    -- stacked two SAF pickers (#553). Clicks are polled inside FlexLove from
    -- love.touch / mouse.isDown, so dropping the synthesized istouch press is
    -- safe. A real mouse (DeX, Chromebook, USB) still reaches mousepressed.
    return Importer:mousepressed(x, y, button, istouch)
  end
  if editorMode and EditorApp.mousepressed then
    -- The editor owns the real touch lifecycle on Android and iOS.
    -- Discard its synthetic mouse twin to avoid a second activation.
    if istouch then return end
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
  if splashBlocksInput() then return end
  if TouchEditor then
    if love.system.getOS() == "Android" then return end
    return TouchEditor.mousereleased(x, y, button)
  end
  if Studio then
    if istouch and (love.system.getOS() == "Android" or love.system.getOS() == "iOS") then return end
    return Studio.mousereleased(x, y, button)
  end
  if Importer then return Importer:mousereleased(x, y, button, istouch) end
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
  if splashBlocksInput() then return end
  if not istouch then eventMouseX, eventMouseY = x, y end
  if TouchEditor then
    if love.system.getOS() == "Android" then return end
    return TouchEditor.mousemoved(x, y)
  end
  if Studio then
    if istouch and (love.system.getOS() == "Android" or love.system.getOS() == "iOS") then return end
    return Studio.mousemoved(x, y)
  end
  if Importer then return Importer:mousemoved(x, y, dx, dy, istouch) end
  if editorMode then return end
  if mouseTouch then
    if Game and love.mouse.isDown(1) then Game:touchmoved("mouse", x, y) end
    return
  end
  if Game then Game:mousemoved(x, y, dx, dy, istouch) end
end

function love.textinput(text)
  if splashBlocksInput() then return end
  if TouchEditor then return end
  if Studio then return Studio.textinput(text) end
  if Importer then return Importer:textinput(text) end
  if editorMode and EditorApp.textinput then
    return EditorApp.textinput(text)
  end
end

function love.quit()
  if launcherSplash then launcherSplash:release(); launcherSplash = nil end
  if Importer and Importer._themeVideo then
    pcall(Importer._themeVideo.release, Importer._themeVideo)
    Importer._themeVideo = nil
  end
  if Importer then
    require("src.import.LauncherWindow").observe(0)
    require("src.import.LauncherWindow").flush()
  end
  local osName = love.system and love.system.getOS and love.system.getOS()
  if osName == "NX" then
    endProcessOnce()
    return
  end
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
  local mobile = (osName == "Android" or osName == "iOS")
  local wouldReturnToLauncher = PlatformHooks.quitToLauncher(function()
    return Game and not Importer and not quitToLauncher and not scripted
      and (mobile or not launchedIntoGame)
  end)
  if wouldReturnToLauncher then
    local HostShell = require("src.core.HostShell")
    if HostShell.restarting and HostShell.canRestart() then
      returnToLauncher({ restarting = true })
    else
      returnToLauncher()
      return true
    end
  end
  endProcessOnce()
end

function love.filedropped(file)
  if splashBlocksInput() then return end
  local filename = file and file.getFilename and file:getFilename()
  if LaunchOptions.isLaunchURI(filename) then
    local request = LaunchOptions.parseURI(filename)
    if launchOptionsSuppressed then return end
    startLaunchRequest(request or {})
    return
  end
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

-- Shane #1830 idle render governor (POKEPORT_IDLE_*): drop presentation rate
-- on static in-game screens; game logic and audio stay at full speed.
local function idlePresentationCap(idleFor)
  if Importer then return 30 end
  local after = tonumber(os.getenv("POKEPORT_IDLE_AFTER"))
  local fps = tonumber(os.getenv("POKEPORT_IDLE_FPS"))
  if not after or after <= 0 or not fps or fps <= 0 then return nil end
  if idleFor < after then return nil end
  if Importer or Prelaunch or editorMode or not Game then return nil end
  return fps
end

function love.run()
  _G.POKEPORT_LOOP_RESTART = true
  if love.load then love.load(love.arg.parseGameArguments(arg), arg) end

  -- don't let love.load's cost land in the first frame's dt
  if love.timer then love.timer.step() end

  local FrameCap = require("src.core.FrameCap")
  _G.POKEPORT_LOOP_PANEL_SYNC = true
  FrameCap.bootPanelSync()
  local RefreshRate = require("src.core.RefreshRate")
  local FixedStep = require("src.core.FixedStep")
  local VSync = require("src.core.VSync")
  local PresentSync = require("src.core.PresentSync")
  local paced = pacingEnabled()
  -- The deadline the next present() should not beat.  Carried forward one
  -- budget per frame so pacing stays even instead of drifting with the
  -- per-frame sleep-granularity jitter.
  local nextFrame = love.timer and love.timer.getTime() or 0
  local dt = 0
  local idleFor = 0
  local SLEEP_FLOOR = 0.001
  -- Sleep until deadline with one or two kernel waits, not 1 ms polling.
  local function sleepUntilFrame(deadline)
    while true do
      local remaining = deadline - love.timer.getTime()
      if remaining <= SLEEP_FLOOR then break end
      if remaining > 0.004 then
        love.timer.sleep(remaining - 0.002)
      else
        love.timer.sleep(remaining)
      end
    end
  end
  local WAKE = {
    keypressed = true, keyreleased = true, textinput = true,
    mousepressed = true, mousereleased = true, mousemoved = true,
    wheelmoved = true, touchpressed = true, touchreleased = true,
    touchmoved = true, joystickpressed = true, joystickreleased = true,
    joystickhat = true, gamepadpressed = true, gamepadreleased = true,
    joystickadded = true, joystickremoved = true, filedropped = true,
    directorydropped = true, focus = true, visible = true, resize = true,
  }

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
            if a ~= "restart" and love.system and love.system.getOS() == "Android" then
              os.exit(a or 0)
            end
            return a or 0
          end
        end
        if WAKE[name] then
          idleFor = 0
        elseif name == "joystickaxis" and type(c) == "number" and math.abs(c) > 0.5 then
          idleFor = 0
        end
        if name == "focus" and a then
          PresentSync.onDisplayChange()
        elseif name == "resize" then
          PresentSync.onDisplayChange()
        end
        love.handlers[name](a, b, c, d, e, f)
      end
    end

    -- update dt
    if love.timer then dt = love.timer.step() end
    idleFor = idleFor + dt
    RefreshRate.sample(dt)

    checkEmergencyQuit(dt)

    -- call update and draw
    if love.update then love.update(dt) end

    local visible = not (love.window and love.window.isVisible)
      or love.window.isVisible()
    local focused = not (love.window and love.window.hasFocus)
      or love.window.hasFocus()
    local cap = FrameCap.current
    if not visible then
      cap = 10
    elseif Importer and (not focused or idleFor > 30) then
      cap = 15
    else
      local idleCap = idlePresentationCap(idleFor)
      if idleCap then cap = idleCap end
    end
    if cap == FrameCap.DISPLAY and not VSync.isOn() then
      cap = FrameCap.DEFAULT
    elseif cap == FrameCap.DISPLAY and PresentSync.needsSoftwareCap() then
      -- Fallback cascade: probe failed / wait abandoned / sync non-
      -- deterministic → FrameCap is the live pacing path on every OS.
      -- (During an active probe we intentionally leave DISPLAY uncapped so
      -- calibration is not grading our own limiter.)
      cap = FrameCap.DEFAULT
    end

    if visible and love.graphics and love.graphics.isActive() then
      love.graphics.origin()
      love.graphics.clear(love.graphics.getBackgroundColor())
      if love.draw then love.draw() end
      PresentSync.waitBeforePresent()
      love.graphics.present()
      PresentSync.notePresent()
    end

    PresentSync.applyFixedStepPeriod()

    if love.timer then
      if paced and cap ~= FrameCap.DISPLAY and not PresentSync.hardwarePacesCap(cap) then
        -- Sleep out the remainder of the frame budget, measured from the
        -- carried deadline.  When vsync already gates at or above the cap,
        -- hardwarePacesCap skips this entirely.  Otherwise one kernel sleep
        -- covers the bulk; only the last couple ms re-check for overshoot.
        local budget = 1 / cap
        nextFrame = nextFrame + budget
        local now = love.timer.getTime()
        -- A stall (alt-tab, a GC pause, a blocked import) can leave the
        -- deadline more than a full budget in the past; re-anchor to now so
        -- we pace the next frame rather than burst uncapped to catch up.
        if now - nextFrame > budget then
          nextFrame = now
        end
        sleepUntilFrame(nextFrame)
      else
        love.timer.sleep(0.001)
      end
    end
  end
end
