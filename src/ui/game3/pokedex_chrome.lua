-- Pokédex Chrome loader and authentic rendering engine for FRLG Pokédex.
-- Implements the authentic diamond paper background, header/footer bars,
-- orange section headings, type badges, 2-page cards, and pulsing habitat spotlights.

local Display = require("src.core.game3.display")
local Extract = require("src.import.gba.extract_island1")
local PokedexData = require("src.core.game3.pokedex_data")

local PokedexChrome = {}

PokedexChrome._cache = nil
PokedexChrome._images = {}
PokedexChrome._footprints = {}
PokedexChrome._installed = false
PokedexChrome._animTimer = 0

local function cache_root()
  local okD, Dataset = pcall(require, "src.core.game3.dataset")
  if okD and Dataset and Dataset.mountExtractRoots then
    Dataset.mountExtractRoots()
  end
  return Extract.CACHE_ROOT or "data/generated/gba"
end

local function pokedex_root()
  return cache_root() .. "/pokemon/pokedex"
end

local function read_bytes(rel)
  local okD, Dataset = pcall(require, "src.core.game3.dataset")
  if okD and Dataset and Dataset.cache then
    local d = Dataset.cache():read(rel)
    if type(d) == "string" and #d > 0 then return d end
  end
  local ok, CacheFs = pcall(require, "src.import.CacheFs")
  if ok and CacheFs and CacheFs.readActive then
    local d = CacheFs.readActive(rel)
    if type(d) == "string" and #d > 0 then return d end
  end
  if love and love.filesystem and love.filesystem.read then
    local d = love.filesystem.read(rel)
    if type(d) == "string" and #d > 0 then return d end
    local alt = "data/generated/gba/" .. (rel:gsub("^data/generated/gba/", ""))
    d = love.filesystem.read(alt)
    if type(d) == "string" and #d > 0 then return d end
  end
  local candidates = {
    rel,
    "data/generated/gba/" .. (rel:gsub("^data/generated/gba/", "")),
  }
  for _, p in ipairs(candidates) do
    local f = io.open(p, "rb")
    if f then
      local d = f:read("*a")
      f:close()
      if d and #d > 0 then return d end
    end
  end
  return nil
end

local function rgba_to_image(rgba, w, h, transparentKey)
  if not (love and love.image and love.graphics) then return nil end
  if not rgba or #rgba < w * h * 4 then return nil end

  local imageData = love.image.newImageData(w, h)
  local i = 1
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local r = (rgba:byte(i) or 0) / 255
      local g = (rgba:byte(i + 1) or 0) / 255
      local b = (rgba:byte(i + 2) or 0) / 255
      local a = (rgba:byte(i + 3) or 0) / 255
      if transparentKey and transparentKey(rgba:byte(i) or 0, rgba:byte(i + 1) or 0, rgba:byte(i + 2) or 0) then
        a = 0
      end
      imageData:setPixel(x, y, r, g, b, a)
      i = i + 4
    end
  end

  local image = love.graphics.newImage(imageData)
  if image.setFilter then image:setFilter("nearest", "nearest") end
  return image
end

function PokedexChrome.install(cache)
  if PokedexChrome._installed and not cache then return true end
  PokedexData.init()

  local root = pokedex_root()

  local textures = {
    { key = "paper_bg", file = "paper_bg.rgba", w = 240, h = 160 },
    { key = "caught_marker", file = "caught_marker.rgba", w = 8, h = 8 },
    { key = "mini_page", file = "mini_page.rgba", w = 64, h = 40 },
    { key = "blit_wide_ellipse", file = "blit_wide_ellipse.rgba", w = 88, h = 16 },
    { key = "map_kanto", file = "map_kanto.rgba", w = 96, h = 72 },
    { key = "map_one_island", file = "map_one_island.rgba", w = 32, h = 24 },
    { key = "map_two_island", file = "map_two_island.rgba", w = 32, h = 24 },
    { key = "map_three_island", file = "map_three_island.rgba", w = 32, h = 24 },
    { key = "map_four_island", file = "map_four_island.rgba", w = 32, h = 32 },
    { key = "map_five_island", file = "map_five_island.rgba", w = 32, h = 32 },
    { key = "map_six_island", file = "map_six_island.rgba", w = 32, h = 32 },
    { key = "map_seven_island", file = "map_seven_island.rgba", w = 32, h = 32 },
    { key = "cat_grassland", file = "cat_icon_grassland.rgba", w = 64, h = 48 },
    { key = "cat_forest", file = "cat_icon_forest.rgba", w = 64, h = 48 },
    { key = "cat_waters_edge", file = "cat_icon_waters_edge.rgba", w = 64, h = 48 },
    { key = "cat_sea", file = "cat_icon_sea.rgba", w = 64, h = 48 },
    { key = "cat_cave", file = "cat_icon_cave.rgba", w = 64, h = 48 },
    { key = "cat_mountain", file = "cat_icon_mountain.rgba", w = 64, h = 48 },
    { key = "cat_rough_terrain", file = "cat_icon_rough_terrain.rgba", w = 64, h = 48 },
    { key = "cat_urban", file = "cat_icon_urban.rgba", w = 64, h = 48 },
    { key = "cat_rare", file = "cat_icon_rare.rgba", w = 64, h = 48 },
    { key = "cat_numerical", file = "cat_icon_numerical.rgba", w = 64, h = 48 },
    { key = "cat_atoz", file = "cat_icon_abc.rgba", w = 64, h = 48 },
    { key = "cat_type", file = "cat_icon_type.rgba", w = 64, h = 48 },
    { key = "cat_lightest", file = "cat_icon_lightest.rgba", w = 64, h = 48 },
    { key = "cat_smallest", file = "cat_icon_smallest.rgba", w = 64, h = 48 },
    { key = "cat_cancel", file = "cat_icon_cancel.rgba", w = 64, h = 48 },
    { key = "cat_qmark", file = "cat_icon_qmark.rgba", w = 64, h = 48 },
    { key = "marker_0", file = "marker_0.rgba", w = 8, h = 8 },
    { key = "marker_1", file = "marker_1.rgba", w = 16, h = 8 },
    { key = "marker_2", file = "marker_2.rgba", w = 8, h = 16 },
    { key = "marker_3", file = "marker_3.rgba", w = 32, h = 16 },
    { key = "marker_4", file = "marker_4.rgba", w = 16, h = 32 },
    { key = "marker_5", file = "marker_5.rgba", w = 32, h = 16 },
    { key = "marker_6", file = "marker_6.rgba", w = 16, h = 32 },
  }

  for _, t in ipairs(textures) do
    local bytes = read_bytes(root .. "/" .. t.file)
    if bytes then
      PokedexChrome._images[t.key] = rgba_to_image(bytes, t.w, t.h, t.trans)
    end
  end

  local sheets = {
    { key = "kanto", file = "dex_tiles_kanto.rgba" },
    { key = "national", file = "dex_tiles_national.rgba" },
  }
  PokedexChrome._sheets = {}
  for _, s in ipairs(sheets) do
    PokedexChrome._sheets[s.key] = read_bytes(root .. "/" .. s.file)
    PokedexChrome._images["dex_data_bg_" .. s.key] = nil
    PokedexChrome._images["dex_area_bg_" .. s.key] = nil
  end

  PokedexChrome._images.trainer_red = nil
  PokedexChrome._images.trainer_leaf = nil
  PokedexChrome._colors = nil
  local colorBytes = read_bytes(root .. "/chrome.lua")
  if colorBytes then
    local chunk = loadstring and loadstring(colorBytes) or load(colorBytes)
    if chunk then
      local ok, tbl = pcall(chunk)
      if ok and type(tbl) == "table" then PokedexChrome._colors = tbl end
    end
  end

  PokedexChrome._installed = true
  return true
end

function PokedexChrome.getImage(key)
  if not PokedexChrome._installed then PokedexChrome.install() end
  return PokedexChrome._images[key]
end

function PokedexChrome.getColor(key)
  if not PokedexChrome._installed then PokedexChrome.install() end
  local c = PokedexChrome._colors and PokedexChrome._colors[key]
  if type(c) ~= "table" or not c[3] then return nil end
  return c[1] / 255, c[2] / 255, c[3] / 255, (c[4] or 255) / 255
end

-- src/pokedex_area_markers.c:219
function PokedexChrome.getMarkerBlend()
  if not PokedexChrome._installed then PokedexChrome.install() end
  local c = PokedexChrome._colors and PokedexChrome._colors.marker_blend
  if type(c) ~= "table" or not c[2] then return nil end
  return c[1] / 16, c[2] / 16
end

function PokedexChrome.measureControlInfo(str)
  return require("src.ui.game3.frlg_font").measure(str, { small = true })
end

--- Draw control info text right-aligned ending at rightX (default 236), at y (default 146)
function PokedexChrome.drawControlInfo(str, rightX, y)
  rightX = rightX or 236
  y = y or 146
  local totalW = PokedexChrome.measureControlInfo(str)
  local startX = rightX - totalW
  PokedexChrome.drawControlInfoLeft(str, startX, y)
end

local CONTROL_INFO_COLORS = { fg = { 1, 1, 1, 1 }, shadow = { 98/255, 98/255, 98/255, 1 } }

--- Draw control info text left-aligned starting at startX, at y (default 146)
function PokedexChrome.drawControlInfoLeft(str, startX, y)
  require("src.ui.game3.frlg_font").draw(str, startX, y or 146, {
    small = true,
    colors = CONTROL_INFO_COLORS,
  })
end

function PokedexChrome.getEntry(speciesId)
  return PokedexData.getEntry(speciesId)
end

-- src/pokedex_screen.c:924 natDex palette, :1161 FillWindowPixelBuffer(0, PIXEL_FILL(15))
function PokedexChrome.drawBars()
  local variant = PokedexData.isNationalUnlocked() and "national" or "kanto"
  local r, g, b = PokedexChrome.getColor("bar_" .. variant)
  if not r then
    error("PokedexChrome: chrome.lua has no bar_" .. variant .. " color", 0)
  end
  love.graphics.setColor(r, g, b, 1)
  love.graphics.rectangle("fill", 0, 0, 240, 16)
  love.graphics.rectangle("fill", 0, 144, 240, 16)
  love.graphics.setColor(1, 1, 1, 1)
end

function PokedexChrome.drawPaperBg()
  if not (love and love.graphics) then return end
  local img = PokedexChrome.getImage("paper_bg")
  if not img then
    error("PokedexChrome: paper_bg.rgba is not in the cache", 0)
  end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, 0, 0)
  PokedexChrome.drawBars()
end

local CARD_SHEET_COLS = 8

local function card_layout(left, top, width, height, divTile)
  local L = {
    left = left, top = top, width = width, height = height,
    divTile = divTile,
    x = left * 8,
    y = top * 8,
    w = (width + 2) * 8,
    h = (height + 2) * 8,
    borderLeft = left * 8 + 1,
    borderRight = (left + 1 + width) * 8 + 5,
    borderTop = top * 8 + 1,
    borderBottom = (top + 1 + height) * 8 + 5,
    borderThickness = 2,
  }
  if divTile then
    L.dividerY = divTile * 8
    L.upperY = L.borderTop + 2
    L.upperH = L.dividerY - L.upperY
    L.lowerY = L.dividerY + 8
    L.lowerH = L.borderBottom - L.lowerY
  else
    L.upperY = L.borderTop + 2
    L.upperH = L.borderBottom - L.upperY
  end
  return L
end

-- pokefirered/src/pokedex_screen.c:2926
function PokedexChrome.dataCardLayout()
  local left, top, width, height = 0, 2, 28, 14
  return card_layout(left, top, width, height, (top + 1) + (math.floor(height / 2) + 1))
end

-- pokefirered/src/pokedex_screen.c:2999
function PokedexChrome.areaCardLayout()
  return card_layout(0, 2, 28, 14, nil)
end

-- pokefirered/src/pokedex_screen.c:2641
function PokedexChrome.cardTilemap(L)
  local grid = {}
  local function put(tile, col, row, w, h, flipH, flipV)
    if w <= 0 or h <= 0 then return end
    for r = row, row + h - 1 do
      grid[r] = grid[r] or {}
      for c = col, col + w - 1 do
        grid[r][c] = { tile = tile, flipH = flipH or false, flipV = flipV or false }
      end
    end
  end

  local left, top, width, height = L.left, L.top, L.width, L.height
  local right = left + 1 + width
  local bottom = top + 1 + height

  if L.divTile then
    local divY = L.divTile
    put(4, left, top, 1, 1)
    put(5, left + 1, top, width, 1)
    put(4, right, top, 1, 1, true, false)
    put(10, left, bottom, 1, 1)
    put(11, left + 1, bottom, width, 1)
    put(10, right, bottom, 1, 1, true, false)
    put(6, left, top + 1, 1, divY - top - 1)
    put(7, left, divY, 1, 1)
    put(9, left, divY + 1, 1, top + height - divY)
    put(6, right, top + 1, 1, divY - top - 1, true, false)
    put(7, right, divY, 1, 1, true, false)
    put(9, right, divY + 1, 1, top + height - divY, true, false)
    put(1, left + 1, top + 1, width, divY - top - 1)
    put(8, left + 1, divY, width, 1)
    put(2, left + 1, divY + 1, width, top + height - divY)
  else
    put(4, left, top, 1, 1)
    put(4, right, top, 1, 1, true, false)
    put(4, left, bottom, 1, 1, false, true)
    put(4, right, bottom, 1, 1, true, true)
    put(5, left + 1, top, width, 1)
    put(5, left + 1, bottom, width, 1, false, true)
    put(6, left, top + 1, 1, height)
    put(6, right, top + 1, 1, height, true, false)
    put(1, left + 1, top + 1, width, height)
  end

  return grid
end

function PokedexChrome.composeCard(L, sheet, w, h)
  w = w or 240
  h = h or 160
  local sheetW = CARD_SHEET_COLS * 8
  if type(sheet) ~= "string" or #sheet < sheetW * 8 * 4 then return nil end
  local sheetTiles = math.floor(#sheet / (sheetW * 8 * 4)) * CARD_SHEET_COLS
  local grid = PokedexChrome.cardTilemap(L)
  local blank = { tile = 0, flipH = false, flipV = false }
  local out = {}
  for py = 0, h - 1 do
    local cols = grid[math.floor(py / 8)]
    local ty = py % 8
    for px = 0, w - 1 do
      local cell = (cols and cols[math.floor(px / 8)]) or blank
      local tile = cell.tile
      if tile >= sheetTiles then tile = 0 end
      local tx = px % 8
      local sx = (tile % CARD_SHEET_COLS) * 8 + (cell.flipH and (7 - tx) or tx)
      local sy = math.floor(tile / CARD_SHEET_COLS) * 8 + (cell.flipV and (7 - ty) or ty)
      local o = (sy * sheetW + sx) * 4
      out[py * w + px + 1] = sheet:sub(o + 1, o + 4)
    end
  end
  return table.concat(out)
end

-- pokefirered/src/pokedex_screen.c:896
function PokedexChrome.cardSheet()
  if not PokedexChrome._installed then PokedexChrome.install() end
  local sheets = PokedexChrome._sheets or {}
  if PokedexData.isNationalUnlocked() and sheets.national then
    return sheets.national, "national"
  end
  if sheets.kanto then return sheets.kanto, "kanto" end
  return nil
end

local function draw_card(key, layoutFn)
  if not (love and love.graphics) then return end
  local sheet, variant = PokedexChrome.cardSheet()
  local img
  if sheet then
    key = key .. "_" .. variant
    img = PokedexChrome._images[key]
    if not img then
      img = rgba_to_image(PokedexChrome.composeCard(layoutFn(), sheet), 240, 160)
      PokedexChrome._images[key] = img
    end
  end
  if not img then
    error("PokedexChrome: dex_tiles_" .. tostring(variant or "kanto") .. ".rgba is not in the cache", 0)
  end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, 0, 0)
  PokedexChrome.drawBars()
end

function PokedexChrome.drawDataCardBg()
  draw_card("dex_data_bg", PokedexChrome.dataCardLayout)
end

function PokedexChrome.drawAreaCardBg()
  draw_card("dex_area_bg", PokedexChrome.areaCardLayout)
end

-- src/trainer_pokemon_sprites.c:276, include/constants/trainers.h:156
PokedexChrome.TRAINER_PIC_IDS = { male = 135, female = 136 }

--- Load trainer front sprite (Red/Leaf) for Size Comparison
function PokedexChrome.getTrainerPic(gender)
  local key = (gender == "female") and "trainer_leaf" or "trainer_red"
  if PokedexChrome._images[key] == nil then
    local picId = (gender == "female") and PokedexChrome.TRAINER_PIC_IDS.female or PokedexChrome.TRAINER_PIC_IDS.male
    local bytes = read_bytes(cache_root() .. "/trainers/front/" .. picId .. ".rgba")
      or read_bytes("data/generated/gba/trainers/front/" .. picId .. ".rgba")
    PokedexChrome._images[key] = bytes and rgba_to_image(bytes, 64, 64) or false
  end
  return PokedexChrome._images[key] or nil
end

--- Draw sprite as solid silhouette with authentic charcoal palette (#4A4A4A)
function PokedexChrome.drawSilhouette(img, x, y, scaleX, scaleY, originX, originY)
  if not (love and love.graphics and img) then return end
  scaleX = scaleX or 1
  scaleY = scaleY or scaleX
  originX = originX or 0
  originY = originY or 0

  if not PokedexChrome._silhouetteShader then
    local ok, shader = pcall(love.graphics.newShader, [[
      vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
        vec4 texcolor = Texel(texture, texture_coords);
        if (texcolor.a > 0.0) {
          return color;
        }
        return vec4(0.0);
      }
    ]])
    if ok and shader then
      PokedexChrome._silhouetteShader = shader
    end
  end

  if PokedexChrome._silhouetteShader then
    love.graphics.setShader(PokedexChrome._silhouetteShader)
  end
  local sr, sg, sb = PokedexChrome.getColor("silhouette")
  love.graphics.setColor(sr or 74 / 255, sg or 74 / 255, sb or 74 / 255, 1)
  love.graphics.draw(img, x, y, 0, scaleX, scaleY, originX, originY)
  if PokedexChrome._silhouetteShader then
    love.graphics.setShader()
  end
  love.graphics.setColor(1, 1, 1, 1)
end

--- Draw Top Header title with white text and gray shadow (at y=2, centered if x is nil)
function PokedexChrome.drawHeader(title, x, y)
  local FrlgFont = require("src.ui.game3.frlg_font")
  y = y or 2
  if not x then
    local w = FrlgFont.measure(title)
    x = math.floor((240 - w) / 2)
  end
  FrlgFont.draw(title, x, y, {
    colors = { fg = { 1, 1, 1, 1 }, shadow = { 98/255, 98/255, 98/255, 1 } }
  })
end

--- Draw Footer controls text with white text and gray shadow
function PokedexChrome.drawFooter(text, x, y)
  local FrlgFont = require("src.ui.game3.frlg_font")
  x = x or 8
  y = y or 146
  FrlgFont.draw(text, x, y, {
    colors = { fg = { 1, 1, 1, 1 }, shadow = { 98/255, 98/255, 98/255, 1 } }
  })
end

--- Texture quads cache for pokedex
local function get_pokedex_quad(key, x, y, w, h, sw, sh)
  if not (love and love.graphics and love.graphics.newQuad) then return nil end
  if not PokedexChrome._quads then PokedexChrome._quads = {} end
  if not PokedexChrome._quads[key] then
    PokedexChrome._quads[key] = love.graphics.newQuad(x, y, w, h, sw, sh)
  end
  return PokedexChrome._quads[key]
end

--- Load authentic GBA menu_info texture containing all 18 type badges & caught ball
function PokedexChrome.menuInfoImage()
  if PokedexChrome._menuInfo then return PokedexChrome._menuInfo end
  local ok, SummaryChrome = pcall(require, "src.ui.game3.summary_chrome")
  if ok and SummaryChrome and SummaryChrome.menuInfoImage then
    PokedexChrome._menuInfo = SummaryChrome.menuInfoImage()
    if PokedexChrome._menuInfo then return PokedexChrome._menuInfo end
  end
  return nil
end

--- Type badge mapping in menu_info.png (128x128)
local TYPE_RECTS = {
  [0]  = { x = 0,  y = 16, w = 32, h = 12 },  -- NORMAL
  [1]  = { x = 32, y = 48, w = 32, h = 12 },  -- FIGHTING
  [2]  = { x = 0,  y = 48, w = 32, h = 12 },  -- FLYING
  [3]  = { x = 0,  y = 64, w = 32, h = 12 },  -- POISON
  [4]  = { x = 64, y = 32, w = 32, h = 12 },  -- GROUND
  [5]  = { x = 32, y = 32, w = 32, h = 12 },  -- ROCK
  [6]  = { x = 96, y = 48, w = 32, h = 12 },  -- BUG
  [7]  = { x = 64, y = 48, w = 32, h = 12 },  -- GHOST
  [8]  = { x = 64, y = 64, w = 32, h = 12 },  -- STEEL
  [9]  = { x = 32, y = 80, w = 32, h = 12 },  -- MYSTERY
  [10] = { x = 32, y = 16, w = 32, h = 12 },  -- FIRE
  [11] = { x = 64, y = 16, w = 32, h = 12 },  -- WATER
  [12] = { x = 96, y = 16, w = 32, h = 12 },  -- GRASS
  [13] = { x = 0,  y = 32, w = 32, h = 12 },  -- ELECTRIC
  [14] = { x = 32, y = 64, w = 32, h = 12 },  -- PSYCHIC
  [15] = { x = 96, y = 32, w = 32, h = 12 },  -- ICE
  [16] = { x = 0,  y = 80, w = 32, h = 12 },  -- DRAGON
  [17] = { x = 96, y = 64, w = 32, h = 12 },  -- DARK
}

--- Draw authentic flat orange down scroll arrow (secondArrowType in pret)
function PokedexChrome.drawDownArrow(x, y)
  if not (love and love.graphics) then return end
  x = x or 200
  y = y or 141
  local bob = math.floor(math.sin(PokedexChrome._animTimer * 4) * 1.5 + 0.5)

  -- Dark coral/red outline
  love.graphics.setColor(205/255, 65/255, 57/255, 1)
  love.graphics.polygon("fill",
    x - 6, y + bob - 1,
    x + 6, y + bob - 1,
    x, y + 6 + bob + 1
  )
  -- Warm vibrant orange fill
  love.graphics.setColor(255/255, 139/255, 57/255, 1)
  love.graphics.polygon("fill",
    x - 5, y + bob,
    x + 5, y + bob,
    x, y + 6 + bob
  )
  love.graphics.setColor(1, 1, 1, 1)
end

--- Draw authentic flat orange up scroll arrow (firstArrowType in pret)
function PokedexChrome.drawUpArrow(x, y)
  if not (love and love.graphics) then return end
  x = x or 200
  y = y or 19
  local bob = math.floor(math.sin(PokedexChrome._animTimer * 4) * 1.5 + 0.5)

  -- Dark coral/red outline
  love.graphics.setColor(205/255, 65/255, 57/255, 1)
  love.graphics.polygon("fill",
    x - 6, y - bob + 1,
    x + 6, y - bob + 1,
    x, y - 6 - bob - 1
  )
  -- Warm vibrant orange fill
  love.graphics.setColor(255/255, 139/255, 57/255, 1)
  love.graphics.polygon("fill",
    x - 5, y - bob,
    x + 5, y - bob,
    x, y - 6 - bob
  )
  love.graphics.setColor(1, 1, 1, 1)
end

--- Draw bouncing horizontal side arrow (left or right)
function PokedexChrome.drawSideArrow(dir, x, y)
  if not (love and love.graphics) then return end
  local bob = math.floor(math.sin(PokedexChrome._animTimer * 4) * 1.5 + 0.5)

  love.graphics.setColor(232/255, 72/255, 32/255, 1)
  if dir == "right" or dir == 1 then
    love.graphics.polygon("fill",
      x + bob, y,
      x + 6 + bob, y + 5,
      x + bob, y + 10
    )
  else
    love.graphics.polygon("fill",
      x + 6 - bob, y,
      x - bob, y + 5,
      x + 6 - bob, y + 10
    )
  end
  love.graphics.setColor(1, 1, 1, 1)
end

--- Draw authentic caught Poké Ball marker icon at (x, y) (8x8 from caught_marker.rgba)
function PokedexChrome.drawCaughtMarker(x, y)
  if not (love and love.graphics) then return end
  local img = PokedexChrome.getImage("caught_marker")
  if img then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(img, x, y)
    return
  end
  local mi = PokedexChrome.menuInfoImage()
  if mi then
    local q = get_pokedex_quad("caught_ball", 0, 0, 12, 12, 128, 128)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(mi, q, x - 2, y - 2)
    return
  end
end

--- Draw authentic Type Badge (32x12 from ROM menu_info)
function PokedexChrome.drawTypeBadge(typeId, x, y)
  if not (love and love.graphics and typeId) then return end
  typeId = tonumber(typeId)
  local rect = assert(TYPE_RECTS[typeId], "type id")
  local img = assert(PokedexChrome.menuInfoImage(), "menu_info")
  local q = get_pokedex_quad("type_" .. typeId, rect.x, rect.y, rect.w, rect.h, 128, 128)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, q, x, y)
end

--- Draw category icon (64x48)
function PokedexChrome.drawCategoryIcon(catKey, x, y, scale)
  scale = scale or 1
  local key = "cat_" .. tostring(catKey or "qmark")
  local img = PokedexChrome.getImage(key) or PokedexChrome.getImage("cat_qmark")
  if img and love and love.graphics then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(img, x, y, 0, scale, scale)
  end
end

--- Draw Town Map (96x72)
function PokedexChrome.drawMap(mapKey, x, y, scale)
  scale = scale or 1
  local key = "map_" .. tostring(mapKey or "kanto")
  local img = PokedexChrome.getImage(key) or PokedexChrome.getImage("map_kanto")
  if img and love and love.graphics then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(img, x, y, 0, scale, scale)
  end
end

local AREA_MARKER_KEYS = {
  MARKER_CIRCULAR = "marker_0",
  MARKER_SMALL_H = "marker_1",
  MARKER_SMALL_V = "marker_2",
  MARKER_MED_H = "marker_3",
  MARKER_MED_V = "marker_4",
  MARKER_LARGE_H = "marker_5",
  MARKER_LARGE_V = "marker_6",
}

local function paint_area_marker(img, x, y)
  if img then
    love.graphics.draw(img, x, y)
  else
    love.graphics.ellipse("fill", x + 4, y + 4, 4, 4)
  end
end

--- Draw Area Route Marker (Steady slightly transparent red overlay)
function PokedexChrome.drawAreaMarker(shape, x, y)
  if not (love and love.graphics) then return end

  local img = PokedexChrome.getImage(AREA_MARKER_KEYS[shape] or "marker_0")
  local mr, mg, mb, ma = PokedexChrome.getColor("marker")
  local eva, evb = PokedexChrome.getMarkerBlend()
  if mr and eva then
    -- src/pokedex_area_markers.c:219
    local mode, alphaMode = love.graphics.getBlendMode()
    love.graphics.setColor(0, 0, 0, 1 - evb)
    paint_area_marker(img, x, y)
    love.graphics.setBlendMode("add", "alphamultiply")
    love.graphics.setColor(mr * eva, mg * eva, mb * eva, 1)
    paint_area_marker(img, x, y)
    love.graphics.setBlendMode(mode, alphaMode)
  else
    love.graphics.setColor(mr or 1, mg or 0.3, mb or 0.3, ma or 0.75)
    paint_area_marker(img, x, y)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- pokefirered/src/pokedex_screen.c:2901
function PokedexChrome.footprintSource(speciesId)
  local rel = pokedex_root() .. "/footprints/" .. tonumber(speciesId) .. ".rgba"
  local bytes = read_bytes(rel)
  if bytes then return bytes, rel end
  return nil, nil
end

--- Draw Footprint (16x16, black footprint on transparent background)
function PokedexChrome.drawFootprint(speciesId, x, y, scale)
  if not (love and love.graphics) then return end
  scale = scale or 1
  local sp = tonumber(speciesId) or 1

  if not PokedexChrome._footprints[sp] then
    local bytes = PokedexChrome.footprintSource(sp)
    if bytes then
      local img = rgba_to_image(bytes, 16, 16)
      if img then
        PokedexChrome._footprints[sp] = img
      end
    end
  end

  local img = PokedexChrome._footprints[sp]
  if img then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(img, x, y, 0, scale, scale)
  end
end

--- Draw Authentic Fixed-Radius Spotlight Disc with Pret Palette Pulsing Animation
function PokedexChrome.drawHabitatSpotlight(cx, cy, radius, timer, isSelected)
  if not (love and love.graphics) then return end
  radius = radius or 32
  timer = timer or 0
  if isSelected == nil then isSelected = true end

  local mainCol, rimCol
  if not isSelected then
    mainCol = { 197/255, 181/255, 140/255, 1 }
    rimCol  = { 214/255, 197/255, 165/255, 1 }
  else
    -- Fades between darkish warm brown (#C5B58C / #D6A57B) and authentic vibrant red/coral (#F7846B)
    -- Matching pret sDexScreen_CategoryCursorPals
    local t = (math.sin(timer * 4) + 1) * 0.5 -- 0.0 to 1.0
    local r = (197 + (247 - 197) * t) / 255
    local g = (181 + (132 - 181) * t) / 255
    local b = (140 + (107 - 140) * t) / 255
    mainCol = { r, g, b, 1 }

    local rRim = (214 + (239 - 214) * t) / 255
    local gRim = (197 + (173 - 197) * t) / 255
    local bRim = (165 + (148 - 165) * t) / 255
    rimCol = { rRim, gRim, bRim, 1 }
  end

  -- Fixed radius circle with subtle shaded rim (no growing/shrinking)
  love.graphics.setColor(rimCol)
  love.graphics.circle("fill", cx, cy, radius)
  love.graphics.setColor(mainCol)
  love.graphics.circle("fill", cx, cy, radius - 2)
  love.graphics.setColor(1, 1, 1, 1)
end

--- Draw Authentic Mini Page Card for Habitat View (64x40)
function PokedexChrome.drawMiniCard(speciesId, x, y, isCaught, isSeen, isSelected)
  if not (love and love.graphics) then return end
  local FrlgFont = require("src.ui.game3.frlg_font")
  local Pokemon = require("src.core.game3.pokemon")

  local sp = tonumber(speciesId) or 1
  local natId = Pokemon.national(sp) or 0
  local name = isSeen and Pokemon.name(sp) or "----------"

  -- Draw authentic 64x40 mini page background (white top, brown dividing line, beige bottom with simulated text)
  local bg = PokedexChrome.getImage("mini_page")
  if bg then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(bg, x, y)
  else
    -- Fallback card chassis
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", x, y, 64, 40, 2, 2)
    love.graphics.setColor(200/255, 136/255, 112/255, 1)
    love.graphics.rectangle("line", x, y, 64, 40, 2, 2)
  end

  -- Selection highlight outline
  if isSelected then
    love.graphics.setColor(247/255, 132/255, 107/255, 1)
    love.graphics.rectangle("line", x, y, 64, 40, 2, 2)
  end

  -- Top Row: Caught Pokéball (8x8) at (x + 2, y + 3)
  if isCaught then
    PokedexChrome.drawCaughtMarker(x + 2, y + 3)
  end

  -- Top Row: №xxx at (x + 12, y + 0) in FONT_SMALL
  local textColors = { fg = { 0x18/255, 0x18/255, 0x18/255, 1 }, shadow = { 0xD0/255, 0xC8/255, 0xB0/255, 1 } }
  FrlgFont.draw(string.format("№%03d", natId), x + 12, y, {
    small = true,
    colors = textColors,
  })

  -- Mid Row: Species Name at (x + 2, y + 13) in FONT_NORMAL
  FrlgFont.draw(name, x + 2, y + 13, {
    colors = textColors,
  })

  love.graphics.setColor(1, 1, 1, 1)
end

return PokedexChrome
