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

local function markDirty()
  Studio.dirty = true
  Studio.status = nil
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
  Studio.imageTarget = "idle"

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
  syncActive()
  Studio.applyImportedOrient()
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
end

-- --------------------------------------------------------------- editing

function Studio.addControl()
  local page = Studio.page()
  if not page then return end
  page.controls[#page.controls + 1] =
    TouchSkin.newControl("a", 0.5, 0.5, 0.16, 0.09, "radial")
  Studio.selected = #page.controls
  markDirty()
end

function Studio.deleteControl()
  local page = Studio.page()
  if not page or not Studio.selected then return end
  table.remove(page.controls, Studio.selected)
  Studio.selected = page.controls[Studio.selected] and Studio.selected
    or (#page.controls > 0 and #page.controls or nil)
  markDirty()
end

function Studio.duplicateControl()
  local page, ctl = Studio.page(), Studio.selectedControl()
  if not page or not ctl then return end
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
  TouchSkin.setBind(ctl, list[((at - 1 + dir) % #list) + 1])
  markDirty()
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
    Studio.status = "Pick a PNG or JPG."
    return false
  end
  commitSkinId()
  local rel, err = TouchSkin.importImage(Studio.skin, name, data)
  if not rel then
    Studio.status = "Import failed: " .. tostring(err)
    return false
  end
  local where = Studio.imageTargetLabel()
  Studio.assignImage(rel)
  Studio.skinIdField = Studio.skin.id
  Studio.status = "Imported " .. rel .. " as " .. where
  if where == "bezel" and not Studio.canvas().lockViewport then
    Studio.status = Studio.status
      .. " -- use Detect screen from bezel to place the screen"
  end
  return true
end

function Studio.importImageFile(target)
  if not Studio.skin then return end
  target = target or Studio.imageTarget
  Studio.imageTarget = target
  if target ~= "bezel" and not Studio.selectedControl() then
    Studio.status = "Select a control first, or import a bezel image."
    return
  end
  if not FilePicker.available() then
    Studio.status = "No file picker here -- drag a PNG onto the window instead."
    return
  end
  local prompt = (target == "bezel") and "Choose a bezel image"
    or "Choose a button image"
  local path = FilePicker.open(prompt, FilePicker.IMAGE)
  if not path then return end
  local base = FilePicker.basename(path)
  local data, err = FilePicker.read(path)
  if not data then
    Studio.status = "Could not read " .. base .. ": " .. tostring(err)
    return
  end
  Studio.adoptImage(base, data, target)
end

function Studio.filedropped(file)
  if not Studio.skin then return end
  local path = (file.getFilename and file:getFilename()) or ""
  local base = FilePicker.basename(path)
  if not FilePicker.matches(base, FilePicker.IMAGE) then
    Studio.status = "Drop a PNG or JPG to use it as art."
    return
  end
  local ok, data = pcall(function()
    file:open("r")
    local bytes = file:read()
    file:close()
    return bytes
  end)
  if not ok or not data then
    Studio.status = "Could not read " .. base
    return
  end
  Studio.adoptImage(base, data)
end

function Studio.detectViewport()
  local page = Studio.page()
  if not page or not Studio.skin then return end
  if Studio.canvas().lockViewport then
    Studio.status = "This preset locks the screen position."
    return
  end
  if not page.imagePath then
    Studio.status = "Pick a bezel image first."
    return
  end
  local rect, pw, ph = TouchSkin.detectViewport(Studio.skin.root, page.imagePath)
  if not rect then
    Studio.status = "No transparent screen hole found in " .. page.imagePath
    return
  end
  page.viewport = rect
  Studio.status = ("Screen detected: %dx%d px in the bezel art"):format(pw, ph)
  Studio.dirty = true
end

function Studio.toggleViewport()
  local page = Studio.page()
  if not page then return end
  if Studio.canvas().lockViewport then return end
  if page.viewport then
    page.viewport = nil
  else
    page.viewport = { x = 0.1, y = 0.05, w = 0.8, h = 0.45 }
  end
  markDirty()
end

function Studio.addPage()
  local skin = Studio.skin
  if not skin then return end
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
    Studio.status = "Give the skin a name first."
    return
  end
  local dest, failed = TouchSkin.saveTo(skin, id)
  if not dest then
    Studio.status = "Save failed: " .. tostring(failed)
    return
  end
  Studio.dirty = false
  Studio.available = TouchSkin.list()
  Studio.status = "Saved to " .. dest
  if type(failed) == "table" and failed[1] then
    Studio.status = Studio.status .. " (" .. #failed .. " image(s) not found)"
  end
end

function Studio.export()
  local skin = Studio.skin
  if not skin then return end
  if Studio.dirty then Studio.save() end
  local path, missing = TouchSkin.export(skin)
  if not path then
    Studio.status = "Export failed: " .. tostring(missing)
    return
  end
  Studio.status = "Exported " .. path
  Studio.available = TouchSkin.list()
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
  Studio.status = "Starting the game with " .. skin.id .. "..."
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

local function viewportRect(page, r)
  local v = page.viewport
  if not v then return nil end
  local bx, by, bw, bh = TouchSkin.pageBox(page, r.w, r.h, r.x, r.y)
  return bx + v.x * bw, by + v.y * bh, v.w * bw, v.h * bh
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

  local ctl = Studio.selectedControl()
  if ctl then
    local bx, by, bw, bh = controlRect(page, ctl, r)
    for _, h in ipairs(handleRects(bx, by, bw, bh)) do
      if mx >= h.x and mx <= h.x + h.w and my >= h.y and my <= h.y + h.h then
        Studio.drag = { kind = "control-resize", handle = h.id, mx = mx, my = my,
                        bx = bx, by = by, bw = bw, bh = bh }
        return
      end
    end
  end

  local vx, vy, vw, vh = viewportRect(page, r)
  if vx and not Studio.canvas().lockViewport then
    for _, h in ipairs(handleRects(vx, vy, vw, vh)) do
      if mx >= h.x and mx <= h.x + h.w and my >= h.y and my <= h.y + h.h then
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
      Studio.drag = { kind = "control-move", mx = mx, my = my,
                      bx = bx, by = by, bw = bw, bh = bh }
      return
    end
  end

  if vx and not Studio.canvas().lockViewport
     and mx >= vx and mx <= vx + vw and my >= vy and my <= vy + vh then
    Studio.selected = nil
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
    if not Studio.canvas().lockViewport then
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
    if selected then
      for _, hd in ipairs(handleRects(bx, by, bw, bh)) do
        Theme.fill(hd.x, hd.y, hd.w, hd.h, PAL.green, 1)
      end
      Kit.text("small", ctl.spec, bx, by - Kit.textHeight("small") - 2 * Kit.scale,
               PAL.green)
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
  if Kit.button(x + third + gap, cy, third, rowH, "Export", { id = "export" }) then
    Studio.export()
  end
  if Kit.button(x + (third + gap) * 2, cy, third, rowH, "Play", { id = "play" }) then
    Studio.play()
  end
  cy = cy + rowH + gap * 2

  Kit.caption(x, cy, "OPEN")
  cy = cy + Kit.textHeight("small") + gap
  local half = (w - gap) / 2
  if Kit.button(x, cy, half, rowH, "New", { id = "new" }) then
    Studio.skin = TouchSkin.newSkin("new_skin")
    Studio.skinIdField = "new_skin"
    Studio.pageIndex, Studio.selected = 1, nil
    Studio.images = {}
    syncActive()
    markDirty()
  end
  if Kit.button(x + half + gap, cy, half, rowH,
                "Load " .. (#Studio.available > 0 and "\226\150\184" or "-"),
                { id = "load", enabled = #Studio.available > 0 }) then
    Studio.loadIndex = ((Studio.loadIndex or 0) % #Studio.available) + 1
    Studio.open(Studio.available[Studio.loadIndex].id)
  end
  cy = cy + rowH + gap * 2

  Kit.caption(x, cy, "PAGE " .. Studio.pageIndex .. " / " .. #(Studio.skin.pages or {}))
  cy = cy + Kit.textHeight("small") + gap
  if Kit.button(x, cy, half, rowH, "Next page", { id = "pagenext" }) then
    Studio.pageIndex = (Studio.pageIndex % #Studio.skin.pages) + 1
    Studio.selected = nil
    syncActive()
    Studio.syncCanvasToPage()
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
    local bezel = page.imagePath or "(none)"
    local pickW = 82 * Kit.scale
    local cycleW = w - pickW - gap
    if Kit.button(x, cy, cycleW, rowH, "Bezel: " .. bezel, { id = "bezel" }) then
      Studio.imageTarget = "bezel"
      Studio.cycleImage(1)
    end
    if Kit.button(x + cycleW + gap, cy, pickW, rowH, "Import",
                  { id = "bezelpick" }) then
      Studio.importImageFile("bezel")
    end
    cy = cy + rowH + gap
    local vpLabel = page.viewport and "Screen cutout: ON" or "Screen cutout: OFF"
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
  if Kit.button(x, cy, w, rowH, "Bind: " .. ctl.spec, { id = "bind" }) then
    Studio.cycleBind(1)
  end
  cy = cy + rowH + 2 * Kit.scale
  Kit.text("small", TouchSkin.describeBind(ctl.spec), x, cy, PAL.muted)
  cy = cy + Kit.textHeight("small") + gap

  if Kit.button(x, cy, half, rowH, "Shape: " .. ctl.shape, { id = "shape" }) then
    ctl.shape = ctl.shape == "radial" and "rect" or "radial"
    markDirty()
  end
  if Kit.button(x + half + gap, cy, half, rowH,
                string.format("Reach x%.2f", ctl.rangeMod), { id = "rangemod" }) then
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
    Studio.imageTarget = "idle"
    Studio.cycleImage(1)
  end
  if Kit.button(x + artW + gap, cy, pickW, rowH, "Import", { id = "imgpick" }) then
    Studio.importImageFile("idle")
  end
  cy = cy + rowH + gap
  local pressed = ctl.pressedImagePath or "(none)"
  if Kit.button(x, cy, artW, rowH, "Pressed art: " .. pressed, { id = "imgp" }) then
    Studio.imageTarget = "pressed"
    Studio.cycleImage(1)
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

function Studio.draw()
  local W, H = love.graphics.getDimensions()
  Kit.layout(W, H)
  local mx, my = love.mouse.getPosition()
  Kit.beginFrame(mx, my, Studio.clicked, Studio.wheel)
  Studio.clicked, Studio.wheel = false, 0

  Theme.fill(0, 0, W, H, PAL.bg, 1)

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

  if Studio.dirty then
    Kit.text("small", "unsaved", bx, pad * 0.5 + btnH * 0.3, PAL.yellow)
  end

  local closeW = 100 * Kit.scale
  if Kit.button(W - pad - closeW, pad * 0.5, closeW, btnH, "Close",
                { id = "close" }) then
    if Studio.onClose then Studio.onClose() end
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
  Kit.text("small", Kit.ellipsize("small", msg, cw), cx, footY, PAL.detail)

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

function Studio.keypressed(key)
  if Kit.focus then
    Kit.keypressed(key)
    return
  end
  if key == "escape" then
    if Studio.onClose then Studio.onClose() end
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
