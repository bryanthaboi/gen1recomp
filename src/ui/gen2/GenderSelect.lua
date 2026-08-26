-- ../pokecrystal/engine/menus/init_gender.asm:23-41 InitGender, which
-- PlayerProfileSetup runs before OakSpeech (engine/menus/intro_menu.asm:61-83).

local Chrome = require("src.ui.gen2.Chrome")
local Music = require("src.core.Music")
local RomText = require("src.core.RomText")
local Sound = require("src.core.Sound")
local Strings = require("src.core.Strings")

local GenderSelect = {}
GenderSelect.__index = GenderSelect
GenderSelect.isOpaque = true

-- .MenuData's two items (../pokecrystal/engine/menus/init_gender.asm:50-53),
-- and the wPlayerGender byte each writes (`ld a, [wMenuCursorY] / dec a`).
GenderSelect.OPTIONS = {
  { label = "Boy", gender = "male" },
  { label = "Girl", gender = "female" },
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
-- writes; colour 1 is the tile the screen is filled with.
GenderSelect.GROUND = { 74, 247, 255 }

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
  self.text = RomText(self.data, "_AreYouABoyOrAreYouAGirlText",
    FALLBACK)
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

function GenderSelect:update(_dt)
  if self.exit then
    self.exit = self.exit - 1
    if self.exit > 0 then return end
    self.exit = nil
    if self.onDone then self.onDone(self.chosen) end
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
  local ground = GenderSelect.GROUND
  G.setColor(ground[1] / 255, ground[2] / 255, ground[3] / 255, 1)
  G.rectangle("fill", 0, 0, Chrome.SCREEN_W * 8, Chrome.SCREEN_H * 8)
  G.setColor(1, 1, 1, 1)
  Chrome.textbox(SAY_X, SAY_Y, SAY_W, SAY_H)
  Chrome.printWrapped(self.text, SAY_TEXT_X, SAY_TEXT_Y, SAY_W, SAY_H - 1)
  Chrome.box(BOX_X, BOX_Y, BOX_W, BOX_H)
  for i, option in ipairs(GenderSelect.OPTIONS) do
    local row = TEXT_Y + (i - 1) * ROW_STEP
    Chrome.print(option.label, TEXT_X, row)
    if i == self.cursor then Chrome.cursor(CURSOR_X, row) end
  end
end

function GenderSelect:draw()
  self:drawPanel()
end

function GenderSelect:drawWidescreen(winW, winH)
  local G = love.graphics
  G.setColor(1, 1, 1, 1)
  G.rectangle("fill", 0, 0, winW, winH)
  local scale = Chrome.fitScale(winW, winH)
  local ox, oy = Chrome.fitOrigin(winW, winH, scale)
  G.push()
  G.translate(ox, oy)
  G.scale(scale, scale)
  self:drawPanel()
  G.pop()
end

return GenderSelect
