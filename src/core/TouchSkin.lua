local TouchSkin = {}

TouchSkin.BUNDLED_ROOT = "assets/skins"
TouchSkin.USER_ROOT = "skins"
TouchSkin.EXPORT_ROOT = "skins/_export"

TouchSkin.GB_BUTTONS = {
  a = "a", b = "b", start = "start", select = "select",
  up = "up", down = "down", left = "left", right = "right",
}

TouchSkin.HOTKEYS = {
  overlay_next = "overlay_next",
  overlay_previous = "overlay_prev",
  menu_toggle = "menu",
  reset = "soft_reset",
  hold_fast_forward = "fast_forward_hold",
  fast_forward = "fast_forward_hold",
  toggle_fast_forward = "fast_forward_toggle",
  screenshot = "screenshot",
  pause_toggle = "pause",
  exit_emulator = "quit",
}

local DEFAULT_ASPECT = 16 / 9
local PORTRAIT_ASPECT = 9 / 16

local function trim(s)
  return (tostring(s or ""):match("^%s*(.-)%s*$"))
end

local function unquote(s)
  s = trim(s)
  local inner = s:match('^"(.*)"$')
  return inner or s
end

local function toBool(v)
  v = trim(v):lower()
  return v == "true" or v == "1"
end

local function tokens(s)
  local out = {}
  for tok in tostring(s or ""):gmatch("[^,%s]+") do out[#out + 1] = tok end
  return out
end

local function num(v, fallback)
  local n = tonumber(trim(v))
  if not n or n ~= n then return fallback end
  return n
end

function TouchSkin.parseConfig(text)
  local kv = {}
  for line in tostring(text or ""):gmatch("[^\r\n]+") do
    if not line:match("^%s*#") then
      local key, value = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
      if key then kv[key] = unquote(value) end
    end
  end
  return kv
end

local function parseBinds(spec)
  local buttons, hotkeys, keys, decorative = {}, {}, {}, true
  for raw in tostring(spec or ""):gmatch("[^|]+") do
    local name = trim(raw):lower()
    local key = name:match("^key:(.+)$") or name:match("^retrok_(.+)$")
    if name == "nul" or name == "" then
      -- decoration
    elseif key then
      keys[#keys + 1] = key
      decorative = false
    elseif TouchSkin.GB_BUTTONS[name] then
      buttons[#buttons + 1] = TouchSkin.GB_BUTTONS[name]
      decorative = false
    elseif TouchSkin.HOTKEYS[name] then
      hotkeys[#hotkeys + 1] = TouchSkin.HOTKEYS[name]
      decorative = false
    end
  end
  return buttons, hotkeys, keys, decorative
end

TouchSkin.AREA_DEFAULTS = {
  dpad_area = { up = "up", down = "down", left = "left", right = "right" },
  abxy_area = { up = "x", down = "b", left = "y", right = "a" },
  analog_left = { up = "up", down = "down", left = "left", right = "right" },
  analog_right = { up = "up", down = "down", left = "left", right = "right" },
}

local DIRECTIONAL_CELLS = {
  { col = 1, row = 1, h = "left", v = "up" },
  { col = 2, row = 1, v = "up" },
  { col = 3, row = 1, h = "right", v = "up" },
  { col = 1, row = 2, h = "left" },
  { col = 3, row = 2, h = "right" },
  { col = 1, row = 3, h = "left", v = "down" },
  { col = 2, row = 3, v = "down" },
  { col = 3, row = 3, h = "right", v = "down" },
}

local function outwardReach(reach)
  return 1 + 3 * ((num(reach, 1)) - 1)
end

function TouchSkin.expandDirectional(base, names)
  names = names or {}
  local cellX = math.abs(num(base.rangeX, 0.05)) / 3
  local cellY = math.abs(num(base.rangeY, 0.05)) / 3
  local out = {}
  for _, cell in ipairs(DIRECTIONAL_CELLS) do
    local parts = {}
    if cell.h and names[cell.h] then parts[#parts + 1] = names[cell.h] end
    if cell.v and names[cell.v] then parts[#parts + 1] = names[cell.v] end
    local spec = #parts > 0 and table.concat(parts, "|") or "nul"
    local ctl = TouchSkin.newControl(spec,
      num(base.x, 0.5) + (cell.col - 2) * cellX * 2,
      num(base.y, 0.5) + (cell.row - 2) * cellY * 2,
      cellX * 2, cellY * 2, "rect")
    ctl.rangeMod = num(base.rangeMod, 1)
    ctl.alphaMod = num(base.alphaMod, 1)
    ctl.reachLeft = cell.col == 1 and outwardReach(base.reachLeft) or 1
    ctl.reachRight = cell.col == 3 and outwardReach(base.reachRight) or 1
    ctl.reachUp = cell.row == 1 and outwardReach(base.reachUp) or 1
    ctl.reachDown = cell.row == 3 and outwardReach(base.reachDown) or 1
    ctl.pixelCoords = base.pixelCoords
    ctl.movable = base.movable
    ctl.exclusive = base.exclusive
    out[#out + 1] = ctl
  end
  return out
end

local SECTOR_CELLS = {
  { h = "right" },
  { h = "right", v = "down" },
  { v = "down" },
  { h = "left", v = "down" },
  { h = "left" },
  { h = "left", v = "up" },
  { v = "up" },
  { h = "right", v = "up" },
}

TouchSkin.SECTOR_SPAN = math.pi / 4

function TouchSkin.sectorHit(sector, dx, dy)
  local span = TouchSkin.SECTOR_SPAN
  local start = (sector - 1) * span - span * 0.5
  local a = (math.atan2(dy, dx) - start) % (math.pi * 2)
  return a < span
end

function TouchSkin.expandSectors(base, names)
  names = names or {}
  local out = {}
  for i, cell in ipairs(SECTOR_CELLS) do
    local parts = {}
    if cell.h and names[cell.h] then parts[#parts + 1] = names[cell.h] end
    if cell.v and names[cell.v] then parts[#parts + 1] = names[cell.v] end
    local spec = #parts > 0 and table.concat(parts, "|") or "nul"
    local ctl = TouchSkin.newControl(spec, num(base.x, 0.5), num(base.y, 0.5),
      math.abs(num(base.rangeX, 0.05)) * 2, math.abs(num(base.rangeY, 0.05)) * 2,
      base.shape)
    ctl.sector = i
    ctl.areaKind = base.areaKind
    ctl.areaNames = base.areaNames
    ctl.rangeMod = num(base.rangeMod, 1)
    ctl.alphaMod = num(base.alphaMod, 1)
    ctl.reachLeft = num(base.reachLeft, 1)
    ctl.reachRight = num(base.reachRight, 1)
    ctl.reachUp = num(base.reachUp, 1)
    ctl.reachDown = num(base.reachDown, 1)
    ctl.pixelCoords = base.pixelCoords
    ctl.movable = base.movable
    ctl.exclusive = base.exclusive
    out[#out + 1] = ctl
  end
  return out
end

local function areaSide(kv, prefix, side, fallback)
  local v = kv[prefix .. "_" .. side]
  if v == nil or trim(v) == "" then return fallback end
  return trim(v)
end

local function parseDesc(kv, prefix, page)
  local spec = kv[prefix]
  if not spec then return nil end
  local t = tokens(spec)
  if #t < 6 then return nil end

  local shape = trim(t[4]):lower()
  if shape ~= "radial" and shape ~= "rect" then shape = "rect" end

  local buttons, hotkeys, keys, decorative = parseBinds(t[1])
  local reachX = num(kv[prefix .. "_reach_x"], 1)
  local reachY = num(kv[prefix .. "_reach_y"], 1)

  local ctl = {
    spec = t[1],
    buttons = buttons,
    hotkeys = hotkeys,
    keys = keys,
    decorative = decorative,
    x = num(t[2], 0.5),
    y = num(t[3], 0.5),
    shape = shape,
    rangeX = math.abs(num(t[5], 0.05)),
    rangeY = math.abs(num(t[6], 0.05)),
    rangeMod = num(kv[prefix .. "_range_mod"], page.rangeMod),
    alphaMod = num(kv[prefix .. "_alpha_mod"], page.alphaMod),
    reachUp = num(kv[prefix .. "_reach_up"], reachY),
    reachDown = num(kv[prefix .. "_reach_down"], reachY),
    reachLeft = num(kv[prefix .. "_reach_left"], reachX),
    reachRight = num(kv[prefix .. "_reach_right"], reachX),
    imagePath = kv[prefix .. "_overlay"],
    pressedImagePath = kv[prefix .. "_overlay_pressed"],
    nextTarget = kv[prefix .. "_next_target"],
    movable = toBool(kv[prefix .. "_movable"]) or nil,
    exclusive = (toBool(kv[prefix .. "_exclusive"])
                 or toBool(kv[prefix .. "_range_mod_exclusive"])) or nil,
    saturatePct = num(kv[prefix .. "_saturate_pct"], nil),
  }
  if ctl.imagePath == "" then ctl.imagePath = nil end
  if ctl.pressedImagePath == "" then ctl.pressedImagePath = nil end

  local normalized = kv[prefix .. "_normalized"]
  if normalized ~= nil then ctl.pixelCoords = not toBool(normalized) end

  local areaKind = trim(t[1]):lower()
  local defaults = TouchSkin.AREA_DEFAULTS[areaKind]
  if defaults then
    ctl.areaKind = areaKind
    ctl.areaNames = {
      up = areaSide(kv, prefix, "up", defaults.up),
      down = areaSide(kv, prefix, "down", defaults.down),
      left = areaSide(kv, prefix, "left", defaults.left),
      right = areaSide(kv, prefix, "right", defaults.right),
    }
  end
  return ctl
end

function TouchSkin.parse(text)
  local kv = TouchSkin.parseConfig(text)
  local count = math.floor(num(kv.overlays, 0))
  if count <= 0 then return nil, "no overlays" end

  local pages, warnings = {}, {}
  local function warn(text)
    for _, existing in ipairs(warnings) do
      if existing == text then return end
    end
    warnings[#warnings + 1] = text
  end

  for i = 0, count - 1 do
    local p = "overlay" .. i
    local page = {
      index = i + 1,
      name = kv[p .. "_name"] or ("overlay" .. i),
      imagePath = kv[p .. "_overlay"],
      fullScreen = toBool(kv[p .. "_full_screen"]),
      normalized = toBool(kv[p .. "_normalized"]),
      rangeMod = num(kv[p .. "_range_mod"], 1),
      alphaMod = num(kv[p .. "_alpha_mod"], 1),
      aspect = num(kv[p .. "_aspect_ratio"], nil),
      controls = {},
    }
    if page.imagePath == "" then page.imagePath = nil end
    -- An explicit aspect_ratio is the overlay's design aspect.  RetroArch
    -- letterboxes to it even when full_screen is set, so range_x/range_y
    -- that were authored as a circle stay a circle.  #1503
    page.aspectFromCfg = page.aspect ~= nil and page.aspect > 0
    if not page.aspectFromCfg then
      page.aspect = page.name:lower():find("portrait", 1, true)
        and PORTRAIT_ASPECT or DEFAULT_ASPECT
    end

    local rect = tokens(kv[p .. "_rect"])
    page.rect = { x = 0, y = 0, w = 1, h = 1 }
    if #rect >= 4 then
      page.rect = { x = num(rect[1], 0), y = num(rect[2], 0),
                    w = num(rect[3], 1), h = num(rect[4], 1) }
    end

    local vp = tokens(kv[p .. "_viewport"])
    if #vp >= 4 then
      page.viewport = { x = num(vp[1], 0), y = num(vp[2], 0),
                        w = num(vp[3], 1), h = num(vp[4], 1) }
      page.viewportFill = toBool(kv[p .. "_viewport_fill"])
      page.viewportExpand = toBool(kv[p .. "_viewport_expand"])
    end

    page.pixelCoords = not page.normalized
    if page.pixelCoords and not page.imagePath then
      page.pixelCoords = false
      warn(page.name .. " has no base image: desc coordinates read as normalized")
    end

    local descs = math.floor(num(kv[p .. "_descs"], 0))
    for d = 0, descs - 1 do
      local ctl = parseDesc(kv, p .. "_desc" .. d, page)
      if not ctl then
        warn(page.name .. " is missing desc " .. d)
      elseif ctl.areaKind then
        if ctl.imagePath or ctl.pressedImagePath then
          local art = TouchSkin.newControl("nul", ctl.x, ctl.y,
            ctl.rangeX * 2, ctl.rangeY * 2, ctl.shape)
          art.imagePath = ctl.imagePath
          art.pressedImagePath = ctl.pressedImagePath
          art.rangeMod, art.alphaMod = ctl.rangeMod, ctl.alphaMod
          art.pixelCoords = ctl.pixelCoords
          art.movable, art.exclusive = ctl.movable, ctl.exclusive
          page.controls[#page.controls + 1] = art
        end
        for _, cell in ipairs(TouchSkin.expandSectors(ctl, ctl.areaNames)) do
          page.controls[#page.controls + 1] = cell
        end
      else
        page.controls[#page.controls + 1] = ctl
      end
    end
    pages[#pages + 1] = page
  end

  -- RetroArch auto-rotate: overlay names containing portrait / landscape
  -- are the lock.  Stamp it so the studio does not need a second click.  #1503
  for _, page in ipairs(pages) do
    if not page.orient then page.orient = TouchSkin.pageOrient(page) end
  end

  return { pages = pages, warnings = warnings }
end

local function readFile(path)
  if love and love.filesystem and love.filesystem.read then
    local ok, data = pcall(love.filesystem.read, path)
    if ok and data then return data end
  end
  local handle = io.open(path, "rb")
  if not handle then return nil end
  local data = handle:read("*a")
  handle:close()
  return data
end

local function listDir(path)
  if love and love.filesystem and love.filesystem.getDirectoryItems then
    local ok, items = pcall(love.filesystem.getDirectoryItems, path)
    if ok and items then return items end
  end
  return {}
end

local function isDir(path)
  if love and love.filesystem and love.filesystem.getInfo then
    local ok, info = pcall(love.filesystem.getInfo, path)
    if ok and info then return info.type == "directory" end
  end
  return false
end

local function joinPath(root, rel)
  rel = tostring(rel or ""):gsub("^%./", ""):gsub("\\", "/")
  if rel:sub(1, 1) == "/" then return rel:sub(2) end
  return root .. "/" .. rel
end

TouchSkin.NATIVE_NAME = "skin.lua"

TouchSkin.readFile = readFile
TouchSkin.listDir = listDir
TouchSkin.isDir = isDir

local function findConfig(root)
  if readFile(root .. "/" .. TouchSkin.NATIVE_NAME) then
    return root .. "/" .. TouchSkin.NATIVE_NAME, "native", ""
  end
  local named = { "overlay.cfg", "skin.cfg", "layout.cfg" }
  for _, name in ipairs(named) do
    if readFile(root .. "/" .. name) then
      return root .. "/" .. name, "retroarch", ""
    end
  end
  local infoPath, prefix = require("src.core.DeltaSkin").findInfo(root)
  if infoPath then return infoPath, "delta", prefix end
  local items = listDir(root)
  table.sort(items)
  for _, name in ipairs(items) do
    if name:match("%.cfg$") then return root .. "/" .. name, "retroarch", "" end
  end
  return nil
end

local function loadDataChunk(text, name)
  if loadstring then
    local chunk, err = loadstring(text, name)
    if not chunk then return nil, err end
    return setfenv(chunk, {})
  end
  return load(text, name, "t", {})
end

function TouchSkin.parseNative(text)
  local chunk, err = loadDataChunk(tostring(text or ""), "skin")
  if not chunk then return nil, "skin.lua does not parse: " .. tostring(err) end
  local ok, data = pcall(chunk)
  if not ok or type(data) ~= "table" then return nil, "skin.lua returned no table" end
  if type(data.pages) ~= "table" or not data.pages[1] then
    return nil, "skin.lua has no pages"
  end

  local pages = {}
  for i, raw in ipairs(data.pages) do
    if type(raw) ~= "table" then return nil, "page " .. i .. " is not a table" end
    local page = {
      index = i,
      name = tostring(raw.name or ("page" .. i)),
      imagePath = raw.image,
      fullScreen = raw.fullScreen ~= false,
      normalized = true,
      pixelCoords = false,
      rangeMod = num(raw.rangeMod, 1),
      alphaMod = num(raw.alphaMod, 1),
      aspect = num(raw.aspect, DEFAULT_ASPECT),
      aspectFromCfg = raw.fitAspect == true,
      orient = (raw.orient == "portrait" or raw.orient == "landscape"
                or raw.orient == "any") and raw.orient or nil,
      screenFit = raw.screenFit == "remainder" and "remainder" or nil,
      anchor = (raw.anchor == "top" or raw.anchor == "bottom"
                or raw.anchor == "left" or raw.anchor == "right")
                and raw.anchor or nil,
      rect = { x = 0, y = 0, w = 1, h = 1 },
      controls = {},
    }
    if type(raw.rect) == "table" then
      page.rect = { x = num(raw.rect.x, 0), y = num(raw.rect.y, 0),
                    w = num(raw.rect.w, 1), h = num(raw.rect.h, 1) }
    end
    if type(raw.viewport) == "table" then
      page.viewport = { x = num(raw.viewport.x, 0), y = num(raw.viewport.y, 0),
                        w = num(raw.viewport.w, 1), h = num(raw.viewport.h, 1) }
      page.viewportFill = raw.viewport.fill == true
      page.viewportExpand = raw.viewport.expand == true
    end
    for _, c in ipairs(raw.controls or {}) do
      local buttons, hotkeys, keys, decorative = parseBinds(c.bind or "nul")
      local sector = tonumber(c.sector)
      if sector then
        sector = math.floor(sector)
        if sector < 1 or sector > #SECTOR_CELLS then sector = nil end
      end
      local areaNames
      if type(c.areaNames) == "table" then
        areaNames = {}
        for _, side in ipairs({ "up", "down", "left", "right" }) do
          if type(c.areaNames[side]) == "string" then
            areaNames[side] = c.areaNames[side]
          end
        end
      end
      page.controls[#page.controls + 1] = {
        sector = sector,
        areaKind = type(c.areaKind) == "string" and c.areaKind or nil,
        areaNames = areaNames,
        spec = tostring(c.bind or "nul"),
        buttons = buttons, hotkeys = hotkeys, keys = keys,
        decorative = decorative,
        x = num(c.x, 0.5), y = num(c.y, 0.5),
        shape = c.shape == "radial" and "radial" or "rect",
        rangeX = math.abs(num(c.w, 0.1)) * 0.5,
        rangeY = math.abs(num(c.h, 0.1)) * 0.5,
        rangeMod = num(c.rangeMod, page.rangeMod),
        alphaMod = num(c.alphaMod, page.alphaMod),
        reachUp = num(c.reachUp, 1), reachDown = num(c.reachDown, 1),
        reachLeft = num(c.reachLeft, 1), reachRight = num(c.reachRight, 1),
        imagePath = c.image,
        pressedImagePath = c.imagePressed,
        nextTarget = c.nextTarget,
        movable = c.movable == true or nil,
        exclusive = c.exclusive == true or nil,
      }
    end
    if not page.orient then page.orient = TouchSkin.pageOrient(page) end
    pages[#pages + 1] = page
  end
  return { pages = pages, name = data.name, author = data.author,
           notes = data.notes, format = "native" }
end

function TouchSkin.toNative(skin)
  local out = {
    name = skin.name or skin.id,
    author = skin.author,
    notes = skin.notes,
    format = 1,
    pages = {},
  }
  for _, page in ipairs(skin.pages or {}) do
    local p = {
      name = page.name,
      image = page.imagePath,
      fullScreen = page.fullScreen ~= false,
      rangeMod = page.rangeMod,
      alphaMod = page.alphaMod,
      aspect = page.aspect,
      fitAspect = page.aspectFromCfg or nil,
      screenFit = page.screenFit == "remainder" and "remainder" or nil,
      anchor = page.anchor,
      orient = (page.orient == "portrait" or page.orient == "landscape"
                or page.orient == "any") and page.orient or nil,
      controls = {},
    }
    if page.rect and (page.rect.x ~= 0 or page.rect.y ~= 0
                      or page.rect.w ~= 1 or page.rect.h ~= 1) then
      p.rect = { x = page.rect.x, y = page.rect.y, w = page.rect.w, h = page.rect.h }
    end
    if page.viewport then
      p.viewport = {
        x = page.viewport.x, y = page.viewport.y,
        w = page.viewport.w, h = page.viewport.h,
        fill = page.viewportFill or nil,
        expand = page.viewportExpand or nil,
      }
    end
    for _, ctl in ipairs(page.controls or {}) do
      p.controls[#p.controls + 1] = {
        bind = ctl.spec,
        x = ctl.x, y = ctl.y,
        w = ctl.rangeX * 2, h = ctl.rangeY * 2,
        shape = ctl.shape,
        rangeMod = ctl.rangeMod ~= p.rangeMod and ctl.rangeMod or nil,
        alphaMod = ctl.alphaMod ~= p.alphaMod and ctl.alphaMod or nil,
        reachUp = ctl.reachUp ~= 1 and ctl.reachUp or nil,
        reachDown = ctl.reachDown ~= 1 and ctl.reachDown or nil,
        reachLeft = ctl.reachLeft ~= 1 and ctl.reachLeft or nil,
        reachRight = ctl.reachRight ~= 1 and ctl.reachRight or nil,
        image = ctl.imagePath,
        imagePressed = ctl.pressedImagePath,
        nextTarget = ctl.nextTarget,
        movable = ctl.movable or nil,
        exclusive = ctl.exclusive or nil,
        sector = ctl.sector,
        areaKind = ctl.areaKind,
        areaNames = ctl.areaNames and {
          up = ctl.areaNames.up, down = ctl.areaNames.down,
          left = ctl.areaNames.left, right = ctl.areaNames.right,
        } or nil,
      }
    end
    out.pages[#out.pages + 1] = p
  end
  return out
end

function TouchSkin.serialize(skin)
  return require("src.import.LuaWriter").encode(TouchSkin.toNative(skin))
end

local imageCache = setmetatable({}, { __mode = "v" })

local function loadImage(path)
  if not (love and love.graphics and love.graphics.newImage) then return nil end
  local cached = imageCache[path]
  if cached then return cached end
  local ok, img = pcall(love.graphics.newImage, path)
  if not ok or not img then return nil end
  if img.setFilter then img:setFilter("linear", "linear") end
  imageCache[path] = img
  return img
end

-- FileData so LOVE sniffs JPEG/PNG from the name, not a path inside the zip.
local function loadImageFromBytes(bytes, name)
  if not bytes or bytes == "" then return nil end
  if not (love and love.graphics and love.graphics.newImage) then return nil end
  if not (love.filesystem and love.filesystem.newFileData) then return nil end
  local key = "bytes:" .. tostring(name) .. ":" .. tostring(#bytes)
  local cached = imageCache[key]
  if cached then return cached end
  local okFd, fd = pcall(love.filesystem.newFileData, bytes, name or "bezel.jpg")
  if not okFd or not fd then return nil end
  local ok, img = pcall(love.graphics.newImage, fd)
  if not ok or not img then
    if love.image and love.image.newImageData then
      local okData, data = pcall(love.image.newImageData, fd)
      if okData and data then ok, img = pcall(love.graphics.newImage, data) end
    end
  end
  if not ok or not img then return nil end
  if img.setFilter then img:setFilter("linear", "linear") end
  imageCache[key] = img
  return img
end

local function rasterizePdfPage(page, root)
  if not page or page.image or not page.pdfPath then return end
  local pdf = readFile(joinPath(root, page.pdfPath))
  local raster = require("src.core.PdfImage").extract(pdf)
  if not raster then return end
  local name = tostring(page.pdfPath):gsub("%.[Pp][Dd][Ff]$", "") .. "." .. raster.ext
  page.rasterData = raster.data
  page.rasterName = name:match("([^/]+)$") or name
  page.image = loadImageFromBytes(raster.data, page.rasterName)
end

local function pixelScalePending(page)
  if page.pixelCoords then return true end
  for _, ctl in ipairs(page.controls or {}) do
    if ctl.pixelCoords then return true end
  end
  return false
end

local function applyPixelScale(page)
  if not pixelScalePending(page) then return true end
  if not page.image or not page.image.getDimensions then return false end
  local iw, ih = page.image:getDimensions()
  if not iw or not ih or iw <= 0 or ih <= 0 then return false end
  for _, ctl in ipairs(page.controls or {}) do
    local pixel = ctl.pixelCoords
    if pixel == nil then pixel = page.pixelCoords end
    if pixel then
      ctl.x, ctl.y = ctl.x / iw, ctl.y / ih
      ctl.rangeX, ctl.rangeY = ctl.rangeX / iw, ctl.rangeY / ih
      ctl.pixelCoords = false
    end
  end
  page.pixelCoords = false
  return true
end

function TouchSkin.load(root, id)
  local cfgPath, format, prefix = findConfig(root)
  if not cfgPath then return nil, "no skin.lua, .cfg or info.json in " .. root end
  local text = readFile(cfgPath)
  if not text then return nil, "unreadable " .. cfgPath end
  local skin, err
  if format == "native" then
    skin, err = TouchSkin.parseNative(text)
  elseif format == "delta" then
    local dir = cfgPath:match("^(.*)/[^/]+$") or root
    skin, err = require("src.core.DeltaSkin").parse(text,
      { prefix = prefix or "", names = listDir(dir) })
  else
    skin, err = TouchSkin.parse(text)
  end
  if not skin then return nil, err end

  skin.id = id or root:match("([^/]+)$") or root
  skin.root = root
  skin.configPath = cfgPath
  skin.format = format
  skin.name = skin.name or skin.pages[1] and skin.pages[1].name or skin.id

  for _, page in ipairs(skin.pages) do
    if page.imagePath then
      page.image = loadImage(joinPath(root, page.imagePath))
    elseif page.pdfPath then
      rasterizePdfPage(page, root)
    end
    if not applyPixelScale(page) then
      return nil, "could not read " .. tostring(page.imagePath)
        .. ", which " .. page.name .. " measures its coordinates against"
    end
    for _, ctl in ipairs(page.controls) do
      if ctl.imagePath then ctl.image = loadImage(joinPath(root, ctl.imagePath)) end
      if ctl.pressedImagePath then
        ctl.pressedImage = loadImage(joinPath(root, ctl.pressedImagePath))
      end
    end
  end
  return skin
end

local function mountZip(archive, point)
  if not (love and love.filesystem and love.filesystem.mount) then return false end
  local ok, mounted = pcall(love.filesystem.mount, archive, point)
  return ok and mounted == true
end

TouchSkin.ARCHIVE_EXTS = { zip = true, deltaskin = true }
TouchSkin.LEGACY_EXTS = { gbcskin = true, gbaskin = true, gbskin = true }
TouchSkin.PDF_ONLY_MESSAGE =
  "This skin uses PDF artwork with no extractable image. "
  .. "Ask the author for a PNG version."

function TouchSkin.archiveId(name)
  name = tostring(name or "")
  local ext = name:match("%.([%w]+)$")
  if not ext or not TouchSkin.ARCHIVE_EXTS[ext:lower()] then return nil end
  local id = name:sub(1, #name - #ext - 1)
  if id == "" then return nil end
  return id, ext:lower()
end

function TouchSkin.list()
  local out, seen = {}, {}
  local function scan(root, source)
    for _, name in ipairs(listDir(root)) do
      local archiveId = TouchSkin.archiveId(name)
      local id = archiveId or name
      if not seen[id] and name:sub(1, 1) ~= "_" then
        local path = root .. "/" .. name
        if archiveId then
          local point = TouchSkin.USER_ROOT .. "/_mounted/" .. id
          if mountZip(path, point) and findConfig(point) then
            seen[id] = true
            out[#out + 1] = { id = id, root = point, source = source, archive = path }
          end
        elseif isDir(path) and findConfig(path) then
          seen[id] = true
          out[#out + 1] = { id = id, root = path, source = source }
        end
      end
    end
  end
  if love and love.filesystem and love.filesystem.createDirectory then
    pcall(love.filesystem.createDirectory, TouchSkin.USER_ROOT)
  end
  scan(TouchSkin.USER_ROOT, "user")
  scan(TouchSkin.BUNDLED_ROOT, "bundled")
  table.sort(out, function(a, b) return a.id < b.id end)
  return out
end

-- Drop a .zip or .deltaskin into <save>/skins and report the id it lists under.
function TouchSkin.installArchive(name, data)
  if not data or data == "" then return nil, "empty archive" end
  if not (love and love.filesystem and love.filesystem.write) then
    return nil, "no writable filesystem"
  end
  name = tostring(name or ""):match("([^/\\]+)$") or ""
  name = name:gsub("[^%w%._%-]", "_"):gsub("^_+", "")
  local legacy = name:match("%.([%w]+)$")
  if legacy and TouchSkin.LEGACY_EXTS[legacy:lower()] then
    return nil, "old GBA4iOS skin, not supported"
  end
  local id = TouchSkin.archiveId(name)
  if not id then return nil, "not a .zip or .deltaskin" end

  pcall(love.filesystem.createDirectory, TouchSkin.USER_ROOT)
  local dest = TouchSkin.USER_ROOT .. "/" .. name
  local ok, err = love.filesystem.write(dest, data)
  if not ok then return nil, tostring(err) end

  local entry = TouchSkin.find(id)
  if not entry then
    love.filesystem.remove(dest)
    return nil, "no skin.lua, .cfg or info.json inside " .. name
  end
  local skin = TouchSkin.load(entry.root, entry.id)
  if skin and require("src.core.DeltaSkin").needsConversion(skin) then
    love.filesystem.remove(dest)
    return nil, TouchSkin.PDF_ONLY_MESSAGE
  end
  return id, skin and skin.warnings or nil
end

function TouchSkin.find(id)
  if not id or id == "" then return nil end
  for _, entry in ipairs(TouchSkin.list()) do
    if entry.id == id then return entry end
  end
  return nil
end

function TouchSkin.assetPaths(skin)
  local out, seen = {}, {}
  local function add(rel)
    if rel and rel ~= "" and not seen[rel] then
      seen[rel] = true
      out[#out + 1] = rel
    end
  end
  for _, page in ipairs(skin.pages or {}) do
    add(page.imagePath)
    for _, ctl in ipairs(page.controls or {}) do
      add(ctl.imagePath)
      add(ctl.pressedImagePath)
    end
  end
  return out
end

local function writeArchive(entries, destPath)
  local blob = require("src.core.SkinZip").encode(entries)
  local absolute = destPath:sub(1, 1) == "/" or destPath:match("^%a:[/\\]") ~= nil
  if not absolute and love and love.filesystem and love.filesystem.createDirectory then
    local dir = destPath:match("^(.*)/[^/]+$")
    if dir then pcall(love.filesystem.createDirectory, dir) end
  end
  if not absolute and love and love.filesystem and love.filesystem.write then
    local ok, err = love.filesystem.write(destPath, blob)
    if not ok then return nil, tostring(err) end
  else
    local handle = io.open(destPath, "wb")
    if not handle then return nil, "cannot write " .. destPath end
    handle:write(blob)
    handle:close()
  end
  return destPath
end

local function collectAssets(skin, rels)
  local entries, missing = {}, {}
  for _, rel in ipairs(rels) do
    local data = readFile(joinPath(skin.root, rel))
    if data then
      entries[#entries + 1] = { name = rel, data = data }
    else
      missing[#missing + 1] = rel
    end
  end
  return entries, missing
end

function TouchSkin.export(skin, destPath)
  if not skin then return nil, "no skin" end
  local entries = { { name = TouchSkin.NATIVE_NAME, data = TouchSkin.serialize(skin) } }
  local assets, missing = collectAssets(skin, TouchSkin.assetPaths(skin))
  for _, entry in ipairs(assets) do entries[#entries + 1] = entry end
  if skin.configPath and skin.format == "retroarch" then
    local cfg = readFile(skin.configPath)
    if cfg then
      entries[#entries + 1] =
        { name = skin.configPath:match("([^/]+)$") or "overlay.cfg", data = cfg }
    end
  end
  destPath = destPath or (TouchSkin.EXPORT_ROOT .. "/" .. skin.id .. "-export.zip")
  local written, err = writeArchive(entries, destPath)
  if not written then return nil, err end
  return destPath, missing
end

local function fmtNum(n)
  n = tonumber(n) or 0
  if n == math.floor(n) then return string.format("%d", n) end
  local s = string.format("%.6f", n):gsub("0+$", ""):gsub("%.$", "")
  return s
end

local function fmtRect(r)
  return ('"%s,%s,%s,%s"'):format(fmtNum(r.x), fmtNum(r.y), fmtNum(r.w), fmtNum(r.h))
end

local function cfgSpec(spec)
  local parts = {}
  for raw in tostring(spec or ""):gmatch("[^|]+") do
    local name = trim(raw)
    local key = name:lower():match("^key:(.+)$")
    parts[#parts + 1] = key and ("retrok_" .. key) or name
  end
  return table.concat(parts, "|")
end

function TouchSkin.toRetroArchConfig(skin)
  local pages = (skin and skin.pages) or {}
  local out = { "overlays = " .. #pages }
  for i, page in ipairs(pages) do
    local p = "overlay" .. (i - 1)
    out[#out + 1] = ""
    out[#out + 1] = p .. '_name = "' .. tostring(page.name or ("overlay" .. (i - 1))) .. '"'
    if page.imagePath then out[#out + 1] = p .. "_overlay = " .. page.imagePath end
    out[#out + 1] = p .. "_full_screen = " .. (page.fullScreen ~= false and "true" or "false")
    out[#out + 1] = p .. "_normalized = true"
    if num(page.rangeMod, 1) ~= 1 then
      out[#out + 1] = p .. "_range_mod = " .. fmtNum(page.rangeMod)
    end
    if num(page.alphaMod, 1) ~= 1 then
      out[#out + 1] = p .. "_alpha_mod = " .. fmtNum(page.alphaMod)
    end
    if page.aspectFromCfg and page.aspect and page.aspect > 0 then
      out[#out + 1] = p .. "_aspect_ratio = " .. fmtNum(page.aspect)
    end
    local r = page.rect
    if r and (r.x ~= 0 or r.y ~= 0 or r.w ~= 1 or r.h ~= 1) then
      out[#out + 1] = p .. "_rect = " .. fmtRect(r)
    end
    if page.viewport then
      out[#out + 1] = p .. "_viewport = " .. fmtRect(page.viewport)
      if page.viewportFill then out[#out + 1] = p .. "_viewport_fill = true" end
      if page.viewportExpand then out[#out + 1] = p .. "_viewport_expand = true" end
    end
    local controls = {}
    for _, ctl in ipairs(page.controls or {}) do
      if not ctl.sector or ctl.sector == 1 then controls[#controls + 1] = ctl end
    end
    out[#out + 1] = p .. "_descs = " .. #controls
    for j, ctl in ipairs(controls) do
      local d = p .. "_desc" .. (j - 1)
      local spec = ctl.areaKind and ctl.sector and ctl.areaKind
        or cfgSpec(ctl.spec)
      if spec == "" then spec = "nul" end
      out[#out + 1] = ('%s = "%s,%s,%s,%s,%s,%s"'):format(d, spec,
        fmtNum(ctl.x), fmtNum(ctl.y),
        ctl.shape == "radial" and "radial" or "rect",
        fmtNum(ctl.rangeX), fmtNum(ctl.rangeY))
      if ctl.imagePath then out[#out + 1] = d .. "_overlay = " .. ctl.imagePath end
      if ctl.pressedImagePath then
        out[#out + 1] = d .. "_overlay_pressed = " .. ctl.pressedImagePath
      end
      if num(ctl.rangeMod, 1) ~= num(page.rangeMod, 1) then
        out[#out + 1] = d .. "_range_mod = " .. fmtNum(ctl.rangeMod)
      end
      if num(ctl.alphaMod, 1) ~= num(page.alphaMod, 1) then
        out[#out + 1] = d .. "_alpha_mod = " .. fmtNum(ctl.alphaMod)
      end
      for key, value in pairs({ up = ctl.reachUp, down = ctl.reachDown,
                                left = ctl.reachLeft, right = ctl.reachRight }) do
        if num(value, 1) ~= 1 then
          out[#out + 1] = d .. "_reach_" .. key .. " = " .. fmtNum(value)
        end
      end
      if ctl.movable then out[#out + 1] = d .. "_movable = true" end
      if ctl.exclusive then out[#out + 1] = d .. "_exclusive = true" end
      if ctl.nextTarget then
        out[#out + 1] = d .. '_next_target = "' .. tostring(ctl.nextTarget) .. '"'
      end
      if ctl.areaKind and ctl.sector and ctl.areaNames then
        local defaults = TouchSkin.AREA_DEFAULTS[ctl.areaKind] or {}
        for _, side in ipairs({ "up", "down", "left", "right" }) do
          local name = ctl.areaNames[side]
          if name and name ~= defaults[side] then
            out[#out + 1] = d .. "_" .. side .. ' = "' .. name .. '"'
          end
        end
      end
    end
  end
  return table.concat(out, "\n") .. "\n"
end

function TouchSkin.exportRetroArch(skin, destPath)
  if not skin then return nil, "no skin" end
  local entries = { { name = "overlay.cfg", data = TouchSkin.toRetroArchConfig(skin) } }
  local assets, missing = collectAssets(skin, TouchSkin.assetPaths(skin))
  for _, entry in ipairs(assets) do entries[#entries + 1] = entry end
  destPath = destPath or (TouchSkin.EXPORT_ROOT .. "/" .. skin.id .. "-retroarch.zip")
  local written, err = writeArchive(entries, destPath)
  if not written then return nil, err end
  return destPath, missing
end

function TouchSkin.exportDelta(skin, opts)
  if not skin then return nil, "no skin" end
  opts = opts or {}
  local DeltaSkin = require("src.core.DeltaSkin")
  local info, assetRels, warnings = DeltaSkin.build(skin, opts)
  if not info then return nil, assetRels end
  local entries = {
    { name = DeltaSkin.INFO_NAME, data = require("src.link.Json").encode(info) },
  }
  local assets, missing = collectAssets(skin, assetRels)
  for _, entry in ipairs(assets) do entries[#entries + 1] = entry end
  local destPath = opts.path
    or (TouchSkin.EXPORT_ROOT .. "/" .. skin.id .. ".deltaskin")
  local written, err = writeArchive(entries, destPath)
  if not written then return nil, err end
  return destPath, missing, warnings
end

TouchSkin.BINDS = {
  "nul",
  "up", "down", "left", "right",
  "a", "b", "start", "select",
  "left|up", "right|up", "left|down", "right|down",
  "hold_fast_forward", "toggle_fast_forward", "reset", "menu_toggle",
  "overlay_next",
}

function TouchSkin.describeBind(spec)
  local buttons, hotkeys, keys, decorative = parseBinds(spec)
  if decorative then return "decoration" end
  local parts = {}
  for _, b in ipairs(buttons) do parts[#parts + 1] = "GB " .. b:upper() end
  for _, h in ipairs(hotkeys) do parts[#parts + 1] = h end
  for _, k in ipairs(keys) do parts[#parts + 1] = "key " .. k end
  return table.concat(parts, " + ")
end

function TouchSkin.newControl(spec, x, y, w, h, shape)
  local buttons, hotkeys, keys, decorative = parseBinds(spec)
  return {
    spec = spec, buttons = buttons, hotkeys = hotkeys, keys = keys,
    decorative = decorative,
    x = x, y = y, rangeX = w * 0.5, rangeY = h * 0.5,
    shape = shape == "radial" and "radial" or "rect",
    rangeMod = 1, alphaMod = 1,
    reachUp = 1, reachDown = 1, reachLeft = 1, reachRight = 1,
  }
end

function TouchSkin.setBind(ctl, spec)
  ctl.spec = spec
  ctl.buttons, ctl.hotkeys, ctl.keys, ctl.decorative = parseBinds(spec)
  return ctl
end

function TouchSkin.newSkin(id)
  local page = {
    index = 1, name = "main", fullScreen = true, normalized = true,
    rangeMod = 1, alphaMod = 1, aspect = PORTRAIT_ASPECT,
    rect = { x = 0, y = 0, w = 1, h = 1 },
    viewport = { x = 0, y = 0, w = 1, h = 0.5 },
    viewportFill = false,
    controls = {},
  }
  return { id = id or "new_skin", name = id or "new_skin",
           root = TouchSkin.USER_ROOT .. "/" .. (id or "new_skin"),
           format = "native", pages = { page } }
end

local function copyTable(src)
  if type(src) ~= "table" then return src end
  local out = {}
  for k, v in pairs(src) do out[k] = copyTable(v) end
  return out
end

function TouchSkin.clone(skin)
  if not skin then return nil end
  local out = {
    id = skin.id, name = skin.name, root = skin.root, format = skin.format,
    author = skin.author, notes = skin.notes, configPath = skin.configPath,
    source = skin.source, pages = {},
    warnings = skin.warnings and copyTable(skin.warnings) or nil,
  }
  for i, page in ipairs(skin.pages or {}) do
    local p = copyTable(page)
    p.image = page.image
    p.controls = {}
    for j, ctl in ipairs(page.controls or {}) do
      local c = copyTable(ctl)
      c.image = ctl.image
      c.pressedImage = ctl.pressedImage
      p.controls[j] = c
    end
    out.pages[i] = p
  end
  return out
end

function TouchSkin.resolveImage(root, rel)
  if not rel or rel == "" then return nil end
  return loadImage(joinPath(root, rel))
end

function TouchSkin.detectViewport(root, imagePath)
  if not (love and love.image and love.image.newImageData) then return nil end
  if not imagePath or imagePath == "" then return nil end
  local ok, data = pcall(love.image.newImageData, joinPath(root, imagePath))
  if not ok or not data then return nil end
  local w, h = data:getWidth(), data:getHeight()
  if w < 2 or h < 2 then return nil end

  local function clear(x, y)
    if x < 0 or y < 0 or x >= w or y >= h then return false end
    local okp, _, _, _, a = pcall(data.getPixel, data, x, y)
    return okp and a ~= nil and a < 0.05
  end

  local cx, cy = math.floor(w / 2), math.floor(h / 2)
  if not clear(cx, cy) then return nil end

  local left, right = cx, cx
  while left > 0 and clear(left - 1, cy) do left = left - 1 end
  while right < w - 1 and clear(right + 1, cy) do right = right + 1 end
  local top, bottom = cy, cy
  while top > 0 and clear(cx, top - 1) do top = top - 1 end
  while bottom < h - 1 and clear(cx, bottom + 1) do bottom = bottom + 1 end

  local rw, rh = right - left + 1, bottom - top + 1
  if rw < 8 or rh < 8 then return nil end
  return { x = left / w, y = top / h, w = rw / w, h = rh / h }, rw, rh
end

-- Bring outside art into the skin's own folder.  A skin still living in
-- assets/ or a mounted zip is saved out to <save>/skins/<id> first, because
-- that is the only root the engine can write to.
function TouchSkin.importImage(skin, name, data)
  if not skin then return nil, "no skin" end
  if not data or data == "" then return nil, "no image data" end
  if not (love and love.filesystem and love.filesystem.write) then
    return nil, "no writable filesystem"
  end
  name = tostring(name):gsub("[^%w%._%-]", "_")
  if name == "" then return nil, "bad file name" end

  local dest = TouchSkin.USER_ROOT .. "/" .. skin.id
  if skin.root ~= dest then
    local saved, err = TouchSkin.saveTo(skin, skin.id)
    if not saved then return nil, tostring(err) end
  end
  pcall(love.filesystem.createDirectory, dest .. "/img")
  local rel = "img/" .. name
  local ok, err = love.filesystem.write(dest .. "/" .. rel, data)
  if not ok then return nil, tostring(err) end
  return rel
end

function TouchSkin.listImages(root)
  local out = {}
  local function scan(dir, prefix)
    for _, name in ipairs(listDir(dir)) do
      local path = dir .. "/" .. name
      local lower = name:lower()
      if lower:match("%.png$") or lower:match("%.jpg$") or lower:match("%.jpeg$") then
        out[#out + 1] = prefix .. name
      elseif isDir(path) and prefix == "" then
        scan(path, name .. "/")
      end
    end
  end
  scan(root, "")
  table.sort(out)
  return out
end

function TouchSkin.saveTo(skin, id)
  id = id or skin.id
  if not id or id == "" then return nil, "no skin id" end
  if not (love and love.filesystem and love.filesystem.write) then
    return nil, "no writable filesystem"
  end
  local dest = TouchSkin.USER_ROOT .. "/" .. id
  pcall(love.filesystem.createDirectory, dest)

  local copied, failed = 0, {}
  for _, rel in ipairs(TouchSkin.assetPaths(skin)) do
    local target = dest .. "/" .. rel
    local dir = target:match("^(.*)/[^/]+$")
    if dir then pcall(love.filesystem.createDirectory, dir) end
    if skin.root ~= dest then
      local data = readFile(joinPath(skin.root, rel))
      if data then
        if love.filesystem.write(target, data) then copied = copied + 1 end
      else
        failed[#failed + 1] = rel
      end
    end
  end

  local ok, err = love.filesystem.write(dest .. "/" .. TouchSkin.NATIVE_NAME,
                                        TouchSkin.serialize(skin))
  if not ok then return nil, tostring(err) end
  skin.id, skin.root, skin.format = id, dest, "native"
  return dest, failed, copied
end

TouchSkin.active = nil
TouchSkin.pageIndex = 1
-- RetroArch Auto-Rotate Overlay (1.7.9, default on mobile): a cfg whose
-- pages are named portrait / landscape is swapped to match the display.
-- The Skin Studio turns this off so PAGE and the canvas preset stay independent.
TouchSkin.autoOrient = true

TouchSkin.surfaceRect = nil

function TouchSkin.setSurface(x, y, w, h)
  if not w or w <= 0 or not h or h <= 0 then
    TouchSkin.surfaceRect = nil
  else
    TouchSkin.surfaceRect = { x = x, y = y, w = w, h = h }
  end
  return TouchSkin.surfaceRect
end

function TouchSkin.setActive(skin)
  TouchSkin.active = skin or nil
  TouchSkin.pageIndex = 1
  return TouchSkin.active
end

function TouchSkin.select(id)
  if not id or id == "" then return TouchSkin.setActive(nil) end
  local entry = TouchSkin.find(id)
  if not entry then return nil, "no skin " .. tostring(id) end
  local skin, err = TouchSkin.load(entry.root, entry.id)
  if not skin then return nil, err end
  skin.source = entry.source
  return TouchSkin.setActive(skin)
end

local function displaySize()
  local r = TouchSkin.surfaceRect
  if r and r.w and r.h and r.w > 0 and r.h > 0 then return r.w, r.h end
  if love and love.graphics and love.graphics.getDimensions then
    return love.graphics.getDimensions()
  end
  return 0, 0
end

-- Explicit lock (studio) wins; otherwise the page name, the RetroArch
-- auto-rotate convention.  "any" means unlocked even if the name says
-- portrait or landscape.
function TouchSkin.pageOrient(page)
  if not page then return nil end
  if page.orient == "any" then return nil end
  if page.orient == "portrait" or page.orient == "landscape" then
    return page.orient
  end
  local n = tostring(page.name or ""):lower()
  if n:find("landscape", 1, true) then return "landscape" end
  if n:find("portrait", 1, true) then return "portrait" end
  return nil
end

function TouchSkin.hasOrientPair(skin)
  local saw = {}
  for _, page in ipairs(skin and skin.pages or {}) do
    local o = TouchSkin.pageOrient(page)
    if o then saw[o] = true end
  end
  return saw.portrait == true and saw.landscape == true
end

local function findOrientPage(skin, keyword)
  for i, page in ipairs(skin.pages or {}) do
    if TouchSkin.pageOrient(page) == keyword then return i end
  end
  return nil
end

-- If the current page is the wrong orientation of a portrait/landscape pair,
-- jump to the matching one.  Pages locked to neither (gb_anim's GameBoy /
-- GameBoyColor) are left alone.  #1503
function TouchSkin.syncOrientation(w, h)
  if not TouchSkin.autoOrient then return end
  local skin = TouchSkin.active
  if not skin or not w or not h or w <= 0 or h <= 0 then return end
  local want = w > h and "landscape" or "portrait"
  local unwant = w > h and "portrait" or "landscape"
  local page = skin.pages[TouchSkin.pageIndex] or skin.pages[1]
  local current = TouchSkin.pageOrient(page)
  if current == want then return end
  if current ~= unwant then return end
  local idx = findOrientPage(skin, want)
  if idx then TouchSkin.pageIndex = idx end
end

function TouchSkin.page()
  local skin = TouchSkin.active
  if not skin then return nil end
  local w, h = displaySize()
  TouchSkin.syncOrientation(w, h)
  return skin.pages[TouchSkin.pageIndex] or skin.pages[1]
end

function TouchSkin.setPage(target)
  local skin = TouchSkin.active
  if not skin then return nil end
  if type(target) == "number" then
    local n = #skin.pages
    TouchSkin.pageIndex = ((math.floor(target) - 1) % n) + 1
    return TouchSkin.page()
  end
  for i, page in ipairs(skin.pages) do
    if page.name == target then
      TouchSkin.pageIndex = i
      return page
    end
  end
  return TouchSkin.page()
end

function TouchSkin.nextPage(target)
  local skin = TouchSkin.active
  if not skin then return nil end
  if target and target ~= "" then return TouchSkin.setPage(target) end
  return TouchSkin.setPage(TouchSkin.pageIndex + 1)
end

function TouchSkin.pageBox(page, w, h, ox, oy)
  ox, oy = ox or 0, oy or 0
  if not page then return ox, oy, w, h end
  local bx, by, bw, bh = ox, oy, w, h
  -- full_screen means "relative to the window, not the game viewport".
  -- When the cfg also names an aspect_ratio, that window is then fitted
  -- to the overlay's design aspect so buttons do not stretch.  #1503
  local fit = ((not page.fullScreen) or page.aspectFromCfg)
    and page.aspect and page.aspect > 0 and h > 0
  if fit then
    local displayAspect = w / h
    local anchor = page.anchor
    if displayAspect > page.aspect then
      bw = h * page.aspect
      local extra = w - bw
      if anchor == "right" then
        bx = ox + extra
      elseif anchor == "left" then
        bx = ox
      else
        bx = ox + extra * 0.5
      end
    else
      bh = w / page.aspect
      local extra = h - bh
      if anchor == "bottom" then
        by = oy + extra
      elseif anchor == "top" then
        by = oy
      else
        by = oy + extra * 0.5
      end
    end
  end
  local r = page.rect
  return bx + r.x * bw, by + r.y * bh, r.w * bw, r.h * bh
end

function TouchSkin.controlGeometry(page, ctl, w, h, ox, oy)
  local bx, by, bw, bh = TouchSkin.pageBox(page, w, h, ox, oy)
  local cx, cy = bx + ctl.x * bw, by + ctl.y * bh
  local halfW, halfH = ctl.rangeX * bw, ctl.rangeY * bh
  return cx, cy, halfW, halfH
end

function TouchSkin.hits(page, ctl, w, h, px, py, ox, oy, held)
  local cx, cy, halfW, halfH = TouchSkin.controlGeometry(page, ctl, w, h, ox, oy)
  local mod = held == false and 1 or ctl.rangeMod
  local left = halfW * ctl.reachLeft * mod
  local right = halfW * ctl.reachRight * mod
  local up = halfH * ctl.reachUp * mod
  local down = halfH * ctl.reachDown * mod
  local dx = px - cx
  local dy = py - cy
  local rx = dx < 0 and left or right
  local ry = dy < 0 and up or down
  if rx <= 0 or ry <= 0 then return false end
  if ctl.sector and not TouchSkin.sectorHit(ctl.sector, dx, dy) then
    return false
  end
  if ctl.shape == "radial" then
    return (dx * dx) / (rx * rx) + (dy * dy) / (ry * ry) <= 1
  end
  return math.abs(dx) <= rx and math.abs(dy) <= ry
end

TouchSkin.overlayLive = false

function TouchSkin.setOverlayLive(on)
  TouchSkin.overlayLive = on and true or false
end

function TouchSkin.decorativeOnly()
  local page = TouchSkin.page()
  if not page then return false end
  for _, ctl in ipairs(page.controls) do
    if not ctl.decorative then return false end
  end
  return true
end

function TouchSkin.drawable()
  if not TouchSkin.active then return false end
  return TouchSkin.overlayLive or TouchSkin.decorativeOnly()
end

function TouchSkin.hasViewport()
  local page = TouchSkin.page()
  if not page or not TouchSkin.drawable() then return false end
  return page.viewport ~= nil or page.screenFit == "remainder"
end

-- Largest strip of (ox,oy,w,h) that does not overlap the overlay box.
local function remainderBox(ox, oy, w, h, bx, by, bw, bh)
  local right, bottom = ox + w, oy + h
  local cand = {
    { ox, oy, w, by - oy },
    { ox, by + bh, w, bottom - (by + bh) },
    { ox, oy, bx - ox, h },
    { bx + bw, oy, right - (bx + bw), h },
  }
  local best, bestArea
  for _, r in ipairs(cand) do
    if r[3] > 1 and r[4] > 1 then
      local area = r[3] * r[4]
      if not best or area > bestArea then
        best, bestArea = r, area
      end
    end
  end
  if not best then return nil end
  return best[1], best[2], best[3], best[4]
end

function TouchSkin.pageViewport(page, w, h, ox, oy)
  if not page then return nil end
  ox, oy = ox or 0, oy or 0
  local bx, by, bw, bh = TouchSkin.pageBox(page, w, h, ox, oy)
  if page.viewport then
    local v = page.viewport
    local x, y = bx + v.x * bw, by + v.y * bh
    local vw, vh = v.w * bw, v.h * bh
    if vw <= 0 or vh <= 0 then return nil end
    return x, y, vw, vh, page.viewportFill == true, page.viewportExpand == true
  end
  if page.screenFit == "remainder" then
    local x, y, vw, vh = remainderBox(ox, oy, w, h, bx, by, bw, bh)
    if not x then return nil end
    return x, y, vw, vh, false, false
  end
  return nil
end

function TouchSkin.viewport(w, h, ox, oy)
  local page = TouchSkin.page()
  if not page or not TouchSkin.drawable() then return nil end
  return TouchSkin.pageViewport(page, w, h, ox, oy)
end

return TouchSkin
