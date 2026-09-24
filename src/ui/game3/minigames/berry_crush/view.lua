local Art = require("src.ui.game3.minigames.common_art")
local FrlgFont = require("src.ui.game3.frlg_font")
local R = require("src.core.game3.minigames.berry_crush.rules")

local View = {}

local floor = math.floor
local STD = FrlgFont.STDPAL
local OPTS = {}

-- pokefirered/src/berry_crush.c:163
View.COLORID = { GRAY = 1, BLACK = 2, LIGHT_GRAY = 3, BLUE = 4, GREEN = 5, RED = 6 }
-- pokefirered/src/berry_crush.c:934
View.HEADERS = {
  [0] = "gText_SpaceTimes2", [1] = "gText_XDotY", [2] = "gText_StrVar1Berry",
  [3] = "gText_NeatnessRankings", [4] = "gText_CooperativeRankings", [5] = "gText_PressingPowerRankings",
}
View.TIMER_COLON = 10

function View.colors(row, pal)
  pal = pal or STD
  return { bg = pal[row[1]] or STD[0], fg = pal[row[2]] or STD[2], shadow = pal[row[3]] or STD[3] }
end

local function textColors(sim, id, pal)
  return View.colors(sim.T.text_colors[id], pal)
end

local function measure(s)
  return FrlgFont.measure(s or "")
end

local function plain(sim, key, vars)
  return sim.hooks.plain(key, vars)
end

local function line(out, text, x, y, colors)
  out[#out + 1] = { text = text, x = x, y = y, colors = colors }
end

-- pokefirered/src/berry_crush.c:2897
local function centered(out, sim, left, colors, text)
  line(out, text, left * 4 - floor(measure(text) / 2), 0, colors)
end

-- pokefirered/src/berry_crush.c:2903
local function rows(out, sim, page, x, y)
  local res = sim.res
  local gray = textColors(sim, View.COLORID.GRAY)
  local mine = { bg = STD[1], fg = STD[8], shadow = STD[9] }
  local rankId = 0
  for i = 1, sim.n do
    local pid
    local yy = y + 14 * (i - 1)
    if page == R.PAGE_PRESSES then
      pid = res.rank0[i]
      if i ~= 1 and res.s0[i] ~= res.s0[i - 1] then rankId = i - 1 end
      local hdr = plain(sim, View.HEADERS[0])
      local realX = x - measure(hdr) - 4
      line(out, hdr, realX, yy, gray)
      line(out, string.format("%4d", res.s0[i]), realX - 24, yy, gray)
    elseif page == R.PAGE_RANDOM then
      pid = res.rank1[i]
      if i ~= 1 and res.s1[i] ~= res.s1[i - 1] then rankId = i - 1 end
      local v = res.s1[i]
      local s = plain(sim, View.HEADERS[1], {
        string.format("%3d", floor(v / 16)), string.format("%02d", R.fraction(v % 16, 4, sim.T)),
      })
      line(out, s, (x - 4) - measure(s), yy, gray)
    else
      pid = i
      rankId = i - 1
      local b = sim.A.berries[i]
      if not b or b < 0 or b >= R.NUM_BERRIES then b = 0 end
      local s = plain(sim, View.HEADERS[2], { sim.hooks.berryName(b) })
      line(out, s, x - measure(s) - 4, yy, gray)
    end
    local key = pid == sim.me and "gText_1_ClrBluShdwLtBlu_Dynamic0" or "gText_1_Dynamic0"
    local prefix = plain(sim, key)
    prefix = tostring(rankId + 1) .. prefix:sub(2)
    line(out, prefix, 4, yy, gray)
    local who = sim.players[pid]
    line(out, who and who.name or "", 4 + measure(prefix), yy, pid == sim.me and mine or gray)
  end
end

-- pokefirered/src/berry_crush.c:2971
local function crushingFooter(out, sim, h)
  local res = sim.res
  local gray = textColors(sim, View.COLORID.GRAY)
  local y = h * 8 - 42
  local m, s, f = R.framesToMinSec(res.time, sim.T)
  line(out, plain(sim, "gText_TimeColon"), 2, y, gray)
  local sec = plain(sim, "gText_SpaceSec")
  local x = 190 - measure(sec)
  line(out, sec, x, y, gray)
  x = x - 32
  line(out, plain(sim, "gText_XDotY2", { string.format("%02d", s % 100), string.format("%02d", f % 100) }), x, y, gray)
  local min = plain(sim, "gText_SpaceMin")
  x = x - (measure(min) + 3)
  line(out, min, x, y, gray)
  x = x - 9
  line(out, plain(sim, "gText_StrVar1", { tostring(m % 10) }), x, y, gray)
  y = y + 14
  line(out, plain(sim, "gText_PressingSpeed"), 2, y, gray)
  local tps = plain(sim, "gText_TimesPerSec")
  x = 190 - measure(tps)
  line(out, tps, x, y, gray)
  local speed = res.speed or 0
  local speedText = plain(sim, "gText_XDotY3", {
    string.format("%3d", floor(speed / 256)), string.format("%02d", R.fraction(speed % 256, 8, sim.T)),
  })
  x = x - 38
  line(out, speedText, x, y, res.newRecord and textColors(sim, View.COLORID.RED) or gray)
  y = y + 14
  line(out, plain(sim, "gText_Silkiness"), 2, y, gray)
  local pct = plain(sim, "gText_Var1Percent", { string.format("%3d", res.silk or 0) })
  line(out, pct, 190 - measure(pct), y, gray)
end

-- pokefirered/src/berry_crush.c:3026
function View.buildPage(sim, page)
  local T = sim.T
  local n = sim.n
  local out = {}
  local tpl, h
  if page == R.PAGE_CRUSHING then
    tpl = T.win_results[3]
    h = T.results_window_heights[2][n - 1]
    centered(out, sim, 24, textColors(sim, View.COLORID.BLUE), plain(sim, "gText_CrushingResults"))
    rows(out, sim, page, 0xC0, 0x10)
    crushingFooter(out, sim, h)
  else
    tpl = T.win_results[page + 1]
    h = T.results_window_heights[1][n - 1]
    if page == R.PAGE_PRESSES then
      centered(out, sim, 22, textColors(sim, View.COLORID.BLUE), plain(sim, "gText_PressesRankings"))
    else
      centered(out, sim, 22, textColors(sim, View.COLORID.GREEN), plain(sim, View.HEADERS[sim.res.page + 3]))
    end
    rows(out, sim, page, 0xB0, 8 * h - n * 14)
  end
  return out, { left = tpl.left, top = tpl.top, width = tpl.width, height = h }
end

-- pokefirered/src/digit_obj_util.c:206
local function drawNumber(sheet, tpl, num)
  local count = tonumber(tpl.oamCount) or 2
  local pow = 10 ^ (count - 1)
  local x = tpl.x
  local started = false
  num = floor(math.abs(tonumber(num) or 0))
  for _ = 1, count do
    local digit = floor(num / pow)
    num = num - digit * pow
    pow = pow / 10
    if tpl.strConvMode == 0 or digit ~= 0 or started or pow < 1 then
      started = true
      Art.drawFrame(sheet, digit % 10, x, tpl.y)
    end
    x = x + tpl.xDelta
  end
end

-- pokefirered/src/berry_crush.c:3201
function View.drawTimer(sim)
  local sheet = sim.art.timer_digits
  -- pokefirered/src/berry_crush.c:3347
  for i = 0, 1 do
    Art.drawFrame(sheet, View.TIMER_COLON, 24 * i + 172, 0)
  end
  local m, s, f = R.framesToMinSec(sim.timerVal, sim.T)
  local tpl = sim.T.digit_templates
  drawNumber(sheet, tpl[1], m)
  drawNumber(sheet, tpl[2], s)
  drawNumber(sheet, tpl[3], f)
end

-- pokefirered/src/berry_crush.c:3231
function View.drawNames(sim, vib)
  local nc = sim.nameColors
  if not nc then
    local pal = sim.art.namePal
    nc = { self = textColors(sim, View.COLORID.BLACK, pal), other = textColors(sim, View.COLORID.LIGHT_GRAY, pal) }
    sim.nameColors = nc
  end
  for p = 1, sim.n do
    if not sim.A.gone[p] then
      local c = sim.coords[p]
      local w = sim.T.win_player_names[c.playerId + 1]
      local name = sim.players[p].name or ""
      OPTS.colors = p == sim.me and nc.self or nc.other
      FrlgFont.draw(name, w.left * 8 + 36 - floor(measure(name) / 2), w.top * 8 + 1 + vib, OPTS)
    end
  end
end

function View.drawResults(sim, vib)
  local Window = require("src.ui.game3.window")
  local win = sim.pageWin
  if not (win and sim.pageLines) then return end
  love.graphics.push()
  love.graphics.translate(0, vib)
  Window.fixedStdFrame(Window.template(win.left, win.top, win.width, win.height))
  local ox, oy = win.left * 8, win.top * 8
  for _, l in ipairs(sim.pageLines) do
    OPTS.colors = l.colors
    FrlgFont.draw(l.text, ox + l.x, oy + l.y, OPTS)
  end
  love.graphics.pop()
end

-- pokefirered/src/new_menu_helpers.c:48
View.YES_NO = { left = 21, top = 9, width = 6, height = 4 }

function View.drawYesNo(sim, vib)
  local Window = require("src.ui.game3.window")
  local w = View.YES_NO
  love.graphics.push()
  love.graphics.translate(0, vib)
  Window.stdFrame(Window.template(w.left, w.top, w.width, w.height))
  local x, y = w.left * 8, w.top * 8 + 1
  local labels = sim.yesNoLabels
  if not labels then
    labels = { plain(sim, "gText_Yes"), plain(sim, "gText_No") }
    sim.yesNoLabels = labels
  end
  OPTS.colors = FrlgFont.COLOR.NORMAL
  for i, label in ipairs(labels) do
    local rowY = y + (i - 1) * 16
    if sim.yesNo == i - 1 then Window.cursorPx(x, rowY) end
    FrlgFont.draw(label, x + 8, rowY, OPTS)
  end
  love.graphics.pop()
end

-- pokefirered/src/berry_crush.c:2695
function View.drawBerries(sim)
  if not sim.berries then return end
  local ok, BagChrome = pcall(require, "src.ui.game3.bag_chrome")
  if not ok then return end
  for p = 1, sim.n do
    local b = sim.berries[p]
    if b and not b.destroyed then
      local img = BagChrome.iconImage(R.FIRST_BERRY + b.berry)
      if img then
        love.graphics.setColor(1, 1, 1, 1)
        local angle = -(b.rot / 0x10000) * 2 * math.pi
        love.graphics.draw(img, b.x + b.x2, b.y + b.y2, angle, 1, 1, 16, 16)
      end
    end
  end
end

function View.draw(sim)
  if not (love and love.graphics) then return end
  local g = love.graphics
  local art = sim.art
  if sim.displayOn then
    local vib = sim.vib
    local off = sim.depth + vib
    Art.drawFrame(art.bg, 0, 0, vib)
    if vib > 0 then Art.drawFrame(art.bg, 0, 0, vib - art.bg.height) end
    -- pokefirered/src/berry_crush.c:3272
    for p = 1, sim.n do
      if not sim.A.gone[p] then
        local c = sim.coords[p]
        Art.drawFrame(art.text_windows, c.playerId, c.windowGfxX * 8, c.windowGfxY * 8 + vib)
      end
    end
    for _, sp in ipairs(sim.sparkles) do
      if not sp.invisible then
        Art.drawFrame(art.sparkle, sp.anim.frame, sp.x + sp.x2 - 8, sp.y + sp.y2 - 8)
      end
    end
    -- pokefirered/src/berry_crush.c:3306
    Art.drawFrame(art.crusher_base, 0, 120 - 32, 88 - 32 + off)
    View.drawBerries(sim)
    Art.drawFrame(art.container_cap, 0, 0, vib)
    Art.drawFrame(art.crusher_top, 0, 0, off)
    for p = 1, sim.n do
      local sp = sim.impacts[p]
      if not sp.invisible then
        Art.drawFrame(art.impact, sp.anim.frame, sp.x + sp.x2 - 16, sp.y + sp.y2 - 16 + off)
      end
    end
    View.drawNames(sim, vib)
    if sim.pageOpen then View.drawResults(sim, vib) end
    if sim.printer then sim.printer:draw(vib) end
    if sim.yesNo then View.drawYesNo(sim, vib) end
    if sim.timerShown then View.drawTimer(sim) end
    local okW, W = pcall(require, "src.ui.game3.wireless_icon")
    if okW then pcall(W.draw, W.X, W.Y) end
    if sim.countdown and sim.countdown.draw then sim.countdown:draw() end
  end
  if sim.blend then
    g.setColor(sim.blend[1], sim.blend[2], sim.blend[3], 0.5)
    g.rectangle("fill", 0, 0, 240, 160)
  end
  if sim.displayOn and sim.fadeY > 0 then
    g.setColor(0, 0, 0, sim.fadeY / 16)
    g.rectangle("fill", 0, 0, 240, 160)
  end
  g.setColor(1, 1, 1, 1)
end

return View
