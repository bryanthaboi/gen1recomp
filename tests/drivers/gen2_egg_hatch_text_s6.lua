-- engine/pokemon/breeding.asm:355
local U = require("tests.drivers.util")
local CommonText = require("src.core.gen2.CommonText")

return function(game)
  local failed = 0
  local function check(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then failed = failed + 1 end
    return ok
  end
  local dir = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gen2-egg-hatch-text"

  U.wait(60)
  local w = game.world
  if not check(w and w.map and game.save and game.stack, "gen2 field booted") then
    return love.event.quit(1)
  end
  w:warpToMapId("NEW_BARK_TOWN", 6, 8, "down")
  U.wait(40)

  local Mon = require("src.battle.gen2.Mon")
  local lead = Mon.new(game.data, "CYNDAQUIL", 5)
  local egg = Mon.new(game.data, "TOGEPI", 5)
  egg.isEgg = true
  egg.nickname = "EGG"
  egg.eggSteps = 0
  game.save.party = { lead, egg }

  local bodies = {}
  local showText = w.showText
  w.showText = function(self, body, ...)
    bodies[#bodies + 1] = body
    return showText(self, body, ...)
  end
  local asked
  local askYesNo = w.askYesNo
  w.askYesNo = function(self, ...)
    asked = self.lastText
    return askYesNo(self, ...)
  end

  local function waitFor(pred, limit)
    for _ = 1, limit or 3000 do
      if pred() then return true end
      U.wait(1)
    end
    return false
  end

  w:hatchEggs()
  check(waitFor(function() return #bodies >= 1 end), "the hatch prints its first box")
  U.wait(90)
  check(U.still(game, dir .. "/s6_01_egg_huh.png"), "Huh? shot written")
  U.tap(game, "a")
  check(waitFor(function() return #bodies >= 2 end, 6000), "the hatch line follows the animation")
  U.wait(120)
  check(U.still(game, dir .. "/s6_02_egg_came_out.png"), "came out shot written")
  U.tap(game, "a")
  check(waitFor(function() return asked ~= nil end), "the nickname question opens")
  U.wait(30)
  check(U.still(game, dir .. "/s6_03_egg_ask_nickname.png"), "nickname shot written")
  U.tap(game, "b")
  U.wait(30)

  local text = w.text
  local hatched = game.save.party[2]
  local name = hatched and (hatched.nickname or hatched.name or hatched.species) or "?"
  local function fill(label)
    return (CommonText.get(text, label):gsub("{STRBUF}", function() return name end))
  end
  check(bodies[1] == CommonText.get(text, "Text_BreedHuh"),
    "the first box is Text_BreedHuh from text.lua")
  check(bodies[2] == fill("_BreedEggHatchText"),
    "the second is _BreedEggHatchText with the hatchling's name: " .. tostring(bodies[2]))
  check(asked == fill("_BreedAskNicknameText"),
    "the question is _BreedAskNicknameText: " .. tostring(asked))
  check(hatched and not hatched.isEgg and hatched.species == "TOGEPI", "the egg hatched")

  print(failed == 0 and "PASS gen2_egg_hatch_text_s6"
    or ("FAIL gen2_egg_hatch_text_s6 (%d)"):format(failed))
  love.event.quit(failed == 0 and 0 or 1)
end
