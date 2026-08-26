-- The Crystal GAME FREAK splash (pokecrystal engine/movie/splash.asm), shot
-- finely enough to catch both Ditto bounces, plus both IntroSequence exits
-- (pokecrystal engine/menus/intro_menu.asm:964-967): watched -> CrystalIntro,
-- skipped -> the title.
local U = require("tests.drivers.util")
local CrystalIntro = require("src.ui.gen2.CrystalIntro")
local CrystalSplash = require("src.ui.gen2.CrystalSplash")
local TitleState = require("src.ui.gen2.TitleState")

local LIMIT = 900

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/crystal-splash"
  local interval = tonumber(os.getenv("POKEPORT_SHOT_INTERVAL") or "") or 2

  U.wait(10)
  local finished, skipped
  local splash = CrystalSplash.new(game, {
    oakSpeech = game.oakSpeechData or {},
    onDone = function(s)
      finished, skipped = true, s
    end,
  })
  game.stack:clear()
  game.stack:push(splash)

  local st = splash.anims.structs[1]
  assert(st and st.index ~= 0, "no Ditto sprite anim struct was spawned")
  local minY, sawMorph, scene = 256, false, -1
  while not finished and splash.frames < LIMIT do
    U.wait(interval)
    local offset = st.yOffset
    if offset >= 128 then offset = offset - 256 end
    if st.jt == 1 and offset < minY then minY = offset end
    if st.jt >= 3 then sawMorph = true end
    if splash.scene ~= scene then
      scene = splash.scene
      U.log(("scene %d at frame %d (jt=%d var1=%d)")
        :format(scene, splash.frames, st.jt, st.var1))
    end
    if not finished then
      U.shot(game, ("%s/splash-%04d-scene%d.png")
        :format(out, splash.frames, splash.scene))
    end
  end
  assert(finished, "the splash never finished (frame "
    .. splash.frames .. ", scene " .. splash.scene .. ")")
  assert(not skipped, "an unskipped splash reported skipped")
  assert(minY <= -90, "Ditto never reached the top of its 96px bounce (min "
    .. minY .. ")")
  assert(sawMorph, "the transform scene never ran")
  U.log(("splash done at frame %d, min bounce offset %d")
    :format(splash.frames, minY))

  -- Watched through: Game2 routes to the intro movie.
  game:showGameFreak()
  U.wait(5)
  assert(getmetatable(game.stack:top()) == CrystalSplash,
    "showGameFreak did not open the Crystal splash")
  for _ = 1, LIMIT do
    if getmetatable(game.stack:top()) == CrystalIntro then break end
    U.wait(5)
  end
  assert(getmetatable(game.stack:top()) == CrystalIntro,
    "a watched splash did not hand off to CrystalIntro (top "
      .. tostring(game.stack:top()) .. ")")
  U.log("watched splash handed off to the intro movie")

  -- Skipped: straight to the title, no intro movie.
  game:showGameFreak()
  U.wait(40)
  U.shot(game, out .. "/skip-before.png")
  U.tap(game, "b")
  for _ = 1, 60 do
    if getmetatable(game.stack:top()) == TitleState then break end
    assert(getmetatable(game.stack:top()) ~= CrystalIntro,
      "a skipped splash still played the intro movie")
    U.wait(1)
  end
  assert(getmetatable(game.stack:top()) == TitleState,
    "a skipped splash did not land on the title (top "
      .. tostring(game.stack:top()) .. ")")
  U.wait(30)
  U.shot(game, out .. "/skip-title.png")
  U.log("PASS crystal splash shots in " .. out)
end
