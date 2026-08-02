-- Manual check that audio stays on the front output pair on interfaces with
-- more than two outputs (#626).  OpenAL only spatializes 1-channel Sources,
-- and one left at the default (0,0,0) position sits on the listener and is
-- spread over every output a device has; the fix renders one-shots as
-- 2-channel buffers so they map onto outputs 1+2 like the music already did.
-- Positions come from pokered data/maps/objects/PalletTown.asm (warps at
-- (5,5), (13,5), (12,11), kept clear of) plus data/generated/maps.lua for the
-- walkable/blocked cells.  Channel counts a machine can check; the routing
-- only an ear on a multi-output interface can, hence the hand-off.
-- Do NOT set POKEPORT_SPEED: fast-forward scales only the logic clock and
-- desyncs the audio ordering this driver depends on.
--   POKEPORT_DRIVER=tests/drivers/audio_channels_bug626_test.lua POKEPORT_IDENTITY=bug626 POKEPORT_TOUCH=0 love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Sound = require("src.core.Sound")
  local Music = require("src.core.Music")
  local ChipAudio = require("src.core.ChipAudio")

  -- pokered data/maps/objects/PalletTown.asm: the three warps sit at (5,5),
  -- (13,5) and (12,11), so (10,8) is open ground clear of all of them and of
  -- the two walking NPCs' start cells ((3,8) girl, (11,14) fisher).
  local MAP = "PALLET_TOWN"
  local STAND = { x = 10, y = 8, facing = "down" }

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  local function channels(src)
    if not src then return nil end
    local ok, n = pcall(function() return src:getChannelCount() end)
    return ok and n or nil
  end

  if not love.audio then
    check("love.audio is available", false)
    U.log("This run has no audio device, so nothing below can be judged.")
    U.log("Rerun on a desktop love build with the interface connected.")
    while true do coroutine.yield() end
  end
  check("love.audio is available", true)

  -- a muted save reads exactly like the bug being fixed: silence everywhere
  local opts = game.save and game.save.options or {}
  check("sfxVol is not zero (" .. tostring(opts.sfxVol or 7) .. ")",
        (opts.sfxVol or 7) ~= 0)
  check("musicVol is not zero (" .. tostring(opts.musicVol or 7) .. ")",
        (opts.musicVol or 7) ~= 0)

  -- an unknown key makes Sound.play return nil, which would read as a channel
  -- FAIL for the wrong reason
  local sfxTable = game.data.audio and game.data.audio.sfx or {}
  local cryTable = game.data.audio and game.data.audio.cries or {}
  local songTable = game.data.audio and game.data.audio.songs or {}
  check("sfx key Press_AB is in this cache", sfxTable.Press_AB ~= nil)
  check("sfx key Collision is in this cache", sfxTable.Collision ~= nil)
  check("cry PIKACHU is in this cache", cryTable.PIKACHU ~= nil)
  check("song Music_PalletTown is in this cache",
        songTable.Music_PalletTown ~= nil)

  -- the machine-checkable half of the fix: every one-shot is a stereo buffer
  local sfx = Sound.play(game.data, "Press_AB")
  check("menu beep source is stereo", channels(sfx) == 2)
  U.wait(30)

  local cry = Sound.playCry(game.data, "PIKACHU")
  check("cry source is stereo", channels(cry) == 2)
  U.wait(60)

  -- the siren is built by hand in ChipAudio, not through ChipSynth, so it is
  -- its own path and its own regression risk
  local ok, alarm = pcall(ChipAudio.newLowHealthAlarm)
  check("low-health siren is stereo", ok and channels(alarm) == 2)
  if ok and alarm and alarm.stop then pcall(alarm.stop, alarm) end

  -- reach the moment: overworld with the town theme running and a beep fired
  U.teleport(game, MAP, STAND.x, STAND.y, STAND.facing)
  U.wait(10)
  Music.play(game.data, "Music_PalletTown", true)
  U.wait(60)

  local ow = game.overworld
  check("overworld is up on " .. MAP, ow ~= nil)

  -- bump a wall so the collision beep (OverworldController: Sound.play
  -- "Collision") sounds at least once before the hand-off.  The blocked
  -- neighbour is looked up rather than hardcoded, so a map edit degrades to
  -- "walked a step" instead of a silent no-op.
  local bumped = false
  if ow and ow.map then
    local dirs = {
      { 0, -1, "up" }, { 0, 1, "down" }, { -1, 0, "left" }, { 1, 0, "right" },
    }
    for _, d in ipairs(dirs) do
      local cx, cy = ow.player.cellX + d[1], ow.player.cellY + d[2]
      if not ow.map:isWalkableCell(cx, cy) then
        U.hold(game, d[3], 24)
        U.wait(20)
        bumped = true
        U.log("walked into the wall at", cx, cy, "facing", d[3])
        break
      end
    end
    if not bumped then
      -- open ground on all four sides: walk a step instead, the human can
      -- find a wall themselves in a moment
      U.hold(game, "down", 24)
      U.wait(20)
      U.log("no wall next to (" .. STAND.x .. ", " .. STAND.y ..
            "), took a step instead; bump one by hand")
    end
  end
  check("a collision beep was fired before hand-off", bumped)

  U.tap(game, "start")
  U.wait(40)
  U.tap(game, "b")
  U.wait(20)

  U.log("Pallet Town is playing and you have the pad; bump walls and open")
  U.log("START to fire beeps, and press a cry with the PC or party screens.")
  U.log("On a multi-output interface the music and every beep and cry should")
  U.log("come out of outputs 1 and 2 only, with 3/4 and 5/6 dead silent.")
  U.log("The near miss to listen for is an SFX still faintly there on 5+6")
  U.log("under the music: that is the old ambient spread and means a one-shot")
  U.log("path was missed, a mod file def or a Yellow PCM clip or the siren.")
  U.log("Also listen for a beep arriving on output 3 alone, which would mean")
  U.log("something positioned a mono source instead of widening it to stereo.")
  U.log("Selecting outputs 5+6 in macOS will not move the game there either")
  U.log("way; that is device-level routing, not something the app can ask for.")

  while true do
    coroutine.yield()
  end
end
