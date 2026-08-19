local Json = require("src.link.Json")
local TouchSkin = require("src.core.TouchSkin")

local DeltaSkin = {}

DeltaSkin.INFO_NAME = "info.json"
DeltaSkin.MAX_INFO_BYTES = 4 * 1024 * 1024

DeltaSkin.GAME_TYPE_PREFIXES = {
  "com.rileytestut.delta.game.",
  "public.aoshuang.game.",
}

DeltaSkin.SYSTEMS = { gb = true, gbc = true }

DeltaSkin.LEGACY_EXTS = { gbcskin = true, gbaskin = true, gbskin = true }

DeltaSkin.DEVICE_ORDER = { "iphone", "ipad", "tv" }
DeltaSkin.DISPLAY_ORDER = { "edgeToEdge", "standard", "splitView" }
DeltaSkin.ORIENTATIONS = { "portrait", "landscape" }
DeltaSkin.SIDES = { "up", "down", "left", "right" }

DeltaSkin.ASSET_LADDER = { "small", "medium", "large" }
DeltaSkin.ASSET_WIDTHS = { small = 640, medium = 750, large = 1080 }
DeltaSkin.DEFAULT_TARGET_WIDTH = 1080

DeltaSkin.INPUTS = {
  a = "a", b = "b", start = "start", select = "select",
  up = "up", down = "down", left = "left", right = "right",
  menu = "menu_toggle",
  fastforward = "hold_fast_forward",
  togglefastforward = "toggle_fast_forward",
}

DeltaSkin.OUTPUT_HOTKEYS = {
  menu = "menu",
  fast_forward_hold = "fastForward",
  fast_forward_toggle = "toggleFastForward",
}

DeltaSkin.MAPPING = {
  portrait = { width = 1080, height = 1920 },
  landscape = { width = 1920, height = 1080 },
}

DeltaSkin.SCREEN_WIDTH = 160
DeltaSkin.SCREEN_HEIGHT = 144

local function pick(t, key)
  if type(t) ~= "table" then return nil end
  local direct = t[key]
  if direct ~= nil then return direct end
  local want = tostring(key):lower()
  for k, v in pairs(t) do
    if tostring(k):lower() == want then return v end
  end
  return nil
end

local function numOr(v, fallback)
  local n = tonumber(v)
  if not n or n ~= n then return fallback end
  return n
end

local function round(n)
  return math.floor(numOr(n, 0) + 0.5)
end

local function isArray(t)
  return type(t) == "table" and t[1] ~= nil
end

local function addWarning(list, text)
  if type(list) ~= "table" then return end
  for _, existing in ipairs(list) do
    if existing == text then return end
  end
  list[#list + 1] = text
end

function DeltaSkin.findInfo(root)
  local direct = root .. "/" .. DeltaSkin.INFO_NAME
  if TouchSkin.readFile(direct) then return direct, "" end
  local items = TouchSkin.listDir(root)
  for _, name in ipairs(items) do
    if tostring(name):lower() == DeltaSkin.INFO_NAME then
      return root .. "/" .. name, ""
    end
  end
  table.sort(items)
  for _, name in ipairs(items) do
    local nested = root .. "/" .. name .. "/" .. DeltaSkin.INFO_NAME
    if TouchSkin.readFile(nested) then return nested, name .. "/" end
  end
  return nil
end

function DeltaSkin.resolveName(name, opts)
  name = tostring(name or ""):gsub("\\", "/"):gsub("^%./", "")
  if name == "" then return nil end
  local names = opts and opts.names
  if type(names) == "table" then
    local want = name:lower()
    for _, entry in ipairs(names) do
      if tostring(entry):lower() == want then
        name = tostring(entry)
        break
      end
    end
  end
  return ((opts and opts.prefix) or "") .. name
end

function DeltaSkin.pickAsset(assets, opts, pdfFiles)
  if type(assets) ~= "table" then return nil end
  pdfFiles = pdfFiles or {}
  local raster = {}
  local pdfName
  for _, key in ipairs(DeltaSkin.ASSET_LADDER) do
    local name = pick(assets, key)
    if key == "medium" and type(name) ~= "string" then name = pick(assets, "normal") end
    if type(name) == "string" and name ~= "" then
      if name:lower():match("%.pdf$") then
        pdfName = name
        pdfFiles[#pdfFiles + 1] = name
      else
        raster[#raster + 1] = { key = key, name = name }
      end
    end
  end
  local resizable = pick(assets, "resizable")
  if type(resizable) == "string" and resizable ~= "" then
    if resizable:lower():match("%.pdf$") then
      pdfName = resizable
      pdfFiles[#pdfFiles + 1] = resizable
    else
      raster[#raster + 1] = { key = "large", name = resizable }
    end
  end
  local pdfPath = pdfName and DeltaSkin.resolveName(pdfName, opts) or nil
  if #raster == 0 then return nil, pdfPath end

  local target = numOr(opts and opts.targetWidth, DeltaSkin.DEFAULT_TARGET_WIDTH)
  local chosen
  for _, cand in ipairs(raster) do
    if not chosen and (DeltaSkin.ASSET_WIDTHS[cand.key] or 0) >= target then
      chosen = cand.name
    end
  end
  if not chosen then chosen = raster[#raster].name end
  return DeltaSkin.resolveName(chosen, opts), nil
end

function DeltaSkin.mergeEdges(base, item)
  local out = { top = 0, bottom = 0, left = 0, right = 0 }
  for _, side in ipairs({ "top", "bottom", "left", "right" }) do
    local v = pick(item, side)
    if v == nil then v = pick(base, side) end
    out[side] = numOr(v, 0)
  end
  return out
end

function DeltaSkin.representation(reps, orient)
  for _, device in ipairs(DeltaSkin.DEVICE_ORDER) do
    local dev = pick(reps, device)
    if type(dev) == "table" then
      for _, display in ipairs(DeltaSkin.DISPLAY_ORDER) do
        local shown = pick(dev, display)
        if type(shown) == "table" then
          local obj = pick(shown, orient)
          if type(obj) == "table" then return obj, device, display end
        end
      end
      local flat = pick(dev, orient)
      if type(flat) == "table" and (pick(flat, "items") or pick(flat, "mappingSize")) then
        return flat, device, nil
      end
    end
  end
  return nil
end

function DeltaSkin.directionalInputs(inputs)
  if type(inputs) ~= "table" or isArray(inputs) then return nil end
  local out, found = {}, 0
  for _, side in ipairs(DeltaSkin.SIDES) do
    local v = pick(inputs, side)
    if type(v) == "string" then
      local lower = v:lower()
      local mapped = DeltaSkin.INPUTS[lower]
      if not mapped and lower:find(side, 1, true) then mapped = side end
      if mapped then
        out[side] = mapped
        found = found + 1
      end
    end
  end
  if found >= 2 then return out end
  return nil
end

function DeltaSkin.specFor(inputs)
  local parts = {}
  local function add(v)
    if type(v) ~= "string" then return end
    local mapped = DeltaSkin.INPUTS[v:lower()]
    if mapped then parts[#parts + 1] = mapped end
  end
  if type(inputs) == "string" then
    add(inputs)
  elseif type(inputs) == "table" then
    if isArray(inputs) then
      for _, v in ipairs(inputs) do add(v) end
    else
      local keys = {}
      for k in pairs(inputs) do keys[#keys + 1] = tostring(k) end
      table.sort(keys)
      for _, k in ipairs(keys) do add(inputs[k]) end
    end
  end
  if #parts == 0 then return "nul" end
  return table.concat(parts, "|")
end

function DeltaSkin.screenRect(obj, mapW, mapH)
  local frame
  local screens = pick(obj, "screens")
  if type(screens) == "table" and type(screens[1]) == "table" then
    frame = pick(screens[1], "outputFrame")
  end
  if type(frame) ~= "table" then frame = pick(obj, "gameScreenFrame") end
  if type(frame) ~= "table" then return nil end
  local w = numOr(pick(frame, "width"), 0)
  local h = numOr(pick(frame, "height"), 0)
  if w <= 0 or h <= 0 then return nil end
  return {
    x = numOr(pick(frame, "x"), 0) / mapW,
    y = numOr(pick(frame, "y"), 0) / mapH,
    w = w / mapW, h = h / mapH,
  }
end

function DeltaSkin.addItem(page, item, baseEdges, mapW, mapH)
  if type(item) ~= "table" then return end
  local frame = pick(item, "frame")
  if type(frame) ~= "table" then return end
  local fw = numOr(pick(frame, "width"), 0)
  local fh = numOr(pick(frame, "height"), 0)
  if fw <= 0 or fh <= 0 then return end
  local fx = numOr(pick(frame, "x"), 0)
  local fy = numOr(pick(frame, "y"), 0)

  local edges = DeltaSkin.mergeEdges(baseEdges, pick(item, "extendedEdges"))
  local cx, cy = (fx + fw * 0.5) / mapW, (fy + fh * 0.5) / mapH
  local w, h = fw / mapW, fh / mapH
  local reachLeft = 1 + edges.left / (fw * 0.5)
  local reachRight = 1 + edges.right / (fw * 0.5)
  local reachUp = 1 + edges.top / (fh * 0.5)
  local reachDown = 1 + edges.bottom / (fh * 0.5)

  local inputs = pick(item, "inputs")
  local dirs = DeltaSkin.directionalInputs(inputs)
  if dirs then
    local base = {
      x = cx, y = cy, rangeX = w * 0.5, rangeY = h * 0.5,
      rangeMod = 1, alphaMod = page.alphaMod, shape = "rect",
      reachLeft = reachLeft, reachRight = reachRight,
      reachUp = reachUp, reachDown = reachDown,
    }
    for _, ctl in ipairs(TouchSkin.expandDirectional(base, dirs)) do
      page.controls[#page.controls + 1] = ctl
    end
    return
  end

  local shape = tostring(pick(item, "mask") or ""):lower() == "circle" and "radial" or "rect"
  local ctl = TouchSkin.newControl(DeltaSkin.specFor(inputs), cx, cy, w, h, shape)
  ctl.alphaMod = page.alphaMod
  ctl.reachLeft, ctl.reachRight = reachLeft, reachRight
  ctl.reachUp, ctl.reachDown = reachUp, reachDown
  page.controls[#page.controls + 1] = ctl
end

function DeltaSkin.buildPage(obj, orient, opts, warnings, pdfFiles)
  local mapping = pick(obj, "mappingSize")
  local mapW = numOr(pick(mapping, "width"), 0)
  local mapH = numOr(pick(mapping, "height"), 0)
  if mapW <= 0 or mapH <= 0 then
    mapW, mapH = 320, 240
    addWarning(warnings, orient .. " has no mappingSize; assuming 320x240")
  end

  local imagePath, pdfPath = DeltaSkin.pickAsset(pick(obj, "assets"), opts, pdfFiles)
  local page = {
    name = orient,
    orient = orient,
    imagePath = imagePath,
    pdfPath = pdfPath,
    fullScreen = true,
    normalized = true,
    pixelCoords = false,
    rangeMod = 1,
    alphaMod = pick(obj, "translucent") == true and 0.7 or 1,
    aspect = mapW / mapH,
    aspectFromCfg = false,
    rect = { x = 0, y = 0, w = 1, h = 1 },
    mappingWidth = mapW,
    mappingHeight = mapH,
    controls = {},
  }

  local screen = DeltaSkin.screenRect(obj, mapW, mapH)
  if screen then
    page.viewport = screen
    page.viewportFill = false
  else
    -- mappingSize is the overlay, not the device.  Portrait controller
    -- skins (GBA4iOS-era 320x240 decks, this Pikachu skin, etc.) keep
    -- that aspect, sit at the bottom, and leave the leftover for the
    -- Game Boy picture.  A screens/gameScreenFrame rect still fills.
    page.aspectFromCfg = true
    page.screenFit = "remainder"
    if orient == "portrait" then page.anchor = "bottom" end
  end

  local baseEdges = pick(obj, "extendedEdges")
  local items = pick(obj, "items")
  if type(items) == "table" then
    for _, item in ipairs(items) do
      DeltaSkin.addItem(page, item, baseEdges, mapW, mapH)
    end
  end
  return page
end

function DeltaSkin.systemOf(gameType)
  if type(gameType) ~= "string" or gameType == "" then return nil end
  for _, prefix in ipairs(DeltaSkin.GAME_TYPE_PREFIXES) do
    if gameType:sub(1, #prefix) == prefix then
      return gameType:sub(#prefix + 1):lower()
    end
  end
  return nil
end

function DeltaSkin.parse(text, opts)
  opts = opts or {}
  local info, err = Json.decode(tostring(text or ""), DeltaSkin.MAX_INFO_BYTES)
  if type(info) ~= "table" then
    return nil, "info.json does not parse: " .. tostring(err)
  end

  local gameType = info.gameTypeIdentifier
  if type(gameType) ~= "string" or gameType == "" then
    return nil, "old GBA4iOS skin, not supported: info.json has no gameTypeIdentifier"
  end
  if gameType:lower():find("gba4ios", 1, true) then
    return nil, "old GBA4iOS skin, not supported"
  end
  local system = DeltaSkin.systemOf(gameType)
  if not system then
    return nil, "not a Delta skin: unknown gameTypeIdentifier " .. gameType
  end

  local warnings = {}
  if not DeltaSkin.SYSTEMS[system] then
    addWarning(warnings, "this skin is for " .. system .. ", not Game Boy")
  end

  local reps = info.representations
  if type(reps) ~= "table" then return nil, "info.json has no representations" end

  local pdfFiles, pages = {}, {}
  for _, orient in ipairs(DeltaSkin.ORIENTATIONS) do
    local obj = DeltaSkin.representation(reps, orient)
    if obj then
      local page = DeltaSkin.buildPage(obj, orient, opts, warnings, pdfFiles)
      page.index = #pages + 1
      pages[#pages + 1] = page
    end
  end
  if #pages == 0 then return nil, "info.json has no usable representation" end

  return {
    pages = pages,
    name = info.name,
    author = info.author,
    notes = info.notes,
    format = "delta",
    system = system,
    identifier = info.identifier,
    warnings = warnings,
    pdfFiles = pdfFiles,
  }
end

function DeltaSkin.needsConversion(skin)
  if type(skin) ~= "table" then return nil end
  local files = skin.pdfFiles
  if type(files) ~= "table" or #files == 0 then return nil end
  for _, page in ipairs(skin.pages or {}) do
    -- A raster asset, or a JPEG recovered from the PDF at load, means the
    -- skin can draw.  Parse-only callers still see pdfOnly because they
    -- have not run extract yet.
    if page.rasterData then return nil end
    if page.imagePath then return nil end
  end
  return { pdfOnly = true, files = files }
end

function DeltaSkin.outputInputs(ctl)
  local out = {}
  for _, b in ipairs(ctl.buttons or {}) do out[#out + 1] = b end
  for _, h in ipairs(ctl.hotkeys or {}) do
    local mapped = DeltaSkin.OUTPUT_HOTKEYS[h]
    if mapped then out[#out + 1] = mapped end
  end
  return out
end

function DeltaSkin.buildRepresentation(page, orient, warnings)
  local map = DeltaSkin.MAPPING[orient] or DeltaSkin.MAPPING.portrait
  local mapW, mapH = map.width, map.height
  local items, files = {}, {}

  for _, ctl in ipairs(page.controls or {}) do
    local names = DeltaSkin.outputInputs(ctl)
    if ctl.sector and ctl.sector ~= 1 then
      names = {}
    elseif ctl.sector and ctl.areaNames then
      local TouchSkin = require("src.core.TouchSkin")
      local dirs = {}
      for _, side in ipairs({ "up", "down", "left", "right" }) do
        local mapped = TouchSkin.GB_BUTTONS[tostring(ctl.areaNames[side]):lower()]
        if mapped then dirs[side] = mapped end
      end
      names = next(dirs) and dirs or {}
    end
    if names.up or names.down or names.left or names.right or #names > 0 then
      local item = {
        inputs = names,
        frame = {
          x = round((ctl.x - ctl.rangeX) * mapW),
          y = round((ctl.y - ctl.rangeY) * mapH),
          width = round(ctl.rangeX * 2 * mapW),
          height = round(ctl.rangeY * 2 * mapH),
        },
      }
      if ctl.shape == "radial" then item.mask = "circle" end
      local edges, any = {}, false
      local pairsList = {
        { key = "left", reach = ctl.reachLeft, half = ctl.rangeX * mapW },
        { key = "right", reach = ctl.reachRight, half = ctl.rangeX * mapW },
        { key = "top", reach = ctl.reachUp, half = ctl.rangeY * mapH },
        { key = "bottom", reach = ctl.reachDown, half = ctl.rangeY * mapH },
      }
      for _, side in ipairs(pairsList) do
        local reach = numOr(side.reach, 1)
        if reach ~= 1 then
          edges[side.key] = round((reach - 1) * side.half)
          any = true
        end
      end
      if any then item.extendedEdges = edges end
      items[#items + 1] = item
    elseif ctl.imagePath then
      addWarning(warnings, "per-button art is dropped: Delta keeps all art in one image")
    end
  end

  local obj = {
    items = items,
    mappingSize = { width = mapW, height = mapH },
    extendedEdges = { top = 0, bottom = 0, left = 0, right = 0 },
    translucent = false,
  }
  if page.imagePath then
    obj.assets = {
      small = page.imagePath, medium = page.imagePath, large = page.imagePath,
    }
    files[#files + 1] = page.imagePath
  end
  if page.viewport then
    obj.screens = { {
      inputFrame = { x = 0, y = 0,
                     width = DeltaSkin.SCREEN_WIDTH, height = DeltaSkin.SCREEN_HEIGHT },
      outputFrame = {
        x = round(page.viewport.x * mapW), y = round(page.viewport.y * mapH),
        width = round(page.viewport.w * mapW), height = round(page.viewport.h * mapH),
      },
    } }
  end
  return obj, files
end

function DeltaSkin.build(skin, opts)
  if type(skin) ~= "table" or not skin.pages or not skin.pages[1] then
    return nil, "skin has no pages"
  end
  opts = opts or {}
  local standard, edgeToEdge = {}, {}
  local assets, warnings, used = {}, {}, {}

  for _, page in ipairs(skin.pages) do
    local orient = TouchSkin.pageOrient(page)
    if orient ~= "portrait" and orient ~= "landscape" then
      orient = (numOr(page.aspect, 1) < 1) and "portrait" or "landscape"
    end
    if not used[orient] then
      used[orient] = true
      local obj, files = DeltaSkin.buildRepresentation(page, orient, warnings)
      standard[orient] = obj
      edgeToEdge[orient] = obj
      for _, rel in ipairs(files) do assets[#assets + 1] = rel end
    end
  end

  local system = tostring(opts.system or "gbc")
  local info = {
    name = skin.name or skin.id or "skin",
    identifier = opts.identifier
      or ("com.gen1recomp.skin." .. tostring(skin.id or "skin")),
    gameTypeIdentifier = DeltaSkin.GAME_TYPE_PREFIXES[1] .. system,
    debug = false,
    representations = { iphone = { standard = standard, edgeToEdge = edgeToEdge } },
  }
  return info, assets, warnings
end

function DeltaSkin.encodeInfo(skin, opts)
  local info, assets, warnings = DeltaSkin.build(skin, opts)
  if not info then return nil, assets end
  return Json.encode(info), assets, warnings
end

return DeltaSkin
