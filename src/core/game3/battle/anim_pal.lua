local bit = require("bit")
local band, rshift, lshift, bor = bit.band, bit.rshift, bit.lshift, bit.bor
local floor = math.floor

local AnimPal = {}

AnimPal.unfaded = {}
AnimPal.faded = {}
AnimPal.loaded = {}
AnimPal.idxOf = setmetatable({}, { __mode = "k" })
AnimPal._pack = nil

local function norm(tag)
  if tag == nil then return nil end
  return (tostring(tag):upper():gsub("^ANIM_TAG_", ""))
end
AnimPal.norm = norm

function AnimPal.reset(pack)
  if pack ~= nil then AnimPal._pack = pack end
  AnimPal.unfaded = {}
  AnimPal.faded = {}
  AnimPal.loaded = {}
end

function AnimPal.setPack(pack)
  if AnimPal._pack ~= pack then
    AnimPal._pack = pack
    AnimPal.unfaded = {}
    AnimPal.faded = {}
  end
end

local function base_ints(tag)
  local pack = AnimPal._pack
  if not pack then return nil end
  local info = pack.tags and pack.tags[tag]
  local p = info and info.pal
  if not p and pack.tagPals then p = pack.tagPals[tag] end
  return p
end

local function copy0(src)
  local out = {}
  for i = 0, 15 do out[i] = src and (src[i + 1] or 0) or 0 end
  return out
end

function AnimPal.tagName(id)
  id = tonumber(id)
  if not id then return nil end
  if id < 0 then id = id + 65536 end
  local ok, Versions = pcall(require, "src.import.gba.versions")
  local names = ok and Versions and Versions.ANIM_TAG_NAMES
  return names and names[id - 10000] or nil
end

function AnimPal.hasBase(tag)
  return base_ints(norm(tag)) ~= nil
end

function AnimPal.unfadedOf(tag)
  tag = norm(tag)
  if not tag then return nil end
  local u = AnimPal.unfaded[tag]
  if u then return u end
  local b = base_ints(tag)
  if not b then return nil end
  u = copy0(b)
  AnimPal.unfaded[tag] = u
  return u
end

function AnimPal.fadedOf(tag)
  tag = norm(tag)
  if not tag then return nil end
  return AnimPal.faded[tag] or AnimPal.unfadedOf(tag)
end

function AnimPal.writeFaded(tag)
  tag = norm(tag)
  local f = AnimPal.faded[tag]
  if f then return f end
  local u = AnimPal.unfadedOf(tag)
  if not u then return nil end
  f = {}
  for i = 0, 15 do f[i] = u[i] end
  AnimPal.faded[tag] = f
  return f
end

function AnimPal.resetFaded(tag)
  AnimPal.faded[norm(tag)] = nil
end

-- pokefirered/src/sprite.c:1638
function AnimPal.markLoaded(tag, on)
  tag = norm(tag)
  if not tag then return end
  if on then
    AnimPal.loaded[tag] = true
  else
    AnimPal.loaded[tag] = nil
    AnimPal.unfaded[tag] = nil
    AnimPal.faded[tag] = nil
  end
end

function AnimPal.isLoaded(tag)
  return AnimPal.loaded[norm(tag)] == true
end

-- pokefirered/src/sprite.c:1609
function AnimPal.alloc(tag)
  tag = norm(tag)
  if not tag then return nil end
  if AnimPal.loaded[tag] and AnimPal.unfaded[tag] then return AnimPal.unfaded[tag] end
  local u = {}
  for i = 0, 15 do u[i] = 0 end
  AnimPal.unfaded[tag] = u
  AnimPal.faded[tag] = nil
  AnimPal.loaded[tag] = true
  return u
end

function AnimPal.free(tag)
  AnimPal.markLoaded(tag, false)
end

-- pokefirered/src/palette.c:88
function AnimPal.load(tag, colors, dst, count)
  tag = norm(tag)
  local u = AnimPal.unfadedOf(tag) or AnimPal.alloc(tag)
  local f = AnimPal.writeFaded(tag)
  for i = 0, count - 1 do
    local c = colors[i] or 0
    u[dst + i] = c
    f[dst + i] = c
  end
end

function AnimPal.rgb(c)
  return band(c, 31), band(rshift(c, 5), 31), band(rshift(c, 10), 31)
end

function AnimPal.pack(r, g, b)
  return bor(band(r, 31), lshift(band(g, 31), 5), lshift(band(b, 31), 10))
end

local function asr4(v)
  return floor(v / 16)
end

function AnimPal.blend5(r, g, b, coeff, tr, tg, tb)
  return r + asr4((tr - r) * coeff), g + asr4((tg - g) * coeff), b + asr4((tb - b) * coeff)
end

-- pokefirered/src/palette.c:779
function AnimPal.blendColor(c, coeff, target)
  local r, g, b = AnimPal.rgb(c)
  local tr, tg, tb = AnimPal.rgb(target)
  return AnimPal.pack(AnimPal.blend5(r, g, b, coeff, tr, tg, tb))
end

local SHADER_SRC = [[
extern vec4 pal[16];
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  vec4 t = Texel(tex, tc);
  float fi = floor(t.r * 15.0 + 0.5);
  vec4 c = vec4(0.0);
  for (int k = 0; k < 16; k++) {
    if (abs(float(k) - fi) < 0.5) { c = pal[k]; }
  }
  if (t.a < 0.5) { c = vec4(0.0); }
  return c * color;
}
]]

local shader, shaderFailed = nil, false
function AnimPal.shader()
  if shader or shaderFailed then return shader end
  if not (love and love.graphics and love.graphics.newShader) then
    shaderFailed = true
    return nil
  end
  local ok, sh = pcall(love.graphics.newShader, SHADER_SRC)
  if ok then shader = sh else shaderFailed = true print("[battle.anim] pal shader: " .. tostring(sh)) end
  return shader
end

local vecs = {}
for i = 1, 16 do vecs[i] = { 0, 0, 0, 0 } end

-- pokefirered/src/battle_anim_mons.c:1287
local function gray5(r, g, b)
  local v = floor((r + g + b) / 3)
  return v, v, v
end
AnimPal.gray5 = gray5

-- pokefirered/src/battle_anim_mons.c:1287
function AnimPal.greyscale(tag, restore)
  local u = AnimPal.unfadedOf(tag)
  local f = AnimPal.writeFaded(tag)
  if not (u and f) then return end
  for i = 0, 15 do
    if restore then
      f[i] = u[i]
    else
      local r, g, b = AnimPal.rgb(u[i])
      f[i] = AnimPal.pack(gray5(r, g, b))
    end
  end
end

function AnimPal.resolve(colors, opts, out)
  out = out or {}
  opts = opts or {}
  local coeff = tonumber(opts.coeff) or 0
  local tr, tg, tb = 0, 0, 0
  if coeff > 0 then tr, tg, tb = AnimPal.rgb(tonumber(opts.color) or 0) end
  local aff = opts.affine
  for i = 0, 15 do
    local c = colors and colors[i] or 0
    local r, g, b = AnimPal.rgb(c)
    if coeff > 0 then r, g, b = AnimPal.blend5(r, g, b, coeff, tr, tg, tb) end
    local k = aff and (1 - aff.m) or 0
    if aff and aff.m >= 0 and k > 0.0001 then
      local cf = floor(k * 16 + 0.5)
      local ar = math.max(0, math.min(31, floor(aff.r / k * 31 + 0.5)))
      local ag = math.max(0, math.min(31, floor(aff.g / k * 31 + 0.5)))
      local ab = math.max(0, math.min(31, floor(aff.b / k * 31 + 0.5)))
      r, g, b = AnimPal.blend5(r, g, b, cf, ar, ag, ab)
    elseif aff and aff.m < 0 then
      r = floor((r / 31 * aff.m + aff.r) * 31 + 0.5)
      g = floor((g / 31 * aff.m + aff.g) * 31 + 0.5)
      b = floor((b / 31 * aff.m + aff.b) * 31 + 0.5)
      r = math.max(0, math.min(31, r))
      g = math.max(0, math.min(31, g))
      b = math.max(0, math.min(31, b))
    end
    if opts.gray then r, g, b = gray5(r, g, b) end
    out[i] = AnimPal.pack(r, g, b)
  end
  return out
end

local resolved = {}

function AnimPal.send(colors, opts)
  local sh = AnimPal.shader()
  if not sh then return nil end
  local fin = AnimPal.resolve(colors, opts, resolved)
  if AnimPal.blackPass then
    for i = 0, 15 do fin[i] = 0 end
  end
  local opaque0 = opts and opts.opaque0
  for i = 0, 15 do
    local r, g, b = AnimPal.rgb(fin[i])
    local v = vecs[i + 1]
    v[1], v[2], v[3] = r / 31, g / 31, b / 31
    v[4] = (i == 0 and not opaque0) and 0 or 1
  end
  local ok = pcall(sh.send, sh, "pal", unpack(vecs))
  if not ok then return nil end
  return sh
end

function AnimPal.register(rgbaImg, idxImg, tag)
  if rgbaImg and idxImg then AnimPal.idxOf[rgbaImg] = { img = idxImg, tag = norm(tag) } end
end

function AnimPal.indexImage(img)
  local e = img and AnimPal.idxOf[img]
  return e and e.img, e and e.tag
end

function AnimPal.spriteTag(s, fallback)
  return norm(s and (s._palTag or s.palTag or s.tag)) or fallback
end

function AnimPal.begin(s, img, opts)
  local idx, sheetTag = AnimPal.indexImage(img)
  if not idx then return nil end
  local tag = AnimPal.spriteTag(s, sheetTag)
  local colors = AnimPal.fadedOf(tag)
  if not colors and tag ~= sheetTag then colors = AnimPal.fadedOf(sheetTag) end
  if not colors then return nil end
  local sh = AnimPal.send(colors, opts)
  if not sh then return nil end
  love.graphics.setShader(sh)
  return idx
end

function AnimPal.beginSprite(s, img, vm)
  local b = s and s.palBlend
  local tint = nil
  if b and (tonumber(b.coeff) or 0) > 0 then
    tint = b
  elseif vm and vm._tagBlend and s and s.tag then
    tint = vm._tagBlend[s.tag]
  end
  return AnimPal.begin(s, img, tint and { coeff = tint.coeff, color = tint.color } or nil)
end

function AnimPal.finish()
  love.graphics.setShader()
end

local function load_image(bytes, name)
  if type(bytes) ~= "string" or #bytes == 0 then return nil end
  local okFd, fd = pcall(love.filesystem.newFileData, bytes, name)
  if not okFd then return nil end
  local okId, data = pcall(love.image.newImageData, fd)
  if not okId or not data then return nil end
  return data
end
AnimPal.loadImageData = load_image

function AnimPal.readPackFile(file)
  local ok, Dataset = pcall(require, "src.core.game3.dataset")
  local cache = ok and Dataset.cache and Dataset.cache() or nil
  local rel = "data/generated/gba/pokemon/battle_anims/" .. tostring(file)
  return cache and cache.read and (cache:read(rel) or cache:read("firered/" .. rel))
end

function AnimPal.hydrateIndex(info, tag, rgbaImg, reader)
  if not (info and info.idxFile and rgbaImg and love and love.graphics) then return nil end
  if info.idxImage == nil then
    info.idxImage = false
    local data = load_image((reader or AnimPal.readPackFile)(info.idxFile), info.idxFile)
    if data then
      info.idxData = data
      local okImg, img = pcall(love.graphics.newImage, data)
      if okImg and img then
        img:setFilter("nearest", "nearest")
        info.idxImage = img
      end
    end
  end
  if info.idxImage then AnimPal.register(rgbaImg, info.idxImage, tag) end
  return info.idxImage or nil
end

function AnimPal.relayIndex(info, tag, rgbaOut, w)
  local src = info and info.idxData
  if not (src and rgbaOut and love and love.image) then return nil end
  local sw, sh = src:getDimensions()
  local srcTilesWide = floor(sw / 8)
  local tiles = srcTilesWide * floor(sh / 8)
  local dstTilesWide = math.max(1, floor(w / 8))
  local dh = math.max(8, math.ceil(tiles / dstTilesWide) * 8)
  local dst = love.image.newImageData(dstTilesWide * 8, dh)
  for t = 0, tiles - 1 do
    local sx, sy = (t % srcTilesWide) * 8, floor(t / srcTilesWide) * 8
    local dx, dy = (t % dstTilesWide) * 8, floor(t / dstTilesWide) * 8
    dst:paste(src, dx, dy, sx, sy, 8, 8)
  end
  local okImg, out = pcall(love.graphics.newImage, dst)
  if not okImg or not out then return nil end
  out:setFilter("nearest", "nearest")
  AnimPal.register(rgbaOut, out, tag)
  return out
end

AnimPal.bgUnfaded = {}
AnimPal.bgFaded = {}

function AnimPal.bgInfo(key)
  local pack = AnimPal._pack
  return pack and pack.animBgs and pack.animBgs[key]
end

function AnimPal.bgLoad(slot, key, palOverride)
  local info = AnimPal.bgInfo(key)
  local src = palOverride or (info and info.pal)
  if not src then
    AnimPal.bgUnfaded[slot] = nil
    AnimPal.bgFaded[slot] = nil
    return nil
  end
  local u = copy0(src)
  AnimPal.bgUnfaded[slot] = u
  AnimPal.bgFaded[slot] = nil
  return u
end

function AnimPal.bgColors(slot)
  return AnimPal.bgFaded[slot] or AnimPal.bgUnfaded[slot]
end

function AnimPal.bgWriteFaded(slot)
  local f = AnimPal.bgFaded[slot]
  if f then return f end
  local u = AnimPal.bgUnfaded[slot]
  if not u then return nil end
  f = {}
  for i = 0, 15 do f[i] = u[i] end
  AnimPal.bgFaded[slot] = f
  return f
end

function AnimPal.bgImages(key)
  local info = AnimPal.bgInfo(key)
  if not info then return nil end
  if info.image == nil then
    info.image = false
    if love and love.graphics and info.file then
      local data = load_image(AnimPal.readPackFile(info.file), info.file)
      if data then
        local ok, img = pcall(love.graphics.newImage, data)
        if ok and img then
          img:setFilter("nearest", "nearest")
          pcall(function() img:setWrap("repeat", "repeat") end)
          info.image = img
        end
      end
    end
  end
  if info.image and info.idxImage == nil then
    info.idxImage = false
    if info.idxFile then
      local data = load_image(AnimPal.readPackFile(info.idxFile), info.idxFile)
      if data then
        local ok, img = pcall(love.graphics.newImage, data)
        if ok and img then
          img:setFilter("nearest", "nearest")
          pcall(function() img:setWrap("repeat", "repeat") end)
          info.idxImage = img
        end
      end
    end
  end
  return info.image or nil, info.idxImage or nil, info
end

local bgQuads = setmetatable({}, { __mode = "k" })

-- pokefirered/src/battle_anim_mons.c:939
function AnimPal.drawBg(key, slot, scrollX, scrollY, opts)
  if not (love and love.graphics) then return false end
  opts = opts or {}
  local img, idx, info = AnimPal.bgImages(key)
  if not img then return false end
  local iw, ih = img:getDimensions()
  local sx = floor(tonumber(scrollX) or 0) % iw
  local sy = floor(tonumber(scrollY) or 0) % ih
  local vw, vh = opts.w or 240, opts.h or 160
  local draw = img
  local sh = nil
  local colors = slot and AnimPal.bgColors(slot)
  if idx and colors then
    sh = AnimPal.send(colors, { coeff = opts.coeff, color = opts.color, affine = opts.affine, opaque0 = info.opaque0 })
    if sh then draw = idx end
  end
  local q = bgQuads[draw]
  if not q then
    q = love.graphics.newQuad(0, 0, vw, vh, iw, ih)
    bgQuads[draw] = q
  end
  q:setViewport(sx, sy, vw, vh, iw, ih)
  local eva, evb = opts.eva, opts.evb
  if eva and evb and eva + evb ~= 16 and sh then
    local zero = AnimPal._zero
    if not zero then
      zero = {}
      for i = 0, 15 do zero[i] = 0 end
      AnimPal._zero = zero
    end
    local blk = AnimPal.send(zero, { opaque0 = info.opaque0 })
    love.graphics.setShader(blk)
    love.graphics.setColor(1, 1, 1, 1 - math.min(16, evb) / 16)
    love.graphics.draw(draw, q, opts.x or 0, opts.y or 0)
    sh = AnimPal.send(colors, { coeff = opts.coeff, color = opts.color, affine = opts.affine, opaque0 = info.opaque0 })
    love.graphics.setShader(sh)
    love.graphics.setBlendMode("add", "alphamultiply")
    love.graphics.setColor(1, 1, 1, math.min(16, eva) / 16)
    love.graphics.draw(draw, q, opts.x or 0, opts.y or 0)
    love.graphics.setBlendMode("alpha", "alphamultiply")
  else
    if sh then love.graphics.setShader(sh) end
    local a = opts.alpha
    if a == nil and eva then a = math.min(16, eva) / 16 end
    love.graphics.setColor(1, 1, 1, a or 1)
    love.graphics.draw(draw, q, opts.x or 0, opts.y or 0)
  end
  love.graphics.setColor(1, 1, 1, 1)
  if sh then love.graphics.setShader() end
  return true
end

function AnimPal.bgLayerDraw(key, slot, x, y, vm, opts)
  opts = opts or {}
  local b = vm and vm.bldAlpha
  if b and not opts.noBlend then
    opts.eva = tonumber(b.eva or b[1]) or 16
    opts.evb = tonumber(b.evb or b[2]) or 0
    if opts.eva <= 0 then return true end
  end
  return AnimPal.drawBg(key, slot, x, y, opts)
end

return AnimPal
