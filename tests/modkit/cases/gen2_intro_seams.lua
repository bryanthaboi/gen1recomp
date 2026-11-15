-- Gold's intro seams: the Oak speech under Gen 1's names, and the GS boot
-- cinema under its own.
--
-- Two different claims are being made here, and they are deliberately not the
-- same claim:
--
--   * src/ui/gen2/OakSpeech.lua reuses `intro.oak_speech.build` and the four
--     `intro.oak_speech.*` events VERBATIM -- same names, same payload keys,
--     same moments -- because Gold has a real Oak speech and a mod written for
--     Red's must land on Gold's without a second listener.
--   * the copyright card, the GAME FREAK splash, the attract movie and the
--     Ho-Oh title have NO Gen 1 counterpart, so they take new `intro.boot.*`
--     names rather than borrowing one that would then mean two things.
--
-- Both halves are also the parity case the no-mod gate wants: with nobody
-- subscribed every one of these sites must be inert.

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Events = require("src.mods.Events")
local Hooks = require("src.mods.Hooks")
local Logger = require("src.core.Logger")
local Runtime = require("src.mods.Runtime")

local CopyrightSplash = require("src.ui.gen2.CopyrightSplash")
local GameFreakPresents = require("src.ui.gen2.GameFreakPresents")
local GoldSilverIntro = require("src.ui.gen2.GoldSilverIntro")
local OakSpeech = require("src.ui.gen2.OakSpeech")
local TitleState = require("src.ui.gen2.TitleState")

-- The shared names, spelled out so a rename has to come through this file.
local SPEECH_EVENTS = {
  "intro.oak_speech.started",
  "intro.oak_speech.step",
  "intro.oak_speech.answered",
  "intro.oak_speech.finished",
}
-- ...and the Gen 2-only ones.
local BOOT_EVENTS = {
  "intro.boot.copyright",
  "intro.boot.gamefreak",
  "intro.boot.movie",
  "intro.boot.movie_ended",
  "intro.boot.title",
}

local savedEvents, savedHooks = Runtime.events, Runtime.hooks

local function logged(fragment)
  for _, line in ipairs(Logger.history or {}) do
    if line:find(fragment, 1, true) then return true end
  end
  return false
end

local function fakeGame()
  return { data = {}, save = { player = {} } }
end

-- ------- 1. no-mod parity: every site cold

do
  Runtime.events, Runtime.hooks = savedEvents, savedHooks
  for _, name in ipairs(SPEECH_EVENTS) do
    T.eq(Runtime.wants(name), false, "no subscriber leaves " .. name .. " cold")
  end
  for _, name in ipairs(BOOT_EVENTS) do
    T.eq(Runtime.wants(name), false, "no subscriber leaves " .. name .. " cold")
  end
  T.eq(Runtime.wantsHook("intro.oak_speech.build"), false,
    "no wrapper leaves intro.oak_speech.build cold")

  -- the four boot cards still run their moment with nobody listening
  CopyrightSplash.new(fakeGame(), {}):enter()
  GameFreakPresents.new(fakeGame(),
    { oakSpeech = require("tests.fixtures.gen2_oak_speech").data() }):enter()
  local movie = GoldSilverIntro.new(fakeGame(), {})
  movie:enter()
  movie:finish()
  TitleState.new(fakeGame(), { title = require("tests.fixture_data.gen2_title_s7_c").gold }):enter()
  T.check(true, "the boot cinema runs unsubscribed")
end

-- ------- 2. the Oak speech step list

do
  local speech = OakSpeech.new(fakeGame(),
    { data = require("tests.fixtures.gen2_oak_speech").data() })
  local steps = OakSpeech.defaultSteps(speech)
  T.eq(#steps, 9, "Gold's vanilla speech has nine beats")
  T.eq(steps[1].id, "init_clock",
    "the speech opens on the farcall InitClock beat")
  T.eq(steps[#steps].id, "shrink", "and ends on ShrinkPlayer")

  -- the anchors a Gen 1 mod already knows how to aim at
  local byId = {}
  for index, step in ipairs(steps) do byId[step.id] = index end
  for _, id in ipairs({ "oak_welcome", "demo_mon", "world_spiel",
                        "ask_player_name", "name_player", "legend",
                        "shrink" }) do
    T.check(byId[id] ~= nil,
      "Gold keeps Gen 1's step anchor `" .. id .. "`")
  end
  T.check(byId.oak_welcome < byId.demo_mon
      and byId.demo_mon < byId.name_player
      and byId.name_player < byId.shrink,
    "and keeps them in Gen 1's order")
end

-- ------- 3. intro.oak_speech.build, the hook Gen 1 already ships

do
  Runtime.events, Runtime.hooks = Events.new(), Hooks.new()
  local speech = OakSpeech.new(fakeGame(),
    { data = require("tests.fixtures.gen2_oak_speech").data() })

  Runtime.hooks:wrap("intro.oak_speech.build", function(nextFn, steps, sp)
    steps = nextFn(steps, sp)
    table.insert(steps, 3, { id = "extra_q", kind = "choice",
      saveKey = "mood", choices = { "FINE", "TIRED" } })
    return steps
  end, 0, "fixture")
  local built = speech:buildSteps()
  T.eq(built[3].id, "extra_q",
    "intro.oak_speech.build can insert a beat into Gold's speech")
  T.eq(built[4].id, "demo_mon", "later vanilla beats shift down")
  Runtime.hooks:removeOwner("fixture")

  Runtime.hooks:wrap("intro.oak_speech.build", function() return 42 end, 0, "bad")
  built = speech:buildSteps()
  T.eq(built[1].id, "init_clock",
    "a non-table intro.oak_speech.build result degrades to vanilla")
  T.check(logged("intro.oak_speech.build returned"),
    "and the degrade is logged, as it is under Gen 1")
  Runtime.hooks:removeOwner("bad")
end

-- ------- 4. the four lifecycle events, with the Gen 1 payload keys

do
  Runtime.events, Runtime.hooks = Events.new(), Hooks.new()
  local speech = OakSpeech.new(fakeGame(),
    { data = require("tests.fixtures.gen2_oak_speech").data() })

  -- Replace the beats with two that need no stack, so the lifecycle can be
  -- driven headlessly: `fn` is the escape hatch a build wrapper gets.
  Runtime.hooks:wrap("intro.oak_speech.build", function()
    return {
      { id = "probe_one", kind = "fn",
        run = function(sp, done) sp:recordAnswer({ id = "probe_one",
          saveKey = "mood" }, 2, "TIRED", "TIRED") done() end },
      { id = "probe_two", kind = "fn", run = function(_, done) done() end },
    }
  end, 0, "fixture")

  local started, stepped, answered, finished = nil, {}, nil, nil
  Runtime.events:on("intro.oak_speech.started", function(ev)
    started = ev
  end, 0, "fixture")
  Runtime.events:on("intro.oak_speech.step", function(ev)
    stepped[#stepped + 1] = ev
  end, 0, "fixture")
  Runtime.events:on("intro.oak_speech.answered", function(ev)
    answered = ev
  end, 0, "fixture")
  Runtime.events:on("intro.oak_speech.finished", function(ev)
    finished = ev
  end, 0, "fixture")

  speech:enter()

  T.check(started ~= nil and started.speech == speech
      and type(started.steps) == "table",
    "intro.oak_speech.started carries { speech, steps }")
  T.eq(#stepped, 2, "intro.oak_speech.step fires once per beat")
  T.eq(stepped[1].index, 1, "and carries the 1-based index")
  T.eq(stepped[1].step.id, "probe_one", "and the step itself")
  T.check(answered ~= nil and answered.saveKey == "mood"
      and answered.value == "TIRED" and answered.index == 2
      and answered.label == "TIRED" and answered.speech == speech,
    "intro.oak_speech.answered carries Gen 1's six keys")
  T.eq(speech.answers.mood, "TIRED", "and the answer is stored on the speech")
  T.check(finished ~= nil and finished.answers == speech.answers,
    "intro.oak_speech.finished carries the answer table")

  -- #308's guard, ported: a second finish is not a second speech.
  local firstFinish = finished
  finished = nil
  speech:finish()
  T.eq(finished, nil, "finished fires exactly once per speech")
  T.check(firstFinish ~= nil, "and it did fire the first time")

  Runtime.events:removeOwner("fixture")
  Runtime.hooks:removeOwner("fixture")
end

-- ------- 5. the GS boot cinema's own names

do
  Runtime.events, Runtime.hooks = Events.new(), Hooks.new()
  local seen = {}
  for _, name in ipairs(BOOT_EVENTS) do
    Runtime.events:on(name, function(ev) seen[name] = ev end, 0, "fixture")
  end

  local game = fakeGame()
  CopyrightSplash.new(game, {}):enter()
  T.check(seen["intro.boot.copyright"] ~= nil,
    "the copyright card announces itself")
  T.check(seen["intro.boot.copyright"].screen ~= nil,
    "with the screen in the payload")

  GameFreakPresents.new(game,
    { oakSpeech = require("tests.fixtures.gen2_oak_speech").data() }):enter()
  T.check(seen["intro.boot.gamefreak"] ~= nil,
    "the GAME FREAK splash announces itself")

  local movie = GoldSilverIntro.new(game, {})
  movie:enter()
  T.check(seen["intro.boot.movie"] ~= nil, "the attract movie announces itself")
  movie:skip()
  T.check(seen["intro.boot.movie_ended"] ~= nil,
    "and announces its end")
  T.eq(seen["intro.boot.movie_ended"].skipped, true,
    "intro.boot.movie_ended reports a button skip")

  -- a movie that plays out reports the other answer
  seen["intro.boot.movie_ended"] = nil
  local watched = GoldSilverIntro.new(game, {})
  watched:enter()
  watched:finish()
  T.eq(seen["intro.boot.movie_ended"].skipped, false,
    "and reports a movie that was watched to the end")

  TitleState.new(game, { title = require("tests.fixture_data.gen2_title_s7_c").gold }):enter()
  T.check(seen["intro.boot.title"] ~= nil, "the title screen announces itself")

  Runtime.events:removeOwner("fixture")
end

Runtime.events, Runtime.hooks = savedEvents, savedHooks

T.finish("gen2_intro_seams")
