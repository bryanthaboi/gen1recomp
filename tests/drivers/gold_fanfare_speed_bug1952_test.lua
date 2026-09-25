-- GAME SPEED must not pitch one-shot SFX (#1990/#1991/#1997).  Wait gates
-- still release early via their logic-frame budget (#1952); that path is
-- covered by the engine + Gen 1 battle drivers.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or os.getenv("POKEPORT_SHOT_DIR") or "/tmp/shots"
  local Sound = require("src.core.Sound")

  U.wait(45)
  if not (game.world and game.world.map) then
    error("bug1952: the gen 2 world never booted")
  end

  local vol = game.options and game.options.sfxVol
  if vol == 0 then error("bug1952: SFX VOL is 0, nothing to measure") end

  U.wait(2)
  if Sound.rate() ~= 1 then
    error(("bug1952: the rate was %s before any fast-forward"):format(
      tostring(Sound.rate())))
  end

  game.speedOverride = 4
  U.wait(2)
  if game:logicSpeed() ~= 4 then
    error(("bug1952: the overworld did not take the 4X override (%s)")
      :format(tostring(game:logicSpeed())))
  end
  U.log("gen2 speed override", 4, "sfx rate", Sound.rate())
  if Sound.rate() ~= 1 then
    error(("bug1952: Game2:update pitched SFX off GAME SPEED (rate %s at 4X)")
      :format(tostring(Sound.rate())))
  end

  local name = "Sfx_CaughtMon"
  local src = Sound.play(game.data, name)
  if not src then error("bug1952: " .. name .. " did not play") end
  local okd, dur = pcall(src.getDuration, src)
  local okp, pitch = pcall(src.getPitch, src)
  if not (okd and dur) then error("bug1952: no duration for " .. name) end
  U.log(("%s duration %.3fs pitch %s"):format(name, dur, tostring(pitch)))
  if not (okp and pitch == 1) then
    error(("bug1952: the gen 2 jingle was pitched with GAME SPEED (%s)")
      :format(tostring(pitch)))
  end

  local budget = Sound.waitFramesFor(name)
  local want = math.ceil(dur * 60) + 2
  U.log(("gate budget %d logic frames, hardware frames %d"):format(budget, want))
  if budget ~= want then
    error(("bug1952: the gen 2 gate budgets %d frames for a %d frame jingle")
      :format(budget, want))
  end

  U.shot(game, DIR .. "/bug1952_gold_fanfare.png")

  local t0, held = love.timer.getTime(), nil
  for _ = 1, 1200 do
    U.wait(1)
    if not Sound.isPlaying(name) then
      held = love.timer.getTime() - t0
      break
    end
  end
  if not held then error("bug1952: the gen 2 jingle never ended") end
  U.log(("held %.3fs of a %.3fs natural-pitch jingle"):format(held, dur))
  -- Freely playing (no wait gate cutting it) must take roughly the full
  -- duration -- proof the 4X logic clock did not chipmunk the source.
  if held < dur * 0.7 then
    error(("bug1952: the jingle finished early under 4X (%.3fs of %.3fs)")
      :format(held, dur))
  end
  if held > dur * 1.4 then
    error(("bug1952: the jingle dragged past its length (%.3fs of %.3fs)")
      :format(held, dur))
  end

  game.linkNet = { closed = false }
  if game:logicSpeed() ~= 1 then
    error(("speed lock: an open gen 2 link ran at %sX under a 4X override")
      :format(tostring(game:logicSpeed())))
  end
  game.linkNet = nil
  game.speedOverride = nil
  U.wait(2)
  if Sound.rate() ~= 1 then
    error(("bug1952: dropping back to 1X left the rate at %s")
      :format(tostring(Sound.rate())))
  end

  U.shot(game, DIR .. "/bug1952_gold_after.png")
  U.log("PASS the gen 2 jingle kept natural pitch under GAME SPEED")
  love.event.quit(0)
end
