-- pokered/scripts/VermilionPidgeyHouse.asm:15 VermilionPidgeyHousePidgeyText
-- text_far, then ld a, PIDGEY / call PlayCry (:19) / call WaitForSoundToFinish

return {
  VERMILION_PIDGEY_HOUSE = {
    talk = {
      TEXT_VERMILIONPIDGEYHOUSE_PIDGEY = {
        {"face_player"},
        {"play_cry", "PIDGEY", true},                    -- 1 PlayCry (#1649)
        {"show_text", "_VermilionPidgeyHousePidgeyText"},
      },
    },
  },
}
