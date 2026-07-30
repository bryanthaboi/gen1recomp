-- Jessie & James, Yellow's Team Rocket duo, at all four ambush sites:
-- Mt Moon B2F (scripts/MtMoonB2F.asm), Rocket Hideout B4F
-- (scripts/RocketHideoutB4F.asm), Pokemon Tower 7F
-- (scripts/PokemonTower7F.asm) and Silph Co 11F (scripts/SilphCo11F.asm).
-- Every site shares one shape: a coordinate trigger swaps the map theme
-- for Music_MeetJessieJames, the motto plays, the duo closes in, one
-- battle against the shared OPP_ROCKET party fights them both, and after
-- their parting lines they vanish together under a second sting of the
-- theme before the map theme resumes (PlayDefaultMusic ->
-- play_default_music).
--
-- Registered on top of the shared tables by data/scripts/init.lua on a
-- Yellow boot; MT_MOON_B2F's onStep chains story2's Super Nerd / fossil
-- trigger and SILPH_CO_11F's chains story's Giovanni trigger, since
-- non-talk hooks replace rather than merge.

local M = {}

-- Capture the FUNCTION, not the table: attachBase stores the module
-- table itself, so once this file's onStep is attached the table's slot
-- points back here -- delegating through the table would self-recurse.
local baseMtMoonStep = require("data.scripts.story2").MT_MOON_B2F.onStep
local baseSilph11Step = require("data.scripts.story").SILPH_CO_11F.onStep

M.MT_MOON_B2F = {
  talk = {
    TEXT_MTMOONB2F_JESSIE = {
      { "face_player" }, { "show_text", "_MtMoonJessieJamesText1" },
    },
    TEXT_MTMOONB2F_JAMES = {
      { "face_player" }, { "show_text", "_MtMoonJessieJamesText1" },
    },
  },

  onStep = function(game, ow, x, y)
    if baseMtMoonStep and baseMtMoonStep(game, ow, x, y) then
      return true
    end
    local f = game.save.flags
    if x ~= 3 or y ~= 5 then return false end
    if f.EVENT_BEAT_MT_MOON_3_JESSIE_JAMES then return false end
    if not (f.EVENT_GOT_DOME_FOSSIL or f.EVENT_GOT_HELIX_FOSSIL) then
      return false
    end
    ow.runner:run({
      { "stop_music" },
      { "play_music", "Music_MeetJessieJames" },
      { "show_object", "MT_MOON_B2F", "MTMOONB2F_JESSIE" },
      { "show_object", "MT_MOON_B2F", "MTMOONB2F_JAMES" },
      { "show_text", "_MtMoonJessieJamesText1" },
      { "face_player_dir", "up" },
      { "emote", "player", "shock", 30 },
      -- MtMoonB2FScript_49e15 simulates PAD_UP for one player step, then
      -- Script6/Script9 walk Jessie (object 2, MovementData_f9e65: six
      -- $06) and James (object 6, f9e66: five $06); both objects' movement
      -- byte 2 is LEFT, so .determineDirection makes those LEFT steps --
      -- Jessie (9,3)->(3,3) above the player at (3,4), James (9,4)->(4,4)
      -- beside him. #423
      { "walk_npc", "player", { "up" } },
      { "walk_npc", 2, { "left", "left", "left", "left", "left", "left" } },
      { "face_object", 2, "down" },
      { "walk_npc", 6, { "left", "left", "left", "left", "left" } },
      { "face_object", 6, "left" },
      { "show_text", "_MtMoonJessieJamesText2" },
      { "start_battle", "trainer", "OPP_ROCKET", 42 },
      { "check_battle_result", "win" },
      { "jump_if_false", "end" },
      { "show_text", "_MtMoonJessieJamesText3" },
      { "show_text", "_MtMoonJessieJamesText4" },
      { "stop_music" },
      { "play_music", "Music_MeetJessieJames" },
      { "fade", "out" },
      { "hide_object", "MT_MOON_B2F", "MTMOONB2F_JESSIE" },
      { "hide_object", "MT_MOON_B2F", "MTMOONB2F_JAMES" },
      { "fade", "in" },
      { "play_default_music" },
      { "set_flag", "EVENT_BEAT_MT_MOON_3_JESSIE_JAMES" },
    }, {})
    return true
  end,
}

-- -------------------------------------------------------------------
-- Rocket Hideout B4F (RocketHideoutB4FScript_455a5..Script13): the
-- motto plays from off-screen FIRST, then the duo pops in at (25,10) /
-- (24,10) and whichever of them shares the player's column ($18=24 or
-- $19=25, EVENT_ROCKET_HIDEOUT_4_JESSIE_JAMES_ON_LEFT) walks the three
-- tiles down to loom over the player while the other steps one.  A loss
-- re-hides them (RocketHideoutB4FResetScripts via EVENT_6A0), so the
-- trigger re-arms clean.
-- -------------------------------------------------------------------

M.ROCKET_HIDEOUT_B4F = {
  talk = {
    TEXT_ROCKETHIDEOUTB4F_JESSIE = {
      { "face_player" }, { "show_text", "_RocketHideoutJessieJamesText1" },
    },
    TEXT_ROCKETHIDEOUTB4F_JAMES = {
      { "face_player" }, { "show_text", "_RocketHideoutJessieJamesText1" },
    },
  },

  onStep = function(game, ow, x, y)
    local f = game.save.flags
    if y ~= 14 or (x ~= 24 and x ~= 25) then return false end
    if f.EVENT_BEAT_ROCKET_HIDEOUT_4_JESSIE_JAMES then return false end
    -- ON_LEFT: player under James's column (25); movement data pairs
    -- RocketHideoutB4FJessieJamesMovementData_45605/45606 swap so the
    -- column-mate walks 3, the other 1.
    local onLeft = (x == 25)
    ow.runner:run({
      { "stop_music" },
      { "play_music", "Music_MeetJessieJames" },
      { "show_text", "_RocketHideoutJessieJamesText1" },
      { "face_player_dir", "up" },
      { "emote", "player", "shock", 30 },
      { "show_object", "ROCKET_HIDEOUT_B4F", "ROCKETHIDEOUTB4F_JAMES" },
      { "show_object", "ROCKET_HIDEOUT_B4F", "ROCKETHIDEOUTB4F_JESSIE" },
      -- James (object 2) then Jessie (object 3), Script4..Script9 order
      { "walk_npc", 2, onLeft and { "down", "down", "down" } or { "down" } },
      { "face_object", 2, onLeft and "down" or "left" },
      { "walk_npc", 3, onLeft and { "down" } or { "down", "down", "down" } },
      { "face_object", 3, onLeft and "right" or "down" },
      { "show_text", "_RocketHideoutJessieJamesText2" },
      { "start_battle", "trainer", "OPP_ROCKET", 43 },
      { "check_battle_result", "win" },
      { "jump_if_false", "lost" },
      { "show_text", "_RocketHideoutJessieJamesText3" },
      { "show_text", "_RocketHideoutJessieJamesText4" },
      { "stop_music" },
      { "play_music", "Music_MeetJessieJames" },
      { "fade", "out" },
      { "hide_object", "ROCKET_HIDEOUT_B4F", "ROCKETHIDEOUTB4F_JAMES" },
      { "hide_object", "ROCKET_HIDEOUT_B4F", "ROCKETHIDEOUTB4F_JESSIE" },
      { "fade", "in" },
      { "play_default_music" },
      { "set_flag", "EVENT_BEAT_ROCKET_HIDEOUT_4_JESSIE_JAMES" },
      { "jump", "end" },
      { "label", "lost" },
      { "hide_object", "ROCKET_HIDEOUT_B4F", "ROCKETHIDEOUTB4F_JAMES" },
      { "hide_object", "ROCKET_HIDEOUT_B4F", "ROCKETHIDEOUTB4F_JESSIE" },
    }, {})
    return true
  end,
}

-- -------------------------------------------------------------------
-- Pokemon Tower 7F (PokemonTower7FScript_60d2a..Script10): same beat
-- one floor below Fuji, except the duo pops in BEFORE the motto and
-- Jessie ($a=10 column) leads the walk-down; ON_LEFT ($b=11) hands the
-- three-tile walk to James instead.  On a loss vanilla only resets the
-- script counter (the blackout warp reloads the map anyway).
-- -------------------------------------------------------------------

M.POKEMON_TOWER_7F = {
  talk = {
    TEXT_POKEMONTOWER7F_JESSIE = {
      { "face_player" }, { "show_text", "_PokemonTowerJessieJamesText1" },
    },
    TEXT_POKEMONTOWER7F_JAMES = {
      { "face_player" }, { "show_text", "_PokemonTowerJessieJamesText1" },
    },
  },

  onStep = function(game, ow, x, y)
    local f = game.save.flags
    if y ~= 12 or (x ~= 10 and x ~= 11) then return false end
    if f.EVENT_BEAT_POKEMONTOWER_7_JESSIE_JAMES then return false end
    local onLeft = (x == 11)   -- EVENT_POKEMONTOWER_7_JESSIE_JAMES_ON_LEFT
    ow.runner:run({
      { "stop_music" },
      { "play_music", "Music_MeetJessieJames" },
      { "show_object", "POKEMON_TOWER_7F", "POKEMONTOWER7F_JESSIE" },
      { "show_object", "POKEMON_TOWER_7F", "POKEMONTOWER7F_JAMES" },
      { "show_text", "_PokemonTowerJessieJamesText1" },
      { "face_player_dir", "up" },
      { "emote", "player", "shock", 30 },
      -- Jessie (object 1) then James (object 2), Script1..Script6 order
      { "walk_npc", 1, onLeft and { "down" } or { "down", "down", "down" } },
      { "face_object", 1, onLeft and "right" or "down" },
      { "walk_npc", 2, onLeft and { "down", "down", "down" } or { "down" } },
      { "face_object", 2, onLeft and "down" or "left" },
      { "show_text", "_PokemonTowerJessieJamesText2" },
      { "start_battle", "trainer", "OPP_ROCKET", 44 },
      { "check_battle_result", "win" },
      { "jump_if_false", "end" },
      { "show_text", "_PokemonTowerJessieJamesText3" },
      { "show_text", "_PokemonTowerJessieJamesText4" },
      { "stop_music" },
      { "play_music", "Music_MeetJessieJames" },
      { "fade", "out" },
      { "hide_object", "POKEMON_TOWER_7F", "POKEMONTOWER7F_JESSIE" },
      { "hide_object", "POKEMON_TOWER_7F", "POKEMONTOWER7F_JAMES" },
      { "fade", "in" },
      { "play_default_music" },
      { "set_flag", "EVENT_BEAT_POKEMONTOWER_7_JESSIE_JAMES" },
    }, {})
    return true
  end,
}

-- -------------------------------------------------------------------
-- Silph Co 11F (SilphCo11FScript_6229c..Script14): the only site where
-- the duo starts VISIBLE (toggleable_objects.asm keeps SILPHCO11F_JAMES
-- / _JESSIE ON), flanking Giovanni at (2,8)/(3,8), so they are talkable
-- before the ambush (SilphCo11FJessieJamesText = the full motto).  The
-- trigger is the top row (y=3, x<4); EVENT_780/EVENT_781 pick one of
-- three approach paths (SilphCo11FMovementData_622f5..62311, $5=up
-- $6=left) that route James then Jessie up to the player without ever
-- crossing the player's tile.  Their duo text lives in
-- text/SilphCo10F.asm (_SilphCoJessieJamesText*).
-- -------------------------------------------------------------------

M.SILPH_CO_11F = {
  talk = {
    TEXT_SILPHCO11F_JESSIE = {
      { "face_player" }, { "show_text", "_SilphCoJessieJamesText1" },
    },
    TEXT_SILPHCO11F_JAMES = {
      { "face_player" }, { "show_text", "_SilphCoJessieJamesText1" },
    },
  },

  onStep = function(game, ow, x, y)
    if baseSilph11Step and baseSilph11Step(game, ow, x, y) then
      return true
    end
    local f = game.save.flags
    if y ~= 3 or x > 3 then return false end
    if f.EVENT_BEAT_SILPH_CO_11F_JESSIE_JAMES then return false end
    -- x==3 -> base path, x==2 -> EVENT_780 variant, x<=1 -> EVENT_781
    local jamesDirs, jamesFace, jessieDirs, jessieFace
    if x == 3 then
      jamesDirs, jamesFace = { "up", "up", "up", "up", "up" }, "right"
      jessieDirs, jessieFace = { "up", "up", "up", "up" }, "up"
    elseif x == 2 then
      jamesDirs, jamesFace = { "up", "up", "up", "up" }, "up"
      jessieDirs, jessieFace = { "up", "up", "up", "up", "up" }, "left"
    else
      jamesDirs = { "up", "up", "left", "up", "up" }
      jamesFace = "up"
      jessieDirs = { "up", "up", "up", "left", "up", "up" }
      jessieFace = "left"
    end
    ow.runner:run({
      { "stop_music" },
      { "play_music", "Music_MeetJessieJames" },
      { "show_text", "_SilphCoJessieJamesText1" },
      { "face_player_dir", "down" },
      { "emote", "player", "shock", 30 },
      -- James (object 4) then Jessie (object 6), Script5..Script10 order
      { "walk_npc", 4, jamesDirs },
      { "face_object", 4, jamesFace },
      { "walk_npc", 6, jessieDirs },
      { "face_object", 6, jessieFace },
      { "show_text", "_SilphCoJessieJamesText2" },
      { "start_battle", "trainer", "OPP_ROCKET", 45 },
      { "check_battle_result", "win" },
      { "jump_if_false", "end" },
      { "show_text", "_SilphCoJessieJamesText3" },
      { "show_text", "_SilphCoJessieJamesText4" },
      { "stop_music" },
      { "play_music", "Music_MeetJessieJames" },
      { "fade", "out" },
      { "hide_object", "SILPH_CO_11F", "SILPHCO11F_JAMES" },
      { "hide_object", "SILPH_CO_11F", "SILPHCO11F_JESSIE" },
      { "fade", "in" },
      { "play_default_music" },
      { "set_flag", "EVENT_BEAT_SILPH_CO_11F_JESSIE_JAMES" },
    }, {})
    return true
  end,
}

return M
