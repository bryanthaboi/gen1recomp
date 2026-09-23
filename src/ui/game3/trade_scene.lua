local Stack = require("src.ui.game3.stack")
local Display = require("src.core.game3.display")
local Chrome = require("src.ui.game3.chrome")
local FrlgFont = require("src.ui.game3.frlg_font")
local Pokemon = require("src.core.game3.pokemon")
local Extract = require("src.import.gba.extract_island1")

local TradeSceneUi = {}

TradeSceneUi.CACHE_SUB = "trade"

TradeSceneUi._core = nil
TradeSceneUi._art = nil
TradeSceneUi._artTried = false
TradeSceneUi._logged = false

local function cache_root()
  return (Extract and Extract.CACHE_ROOT) or "data/generated/gba"
end

local function trade_root()
  return cache_root() .. "/" .. TradeSceneUi.CACHE_SUB
end

local function log(msg)
  if TradeSceneUi._logged then return end
  TradeSceneUi._logged = true
  print("[game3/trade_scene] " .. tostring(msg))
end

local function read_bytes(rel)
  local okD, Dataset = pcall(require, "src.core.game3.dataset")
  if okD and Dataset and Dataset.cache then
    local cache = Dataset.cache()
    if cache and cache.read then
      local d = cache:read(rel)
      if type(d) == "string" and #d > 0 then return d end
    end
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
  for _, p in ipairs({ rel, "data/generated/gba/" .. (rel:gsub("^data/generated/gba/", "")) }) do
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
  local chunk = (loadstring or load)(src, "@" .. rel)
  if not chunk then return nil end
  local ok, t = pcall(chunk)
  if ok and type(t) == "table" then return t end
  return nil
end

local function rgba_to_image(rgba, w, h)
  if not (love and love.image and love.graphics) then return nil end
  if not rgba or w < 1 or h < 1 or #rgba < w * h * 4 then return nil end
  local ok, imageData = pcall(love.image.newImageData, w, h, "rgba8", rgba)
  if not ok or not imageData then return nil end
  local image = love.graphics.newImage(imageData)
  if image.setFilter then image:setFilter("nearest", "nearest") end
  return image
end

-- pokefirered/src/trade_scene.c:398 sAnim_GbaScreen_Long
local FLASH_FRAMES = 7

local SHEETS = {
  gba = "gba_screen",
  cableCloseup = "cable_closeup",
  cableEnd = "cable_end",
  linkMonGlow = "link_mon_glow",
  linkMonShadow = "link_mon_shadow",
  monShadowBg = "mon_shadow_bg",
  gbaFlash = "gba_screen_flash",
  ball = "ball",
}

-- pokefirered/src/trade_scene.c:1220 LoadTradeGbaSpriteGfx
function TradeSceneUi.loadArt()
  if TradeSceneUi._artTried then return TradeSceneUi._art end
  TradeSceneUi._artTried = true
  local man = load_lua(trade_root() .. "/manifest.lua")
  if not man then
    log("no trade art in the cache, holding on black through the transfer")
    return nil
  end
  local art = { manifest = man }
  for key, name in pairs(SHEETS) do
    local entry = man[name] or man[key]
    local w = tonumber(entry and entry.width) or 0
    local h = tonumber(entry and entry.height) or 0
    art[key] = rgba_to_image(read_bytes(trade_root() .. "/" .. name .. ".rgba"), w, h)
  end
  if not art.gba then
    log("trade manifest has no gba screen sheet, holding on black through the transfer")
    return nil
  end
  -- pokefirered/src/trade_scene.c:1126
  local center = tonumber((man.gba_screen or {}).center_y) or (0x15C + 80)
  art.gbaTop = center - art.gba:getHeight() / 2
  if art.gbaFlash then
    local fw = art.gbaFlash:getWidth() / FLASH_FRAMES
    local fh = art.gbaFlash:getHeight()
    local quads = {}
    for i = 0, FLASH_FRAMES - 1 do
      quads[i] = love.graphics.newQuad(i * fw, 0, fw, fh, art.gbaFlash:getDimensions())
    end
    art.gbaFlashQuads = quads
    art.gbaFlashW = fw
  end
  TradeSceneUi._art = art
  return art
end

function TradeSceneUi.invalidate()
  TradeSceneUi._art = nil
  TradeSceneUi._artTried = false
end

function TradeSceneUi.isOpen()
  return TradeSceneUi._core ~= nil
end

function TradeSceneUi.start(core)
  TradeSceneUi._core = core
  Stack.push("trade_scene", TradeSceneUi, { hideBelow = true })
end

function TradeSceneUi.close()
  TradeSceneUi._core = nil
  Stack.pop("trade_scene")
end

-- pokefirered/src/trade_scene.c:1103 CB2_InGameTrade
function TradeSceneUi.update()
  local core = TradeSceneUi._core
  if not core then return end
  local s = core.state and core.state()
  -- pokefirered/src/trade_scene.c:2527 CB2_UpdateLinkTrade
  if s and s.uiDriven then
    core.step()
    return
  end
  local Space = package.loaded["src.core.game3.scripting.space"]
  if Space and Space.vm then Space.vm:tick() end
end

-- pokefirered/src/trade_scene.c:1770
function TradeSceneUi.handleInput(input)
  local core = TradeSceneUi._core
  if not core or not input then return end
  if core.isLink and core.isLink() then return end
  if input:wasPressed("a") then core.pressA() end
end

local function draw_mon(pic, x, y, scale)
  if not (pic and pic.image) then return end
  scale = scale or 1
  if scale <= 0.02 then return end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(pic.image, x, y, 0, scale, scale, 32, 32)
end

-- pokefirered/src/pokeball.c:59 gBallSpriteSheets BALL_POKE
local function draw_ball(s, art, x, y)
  if art and art.ball then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(art.ball, x - 8, y - 8)
    return
  end
  love.graphics.setColor(0.86, 0.15, 0.15, 1)
  love.graphics.circle("fill", x, y, 7)
  love.graphics.setColor(0.94, 0.94, 0.94, 1)
  love.graphics.arc("fill", x, y, 7, 0, math.pi)
  love.graphics.setColor(0.1, 0.1, 0.1, 1)
  love.graphics.rectangle("fill", x - 7, y - 1, 14, 2)
  love.graphics.circle("line", x, y, 2.5)
  if (s.ballWhite or 0) > 0 then
    love.graphics.setColor(1, 1, 1, s.ballWhite)
    love.graphics.circle("fill", x, y, 8)
  end
end

local function draw_text_window(text)
  if not text or text == "" then return end
  -- pokefirered/src/trade_scene.c:480 sTradeMessageWindowTemplates
  Chrome.fixedStdFrame(2, 15, 26, 4)
  FrlgFont.draw(text, 16, 122, { maxWidth = 208 })
end

function TradeSceneUi.draw()
  local core = TradeSceneUi._core
  if not core or not (love and love.graphics) then return end
  local s = core.state()
  if not s then return end
  local art = s.art

  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("fill", 0, 0, Display.W, Display.H)

  -- pokefirered/src/trade_scene.c:1121
  if art and s.monShadowBg and art.monShadowBg then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(art.monShadowBg, -(tonumber(s.bg2hofs) or 0), 0)
  end

  if art and s.gbaVisible then
    love.graphics.setColor(1, 1, 1, 1)
    -- pokefirered/src/trade_scene.c:678 REG_OFFSET_BG1VOFS
    love.graphics.draw(art.gba, 0, (art.gbaTop or 0) - (tonumber(s.bg1vofs) or 0))
    if s.cableEnd and art.cableEnd then
      love.graphics.draw(art.cableEnd, 128 - art.cableEnd:getWidth() / 2, 65)
    end
    if s.flash and art.gbaFlash and art.gbaFlashQuads then
      local idx = math.floor((s.flash / 2) % FLASH_FRAMES)
      local fw = art.gbaFlashW
      love.graphics.draw(art.gbaFlash, art.gbaFlashQuads[idx], 120 - fw / 2,
        80 - art.gbaFlash:getHeight() / 2)
    end
  end

  if art and s.cableCloseup and art.cableCloseup then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(art.cableCloseup, 0, 0)
  end

  if art and s.linkVisible then
    local y = (s.linkY or 0) + (s.linkY2 or 0)
    if art.linkMonGlow then
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(art.linkMonGlow, 128 - art.linkMonGlow:getWidth() / 2,
        y - art.linkMonGlow:getHeight() / 2)
    end
    if art.linkMonShadow then
      love.graphics.draw(art.linkMonShadow, 128 - art.linkMonShadow:getWidth() / 2,
        y - art.linkMonShadow:getHeight() / 2)
    end
  end

  if art and s.crossVisible and art.linkMonShadow then
    love.graphics.setColor(1, 1, 1, 1)
    local w2 = art.linkMonShadow:getWidth() / 2
    local h2 = art.linkMonShadow:getHeight() / 2
    love.graphics.draw(art.linkMonShadow, 111 - w2, (s.crossMonAy or 170) + (s.crossY2a or 0) - h2)
    love.graphics.draw(art.linkMonShadow, 129 - w2, (s.crossMonBy or -10) + (s.crossY2b or 0) - h2)
  end

  -- pokefirered/src/trade_scene.c:757 draws every mon by MON_DATA_SPECIES_OR_EGG
  -- pokefirered/src/trade_scene.c:1541
  if s.crossMonVisible then
    draw_mon(Pokemon.monFrontPic(s.offer),
      60, 192 + (s.monY2a or 0), 1)
    draw_mon(Pokemon.monFrontPic(s.received),
      180, -32 + (s.monY2b or 0), 1)
  end

  -- pokefirered/src/trade_scene.c:772
  if s.playerVisible then
    draw_mon(Pokemon.monFrontPic(s.offer),
      120 + (s.monX2 or 0), 60, s.monScale or 1)
  end

  -- pokefirered/src/trade_scene.c:1716
  if s.partnerVisible then
    draw_mon(Pokemon.monFrontPic(s.received),
      120, 60, 1)
  end

  if s.ballVisible then
    draw_ball(s, art, s.ballX or 120, (s.ballY or 32) + (s.ballY2 or 0))
  end

  if (s.whiteBlend or 0) > 0 then
    love.graphics.setColor(1, 1, 1, s.whiteBlend)
    love.graphics.rectangle("fill", 0, 0, Display.W, Display.H)
  end

  if (s.veil or 0) > 0 then
    love.graphics.setColor(0, 0, 0, math.min(1, s.veil))
    love.graphics.rectangle("fill", 0, 0, Display.W, Display.H)
  end

  draw_text_window(s.text)
  love.graphics.setColor(1, 1, 1, 1)
end

return TradeSceneUi
