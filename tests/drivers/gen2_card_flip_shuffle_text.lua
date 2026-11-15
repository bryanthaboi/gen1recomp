local U = require("tests.drivers.util")
local CardFlip = require("src.ui.gen2.CardFlip")

-- pokegold engine/games/card_flip.asm:300-301

return function(game)
  local failed = 0
  local function check(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then failed = failed + 1 end
    return ok
  end
  local function finish()
    love.event.quit(failed == 0 and 0 or 1)
  end
  local identity = os.getenv("POKEPORT_IDENTITY") or ""
  if not check(identity ~= "" and identity ~= "pokemon-love2d", "isolated identity") then return finish() end
  local dir = os.getenv("POKEPORT_SHOT_DIR") or "."
  local version = game.save and game.save.version or "?"
  game.writeSave = function() end
  U.wait(60)
  if not check(game.world and game.world.map and game.stack, version .. " Gen 2 field booted") then
    return finish()
  end
  game.world:warpToMapId("GOLDENROD_GAME_CORNER", 5, 5, "down")
  U.wait(30)
  game.save.player.coins = 1000
  if not check(game.world:gameCornerGame("cardflip"), version .. " Card Flip opens") then return finish() end
  local flip = game.stack:top()
  if not check(getmetatable(flip) == CardFlip, version .. " Card Flip screen is active") then return finish() end
  U.wait(10)
  flip.played = CardFlip.HANDS_PER_DECK - 1
  flip:continue()
  U.wait(10)
  check(flip.phase == "message" and flip.lines and flip.lines.withoutCoinBox,
    version .. " the twelfth hand prints the shuffled text without the coin box")
  check(flip.lines and flip.lines[2] == "been shuffled.",
    version .. " second row reads " .. tostring(flip.lines and flip.lines[2]))
  check(U.still(game, dir .. "/rf1b_" .. version .. "_cards_shuffled_full_line.png"),
    version .. " shuffled screenshot written")
  U.tap(game, "a")
  U.wait(20)
  check(not (flip.lines and flip.lines.withoutCoinBox), version .. " the coin box returns after the shuffled text")
  flip:quit()
  finish()
end
