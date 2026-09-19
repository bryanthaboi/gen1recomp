-- Load ROM-extracted naming-screen chrome (data/generated/gba/naming/).

local NamingChrome = {}

NamingChrome._ready = false
NamingChrome._images = {}

local ROOTS = {
  "data/generated/gba/naming",
}

local function tryLoad(path)
  if not (love and love.filesystem and love.filesystem.getInfo(path)) then
    return nil
  end
  local ok, img = pcall(love.graphics.newImage, path)
  if ok and img then
    if img.setFilter then img:setFilter("nearest", "nearest") end
    return img
  end
  return nil
end

local function loadManifest(root)
  local path = root .. "/manifest.lua"
  if not (love and love.filesystem and love.filesystem.load) then return nil end
  local ok, chunk = pcall(love.filesystem.load, path)
  if not ok or type(chunk) ~= "function" then return nil end
  local ok2, t = pcall(chunk)
  if ok2 and type(t) == "table" then return t end
  return nil
end

NamingChrome.KEYS = {
  "bg", "kb_upper", "kb_lower", "kb_symbols",
  "back_button", "ok_button", "page_swap_frame", "page_swap_button",
  "page_swap_button_upper", "page_swap_button_lower", "page_swap_button_others",
  "page_swap_upper", "page_swap_lower", "page_swap_others",
  "page_swap_button_glow", "back_button_glow", "ok_button_glow",
  "cursor", "input_arrow", "underscore", "rival",
}

function NamingChrome.install(_cache)
  NamingChrome._images = {}
  NamingChrome._ready = false
  for _, root in ipairs(ROOTS) do
    local man = loadManifest(root)
    if man then
      for _, k in ipairs(NamingChrome.KEYS) do
        local p = man[k] or (root .. "/" .. k .. ".png")
        NamingChrome._images[k] = tryLoad(p)
      end
      NamingChrome._ready = NamingChrome._images.bg ~= nil
      return NamingChrome._ready
    end
    -- Flat files without manifest
    NamingChrome._images.bg = tryLoad(root .. "/bg.png")
    if NamingChrome._images.bg then
      NamingChrome._images.kb_upper = tryLoad(root .. "/kb_upper.png")
      NamingChrome._images.kb_lower = tryLoad(root .. "/kb_lower.png")
      NamingChrome._images.kb_symbols = tryLoad(root .. "/kb_symbols.png")
      NamingChrome._images.back_button = tryLoad(root .. "/back_button.png")
      NamingChrome._images.ok_button = tryLoad(root .. "/ok_button.png")
      NamingChrome._images.page_swap_frame = tryLoad(root .. "/page_swap_frame.png")
      NamingChrome._images.page_swap_button = tryLoad(root .. "/page_swap_button.png")
      NamingChrome._images.page_swap_button_upper = tryLoad(root .. "/page_swap_button_upper.png")
      NamingChrome._images.page_swap_button_lower = tryLoad(root .. "/page_swap_button_lower.png")
      NamingChrome._images.page_swap_button_others = tryLoad(root .. "/page_swap_button_others.png")
      NamingChrome._images.page_swap_upper = tryLoad(root .. "/page_swap_upper.png")
      NamingChrome._images.page_swap_lower = tryLoad(root .. "/page_swap_lower.png")
      NamingChrome._images.page_swap_others = tryLoad(root .. "/page_swap_others.png")
      NamingChrome._images.page_swap_button_glow = tryLoad(root .. "/page_swap_button_glow.png")
      NamingChrome._images.back_button_glow = tryLoad(root .. "/back_button_glow.png")
      NamingChrome._images.ok_button_glow = tryLoad(root .. "/ok_button_glow.png")
      NamingChrome._images.cursor = tryLoad(root .. "/cursor.png")
      NamingChrome._images.input_arrow = tryLoad(root .. "/input_arrow.png")
      NamingChrome._images.underscore = tryLoad(root .. "/underscore.png")
      NamingChrome._images.rival = tryLoad(root .. "/rival.png")
      NamingChrome._ready = true
      return true
    end
  end
  return false
end

function NamingChrome.ready()
  if NamingChrome._ready then return true end
  return NamingChrome.install()
end

function NamingChrome.get(key)
  NamingChrome.ready()
  return NamingChrome._images[key]
end

function NamingChrome.cursorQuad(frame)
  local img = NamingChrome.get("cursor")
  if not img or not love.graphics.newQuad then return nil, nil end
  frame = math.max(0, math.min(2, tonumber(frame) or 0))
  local qw, qh = 16, 16
  local q = love.graphics.newQuad(frame * qw, 0, qw, qh, img:getDimensions())
  return img, q
end

-- Keyboard chrome: full frame + SELECT tab (extract v3).
-- WIN_KB text still originates at (24,80); older caches may be 152×64 inner-only.
NamingChrome.KB_X = 16
NamingChrome.KB_Y = 72
NamingChrome.KB_W = 176
NamingChrome.KB_H = 80
NamingChrome.KB_INNER_X = 24
NamingChrome.KB_INNER_Y = 80
NamingChrome.KB_INNER_W = 152
NamingChrome.KB_INNER_H = 64

function NamingChrome.kbQuad(pageKey)
  local img = NamingChrome.get(pageKey)
  if not img or not love.graphics.newQuad then return nil, nil end
  local iw, ih = img:getDimensions()
  -- v3: pre-cropped frame including border/tab
  if iw <= NamingChrome.KB_W + 8 and ih <= NamingChrome.KB_H + 8 and iw >= 160 then
    return img, nil
  end
  -- v2: inner-only crop drawn at WIN_KB
  if iw <= NamingChrome.KB_INNER_W + 8 and ih <= NamingChrome.KB_INNER_H + 8 then
    return img, nil, "inner"
  end
  -- Full 256×160 map: crop frame region
  local w = math.min(NamingChrome.KB_W, iw - NamingChrome.KB_X)
  local h = math.min(NamingChrome.KB_H, ih - NamingChrome.KB_Y)
  if w < 1 or h < 1 then return img, nil end
  local q = love.graphics.newQuad(NamingChrome.KB_X, NamingChrome.KB_Y, w, h, iw, ih)
  return img, q
end

return NamingChrome
