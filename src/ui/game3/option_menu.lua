local Stack = require("src.ui.game3.stack")
local Window = require("src.ui.game3.window")
local Options = require("src.core.game3.options")
local Rows = require("src.ui.game3.option_rows")

local OptionMenu = {}

OptionMenu.open = false
OptionMenu.cursor = 1

local VISIBLE = 7
local WIN_X, WIN_Y, WIN_W, WIN_H = 16, 56, 208, 96
local ROW_Y0 = WIN_Y + 2
local ROW_STEP = 13
local ROW_H = 14
local LABEL_X = WIN_X + 8
local VALUE_X = WIN_X + 0x82
local HELP_BG = { 0 / 255, 123 / 255, 197 / 255, 1 }
local HELP_TEXT = "{DPAD_UPDOWN}PICK {DPAD_LEFTRIGHT}SWITCH {A_BUTTON}{B_BUTTON}CANCEL"

local function ctx()
  return OptionMenu._ctx
end

local function page()
  local pages = OptionMenu._pages
  return pages and pages[#pages]
end

local function pushPage(title, rows)
  OptionMenu._pages[#OptionMenu._pages + 1] = {
    title = title, rows = rows, index = 1, scroll = 0,
  }
end

local function buildTop()
  local c = ctx()
  local flat = Rows.build(c)
  OptionMenu._flat = flat
  return Rows.group(flat, function(title, members)
    pushPage(title, members)
  end)
end

function OptionMenu.show(opts)
  opts = opts or {}
  OptionMenu.open = true
  OptionMenu._session = opts.session
  OptionMenu._onClose = opts.onClose
  local Runtime = package.loaded["src.core.game3.runtime"]
  OptionMenu._game = opts.game or (Runtime and Runtime._game)
  local engine = Options.engine(opts.session)
    or (OptionMenu._game and OptionMenu._game.options)
    or (opts.session and opts.session.options)
    or {}
  Options.bind(opts.session or {}, engine)
  OptionMenu._ctx = {
    session = opts.session,
    game = OptionMenu._game,
    options = engine,
  }
  OptionMenu._pages = {}
  pushPage("OPTION", buildTop())
  OptionMenu.cursor = 1
  Stack.push("option", OptionMenu, { hideBelow = true })
end

function OptionMenu.close()
  OptionMenu.open = false
  OptionMenu._pages = nil
  Stack.pop("option")
  local cb = OptionMenu._onClose
  OptionMenu._onClose = nil
  if cb then cb() end
end

function OptionMenu.isOpen()
  return OptionMenu.open
end

local function rowCount(p)
  return #p.rows + 1
end

local function clampScroll(p)
  local total = rowCount(p)
  if total <= VISIBLE then
    p.scroll = 0
    return
  end
  if p.index - 1 < p.scroll then p.scroll = p.index - 1 end
  if p.index > p.scroll + VISIBLE then p.scroll = p.index - VISIBLE end
  if p.scroll < 0 then p.scroll = 0 end
  if p.scroll > total - VISIBLE then p.scroll = total - VISIBLE end
end

function OptionMenu.move(delta)
  local p = page()
  if not p then return end
  local total = rowCount(p)
  p.index = ((p.index - 1 + delta) % total) + 1
  OptionMenu.cursor = p.index
  clampScroll(p)
end

local function persist()
  local c = ctx()
  local g = c and c.game
  if g and g.writeOptions then g:writeOptions() end
end

function OptionMenu.adjust(delta)
  local p = page()
  if not p then return end
  local row = p.rows[p.index]
  if not row or not row.step then return end
  if row.step(ctx(), delta) then persist() end
end

function OptionMenu.confirm()
  local p = page()
  if not p then return end
  if p.index > #p.rows then
    OptionMenu.back()
    return
  end
  local row = p.rows[p.index]
  if not row then return end
  if row.activate then
    row.activate(ctx())
    return
  end
  OptionMenu.adjust(1)
end

function OptionMenu.back()
  local pages = OptionMenu._pages
  if pages and #pages > 1 then
    pages[#pages] = nil
    local p = page()
    OptionMenu.cursor = p and p.index or 1
    return
  end
  OptionMenu.close()
end

function OptionMenu.handleInput(input)
  if not input then return end
  if input:wasPressed("up") then OptionMenu.move(-1)
  elseif input:wasPressed("down") then OptionMenu.move(1)
  elseif input:wasPressed("left") then OptionMenu.adjust(-1)
  elseif input:wasPressed("right") then OptionMenu.adjust(1)
  elseif input:wasPressed("a") then OptionMenu.confirm()
  elseif input:wasPressed("b") or input:wasPressed("start") then OptionMenu.back()
  end
end

function OptionMenu.update()
  if OptionMenu.open then
    OptionMenu._arrowK = (OptionMenu._arrowK or 0) + 1
  end
end

local function valueColors()
  local FrlgFont = require("src.ui.game3.frlg_font")
  return { fg = FrlgFont.STDPAL[5], shadow = FrlgFont.STDPAL[4], bg = FrlgFont.STDPAL[0] } -- src/option_menu.c:180
end

-- src/menu_indicators.c:289
local function bob(k, freq)
  local Trig = require("src.core.game3.trig")
  local v = Trig.sin(((k or 0) * freq) % 256) * 2 / 256
  return v < 0 and math.ceil(v) or math.floor(v)
end

local function scrollArrow(dir, x, y)
  local ok, BagChrome = pcall(require, "src.ui.game3.bag_chrome")
  if ok and BagChrome and BagChrome.drawArrow then
    local drew, res = pcall(BagChrome.drawArrow, dir, x, y)
    if drew and res then return end
  end
  local FrlgFont = require("src.ui.game3.frlg_font")
  FrlgFont.drawGlyph(dir == "up" and FrlgFont.CHAR_UP_ARROW or FrlgFont.CHAR_DOWN_ARROW,
    x + 4, y + 1, { colors = FrlgFont.COLOR.RED })
end

-- src/option_menu.c:316
local function drawHelpBar()
  love.graphics.setColor(HELP_BG)
  love.graphics.rectangle("fill", 0, 0, 240, 16)
  love.graphics.setColor(1, 1, 1, 1)
  local PokedexChrome = require("src.ui.game3.pokedex_chrome")
  PokedexChrome.drawControlInfo(HELP_TEXT, 0xE4, 0)
end

function OptionMenu.draw()
  if not OptionMenu.open then return end
  local p = page()
  if not p then return end
  local c = ctx()
  local Chrome = require("src.ui.game3.chrome")
  local FrlgFont = require("src.ui.game3.frlg_font")

  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("fill", 0, 0, 240, 160)
  love.graphics.setColor(1, 1, 1, 1)
  drawHelpBar()

  Chrome.fixedStdFrame(2, 3, 26, 2) -- src/option_menu.c:537
  Window.printPx(p.title or "OPTION", 16 + 8, 24 + 1, { colors = FrlgFont.COLOR.NORMAL })

  local frameType = tonumber(Options.block(c.options).frameType) or 0
  Window.userFrame(Window.template(2, 7, 26, 12), frameType)

  local total = rowCount(p)
  clampScroll(p)
  local vcol = valueColors()
  for slot = 1, VISIBLE do
    local idx = p.scroll + slot
    if idx <= total then
      local y = ROW_Y0 + (slot - 1) * ROW_STEP -- src/option_menu.c:563
      if idx > #p.rows then
        Window.printPx("CANCEL", LABEL_X, y, { colors = FrlgFont.COLOR.NORMAL })
      else
        local row = p.rows[idx]
        Window.printPx(row.label or "?", LABEL_X, y, { colors = FrlgFont.COLOR.NORMAL })
        if row.value then
          local ok, text = pcall(row.value, c)
          Window.printPx(ok and tostring(text) or "----", VALUE_X, y, { colors = vcol })
        end
      end
    end
  end

  -- src/option_menu.c:572
  local selTop = ROW_Y0 + (p.index - p.scroll - 1) * ROW_STEP
  local selBot = selTop + ROW_H
  love.graphics.setColor(0, 0, 0, 2 / 16)
  if selTop > WIN_Y then
    love.graphics.rectangle("fill", WIN_X, WIN_Y, WIN_W, selTop - WIN_Y)
  end
  if selBot < WIN_Y + WIN_H then
    love.graphics.rectangle("fill", WIN_X, selBot, WIN_W, WIN_Y + WIN_H - selBot)
  end
  love.graphics.setColor(1, 1, 1, 1)

  if total > VISIBLE then
    local k = OptionMenu._arrowK or 0
    if p.scroll > 0 then
      scrollArrow("up", 208, WIN_Y + bob(k, 8))
    end
    if p.scroll + VISIBLE < total then
      scrollArrow("down", 208, WIN_Y + WIN_H - 16 + bob(k, -8))
    end
  end
end

return OptionMenu
