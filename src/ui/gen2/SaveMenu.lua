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
--     more (SavedTheGame, engine/menus/save.asm:242-262).
--
-- Overwriting an existing file gets a second yes/no first
-- (AskOverwriteSaveFile), which is the whole reason this is a state and not a
-- one-line call.

local Chrome = require("src.ui.gen2.Chrome")
local Save = require("src.core.gen2.Save")
local Sound = require("src.core.Sound")
local Strings = require("src.core.Strings")
local Typer = require("src.ui.gen2.Typer")

local SaveMenu = {}
SaveMenu.__index = SaveMenu
-- ../pokecrystal/engine/menus/save.asm:1
SaveMenu.isOpaque = false

-- SFX_SAVE ($25, constants/sfx_constants.asm:40) is what plays as the file is
-- written: `ld de, SFX_SAVE / call PlaySFX` right after ResumeGameLogic in
-- SaveGameData (engine/menus/save.asm:110), and again under SavedTheGameText
-- (:265).  It is an index into the sfx pointer table, so an id that is off by
-- anything plays a different sound rather than nothing -- $1f is
-- SFX_ENTER_DOOR, which is what saving used to creak with.
local SFX_SAVE = 0x25

-- SavingDontTurnOffThePower's DelayFrames counts, at the 60 Hz logic clock.
-- ../pokecrystal/engine/menus/save.asm:242 SavedTheGame
local SAVING_FRAMES = 16
local SAVED_GAP_FRAMES = 32
local SAVED_TAIL_FRAMES = 30
local SAVED_FRAMES = SAVED_GAP_FRAMES + SAVED_TAIL_FRAMES

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
-- SavingDontTurnOffThePower's own line -- one \n-joined translatable key
-- each, used both by this screen's own prompt() below and, through the
-- SOURCE/pagesOf() exports at the bottom of this file, by the PC's CHANGE
-- BOX save (src/ui/gen2/PcMenu.lua:savePrompt()), which shares these exact
-- same two cart messages. One key per prompt lets a translation write one
-- whole, freely reordered sentence instead of two fragments translated in
-- isolation, and lets a cart whose own text is a single line (German's
-- SAVING prompt) say so directly by simply omitting the "\n" -- the
-- per-line override style used elsewhere requires a non-empty value for
-- every line, so it can't express "this line is blank".
--
-- Written as a literal, not built from a table: the translation tooling's
-- string harvester only recognizes a literal inside Strings.source(...),
-- not a computed expression, so a concat call here would quietly never
-- reach a translator.
-- ../pokecrystal/data/text/common_3.asm:202 _AlreadyASaveFileText
local OVERWRITE_PROMPT_SOURCE = Strings.source("There is already a\nsave file. Is it\vOK to overwrite?")
local SAVING_PROMPT_SOURCE = Strings.source("SAVING… DON'T TURN\nOFF THE POWER.")

-- ../pokecrystal/home/text.asm:630 LoadBlinkingCursor
local DOWN_ARROW = "\xe2\x96\xbc"
local ARROW_X, ARROW_Y = 18, 17

-- ../pokecrystal/home/text.asm:479 Paragraph
-- ../pokecrystal/home/text.asm:520 _ContTextNoPause
local function pagesOf(body)
  local pages = {}
  for chunk in (tostring(body) .. "\f"):gmatch("(.-)\f") do
    local flat, pos, scrolled = {}, 1, false
    while true do
      local brk = chunk:find("[\n\v]", pos)
      local line = brk and chunk:sub(pos, brk - 1) or chunk:sub(pos)
      if line ~= "" then flat[#flat + 1] = { line, scrolled } end
      if not brk then break end
      scrolled = chunk:sub(brk, brk) == "\v"
      pos = brk + 1
    end
    local page
    for _, entry in ipairs(flat) do
      if not page then
        page = { entry[1] }
        pages[#pages + 1] = page
      elseif entry[2] then
        page = { page[#page], entry[1], scrolled = true }
        pages[#pages + 1] = page
      elseif #page >= 2 then
        page = { entry[1] }
        pages[#pages + 1] = page
      else
        page[#page + 1] = entry[1]
      end
    end
  end
  if #pages == 0 then pages[1] = { "" } end
  return pages
end

function SaveMenu:wantsFillScale() return true end

-- opts: save, onDone(saved), existed (override), writer (injected for tests)
function SaveMenu.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, SaveMenu)
  self.game = game
  self.save = opts.save or (game and game.save)
  self.onDone = opts.onDone
  self.writer = opts.writer or Save.save
  local existed = opts.existed
  if existed == nil then existed = Save.exists() end
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

-- ../pokecrystal/home/joypad.asm:392
function SaveMenu:playSfxNamed(name)
  local data = self.game and self.game.data
  local sfx = data and data.audio and data.audio.sfx
  if sfx and sfx[Sound.resolve(data, name)] then Sound.play(data, name) end
end

function SaveMenu:finish(saved)
  if self.onDone then self.onDone(saved) end
end

function SaveMenu:playerName()
  return (self.save and self.save.player and self.save.player.name) or "GOLD"
end

-- The write itself, which the cart does between the two messages.
-- ../pokecrystal/engine/menus/save.asm:244 _SaveGameData
function SaveMenu:writeNow()
  local ok = self.writer(self.save)
  self.saved = ok and true or false
end

-- ../pokecrystal/engine/menus/save.asm:346
function SaveMenu:enterPhase(phase)
  self.phase = phase
  self.timer = 0
  self.typedPhase = phase
  self.pages = pagesOf(self:promptText())
  self.page = 1
  local pinned = (phase == "saving" or phase == "done") and "MID" or nil
  self.typer = Typer.new(self.game, { speed = pinned })
  self.typer:start(self.pages[1])
end

function SaveMenu:accept()
  if self.phase == "confirm" then
    if self.choice == 2 then
      self:finish(false)
      return
    end
    if self.existed then
      self.choice = 1
      self:enterPhase("overwrite")
      return
    end
    self:enterPhase("saving")
    return
  end
  if self.phase == "overwrite" then
    if self.choice == 2 then
      self:finish(false)
      return
    end
    self:enterPhase("saving")
  end
end

function SaveMenu:update(_dt)
  if self.typedPhase ~= self.phase then self:enterPhase(self.phase) end
  local typed = Typer.step(self)

  -- The saving and saved messages are DelayFrames, not prompts: no button
  -- does anything until the sequence runs out.
  -- ../pokecrystal/engine/menus/save.asm:352
  if self.phase == "saving" then
    if not typed then return end
    self.timer = self.timer + 1
    if self.timer == SAVING_FRAMES then self:writeNow() end
    if self.timer >= SAVING_FRAMES + SAVED_GAP_FRAMES then
      self:enterPhase("done")
    end
    return
  end
  if self.phase == "done" then
    if not typed then return end
    -- ../pokecrystal/engine/menus/save.asm:259 WaitPlaySFX / home/audio.asm:220
    if self.saved and not self.rang then
      self.rang = true
      Sound.waitSfxDone()
      self:playSfx(SFX_SAVE)
      return
    end
    -- ../pokecrystal/engine/menus/save.asm:260 WaitSFX
    if Sound.sfxBusy() then return end
    self.timer = self.timer + 1
    if self.timer >= SAVED_TAIL_FRAMES then self:finish(self.saved) end
    return
  end

  local input = self.game and self.game.input
  if not input then return end
  if Typer.typing(self) then return end
  -- ../pokecrystal/home/text.asm:502 _ContText
  if self.page < #self.pages then
    if input:wasPressed("a") or input:wasPressed("b") then
      self.page = self.page + 1
      self.typer:start(self.pages[self.page])
      self:playSfxNamed("Sfx_ReadText2")
    end
    return
  end
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
function SaveMenu:promptText()
  if self.phase == "overwrite" then
    -- AlreadyASaveFileText when the file is this player's; AnotherSaveFileText
    -- when the ID differs.  Only the first can happen here.
    return Strings(OVERWRITE_PROMPT_SOURCE)
  end
  if self.phase == "saving" then
    return Strings(SAVING_PROMPT_SOURCE)
  end
  if self.phase == "done" then
    if self.saved then
      return Strings("%s saved\nthe game.", self:playerName())
    end
    return Strings("Could not save.")
  end
  return Strings("Would you like to\nsave the game?")
end

function SaveMenu:prompt()
  if self.typedPhase == self.phase and self.pages then
    return self.pages[self.page] or self.pages[1]
  end
  return pagesOf(self:promptText())[1]
end

-- ../pokecrystal/engine/menus/save.asm:209 SaveTheGame_yesorno
function SaveMenu:yesNoVisible()
  if self.phase ~= "confirm" and self.phase ~= "overwrite" then return false end
  if self.typedPhase ~= self.phase or Typer.typing(self) then return false end
  return self.page >= #self.pages
end

function SaveMenu:drawPanel()
  local summary = Save.summary(self.save)
  Chrome.box(PANEL_X, PANEL_Y, PANEL_W, PANEL_H)
  if summary then
    Chrome.print(Strings("PLAYER %s", summary.name), LABEL_X, LABEL_Y)
    Chrome.print(Strings("BADGES"), LABEL_X, LABEL_Y + 2)
    Chrome.print(Strings("POKéDEX"), LABEL_X, LABEL_Y + 4)
    Chrome.print(Strings("TIME"), LABEL_X, LABEL_Y + 6)
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
  if self.typedPhase == self.phase then lines = Typer.text(self, lines) end
  Chrome.print(lines[1] or "", 1, 14)
  Chrome.print(lines[2] or "", 1, 16)

  if self.typedPhase == self.phase and not Typer.typing(self)
    and self.page < #self.pages and Typer.arrowOn(self) then
    Chrome.print(DOWN_ARROW, ARROW_X, ARROW_Y)
  end

  if self:yesNoVisible() then
    Chrome.box(YESNO_X, YESNO_Y, YESNO_W, YESNO_H)
    Chrome.print(Strings("YES"), YESNO_X + 2, YESNO_Y + 1)
    Chrome.print(Strings("NO"), YESNO_X + 2, YESNO_Y + 3)
    Chrome.cursor(YESNO_X + 1, YESNO_Y + (self.choice == 1 and 1 or 3))
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function SaveMenu:draw()
  self:drawPanel()
end

-- ../pokecrystal/engine/menus/intro_menu.asm:479
SaveMenu.PANEL = {
  x = PANEL_X, y = PANEL_Y, w = PANEL_W, h = PANEL_H,
  labelX = LABEL_X, labelDy = LABEL_Y,
  badgesX = BADGES_X, badgesDy = BADGES_Y,
  dexX = DEX_X, dexDy = DEX_Y,
  timeX = TIME_X, timeDy = TIME_Y,
}

SaveMenu.SFX_SAVE = SFX_SAVE
SaveMenu.SAVING_FRAMES = SAVING_FRAMES
SaveMenu.SAVED_GAP_FRAMES = SAVED_GAP_FRAMES
SaveMenu.SAVED_TAIL_FRAMES = SAVED_TAIL_FRAMES
SaveMenu.SAVED_FRAMES = SAVED_FRAMES
SaveMenu.OVERWRITE_PROMPT_SOURCE = OVERWRITE_PROMPT_SOURCE
SaveMenu.SAVING_PROMPT_SOURCE = SAVING_PROMPT_SOURCE
SaveMenu.pagesOf = pagesOf
SaveMenu.DOWN_ARROW = DOWN_ARROW
SaveMenu.ARROW_X, SaveMenu.ARROW_Y = ARROW_X, ARROW_Y

return SaveMenu
