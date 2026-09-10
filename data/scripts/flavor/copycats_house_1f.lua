-- Flavor talk scripts for Copycat's House 1F (pokered/scripts/CopycatsHouse1F.asm)
return {
  COPYCATS_HOUSE_1F = {
    talk = {
      -- CopycatsHouse1FChanseyText: text_far _CopycatsHouse1FChanseyText, then
      -- text_asm plays the CHANSEY cry (ld a, CHANSEY / call PlayCry) before
      TEXT_COPYCATSHOUSE1F_CHANSEY = {
        { "play_cry", "CHANSEY", true },
        { "show_text", "_CopycatsHouse1FChanseyText" },
      },
    },
  },
}
