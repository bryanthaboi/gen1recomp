-- Fuchsia City (pokered/scripts/FuchsiaCity.asm)
--
-- The exhibit signs are text_asm bodies: PrintText of a single text_far,
-- then DisplayPokedex for the exhibited species.  The preview marks the
-- species seen but not owned, same as the S.S. Anne passenger's Snorlax.
--
-- The fossil sign branches on the Mt. Moon fossil events.  The exhibit
-- holds the fossil the player did NOT take: taking the Dome Fossil puts
-- Omanyte on display, taking the Helix Fossil puts Kabuto.  With neither
-- event set the sign only prints its undetermined line and no dex entry
-- opens.
--
-- The other text pointers (city sign, Safari Game signs, mart/center/gym
-- and warden signs, the four NPCs, the exhibited-mon FuchsiaCityPokemonText
-- rows) are plain text_far wrappers that resolve through Data:resolveText,
-- so they are not ported here.
return {
  FUCHSIA_CITY = {
    talk = {
      -- FuchsiaCityChanseySignText: PrintText(_FuchsiaCityChanseySignText),
      -- then DisplayPokedex CHANSEY.
      TEXT_FUCHSIACITY_CHANSEY_SIGN = {
        { "show_text", "_FuchsiaCityChanseySignText" },
        { "mark_seen", "CHANSEY" },
        { "push_screen", "DexEntryMenu", "CHANSEY" },
      },

      -- FuchsiaCityVoltorbSignText: PrintText(_FuchsiaCityVoltorbSignText),
      -- then DisplayPokedex VOLTORB.
      TEXT_FUCHSIACITY_VOLTORB_SIGN = {
        { "show_text", "_FuchsiaCityVoltorbSignText" },
        { "mark_seen", "VOLTORB" },
        { "push_screen", "DexEntryMenu", "VOLTORB" },
      },

      -- FuchsiaCityKangaskhanSignText: PrintText(_FuchsiaCityKangaskhanSignText),
      -- then DisplayPokedex KANGASKHAN.
      TEXT_FUCHSIACITY_KANGASKHAN_SIGN = {
        { "show_text", "_FuchsiaCityKangaskhanSignText" },
        { "mark_seen", "KANGASKHAN" },
        { "push_screen", "DexEntryMenu", "KANGASKHAN" },
      },

      -- FuchsiaCitySlowpokeSignText: PrintText(_FuchsiaCitySlowpokeSignText),
      -- then DisplayPokedex SLOWPOKE.
      TEXT_FUCHSIACITY_SLOWPOKE_SIGN = {
        { "show_text", "_FuchsiaCitySlowpokeSignText" },
        { "mark_seen", "SLOWPOKE" },
        { "push_screen", "DexEntryMenu", "SLOWPOKE" },
      },

      -- FuchsiaCityLaprasSignText: PrintText(_FuchsiaCityLaprasSignText),
      -- then DisplayPokedex LAPRAS.
      TEXT_FUCHSIACITY_LAPRAS_SIGN = {
        { "show_text", "_FuchsiaCityLaprasSignText" },
        { "mark_seen", "LAPRAS" },
        { "push_screen", "DexEntryMenu", "LAPRAS" },
      },

      -- FuchsiaCityFossilSignText: CheckEvent EVENT_GOT_DOME_FOSSIL /
      -- CheckEventReuseA EVENT_GOT_HELIX_FOSSIL pick the text and the
      -- displayed entry; with neither set only the undetermined line prints.
      TEXT_FUCHSIACITY_FOSSIL_SIGN = {
        { "check_flag", "EVENT_GOT_DOME_FOSSIL" },                 -- 1
        { "jump_if_true", 7 },                                     -- 2
        { "check_flag", "EVENT_GOT_HELIX_FOSSIL" },                -- 3
        { "jump_if_true", 11 },                                    -- 4
        { "show_text", "_FuchsiaCityFossilSignUndeterminedText" }, -- 5
        { "jump", "end" },                                         -- 6
        { "show_text", "_FuchsiaCityFossilSignOmanyteText" },      -- 7
        { "mark_seen", "OMANYTE" },                                -- 8
        { "push_screen", "DexEntryMenu", "OMANYTE" },              -- 9
        { "jump", "end" },                                         -- 10
        { "show_text", "_FuchsiaCityFossilSignKabutoText" },       -- 11
        { "mark_seen", "KABUTO" },                                 -- 12
        { "push_screen", "DexEntryMenu", "KABUTO" },               -- 13
      },
    },
  },
}
