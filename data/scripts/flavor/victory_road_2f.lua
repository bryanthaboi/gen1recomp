-- Moltres (scripts/VictoryRoad2F.asm VictoryRoad2FMoltresText +
-- home/trainers.asm TalkToTrainer; MOLTRES 50 from
-- data/maps/objects/VictoryRoad2F.asm).
--
-- The text_asm loads MoltresTrainerHeader and calls TalkToTrainer:
-- VictoryRoad2FMoltresBattleText is text_far "Gyaoo!" + text_asm
-- PlayCry MOLTRES + WaitForSoundToFinish, then the wild battle starts --
-- or, when EVENT_BEAT_MOLTRES is already set, the (identical)
-- after-battle text prints and nothing else happens.  EndTrainerBattle
-- sets EVENT_BEAT_MOLTRES and hides the object on any non-blackout
-- result (win, catch or flee) -- static_battle mirrors that.

local M = {}

M.VICTORY_ROAD_2F = {
  talk = {
    TEXT_VICTORYROAD2F_MOLTRES = {
      { "check_flag", "EVENT_BEAT_MOLTRES" },
      { "jump_if_true", "beaten" },
      { "play_cry", "MOLTRES", true },
      { "engage_music", "Music_MeetMaleTrainer" },              -- home/trainers.asm:123
      { "show_text", "_VictoryRoad2FMoltresBattleText" },
      { "static_battle", "MOLTRES", 50, "EVENT_BEAT_MOLTRES" },
      { "jump", "end" },
      { "label", "beaten" },
      { "play_cry", "MOLTRES", true },
      { "show_text", "_VictoryRoad2FMoltresBattleText" },
    },
  },
}

return M
