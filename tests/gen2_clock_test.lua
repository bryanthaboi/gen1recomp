-- Gen 2 clock setup: the InitClock screens and the RTC base they write.
--
-- The cart does not store "the time": InitClock stores the RTC reading at the
-- moment the player answered (wStartHour / wStartMinute / wStartDay) and every
-- later read goes through it.  src/core/gen2/Clock.lua is that arithmetic and
-- src/ui/gen2/InitClock.lua is both screens that write it.
--   luajit tests/gen2_clock_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 clock")
local check, eq = S.check, S.eq

love = require("tests.love_stub")

-- No font is loaded here (these are layout and arithmetic assertions), so
-- Font.encode would warn once per unknown glyph and bury a real failure.
require("src.core.Logger").warn = function() end

local Clock = require("src.core.gen2.Clock")
local InitClock = require("src.ui.gen2.InitClock")
local Strings = require("src.core.Strings")

-- A stub input the screen drives off, the same shape Input:wasPressed has.
local function fakeInput()
  local pressed = {}
  return {
    press = function(self, button) pressed[button] = true end,
    wasPressed = function(_self, button)
      if pressed[button] then
        pressed[button] = nil
        return true
      end
      return false
    end,
  }
end

-- (../pokecrystal/home/print_text.asm:5)
local function settle(screen)
  for _ = 1, 900 do
    if not screen.typer or screen.typer:done() then break end
    screen:update(0)
  end
end

local function press(screen, input, button)
  settle(screen)
  input:press(button)
  screen:update(0)
end

-- --------------------------------------------------------------- the offsets
do
  local save = {}
  check(not Clock.isSet(save), "a fresh save has no base")
  eq(Clock.hour(save), math.floor(Clock.hostMinutes() / 60),
    "so it reads the host clock straight through")

  Clock.setTime(save, 10, 0)
  check(Clock.isSet(save), "answering Oak writes the base")
  eq(Clock.hour(save), 10, "and the clock reads back what was set")
  eq(Clock.minute(save), 0, "minutes too")

  Clock.setTime(save, 23, 45)
  eq(Clock.hour(save), 23, "a second answer re-anchors it")
  eq(Clock.minute(save), 45, "minutes and all")

  -- The base is an OFFSET, not a frozen reading: the clock keeps running.
  local base = save.rtc.startMinute
  local moved = (Clock.hostMinutes() + 90 + base) % Clock.MINUTES_PER_DAY
  eq(math.floor(moved / 60), 1,
    "an hour and a half later it is 1:15, not still 23:45")
  eq(moved % 60, 15, "minutes and all")

  Clock.setTime(save, 0, 0)
  eq(Clock.hour(save), 0, "midnight is hour 0")
  Clock.setTime(save, 12, 30)
  eq(Clock.hour(save), 12, "noon is hour 12")
end

do
  local save = {}
  eq(Clock.weekday(save), Clock.hostWeekday(),
    "with no base the weekday is the host's")
  for day = 0, 6 do
    Clock.setWeekday(save, day)
    eq(Clock.weekday(save), day, ("SetDayOfWeek pins day %d"):format(day))
  end
  eq(save.rtc.dayOfWeek, 6,
    "and leaves wCurDay where the daily rollovers read it")
end

-- ------------------------------------------------------------ the hour screen
do
  local save = {}
  local input = fakeInput()
  local done = {}
  local screen = InitClock.new({ input = input }, {
    save = save,
    onDone = function(hour, minute) done = { hour = hour, minute = minute } end,
  })
  eq(screen.phase, "intro", "the screen opens on Oak waking up")
  eq(screen.hour, 10, "with InitClock's own default of 10 AM")
  eq(screen.minute, 0, "and no minutes")

  -- OakTimeWokeUpText is two `para` pages, so A turns the page before it takes
  -- the box down.
  eq(#screen:pages(), 2, "Oak's opening is two pages")
  press(screen, input, "a")
  eq(screen.phase, "intro", "the first A turns the page")
  check(screen:pageText():find("clock", 1, true) ~= nil,
    "onto the one that asks about the clock")
  press(screen, input, "a")
  eq(screen.phase, "hour", "and the second opens the hour picker")
  -- DisplayHourOClock is PrintHour + String_oclock, so the word rides along
  eq(screen:display(), "DAY 10 o'clock", "which shows the hour DisplayHourOClock does")

  press(screen, input, "up")
  eq(screen.hour, 11, "up walks the hour forward")
  press(screen, input, "down")
  press(screen, input, "down")
  eq(screen.hour, 9, "down walks it back")
  -- .DecreaseThroughMidnight / .AdvanceThroughMidnight: both ends wrap.
  screen.hour = 0
  press(screen, input, "down")
  eq(screen.hour, 23, "and midnight wraps to 11 PM")
  press(screen, input, "up")
  eq(screen.hour, 0, "and back again")

  screen.hour = 7
  press(screen, input, "a")
  eq(screen.phase, "confirm-hour", "A confirms the hour")
  check(screen:question():find("o'clock", 1, true) ~= nil,
    "and the question reads it back")
  -- NO drops back to the picker (`jr c, .loop`).
  screen.yesNo = 2
  press(screen, input, "a")
  eq(screen.phase, "hour", "NO goes back to the picker")
  press(screen, input, "a")
  press(screen, input, "a")
  eq(screen.phase, "minute", "YES moves on to the minutes")

  press(screen, input, "up")
  eq(screen.minute, 1, "up walks the minutes")
  screen.minute = 0
  press(screen, input, "down")
  eq(screen.minute, 59, "and they wrap at the hour")
  screen.minute = 30
  eq(screen:display(), "30 min.", "DisplayMinutesWithMinString's own string")
  press(screen, input, "a")
  eq(screen.phase, "confirm-minute", "A confirms them")
  press(screen, input, "a")
  eq(screen.phase, "response", "and Oak answers with the time")
  -- "MORN 7:30", not "7 AM:30": OakText_ResponseToSetTime is PrintHour (the
  -- time-of-day word then the 1-12 hour) then ':' then two-digit minutes, so
  -- the meridiem never appears and cannot land between the hour and them.
  check(screen:question():find("MORN 7:30", 1, true) ~= nil,
    "which is the pair the player just set")
  press(screen, input, "a")
  eq(done.hour, 7, "the screen hands the hour back")
  eq(done.minute, 30, "and the minutes")
  eq(Clock.hour(save), 7, "and the save now reads that hour")
  eq(Clock.minute(save), 30, "and those minutes")
end

-- OakText_ResponseToSetTime's own ladder.
eq(InitClock.responseKey(2), "soDark", "before MORN_HOUR it is still dark")
eq(InitClock.responseKey(4), "overslept", "MORN_HOUR is 'I overslept'")
-- DAY_HOUR is 10 (constants/misc_constants.asm:38), and
-- OakText_ResponseToSetTime's `cp DAY_HOUR + 1 / jr c, .morn` keeps the hour
-- ITSELF in the plain "I overslept!" arm; "Yikes!" starts at 11.  This read 9
-- when InitClock did, so both were an hour early together.
eq(InitClock.responseKey(10), "overslept", "and so is DAY_HOUR itself")
eq(InitClock.responseKey(11), "yikes", "past it Oak yikes")
eq(InitClock.responseKey(18), "soDark", "and NITE_HOUR is dark again")

-- PrintHour (engine/rtc/timeset.asm:672) is GetTimeOfDayString + PlaceString
-- and THEN the 1-12 hour, so the cart prints the time-of-day word ahead of the
-- number and no meridiem at all.  These read "12 AM" / "1 PM" while InitClock
-- built the string that way, which is what let InitClock.timeString append
-- ":mm" to a meridiem and have Oak say "5 AM:30".
eq(InitClock.hourString(0), "NITE 12", "PrintHour shows midnight as NITE 12")
eq(InitClock.hourString(12), "DAY 12", "and noon as DAY 12")
eq(InitClock.hourString(13), "DAY 1", "and the afternoon on a 12-hour clock")
eq(InitClock.timeString(5, 30), "MORN 5:30",
   "and OakText_ResponseToSetTime's line is PrintHour, ':', two-digit minutes")

-- --------------------------------------------------------- the weekday wheel
do
  local save = {}
  local input = fakeInput()
  local picked
  local screen = InitClock.new({ input = input }, {
    mode = "day", save = save,
    onDone = function(day) picked = day end,
  })
  eq(screen.phase, "day", "the wheel opens on its picker, with no preamble")
  eq(screen.day, 0, "`xor a / ld [wTempDayOfWeek], a`: SUNDAY")
  eq(screen:display(), "SUNDAY", "which is what the box shows")
  for _ = 1, 2 do
    press(screen, input, "up")
  end
  eq(screen:display(), "TUESDAY", "up walks the wheel forward")
  press(screen, input, "down")
  press(screen, input, "down")
  press(screen, input, "down")
  eq(screen:display(), "SATURDAY", "and it wraps past SUNDAY")
  press(screen, input, "a")
  eq(screen.phase, "confirm-day", "A confirms it")
  press(screen, input, "b")
  eq(screen.phase, "day", "B is NO and drops back to the wheel")
  press(screen, input, "a")
  press(screen, input, "a")
  eq(picked, 6, "YES hands the day back")
  eq(Clock.weekday(save), 6, "and the save reads it")
end

-- ------------------------------------------- the wheel is an OVERLAY, unclipped
--
-- SetDayOfWeek stands OVER the living room (timeset.asm:385), so day mode is
-- the one screen in this file that answers false to `drawsWidescreen` -- which
-- means Game2:drawScene never paints it through `drawWidescreen` /
-- `Chrome.withPanel`, and `stack:draw()` is its ONLY paint, inside Game2's own
-- translate/scale.
--
-- `Chrome.withClip` clips to (0, 0, 160, 144) and a LOVE scissor is in WINDOW
-- pixels, ignoring that transform.  So clipping here put the wheel in the
-- top-left corner of the window while it drew into a panel scaled several
-- times that: alive, taking A and B, and invisible.  Reported as "nothing pops
-- up for me to answer mom, but if I spam a it continues".
--
-- Clock mode keeps its clip: it owns the frame, and its own `drawWidescreen`
-- has already set a correct scissor that this one only intersects.
do
  local scissors = {}
  local realIntersect = love.graphics.intersectScissor
  local realSet = love.graphics.setScissor
  love.graphics.intersectScissor = function(x, y, w, h)
    scissors[#scissors + 1] = { x, y, w, h }
  end
  love.graphics.setScissor = love.graphics.intersectScissor

  local day = InitClock.new({}, { mode = "day", save = {} })
  day:draw()
  eq(#scissors, 0, "the day wheel sets no scissor of its own")

  local clock = InitClock.new({}, { mode = "clock", save = {} })
  clock:draw()
  eq(#scissors, 1, "clock mode still clips to the field it owns")
  if scissors[1] then
    eq(("%d,%d,%d,%d"):format(scissors[1][1], scissors[1][2],
                              scissors[1][3], scissors[1][4]),
       "0,0,160,144", "at the GB field's own rectangle")
  end

  love.graphics.intersectScissor = realIntersect
  love.graphics.setScissor = realSet
end

-- The driven path: a screen this new must not stall a scripted run, so it
-- walks itself to the end on its defaults.
do
  local save = {}
  local finished = false
  local screen = InitClock.new({}, {
    save = save, autoConfirm = true,
    onDone = function() finished = true end,
  })
  for _ = 1, 20 do
    if finished then break end
    screen:update(0)
  end
  check(finished, "autoConfirm reaches the end on its own")
  eq(Clock.hour(save), Clock.DEFAULT_HOUR, "taking InitClock's 10 AM default")
  eq(Clock.minute(save), Clock.DEFAULT_MINUTE, "and no minutes")
end

-- Drawing must not throw with the stub canvas: the layout is transcribed from
-- hlcoord calls, so a bad coordinate is a crash rather than a wrong pixel.
do
  local screen = InitClock.new({}, { save = {} })
  for _, phase in ipairs({ "intro", "hour", "confirm-hour", "minute",
      "confirm-minute", "response", "day", "confirm-day" }) do
    screen.phase = phase
    local ok, err = pcall(function() screen:drawPanel() end)
    check(ok, ("phase %s draws (%s)"):format(phase, tostring(err)))
  end
end

-- ../pokecrystal/home/text.asm:473
do
  local Chrome = require("src.ui.gen2.Chrome")
  local priorPrint = Chrome.print
  local rows = {}
  Chrome.print = function(text, _tx, ty) rows[text] = ty end
  local screen = InitClock.new({}, { save = {} })
  settle(screen)
  screen:drawPanel()
  Chrome.print = priorPrint
  eq(rows["Zzz... Hm? Wha...?"], 14, "Oak's first line prints on row 14")
  eq(rows["You woke me up!"], 16, "and `line` puts the second on row 16")
end

-- ../pokecrystal/engine/rtc/timeset.asm:385
do
  local Chrome = require("src.ui.gen2.Chrome")
  local day = InitClock.new({}, { mode = "day", save = {} })
  eq(day.isOpaque, false, "SetDayOfWeek draws over the map")
  eq(day:drawsWidescreen(), false, "and paints no surround of its own")
  eq(day:wantsFillScale(), false, "nor asks for the fill scale")
  local clock = InitClock.new({}, { mode = "clock", save = {} })
  eq(clock.isOpaque, true, "InitClock still runs on a cleared page")
  eq(clock:drawsWidescreen(), true, "with its own widescreen surround")
  -- ../pokecrystal/engine/rtc/timeset.asm:22-32
  local G = love.graphics
  local priorColor, priorRect = G.setColor, G.rectangle
  local held, fills = nil, {}
  G.setColor = function(r, g, b, a)
    held = { r, g, b }
    priorColor(r, g, b, a)
  end
  G.rectangle = function(mode, x, y, w, h)
    fills[#fills + 1] = { color = held, x = x, y = y, w = w, h = h }
    priorRect(mode, x, y, w, h)
  end
  local function groundFill(list)
    local first = list[1]
    if not first then return nil end
    if first.x ~= 0 or first.y ~= 0 or first.w ~= 160 or first.h ~= 144 then
      return nil
    end
    return first.color
  end
  clock:drawPanel()
  local ground = groundFill(fills)
  check(ground ~= nil, "the clock screen fills the whole tilemap first")
  eq(ground[1], 0, "with black")
  eq(ground[2], 0, "and black")
  eq(ground[3], 0, "and black")
  fills = {}
  day:drawPanel()
  check(groundFill(fills) == nil, "the day wheel never clears the tilemap")
  G.setColor, G.rectangle = priorColor, priorRect
  eq(InitClock.GROUND[1] + InitClock.GROUND[2] + InitClock.GROUND[3], 0,
    "gfx/diploma/diploma.pal colour 3")
end

-- ../pokecrystal/home/print_text.asm:5
do
  local slow = InitClock.new(
    { input = fakeInput(), save = { options = { textSpeed = "SLOW" } } },
    { save = {} })
  check(slow.typer ~= nil, "the clock screen types its text")
  check(not slow.typer:done(), "and opens with nothing shown")
  for _ = 1, 25 do slow:update(0) end
  eq(slow.typer.shown, 5, "SLOW is one character every five frames")

  local input = fakeInput()
  local fast = InitClock.new(
    { input = input, save = { options = { textSpeed = "FAST" } } },
    { save = {} })
  for _ = 1, 25 do fast:update(0) end
  eq(fast.typer.shown, 25, "FAST is one a frame")
  check(not fast.typer:done(), "the page is still going")
  input:press("a")
  fast:update(0)
  eq(fast.page, 1, "A mid-line does not turn the page")
  check(fast.typer:done(), "it finishes the line instead")
  input:press("a")
  fast:update(0)
  eq(fast.page, 2, "the next A turns it")
  check(not fast.typer:done(), "and the new page starts from nothing")

  local driven = InitClock.new({}, { save = {}, autoConfirm = true })
  check(driven.typer.instant, "autoConfirm takes the whole line at once")
  local wheel = InitClock.new({}, { mode = "day", save = {} })
  check(wheel.typer.instant, "and so does SetDayOfWeek")
end

-- ../pokecrystal/home/text.asm:502
do
  local screen = InitClock.new({}, { save = {}, hour = 12, minute = 0 })
  screen.phase = "response"
  eq(InitClock.responseKey(12), "yikes", "noon is the three-line response")
  local pages = screen:pages()
  eq(#pages, 2, "`cont` scrolls the third line in as a second page")
  check(pages[1]:find("Yikes! I over-", 1, true) ~= nil
    and not pages[1]:find("slept!", 1, true), "page one holds lines 1-2")
  check(pages[2]:find("^Yikes! I over%-\nslept!$") ~= nil,
    "page two keeps line 2 on top and scrolls line 3 under it")
end

-- Clock.DAY_NAMES / Clock.weekdayName / Clock.daytimeLabel: the single home
-- InitClock, MainMenu and the Pokegear clock card all share, so a weekday
-- cannot be named one way on one screen and another way on the next.
do
  eq(Clock.weekdayName(1), "SUNDAY", "1-based, SUNDAY first")
  eq(Clock.weekdayName(6), "FRIDAY", "and the rest in wCurDay's order")
  check(Clock.weekdayName(0) == nil, "day 0 is out of range")
  check(Clock.weekdayName(8) == nil, "and so is day 8")

  eq(Clock.daytimeLabel(4), "MORN", "daytimeLabel matches clockDaytime's word")
  eq(Clock.daytimeLabel(10), "DAY", "for every hour band")
  eq(Clock.daytimeLabel(20), "NITE", "including the wrap back to NITE")

  local MainMenu = require("src.ui.gen2.MainMenu")
  check(MainMenu.DAYS == Clock.DAY_NAMES,
    "MainMenu reuses the same table InitClock and the Pokegear do")
end

-- ------------------------------------------------- a translation mod's turn
--
-- DAYS, the clockDaytime word and the "o'clock"/"min." suffixes used to
-- bypass Strings entirely, so a translation mod's `strings` registry had no
-- seam to catch them: the picker kept printing the English day name and
-- "o'clock" no matter the catalog (reported from a real Gold build).
do
  Strings.load({
    strings = {
      SUNDAY = "DIMANCHE",
      MORN = "MATIN",
      ["%s o'clock"] = "%s heures",
      ["%d min."] = "%d min",
    },
  })

  local wheel = InitClock.new({ input = fakeInput() }, { mode = "day", save = {} })
  eq(wheel:display(), "DIMANCHE", "a translated catalog reaches the day wheel")

  eq(InitClock.hourString(4), "MATIN 4",
    "and the clockDaytime word, through Clock.daytimeLabel")
  eq(InitClock.oclockString(4), "MATIN 4 heures",
    "and the o'clock suffix, template and all")

  local minutePicker = InitClock.new({ input = fakeInput() }, { save = {} })
  minutePicker.phase = "minute"
  minutePicker.minute = 30
  eq(minutePicker:display(), "30 min", "and the minutes picker's own suffix")

  -- Palettes.clockDaytime itself must stay untranslated even with a catalog
  -- loaded: FORCED_DAYTIME and the rest of Palettes.lua's own lookups
  -- compare against its return value as an internal key, not display text.
  local Palettes = require("src.world.gen2.Palettes")
  eq(Palettes.clockDaytime(4), "MORN",
    "the internal palette key is untouched by the loaded catalog")

  -- Module state is process-global and tests/run_tests.lua runs every suite
  -- in one process (see tests/mod_strings_tests.lua's own note): leaving the
  -- catalog loaded would translate the day/hour of every suite after this
  -- one.
  Strings.load({})
  check(not Strings.active(), "the catalog is unloaded for the suites after this one")
end

S.finish()
