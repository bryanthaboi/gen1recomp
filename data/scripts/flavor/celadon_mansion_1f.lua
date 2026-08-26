-- CeladonMansion1F flavor talk scripts (pokered/scripts/CeladonMansion1F.asm)
return {
  CELADON_MANSION_1F = {
    talk = {
      TEXT_CELADONMANSION1F_CLEFAIRY = {
        {"face_player"},
        -- pokered/scripts/CeladonMansion1F.asm:27
        {"play_cry", "CLEFAIRY", true},
        {"show_text", "_CeladonMansion1FClefairyText"},
      },

      TEXT_CELADONMANSION1F_MEOWTH = {
        {"face_player"},
        -- pokered/scripts/CeladonMansion1F.asm:18
        {"play_cry", "MEOWTH", true},
        {"show_text", "_CeladonMansion1FMeowthText"},
      },

      TEXT_CELADONMANSION1F_NIDORANF = {
        {"face_player"},
        -- pokered/scripts/CeladonMansion1F.asm:33
        {"play_cry", "NIDORAN_F", true},
        {"show_text", "_CeladonMansion1FNidoranFText"},
      },
    },
  },
}
