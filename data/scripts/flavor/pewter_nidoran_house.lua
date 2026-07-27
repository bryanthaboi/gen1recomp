-- pokered/scripts/PewterNidoranHouse.asm
-- PewterNidoranHouseNidoranText: text_far _PewterNidoranHouseNidoranText, then
-- text_asm plays the NIDORAN_M cry (PlayCry/WaitForSoundToFinish) before ending.
-- play_cry only stashes ctx.pendingCry for the very next show_text row, so it
-- has to sit immediately before that row (src/script/Commands.lua); the cry
-- then sounds once the box has typed out, matching the asm's print-then-cry
-- order.  Its waitForButton form keeps DisplayTextID's trailing
-- WaitForTextScrollButtonPress -- PewterNidoranHouse_Script is
-- `jp EnableAutoTextBoxDrawing`, which zeroes
-- wDoNotWaitForButtonPressAfterDisplayingText -- so the box still holds until
-- A/B.  The cry row was missing, leaving the NIDORAN silent (#247).
return {
  PEWTER_NIDORAN_HOUSE = {
    talk = {
      TEXT_PEWTERNIDORANHOUSE_NIDORAN = {
        { "face_player" },
        -- text_asm: ld a, NIDORAN_M / call PlayCry
        { "play_cry", "NIDORAN_M", true },
        { "show_text", "_PewterNidoranHouseNidoranText" },
      },
    },
  },
}
