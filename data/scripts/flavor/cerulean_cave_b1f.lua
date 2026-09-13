-- Mewtwo (scripts/CeruleanCaveB1F.asm CeruleanCaveB1FMewtwoText +
-- home/trainers.asm TalkToTrainer; MEWTWO 70 from
-- data/maps/objects/CeruleanCaveB1F.asm).
--
-- The text_asm loads MewtwoTrainerHeader and calls TalkToTrainer:
-- MewtwoBattleText is text_far "Mew!" + text_asm PlayCry MEWTWO +
-- WaitForSoundToFinish, then the wild battle starts -- or, when
-- EVENT_BEAT_MEWTWO is already set, the (identical) after-battle text
-- prints and nothing else happens.  EndTrainerBattle sets
-- EVENT_BEAT_MEWTWO and hides the object on any non-blackout result
-- (win, catch or flee) -- static_battle mirrors that.

local M = {}

M.CERULEAN_CAVE_B1F = {
  talk = {
    TEXT_CERULEANCAVEB1F_MEWTWO = {
      { "check_flag", "EVENT_BEAT_MEWTWO" },
      { "jump_if_true", "beaten" },
      { "play_cry", "MEWTWO", true },
      { "engage_music", "Music_MeetMaleTrainer" },            -- home/trainers.asm:123
      { "show_text", "_MewtwoBattleText" },
      { "static_battle", "MEWTWO", 70, "EVENT_BEAT_MEWTWO" },
      { "jump", "end" },
      { "label", "beaten" },
      { "play_cry", "MEWTWO", true },
      { "show_text", "_MewtwoBattleText" },
    },
  },
}

return M
