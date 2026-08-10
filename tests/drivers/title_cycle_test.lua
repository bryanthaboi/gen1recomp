-- ..(engine/movie/title.asm ln 28)
-- ..(engine/movie/title2.asm ln 13)
--   POKEPORT_DRIVER=tests/drivers/title_cycle_test.lua POKEPORT_TOUCH=0 SHOT_DIR=/tmp/shots love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local shot = 0
  local function grab(tag)
    shot = shot + 1
    U.shot(game, ("%s/title_%02d_%s.png"):format(DIR, shot, tag))
  end

  U.wait(30)
  grab("copyright")
  -- ..(engine/movie/splash.asm ln 230)
  local movie = game.stack:top()
  while movie.phase ~= 2 or movie.timer < 70 do U.wait(1) end
  grab("star_topbar")
  while movie.timer < 88 do U.wait(1) end
  grab("star_middle")
  while movie.timer < 100 do U.wait(1) end
  grab("star_lowbar")
  while movie.timer < 130 do U.wait(1) end
  grab("gamefreak")

  U.tap(game, "start")
  U.wait(2)
  local title = game.stack:top()
  U.log("top is", tostring(title and title.screenId))
  if not (title and title.scrollPhase) then
    U.log("no TitleState on top; nothing below can run")
    while true do coroutine.yield() end
  end

  grab("drop_early")
  U.wait(14)
  grab("drop_late")
  while title.phase == "drop" do U.wait(1) end
  grab("settle")
  while title.phase == "settle" do U.wait(1) end
  grab("ribbon_start")
  U.wait(10)
  U.shot(game, DIR .. "/title_ribbon_mid.png")
  while title.phase ~= "loop" do U.wait(1) end
  grab("landed")

  title.cycleIndex = 1
  title.scrollPhase, title.scrollFrame, title.timer = "hold", 1, 0
  title.monOffset = 0
  while title.scrollPhase == "hold" do U.wait(1) end
  grab("out_a")
  U.wait(6)
  grab("out_b")
  while title.scrollPhase == "out" do U.wait(1) end
  U.log("after the scroll out the phase is", title.scrollPhase)
  for _ = 1, 5 do
    grab("ball")
    U.wait(1)
  end
  while title.scrollPhase == "ball" do U.wait(1) end
  grab("in")
  U.wait(30)
  grab("next_mon")
  U.log("captured", DIR)
  while true do coroutine.yield() end
end
