-- SAVE from the start menu (engine/menus/save.asm SaveMenu).
--
-- Transcribed rather than laid out by eye.  SaveMenu is four calls:
--
--   DisplayNormalContinueData with `lb de, 4, 0`, which is the *same* panel
--     CONTINUE shows, moved: _OffsetMenuHeader keeps the header's 15x9 size
--     but puts its left edge at 4 and its top at 0, so MenuBox draws a 16x10
--     box over (4,0)..(19,9).  GetMenuTextStartCoord then lands the four
--     labels at (5,2), (5,4), (5,6), (5,8) -- border + 1, plus one more row
--     because the header does not set STATICMENU_NO_TOP_SPACING, and no extra
--     column because it does not set STATICMENU_CURSOR.
--   SpeechTextbox, the ordinary 18x4 box over rows 12-17.
--   SaveTheGame_yesorno, which prints into that box and puts the yes/no at
--     `lb bc, 0, 7` -- left 0, top 7, so a 6x5 box at (0,7) with YES at (2,8)
--     and NO at (2,10).  YesNoMenuHeader sets STATICMENU_CURSOR and
--     STATICMENU_NO_TOP_SPACING, which is what puts the labels one column in
--     from the cursor and skips the blank row.
--   SavingDontTurnOffThePower, which is a timed sequence and not a prompt:
--     "SAVING… DON'T TURN / OFF THE POWER." for 16 frames, the write, 32
--     frames, "<PLAYER> saved / the game.", SFX_SAVE, then 30 more.
--
-- Overwriting an existing file gets a second yes/no first
-- (AskOverwriteSaveFile), which is the whole reason this is a state and not a
-- one-line call.

local Chrome = require("src.ui.gen2.Chrome")
local Save = require("src.core.gen2.Save")
local Sound = require("src.core.Sound")

local SaveMenu = {}
SaveMenu.__index = SaveMenu
SaveMenu.isOpaque = true

-- SFX_SAVE ($25, constants/sfx_constants.asm:40) is what plays as the file is
-- written: `ld de, SFX_SAVE / call PlaySFX` right after ResumeGameLogic in
-- SaveGameData (engine/menus/save.asm:110), and again under SavedTheGameText
-- (:265).  It is an index into the sfx pointer table, so an id that is off by
-- anything plays a different sound rather than nothing -- $1f is
-- SFX_ENTER_DOOR, which is what saving used to creak with.
local SFX_SAVE = 0x25

-- SavingDontTurnOffThePower's DelayFrames counts, at the 60 Hz logic clock.
local SAVING_FRAMES = 16
local SAVED_FRAMES = 32 + 30

-- MenuBox coordinates after _OffsetMenuHeader(4, 0).
local PANEL_X, PANEL_Y, PANEL_W, PANEL_H = 4, 0, 16, 10
local LABEL_X, LABEL_Y = 5, 2
-- Continue_DisplayBadgesDex / Continue_PrintGameTime add these to the box's
-- own origin, so they are (4,0) + (13,4) / (12,6) / (9,8).
local BADGES_X, BADGES_Y = 17, 4
local DEX_X, DEX_Y = 16, 6
local TIME_X, TIME_Y = 13, 8

local YESNO_X, YESNO_Y, YESNO_W, YESNO_H = 0, 7, 6, 5

-- AlreadyASaveFileText (AskOverwriteSaveFile, engine/menus/save.asm:47) and
-- SavingDontTurnOffThePower's own line, shared with the PC's CHANGE BOX save.
local OVERWRITE_PROMPT = { "There is already a", "save file. Is it" }
local SAVING_PROMPT = { "SAVING… DON'T TURN", "OFF THE POWER." }

function SaveMenu:wantsFillScale() return true end
function SaveMenu:drawsWidescreen() return true end

-- opts: save, onDone(saved), existed (override), writer (injected for tests)
function SaveMenu.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, SaveMenu)
  self.game = game
  self.save = opts.save or (game and game.save)
  self.onDone = opts.onDone
  self.writer = opts.writer or Save.save
  local existed = opts.existed
  if existed == nil then existed = Save.exists("gold") end
  self.existed = existed
  -- confirm -> overwrite (only when a file exists) -> saving -> done
  self.phase = "confirm"
  self.choice = 1 -- 1 YES, 2 NO
  self.timer = 0
  return self
end

function SaveMenu.playSaveSfx(game, id)
  local data = game and game.data
  local audio = data and data.audio
  if not (audio and audio.sfxOrder) then return end
  local name = audio.sfxOrder[id + 1]
  if name and audio.sfx and audio.sfx[name] then Sound.play(data, name) end
end

function SaveMenu:playSfx(id)
  SaveMenu.playSaveSfx(self.game, id)
end

function SaveMenu:finish(saved)
  if self.onDone then self.onDone(saved) end
end

function SaveMenu:playerName()
  return (self.save and self.save.player and self.save.player.name) or "GOLD"
end

-- The write itself, which the cart does between the two messages.
function SaveMenu:writeNow()
  local ok = self.writer(self.save)
  self.saved = ok and true or false
  if ok then self:playSfx(SFX_SAVE) end
end

function SaveMenu:accept()
  if self.phase == "confirm" then
    if self.choice == 2 then
      self:finish(false)
      return
    end
    if self.existed then
      self.phase = "overwrite"
      self.choice = 1
      return
    end
    self.phase = "saving"
    self.timer = 0
    return
  end
  if self.phase == "overwrite" then
    if self.choice == 2 then
      self:finish(false)
      return
    end
    self.phase = "saving"
    self.timer = 0
  end
end

function SaveMenu:update(_dt)
  -- The saving and saved messages are DelayFrames, not prompts: no button
  -- does anything until the sequence runs out.
  if self.phase == "saving" then
    self.timer = self.timer + 1
    if self.timer >= SAVING_FRAMES then
      self:writeNow()
      self.phase = "done"
      self.timer = 0
    end
    return
  end
  if self.phase == "done" then
    self.timer = self.timer + 1
    if self.timer >= SAVED_FRAMES then self:finish(self.saved) end
    return
  end

  local input = self.game and self.game.input
  if not input then return end
  if input:wasPressed("up") or input:wasPressed("down") then
    self.choice = self.choice == 1 and 2 or 1
    return
  end
  if input:wasPressed("a") then
    self:accept()
  elseif input:wasPressed("b") then
    -- B out of a yes/no is NO (InterpretTwoOptionMenu returns carry).
    self:finish(false)
  end
end

-- The two lines the speech box holds, in the cart's own wording.  `line` puts
-- the second one on the box's lower line; `cont` scrolls, which the overwrite
-- prompt uses for its third line and which this shows as a second page.
function SaveMenu:prompt()
  if self.phase == "overwrite" then
    -- AlreadyASaveFileText when the file is this player's; AnotherSaveFileText
    -- when the ID differs.  Only the first can happen here.
    return OVERWRITE_PROMPT
  end
  if self.phase == "saving" then
    return SAVING_PROMPT
  end
  if self.phase == "done" then
    if self.saved then
      return { self:playerName() .. " saved", "the game." }
    end
    return { "Could not save.", "" }
  end
  return { "Would you like to", "save the game?" }
end

function SaveMenu:drawPanel()
  Chrome.clear()
  local summary = Save.summary(self.save)
  Chrome.box(PANEL_X, PANEL_Y, PANEL_W, PANEL_H)
  if summary then
    Chrome.print("PLAYER " .. summary.name, LABEL_X, LABEL_Y)
    Chrome.print("BADGES", LABEL_X, LABEL_Y + 2)
    Chrome.print("POKéDEX", LABEL_X, LABEL_Y + 4)
    Chrome.print("TIME", LABEL_X, LABEL_Y + 6)
    -- PrintNum fills its field from the left, space padded.
    Chrome.print(Chrome.number(summary.badges, 2), BADGES_X, BADGES_Y)
    Chrome.print(Chrome.number(summary.caught, 3), DEX_X, DEX_Y)
    Chrome.print(Chrome.number(summary.hours, 3), TIME_X, TIME_Y)
    Chrome.print(":", TIME_X + 3, TIME_Y)
    Chrome.print(Chrome.number(summary.minutes, 2, true), TIME_X + 4, TIME_Y)
  end

  -- SpeechTextbox: interior 18x4 at (0,12), so the two lines are at (1,14)
  -- and (1,16) -- `line` is the box's lower line, two rows down.
  Chrome.textbox(0, 12, 18, 4)
  local lines = self:prompt()
  Chrome.print(lines[1] or "", 1, 14)
  Chrome.print(lines[2] or "", 1, 16)

  if self.phase == "confirm" or self.phase == "overwrite" then
    Chrome.box(YESNO_X, YESNO_Y, YESNO_W, YESNO_H)
    Chrome.print("YES", YESNO_X + 2, YESNO_Y + 1)
    Chrome.print("NO", YESNO_X + 2, YESNO_Y + 3)
    Chrome.cursor(YESNO_X + 1, YESNO_Y + (self.choice == 1 and 1 or 3))
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function SaveMenu:draw()
  self:drawPanel()
end

function SaveMenu:drawWidescreen(winW, winH)
  local G = love.graphics
  G.setColor(1, 1, 1, 1)
  G.rectangle("fill", 0, 0, winW, winH)
  local scale = Chrome.fitScale(winW, winH)
  G.push()
  G.translate(math.floor((winW - 160 * scale) / 2),
    math.floor((winH - 144 * scale) / 2))
  G.scale(scale, scale)
  self:drawPanel()
  G.pop()
end

SaveMenu.SFX_SAVE = SFX_SAVE
SaveMenu.SAVING_FRAMES = SAVING_FRAMES
SaveMenu.SAVED_FRAMES = SAVED_FRAMES
SaveMenu.OVERWRITE_PROMPT = OVERWRITE_PROMPT
SaveMenu.SAVING_PROMPT = SAVING_PROMPT

return SaveMenu
