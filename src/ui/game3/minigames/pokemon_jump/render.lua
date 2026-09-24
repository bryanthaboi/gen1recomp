local Art = require("src.ui.game3.minigames.common_art")

local Render = {}

local T = 8
local SCREEN_W, SCREEN_H = 240, 160
local TRANSPARENT = { 0, 0, 0, 0 }
-- pokefirered/src/pokemon_jump.c:3629
local DIGITS = {
  points = { x = 108, y = 6, count = 5 },
  times = { x = 30, y = 6, count = 4 },
}
local VINE_KEYS = { "vine1", "vine2", "vine3", "vine4" }

local quadCache = setmetatable({}, { __mode = "k" })

local function quad(image, x, y, w, h, iw, ih)
  local byImage = quadCache[image]
  if not byImage then
    byImage = {}
    quadCache[image] = byImage
  end
  local key = x .. ":" .. y .. ":" .. w .. ":" .. h
  local q = byImage[key]
  if not q then
    q = love.graphics.newQuad(x, y, w, h, iw, ih)
    byImage[key] = q
  end
  return q
end

local function drawBg(sheet, sx, sy)
  if not (sheet and sheet.image) then return end
  local W, H = sheet.width, sheet.height
  sx, sy = math.floor(sx) % W, math.floor(sy) % H
  love.graphics.setColor(1, 1, 1, 1)
  local x = 0
  while x < SCREEN_W do
    local u = (sx + x) % W
    local w = math.min(W - u, SCREEN_W - x)
    local y = 0
    while y < SCREEN_H do
      local v = (sy + y) % H
      local h = math.min(H - v, SCREEN_H - y)
      love.graphics.draw(sheet.image, quad(sheet.image, u, v, w, h, W, H), x, y)
      y = y + h
    end
    x = x + w
  end
end

local function colors(fg, shadow, bg)
  return { fg = fg, shadow = shadow, bg = bg or TRANSPARENT }
end

-- pokefirered/src/pokemon_jump.c:4376
local function drawVines(g, art)
  local v = g.vine
  local tables = art.tables
  local count = 0
  local function one(i, flip)
    count = count + 1
    local sheet = art[VINE_KEYS[i] .. (v.pal2 and "_pal2" or "")]
    if not sheet then return end
    local cx = tables.vine_x[count]
    local cy = tables.vine_y[i][v.anim + 1]
    local w, h = sheet.frame_w, sheet.frame_h
    local left, top = cx - w / 2, cy - h / 2
    if flip then
      Art.drawFrame(sheet, v.anim, left, top, -1, 1, w, 0)
    else
      Art.drawFrame(sheet, v.anim, left, top)
    end
  end
  for i = 1, 4 do one(i, false) end
  for i = 4, 1, -1 do one(i, true) end
end

local function monPic(sim, i)
  local info = sim.game.monInfo[i]
  if not info then return nil end
  local key = tostring(info.species) .. ":" .. tostring(info.personality) .. ":" .. tostring(info.shiny)
  sim._pics = sim._pics or {}
  local cached = sim._pics[i]
  if cached and cached.key == key then return cached.entry end
  local entry
  local ok, Pokemon = pcall(require, "src.core.game3.pokemon")
  if ok and Pokemon and Pokemon.monFrontPic then
    local okPic, e = pcall(Pokemon.monFrontPic, {
      species = info.species, personality = info.personality, isShiny = info.shiny,
    })
    if okPic then entry = e end
  end
  sim._pics[i] = { key = key, entry = entry }
  return entry
end

-- pokefirered/src/sprite.c:321
local function drawMons(sim)
  local g = sim.game.gfx
  local order = {}
  for i = 0, g.numPlayers - 1 do
    local s = g.monSprites[i]
    if s and not s.invisible and not s.gone then order[#order + 1] = i end
  end
  table.sort(order, function(a, b)
    local sa, sb = g.monSprites[a].subpriority, g.monSprites[b].subpriority
    if sa ~= sb then return sa > sb end
    return a > b
  end)
  love.graphics.setColor(1, 1, 1, 1)
  for _, i in ipairs(order) do
    local s = g.monSprites[i]
    local entry = monPic(sim, i)
    if entry and entry.image then
      local iw, ih = entry.w or 64, entry.h or 64
      love.graphics.draw(entry.image, s.x - math.floor(iw / 2), s.y - math.floor(ih / 2) + s.y2)
    end
  end
end

local function drawStars(g, art)
  for i = 0, g.numPlayers - 1 do
    local star = g.starSprites[i]
    if star and not star.invisible then
      Art.drawFrame(art.star, star.frame, star.x - 8, star.y - 8)
    end
  end
end

-- pokefirered/src/digit_obj_util.c:241
local function drawDigits(sheet, spec, num)
  num = math.max(0, math.floor(tonumber(num) or 0))
  local pow10 = 10 ^ (spec.count - 1)
  local x = spec.x
  for _ = 1, spec.count do
    local digit = math.floor(num / pow10)
    num = num - digit * pow10
    pow10 = pow10 / 10
    Art.drawFrame(sheet, digit % 10, x, spec.y)
    x = x + 8
  end
end

local function fontModule()
  return require("src.ui.game3.frlg_font")
end

local textCache = {}

local function romText(key, ctx, cacheKey)
  cacheKey = cacheKey or (ctx == nil and key or nil)
  if cacheKey and textCache[cacheKey] then return textCache[cacheKey] end
  local ok, RomText = pcall(require, "src.core.game3.rom_text")
  if not ok then return "" end
  local okText, text = pcall(RomText.plain, key, ctx)
  if not okText then return "" end
  if cacheKey then textCache[cacheKey] = text end
  return text
end

-- pokefirered/src/pokemon_jump.c:3500
local function drawSuffixes(art)
  local FrlgFont = fontModule()
  local pal = art.interface
  local c = colors(pal[2], pal[3])
  local wins = art.tables.window_templates
  local points, times = wins[1], wins[2]
  FrlgFont.draw(romText("gText_SpacePoints2"), points.left * T, points.top * T + 2, { small = true, colors = c })
  FrlgFont.draw(romText("gText_SpaceTimes3"), times.left * T, times.top * T + 2, { small = true, colors = c })
end

-- pokefirered/src/pokemon_jump.c:3723
local function drawNames(sim, art)
  local g = sim.game
  local gfx = g.gfx
  if not gfx.names.visible then return end
  local FrlgFont = fontModule()
  local pal = art.interface
  local coords = art.tables.player_name_window_coords[g.numPlayers]
  for i = 0, g.numPlayers - 1 do
    local at = coords and coords[i + 1]
    if at and not g.gone[i] then
      local name = g.players[i].name or ""
      local c
      if gfx.names.highlight and i == g.multiplayerId then
        c = colors(pal[4], pal[5])
      else
        c = colors(pal[2], pal[3])
      end
      local width = FrlgFont.measure(name, { small = true })
      local x = math.floor(math.max(0, 64 - width) / 2)
      FrlgFont.draw(name, at[1] * T + x, at[2] * T + 2, { small = true, colors = c })
    end
  end
end

local function prizeText(w)
  local item = tonumber(w.itemId) or 0
  local name = ""
  local okI, ItemsData = pcall(require, "src.core.game3.items_data")
  if okI and ItemsData and ItemsData.displayName then
    local okN, n = pcall(ItemsData.displayName, item)
    if okN and n then name = n end
  end
  if w.key == "gText_AwesomeWonF701F700" then
    local Game = require("src.core.game3.minigames.pokemon_jump.game")
    local qty = tonumber(w.quantity) or 0
    return romText(w.key, { dynamic = { [0] = Game.prizeItemName(item, qty, name), [1] = tostring(qty) } },
      w.key .. ":" .. item .. ":" .. qty)
  end
  return romText(w.key, { dynamic = { [0] = name } }, w.key .. ":" .. item)
end

-- pokefirered/src/pokemon_jump.c:3465
local function drawMessage(gfx)
  local w = gfx.msgWindow
  if not (w and w.shown) then return end
  local Window = require("src.ui.game3.window")
  local FrlgFont = fontModule()
  local tpl = Window.template(w.left, w.top, w.width, w.height)
  Window.fixedStdFrame(tpl)
  Window.fill(tpl, 1, 1, 1, 1)
  local text = w.itemId and prizeText(w) or romText(w.key)
  FrlgFont.draw(text, w.left * T, w.top * T + 2,
    { maxWidth = w.width * T, colors = FrlgFont.COLOR.NORMAL })
end

-- pokefirered/src/menu.c:531
local function drawYesNo(gfx, art)
  local menu = gfx.yesno
  if not menu then return end
  local Window = require("src.ui.game3.window")
  local FrlgFont = fontModule()
  local pal = art.interface
  local tpl = Window.template(menu.left, menu.top, menu.width, menu.height)
  Window.stdFrame(tpl)
  local bg = pal[1]
  Window.fill(tpl, bg[1], bg[2], bg[3], 1)
  local c = colors(pal[2], pal[3])
  local px, py = menu.left * T, menu.top * T + 2
  FrlgFont.draw(romText("gText_YesNo"), px + 8, py, { colors = c })
  Window.cursorPx(px, py + menu.cursor * FrlgFont.LINE_PITCH, { colors = c })
end

function Render.draw(sim)
  if not (love and love.graphics) then return end
  local art = sim.art
  if not art then return end
  local g = sim.game.gfx
  drawBg(art.bg, 0, 0)
  if g.vine.priority == 3 then drawVines(g, art) end
  drawBg(art.venusaur, 0, g.venusaurY)
  drawMons(sim)
  if g.vine.priority == 2 then drawVines(g, art) end
  if g.bonus.visible then drawBg(art.bonuses, g.bonus.x, g:bonusScrollY()) end
  drawStars(g, art)
  if art.digits then
    drawDigits(art.digits, DIGITS.points, g.points)
    drawDigits(art.digits, DIGITS.times, g.times)
  end
  drawSuffixes(art)
  drawNames(sim, art)
  drawMessage(g)
  drawYesNo(g, art)
  if g.countdown and g.countdown:running() then pcall(g.countdown.draw, g.countdown) end
  pcall(function() require("src.ui.game3.wireless_icon").draw() end)
  local level = g:fadeLevel()
  if level > 0 then
    love.graphics.setColor(0, 0, 0, level / 16)
    love.graphics.rectangle("fill", 0, 0, SCREEN_W, SCREEN_H)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return Render
