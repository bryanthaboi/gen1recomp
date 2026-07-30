-- Ear check on Music_YellowIntro across the cut to the title (#436): finish()
-- used to stop the song there, on both the scene-done exit and the A/B/START
-- skip.  pokeyellow engine/movie/intro_yellow.asm PlayIntroScene
-- .go_to_title_screen (both exits land there) touches no audio at all; the
-- song only dies at engine/movie/title.asm:149 StopAllMusic, one instruction
-- before MUSIC_TITLE_SCREEN, which TitleState:startMusic stands in for.
--   POKEPORT_VERSION=yellow POKEPORT_DRIVER=tests/drivers/yellow_intro_music_bug436_test.lua POKEPORT_TOUCH=0 love .
--   SKIP=1 on the same command taps START 300 frames into the movie.  Add
--   POKEPORT_IDENTITY only if that identity already carries a Yellow import;
--   an identity with no cache lands in the launcher and nothing runs.
-- Do not set POKEPORT_SPEED: it scales the logic clock only, so the movie and
-- the audio clock drift apart and the comparison means nothing.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Music = require("src.core.Music")
  local GameVersion = require("src.core.GameVersion")
  local SHOT_DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local SKIP = os.getenv("SKIP") == "1"

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- every music call in order, so "the song was cut" and "the song was never
  -- started" read differently in the log; nothing under src/ changes
  local events = {}
  local realPlay, realStop = Music.play, Music.stop
  Music.play = function(data, song, loop, ctx)
    events[#events + 1] = { kind = "play", song = song, frame = U.frame() }
    U.log(("frame %d play %s"):format(U.frame(), tostring(song)))
    return realPlay(data, song, loop, ctx)
  end
  Music.stop = function(...)
    events[#events + 1] = { kind = "stop", frame = U.frame() }
    U.log(("frame %d stop"):format(U.frame()))
    return realStop(...)
  end

  local function firstPlay(song)
    for i, e in ipairs(events) do
      if e.kind == "play" and e.song == song then return i, e end
    end
    return nil
  end

  local function stopBetween(a, b)
    for i = a, b do
      if events[i] and events[i].kind == "stop" then return events[i] end
    end
    return nil
  end

  local function waitFor(fn, limit)
    for _ = 1, limit do
      if fn() then return true end
      U.wait(1)
    end
    return false
  end

  check("this build booted as Yellow", GameVersion.isYellow())
  if not GameVersion.isYellow() then
    U.log("Only Yellow plays this movie; rerun with POKEPORT_VERSION=yellow.")
    while true do coroutine.yield() end
  end

  local opts = game.save.options
  if (opts and opts.musicVol or 0) == 0 then
    U.log("MUSIC VOLUME IS 0. There is nothing to hear. Raise it in OPTION,")
    U.log("quit and rerun; the log half below still holds.")
  end
  if (opts and opts.sfxVol or 0) == 0 then
    U.log("WARNING sfx volume is 0: the logo crash and the whoosh over the")
    U.log("song will be silent, and Pikachu's cry with them.")
  end

  local songs = game.data.audio and game.data.audio.songs
  local INTRO = songs and songs.Music_YellowIntro and "Music_YellowIntro"
             or "Music_IntroBattle"
  check("the movie's song is in the audio table", songs ~= nil
        and songs[INTRO] ~= nil)

  -- the copyright card and the GAME FREAK splash run before the scenes
  -- (IntroMovie phases 1-2), so wait on the song rather than a frame count
  local started = waitFor(function() return firstPlay(INTRO) ~= nil end, 900)
  check("the movie started " .. INTRO, started)
  if not started then
    U.log("The movie never reached its own music; nothing below can run.")
    while true do coroutine.yield() end
  end
  local introIdx = firstPlay(INTRO)

  if SKIP then
    -- PlayIntroScene:16-19, hJoyPressed & (PAD_A | PAD_B | PAD_START)
    U.wait(300)
    U.log("tapping START mid-movie (the skip exit)")
    U.tap(game, "start")
  end

  local function titleState()
    local top = game.stack:top()
    if top and top.screenId == "TitleState" then return top end
    return nil
  end

  -- the scene timers add up to about 1040 frames; the skip path lands sooner
  local reached = waitFor(function() return titleState() ~= nil end, 1500)
  check("the movie handed off to the title screen", reached)
  if not reached then
    U.log("The title never came up; nothing below can run.")
    while true do coroutine.yield() end
  end
  local title = titleState()
  local cut = U.frame()
  U.log(("cut to the title at frame %d, %d frames after the song started")
    :format(cut, cut - events[introIdx].frame))

  -- the bug: a stop right here, at the cut
  local cutStop = stopBetween(introIdx + 1, #events)
  check("no music was stopped at the cut", cutStop == nil)
  if cutStop then
    U.log(("a stop landed on frame %d; before #436 that is finish() killing")
      :format(cutStop.frame))
    U.log("the song, and the title screen comes up silent until the cry.")
  end
  check("the title runs the Yellow logo-drop sequence, not the plain title",
        title.yellowLayout == true and title.phase == "drop")

  U.shot(game, SHOT_DIR .. "/bug436_logo_drop.png")
  U.log("captured", SHOT_DIR .. "/bug436_logo_drop.png")

  -- drop 32 frames, settle 36, bubble 3, then the cry (title.asm's
  -- WaitForSoundToFinish) before MUSIC_TITLE_SCREEN
  local seen = title.phase
  for _ = 1, 600 do
    if title.phase ~= seen then
      seen = title.phase
      U.log(("frame %d title phase %s"):format(U.frame(), seen))
      if seen == "loop" then break end
    end
    U.wait(1)
  end
  check("the title sequence reached its interactive loop", title.phase == "loop")

  -- read the song off the log rather than naming it: field.boot lets a mod
  -- own the title theme (TitleState:startMusic, self.title.music)
  local titleIdx, titlePlay
  for i = introIdx + 1, #events do
    if events[i].kind == "play" then titleIdx, titlePlay = i, events[i] break end
  end
  check("the title theme started", titlePlay ~= nil)
  if titlePlay then
    check("it started after the cut, not at it", titlePlay.frame > cut + 32)
    U.log(("%s started %d frames after the cut"):format(
      tostring(titlePlay.song), titlePlay.frame - cut))
    check("nothing stopped the music between the two songs",
          stopBetween(introIdx + 1, titleIdx - 1) == nil)
  end

  U.log("The title is up and the pad is yours. The one thing to hear: the")
  U.log("intro song runs unbroken through the cut and on over the logo drop,")
  U.log("with the crash and the whoosh layered on top, until the title theme")
  U.log("takes over after Pikachu's cry. A break at the cut is the bug.")
  U.log("Rerun with SKIP=1 for the START skip; it must sound the same.")

  while true do
    coroutine.yield()
  end
end
