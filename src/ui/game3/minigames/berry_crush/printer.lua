local TextIR = require("src.core.game3.scripting.text_ir")
local FrlgFont = require("src.ui.game3.frlg_font")

local Printer = {}
Printer.__index = Printer

-- pokefirered/src/berry_crush.c:1138
Printer.SPEEDS = { [0] = 8, [1] = 4, [2] = 1 }
-- pokefirered/include/constants/songs.h:9
Printer.SE_SELECT = 5
-- pokefirered/src/text.c:721
Printer.EXT_PLAY_BGM = 0x0B
-- pokefirered/src/text.c:751
Printer.EXT_PAUSE_MUSIC = 0x17
-- pokefirered/src/text.c:754
Printer.EXT_RESUME_MUSIC = 0x18

local ARROW_SEQ = { 0, 1, 2, 3, 2, 1 }

local MUSIC_EXT = {
  [Printer.EXT_PLAY_BGM] = true, [Printer.EXT_PAUSE_MUSIC] = true, [Printer.EXT_RESUME_MUSIC] = true,
}

function Printer.speedFor(optionIndex)
  local s = Printer.SPEEDS[tonumber(optionIndex) or 1] or 4
  return s
end

local function pageEvents(page)
  local ev, i, n = nil, 1, #page
  while true do
    local at = page:find("\252", i, true)
    if not at or at >= n then break end
    local cmd = page:byte(at + 1)
    if MUSIC_EXT[cmd] then
      local arg = 0
      if cmd == Printer.EXT_PLAY_BGM then arg = (page:byte(at + 2) or 0) + (page:byte(at + 3) or 0) * 256 end
      ev = ev or {}
      ev[#ev + 1] = { at = FrlgFont.countChars(page:sub(1, at - 1)), cmd = cmd, arg = arg }
    end
    i = at + 2 + (TextIR.EXT_ARGS[cmd] or 0)
  end
  return ev
end

-- pokefirered/src/berry_crush.c:1250
function Printer.new(text, speed, opts)
  opts = opts or {}
  local split = TextIR.splitPages(text or "", true)
  local waitEnd = #split > 1 and split[#split] == ""
  local pages = {}
  for _, page in ipairs(split) do
    if page ~= "" then pages[#pages + 1] = page end
  end
  if #pages == 0 then pages[1] = "" end
  local self = setmetatable({
    pages = pages, page = 1, revealed = 0, delay = 0,
    speed = tonumber(speed) or 4, prompt = false, finished = false, shown = false,
    waitEnd = waitEnd, cleared = false,
    doneFrames = 0, clear = opts.clear and true or false, frames = 0,
    playSe = opts.playSe, music = opts.music,
    events = {}, evi = 1,
    drawOpts = { maxWidth = 0, limitChars = 0, colors = FrlgFont.COLOR.NORMAL },
  }, Printer)
  for p, page in ipairs(pages) do self.events[p] = pageEvents(page) or false end
  self:startPage()
  return self
end

function Printer:text()
  if self.cleared then return "" end
  return self.pages[self.page] or ""
end

-- pokefirered/src/text.c:670
function Printer:fire()
  local ev = self.events[self.page]
  if not ev then return end
  while ev[self.evi] and ev[self.evi].at <= self.revealed do
    local e = ev[self.evi]
    self.evi = self.evi + 1
    if self.music then self.music(e.cmd, e.arg) end
  end
end

function Printer:startPage()
  self.revealed = 0
  self.delay = 0
  self.evi = 1
  self.total = FrlgFont.countChars(self:text())
  self:fire()
  if self.total == 0 then self:pageEnd() end
end

function Printer:pageEnd()
  if self.page < #self.pages then
    self.prompt = true
  elseif self.waitEnd then
    self.prompt = true
    self.shown = true
  else
    self.finished = true
    self.shown = true
  end
end

-- pokefirered/src/text.c:629
function Printer:tick(input)
  self.frames = self.frames + 1
  if self.finished then
    self.doneFrames = self.doneFrames + 1
    return
  end
  if self.prompt then
    if input and input.wasPressed and (input:wasPressed("a") or input:wasPressed("b")) then
      if self.playSe then self.playSe(Printer.SE_SELECT) end
      self.prompt = false
      if self.page >= #self.pages then
        -- pokefirered/src/text.c:863
        self.cleared = true
        self.revealed = 0
        self.finished = true
        return
      end
      self.page = self.page + 1
      self:startPage()
    end
    return
  end
  if self.delay > 0 then
    self.delay = self.delay - 1
    return
  end
  self.revealed = self.revealed + 1
  self:fire()
  if self.revealed >= self.total then
    self:pageEnd()
  else
    local d = self.speed
    if d > 0 then d = d - 1 end
    self.delay = d
  end
end

function Printer:done()
  return self.finished and self.doneFrames >= 2
end

function Printer:printed()
  return self.shown
end

function Printer:draw(vib)
  local Window = require("src.ui.game3.window")
  local Chrome = require("src.ui.game3.chrome")
  local T = 8
  love.graphics.push()
  love.graphics.translate(0, vib or 0)
  Window.dialogueFrame()
  local x = Chrome.DLG_LEFT * T
  local y = Chrome.DLG_TOP * T + 1
  local o = self.drawOpts
  o.maxWidth = Chrome.DLG_W * T
  o.limitChars = self.revealed
  local _, endX, endY = FrlgFont.draw(self:text(), x, y, o)
  if self.prompt then
    local frame = ARROW_SEQ[1 + math.floor(self.frames / 8) % #ARROW_SEQ]
    local ax = (endX or (x + 16)) + 2
    if ax + 10 > x + Chrome.DLG_W * T then ax = x + Chrome.DLG_W * T - 10 end
    Chrome.promptArrow(ax, endY or y, frame)
  end
  love.graphics.pop()
end

return Printer
