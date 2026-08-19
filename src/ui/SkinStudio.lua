local Kit = require("src.ui.kit.Kit")
local Theme = require("src.ui.kit.Theme")
local PAL = Theme.PAL
local TouchSkin = require("src.core.TouchSkin")
local TouchControls = require("src.core.TouchControls")
local SaveData = require("src.core.SaveData")
local FilePicker = require("src.core.FilePicker")

local Studio = {}

Studio.CANVASES = {
  { id = "phone_portrait", label = "Phone portrait", w = 1080, h = 1920 },
  { id = "phone_landscape", label = "Phone landscape", w = 1920, h = 1080 },
  { id = "tablet_portrait", label = "Tablet portrait", w = 1536, h = 2048 },
  { id = "tablet_landscape", label = "Tablet landscape", w = 2048, h = 1536 },
  { id = "steamdeck", label = "Steam Deck", w = 1280, h = 800 },
  { id = "desktop_1080", label = "Desktop 1080p", w = 1920, h = 1080 },
  { id = "ultrawide", label = "Ultrawide 21:9", w = 2560, h = 1080 },
  { id = "sgb_border", label = "Super Game Boy border", w = 256, h = 224,
    lockViewport = { x = 48 / 256, y = 40 / 224, w = 160 / 256, h = 144 / 224 } },
}

-- Per-page lock, and whether the canvas preset follows it.  Match is on
-- by default so a portrait/landscape overlay pair does not need two
-- separate clicks to preview the right way up.  #1503
Studio.matchOrient = true
Studio.ORIENT_CYCLE = { "any", "portrait", "landscape" }
Studio.ORIENT_LABEL = {
  any = "Lock: Off",
  portrait = "Lock: Portrait",
  landscape = "Lock: Landscape",
}

local HANDLE = 7
local HANDLES = {
  { "nw", 0, 0 }, { "n", 0.5, 0 }, { "ne", 1, 0 },
  { "w", 0, 0.5 }, { "e", 1, 0.5 },
  { "sw", 0, 1 }, { "s", 0.5, 1 }, { "se", 1, 1 },
}

local GB_ASPECT = 160 / 144

Studio.UNDO_CAP = 50
Studio.SNAP_PX = 4
Studio.STATUS_HOLD = 4

Studio.FORMAT_LABEL = {
  native = "gen1recomp",
  retroarch = "RetroArch",
  delta = "Delta",
}

Studio.EXPORTS = {
  { id = "native", label = "gen1recomp .zip",
    hint = "Reopens here and in the launcher." },
  { id = "retroarch", label = "RetroArch .zip",
    hint = "An overlay .cfg RetroArch can load." },
  { id = "delta", label = "Delta .deltaskin",
    hint = "info.json plus art, for Delta and Ignited." },
}

Studio.BIND_GROUPS = {
  { title = "GAME BOY",
    specs = { "a", "b", "start", "select", "up", "down", "left", "right" } },
  { title = "DIAGONALS",
    specs = { "left|up", "right|up", "left|down", "right|down" } },
  { title = "HOTKEYS",
    specs = { "menu_toggle", "reset", "hold_fast_forward",
              "toggle_fast_forward", "overlay_next", "overlay_previous",
              "pause_toggle", "screenshot", "exit_emulator" } },
  { title = "KEYBOARD",
    specs = { "key:escape", "key:return", "key:space", "key:tab", "key:f1" } },
  { title = "NO INPUT", specs = { "nul" } },
}

Studio.BIND_PARTS = { "left", "right", "up", "down", "a", "b", "start", "select" }

local PART_RANK = {
  left = 1, right = 2, up = 3, down = 4,
  a = 5, b = 6, start = 7, select = 8,
}

local function now()
  if love and love.timer and love.timer.getTime then return love.timer.getTime() end
  return 0
end

local function clamp01(v)
  if v ~= v then return 0 end
  if v < 0 then return 0 end
  if v > 1 then return 1 end
  return v
end

local function round(v) return math.floor(v + 0.5) end

function Studio.canvas()
  return Studio.CANVASES[Studio.canvasIndex] or Studio.CANVASES[1]
end

function Studio.page()
  local skin = Studio.skin
  if not skin then return nil end
  return skin.pages[Studio.pageIndex] or skin.pages[1]
end

function Studio.selectedControl()
  local page = Studio.page()
  if not page then return nil end
  return page.controls[Studio.selected]
end

local function setStatus(text, isError)
  Studio.status = text
  Studio.statusErr = isError == true
  Studio.statusAt = now()
end
Studio.setStatus = setStatus

function Studio.expireStatus()
  if not Studio.statusErr or not Studio.status then return end
  if now() - (Studio.statusAt or 0) > Studio.STATUS_HOLD then
    Studio.status, Studio.statusErr = nil, false
  end
end

local function markDirty()
  Studio.dirty = true
  if not Studio.statusErr then Studio.status = nil end
end

local function snapshot()
  return {
    skin = TouchSkin.clone(Studio.skin),
    pageIndex = Studio.pageIndex,
    selected = Studio.selected,
    idField = Studio.skinIdField,
  }
end

local function restore(snap)
  Studio.skin = snap.skin
  Studio.pageIndex = snap.pageIndex or 1
  Studio.selected = snap.selected
  Studio.skinIdField = snap.idField or Studio.skinIdField
  TouchSkin.setActive(Studio.skin)
  TouchSkin.pageIndex = Studio.pageIndex
  Studio.dirty = true
end

function Studio.pushUndo(tag)
  if not Studio.skin then return false end
  Studio.undoStack = Studio.undoStack or {}
  Studio.redoStack = {}
  if tag and Studio.undoTag == tag and now() - (Studio.undoAt or 0) < 1 then
    return false
  end
  Studio.undoTag, Studio.undoAt = tag, now()
  local stack = Studio.undoStack
  stack[#stack + 1] = snapshot()
  while #stack > Studio.UNDO_CAP do table.remove(stack, 1) end
  return true
end

function Studio.undo()
  local stack = Studio.undoStack or {}
  local snap = stack[#stack]
  if not snap then
    setStatus("Nothing to undo.")
    return false
  end
  table.remove(stack)
  Studio.redoStack = Studio.redoStack or {}
  Studio.redoStack[#Studio.redoStack + 1] = snapshot()
  Studio.undoTag = nil
  restore(snap)
  setStatus("Undo")
  return true
end

function Studio.redo()
  local stack = Studio.redoStack or {}
  local snap = stack[#stack]
  if not snap then
    setStatus("Nothing to redo.")
    return false
  end
  table.remove(stack)
  Studio.undoStack = Studio.undoStack or {}
  Studio.undoStack[#Studio.undoStack + 1] = snapshot()
  Studio.undoTag = nil
  restore(snap)
  setStatus("Redo")
  return true
end

function Studio.canUndo() return #(Studio.undoStack or {}) > 0 end
function Studio.canRedo() return #(Studio.redoStack or {}) > 0 end

function Studio.openModal(kind, data)
  data = data or {}
  data.kind = kind
  data.scroll = 0
  Studio.modal = data
  return data
end

function Studio.closeModal()
  Studio.modal = nil
  Kit.blur()
end

function Studio.modalUp()
  return Studio.modal ~= nil or Studio.confirm ~= nil
end

function Studio.ask(text, onYes, yesLabel)
  Studio.confirm = { text = text, onYes = onYes,
                     yesLabel = yesLabel or "Discard" }
  return Studio.confirm
end

function Studio.confirmYes()
  local c = Studio.confirm
  Studio.confirm = nil
  if c and c.onYes then c.onYes() end
  return c ~= nil
end

function Studio.confirmNo()
  local had = Studio.confirm ~= nil
  Studio.confirm = nil
  return had
end

function Studio.guard(text, fn)
  if not Studio.dirty or not Studio.skin then
    fn()
    return true
  end
  Studio.ask(text, fn)
  return false
end

local function syncActive()
  TouchSkin.setActive(Studio.skin)
  TouchSkin.pageIndex = Studio.pageIndex
end

local function canvasOrientation(canvas)
  canvas = canvas or Studio.canvas()
  if not canvas then return nil end
  return canvas.w > canvas.h and "landscape" or "portrait"
end

local function pickCanvasIndex(want)
  local cur = Studio.canvas()
  if canvasOrientation(cur) == want then return Studio.canvasIndex end
  if cur and cur.id then
    local hint = cur.id:gsub("portrait", want):gsub("landscape", want)
    for i, c in ipairs(Studio.CANVASES) do
      if c.id == hint then return i end
    end
  end
  for i, c in ipairs(Studio.CANVASES) do
    if canvasOrientation(c) == want and not c.lockViewport then return i end
  end
  return nil
end

function Studio.applyImportedOrient()
  if not Studio.skin then return false end
  if not TouchSkin.hasOrientPair(Studio.skin) then
    Studio.syncCanvasToPage()
    return false
  end
  -- A RetroArch overlay that already auto-rotates should do the same in
  -- the studio: lock is on, canvas follows, and the visible page matches
  -- the mock device.  #1503
  Studio.matchOrient = true
  Studio.syncPageToCanvas()
  Studio.syncCanvasToPage()
  return true
end

function Studio.syncCanvasToPage()
  if not Studio.matchOrient then return end
  local want = TouchSkin.pageOrient(Studio.page())
  if not want then return end
  local idx = pickCanvasIndex(want)
  if idx and idx ~= Studio.canvasIndex then Studio.setCanvas(idx, true) end
end

function Studio.syncPageToCanvas()
  if not Studio.matchOrient or not Studio.skin then return end
  local want = canvasOrientation()
  if TouchSkin.pageOrient(Studio.page()) == want then return end
  for i, page in ipairs(Studio.skin.pages or {}) do
    if TouchSkin.pageOrient(page) == want then
      Studio.pageIndex = i
      Studio.selected = nil
      syncActive()
      return
    end
  end
end

function Studio.cyclePageOrient(dir)
  local page = Studio.page()
  if not page then return end
  local cur = TouchSkin.pageOrient(page) or "any"
  local idx = 1
  for i, o in ipairs(Studio.ORIENT_CYCLE) do
    if o == cur then idx = i break end
  end
  local n = #Studio.ORIENT_CYCLE
  local nxt = Studio.ORIENT_CYCLE[((idx - 1 + (dir or 1)) % n) + 1]
  page.orient = nxt
  local name = tostring(page.name or "")
  if (nxt == "portrait" or nxt == "landscape")
     and (name == "" or name == "main" or name:match("^page%d+$")) then
    page.name = nxt
  end
  markDirty()
  Studio.syncCanvasToPage()
  return nxt
end

function Studio.setCanvas(index, fromSync)
  local n = #Studio.CANVASES
  Studio.canvasIndex = ((index - 1) % n) + 1
  -- Pick the matching page before writing canvas-owned fields onto it,
  -- so a landscape preset does not stamp a portrait page.  #1503
  if not fromSync then Studio.syncPageToCanvas() end
  local canvas = Studio.canvas()
  local page = Studio.page()
  if page and canvas.lockViewport then
    page.viewport = {
      x = canvas.lockViewport.x, y = canvas.lockViewport.y,
      w = canvas.lockViewport.w, h = canvas.lockViewport.h,
    }
    page.viewportFill = false
    markDirty()
  end
  -- A cfg-authored aspect_ratio is the overlay's design aspect; keep it so
  -- the preview letterboxes like RetroArch instead of stretching (#1503).
  if page and not page.aspectFromCfg then
    page.aspect = canvas.w / canvas.h
  end
end

function Studio.load(opts)
  opts = opts or {}
  Studio.onClose = opts.onClose
  Studio.onPlay = opts.onPlay
  Studio.version = opts.version
  Studio.pageIndex = 1
  Studio.selected = nil
  Studio.testing = false
  Studio.dirty = false
  Studio.status = nil
  Studio.drag = nil
  Studio.pendingPlay = false
  Studio.canvasIndex = 1
  Studio.aspectLock = true
  Studio.skinIdField = ""
  Studio.available = TouchSkin.list()
  Studio.availableMeta = {}
  Studio.imageTarget = "idle"
  Studio.undoStack, Studio.redoStack = {}, {}
  Studio.undoTag, Studio.undoAt = nil, nil
  Studio.modal, Studio.confirm = nil, nil
  Studio.guides = nil
  Studio.showLabels = true
  Studio.statusErr = false
  Studio.thumbs = {}

  TouchControls:init()
  TouchControls.active = true
  TouchControls.enabled = true
  TouchControls:setPreview(true)
  -- Play snaps pages from the window aspect.  The studio uses its own
  -- Match canvas toggle against the mock device instead.  #1503
  TouchSkin.autoOrient = false
  Studio.matchOrient = true

  local start = opts.skinId
  if not start then
    local saved = SaveData.loadOptions()
    local tc = type(saved.touchControls) == "table" and saved.touchControls or {}
    start = tc.skin
  end
  if start and TouchSkin.find(start) then
    Studio.open(start)
  else
    Studio.skin = TouchSkin.newSkin("new_skin")
    Studio.skinIdField = Studio.skin.id
    syncActive()
  end
end

function Studio.open(id)
  local entry = TouchSkin.find(id)
  if not entry then return false end
  local loaded = TouchSkin.load(entry.root, entry.id)
  if not loaded then return false end
  Studio.skin = TouchSkin.clone(loaded)
  Studio.skinIdField = Studio.skin.id
  Studio.pageIndex = 1
  Studio.selected = nil
  Studio.dirty = false
  Studio.images = TouchSkin.listImages(Studio.skin.root)
  Studio.undoStack, Studio.redoStack = {}, {}
  Studio.undoTag = nil
  Studio.thumbs = {}
  syncActive()
  Studio.applyImportedOrient()
  return true
end

function Studio.newSkin()
  Studio.pushUndo()
  Studio.skin = TouchSkin.newSkin("new_skin")
  Studio.skinIdField = "new_skin"
  Studio.pageIndex, Studio.selected = 1, nil
  Studio.images = {}
  Studio.thumbs = {}
  syncActive()
  markDirty()
end

function Studio.skinFormat(skin)
  skin = skin or Studio.skin
  local fmt = skin and skin.format or "native"
  return Studio.FORMAT_LABEL[fmt] or fmt
end

function Studio.describeSkin(entry)
  Studio.availableMeta = Studio.availableMeta or {}
  local meta = Studio.availableMeta[entry.id]
  if meta then return meta end
  local skin = TouchSkin.load(entry.root, entry.id)
  local page = skin and skin.pages[1]
  local controls = 0
  for _, ctl in ipairs(page and page.controls or {}) do
    if not ctl.decorative then controls = controls + 1 end
  end
  meta = {
    id = entry.id,
    source = entry.source,
    format = Studio.skinFormat(skin),
    pages = skin and #skin.pages or 0,
    controls = controls,
    ok = skin ~= nil,
  }
  Studio.availableMeta[entry.id] = meta
  return meta
end

function Studio.skinSummary(entry)
  local meta = Studio.describeSkin(entry)
  local bits = { meta.source == "user" and "installed" or "bundled", meta.format }
  bits[#bits + 1] = meta.controls .. " buttons"
  if meta.pages > 1 then bits[#bits + 1] = meta.pages .. " pages" end
  return table.concat(bits, "  \194\183  ")
end

function Studio.refreshAvailable()
  Studio.available = TouchSkin.list()
  Studio.availableMeta = {}
  return Studio.available
end

function Studio.openLoadPicker()
  return Studio.guard("Open another skin and lose the unsaved changes?",
    function()
      Studio.refreshAvailable()
      Studio.openModal("open")
    end)
end

function Studio.loadEntry(id)
  Studio.closeModal()
  if not Studio.open(id) then
    setStatus("Could not open " .. tostring(id), true)
    return false
  end
  local warning = Studio.skin and Studio.skin.warnings
    and Studio.skin.warnings[1]
  if warning then
    setStatus("Opened " .. id .. ": " .. tostring(warning), true)
  else
    setStatus("Opened " .. id)
  end
  return true
end

function Studio.unload()
  Studio.pendingPlay = false
  TouchSkin.setSurface(nil)
  TouchSkin.setActive(nil)
  TouchSkin.autoOrient = true
  TouchControls:setPreview(false)
  TouchControls:reset()
  Studio.skin = nil
  Studio.onClose = nil
  Studio.onPlay = nil
  Studio.drag = nil
  Studio.modal, Studio.confirm = nil, nil
  Studio.guides = nil
  Studio.undoStack, Studio.redoStack = {}, {}
end

-- --------------------------------------------------------------- editing

function Studio.addControl()
  local page = Studio.page()
  if not page then return end
  Studio.pushUndo()
  page.controls[#page.controls + 1] =
    TouchSkin.newControl("a", 0.5, 0.5, 0.16, 0.09, "radial")
  Studio.selected = #page.controls
  markDirty()
end

function Studio.deleteControl()
  local page = Studio.page()
  if not page or not Studio.selected then return end
  Studio.pushUndo()
  table.remove(page.controls, Studio.selected)
  Studio.selected = page.controls[Studio.selected] and Studio.selected
    or (#page.controls > 0 and #page.controls or nil)
  markDirty()
end

function Studio.duplicateControl()
  local page, ctl = Studio.page(), Studio.selectedControl()
  if not page or not ctl then return end
  Studio.pushUndo()
  local copy = TouchSkin.newControl(ctl.spec, clamp01(ctl.x + 0.04),
    clamp01(ctl.y + 0.04), ctl.rangeX * 2, ctl.rangeY * 2, ctl.shape)
  copy.imagePath, copy.image = ctl.imagePath, ctl.image
  copy.pressedImagePath, copy.pressedImage = ctl.pressedImagePath, ctl.pressedImage
  copy.rangeMod, copy.alphaMod = ctl.rangeMod, ctl.alphaMod
  table.insert(page.controls, Studio.selected + 1, copy)
  Studio.selected = Studio.selected + 1
  markDirty()
end

function Studio.cycleBind(dir)
  local ctl = Studio.selectedControl()
  if not ctl then return end
  local list, at = TouchSkin.BINDS, 1
  for i, spec in ipairs(list) do
    if spec == ctl.spec then at = i break end
  end
  Studio.pushUndo("bind")
  TouchSkin.setBind(ctl, list[((at - 1 + dir) % #list) + 1])
  markDirty()
end

function Studio.bindParts(spec)
  local out = {}
  for raw in tostring(spec or ""):gmatch("[^|]+") do
    local name = raw:gsub("^%s+", ""):gsub("%s+$", ""):lower()
    if name ~= "" and name ~= "nul" then out[#out + 1] = name end
  end
  return out
end

function Studio.hasBindPart(spec, part)
  for _, name in ipairs(Studio.bindParts(spec)) do
    if name == part then return true end
  end
  return false
end

function Studio.toggleBindPart(spec, part)
  local kept, found = {}, false
  for _, name in ipairs(Studio.bindParts(spec)) do
    if name == part then
      found = true
    else
      kept[#kept + 1] = name
    end
  end
  if not found then kept[#kept + 1] = part end
  if #kept == 0 then return "nul" end
  table.sort(kept, function(a, b)
    local ra, rb = PART_RANK[a] or 9, PART_RANK[b] or 9
    if ra ~= rb then return ra < rb end
    return a < b
  end)
  return table.concat(kept, "|")
end

function Studio.setBindSpec(spec)
  local ctl = Studio.selectedControl()
  if not ctl or not spec then return false end
  Studio.pushUndo()
  TouchSkin.setBind(ctl, spec)
  markDirty()
  return true
end

function Studio.toggleSelectedBindPart(part)
  local ctl = Studio.selectedControl()
  if not ctl then return false end
  return Studio.setBindSpec(Studio.toggleBindPart(ctl.spec, part))
end

function Studio.openBindPicker()
  if not Studio.selectedControl() then
    setStatus("Select a control first.", true)
    return false
  end
  Studio.openModal("bind")
  return true
end

function Studio.moveControlOrder(delta)
  local page, i = Studio.page(), Studio.selected
  if not page or not i then return false end
  local j = i + delta
  if j < 1 or j > #page.controls then return false end
  Studio.pushUndo()
  page.controls[i], page.controls[j] = page.controls[j], page.controls[i]
  Studio.selected = j
  markDirty()
  return true
end

function Studio.nudge(dx, dy, big)
  local ctl = Studio.selectedControl()
  if not ctl then return false end
  local canvas = Studio.canvas()
  local step = big and 10 or 1
  Studio.pushUndo("nudge")
  ctl.x = clamp01(ctl.x + dx * step / canvas.w)
  ctl.y = clamp01(ctl.y + dy * step / canvas.h)
  markDirty()
  return true
end

function Studio.snapOffset(edges, lines, tol)
  local best, at = nil, nil
  for _, e in ipairs(edges) do
    for _, l in ipairs(lines) do
      local d = l - e
      if math.abs(d) <= tol and (best == nil or math.abs(d) < math.abs(best)) then
        best, at = d, l
      end
    end
  end
  return best or 0, at
end


function Studio.cycleImage(dir)
  local ctl = Studio.selectedControl()
  local page = Studio.page()
  if not page then return end
  Studio.images = Studio.images or TouchSkin.listImages(Studio.skin.root)
  local list = Studio.images
  local field = Studio.imageTarget
  local owner = (field == "bezel") and page or ctl
  if not owner then return end
  local key = (field == "pressed") and "pressedImagePath" or "imagePath"
  if field == "bezel" then key = "imagePath" end

  local at = 0
  for i, rel in ipairs(list) do
    if rel == owner[key] then at = i break end
  end
  local next_ = at + dir
  if next_ < 0 then next_ = #list end
  if next_ > #list then next_ = 0 end
  local rel = (next_ >= 1) and list[next_] or nil
  owner[key] = rel
  local img = rel and TouchSkin.resolveImage(Studio.skin.root, rel) or nil
  if field == "pressed" then owner.pressedImage = img else owner.image = img end
  markDirty()
end

function Studio.refreshImages()
  Studio.images = Studio.skin and TouchSkin.listImages(Studio.skin.root) or {}
  Studio.thumbs = {}
  return Studio.images
end

function Studio.openImagePicker(target)
  if not Studio.skin then return false end
  target = target or Studio.imageTarget
  if target ~= "bezel" and not Studio.selectedControl() then
    setStatus("Select a control first, or pick a bezel image.", true)
    return false
  end
  Studio.imageTarget = target
  Studio.refreshImages()
  Studio.openModal("image")
  return true
end

function Studio.currentImagePath()
  local target = Studio.imageTarget
  if target == "bezel" then
    local page = Studio.page()
    return page and page.imagePath
  end
  local ctl = Studio.selectedControl()
  if not ctl then return nil end
  return (target == "pressed") and ctl.pressedImagePath or ctl.imagePath
end

function Studio.thumb(rel)
  if not rel or not Studio.skin then return nil end
  Studio.thumbs = Studio.thumbs or {}
  local cached = Studio.thumbs[rel]
  if cached ~= nil then return cached or nil end
  local img = TouchSkin.resolveImage(Studio.skin.root, rel)
  Studio.thumbs[rel] = img or false
  return img
end

function Studio.chooseImage(rel)
  if not Studio.skin then return false end
  Studio.pushUndo()
  Studio.assignImage(rel)
  Studio.closeModal()
  setStatus(rel and ("Using " .. rel .. " as " .. Studio.imageTargetLabel())
    or ("Cleared the " .. Studio.imageTargetLabel()))
  return true
end

function Studio.imageTargetLabel()
  local target = Studio.imageTarget
  if target == "bezel" or not Studio.selectedControl() then return "bezel" end
  return target == "pressed" and "pressed art" or "idle art"
end

function Studio.assignImage(rel)
  local page, ctl = Studio.page(), Studio.selectedControl()
  local img = TouchSkin.resolveImage(Studio.skin.root, rel)
  local target = Studio.imageTarget
  if ctl and target == "pressed" then
    ctl.pressedImagePath, ctl.pressedImage = rel, img
  elseif ctl and target == "idle" then
    ctl.imagePath, ctl.image = rel, img
  elseif page then
    page.imagePath, page.image = rel, img
  end
  Studio.images = TouchSkin.listImages(Studio.skin.root)
  Studio.dirty = true
end

local function commitSkinId()
  local skin = Studio.skin
  if not skin then return end
  local id = (Studio.skinIdField or ""):gsub("[^%w_%-]", "")
  if id == "" or id == skin.id then return end
  TouchSkin.saveTo(skin, id)
  Studio.available = TouchSkin.list()
end

function Studio.adoptImage(name, data, target)
  if not Studio.skin then return false end
  if target then Studio.imageTarget = target end
  if not FilePicker.matches(name, FilePicker.IMAGE) then
    setStatus("Pick a PNG or JPG.", true)
    return false
  end
  commitSkinId()
  local rel, err = TouchSkin.importImage(Studio.skin, name, data)
  if not rel then
    setStatus("Import failed: " .. tostring(err), true)
    return false
  end
  local where = Studio.imageTargetLabel()
  Studio.pushUndo()
  Studio.assignImage(rel)
  Studio.skinIdField = Studio.skin.id
  local text = "Imported " .. rel .. " as " .. where
  if where == "bezel" and not Studio.canvas().lockViewport then
    text = text .. " -- use Detect screen from bezel to place the screen"
  end
  setStatus(text)
  return true
end

function Studio.importImageFile(target)
  if not Studio.skin then return end
  target = target or Studio.imageTarget
  Studio.imageTarget = target
  if target ~= "bezel" and not Studio.selectedControl() then
    setStatus("Select a control first, or import a bezel image.", true)
    return
  end
  if not FilePicker.available() then
    setStatus("No file picker here -- drag a PNG onto the window instead.", true)
    return
  end
  local prompt = (target == "bezel") and "Choose a bezel image"
    or "Choose a button image"
  local path = FilePicker.open(prompt, FilePicker.IMAGE)
  if not path then return end
  local base = FilePicker.basename(path)
  local data, err = FilePicker.read(path)
  if not data then
    setStatus("Could not read " .. base .. ": " .. tostring(err), true)
    return
  end
  Studio.adoptImage(base, data, target)
end

function Studio.filedropped(file)
  if not Studio.skin then return end
  local path = (file.getFilename and file:getFilename()) or ""
  local base = FilePicker.basename(path)
  if not FilePicker.matches(base, FilePicker.IMAGE) then
    setStatus("Drop a PNG or JPG to use it as art.", true)
    return
  end
  local ok, data = pcall(function()
    file:open("r")
    local bytes = file:read()
    file:close()
    return bytes
  end)
  if not ok or not data then
    setStatus("Could not read " .. base, true)
    return
  end
  Studio.adoptImage(base, data)
end

function Studio.detectViewport()
  local page = Studio.page()
  if not page or not Studio.skin then return end
  if Studio.canvas().lockViewport then
    setStatus("This preset locks the screen position.", true)
    return
  end
  if not page.imagePath then
    setStatus("Pick a bezel image first.", true)
    return
  end
  local rect, pw, ph = TouchSkin.detectViewport(Studio.skin.root, page.imagePath)
  if not rect then
    setStatus("No transparent screen hole found in " .. page.imagePath, true)
    return
  end
  Studio.pushUndo()
  page.viewport = rect
  page.screenFit = nil
  setStatus(("Screen detected: %dx%d px in the bezel art"):format(pw, ph))
  Studio.dirty = true
end

function Studio.toggleViewport()
  local page = Studio.page()
  if not page then return end
  if Studio.canvas().lockViewport then return end
  Studio.pushUndo()
  if page.viewport or page.screenFit == "remainder" then
    page.viewport = nil
    page.screenFit = nil
  else
    page.viewport = { x = 0.1, y = 0.05, w = 0.8, h = 0.45 }
  end
  markDirty()
end

function Studio.setPage(index)
  local skin = Studio.skin
  if not skin or not skin.pages[index] then return false end
  Studio.pageIndex = index
  Studio.selected = nil
  syncActive()
  Studio.syncCanvasToPage()
  return true
end

function Studio.nextPage()
  local skin = Studio.skin
  if not skin or #skin.pages == 0 then return false end
  return Studio.setPage((Studio.pageIndex % #skin.pages) + 1)
end

function Studio.pageLabel(index)
  local skin = Studio.skin
  local page = skin and skin.pages[index]
  if not page then return "" end
  local name = tostring(page.name or ("page" .. index))
  local orient = TouchSkin.pageOrient(page)
  local bits = { #(page.controls or {}) .. " controls" }
  if orient then bits[#bits + 1] = orient end
  if page.viewport or page.screenFit == "remainder" then bits[#bits + 1] = "screen" end
  return name, table.concat(bits, "  \194\183  ")
end

function Studio.openPageMenu()
  local skin = Studio.skin
  if not skin then return false end
  Studio.pageNameField = tostring(Studio.page() and Studio.page().name or "")
  Studio.openModal("page")
  return true
end

function Studio.renamePage(name)
  local page = Studio.page()
  if not page then return false end
  name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if name == "" then
    setStatus("Give the page a name first.", true)
    return false
  end
  Studio.pushUndo()
  page.name = name
  markDirty()
  setStatus("Renamed page " .. Studio.pageIndex .. " to " .. name)
  return true
end

function Studio.deletePage(index)
  local skin = Studio.skin
  index = index or Studio.pageIndex
  if not skin or not skin.pages[index] then return false end
  if #skin.pages <= 1 then
    setStatus("A skin needs at least one page.", true)
    return false
  end
  Studio.pushUndo()
  table.remove(skin.pages, index)
  for i, page in ipairs(skin.pages) do page.index = i end
  Studio.pageIndex = math.min(Studio.pageIndex, #skin.pages)
  Studio.selected = nil
  syncActive()
  markDirty()
  setStatus("Deleted a page")
  return true
end

function Studio.addPage()
  local skin = Studio.skin
  if not skin then return end
  Studio.pushUndo()
  local page = TouchSkin.newSkin(skin.id).pages[1]
  page.name = "page" .. (#skin.pages + 1)
  page.index = #skin.pages + 1
  skin.pages[#skin.pages + 1] = page
  Studio.pageIndex = #skin.pages
  Studio.selected = nil
  syncActive()
  Studio.syncCanvasToPage()
  markDirty()
end

function Studio.save()
  local skin = Studio.skin
  if not skin then return end
  local id = (Studio.skinIdField or ""):gsub("[^%w_%-]", "")
  if id == "" then
    setStatus("Give the skin a name first.", true)
    return
  end
  local dest, failed = TouchSkin.saveTo(skin, id)
  if not dest then
    setStatus("Save failed: " .. tostring(failed), true)
    return
  end
  Studio.dirty = false
  Studio.refreshAvailable()
  local text = "Saved to " .. dest
  if type(failed) == "table" and failed[1] then
    text = text .. " (" .. #failed .. " image(s) not found)"
  end
  setStatus(text)
end

function Studio.exportAs(kind)
  local skin = Studio.skin
  if not skin then return nil end
  if Studio.dirty then Studio.save() end
  if Studio.dirty then return nil end
  local path, missing, warnings
  if kind == "retroarch" then
    path, missing = TouchSkin.exportRetroArch(skin)
  elseif kind == "delta" then
    path, missing, warnings = TouchSkin.exportDelta(skin)
  else
    path, missing = TouchSkin.export(skin)
  end
  if not path then
    setStatus("Export failed: " .. tostring(missing), true)
    return nil
  end
  local text = "Exported " .. path
  if type(missing) == "table" and missing[1] then
    text = text .. " (" .. #missing .. " image(s) not found)"
  end
  if type(warnings) == "table" and warnings[1] then
    text = text .. " " .. tostring(warnings[1])
  end
  setStatus(text)
  Studio.lastExport = path
  Studio.refreshAvailable()
  return path
end

function Studio.export()
  return Studio.exportAs("native")
end

function Studio.openExportMenu()
  Studio.openModal("export")
  return true
end

function Studio.fileUrl(path)
  path = tostring(path):gsub("\\", "/")
  if path:sub(1, 1) ~= "/" then path = "/" .. path end
  local encoded = path:gsub("[^%w%-%._~/:]", function(c)
    return string.format("%%%02X", string.byte(c))
  end)
  return "file://" .. encoded
end

function Studio.revealExport()
  local path = Studio.lastExport
  if not path then return false end
  if not (love and love.filesystem and love.filesystem.getSaveDirectory) then
    return false
  end
  local dir = love.filesystem.getSaveDirectory()
  if not dir then return false end
  if love.system and love.system.openURL then
    pcall(love.system.openURL, Studio.fileUrl(dir))
  end
  setStatus("Saved in " .. dir .. "/" .. path)
  return true
end

function Studio.play()
  local skin = Studio.skin
  if not skin then return end
  Studio.save()
  if Studio.dirty then return end
  local opts = SaveData.loadOptions()
  local block = type(opts.touchControls) == "table" and opts.touchControls or {}
  block.enabled = true
  block.skin = skin.id
  opts.touchControls = block
  SaveData.saveOptions(opts)
  -- Handing off here would unload the studio inside its own draw pass and
  -- leave the rest of this frame drawing against a dead skin; Studio.update
  -- runs it on the next tick instead.
  Studio.pendingPlay = true
  setStatus("Starting the game with " .. skin.id .. "...")
end

-- ---------------------------------------------------------------- canvas

function Studio.canvasRect(x, y, w, h)
  local canvas = Studio.canvas()
  local aspect = canvas.w / canvas.h
  local cw, ch = w, w / aspect
  if ch > h then ch, cw = h, h * aspect end
  return x + (w - cw) * 0.5, y + (h - ch) * 0.5, cw, ch
end

local function controlRect(page, ctl, r)
  local cx, cy, halfW, halfH =
    TouchSkin.controlGeometry(page, ctl, r.w, r.h, r.x, r.y)
  return cx - halfW, cy - halfH, halfW * 2, halfH * 2
end

function Studio.snapLines(page, r, skipIndex)
  local xs, ys = {}, {}
  local px, py, pw, ph = TouchSkin.pageBox(page, r.w, r.h, r.x, r.y)
  xs[1], xs[2], xs[3] = px, px + pw * 0.5, px + pw
  ys[1], ys[2], ys[3] = py, py + ph * 0.5, py + ph
  for i, ctl in ipairs(page.controls or {}) do
    if i ~= skipIndex then
      local bx, by, bw, bh = controlRect(page, ctl, r)
      xs[#xs + 1] = bx
      xs[#xs + 1] = bx + bw * 0.5
      xs[#xs + 1] = bx + bw
      ys[#ys + 1] = by
      ys[#ys + 1] = by + bh * 0.5
      ys[#ys + 1] = by + bh
    end
  end
  return xs, ys
end

local function viewportRect(page, r)
  local x, y, w, h = TouchSkin.pageViewport(page, r.w, r.h, r.x, r.y)
  if not x then return nil end
  return x, y, w, h
end

local function handleRects(bx, by, bw, bh)
  local out = {}
  for _, h in ipairs(HANDLES) do
    out[#out + 1] = {
      id = h[1],
      x = bx + bw * h[2] - HANDLE * Kit.scale,
      y = by + bh * h[3] - HANDLE * Kit.scale,
      w = HANDLE * 2 * Kit.scale, h = HANDLE * 2 * Kit.scale,
    }
  end
  return out
end

local function applyResize(id, bx, by, bw, bh, dx, dy)
  if id:find("w") then bx = bx + dx bw = bw - dx end
  if id:find("e") then bw = bw + dx end
  if id:find("n") then by = by + dy bh = bh - dy end
  if id:find("s") then bh = bh + dy end
  return bx, by, math.max(4, bw), math.max(4, bh)
end

function Studio.beginCanvasDrag(mx, my, r)
  local page = Studio.page()
  if not page then return end
  Studio.guides = nil

  local ctl = Studio.selectedControl()
  if ctl then
    local bx, by, bw, bh = controlRect(page, ctl, r)
    for _, h in ipairs(handleRects(bx, by, bw, bh)) do
      if mx >= h.x and mx <= h.x + h.w and my >= h.y and my <= h.y + h.h then
        Studio.pushUndo()
        Studio.drag = { kind = "control-resize", handle = h.id, mx = mx, my = my,
                        bx = bx, by = by, bw = bw, bh = bh }
        return
      end
    end
  end

  local vx, vy, vw, vh = viewportRect(page, r)
  if vx and not Studio.canvas().lockViewport and page.screenFit ~= "remainder" then
    for _, h in ipairs(handleRects(vx, vy, vw, vh)) do
      if mx >= h.x and mx <= h.x + h.w and my >= h.y and my <= h.y + h.h then
        Studio.pushUndo()
        Studio.drag = { kind = "viewport-resize", handle = h.id, mx = mx, my = my,
                        bx = vx, by = vy, bw = vw, bh = vh }
        Studio.selected = nil
        return
      end
    end
  end

  for i = #page.controls, 1, -1 do
    local c = page.controls[i]
    local bx, by, bw, bh = controlRect(page, c, r)
    if mx >= bx and mx <= bx + bw and my >= by and my <= by + bh then
      Studio.selected = i
      Studio.pushUndo()
      Studio.drag = { kind = "control-move", mx = mx, my = my,
                      bx = bx, by = by, bw = bw, bh = bh }
      return
    end
  end

  if vx and not Studio.canvas().lockViewport and page.screenFit ~= "remainder"
     and mx >= vx and mx <= vx + vw and my >= vy and my <= vy + vh then
    Studio.selected = nil
    Studio.pushUndo()
    Studio.drag = { kind = "viewport-move", mx = mx, my = my,
                    bx = vx, by = vy, bw = vw, bh = vh }
    return
  end

  Studio.selected = nil
end

function Studio.updateDrag(mx, my, r)
  local d = Studio.drag
  local page = Studio.page()
  if not d or not page then return end
  local dx, dy = mx - d.mx, my - d.my
  local bx, by, bw, bh = d.bx, d.by, d.bw, d.bh

  if d.kind == "control-move" or d.kind == "viewport-move" then
    bx, by = bx + dx, by + dy
  else
    bx, by, bw, bh = applyResize(d.handle, bx, by, bw, bh, dx, dy)
  end

  if d.kind:find("viewport") and Studio.aspectLock and d.handle then
    -- Derive the axis the handle does not drive, or an edge handle fights the
    -- lock and appears dead.  A corner drives whichever way the pointer moved
    -- furthest, so dragging it up/down resizes as readily as left/right.
    local byHeight = (d.handle == "n" or d.handle == "s")
    if not byHeight and #d.handle > 1 then
      byHeight = math.abs(dy) > math.abs(dx)
    end
    if byHeight then
      local newW = bh * GB_ASPECT
      if d.handle:find("w") then bx = bx + (bw - newW)
      elseif not d.handle:find("e") then bx = bx + (bw - newW) * 0.5 end
      bw = newW
    else
      local newH = bw / GB_ASPECT
      if d.handle:find("n") then by = by + (bh - newH)
      elseif not d.handle:find("s") then by = by + (bh - newH) * 0.5 end
      bh = newH
    end
  end

  if d.kind == "control-move" then
    local tol = Studio.SNAP_PX * Kit.scale
    local xs, ys = Studio.snapLines(page, r, Studio.selected)
    local offX, lineX = Studio.snapOffset({ bx, bx + bw * 0.5, bx + bw }, xs, tol)
    local offY, lineY = Studio.snapOffset({ by, by + bh * 0.5, by + bh }, ys, tol)
    bx, by = bx + offX, by + offY
    Studio.guides = { x = lineX, y = lineY }
  end

  local px, py, pw, ph = TouchSkin.pageBox(page, r.w, r.h, r.x, r.y)
  if pw <= 0 or ph <= 0 then return end
  if d.kind:find("control") then
    local ctl = Studio.selectedControl()
    if not ctl then return end
    ctl.x = clamp01(((bx + bw * 0.5) - px) / pw)
    ctl.y = clamp01(((by + bh * 0.5) - py) / ph)
    ctl.rangeX = math.max(0.002, (bw * 0.5) / pw)
    ctl.rangeY = math.max(0.002, (bh * 0.5) / ph)
  else
    page.viewport = {
      x = clamp01((bx - px) / pw), y = clamp01((by - py) / ph),
      w = math.max(0.02, bw / pw), h = math.max(0.02, bh / ph),
    }
  end
  markDirty()
end

-- ----------------------------------------------------------------- draw

local function drawCanvas(x, y, w, h)
  local page = Studio.page()
  local r = { }
  r.x, r.y, r.w, r.h = Studio.canvasRect(x, y, w, h)
  Studio.lastCanvas = r
  if not page then return r end

  Theme.fill(r.x, r.y, r.w, r.h, { 0, 0, 0 }, 1)

  TouchSkin.setSurface(r.x, r.y, r.w, r.h)
  syncActive()

  local vx, vy, vw, vh = viewportRect(page, r)
  if vx then
    local scale = math.min(vw / 160, vh / 144)
    local gw, gh = 160 * scale, 144 * scale
    local gx, gy = vx + (vw - gw) * 0.5, vy + (vh - gh) * 0.5
    Theme.fill(vx, vy, vw, vh, { 12, 12, 12 }, 1)
    Theme.fill(gx, gy, gw, gh, { 155, 188, 15 }, 1)
    Kit.textCenter("small", "160 x 144", gx, gy + gh * 0.5 - Kit.textHeight("small") * 0.5,
                   gw, { 20, 40, 20 })
  end

  TouchControls:draw()
  TouchSkin.setSurface(nil)

  Theme.strokeRounded(r.x, r.y, r.w, r.h, PAL.line, Theme.A.hairline, 1, 2)

  if Studio.testing then return r end

  if vx then
    Theme.strokeRounded(vx, vy, vw, vh, PAL.blue, 0.9, 2, 2)
    Kit.text("small", "SCREEN", vx + 4 * Kit.scale, vy + 4 * Kit.scale, PAL.blue)
    if not Studio.canvas().lockViewport and page.screenFit ~= "remainder" then
      local a = Studio.selectedControl() and 0.45 or 1
      for _, hd in ipairs(handleRects(vx, vy, vw, vh)) do
        Theme.fill(hd.x, hd.y, hd.w, hd.h, PAL.blue, a)
      end
    end
  end

  for i, ctl in ipairs(page.controls) do
    local bx, by, bw, bh = controlRect(page, ctl, r)
    local selected = (i == Studio.selected)
    local c = ctl.decorative and PAL.muted or (selected and PAL.green or PAL.line)
    Theme.strokeRounded(bx, by, bw, bh, c, selected and 1 or 0.45,
                        selected and 2 or 1, ctl.shape == "radial" and bh * 0.5 or 2)
    if Studio.showLabels and bw > 8 * Kit.scale then
      Kit.textCenter("micro", Kit.ellipsize("micro", ctl.spec, bw), bx,
                     by + bh * 0.5 - Kit.textHeight("micro") * 0.5, bw,
                     selected and PAL.green or PAL.muted)
    end
    if selected then
      for _, hd in ipairs(handleRects(bx, by, bw, bh)) do
        Theme.fill(hd.x, hd.y, hd.w, hd.h, PAL.green, 1)
      end
      Kit.text("small", ctl.spec, bx, by - Kit.textHeight("small") - 2 * Kit.scale,
               PAL.green)
    end
  end

  local guides = Studio.drag and Studio.guides
  if guides then
    if guides.x then
      Theme.fill(guides.x, r.y, math.max(1, Kit.scale), r.h, PAL.yellow, 0.6)
    end
    if guides.y then
      Theme.fill(r.x, guides.y, r.w, math.max(1, Kit.scale), PAL.yellow, 0.6)
    end
  end
  return r
end

local function inspectorBody(x, y, w)
  if not Studio.skin then return y end
  local page = Studio.page()
  local ctl = Studio.selectedControl()
  local rowH = math.max(Kit.tapMin(), 30 * Kit.scale)
  local gap = 6 * Kit.scale
  local cy = y

  Kit.caption(x, cy, "SKIN")
  cy = cy + Kit.textHeight("small") + gap
  Studio.skinIdField = Kit.textfield("skinid", x, cy, w, rowH,
                                     Studio.skinIdField, "skin name")
  cy = cy + rowH + gap

  local third = (w - gap * 2) / 3
  if Kit.button(x, cy, third, rowH, "Save", { id = "save" }) then Studio.save() end
  if Kit.button(x + third + gap, cy, third, rowH, "Export \226\150\184",
                { id = "export" }) then
    Studio.openExportMenu()
  end
  if Kit.button(x + (third + gap) * 2, cy, third, rowH, "Play", { id = "play" }) then
    Studio.play()
  end
  cy = cy + rowH + 2 * Kit.scale
  Kit.text("small", "Format: " .. Studio.skinFormat(), x, cy, PAL.faint)
  cy = cy + Kit.textHeight("small") + gap * 2

  Kit.caption(x, cy, "OPEN")
  cy = cy + Kit.textHeight("small") + gap
  local half = (w - gap) / 2
  if Kit.button(x, cy, half, rowH, "New", { id = "new" }) then
    Studio.guard("Start a new skin and lose the unsaved changes?",
      Studio.newSkin)
  end
  if Kit.button(x + half + gap, cy, half, rowH,
                "Load " .. (#Studio.available > 0 and "\226\150\184" or "-"),
                { id = "load", enabled = #Studio.available > 0 }) then
    Studio.openLoadPicker()
  end
  cy = cy + rowH + gap * 2

  Kit.caption(x, cy, "PAGE " .. Studio.pageIndex .. " / " .. #(Studio.skin.pages or {}))
  cy = cy + Kit.textHeight("small") + gap
  if Kit.button(x, cy, half, rowH,
                "Pages \226\150\184  " .. tostring(page and page.name or "-"),
                { id = "pagelist" }) then
    Studio.openPageMenu()
  end
  if Kit.button(x + half + gap, cy, half, rowH, "Add page", { id = "pageadd" }) then
    Studio.addPage()
  end
  cy = cy + rowH + gap
  local lock = TouchSkin.pageOrient(page) or "any"
  if Kit.button(x, cy, half, rowH, Studio.ORIENT_LABEL[lock] or "Lock: Off",
                { id = "orient" }) then
    Studio.cyclePageOrient(1)
  end
  local matchOn = Studio.matchOrient
  Studio.matchOrient = Kit.checkbox(x + half + gap, cy, half, rowH,
                                    Studio.matchOrient, "Match canvas", "matchorient")
  if Studio.matchOrient and not matchOn then Studio.syncCanvasToPage() end
  cy = cy + rowH + gap

  if page then
    local bezel = page.imagePath or page.rasterName or "(none)"
    local pickW = 82 * Kit.scale
    local cycleW = w - pickW - gap
    if Kit.button(x, cy, cycleW, rowH, "Bezel: " .. bezel, { id = "bezel" }) then
      Studio.openImagePicker("bezel")
    end
    if Kit.button(x + cycleW + gap, cy, pickW, rowH, "Import",
                  { id = "bezelpick" }) then
      Studio.importImageFile("bezel")
    end
    cy = cy + rowH + gap
    local vpLabel = (page.viewport or page.screenFit == "remainder")
      and "Screen cutout: ON" or "Screen cutout: OFF"
    if Kit.button(x, cy, half, rowH, vpLabel, { id = "vp",
        enabled = not Studio.canvas().lockViewport }) then
      Studio.toggleViewport()
    end
    Studio.aspectLock = Kit.checkbox(x + half + gap, cy, half, rowH,
                                     Studio.aspectLock, "10:9 lock", "aspect")
    cy = cy + rowH + gap
    if Kit.button(x, cy, w, rowH, "Detect screen from bezel", { id = "detect",
        enabled = page.imagePath ~= nil and not Studio.canvas().lockViewport }) then
      Studio.detectViewport()
    end
    cy = cy + rowH + gap * 2
  end

  Kit.caption(x, cy, "CONTROLS")
  cy = cy + Kit.textHeight("small") + gap
  if Kit.button(x, cy, third, rowH, "Add", { id = "add" }) then Studio.addControl() end
  if Kit.button(x + third + gap, cy, third, rowH, "Dup",
                { id = "dup", enabled = ctl ~= nil }) then
    Studio.duplicateControl()
  end
  if Kit.button(x + (third + gap) * 2, cy, third, rowH, "Del",
                { id = "del", enabled = ctl ~= nil }) then
    Studio.deleteControl()
  end
  cy = cy + rowH + gap

  if not ctl then
    Kit.textWrapped("small", page and #page.controls == 0
      and "No controls yet. Add one, then drag it on the canvas."
      or "Click a control on the canvas to edit it.", x, cy, w, PAL.muted, 3)
    return cy + Kit.textHeight("small") * 3
  end

  local canvas = Studio.canvas()
  local zW = 68 * Kit.scale
  if Kit.button(x, cy, zW, rowH, "Back", { id = "zback",
      enabled = (Studio.selected or 1) > 1 }) then
    Studio.moveControlOrder(-1)
  end
  if Kit.button(x + zW + gap, cy, zW, rowH, "Front", { id = "zfront",
      enabled = Studio.selected ~= nil and page ~= nil
        and Studio.selected < #page.controls }) then
    Studio.moveControlOrder(1)
  end
  Kit.text("small", ("%d / %d"):format(Studio.selected or 0,
    page and #page.controls or 0), x + (zW + gap) * 2,
    cy + (rowH - Kit.textHeight("small")) * 0.5, PAL.faint)
  cy = cy + rowH + gap

  if Kit.button(x, cy, w, rowH, "Bind: " .. ctl.spec, { id = "bind" }) then
    Studio.openBindPicker()
  end
  cy = cy + rowH + 2 * Kit.scale
  Kit.text("small", TouchSkin.describeBind(ctl.spec), x, cy, PAL.muted)
  cy = cy + Kit.textHeight("small") + gap

  if Kit.button(x, cy, half, rowH, "Shape: " .. ctl.shape, { id = "shape" }) then
    Studio.pushUndo()
    ctl.shape = ctl.shape == "radial" and "rect" or "radial"
    markDirty()
  end
  if Kit.button(x + half + gap, cy, half, rowH,
                string.format("Reach x%.2f", ctl.rangeMod), { id = "rangemod" }) then
    Studio.pushUndo()
    ctl.rangeMod = ctl.rangeMod >= 2 and 0.5 or (ctl.rangeMod + 0.25)
    markDirty()
  end
  cy = cy + rowH + gap

  local quarter = (w - gap * 3) / 4
  local fields = {
    { "X", round((ctl.x - ctl.rangeX) * canvas.w) },
    { "Y", round((ctl.y - ctl.rangeY) * canvas.h) },
    { "W", round(ctl.rangeX * 2 * canvas.w) },
    { "H", round(ctl.rangeY * 2 * canvas.h) },
  }
  for i, f in ipairs(fields) do
    local fx = x + (quarter + gap) * (i - 1)
    Kit.text("small", f[1], fx, cy, PAL.faint)
    local id = "num" .. f[1]
    local shown = Studio.editing == id and Studio.editBuf or tostring(f[2])
    local typed = Kit.textfield(id, fx, cy + Kit.textHeight("small"),
                                quarter, rowH, shown, "0")
    if Kit.focus == id then
      Studio.editing, Studio.editBuf = id, typed
    elseif Studio.editing == id then
      Studio.commitField(id, Studio.editBuf)
      Studio.editing, Studio.editBuf = nil, nil
    end
  end
  cy = cy + Kit.textHeight("small") + rowH + gap
  Kit.text("small", ("canvas %dx%d px"):format(canvas.w, canvas.h), x, cy, PAL.faint)
  cy = cy + Kit.textHeight("small") + gap

  local pickW = 82 * Kit.scale
  local artW = w - pickW - gap
  local idle = ctl.imagePath or "(none)"
  if Kit.button(x, cy, artW, rowH, "Idle art: " .. idle, { id = "img" }) then
    Studio.openImagePicker("idle")
  end
  if Kit.button(x + artW + gap, cy, pickW, rowH, "Import", { id = "imgpick" }) then
    Studio.importImageFile("idle")
  end
  cy = cy + rowH + gap
  local pressed = ctl.pressedImagePath or "(none)"
  if Kit.button(x, cy, artW, rowH, "Pressed art: " .. pressed, { id = "imgp" }) then
    Studio.openImagePicker("pressed")
  end
  if Kit.button(x + artW + gap, cy, pickW, rowH, "Import", { id = "imgppick" }) then
    Studio.importImageFile("pressed")
  end
  return cy + rowH
end

local function drawInspector(x, y, w, h)
  local pad = 10 * Kit.scale
  Kit.card(x, y, w, h)

  local scroll = Studio.inspectorScroll or 0
  if Kit.hit(x, y, w, h) and (Kit.wheelY or 0) ~= 0 then
    scroll = scroll - Kit.wheelY * 48 * Kit.scale
  end
  local maxScroll = math.max(0, (Studio.inspectorH or 0) - (h - pad * 2))
  scroll = math.max(0, math.min(scroll, maxScroll))
  Studio.inspectorScroll = scroll

  Kit.pushClip(x, y, w, h)
  local top = y + pad - scroll
  local endY = inspectorBody(x + pad, top, w - pad * 2) or top
  Studio.inspectorH = endY - top
  Kit.popClip()

  if maxScroll > 0 then
    local frac = h / (h + maxScroll)
    local barH = math.max(24 * Kit.scale, h * frac)
    local barY = y + (h - barH) * (scroll / maxScroll)
    Theme.fill(x + w - 4 * Kit.scale, barY, 3 * Kit.scale, barH, PAL.line, 0.4)
  end
end

function Studio.commitField(id, text)
  local ctl = Studio.selectedControl()
  if not ctl then return end
  local n = tonumber(text)
  if not n then return end
  Studio.pushUndo("field")
  local canvas = Studio.canvas()
  local left = (ctl.x - ctl.rangeX) * canvas.w
  local top = (ctl.y - ctl.rangeY) * canvas.h
  local wpx = ctl.rangeX * 2 * canvas.w
  local hpx = ctl.rangeY * 2 * canvas.h
  if id == "numX" then left = n
  elseif id == "numY" then top = n
  elseif id == "numW" then wpx = math.max(1, n)
  elseif id == "numH" then hpx = math.max(1, n) end
  ctl.rangeX = (wpx * 0.5) / canvas.w
  ctl.rangeY = (hpx * 0.5) / canvas.h
  ctl.x = clamp01((left + wpx * 0.5) / canvas.w)
  ctl.y = clamp01((top + hpx * 0.5) / canvas.h)
  markDirty()
end

local function modalFrame(W, H, title, wFrac, hFrac)
  Theme.fill(0, 0, W, H, PAL.bg, 0.85)
  local pad = 14 * Kit.scale
  local mw = math.min(W - pad * 2, math.max(320 * Kit.scale, (wFrac or 0.6) * W))
  local mh = math.min(H - pad * 2, math.max(220 * Kit.scale, (hFrac or 0.72) * H))
  local mx = math.floor((W - mw) * 0.5)
  local my = math.floor((H - mh) * 0.5)
  Kit.card(mx, my, mw, mh)
  Kit.textBold("title", title, mx + pad, my + pad * 0.7, PAL.heading)
  return mx, my, mw, mh, pad
end

local function modalFooter(mx, my, mw, mh, pad)
  local bh = math.max(Kit.tapMin(), 32 * Kit.scale)
  local by = my + mh - pad - bh
  if Kit.button(mx + mw - pad - 110 * Kit.scale, by, 110 * Kit.scale, bh,
                "Close", { id = "modal-close" }) then
    Studio.closeModal()
  end
  return by, bh
end

local function modalScroll(modal, x, y, w, h, contentH)
  local maxScroll = Kit.scrollExtent(contentH, h)
  modal.scroll = select(1, Kit.scrollWheel(modal.scroll or 0, maxScroll,
    x, y, w, h))
  modal.scroll = Kit.scrollClamp(modal.scroll, maxScroll)
  return modal.scroll, maxScroll
end

local function drawBindModal(W, H)
  local modal = Studio.modal
  local ctl = Studio.selectedControl()
  local mx, my, mw, mh, pad = modalFrame(W, H, "Choose a bind", 0.66, 0.8)
  local top = my + pad + Kit.textHeight("title") + pad * 0.5
  local by = modalFooter(mx, my, mw, mh, pad)
  local viewH = by - top - pad
  local rowH = math.max(Kit.tapMin(), 30 * Kit.scale)
  local gap = 6 * Kit.scale
  local cols = math.max(2, math.floor((mw - pad * 2) / (150 * Kit.scale)))
  local colW = (mw - pad * 2 - gap * (cols - 1)) / cols

  local contentH = modal.contentH or viewH
  local at = modalScroll(modal, mx + pad, top, mw - pad * 2, viewH, contentH)
  local cy = Kit.scrollBegin(mx + pad, top, mw - pad * 2, viewH, at,
    Kit.scrollExtent(contentH, viewH))
  local startY = cy

  Kit.caption(mx + pad, cy, "COMBINE")
  cy = cy + Kit.textHeight("small") + gap
  for i, part in ipairs(Studio.BIND_PARTS) do
    local col = (i - 1) % cols
    local px = mx + pad + col * (colW + gap)
    local py = cy + math.floor((i - 1) / cols) * (rowH + gap)
    local on = ctl and Studio.hasBindPart(ctl.spec, part)
    if Kit.chip(px, py, colW, rowH, part, on, on and PAL.green or nil,
                "bindpart-" .. part) then
      Studio.toggleSelectedBindPart(part)
    end
  end
  cy = cy + math.ceil(#Studio.BIND_PARTS / cols) * (rowH + gap) + gap

  for _, group in ipairs(Studio.BIND_GROUPS) do
    Kit.caption(mx + pad, cy, group.title)
    cy = cy + Kit.textHeight("small") + gap
    for i, spec in ipairs(group.specs) do
      local col = (i - 1) % cols
      local px = mx + pad + col * (colW + gap)
      local py = cy + math.floor((i - 1) / cols) * (rowH + gap)
      local active = ctl and ctl.spec == spec
      if Kit.button(px, py, colW, rowH, spec,
                    { id = "bind-" .. spec, kind = active and "accent" or nil,
                      font = "small" }) then
        Studio.setBindSpec(spec)
        Studio.closeModal()
      end
    end
    cy = cy + math.ceil(#group.specs / cols) * (rowH + gap) + gap
  end
  modal.contentH = cy - startY
  Kit.scrollEnd(mx + pad, top, mw - pad * 2, viewH, at,
    Kit.scrollExtent(contentH, viewH))

  if ctl then
    Kit.text("small", Kit.ellipsize("small",
      "Bind: " .. ctl.spec .. "  ->  " .. TouchSkin.describeBind(ctl.spec),
      mw - pad * 2 - 120 * Kit.scale), mx + pad, by + Kit.scale * 8, PAL.muted)
  end
end

local function drawImageModal(W, H)
  local modal = Studio.modal
  local mx, my, mw, mh, pad = modalFrame(W, H,
    "Choose art for the " .. Studio.imageTargetLabel(), 0.7, 0.8)
  local top = my + pad + Kit.textHeight("title") + pad * 0.5
  local by, bh = modalFooter(mx, my, mw, mh, pad)
  if Kit.button(mx + pad, by, 150 * Kit.scale, bh, "Import a file...",
                { id = "modal-import", kind = "accent",
                  enabled = FilePicker.available() }) then
    local target = Studio.imageTarget
    Studio.closeModal()
    Studio.importImageFile(target)
  end

  local viewH = by - top - pad
  local gap = 8 * Kit.scale
  local tile = math.max(72 * Kit.scale, 96 * Kit.scale)
  local cols = math.max(2, math.floor((mw - pad * 2) / (tile + gap)))
  local tileW = (mw - pad * 2 - gap * (cols - 1)) / cols
  local tileH = tileW * 0.75 + Kit.textHeight("micro") + 6 * Kit.scale

  local list = { false }
  for _, rel in ipairs(Studio.images or {}) do list[#list + 1] = rel end
  local rows = math.ceil(#list / cols)
  local contentH = rows * (tileH + gap)
  local at = modalScroll(modal, mx + pad, top, mw - pad * 2, viewH, contentH)
  local maxScroll = Kit.scrollExtent(contentH, viewH)
  local baseY = Kit.scrollBegin(mx + pad, top, mw - pad * 2, viewH, at, maxScroll)
  local current = Studio.currentImagePath()

  for i, rel in ipairs(list) do
    local col = (i - 1) % cols
    local row = math.floor((i - 1) / cols)
    local px = mx + pad + col * (tileW + gap)
    local py = baseY + row * (tileH + gap)
    local selected = (rel or nil) == current
    local clicked = Kit.row(px, py, tileW, tileH, selected, "imgtile-" .. i)
    local art = rel and Studio.thumb(rel) or nil
    local artH = tileH - Kit.textHeight("micro") - 6 * Kit.scale
    if art and art.getWidth then
      local iw, ih = art:getWidth(), art:getHeight()
      if iw > 0 and ih > 0 then
        local scale = math.min((tileW - 8 * Kit.scale) / iw,
          (artH - 8 * Kit.scale) / ih)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(art, px + (tileW - iw * scale) * 0.5,
          py + (artH - ih * scale) * 0.5, 0, scale, scale)
      end
    elseif not rel then
      Kit.textCenter("small", "(none)", px,
        py + artH * 0.5 - Kit.textHeight("small") * 0.5, tileW, PAL.muted)
    end
    Kit.textCenter("micro", Kit.ellipsize("micro", rel or "no art", tileW),
      px, py + tileH - Kit.textHeight("micro") - 2 * Kit.scale, tileW,
      selected and PAL.green or PAL.detail)
    if clicked then Studio.chooseImage(rel or nil) end
  end
  if #list == 1 then
    Kit.text("small", "No images in this skin yet. Import one.", mx + pad,
      baseY, PAL.muted)
  end
  Kit.scrollEnd(mx + pad, top, mw - pad * 2, viewH, at, maxScroll)
end

local function drawOpenModal(W, H)
  local modal = Studio.modal
  local mx, my, mw, mh, pad = modalFrame(W, H, "Open a skin", 0.62, 0.76)
  local top = my + pad + Kit.textHeight("title") + pad * 0.5
  local by = modalFooter(mx, my, mw, mh, pad)
  local viewH = by - top - pad
  local rowH = math.max(Kit.tapMin(), 46 * Kit.scale)
  local gap = 4 * Kit.scale
  local list = Studio.available or {}
  local contentH = #list * (rowH + gap)
  local at = modalScroll(modal, mx + pad, top, mw - pad * 2, viewH, contentH)
  local maxScroll = Kit.scrollExtent(contentH, viewH)
  local baseY = Kit.scrollBegin(mx + pad, top, mw - pad * 2, viewH, at, maxScroll)

  for i, entry in ipairs(list) do
    local py = baseY + (i - 1) * (rowH + gap)
    local selected = Studio.skin and Studio.skin.id == entry.id
    local clicked = Kit.row(mx + pad, py, mw - pad * 2, rowH, selected,
      "open-" .. entry.id)
    Kit.text("mono", Kit.ellipsize("mono", entry.id, mw - pad * 4),
      mx + pad * 2, py + 6 * Kit.scale, selected and PAL.green or PAL.heading)
    Kit.text("small", Kit.ellipsize("small", Studio.skinSummary(entry),
      mw - pad * 4), mx + pad * 2, py + 6 * Kit.scale + Kit.textHeight("mono"),
      PAL.muted)
    if clicked then Studio.loadEntry(entry.id) end
  end
  if #list == 0 then
    Kit.text("small", "No skins installed yet.", mx + pad, baseY, PAL.muted)
  end
  Kit.scrollEnd(mx + pad, top, mw - pad * 2, viewH, at, maxScroll)
end

local function drawPageModal(W, H)
  local modal = Studio.modal
  local skin = Studio.skin
  local mx, my, mw, mh, pad = modalFrame(W, H, "Pages", 0.58, 0.72)
  local top = my + pad + Kit.textHeight("title") + pad * 0.5
  local by, bh = modalFooter(mx, my, mw, mh, pad)
  local gap = 6 * Kit.scale
  local fieldW = math.min(220 * Kit.scale, (mw - pad * 2) * 0.5)
  Studio.pageNameField = Kit.textfield("pagename", mx + pad, by, fieldW, bh,
    Studio.pageNameField or "", "page name")
  if Kit.button(mx + pad + fieldW + gap, by, 100 * Kit.scale, bh, "Rename",
                { id = "page-rename" }) then
    Studio.renamePage(Studio.pageNameField)
  end
  if Kit.button(mx + pad + fieldW + gap + 106 * Kit.scale, by, 100 * Kit.scale,
                bh, "Delete", { id = "page-del", kind = "danger",
                  enabled = skin and #skin.pages > 1 }) then
    local index = Studio.pageIndex
    Studio.closeModal()
    Studio.ask("Delete this page and everything on it?",
      function() Studio.deletePage(index) end, "Delete")
  end

  local viewH = by - top - pad
  local rowH = math.max(Kit.tapMin(), 44 * Kit.scale)
  local pages = (skin and skin.pages) or {}
  local contentH = #pages * (rowH + gap)
  local at = modalScroll(modal, mx + pad, top, mw - pad * 2, viewH, contentH)
  local maxScroll = Kit.scrollExtent(contentH, viewH)
  local baseY = Kit.scrollBegin(mx + pad, top, mw - pad * 2, viewH, at, maxScroll)
  for i = 1, #pages do
    local py = baseY + (i - 1) * (rowH + gap)
    local selected = i == Studio.pageIndex
    local clicked = Kit.row(mx + pad, py, mw - pad * 2, rowH, selected,
      "page-" .. i)
    local name, detail = Studio.pageLabel(i)
    Kit.text("mono", Kit.ellipsize("mono", i .. ".  " .. name, mw - pad * 4),
      mx + pad * 2, py + 5 * Kit.scale, selected and PAL.green or PAL.heading)
    Kit.text("small", Kit.ellipsize("small", detail, mw - pad * 4),
      mx + pad * 2, py + 5 * Kit.scale + Kit.textHeight("mono"), PAL.muted)
    if clicked then
      Studio.setPage(i)
      Studio.pageNameField = name
    end
  end
  Kit.scrollEnd(mx + pad, top, mw - pad * 2, viewH, at, maxScroll)
end

local function drawExportModal(W, H)
  local mx, my, mw, mh, pad = modalFrame(W, H, "Export this skin", 0.56, 0.6)
  local cy = my + pad + Kit.textHeight("title") + pad
  local rowH = math.max(Kit.tapMin(), 34 * Kit.scale)
  local gap = 6 * Kit.scale
  local by, bh = modalFooter(mx, my, mw, mh, pad)
  for _, spec in ipairs(Studio.EXPORTS) do
    if Kit.button(mx + pad, cy, mw - pad * 2, rowH, spec.label,
                  { id = "export-" .. spec.id, kind = "accent" }) then
      Studio.exportAs(spec.id)
      Studio.closeModal()
    end
    cy = cy + rowH + 2 * Kit.scale
    Kit.text("small", Kit.ellipsize("small", spec.hint, mw - pad * 2),
      mx + pad, cy, PAL.muted)
    cy = cy + Kit.textHeight("small") + gap
  end
  if Studio.lastExport then
    if Kit.button(mx + pad, by, 150 * Kit.scale, bh, "Show the file",
                  { id = "export-reveal" }) then
      Studio.revealExport()
    end
  end
  Kit.textWrapped("small",
    "Exports land in the skins folder of your save directory.",
    mx + pad, cy, mw - pad * 2, PAL.faint, 2)
end

local function drawConfirm(W, H)
  local c = Studio.confirm
  local mx, my, mw, mh, pad = modalFrame(W, H, "Unsaved changes", 0.42, 0.3)
  Kit.textWrapped("button", c.text, mx + pad,
    my + pad + Kit.textHeight("title") + pad, mw - pad * 2, PAL.text, 3)
  local bh = math.max(Kit.tapMin(), 32 * Kit.scale)
  local by = my + mh - pad - bh
  local bw = (mw - pad * 2 - 12 * Kit.scale) / 3
  if Kit.button(mx + pad, by, bw, bh, "Save first",
                { id = "confirm-save", kind = "accent" }) then
    Studio.save()
    if not Studio.dirty then Studio.confirmYes() end
  end
  if Kit.button(mx + pad + bw + 6 * Kit.scale, by, bw, bh, c.yesLabel,
                { id = "confirm-yes", kind = "danger" }) then
    Studio.confirmYes()
  end
  if Kit.button(mx + pad + (bw + 6 * Kit.scale) * 2, by, bw, bh, "Cancel",
                { id = "confirm-no" }) then
    Studio.confirmNo()
  end
end

function Studio.drawOverlay(W, H)
  if Studio.confirm then
    drawConfirm(W, H)
    return true
  end
  local modal = Studio.modal
  if not modal then return false end
  if modal.kind == "bind" then drawBindModal(W, H)
  elseif modal.kind == "image" then drawImageModal(W, H)
  elseif modal.kind == "open" then drawOpenModal(W, H)
  elseif modal.kind == "page" then drawPageModal(W, H)
  elseif modal.kind == "export" then drawExportModal(W, H)
  else Studio.closeModal() end
  return true
end

function Studio.draw()
  local W, H = love.graphics.getDimensions()
  Kit.layout(W, H)
  local mx, my = love.mouse.getPosition()
  Kit.beginFrame(mx, my, Studio.clicked, Studio.wheel)
  Studio.clicked, Studio.wheel = false, 0

  Theme.fill(0, 0, W, H, PAL.bg, 1)
  Studio.expireStatus()
  Kit.blockClicks = Studio.modalUp()

  local pad = 14 * Kit.scale
  local barH = math.max(Kit.tapMin(), 34 * Kit.scale) + pad

  Kit.textBold("title", "Skin Studio", pad, pad * 0.6, PAL.heading)
  local titleW = Kit.textWidth("title", "Skin Studio") + pad * 2

  local btnH = math.max(Kit.tapMin(), 32 * Kit.scale)
  local bx = titleW
  local canvas = Studio.canvas()
  if Kit.button(bx, pad * 0.5, 200 * Kit.scale, btnH,
                canvas.label, { id = "canvas" }) then
    Studio.setCanvas(Studio.canvasIndex + 1)
  end
  bx = bx + 208 * Kit.scale
  if Kit.button(bx, pad * 0.5, 110 * Kit.scale, btnH,
                Studio.testing and "Test: ON" or "Test: OFF",
                { id = "test", active = Studio.testing }) then
    Studio.testing = not Studio.testing
    TouchControls:setPreview(not Studio.testing)
    TouchControls:reset()
  end
  bx = bx + 118 * Kit.scale
  local smallW = 74 * Kit.scale
  if Kit.button(bx, pad * 0.5, smallW, btnH, "Undo",
                { id = "undo", font = "small", enabled = Studio.canUndo() }) then
    Studio.undo()
  end
  bx = bx + smallW + 6 * Kit.scale
  if Kit.button(bx, pad * 0.5, smallW, btnH, "Redo",
                { id = "redo", font = "small", enabled = Studio.canRedo() }) then
    Studio.redo()
  end
  bx = bx + smallW + 6 * Kit.scale
  if Kit.button(bx, pad * 0.5, smallW + 20 * Kit.scale, btnH,
                Studio.showLabels and "Labels: ON" or "Labels: OFF",
                { id = "labels", font = "small", active = Studio.showLabels }) then
    Studio.showLabels = not Studio.showLabels
  end
  bx = bx + smallW + 26 * Kit.scale

  if Studio.dirty then
    Kit.text("small", "unsaved", bx, pad * 0.5 + btnH * 0.3, PAL.yellow)
  end

  local closeW = 100 * Kit.scale
  local closed = false
  if Kit.button(W - pad - closeW, pad * 0.5, closeW, btnH, "Close",
                { id = "close" }) then
    Studio.guard("Close the studio and lose the unsaved changes?", function()
      closed = true
      if Studio.onClose then Studio.onClose() end
    end)
  end
  if closed then
    Kit.blockClicks = false
    Kit.endFrame()
    return
  end

  local panelW = math.min(360 * Kit.scale, W * 0.34)
  local bodyY = barH + pad * 0.5
  local bodyH = H - bodyY - pad

  drawInspector(pad, bodyY, panelW, bodyH)

  local cx = pad * 2 + panelW
  local cw = W - cx - pad
  local r = drawCanvas(cx, bodyY, cw, bodyH - 40 * Kit.scale)

  local footY = bodyY + bodyH - 30 * Kit.scale
  local msg = Studio.status
  if not msg and Studio.testing then
    local held = {}
    for btn in pairs(TouchControls.held or {}) do held[#held + 1] = btn end
    table.sort(held)
    msg = "TEST: click the pad. Held: "
      .. (held[1] and table.concat(held, ", ") or "(none)")
  end
  if not msg then
    msg = "Drag to move, corner handles to resize, blue box is the game screen."
  end
  Kit.text("small", Kit.ellipsize("small", msg, cw), cx, footY,
    Studio.statusErr and PAL.red or PAL.detail)

  Kit.blockClicks = false
  Studio.drawOverlay(W, H)

  Kit.endFrame()
  Studio.canvasArea = r
end

-- ---------------------------------------------------------------- input

function Studio.update()
  if not Studio.pendingPlay then return end
  Studio.pendingPlay = false
  local onPlay, version, canvas = Studio.onPlay, Studio.version, Studio.canvas()
  if onPlay then onPlay(version, canvas) end
end

function Studio.mousepressed(x, y, button)
  if button ~= 1 then return end
  Studio.clicked = true
  if Studio.modalUp() then return end
  local r = Studio.lastCanvas
  if not r then return end
  if Studio.testing then
    if x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h then
      TouchControls:touchpressed("studio", x, y)
    end
    return
  end
  local slop = HANDLE * 2 * Kit.scale
  if x < r.x - slop or x > r.x + r.w + slop
     or y < r.y - slop or y > r.y + r.h + slop then
    return
  end
  Studio.beginCanvasDrag(x, y, r)
end

function Studio.mousemoved(x, y)
  if Studio.modalUp() then return end
  if Studio.testing then
    TouchControls:touchmoved("studio", x, y)
    return
  end
  if Studio.drag and love.mouse.isDown(1) and Studio.lastCanvas then
    Studio.updateDrag(x, y, Studio.lastCanvas)
  end
end

function Studio.mousereleased(x, y, button)
  if button ~= 1 then return end
  if Studio.testing then
    TouchControls:touchreleased("studio", x, y)
    return
  end
  Studio.drag = nil
  Studio.guides = nil
end

function Studio.wheelmoved(_, dy)
  Studio.wheel = dy
end

function Studio.focus()
  Studio.drag = nil
  Studio.clicked = false
  if Studio.testing then TouchControls:reset() end
end

function Studio.visible()
  Studio.focus()
end

function Studio.textinput(text)
  Kit.textinput(text)
end

local function heldCtrl()
  if not (love and love.keyboard and love.keyboard.isDown) then return false end
  local ok, down = pcall(love.keyboard.isDown, "lctrl", "rctrl", "lgui", "rgui")
  return ok and down == true
end

local function heldShift()
  if not (love and love.keyboard and love.keyboard.isDown) then return false end
  local ok, down = pcall(love.keyboard.isDown, "lshift", "rshift")
  return ok and down == true
end

Studio.NUDGES = {
  up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 },
}

function Studio.keypressed(key)
  if Kit.focus then
    Kit.keypressed(key)
    return
  end
  if Studio.confirm then
    if key == "escape" then Studio.confirmNo()
    elseif key == "return" or key == "kpenter" then Studio.confirmYes()
    else Kit.keypressed(key) end
    return
  end
  if Studio.modal then
    if key == "escape" then Studio.closeModal() else Kit.keypressed(key) end
    return
  end
  local nudge = Studio.NUDGES[key]
  if nudge then
    Studio.nudge(nudge[1], nudge[2], heldShift())
    return
  end
  if (key == "y" and heldCtrl())
      or (key == "z" and heldShift() and heldCtrl()) then
    Studio.redo()
  elseif key == "z" and heldCtrl() then
    Studio.undo()
  elseif key == "u" then
    if heldShift() then Studio.redo() else Studio.undo() end
  elseif key == "l" then
    Studio.showLabels = not Studio.showLabels
  elseif key == "escape" then
    Studio.guard("Close the studio and lose the unsaved changes?", function()
      if Studio.onClose then Studio.onClose() end
    end)
  elseif key == "delete" or key == "backspace" then
    Studio.deleteControl()
  elseif key == "n" then
    Studio.addControl()
  elseif key == "d" then
    Studio.duplicateControl()
  elseif key == "t" then
    Studio.testing = not Studio.testing
    TouchControls:setPreview(not Studio.testing)
    TouchControls:reset()
  elseif key == "s" then
    Studio.save()
  elseif key == "tab" then
    local page = Studio.page()
    if page and #page.controls > 0 then
      Studio.selected = ((Studio.selected or 0) % #page.controls) + 1
    end
  else
    Kit.keypressed(key)
  end
end

function Studio.available_desktop()
  local osName = love.system and love.system.getOS and love.system.getOS()
  return osName ~= "Android" and osName ~= "iOS"
end

return Studio
