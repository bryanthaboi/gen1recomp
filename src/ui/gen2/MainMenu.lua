-- Gold's intro menu (engine/menus/main_menu.asm MainMenu).
--
-- Which entries appear depends on whether a save exists
-- (MainMenu_GetWhichMenu reads wSaveFileExists):
--   no save  -> NEW GAME, OPTION
--   save     -> CONTINUE, NEW GAME, OPTION
-- MYSTERY GIFT is a third case on a CGB with an unlocked SRAM counter; it
-- needs the link cable, so it is not offered here.
--
-- With a save present the menu also shows the clock box
-- the week and the current time.  Its .PlaceTime calls UpdateTime before it
-- reads hHours, so it prints the GAME clock -- the RTC through the save's own
-- wStartHour / wStartMinute base -- and not the raw RTC.  That is the same
-- read the overworld makes (World:hour), so the time on this screen and the
-- light outside the door always agree.
--
-- Choosing CONTINUE shows the save panel (DisplaySaveInfoOnContinue) and waits
-- for A to confirm or B to back out (ConfirmContinue).

local Chrome = require("src.ui.gen2.Chrome")
local Clock = require("src.core.gen2.Clock")
local InitClock = require("src.ui.gen2.InitClock")
local Logger = require("src.core.Logger")
local Music = require("src.core.Music")
local RomText = require("src.core.RomText")
local Runtime = require("src.mods.Runtime")
local Save = require("src.core.gen2.Save")
local SaveMenu = require("src.ui.gen2.SaveMenu")
local Strings = require("src.core.Strings")

-- ../pokecrystal/engine/menus/intro_menu.asm:487
local PANEL = SaveMenu.PANEL
local PANEL_Y = 8

local MainMenu = {}
MainMenu.__index = MainMenu
MainMenu.isOpaque = true

-- MUSIC_MAIN_MENU; resolved by name so a cache without it just stays quiet.
local MENU_MUSIC = "Music_MainMenu"

function MainMenu:wantsFillScale() return true end
function MainMenu:drawsWidescreen() return true end

-- opts: onNewGame(), onContinue(save), onOption(), hasSave (override for
-- tests), save (a pre-loaded save table, so the menu does not read the disk
-- twice), clock ({ hour, minute, weekday }) to pin the clock box.
function MainMenu.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, MainMenu)
  self.game = game
  self.onNewGame = opts.onNewGame
  self.onContinue = opts.onContinue
  self.onOption = opts.onOption
  self.onExit = opts.onExit
  self.clock = opts.clock

  self.save = opts.save
  if self.save == nil and opts.hasSave ~= false then
    local loaded = Save.load(nil, game and game.data)
    self.save = loaded
  end
  self.hasSave = opts.hasSave
  if self.hasSave == nil then self.hasSave = self.save ~= nil end

  self.phase = "menu" -- menu | confirm
  self:buildList()
  return self
end

-- ui.title_menu.items identity: an unhooked build hands its own list back.
local function sameItems(_, items) return items end

function MainMenu:romText(label, ...)
  return RomText(self.game and self.game.data, label, nil, ...)
end

-- engine/menus/main_menu.asm:67 MainMenu.Strings
function MainMenu:buildList()
  local items = {}
  if self.hasSave then
    items[#items + 1] = { label = self:romText("MainMenu.Strings#1"), value = "continue" }
  end
  items[#items + 1] = { label = self:romText("MainMenu.Strings#2"), value = "new" }
  items[#items + 1] = { label = self:romText("MainMenu.Strings#3"), value = "option" }
  -- Not on the cart: a cartridge is left by switching the console off, and
  -- there is no console here.  Mirrors the Gen 1 port's title menu
  -- (src/ui/TitleState.lua), which adds the same row for the same reason.
  items[#items + 1] = { label = Strings("EXIT GAME"), value = "exit" }
  -- The same hook name and the same (game, items) payload the Gen 1 title
  -- menu raises (src/ui/TitleState.lua:openMenu), so one mod's title rows
  -- serve both games; only the row shape differs, because Chrome.List reads
  -- { label, value } where the Gen 1 Menu reads { label, onSelect }.  A hook
  -- that answers with anything but a table is degraded to the vanilla list
  -- rather than leaving the player with no way into the game.
  local hooked = Runtime.call("ui.title_menu.items", sameItems, self.game, items)
  if type(hooked) == "table" then
    items = hooked
  else
    Logger.error("ui.title_menu.items returned %s; keeping the vanilla items",
                 type(hooked))
  end
  -- MenuHeader's "db 1 ; default option": the first entry, so CONTINUE when
  -- there is a save and NEW GAME when there is not.
  self.list = Chrome.List.new({
    items = items,
    x = 2, y = 2, spacing = 2,
    wrap = true,
    index = 1,
    onChoose = function(value) self:choose(value) end,
  })
end

function MainMenu:choose(value)
  if value == "continue" then
    self.phase = "confirm"
    self.confirmDelay = 20 -- ld c, 20 / DelayFrames before input is read
  elseif value == "new" then
    if self.onNewGame then self.onNewGame() end
  elseif value == "option" then
    if self.onOption then self.onOption() end
  elseif value == "exit" then
    if self.onExit then
      self.onExit()
    elseif love.event and love.event.quit then
      love.event.quit()
    end
  end
end

function MainMenu:enter()
  local data = self.game and self.game.data
  local audio = data and data.audio
  if audio and audio.runtime and audio.songs and audio.songs[MENU_MUSIC] then
    Music.play(data, MENU_MUSIC)
  end
end

function MainMenu:update(_dt)
  local input = self.game and self.game.input
  if not input then return end
  if self.phase == "confirm" then
    if self.confirmDelay and self.confirmDelay > 0 then
      self.confirmDelay = self.confirmDelay - 1
      return
    end
    if input:wasPressed("a") then
      if self.onContinue then self.onContinue(self.save) end
    elseif input:wasPressed("b") then
      self.phase = "menu"
    end
    return
  end
  self.list:update(input)
end

-- .PlaceTime's three reads: GetWeekday, hHours and hMinutes, all of them after
-- UpdateTime.  `weekday` is returned 1-based for Clock.weekdayName, which is
-- os.date's wday numbering and NOT wCurDay's (Clock.weekday counts SUNDAY 0).
-- opts.clock still pins the box outright for a driver's screenshots.
function MainMenu:clockParts()
  if self.clock then
    return self.clock.hour or 0, self.clock.minute or 0,
      self.clock.weekday or 1
  end
  local save = self.save
  return Clock.hour(save), Clock.minute(save), Clock.weekday(save) + 1
end

-- ../pokecrystal/engine/rtc/timeset.asm:675
function MainMenu.timeString(hour, minute, data)
  return InitClock.timeString(hour, minute, data)
end

function MainMenu:drawClockBox()
  -- ../pokecrystal/engine/menus/main_menu.asm:286
  Chrome.textbox(0, 14, 18, 2)
  local hour, minute, weekday = self:clockParts()
  local data = self.game and self.game.data
  Chrome.print(Clock.weekdayName(weekday, data) or RomText(data, "PrintDayOfWeek.Day"), 1, 15)
  Chrome.print(MainMenu.timeString(hour, minute, data), 4, 16)
end

function MainMenu:drawSavePanel()
  local summary = Save.summary(self.save)
  Chrome.box(PANEL.x, PANEL_Y, PANEL.w, PANEL.h)
  if not summary then
    Chrome.print(Strings("NO SAVE FILE"), PANEL.labelX, PANEL_Y + PANEL.labelDy)
    return
  end
  local labelY = PANEL_Y + PANEL.labelDy
  for i, line in ipairs(SaveMenu.panelLabels(self.game and self.game.data, summary.name)) do
    Chrome.print(line, PANEL.labelX, labelY + (i - 1) * 2)
  end
  -- ../pokecrystal/engine/menus/intro_menu.asm:555
  Chrome.print(Chrome.number(summary.badges, 2), PANEL.badgesX,
    PANEL_Y + PANEL.badgesDy)
  Chrome.print(Chrome.number(summary.caught, 3), PANEL.dexX,
    PANEL_Y + PANEL.dexDy)
  local timeY = PANEL_Y + PANEL.timeDy
  Chrome.print(Chrome.number(summary.hours, 3), PANEL.timeX, timeY)
  Chrome.print(":", PANEL.timeX + 3, timeY)
  Chrome.print(Chrome.number(summary.minutes, 2, true), PANEL.timeX + 4, timeY)
end

function MainMenu:drawPanel()
  Chrome.clear()
  if self.phase == "confirm" then
    self:drawSavePanel()
    return
  end
  -- is exactly two rows per entry plus the border.  The extra EXIT GAME row
  -- grows it the way AutomaticGetMenuBottomCoord would.
  Chrome.box(0, 0, 17,
    math.min(#self.list.items * 2 + 2, Chrome.SCREEN_H))
  self.list:draw()
  if self.hasSave then self:drawClockBox() end
end

function MainMenu:draw()
  self:drawPanel()
end

function MainMenu:drawWidescreen(winW, winH)
  local G = love.graphics
  Chrome.letterbox(winW, winH, 1, 1, 1)
  local scale = Chrome.fitScale(winW, winH)
  G.push()
  G.translate(Chrome.fitOrigin(winW, winH, scale))
  G.scale(scale, scale)
  self:drawPanel()
  G.pop()
end

MainMenu.PANEL = PANEL
MainMenu.PANEL_Y = PANEL_Y

return MainMenu
