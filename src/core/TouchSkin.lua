local TouchSkin = {}

TouchSkin.BUNDLED_ROOT = "assets/skins"
TouchSkin.USER_ROOT = "skins"

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
  }
  if ctl.imagePath == "" then ctl.imagePath = nil end
  if ctl.pressedImagePath == "" then ctl.pressedImagePath = nil end
  return ctl
end

function TouchSkin.parse(text)
  local kv = TouchSkin.parseConfig(text)
  local count = math.floor(num(kv.overlays, 0))
  if count <= 0 then return nil, "no overlays" end

  local pages = {}
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

    local descs = math.floor(num(kv[p .. "_descs"], 0))
    for d = 0, descs - 1 do
      local ctl = parseDesc(kv, p .. "_desc" .. d, page)
      if ctl then page.controls[#page.controls + 1] = ctl end
    end
    pages[#pages + 1] = page
  end

  -- RetroArch auto-rotate: overlay names containing portrait / landscape
  -- are the lock.  Stamp it so the studio does not need a second click.  #1503
  for _, page in ipairs(pages) do
    if not page.orient then page.orient = TouchSkin.pageOrient(page) end
  end

  return { pages = pages }
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

local function findConfig(root)
  if readFile(root .. "/" .. TouchSkin.NATIVE_NAME) then
    return root .. "/" .. TouchSkin.NATIVE_NAME, "native"
  end
  local named = { "overlay.cfg", "skin.cfg", "layout.cfg" }
  for _, name in ipairs(named) do
    if readFile(root .. "/" .. name) then return root .. "/" .. name, "retroarch" end
  end
  local items = listDir(root)
  table.sort(items)
  for _, name in ipairs(items) do
    if name:match("%.cfg$") then return root .. "/" .. name, "retroarch" end
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
      rangeMod = num(raw.rangeMod, 1),
      alphaMod = num(raw.alphaMod, 1),
      aspect = num(raw.aspect, DEFAULT_ASPECT),
      aspectFromCfg = raw.fitAspect == true,
      orient = (raw.orient == "portrait" or raw.orient == "landscape"
                or raw.orient == "any") and raw.orient or nil,
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
      page.controls[#page.controls + 1] = {
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

function TouchSkin.load(root, id)
  local cfgPath, format = findConfig(root)
  if not cfgPath then return nil, "no skin.lua or .cfg in " .. root end
  local text = readFile(cfgPath)
  if not text then return nil, "unreadable " .. cfgPath end
  local skin, err
  if format == "native" then
    skin, err = TouchSkin.parseNative(text)
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

function TouchSkin.list()
  local out, seen = {}, {}
  local function scan(root, source)
    for _, name in ipairs(listDir(root)) do
      local id = name:gsub("%.zip$", "")
      if not seen[id] then
        local path = root .. "/" .. name
        if name:match("%.zip$") then
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

-- Drop a .zip into <save>/skins and report the id it will list under.
function TouchSkin.installArchive(name, data)
  if not data or data == "" then return nil, "empty archive" end
  if not (love and love.filesystem and love.filesystem.write) then
    return nil, "no writable filesystem"
  end
  name = tostring(name or ""):match("([^/\\]+)$") or ""
  name = name:gsub("[^%w%._%-]", "_")
  if not name:lower():match("%.zip$") then return nil, "not a .zip" end
  local id = name:gsub("%.[Zz][Ii][Pp]$", "")
  if id == "" then return nil, "bad archive name" end

  pcall(love.filesystem.createDirectory, TouchSkin.USER_ROOT)
  local dest = TouchSkin.USER_ROOT .. "/" .. name
  local ok, err = love.filesystem.write(dest, data)
  if not ok then return nil, tostring(err) end

  local entry = TouchSkin.find(id)
  if not entry then
    love.filesystem.remove(dest)
    return nil, "no skin.lua or .cfg inside " .. name
  end
  return id
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

function TouchSkin.export(skin, destPath)
  if not skin then return nil, "no skin" end
  local SkinZip = require("src.core.SkinZip")
  local entries = { { name = TouchSkin.NATIVE_NAME, data = TouchSkin.serialize(skin) } }
  local missing = {}
  for _, rel in ipairs(TouchSkin.assetPaths(skin)) do
    local data = readFile(joinPath(skin.root, rel))
    if data then
      entries[#entries + 1] = { name = rel, data = data }
    else
      missing[#missing + 1] = rel
    end
  end
  if skin.configPath and skin.format == "retroarch" then
    local cfg = readFile(skin.configPath)
    if cfg then
      entries[#entries + 1] =
        { name = skin.configPath:match("([^/]+)$") or "overlay.cfg", data = cfg }
    end
  end
  local blob = SkinZip.encode(entries)
  destPath = destPath or (TouchSkin.USER_ROOT .. "/" .. skin.id .. "-export.zip")
  local absolute = destPath:sub(1, 1) == "/" or destPath:match("^%a:[/\\]") ~= nil
  if not absolute and love and love.filesystem and love.filesystem.write then
    local ok, err = love.filesystem.write(destPath, blob)
    if not ok then return nil, tostring(err) end
  else
    local handle = io.open(destPath, "wb")
    if not handle then return nil, "cannot write " .. destPath end
    handle:write(blob)
    handle:close()
  end
  return destPath, missing
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
      if name:lower():match("%.png$") or name:lower():match("%.jpg$") then
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
    if displayAspect > page.aspect then
      bw = h * page.aspect
      bx = ox + (w - bw) * 0.5
    else
      bh = w / page.aspect
      by = oy + (h - bh) * 0.5
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

function TouchSkin.hits(page, ctl, w, h, px, py, ox, oy)
  local cx, cy, halfW, halfH = TouchSkin.controlGeometry(page, ctl, w, h, ox, oy)
  local left = halfW * ctl.reachLeft * ctl.rangeMod
  local right = halfW * ctl.reachRight * ctl.rangeMod
  local up = halfH * ctl.reachUp * ctl.rangeMod
  local down = halfH * ctl.reachDown * ctl.rangeMod
  local dx = px - cx
  local dy = py - cy
  local rx = dx < 0 and left or right
  local ry = dy < 0 and up or down
  if rx <= 0 or ry <= 0 then return false end
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
  return page ~= nil and page.viewport ~= nil and TouchSkin.drawable()
end

function TouchSkin.viewport(w, h, ox, oy)
  local page = TouchSkin.page()
  if not page or not page.viewport or not TouchSkin.drawable() then return nil end
  local v = page.viewport
  local bx, by, bw, bh = TouchSkin.pageBox(page, w, h, ox, oy)
  local x, y = bx + v.x * bw, by + v.y * bh
  local vw, vh = v.w * bw, v.h * bh
  if vw <= 0 or vh <= 0 then return nil end
  return x, y, vw, vh, page.viewportFill == true, page.viewportExpand == true
end

return TouchSkin
