-- ../pokecrystal/engine/menus/init_gender.asm:23-41 InitGender, which
-- PlayerProfileSetup runs before OakSpeech (engine/menus/intro_menu.asm:61-83).

local Chrome = require("src.ui.gen2.Chrome")
local CommonText = require("src.core.gen2.CommonText")
local GbcPalette = require("src.render.GbcPalette")
local IntroFade = require("src.ui.gen2.IntroFade")
local Music = require("src.core.Music")
local RomText = require("src.core.RomText")
local Sound = require("src.core.Sound")
local Strings = require("src.core.Strings")
local Typer = require("src.ui.gen2.Typer")

local GenderSelect = {}
GenderSelect.__index = GenderSelect
GenderSelect.isOpaque = true

-- .MenuData's two items (../pokecrystal/engine/menus/init_gender.asm:50-53),
-- and the wPlayerGender byte each writes (`ld a, [wMenuCursorY] / dec a`).
GenderSelect.OPTIONS = {
  { label = Strings.source("Boy"), gender = "male" },
  { label = Strings.source("Girl"), gender = "female" },
}

-- menu_coords 6, 4, 12, 9 -- inclusive, so 7 columns by 6 rows.
local BOX_X, BOX_Y, BOX_W, BOX_H = 6, 4, 7, 6
local TEXT_X, TEXT_Y = BOX_X + 2, BOX_Y + 2
local CURSOR_X = TEXT_X - 1
local ROW_STEP = 2

-- TEXTBOX_X / TEXTBOX_Y / TEXTBOX_INNERX / TEXTBOX_INNERY
-- (../pokecrystal/constants/text_constants.asm:25-32), the box PrintText fills.
local SAY_X, SAY_Y, SAY_W, SAY_H = 0, 12, 18, 4
local SAY_TEXT_X, SAY_TEXT_Y = 1, 14

-- gfx/new_game/gender_screen.pal:1-4, the one palette LoadGenderScreenPal
GenderSelect.PALETTE = {
  { 255, 255, 255 }, { 74, 247, 255 }, { 8, 90, 255 }, { 0, 0, 0 },
}
GenderSelect.GROUND = GenderSelect.PALETTE[2]

-- pokecrystal/engine/menus/init_gender.asm:31-33
local MENU_OPEN_FRAMES = 4
GenderSelect.MENU_OPEN_FRAMES = MENU_OPEN_FRAMES

-- `ld a, $10 / ld [wMusicFade]` with MUSIC_NONE as the fade target
-- (../pokecrystal/engine/menus/init_gender.asm:59-65).
local FADE_CONTROL = 0x10
-- `ld c, 10 / call DelayFrames` on the way out
-- (../pokecrystal/engine/menus/init_gender.asm:39-40).
local EXIT_FRAMES = 10

local FALLBACK = Strings.source("Are you a boy?\nOr are you a girl?")

function GenderSelect:wantsFillScale() return true end
function GenderSelect:drawsWidescreen() return true end

-- opts: onDone(gender), save
function GenderSelect.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, GenderSelect)
  self.game = game
  self.save = opts.save or (game and game.save)
  self.onDone = opts.onDone
  self.data = (game and game.data) or {}
  -- `db 1 ; default option`: the cursor opens on Boy.
  self.cursor = 1
  self.exit = nil
  self.fades = opts.fades and true or false
  self.text = CommonText.plain(RomText(self.data,
    "_AreYouABoyOrAreYouAGirlText", FALLBACK))
  -- ../pokecrystal/home/print_text.asm:5, ../pokecrystal/engine/menus/init_gender.asm:30-34
  self.typer = Typer.new(game, {})
  self.typer:start(self.text)
  return self
end

function GenderSelect:enter()
  Music.fadeOut(FADE_CONTROL)
end

function GenderSelect:playSfx(name)
  local sfx = self.data.audio and self.data.audio.sfx
  if sfx and sfx[Sound.resolve(self.data, name)] then
    Sound.play(self.data, name)
  end
end

function GenderSelect:choose(index)
  local option = GenderSelect.OPTIONS[index] or GenderSelect.OPTIONS[1]
  if self.save and self.save.player then
    self.save.player.gender = option.gender
  end
  self.chosen = option.gender
  self.exit = EXIT_FRAMES
end

function GenderSelect:leave()
  local function done()
    if self.onDone then self.onDone(self.chosen) end
  end
  -- ../pokecrystal/engine/rtc/timeset.asm:22
  if self.fades then return IntroFade.run(self, { "outBlack" }, done) end
  done()
end

-- pokecrystal/engine/menus/init_gender.asm:29-34
function GenderSelect:menuOpen()
  if not self.typer then return true end
  return self.typer:done() and (self.menuWait or MENU_OPEN_FRAMES) <= 0
end

function GenderSelect:update(_dt)
  -- ../pokecrystal/home/fade.asm:22-101
  if IntroFade.advance(self) then return end
  if self.typer then self.typer:tick() end
  if self.exit then
    self.exit = self.exit - 1
    if self.exit > 0 then return end
    self.exit = nil
    self:leave()
    return
  end
  if not self:menuOpen() then
    if self.typer:done() then
      if self.menuWait then
        self.menuWait = self.menuWait - 1
      else
        self.menuWait = MENU_OPEN_FRAMES
      end
    end
    return
  end
  local input = self.game and self.game.input
  if not input then return end
  -- STATICMENU_WRAP, and STATICMENU_DISABLE_B: no `b` arm at all.
  if input:wasPressed("up") then
    self.cursor = self.cursor > 1 and self.cursor - 1 or #GenderSelect.OPTIONS
  elseif input:wasPressed("down") then
    self.cursor = self.cursor < #GenderSelect.OPTIONS and self.cursor + 1 or 1
  elseif input:wasPressed("a") or input:wasPressed("start") then
    -- MenuClickSound (../pokecrystal/home/menu.asm:793-803).
    self:playSfx("Sfx_ReadText2")
    self:choose(self.cursor)
  end
end

function GenderSelect:drawPanel()
  local G = love.graphics
  local palette = GenderSelect.PALETTE
  -- pokecrystal/engine/menus/init_gender.asm:93-101
  local ground = GbcPalette.color(palette, 2) or GenderSelect.GROUND
  G.setColor(ground[1] / 255, ground[2] / 255, ground[3] / 255, 1)
  G.rectangle("fill", 0, 0, Chrome.SCREEN_W * 8, Chrome.SCREEN_H * 8)
  G.setColor(1, 1, 1, 1)
  Chrome.paletteBox(SAY_X, SAY_Y, SAY_W + 2, SAY_H + 2, palette)
  -- ../pokecrystal/home/text.asm:473
  Chrome.printWrapped(table.concat(Typer.text(self, {}), "\n"),
    SAY_TEXT_X, SAY_TEXT_Y, SAY_W, 2, 2, palette)
  -- pokecrystal/engine/menus/init_gender.asm:31-34
  if not self:menuOpen() then return end
  Chrome.paletteBox(BOX_X, BOX_Y, BOX_W, BOX_H, palette)
  for i, option in ipairs(GenderSelect.OPTIONS) do
    local row = TEXT_Y + (i - 1) * ROW_STEP
    Chrome.printThrough(Strings(option.label), TEXT_X, row, palette)
    if i == self.cursor then
      Chrome.cursorThrough(CURSOR_X, row, palette)
    end
  end
end

function GenderSelect:drawBody()
  IntroFade.paint(self, Chrome.SCREEN_W * 8, Chrome.SCREEN_H * 8,
    function() self:drawPanel() end)
end

function GenderSelect:draw()
  Chrome.withClip(function() self:drawBody() end)
end

function GenderSelect:drawWidescreen(winW, winH)
  local r, g, b = IntroFade.surround(self, GenderSelect.PALETTE, 1, 1, 1)
  Chrome.withPanel(winW, winH, r, g, b, function() self:drawBody() end)
end

return GenderSelect
