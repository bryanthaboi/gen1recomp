-- Hand-ported from pret/pokeyellow scripts/OaksLab.asm.
-- Yellow: one Eevee ball on the table.  Rival snatches it; Oak then
-- gives the player the wild Pikachu he caught earlier (STARTER_PIKACHU).
-- Object indices differ from Red (no Charmander/Squirtle/Bulbasaur balls):
--   1 RIVAL (4,3), 2 EEVEE_POKE_BALL (7,3), 3 OAK1 (5,2),
--   4-5 POKEDEX (2,1)/(3,1), 6 OAK2 (door), 7 GIRL, 8-9 SCIENTIST.
--
-- wRivalStarter rides in save.rivalStarter (RIVAL_STARTER_* 1 JOLTEON /
-- 2 FLAREON / 3 VAPOREON): JOLTEON baseline at the snatch
-- (OaksLabRivalTakesPokeballScript), FLAREON on a lab win / VAPOREON on
-- a lab loss (OaksLabRivalEndBattleScript), and Route 22's first battle
-- upgrades FLAREON back to JOLTEON (Route22Rival1AfterBattleScript).

local OAK1 = 3
local RIVAL = 1

return {
  talk = {
    TEXT_OAKSLAB_OAK1 = {
      { "face_player" },
      -- Yellow's OaksLabOak1Text leads with the dex-rating branch: once
      -- EVENT_PALLET_AFTER_GETTING_POKEBALLS is set (converted saves) or
      -- 2+ species are owned, Oak asks how the Pokédex is coming and
      -- rates it (predef DisplayDexRating)
      { "check_flag", "EVENT_PALLET_AFTER_GETTING_POKEBALLS" },
      { "jump_if_true", "dex_rating" },
      { "check_dex_owned", 2 },
      { "jump_if_true", "dex_rating" },
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
      -- .DeliverParcelText: parcel handover, then the Pokédex scene
      -- (OaksLabRivalArrivesAtOaksRequestScript -> OakGivesPokedexScript)
      { "show_text", "_OaksLabOak1DeliverParcelText" },
      { "play_sound", "Get_Key_Item" },
      { "show_text", "_OaksLabOak1ParcelThanksText" },
      { "take_item", "OAKS_PARCEL", 1 },
      { "stop_music" },
      { "play_music", "Music_MeetRival" },
      { "show_text", "_OaksLabRivalGrampsText" },
      { "show_object", "OAKS_LAB", "OAKSLAB_RIVAL" },
      { "place_npc", RIVAL, 4, 7, "up" },
      { "move_npc_to", RIVAL, 4, 3 },
      { "play_music", "Music_OaksLab" },
      { "face_object", RIVAL, "up" },
      { "face_object", OAK1, "down" },
      -- Yellow opens with the rival bragging, not Red's "what did you
      -- call me for" (OaksLabOakGivesPokedexScript text order)
      { "show_text", "_OaksLabRivalMyPokemonHasGrownStrongerText" },
      { "face_object", RIVAL, "up" },
      { "face_object", OAK1, "down" },
      { "show_text", "_OaksLabOakIHaveARequestText" },
      { "face_object", RIVAL, "up" },
      { "face_object", OAK1, "down" },
      { "show_text", "_OaksLabOakMyInventionPokedexText" },
      { "show_text", "_OaksLabOakGotPokedexText" },
      { "play_sound", "Get_Key_Item" },
      { "hide_object", "OAKS_LAB", "OAKSLAB_POKEDEX1" },
      { "hide_object", "OAKS_LAB", "OAKSLAB_POKEDEX2" },
      { "face_object", RIVAL, "up" },
      { "face_object", OAK1, "down" },
      { "show_text", "_OaksLabOakThatWasMyDreamText" },
      { "face_object", RIVAL, "right" },
      { "show_text", "_OaksLabRivalLeaveItAllToMeText" },
      { "set_flag", "EVENT_GOT_POKEDEX" },
      { "set_flag", "EVENT_OAK_GOT_PARCEL" },
      -- OaksLabOakGivesPokedexScript: HideObject TOGGLE_LYING_OLD_MAN /
      -- ShowObject TOGGLE_OLD_MAN_2 -- Yellow's tutorial old man stands
      -- on the sleeper's cell (18,9); the Red/Blue walker OLD_MAN at
      -- (17,5) never appears in Yellow (#617)
      { "hide_object", "VIRIDIAN_CITY", "VIRIDIANCITY_OLD_MAN_SLEEPY" },
      { "show_object", "VIRIDIAN_CITY", "VIRIDIANCITY_OLD_MAN2" },
      { "stop_music" },
      { "play_music", "Music_MeetRival" },
      { "move_npc_to", RIVAL, 4, 7 },
      { "hide_object", "OAKS_LAB", "OAKSLAB_RIVAL" },
      { "play_music", "Music_OaksLab" },
      { "set_flag", "EVENT_1ST_ROUTE22_RIVAL_BATTLE" },
      { "clear_flag", "EVENT_2ND_ROUTE22_RIVAL_BATTLE" },
      { "set_flag", "EVENT_ROUTE22_RIVAL_WANTS_BATTLE" },
      { "show_object", "ROUTE_22", "ROUTE22_RIVAL1" },
      { "jump", "end" },

      { "label", "raise_young" },
      -- Yellow: talk-to-it (starter Pikachu) instead of Red raise-young line.
      { "show_text", "_OaksLabOak1YouShouldTalkToIt" },
      { "jump", "end" },

      { "label", "pre_lab_battle" },
      { "check_flag", "EVENT_GOT_STARTER" },
      { "jump_if_true", "can_fight" },
      { "show_text", "_OaksLabOak1GoAheadItsYours" },
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
      { "play_sound", "Get_Key_Item" },
      { "show_text", "_OaksLabGivePokeballsExplanationText" },
      { "jump", "end" },

      { "label", "come_see" },
      { "show_text", "_OaksLabOak1ComeSeeMeSometimesText" },
      { "jump", "end" },

      { "label", "dex_rating" },
      { "show_text", "_OaksLabOak1HowIsYourPokedexComingText" },
      { "dex_rating" },
    },

    -- OaksLabEeveePokeBallText / OaksLabRivalExclamationScript ->
    -- OaksLabChoseStarterScript..OaksLabPlayerReceivesPikachuScript:
    -- before Oak's choose speech the ball is just flavor; after it, the
    -- rival "!"s, shoves the player off the table, snatches the ball,
    -- then the player is walked over to Oak and handed Pikachu.
    TEXT_OAKSLAB_EEVEE_POKE_BALL = function(game, ow, npc, done)
      local flags = game.save.flags
      if flags.EVENT_GOT_STARTER then
        done()
        return
      end
      if not flags.EVENT_OAK_ASKED_TO_CHOOSE_MON then
        ow.runner:run({
          { "show_text", "_OaksLabThatsAPokeball" },
        }, { onDone = done })
        return
      end
      local px, py = ow.player.cellX, ow.player.cellY
      local rows = {
        -- OaksLabRivalExclamationScript: "!" over the rival
        { "emote", RIVAL, "shock" },
      }
      -- .RivalPushesPlayerAwayFromEeveeBall is DOWN then RIGHT x3 (the $07
      -- bytes are Yellow's own step-right encoding, decoded by
      -- engine/overworld/movement.asm Func_5288 -> Func_532b), and the
      -- PAD_RIGHT x2 shove is NOT queued alongside it:
      -- OaksLabRivalTakesPokeballScript .asm_1c564 polls every frame and
      -- only simulates the pair once wNPCNumScriptedSteps reads 1 -- i.e.
      -- as the rival begins the LAST byte, the step onto the tile the
      -- player is standing on.  Starting both on one row had Red stroll
      -- off the Eevee while the rival was still at the top of the table
      -- (#559).
      if py == 4 then
        rows[#rows + 1] = { "walk_npc", RIVAL, { "down", "right", "right" } }
        -- this one runs concurrently with the shove below
        rows[#rows + 1] = { "walk_npc", RIVAL, { "right" }, { wait = false } }
        rows[#rows + 1] = { "face_player_dir", "left" }
        rows[#rows + 1] = { "move_player", "right", 2 }
        -- move_player blocks for both tiles, so the rival has already
        -- landed on (7,4); this is just the beat before he turns up
        rows[#rows + 1] = { "wait", 20 }
      else
        rows[#rows + 1] = { "move_npc_to", RIVAL, 7, 4 }
      end
      rows[#rows + 1] = { "face_object", RIVAL, "up" }
      rows[#rows + 1] = { "hide_object", "OAKS_LAB", "OAKSLAB_EEVEE_POKE_BALL" }
      -- rival starter baseline (RIVAL_STARTER_JOLTEON) at snatch time
      rows[#rows + 1] = { "set_field", "rivalStarter", 1 }
      rows[#rows + 1] = { "show_text", "_OaksLabRivalTakesText1" }
      rows[#rows + 1] = { "play_sound", "Get_Key_Item" }
      rows[#rows + 1] = { "show_text", "_OaksLabRivalTakesText2" }
      rows[#rows + 1] = { "show_text", "_OaksLabRivalTakesText3" }
      rows[#rows + 1] = { "show_text", "_OaksLabRivalTakesText4" }
      rows[#rows + 1] = { "show_text", "_OaksLabRivalTakesText5" }
      -- OaksLabRLE_PlayerWalksToOak: the simulated-joypad buffer plays
      -- its RLE list BACKWARDS (StartSimulatingJoypadStates consumes
      -- from wSimulatedJoypadStatesEnd), so the real order is LEFT 1,
      -- DOWN 1, LEFT 3, UP 2 -- from the shove spot (9,4) the player
      -- rounds the BOTTOM of the table to (5,3), directly below Oak
      if py == 4 then
        rows[#rows + 1] = { "walk_npc", "player",
          { "left", "down", "left", "left", "left", "up", "up" } }
      else
        rows[#rows + 1] = { "walk_npc", "player", { "left" } }
      end
      rows[#rows + 1] = { "face_player_dir", "up" }
      rows[#rows + 1] = { "face_object", OAK1, "down" }
      -- OaksLabPlayerReceivedMonText: no nickname prompt -- the starter
      -- Pikachu keeps its species name
      rows[#rows + 1] = { "show_text", "_OaksLabOakGivesText" }
      rows[#rows + 1] = { "play_sound", "Get_Key_Item" }
      rows[#rows + 1] = { "show_text", "_OaksLabReceivedText", { RAM = "PIKACHU" } }
      rows[#rows + 1] = { "give_pokemon", "PIKACHU", 5, true }
      rows[#rows + 1] = { "set_flag", "EVENT_GOT_STARTER" }
      rows[#rows + 1] = { "set_flag", "EVENT_CHOSE_PIKACHU" }
      ow.runner:run(rows, { npc = npc, onDone = done })
    end,

    TEXT_OAKSLAB_RIVAL = {
      { "face_player" },
      { "check_flag", "EVENT_GOT_STARTER" },
      { "jump_if_false", "pre_starter" },
      { "show_text", "_OaksLabRivalMyPokemonLooksStrongerText" },
      { "jump", "end" },

      { "label", "pre_starter" },
      { "check_flag", "EVENT_FOLLOWED_OAK_INTO_LAB_2" },
      { "jump_if_false", "gramps_gone" },
      { "show_text", "_OaksLabRivalIllGetABetterPokemonThanYou" },
      { "jump", "end" },

      { "label", "gramps_gone" },
      { "show_text", "_OaksLabRivalGrampsIsntAroundText" },
    },
  },

  onEnter = function(game, ow)
    if not (game.save.flags and game.save.flags.EVENT_GOT_POKEDEX) then
      return
    end
    local Commands = require("src.script.Commands")
    local ctx = { save = game.save, game = game, overworld = ow }
    Commands.hide_object(ctx, "OAKS_LAB", "OAKSLAB_POKEDEX1")
    Commands.hide_object(ctx, "OAKS_LAB", "OAKSLAB_POKEDEX2")
  end,

  onStep = function(game, ow, x, y)
    local flags = game.save.flags
    -- OaksLabPlayerDontGoAwayScript: y==6 without the starter walks the
    -- player back up a tile
    if flags.EVENT_FOLLOWED_OAK_INTO_LAB and not flags.EVENT_GOT_STARTER
       and y >= 6 then
      ow.runner:run({
        { "face_object", OAK1, "down" },
        { "face_object", RIVAL, "down" },
        { "show_text", "_OaksLabOakDontGoAwayYetText" },
        { "move_player", "up", 1 },
      }, {})
      return true
    end
    -- OaksLabRivalChallengesPlayerScript..OaksLabPikachuDislikesPokeballsScript:
    -- heading for the door with Pikachu starts the rival battle, his
    -- exit walk, then Pikachu pops out of its ball.
    if flags.EVENT_GOT_STARTER and not flags.EVENT_BATTLED_RIVAL_IN_OAKS_LAB
       and y >= 6 then
      local rival = ow:npcByIndex(RIVAL)
      if not rival then return false end
      local rows = {
        { "face_player_dir", "up" },
        { "stop_music" },
        { "play_music", "Music_MeetRival" },
        { "show_text", "_OaksLabRivalIllTakeYouOnText" },
      }
      -- FindPathToPlayer with the Y distance decremented: the rival
      -- stops one tile above the player
      local target
      for _, c in ipairs({ { x, y - 1 }, { x - 1, y }, { x + 1, y },
                           { x, y + 1 } }) do
        if ow.map:inBounds(c[1], c[2]) and ow.map:isWalkableCell(c[1], c[2]) then
          target = c
          break
        end
      end
      if target then
        table.insert(rows, { "move_npc_to", RIVAL, target[1], target[2] })
      end
      table.insert(rows, { "face_object", RIVAL,
                           target and target[2] < y and "down"
                           or target and target[2] > y and "up"
                           or target and target[1] < x and "right" or "left" })
      table.insert(rows, { "start_battle", "trainer", "OPP_RIVAL1", 1 })
      table.insert(rows, { "heal_party" })
      table.insert(rows, { "set_flag", "EVENT_BATTLED_RIVAL_IN_OAKS_LAB" })
      -- OaksLabRivalEndBattleScript: his Eevee's future evolution is
      -- decided here -- FLAREON if the player won, VAPOREON otherwise
      table.insert(rows, { "check_battle_result", "win" })
      table.insert(rows, { "jump_if_false", "lost_lab" })
      table.insert(rows, { "set_field", "rivalStarter", 2 })
      table.insert(rows, { "jump", "exit" })
      table.insert(rows, { "label", "lost_lab" })
      table.insert(rows, { "set_field", "rivalStarter", 3 })
      table.insert(rows, { "label", "exit" })
      -- OaksLabRivalStartsExitScript: parting shot, rival exit fanfare, then
      -- walk out past the player (#683).
      table.insert(rows, { "wait", 20 })
      table.insert(rows, { "show_text", "_OaksLabRivalSmellYouLaterText" })
      table.insert(rows, { "stop_music" })
      table.insert(rows, { "play_music", "Music_MeetRival" })
      table.insert(rows, { "move_npc_to", RIVAL, 4, 11 })
      table.insert(rows, { "hide_object", "OAKS_LAB", "OAKSLAB_RIVAL" })
      table.insert(rows, { "play_music", "Music_OaksLab" })
      -- OaksLabPikachuEscapesPokeballScript: Pikachu hates its ball.
      -- The overworld follower itself is still an open port
      -- (docs/yellow-version.md runtime backlog); the story beat plays.
      table.insert(rows, { "play_cry", "PIKACHU" })
      table.insert(rows, { "show_text", "_OaksLabPikachuDislikesPokeballsText1" })
      table.insert(rows, { "show_text", "_OaksLabPikachuDislikesPokeballsText2" })
      ow.runner:run(rows, { npc = rival })
      return true
    end
    return false
  end,
}
