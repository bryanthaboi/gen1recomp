local R = require("src.core.game3.minigames.dodrio_berry_picking.rules")
local Common = require("src.ui.game3.minigames.common_art")

local Draw = {}

-- pokefirered/src/dodrio_berry_picking.c:4263
Draw.RANK_TEXTS = { "gText_1Colon", "gText_2Colon", "gText_3Colon", "gText_4Colon", "gText_5Colon" }
-- pokefirered/src/dodrio_berry_picking.c:3130
Draw.RESULTS_WIN = { { 1, 1, 28, 3 }, { 1, 6, 28, 13 } }
-- pokefirered/src/dodrio_berry_picking.c:3152
Draw.PRIZE_WIN = { 1, 6, 28, 7 }
-- pokefirered/src/dodrio_berry_picking.c:3201
Draw.STANDBY_WIN = { 5, 8, 19, 3 }
-- pokefirered/src/dodrio_berry_picking.c:3168
Draw.PLAY_AGAIN_WIN = { 1, 8, 19, 3 }
Draw.YES_NO_WIN = { 22, 7, 6, 4 }
-- pokefirered/src/dodrio_berry_picking.c:3190
Draw.DROPPED_WIN = { 4, 6, 22, 5 }
-- pokefirered/src/dodrio_berry_picking.c:4366
Draw.NAME_W, Draw.NAME_H = 7, 2

local function mods()
  return require("src.ui.game3.frlg_font"), require("src.ui.game3.chrome"), require("src.core.game3.rom_text")
end

local colorCache = nil

-- pokefirered/src/dodrio_berry_picking.c:4240
local function colors(T)
  if colorCache and colorCache.T == T then return colorCache end
  local FrlgFont = mods()
  local out = { T = T }
  for i, row in ipairs(T.text_colors) do
    out[i - 1] = { bg = FrlgFont.STDPAL[0], fg = FrlgFont.STDPAL[row[2]], shadow = FrlgFont.STDPAL[row[3]] }
  end
  colorCache = out
  return out
end

local function text(key, ctx)
  local _, _, RomText = mods()
  local ok, s = pcall(RomText.plain, key, ctx)
  if ok and type(s) == "string" then return s end
  return ""
end

local function small(str, x, y, col)
  local FrlgFont = mods()
  FrlgFont.draw(str, x, y, { small = true, colors = col or FrlgFont.COLOR.NORMAL, maxWidth = 240 })
end

local function width(str)
  local FrlgFont = mods()
  return FrlgFont.measure(str, { small = true })
end

local function frame(win)
  local _, Chrome = mods()
  Chrome.fixedStdFrame(win[1], win[2], win[3], win[4])
end

local function sprite(sheet, index, x, y)
  Common.drawFrame(sheet, index, x, y)
end

function Draw.clouds(sim, art)
  local c = sim.clouds
  if not c.visible then return end
  for s = 1, 2 do
    local lx = (c.x[s] - 32) % 512
    if lx >= 256 then lx = lx - 512 end
    local ty = (c.y[s] - 16) % 256
    if ty >= 160 then ty = ty - 256 end
    sprite(art.cloud, 0, lx, ty)
  end
end

-- pokefirered/src/dodrio_berry_picking.c:3572
function Draw.dodrios(sim, art)
  for pos = sim.n - 1, 0, -1 do
    local p = (sim.me + pos) % sim.n
    local x = R.dodrioX(pos, sim.n)
    if pos == 0 then x = x + sim.own.dx end
    local sheet = sim:isShiny(p) and art.dodrio_shiny or art.dodrio
    sprite(sheet, sim:dodrioPose(p), x - 32, sim.DODRIO_Y - 32)
  end
end

-- pokefirered/src/dodrio_berry_picking.c:2151
function Draw.berryCell(sim, pos)
  local v = sim:displayView()
  local column = sim:column(pos)
  local f = v.fall[column] or 0
  if f == 0 then return nil end
  local id = v.ids[column] or 0
  if f >= R.MAX_FALL_DIST then
    return id + R.BERRY_MISSED, pos * 24 - 8, (f * 2 - 1) * 8 - 8
  elseif id == R.BERRY_MISSED then
    return R.BERRY_MISSED * 2, pos * 24 - 8, (R.EAT_FALL_DIST * 2 - 1) * 8 - 8
  end
  return id, pos * 24 - 8, f * 2 * 8 - 8
end

function Draw.berries(sim, art)
  for pos = sim.stop - 1, sim.start, -1 do
    local anim, x, y = Draw.berryCell(sim, pos)
    if anim then sprite(art.berries, anim, x, y) end
  end
end

-- pokefirered/src/dodrio_berry_picking.c:1848
function Draw.trees(sim, art)
  local h = sim.intro.hofs
  love.graphics.setColor(1, 1, 1, 1)
  if art.tree_border_right.image then love.graphics.draw(art.tree_border_right.image, h, 0) end
  if art.tree_border_left.image then love.graphics.draw(art.tree_border_left.image, -h, 0) end
end

-- pokefirered/src/dodrio_berry_picking.c:4353
function Draw.names(sim)
  local T = sim.T
  local coords = T.name_window_coords[sim.n]
  local col = colors(T)
  for pos = 0, sim.n - 1 do
    local c = coords[pos + 1]
    local p = (sim.me + pos) % sim.n
    frame({ c.left, c.top, Draw.NAME_W, Draw.NAME_H })
    local name = sim.names[p] or ""
    local x = math.floor((56 - width(name)) / 2)
    small(name, c.left * 8 + x, c.top * 8 + 1, p == sim.me and col[2] or col[0])
  end
end

local function centered(key, win)
  local s = text(key)
  local x = math.floor((240 - 16 - width(s)) / 2)
  small(s, win[1] * 8 + x, win[2] * 8 + 2, nil)
end

-- pokefirered/src/dodrio_berry_picking.c:4503
function Draw.resultsTable(sim)
  local rs = sim.rs
  local T = sim.T
  local col = colors(T)
  local w1 = Draw.RESULTS_WIN[2]
  local ox, oy = w1[1] * 8, w1[2] * 8
  frame(Draw.RESULTS_WIN[1])
  frame(w1)
  centered("gText_BerryPickingResults", Draw.RESULTS_WIN[1])
  small(text("gText_10P30P50P50P"), ox + 68, oy + 16, col[0])
  for p = 0, sim.n - 1 do
    local y = oy + T.results_y[p + 1]
    small(sim.names[p] or "", ox + 2, y, p == sim.me and col[2] or col[0])
    for j = 0, 3 do
      local val = math.min(rs.res[p][j] or 0, R.MAX_BERRIES)
      local best = math.min(R.highestResult(rs.res, sim.n, j), R.MAX_BERRIES)
      local s = tostring(val)
      local x = ox + T.results_x[j + 1] - width(s)
      small(s, x, y, (best == val and best ~= 0) and col[1] or col[0])
    end
  end
end

-- pokefirered/src/dodrio_berry_picking.c:3933
function Draw.berryIcons(sim, art)
  local T = sim.T
  for j = 0, 3 do
    local y = (j == R.BERRY_MISSED) and 57 or 60
    sprite(art.berries, j, T.berry_icon_x[j + 1] - 8, y - 8)
  end
end

-- pokefirered/src/dodrio_berry_picking.c:4417
function Draw.rankings(sim)
  local rs = sim.rs
  local T = sim.T
  local col = colors(T)
  local w1 = Draw.RESULTS_WIN[2]
  local ox, oy = w1[1] * 8, w1[2] * 8
  frame(Draw.RESULTS_WIN[1])
  frame(w1)
  centered("gText_AnnouncingRankings", Draw.RESULTS_WIN[1])
  local points = text("gText_SpacePoints")
  local x = 216 - width(points)
  for i, row in ipairs(rs.rows or {}) do
    local y = oy + T.ranking_y[i]
    small(text(Draw.RANK_TEXTS[row.ranking + 1] or Draw.RANK_TEXTS[5]), ox + 8, y, col[0])
    small(sim.names[row.player] or "", ox + 28, y, row.player == sim.me and col[2] or col[0])
    small(string.format("%7d", row.score), ox + x - 35, y, col[0])
    small(points, ox + x, y, col[0])
  end
end

-- pokefirered/src/dodrio_berry_picking.c:4602
function Draw.prize(sim)
  local rs = sim.rs
  local win = Draw.PRIZE_WIN
  local ox, oy = win[1] * 8, win[2] * 8
  frame(Draw.RESULTS_WIN[1])
  frame(win)
  centered("gText_AnnouncingPrizes", Draw.RESULTS_WIN[1])
  local item = R.prizeItem(rs.prize)
  local okI, Items = pcall(require, "src.core.game3.items")
  local name = okI and Items.displayName(item) or ""
  small(text("gText_FirstPlacePrize", { dynamic = { [0] = name } }), ox + 8, oy + 2, nil)
  local state = rs.prizeState
  if state == R.PRIZE_NO_ROOM then
    small(text("gText_CantHoldAnyMore", { dynamic = { [0] = name } }), ox + 8, oy + 40, nil)
  elseif state == R.PRIZE_FILLED_BAG then
    small(text("gText_FilledStorageSpace", { dynamic = { [0] = name } }), ox + 8, oy + 40, nil)
  end
end

local function normal(key, win, x, y)
  local FrlgFont = mods()
  FrlgFont.draw(text(key), win[1] * 8 + x, win[2] * 8 + y,
    { colors = FrlgFont.COLOR.NORMAL, maxWidth = 240 })
end

-- pokefirered/src/dodrio_berry_picking.c:4787
function Draw.standby()
  local win = Draw.STANDBY_WIN
  frame(win)
  normal("gText_CommunicationStandby3", win, 0, 6)
end

-- pokefirered/src/dodrio_berry_picking.c:4755
function Draw.saving()
  local FrlgFont, Chrome = mods()
  Chrome.dialogueFrame()
  FrlgFont.draw(text("gText_SavingDontTurnOffThePower2"), Chrome.DLG_LEFT * 8, Chrome.DLG_TOP * 8 + 1,
    { colors = FrlgFont.COLOR.NORMAL, maxWidth = Chrome.DLG_W * 8 })
end

-- pokefirered/src/dodrio_berry_picking.c:4660
function Draw.ask(sim)
  local FrlgFont, Chrome = mods()
  local msg, yn = Draw.PLAY_AGAIN_WIN, Draw.YES_NO_WIN
  frame(msg)
  normal("gText_WantToPlayAgain", msg, 0, 6)
  Chrome.stdFrame(yn[1], yn[2], yn[3], yn[4])
  normal("gText_Yes", yn, 8, 2)
  normal("gText_No", yn, 8, 16)
  local y = (sim.rs.cursor == 2) and 16 or 2
  normal("gText_SelectorArrow2", yn, 0, y)
end

-- pokefirered/src/dodrio_berry_picking.c:4824
function Draw.dropped()
  local win = Draw.DROPPED_WIN
  frame(win)
  normal("gText_SomeoneDroppedOut", win, 0, 6)
end

function Draw.status(sim, art)
  local s = sim.status
  if not s.visible then return end
  for i = 0, R.NUM_STATUS_SQUARES - 1 do
    sprite(art.status, s.bar.frames[i] or 0, 40 + i * 16, s.y[i] - 8)
  end
end

function Draw.draw(sim, art)
  if not (art and love and love.graphics) then return end
  local lg = love.graphics
  lg.setColor(art.backdrop)
  lg.rectangle("fill", 0, 0, 240, 160)
  lg.setColor(1, 1, 1, 1)
  Draw.clouds(sim, art)
  if art.scenery then
    lg.setColor(1, 1, 1, 1)
    lg.draw(art.scenery, 0, 0)
  end
  Draw.dodrios(sim, art)
  Draw.berries(sim, art)
  Draw.trees(sim, art)
  local rs = sim.rs
  if sim.intro.names then Draw.names(sim) end
  if rs then
    if rs.show == "results" then
      Draw.resultsTable(sim)
    elseif rs.show == "rankings" then
      Draw.rankings(sim)
    elseif rs.show == "prize" then
      Draw.prize(sim)
    elseif rs.show == "standby" then
      Draw.standby()
    elseif rs.show == "saving" then
      Draw.saving()
    elseif rs.show == "ask" then
      Draw.ask(sim)
    elseif rs.show == "dropped" then
      Draw.dropped()
    end
  end
  Draw.status(sim, art)
  if rs and rs.icons and rs.show == "results" then Draw.berryIcons(sim, art) end
  if sim.countdown and sim.countdown.draw then sim.countdown:draw() end
  if sim:displayed() then
    pcall(function() require("src.ui.game3.wireless_icon").draw() end)
  end
  if (sim.fadeY or 0) > 0 then
    lg.setColor(0, 0, 0, math.min(1, sim.fadeY / 16))
    lg.rectangle("fill", 0, 0, 240, 160)
  end
  lg.setColor(1, 1, 1, 1)
end

return Draw
