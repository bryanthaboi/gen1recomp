-- The clock-setting screens (pokegold engine/rtc/timeset.asm).
--
-- Two screens out of one file, because the cart builds them out of one set of
-- pieces: a Textbox with an up arrow above the value and a down arrow below
-- it, the d-pad walking the value with wraparound, A confirming, and a YES/NO
-- box that either takes the answer or drops back to the picker.
--
--   mode "clock"  InitClock, the first thing OakSpeech does
--                 (engine/menus/intro_menu.asm OakSpeech: `farcall InitClock`).
--                 Oak asks the hour, confirms it, asks the minutes, confirms
--                 them, and reads the whole time back.
--   mode "day"    SetDayOfWeek, the wheel Mom puts up when she hands over the
--                 POKeGEAR (maps/PlayersHouse1F.asm `special SetDayOfWeek`).
--
-- Layout, transcribed from the hlcoord calls:
--   clock hour     Textbox (3,7) 2x15, up arrow (11,7), down (11,10),
--                  "<hour> o'clock" at (4,9)
--   clock minutes  Textbox (11,7) 2x7, up arrow (15,7), down (15,10),
--                  "<mm> min." at (12,9)
--   day            Textbox (9,3) 2x9, up arrow (14,3), down (14,6),
--                  the weekday at (10,5), question in the (0,12) 4x18 box
--
-- The answer is written through src/core/gen2/Clock.lua, which stores the same
-- wStartHour / wStartMinute / wStartDay base the cart does.

local Chrome = require("src.ui.gen2.Chrome")
local Clock = require("src.core.gen2.Clock")
local GbcPalette = require("src.render.GbcPalette")
local IntroFade = require("src.ui.gen2.IntroFade")
local Strings = require("src.core.Strings")
local Typer = require("src.ui.gen2.Typer")

local InitClock = {}
InitClock.__index = InitClock
InitClock.isOpaque = true

-- data/text/common_1.asm.  None of these are extracted: PrintText reaches them
-- from engine code, so no script pointer walks them and the extractor never
-- sees them.
local TEXT = {
  wokeUp = Strings.source(
    "Zzz... Hm? Wha...?\nYou woke me up!"
    .. "\fWill you check the\nclock for me?"),
  whatTime = Strings.source("What time is it?"),
  whatHours = Strings.source("What?\n%s?"),
  howManyMinutes = Strings.source("How many minutes?"),
  whoaMinutes = Strings.source("Whoa!\n%d min.?"),
  -- OakText_ResponseToSetTime prints the time it has just been given and then
  -- picks its line off the hour: NITE and before MORN_HOUR is "So dark...",
  -- through DAY_HOUR is "I overslept!", and the rest of the day is "Yikes!".
  soDark = Strings.source("%s!\nIt's so dark!"),
  overslept = Strings.source("%s!\nI overslept!"),
  yikes = Strings.source("%s!\nYikes! I over-\nslept!"),
  whatDay = Strings.source("What day is it?"),
  confirmDay = Strings.source("%s, is that right?"),
}
InitClock.TEXT = TEXT

-- constants/misc_constants.asm:37-39.  DAY_HOUR is 10, not 9: it read 9 here,
-- which moved Oak's line an hour early -- 10 o'clock answered "Yikes! I
-- overslept!" where OakText_ResponseToSetTime's `cp DAY_HOUR + 1` still puts
-- it in the plain "I overslept!" arm.  src/world/gen2/Palettes.lua carries the
-- same three and has always had them right.
local MORN_HOUR, DAY_HOUR, NITE_HOUR = 4, 10, 18

-- ../pokecrystal/engine/rtc/timeset.asm:24
InitClock.GROUND = { 0, 0, 0 }

-- pokecrystal/engine/gfx/cgb_layouts.asm:509-521
InitClock.PALETTE = {
  { 222, 255, 222 }, { 173, 173, 173 }, { 107, 107, 107 }, { 0, 0, 0 },
}

-- Clock.DAY_NAMES / Clock.weekdayName is the single translated home for this
-- table: MainMenu's clock box and the Pokegear's clock card read the same
-- weekday off the same save and must never disagree about what it is
-- called.
local DAYS = Clock.DAY_NAMES
InitClock.DAYS = DAYS

-- ../pokecrystal/engine/rtc/timeset.asm:385
function InitClock:wantsFillScale() return self.mode ~= "day" end
function InitClock:drawsWidescreen() return self.mode ~= "day" end

-- PrintHour (engine/rtc/timeset.asm:672) is GetTimeOfDayString + PlaceString,
-- then AdjustHourForAMorPM as a left-aligned two-digit number.  So the cart
-- prints the time-of-day WORD and a 1-12 hour -- "MORN 5" -- and never an
-- AM/PM suffix.  Writing it as "5 AM" was what put the meridiem in the middle
-- of the clock-set line, because InitClock.timeString appends ":mm" to this
-- and Oak came out saying "5 AM:30".
--
-- AdjustHourForAMorPM still governs the number: 0 shows as 12, 13-23 lose 12,
-- so midnight is "NITE 12" and not "NITE 0".
--
-- The word comes from src/world/gen2/Palettes.lua:clockDaytime, which already
-- transcribes GetTimeOfDayString's own ladder (NITE below MORN_HOUR, MORN
-- below DAY_HOUR, DAY below NITE_HOUR, NITE after) off the real constants.
-- One source for it means the clock Oak reads out cannot disagree with the
-- palette the world is lit by.
function InitClock.hourString(hour)
  local h = math.floor(hour or 0) % 24
  local display = h % 12
  if display == 0 then display = 12 end
  -- Clock.daytimeLabel, not Palettes.clockDaytime: the printed word,
  -- translated -- this string reaches the player as-is, unlike the internal
  -- MORN/DAY/NITE key other palette code compares against.
  local word = Clock.daytimeLabel(h)
  return ("%s %d"):format(word, display)
end

function InitClock.oclockString(hour)
  return Strings("%s o'clock", InitClock.hourString(hour))
end

function InitClock.timeString(hour, minute)
  return ("%s:%02d"):format(InitClock.hourString(hour),
    math.floor(minute or 0) % 60)
end

-- .OakTimeSoDarkText / .OakTimeOversleptText / .OakTimeYikesText, in the ladder
-- OakText_ResponseToSetTime walks them in.
function InitClock.responseKey(hour)
  local h = math.floor(hour or 0) % 24
  if h < MORN_HOUR then return "soDark" end
  if h <= DAY_HOUR then return "overslept" end
  if h < NITE_HOUR then return "yikes" end
  return "soDark"
end

-- opts: mode ("clock" | "day"), save, onDone(hour, minute) / onDone(day),
-- autoConfirm (a driver's deterministic path: every step takes its default and
-- answers YES).
function InitClock.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, InitClock)
  self.game = game
  self.mode = opts.mode == "day" and "day" or "clock"
  -- ../pokecrystal/engine/rtc/timeset.asm:385
  self.isOpaque = self.mode ~= "day"
  self.save = opts.save or (game and game.save)
  self.onDone = opts.onDone
  self.autoConfirm = opts.autoConfirm or false
  self.hour = opts.hour or Clock.DEFAULT_HOUR
  self.minute = opts.minute or Clock.DEFAULT_MINUTE
  -- `xor a / ld [wTempDayOfWeek], a`: the wheel opens on SUNDAY.
  self.day = opts.day or 0
  -- YesNoBox's cursor, which opens on YES.
  self.yesNo = 1
  -- The cart opens on the "you woke me up" page and only then starts asking;
  -- the day wheel has no preamble.
  self.phase = self.mode == "day" and "day" or "intro"
  -- Which page of the current question is showing.  PrintText pages a `para`
  -- (a \f here) on a button press like any other text box, and Oak's opening
  -- is three lines long over two of them.
  self.page = 1
  -- ../pokecrystal/home/print_text.asm:5
  self.typer = Typer.new(game, {
    instant = self.autoConfirm or self.mode == "day",
  })
  self:startText()
  self.fades = opts.fades and self.mode ~= "day" and not self.autoConfirm
  if self.fades then
    -- ../pokecrystal/engine/rtc/timeset.asm:22, :42
    if opts.faded then
      IntroFade.run(self, { "inBlack" })
    else
      -- ../pokecrystal/engine/menus/intro_menu.asm:42-49, :65
      self.blank = true
      IntroFade.run(self, { "outBlack" }, function()
        self.blank = false
        IntroFade.run(self, { "inBlack" })
      end)
    end
  end
  return self
end

function InitClock:startText()
  if self.typer then self.typer:start(self:pageText()) end
end

-- The current question, split into its pages.
function InitClock:pages()
  local question = self:question()
  if self.pagesText == question and self.pagesCache then
    return self.pagesCache
  end
  local out = {}
  for page in (question .. "\f"):gmatch("(.-)\f") do
    if page ~= "" then
      local lines = {}
      for line in (page .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
      -- ../pokecrystal/home/text.asm:502
      out[#out + 1] = table.concat({ lines[1], lines[2] }, "\n")
      for i = 3, #lines do
        out[#out + 1] = table.concat({ lines[i - 1], lines[i] }, "\n")
      end
    end
  end
  if #out == 0 then out[1] = "" end
  self.pagesText, self.pagesCache = question, out
  return out
end

function InitClock:pageText()
  local pages = self:pages()
  return pages[math.min(self.page, #pages)] or ""
end

-- True while there is another page of the same question to show.
function InitClock:morePages()
  return self.page < #self:pages()
end

-- The value the picker is walking right now, and its wrap limit.
function InitClock:value()
  if self.phase == "hour" then return self.hour, 23 end
  if self.phase == "minute" then return self.minute, 59 end
  return self.day, 6
end

function InitClock:step(delta)
  local value, last = self:value()
  -- .AdvanceThroughMidnight / .DecreaseThroughMidnight: both ends wrap.
  value = (value + delta) % (last + 1)
  if self.phase == "hour" then self.hour = value
  elseif self.phase == "minute" then self.minute = value
  else self.day = value end
end

-- The line printed above the picker.
function InitClock:question()
  if self.phase == "intro" then return Strings(TEXT.wokeUp) end
  if self.phase == "hour" then return Strings(TEXT.whatTime) end
  if self.phase == "minute" then return Strings(TEXT.howManyMinutes) end
  if self.phase == "day" then return Strings(TEXT.whatDay) end
  if self.phase == "confirm-hour" then
    return Strings(TEXT.whatHours, InitClock.oclockString(self.hour))
  end
  if self.phase == "confirm-minute" then
    return Strings(TEXT.whoaMinutes, self.minute)
  end
  if self.phase == "confirm-day" then
    return Strings(TEXT.confirmDay, Clock.weekdayName(self.day + 1) or "?")
  end
  if self.phase == "response" then
    return Strings(TEXT[InitClock.responseKey(self.hour)],
      InitClock.timeString(self.hour, self.minute))
  end
  return ""
end

-- data/text/common_1.asm's "@MIN." suffix (DisplayMinutesWithMinString),
-- separate from TEXT.whoaMinutes' own "%d min.?" confirmation line above.
local MINUTES = Strings.source("%d min.")

-- The value the picker box shows, or nil while a page is up with no picker.
function InitClock:display()
  if self.phase == "hour" then return InitClock.oclockString(self.hour) end
  if self.phase == "minute" then return Strings(MINUTES, self.minute) end
  if self.phase == "day" then return Clock.weekdayName(self.day + 1) or "?" end
  return nil
end

function InitClock:confirming()
  return self.phase == "confirm-hour" or self.phase == "confirm-minute"
    or self.phase == "confirm-day"
end

function InitClock:finish()
  if self.mode == "day" then
    Clock.setWeekday(self.save, self.day)
    if self.onDone then self.onDone(self.day) end
    return
  end
  Clock.setTime(self.save, self.hour, self.minute)
  local function done()
    if self.onDone then self.onDone(self.hour, self.minute) end
  end
  -- ../pokecrystal/engine/menus/intro_menu.asm:628
  if self.fades then return IntroFade.run(self, { "outBlack" }, done) end
  done()
end

-- A on a picker confirms it, YES on a confirmation takes it, NO drops back to
-- the picker it came from (`jr c, .loop` / `jr nc, .HourIsSet`).
function InitClock:accept()
  -- A on a page that has more behind it turns the page, the way `para` does.
  if self:morePages() then
    self.page = self.page + 1
    self:startText()
    return
  end
  self.page = 1
  if self.phase == "intro" then
    self.phase = "hour"
  elseif self.phase == "hour" then
    self.phase = "confirm-hour"
  elseif self.phase == "confirm-hour" then
    self.phase = "minute"
  elseif self.phase == "minute" then
    self.phase = "confirm-minute"
  elseif self.phase == "confirm-minute" then
    self.phase = "response"
  elseif self.phase == "response" then
    -- ../pokecrystal/engine/menus/intro_menu.asm:628
    return self:finish()
  elseif self.phase == "day" then
    self.phase = "confirm-day"
  elseif self.phase == "confirm-day" then
    return self:finish()
  end
  self:startText()
end

function InitClock:decline()
  if self.phase == "confirm-hour" then
    self.phase = "hour"
  elseif self.phase == "confirm-minute" then
    self.phase = "minute"
  elseif self.phase == "confirm-day" then
    self.phase = "day"
  end
  self:startText()
end

function InitClock:update(_dt)
  -- ../pokecrystal/home/fade.asm:22-101
  if IntroFade.advance(self) then return end
  -- The driver path: no screen this new may be allowed to stall a scripted
  -- run, so it walks itself to the end taking every default.
  if self.autoConfirm then
    self:accept()
    return
  end
  local input = self.game and self.game.input
  -- ../pokecrystal/home/print_text.asm:5, ../pokecrystal/home/text.asm:473
  if self.typer and not self.typer:tick() then
    if input and (input:wasPressed("a") or input:wasPressed("b")) then
      self.typer.shown = self.typer.total
    end
    return
  end
  if not input then return end
  if self:confirming() and not self:morePages() then
    -- YesNoBox: the cursor walks two rows and B is NO.
    if input:wasPressed("up") or input:wasPressed("down") then
      self.yesNo = self.yesNo == 1 and 2 or 1
    elseif input:wasPressed("a") then
      if self.yesNo == 1 then self:accept() else self:decline() end
      self.yesNo = 1
    elseif input:wasPressed("b") then
      self:decline()
      self.yesNo = 1
    end
    return
  end
  if input:wasPressed("up") then
    self:step(1)
  elseif input:wasPressed("down") then
    self:step(-1)
  elseif input:wasPressed("a") then
    self:accept()
  end
end

-- ------------------------------------------------------------------- drawing

-- The picker box: a Textbox with the value inside it, TIMESET_UP_ARROW on its
-- top border and TIMESET_DOWN_ARROW three rows below.
function InitClock:pickerBox()
  if self.phase == "hour" then return 3, 7, 15, 2, 11, 4, 9 end
  if self.phase == "minute" then return 11, 7, 7, 2, 15, 12, 9 end
  if self.phase == "day" then return 9, 3, 9, 2, 14, 10, 5 end
  return nil
end

-- TimeSetUpArrowGFX / TimeSetDownArrowGFX are two 1bpp tiles the cart loads
-- OVER the ♂ and ♀ font cells for this screen only; the extractor carries the
-- font page, not the replacements, so the pair are drawn rather than printed.
-- Four pixel rows, widest at the base, which is what the two 1bpp tiles are.
local ARROW_ROWS = { 1, 3, 5, 7 }

local function arrow(tx, ty, up)
  local G = love.graphics
  local x, y = tx * 8, ty * 8
  local pal = InitClock.PALETTE
  local paper = GbcPalette.color(pal, 1) or pal[1]
  local ink = GbcPalette.color(pal, 4) or pal[4]
  -- The arrow tile REPLACES the border tile it lands on (hlcoord 11, 7 is the
  -- box's own top row), so the cell is cleared before it is drawn.
  G.setColor(paper[1] / 255, paper[2] / 255, paper[3] / 255, 1)
  G.rectangle("fill", x, y, 8, 8)
  G.setColor(ink[1] / 255, ink[2] / 255, ink[3] / 255, 1)
  for i, width in ipairs(ARROW_ROWS) do
    local row = up and (i - 1) or (#ARROW_ROWS - i)
    G.rectangle("fill", x + math.floor((8 - width) / 2), y + 2 + row, width, 1)
  end
  G.setColor(1, 1, 1, 1)
end

function InitClock:drawPanel()
  -- ../pokecrystal/engine/menus/intro_menu.asm:42-49
  local palette = InitClock.PALETTE
  if self.blank then
    Chrome.paletteFill(0, 0, Chrome.SCREEN_W * 8, Chrome.SCREEN_H * 8, palette)
    love.graphics.setColor(1, 1, 1, 1)
    return
  end
  -- ../pokecrystal/engine/rtc/timeset.asm:22-32
  if self.mode ~= "day" then
    local G = love.graphics
    local ground = GbcPalette.color(palette, 4) or InitClock.GROUND
    G.setColor(ground[1] / 255, ground[2] / 255, ground[3] / 255, 1)
    G.rectangle("fill", 0, 0, Chrome.SCREEN_W * 8, Chrome.SCREEN_H * 8)
    G.setColor(1, 1, 1, 1)
  end
  local value = self:display()
  if value then
    local bx, by, bw, bh, arrowX, tx, ty = self:pickerBox()
    Chrome.paletteBox(bx, by, bw + 2, bh + 2, palette)
    -- The two arrows sit ON the border rows, which is why they are placed
    -- after the box rather than inside it.
    arrow(arrowX, by, true)
    arrow(arrowX, by + bh + 1, false)
    Chrome.printThrough(value, tx, ty, palette)
  end
  -- The question (and the confirmations) share the bottom textbox every other
  -- Gold prompt uses.
  Chrome.paletteBox(0, 12, 20, 6, palette)
  -- ../pokecrystal/home/text.asm:473
  Chrome.printWrapped(table.concat(Typer.text(self, {}), "\n"), 1, 14, 18, 2, 2,
    palette)
  if self:confirming() then
    -- ../pokecrystal/home/menu.asm:418
    Chrome.paletteBox(14, 7, 6, 5, palette)
    Chrome.printThrough(Strings("YES"), 16, 8, palette)
    Chrome.printThrough(Strings("NO"), 16, 10, palette)
    Chrome.cursorThrough(15, self.yesNo == 1 and 8 or 10, palette)
  end
end

function InitClock:drawBody()
  IntroFade.paint(self, Chrome.SCREEN_W * 8, Chrome.SCREEN_H * 8,
    function() self:drawPanel() end)
end

function InitClock:draw()
  Chrome.withClip(function() self:drawBody() end)
end

function InitClock:drawWidescreen(winW, winH)
  local ground = InitClock.GROUND
  local r, g, b = ground[1] / 255, ground[2] / 255, ground[3] / 255
  if self.blank then r, g, b = 1, 1, 1 end
  local index = self.blank and 1 or 4
  r, g, b = IntroFade.surround(self, InitClock.PALETTE, r, g, b, index)
  Chrome.withPanel(winW, winH, r, g, b, function() self:drawBody() end)
end

return InitClock
