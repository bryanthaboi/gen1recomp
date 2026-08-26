-- A button during the GS splash skips the intro movie
-- (pokegold engine/menus/intro_menu.asm:848-851 IntroSequence).
local U = require("tests.drivers.util")
local GameFreakPresents = require("src.ui.gen2.GameFreakPresents")
local GoldSilverIntro = require("src.ui.gen2.GoldSilverIntro")
local TitleState = require("src.ui.gen2.TitleState")

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gold-splash"

  U.wait(10)
  game:showGameFreak()
  U.wait(5)
  assert(getmetatable(game.stack:top()) == GameFreakPresents,
    "showGameFreak did not open the GS splash (top "
      .. tostring(game.stack:top()) .. ")")
  U.wait(40)
  U.shot(game, out .. "/splash.png")
  U.tap(game, "b")
  for _ = 1, 60 do
    if getmetatable(game.stack:top()) == TitleState then break end
    assert(getmetatable(game.stack:top()) ~= GoldSilverIntro,
      "a skipped splash still played the intro movie")
    U.wait(1)
  end
  assert(getmetatable(game.stack:top()) == TitleState,
    "a skipped splash did not land on the title (top "
      .. tostring(game.stack:top()) .. ")")
  U.wait(30)
  U.shot(game, out .. "/title.png")

  -- Watched through, the splash still hands off to the movie.
  game:showGameFreak()
  for _ = 1, 900 do
    if getmetatable(game.stack:top()) == GoldSilverIntro then break end
    U.wait(5)
  end
  assert(getmetatable(game.stack:top()) == GoldSilverIntro,
    "a watched splash did not hand off to the intro movie (top "
      .. tostring(game.stack:top()) .. ")")
  U.log("PASS gold splash skip in " .. out)
end
