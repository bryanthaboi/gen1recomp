local Gpu = {}

local bit = require("bit")
local band = bit.band

Gpu.W, Gpu.H = 240, 160

Gpu.BG0, Gpu.BG1, Gpu.BG2, Gpu.BG3, Gpu.OBJ = 1, 2, 4, 8, 16
Gpu.CLR = 32
Gpu.BD = 32
Gpu.BG_ALL = 15
Gpu.ALL = 63

Gpu.NONE, Gpu.BLEND, Gpu.LIGHTEN, Gpu.DARKEN = 0, 1, 2, 3

function Gpu.new()
  return {
    tgt1 = 0, tgt2 = 0, effect = Gpu.NONE, bldy = 0, eva = 0, evb = 0,
    winin0 = 0, winin1 = 0, winout = 0,
    win0 = { 0, 0, 0, 0 }, win1 = { 0, 0, 0, 0 },
    win0on = false, win1on = false,
  }
end

-- src/region_map.c:3711 ResetGpuRegs
function Gpu.reset(g)
  g.tgt1, g.tgt2, g.effect = 0, 0, Gpu.NONE
  g.bldy = 0
  g.win0 = { 0, 0, 0, 0 }
  g.win1 = { 0, 0, 0, 0 }
  g.winin0, g.winin1 = 0, 0
  g.win0on, g.win1on = false, false
end

-- src/region_map.c:3723 SetBldCnt
function Gpu.setBldCnt(g, tgt2, tgt1, effect)
  g.tgt2, g.tgt1, g.effect = tgt2, tgt1, effect
end

-- src/region_map.c:3731 SetBldY
function Gpu.setBldY(g, y)
  g.bldy = y
end

-- src/region_map.c:3736 SetBldAlpha
function Gpu.setBldAlpha(g, evb, eva)
  g.evb, g.eva = evb, eva
end

-- src/region_map.c:3743 SetWinIn
function Gpu.setWinIn(g, win0, win1)
  g.winin0, g.winin1 = win0, win1
end

-- src/region_map.c:3750 SetWinOut
function Gpu.setWinOut(g, mask)
  g.winout = mask
end

-- src/region_map.c:3755 SetDispCnt
function Gpu.setDispCnt(g, idx, clear)
  if idx == 0 then g.win0on = not clear else g.win1on = not clear end
end

-- src/region_map.c:3770 SetGpuWindowDims
function Gpu.setWindowDims(g, idx, l, t, r, b)
  local dims = { l, t, r, b }
  if idx == 0 then g.win0 = dims else g.win1 = dims end
end

-- src/region_map.c:3670 SaveRegionMapGpuRegs
function Gpu.save(g)
  return {
    tgt1 = g.tgt1, tgt2 = g.tgt2, effect = g.effect, bldy = g.bldy, eva = g.eva, evb = g.evb,
    winin0 = g.winin0, winin1 = g.winin1, winout = g.winout,
    win0 = { unpack(g.win0) }, win1 = { unpack(g.win1) },
  }
end

-- src/region_map.c:3687 SetRegionMapGpuRegs
function Gpu.restore(g, saved)
  for k, v in pairs(saved) do g[k] = v end
end

local function rectOf(dims)
  local l, t, r, b = dims[1], dims[2], dims[3], dims[4]
  if r > Gpu.W or l > r then r = Gpu.W end
  if b > Gpu.H or t > b then b = Gpu.H end
  if r <= l or b <= t then return nil end
  return { l, t, r, b }
end

local function subtract(rects, cut)
  local out = {}
  for _, r in ipairs(rects) do
    local l, t, rr, b = r[1], r[2], r[3], r[4]
    local cl, ct, cr, cb = math.max(l, cut[1]), math.max(t, cut[2]), math.min(rr, cut[3]), math.min(b, cut[4])
    if cl >= cr or ct >= cb then
      out[#out + 1] = r
    else
      if t < ct then out[#out + 1] = { l, t, rr, ct } end
      if cb < b then out[#out + 1] = { l, cb, rr, b } end
      if l < cl then out[#out + 1] = { l, ct, cl, cb } end
      if cr < rr then out[#out + 1] = { cr, ct, rr, cb } end
    end
  end
  return out
end

function Gpu.regions(g)
  local full = { 0, 0, Gpu.W, Gpu.H }
  if not g.win0on and not g.win1on then
    return { { rects = { full }, mask = Gpu.ALL } }
  end
  local out, covered = {}, {}
  if g.win0on then
    local r = rectOf(g.win0)
    if r then
      out[#out + 1] = { rects = { r }, mask = g.winin0 }
      covered[#covered + 1] = r
    end
  end
  if g.win1on then
    local r = rectOf(g.win1)
    if r then
      local rs = { r }
      for _, c in ipairs(covered) do rs = subtract(rs, c) end
      out[#out + 1] = { rects = rs, mask = g.winin1 }
      covered[#covered + 1] = r
    end
  end
  local rest = { full }
  for _, c in ipairs(covered) do rest = subtract(rest, c) end
  out[#out + 1] = { rects = rest, mask = g.winout }
  return out
end

local SHADER_SRC = [[
extern number tintOn;
extern vec3 tone;
extern number fadeY;
extern number fx;
extern number amt;
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  vec4 p = Texel(tex, tc) * color;
  vec3 c = floor(p.rgb * 31.0 + 0.5);
  if (tintOn > 0.5) {
    float gray = floor((c.r * 76.0 + c.g * 151.0 + c.b * 29.0) / 256.0);
    c = min(floor(tone * gray / 256.0), vec3(31.0));
  }
  if (fadeY > 0.0) c = c + floor((vec3(0.0) - c) * fadeY / 16.0);
  if (fx > 2.5) c = c - floor(c * amt / 16.0);
  else if (fx > 1.5) c = c + floor((vec3(31.0) - c) * amt / 16.0);
  return vec4(c / 31.0, p.a);
}
]]

local shader = nil
local function getShader()
  if not shader then shader = love.graphics.newShader(SHADER_SRC) end
  return shader
end

local function has(mask, b)
  return band(mask, b) ~= 0
end

function Gpu.compose(g, pal, layers)
  local sh = getShader()
  local sx, sy, sw, shh = love.graphics.getScissor()
  love.graphics.setShader(sh)
  local function apply(effect, fadeY, tone)
    sh:send("fadeY", fadeY)
    sh:send("fx", effect)
    sh:send("amt", math.min(g.bldy, 16))
    if tone then
      sh:send("tintOn", 1)
      sh:send("tone", tone)
    else
      sh:send("tintOn", 0)
    end
  end
  for _, region in ipairs(Gpu.regions(g)) do
    local clr = has(region.mask, Gpu.CLR)
    for _, r in ipairs(region.rects) do
      love.graphics.setScissor(r[1], r[2], r[3] - r[1], r[4] - r[2])
      local bdFx = (clr and has(g.tgt1, Gpu.BD) and g.effect ~= Gpu.BLEND) and g.effect or Gpu.NONE
      apply(bdFx, pal.bgFade)
      local bd = pal.backdrop
      love.graphics.setColor(bd[1], bd[2], bd[3], 1)
      love.graphics.rectangle("fill", 0, 0, Gpu.W, Gpu.H)
      for _, layer in ipairs(layers) do
        if has(region.mask, layer.bit) then
          local effect = (clr and has(g.tgt1, layer.bit)) and g.effect or Gpu.NONE
          local alpha = 1
          if effect == Gpu.BLEND then
            alpha = math.min(g.eva, 16) / 16
            effect = Gpu.NONE
          end
          apply(effect, layer.obj and pal.objFade or pal.bgFade, layer.tone)
          love.graphics.setColor(1, 1, 1, alpha)
          layer.draw(alpha)
        end
      end
    end
  end
  love.graphics.setShader()
  love.graphics.setColor(1, 1, 1, 1)
  if sx then love.graphics.setScissor(sx, sy, sw, shh) else love.graphics.setScissor() end
end

Gpu.images = {}

local function cacheDir()
  local RegionExtract = require("src.import.gba.region_map_extract")
  return require("src.import.gba.extract_island1").CACHE_ROOT .. "/" .. RegionExtract.CACHE_SUB .. "/"
end

local function readCache(rel)
  local Dataset = require("src.core.game3.dataset")
  return assert(Dataset.cache():read(rel), rel .. " is not in the cache")
end

function Gpu.image(name)
  local img = Gpu.images[name]
  if img then return img end
  local rel = cacheDir() .. name .. ".png"
  local fd = love.filesystem.newFileData(readCache(rel), name .. ".png")
  img = love.graphics.newImage(love.image.newImageData(fd))
  img:setFilter("nearest", "nearest")
  Gpu.images[name] = img
  return img
end

local quads = {}
function Gpu.frameQuad(name, frame, w, h)
  local key = name .. ":" .. frame
  local q = quads[key]
  if not q then
    local img = Gpu.image(name)
    q = love.graphics.newQuad(0, frame * h, w, h, img:getWidth(), img:getHeight())
    quads[key] = q
  end
  return q
end

local manifest = nil
function Gpu.manifest()
  if not manifest then
    local rel = cacheDir() .. "manifest.lua"
    manifest = assert(load(readCache(rel), "@" .. rel, "t", {}))()
  end
  return manifest
end

function Gpu.rgb(c)
  local r5, g5, b5 = c % 32, math.floor(c / 32) % 32, math.floor(c / 1024) % 32
  return { math.floor(r5 * 255 / 31 + 0.5) / 255, math.floor(g5 * 255 / 31 + 0.5) / 255,
    math.floor(b5 * 255 / 31 + 0.5) / 255, 1 }
end

function Gpu.topBarColor(i)
  return Gpu.rgb(Gpu.manifest().topBarPal[i])
end

return Gpu
