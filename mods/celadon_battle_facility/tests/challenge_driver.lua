-- Driver: the ladder gates correctly and the opponent scales to your party.
--
--   POKEPORT_DRIVER=mods/celadon_battle_facility/tests/challenge_driver.lua \
--   POKEPORT_IDENTITY=cbf_driver love .
--
-- The unit suite proves the script validates and every roster resolves.  This
-- proves the run-time behaviour: GOLD is refused before it is earned, BRONZE
-- starts, and the opponent that appears is built at the player's level rather
-- than the placeholder levels the rosters ship with.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "shots"
  local TextBox = require("src.render.TextBox")
  local ChoiceBox = require("src.ui.ChoiceBox")
  local BattleState = require("src.battle.BattleState")
  local Pokemon = require("src.pokemon.Pokemon")

  local FACILITY = "CELADON_BATTLE_FACILITY"
  local failures = 0
  local function check(cond, msg)
    U.log(cond and "ok  " or "FAIL", msg)
    if not cond then failures = failures + 1 end
  end

  if not game.data.maps[FACILITY] then
    U.log("driver aborted: the mod is not loaded")
    return
  end

  game.save.flags = game.save.flags or {}
  game.save.flags.EVENT_GOT_STARTER = true

  -- A party at a known level, so the scaling assertion has something exact
  -- to check against.  The greeter asks hardest-tier-first, so the answer
  -- list below is read in that order too.
  local PARTY_LEVEL = 40
  local function setParty(level)
    for i = #game.save.party, 1, -1 do table.remove(game.save.party, i) end
    table.insert(game.save.party, Pokemon.new(game.data, "CHARIZARD", level))
    table.insert(game.save.party, Pokemon.new(game.data, "PIDGEOT", level))
  end

  -- Talk to the greeter, answering each yes/no from `answers` in turn.
  -- Returns the BattleState if one started, plus how many prompts appeared.
  local function talk(answers)
    U.teleport(game, FACILITY, 6, 5, "up")
    U.tap(game, "a")
    -- A box stays on the stack for several frames after its tap, so count
    -- distinct box instances rather than loop iterations -- otherwise one
    -- prompt reads as six.
    local asked, lastBox = 0, nil
    for _ = 1, 400 do
      local top = game.stack:top()
      if getmetatable(top) == BattleState then return top, asked end
      if top == game.overworld then return nil, asked end
      if getmetatable(top) == ChoiceBox then
        if top ~= lastBox then
          lastBox = top
          asked = asked + 1
          -- A accepts, B declines
          U.tap(game, answers[asked] and "a" or "b")
        end
      else
        U.tap(game, "a")
      end
      U.wait(2)
    end
    return nil, asked
  end

  -- ------- GOLD is refused before it is earned

  setParty(PARTY_LEVEL)
  local battle, asked = talk({ true })
  check(asked >= 1, "the greeter offers a tier")
  check(battle == nil, "accepting GOLD before earning it starts no battle")
  U.shot(game, DIR .. "/cbf_6_gold_locked.png")

  -- ------- BRONZE runs, and the opponent is built at the party's level

  setParty(PARTY_LEVEL)
  battle, asked = talk({ false, false, true })
  check(asked == 3, ("all three tiers are offered (saw %d)"):format(asked))
  check(battle ~= nil, "declining GOLD and SILVER and accepting BRONZE battles")

  if battle then
    U.wait(20)
    U.shot(game, DIR .. "/cbf_7_bronze.png")
    check(battle.oppClass == "OPP_CBF_BRONZE", "the BRONZE class is the opponent")
    local levels = {}
    for _, mon in ipairs(battle.enemyParty or {}) do
      levels[#levels + 1] = mon.level
    end
    U.log("enemy levels:", table.concat(levels, ","), "party level:", PARTY_LEVEL)
    check(#levels > 0, "the opponent has a party")
    -- bronze adds no bonus, and round 1 is not the tier champion, so the
    -- opponent should land exactly on the player's average
    local scaled = true
    for _, lv in ipairs(levels) do
      if lv ~= PARTY_LEVEL then scaled = false end
    end
    check(scaled, ("the opponent scaled to L%d rather than the placeholder L30")
      :format(PARTY_LEVEL))
  end

  U.log(failures == 0 and "DRIVER PASS" or ("DRIVER FAIL (" .. failures .. ")"))
end
