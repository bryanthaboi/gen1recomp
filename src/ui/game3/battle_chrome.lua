-- FRLG battle interface chrome (ROM-baked under pokemon/battle/).

local Extract = require("src.import.gba.extract_island1")
local BattleChromeExtract = require("src.import.gba.battle_chrome_extract")

local BattleChrome = {}

BattleChrome._cache = nil
BattleChrome._manifest = nil
BattleChrome._textbox = nil
BattleChrome._playerBox = nil
BattleChrome._enemyBox = nil
BattleChrome._doublesPlayerBox = nil
BattleChrome._doublesOpponentBox = nil
BattleChrome._elements = nil
BattleChrome._partyBar = nil
BattleChrome._terrains = {}
BattleChrome._terrainInfo = {}
BattleChrome._terrainMissing = {}
BattleChrome._logged = false
BattleChrome._quads = {}

local function cache_root()
  return Extract.CACHE_ROOT or "data/generated/gba"
end

local function battle_root()
  return cache_root() .. "/pokemon/battle"
end

local function log(msg)
  if BattleChrome._logged then return end
  BattleChrome._logged = true
  print("[game3/battle_chrome] " .. tostring(msg))
end

local function resolve_cache(cache)
  if cache and cache.read then return cache end
  local okD, Dataset = pcall(require, "src.core.game3.dataset")
  if okD and Dataset and Dataset.cache then
    return Dataset.cache()
  end
  return {
    read = function(_, rel)
      local ok, CacheFs = pcall(require, "src.import.CacheFs")
      if ok and CacheFs and CacheFs.readActive then
        return CacheFs.readActive(rel)
      end
      return nil
    end,
  }
end

local function read_bytes(rel)
  local cache = BattleChrome._cache
  if cache and cache.read then
    local d = cache:read(rel)
    if type(d) == "string" and #d > 0 then return d end
  end
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

local function load_lua(rel)
  local src = read_bytes(rel)
  if not src then return nil end
  local chunk = load(src, "@" .. rel, "t", {})
  if not chunk then return nil end
  local ok, t = pcall(chunk)
  if ok then return t end
  return nil
end

local function rgba_to_image(rgba, w, h)
  if not (love and love.image and love.graphics) then return nil end
  if not rgba or #rgba < w * h * 4 then return nil end
  local ok, imageData = pcall(love.image.newImageData, w, h, "rgba8", rgba)
  if not ok or not imageData then return nil end
  local image = love.graphics.newImage(imageData)
  if image.setFilter then image:setFilter("nearest", "nearest") end
  return image
end

-- pokefirered/src/battle_bg.c:644
function BattleChrome.terrain(key)
  key = tostring(key or "")
  local cache = BattleChrome._terrains
  local hit = rawget(cache, key)
  if hit ~= nil then return hit end
  if BattleChrome._terrainMissing[key] then return nil end
  local info = BattleChrome._terrainInfo and BattleChrome._terrainInfo[key]
  if not info then return nil end
  local root = battle_root()
  local w, h = info.w or 256, info.h or 256
  local img = rgba_to_image(read_bytes(root .. "/" .. (info.file or ("terrain_" .. key .. ".rgba"))), w, h)
  if not img then
    BattleChrome._terrainMissing[key] = true
    return nil
  end
  local entry = {
    image = img,
    bgImage = rgba_to_image(read_bytes(root .. "/terrain_bg_" .. key .. ".rgba"), 256, 160),
    enemyPlat = rgba_to_image(read_bytes(root .. "/terrain_enemy_" .. key .. ".rgba"), 256, 160),
    playerPlat = rgba_to_image(read_bytes(root .. "/terrain_player_" .. key .. ".rgba"), 256, 160),
    w = w,
    h = h,
  }
  rawset(cache, key, entry)
  return entry
end

local TERRAIN_MT = {
  __index = function(_, key) return BattleChrome.terrain(key) end,
}

function BattleChrome.install(cache)
  BattleChrome._cache = resolve_cache(cache)
  BattleChrome._manifest = nil
  BattleChrome._textbox = nil
  BattleChrome._playerBox = nil
  BattleChrome._enemyBox = nil
  BattleChrome._doublesPlayerBox = nil
  BattleChrome._doublesOpponentBox = nil
  BattleChrome._doublesTried = false
  BattleChrome._hpBold = nil
  BattleChrome._hpBoldQuads = {}
  BattleChrome._hpBoldTried = false
  BattleChrome._elements = nil
  BattleChrome._elementsExp = nil
  BattleChrome._partyBar = nil
  BattleChrome._terrains = setmetatable({}, TERRAIN_MT)
  BattleChrome._terrainInfo = {}
  BattleChrome._terrainMissing = {}
  BattleChrome._quads = {}
  BattleChrome._logged = false
  local root = battle_root()
  BattleChrome._manifest = load_lua(root .. "/manifest.lua")
  local m = BattleChrome._manifest or {}
  local tw, th = m.textboxW or 256, m.textboxH or 512
  local tb = read_bytes(root .. "/textbox.rgba")
  local pb = read_bytes(root .. "/healthbox_player.rgba")
  local eb = read_bytes(root .. "/healthbox_enemy.rgba")
  local el = read_bytes(root .. "/elements.rgba")
  local elExp = read_bytes(root .. "/elements_exp.rgba")
  local pbar = read_bytes(root .. "/party_summary_bar.rgba")
  BattleChrome._textbox = rgba_to_image(tb, tw, th)
  BattleChrome._playerBox = rgba_to_image(pb, 128, 64)
  BattleChrome._enemyBox = rgba_to_image(eb, 128, 32)
  BattleChrome._elements = rgba_to_image(el, 320, 24)
  -- EXP bar tiles need healthbox palette (blue); fall back to HP sheet if missing
  BattleChrome._elementsExp = rgba_to_image(elExp, 320, 24) or BattleChrome._elements
  local pinfo = m.partySummaryBar or { w = 128, h = 8 }
  BattleChrome._partyBar = rgba_to_image(pbar, pinfo.w or 128, pinfo.h or 8)
  BattleChrome._terrainInfo = m.terrains or {
    grass = { file = "terrain_grass.rgba", w = m.terrainW or 256, h = m.terrainH or 256 },
  }

  if pb and eb and tb and next(BattleChrome._terrainInfo) then
    log("battle chrome ready (v" .. tostring(m.format or "?") .. ")")
  else
    log("battle chrome missing — re-run --pokemon extract")
  end
end

local function rom_bytes()
  local okP, Pokemon = pcall(require, "src.core.game3.pokemon")
  if okP and Pokemon and type(Pokemon._romBytes) == "string" then return Pokemon._romBytes end
  for _, p in ipairs({ "1636 - Pokemon Fire Red (U)(Squirrels).gba", "firered.gba", "Pokemon FireRed.gba" }) do
    local f = io.open(p, "rb")
    if f then
      local d = f:read("*a")
      f:close()
      if d and #d >= 0x1000000 then return d end
    end
  end
  return nil
end

local function load_doubles_boxes()
  if BattleChrome._doublesTried then return end
  BattleChrome._doublesTried = true
  local root = battle_root()
  local files = BattleChromeExtract.DOUBLES_FILES or {}
  local pRgba = read_bytes(root .. "/" .. (files.player or "healthbox_doubles_player.rgba"))
  local oRgba = read_bytes(root .. "/" .. (files.opponent or "healthbox_doubles_opponent.rgba"))
  if not (pRgba and oRgba) then
    local rom = rom_bytes()
    if rom then
      local ok, p2, o2 = pcall(BattleChromeExtract.bakeDoubles, function(i) return rom:byte(i + 1) or 0 end)
      if ok and p2 and o2 then pRgba, oRgba = p2, o2 end
    end
  end
  BattleChrome._doublesPlayerBox = rgba_to_image(pRgba, 128, 32)
  BattleChrome._doublesOpponentBox = rgba_to_image(oRgba, 128, 32)
  if not (BattleChrome._doublesPlayerBox and BattleChrome._doublesOpponentBox) then
    print("[game3/battle_chrome] doubles healthboxes missing; re-import the ROM to extract them")
  end
end

local function load_hp_bold()
  if BattleChrome._hpBoldTried then return end
  BattleChrome._hpBoldTried = true
  local w, h = BattleChromeExtract.HP_BOLD_W or 88, BattleChromeExtract.HP_BOLD_H or 8
  local rgba = read_bytes(battle_root() .. "/" .. (BattleChromeExtract.HP_BOLD_FILE or "hp_bold_digits.rgba"))
  if not rgba then
    local rom = rom_bytes()
    if rom then
      local ok, r2 = pcall(BattleChromeExtract.bakeHpBoldDigits, function(i) return rom:byte(i + 1) or 0 end)
      if ok and r2 then rgba = r2 end
    end
  end
  BattleChrome._hpBold = rgba_to_image(rgba, w, h)
  BattleChrome._hpBoldQuads = {}
  if not BattleChrome._hpBold then
    print("[game3/battle_chrome] bold HP digits missing; re-import the ROM to extract them")
  end
end

function BattleChrome.hasHpBoldDigits()
  load_hp_bold()
  return BattleChrome._hpBold ~= nil
end

-- pokefirered/src/battle_interface.c:889
function BattleChrome.drawHpBoldChar(ch, x, y)
  load_hp_bold()
  local img = BattleChrome._hpBold
  if not img then return false end
  local chars = BattleChromeExtract.HP_BOLD_CHARS or "0123456789/"
  local n = chars:find(ch, 1, true)
  if not n then return false end
  local q = BattleChrome._hpBoldQuads[n]
  if not q then
    q = love.graphics.newQuad((n - 1) * 8, 0, 8, 8, img:getDimensions())
    BattleChrome._hpBoldQuads[n] = q
  end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, q, x, y)
  return true
end

function BattleChrome.hasDoublesBoxes()
  load_doubles_boxes()
  return BattleChrome._doublesPlayerBox ~= nil and BattleChrome._doublesOpponentBox ~= nil
end

-- pokefirered/src/battle_gfx_sfx_util.c:39
function BattleChrome.drawDoublesBox(isPlayer, x, y)
  load_doubles_boxes()
  local img = isPlayer and BattleChrome._doublesPlayerBox or BattleChrome._doublesOpponentBox
  img = img or BattleChrome._enemyBox
  if not img then return end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, x, y)
end

function BattleChrome.ready()
  if BattleChrome._playerBox and next(BattleChrome._terrains) then return true end
  return BattleChromeExtract.ready(BattleChrome._cache, cache_root())
end

function BattleChrome.hasAssets()
  local root = battle_root()
  return read_bytes(root .. "/healthbox_player.rgba") ~= nil
    and read_bytes(root .. "/textbox.rgba") ~= nil
end

function BattleChrome.manifest()
  if not BattleChrome._manifest then BattleChrome.install(BattleChrome._cache) end
  return BattleChrome._manifest or {}
end

--- Draw terrain sheet ("grass" | "building"). Returns false if missing.
-- During intro slide-in:
-- 1. Base clean wallpaper (continuous sky and ground, no platforms).
-- 2. Transparent enemy platform oval sliding with enemyOx (no wrap, no solid bars).
-- 3. Transparent player platform oval sliding with playerOx (no wrap, no solid bars).
-- When at rest (enemyOx == 0, playerOx == 0), draws standard full terrain at (0, 0).
function BattleChrome.drawTerrain(key, enemyOx, playerOx, bgOx)
  key = key or "building"
  enemyOx = tonumber(enemyOx) or 0
  playerOx = tonumber(playerOx) or 0
  bgOx = tonumber(bgOx) or 0
  local entry = BattleChrome.terrain(key) or BattleChrome.terrain("building")
    or BattleChrome.terrain("grass")
  if not entry or not entry.image then return false end

  local qFullKey = "terrain_full_" .. key
  if not BattleChrome._quads[qFullKey] and love and love.graphics then
    BattleChrome._quads[qFullKey] = love.graphics.newQuad(0, 0, 240, 160, entry.w, entry.h)
  end

  if enemyOx == 0 and playerOx == 0 then
    local q = BattleChrome._quads[qFullKey]
    if q then
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(entry.image, q, 0, 0)
      return true
    end
    return false
  end

  -- During intro slide, use split transparent platforms over continuous wallpaper
  if entry.bgImage and entry.enemyPlat and entry.playerPlat then
    local qBgKey = "terrain_bg_view_" .. key
    if not BattleChrome._quads[qBgKey] and love and love.graphics then
      BattleChrome._quads[qBgKey] = love.graphics.newQuad(0, 0, 240, 160, 256, 160)
    end
    local qBg = BattleChrome._quads[qBgKey]
    love.graphics.setColor(1, 1, 1, 1)
    if bgOx ~= 0 then
      -- pokefirered/src/battle_intro.c:139
      local qWrapKey = "terrain_bg_wrap_" .. key
      if not BattleChrome._quads[qWrapKey] and love and love.graphics then
        BattleChrome._quads[qWrapKey] = love.graphics.newQuad(0, 0, 256, 160, 256, 160)
      end
      local qWrap = BattleChrome._quads[qWrapKey]
      if qWrap then
        local off = -(bgOx % 256)
        love.graphics.draw(entry.bgImage, qWrap, off, 0)
        love.graphics.draw(entry.bgImage, qWrap, off + 256, 0)
      elseif qBg then
        love.graphics.draw(entry.bgImage, qBg, 0, 0)
      end
    elseif qBg then
      love.graphics.draw(entry.bgImage, qBg, 0, 0)
    end
    love.graphics.draw(entry.enemyPlat, enemyOx, 0)
    love.graphics.draw(entry.playerPlat, playerOx, 0)
    return true
  end

  local q = BattleChrome._quads[qFullKey]
  if q then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(entry.image, q, 0, 0)
    return true
  end
  return false
end

--- Draw clean background wallpaper without battle platforms (e.g. for evolution scene).
function BattleChrome.drawCleanBg(key)
  key = key or "building"
  local entry = BattleChrome.terrain(key) or BattleChrome.terrain("building")
    or BattleChrome.terrain("grass")
  if not entry then return false end

  if entry.bgImage and love and love.graphics then
    local qBgKey = "terrain_bg_view_" .. key
    if not BattleChrome._quads[qBgKey] then
      BattleChrome._quads[qBgKey] = love.graphics.newQuad(0, 0, 240, 160, 256, 160)
    end
    local qBg = BattleChrome._quads[qBgKey]
    love.graphics.setColor(1, 1, 1, 1)
    if qBg then
      love.graphics.draw(entry.bgImage, qBg, 0, 0)
      return true
    end
  end

  local qFullKey = "terrain_full_" .. key
  if not BattleChrome._quads[qFullKey] and entry.image and love and love.graphics then
    BattleChrome._quads[qFullKey] = love.graphics.newQuad(0, 0, 240, 160, entry.w, entry.h)
  end
  local q = BattleChrome._quads[qFullKey]
  if q and entry.image then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(entry.image, q, 0, 0)
    return true
  end
  return false
end

--- Draw textbox panel: message / action / fight.
--- Tilemap chrome starts at y=112 (not 120); panels are 48px tall, 160px apart.
function BattleChrome.drawPanel(mode)
  if not BattleChrome._textbox then return end
  local scroll = 0
  if mode == "menu" then scroll = 160
  elseif mode == "moves" then scroll = 320 end
  local tw = (BattleChrome._manifest and BattleChrome._manifest.textboxW) or 256
  local th = (BattleChrome._manifest and BattleChrome._manifest.textboxH) or 512
  local key = "panel48_" .. tostring(scroll)
  if not BattleChrome._quads[key] and love and love.graphics then
    local y = 112 + scroll
    if y + 48 > th then y = math.max(0, th - 48) end
    BattleChrome._quads[key] = love.graphics.newQuad(0, y, 240, 48, tw, th)
  end
  local q = BattleChrome._quads[key]
  if q then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(BattleChrome._textbox, q, 0, 112)
  end
end

function BattleChrome.drawEnemyBox(x, y)
  if not BattleChrome._enemyBox then return end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(BattleChrome._enemyBox, x, y)
end

function BattleChrome.drawPlayerBox(x, y)
  if not BattleChrome._playerBox then return end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(BattleChrome._playerBox, x, y)
end

-- Element tile bases (pret B_INTERFACE_GFX_*)
local HP_TEXT_TILE = 1
local HP_BAR_LEFT_BORDER = 65
local HP_BAR_BASE = { green = 3, yellow = 47, red = 56 }
local HP_BAR_TILES = 6
local HP_BAR_PIXELS = 48
local EXP_BAR_TILE = 12
local EXP_BAR_TILES = 8

-- pokefirered/src/battle_interface.c:2155
function BattleChrome.scaledHpFraction(hp, maxHp, scale)
  hp = tonumber(hp) or 0
  maxHp = tonumber(maxHp) or 0
  scale = tonumber(scale) or HP_BAR_PIXELS
  if maxHp <= 0 or hp <= 0 then return 0 end
  if hp > maxHp then hp = maxHp end
  local result = math.floor(hp * scale / maxHp)
  if result == 0 then return 1 end
  return result
end

-- pokefirered/src/battle_interface.c:2168
function BattleChrome.hpBarLevel(hp, maxHp)
  hp = tonumber(hp) or 0
  maxHp = tonumber(maxHp) or 0
  if maxHp <= 0 then return "empty" end
  if hp >= maxHp then return "full" end
  local fraction = BattleChrome.scaledHpFraction(hp, maxHp, HP_BAR_PIXELS)
  if fraction > math.floor(HP_BAR_PIXELS * 50 / 100) then return "green" end
  if fraction > math.floor(HP_BAR_PIXELS * 20 / 100) then return "yellow" end
  if fraction > 0 then return "red" end
  return "empty"
end

-- pokefirered/src/battle_interface.c:1907
function BattleChrome.hpColor(hp, maxHp)
  local level = BattleChrome.hpBarLevel(hp, maxHp)
  if level == "full" then return "green" end
  if level == "empty" then return "red" end
  return level
end

local function elements_tile_quad(ti, sheet)
  sheet = sheet or BattleChrome._elements
  if not sheet or not love or not love.graphics then return nil end
  local key = (sheet == BattleChrome._elementsExp and "exp_" or "elt_") .. tostring(ti)
  if not BattleChrome._quads[key] then
    local tw = 40 -- 320/8
    local tx, ty = ti % tw, math.floor(ti / tw)
    BattleChrome._quads[key] = love.graphics.newQuad(tx * 8, ty * 8, 8, 8, 320, 24)
  end
  return BattleChrome._quads[key]
end

-- pokefirered/src/battle_interface.c:2050
local function split_bar_pixels(filled, numTiles)
  local remaining = math.max(0, math.min(numTiles * 8, math.floor(tonumber(filled) or 0)))
  local out = {}
  for i = 1, numTiles do
    local pix = math.max(0, math.min(8, remaining))
    remaining = remaining - pix
    out[i] = pix
  end
  return out
end

local function filled_pixels_for_bar(ratio, numTiles)
  local total = numTiles * 8
  local filled = math.floor(total * ratio)
  if filled < 1 and ratio > 0 then filled = 1 end
  return split_bar_pixels(filled, numTiles)
end

--- Draw pret HP bar: HP label tiles + 6 fill tiles (48px). Top-left of 64×8 strip.
function BattleChrome.drawHpBar(x, y, hp, maxHp, statusBorder)
  if not BattleChrome._elements then return end
  local color = BattleChrome.hpColor(hp, maxHp)
  local base = HP_BAR_BASE[color] or HP_BAR_BASE.green
  local pix = split_bar_pixels(BattleChrome.scaledHpFraction(hp, maxHp, HP_BAR_PIXELS), HP_BAR_TILES)

  love.graphics.setColor(1, 1, 1, 1)
  if statusBorder then
    -- pokefirered/src/battle_interface.c:1672
    local q = elements_tile_quad(HP_BAR_LEFT_BORDER)
    if q then love.graphics.draw(BattleChrome._elements, q, x + 8, y) end
  else
    for i = 0, 1 do
      local q = elements_tile_quad(HP_TEXT_TILE + i)
      if q then love.graphics.draw(BattleChrome._elements, q, x + i * 8, y) end
    end
  end
  for i = 0, HP_BAR_TILES - 1 do
    local q = elements_tile_quad(base + (pix[i + 1] or 0))
    if q then love.graphics.draw(BattleChrome._elements, q, x + 16 + i * 8, y) end
  end
end

function BattleChrome.drawElementTile(ti, x, y, healthboxPal)
  local sheet = healthboxPal and (BattleChrome._elementsExp or BattleChrome._elements) or BattleChrome._elements
  if not sheet then return end
  local q = elements_tile_quad(ti, sheet)
  if not q then return end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(sheet, q, x, y)
end

function BattleChrome.drawHpFill(x, y, hp, maxHp)
  BattleChrome.drawHpBar(x - 16, y, hp, maxHp)
end

--- Pret EXP bar: 8 element tiles in healthbox VRAM (TAG_HEALTHBOX_PAL → blue).
function BattleChrome.drawExpBar(x, y, ratio)
  local sheet = BattleChrome._elementsExp or BattleChrome._elements
  if not sheet then return end
  ratio = math.max(0, math.min(1, ratio or 0))
  local pix = filled_pixels_for_bar(ratio, EXP_BAR_TILES)
  love.graphics.setColor(1, 1, 1, 1)
  for i = 0, EXP_BAR_TILES - 1 do
    local q = elements_tile_quad(EXP_BAR_TILE + (pix[i + 1] or 0), sheet)
    if q then love.graphics.draw(sheet, q, x + i * 8, y) end
  end
end

function BattleChrome.drawExpFill(x, y, ratio, _pixels)
  BattleChrome.drawExpBar(x, y, ratio)
end

-- Party summary balls: pret B_INTERFACE_GFX_BALL_PARTY_SUMMARY = tile 66.
-- In pokefirered (battle_interface.c:1183-1202):
--   tile 66 (+0): ok (filled normal Pokéball)
--   tile 67 (+1): empty (empty circle outline)
--   tile 68 (+2): status (status ailment circle)
--   tile 69 (+3): faint (fainted dark circle)
local PARTY_BALL_TILE = {
  ok = 66,
  empty = 67,
  status = 68,
  faint = 69,
  caught = 70,
}

function BattleChrome.drawPartyBall(x, y, kind)
  local ti = PARTY_BALL_TILE[kind or "ok"] or PARTY_BALL_TILE.ok
  local q = elements_tile_quad(ti)
  if not q or not BattleChrome._elements then
    local okP, PokedexChrome = pcall(require, "src.ui.game3.pokedex_chrome")
    if okP and PokedexChrome and PokedexChrome.drawCaughtMarker then
      PokedexChrome.drawCaughtMarker(x, y)
    end
    return
  end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(BattleChrome._elements, q, x, y)
end

function BattleChrome.drawCaughtBall(x, y)
  BattleChrome.drawPartyBall(x, y, "caught")
end

--- Draw party summary bar and 6 ball slots (1:1 with pokefirered CreatePartyStatusSummarySprites).
-- Player: base (136, 96), un-flipped bar (<=====), balls at y=92 from x=160..210 (left-to-right).
-- Opponent: base (104, 40), H-flipped bar (=====>), balls at y=36 from x=30..80 (right-aligned).
function BattleChrome.drawPartyBar(x, y, balls, ox, isOpponent)
  ox = tonumber(ox) or 0
  balls = balls or {}
  if isOpponent then
    local barX = x + ox
    if BattleChrome._partyBar then
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(BattleChrome._partyBar, barX, y, 0, -1, 1)
    end
    for i = 1, 6 do
      local kind = balls[i] or "empty"
      local bx = (x + ox) - 24 - 10 * (6 - i)
      BattleChrome.drawPartyBall(bx, y - 7, kind)
    end
  else
    local barX = x + ox
    if BattleChrome._partyBar then
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(BattleChrome._partyBar, barX, y, 0, 1, 1)
    end
    for i = 1, 6 do
      local kind = balls[i] or "empty"
      local bx = (x + ox) + 24 + 10 * (i - 1)
      BattleChrome.drawPartyBall(bx, y - 8, kind)
    end
  end
end

return BattleChrome
