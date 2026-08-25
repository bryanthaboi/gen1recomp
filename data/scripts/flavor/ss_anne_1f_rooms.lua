-- pokered/scripts/SSAnne1FRooms.asm:66 SSAnne1FRoomsWigglytuffText
-- text_far _SSAnne1FRoomsWigglytuffText, then ld a, WIGGLYTUFF / call PlayCry (:70)
return {
  SS_ANNE_1F_ROOMS = {
    talk = {
      TEXT_SSANNE1FROOMS_WIGGLYTUFF = {
        {"face_player"},
        {"play_cry", "WIGGLYTUFF", true},               -- 1 PlayCry (#1687)
        {"show_text", "_SSAnne1FRoomsWigglytuffText"},
      },
    },
  },
}
