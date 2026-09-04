-- Hand-ported story-critical scripts, one table per map, all using real
-- extracted text.  Each cites its pokered source.  Registered in
-- data/scripts/init.lua.

local M = {}

-- -------------------------------------------------------------------
-- Oak's Parcel chain (scripts/ViridianMart.asm, OaksLab.asm,
-- ViridianCity.asm)
-- -------------------------------------------------------------------

M.VIRIDIAN_MART = {
  -- scripts/ViridianMart.asm: the parcel hand-off is the map's DEFAULT
  -- script, not a talk.  Entering with a starter and no parcel runs
  -- ViridianMartDefaultScript -- the clerk calls out, then
  -- StartSimulatingJoypadStates walks the player to the counter
  -- (.PlayerMovement: PAD_LEFT 1, PAD_UP 2, door (3,7) -> counter (2,5))
  -- and ViridianMartOaksParcelScript hands the parcel over.  The player
  -- never presses A.
  --
  -- The RLE list is consumed back to front: DecodeRLEList fills forward
  -- from wSimulatedJoypadStatesEnd, the script seeds wSimulatedJoypadStates-
  -- Index with the count, and home/overworld.asm decrements that index
  -- before each read.  So PAD_LEFT 1, PAD_UP 2 actually plays up, up, left,
  -- and the walk ends facing the clerk.  Replaying the list front to back
  -- put the player at the counter facing up instead (#235).  The player
  -- never presses A.  This matters beyond convenience: the parcel gates
  -- Oak's Pokedex and the old man clearing Route 2, so vanilla guarantees
  -- it on entry rather than letting you walk out without it.
  --
  -- The talk branch below is kept as the fallback for a save that reaches
  -- the counter without this having fired.
  onEnter = function(game, ow)
    local f = game.save.flags
    if f.EVENT_OAK_GOT_PARCEL or f.EVENT_GOT_OAKS_PARCEL then return end
    if not f.EVENT_GOT_STARTER then return end
    ow:queueScript({
      { "show_text", "_ViridianMartClerkYouCameFromPalletTownText" },
      { "move_player", "up", 2 },
      { "move_player", "left", 1 },
      -- the quest text's last page is "{PLAYER} got\nOAK's PARCEL!"
      { "give_item", "OAKS_PARCEL", 1, "_ViridianMartClerkParcelQuestText" },
      { "set_flag", "EVENT_GOT_OAKS_PARCEL" },
    })
  end,
  talk = {
    TEXT_VIRIDIANMART_CLERK = {
      { "check_flag", "EVENT_OAK_GOT_PARCEL" },                       -- 1
      { "jump_if_true", 11 },                                         -- 2
      { "check_flag", "EVENT_GOT_OAKS_PARCEL" },                      -- 3
      { "jump_if_true", 13 },                                         -- 4
      { "check_flag", "EVENT_GOT_STARTER" },                          -- 5
      { "jump_if_false", 11 },                                        -- 6
      { "show_text", "_ViridianMartClerkYouCameFromPalletTownText" }, -- 7
      -- the parcel-quest text's last page is "{PLAYER} got\nOAK's
      -- PARCEL!" (scripts/ViridianMart.asm, sound_get_key_item)
      { "give_item", "OAKS_PARCEL", 1, "_ViridianMartClerkParcelQuestText" }, -- 8
      { "set_flag", "EVENT_GOT_OAKS_PARCEL" },                        -- 9
      { "jump", 14 },                                                 -- 10
      { "open_mart", "TEXT_VIRIDIANMART_CLERK" },                     -- 11
      { "jump", 14 },                                                 -- 12
      { "show_text", "_ViridianMartClerkSayHiToOakText" },            -- 13
    },
  },
}

M.VIRIDIAN_CITY = {
  talk = {
    -- The GAMBLER_ASLEEP at (18,9) (ViridianCityOldManSleepyText): he
    -- only ever grumbles and shoves you back down -- he never wakes,
    -- moves or hides.  The coffee ask and the catch tutorial belong to
    -- the *other* old man, the walking SPRITE_GAMBLER at (17,5)
    -- (TEXT_VIRIDIANCITY_OLD_MAN, below).  The two are swapped by the
    -- Pokédex in data/scripts/oaks_lab.lua, not by talking to either.
    TEXT_VIRIDIANCITY_OLD_MAN_SLEEPY = {
      { "show_text", "_ViridianCityOldManSleepyPrivatePropertyText" },   -- 1
      { "move_player", "down", 1 },                                     -- 2
    },

    -- The walking old man at (17,5), shown once the Pokédex swaps him in
    -- (ViridianCityOldManText).  "Are you in a hurry?" -- YES brushes you
    -- off, NO leads into the catch tutorial: he explains, demos a catch
    -- on a wild WEEDLE (BATTLE_TYPE_OLD_MAN), then comments afterwards.
    -- pokered prints YouNeedToWeakenTheTarget *after* the demo battle
    -- (ViridianCityOldManEndCatchTrainingScript), not before it.
    TEXT_VIRIDIANCITY_OLD_MAN = {
      { "face_player" },                                                 -- 1
      { "ask", "_ViridianCityOldManHadMyCoffeeNowText" },                -- 2
      { "jump_if_true", 8 },                                             -- 3 (yes = in a hurry)
      { "show_text", "_ViridianCityOldManKnowHowToCatchPokemonText" },   -- 4
      { "old_man_demo" },                                                -- 5
      { "show_text", "_ViridianCityOldManYouNeedToWeakenTheTargetText" },-- 6
      { "jump", 9 },                                                     -- 7
      { "show_text", "_ViridianCityOldManTimeIsMoneyText" },             -- 8 (9 = end)
    },
  },
  -- Re-apply the Pokedex old-man swap for a save that already holds the flag
  -- but was never standing here when it fired: a vanilla .sav imported
  -- through src/save_convert, whose codec does not model pokered's
  -- wToggleableObjectFlags array, so save.objectToggles arrives empty and
  -- both objects fall back to their compiled-in defaults -- the sleeper ON
  -- (data/maps/toggleable_objects.asm toggleable_objects_for VIRIDIAN_CITY),
  -- still lying across the north path (#234).
  -- OaksLabOakGivesPokedexScript (scripts/OaksLab.asm) sets EVENT_GOT_POKEDEX
  -- and, with no branch in between, runs HideObject TOGGLE_LYING_OLD_MAN /
  -- ShowObject TOGGLE_OLD_MAN, so that one flag settles both toggles exactly.
  -- Same shape as M.OAKS_LAB.onEnter in data/scripts/oaks_lab.lua, which
  -- re-applies the same script's other two HideObjects on entry (#106).
  onEnter = function(game, ow)
    if not (game.save.flags and game.save.flags.EVENT_GOT_POKEDEX) then
      return
    end
    local Commands = require("src.script.Commands")
    local ctx = { save = game.save, game = game, overworld = ow }
    Commands.hide_object(ctx, "VIRIDIAN_CITY", "VIRIDIANCITY_OLD_MAN_SLEEPY")
    Commands.show_object(ctx, "VIRIDIAN_CITY", "VIRIDIANCITY_OLD_MAN")
  end,
  -- ViridianCityCheckGotPokedexScript: the north corridor is gated on
  -- EVENT_GOT_POKEDEX, NOT on the sleeper being hidden, and it triggers
  -- on exactly one cell -- (19,9), the gap east of the sleeper (18,9)
  -- and the girl (17,9).  With the Pokédex the check returns immediately
  -- and you simply walk past at x=19.
  onStep = function(game, ow, x, y)
    if game.save.flags and game.save.flags.EVENT_GOT_POKEDEX then return false end
    if x ~= 19 or y ~= 9 then return false end
    local TextBox = require("src.render.TextBox")
    game.stack:push(TextBox.new(game,
      game.data.text._ViridianCityOldManSleepyPrivatePropertyText
      or "You can't go\nthrough here!\fThis is private\nproperty!",
      function() ow:scriptMove(ow.player, "down", 1, nil, { collide = true }) end))
    return true
  end,
}

-- -------------------------------------------------------------------
-- Bill's SS ticket (scripts/BillsHouse.asm; the cell-separation cutscene
-- is compressed into the dialogue)
-- -------------------------------------------------------------------

-- Daisy hands over the TOWN MAP once Oak's errand is under way
-- (scripts/BluesHouse.asm BluesHouseDaisySittingText)
M.BLUES_HOUSE = {
  -- scripts/BluesHouse.asm:12-16
  onEnter = function(game, ow)
    game.save.flags.EVENT_ENTERED_BLUES_HOUSE = true
  end,
  talk = {
    TEXT_BLUESHOUSE_DAISY_SITTING = {
      { "face_player" },
      { "check_flag", "EVENT_GOT_TOWN_MAP" },
      { "jump_if_true", "got_map" },
      { "check_flag", "EVENT_GOT_POKEDEX" },
      { "jump_if_false", "too_early" },
      { "show_text", "_BluesHouseDaisyOfferMapText" },
      -- _GotMapText: "{PLAYER} got a\n{RAM:wStringBuffer}!" -- the
      -- buffer supplies "TOWN MAP" (scripts/BluesHouse.asm GotMapText)
      { "give_item", "TOWN_MAP", 1, "_GotMapText" },
      { "hide_object", "BLUES_HOUSE", "BLUESHOUSE_TOWN_MAP" },
      { "set_flag", "EVENT_GOT_TOWN_MAP" },
      { "jump", "end" },
      { "label", "got_map" },
      { "show_text", "_BluesHouseDaisyUseMapText" },
      { "jump", "end" },
      { "label", "too_early" },
      { "show_text", "_BluesHouseDaisyRivalAtLabText" },
    },
  },
}

M.BILLS_HOUSE = {
  talk = {
    -- BillsHouseBillPokemonText: "I'm not a POKéMON!", a YES/NO choice
    -- (NO only adds "No, you gotta help!" before rejoining the YES
    -- path), then the "get in the TELEPORTER" line and the monster
    -- walking into the cell-separator machine
    -- (BillsHousePokemonWalkToMachineScript: up 3, or around the player
    -- when they stand in the way facing down), where it is hidden and
    -- EVENT_BILL_SAID_USE_CELL_SEPARATOR arms the PC at (1,4) -- see
    -- OverworldState.billsHousePC for the separator itself.
    TEXT_BILLSHOUSE_BILL_POKEMON = function(game, ow, npc, done)
      local TextBox = require("src.render.TextBox")
      local t = game.data.text
      local function toMachine()
        game.stack:push(TextBox.new(game,
          t._BillsHouseBillUseSeparationSystemText
          or "When I'm in the\nTELEPORTER, run\nthe Cell\nSeparation System!", function()
          local function entered()
            local Commands = require("src.script.Commands")
            Commands.hide_object({ game = game, save = game.save,
                                   overworld = ow },
                                 "BILLS_HOUSE", "BILLSHOUSE_BILL_POKEMON")
            game.save.flags.EVENT_BILL_SAID_USE_CELL_SEPARATOR = true
            require("src.world.PikachuFollower").onBillEnteredMachine(game, ow)
            done()
          end
          if ow.player.facing == "down" then
            -- the player is standing on his straight path: walk around
            -- (.PokemonWalkAroundPlayerMovement).  BillsHouseScript2 runs
            -- BillsHousePikachuWatchPlayer first on this branch, so a
            -- Pikachu that is still following steps clear of Bill's detour
            -- and turns to watch the player (#455).
            require("src.world.PikachuFollower")
              .onBillWalksAroundPlayer(game, ow)
            ow:scriptMove(npc, "right", 1, function()
              ow:scriptMove(npc, "up", 2, function()
                ow:scriptMove(npc, "left", 1, function()
                  ow:scriptMove(npc, "up", 1, entered)
                end)
              end)
            end)
          else
            ow:scriptMove(npc, "up", 3, entered)
          end
        end))
      end
      game.stack:push(TextBox.new(game,
        t._BillsHouseBillImNotAPokemonText or "Hey! I'm not a\nPOKéMON!",
        nil, { choice = function(yes)
          if yes then
            toMachine()
          else
            game.stack:push(TextBox.new(game,
              t._BillsHouseBillNoYouGottaHelpText
              or "No! You gotta\nhelp me!", toMachine))
          end
        end }))
    end,

    -- BillsHouseBillSSTicketText (human Bill after the separation)
    TEXT_BILLSHOUSE_BILL_SS_TICKET = {
      { "face_player" },                                           -- 1
      { "check_flag", "EVENT_GOT_SS_TICKET" },                     -- 2
      { "jump_if_true", 12 },                                      -- 3
      { "show_text", "_BillsHouseBillThankYouText" },              -- 4
      -- pokered gives first (GiveItem fills wStringBuffer), then prints
      -- the received text that reads it (scripts/BillsHouse.asm; the
      -- item id is S_S_TICKET in generated items.lua -- keyItem, so the
      -- sound_get_key_item jingle plays like BillsHouse.asm:196)
      -- .bag_full (scripts/BillsHouse.asm:184-186)
      { "give_item", "S_S_TICKET", 1, false, "_SSTicketNoRoomText" }, -- 5
      { "show_text", "_SSTicketReceivedText" },                    -- 6
      { "set_flag", "EVENT_GOT_SS_TICKET" },                       -- 7
      -- The two Cerulean guards are a SWAP PAIR, not scenery
      -- (BillsHouse.asm:174-178): handing over the ticket shows GUARD1 at
      -- (28,12) and hides GUARD2 at (27,12).  This matters far more than it
      -- looks: (27,12) is the ONLY walkable neighbour of the trashed
      -- house's south door at (27,11), and that house is one of the two
      -- ways through the fence that splits Cerulean in half (the badge
      -- house is the other).  Leaving GUARD2 up forever severs the city --
      -- the gym/mart half can never reach the Route 5 exit.
      -- Same swap fires after the TM28 Rocket (CeruleanCity_2.asm
      -- CeruleanHideRocket), so either route opens the path.
      { "show_object", "CERULEAN_CITY", "CERULEANCITY_GUARD1" },   -- 8
      { "hide_object", "CERULEAN_CITY", "CERULEANCITY_GUARD2" },   -- 9
      { "show_text", "_BillsHouseBillWhyDontYouGoInsteadOfMeText" }, -- 10
      { "jump", 13 },                                              -- 11
      { "show_text", "_BillsHouseBillWhyDontYouGoInsteadOfMeText" }, -- 12
    },

    TEXT_BILLSHOUSE_BILL_CHECK_OUT_MY_RARE_POKEMON = {
      { "face_player" },                                           -- 1
      { "show_text", "_BillsHouseBillCheckOutMyRarePokemonText" }, -- 2
    },
  },
  -- repair saves that already got the ticket under the old collapsed
  -- script (the monster never hidden, human Bill never shown)
  onEnter = function(game, ow)
    local flags = game.save.flags
    if flags.EVENT_GOT_SS_TICKET
       and not flags.EVENT_USED_CELL_SEPARATOR_ON_BILL then
      local Commands = require("src.script.Commands")
      local ctx = { game = game, save = game.save, overworld = ow }
      Commands.hide_object(ctx, "BILLS_HOUSE", "BILLSHOUSE_BILL_POKEMON")
      Commands.show_object(ctx, "BILLS_HOUSE", "BILLSHOUSE_BILL1")
      flags.EVENT_BILL_SAID_USE_CELL_SEPARATOR = true
      flags.EVENT_USED_CELL_SEPARATOR_ON_BILL = true
      flags.EVENT_MET_BILL = true
      flags.EVENT_MET_BILL_2 = true
    end
    -- After Route25ToggleBillsScript, BILL2 is the visible human Bill
    -- ("check out my rare POKéMON").  Re-apply on enter so a mid-house
    -- load still matches the toggles if the pool was rebuilt.
    if flags.EVENT_LEFT_BILLS_HOUSE_AFTER_HELPING then
      local Commands = require("src.script.Commands")
      local ctx = { game = game, save = game.save, overworld = ow }
      Commands.hide_object(ctx, "BILLS_HOUSE", "BILLSHOUSE_BILL_POKEMON")
      Commands.hide_object(ctx, "BILLS_HOUSE", "BILLSHOUSE_BILL1")
      Commands.show_object(ctx, "BILLS_HOUSE", "BILLSHOUSE_BILL2")
    end
    if not flags.EVENT_MET_BILL_2 then
      require("src.world.PikachuFollower").onBillsHouseEnter(game, ow)
    end
  end,
}

-- -------------------------------------------------------------------
-- Route 25 outside Bill's house (scripts/Route25.asm
-- Route25ToggleBillsScript): leaving after the SS Ticket arms the
-- Eevee PC list and swaps human Bill to his post-help dialogue NPC.
-- Leaving mid-quest (Bill still in the machine) puts the monster back.
-- -------------------------------------------------------------------

M.ROUTE_25 = {
  onEnter = function(game, ow)
    game.save.pikachuMapScriptActive = nil
    local flags = game.save.flags
    if flags.EVENT_LEFT_BILLS_HOUSE_AFTER_HELPING then return end
    local Commands = require("src.script.Commands")
    local ctx = { game = game, save = game.save, overworld = ow }
    if not flags.EVENT_MET_BILL_2 then
      flags.EVENT_BILL_SAID_USE_CELL_SEPARATOR = nil
      Commands.show_object(ctx, "BILLS_HOUSE", "BILLSHOUSE_BILL_POKEMON")
      return
    end
    if not flags.EVENT_GOT_SS_TICKET then return end
    flags.EVENT_LEFT_BILLS_HOUSE_AFTER_HELPING = true
    -- TOGGLE_NUGGET_BRIDGE_GUY (ROUTE24_COOLTRAINER_M1)
    Commands.hide_object(ctx, "ROUTE_24", "ROUTE24_COOLTRAINER_M1")
    Commands.hide_object(ctx, "BILLS_HOUSE", "BILLSHOUSE_BILL1")
    Commands.show_object(ctx, "BILLS_HOUSE", "BILLSHOUSE_BILL2")
  end,
}

-- -------------------------------------------------------------------
-- SS Anne (scripts/VermilionCity.asm, SSAnne2F.asm,
-- SSAnneCaptainsRoom.asm)
-- -------------------------------------------------------------------

M.VERMILION_CITY = {
  -- VermilionCity_Script .setFirstLockTrashCanIndex (scripts/
  -- VermilionCity.asm): every load of this map re-rolls which Vermilion
  -- Gym trash can hides the first-lock switch (Random & $0e: a random
  -- EVEN can, 0-14).  The roll is unconditional -- pokered does not
  -- care whether the first lock is already open, because the index is
  -- only read while EVENT_1ST_LOCK_OPENED is unset (the gym is only
  -- reachable through this map, so a fresh visit always re-rolls).
  onEnter = function(game, ow)
    game.save.pikachuMapScriptActive = nil
    local puz = game.save.trashPuzzle or {}
    game.save.trashPuzzle = puz
    puz.first = love.math.random(0, 7) * 2
  end,
  -- VermilionCityDefaultScript's per-frame SSAnneTicketCheckCoords check:
  -- the unguarded cell (18,30) just west of the sailor leads straight
  -- onto the dock warp.  Stepping onto it facing down always runs the
  -- sailor dialog (DisplayTextID TEXT_VERMILIONCITY_SAILOR1); only a
  -- ticket while the ship is still docked lets the player continue --
  -- otherwise they are walked back up.  The sailor himself never hides.
  onStep = function(game, ow, x, y)
    if x ~= 18 or y ~= 30 then return false end
    if ow.player.facing ~= "down" then return false end
    local Flags = require("src.script.Flags")
    local t = game.data.text
    local TextBox = require("src.render.TextBox")
    local shipLeft = Flags.get(game.save, "EVENT_SS_ANNE_LEFT")
    local hasTicket = (game.save.inventory.S_S_TICKET or 0) > 0
    if shipLeft then
      game.stack:push(TextBox.new(game,
        t._VermilionCitySailor1ShipSetSailText or "The ship set sail.",
        function() ow:scriptMove(ow.player, "up", 1, nil, { collide = true }) end))
      return true
    end
    -- Walk-past is never facing-right / inFrontOfOrBehindGuardCoords, so
    -- VermilionCitySailor1Text always takes .greet_player_and_check_ticket:
    -- DoYouHaveATicket, then FlashedTicket (allow through) or YouNeedATicket
    -- (walk back).  Returning true while the box is up also blocks the
    -- dock warp on this step.
    local ask = t._VermilionCitySailor1DoYouHaveATicketText
      or "Welcome to S.S.\nANNE!\fExcuse me, do you\nhave a ticket?"
    if hasTicket then
      game.stack:push(TextBox.new(game,
        ask .. "\f"
        .. (t._VermilionCitySailor1FlashedTicketText
            or "{PLAYER} flashed\nthe S.S.TICKET!")))
      return true
    end
    game.stack:push(TextBox.new(game,
      ask .. "\f"
      .. (t._VermilionCitySailor1YouNeedATicketText
          or "You need a ticket\nto get aboard."),
      function() ow:scriptMove(ow.player, "up", 1, nil, { collide = true }) end))
    return true
  end,
  talk = {
    -- scripts/VermilionCity.asm:158 (#1651)
    TEXT_VERMILIONCITY_SAILOR1 = function(game, ow, npc, done)
      local Flags = require("src.script.Flags")
      local TextBox = require("src.render.TextBox")
      local t = game.data.text
      if Flags.get(game.save, "EVENT_SS_ANNE_LEFT") then
        game.stack:push(TextBox.new(game,
          t._VermilionCitySailor1ShipSetSailText or "The ship set sail.",
          done))
        return
      end
      -- scripts/VermilionCity.asm:195
      local p = ow and ow.player
      if not p or p.facing == "right"
         or (p.cellX == 19 and (p.cellY == 29 or p.cellY == 31)) then
        game.stack:push(TextBox.new(game,
          t._VermilionCitySailor1WelcomeToSSAnneText
            or "Welcome to S.S.\nANNE!", done))
        return
      end
      local ask = t._VermilionCitySailor1DoYouHaveATicketText
        or "Welcome to S.S.\nANNE!\fExcuse me, do you\nhave a ticket?"
      local tail = ((game.save.inventory.S_S_TICKET or 0) > 0)
        and (t._VermilionCitySailor1FlashedTicketText
             or "{PLAYER} flashed\nthe S.S.TICKET!")
        or (t._VermilionCitySailor1YouNeedATicketText
            or "You need a ticket\nto get aboard.")
      game.stack:push(TextBox.new(game, ask .. "\f" .. tail, done))
    end,
  },
}

M.SS_ANNE_2F = {
  talk = {
    TEXT_SSANNE2F_RIVAL = {
      { "face_player" },                                  -- 1
      { "check_flag", "EVENT_BEAT_SS_ANNE_RIVAL" },       -- 2
      { "jump_if_true", 9 },                              -- 3 (beaten: silent)
      { "show_text", "_SSAnne2FRivalText" },              -- 4
      -- SSAnne2FRivalText's text_asm arms SaveEndBattleTextPointers
      -- (scripts/SSAnne2F.asm:199), so the line prints in battle (#1688)
      { "save_end_battle_text", "_SSAnne2FRivalDefeatedText" }, -- 5
      { "rival_battle", "OPP_RIVAL2", 1 },                -- 6
      { "jump_if_false", 9 },                             -- 7
      { "set_flag", "EVENT_BEAT_SS_ANNE_RIVAL" },         -- 8
    },
  },
}

M.SS_ANNE_CAPTAINS_ROOM = {
  talk = {
    -- SSAnneCaptainsRoomCaptainText: after the rub line's text_asm tail,
    -- pokered plays MUSIC_PKMN_HEALED (scripts/SSAnneCaptainsRoom.asm).
    TEXT_SSANNECAPTAINSROOM_CAPTAIN = {
      { "check_flag", "EVENT_GOT_HM01" },                                 -- 1
      { "jump_if_true", 10 },                                             -- 2
      { "show_text", "_SSAnneCaptainsRoomRubCaptainsBackText" },          -- 3
      { "play_once", "Music_PkmnHealed" },                                -- 4
      { "show_text", "_SSAnneCaptainsRoomCaptainIFeelMuchBetterText" },   -- 5
      -- give-then-print like scripts/SSAnneCaptainsRoom.asm (GiveItem
      -- fills wStringBuffer; the received text reads it)
      { "give_item", "HM_CUT", 1, false },                                -- 6
      { "show_text", "_SSAnneCaptainsRoomCaptainReceivedHM01Text" },      -- 7
      { "set_flag", "EVENT_GOT_HM01" },                                   -- 8
      { "jump", 11 },                                                     -- 9
      { "show_text", "_SSAnneCaptainsRoomCaptainNotSickAnymoreText" },    -- 10
    },
  },
}

-- -------------------------------------------------------------------
-- Pokémon Tower / Poké Flute (scripts/PokemonTower7F.asm,
-- MrFujisHouse.asm; the teleport back to his house is a warp)
-- -------------------------------------------------------------------

-- scripts/PokemonTower7F.asm: after each Rocket loses,
-- PokemonTower7FEndBattleScript shows its EndBattle text (EndTrainerBattle),
-- prints its AfterBattle text (DisplayTextID), then
-- PokemonTower7FRocketLeaveMovementScript walks the grunt off toward the
-- (9,16) stairs (MoveSprite) and PokemonTower7FHideNPCScript despawns it
-- (HideObject).  Without this the beaten grunts stood in the corridor
-- forever (#200).
local POKEMON_TOWER_7F_ROCKETS = {
  { index = 1, name = "POKEMONTOWER7F_ROCKET1",
    beat = "EVENT_BEAT_POKEMONTOWER_7_TRAINER_0",
    after = "_PokemonTower7FRocket1AfterBattleText" },
  { index = 2, name = "POKEMONTOWER7F_ROCKET2",
    beat = "EVENT_BEAT_POKEMONTOWER_7_TRAINER_1",
    after = "_PokemonTower7FRocket2AfterBattleText" },
  { index = 3, name = "POKEMONTOWER7F_ROCKET3",
    beat = "EVENT_BEAT_POKEMONTOWER_7_TRAINER_2",
    after = "_PokemonTower7FRocket3AfterBattleText" },
}

-- PokemonTower7FNPCCoordMovementTable, keyed by the PLAYER's tile ("x,y")
-- at the engagement (both the talk and the sight walk-up leave the player on
-- the tile the vanilla table indexes).  Each list is that entry's
-- NPC_MOVEMENT_* exit, applied from the grunt's current tile.  The exact
-- tables are one per grunt (dbmapcoord bytes decoded back to x,y).
local POKEMON_TOWER_7F_EXITS = {
  [1] = { -- ROCKET1 @ (9,11), faces RIGHT
    ["9,12"]  = { "right", "down", "down", "down", "down", "down", "left" },
    ["10,11"] = { "down", "right", "down", "down", "down", "down" },
    ["11,11"] = { "down", "down", "down", "down", "down" },
    ["12,11"] = { "down", "down", "down", "down", "down" },
  },
  [2] = { -- ROCKET2 @ (12,9), faces LEFT
    ["12,10"] = { "left", "down", "down", "down", "down", "down", "down" },
    ["11,9"]  = { "down", "down", "down", "left", "down", "down" },
    ["10,9"]  = { "down", "down", "down", "down", "down" },
    ["9,9"]   = { "down", "down", "down", "down", "down" },
  },
  [3] = { -- ROCKET3 @ (9,7), faces RIGHT
    ["9,8"]  = { "right", "down", "down", "down", "down", "down", "down" },
    ["10,7"] = { "down", "down", "down", "down", "down" },
    ["11,7"] = { "down", "down", "down", "down", "down" },
    ["12,7"] = { "down", "down", "down", "down", "down" },
  },
}
-- The vanilla table only lists the sight/talk tiles the map geometry allows;
-- a plain down-walk keeps any other engagement tile (e.g. talking from the
-- side) safe -- it still clears the corridor and despawns the grunt.
local POKEMON_TOWER_7F_EXIT_FALLBACK =
  { "down", "down", "down", "down", "down" }

M.POKEMON_TOWER_7F = {
  -- Repair saves that beat a grunt before the exit walk was ported: in
  -- vanilla HideObject persists (wMissableObjectFlags), so a beaten grunt is
  -- still gone on re-entry.  hide_object below writes objectToggles for new
  -- wins; this hides any grunt whose BEAT flag is already set.
  onEnter = function(game, ow)
    local Commands = require("src.script.Commands")
    local ctx = { game = game, save = game.save, overworld = ow }
    for _, r in ipairs(POKEMON_TOWER_7F_ROCKETS) do
      if game.save.flags[r.beat] then
        Commands.hide_object(ctx, "POKEMON_TOWER_7F", r.name)
      end
    end
  end,
  -- runVictoryHook fires after every trainer win on the map (both the sight
  -- and talk paths route through engageTrainer -> checkVictoryRewards), so
  -- this walks off whichever grunt was just beaten but is still standing.
  -- The AfterBattle text + walk queue UNDER the EndBattle box engageTrainer
  -- pushes right after, giving the vanilla order: EndBattle, AfterBattle,
  -- walk, despawn.
  onVictory = function(game, ow)
    if ow.runner:isRunning() then return end
    for _, r in ipairs(POKEMON_TOWER_7F_ROCKETS) do
      local npc = ow:npcByIndex(r.index)
      if npc and game.save.flags[r.beat] then
        local key = ow.player.cellX .. "," .. ow.player.cellY
        local dirs = (POKEMON_TOWER_7F_EXITS[r.index] or {})[key]
                     or POKEMON_TOWER_7F_EXIT_FALLBACK
        ow.runner:run({
          { "show_text", r.after },                       -- DisplayTextID
          { "walk_npc", r.index, dirs },                  -- MoveSprite
          { "hide_object", "POKEMON_TOWER_7F", r.name },  -- HideObject
        }, { npc = npc })
        return
      end
    end
  end,
  talk = {
    TEXT_POKEMONTOWER7F_MR_FUJI = {
      { "face_player" },                                  -- 1
      { "show_text", "_PokemonTower7FMrFujiRescueText" }, -- 2
      { "set_flag", "EVENT_RESCUED_MR_FUJI" },            -- 3
      { "set_flag", "EVENT_RESCUED_MR_FUJI_2" },          -- 4
      -- pokered shows Fuji at home and swaps the Silph Co door
      -- guard (ROCKET8 on the door tile -> ROCKET9 beside it)
      { "show_object", "MR_FUJIS_HOUSE", "MRFUJISHOUSE_MR_FUJI" },   -- 5
      { "hide_object", "SAFFRON_CITY", "SAFFRONCITY_ROCKET8" },      -- 6
      { "show_object", "SAFFRON_CITY", "SAFFRONCITY_ROCKET9" },      -- 7
      -- pokered warps to wDestinationWarpID $1 (0-based) -- the house's
      -- SECOND warp, the door mat at (3,7) -- facing UP
      -- (PokemonTower7FWarpToMrFujiHouseScript: SPRITE_FACING_UP +
      -- hWarpDestinationMap MR_FUJIS_HOUSE). Landing (3,3) instead put
      -- the player at the Pokédex table, and the route's first waypoint
      -- (3,7) then stepped onto a LIVE door mat and exited the house
      -- before ever talking to Fuji -- so the POKE_FLUTE was never
      -- collected and the Route 16 SNORLAX sealed the map. The arrival
      -- mat itself is inert until stepped off (warpEntryCell), which is
      -- what makes the vanilla coordinates safe.
      { "warp", "MR_FUJIS_HOUSE", 3, 7, "up" },           -- 8
    },
  },
}

M.MR_FUJIS_HOUSE = {
  -- repair saves from before the rescue toggled him visible
  onEnter = function(game, ow)
    if game.save.flags.EVENT_RESCUED_MR_FUJI then
      local Commands = require("src.script.Commands")
      Commands.show_object({ game = game, save = game.save, overworld = ow },
                           "MR_FUJIS_HOUSE", "MRFUJISHOUSE_MR_FUJI")
    end
  end,
  talk = {
    TEXT_MRFUJISHOUSE_MR_FUJI = {
      { "face_player" },                                                -- 1
      { "check_flag", "EVENT_GOT_POKE_FLUTE" },                         -- 2
      { "jump_if_true", 12 },                                           -- 3
      { "check_flag", "EVENT_RESCUED_MR_FUJI" },                        -- 4
      { "jump_if_false", 14 },                                          -- 5
      { "show_text", "_MrFujisHouseMrFujiIThinkThisMayHelpYourQuestText" }, -- 6
      -- give-then-print like scripts/MrFujisHouse.asm
      { "give_item", "POKE_FLUTE", 1, false },                          -- 7
      { "show_text", "_MrFujisHouseMrFujiReceivedPokeFluteText" },      -- 8
      { "set_flag", "EVENT_GOT_POKE_FLUTE" },                           -- 9
      { "show_text", "_MrFujisHouseMrFujiPokeFluteExplanationText" },   -- 10
      { "jump", 15 },                                                   -- 11
      { "show_text", "_MrFujisHouseMrFujiHasMyFluteHelpedYouText" },    -- 12
      { "jump", 15 },                                                   -- 13
      { "show_text", "_MrFujisHouseMrFujiPokedexText" },                -- 14
    },
  },
}

-- -------------------------------------------------------------------
-- Snorlax (scripts/Route12.asm, Route16.asm)
-- -------------------------------------------------------------------

-- each route has its own strings (text/Route12.asm, text/Route16.asm;
-- Route 16's sleeping line is the unnamed _Route16Text7).  Talking to
-- Snorlax before it's beaten always just shows the sleeping line --
-- Route12DefaultScript/Route16DefaultScript only special-case
-- EVENT_FIGHT_ROUTEnn_SNORLAX, which ItemUsePokeFlute sets when the
-- player USES the POKé FLUTE from the item-use menu while standing next
-- to Snorlax (see ItemEffects.lua's POKE_FLUTE branch); merely talking
-- to it with the flute in the bag does nothing.  From the woke-up text
-- on, snorlaxWake below mirrors Route12DefaultScript's fight branch /
-- Route12SnorlaxPostBattleScript (scripts/Route12.asm, Route16.asm):
-- HideObject runs BEFORE the battle (so Snorlax is gone even after a
-- blackout), then the battle, then the calmed-down/returned line only
-- when it was NOT caught (`ld a, [wBattleResult] / cp $2` skips it),
-- and EVENT_BEAT_ROUTEnn_SNORLAX on any non-blackout result.
local function snorlaxWake(mapId, objName, beatFlag, wokeUpText, calmedText)
  return {
    { "show_text", wokeUpText },                    -- 1
    { "hide_object", mapId, objName },              -- 2 HideObject pre-battle
    { "static_battle", "SNORLAX", 30, beatFlag },   -- 3
    { "check_battle_result", "win", "run" },        -- 4 not caught, not blackout
    { "jump_if_false", 7 },                         -- 5 end (skip calmed-down)
    { "show_text", calmedText },                    -- 6
  }
end

-- A beaten Snorlax is gone for good: Route12/Route16DefaultScript run
-- HideObject in the same breath as the battle that sets
-- EVENT_BEAT_ROUTEnn_SNORLAX, so "event set, object still on the map" is a
-- state the asm cannot produce.  Here it can (a mod's world:toggleObject, a
-- save edited or migrated from a build older than the flag), and it is a
-- dead end: ItemEffects' adjacentSleepingSnorlax refuses to wake a Snorlax
-- whose beat flag is set (ItemUsePokeFlute's CheckEvent, engine/items/
-- item_effects.asm), so the sleeper sits in the road forever and Cycling
-- Road is unreachable (#585).  Reconcile the toggle from the flag on every
-- entry -- the mirror of SaveData.lua's toggle -> flag backfill, and the
-- same repair shape the Silph Co. floors use below.
local function hideBeatenSnorlax(mapId, objName, beatFlag)
  return function(game, ow)
    if not game.save.flags[beatFlag] then return end
    local Commands = require("src.script.Commands")
    Commands.hide_object({ game = game, save = game.save, overworld = ow },
                         mapId, objName)
  end
end

-- snorlaxWake is looked up by ItemEffects.lua/BagMenu.lua (via
-- data/scripts/init.lua's M.get) and run when the flute wakes Snorlax;
-- objName/beatFlag let ItemEffects find the NPC and check whether it's
-- already been beaten before allowing the wake.
M.ROUTE_12 = {
  talk = { TEXT_ROUTE12_SNORLAX = { { "show_text", "_Route12SnorlaxText" } } },
  onEnter = hideBeatenSnorlax("ROUTE_12", "ROUTE12_SNORLAX",
                              "EVENT_BEAT_ROUTE12_SNORLAX"),
  snorlaxWake = {
    objName = "ROUTE12_SNORLAX", beatFlag = "EVENT_BEAT_ROUTE12_SNORLAX",
    script = snorlaxWake("ROUTE_12", "ROUTE12_SNORLAX", "EVENT_BEAT_ROUTE12_SNORLAX",
                         "_Route12SnorlaxWokeUpText", "_Route12SnorlaxCalmedDownText"),
  },
}
M.ROUTE_16 = {
  talk = { TEXT_ROUTE16_SNORLAX = { { "show_text", "_Route16Text7" } } },
  onEnter = hideBeatenSnorlax("ROUTE_16", "ROUTE16_SNORLAX",
                              "EVENT_BEAT_ROUTE16_SNORLAX"),
  snorlaxWake = {
    objName = "ROUTE16_SNORLAX", beatFlag = "EVENT_BEAT_ROUTE16_SNORLAX",
    script = snorlaxWake("ROUTE_16", "ROUTE16_SNORLAX", "EVENT_BEAT_ROUTE16_SNORLAX",
                         "_Route16SnorlaxWokeUpText", "_Route16SnorlaxReturnedToMountainsText"),
  },
}

-- -------------------------------------------------------------------
-- Safari Zone HMs (scripts/SafariZoneSecretHouse.asm, WardensHouse.asm)
-- -------------------------------------------------------------------

M.SAFARI_ZONE_SECRET_HOUSE = {
  talk = {
    TEXT_SAFARIZONESECRETHOUSE_FISHING_GURU = {
      { "face_player" },                                                     -- 1
      { "check_flag", "EVENT_GOT_HM03" },                                    -- 2
      { "jump_if_true", 9 },                                                 -- 3
      { "show_text", "_SafariZoneSecretHouseFishingGuruYouHaveWonText" },    -- 4
      -- give-then-print like scripts/SafariZoneSecretHouse.asm
      { "give_item", "HM_SURF", 1, false },                                  -- 5
      { "show_text", "_SafariZoneSecretHouseFishingGuruReceivedHM03Text" },  -- 6
      { "set_flag", "EVENT_GOT_HM03" },                                      -- 7
      { "jump", 10 },                                                        -- 8
      { "show_text", "_SafariZoneSecretHouseFishingGuruHM03ExplanationText" }, -- 9
    },
  },
}

M.WARDENS_HOUSE = {
  talk = {
    TEXT_WARDENSHOUSE_WARDEN = {
      -- Labelled rather than hand-numbered: the branches here have been
      -- re-pointed twice now (#535, #645), and every insert used to mean
      -- renumbering three jumps that had no way of announcing they were stale.
      { "face_player" },                                             -- 1
      { "check_flag", "EVENT_GOT_HM04" },                            -- 2
      -- #535: previously jumped to the same silent-end target as the
      -- give-then-thank fallthrough, so the warden said nothing on every
      -- visit after the trade. pokered's .got_item branch
      -- (scripts/WardensHouse.asm) instead prints HM04ExplanationText.
      { "jump_if_true", "got_hm04" },                                -- 3
      { "check_item", "GOLD_TEETH" },                                -- 4
      { "jump_if_false", "no_teeth" },                               -- 5
      { "show_text", "_WardensHouseWardenGaveTheGoldTeethText" },    -- 6
      { "take_item", "GOLD_TEETH", 1 },                              -- 7
      { "set_flag", "EVENT_GAVE_GOLD_TEETH" },                       -- 8
      { "show_text", "_WardensHouseWardenThanksText" },              -- 9
      -- give-then-print like scripts/WardensHouse.asm
      { "give_item", "HM_STRENGTH", 1, false },                      -- 10
      { "show_text", "_WardensHouseWardenReceivedHM04Text" },        -- 11
      { "set_flag", "EVENT_GOT_HM04" },                              -- 12
      { "jump", "end" },                                             -- 13 (jp .done)

      -- #645: WardensHouseWardenText prints Gibberish1, then YesNoChoice,
      -- and the warden answers the same gibberish either way -- Gibberish2
      -- on yes, Gibberish3 on no (scripts/WardensHouse.asm).  The port
      -- printed the question and walked off before the answer.
      { "label", "no_teeth" },                                       -- 14
      { "ask", "_WardensHouseWardenGibberish1Text" },                -- 15
      { "jump_if_true", "gibberish_yes" },                           -- 16
      { "show_text", "_WardensHouseWardenGibberish3Text" },          -- 17
      { "jump", "end" },                                             -- 18
      { "label", "gibberish_yes" },                                  -- 19
      { "show_text", "_WardensHouseWardenGibberish2Text" },          -- 20
      { "jump", "end" },                                             -- 21

      -- #535: pokered .got_item branch (scripts/WardensHouse.asm) --
      -- printed on every subsequent talk once EVENT_GOT_HM04 is set.
      -- Text is _WardensHouseWardenHM04ExplanationText (text/WardensHouse.asm):
      -- HM04 teaches Strength, and hints at the Safari Zone secret house.
      { "label", "got_hm04" },                                       -- 22
      { "show_text", "_WardensHouseWardenHM04ExplanationText" },     -- 23
    },
  },
}

-- -------------------------------------------------------------------
-- Silph Co. president (scripts/SilphCo11F.asm; Giovanni there is the
-- generic OPP_GIOVANNI#2 battle)
-- -------------------------------------------------------------------

-- SilphCo11FTeamRocketLeavesScript (scripts/SilphCo11F.asm) hides every
-- ROCKET and rocket-aligned SCIENTIST toggle on 2F-11F the moment Giovanni
-- falls; the item balls, the 2F/10F rescued workers and the 7F rival keep
-- theirs.  Names and order are data/maps/toggleable_objects.asm's
-- TOGGLE_SILPH_CO_<floor>_n entries.  Saffron City's half of the same
-- script lives in M.SAFFRON_CITY (story4.lua) (#392).
local SILPH_ROCKET_OBJECTS = {
  { "SILPH_CO_2F",  { "SILPHCO2F_SCIENTIST1", "SILPHCO2F_SCIENTIST2",
                      "SILPHCO2F_ROCKET1", "SILPHCO2F_ROCKET2" } },
  { "SILPH_CO_3F",  { "SILPHCO3F_ROCKET", "SILPHCO3F_SCIENTIST" } },
  { "SILPH_CO_4F",  { "SILPHCO4F_ROCKET1", "SILPHCO4F_SCIENTIST",
                      "SILPHCO4F_ROCKET2" } },
  { "SILPH_CO_5F",  { "SILPHCO5F_ROCKET1", "SILPHCO5F_SCIENTIST",
                      "SILPHCO5F_ROCKER", "SILPHCO5F_ROCKET2" } },
  { "SILPH_CO_6F",  { "SILPHCO6F_ROCKET1", "SILPHCO6F_SCIENTIST",
                      "SILPHCO6F_ROCKET2" } },
  { "SILPH_CO_7F",  { "SILPHCO7F_ROCKET1", "SILPHCO7F_SCIENTIST",
                      "SILPHCO7F_ROCKET2", "SILPHCO7F_ROCKET3" } },
  { "SILPH_CO_8F",  { "SILPHCO8F_ROCKET1", "SILPHCO8F_SCIENTIST",
                      "SILPHCO8F_ROCKET2" } },
  { "SILPH_CO_9F",  { "SILPHCO9F_ROCKET1", "SILPHCO9F_SCIENTIST",
                      "SILPHCO9F_ROCKET2" } },
  { "SILPH_CO_10F", { "SILPHCO10F_ROCKET", "SILPHCO10F_SCIENTIST" } },
  { "SILPH_CO_11F", { "SILPHCO11F_GIOVANNI", "SILPHCO11F_ROCKET1",
                      "SILPHCO11F_ROCKET2" } },
}

-- hide_object writes save.objectToggles, so the single pass at the win
-- covers floors the player is not standing on; onlyMap is the per-floor
-- repair path below.
local function silphRocketsLeave(game, ow, onlyMap)
  local Commands = require("src.script.Commands")
  local ctx = { game = game, save = game.save, overworld = ow }
  for _, floor in ipairs(SILPH_ROCKET_OBJECTS) do
    if not onlyMap or onlyMap == floor[1] then
      for _, name in ipairs(floor[2]) do
        Commands.hide_object(ctx, floor[1], name)
      end
    end
  end
end

-- SilphCo11FGiovanniAfterBattleScript (scripts/SilphCo11F.asm) is the whole
-- aftermath: DisplayTextID TEXT_SILPHCO11F_GIOVANNI_YOU_RUINED_OUR_PLANS,
-- GBFadeOutToBlack, SilphCo11FTeamRocketLeavesScript, Delay3,
-- GBFadeInFromBlack, then SetEvent.  The port had only the hide pass, so the
-- speech never played and every rocket blinked out in front of the player
-- (#722).  Same hide list as silphRocketsLeave, spelled as script rows so the
-- fade can hold over it.
local function silphAftermathRows()
  local rows = {
    { "show_text", "_SilphCo11FGiovanniYouRuinedOurPlansText" },
    { "fade", "out" },
  }
  for _, floor in ipairs(SILPH_ROCKET_OBJECTS) do
    for _, name in ipairs(floor[2]) do
      rows[#rows + 1] = { "hide_object", floor[1], name }
    end
  end
  rows[#rows + 1] = { "wait", 3 }   -- Delay3
  rows[#rows + 1] = { "fade", "in" }
  return rows
end

M.SILPH_CO_11F = {
  -- Giovanni's battle is a COORDINATE TRIGGER, not a talk.
  -- SilphCo11FDefaultScript (scripts/SilphCo11F.asm) checks
  -- .PlayerCoordsArray -- (6,13) and (7,12) -- every frame while
  -- EVENT_BEAT_SILPH_CO_GIOVANNI is unset: standing there shows his text,
  -- walks him three tiles down (.GiovanniMovement), and starts the fight.
  -- He also has no trainer-header entry, so sight engagement never fires
  -- either. Without this hook he was a talk-only statue four tiles away
  -- from anything the route (or a vanilla-faithful player walking the same
  -- line) would touch, and the whole Silph ending -- the flag, the Master
  -- Ball, the Saffron streets clearing -- silently never happened.
  --
  -- SilphCo11FDefaultScript orders it DisplayTextID TEXT_SILPHCO11F_GIOVANNI
  -- FIRST, then MoveSprite .GiovanniMovement: he speaks from behind the desk
  -- and only then walks the three tiles down.  Moving him before the box made
  -- him cross the room in silence and deliver the speech point-blank (#869),
  -- so the box comes first here and engageTrainer skips its own battle text.
  -- victories.lua OPP_GIOVANNI#2 sets the event on a win; a loss sets
  -- nothing, so the trigger re-arms exactly as vanilla does.
  onStep = function(game, ow, x, y)
    if game.save.flags.EVENT_BEAT_SILPH_CO_GIOVANNI then return false end
    if not ((x == 6 and y == 13) or (x == 7 and y == 12)) then return false end
    local gio
    for _, npc in ipairs(ow.npcs) do
      if npc.def and npc.def.name == "SILPHCO11F_GIOVANNI" then gio = npc break end
    end
    if not gio or ow:trainerDefeated(gio) then return false end
    local TextBox = require("src.render.TextBox")
    game.stack:push(TextBox.new(game,
      game.data.text._SilphCo11FGiovanniText
      or "Ah {PLAYER}!\nSo we meet again!",
      function()
        ow:scriptMove(gio, "down", 3, function()
          gio:facePlayer(ow.player)
          ow:engageTrainer(gio, function()
            -- SilphCo11FGiovanniAfterBattleScript: the "Blast it all!"
            -- speech, then SilphCo11FTeamRocketLeavesScript behind a fade so
            -- every Silph rocket leaves off-screen (the street rockets are
            -- handled by M.SAFFRON_CITY.onEnter in story4.lua).  Queued, not
            -- run here: the battle's own callbacks are still unwinding, so
            -- queueScript starts it on the first idle overworld frame (#722).
            if game.save.flags.EVENT_BEAT_SILPH_CO_GIOVANNI then
              ow:queueScript(silphAftermathRows())
            end
          end,
          -- "Arrgh!!" is armed for the battle screen, not the map
          -- (scripts/SilphCo11F.asm:264-266 SaveEndBattleTextPointers) #1606
          game.data.text._SilphCo10FGiovanniILostAgainText, true)
        end)
      end))
    return true
  end,
  onEnter = function(game, ow)
    if game.save.flags.EVENT_BEAT_SILPH_CO_GIOVANNI then
      silphRocketsLeave(game, ow)
    end
  end,
  talk = {
    -- SilphCo11FSilphPresidentText branches on EVENT_GOT_MASTER_BALL only:
    -- the teleport pads reach him without passing Giovanni's trigger, and
    -- afterwards he describes the ball forever.  The old rows fell off the
    -- end of the script on both branches, so a second talk was silence
    -- (#392).
    TEXT_SILPHCO11F_SILPH_PRESIDENT = {
      { "face_player" },                                                     -- 1
      { "check_flag", "EVENT_GOT_MASTER_BALL" },                             -- 2
      { "jump_if_true", 9 },                                                 -- 3
      { "show_text", "_SilphCo11FSilphPresidentText" },                      -- 4
      -- give-then-print like scripts/SilphCo11F.asm
      { "give_item", "MASTER_BALL", 1, false },                              -- 5
      { "show_text", "_SilphCo11FSilphPresidentReceivedMasterBallText" },    -- 6
      { "set_flag", "EVENT_GOT_MASTER_BALL" },                               -- 7
      { "jump", "end" },                                                     -- 8
      { "show_text",
        "_SilphCo11FSilphPresidentMasterBallDescriptionText" },              -- 9
    },
  },
}

-- Floors 2F-10F carry no other onEnter, so this repairs saves that beat
-- Giovanni before the hide list existed (same shape as
-- M.POKEMON_TOWER_7F.onEnter); 11F hides its own inside the table above.
for _, floor in ipairs(SILPH_ROCKET_OBJECTS) do
  local mapId = floor[1]
  if mapId ~= "SILPH_CO_11F" then
    M[mapId] = M[mapId] or {}
    M[mapId].onEnter = function(game, ow)
      if game.save.flags.EVENT_BEAT_SILPH_CO_GIOVANNI then
        silphRocketsLeave(game, ow, mapId)
      end
    end
  end
end

-- -------------------------------------------------------------------
-- Victory Road boulder switches (scripts/VictoryRoad1F/2F/3F.asm):
-- a boulder resting on a switch removes a barrier block; the 3F hole
-- drops a boulder down to the 2F switch, and also dungeon-warps the
-- player (IsPlayerOnDungeonWarp + DungeonWarpList/Data -> 2F at 22,16).
-- -------------------------------------------------------------------

local function boulderAt(ow, x, y)
  local npc = ow:npcAtCell(x, y)
  return npc and npc.def.sprite == "SPRITE_BOULDER" and npc or nil
end

-- Each barrier is stamped BOTH ways on entry.  pokered only ever stamps the
-- OPEN block (ReplaceTileBlock edits the loaded block map, which the next map
-- load throws away, so a fresh entry always shows the .blk's closed barrier),
-- but OverworldState:replaceBlock writes through Map:setBlock into the SHARED
-- map record in Game.data, so the port has to put the closed block back
-- itself or a solved barrier stays open for the rest of the session (#258).
-- The closed ids are the shipped .blk bytes: VictoryRoad1F.blk (4,6) = $25,
-- VictoryRoad2F.blk (3,4) = $37 and (11,7) = $25, VictoryRoad3F.blk
-- (3,5) = $25.  Same both-ways pattern as the card-key doors in
-- OverworldState:setMap.
M.VICTORY_ROAD_1F = {
  onEnter = function(game, ow)
    ow:replaceBlock(4, 6,
      game.save.flags.EVENT_VICTORY_ROAD_1_BOULDER_ON_SWITCH and 0x1D or 0x25)
  end,
  onBoulderMoved = function(game, ow, npc)
    if npc.cellX == 17 and npc.cellY == 13
       and not game.save.flags.EVENT_VICTORY_ROAD_1_BOULDER_ON_SWITCH then
      game.save.flags.EVENT_VICTORY_ROAD_1_BOULDER_ON_SWITCH = true
      ow:replaceBlock(4, 6, 0x1D)
    end
  end,
}

M.VICTORY_ROAD_2F = {
  onEnter = function(game, ow)
    -- VictoryRoad2FResetBoulderEventScript (scripts/VictoryRoad2F.asm:19):
    -- entering 2F clears the 1F switch event, so 1F's barrier is closed
    -- again the next time you climb down (#258)
    game.save.flags.EVENT_VICTORY_ROAD_1_BOULDER_ON_SWITCH = nil
    ow:replaceBlock(3, 4,
      game.save.flags.EVENT_VICTORY_ROAD_2_BOULDER_ON_SWITCH1 and 0x15 or 0x37)
    ow:replaceBlock(11, 7,
      game.save.flags.EVENT_VICTORY_ROAD_2_BOULDER_ON_SWITCH2 and 0x1D or 0x25)
  end,
  onBoulderMoved = function(game, ow, npc)
    if npc.cellX == 1 and npc.cellY == 16
       and not game.save.flags.EVENT_VICTORY_ROAD_2_BOULDER_ON_SWITCH1 then
      game.save.flags.EVENT_VICTORY_ROAD_2_BOULDER_ON_SWITCH1 = true
      ow:replaceBlock(3, 4, 0x15)
    end
    if npc.cellX == 9 and npc.cellY == 16
       and not game.save.flags.EVENT_VICTORY_ROAD_2_BOULDER_ON_SWITCH2 then
      game.save.flags.EVENT_VICTORY_ROAD_2_BOULDER_ON_SWITCH2 = true
      ow:replaceBlock(11, 7, 0x1D)
    end
  end,
}

M.VICTORY_ROAD_3F = {
  onEnter = function(game, ow)
    ow:replaceBlock(3, 5,
      game.save.flags.EVENT_VICTORY_ROAD_3_BOULDER_ON_SWITCH1 and 0x1D or 0x25)
  end,
  onBoulderMoved = function(game, ow, npc)
    if npc.cellX == 3 and npc.cellY == 5
       and not game.save.flags.EVENT_VICTORY_ROAD_3_BOULDER_ON_SWITCH1 then
      game.save.flags.EVENT_VICTORY_ROAD_3_BOULDER_ON_SWITCH1 = true
      ow:replaceBlock(3, 5, 0x1D)
    end
    -- the hole at (23,15): the boulder drops to 2F next to switch 2.
    -- VictoryRoad3FDefaultScript .handle_hole gates the swap on
    -- CheckAndSetEvent EVENT_VICTORY_ROAD_3_BOULDER_ON_SWITCH2, then
    -- HideObject TOGGLE_VICTORY_ROAD_3F_BOULDER / ShowObject
    -- TOGGLE_VICTORY_ROAD_2F_BOULDER.  Those two toggles are
    -- VICTORYROAD3F_BOULDER4 and VICTORYROAD2F_BOULDER3
    -- (data/maps/toggleable_objects.asm); the old "VICTORYROAD2F_BOULDER"
    -- matched no object_event name, so the toggle landed under a key
    -- objectVisible never reads: harmless only while nothing hid that
    -- boulder, and fatal once Route 23's reset does (#258).
    if npc.cellX == 23 and npc.cellY == 15
       and not game.save.flags.EVENT_VICTORY_ROAD_3_BOULDER_ON_SWITCH2 then
      game.save.flags.EVENT_VICTORY_ROAD_3_BOULDER_ON_SWITCH2 = true
      local Commands = require("src.script.Commands")
      local ctx = { save = game.save, overworld = ow, game = game }
      Commands.hide_object(ctx, "VICTORY_ROAD_3F", npc.def.name)
      Commands.show_object(ctx, "VICTORY_ROAD_2F", "VICTORYROAD2F_BOULDER3")
    end
  end,
  -- scripts/VictoryRoad3F.asm VictoryRoad3FDefaultScript: the same hole
  -- is a dungeon warp for the player (wDungeonWarpDestinationMap =
  -- VICTORY_ROAD_2F, wWhichDungeonWarp = 2 -> DungeonWarpData 22,16).
  -- Mirrors POKEMON_MANSION_3F.onStep; CAVERN $22 is walkable so the
  -- fall is onStep, not a collision block.
  onStep = function(game, ow, x, y)
    if x == 23 and y == 15 then
      ow:fallThroughHole("VICTORY_ROAD_2F", 22, 16, ow.player.facing)
      return true
    end
    return false
  end,
}

-- -------------------------------------------------------------------
-- Champion (scripts/ChampionsRoom.asm): rival with the Rival3 party for
-- your starter, then Oak's congratulations (Hall of Fame-lite).
-- -------------------------------------------------------------------

-- The battle gate is the run-scoped EVENT_BEAT_CHAMPION_RIVAL_THIS_RUN,
-- cleared by the Indigo lobby's Elite Four reset (scripts/
-- IndigoPlateauLobby.asm) so the champion is re-fightable on rematches,
-- like pokered's re-entry cutscene.  EVENT_BEAT_CHAMPION_RIVAL stays set
-- forever (postgame gates like the Cerulean cave guard read it).
--
-- pokered forces the fight on map entry: Agatha's victory arms
-- SCRIPT_CHAMPIONSROOM_PLAYER_ENTERS (scripts/AgathasRoom.asm), and
-- ChampionsRoomPlayerEntersScript then runs RivalEntrance_RLEMovement
-- (up 1, right 1, up 3) before ChampionsRoomRivalReadyToBattleScript.
-- The rival object has no trainer header / sight range, so without that
-- entrance script the player can walk past (issue #99).  We arm on the
-- run flag instead of Agatha's victory bit: same observable effect for
-- first clear and Indigo rematches, without a cross-map script pointer.
--
-- scripts/ChampionsRoom.asm ChampionsRoomRivalDefeatedScript ->
-- OakArrivesScript -> OakCongratulatesPlayerScript ->
-- OakDisappointedWithRivalScript -> OakComeWithMeScript -> OakExitsScript,
-- then the simulated walk up-and-left into the HALL_OF_FAME warp
-- (PlayerFollowsOakScript / WalkToHallOfFame_RLEMovement).  The induction
-- itself is NOT run here: it belongs to the HALL_OF_FAME room script
-- (scripts/HallOfFame.asm), so we set a one-shot marker and warp; the room
-- onEnter (M.HALL_OF_FAME below) drives the HoF Oak speech + record.
local championsRoomRivalScript = {
  { "face_player" },                                        -- 1
  { "check_flag", "EVENT_BEAT_CHAMPION_RIVAL_THIS_RUN" },   -- 2
  -- "end" rather than a row number past the tail: this script grew by a row
  -- when the follow-Oak walk landed (#704), which silently turned the old
  -- numeric 26 into a jump ONTO the closing HALL_OF_FAME warp instead of past
  -- it, so a returning champion warped straight into the induction.
  { "jump_if_true", "end" },                                -- 3
  { "set_option", "animations", true },                     -- scripts/ChampionsRoom.asm:57
  { "show_text", "_ChampionsRoomRivalIntroText" },          -- 4
  -- ChampionsRoomRivalReadyToBattleScript plays MUSIC_FINAL_BATTLE after
  -- the intro text, before the battle itself (#706); pushBattle's wipe-time
  -- playBattle("final") then no-ops on the same song, so the theme stays
  -- continuous into the fight
  { "play_music", "Music_FinalBattle" },                    -- 5
  { "rival_battle", "OPP_RIVAL3", 1 },                      -- 6
  -- losing halts here; the numeric target this replaced pointed at the
  -- closing warp, which inducted a player who had just lost the fight (#704)
  { "jump_if_false", "end" },                               -- 7
  { "set_flag", "EVENT_BEAT_CHAMPION_RIVAL_THIS_RUN" },     -- 8
  { "set_flag", "EVENT_BEAT_CHAMPION_RIVAL" },              -- 9
  -- ChampionsRoomRivalDefeatedScript re-displays TEXT_CHAMPIONSROOM_RIVAL,
  -- whose text_asm takes the EVENT_BEAT_CHAMPION_RIVAL branch =
  -- _ChampionsRoomRivalAfterBattleText (the in-battle _RivalDefeatedText
  -- is the port's generic "<PLAYER> defeated BLUE!" engine line instead).
  { "show_text", "_ChampionsRoomRivalAfterBattleText" },    -- 10
  -- ChampionsRoomOakArrivesScript: Music_Cities1AlternateTempo
  -- (Cities1, kept into HALL_OF_FAME like BIT_NO_MAP_MUSIC after
  -- defeating RIVAL3), then Oak's "{PLAYER}!" + reveal + walk in.
  -- audio/alternate_tempo.asm Music_Cities1AlternateTempo is not a plain
  -- PlayMusic: it fades the current song out (wAudioFadeOutControl = 10),
  -- waits 100 frames for the fade, then restarts Cities1 with channel 1
  -- pointed at Music_Cities1_Ch1_AlternateTempo -- `tempo 232` where the
  -- normal Music_Cities1_Ch1 opens `tempo 144`, i.e. the slower, heavier
  -- reading of the town theme this scene is known for (#847).
  { "fade_music", 10 },                                     -- 11
  { "wait", 100 },                                          -- 12
  { "play_music", "Music_Cities1", { keep = true, tempo = 232 } }, -- 13
  { "show_text", "_ChampionsRoomOakText" },                 -- 14
  { "show_object", "CHAMPIONS_ROOM", "CHAMPIONSROOM_OAK" },  -- 15
  { "move_npc", 2, "up", 5 },                               -- 16 OakEntranceAfterVictoryMovement
  -- OakCongratulatesPlayerScript: rival faces left, Oak faces down
  { "face_object", 1, "left" },                             -- 17
  { "face_object", 2, "down" },                             -- 18
  { "load_player_starter_name" },
  { "show_text", "_ChampionsRoomOakCongratulatesPlayerText" }, -- 19
  -- OakDisappointedWithRivalScript: Oak turns to the rival (right)
  { "face_object", 2, "right" },                            -- 20
  { "show_text", "_ChampionsRoomOakDisappointedWithRivalText" }, -- 21
  -- OakComeWithMeScript: Oak faces down again, then exits up
  { "face_object", 2, "down" },                             -- 22
  { "show_text", "_ChampionsRoomOakComeWithMeText" },       -- 23
  { "move_npc", 2, "up", 2 },                               -- 24 OakExitChampionsRoomMovement
  { "hide_object", "CHAMPIONS_ROOM", "CHAMPIONSROOM_OAK" },  -- 25
  -- scripts/ChampionsRoom.asm WalkToHallOfFame_RLEMovement
  { "move_player", "left", 1 },
  { "move_player", "up", 3 },                               -- 27
  -- hand the induction off to the HALL_OF_FAME room (consumed by its
  -- onEnter), then warp up into it (destWarp 1 lands at (4,7) facing up)
  { "set_field", "pendingHallOfFame", true },               -- 28
  { "warp", "HALL_OF_FAME", 4, 7, "up" },                   -- 29
}

M.CHAMPIONS_ROOM = {
  onEnter = function(game, ow)
    if game.save.flags.EVENT_BEAT_CHAMPION_RIVAL_THIS_RUN then return end
    -- Lance entrance warps land at y=7; HoF return warps land at y=0.
    -- Only the south entry should run ChampionsRoomPlayerEntersScript.
    if ow.player.cellY < 7 then return end
    local rival
    for _, npc in ipairs(ow.npcs) do
      if npc.def and npc.def.name == "CHAMPIONSROOM_RIVAL" then
        rival = npc
        break
      end
    end
    -- RivalEntrance_RLEMovement, then the battle/Oak script (queued
    -- separately so talk-script jump indices stay 1-based as written).
    ow:queueScript({
      { "move_player", "up", 1 },
      { "move_player", "right", 1 },
      { "move_player", "up", 3 },
    })
    ow:queueScript(championsRoomRivalScript, { npc = rival })
  end,
  talk = {
    TEXT_CHAMPIONSROOM_RIVAL = championsRoomRivalScript,
  },
}

-- -------------------------------------------------------------------
-- Hall of Fame (scripts/HallOfFame.asm): the induction's entry point is
-- the ROOM, not the Champions Room script.  HallOfFameDefaultScript walks
-- the player up 5 into Oak (HallOfFameEntryMovement), then
-- HallOfFameOakCongratulationsScript turns them face-to-face, shows
-- _HallOfFameOakText, hides Oak (predef HideObject) and runs
-- HallOfFameResetEventsAndSaveScript's predef HallOfFamePC (the induction +
-- credits, here Commands.record_hall_of_fame).
--
-- onEnter fires DURING the Champions Room warp's setMap, while that warp
-- command's runner is still suspended-alive (yielded at the warp), so we
-- cannot start a runner here directly (ScriptRunner:run asserts the runner
-- is idle).  Instead we QUEUE the cutscene: OverworldState:update drains
-- self.pendingScript once the warp's transition has finished and its runner
-- has gone dead, so the room cutscene begins a frame after the warp fully
-- completes.  The one-shot save.pendingHallOfFame marker (set by the
-- Champions Room script) is consumed here so re-entering the room later
-- does not replay the induction.
M.HALL_OF_FAME = {
  onEnter = function(game, ow)
    -- self-heal saves poisoned by a prior version of this script, which
    -- wrongly hid Oak here instead of the Cerulean Cave guard (see
    -- CERULEAN_CITY onEnter, which handles the real HideObject target)
    local toggles = game.save.objectToggles and game.save.objectToggles.HALL_OF_FAME
    if toggles then toggles.HALLOFFAME_OAK = nil end

    -- Make the Hall of Fame recording machine interactable.  The console
    -- juts from the north wall as the two solid cells (4,1) and (5,1); a
    -- sign on each lets the player face the machine (from below, or from
    -- either side) and press A to run the TEXT_HALLOFFAME_PC talk script.
    -- maps.lua is generated from the ROM and gitignored, so the sign is
    -- injected here (a tracked script) rather than baked into map data.
    local def = ow.map.def
    def.signs = def.signs or {}
    local present = false
    for _, s in ipairs(def.signs) do
      if s.text == "TEXT_HALLOFFAME_PC" then present = true break end
    end
    if not present then
      table.insert(def.signs, { text = "TEXT_HALLOFFAME_PC", x = 4, y = 1 })
      table.insert(def.signs, { text = "TEXT_HALLOFFAME_PC", x = 5, y = 1 })
    end
    -- the live Map instance built its signAt lookup from def.signs before
    -- this hook ran, so rebuild it (idempotent) to pick up the injection
    ow.map.signAt = {}
    for _, s in ipairs(def.signs) do
      ow.map.signAt[s.y * ow.map.widthCells + s.x] = s
    end

    if not game.save.pendingHallOfFame then return end
    game.save.pendingHallOfFame = false
    ow:queueScript({
      { "move_player", "up", 5 },                      -- (4,7)->(4,2) beside Oak (5,2)
      { "face_object", 1, "left" },                    -- HALLOFFAME_OAK faces the player
      { "face_player_dir", "right" },                  -- player faces Oak (PLAYER_DIR_RIGHT)
      { "show_text", "_HallOfFameOakText" },           -- TEXT_HALLOFFAME_OAK
      -- HallOfFameOakCongratulationsScript hides TOGGLE_CERULEAN_CAVE_GUY
      -- here, not Oak; that's handled separately by CERULEAN_CITY onEnter
      -- gating on EVENT_BEAT_CHAMPION_RIVAL
      { "record_hall_of_fame" },                       -- predef HallOfFamePC: induction + credits
    })
  end,
  talk = {
    -- The recording machine doubles as a "warp home" PC: a YES/NO prompt
    -- that teleports back to the new-game bedroom spawn (special_warps.asm
    -- NewGameWarp: REDS_HOUSE_2F, 3, 6, facing down).  Fabricated
    -- convenience -- there is no such prompt in the original ROM.
    -- Heal + remember_outdoor so house LAST_MAP mats land in Pallet, not
    -- Indigo Plateau (issue #103 escape path for already-stuck saves).
    TEXT_HALLOFFAME_PC = {
      { "ask", "Return to\nPALLET TOWN?" },             -- 1  YES/NO -> lastCheck
      { "jump_if_false", "end" },                       -- 2  NO: back away
      { "heal_party" },                                 -- 3
      { "remember_outdoor", "PALLET_TOWN", 5, 6 },       -- 4  LAST_MAP -> Pallet door
      { "warp", "REDS_HOUSE_2F", 3, 6, "down" },        -- 5  YES: home to your room
    },
  },
}

-- -------------------------------------------------------------------
-- Mid-game rival battles (scripts/CeruleanCity.asm, PokemonTower2F.asm);
-- Rival1 parties 7-9 are the Cerulean set, Rival2 parties 4-6 the Tower
-- set (data/trainers/parties.asm)
-- -------------------------------------------------------------------

M.CERULEAN_CITY = {
  talk = {
    -- CeruleanCityRivalText: Bill line once beaten; pre-battle otherwise.
    -- Post-fight walk matches CeruleanCityMovement4 (right then into town).
    TEXT_CERULEANCITY_RIVAL = {
      { "face_player" },
      { "check_flag", "EVENT_BEAT_CERULEAN_RIVAL" },
      { "jump_if_true", "beaten" },
      { "show_text", "_CeruleanCityRivalPreBattleText" },
      -- SaveEndBattleTextPointers (scripts/CeruleanCity.asm:141)
      { "save_end_battle_text", "_CeruleanCityRivalDefeatedText" },
      { "rival_battle", "OPP_RIVAL1", 7 },
      { "jump_if_false", "end" },
      { "set_flag", "EVENT_BEAT_CERULEAN_RIVAL" },
      { "show_text", "_CeruleanCityRivalIWentToBillsText" },
      { "walk_npc", 1, { "right", "down", "down", "down",
                         "down", "down", "down" } },
      { "hide_object", "CERULEAN_CITY", "CERULEANCITY_RIVAL" },
      { "jump", "end" },
      { "label", "beaten" },
      { "show_text", "_CeruleanCityRivalIWentToBillsText" },
    },
  },
}

-- PokemonTower2F.asm: after the battle, PokemonTower2FDefeatedRivalScript
-- walks him out (RightThenDown vs DownThenRight from EVENT_POKEMON_TOWER_
-- RIVAL_ON_LEFT) then HideObject TOGGLE_POKEMON_TOWER_2F_RIVAL.  Player
-- at (15,5) is the ON_LEFT case.
local TOWER_RIVAL_EXIT_RIGHT_THEN_DOWN =
  { "right", "down", "down", "right", "down", "down", "right", "right" }
local TOWER_RIVAL_EXIT_DOWN_THEN_RIGHT =
  { "down", "down", "right", "right", "right", "right", "down", "down" }

local function pokemonTower2FRivalScript(playerX)
  local exitDirs = (playerX == 15)
    and TOWER_RIVAL_EXIT_DOWN_THEN_RIGHT
    or TOWER_RIVAL_EXIT_RIGHT_THEN_DOWN
  return {
    { "face_player" },
    { "check_flag", "EVENT_BEAT_POKEMON_TOWER_RIVAL" },
    { "jump_if_true", "beaten" },
    { "show_text", "_PokemonTower2FRivalWhatBringsYouHereText" },
    -- .DefeatedText rides BIT_PRINT_END_BATTLE_TEXT, so it prints on the
    -- battle screen -- scripts/PokemonTower2F.asm:145-150
    { "save_end_battle_text", "_PokemonTower2FRivalDefeatedText" },
    { "rival_battle", "OPP_RIVAL2", 4 },
    { "jump_if_false", "end" },                                   -- loss: stay
    { "set_flag", "EVENT_BEAT_POKEMON_TOWER_RIVAL" },
    -- the win re-runs DisplayTextID on the beaten branch
    -- scripts/PokemonTower2F.asm:72-75, :137-140
    { "show_text", "_PokemonTower2FRivalHowsYourDexText" },
    { "play_music", "Music_MeetRival", { start = "rival" } },
    { "walk_npc", 1, exitDirs },
    { "hide_object", "POKEMON_TOWER_2F", "POKEMONTOWER2F_RIVAL" },
    { "play_default_music" },              -- scripts/PokemonTower2F.asm:124
    { "jump", "end" },
    { "label", "beaten" },
    { "show_text", "_PokemonTower2FRivalHowsYourDexText" },
  }
end

M.POKEMON_TOWER_2F = {
  rivalScript = pokemonTower2FRivalScript,
  talk = {
    TEXT_POKEMONTOWER2F_RIVAL = function(game, ow, npc, done)
      ow.runner:run(pokemonTower2FRivalScript(ow.player.cellX),
                    { npc = npc, onDone = done })
    end,
  },
  -- Saves that beat him before the exit walk was ported still have the
  -- flag but a visible rival; hide on enter like BillsHouse repairs.
  onEnter = function(game, ow)
    if not game.save.flags.EVENT_BEAT_POKEMON_TOWER_RIVAL then return end
    local Commands = require("src.script.Commands")
    Commands.hide_object({ game = game, save = game.save, overworld = ow },
                         "POKEMON_TOWER_2F", "POKEMONTOWER2F_RIVAL")
  end,
  -- PokemonTower2FDefaultScript: walking past the rival's tile forces
  -- the encounter (ArePlayerCoordsInArray on (15,5)/(14,6)) -- he never
  -- waits to be talked to
  onStep = function(game, ow, x, y)
    if game.save.flags.EVENT_BEAT_POKEMON_TOWER_RIVAL then return false end
    if not ((x == 15 and y == 5) or (x == 14 and y == 6)) then return false end
    if ow.runner:isRunning() then return false end
    local rival = ow:npcByIndex(1)
    if not rival then return false end
    ow.player.facing = (x == 15) and "left" or "up"
    require("src.core.Music").play(game.data, "Music_MeetRival")
    ow.runner:run(pokemonTower2FRivalScript(x), { npc = rival })
    return true
  end,
}

-- -------------------------------------------------------------------
-- In-game trades (data/events/trades.asm; the NPC<->trade mapping is
-- from each map's DoInGameTradeDialogue call)
-- -------------------------------------------------------------------

M.ROUTE_2_TRADE_HOUSE = {
  talk = {
    -- The Scientist is plain flavor; the Game Boy Kid holds the trade
    -- (data/scripts/flavor/route_2_trade_house.lua), per Route2TradeHouse.asm.
    TEXT_ROUTE2TRADEHOUSE_SCIENTIST = {
      { "face_player" },
      { "show_text", "_Route2TradeHouseScientistText" },
    },
  },
}

M.CERULEAN_TRADE_HOUSE = {
  talk = {
    -- The Granny is plain flavor (points you to her husband); the Gambler
    -- holds the trade (data/scripts/flavor/cerulean_trade_house.lua), per
    -- CeruleanTradeHouse.asm.
    TEXT_CERULEANTRADEHOUSE_GRANNY = {
      { "face_player" },
      { "show_text", "_CeruleanTradeHouseGrannyText" },
    },
  },
}

M.VERMILION_TRADE_HOUSE = {
  talk = {
    TEXT_VERMILIONTRADEHOUSE_LITTLE_GIRL = {
      { "face_player" },
      { "trade", 5, "EVENT_TRADED_SPEAROW_FOR_FARFETCHD" }, -- DUX
    },
  },
}

return M
