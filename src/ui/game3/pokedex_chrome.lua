-- Pokédex Chrome loader and authentic rendering engine for FRLG Pokédex.
-- Implements the authentic diamond paper background, khaki header/footer bars,
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

local TYPE_COLORS = {
  NORMAL = { 168/255, 168/255, 120/255, 1 },
  FIRE = { 240/255, 128/255, 48/255, 1 },
  WATER = { 104/255, 144/255, 240/255, 1 },
  GRASS = { 120/255, 200/255, 80/255, 1 },
  ELECTRIC = { 248/255, 208/255, 48/255, 1 },
  ICE = { 152/255, 216/255, 216/255, 1 },
  FIGHTING = { 192/255, 48/255, 40/255, 1 },
  POISON = { 160/255, 64/255, 160/255, 1 },
  GROUND = { 224/255, 192/255, 104/255, 1 },
  FLYING = { 168/255, 144/255, 240/255, 1 },
  PSYCHIC = { 248/255, 88/255, 136/255, 1 },
  BUG = { 168/255, 184/255, 32/255, 1 },
  ROCK = { 184/255, 160/255, 56/255, 1 },
  GHOST = { 112/255, 88/255, 152/255, 1 },
  DRAGON = { 112/255, 56/255, 248/255, 1 },
  STEEL = { 184/255, 184/255, 208/255, 1 },
  DARK = { 112/255, 88/255, 72/255, 1 },
  FAIRY = { 238/255, 153/255, 172/255, 1 },
}

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
    { key = "caught_marker", file = "caught_marker.rgba", w = 8, h = 8, trans = function(r, g, b) return (r == 156 and g == 156 and b == 189) or (r == 156 and g == 156) end },
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

  local kpBytes = read_bytes("data/generated/gba/keypad_icons.rgba")
  if kpBytes then
    PokedexChrome._images["keypad_icons"] = rgba_to_image(kpBytes, 128, 32)
  end

  PokedexChrome._installed = true
  return true
end

function PokedexChrome.getImage(key)
  if not PokedexChrome._installed then PokedexChrome.install() end
  return PokedexChrome._images[key]
end

local KEYPAD_ICON_QUADS = nil

--- Draw authentic GBA keypad button icon (A, B, L, R, START, SELECT, DPAD_UPDOWN, DPAD_LEFTRIGHT)
function PokedexChrome.drawKeypadIcon(iconName, x, y)
  if not (love and love.graphics and iconName) then return end
  local img = PokedexChrome.getImage("keypad_icons")
  if not img then
    -- Try rgba files (written by TextChromeExtract.extractKeypadIcons)
    local rgba_candidates = {
      "data/generated/gba/keypad_icons.rgba",
      "data/generated/gba/chrome/keypad_icons.rgba",
      "data/generated/gba/chrome/fonts/keypad_icons.rgba",
    }
    for _, p in ipairs(rgba_candidates) do
      local d
      local okC, CacheFs = pcall(require, "src.import.CacheFs")
      if okC and CacheFs and CacheFs.readActive then d = CacheFs.readActive(p) end
      if not d or #d == 0 then
        if love and love.filesystem then
          d = love.filesystem.read(p)
        end
      end
      if d and #d > 0 then
        local kpImg = rgba_to_image(d, 128, 32)
        if kpImg then
          img = kpImg
          PokedexChrome._images["keypad_icons"] = img
          break
        end
      end
    end
  end
  if not img then
    local candidates = {
      "chrome/keypad_icons.png",
      "data/generated/gba/chrome/keypad_icons.png",
    }
    for _, p in ipairs(candidates) do
      local ok, newImg = pcall(love.graphics.newImage, p)
      if ok and newImg then
        if newImg.setFilter then newImg:setFilter("nearest", "nearest") end
        img = newImg
        PokedexChrome._images["keypad_icons"] = img
        break
      end
    end
  end

  if img then
    if not KEYPAD_ICON_QUADS then
      local iw, ih = img:getDimensions()
      KEYPAD_ICON_QUADS = {
        a = love.graphics.newQuad(0, 0, 8, 12, iw, ih),
        a_button = love.graphics.newQuad(0, 0, 8, 12, iw, ih),
        b = love.graphics.newQuad(8, 0, 8, 12, iw, ih),
        b_button = love.graphics.newQuad(8, 0, 8, 12, iw, ih),
        l = love.graphics.newQuad(16, 0, 16, 12, iw, ih),
        r = love.graphics.newQuad(32, 0, 16, 12, iw, ih),
        start = love.graphics.newQuad(48, 0, 24, 12, iw, ih),
        select = love.graphics.newQuad(72, 0, 24, 12, iw, ih),
        dpad_up = love.graphics.newQuad(96, 0, 8, 12, iw, ih),
        dpad_down = love.graphics.newQuad(104, 0, 8, 12, iw, ih),
        dpad_left = love.graphics.newQuad(112, 0, 8, 12, iw, ih),
        dpad_right = love.graphics.newQuad(120, 0, 8, 12, iw, ih),
        dpad_updown = love.graphics.newQuad(0, 16, 8, 12, iw, ih),
        dpad_ud = love.graphics.newQuad(0, 16, 8, 12, iw, ih),
        dpad_leftright = love.graphics.newQuad(8, 16, 8, 12, iw, ih),
        dpad_lr = love.graphics.newQuad(8, 16, 8, 12, iw, ih),
      }
    end
    local q = KEYPAD_ICON_QUADS[iconName:lower()]
    if q then
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(img, q, x, y)
      return
    end
  end
end

local ICON_TAG_MAP = {
  ["{DPAD_UPDOWN}"] = { icon = "dpad_updown", w = 8 },
  ["{DPAD_UD}"] = { icon = "dpad_updown", w = 8 },
  ["{DPAD_LEFTRIGHT}"] = { icon = "dpad_leftright", w = 8 },
  ["{DPAD_LR}"] = { icon = "dpad_leftright", w = 8 },
  ["{DPAD_UP}"] = { icon = "dpad_up", w = 8 },
  ["{DPAD_DOWN}"] = { icon = "dpad_down", w = 8 },
  ["{DPAD_LEFT}"] = { icon = "dpad_left", w = 8 },
  ["{DPAD_RIGHT}"] = { icon = "dpad_right", w = 8 },
  ["{A_BUTTON}"] = { icon = "a", w = 8 },
  ["{B_BUTTON}"] = { icon = "b", w = 8 },
  ["{L_BUTTON}"] = { icon = "l", w = 16 },
  ["{R_BUTTON}"] = { icon = "r", w = 16 },
  ["{START_BUTTON}"] = { icon = "start", w = 24 },
  ["{SELECT_BUTTON}"] = { icon = "select", w = 24 },
}

--- Measure total width of control info string containing icon tags and small font text
function PokedexChrome.measureControlInfo(str)
  local FrlgFont = require("src.ui.game3.frlg_font")
  local totalW = 0
  local pos = 1
  local len = #str
  while pos <= len do
    local tag = str:match("^{[^}]+}", pos)
    if tag and ICON_TAG_MAP[tag] then
      totalW = totalW + ICON_TAG_MAP[tag].w
      pos = pos + #tag
    else
      local nextTagStart = str:find("{", pos)
      local textChunk
      if nextTagStart then
        textChunk = str:sub(pos, nextTagStart - 1)
        pos = nextTagStart
      else
        textChunk = str:sub(pos)
        pos = len + 1
      end
      if #textChunk > 0 then
        totalW = totalW + FrlgFont.measure(textChunk, { small = true })
      end
    end
  end
  return totalW
end

--- Draw control info text right-aligned ending at rightX (default 236), at y (default 146)
function PokedexChrome.drawControlInfo(str, rightX, y)
  rightX = rightX or 236
  y = y or 146
  local totalW = PokedexChrome.measureControlInfo(str)
  local startX = rightX - totalW
  PokedexChrome.drawControlInfoLeft(str, startX, y)
end

--- Draw control info text left-aligned starting at startX, at y (default 146)
function PokedexChrome.drawControlInfoLeft(str, startX, y)
  local FrlgFont = require("src.ui.game3.frlg_font")
  y = y or 146
  local curX = startX
  local pos = 1
  local len = #str
  local colors = { fg = { 1, 1, 1, 1 }, shadow = { 98/255, 98/255, 98/255, 1 } }

  while pos <= len do
    local tag = str:match("^{[^}]+}", pos)
    if tag and ICON_TAG_MAP[tag] then
      local info = ICON_TAG_MAP[tag]
      PokedexChrome.drawKeypadIcon(info.icon, curX, y)
      curX = curX + info.w
      pos = pos + #tag
    else
      local nextTagStart = str:find("{", pos)
      local textChunk
      if nextTagStart then
        textChunk = str:sub(pos, nextTagStart - 1)
        pos = nextTagStart
      else
        textChunk = str:sub(pos)
        pos = len + 1
      end
      if #textChunk > 0 then
        FrlgFont.draw(textChunk, curX, y, {
          small = true,
          colors = colors,
        })
        curX = curX + FrlgFont.measure(textChunk, { small = true })
      end
    end
  end
end

function PokedexChrome.getEntry(speciesId)
  return PokedexData.getEntry(speciesId)
end

--- Draw authentic FRLG cream diamond paper background with khaki top/bottom bars (no dark dividing lines)
function PokedexChrome.drawPaperBg(w, h)
  if not (love and love.graphics) then return end
  w = w or Display.W or 240
  h = h or Display.H or 160

  local img = PokedexChrome.getImage("paper_bg")
  if img then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(img, 0, 0)
    return
  end

  -- Procedural Diamond Paper Pattern Fallback
  love.graphics.setColor(246/255, 246/255, 238/255, 1)
  love.graphics.rectangle("fill", 0, 0, w, h)

  love.graphics.setColor(255/255, 255/255, 255/255, 0.6)
  for y = 16, h - 16, 8 do
    for x = 0, w, 8 do
      if ((x + y) / 8) % 2 == 0 then
        love.graphics.rectangle("fill", x, y, 4, 4)
      end
    end
  end

  -- Top bar (y=0..16) and Bottom bar (y=144..160) seamlessly meeting paper bg
  love.graphics.setColor(213/255, 197/255, 164/255, 1)
  love.graphics.rectangle("fill", 0, 0, w, 16)
  love.graphics.rectangle("fill", 0, 144, w, 16)

  love.graphics.setColor(1, 1, 1, 1)
end

--- Draw authentic FRLG Pokédex Detailed Data Screen card background (240x160)
function PokedexChrome.drawDataCardBg()
  if not (love and love.graphics) then return end
  local img = PokedexChrome.getImage("dex_data_bg")
  if not img then
    local candidates = {
      "pokemon/pokedex/dex_data_bg.png",
      "data/generated/gba/pokemon/pokedex/dex_data_bg.png",
    }
    for _, p in ipairs(candidates) do
      local ok, newImg = pcall(love.graphics.newImage, p)
      if ok and newImg then
        if newImg.setFilter then newImg:setFilter("nearest", "nearest") end
        img = newImg
        PokedexChrome._images["dex_data_bg"] = img
        break
      end
    end
  end

  if img then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(img, 0, 0)
    return
  end

  -- Fallback if image not found
  PokedexChrome.drawPaperBg()
end

--- Draw authentic FRLG Pokédex Page 2 Area & Size Screen card background (240x160)
function PokedexChrome.drawAreaCardBg()
  if not (love and love.graphics) then return end
  local img = PokedexChrome.getImage("dex_area_bg")
  if not img then
    local candidates = {
      "pokemon/pokedex/dex_area_bg.png",
      "data/generated/gba/pokemon/pokedex/dex_area_bg.png",
    }
    for _, p in ipairs(candidates) do
      local ok, newImg = pcall(love.graphics.newImage, p)
      if ok and newImg then
        if newImg.setFilter then newImg:setFilter("nearest", "nearest") end
        img = newImg
        PokedexChrome._images["dex_area_bg"] = img
        break
      end
    end
  end

  if img then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(img, 0, 0)
    return
  end

  -- Fallback if image not found
  PokedexChrome.drawPaperBg()
end

--- Load trainer front sprite (Red/Leaf) for Size Comparison
function PokedexChrome.getTrainerPic(gender)
  local key = (gender == "female") and "trainer_leaf" or "trainer_red"
  if not PokedexChrome._images[key] then
    local file = (gender == "female") and "data/generated/gba/trainers/leaf_front_pic.png" or "data/generated/gba/trainers/red_front_pic.png"
    local ok, img = pcall(love.graphics.newImage, file)
    if ok and img then
      if img.setFilter then img:setFilter("nearest", "nearest") end
      PokedexChrome._images[key] = img
    end
  end
  return PokedexChrome._images[key]
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
  love.graphics.setColor(74 / 255, 74 / 255, 74 / 255, 1)
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

local function sanitize_menu_info_imagedata(id)
  if not id or not id.getPixel or not id.setPixel then return id end
  local ok, w, h = pcall(function() return id:getDimensions() end)
  if not ok or not w or not h then return id end
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local r, g, b, a = id:getPixel(x, y)
      if math.abs(r - 123/255) < 0.02 and math.abs(g - 156/255) < 0.02 and math.abs(b - 131/255) < 0.02 then
        id:setPixel(x, y, 1, 1, 1, 0)
      end
    end
  end
  return id
end

--- Load authentic GBA menu_info texture containing all 18 type badges & caught ball
function PokedexChrome.menuInfoImage()
  if PokedexChrome._menuInfo then return PokedexChrome._menuInfo end
  local ok, SummaryChrome = pcall(require, "src.ui.game3.summary_chrome")
  if ok and SummaryChrome and SummaryChrome.menuInfoImage then
    PokedexChrome._menuInfo = SummaryChrome.menuInfoImage()
    if PokedexChrome._menuInfo then return PokedexChrome._menuInfo end
  end
  local paths = {
    "data/generated/gba/pokemon/summary/menu_info.png",
    "src/import/gba/chrome/menus/menu_info.png",
  }
  for _, p in ipairs(paths) do
    local bytes = read_bytes(p)
    if bytes and love and love.image and love.graphics then
      local ok, img = pcall(function()
        local fd = love.filesystem.newFileData(bytes, "menu_info.png")
        local id = sanitize_menu_info_imagedata(love.image.newImageData(fd))
        local image = love.graphics.newImage(id)
        if image.setFilter then image:setFilter("nearest", "nearest") end
        return image
      end)
      if ok and img then
        PokedexChrome._menuInfo = img
        return img
      end
    end
    if love and love.graphics and love.image and love.image.newImageData then
      local ok, img = pcall(function()
        local id = sanitize_menu_info_imagedata(love.image.newImageData(p))
        local image = love.graphics.newImage(id)
        if image.setFilter then image:setFilter("nearest", "nearest") end
        return image
      end)
      if ok and img then
        PokedexChrome._menuInfo = img
        return img
      end
    end
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

local TYPE_NAMES = {
  NORMAL = 0, FIGHTING = 1, FLYING = 2, POISON = 3, GROUND = 4,
  ROCK = 5, BUG = 6, GHOST = 7, STEEL = 8, MYSTERY = 9,
  FIRE = 10, WATER = 11, GRASS = 12, ELECTRIC = 13, PSYCHIC = 14,
  ICE = 15, DRAGON = 16, DARK = 17,
}

--- Draw authentic flat orange down scroll arrow (secondArrowType in pret)
function PokedexChrome.drawDownArrow(x, y)
  if not (love and love.graphics) then return end
  x = x or 200
  y = y or 141
  PokedexChrome._animTimer = (PokedexChrome._animTimer or 0) + 0.05
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
  PokedexChrome._animTimer = (PokedexChrome._animTimer or 0) + 0.05
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
  PokedexChrome._animTimer = (PokedexChrome._animTimer or 0) + 0.05
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
function PokedexChrome.drawTypeBadge(typeNameOrId, x, y)
  if not (love and love.graphics and typeNameOrId) then return end
  local typeId = typeNameOrId
  if type(typeId) == "string" then
    typeId = TYPE_NAMES[typeId:upper()] or 0
  end
  typeId = tonumber(typeId) or 0
  local rect = TYPE_RECTS[typeId] or TYPE_RECTS[0]
  local img = PokedexChrome.menuInfoImage()
  if img then
    local q = get_pokedex_quad("type_" .. typeId, rect.x, rect.y, rect.w, rect.h, 128, 128)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(img, q, x, y)
    return
  end

  local FrlgFont = require("src.ui.game3.frlg_font")
  local tUpper = type(typeNameOrId) == "string" and typeNameOrId:upper() or "NORMAL"
  local col = TYPE_COLORS[tUpper] or { 168/255, 168/255, 120/255, 1 }

  -- Badge background fallback
  love.graphics.setColor(col)
  love.graphics.rectangle("fill", x, y, 32, 11, 2, 2)
  love.graphics.setColor(col[1] * 0.7, col[2] * 0.7, col[3] * 0.7, 1)
  love.graphics.rectangle("line", x, y, 32, 11, 2, 2)
  local txt = tUpper:sub(1, 6)
  local offX = math.floor((32 - (#txt * 5)) / 2)
  FrlgFont.draw(txt, x + math.max(2, offX), y - 1, { color = { 1, 1, 1, 1 } })
  love.graphics.setColor(1, 1, 1, 1)
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

--- Draw Area Route Marker (Static partially transparent red overlay)
function PokedexChrome.drawAreaMarker(shape, x, y)
  if not (love and love.graphics) then return end

  local shapeMap = {
    MARKER_CIRCULAR = "marker_0",
    MARKER_SMALL_H = "marker_1",
    MARKER_SMALL_V = "marker_2",
    MARKER_MED_H = "marker_3",
    MARKER_MED_V = "marker_4",
    MARKER_LARGE_H = "marker_5",
    MARKER_LARGE_V = "marker_6",
  }
  local imgKey = shapeMap[shape] or "marker_0"
  local img = PokedexChrome.getImage(imgKey)

  love.graphics.setColor(1, 0.35, 0.35, 0.75)
  if img then
    love.graphics.draw(img, x, y)
  else
    love.graphics.ellipse("fill", x + 4, y + 4, 4, 4)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

--- Draw Footprint (16x16, black footprint on transparent background)
function PokedexChrome.drawFootprint(speciesId, x, y, scale)
  if not (love and love.graphics) then return end
  scale = scale or 1
  local sp = tonumber(speciesId) or 1
  local Pokemon = require("src.core.game3.pokemon")
  local rawName = Pokemon.name and Pokemon.name(sp) and Pokemon.name(sp):lower()
  local name = rawName and rawName:gsub("[^%w_]", ""):gsub("♀", "_f"):gsub("♂", "_m")

  if not PokedexChrome._footprints[sp] then
    local root = pokedex_root() .. "/footprints"
    local bytes = (name and read_bytes(root .. "/" .. name .. ".rgba"))
      or (rawName and read_bytes(root .. "/" .. rawName .. ".rgba"))
      or read_bytes(root .. "/question_mark.rgba")
      or read_bytes(root .. "/bulbasaur.rgba")
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
  local natId = Pokemon.nationalPokedexNumber and Pokemon.nationalPokedexNumber(sp) or sp
  local name = isSeen and (Pokemon.name and Pokemon.name(sp) or string.format("POKéMON %d", sp)) or "----------"

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

--- Draw Context Action Menu popup modal
function PokedexChrome.drawActionMenu(items, cursor, x, y)
  if not (love and love.graphics) then return end
  local FrlgFont = require("src.ui.game3.frlg_font")

  local itemH = 14
  local menuW = 68
  local menuH = #items * itemH + 8

  -- Window drop shadow
  love.graphics.setColor(0, 0, 0, 0.25)
  love.graphics.rectangle("fill", x + 2, y + 2, menuW, menuH, 3, 3)

  -- Window body (White card with tan/brown border)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", x, y, menuW, menuH, 3, 3)
  love.graphics.setColor(184/255, 152/255, 112/255, 1)
  love.graphics.rectangle("line", x, y, menuW, menuH, 3, 3)

  for i, it in ipairs(items) do
    local rowY = y + 4 + (i - 1) * itemH
    if i == cursor then
      -- Cursor arrow
      love.graphics.setColor(0, 0, 0, 1)
      love.graphics.polygon("fill",
        x + 4, rowY + 3,
        x + 8, rowY + 7,
        x + 4, rowY + 11
      )
    end
    FrlgFont.draw(it.label, x + 12, rowY + 1, { color = { 0.15, 0.15, 0.15, 1 } })
  end

  love.graphics.setColor(1, 1, 1, 1)
end

return PokedexChrome
