-- pokered/scripts/SSAnneB1FRooms.asm:82 SSAnneB1FRoomsMachokeText
-- text_far _SSAnneB1FRoomsMachokeText, then ld a, MACHOKE / call PlayCry (:86)
return {
    SS_ANNE_B1F_ROOMS = {
        talk = {
            TEXT_SSANNEB1FROOMS_MACHOKE = {
                { "face_player" },
                { "play_cry", "MACHOKE", true },          -- 1 PlayCry (#1687)
                { "show_text", "_SSAnneB1FRoomsMachokeText" },
            },
        },
    },
}
