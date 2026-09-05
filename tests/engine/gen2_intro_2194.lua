-- pokecrystal/engine/menus/init_gender.asm:23-41
-- pokecrystal/engine/menus/intro_menu.asm:645-696,854-888
-- pokecrystal/home/fade.asm:22-113

package.path = "./?.lua;./?/init.lua;" .. package.path

love = love or require("tests.love_stub")

local T = require("tests.harness")
local eq, check = T.eq, T.check
local GbcPalette = require("src.render.GbcPalette")
local GenderSelect = require("src.ui.gen2.GenderSelect")
local IntroFade = require("src.ui.gen2.IntroFade")
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

do
  local input = fakeInput()
  local gender = GenderSelect.new({ input = input }, { save = { player = {} } })
  check(gender.typer ~= nil and not gender.typer:done(),
    "the prompt opens mid-typewriter")
  check(not gender:menuOpen(),
    "LoadMenuHeader runs after PrintText, so there is no box yet")
  input:press("a")
  gender:update(0)
  eq(gender.chosen, nil, "and A while it types does not pick Boy")

  for _ = 1, 600 do
    if gender.typer:done() then break end
    gender:update(0)
  end
  check(gender.typer:done(), "the text finishes")
  check(not gender:menuOpen(), "WaitBGMap2 still holds the box")
  for _ = 1, GenderSelect.MENU_OPEN_FRAMES - 1 do
    gender:update(0)
    check(not gender:menuOpen(), "for its whole four frames")
  end
  gender:update(0)
  check(gender:menuOpen(), "and only then is VerticalMenu up")

  input:press("a")
  gender:update(0)
  eq(gender.chosen, "male", "A on the open menu picks Boy")
end

do
  local want = { 0x54, 0xA8, 0xFC, 0xF8, 0xF4, 0xE4 }
  eq(#OakSpeech.FRONTPIC_BGP, #want, "IntroFadePalettes is six rows")
  for i, byte in ipairs(want) do
    eq(OakSpeech.FRONTPIC_BGP[i], byte,
      string.format("IntroFadePalettes[%d] is 0x%02X", i, byte))
  end
  eq(OakSpeech.FRONTPIC_STEP, 10, "each row is held ld c, 10")
  eq(OakSpeech.ROTATE_FRAMES, 60, "b = 6 rows x 10 frames")

  for t = 0, OakSpeech.ROTATE_FRAMES - 1 do
    eq(OakSpeech.frontpicBgp(t), want[math.floor(t / 10) + 1],
      "the walk steps every 10 frames")
  end
  eq(OakSpeech.frontpicBgp(120), 0xE4, "and ends on the identity")

  local speech = setmetatable({}, OakSpeech)
  speech:reveal("rotate")
  eq(speech.picReveal.dur, 60, "a rotate reveal runs the whole walk")
  speech:reveal("wipe")
  eq(speech.picReveal.dur, OakSpeech.WIPE_FRAMES,
    "Intro_WipeInFrontpic is its own length")
  eq(OakSpeech.WIPE_FRAMES, 16, "hWX $77, sub 8 per frame, plus the first")

  local oak = {
    { 255, 255, 255 }, { 248, 168, 80 }, { 112, 88, 56 }, { 0, 0, 0 },
  }
  local flat = GbcPalette.remap(oak, 0xA8)
  eq(flat[1], oak[1], "colour 0 stays 0, so the ground never moves")
  eq(flat[2], oak[3], "shade 1 is colour 2")
  eq(flat[3], oak[3], "and so is shade 2")
  eq(flat[4], oak[3], "and shade 3: one flat colour")
end

do
  local steps = OakSpeech.defaultSteps({ game = { data = {} } })
  local fades = { oak_welcome = true, world_spiel = true, oak_study = true }
  local seen = {}
  for _, step in ipairs(steps) do
    eq(step.fadeOut and true or false, fades[step.id] or false,
      "RotateThreePalettesRight after " .. tostring(step.id))
    if step.reveal then seen[step.id] = step.reveal end
  end
  eq(seen.oak_welcome, "rotate", "Oak comes up on the frontpic walk")
  eq(seen.oak_study, "rotate", "and so does he the second time")
  eq(seen.ask_player_name, "rotate", "and the player pic with him")
end

do
  local rows = {
    outBlack = { 0xE4, 0xF9, 0xFE, 0xFF },
    inBlack = { 0xFF, 0xFE, 0xF9, 0xE4 },
    outWhite = { 0x90, 0x40, 0x00 },
    inWhite = { 0x40, 0x90, 0xE4 },
  }
  for kind, want in pairs(rows) do
    local fade = IntroFade.new(kind)
    for i, byte in ipairs(want) do
      eq(fade:bgp(), byte,
        string.format("%s step %d writes 0x%02X", kind, i, byte))
      for _ = 1, IntroFade.STEP_FRAMES do fade:tick() end
    end
    check(fade:done(), kind .. " is #rows x 8 frames")
  end

  local pal = GenderSelect.PALETTE
  local rotated = GbcPalette.remap(pal, 0xF9)
  eq(rotated[1], pal[2], "colour 0 shows colour 1")
  eq(rotated[2], pal[3], "colour 1 shows colour 2")
  eq(rotated[3], pal[4], "colour 2 shows black")
  eq(rotated[4], pal[4], "and colour 3 stays black")
end
