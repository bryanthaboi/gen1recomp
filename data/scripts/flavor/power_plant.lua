-- Power Plant static encounters (scripts/PowerPlant.asm + home/trainers.asm
-- TalkToTrainer; species/levels from data/maps/objects/PowerPlant.asm).
--
-- Each "item ball" is a disguised VOLTORB/ELECTRODE: its text_asm loads a
-- trainer header (Voltorb0..7TrainerHeader) and calls TalkToTrainer, which
-- prints PowerPlantVoltorbBattleText ("Bzzzt!") and starts a wild battle --
-- or, when the header's EVENT_BEAT_POWER_PLANT_VOLTORB_n flag is already
-- set, prints the (identical) after-battle text and stops.  Zapdos is the
-- same flow with ZapdosTrainerHeader/EVENT_BEAT_ZAPDOS, except its battle
-- text is text_far "Gyaoo!" followed by text_asm PlayCry ZAPDOS +
-- WaitForSoundToFinish.  EndTrainerBattle sets the EVENT_BEAT_* flag and
-- hides the object on any non-blackout result (win, catch or flee) --
-- static_battle mirrors that.

-- header order in scripts/PowerPlant.asm: text_asm n uses header n-1
local function ballMon(species, level, flag)
  return {
    { "check_flag", flag },
    { "jump_if_true", "beaten" },
    { "engage_music", "Music_MeetMaleTrainer" },       -- home/trainers.asm:123
    { "show_text", "_PowerPlantVoltorbBattleText" },
    { "static_battle", species, level, flag },
    { "jump", "end" },
    { "label", "beaten" },
    { "show_text", "_PowerPlantVoltorbBattleText" },
  }
end

local M = {}

M.POWER_PLANT = {
  talk = {
    TEXT_POWERPLANT_VOLTORB1 = ballMon("VOLTORB", 40, "EVENT_BEAT_POWER_PLANT_VOLTORB_0"),
    TEXT_POWERPLANT_VOLTORB2 = ballMon("VOLTORB", 40, "EVENT_BEAT_POWER_PLANT_VOLTORB_1"),
    TEXT_POWERPLANT_VOLTORB3 = ballMon("VOLTORB", 40, "EVENT_BEAT_POWER_PLANT_VOLTORB_2"),
    TEXT_POWERPLANT_ELECTRODE1 = ballMon("ELECTRODE", 43, "EVENT_BEAT_POWER_PLANT_VOLTORB_3"),
    TEXT_POWERPLANT_VOLTORB4 = ballMon("VOLTORB", 40, "EVENT_BEAT_POWER_PLANT_VOLTORB_4"),
    TEXT_POWERPLANT_VOLTORB5 = ballMon("VOLTORB", 40, "EVENT_BEAT_POWER_PLANT_VOLTORB_5"),
    TEXT_POWERPLANT_ELECTRODE2 = ballMon("ELECTRODE", 43, "EVENT_BEAT_POWER_PLANT_VOLTORB_6"),
    TEXT_POWERPLANT_VOLTORB6 = ballMon("VOLTORB", 40, "EVENT_BEAT_POWER_PLANT_VOLTORB_7"),
    TEXT_POWERPLANT_ZAPDOS = {
      { "check_flag", "EVENT_BEAT_ZAPDOS" },
      { "jump_if_true", "beaten" },
      { "play_cry", "ZAPDOS", true },
      { "engage_music", "Music_MeetMaleTrainer" },     -- home/trainers.asm:123
      { "show_text", "_PowerPlantZapdosBattleText" },
      { "static_battle", "ZAPDOS", 50, "EVENT_BEAT_ZAPDOS" },
      { "jump", "end" },
      { "label", "beaten" },
      { "play_cry", "ZAPDOS", true },
      { "show_text", "_PowerPlantZapdosBattleText" },
    },
  },
}

return M
