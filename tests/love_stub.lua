-- Minimal love API stub so game logic can run headless under plain Lua
-- (lua5.4 tests/run_tests.lua).  Graphics calls are no-ops that record
-- enough state for assertions.

local stub = {}

local function noop() end

local Image = {}
Image.__index = Image
function Image:getDimensions() return self.w, self.h end
function Image:getWidth() return self.w end
function Image:getHeight() return self.h end
-- IntroMovie sets the studio logo filter unconditionally on load
function Image:setFilter(min, mag) self.minFilter, self.magFilter = min, mag end
function Image:getFilter() return self.minFilter or "nearest", self.magFilter or "nearest" end

-- read PNG dimensions from the file header (no decoder needed)
local function pngSize(path)
  local f = io.open(path, "rb")
  if not f then return 8, 8 end
  local header = f:read(24)
  f:close()
  if not header or #header < 24 then return 8, 8 end
  local function be32(s, i)
    local a, b, c, d = s:byte(i, i + 3)
    return ((a * 256 + b) * 256 + c) * 256 + d
  end
  return be32(header, 17), be32(header, 21)
end

local files = {} -- in-memory love.filesystem

-- Minimal graphics-state tracking so push("all")/pop actually save and
-- restore, and getShader/getCanvas/etc can be read back.  The render-pipeline
-- fold fences each mod callback between push("all")/pop so a callback that
-- dirties state cannot leak into the engine composite; mod_render_tests
-- asserts exactly that, which needs the stub to model the save/restore rather
-- than no-op it.  Plain push()/pop() (the tilt upright pass) ride the same
-- stack and restore the same fields, which for those call sites is a no-op.
local gstate = { shader = nil, canvas = nil, blend = "alpha",
                 color = { 1, 1, 1, 1 } }
local gstack = {}

stub.graphics = {
  newImage = function(pathOrData)
    local path = pathOrData
    if type(pathOrData) == "table" and pathOrData._fileData then
      path = pathOrData.name or "<filedata>"
    elseif type(pathOrData) == "table" and pathOrData.path then
      path = pathOrData.path
    end
    local w, h = 8, 8
    if type(path) == "string" then w, h = pngSize(path) end
    return setmetatable({ w = w, h = h, path = path }, Image)
  end,
  newQuad = function(x, y, w, h) return { x = x, y = y, w = w, h = h } end,
  newCanvas = function(w, h)
    local canvas = setmetatable({ w = w, h = h, setFilter = noop, released = false }, Image)
    function canvas:release() self.released = true end
    function canvas:newImageData()
      return love.image.newImageData(self.w or 8, self.h or 8)
    end
    return canvas
  end,
  newSpriteBatch = function(image, size)
    local batch = { image = image, sprites = {} }
    function batch:add(quad, x, y) table.insert(self.sprites, { quad, x, y }) end
    function batch:clear() self.sprites = {} end
    function batch:setTexture(tex) self.texture = tex end
    return batch
  end,
  draw = noop, rectangle = noop, clear = noop,
  setDefaultFilter = noop, print = noop, printf = noop,
  line = noop, circle = noop, setLineWidth = noop,
  -- Fonts: the save editor lays itself out from font metrics, so a headless
  -- draw needs measurable text.  A fixed 6px advance / 12px line is enough
  -- for the layout to be exercised (tests assert state, never pixels).
  -- newMesh / stencil stay absent on purpose: tools/save-editor/Theme.lua
  -- probes for them and falls back to flat fills, which is the path a
  -- headless run should take.
  -- Accepts both real signatures: newFont(size) and
  -- newFont(filename, size, hinting), the latter for the TTF text mode
  -- (src/render/Font.lua).  Width counts codepoints, not bytes, and CJK /
  -- kana measure double, so tests can assert the wide-glyph metrics a real
  -- pixel font (5px base, 11px double-width) exhibits without rasterizing.
  newFont = function(a, b)
    if type(a) == "string" then
      -- real LÖVE raises on a missing file; callers pcall and fall back
      local handle = io.open(a, "rb")
      if not handle then error("Could not open file " .. a) end
      handle:close()
    end
    local px = (type(a) == "number" and a) or b or 12
    local unit = math.max(1, px * 0.5)
    return {
      getWidth = function(_, text)
        text = tostring(text)
        local w, i, n = 0, 1, #text
        while i <= n do
          local byte = text:byte(i)
          local len = byte >= 0xF0 and 4 or byte >= 0xE0 and 3
                      or byte >= 0xC0 and 2 or 1
          w = w + (byte >= 0xE1 and 2 or 1) * unit  -- U+1000+: double width
          i = i + len
        end
        return w
      end,
      getHeight = function() return px end,
      getBaseline = function() return px - 2 end,
      setFilter = noop,
    }
  end,
  setFont = function(f) gstate.font = f end,
  getFont = function() return gstate.font end,
  setColor = function(r, g, b, a) gstate.color = { r, g, b, a } end,
  getColor = function()
    local c = gstate.color
    return c[1], c[2], c[3], c[4]
  end,
  setCanvas = function(c) gstate.canvas = c or nil end,
  getCanvas = function() return gstate.canvas end,
  setShader = function(s) gstate.shader = s or nil end,
  getShader = function() return gstate.shader end,
  setBlendMode = function(m) gstate.blend = m or "alpha" end,
  getBlendMode = function() return gstate.blend end,
  -- coordinate-transform + state stack used by the tilt-mode upright pass
  -- (billboards) and the render-pipeline fold; push snapshots the tracked
  -- state, pop restores it (tests that need to observe the transforms swap
  -- in their own recorders, e.g. tests/parity_tilt.lua)
  push = function()
    gstack[#gstack + 1] = { shader = gstate.shader, canvas = gstate.canvas,
                            blend = gstate.blend, color = gstate.color }
  end,
  pop = function()
    local s = gstack[#gstack]
    if s then
      gstack[#gstack] = nil
      gstate.shader, gstate.canvas = s.shader, s.canvas
      gstate.blend, gstate.color = s.blend, s.color
    end
  end,
  translate = noop, scale = noop,
  rotate = noop, origin = noop, setScissor = noop,
  getScissor = function() return nil end,
  getDimensions = function() return 640, 576 end,
  -- dpi=1 desktop default; issue #87 tests override these for Android density
  getPixelDimensions = function() return 640, 576 end,
  getDPIScale = function() return 1 end,
}

stub.math = {
  random = function(a, b)
    if a == nil then return math.random() end
    if b == nil then return math.random(a) end
    return math.random(a, b)
  end,
}

stub.filesystem = {
  write = function(name, content) files[name] = content return true end,
  remove = function(name) files[name] = nil return true end,
  newFileData = function(contents, name)
    return { _fileData = true, contents = contents, name = name or "" }
  end,
  createDirectory = function() return true end,
  -- Record mounts for CacheFs.mountVersion tests (NX Blue/Yellow overlay).
  _mounts = {},
  mount = function(archive, mountpoint, appendToPath)
    stub.filesystem._mounts[#stub.filesystem._mounts + 1] = {
      archive = archive, mountpoint = mountpoint or "",
      append = appendToPath and true or false,
    }
    return true
  end,
  unmount = function(archive)
    local mounts = stub.filesystem._mounts
    for i = #mounts, 1, -1 do
      if mounts[i].archive == archive then
        table.remove(mounts, i)
        return true
      end
    end
    return false
  end,
  getSaveDirectory = function() return "/tmp/pokeport-stub-save" end,
  isFused = function() return false end,
}

-- Resolve a PhysFS path through recorded mounts (prepend first, newest wins).
local function resolveViaMounts(name)
  local mounts = stub.filesystem._mounts
  for i = #mounts, 1, -1 do
    local m = mounts[i]
    if not m.append then
      local mp = m.mountpoint or ""
      local key
      if mp == "" then
        key = m.archive .. "/" .. name
      elseif name == mp then
        key = m.archive
      elseif name:sub(1, #mp + 1) == mp .. "/" then
        local rel = name:sub(#mp + 2)
        key = m.archive .. "/" .. rel
      end
      if key then
        if files[key] then return key, "file" end
        local prefix = key .. "/"
        for k in pairs(files) do
          if k:sub(1, #prefix) == prefix then return key, "directory" end
        end
      end
    end
  end
  return nil
end

function stub.filesystem.read(name)
  if files[name] then return files[name] end
  local key = resolveViaMounts(name)
  if key and files[key] then return files[key] end
  return nil
end

function stub.filesystem.getInfo(name, filter)
  if files[name] then
    if filter and filter ~= "file" then return nil end
    return { type = "file" }
  end
  local prefix = name .. "/"
  for key in pairs(files) do
    if key:sub(1, #prefix) == prefix then
      if filter and filter ~= "directory" then return nil end
      return { type = "directory" }
    end
  end
  local key, kind = resolveViaMounts(name)
  if key and kind then
    if filter and filter ~= kind then return nil end
    return { type = kind }
  end
  return nil
end

stub.filesystem.load = function(name)
  local data = stub.filesystem.read(name)
  if not data then return nil, "no file" end
  return load(data, name)
end

stub.filesystem.getDirectoryItems = function(name)
  local seen, items = {}, {}
  name = name or ""
  local function addChild(child)
    if child and not seen[child] then
      seen[child] = true
      items[#items + 1] = child
    end
  end
  -- "" / "/" = save-dir root (RomImporter Android ROM scan)
  if name == "" or name == "/" then
    for key in pairs(files) do
      addChild(key:match("^[^/]+"))
    end
  else
    local prefix = name .. "/"
    for key in pairs(files) do
      if key:sub(1, #prefix) == prefix then
        addChild(key:sub(#prefix + 1):match("^[^/]+"))
      end
    end
    -- Also surface children exposed via mounts.
    local key = resolveViaMounts(name)
    if key then
      local mprefix = key .. "/"
      for k in pairs(files) do
        if k:sub(1, #mprefix) == mprefix then
          addChild(k:sub(#mprefix + 1):match("^[^/]+"))
        end
      end
    end
  end
  table.sort(items)
  return items
end

-- table-backed SoundData so ChipAudio's offline render seam
-- (_renderMusicForTest) runs headless; modkit bounce writes WAVs from it
local SoundData = {}
SoundData.__index = SoundData
local function slot(self, index, channel)
  return index * self.channels + (channel - 1) + 1
end
function SoundData:setSample(index, a, b)
  if b == nil then
    self.data[slot(self, index, 1)] = a
  else
    self.data[slot(self, index, a)] = b
  end
end
function SoundData:getSample(index, channel)
  return self.data[slot(self, index, channel or 1)] or 0
end
function SoundData:getSampleCount() return self.samples end
function SoundData:getSampleRate() return self.rate end
function SoundData:getBitDepth() return self.bits end
function SoundData:getChannelCount() return self.channels end
function SoundData:getDuration() return self.samples / self.rate end

stub.sound = {
  newSoundData = function(samples, rate, bits, channels)
    -- Path form (love.sound.newSoundData(filename)): only succeed when the
    -- stub FS has the file, matching real LÖVE.  Synthesize a short mono
    -- 8-bit buffer so Sound.widenMono can run headless for seeded paths
    -- (pika cries); missing files must error so widenMono keeps the
    -- original Source (give_item_jingle identity checks, etc.).
    if type(samples) == "string" then
      if not stub.filesystem.getInfo(samples) then
        error("Could not open file " .. samples .. ". Does not exist.")
      end
      local n = 32
      local sd = setmetatable({
        samples = n, rate = rate or 22050, bits = bits or 8,
        channels = channels or 1, data = {}, path = samples,
      }, SoundData)
      for i = 0, n - 1 do
        sd:setSample(i, (i % 2 == 0) and 0.5 or -0.5)
      end
      return sd
    end
    return setmetatable({ samples = samples, rate = rate or 44100,
      bits = bits or 16, channels = channels or 1, data = {} }, SoundData)
  end,
}

stub.keyboard = { isDown = function() return false end }

stub.mouse = {
  getPosition = function() return 0, 0 end,
  isCursorSupported = function() return false end,
  getSystemCursor = function(name) return name end,
  setCursor = function() end,
}

stub.timer = { getTime = function() return 0 end }

-- Minimal image module so Assets.imageData can decode FileData fallbacks
-- headless (full pixel stubs live in tests/mod_graphics_tests.lua).
local ImageData = {}
ImageData.__index = ImageData
function ImageData:getWidth() return self.w end
function ImageData:getHeight() return self.h end
function ImageData:getDimensions() return self.w, self.h end
function ImageData:getPixel() return 0, 0, 0, 1 end
function ImageData:setPixel() end
function ImageData:mapPixel() end
function ImageData:paste() end
function ImageData:encode(format, filename)
  local bytes = "\137PNG\r\n\26\n"
  if type(filename) == "string" and love.filesystem and love.filesystem.write then
    love.filesystem.write(filename, bytes)
  end
  return { getString = function() return bytes end }
end

stub.image = {
  newImageData = function(a, b)
    if type(a) == "table" and a._fileData then
      return setmetatable({ w = 8, h = 8, path = a.name, source = a }, ImageData)
    end
    if type(a) == "string" then
      return setmetatable({ w = 8, h = 8, path = a }, ImageData)
    end
    return setmetatable({ w = a or 8, h = b or 8 }, ImageData)
  end,
}

-- Headless runs report the desktop OS so platform gates (GamepadMap's NX
-- check, the touch-overlay filter) take their desktop branch.
stub.system = {
  getOS = function() return "OS X" end,
}

-- Desktop / headless: full-window safe area (matches LÖVE's fallback).
stub.window = {
  getSafeArea = function()
    local ww, wh = stub.graphics.getDimensions()
    return 0, 0, ww, wh
  end,
}

return stub
