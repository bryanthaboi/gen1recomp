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
-- Vertical rhythm (scaled by Kit's height/768 factor, everything else flexes):
--   0    6px   tri-colour version rail, identical to the launcher's
--   6    64px  title bar   identity, file chip, Save / Reload / Open / Close
--   70   66px  tab rail    6 tab tiles + right-aligned validation pill
--   136  flex  content     one panel per tab, 20px gutters
--   -38  38px  status bar  the last Ops message + the keyboard map

local Data = require("src.core.Data")
local TileRenderer = require("src.render.TileRenderer")
local SaveIO = require("SaveIO")
local Catalog = require("Catalog")
local State = require("State")
local Kit = require("Kit")
local Theme = require("Theme")
local Ops = require("Ops")
local PAL = Theme.PAL

local Party = require("Party")
local Boxes = require("Boxes")
local Items = require("Items")
local Events = require("Events")
local MapBrowser = require("MapBrowser")
local Dex = require("Dex")
-- chrome, not a tab panel, so deliberately kept out of PANELS below (#541)
local SpeciesPicker = require("SpeciesPicker")

local App = {}
local S
-- one loader per process: registries collide if a second load re-registers
-- vanilla records over an already-merged Data
local mods
local mouseClicked = false
-- Wheel notches queued by App.wheelmoved since the last draw, handed to Kit
-- there like mouseClicked is: LOVE delivers events before love.draw, so a
-- notch is always spent by the frame that follows it (#595).
local wheelY = 0

-- Which game's cache Data was loaded from.  main.lua checks this before
-- opening the editor on a save from the other version, because the two
-- caches cannot both be mounted in one process (see CacheFs.mountVersion).
App.dataVersion = nil

local TABS = {
  { id = "party",  glyph = "PT", label = "PARTY" },
  { id = "boxes",  glyph = "BX", label = "BOXES" },
  { id = "items",  glyph = "IT", label = "ITEMS" },
  { id = "events", glyph = "EV", label = "EVENTS" },
  { id = "map",    glyph = "MP", label = "MAP" },
  { id = "dex",    glyph = "DX", label = "DEX" },
}

local PANELS = {
  party = Party, boxes = Boxes, items = Items,
  events = Events, map = MapBrowser, dex = Dex,
}

local function fileExists(path)
  local f = io.open(path, "rb")
  if f then f:close(); return true end
  return false
end

-- Apply a load attempt for `path` into the current State (S must exist).
local function applyLoaded(path, statusVerb)
  statusVerb = statusVerb or "Loaded"
  S.path = path
  local existed = fileExists(path)
  local save, err = SaveIO.load(path)
  if save then
    S.save = save
    S.status = statusVerb .. " " .. path
    S.mapId = save.player.map
    S.loadError = false
    S.allowSave = true
  elseif existed then
    -- File is present but SaveIO.load couldn't decode it: treat it as a
    -- real (corrupt) save, not a missing one. Editing a stub here is fine,
    -- but Save must stay disabled so we never clobber the corrupt file
    -- until the user fixes it and Reload succeeds.
    S.save = require("src.core.SaveData").newGame()
    S.status = "Corrupt save at " .. path .. " (" .. tostring(err) ..
      "),  Save disabled, use Reload after fixing the file"
    S.mapId = S.save.player.map
    S.loadError = true
    S.allowSave = false
  else
    S.save = require("src.core.SaveData").newGame()
    S.status = "No save at " .. path .. " (" .. tostring(err) ..
      "),  editing new game stub"
    S.mapId = S.save.player.map
    S.loadError = false
    S.allowSave = true
  end
  S.dirty = false
  S._quitArmed = false
  S._openArmed = false
  S.editingMon = nil
  Ops.disarm(S)
  local boxes = require("src.pokemon.Boxes").ensure(S.save)
  -- Imported .sav box mons have no stat block (box_struct stops before
  -- MON_STATS).  The game derives them in SaveData.validate; the editor
  -- only validates a copy, so hydrate here for Boxes/Party/MonEditor.
  local Stats = require("src.pokemon.Stats")
  local function ensureStats(mon)
    Stats.ensure(Data.pokemon and Data.pokemon[mon.species], mon)
  end
  for _, mon in ipairs(S.save.party or {}) do ensureStats(mon) end
  for _, box in ipairs(boxes) do
    for _, mon in ipairs(box) do ensureStats(mon) end
  end
  if S.save.daycare and S.save.daycare.mon then
    ensureStats(S.save.daycare.mon)
  end
  -- what the running game would quarantine, computed on a copy so the
  -- editor never mutates the file behind the user's back
  local SaveData = require("src.core.SaveData")
  local probe = require("src.mods.Merge").deepCopy(S.save)
  S.validation = SaveData.validate(probe, Data)
  if not SaveData.emptyReport(S.validation) then
    S.status = S.status .. string.format(",  game would quarantine: %d mons, %d items, %d maps",
      #S.validation.lostMons, #S.validation.lostItems, #S.validation.remappedMaps)
  end
end

-- pathOverride lets tests point App.load at a scratch file instead of the
-- real default save path (used to exercise the corrupt-save branch below).
-- opts carries what only the launcher knows: which game the save belongs to,
-- its slot id, and where Close should go back to.
function App.load(pathOverride, opts)
  opts = opts or {}
  S = State.new()
  S.data = Data
  S.version = opts.version
  S.slotId = opts.slotId
  S.embedded = opts.embedded or false
  S.onClose = opts.onClose
  -- the same mod set the game loads, merged into Data before the catalogs
  -- build, so modded species/items/moves are editable and MonOps stops
  -- asserting on them
  if not mods then
    -- One loader per editor session.  A previous session leaves Data holding
    -- that session's merged registries (and possibly the other game's cache),
    -- and a second builtin registration over them collides -- "statuses
    -- already registered: FRZ".  _pristineKeys only exists once Data has been
    -- loaded at least once, so it doubles as the "needs evicting" marker.
    if Data._pristineKeys then Data:unloadGenerated() end
    Data:load()
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
  S.events = Catalog.scrapeEvents("data/scripts", "data/generated/trainer_headers.lua",
                                  nil, modRoots)
  applyLoaded(pathOverride or SaveIO.defaultPath(), "Loaded")
end

-- Switch to another save file (Open button, drag-drop, or --save arg).
-- If there are unsaved edits, the first call arms a confirm; call again
-- (or pass force=true) to discard and open.
function App.openPath(path, force)
  if not path or path == "" then return false end
  if not S then return false end
  if S.dirty and not force and not S._openArmed then
    S._openArmed = true
    S.status = "Unsaved changes,  open again to discard and load " .. path
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
    local osName = love and love.system and love.system.getOS
      and love.system.getOS()
    if osName ~= "OS X" and osName ~= "Windows" and osName ~= "Linux" then
      S.status = "File picker unavailable,  drop a save.lua onto the window"
    end
  end
end

function App.filedropped(file)
  if not (file and S) then return end
  local path = file.getFilename and file:getFilename() or nil
  if not path or path == "" then
    S.status = "Could not read dropped file path"
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
end

function App.save()
  if not S.allowSave then
    return Ops.say(S, "Save disabled,  corrupt save loaded; fix the file and Reload first")
  end
  local ok, err = SaveIO.save(S.path, S.save)
  if ok then
    S.dirty = false
    S._quitArmed = false
    Ops.disarm(S)
    S.status = "Saved " .. S.path
    return true
  end
  S.status = "Save failed: " .. tostring(err)
  return false
end

function App.reload()
  local save, err = SaveIO.load(S.path)
  if save then
    S.save = save
    S.dirty = false
    S.loadError = false
    S.allowSave = true
    S._quitArmed = false
    S._openArmed = false
    S.editingMon = nil
    S.status = "Reloaded " .. S.path
    require("src.pokemon.Boxes").ensure(S.save)
    return true
  end
  S.status = "Reload failed: " .. tostring(err)
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
  if S.dirty and not S._quitArmed then
    S._quitArmed = true
    S.status = "Unsaved changes,  Save first or click Close again to discard"
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
end

function App.mousepressed(x, y, button)
  if button == 1 then mouseClicked = true end
end

function App.textinput(text)
  Kit.textinput(text)
end

-- ------------------------------------------------------------------ chrome
-- The file chip: the single source of truth for "which file am I editing".
-- The path truncates from the LEFT so the filename is always readable, and
-- an amber dot plus the word UNSAVED calls out dirty state from any tab.
local function drawFileChip(x, y, w, h)
  local s = Kit.scale
  Theme.row(x, y, w, h, 10 * s, 0.6)
  local pad = 14 * s
  local dot = 8 * s
  local cx = x + pad
  if S.dirty then
    Theme.col(PAL.yellow, 1)
    if love.graphics.circle then
      love.graphics.circle("fill", cx + dot / 2, y + h / 2, dot / 2)
    else
      love.graphics.rectangle("fill", cx, y + h / 2 - dot / 2, dot, dot)
    end
    cx = cx + dot + 8 * s
  end
  local label = S.dirty and "UNSAVED" or "SAVED"
  local labelW = Kit.textWidth("tiny", label)
  Kit.textRight("tiny", label, x + w - pad, y + (h - Kit.textHeight("tiny")) / 2,
    S.dirty and PAL.yellow or PAL.caption)
  local avail = (x + w - pad - labelW - 10 * s) - cx
  local shown = Theme.ellipsizeLeft(Kit.fonts.mono, S.path or "(no file)", avail)
  Kit.text("mono", shown, cx, y + (h - Kit.textHeight("mono")) / 2, PAL.detail)
end

local function drawTitleBar(x, y, w, h)
  local s = Kit.scale
  local pad = 22 * s
  Theme.col(PAL.cardBorder, 0.22)
  love.graphics.rectangle("fill", x, y + h - 1, w, 1)

  local cx = x + pad
  -- SE badge, the same rounded-square chip shape the launcher's tabs use
  local badge = 34 * s
  local by = y + (h - badge) / 2
  Theme.gradRounded(cx, by, badge, badge, 9 * s, PAL.chipTop, PAL.chipBot, 1, 1)
  Kit.textCenter("tab", "SE", cx, by + (badge - Kit.textHeight("tab")) / 2, badge,
    { 159, 180, 221 })
  cx = cx + badge + 10 * s

  -- The right-aligned action cluster is laid out from the right edge inward
  -- BEFORE anything on the left is drawn: the buttons are the one thing in
  -- this bar that must always be reachable, so on a phone the identity block,
  -- the version chip and the file chip are what yield.  Measuring them last
  -- is why they used to paint straight through the buttons (#497).
  local btnH = 38 * s
  local btnY = y + (h - btnH) / 2
  local rightEdge = x + w - pad
  local gap = 8 * s
  local closeW = 22 * s + Kit.textWidth("button", "Close")
  local openW = 22 * s + Kit.textWidth("button", "Open...")
  local reloadW = 22 * s + Kit.textWidth("button", "Reload")

  local saveLabel, saveKind, saveEnabled = "SAVED", "disabled", false
  if not S.allowSave then
    saveLabel = "SAVE LOCKED"
  elseif S.dirty then
    saveLabel, saveKind, saveEnabled = "SAVE", "primary", true
  end
  local saveW = 30 * s + Kit.textWidth("button", saveLabel)

  local closeX = rightEdge - closeW
  local openX = closeX - gap - openW
  local reloadX = openX - gap - reloadW
  local saveX = reloadX - gap - saveW

  local wordH = Kit.textHeight("wordmark")
  local brandH = Kit.textHeight("brand")
  local blockY = y + (h - (wordH + 2 * s + brandH)) / 2
  local wordW = math.max(
    Theme.spacedWidth(Kit.fonts.wordmark, "SAVE EDITOR", 2 * s),
    Theme.spacedWidth(Kit.fonts.brand, "GEN1RECOMP", 1 * s))
  if cx + wordW + 12 * s < saveX then
    love.graphics.setFont(Kit.fonts.wordmark)
    Theme.col(PAL.heading, 1)
    Theme.spaced(Kit.fonts.wordmark, "SAVE EDITOR", cx, blockY, 2 * s)
    love.graphics.setFont(Kit.fonts.brand)
    Theme.col(PAL.caption, 1)
    Theme.spaced(Kit.fonts.brand, "GEN1RECOMP", cx,
      blockY + wordH + 2 * s, 1 * s)
    cx = cx + wordW + 12 * s
  end

  -- version chip: which game this save belongs to (from the launcher slot,
  -- or the save's own header in a standalone run)
  if S.version then
    local name = S.version:upper()
    local c = (S.version == "blue") and PAL.blue or PAL.red
    local cw = Kit.textWidth("chip", name) + 16 * s
    local ch = 22 * s
    local cy = y + (h - ch) / 2
    if cx + cw + 12 * s < saveX then
      Theme.col(c, 0.1)
      love.graphics.rectangle("fill", cx, cy, cw, ch, 6 * s, 6 * s)
      Theme.stroke(cx, cy, cw, ch, 6 * s, c, 0.5, 1)
      Kit.textCenter("chip", name, cx, cy + (ch - Kit.textHeight("chip")) / 2,
        cw, c)
      cx = cx + cw + 12 * s
    end
  end

  -- Save is the only green-filled control in the chrome; a corrupt load
  -- renders it steel with the reason parked in the status bar rather than
  -- hiding it (rule 3 of the design spec).
  if Kit.button(saveX, btnY, saveW, btnH, saveLabel,
      { kind = saveKind, enabled = saveEnabled or not S.allowSave,
        glow = S.dirty and S.allowSave and 0.6 or nil }) then
    App.save()
  end
  if Kit.button(reloadX, btnY, reloadW, btnH, "Reload") then App.reload() end
  if Kit.button(openX, btnY, openW, btnH, "Open...") then App.chooseAndOpen() end
  if Kit.button(closeX, btnY, closeW, btnH,
      S._quitArmed and "Discard?" or "Close",
      { kind = S._quitArmed and "danger" or "ghost" }) then
    App.close()
  end

  local chipW = (saveX - 14 * s) - cx
  if chipW > 80 * s then
    drawFileChip(cx, y + (h - 38 * s) / 2, chipW, 38 * s)
  end
end

-- Per-tab counters shown under each tile, so the rail doubles as a summary.
local function tabCount(id)
  if id == "party" then
    return ("%d/%d"):format(#S.save.party, require("src.pokemon.Party").MAX)
  elseif id == "boxes" then
    local n = 0
    for _, box in ipairs(Ops.boxes(S)) do n = n + #box end
    return tostring(n)
  elseif id == "items" then
    local Bag = require("src.inventory.Bag")
    return ("%d/%d"):format(Bag.slots(S.save), Bag.capacity(S.data))
  elseif id == "events" then
    local n = 0
    for _ in pairs(S.save.flags or {}) do n = n + 1 end
    return tostring(n)
  elseif id == "map" then
    -- map ids run long (REDS_HOUSE_2F); the rail is a summary, not a label
    return Kit.ellipsize("tiny", S.mapId or "", 110 * Kit.scale)
  elseif id == "dex" then
    local _, owned, total = Ops.dexCounts(S)
    return ("%d/%d"):format(owned, total)
  end
  return ""
end

-- The validation pill mirrors SaveData.validate: green when the report is
-- empty, yellow with counts when the running game would quarantine
-- something.  Returns what to draw plus the tab that owns the first problem,
-- so the rail can reserve the pill's width before laying out the tiles.
local function validationPill()
  local SaveData = require("src.core.SaveData")
  local report = S.validation
  if not report or SaveData.emptyReport(report) then
    return "Save validates clean", PAL.green, nil, true
  end
  local parts = {}
  local target
  local function add(n, singular, plural, tab)
    if n <= 0 then return end
    parts[#parts + 1] = ("%d %s"):format(n, n == 1 and singular or plural)
    target = target or tab
  end
  add(#report.lostMons, "mon", "mons", "party")
  add(#report.lostItems, "item", "items", "items")
  add(#report.remappedMaps, "map", "maps", "map")
  return "Would quarantine " .. table.concat(parts, ", "), PAL.yellow, target, false
end

-- Tab tiles degrade rather than collide: at full width each tile carries its
-- glyph, label and counter; when the validation pill would overlap, the
-- counters drop first and then the labels, leaving the 2-letter glyphs.  A
-- tile is always at least its own square, so every tab stays clickable.
local function railDetail(x, pillX)
  local s = Kit.scale
  local tile = 40 * s
  local widths = { full = 0, nocount = 0, glyph = 0 }
  for _, t in ipairs(TABS) do
    local labelW = Theme.spacedWidth(Kit.fonts.tab, t.label, 1.5 * s)
    local countW = Kit.textWidth("tiny", tabCount(t.id))
    widths.full = widths.full + tile + 9 * s + labelW + 8 * s + countW + 20 * s
    widths.nocount = widths.nocount + tile + 9 * s + labelW + 20 * s
    widths.glyph = widths.glyph + tile + 12 * s
  end
  local avail = pillX - 14 * s - (x + 22 * s)
  -- the widths come back too: the caller needs the glyph-mode figure to decide
  -- whether the pill still has room, and measuring the rail twice is waste
  if widths.full <= avail then return "full", widths end
  if widths.nocount <= avail then return "nocount", widths end
  return "glyph", widths
end

local function drawTabRail(x, y, w, h)
  local s = Kit.scale
  local pad = 22 * s
  Theme.col(PAL.cardBorder, 0.22)
  love.graphics.rectangle("fill", x, y + h - 1, w, 1)

  local label, pillColor, target, clean = validationPill()
  local ph = 26 * s
  local pw = Kit.textWidth("small", label) + 28 * s
  local px = x + w - pad - pw
  local detail, widths = railDetail(x, px)
  -- Last stop before the tiles and the pill collide: at phone widths even the
  -- 2-letter glyph tiles need the room the pill is sitting in, and the pill
  -- only repeats a line the status bar already prints on load, so the pill is
  -- what goes (#497).  With it gone the tiles get the full bar back.
  local showPill = widths.glyph <= px - 14 * s - (x + 22 * s)
  if not showPill then
    detail = railDetail(x, x + w - pad)
  end

  local tile = 40 * s
  local cx = x + pad
  local tileY = y + h - 12 * s - tile
  for _, t in ipairs(TABS) do
    local active = (S.tab == t.id)
    local count = (detail == "full") and tabCount(t.id) or ""
    local labelW = (detail == "glyph") and 0
      or Theme.spacedWidth(Kit.fonts.tab, t.label, 1.5 * s)
    local countW = Kit.textWidth("tiny", count)
    local cellW = (detail == "glyph") and (tile + 12 * s)
      or (tile + 9 * s + labelW + (count ~= "" and 8 * s + countW or 0) + 20 * s)

    Theme.gradRounded(cx, tileY, tile, tile, 11 * s, PAL.chipTop, PAL.chipBot, 1, 1)
    Kit.textCenter("tile", t.glyph, cx, tileY + (tile - Kit.textHeight("tile")) / 2,
      tile, PAL.chipInk)
    if not active then
      -- one tile style plus a scrim, the same trick the launcher uses
      Theme.col(PAL.bgBot, 0.55)
      love.graphics.rectangle("fill", cx, tileY, tile, tile, 11 * s, 11 * s)
    else
      Theme.stroke(cx, tileY, tile, tile, 11 * s, PAL.blue, 0.75, 1.5 * s)
    end

    if detail ~= "glyph" then
      local lx = cx + tile + 9 * s
      love.graphics.setFont(Kit.fonts.tab)
      Theme.col(active and PAL.heading or PAL.muted, 1)
      Theme.spaced(Kit.fonts.tab, t.label, lx,
        tileY + (tile - Kit.textHeight("tab")) / 2, 1.5 * s)
      if count ~= "" then
        Kit.text("tiny", count, lx + labelW + 8 * s,
          tileY + (tile - Kit.textHeight("tiny")) / 2, PAL.faint)
      end
    end

    if active then
      Theme.col(PAL.blue, 1)
      love.graphics.rectangle("fill", cx, y + h - 3 * s,
        math.max(tile, cellW - 20 * s), 3 * s)
    end
    if Kit.press(cx - 8 * s, y, cellW, h) then
      S.tab = t.id
      Kit.blur()
      Ops.disarm(S)
    end
    cx = cx + cellW
  end

  if showPill then
    local py = y + h - 14 * s - ph
    Theme.col(pillColor, clean and 0.08 or 0.1)
    love.graphics.rectangle("fill", px, py, pw, ph, ph / 2, ph / 2)
    Theme.stroke(px, py, pw, ph, ph / 2, pillColor, clean and 0.45 or 0.5, 1)
    Kit.textCenter("small", label, px, py + (ph - Kit.textHeight("small")) / 2,
      pw, pillColor)
    -- paint and hit target are suppressed together, so a hidden pill cannot
    -- still eat a tap meant for the DEX tile
    if target and Kit.press(px, py, pw, ph) then
      S.tab = target
      Ops.say(S, "Jumped to the tab holding the first quarantine warning")
    end
  end
end

local function drawStatusBar(x, y, w, h)
  local s = Kit.scale
  local pad = 22 * s
  Theme.col(PAL.bgBot, 0.6)
  love.graphics.rectangle("fill", x, y, w, h)
  Theme.col(PAL.cardBorder, 0.22)
  love.graphics.rectangle("fill", x, y, w, 1)

  local ctrl = (love.system and love.system.getOS
    and love.system.getOS() == "OS X") and "Cmd" or "Ctrl"
  local hint = S.embedded
    and (ctrl .. "+S save . " .. ctrl ..
         "+R reload . Esc clear selection . Close returns to the launcher")
    or (ctrl .. "+S save . " .. ctrl ..
        "+R reload . Esc clear selection . arrows pan map . wheel scrolls lists")
  local hintW = Kit.textWidth("tiny", hint)
  Kit.textRight("tiny", hint, x + w - pad, y + (h - Kit.textHeight("tiny")) / 2, PAL.faint)
  local avail = w - 2 * pad - hintW - 14 * s
  Kit.text("mono", Kit.ellipsize("mono", S.status or "", avail), x + pad,
    y + (h - Kit.textHeight("mono")) / 2, PAL.detail)
end

function App.draw()
  -- Closing the editor unloads it, and the host may still deliver one more
  -- frame or a queued event before it re-routes; every entry point below
  -- tolerates that rather than indexing a torn-down state.
  if not S then return end
  local width, height = love.graphics.getDimensions()
  Kit.layout(width, height)
  local s = Kit.scale

  local mx, my = love.mouse.getPosition()
  Kit.beginFrame(mx, my, mouseClicked, wheelY)
  mouseClicked = false
  wheelY = 0
  -- Modal shield.  Kit has no z-order, so the picker cannot simply be drawn
  -- last: the chrome and the panel underneath would take the same tap.  The
  -- shield goes up before anything dispatches and comes down only for the
  -- picker's own layer at the bottom of this function (#541).
  Kit.blockClicks = (S.speciesPicker ~= nil)

  Theme.field(width, height)

  local railH = 6 * s
  local titleH = 64 * s
  local tabH = 66 * s
  local statusH = 38 * s

  Theme.versionRail(0, 0, width, railH)
  drawTitleBar(0, railH, width, titleH)
  drawTabRail(0, railH + titleH, width, tabH)

  local contentY = railH + titleH + tabH
  local contentH = height - contentY - statusH
  local panel = PANELS[S.tab]
  if panel then
    panel.draw(S, Kit, 22 * s, contentY + 20 * s,
      width - 44 * s, contentH - 38 * s)
  end

  drawStatusBar(0, height - statusH, width, statusH)
  Kit.blockClicks = false
  SpeciesPicker.draw(S, Kit, width, height)
  Kit.endFrame()

  -- Only now, with the whole frame painted, is it safe to drop the editor.
  if S._closeRequested then finishClose() end
end

function App.keypressed(key)
  if not S then return end
  -- The picker takes Enter and Escape before the focused field does: Kit maps
  -- both to the same "\r" edit (a blur), which cannot tell "commit the top
  -- match" apart from "give up" (#541).
  if S.speciesPicker then
    if key == "return" or key == "kpenter" then
      SpeciesPicker.commitFirst(S, Kit)
      return
    elseif key == "escape" then
      Ops.closeSpeciesPicker(S, Kit)
      return
    end
  end
  -- A focused text field eats the keys it cares about (typing "s" into the
  -- map filter must not trigger Save).
  if Kit.keypressed(key) then return end
  if Kit.focus then
    if key == "escape" then Kit.blur() end
    return
  end
  -- Save and Reload both touch the file on disk (Reload discards unsaved
  -- edits), so they need a modifier.  A bare letter is one stray keystroke
  -- away from a write, and the editor has no undo.
  local mod = love.keyboard and love.keyboard.isDown
    and (love.keyboard.isDown("lgui", "rgui")
      or love.keyboard.isDown("lctrl", "rctrl"))
  if key == "escape" then
    S.editingMon = nil
    Ops.disarm(S)
    Ops.say(S, "Selection cleared")
  elseif key == "s" and mod then
    App.save()
  elseif key == "r" and mod then
    App.reload()
  end
  if S.tab == "map" and MapBrowser.keypressed then
    MapBrowser.keypressed(S, key)
  end
end

function App.wheelmoved(x, y)
  if not S then return end
  -- The map tab spends the wheel on zoom; every other tab routes it through
  -- Kit so whichever list the pointer is over takes it next draw (#595).
  if S.tab == "map" and MapBrowser.wheelmoved then
    MapBrowser.wheelmoved(S, y)
    return
  end
  wheelY = wheelY + (y or 0)
end

function App.quit()
  if not S then return false end
  if S.dirty then
    -- simple: block quit once and set status; user saves or force-quits again
    if not S._quitArmed then
      S._quitArmed = true
      S.status = "Unsaved changes,  save or press quit again"
      return true
    end
  end
  return false
end

return App
