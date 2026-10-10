-- engine/movie/hall_of_fame.asm:1
-- scripts/HallOfFame.asm:24
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local Music = require("src.core.Music")
  local HallOfFame = require("src.ui.HallOfFame")
  os.execute('mkdir -p "' .. DIR .. '" 2>/dev/null')

  local failed = false
  local function check(label, ok)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then failed = true end
    return ok
  end

  U.newGame(game)
  game.save.party = { Pokemon.new(game.data, "NIDOKING", 63) }
  game.save.player.name = "RED"
  game.save.pendingHallOfFame = true
  U.teleport(game, "HALL_OF_FAME", 4, 7, "up")

  local hof
  for _ = 1, 3000 do
    local top = game.stack:top()
    if getmetatable(top) == HallOfFame then hof = top break end
    U.tap(game, "a")
    U.wait(3)
  end
  check("the induction started", hof ~= nil)
  if not hof then love.event.quit(1) return end

  check("it opens on the fade, not the back pic sweep", hof.phase == "intro")
  check("the room is still drawn under the fade", hof.isOpaque == false)

  local opaqueAt, lastIntro
  local midFadeShot, pauseShot, heardHof = false, false, false
  for _ = 1, 400 do
    if hof.phase ~= "intro" then break end
    lastIntro = hof.introT
    if Music.current() == "Music_HallOfFame" then heardHof = true end
    if hof.isOpaque then
      opaqueAt = opaqueAt or hof.introT
      if not pauseShot and hof.introT >= 80 then
        pauseShot = U.still(game, DIR .. "/2836_02_white_pause.png")
      end
    elseif not midFadeShot and hof.introT >= 3 + 12 then
      midFadeShot = U.still(game, DIR .. "/2836_01_fade_to_white.png")
    end
    U.wait(1)
  end
  local pause = (lastIntro or 0) + 1 - ((opaqueAt or 0) - 1)
  check("GBFadeOutToWhite runs after Delay3 (opaque white from intro frame "
        .. tostring(opaqueAt) .. ")", opaqueAt == 3 + 24 + 1)
  check("100 frame white pause before a mon comes in (got " .. pause .. ")",
        pause == 100)
  check("Music_HallOfFame waits for the pause", not heardHof)
  check("mid-fade screenshot", midFadeShot)
  check("white pause screenshot", pauseShot)
  check("the back pic sweep follows, entering from the right",
        hof.phase == "back" and (hof.scrollX or 0) >= 150)
  check("Music_HallOfFame starts with the sweep",
        Music.current() == "Music_HallOfFame")
  for _ = 1, 60 do
    if hof.phase ~= "back" or (hof.scrollX or 0) <= 120 then break end
    U.wait(1)
  end
  check("back pic entering screenshot",
        U.still(game, DIR .. "/2836_03_back_pic_enters.png"))

  love.event.quit(failed and 1 or 0)
end
