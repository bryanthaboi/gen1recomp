-- Ear check: Route 8's wave-channel countermelody, at full volume and in the
-- right octave (#429).  ROUTE_8 is MUSIC_ROUTES3 (pokered data/maps/songs.asm:22)
-- and Music_Routes3_Ch3 is a dense 2-frame-per-note line; ChipAudio shipped
-- ch3 at 0.25 volume and 0.5 pitch, a quarter as loud and an octave below the
-- hardware's own octave (audio/engine_1.asm:904-944 writes CHAN3's frequency
-- register unmodified).  SELECT toggles the 0.1.38 mix back on to compare.
--   POKEPORT_DRIVER=tests/drivers/route8_music_bug429_test.lua POKEPORT_IDENTITY=bug429 POKEPORT_TOUCH=0 love .
-- No POKEPORT_SPEED: fast-forward scales the logic clock only and desyncs audio.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local ChipAudio = require("src.core.ChipAudio")
  local Music = require("src.core.Music")

  -- pokered data/maps/objects/Route8.asm keeps its trainers at (8,5), (13,9),
  -- (26,3-6) and (42,6), and warps at x 1, 8 and 13, so the road east of the
  -- gate is clear; (30, 8) is only a listening spot, walk anywhere from it.
  local MAP = "ROUTE_8"
  local SONG = "Music_Routes3"
  local STAND = { x = 30, y = 8, facing = "down" }

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- ---- what the ear cannot check -----------------------------------------
  local opts = game.save.options or {}
  local musicVol = opts.musicVol or 7
  local sfxVol = opts.sfxVol or 7
  if musicVol == 0 then
    U.log("FAIL music volume is 0: nothing below can be heard at all.")
    U.log("     Set MUSIC to 7 in OPTION first.")
  end
  if sfxVol == 0 then
    U.log("FAIL sfx volume is 0, so the step and menu sounds are gone too;")
    U.log("     set SFX to 7 in OPTION if the run should sound normal.")
  end
  check(("music volume %d, sfx volume %d"):format(musicVol, sfxVol),
        musicVol > 0)

  check(MAP .. " plays " .. SONG,
        (game.data.audio.mapSongs or {})[MAP] == SONG)
  local vols = ChipAudio.getChannelVolumes()
  local pitches = ChipAudio.getChannelPitches()
  check(("the shipped wave mix is unity (volume %s, pitch %s)")
          :format(tostring(vols[3]), tostring(pitches[3])),
        vols[3] == 1 and pitches[3] == 1)

  -- render the ch3 layer alone: a silent or near-silent wave track would make
  -- every claim below unhearable no matter what the mix says
  local song = (game.data.audio.songs or {})[SONG]
  local function waveLayer()
    return ChipAudio._renderMusicChannelForTest(game.data, song, 1.5, 3)
  end
  local function measure(sd)
    local peak, crossings, prev = 0, 0, sd:getSample(0)
    for index = 1, sd:getSampleCount() - 1 do
      local sample = sd:getSample(index)
      if math.abs(sample) > peak then peak = math.abs(sample) end
      if prev * sample < 0 then crossings = crossings + 1 end
      prev = sample
    end
    return peak, crossings
  end
  local peak, crossings = measure(waveLayer())
  check(("the ch3 countermelody renders (peak %.3f, %d zero crossings)")
          :format(peak, crossings), peak > 0.02 and crossings > 200)

  ChipAudio.setChannelVolumes({ 1, 1, 0.25, 1 })
  ChipAudio.setChannelPitches({ 1, 1, 0.5, 1 })
  local brokenPeak, brokenCrossings = measure(waveLayer())
  ChipAudio.setChannelVolumes({ 1, 1, 1, 1 })
  ChipAudio.setChannelPitches({ 1, 1, 1, 1 })
  check(("the 0.1.38 mix would render it at peak %.3f and %d crossings")
          :format(brokenPeak, brokenCrossings),
        brokenPeak < peak * 0.4 and brokenCrossings < crossings * 0.7)
  -- the invariant tests/engine/wave_channel_mix_bug429.lua asserts on blobs;
  -- this is the same statement measured on the ROM's own Music_Routes3

  -- ---- stand on the road with the theme running --------------------------
  U.teleport(game, MAP, STAND.x, STAND.y, STAND.facing)
  U.wait(20)
  local ow = game.overworld
  if not ow.map:isWalkableCell(STAND.x, STAND.y) then
    -- a map edit or a mod blocked the cell: take any free neighbour, the
    -- audio is what is being judged and any cell on Route 8 will do
    for _, d in ipairs({ { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 } }) do
      local cx, cy = STAND.x + d[1], STAND.y + d[2]
      if ow.map:isWalkableCell(cx, cy) and not ow:npcAtCell(cx, cy) then
        U.log(("(%d, %d) is blocked, standing on"):format(STAND.x, STAND.y),
              cx, cy)
        U.teleport(game, MAP, cx, cy, STAND.facing)
        U.wait(20)
        ow = game.overworld
        break
      end
    end
  end
  check("standing on " .. MAP, ow.map.id == MAP)

  local function restart()
    -- the playback queue holds ~6s of already-synthesized audio, so a mix
    -- change is inaudible until the song is rebuilt from the new values
    Music.stop()
    Music.playMap(game.data, MAP)
  end
  restart()
  U.wait(60)

  U.log("Route 8's theme is running and the pad is yours; walking works.")
  U.log("Under the lead there is a fast wave line, about two notes per beat,")
  U.log("as loud as the melody and no lower than the octave it is written in.")
  U.log("SELECT swaps in the 0.1.38 mix (quarter volume, a further octave")
  U.log("down: a dull rumble that all but vanishes), SELECT again restores it.")

  local broken = false
  local held = false
  while true do
    local down = game.input:isDown("select")
    if down and not held then
      broken = not broken
      if broken then
        ChipAudio.setChannelVolumes({ 1, 1, 0.25, 1 })
        ChipAudio.setChannelPitches({ 1, 1, 0.5, 1 })
        U.log("0.1.38 mix: wave volume 0.25, one octave down")
      else
        ChipAudio.setChannelVolumes({ 1, 1, 1, 1 })
        ChipAudio.setChannelPitches({ 1, 1, 1, 1 })
        U.log("authentic mix: wave volume 1, pitch 1")
      end
      restart()
    end
    held = down
    coroutine.yield()
  end
end
