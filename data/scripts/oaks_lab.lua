-- Hand-ported from pret/pokered scripts/OaksLab.asm.  All text is real
-- extracted text.
--
-- * Starter poke balls (objects 2-4): ask, give the real species, flag,
--   then the rival's counter-pick: he steps to the countering ball,
--   takes it ("I'll take this one, then!") and both balls disappear.
--   Source: scripts/OaksLab.asm OaksLabCharmanderPokeBallText /
--   OaksLabRivalTakePokeBallScript.
-- * Leftover ball (after the pick): Oak turns and reads the last-mon
--   line instead of re-offering the starter (OaksLabLastMonScript, #601).
-- * Rival (object 1): before starter -> "go ahead and choose" once Oak
--   has walked you in, else "gramps isn't around" (#218); with
--   starter -> taunt + battle OPP_RIVAL1 with the counter-pick party
--   (player Bulbasaur -> rival Charmander etc., parties 1/2/3 =
--   Squirtle/Bulbasaur/Charmander in data/trainers/parties.asm);
--   afterwards HealParty + flag always, then he gloats or sulks and
--   marches out (OaksLabRivalEndBattleScript).  A loss does not black out.

-- ball objects: CHARMANDER (6,3), SQUIRTLE (7,3), BULBASAUR (8,3);
-- rival = object 1 at (4,3).  rivalBallX is the counter-pick's column.
local function starterBall(askText, species, choseFlag, ownBall,
                           rivalBallX, rivalBall)
  return {
    { "check_flag", "EVENT_GOT_STARTER" },        -- 1
    { "jump_if_true", 22 },                       -- 2
    -- no picking until Oak has walked you in (OaksLabScript gating)
    { "check_flag", "EVENT_FOLLOWED_OAK_INTO_LAB" }, -- 3
    { "jump_if_false", 25 },                      -- 4
    -- the Pokédex "new species" entry shows before the ask (predef
    -- StarterDex ahead of OaksLabYouWant...Text).  StarterDex temporarily
    -- sets the owned bits so ShowPokedexData prints height/weight/text;
    -- forceOwned is that bypass without mutating save.pokedex.owned.
    { "push_screen", "DexEntryMenu",
      { species = species, forceOwned = true } }, -- 5
    { "ask", askText },                           -- 6
    { "jump_if_false", "end" },                   -- 7
    -- OaksLab.asm prints ReceivedMon then AddPartyMon (AskName lives
    -- inside give_pokemon).  Show the received text first so the
    -- nickname prompt follows "you got X", matching Gen1.
    -- The received text carries sound_get_key_item (OaksLab.asm
    -- OaksLabReceivedMonText); the jingle plays as the box opens
    -- (same beat as the Yellow port's starter, #668).
    { "play_sound", "Get_Key_Item" },                              -- 8
    { "show_text", "_OaksLabReceivedMonText", { RAM = species } }, -- 9
    { "give_pokemon", species, 5 },               -- 10
    { "set_flag", "EVENT_GOT_STARTER" },          -- 11
    { "set_flag", choseFlag },                    -- 12
    -- POKé BALLs are not handed out here in the original -- Oak gives
    -- them later, at OaksLabOak1Text's .give_poke_balls beat once the
    -- player has beaten the Route 22 rival (see TEXT_OAKSLAB_OAK1 below)
    { "hide_object", "OAKS_LAB", ownBall },       -- 13
    -- the rival walks to the countering ball (around the furniture)
    { "move_npc_to", 1, rivalBallX, 4 },          -- 14
    { "face_object", 1, "up" },                   -- 15
    { "show_text", "_OaksLabRivalIllTakeThisOneText" },            -- 16
    { "hide_object", "OAKS_LAB", rivalBall },     -- 17
    { "play_sound", "Get_Key_Item" },             -- 18 (sound_get_key_item)
    { "show_text", "_OaksLabRivalReceivedMonText",
      { RAM = rivalBall == "OAKSLAB_CHARMANDER_POKE_BALL" and "CHARMANDER"
              or rivalBall == "OAKSLAB_SQUIRTLE_POKE_BALL" and "SQUIRTLE"
              or "BULBASAUR" } },                 -- 19
    { "jump", "end" },                            -- 20
    { "jump", "end" },                            -- 21 (spacer)
    -- a leftover ball after the player's pick: Oak turns to face the
    -- player and reads the last-mon line instead of re-offering the
    -- starter (scripts/OaksLab.asm OaksLabSelectedPokeBallScript ->
    -- OaksLabLastMonScript; #601).  The ROM's "#MON" ligature is spelled
    -- out as Pokémon here.
    { "face_object", 5, "down" },                 -- 22
    { "show_text", "_OaksLabLastMonText" },       -- 23
    -- OaksLabLastMonScript ends at TextScriptEnd; the port used to fall
    -- through into the pre-pick line below (#601 remnant, reported on #600)
    { "jump", "end" },                            -- 24
    { "show_text", "_OaksLabThoseArePokeBallsText" }, -- 25
  }
end

return {
  talk = {
    -- Oak: OaksLabOak1Text.  Parcel delivery kicks SCRIPT_OAKSLAB_RIVAL_
    -- ARRIVES_AT_OAKS_REQUEST + OaksLabOakGivesPokedexScript (rival walk-
    -- in, full Pokédex speech, rival exit, Route 22 arm).
    TEXT_OAKSLAB_OAK1 = {
      { "face_player" },
      -- OaksLabOak1Text leads with the dex-rating branch (#600): with
      -- EVENT_PALLET_AFTER_GETTING_POKEBALLS set (converted saves), or
      -- 2+ species owned once the Pokédex is in hand, Oak asks how it is
      -- coming and rates it (predef DisplayDexRating).  Red keeps the
      -- GOT_POKEDEX gate that Yellow's copy of this text drops
      -- (data/scripts/oaks_lab_yellow.lua).
      { "check_flag", "EVENT_PALLET_AFTER_GETTING_POKEBALLS" },
      { "jump_if_true", "dex_rating" },
      { "check_dex_owned", 2 },
      { "jump_if_false", "no_rating" },
      { "check_flag", "EVENT_GOT_POKEDEX" },
      { "jump_if_true", "dex_rating" },
      { "label", "no_rating" },
      { "check_item", "POKE_BALL" },
      { "jump_if_true", "come_see" },
      { "check_flag", "EVENT_BEAT_ROUTE22_RIVAL_1ST_BATTLE" },
      { "jump_if_true", "give_balls" },
      { "check_flag", "EVENT_GOT_POKEDEX" },
      { "jump_if_true", "around_world" },
      { "check_flag", "EVENT_BATTLED_RIVAL_IN_OAKS_LAB" },
      { "jump_if_false", "pre_lab_battle" },
      { "check_item", "OAKS_PARCEL" },
      { "jump_if_false", "raise_young" },
      -- OaksLabOak1Text.got_parcel → RivalArrives + OakGivesPokedex
      { "show_text", "_OaksLabOak1DeliverParcelText" },
      { "play_sound", "Get_Key_Item" },
      { "show_text", "_OaksLabOak1ParcelThanksText" },
      { "take_item", "OAKS_PARCEL", 1 },
      { "stop_music" },
      { "play_music", "Music_MeetRival" },
      { "show_text", "_OaksLabRivalGrampsText" },
      { "show_object", "OAKS_LAB", "OAKSLAB_RIVAL" },
      -- OaksLabCalcRivalMovementScript: sprite map (8,11) → cell (4,7)
      -- when the player stands below Oak (the usual desk talk).
      { "place_npc", 1, 4, 7, "up" },
      { "move_npc_to", 1, 4, 3 },
      { "play_music", "Music_OaksLab" },
      { "face_object", 1, "up" },
      { "face_object", 5, "down" },
      { "show_text", "_OaksLabRivalWhatDidYouCallMeForText" },
      { "face_object", 1, "up" },
      { "face_object", 5, "down" },
      { "show_text", "_OaksLabOakIHaveARequestText" },
      { "face_object", 1, "up" },
      { "face_object", 5, "down" },
      { "show_text", "_OaksLabOakMyInventionPokedexText" },
      { "show_text", "_OaksLabOakGotPokedexText" },
      { "play_sound", "Get_Key_Item" },
      { "hide_object", "OAKS_LAB", "OAKSLAB_POKEDEX1" },
      { "hide_object", "OAKS_LAB", "OAKSLAB_POKEDEX2" },
      { "face_object", 1, "up" },
      { "face_object", 5, "down" },
      { "show_text", "_OaksLabOakThatWasMyDreamText" },
      { "face_object", 1, "right" },
      { "show_text", "_OaksLabRivalLeaveItAllToMeText" },
      { "set_flag", "EVENT_GOT_POKEDEX" },
      { "set_flag", "EVENT_OAK_GOT_PARCEL" },
      { "hide_object", "VIRIDIAN_CITY", "VIRIDIANCITY_OLD_MAN_SLEEPY" },
      { "show_object", "VIRIDIAN_CITY", "VIRIDIANCITY_OLD_MAN" },
      { "stop_music" },
      { "play_music", "Music_MeetRival" },
      { "move_npc_to", 1, 4, 7 },
      { "hide_object", "OAKS_LAB", "OAKSLAB_RIVAL" },
      { "play_music", "Music_OaksLab" },
      { "set_flag", "EVENT_1ST_ROUTE22_RIVAL_BATTLE" },
      { "clear_flag", "EVENT_2ND_ROUTE22_RIVAL_BATTLE" },
      { "set_flag", "EVENT_ROUTE22_RIVAL_WANTS_BATTLE" },
      { "show_object", "ROUTE_22", "ROUTE22_RIVAL1" },
      { "jump", "end" },

      { "label", "raise_young" },
      { "show_text", "_OaksLabOak1RaiseYourYoungPokemonText" },
      { "jump", "end" },

      { "label", "pre_lab_battle" },
      { "check_flag", "EVENT_GOT_STARTER" },
      { "jump_if_true", "can_fight" },
      { "show_text", "_OaksLabOak1WhichPokemonDoYouWantText" },
      { "jump", "end" },
      { "label", "can_fight" },
      { "show_text", "_OaksLabOak1YourPokemonCanFightText" },
      { "jump", "end" },

      { "label", "around_world" },
      { "show_text", "_OaksLabOak1PokemonAroundTheWorldText" },
      { "jump", "end" },

      { "label", "give_balls" },
      { "check_flag", "EVENT_GOT_POKEBALLS_FROM_OAK" },
      { "jump_if_true", "come_see" },
      { "set_flag", "EVENT_GOT_POKEBALLS_FROM_OAK" },
      { "give_item", "POKE_BALL", 5, false },
      { "show_text", "_OaksLabOak1ReceivedPokeballsText" },
      { "show_text", "_OaksLabGivePokeballsExplanationText" },
      { "jump", "end" },

      { "label", "come_see" },
      { "show_text", "_OaksLabOak1ComeSeeMeSometimesText" },
      { "jump", "end" },

      -- .HowIsYourPokedexComingText ends on `prompt` and OaksLabOak1Text
      -- sets wDoNotWaitForButtonPressAfterDisplayingText, so the seen/owned
      -- tally follows with no button wait (engine/events/pokedex_rating.asm)
      { "label", "dex_rating" },
      { "show_text", "_OaksLabOak1HowIsYourPokedexComingText" },
      { "dex_rating" },
    },

    TEXT_OAKSLAB_CHARMANDER_POKE_BALL =
      starterBall("_OaksLabYouWantCharmanderText", "CHARMANDER", "EVENT_CHOSE_CHARMANDER",
                  "OAKSLAB_CHARMANDER_POKE_BALL", 7, "OAKSLAB_SQUIRTLE_POKE_BALL"),
    TEXT_OAKSLAB_SQUIRTLE_POKE_BALL =
      starterBall("_OaksLabYouWantSquirtleText", "SQUIRTLE", "EVENT_CHOSE_SQUIRTLE",
                  "OAKSLAB_SQUIRTLE_POKE_BALL", 8, "OAKSLAB_BULBASAUR_POKE_BALL"),
    TEXT_OAKSLAB_BULBASAUR_POKE_BALL =
      starterBall("_OaksLabYouWantBulbasaurText", "BULBASAUR", "EVENT_CHOSE_BULBASAUR",
                  "OAKSLAB_BULBASAUR_POKE_BALL", 6, "OAKSLAB_CHARMANDER_POKE_BALL"),

    -- Talking to the rival only ever prints a line: the lab battle is a
    -- coordinate trigger (OaksLabRivalChallengesPlayerScript, wYCoord == 6;
    -- see onStep below), never a talk action.  The handler used to fall
    -- through from the "looks stronger" taunt straight into start_battle,
    -- so talking to Blue at the table launched the rival fight before the
    -- player ever stepped onto the trigger (#219).  scripts/OaksLab.asm
    -- OaksLabText8 branches text only:
    --   * got starter, not yet battled -> _OaksLabRivalMyPokemonLooksStronger
    --   * already battled -> _OaksLabRivalFedUpWithWaitingText (a Route 22
    --     line; normally unreachable since the rival is hidden after the
    --     lab battle in OaksLabRivalEndBattleScript)
    --   * no starter yet -> the FOLLOWED_OAK pre-starter fork (#218)
    TEXT_OAKSLAB_RIVAL = {
      { "face_player" },
      { "check_flag", "EVENT_GOT_STARTER" },
      { "jump_if_false", "pre_starter" },
      { "check_flag", "EVENT_BATTLED_RIVAL_IN_OAKS_LAB" },
      { "jump_if_true", "after_battle" },
      -- has a starter, has not fought yet: just the taunt.  The battle is
      -- the coordinate trigger in onStep, not this talk (#219)
      { "show_text", "_OaksLabRivalMyPokemonLooksStrongerText" },
      { "jump", "end" },

      { "label", "after_battle" },
      { "show_text", "_OaksLabRivalFedUpWithWaitingText" },
      { "jump", "end" },

      -- pre-starter fork (scripts/OaksLab.asm OaksLabText8 rival handler):
      -- Oak has already escorted you in (three balls on the table) -> he
      -- waves you on to choose; not yet escorted (very early game) -> the
      -- "Gramps isn't around" line.  #218
      { "label", "pre_starter" },
      { "check_flag", "EVENT_FOLLOWED_OAK_INTO_LAB" },
      { "jump_if_false", "gramps_gone" },
      { "show_text", "_OaksLabRivalGoAheadAndChooseText" },
      { "jump", "end" },

      { "label", "gramps_gone" },
      { "show_text", "_OaksLabRivalGrampsIsntAroundText" },
    },
  },

  -- Saves that got the Pokédex before #106 never wrote objectToggles for
  -- the table sprites; re-entering the lab applies the same HideObject
  -- the gift script now does (OaksLab.asm OakGivesPokedex).
  onEnter = function(game, ow)
    local flags = game.save.flags or {}
    if flags.EVENT_GOT_STARTER and not flags.EVENT_BATTLED_RIVAL_IN_OAKS_LAB then
      local rival = ow:npcByIndex(1)
      if rival then
        rival.cellX = flags.EVENT_CHOSE_CHARMANDER and 7
          or flags.EVENT_CHOSE_SQUIRTLE and 8 or 6
        rival.cellY = 4
        rival.px, rival.py = rival.cellX * 16, rival.cellY * 16
      end
    end
    if not flags.EVENT_GOT_POKEDEX then return end
    local Commands = require("src.script.Commands")
    local ctx = { save = game.save, game = game, overworld = ow }
    Commands.hide_object(ctx, "OAKS_LAB", "OAKSLAB_POKEDEX1")
    Commands.hide_object(ctx, "OAKS_LAB", "OAKSLAB_POKEDEX2")
  end,

  -- Oak stops you leaving without a starter; the rival stops you on
  -- the way out for the first battle (scripts/OaksLab.asm
  -- OaksLabScript8 / OaksLabRivalChallenge)
  onStep = function(game, ow, x, y)
    local flags = game.save.flags
    -- Oak stops you leaving without a starter at the bookshelf row (cell
    -- y == 6): this is the same wYCoord == 6 coordinate script the rival
    -- challenge just below uses (scripts/OaksLab.asm, both gated on
    -- EVENT_GOT_STARTER), so Oak halts you level with the shelves, not one
    -- corridor length later on the exit mat.  At y>=6 only the x=4,5
    -- corridor is walkable and the up-push keeps the player above y=7, so
    -- this only ever fires at y=6 in the corridor -- matching the rival
    -- trigger's shape. (#232)
    if flags.EVENT_FOLLOWED_OAK_INTO_LAB and not flags.EVENT_GOT_STARTER
       and y >= 6 then
      ow.runner:run({
        { "show_text", "_OaksLabOakDontGoAwayYetText" },
        { "move_player", "up", 1 },
      }, {})
      return true
    end
    -- the challenge fires as soon as the player steps away from the
    -- table (OaksLabRivalChallengesPlayerScript: wYCoord == 6)
    if flags.EVENT_GOT_STARTER and not flags.EVENT_BATTLED_RIVAL_IN_OAKS_LAB
       and y >= 6 then
      local rival = ow:npcByIndex(1)
      if not rival then return false end
      -- OaksLabRivalChallengesPlayerScript swaps in the rival encounter
      -- fanfare for the taunt/challenge exchange, same as the Yellow port
      -- (oaks_lab_yellow.lua); it was silently dropped here (#596).
      local rows = {
        { "face_player_dir", "up" },
        { "stop_music" },
        { "play_music", "Music_MeetRival" },
        { "show_text", "_OaksLabRivalIllTakeYouOnText" },         -- 1
      }
      -- the rival routes to a free cell beside the player
      local target
      for _, c in ipairs({ { x, y - 1 }, { x - 1, y }, { x + 1, y },
                           { x, y + 1 } }) do
        if ow.map:inBounds(c[1], c[2]) and ow.map:isWalkableCell(c[1], c[2]) then
          target = c
          break
        end
      end
      if target then
        table.insert(rows, { "move_npc_to", 1, target[1], target[2] })
      end
      table.insert(rows, { "face_object", 1,
                           target and target[2] < y and "down"
                           or target and target[2] > y and "up"
                           or target and target[1] < x and "right" or "left" })
      local base = #rows
      local party = flags.EVENT_CHOSE_BULBASAUR and 3
                    or flags.EVENT_CHOSE_SQUIRTLE and 2 or 1
      table.insert(rows, { "save_end_battle_text", "_OaksLabRivalIPickedTheWrongPokemonText" })
      table.insert(rows, { "start_battle", "trainer", "OPP_RIVAL1", party })
      -- OaksLabRivalEndBattleScript: heal + flag on win or loss; no blackout
      table.insert(rows, { "heal_party" })
      table.insert(rows, { "set_flag", "EVENT_BATTLED_RIVAL_IN_OAKS_LAB" })
      table.insert(rows, { "jump_if_false", base + 6 })
      table.insert(rows, { "show_text", "_OaksLabRivalSmellYouLaterText" })
      -- OaksLabRivalStartsExitScript: parting shot, rival exit fanfare, then
      -- walk out past the player.  The fanfare was dropped here (#683) -- the
      -- parcel scene above already plays Music_MeetRival on both arrival and
      -- departure (lines 144-146), and this exit should match (#596).
      table.insert(rows, { "stop_music" })
      table.insert(rows, { "play_music", "Music_MeetRival", { start = "rival" } })
      table.insert(rows, { "move_npc_to", 1, 4, 11 })
      table.insert(rows, { "hide_object", "OAKS_LAB", "OAKSLAB_RIVAL" })
      table.insert(rows, { "play_music", "Music_OaksLab" })
      ow.runner:run(rows, { npc = rival })
      return true
    end
    return false
  end,
}
