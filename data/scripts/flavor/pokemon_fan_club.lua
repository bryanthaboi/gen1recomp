-- Flavor talk scripts for POKEMON_FAN_CLUB (pokered/scripts/PokemonFanClub.asm)
--
-- TEXT_POKEMONFANCLUB_CHAIRMAN is already ported in data/scripts/story2.lua
-- (the bike voucher chain), so it is intentionally omitted here.

local M = {}

M.POKEMON_FAN_CLUB = {
  talk = {
    -- PokemonFanClubPikachuFanText (scripts/PokemonFanClub.asm): brags
    -- about her PIKACHU unless she's already "won" the boast war against
    -- the SEEL fan (EVENT_PIKACHU_FAN_BOAST set), in which case she gets
    -- huffy and resets it. Either way she sets the other fan's boast flag
    -- so their next line is the "mine is better" retort.
    TEXT_POKEMONFANCLUB_PIKACHU_FAN = {
      { "face_player" },                                              -- 1
      { "check_flag", "EVENT_PIKACHU_FAN_BOAST" },                    -- 2
      { "jump_if_true", 7 },                                          -- 3
      { "show_text", "_PokemonFanClubPikachuFanNormalText" },         -- 4
      { "set_flag", "EVENT_SEEL_FAN_BOAST" },                         -- 5
      { "jump", 9 },                                                  -- 6 (skip the "mineisbetter" branch)
      { "show_text", "_PokemonFanClubPikachuFanBetterText" },         -- 7
      { "clear_flag", "EVENT_PIKACHU_FAN_BOAST" },                    -- 8
    },

    -- PokemonFanClubSeelFanText (scripts/PokemonFanClub.asm): mirror of
    -- the PIKACHU fan above, keyed off EVENT_SEEL_FAN_BOAST.
    TEXT_POKEMONFANCLUB_SEEL_FAN = {
      { "face_player" },                                              -- 1
      { "check_flag", "EVENT_SEEL_FAN_BOAST" },                       -- 2
      { "jump_if_true", 7 },                                          -- 3
      { "show_text", "_PokemonFanClubSeelFanNormalText" },            -- 4
      { "set_flag", "EVENT_PIKACHU_FAN_BOAST" },                      -- 5
      { "jump", 9 },                                                  -- 6 (skip the "mineisbetter" branch)
      { "show_text", "_PokemonFanClubSeelFanBetterText" },            -- 7
      { "clear_flag", "EVENT_SEEL_FAN_BOAST" },                       -- 8
    },

    -- PokemonFanClubPikachuText (scripts/PokemonFanClub.asm:71): PrintText,
    -- then ld a, PIKACHU / call PlayCry (:76) / call WaitForSoundToFinish.
    TEXT_POKEMONFANCLUB_PIKACHU = {
      { "play_cry", "PIKACHU", true },                                -- 1 PlayCry (#1649)
      { "show_text", "_PokemonFanClubPikachuText" },                  -- 2 PrintText
    },

    -- PokemonFanClubSeelText (scripts/PokemonFanClub.asm:84): the same
    -- shape with SEEL, PlayCry at :89.
    TEXT_POKEMONFANCLUB_SEEL = {
      { "play_cry", "SEEL", true },                                   -- 1 PlayCry (#1649)
      { "show_text", "_PokemonFanClubSeelText" },                     -- 2 PrintText
    },
  },
}

-- pokeyellow/scripts/PokemonFanClub.asm:149 PokemonFanClubClefairyText: Yellow's
-- pet is a CLEFAIRY on its own TEXT_POKEMONFANCLUB_CLEFAIRY, PlayCry at :154.
if require("src.core.GameVersion").isYellow() then
  M.POKEMON_FAN_CLUB.talk.TEXT_POKEMONFANCLUB_CLEFAIRY = {
    { "play_cry", "CLEFAIRY", true },                                 -- 1 PlayCry
    { "show_text", "_PokemonFanClubClefairyText" },                   -- 2 PrintText
  }
end

return M
