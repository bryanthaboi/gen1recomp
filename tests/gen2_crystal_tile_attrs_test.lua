-- Crystal PalMap decoder and TileAttrs helper (bank-0 / $ff skip / bank-1 $80+).
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 crystal tile attrs")
local check, eq = S.check, S.eq

love = require("tests.love_stub")

local Extractor = require("src.import.RomExtractorGen2")
local GameVersion = require("src.core.GameVersion")
local TileAttrs = require("src.world.gen2.TileAttrs")
local OamFootprint = require("src.world.gen2.OamFootprint")

local priorVersion = GameVersion.get()
GameVersion.set("crystal")

local PAL_BANK = 0x13
local PAL_ADDR = 0x5000

local function fakeRom(bytes)
  return {
    bytes = function(_, bank, address, length)
      local out = {}
      if bank ~= PAL_BANK then return out end
      for i = 0, length - 1 do
        out[#out + 1] = bytes[address + i] or 0
      end
      return out
    end,
  }
end

local function crystalExtractor(palBytes)
  local romBytes = {}
  for i, b in ipairs(palBytes) do romBytes[PAL_ADDR + i - 1] = b end
  return setmetatable({
    rom = fakeRom(romBytes),
    edition = "crystal",
  }, Extractor)
end

-- Bank 0: one data byte, padding, bank 1: one data byte.
do
  local pal = {}
  pal[1] = 0x12 -- tile 0 pal 3, tile 1 pal 2
  for i = 2, 48 do pal[i] = 0x00 end
  for i = 49, 64 do pal[i] = 0xff end
  pal[65] = 0x08 -- tile $80: nibble 8 -> pal 1, VRAM bank 1
  for i = 66, 112 do pal[i] = 0x00 end

  local ex = crystalExtractor(pal)
  local palettes, attrs = ex:readCrystalPalMap(PAL_ADDR)
  eq(palettes[1], 3, "bank-0 tile 0 palette")
  eq(palettes[2], 2, "bank-0 tile 1 palette")
  eq(palettes[97], nil, "padding does not land on tile 96")
  eq(palettes[0x80 + 1], 1, "bank-1 tile $80 palette")
  eq(attrs[0x80 + 1].vramBank, 1, "bank-1 tile $80 VRAM bank")
  eq(attrs[0x80 + 1].priority, false, "retail nibble has no BG_PRIO")
end

-- TileAttrs lookup and backward-compat paletteSlot.
do
  local tileset = {
    tilePalettes = { [1] = 2, [0x81] = 5 },
    tileAttrs = {
      [1] = { palette = 2, vramBank = 0, priority = false,
        xFlip = false, yFlip = false },
      [0x81] = { palette = 5, vramBank = 1, priority = true,
        xFlip = false, yFlip = false },
    },
  }
  eq(TileAttrs.paletteSlot(tileset, 0), 2, "paletteSlot reads attrs")
  eq(TileAttrs.forTile(tileset, 0x80).vramBank, 1, "bank-1 default when attrs sparse")
  check(TileAttrs.forTile(tileset, 0x80).priority, "priority flag preserved")
  local bankAlias = {
    tileAttrs = {
      [0x85 + 1] = { palette = 4, vramBank = 1, priority = false,
        xFlip = false, yFlip = false },
    },
  }
  eq(TileAttrs.forTile(bankAlias, 5).palette, 4,
    "low tile id aliases bank-1 attrs at $80+")
end

-- MapAttrGrid pret normalization (bit 7 -> bank, norm id).
do
  local MapAttrGrid = require("src.world.gen2.MapAttrGrid")
  local tileset = {
    tileAttrs = {
      [0x05 + 1] = { palette = 2, vramBank = 0, priority = false,
        xFlip = false, yFlip = false },
      [0x85 + 1] = { palette = 6, vramBank = 1, priority = false,
        xFlip = false, yFlip = false },
    },
  }
  local norm, attr = MapAttrGrid.normalizeTile(0x85, tileset)
  eq(norm, 5, "tile $85 normalizes to $05")
  eq(attr.vramBank, 1, "bank from tile bit 7")
  eq(attr.palette, 6, "bank-1 palmap slot")
end

-- OamFacings: RELATIVE_ATTRIBUTES only on bottom row (y = 8).
do
  local OamFacings = require("src.world.gen2.OamFacings")
  eq(OamFacings.bottomRowY(), 8, "facings.asm bottom row at y=8")
  local rel = OamFacings.relativeAttrRows(OamFacings.standingDown)
  eq(#rel, 2, "standing down has two RELATIVE_ATTRIBUTES tiles")
  for _, entry in ipairs(rel) do
    eq(entry.y, 8, "relative attr row is y=8")
  end
end

-- sheetTileId maps B_BG_BANK1 attrs onto the Crystal 256-tile sheet.
do
  eq(TileAttrs.sheetTileId(5, { vramBank = 0 }), 5, "bank 0 keeps tile id")
  eq(TileAttrs.sheetTileId(5, { vramBank = 1 }), 0x85, "bank 1 remaps to $80+")
  eq(TileAttrs.sheetTileId(0x85, { vramBank = 1 }), 0x85, "already $80+ unchanged")
end

-- drawFlippedTile keeps an 8x8 cell anchored (centre origin on flip).
do
  local calls = {}
  local orig = love.graphics.draw
  love.graphics.draw = function(_, _, x, y, _, sx, sy, ox, oy)
    calls[#calls + 1] = { x = x, y = y, sx = sx, sy = sy, ox = ox, oy = oy }
  end
  local img = love.graphics.newImage("missing.png")
  local quad = { w = 8, h = 8 }
  TileAttrs.drawFlippedTile(img, quad, 16, 16,
    { xFlip = false, yFlip = false }, 1, 1)
  eq(#calls, 1, "no-flip draws once")
  eq(calls[1].x, 16, "no-flip x at corner")
  eq(calls[1].y, 16, "no-flip y at corner")
  calls = {}
  TileAttrs.drawFlippedTile(img, quad, 16, 16,
    { xFlip = true, yFlip = false }, 1, 1)
  eq(calls[1].x, 20, "xFlip origin at cell centre")
  eq(calls[1].y, 20, "xFlip y at cell centre")
  eq(calls[1].sx, -1, "xFlip scale")
  eq(calls[1].ox, 4, "xFlip pivot x")
  eq(calls[1].oy, 4, "xFlip pivot y")
  love.graphics.draw = orig
end

-- OamFootprint matches facings.asm RELATIVE_ATTRIBUTES row + yOffset.
do
  local x0, y0, x1, y1 = OamFootprint.feetStrip({ px = 16, py = 80 })
  eq(x0, 16, "feet strip x0")
  eq(y0, 84, "feet strip y0 = py + 4")
  eq(x1, 32, "feet strip x1")
  eq(y1, 92, "feet strip y1 = py + 12")
  x0, y0, x1, y1 = OamFootprint.feetStrip(
    { px = 0, py = 0, spriteYOffset = -4 })
  eq(y0, 0, "feet strip follows spriteYOffset")
  eq(y1, 8, "feet strip height stays 8 px")
end

-- drawPriorityOver blits when a tile carries priority.
do
  local World = require("src.world.gen2.World")
  local world = setmetatable({
    map = { id = "TEST", def = {}, width = 1, height = 1,
      blocks = { 0 }, borderBlock = 0 },
    bgSets = {},
    animCells = {},
  }, { __index = World })

  local draws = {}
  local orig = love.graphics.draw
  love.graphics.draw = function(img, quad, x, y, ...)
    draws[#draws + 1] = { img = img, x = x, y = y }
    return orig(img, quad, x, y, ...)
  end

  local atlas = love.graphics.newImage("missing.png")
  local block = {}
  for i = 1, 16 do block[i] = 0 end
  block[6] = 0x42 -- 8x8 cell at map pixel (8, 8)
  local tileset = {
    tilesPerRow = 16,
    blocks = { block },
    tileAttrs = {
      [0x42 + 1] = { palette = 1, vramBank = 0, priority = true,
        xFlip = false, yFlip = false },
    },
  }
  function world:grassAtlasFor() return atlas, tileset end
  function world:atlasFor() return atlas, tileset end
  function world:mapCacheKey() return "TEST|DAY" end

  local entity = { px = 8, py = 8, inGrass = false, grassShake = false, moving = false }
  world:drawPriorityOver(entity, 0, 0, 2)
  check(#draws > 0, "priority tile redraws over the sprite")
  love.graphics.draw = orig
end

-- IN_GRASS only covers the RELATIVE_ATTRIBUTES row (py+4 .. py+12), not the torso.
do
  local World = require("src.world.gen2.World")
  local world = setmetatable({
    map = { id = "TEST", def = {}, width = 2, height = 2,
      blocks = { 0, 0, 0, 0 }, borderBlock = 0 },
    bgSets = {},
    animCells = {},
  }, { __index = World })

  local draws = {}
  local scissorCalls = {}
  local origDraw = love.graphics.draw
  local origScissor = love.graphics.setScissor
  love.graphics.draw = function(img, quad, x, y, r, sx, sy, ox, oy)
    local h = 8
    if quad and quad.getViewport then
      local okv, _, _, _, qh = pcall(quad.getViewport, quad)
      if okv and qh then h = qh end
    elseif quad and quad.h then h = quad.h end
    draws[#draws + 1] = { x = x, y = y, h = h }
    return origDraw(img, quad, x, y, r, sx, sy, ox, oy)
  end
  love.graphics.setScissor = function(x, y, w, h)
    scissorCalls[#scissorCalls + 1] = { x = x, y = y, w = w, h = h }
  end

  local atlas = love.graphics.newImage("missing.png")
  local block = {}
  for i = 1, 16 do block[i] = 0x18 end
  local tileset = { tilesPerRow = 16, blocks = { block } }
  function world:grassAtlasFor() return atlas, tileset end
  function world:atlasFor() return atlas, tileset end
  function world:mapCacheKey() return "TEST|DAY" end

  -- py=0: feet strip is map y=4..12 (facings.asm y=8 + OAM_Y_OFS-4).
  world:drawGrassOver(
    { px = 0, py = 0, inGrass = true, grassShake = false, moving = false },
    0, 0, 1)
  check(#draws > 0, "IN_GRASS redraws grass over the feet")
  for _, d in ipairs(draws) do
    eq(d.h, 8, "IN_GRASS draws full 8x8 tiles, not sub-quad slivers")
  end
  check(#scissorCalls > 0, "IN_GRASS sets scissor for the feet strip")
  eq(scissorCalls[1].y, 4, "scissor y0 matches feet strip")
  eq(scissorCalls[1].h, 8, "scissor height is 8 px")

  -- py=8 (not 8-aligned feet): two full tile rows, scissor clips to y=12..20.
  draws = {}
  scissorCalls = {}
  world:drawGrassOver(
    { px = 0, py = 8, inGrass = true, grassShake = false, moving = false },
    0, 0, 1)
  eq(#draws, 4, "misaligned py blits every intersecting 8x8 cell whole")
  for _, d in ipairs(draws) do
    eq(d.h, 8, "misaligned py still uses full 8x8 quads")
  end
  check(#scissorCalls > 0, "misaligned py sets scissor")
  eq(scissorCalls[1].y, 12, "misaligned scissor y0 = py + 4")
  eq(scissorCalls[1].h, 8, "misaligned scissor height = 8")

  love.graphics.draw = origDraw
  love.graphics.setScissor = origScissor
end

-- Playfield letterbox offset must reach scissor (LÖVE screen space).
do
  local World = require("src.world.gen2.World")
  local Playfield = require("src.render.Playfield")
  local world = setmetatable({
    map = { id = "TEST", def = {}, width = 2, height = 2,
      blocks = { 0, 0, 0, 0 }, borderBlock = 0 },
    bgSets = {},
    animCells = {},
  }, { __index = World })

  local scissorCalls = {}
  local origScissor = love.graphics.setScissor
  love.graphics.setScissor = function(x, y, w, h)
    scissorCalls[#scissorCalls + 1] = { x = x, y = y, w = w, h = h }
    return origScissor(x, y, w, h)
  end

  local atlas = love.graphics.newImage("missing.png")
  local block = {}
  for i = 1, 16 do block[i] = 0x18 end
  local tileset = { tilesPerRow = 16, blocks = { block } }
  function world:atlasFor() return atlas, tileset end
  function world:mapCacheKey() return "TEST|DAY" end

  Playfield.enter(48, 32, 160, 144)
  world:drawGrassOver(
    { px = 0, py = 0, inGrass = true, grassShake = false, moving = false },
    10, 20, 2)
  Playfield.leave()

  check(#scissorCalls > 0, "scissor set under Playfield offset")
  eq(scissorCalls[1].x, 48 + 10, "scissor x includes Playfield.box.x")
  eq(scissorCalls[1].y, 32 + 20 + 4 * 2, "scissor y includes Playfield.box.y")
  eq(scissorCalls[1].h, 16, "scissor height scaled")

  love.graphics.setScissor = origScissor
end

-- IN_GRASS uses screen-space compositing (bottom OAM, keyed grass, top OAM).
do
  local World = require("src.world.gen2.World")
  local world = setmetatable({
    map = { id = "TEST", def = {}, width = 2, height = 2,
      blocks = { 0, 0, 0, 0 }, borderBlock = 0 },
    bgSets = { ["TEST|DAY"] = { [1] = { {0,0,0}, {1,1,1}, {2,2,2}, {3,3,3} } } },
    animCells = {},
  }, { __index = World })

  local order = {}
  local origGrass = world.drawGrassOver
  function world:drawGrassOver(e, ox, oy, sc)
    order[#order + 1] = "grass"
    return origGrass(self, e, ox, oy, sc)
  end

  local atlas = love.graphics.newImage("missing.png")
  local block = {}
  for i = 1, 16 do block[i] = 0x18 end
  local tileset = { tilesPerRow = 16, blocks = { block } }
  function world:atlasFor() return atlas, tileset end
  function world:mapCacheKey() return "TEST|DAY" end

  world:drawEntityComposite(
    { px = 0, py = 0, inGrass = true, grassShake = false, moving = false },
    0, 0, 1,
    function(row)
      order[#order + 1] = row or "full"
    end,
    false)
  eq(order[1], "bottom", "IN_GRASS draws bottom OAM first")
  eq(order[2], "grass", "IN_GRASS redraws keyed grass over bottom OAM")
  eq(order[3], "top", "IN_GRASS draws top OAM last")
end

-- Animated feet cells use the live anim frame, not the baked atlas tile.
do
  local World = require("src.world.gen2.World")
  local world = setmetatable({
    map = { id = "TEST", def = { tileset = "JOHTO" }, width = 1, height = 1,
      blocks = { 0 }, borderBlock = 0 },
    bgSets = { ["TEST|DAY"] = { [2] = { {0,0,0}, {1,1,1}, {2,2,2}, {3,3,3} } } },
    animCells = {
      ["TEST|DAY"] = {
        [0x03] = {
          layer = { kind = "flower", sheet = "flower.png", frames = 4 },
          tile = 0x03,
          slot = 2,
          cells = { 0, 8, 8, 8 },
        },
      },
    },
  }, { __index = World })

  local atlas = love.graphics.newImage("missing.png")
  local animImg = love.graphics.newImage("missing2.png")
  local block = {}
  for i = 1, 16 do block[i] = 0 end
  block[5] = 0x03 -- map pixel (0, 8)
  block[6] = 0x03 -- map pixel (8, 8)
  local tileset = { tilesPerRow = 16, blocks = { block } }
  function world:atlasFor() return atlas, tileset end
  function world:mapCacheKey() return "TEST|DAY" end
  function world:animSheet(path)
    if path == "flower.png" then return animImg end
  end

  local drewAnim, drewAtlas = false, false
  local orig = love.graphics.draw
  love.graphics.draw = function(img, ...)
    if img == animImg then drewAnim = true end
    if img == atlas then drewAtlas = true end
    return orig(img, ...)
  end

  world:drawGrassOver(
    { px = 0, py = 4, inGrass = true, grassShake = false, moving = false },
    0, 0, 1)
  check(drewAnim, "feet overdraw uses live anim sheet for animated cells")
  check(not drewAtlas, "feet overdraw skips static atlas for animated cells")
  love.graphics.draw = orig
end

-- blitBgOverRegion must land tiles at ox + tx*s (absolute map px), not ox.
do
  local World = require("src.world.gen2.World")
  local world = setmetatable({
    map = { id = "TEST", def = {}, width = 4, height = 4,
      blocks = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
      borderBlock = 0 },
    bgSets = { ["TEST|DAY"] = { [1] = { {0,0,0}, {1,1,1}, {2,2,2}, {3,3,3} } } },
    animCells = {},
  }, { __index = World })

  local atlas = love.graphics.newImage("missing.png")
  local block = {}
  for i = 1, 16 do block[i] = 0x18 end
  local tileset = { tilesPerRow = 16, blocks = { block },
    tileAttrs = { [0x19] = { palette = 1, vramBank = 0, priority = false,
      xFlip = false, yFlip = false } } }
  function world:atlasFor() return atlas, tileset end
  function world:mapCacheKey() return "TEST|DAY" end

  local draws = {}
  local orig = love.graphics.draw
  love.graphics.draw = function(img, quad, x, y, ...)
    if img == atlas then draws[#draws + 1] = { x = x, y = y } end
    return orig(img, quad, x, y, ...)
  end

  -- Camera at 0,0; entity at map px (32, 40); feet strip py+4 = 44.
  world:drawGrassOverCrystal(
    { px = 32, py = 40, inGrass = true, grassShake = false, moving = false },
    0, 0, 1)
  check(#draws > 0, "grass overdraw blits when entity is off map origin")
  eq(draws[1].x, 32, "blit x uses absolute map pixel tx")
  check(draws[1].y >= 40 and draws[1].y < 52,
    "blit y is tile-aligned under the feet strip, not stuck at oy")
  check(draws[1].y ~= 0, "blit y is not the pre-fix map-origin bug")

  love.graphics.draw = orig
end

-- OAM row split works on standing sheets (frames = 1, height = 16).
do
  local SpriteRenderer = require("src.render.SpriteRenderer")
  local calls = {}
  local orig = love.graphics.draw
  love.graphics.draw = function(_, quad, x, y)
    calls[#calls + 1] = { x = x, y = y, quad = quad }
    return orig(_, quad, x, y)
  end
  local sr = SpriteRenderer.new({
    image = "missing.png", frames = 1, frameWidth = 16, frameHeight = 16,
  })
  sr:draw(0, 16, 0, 0, "down", 0, false, nil, nil, nil, "bottom")
  sr:draw(0, 16, 0, 0, "down", 0, false, nil, nil, nil, "top")
  eq(#calls, 2, "bottom and top OAM rows each draw once")
  check(sr.bottomFrames and sr.bottomFrames[0] ~= nil,
    "bottom OAM uses a dedicated 8 px quad")
  check(sr.halfFrames and sr.halfFrames[0] ~= nil,
    "top OAM uses a dedicated 8 px quad")
  check(calls[1].y > calls[2].y,
    "bottom row draws below the top row (facings.asm y = 8)")
  love.graphics.draw = orig
end

GameVersion.set(priorVersion)

S.finish()
