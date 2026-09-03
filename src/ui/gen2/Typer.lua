-- ../pokecrystal/home/print_text.asm:1 PrintLetterDelay
-- ../pokecrystal/home/text.asm:660 PrintTextboxTextAt

local Font = require("src.render.Font")

local Typer = {}
Typer.__index = Typer

-- ../pokecrystal/home/print_text.asm:5
local DELAYS = { FAST = 1, MID = 3, SLOW = 5 }

local function spansOf(text)
  if Font.split then return Font.split(text) end
  local spans = {}
  local i, n = 1, #text
  while i <= n do
    local last = i
    if text:byte(i) >= 0xC0 then
      local k = i + 1
      while k <= n do
        local b = text:byte(k)
        if b < 0x80 or b > 0xBF then break end
        last, k = k, k + 1
      end
    end
    spans[#spans + 1] = { from = i, to = last }
    i = last + 1
  end
  return spans
end

local function linesOf(page)
  if page == nil then return {} end
  if type(page) == "string" then
    local lines = {}
    for part in (page .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = part end
    return lines
  end
  return page
end

-- ../pokecrystal/engine/events/pokecenter_pc.asm:314
function Typer.new(game, opts)
  opts = opts or {}
  return setmetatable({
    game = game,
    speed = opts.speed,
    instant = opts.instant and true or false,
    expand = opts.expand,
    shown = 0,
    total = 0,
    timer = 0,
    page = {},
  }, Typer)
end

-- ../pokecrystal/home/text.asm:520 _ContTextNoPause
function Typer:start(page)
  local out, total, kept = {}, 0, 0
  local scrolled = type(page) == "table" and page.scrolled
  for i, line in ipairs(linesOf(page)) do
    local text = self.expand and self.expand(line) or line
    out[i] = text
    local n = #spansOf(text)
    total = total + n
    if scrolled and i == 1 then kept = n end
  end
  self.page = out
  self.total = total
  self.shown = self.instant and total or kept
  self.timer = 0
end

-- ../pokecrystal/home/print_text.asm:52
function Typer:delay()
  if self.instant then return 0 end
  local options = self.game and self.game.save and self.game.save.options
  local raw = self.speed or (options and options.textSpeed)
  local delay = DELAYS[raw] or tonumber(raw) or 3
  if delay ~= 1 and delay ~= 3 and delay ~= 5 then delay = 3 end
  local input = self.game and self.game.input
  if input and input.isDown
    and (input:isDown("a") or input:isDown("b")) then
    delay = 1
  end
  return delay
end

function Typer:done()
  return self.shown >= self.total
end

function Typer:tick()
  if self:done() then return true end
  local delay = self:delay()
  if delay <= 0 then
    self.shown = self.total
    return true
  end
  if self.timer >= delay then self.timer = delay - 1 end
  self.timer = self.timer + 1
  while self.timer >= delay and self.shown < self.total do
    self.timer = self.timer - delay
    self.shown = self.shown + 1
  end
  return self:done()
end

function Typer:lines()
  if self:done() then return self.page end
  local out, left = {}, self.shown
  for i, line in ipairs(self.page) do
    local spans = spansOf(line)
    if left >= #spans then
      out[i] = line
    elseif left <= 0 then
      out[i] = ""
    else
      out[i] = line:sub(1, spans[left].to)
    end
    left = left - #spans
  end
  return out
end

-- ../pokecrystal/home/menu.asm:328
function Typer.say(screen, pages, onDone, opts)
  screen.message = { pages = pages or {}, page = 1, onDone = onDone }
  screen.typer = Typer.new(screen.game, opts)
  screen.typer:start(screen.message.pages[1])
  return screen.message
end

function Typer.begin(screen, record, opts)
  screen.typer = Typer.new(screen.game, opts)
  screen.typer:start(record.pages and record.pages[record.page or 1])
  return record
end

function Typer.turn(screen, record)
  record.page = record.page + 1
  if screen.typer then screen.typer:start(record.pages[record.page]) end
end

function Typer.step(screen)
  screen.arrowBlink = ((screen.arrowBlink or 0) + 1) % 32
  local typer = screen.typer
  if not typer then return true end
  return typer:tick()
end

-- ../pokegold/home/joypad.asm:430
function Typer.arrowOn(screen)
  return ((screen.arrowBlink or 0) % 32) < 16
end

-- ../pokecrystal/home/print_text.asm:59
function Typer.typing(screen)
  local typer = screen.typer
  return typer ~= nil and not typer:done()
end

function Typer.text(screen, fallback)
  local typer = screen.typer
  if not typer then return fallback end
  return typer:lines()
end

Typer.DELAYS = DELAYS

return Typer
