-- #2171 the intro's missing palette rotations and ShrinkPlayer's player icon.
-- ../pokecrystal/home/fade.asm:22-113
-- ../pokecrystal/engine/rtc/timeset.asm:4-46
-- ../pokecrystal/engine/menus/intro_menu.asm:627-700, :802-950

package.path = "./?.lua;./?/init.lua;" .. package.path

love = love or require("tests.love_stub")

local T = require("tests.harness")
local eq, check = T.eq, T.check
local IntroFade = require("src.ui.gen2.IntroFade")
local InitClock = require("src.ui.gen2.InitClock")
local GenderSelect = require("src.ui.gen2.GenderSelect")
local OakSpeech = require("src.ui.gen2.OakSpeech")

local function fakeInput()
  return {
    pressed = {},
    wasPressed = function(self, b)
      local hit = self.pressed[b]
      self.pressed[b] = nil
      return hit and true or false
    end,
    press = function(self, b) self.pressed[b] = true end,
  }
end

-- --------------------------------------------------------------- the tables
do
  eq(IntroFade.STEP_FRAMES, 8, "RotatePalettesRight: ld c, 8 / DelayFrames")
  eq(IntroFade.frames("outBlack"), 32,
    "RotateFourPalettesLeft: b = 4 steps x 8 frames")
  eq(IntroFade.frames("inBlack"), 32, "RotateFourPalettesRight, the same")
  eq(IntroFade.frames("outWhite"), 24, "RotateThreePalettesRight: b = 3")
  eq(IntroFade.frames("inWhite"), 24, "RotateThreePalettesLeft: b = 3")
  eq(IntroFade.new("nonesuch"), nil, "and nothing else is a rotation")

  -- IncGradGBPalTable_03 .. _00: the first step is still the loaded palette.
  local out = IntroFade.new("outBlack")
  eq(out:level(), 0, "outBlack step 1 is table 03, the normal palette")
  for _ = 1, 8 do out:tick() end
  eq(out:level(), 1 / 3, "step 2 is table 02")
  for _ = 1, 24 do out:tick() end
  check(out:done(), "32 frames is the whole rotation")
  eq(out:level(), 1, "ending on table 00, every index black")
  local r, g, b = out:blend(1, 1, 1)
  eq(r + g + b, 0, "so the surround under it is black too")

  -- IncGradGBPalTable_00 .. _03: black first, loaded palette last.
  local into = IntroFade.new("inBlack")
  eq(into:level(), 1, "inBlack opens on table 00, fully black")
  for _ = 1, 32 do into:tick() end
  eq(into:level(), 0, "and lands back on the loaded palette")

  -- IncGradGBPalTable_05 .. _07.
  local white = IntroFade.new("outWhite")
  eq(white:level(), 1 / 3, "outWhite opens on table 05")
  for _ = 1, 24 do white:tick() end
  eq(white:level(), 1, "and ends on table 07, every index white")
  local wr, wg, wb = white:blend(0, 0, 0)
  eq(wr + wg + wb, 3, "with a white surround")
end

-- ---------------------------------------------------- NEW GAME -> the clock
do
  -- Gold and Silver: NewGame_ClearTilemapEtc has already blanked the screen,
  -- so InitClock's RotateFourPalettesLeft fades a cleared tilemap out.
  local clock = InitClock.new({ input = fakeInput() },
    { save = {}, fades = true })
  check(clock.blank, "the leading fade runs over a cleared tilemap")
  check(IntroFade.busy(clock), "and it is a fade, not the clock screen")
  eq(clock.fade.kind, "outBlack", "RotateFourPalettesLeft first")
  for _ = 1, 32 do clock:update(0) end
  eq(clock.fade and clock.fade.kind, "inBlack",
    "then RotateFourPalettesRight into the clock")
  check(not clock.blank, "which is the clock screen, not the cleared tilemap")
  eq(clock.phase, "intro", "and no input reached it while it was fading")
  for _ = 1, 32 do clock:update(0) end
  check(not IntroFade.busy(clock), "64 frames covers both rotations")

  -- Crystal: the gender screen carried RotateFourPalettesLeft out with it.
  local after = InitClock.new({ input = fakeInput() },
    { save = {}, fades = true, faded = true })
  eq(after.fade and after.fade.kind, "inBlack",
    "so the clock opens straight on RotateFourPalettesRight")
  check(not after.blank, "with the clock screen already under it")

  -- The day wheel and the driver path never fade.
  local day = InitClock.new({}, { save = {}, mode = "day", fades = true })
  check(not IntroFade.busy(day), "SetDayOfWeek is not InitClock")
  local driven = InitClock.new({}, { save = {}, autoConfirm = true,
    fades = true })
  check(not IntroFade.busy(driven), "and autoConfirm keeps its frame counts")
  local plain = InitClock.new({ input = fakeInput() }, { save = {} })
  check(not IntroFade.busy(plain), "a screen opened without fades has none")
end

-- ------------------------------------------------- the clock's own way out
do
  local input = fakeInput()
  local done = false
  local clock = InitClock.new({ input = input },
    { save = {}, fades = true, faded = true,
      onDone = function() done = true end })
  for _ = 1, 32 do clock:update(0) end
  clock.phase = "response"
  clock.page = 1
  clock:startText()
  clock.typer.shown = clock.typer.total
  input:press("a")
  clock:update(0)
  check(not done, "A on the last page does not hand over on the same frame")
  eq(clock.fade and clock.fade.kind, "outBlack",
    "OakSpeech's RotateFourPalettesLeft runs on the clock screen")
  eq(clock.typer.shown, clock.typer.total,
    "with Oak's answer still printed, not reprinted into an empty box")
  for _ = 1, 31 do clock:update(0) end
  check(not done, "for the whole 32 frames")
  clock:update(0)
  check(done, "and only then is InitClock done")
end

-- ------------------------------------------- the gender screen's way out
do
  local chosen = nil
  local gender = GenderSelect.new({}, {
    save = { player = {} }, fades = true,
    onDone = function(g) chosen = g end,
  })
  gender:choose(2)
  for _ = 1, 10 do gender:update(0) end
  eq(chosen, nil, "the 10-frame DelayFrames does not hand over on its own")
  eq(gender.fade and gender.fade.kind, "outBlack",
    "InitClock's fade runs while the answered gender screen is still up")
  for _ = 1, 31 do gender:update(0) end
  eq(chosen, nil, "for the whole rotation")
  gender:update(0)
  eq(chosen, "female", "and the answer follows the black screen")

  local quick = nil
  local plain = GenderSelect.new({}, {
    save = { player = {} }, onDone = function(g) quick = g end })
  plain:choose(1)
  for _ = 1, 10 do plain:update(0) end
  eq(quick, "male", "a screen opened without fades keeps its old timing")
end

-- ---------------------------------------------------- the shrink timeline
do
  eq(OakSpeech.SHRINK_MUSIC_FADE, 32,
    "ld a, 32 / ld [wMusicFade] -- and it is set before the SFX")
  eq(OakSpeech.SHRINK_PIC1, 8, "DelayFrames 8, then Shrink1Pic")
  eq(OakSpeech.SHRINK_PIC2, 16, "DelayFrames 8, then Shrink2Pic")
  eq(OakSpeech.SHRINK_CLEAR, 24, "DelayFrames 8, then ClearBox 6,5 7x7")
  eq(OakSpeech.SHRINK_ICON, 27,
    "DelayFrames 3, then Intro_PlacePlayerSprite")
  eq(OakSpeech.SHRINK_END, 77, "DelayFrames 50, then RotateThreePalettesRight")

  local speech = setmetatable({}, OakSpeech)
  speech.shrinkPic1, speech.shrinkPic2 = "pic1", "pic2"
  speech.shrink = { frame = 0 }
  speech.shrinkText = { "I'll be seeing you" }
  speech.answers = {}
  local placed = 0
  speech.overworldIcon = function()
    placed = placed + 1
    return { image = false }
  end
  local finished = false
  speech.onDone = function() finished = true end

  for _ = 1, OakSpeech.SHRINK_CLEAR do speech:update(0) end
  eq(speech.pic, nil, "ClearBox takes the shrink frame down at 24")
  eq(speech.playerIcon, nil, "and nothing replaces it yet")
  for _ = 1, OakSpeech.SHRINK_ICON - OakSpeech.SHRINK_CLEAR do
    speech:update(0)
  end
  eq(placed, 1, "Intro_PlacePlayerSprite runs once, at frame 27")
  check(speech.playerIcon ~= nil, "and the icon is what is on the screen")

  for _ = 1, OakSpeech.SHRINK_END - OakSpeech.SHRINK_ICON do speech:update(0) end
  eq(speech.shrink, nil, "the 50-frame hold ends at 77")
  eq(speech.fade and speech.fade.kind, "outWhite",
    "on RotateThreePalettesRight, not on the world load")
  check(speech.playerIcon ~= nil, "with the icon still up through the fade")
  check(not finished, "and the speech is not over yet")
  for _ = 1, 24 do speech:update(0) end
  check(finished, "24 frames later it is")
  eq(speech.playerIcon, nil, "ClearTilemap takes the icon with it")
  eq(speech.shrinkText, nil, "and the line under it")
end
