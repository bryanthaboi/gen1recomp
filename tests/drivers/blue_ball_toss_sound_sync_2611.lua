-- pokered/engine/battle/animations.asm:694
local U = require("tests.drivers.util")
local Pokemon = require("src.pokemon.Pokemon")
local BattleState = require("src.battle.BattleState")
local Sound = require("src.core.Sound")

return function(game)
  local dir = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/ball-toss-2611"
  local failures, active, record = 0, nil, nil
  local realPlay = Sound.play
  local function check(label, condition, detail)
    if condition then U.log("PASS", label) else
      failures = failures + 1
      U.log("FAIL", label, tostring(detail))
    end
    return condition
  end
  Sound.play = function(data, name, ...)
    local src = realPlay(data, name, ...)
    if active and record and name == "Ball_Toss" then
      local ap = active.animPlayer
      record.sounds[#record.sounds + 1] = { tick = U.frame(),
        elapsed = ap and ap.elapsed, name = active.animName,
        playing = active.animPlaying, source = src ~= nil }
    end
    return src
  end
  local function waitFor(predicate, limit, mash)
    for i = 1, limit do
      if predicate() then return true end
      if mash and i % 6 == 0 then U.tap(game, "a") else U.wait(1) end
    end
    return predicate() and true or false
  end
  local function run()
    game.save.options = game.save.options or {}
    game.save.options.animations = true
    U.teleport(game, "PALLET_TOWN", 10, 8, "down")
    local ow = game.overworld
    assert(ow, "overworld unavailable")
    local function leave()
      active = nil
      for _ = 1, 10 do
        if game.stack:top() == ow then return end
        game.stack:pop()
      end
      error("battle stack did not unwind")
    end
    local function scenario(kind, ball, shots)
      game.save.party = { Pokemon.new(game.data, "BLASTOISE", 60) }
      game.save.inventory = { [ball] = 10 }
      local b = kind == "trainer" and BattleState.newTrainer(game, "OPP_YOUNGSTER", 1)
        or BattleState.newWild(game, "DITTO", 10)
      b.onFinish = function() end
      b.catchAttempt = function() return false, 0 end
      if kind == "oldman" then b:makeOldManDemo(nil, false) end
      if kind == "safari" then b:makeSafari({ balls = 30, steps = 500 }) end
      ow:pushBattle(b)
      assert(waitFor(function() return b.phase == "menu" end, 2500, true),
        kind .. " battle menu never opened")
      if kind == "nocatch" then b.noCatch = true end
      if kind == "ghost" then b.ghost = true end
      record = { sounds = {} }
      active = b
      if kind == "safari" then
        U.tap(game, "a")
      elseif kind ~= "oldman" then
        U.tap(game, "down")
        assert(b.menuIndex == 3, "ITEM cursor unavailable")
        U.tap(game, "a")
        assert(waitFor(function() return game.stack:top() ~= b end, 180), "bag did not open")
        U.tap(game, "a")
      end
      local tossId = (kind == "trainer" or kind == "oldman") and "TOSS_ANIM"
        or b:tossAnimFor(ball)
      assert(waitFor(function()
        return b.animPlaying and b.animName == tossId
      end, 2000), kind .. " toss never started")
      local ap = b.animPlayer
      local expected = ap.steps[1].dur + ap.steps[2].dur
      local firstVisible, firstTick
      for _ = 1, 1000 do
        if not b.animPlaying or b.animName ~= tossId then break end
        local st = ap.steps[ap.stepIndex]
        if st and #st.sprites > 0 and not firstVisible then
          firstVisible, firstTick = ap.elapsed, U.frame()
        end
        if shots and ap.elapsed == ap.steps[1].dur then
          check("ball_first_visible_screenshot", U.still(game, dir .. "/2611_ball_first_visible.png"))
        elseif shots and ap.elapsed == expected then
          check("ball_sound_boundary_screenshot", U.still(game, dir .. "/2611_ball_in_flight_at_sound.png"))
        end
        U.wait(1)
      end
      local label = kind .. "_" .. ball:lower()
      local event = record.sounds[1]
      check(label .. "_first_visible_after_load", firstVisible == ap.steps[1].dur, firstVisible)
      check(label .. "_one_toss_sound", #record.sounds == 1, #record.sounds)
      check(label .. "_sound_after_first_block", event and event.playing
        and event.name == tossId and event.elapsed == expected,
        event and (tostring(event.name) .. "@" .. tostring(event.elapsed)))
      if not shots then
        check(label .. "_sound_lag_matches_block", event and firstTick
          and event.tick - firstTick == ap.steps[2].dur,
          event and firstTick and event.tick - firstTick)
      end
      check(label .. "_real_audio_source", event and event.source, event and event.source)
      check(label .. "_animation_started_cleanly", b.animStartWarned == nil)
      leave()
    end
    for _, s in ipairs({
      { "wild", "POKE_BALL" }, { "wild", "GREAT_BALL" },
      { "wild", "ULTRA_BALL" }, { "trainer", "POKE_BALL" },
      { "nocatch", "ULTRA_BALL" }, { "ghost", "POKE_BALL" },
      { "oldman", "POKE_BALL" }, { "safari", "SAFARI_BALL" },
    }) do scenario(s[1], s[2], false) end
    scenario("wild", "POKE_BALL", true)
  end
  local ok, err = xpcall(run, debug.traceback)
  Sound.play = realPlay
  if not ok then failures = failures + 1 U.log("FAIL ball_toss_driver_error", err) end
  U.log(failures == 0 and "PASS" or "FAIL", "ball_toss_sound_sync_2611")
  love.event.quit(failures == 0 and 0 or 1)
end
