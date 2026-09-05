-- pokered/engine/movie/oak_speech/oak_speech.asm:70-108,191-209
-- pokered/home/fade.asm:26-62,65-73

package.path = "./?.lua;./?/init.lua;" .. package.path

love = love or require("tests.love_stub")

local T = require("tests.harness")
local eq, check = T.eq, T.check
local OakSpeech = require("src.ui.OakSpeech")
local Transition = require("src.render.Transition")

do
  local want = { 0x54, 0xA8, 0xFC, 0xF8, 0xF4, 0xE4 }
  eq(#OakSpeech.INTRO_FADE_BGP, #want, "IntroFadePalettes is six entries")
  for i, byte in ipairs(want) do
    eq(OakSpeech.INTRO_FADE_BGP[i], byte,
      string.format("IntroFadePalettes[%d] is 0x%02X", i, byte))
  end
  eq(OakSpeech.INTRO_FADE_STEP, 10, "FadeInIntroPic holds each write ld c, 10")
  eq(#OakSpeech.INTRO_FADE_BGP * OakSpeech.INTRO_FADE_STEP, 60,
    "FadeInIntroPic is b = 6 steps x 10 frames")

  eq(OakSpeech.WHITE_FADE_STEP, 8, "GBFadeIncCommon holds each write ld c, 8")
  local wantIn = { 0x40, 0x90, 0xE4 }
  for i, byte in ipairs(wantIn) do
    eq(OakSpeech.WHITE_IN_BGP[i], byte,
      string.format("GBFadeInFromWhite step %d is 0x%02X", i, byte))
  end
  eq(#OakSpeech.WHITE_IN_BGP * OakSpeech.WHITE_FADE_STEP, 24,
    "GBFadeInFromWhite is b = 3 steps x 8 frames")
end

do
  local popped, done = 0, false
  local game = { stack = { pop = function() popped = popped + 1 end } }
  local fade = Transition.whiteOut(game, function() done = true end)
  check(fade.isOpaque == false,
    "the fade draws nothing of its own so the pic and box fade under it")
  local seen = {}
  for _ = 1, 24 do
    fade:update(0)
    if not done then seen[#seen + 1] = fade:bgpByte() end
  end
  eq(popped, 1, "GBFadeOutToWhite is 24 frames, not whiteFlash's 7")
  check(done, "and the callback runs at the end of them")
  eq(seen[1], 0x90, "FadePal6 first")
  eq(seen[8], 0x90, "held eight frames")
  eq(seen[9], 0x40, "then FadePal7")
  eq(seen[16], 0x40, "held eight frames")
  eq(seen[17], 0x00, "then FadePal8, solid white")
  eq(#seen, 23, "and the 24th frame hands over")
  local map = Transition.shadeMapFor(0x00)
  check(map and map[0] == 0 and map[1] == 0 and map[2] == 0 and map[3] == 0,
    "FadePal8 maps every shade to color 0")
  check(Transition.shadeMapFor(0x54) == Transition.shadeMapFor(0x54),
    "the shade map for a BGP byte is memoized, not rebuilt per frame")
  check(Transition.shadeMapFor(0x54) ~= Transition.shadeMapFor(0xA8),
    "and distinct bytes keep distinct maps")
end

do
  local steps = {}
  for _, step in ipairs(OakSpeech.defaultSteps({})) do steps[step.id] = step end

  eq(steps.oak_welcome and steps.oak_welcome.reveal, "fade",
    "FadeInIntroPic opens on Oak (oak_speech.asm:70)")
  check(steps.oak_welcome and steps.oak_welcome.fadeOut,
    "and OakSpeechText1 is followed by GBFadeOutToWhite (:73)")
  check(steps.world_spiel and steps.world_spiel.fadeOut,
    "OakSpeechText2 ends on GBFadeOutToWhite too (:84)")
  check(steps.confirm_player_name and steps.confirm_player_name.fadeOut,
    "ChoosePlayerName's fade out (:93)")
  eq(steps.ask_rival_name and steps.ask_rival_name.reveal, "fade",
    "FadeInIntroPic opens on the rival (:98)")
  check(steps.confirm_rival_name and steps.confirm_rival_name.fadeOut,
    ".skipSpeech's fade out (:103)")
  eq(steps.legend and steps.legend.reveal, "fade_white_in",
    "and the player pic comes back on GBFadeInFromWhite (:108)")
end

local function stub()
  return setmetatable({}, OakSpeech)
end

do
  local speech = stub()
  local fired = 0
  speech:revealPic("fade", function() fired = fired + 1 end)
  eq(speech.picReveal.dur, 60, "the Oak/rival fade in runs 60 frames")

  local seen = {}
  for _ = 1, 60 do
    speech:update(0)
    seen[#seen + 1] = OakSpeech.revealBgp(speech.picReveal)
  end
  eq(fired, 1, "FadeInIntroPic hands over once, on frame 60")
  eq(seen[1], 0x54, "the first palette is up on frame 1")
  eq(seen[10], 0x54, "and held for ten frames")
  eq(seen[11], 0xA8, "then the second")
  eq(seen[30], 0xFC, "the silhouette is solid black by frame 30")
  eq(seen[41], 0xF4, "the fifth palette at frame 41")
  eq(seen[51], 0xE4, "and the identity palette at frame 51")
  eq(seen[60], nil, "with the reveal gone on the frame it hands over")
  eq(speech.picReveal, nil, "and nothing left to re-arm")
end

do
  local speech = stub()
  local fired = 0
  speech:revealPic("fade_white_in", function() fired = fired + 1 end)
  eq(speech.picReveal.dur, 24, "GBFadeInFromWhite runs 24 frames")
  local seen = {}
  for _ = 1, 24 do
    speech:update(0)
    seen[#seen + 1] = OakSpeech.revealBgp(speech.picReveal)
  end
  eq(fired, 1, "and hands over once")
  eq(seen[1], 0x40, "FadePal7 first")
  eq(seen[9], 0x90, "then FadePal6")
  eq(seen[17], 0xE4, "then the identity palette")
end

do
  local speech = stub()
  speech:revealPic("wipe", function() end)
  eq(speech.picReveal.dur, 32, "MovePicLeft is still a 32-frame wipe")
  eq(OakSpeech.revealBgp(speech.picReveal), nil,
    "and writes no palette of its own (oak_speech.asm:211-225)")
end

T.finish("intro_fades_2188")
