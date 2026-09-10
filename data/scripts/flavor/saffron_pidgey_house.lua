-- SaffronPidgeyHouse (pokered/scripts/SaffronPidgeyHouse.asm)
--
-- TEXT_SAFFRONPIDGEYHOUSE_PIDGEY: SaffronPidgeyHousePidgeyText plays the
-- PIDGEY cry after showing its "Kurukkoo!" line (text_asm: ld a, PIDGEY /
-- call PlayCry / jp TextScriptEnd).

return {
  SAFFRON_PIDGEY_HOUSE = {
    talk = {
      TEXT_SAFFRONPIDGEYHOUSE_PIDGEY = {
        { "face_player" },
        { "play_cry", "PIDGEY", true },
        { "show_text", "_SaffronPidgeyHousePidgeyText" },
      },
    },
  },
}
