local U = require("tests.drivers.util")
local CrystalIntro = require("src.ui.gen2.CrystalIntro")
local TitleState = require("src.ui.gen2.TitleState")

local INTERVAL = 20
local LIMIT = 4000

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/crystal-intro"
  local interval = tonumber(os.getenv("POKEPORT_SHOT_INTERVAL") or "")
    or INTERVAL

  U.wait(30)
  local assets = game.data and game.data.gen2Intro
  if not (assets and assets.acts) then
    U.log("SKIP no crystal intro acts in this cache -- re-import crystal")
    return
  end

  local finished = false
  local intro = CrystalIntro.new(game, {
    onDone = function() finished = true end,
  })
  game.stack:clear()
  game.stack:push(intro)

  local shots, scene = 0, 0
  while not finished and intro.frames < LIMIT do
    U.wait(interval)
    if intro.scene ~= scene then
      scene = intro.scene
      U.log(("scene %d at frame %d (scx=%02x scy=%02x)")
        :format(scene, intro.frames, intro.scx % 256, intro.scy % 256))
    end
    if not finished then
      U.shot(game, ("%s/intro-%04d-scene%02d.png")
        :format(out, intro.frames, intro.scene))
      shots = shots + 1
    end
  end
  assert(finished,
    "the movie never reached IntroScene28 (frame " .. intro.frames .. ")")
  U.log(("movie done: %d shots over %d frames"):format(shots, intro.frames))

  local skipped = false
  local intro2 = CrystalIntro.new(game, {
    onDone = function() skipped = true end,
  })
  game.stack:clear()
  game.stack:push(intro2)
  U.wait(45)
  U.tap(game, "b")
  U.wait(3)
  assert(skipped and intro2.skipped, "a button did not skip the intro")
  U.log("skip via B verified at frame " .. intro2.frames)

  game:showTitle()
  U.wait(1)
  local title = game.stack:top()
  assert(getmetatable(title) == TitleState,
    "showTitle left " .. tostring(title) .. " on the stack")
  assert(#title.suicuneColor == 4,
    "title.lua has no 4-frame Suicune set -- stale cache?")
  assert(title.entrance, "title.lua has no entrance block -- stale cache?")
  assert(title.suicuneX == 48 and title.suicuneY == 96,
    ("Suicune is at (%s, %s), expected (48, 96)")
      :format(tostring(title.suicuneX), tostring(title.suicuneY)))

  for i = 1, 4 do
    U.shot(game, ("%s/title-entrance-%d.png"):format(out, i))
    U.wait(4)
  end
  for _ = 1, 90 do
    if title.entranceScx == 0 then break end
    U.wait(1)
  end
  assert(title.entranceScx == 0, "the entrance never landed")
  assert(title.gemY == title.gemRestY,
    ("gem y %s did not land at %s with the entrance")
      :format(tostring(title.gemY), tostring(title.gemRestY)))
  U.wait(2)
  for i = 1, 5 do
    U.shot(game, ("%s/title-suicune-%d.png"):format(out, i))
    U.wait(6)
  end

  if love.window and love.window.setMode then
    for _, shape in ipairs({ { 1280, 720 }, { 1920, 500 }, { 480, 800 } }) do
      love.window.setMode(shape[1], shape[2], { resizable = true })
      U.wait(3)
      U.shot(game, ("%s/title-wide-%dx%d.png"):format(out, shape[1], shape[2]))
    end
    love.window.setMode(1280, 720, { resizable = true })
  end

  local intro3 = CrystalIntro.new(game, {})
  game.stack:clear()
  game.stack:push(intro3)
  local function runTo(target, extra)
    for _ = 1, LIMIT do
      if intro3.scene >= target then break end
      U.wait(5)
    end
    assert(intro3.scene >= target,
      "widescreen pass never reached scene " .. target)
    U.wait(extra)
  end
  runTo(4, 40)
  U.shot(game, out .. "/intro-wide-scene04.png")
  runTo(10, 60)
  U.shot(game, out .. "/intro-wide-scene10.png")
  runTo(18, 20)
  U.shot(game, out .. "/intro-wide-scene18.png")
  intro3:skip()

  U.log(("PASS crystal intro + title shots in %s"):format(out))
end
