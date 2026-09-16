-- engine/battle/effects.asm:57 -- engine/battle/move_effects/leech_seed.asm:28
--   SHOT_DIR=/tmp/shots POKEPORT_DRIVER=tests/drivers/hypnosis_miss_bug2282_test.lua love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or os.getenv("POKEPORT_SHOT_DIR")
    or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")

  local lead = Pokemon.new(game.data, "GENGAR", 29)
  lead.moves = {
    { id = "HYPNOSIS", pp = 20 },
    { id = "LEECH_SEED", pp = 10 },
    { id = "GROWL", pp = 40 },
    { id = "TACKLE", pp = 35 },
  }
  game.save.party = { lead }
  U.teleport(game, "ROUTE_1", 5, 5, "down")
  local ow = game.overworld

  local failures = 0

  -- home/text.asm:209 -- a page is finished when every glyph is typed and
  -- PromptText is blinking the arrow, so the whole string is on screen
  local function typedFully(battle, needle)
    local item = battle.current
    local text = item and item.text
    if not text or not text:find(needle, 1, true) then return false end
    return (battle.total or 0) > 0 and (battle.charIndex or 0) >= battle.total
  end

  local function fight(slot, needle, label, shot)
    local battle = BattleState.newWild(game, "PONYTA", 29)
    battle.onFinish = function() end
    battle.rng = function(a, b) return b end
    ow:pushBattle(battle)
    for _ = 1, 200 do
      if battle.phase == "menu" then break end
      U.tap(game, "a")
      U.wait(4)
    end
    U.log("battle phase:", battle.phase)
    U.tap(game, "a"); U.wait(20)
    for _ = 2, slot do U.tap(game, "down"); U.wait(6) end
    U.tap(game, "a")
    local typed = false
    for _ = 1, 900 do
      if typedFully(battle, needle) then typed = true break end
      U.wait(1)
    end
    if typed then
      U.log("full page:", (battle.current.text:gsub("\n", " / ")))
      U.shot(game, DIR .. "/" .. shot)
      U.log("PASS " .. label)
    else
      failures = failures + 1
      U.log("FAIL " .. label .. ": page never finished typing " .. needle)
      local item = battle.current
      U.log("  current:", item and item.text, battle.charIndex, battle.total)
    end
    battle.result = "run"
    for _ = 1, 200 do
      if game.stack:top() ~= battle then break end
      U.tap(game, "b"); U.wait(6)
    end
  end

  fight(1, "didn't affect", "hypnosis prints DidntAffectText",
        "bug2282_1_hypnosis_miss.png")
  fight(2, "evaded attack", "leech seed prints EvadedAttackText",
        "bug2282_2_leech_seed_miss.png")
  fight(3, "But, it failed!", "growl prints ButItFailedText",
        "bug2282_3_growl_miss.png")
  fight(4, "attack missed!", "tackle still prints AttackMissedText",
        "bug2282_4_tackle_miss.png")

  U.log(failures == 0 and "PASS bug2282_status_miss_text"
        or ("FAIL bug2282_status_miss_text: " .. failures .. " shots"))
  love.event.quit(failures == 0 and 0 or 1)
end
