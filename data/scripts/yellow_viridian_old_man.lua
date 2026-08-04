-- The Viridian City old-man catch tutorial, Yellow's way
-- (pokeyellow scripts/ViridianCity.asm, scripts/ViridianCity_2.asm,
--  scripts/OaksLab.asm).  Registered on top of the shared tables by
-- data/scripts/init.lua on a Yellow boot.
--
-- Yellow has TWO gambler objects where Red/Blue have one:
--   * VIRIDIANCITY_OLD_MAN    at (17,5) -- a Red/Blue leftover; its
--     toggle stays OFF forever in Yellow, no script ever shows it.
--   * VIRIDIANCITY_OLD_MAN2   at (18,9) -- replaces the sleeper the
--     moment the Pokédex is given (OaksLabOakGivesPokedexScript:
--     HideObject TOGGLE_LYING_OLD_MAN / ShowObject TOGGLE_OLD_MAN_2).
--
-- This is the tutorial old man.  The Red/Blue "Are you in a hurry?"
-- yes/no script must NOT run against him: Yellow's
-- _ViridianCityOldManHadMyCoffeeNowText is the apology speech ("I've had
-- my coffee now ... I'll show you how to catch POKéMON as my apology"),
-- and the shared story.lua TEXT_VIRIDIANCITY_OLD_MAN rows hang an
-- invented yes/no over it -- YES printed the TimeIsMoney alias
-- (_ViridianCityOldManLosingMyTouchText) and NO ran the demo, every
-- talk, forever (#617).
--
-- The real flow (ViridianCityCheckWaitingOldMan + ViridianCityOldMan2Text
-- + ViridianCityOldManInitialCatchTrainingScript + ...EndInitial... +
-- ViridianCityPostInitialCatchTraining): stepping into (19,9) -- the gap
-- east of the sleeper's cell -- faces the old man right and the player
-- left, prints the apology, and without any choice runs the demo battle
-- (BATTLE_TYPE_OLD_MAN, RATTATA lvl 5), which he FAILS -- the ball shakes
-- three times and breaks open.  After it, the same text pointer
-- now prints _ViridianCityOldManLosingMyTouchText ("That didn't work!
-- I must be losing my touch."), the old man walks off (down 6 with the
-- player on (19,9), right 1 otherwise, Pikachu nudged out of the way
-- first) and TOGGLE_OLD_MAN_2 hides.  A direct talk does the same.

local M = {}

local OLD_MAN2 = "VIRIDIANCITY_OLD_MAN2"

-- Capture the FUNCTION, not the table: attachBase stores the module
-- table itself, so once this file's onStep is attached the table's slot
-- points back here -- delegating through the table would self-recurse.
-- story5's VIRIDIAN_CITY.onStep chains story.lua's sleeping-old-man
-- gate and its own gym-lock step (same pattern as yellow_jessie_james).
local baseViridianStep = require("data.scripts.story5").VIRIDIAN_CITY.onStep

-- pokeyellow text/ViridianCity.asm, _ViridianCityOldManHadMyCoffeeNowText
-- and _ViridianCityOldManLosingMyTouchText, spelled with the extractor's
-- markers (line -> \n, cont -> \v, para -> \f)
local function text(game)
  return {
    apology = game.data.text._ViridianCityOldManHadMyCoffeeNowText
      or "Ahh, I've had my\ncoffee now and I\vfeel great!\fSure, you can go\n"
      .. "through!\fI'm sorry I was\nso rude to you!\fI see you're using\n"
      .. "a POKéDEX.\fI'll show you how\nto catch POKéMON\vas my apology.",
    losingMyTouch = game.data.text._ViridianCityOldManLosingMyTouchText
      or "That didn't work!\nI must be losing\vmy touch.\fI've run out of\n"
      .. "POKé BALLs too.\fI have to get some\nat POKéMON MART.",
  }
end

-- The row list for the initial-tutorial branch, keyed by where the
-- player stands when the battle ends (ViridianCityPostInitialCatchTraining
-- reads wXCoord: (19,9) walks the old man down the corridor, anywhere
-- else walks him right 1 after moving the follower Pikachu aside).
local function oldMan2Rows(game, ow, npc)
  local rows = {
    { "show_text", "_ViridianCityOldManHadMyCoffeeNowText" },
    -- ViridianCityOldManInitialCatchTrainingScript sets
    -- EVENT_INITIAL_CATCH_TRAINING before the battle runs, and
    -- ItemUseBall's .oldManBattle branch turns that event into anim data
    -- $63: three shakes, then the ball breaks open.  The losing-my-touch
    -- line below only follows a throw that failed (#636).
    { "old_man_demo", "fail" },
    { "set_flag", "EVENT_COMPLETED_CATCH_TRAINING" },
    { "show_text", "_ViridianCityOldManLosingMyTouchText" },
  }
  if ow.player and ow.player.cellX == 19 then
    rows[#rows + 1] =
      { "walk_npc", npc.def.index,
        { "down", "down", "down", "down", "down", "down" } }
  else
    -- ViridianCityMovePikachu (scripts/ViridianCity_2.asm): Pikachu
    -- steps out of the old man's way before he turns right
    local PikachuFollower = require("src.world.PikachuFollower")
    local pika = ow and PikachuFollower.current(ow)
    if pika then
      rows[#rows + 1] = { "walk_npc", pika.def.index, { "right" } }
    end
    rows[#rows + 1] = { "walk_npc", npc.def.index, { "right" } }
  end
  rows[#rows + 1] =
    { "hide_object", "VIRIDIAN_CITY", OLD_MAN2 }
  return rows
end

-- The shared talk handler: TEXT_VIRIDIANCITY_OLD_MAN2's text_asm branch
-- (ViridianCityOldMan2Text) on EVENT_COMPLETED_CATCH_TRAINING.
local function oldMan2Talk(game, ow, npc, done)
  if game.save.flags and game.save.flags.EVENT_COMPLETED_CATCH_TRAINING then
    local TextBox = require("src.render.TextBox")
    game.stack:push(TextBox.new(game, text(game).losingMyTouch, done))
    return
  end
  ow.runner:run(oldMan2Rows(game, ow, npc), { npc = npc, onDone = done })
end

M.VIRIDIAN_CITY = {
  talk = {
    TEXT_VIRIDIANCITY_OLD_MAN2 = oldMan2Talk,
  },

  -- Re-apply the Pokédex swap for a save that already holds the flag but
  -- was never standing here when it fired (converted .sav imports, same
  -- shape as story.lua's VIRIDIAN_CITY.onEnter).  Yellow shows OLD_MAN2,
  -- not the Red/Blue OLD_MAN at (17,5), and also puts away a stray
  -- OLD_MAN a save made by the pre-#617 build left standing.
  onEnter = function(game, ow)
    if not (game.save.flags and game.save.flags.EVENT_GOT_POKEDEX) then
      return
    end
    local Commands = require("src.script.Commands")
    local ctx = { save = game.save, game = game, overworld = ow }
    Commands.hide_object(ctx, "VIRIDIAN_CITY", "VIRIDIANCITY_OLD_MAN_SLEEPY")
    Commands.hide_object(ctx, "VIRIDIAN_CITY", "VIRIDIANCITY_OLD_MAN")
    Commands.show_object(ctx, "VIRIDIAN_CITY", OLD_MAN2)
  end,

  -- ViridianCityCheckWaitingOldMan: with the Pokédex held and the
  -- tutorial undone, (19,9) -- the gap east of the old man, the same
  -- cell the sleeper used to gate -- faces him right, turns the player
  -- left and starts the OLD_MAN2 flow with no choice.
  onStep = function(game, ow, x, y)
    if baseViridianStep and baseViridianStep(game, ow, x, y) then
      return true
    end
    local flags = game.save.flags
    if not flags.EVENT_GOT_POKEDEX then return false end
    if flags.EVENT_COMPLETED_CATCH_TRAINING then return false end
    if x ~= 19 or y ~= 9 then return false end
    local man
    for _, npc in ipairs(ow.npcs) do
      if npc.def and npc.def.name == OLD_MAN2 then man = npc break end
    end
    if not man then return false end
    man.facing = "right"
    ow.player.facing = "left"
    oldMan2Talk(game, ow, man, nil)
    return true
  end,
}

return M
