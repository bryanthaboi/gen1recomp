-- Save editor app shell.  Boots the game's generated Data plus a save file
-- and draws the chrome the design spec fixes (SaveEditor.dc.html): a version
-- rail, a title bar, a tab rail and a status bar, with one panel filling the
-- space between.  Panels own their tab's content; this module owns everything
-- around it.
--
-- The editor is reachable two ways and behaves the same in both:
--   * `love . --editor`      standalone window, Close quits
--   * Edit on a launcher save row (main.lua, embedded = true), Close returns
--     to the launcher with the slot list refreshed
--
-- Chrome reflows inside the platform safe area. Phones use a compact action
-- menu and popup page choosers; wide windows keep actions on one row. Each page
-- owns its scrolling viewport and slides with the launcher's navigation.

local Data = require("src.core.Data")
local SafeArea = require("src.core.SafeArea")
local TileRenderer = require("src.render.TileRenderer")
local SaveIO = require("SaveIO")
local Catalog = require("Catalog")
local State = require("State")
local Kit = require("Kit")
local Theme = require("Theme")
local Ops = require("Ops")
local Gen = require("Gen")
local PadInput = require("PadInput")
local GamepadMap = require("src.core.GamepadMap")
local VirtualKeyboard = require("src.ui.kit.VirtualKeyboard")
local Motion = require("Motion")
local Chooser = require("Chooser")
local Toast = require("src.ui.kit.Toast")
local PAL = Theme.PAL
local toastArea = {}
local toastSlots = {}

local function placeClearOfControls(x, w, h)
  local rects, n = Kit.trackedControls()
  local gap = 12 * toastSlots.s
  local best, bestHits, bestAbove
  local function try(y, fromAbove, limit)
    if y < toastSlots.minY or y + h > (limit or toastSlots.maxY) then return end
    local hits = 0
    for i = 1, n do
      local r = rects[i]
      if r[1] < x + w and r[1] + r[3] > x and r[2] < y + h and r[2] + r[4] > y then hits = hits + 1 end
    end
    if not best or hits < bestHits then best, bestHits, bestAbove = y, hits, fromAbove end
  end
  local fr = toastSlots.field
  try(fr.y + fr.h + gap, true)
  try(fr.y - h - gap, false)
  try(toastSlots.contentY + gap, true)
  try(toastSlots.maxY - h - gap, false)
  try(toastSlots.screenBottom - h - 4 * toastSlots.s, false, toastSlots.screenBottom)
  return best, bestAbove
end

local Party = require("Party")
local Boxes = require("Boxes")
local Items = require("Items")
local Events = require("Events")
local MapBrowser = require("MapBrowser")
local Dex = require("Dex")
-- chrome, not a tab panel, so deliberately kept out of PANELS below (#541)
local SpeciesPicker = require("SpeciesPicker")
local MovePicker = require("MovePicker")
local ItemPicker = require("ItemPicker")

local App = {}
local S
-- one loader per process: registries collide if a second load re-registers
-- vanilla records over an already-merged Data
local mods
local mouseClicked = false
-- Click position from the press event.  Kit samples the pointer in draw, so a
-- touch / mouse / pad-A click must use the event coords -- not love.mouse
-- (often stale on NX) and not the virtual cursor when a finger taps elsewhere.
local clickX, clickY
-- Wheel notches queued by App.wheelmoved since the last draw, handed to Kit
-- there like mouseClicked is: LOVE delivers events before love.draw, so a
-- notch is always spent by the frame that follows it (#595).
local TouchEditor = require("TouchEditor")
local wheelY = 0
local touch

-- Which game's cache Data was loaded from.  main.lua checks this before
-- opening the editor on a save from the other version, because the two
-- caches cannot both be mounted in one process (see CacheFs.mountVersion).
App.dataVersion = nil

local TABS = {
  { id = "party", glyph = "PT", label = "Party" },
  { id = "boxes", glyph = "BX", label = "Boxes" },
  { id = "items", glyph = "IT", label = "Items" },
  { id = "events", glyph = "EV", label = "Events" },
  { id = "map", glyph = "MP", label = "Map" },
  { id = "dex", glyph = "DX", label = "Pokédex" },
  { id = "trainer", glyph = "TR", label = "Trainer" },
  { id = "legality", glyph = "CK", label = "Checks" },
}

local PANELS = {
  party = Party,
  boxes = Boxes,
  items = Items,
  events = Events,
  map = MapBrowser,
  dex = Dex,
  trainer = require("Trainer"),
  legality = require("Checks"),
}

local function fileExists(path)
  local f = io.open(path, "rb")
  if f then
    f:close()
    return true
  end
  return false
end

-- Apply a load attempt for `path` into the current State (S must exist).
local function applyLoaded(path, statusVerb)
  statusVerb = statusVerb or "Loaded"
  Motion.reset()
  Kit.blur()
  S.path = path
  local existed = fileExists(path)
  local save, err = SaveIO.load(path)
  local kind = "ok"
  if save then
    S.save = save
    S.status = statusVerb .. " " .. path
    S.loadError = false
    S.allowSave = true
  elseif existed then
    S.save = Gen.newGame(S.version, Data)
    S.status = "Corrupt save at "
      .. path
      .. " ("
      .. tostring(err)
      .. "),  Save disabled, use Reload after fixing the file"
    kind = "error"
    S.loadError = true
    S.allowSave = false
  else
    S.save = Gen.newGame(S.version, Data)
    S.status = "No save at " .. path .. " (" .. tostring(err) .. "),  editing new game stub"
    kind = "info"
    S.loadError = false
    S.allowSave = true
  end
  if Gen.of(S.save, S.version) == 3 then
    S.events = Catalog.game3EventList(S.modRoots)
    S.game3Events = Catalog.game3Categories(S.modRoots)
  elseif Gen.of(S.save, S.version) == 2 then
    S.events = Catalog.gen2EventList(Gen.engineOf(S.save, S.version), S.modRoots)
  end
  local mapId = Gen.playerMap(S.save)
  S.mapId = mapId
  S.dirty = false
  S.undoStack, S.redoStack = {}, {}
  S.historyToken, S.historySavedToken = 0, 0
  S.revision = (S.revision or 0) + 1
  S.speciesPicker, S.movePicker, S.itemPicker = nil, nil, nil
  S.formMon, S.nicknameMon = nil, nil
  S.monDrafts, S.trainerDrafts, S.walletDrafts = {}, {}, {}
  S.propertyChoice, S.itemMenu = nil, nil
  S.navPopup, S.editPopup = nil, nil
  S._listState = nil
  S.mobileInspector = nil
  S._quitArmed = false
  S._openArmed = false
  S.editingMon = nil
  Ops.disarm(S)
  local prepared, prepareError = pcall(function()
    Gen.ensureBoxes(S.save)
    Gen.hydrateSave(Data, S.save)
  end)
  if not prepared then
    S.loadError, S.allowSave = true, false
    S.status = "Save disabled: " .. tostring(prepareError)
    Toast.show(S, S.status, "error", { sticky = true })
    return
  end
  local probe = require("src.mods.Merge").deepCopy(S.save)
  S.validation = Gen.validate(probe, Data)
  if not Gen.emptyReport(S.save, S.validation) then
    if Gen.of(S.save, S.version) == 2 then
      S.status = S.status
        .. string.format(
          ",  game would quarantine: %d script bytes, %d mail, %d events",
          #(S.validation.lostScriptMem or {}),
          #(S.validation.lostMail or {}),
          #(S.validation.lostEvents or {})
        )
    elseif Gen.of(S.save, S.version) ~= 3 then
      S.status = S.status
        .. string.format(
          ",  game would quarantine: %d mons, %d items, %d maps",
          #S.validation.lostMons,
          #S.validation.lostItems,
          #S.validation.remappedMaps
        )
    end
    if kind == "ok" and S.status:find("game would quarantine", 1, true) then kind = "warn" end
  end
  Toast.show(S, S.status, kind, { sticky = kind == "error" })
end

-- pathOverride lets tests point App.load at a scratch file instead of the
-- real default save path (used to exercise the corrupt-save branch below).
-- opts carries what only the launcher knows: which game the save belongs to,
-- its slot id, and where Close should go back to.
function App.load(pathOverride, opts)
  opts = opts or {}
  Motion.reset()
  local transition = require("src.ui.kit.Transition")
  local okMotion, motionOptions = pcall(function()
    return require("src.core.SaveData").loadOptions()
  end)
  transition.reduceMotion = opts.reduceMotion == true
    or os.getenv("POKEPORT_REDUCE_MOTION") == "1"
    or (okMotion and type(motionOptions) == "table" and motionOptions.reduceMotion == true)
    or transition.reduceMotion
  S = State.new()
  S.data = Data
  S.version = opts.version
  S.slotId = opts.slotId
  S.embedded = opts.embedded or false
  S.onClose = opts.onClose
  if opts.version then
    require("src.core.GameVersion").set(opts.version)
  end
  local editGeneration = Gen.of(nil, opts.version)
  local runGeneration = require("src.core.GameVersion").generation()
  if
    ((editGeneration == 3 or runGeneration == 3) and not Gen.game3CacheReady())
    or (editGeneration ~= 3 and runGeneration ~= 3 and (editGeneration == 2 or runGeneration == 2)
      and not Gen.gen2CacheReady(opts.version))
  then
    S.path = pathOverride or SaveIO.defaultPath()
    S.missingCache = Gen.missingCacheMessage(opts.version)
    S.status = S.missingCache
    S.loadError, S.allowSave = true, false
    return
  end
  -- the same mod set the game loads, merged into Data before the catalogs
  -- build, so modded species/items/moves are editable and MonOps stops
  -- asserting on them
  if not mods or App.dataVersion ~= opts.version then
    -- One loader per editor session.  A previous session leaves Data holding
    -- that session's merged registries (and possibly the other game's cache),
    -- and a second builtin registration over them collides -- "statuses
    -- already registered: FRZ".  _pristineKeys only exists once Data has been
    -- loaded at least once, so it doubles as the "needs evicting" marker.
    if Data._pristineKeys then
      Data:unloadGenerated()
    end
    Data:load()
    if Gen.of(nil, opts.version) == 3 or require("src.core.GameVersion").generation() == 3 then
      Gen.bindGame3Data(Data)
    elseif Gen.of(nil, opts.version) == 2 or require("src.core.GameVersion").generation() == 2 then
      Gen.bindGoldData(Data)
    end
    local ModLoader = require("src.mods.Loader")
    mods = ModLoader.new()
    mods:load(Data)
    App.dataVersion = opts.version
  end
  S.mods = mods
  S.cat = Catalog.build(Data)
  local modRoots = {}
  for _, mod in ipairs(S.mods:status().loaded) do
    modRoots[#modRoots + 1] = mod.path
  end
  S.modRoots = modRoots
  if Gen.of(nil, opts.version) == 3 or require("src.core.GameVersion").generation() == 3 then
    S.events = Catalog.game3EventList(modRoots)
  elseif Gen.of(nil, opts.version) == 2 or require("src.core.GameVersion").generation() == 2 then
    S.events = Catalog.gen2EventList(Gen.engineOf(nil, opts.version), modRoots)
  else
    S.events =
      Catalog.scrapeEvents("data/scripts", "data/generated/trainer_headers.lua", nil, modRoots)
  end
  applyLoaded(pathOverride or SaveIO.defaultPath(), "Loaded")
end

-- Switch to another save file (Open button, drag-drop, or --save arg).
-- If there are unsaved edits, the first call arms a confirm; call again
-- (or pass force=true) to discard and open.
function App.openPath(path, force)
  if not path or path == "" then
    return false
  end
  if not S or S.missingCache then
    return false
  end
  if S.dirty and not force and not S._openArmed then
    S._openArmed = true
    Ops.say(S, "Unsaved changes,  open again to discard and load " .. path, "warn")
    return false
  end
  applyLoaded(path, "Opened")
  return true
end

function App.chooseAndOpen()
  local path = SaveIO.choosePath()
  if path then
    App.openPath(path)
  else
    local osName = love and love.system and love.system.getOS and love.system.getOS()
    if osName ~= "OS X" and osName ~= "Windows" and osName ~= "Linux" then
      Ops.say(S, "File picker unavailable,  drop a save.lua onto the window")
    end
  end
end

function App.filedropped(file)
  if not (file and S) then
    return
  end
  local path = file.getFilename and file:getFilename() or nil
  if not path or path == "" then
    Ops.say(S, "Could not read dropped file path")
    return
  end
  App.openPath(path)
end

-- Test hook: App.load keeps its state in a module-local so headless tests
-- can drive App.load/App.draw against a scratch path and then inspect the
-- resulting flags/status without loving a real save file.
function App.getState()
  return S
end

-- Tear the editor down far enough that a later App.load rebuilds from
-- scratch.  main.lua calls this after Close so the next Edit -- possibly on
-- the other game's save -- re-runs Data:load against whatever cache is
-- mounted by then, instead of reusing this session's merged registries.
function App.unload()
  Motion.reset()
  touch = nil
  Kit.touchDown, Kit.ignoreMouseDown = nil, nil
  Kit._touchDrag, Kit._pointerDrag, Kit._tapPending, Kit._dragDelta = nil, nil, nil, 0
  S = nil
  mods = nil
  App.dataVersion = nil
  -- Kit is never evicted from package.loaded, so a Close taken while a text
  -- field still owns focus would leak Kit.focus and a raised soft keyboard
  -- (against a rect that is gone) into the launcher and the next session
  -- (#529).  A Close taken on the frame the species picker went up would
  -- likewise leave its modal shield raised, and the next session would open
  -- deaf to every click (#541).
  Kit.blur()
  Kit.blockClicks = false
  VirtualKeyboard.close(false)
  PadInput.reset()
end

local function cycleTab(delta)
  if not S then
    return
  end
  local idx = 1
  for i, t in ipairs(TABS) do
    if t.id == S.tab then
      idx = i
      break
    end
  end
  idx = ((idx - 1 + delta) % #TABS) + 1
  Motion.change(S, "tab", TABS[idx].id, delta)
  Ops.note(S, "Tab: " .. TABS[idx].label)
end

-- Pad / Joy-Con actions from PadInput.gamepadpressed (A/B via GamepadMap so
-- NX physical A confirms and B closes).
local function handlePadAction(action)
  if not action or not S then
    return
  end
  if action == "a" then
    local mx, my = PadInput.pointer()
    App.mousepressed(mx, my, 1)
  elseif action == "b" then
    if S.editPopup then
      TouchEditor.close(S, Kit)
    elseif S.navPopup then
      Chooser.close(S)
    elseif S.speciesPicker or S.movePicker or S.itemPicker or S.itemMenu or S.chromeMenu
        or Kit.focus or S.editingMon or (S.tab == "map" and S.mapFocused) then
      App.keypressed("escape")
    else
      App.close()
    end
  elseif action == "tab_prev" then
    if S.editPopup then
      TouchEditor.keypressed(S, Kit, S.editPopup.mode == "number" and "left" or "up")
    elseif S.navPopup then
      Chooser.keypressed(S, "up")
    else
      cycleTab(-1)
    end
  elseif action == "tab_next" then
    if S.editPopup then
      TouchEditor.keypressed(S, Kit, S.editPopup.mode == "number" and "right" or "down")
    elseif S.navPopup then
      Chooser.keypressed(S, "down")
    else
      cycleTab(1)
    end
  end
end

function App.save()
  if S.missingCache then
    return Ops.say(S, S.missingCache)
  end
  if not S.allowSave then
    return Ops.say(S, "Save disabled,  corrupt save loaded; fix the file and Reload first")
  end
  local output = S.save
  if Gen.ofState(S) == 3 then
    local prepared, result = pcall(require("Game3Adapter").export, S.save)
    if not prepared then
      Ops.say(S, "Save failed: " .. tostring(result))
      return false
    end
    output = result
  end
  local ok, err = SaveIO.save(S.path, output)
  if ok then
    S.dirty = false
    S.historySavedToken = S.historyToken or 0
    S._quitArmed = false
    Ops.disarm(S)
    Ops.say(S, "Saved " .. S.path, "ok")
    return true
  end
  Ops.say(S, "Save failed: " .. tostring(err))
  return false
end

function App.reload()
  if S.missingCache then
    return Ops.say(S, S.missingCache)
  end
  local save, err = SaveIO.load(S.path)
  if save then
    applyLoaded(S.path, "Reloaded")
    return not S.loadError
  end
  Ops.say(S, "Reload failed: " .. tostring(err))
  return false
end

-- Close: back to the launcher when hosted there, otherwise quit.  Unsaved
-- edits arm a confirm exactly like Open does, so leaving can't lose work.
--
-- The teardown itself is DEFERRED to the end of the frame (App.draw calls
-- finishClose below).  Close is dispatched from inside drawTitleBar, and the
-- host's onClose runs App.unload, which drops S -- doing that inline left the
-- rest of the frame drawing against a nil state.
function App.close()
  if not S then
    return false
  end
  if S.dirty and not S._quitArmed then
    S._quitArmed = true
    Ops.say(S, "Unsaved changes,  Save first or click Close again to discard", "warn")
    return false
  end
  S._closeRequested = true
  return true
end

local function finishClose()
  local embedded, onClose = S.embedded, S.onClose
  S._closeRequested = false
  if embedded and onClose then
    onClose()
  elseif love and love.event then
    love.event.quit()
  end
end

function App.update(dt)
  -- Immediate-mode UI: nothing to simulate per-frame; input is sampled
  -- directly in App.draw() via Kit.beginFrame. Tile animation (water,
  -- flowers) still needs ticking so the Map tab isn't static.
  TileRenderer.tick()
  if S and S.recommendJob then Ops.pollRecommendedMoves(S) end
  PadInput.update(dt)
  local notches = PadInput.takeWheel()
  if notches ~= 0 then
    App.wheelmoved(0, notches)
  end

  -- Dev harness, the launcher's POKEPORT_LAUNCHER_SHOT for this window:
  -- POKEPORT_EDITOR_SHOT=/path.png with POKEPORT_WIN=WxH resizes, lets the
  -- view settle, captures one frame and quits, so a scripted run can see the
  -- real editor at any window shape.  POKEPORT_EDITOR_TAB picks the tab and
  -- POKEPORT_EDITOR_ITEMPICK=1 opens the add-item modal.
  local shot = os.getenv("POKEPORT_EDITOR_SHOT")
  if shot and not App._shotDone then
    if not App._shotSized then
      App._shotSized = true
      local w, h = (os.getenv("POKEPORT_WIN") or ""):match("^(%d+)x(%d+)$")
      if w and love.window and love.window.setMode then
        pcall(love.window.setMode, tonumber(w), tonumber(h), { resizable = true })
      end
      local tab = os.getenv("POKEPORT_EDITOR_TAB")
      if tab and tab ~= "" and S then
        S.tab = tab
      end
      local monSlot = tonumber(os.getenv("POKEPORT_EDITOR_MON") or "")
      if monSlot and S and S.save and S.save.party then
        S.editingMon = S.save.party[monSlot]
      end
      if os.getenv("POKEPORT_EDITOR_ITEMPICK") == "1" and S then
        Ops.openItemPicker(S, Kit, "bag")
      end
    end
    App._shotTimer = (App._shotTimer or 0) + dt
    if App._shotTimer > 1.0 then
      App._shotDone = true
      love.graphics.captureScreenshot(function(imagedata)
        local fd = imagedata:encode("png")
        local f = io.open(shot, "wb")
        if f then
          f:write(fd:getString())
          f:close()
        end
        love.event.quit()
      end)
    end
  end
end

function App.mousepressed(x, y, button)
  if touch then
    return
  end
  if button == 1 then
    mouseClicked = true
    clickX, clickY = x, y
    -- A finger / mouse tap yields the virtual cursor so the click lands where
    -- the event said, not under the Joy-Con pointer (NX touch soft-miss).
    PadInput.yieldToPointer()
  end
end

function App.touchpressed(id, x, y)
  if S and MapBrowser.touchpressed(S, id, x, y) then
    if touch then touch.moved = true end
    Kit.blur()
    return
  end
  if touch then
    return
  end
  touch = { id = id, x = x, y = y, startX = x, startY = y, moved = false }
  Kit.touchDown = true
  Kit.ignoreMouseDown = true
  Kit._pointerDrag, Kit._tapPending = nil, nil
  Kit._touchDrag = { x = x, startY = y }
  Kit._dragDelta = 0
  PadInput.yieldToPointer()
end

function App.touchmoved(id, x, y)
  local pinched = S and MapBrowser.touchmoved(S, id, x, y)
  if pinched and touch then touch.moved = true end
  if not touch or touch.id ~= id then
    return
  end
  local lastY = touch.y
  touch.x, touch.y = x, y
  if math.abs(x - touch.startX) + math.abs(y - touch.startY) > 10 then
    touch.moved = true
  end
  if touch.moved and not pinched then
    Kit.dragAdd(lastY - y)
  end
end

function App.touchreleased(id, x, y)
  App.touchmoved(id, x, y)
  local pinched = S and MapBrowser.touchreleased(S, id)
  if not touch or touch.id ~= id then
    return
  end
  if pinched then
    local nextId, point = next(S._mapTouches)
    if nextId then
      touch = { id = nextId, x = point.x, y = point.y, startX = point.x, startY = point.y, moved = true }
      Kit._touchDrag = { x = point.x, startY = point.y }
      return
    end
  end
  if not touch.moved then
    mouseClicked, clickX, clickY = true, x, y
  end
  touch = nil
  Kit.touchDown = false
  Kit.ignoreMouseDown = true
end

function App.textinput(text)
  if VirtualKeyboard.textinput(text) then
    return
  end
  Kit.textinput(text)
end

local KEY_SCROLL = { up = 1, down = -1, pageup = 3, pagedown = -3 }

local HAT_DIRS = {
  u = { "dpup" }, d = { "dpdown" }, l = { "dpleft" }, r = { "dpright" },
}

function App.gamepadpressed(joystick, button)
  if VirtualKeyboard.active then
    VirtualKeyboard.gamepadpressed(GamepadMap.mapLauncherButton(button))
    return
  end
  handlePadAction(PadInput.gamepadpressed(joystick, button))
end

function App.gamepadreleased(joystick, button)
  PadInput.gamepadreleased(joystick, button)
end

function App.gamepadaxis(joystick, axis, value)
  PadInput.gamepadaxis(joystick, axis, value)
end

function App.joystickpressed(joystick, button)
  if VirtualKeyboard.active then
    if GamepadMap.ignoreRawForJoystick(joystick) or GamepadMap.isAccelerometer(joystick) then
      return
    end
    local padButton = GamepadMap.mapRawToGamepadButton(button)
    if padButton then
      VirtualKeyboard.gamepadpressed(GamepadMap.mapLauncherButton(padButton))
    end
    return
  end
  handlePadAction(PadInput.joystickpressed(joystick, button))
end

function App.joystickreleased(joystick, button)
  PadInput.joystickreleased(joystick, button)
end

function App.joystickaxis(joystick, axis, value)
  PadInput.joystickaxis(joystick, axis, value)
end

function App.joystickhat(joystick, hat, direction)
  if VirtualKeyboard.active then
    if GamepadMap.ignoreRawForJoystick(joystick) or GamepadMap.isAccelerometer(joystick) then
      return
    end
    for _, d in ipairs(HAT_DIRS[direction] or {}) do
      VirtualKeyboard.gamepadpressed(d)
    end
    return
  end
  PadInput.joystickhat(joystick, hat, direction)
end

local function drawVirtualKeyboard(width, height, mx, my, clicked)
  local LKit = require("src.ui.kit.Kit")
  if not LKit.fonts or next(LKit.fonts) == nil then
    LKit.layout(width, height)
  end
  local sx, sy, sc, sb, so = LKit.mouseX, LKit.mouseY, LKit.mouseClicked, LKit.blockClicks, LKit._occluders
  LKit.mouseX, LKit.mouseY, LKit.mouseClicked = mx, my, clicked and true or false
  LKit.blockClicks, LKit._occluders = false, 0
  LKit.resetClip()
  VirtualKeyboard.draw({ s = math.min(Kit.scale, height / 380), W = width, H = height })
  LKit.mouseX, LKit.mouseY, LKit.mouseClicked = sx, sy, sc
  LKit.blockClicks, LKit._occluders = sb, so
end

-- ------------------------------------------------------------------ chrome
local function versionLabel()
  local ok, info = pcall(require("src.core.GameVersion").info, S.version)
  if ok and type(info) == "table" and info.label then return info.label end
  return S.version and (S.version:sub(1, 1):upper() .. S.version:sub(2)) or nil
end

local function shortPath(path)
  if not path then return "New save" end
  local parts = {}
  for part in tostring(path):gmatch("[^/\\]+") do parts[#parts + 1] = part end
  if #parts <= 3 then return tostring(path) end
  return ".../" .. table.concat(parts, "/", #parts - 2)
end

local function drawIdentity(x, y, w, h)
  local s = Kit.scale
  local titleH, pathH = Kit.textHeight("button"), Kit.textHeight("tiny")
  local ty = y + (h - titleH - pathH - 4 * s) / 2
  local lead, version, sep = "Save editor", versionLabel(), " / "
  local leadW, sepW = Kit.textWidth("button", lead), Kit.textWidth("button", sep)
  Kit.textBold("button", Kit.ellipsize("button", lead, w), x, ty, PAL.heading)
  if version and leadW + sepW + 40 * s < w then
    Kit.text("button", sep, x + leadW + 1, ty, PAL.muted)
    Kit.textBold("button", Kit.ellipsize("button", version, w - leadW - sepW - 1), x + leadW + sepW + 1, ty, PAL.heading)
  end
  Kit.text("tiny", Kit.ellipsize("tiny", shortPath(S.path), w), x, ty + titleH + 4 * s, PAL.muted)
end

local function saveStatus()
  if S.dirty then return "Unsaved changes", PAL.yellow end
  return "Saved", PAL.muted
end

local function saveButton(x, y, h, measure)
  local label = S.allowSave and "Save" or "Save locked"
  local ink = S.allowSave and S.dirty and PAL.green or PAL.muted
  local opts = {
    font = "button",
    face = "invert",
    ink = ink,
    stroke = ink,
    icon = S.allowSave and "save" or "lock",
    enabled = S.dirty or not S.allowSave,
  }
  local w = Kit.buttonWidth(label, opts, h)
  if not measure and Kit.button(x - w, y, w, h, label, opts) then
    App.save()
  end
  return w
end

local function drawActionRow(x, y, w, h, withIdentity)
  local s, row = Kit.scale, Kit.controlH()
  local gap, pad = 8 * s, (Kit.desktop and 20 or 12) * s
  local by = y + (h - row) / 2
  local rx = x + w - pad
  if S._quitArmed then
    local cw = Kit.buttonWidth("Discard?", { font = "button" }, row)
    rx = rx - cw
    if Kit.button(rx, by, cw, row, "Discard?", { kind = "danger", font = "button" }) then App.close() end
  else
    rx = rx - row
    if Kit.iconButton(rx, by, row, row, "x", "Close", { kind = "ghost" }) then App.close() end
  end
  rx = rx - 2 * gap
  rx = rx - saveButton(rx, by, row)
  rx = rx - gap - row
  if Kit.iconButton(rx, by, row, row, "folder-open", "Open", { kind = "ghost" }) then App.chooseAndOpen() end
  rx = rx - gap - row
  if Kit.iconButton(rx, by, row, row, "rotate-ccw", "Reload", { kind = "ghost" }) then App.reload() end
  rx = rx - gap - row
  if Kit.iconButton(rx, by, row, row, "redo-2", "Redo", { kind = "ghost", enabled = S.redoStack and #S.redoStack > 0 }) then
    require("History").redo(S)
  end
  rx = rx - 4 * s - row
  if Kit.iconButton(rx, by, row, row, "undo-2", "Undo", { kind = "ghost", enabled = S.undoStack and #S.undoStack > 0 }) then
    require("History").undo(S)
  end
  rx = rx - 18 * s
  local status, color = saveStatus()
  local statusW = Kit.textWidth("small", status)
  local left = x + pad + (withIdentity and 150 * s or 0)
  if rx - statusW >= left then
    Kit.textRight("small", status, rx, by + (row - Kit.textHeight("small")) / 2, color)
    rx = rx - statusW - 24 * s
  end
  if withIdentity then
    drawIdentity(x + pad, y, rx - x - pad, h)
  end
end

local function chromeMenuCols(w)
  local s, gap = Kit.scale, 8 * Kit.scale
  local widest = 0
  for _, label in ipairs({ "Redo", "Reload", "Open", "Close", "Discard?" }) do
    widest = math.max(widest, Kit.buttonWidth(label, { font = "small" }, Kit.controlH()))
  end
  return (w - 24 * s) >= 4 * widest + 3 * gap and 4 or 2
end

local function drawTitleBar(x, y, w, h)
  if Kit.desktop or S.compactChrome or w >= 760 * Kit.scale then
    return drawActionRow(x, y, w, h, not S.compactChrome)
  end
  local s = Kit.scale
  local pad, gap, row = 12 * s, 8 * s, Kit.controlH()
  local inner = w - 2 * pad
  local idH = Kit.textHeight("button") + Kit.textHeight("tiny") + 4 * s
  drawIdentity(x + pad, y + 8 * s, inner, idH)
  local by = y + idH + 20 * s
  local rx = x + w - pad - row
  if Kit.iconButton(rx, by, row, row, S.chromeMenu and "x" or "ellipsis", S.chromeMenu and "Less" or "More", { kind = "ghost" }) then
    S.chromeMenu = not S.chromeMenu
    Kit.blur()
  end
  rx = rx - gap
  rx = rx - saveButton(rx, by, row) - gap - row
  if Kit.iconButton(rx, by, row, row, "undo-2", "Undo", { kind = "ghost", enabled = S.undoStack and #S.undoStack > 0 }) then
    require("History").undo(S)
  end
  local status, color = saveStatus()
  Kit.text("small", Kit.ellipsize("small", status, rx - gap - x - pad), x + pad, by + (row - Kit.textHeight("small")) / 2, color)
  if S.chromeMenu then
    local menu = {
      { "Redo", "redo-2", function() require("History").redo(S) end, S.redoStack and #S.redoStack > 0 },
      { "Reload", "rotate-ccw", function() App.reload() end, true },
      { "Open", "folder-open", function() App.chooseAndOpen() end, true },
      { S._quitArmed and "Discard?" or "Close", S._quitArmed and "trash" or "x", function() App.close() end, true },
    }
    local cols = chromeMenuCols(w)
    local bw = (inner - (cols - 1) * gap) / cols
    for i, m in ipairs(menu) do
      local mx = x + pad + (i - 1) % cols * (bw + gap)
      local my = by + row + gap + math.floor((i - 1) / cols) * (row + gap)
      local opts = { font = "small", icon = m[2], enabled = m[4], kind = m[1] == "Discard?" and "danger" or "ghost" }
      if Kit.button(mx, my, bw, row, m[1], opts) then m[3]() end
    end
  end
end

local function drawTabRail(x, y, w, h)
  local pad, row = 12 * Kit.scale, Kit.controlH()
  Chooser.navigation(
    S,
    Kit,
    "tab",
    "Save editor page",
    TABS,
    x + pad,
    y,
    math.min(w - 2 * pad, (Kit.desktop and 240 or 360) * Kit.scale),
    row,
    function()
      S.mobileInspector = false
      S.chromeMenu, S.itemMenu = false, nil
    end
  )
end

local function drawStatusBar(x, y, w, h)
  local s = Kit.scale
  local pad = 22 * s
  Theme.col(PAL.bgBot, 0.6)
  love.graphics.rectangle("fill", x, y, w, h)
  Theme.col(PAL.cardBorder, 0.22)
  love.graphics.rectangle("fill", x, y, w, 1)

  local ctrl = (love.system and love.system.getOS and love.system.getOS() == "OS X") and "Cmd"
    or "Ctrl"
  local hint = S.embedded
      and (ctrl .. "+S save . " .. ctrl .. "+R reload . Esc clear selection . Close returns to the launcher")
    or (
      ctrl
      .. "+S save . "
      .. ctrl
      .. "+R reload . Esc clear selection . arrows pan map . wheel scrolls lists"
    )
  local hintW = Kit.textWidth("tiny", hint)
  local avail = w - 2 * pad - hintW - 14 * s
  if avail >= 120 * s then
    Kit.textRight("tiny", hint, x + w - pad, y + (h - Kit.textHeight("tiny")) / 2, PAL.faint)
  else
    avail = w - 2 * pad
  end
  Kit.text(
    "mono",
    Kit.ellipsize("mono", S.note or "", avail),
    x + pad,
    y + (h - Kit.textHeight("mono")) / 2,
    PAL.detail
  )
end

function App.draw()
  -- Closing the editor unloads it, and the host may still deliver one more
  -- frame or a queued event before it re-routes; every entry point below
  -- tolerates that rather than indexing a torn-down state.
  if not S then
    return
  end
  local width, height = love.graphics.getDimensions()
  width = math.max(1, tonumber(width) or 1)
  height = math.max(1, tonumber(height) or 1)
  -- Usable chrome rect.  Background still fills the window so the notch /
  -- home-indicator bands stay the field colour; every button (Save first)
  -- lives inside the safe area, matching the launcher and Skin Studio (#917).
  local ox, oy, sw, sh = SafeArea.rect()
  ox = math.max(0, tonumber(ox) or 0)
  oy = math.max(0, tonumber(oy) or 0)
  sw = math.max(1, tonumber(sw) or width)
  sh = math.max(1, tonumber(sh) or height)
  Kit.layout(sw, sh)
  local s = Kit.scale
  if S.tab == "map" then
    local shape = sw .. "x" .. sh
    if S._mapFocusShape ~= shape then
      S._mapFocusShape = shape
      if not Kit.desktop and sw > sh and sh < 500 * s then S.mapFocused = true end
    end
  else
    S._mapFocusShape = nil
  end

  local mx, my = love.mouse.getPosition()
  local padX, padY, padOn = PadInput.pointer()
  if mouseClicked and clickX ~= nil then
    mx, my = clickX, clickY
  elseif touch then
    mx, my = touch.x, touch.y
  elseif padOn then
    mx, my = padX, padY
  end
  local vkClick = VirtualKeyboard.active and mouseClicked
  if vkClick then
    mouseClicked = false
  end
  if mouseClicked and clickX ~= nil and Toast.hit(S, clickX, clickY) then
    Toast.clear(S)
    mouseClicked = false
  end
  Motion.update()
  Kit.beginFrame(mx, my, mouseClicked, wheelY)
  Kit.trackControls = S.toast ~= nil and Kit.focus ~= nil and not Kit.desktop
  mouseClicked = false
  clickX, clickY = nil, nil
  wheelY = 0
  -- Modal shield.  Kit has no z-order, so the picker cannot simply be drawn
  -- last: the chrome and the panel underneath would take the same tap.  The
  -- shield goes up before anything dispatches and comes down only for the
  -- picker's own layer at the bottom of this function (#541).
  Kit.blockClicks = (S.speciesPicker ~= nil)
    or (S.itemPicker ~= nil)
    or (S.movePicker ~= nil)
    or (S.navPopup ~= nil)
    or (S.editPopup ~= nil)
    or VirtualKeyboard.active
    or Motion.active()
  if S.tab ~= "map" or Kit.blockClicks then MapBrowser.clearTouches(S) end

  Theme.field(width, height)

  if S.missingCache then
    Theme.versionRail(ox, oy, sw, 6 * s)
    local pad = 22 * s
    local ty = oy + sh / 2 - 60 * s
    for line in (S.missingCache .. " "):gmatch("(.-%.)%s+") do
      Kit.textCenter("button", line, ox + pad, ty, sw - 2 * pad, PAL.heading)
      ty = ty + Kit.textHeight("button") + 8 * s
    end
    local label = "Close"
    local bw = 22 * s + Kit.textWidth("button", label)
    if Kit.button(ox + (sw - bw) / 2, ty + 40 * s, bw, 38 * s, label, { kind = "ghost" }) then
      App.close()
    end
    Kit.endFrame()
    PadInput.draw()
    if S._closeRequested then
      finishClose()
    end
    return
  end

  local railH = 6 * s
  -- The title bar reflows to two rows (identity above, buttons below) when
  -- the window is too narrow for both on one, instead of the buttons and the
  -- identity painting through each other (#715).  The taller bar simply
  -- costs the content column height, which scrolls.
  S.compactChrome = sh < 500 * s and sw > sh
  local titleH
  if S.compactChrome or Kit.desktop or sw >= 760 * s then
    titleH = Kit.controlH() + 16 * s
  else
    local menuRows = S.chromeMenu and (chromeMenuCols(sw) == 4 and 1 or 2) or 0
    titleH = Kit.textHeight("button") + Kit.textHeight("tiny") + 4 * s + 28 * s
      + (1 + menuRows) * (Kit.controlH() + 8 * s)
  end
  local tabH = Kit.controlH() + 6 * s
  local statusH = (Kit.desktop and 28 or 38) * s
  -- A phone map needs room for actual cells. Its focus control
  -- hides the editor chrome while keeping the map navigation and status.
  local focusMap = S.tab == "map" and S.mapFocused
  if focusMap then
    titleH, tabH = 0, 0
  end

  Theme.versionRail(ox, oy, sw, railH)
  if not focusMap then
    drawTitleBar(ox, oy + railH, sw, titleH)
    drawTabRail(ox, oy + railH + titleH, sw, tabH)
  end

  local contentY = oy + railH + titleH + tabH
  local contentH = sh - railH - titleH - tabH - statusH
  S.toastBottom, S.toastHeader = nil, nil
  local px, py = ox + 10 * s, contentY + 8 * s
  local pw, ph = sw - 20 * s, math.max(1, contentH - 16 * s)
  local ok, err = xpcall(function()
    Motion.pages(S, Kit, "tab", px, py, pw, ph, function(state, kit, dx, dy, dw, dh)
      local panel = PANELS[state.tab]
      if not panel then
        return
      end
      local minH = (state.tab == "events" and 360 or state.tab == "dex" and 580 or 0) * s
      state._scrollingPage = minH > dh
      kit.pushClip(dx, dy, dw, dh)
      if minH > dh then
        state.pageScroll = state.pageScroll or {}
        local off = state.pageScroll[state.tab] or 0
        panel.draw(state, kit, dx, dy - off, dw, minH)
        state.pageScroll[state.tab] = kit.scrollPixels(dx, dy, dw, dh, off, minH)
      else
        panel.draw(state, kit, dx, dy, dw, dh)
      end
      kit.popClip()
    end)
  end, debug.traceback)
  if not ok then
    Kit.resetClip()
    print(string.format("[SAVE-EDITOR ERROR in %s panel]\n%s", tostring(S.tab), tostring(err)))
    Kit.text(
      "mono",
      "Error rendering " .. tostring(S.tab) .. " panel",
      px + 12 * s,
      py + 12 * s,
      PAL.red
    )
  end

  drawStatusBar(ox, oy + sh - statusH, sw, statusH)
  Kit.blockClicks = false
  -- Scrim still covers the full window (including unsafe bands); the card
  -- itself is centred in the safe rect so search fields clear the notch.
  if S.editPopup then
    TouchEditor.draw(S, Kit, width, height)
  elseif S.navPopup then
    Chooser.draw(S, Kit, width, height)
  else
    SpeciesPicker.draw(S, Kit, width, height)
    MovePicker.draw(S, Kit, width, height)
    ItemPicker.draw(S, Kit, width, height)
  end
  if S.toast then
    local a = toastArea
    a.x, a.w, a.s, a.font = ox, sw, s, Kit.fonts.small
    a.top, a.bottom, a.maxY, a.centerY, a.width, a.maxLines, a.place = nil, nil, nil, nil, nil, nil, nil
    local hdr, fr = S.toastHeader, Kit.focusRect
    if hdr then
      a.x, a.w, a.width, a.maxLines = hdr.x, hdr.w, hdr.w, 2
      a.centerY = hdr.y + hdr.h / 2
    elseif Kit.focus and not Kit.desktop then
      if fr then
        a.top, a.bottom, a.maxY = fr.y + fr.h, fr.y, oy + sh - statusH
        toastSlots.s, toastSlots.field, toastSlots.contentY = s, fr, contentY
        toastSlots.minY, toastSlots.maxY, toastSlots.screenBottom = oy, oy + sh - statusH, oy + sh
        a.place = placeClearOfControls
      else
        a.top = contentY
      end
    else
      a.bottom = math.min(S.toastBottom or math.huge, oy + sh - statusH)
    end
    Toast.draw(S, a)
  end
  Kit.endFrame()
  if VirtualKeyboard.active then
    drawVirtualKeyboard(width, height, mx, my, vkClick)
  end
  PadInput.draw()

  -- Only now, with the whole frame painted, is it safe to drop the editor.
  if S._closeRequested then
    finishClose()
  end
end

function App.keypressed(key)
  if not S or S.missingCache then
    return
  end
  if VirtualKeyboard.keypressed(key) or VirtualKeyboard.active then
    return
  end
  if TouchEditor.keypressed(S, Kit, key) then
    return
  end
  if Chooser.keypressed(S, key) then
    return
  end
  -- The picker takes Enter and Escape before the focused field does: Kit maps
  -- fields handle their own commit/cancel instead of submitting a form.
  if S.itemPicker then
    if key == "return" or key == "kpenter" then
      S.itemPicker.query = Kit.flushText("item-picker", S.itemPicker.query)
      ItemPicker.commitFirst(S, Kit)
      return
    elseif key == "escape" then
      Ops.closeItemPicker(S, Kit)
      return
    end
  end
  if S.movePicker then
    if key == "return" or key == "kpenter" then
      S.movePicker.query = Kit.flushText("move-picker", S.movePicker.query)
      MovePicker.commitFirst(S, Kit)
      return
    elseif key == "escape" then
      Ops.closeMovePicker(S, Kit)
      return
    end
  end
  if S.speciesPicker then
    if key == "return" or key == "kpenter" then
      S.speciesPicker.query = Kit.flushText("species-picker", S.speciesPicker.query)
      SpeciesPicker.commitFirst(S, Kit)
      return
    elseif key == "escape" then
      Ops.closeSpeciesPicker(S, Kit)
      return
    end
  end
  -- The inspector's nickname field is a commit-on-Enter field, unlike the
  -- search fields, which are live view state.  Enter commits the draft through
  -- Ops and blurs; Escape discards it and blurs.  Both must run before
  -- Kit.keypressed. Drain queued typing before committing the draft.
  if Kit.focus == "mon-nickname" then
    if key == "return" or key == "kpenter" then
      if
        S.editingMon
        and Ops.setNickname(
          S,
          S.editingMon,
          Kit.flushText("mon-nickname", S.nicknameDraft, function(v)
            return Ops.nicknameSanitize(S, v)
          end)
        )
      then
        S.nicknameDraft = S.editingMon.nickname or ""
      end
      Kit.blur()
      return
    elseif key == "escape" then
      Kit.blur()
      if S.editingMon then
        S.nicknameDraft = S.editingMon.nickname or ""
      end
      return
    end
  end
  -- A focused text field eats the keys it cares about (typing "s" into the
  -- map filter must not trigger Save).
  if Kit.keypressed(key) then
    return
  end
  if Kit.focus then
    if key == "escape" then
      Kit.blur()
    end
    return
  end
  -- Save and Reload both touch the file on disk (Reload discards unsaved
  -- edits), so they need a modifier. A bare letter must remain safe to type.
  local mod = love.keyboard
    and love.keyboard.isDown
    and (love.keyboard.isDown("lgui", "rgui") or love.keyboard.isDown("lctrl", "rctrl"))
  if key == "escape" and (S.itemMenu or S.chromeMenu) then
    S.itemMenu, S.chromeMenu = nil, false
    Ops.note(S, "Menu closed")
    return
  end
  if key == "escape" and S.tab == "map" and S.mapFocused then
    S.mapFocused = false
    MapBrowser.clearTouches(S)
    Kit.blur()
    return
  end
  if key == "escape" then
    S.editingMon = nil
    Ops.disarm(S)
    Ops.note(S, "Selection cleared")
  elseif key == "z" and mod then
    if love.keyboard.isDown("lshift", "rshift") then
      require("History").redo(S)
    else
      require("History").undo(S)
    end
  elseif key == "y" and mod then
    require("History").redo(S)
  elseif key == "s" and mod then
    App.save()
  elseif key == "r" and mod then
    App.reload()
  end
  local panKey = S.tab == "map" and (key == "up" or key == "down")
  if KEY_SCROLL[key] and not panKey then
    App.wheelmoved(0, KEY_SCROLL[key])
  end
  if S.tab == "map" and MapBrowser.keypressed then
    MapBrowser.keypressed(S, key)
  end
end

function App.wheelmoved(x, y)
  if not S or S.missingCache then
    return
  end
  if S.navPopup or S.editPopup or S.speciesPicker or S.movePicker or S.itemPicker then
    wheelY = wheelY + (y or 0)
    return
  end
  -- Only the map viewport spends the wheel on zoom. Search results keep the
  -- launcher's normal scrolling under the pointer.
  local mx, my = love.mouse.getPosition()
  if
    S.tab == "map"
    and MapBrowser.wheelmoved
    and not S._scrollingPage
    and (not S._mapStacked or not S.mapSection or S.mapSection == "view")
    and (not S._mapViewRect or MapBrowser.contains(S, mx, my))
  then
    MapBrowser.wheelmoved(S, y)
    return
  end
  wheelY = wheelY + (y or 0)
end

function App.quit()
  if not S then
    return false
  end
  if S.dirty then
    -- simple: block quit once and set status; user saves or force-quits again
    if not S._quitArmed then
      S._quitArmed = true
      Ops.say(S, "Unsaved changes,  save or press quit again", "warn")
      return true
    end
  end
  return false
end

return App
