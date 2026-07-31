-- Voxel world mode: the texture terrain samples.
--
-- Voxel terrain is textured from the tileset atlas, so a map's colors have
-- to live IN that atlas. Two of the three color paths already do:
--
--   RED++      TileRenderer.new bakes a fully recolored per-map atlas
--              (getGbcAtlas) and hands it over as renderer.image -- nothing
--              to do here, true GBC terrain color comes through untouched.
--   trueColor  a mod's full-color atlas is already its own colors.
--
-- The SGB modes are the gap. There the atlas is raw 4-shade grayscale and
-- the color normally arrives as a screen-space shade-remap pass over
-- rectangular zones (PaletteFX) -- which has no meaning once the ground is
-- geometry rather than a rectangle. So bake instead: one atlas copy per
-- (atlas, palette), remapped through the same cutoffs the shader uses.
--
-- A map has exactly one world palette, so this is a handful of 128x48
-- images for a whole session, built once and cached.
--
-- ANIMATED TILES (water, flowers) are the other thing this file owns. The
-- 2D path animates them by OVERDRAWING the animated cells on top of the
-- static tile layer each frame, which a single static mesh has no
-- equivalent of -- the geometry samples one texture and that is that. So
-- animate the texture: rewrite the animated tile's slot in a private copy
-- of the atlas whenever the step advances, and every instance of that tile
-- across the whole mesh moves at once. Which is what the Game Boy does in
-- the first place (home/vcopy.asm rewrites the tile's VRAM bytes); the 2D
-- overdraw is the port's workaround, not the original.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local Assets = require("src.render.Assets")
local TileRenderer = require("src.render.TileRenderer")
local PaletteFX = require("src.render.PaletteFX")

local TerrainAtlas = {}

local cache = {}
local cacheData = {}    -- the pixels behind the atlases we baked ourselves
local animated = {}     -- key -> one map's private, mutable animated atlas
                        -- false = given up on; nil = not built (or retrying)
local attempts = {}     -- key -> consecutive failures, for the retry budget

-- A failure that might not repeat -- a driver refusing one readback, an
-- asset briefly unreadable, a patch that threw once mid-reload -- must not
-- cost the animation for the rest of the session. It used to: the key was
-- condemned to `false` on the first miss and nothing ever rebuilt it, so
-- water stopped moving and stayed stopped until a hot reload.
--
-- Retry a few times, then give up for good so a genuinely broken atlas is
-- not rebuilt on every frame forever.
local MAX_ATTEMPTS = 3

local function attemptFailed(key)
  local n = (attempts[key] or 0) + 1
  attempts[key] = n
  if n >= MAX_ATTEMPTS then return false end   -- condemn it
  return nil                                    -- rebuild next frame
end

local function paletteKey(colors)
  local parts = {}
  for i = 1, 4 do
    local c = colors[i]
    parts[i] = c and (c[1] .. "," .. c[2] .. "," .. c[3]) or "-"
  end
  return table.concat(parts, ";")
end

-- The atlas image `map`'s terrain should sample, given the 4-color world
-- palette it sits under (nil to leave the atlas as-is). Falls back to the
-- renderer's own image whenever a bake is impossible -- headless, or no
-- pixel access -- which just means grayscale terrain rather than no
-- terrain.
-- The static atlas for `map` under `colors`: the answer this file gave
-- before animation existed, and the base every animated frame is patched
-- over. Returns the image and, when we baked it ourselves, its pixels.
local function staticAtlas(map, colors)
  local renderer = map.renderer
  local base = renderer and renderer.image
  if not base then return nil end
  -- already true color: RED++'s baked per-map atlas, or a mod's own art
  if not colors or renderer.gbcAtlas or map.tileset.trueColor then
    return base, false
  end
  if not (love.image and love.image.newImageData) then return base, false end

  local path = map.tileset.image
  local key = path .. "#" .. paletteKey(colors)
  if cache[key] ~= nil then return cache[key] or base, cacheData[key] end

  local data
  local ok, img = pcall(function()
    local src = Assets.imageData(path)
    local w, h = src:getDimensions()
    local out = love.image.newImageData(w, h)
    for y = 0, h - 1 do
      for x = 0, w - 1 do
        local r, g, b, a = src:getPixel(x, y)
        r, g, b, a = TileRenderer.recolorSample(r, g, b, a, colors)
        out:setPixel(x, y, r, g, b, a)
      end
    end
    local image = love.graphics.newImage(out)
    image:setFilter("nearest", "nearest")
    data = out
    return image
  end)
  cache[key] = ok and img or false
  cacheData[key] = (ok and data) or false
  return cache[key] or base, cacheData[key]
end

-- ------------------------------------------------------------ animation --

-- The four GB shades as the ORIGINAL art carries them, by the same cutoffs
-- TileRenderer.recolorSample splits on -- so a shade learned here and a
-- shade recolored there are the same shade.
local function shadeOf(r)
  if r > 0.83 then return 1 end
  if r > 0.5 then return 2 end
  if r > 0.17 then return 3 end
  return 4
end

-- How this atlas recolored one tile, learned by reading the tile's slot in
-- the raw art and in the finished atlas side by side: shade -> the colour
-- it became.
--
-- Learned rather than recomputed because the two recolour paths do not
-- share a rule -- SGB bakes one world palette over everything, RED++ picks
-- a palette group per tile GRAPHIC -- and a flower frame arrives as its own
-- little grayscale file that never went through either. Asking "what
-- happened to the tile I am replacing" gets the right answer from both
-- without this file knowing which one ran.
local function learnShades(raw, baked, tile, perRow)
  local sx, sy = (tile % perRow) * 8, math.floor(tile / perRow) * 8
  local map = {}
  for y = 0, 7 do
    for x = 0, 7 do
      local k = shadeOf(raw:getPixel(sx + x, sy + y))
      if not map[k] then
        local r, g, b, a = baked:getPixel(sx + x, sy + y)
        map[k] = { r, g, b, a }
      end
    end
  end
  return map
end

local DIRS4 = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

-- One animated entry's tile slot, written into `out` at step `step`.
local function patch(out, entry, spec, step)
  local perRow, tile = entry.perRow, spec.tile
  local dx, dy = (tile % perRow) * 8, math.floor(tile / perRow) * 8
  if spec.kind == "hshift" then
    -- the water rotate (the asm's rrca/rlca run): the tile's own pixels,
    -- rolled sideways. Read from the UNANIMATED base, or each step would
    -- compound on the last one's shift.
    local o = spec.offsets[step % #spec.offsets + 1]
    for y = 0, 7 do
      for x = 0, 7 do
        local r, g, b, a = entry.base:getPixel(dx + x, dy + y)
        out:setPixel(dx + (x + o) % 8, dy + y, r, g, b, a)
      end
    end
  elseif spec.kind == "frames" then
    local path = spec.images[spec.sequence[step % #spec.sequence + 1]]
    if not path then return end
    local ok, frame = pcall(Assets.imageData, path)
    if not ok or not frame then return end
    local shades = entry.shades and entry.shades[tile]
    -- a `cut` tile is the flower billboard's slot (Structures'
    -- buildFlowers): only the frame's darkest tones AND what they
    -- enclose stay opaque -- the round-scenery hull's rule, flooding
    -- the frame border through every non-dark pixel so the pale petal
    -- insides survive with the outline. The true background is keyed
    -- to alpha; nothing else samples this slot (the ground under a
    -- flower is synthesized), and the shader's discard is what lets
    -- the billboard's silhouette change per frame under geometry that
    -- never moves.
    local mask = nil
    if entry.cut and entry.cut[tile] then
      local dark, reach, stack = {}, {}, {}
      for y = 0, 7 do
        for x = 0, 7 do
          local r, _, _, a = frame:getPixel(x, y)
          if a > 0 and shadeOf(r) >= 3 then dark[y * 8 + x] = true end
        end
      end
      for i = 0, 7 do
        for _, s in ipairs({ i, 56 + i, i * 8, i * 8 + 7 }) do
          if not dark[s] and not reach[s] then
            reach[s] = true
            stack[#stack + 1] = s
          end
        end
      end
      while #stack > 0 do
        local p = table.remove(stack)
        local px, py = p % 8, math.floor(p / 8)
        for _, d in ipairs(DIRS4) do
          local nx, ny = px + d[1], py + d[2]
          if nx >= 0 and nx < 8 and ny >= 0 and ny < 8 then
            local ni = ny * 8 + nx
            if not dark[ni] and not reach[ni] then
              reach[ni] = true
              stack[#stack + 1] = ni
            end
          end
        end
      end
      mask = {}
      for i = 0, 63 do mask[i] = dark[i] or not reach[i] end
    end
    for y = 0, 7 do
      for x = 0, 7 do
        local r, g, b, a = frame:getPixel(x, y)
        if mask and not mask[y * 8 + x] then
          out:setPixel(dx + x, dy + y, 0, 0, 0, 0)
        else
          local col = shades and shades[shadeOf(r)]
          if col and a > 0 then r, g, b = col[1], col[2], col[3] end
          out:setPixel(dx + x, dy + y, r, g, b, a)
        end
      end
    end
  end
end

-- The animation specs this file can serve: the two that rewrite a tile's
-- pixels. "toggle" (the spinner-puzzle blur) is a whole-atlas swap gated on
-- a gameplay state, and is left to the 2D path -- voxel mode does not draw
-- the spinner rooms' tile layer any differently for it.
local function specsFor(tileset)
  local declared = tileset.animatedTiles
                   or TileRenderer.defaultAnimatedTiles(tileset)
  local out = nil
  for _, spec in ipairs(declared or {}) do
    local usable = spec.tile
      and ((spec.kind == "hshift" and spec.offsets and #spec.offsets > 0)
           or (spec.kind == "frames" and spec.images and spec.sequence
               and #spec.sequence > 0))
    if usable then
      out = out or {}
      out[#out + 1] = spec
    end
  end
  return out
end

-- Pixels back off a texture the engine built on the GPU and kept no copy
-- of. LOVE 11 hands out no ImageData for an Image, so the only route is a
-- round trip: draw it 1:1 into a canvas and read that back.
--
-- This runs inside the world pass, with the pipeline's own canvas bound, so
-- the previous target is captured and put back rather than unbound -- the
-- usual setCanvas() would drop the rest of the frame on the floor. One
-- readback per map, cached with the entry it feeds; the atlas is a couple
-- of hundred pixels square, so the GPU sync costs far less than the mesh
-- build it happens alongside. Every step is guarded: a driver that refuses
-- canvas readback costs the animation and nothing else.
local function readback(image)
  if not (image and love.graphics and love.graphics.newCanvas
          and love.graphics.getCanvas) then
    return nil
  end
  local prev = love.graphics.getCanvas()
  local ok, data = pcall(function()
    local w, h = image:getDimensions()
    local canvas = love.graphics.newCanvas(w, h)
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 0)
    -- straight copy: no blending against the cleared target, no tint from
    -- whatever colour the pass left set, or the atlas comes back wrong
    love.graphics.setBlendMode("replace", "premultiplied")
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(image, 0, 0)
    love.graphics.setBlendMode("alpha", "alphamultiply")
    -- LOVE refuses newImageData on the currently-active canvas, so the
    -- previous target has to come back BEFORE the read, not just after
    love.graphics.setCanvas(prev)
    local out = canvas:newImageData()
    if canvas.release then canvas:release() end
    return out
  end)
  pcall(love.graphics.setCanvas, prev)
  return ok and data or nil
end

-- RED++'s per-map atlas, rebuilt on the CPU.
--
-- This is the case that has no pixels anywhere: `getGbcAtlas` bakes one
-- ImageData per map, hands the texture to the renderer and drops the
-- pixels on the floor. Without them the animated tiles cannot be patched,
-- which is why water and flowers stood still under RED++ and nowhere else.
--
-- The readback below can recover them from the texture, but it is at the
-- mercy of whether the driver will read a canvas back, and it costs a GPU
-- sync mid-frame. Everything the engine baked FROM is public, so bake it
-- again instead: the raw art, the per-tile palette group, the group's
-- colours, and the same recolorSample cutoffs. Deterministic, no driver
-- involved, and it can be tested without a GPU.
--
-- It does mirror engine logic and could drift from getGbcAtlas if that
-- changes -- the readback stays behind it as the exact-but-fragile route.
local function gbcPixels(map)
  local renderer, tileset = map.renderer, map.tileset
  local data = renderer and renderer.data
  if not (data and tileset and love.image and love.image.newImageData) then
    return nil
  end
  local ok, out = pcall(function()
    local groupColors = PaletteFX.worldGroupColors(data, tileset.id, map.id, nil)
    if not groupColors then return nil end
    local src = Assets.imageData(tileset.image)
    local iw, ih = src:getDimensions()
    local perRow = tileset.tilesPerRow or 16
    local total = (iw / 8) * (ih / 8)
    local dst = love.image.newImageData(iw, ih)

    local function bake(from, to, colors)
      local sxo, syo = (from % perRow) * 8, math.floor(from / perRow) * 8
      local dxo, dyo = (to % perRow) * 8, math.floor(to / perRow) * 8
      for py = 0, 7 do
        for px = 0, 7 do
          local r, g, b, a = src:getPixel(sxo + px, syo + py)
          r, g, b, a = TileRenderer.recolorSample(r, g, b, a, colors)
          dst:setPixel(dxo + px, dyo + py, r, g, b, a)
        end
      end
    end

    local tileColors = {}
    for t = 0, total - 1 do
      local colors = tileColors[t]
      if colors == nil then
        local group = PaletteFX.worldGroupAt(tileset.id, map.id, t)
        colors = (group and groupColors[group + 1]) or false
        tileColors[t] = colors
      end
      bake(t, t, colors)
    end
    -- duplicate-tile aliases: the same graphic baked into a spare slot
    -- under a second palette group, so cells drawing the alias colour apart
    for _, al in ipairs(PaletteFX.TILE_ALIASES
                        and PaletteFX.TILE_ALIASES[map.id] or {}) do
      if al.alias < total then
        bake(al.tile, al.alias, groupColors[al.group + 1])
      end
    end
    return dst
  end)
  return ok and out or nil
end

-- The pixels behind the atlas texture the engine is drawing with, for the
-- frames where we did not bake one ourselves (staticAtlas returns `false`
-- for its own bake whenever the palette is absent, RED++ already baked, or
-- the tileset is trueColor).
--
-- TileRenderer.atlasImageData is the engine's own accessor for exactly this
-- and is preferred wherever the build offers it -- but like the sibling
-- clock TileRenderer.animFrame it is an OPTIONAL seam, and a build without
-- it has to cost us the animation, not the whole render pipeline. Reading
-- it unguarded is what took the pass down for the session.
--
-- Without the seam the pixels are still recoverable, by two different
-- routes. An atlas neither we nor RED++ replaced is the tileset art itself,
-- so the art on disk IS what it was built from. RED++'s per-map bake exists
-- only on the GPU -- getGbcAtlas throws its ImageData away once the texture
-- is made -- so that one has to come back off the texture (readback below).
local function rendererPixels(map)
  local renderer = map.renderer
  if not renderer then return nil end
  if TileRenderer.atlasImageData then
    local ok, data = pcall(TileRenderer.atlasImageData, renderer)
    if ok and data then return data end
  end
  if renderer.gbcAtlas then
    return gbcPixels(map) or readback(renderer.image)
  end
  local ok, data = pcall(Assets.imageData, map.tileset.image)
  return ok and data or nil
end

-- The engine's tile-animation clock: TileRenderer's 60Hz counter, by
-- whatever route this build offers.
--
-- It matters that this is the ENGINE's number and not one of our own. The
-- 2D tile layer and this texture animate the same water off the same
-- counter, so toggling voxel mode mid-cycle continues the animation instead
-- of restarting or jumping it. A clock of our own would free-run against
-- the one the flat path is drawing from.
--
--   1. TileRenderer.animFrame(), where the build exports it.
--   2. else the counter itself, off tick()'s upvalues. It is a plain local
--      in that module, so this is exact and live -- the same number, not an
--      approximation of it. Reading engine internals is what this mod's
--      "engine_internals" permission is declared for, and this one is
--      read-only and entirely optional.
--   3. else wall time in 60Hz steps. Free-running, but the water moves,
--      which beats a frozen pond. Derived from absolute time rather than
--      accumulated deltas because animate() is called once per map in the
--      neighbourhood, so a per-call accumulator would run several times
--      too fast.
local clockUpvalue = nil        -- nil = not looked for yet, false = absent

local function findClockUpvalue()
  if not (debug and debug.getupvalue) then return false end
  if type(TileRenderer.tick) ~= "function" then return false end
  for i = 1, 32 do
    local ok, name, value = pcall(debug.getupvalue, TileRenderer.tick, i)
    if not (ok and name) then break end
    if name == "animFrame" and type(value) == "number" then return i end
  end
  return false
end

local function animFrame()
  if TileRenderer.animFrame then
    local ok, f = pcall(TileRenderer.animFrame)
    if ok and type(f) == "number" then return f end
  end
  if clockUpvalue == nil then clockUpvalue = findClockUpvalue() end
  if clockUpvalue then
    local ok, _, value = pcall(debug.getupvalue, TileRenderer.tick, clockUpvalue)
    if ok and type(value) == "number" then return value end
  end
  if love.timer and love.timer.getTime then
    return math.floor(love.timer.getTime() * 60)
  end
  return 0
end

TerrainAtlas._animFrame = animFrame   -- named for the suite

-- false = this can never work and asking again is waste; nil = it did not
-- work THIS time and might next. The caller latches the first and retries
-- the second (see attemptFailed).
local function newEntry(map, base, baked)
  local tileset = map.tileset
  local specs = specsFor(tileset)
  if not specs then return false end        -- nothing on this tileset animates
  if not (love.image and love.image.newImageData
          and base.replacePixels) then
    return false                            -- no pixel access on this machine
  end
  -- the pixels the atlas texture was built from: our own SGB bake when we
  -- made one, else whatever the engine's renderer is drawing with. A
  -- readback can fail for one frame and work the next, so this is a
  -- retryable miss rather than a verdict.
  local src = baked or rendererPixels(map)
  if not src then return nil end

  local ok, entry = pcall(function()
    local w, h = src:getDimensions()
    -- A PRIVATE copy, always. The base may be the engine's own atlas, and
    -- the 2D path draws the static tile from it and overdraws the animated
    -- cell on top -- rewriting the slot underneath would animate the tile
    -- twice over there and corrupt every still frame of it.
    local data = love.image.newImageData(w, h)
    data:paste(src, 0, 0, 0, 0, w, h)
    local image = love.graphics.newImage(data)
    image:setFilter("nearest", "nearest")
    local e = { base = src, data = data, image = image, specs = specs,
                perRow = tileset.tilesPerRow or 16, step = nil }
    -- the frame files are raw grayscale; learn what the atlas did to the
    -- tile each one stands in for, so they land on the same colours
    local recolored = baked or (map.renderer and map.renderer.gbcAtlas)
    if recolored and not tileset.trueColor then
      local raw = Assets.imageData(tileset.image)
      e.shades = {}
      for _, spec in ipairs(specs) do
        if spec.kind == "frames" then
          e.shades[spec.tile] = learnShades(raw, src, spec.tile, e.perRow)
        end
      end
    end
    -- a frame-animated tile that resolved to the `flower` class stands as
    -- a 1px billboard (Structures.buildFlowers), and its slot in THIS
    -- copy carries only each frame's dark tones with the rest keyed to
    -- alpha -- see patch(). Gated on the resolved shape so a profile that
    -- pins the tile to something solid keeps a fully opaque slot, and on
    -- the tileset art being readable: without pixels Structures cannot
    -- have stood the billboard up (or synthesized the ground), and an
    -- alpha-keyed slot under an ordinary flat quad is a hole in the world.
    for _, spec in ipairs(specs) do
      if spec.kind == "frames" then
        local okCut, isFlower = pcall(function()
          local okA, art = pcall(Assets.imageData, tileset.image)
          if not (okA and art and art.getPixel) then return false end
          local sh = V.require("TileShape").forMap(map)[spec.tile]
          return sh ~= nil and sh.class == "flower"
        end)
        if okCut and isFlower then
          e.cut = e.cut or {}
          e.cut[spec.tile] = true
        end
      end
    end
    return e
  end)
  return (ok and entry) or false
end

-- The atlas for this frame: the static one when nothing on this tileset
-- animates (or anything at all goes wrong), else a private copy with the
-- animated slots rewritten to the current step. Repatched only when the
-- step actually changes -- three times a second, ~130 pixels of work.
function TerrainAtlas.animate(map, colors, base, baked)
  -- RED++ bakes a per-MAP atlas, so its animated copy is per map too and
  -- has to be evicted with the meshes (setLive below); the shared paths key
  -- on the tileset and palette alone, which is bounded by how many of those
  -- exist at all.
  local perMap = map.renderer and map.renderer.gbcAtlas and map.id or nil
  local key = map.tileset.image .. "#a#" .. paletteKey(colors or {})
    .. (perMap or "")
  local entry = animated[key]
  if entry == nil then
    entry = newEntry(map, base, baked)
    if entry then
      entry.mapId = perMap
      animated[key] = entry
    else
      -- false from newEntry is a verdict (nothing animates on this tileset,
      -- no pixel access at all); nil is a miss that may not repeat
      animated[key] = (entry == false) and false or attemptFailed(key)
    end
  end
  if not entry then return nil end

  local frame = animFrame()
  -- one number for the whole entry: every spec's own step, folded together,
  -- so a repatch happens when ANY of them turns over
  local step = 0
  for i, spec in ipairs(entry.specs) do
    local n = spec.kind == "hshift" and #spec.offsets or #spec.sequence
    step = step + (math.floor(frame / (spec.period or 20)) % n) * (16 ^ i)
  end
  if step ~= entry.step then
    entry.step = step
    local ok = pcall(function()
      for _, spec in ipairs(entry.specs) do
        local n = spec.kind == "hshift" and #spec.offsets or #spec.sequence
        patch(entry.data, entry, spec,
              math.floor(frame / (spec.period or 20)) % n)
      end
      entry.image:replacePixels(entry.data)
    end)
    if not ok then
      -- drop the entry rather than condemning the key: the next frame
      -- rebuilds and tries again, and attemptFailed gives up eventually
      animated[key] = attemptFailed(key)
      return nil
    end
  end
  -- Only a frame that got all the way here counts as healthy. Clearing the
  -- budget on a successful BUILD instead would never let it run out: an
  -- entry that builds fine and fails on upload would rebuild every frame,
  -- forever, which is worse than either animating or giving up.
  if attempts[key] then attempts[key] = nil end
  return entry.image
end

function TerrainAtlas.forMap(map, colors)
  local base, baked = staticAtlas(map, colors)
  if not base then return nil end
  return TerrainAtlas.animate(map, colors, base, baked) or base
end

-- The image a character model should texture from under an SGB palette.
--
-- In the 2D SGB modes, sprites are colorized by the screen-space
-- shade-remap shader at blit time -- the sheet itself stays grayscale. The
-- voxel canvas composites 1:1 with no shader pass, so a model textured
-- straight from the sheet renders in raw DMG grays (a black-and-gray
-- character standing in a colored room). Bake instead, exactly like the
-- terrain above: one recolored sheet per (sheet, palette), remapped
-- through the same cutoffs the shader uses, alpha preserved so OBJ color
-- 0 stays transparent. Falls back to nil (caller keeps its texture) when
-- pixels are unreachable.
function TerrainAtlas.forSprite(path, colors)
  if not (colors and love.image and love.image.newImageData) then
    return nil
  end
  local key = "spr:" .. path .. "#" .. paletteKey(colors)
  if cache[key] ~= nil then return cache[key] or nil end

  local ok, img = pcall(function()
    local src = Assets.imageData(path)
    local w, h = src:getDimensions()
    local out = love.image.newImageData(w, h)
    for y = 0, h - 1 do
      for x = 0, w - 1 do
        local r, g, b, a = src:getPixel(x, y)
        r, g, b, a = TileRenderer.recolorSample(r, g, b, a, colors)
        out:setPixel(x, y, r, g, b, a)
      end
    end
    local image = love.graphics.newImage(out)
    image:setFilter("nearest", "nearest")
    return image
  end)
  cache[key] = ok and img or false
  return cache[key] or nil
end

-- Release the animated copies of maps outside `live` (a set of map ids),
-- the same neighbourhood ChunkMesher bounds its meshes to and called from
-- the same place. Only the per-map RED++ copies are held this way; the rest
-- are keyed by tileset and palette, of which a session sees a handful.
-- Without this a cross-region trek accumulates one atlas and one texture
-- per map ever entered, and each pins the engine's own baked ImageData
-- alive behind it.
function TerrainAtlas.setLive(live)
  for key, entry in pairs(animated) do
    if entry and entry.mapId and not live[entry.mapId] then
      if entry.image and entry.image.release then
        pcall(entry.image.release, entry.image)
      end
      animated[key] = nil
    end
  end
end

function TerrainAtlas.invalidate()
  cache = {}
  cacheData = {}
  attempts = {}
  for _, entry in pairs(animated) do
    if entry and entry.image and entry.image.release then
      pcall(entry.image.release, entry.image)
    end
  end
  animated = {}
end

Assets.register(TerrainAtlas.invalidate)

return TerrainAtlas
