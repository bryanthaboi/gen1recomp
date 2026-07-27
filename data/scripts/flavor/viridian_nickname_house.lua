-- Viridian Nickname House (pokered/scripts/ViridianNicknameHouse.asm).

return {
  VIRIDIAN_NICKNAME_HOUSE = {
    talk = {
      -- ViridianNicknameHouseSpearowText: text_asm that PrintTexts the
      -- line, then plays the SPEAROW cry (PlayCry/WaitForSoundToFinish)
      -- before TextScriptEnd.  play_cry only arms the show_text row that
      -- follows it, so the cry sounds once the box has typed out; its
      -- waitForButton form keeps DisplayTextID's trailing
      -- WaitForTextScrollButtonPress, so the box then holds until A/B like
      -- any other NPC line rather than popping itself (#251).
      TEXT_VIRIDIANNICKNAMEHOUSE_SPEAROW = {
        { "play_cry", "SPEAROW", true },                      -- 1 PlayCry
        { "show_text", "_ViridianNicknameHouseSpearowText" }, -- 2 PrintText
      },
    },
  },
}
