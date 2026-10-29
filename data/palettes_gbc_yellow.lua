-- Yellow-only Advanced (redpp) deltas.  Merged on top of data/palettes_gbc.lua
-- world tables when GameVersion.isYellow(); Red/Blue never load this file's
-- world path.  Named SuperPalettes stay washed on Yellow -- PaletteFX.pal
-- prefers CGBBase under Advanced instead (title MEWMON/LOGO, YELLOWMON).
-- See #1639.

return {
  world = {
    -- Summer Beach House: Yellow-only tileset.  Tile→group map mirrors HOUSE
    -- (closest Advanced indoor profile); colors lean sand / wood / water.
    tileGroups = {
      BEACH_HOUSE = {
        [0] = 5,
        [1] = 0,
        [2] = 0,
        [3] = 0,
        [4] = 1,
        [5] = 0,
        [6] = 3,
        [7] = 3,
        [8] = 2,
        [9] = 2,
        [10] = 2,
        [11] = 2,
        [12] = 2,
        [13] = 2,
        [14] = 5,
        [15] = 5,
        [16] = 0,
        [17] = 0,
        [18] = 0,
        [19] = 0,
        [20] = 1,
        [21] = 0,
        [22] = 3,
        [23] = 3,
        [24] = 5,
        [25] = 5,
        [26] = 5,
        [27] = 5,
        [28] = 0,
        [29] = 0,
        [30] = 5,
        [31] = 5,
        [32] = 0,
        [33] = 0,
        [34] = 3,
        [35] = 5,
        [36] = 5,
        [37] = 5,
        [38] = 5,
        [39] = 5,
        [40] = 5,
        [41] = 5,
        [42] = 2,
        [43] = 2,
        [44] = 5,
        [45] = 5,
        [46] = 5,
        [47] = 5,
        [48] = 5,
        [49] = 5,
        [50] = 5,
        [51] = 5,
        [52] = 5,
        [53] = 5,
        [54] = 5,
        [55] = 5,
        [56] = 5,
        [57] = 5,
        [58] = 5,
        [59] = 5,
        [60] = 5,
        [61] = 5,
        [62] = 5,
        [63] = 5,
        [64] = 0,
        [65] = 0,
        [66] = 0,
        [67] = 0,
        [68] = 0,
        [69] = 0,
        [70] = 5,
        [71] = 5,
        [72] = 5,
        [73] = 5,
        [74] = 5,
        [75] = 5,
        [76] = 5,
        [77] = 5,
        [78] = 5,
        [79] = 5,
        [80] = 5,
        [81] = 5,
        [82] = 5,
        [83] = 5,
        [84] = 5,
        [85] = 5,
        [86] = 5,
        [87] = 5,
        [88] = 5,
        [89] = 5,
        [90] = 5,
        [91] = 5,
        [92] = 5,
        [93] = 5,
        [94] = 5,
        [95] = 5,
      },
    },
    groupColors = {
      BEACH_HOUSE = {
        -- sand / wood floor
        {
          { 255, 239, 198 },
          { 206, 173, 115 },
          { 156, 123, 74 },
          { 58, 58, 58 },
        },
        -- signs / accents (warm coral)
        {
          { 255, 239, 198 },
          { 255, 156, 148 },
          { 230, 82, 66 },
          { 58, 58, 58 },
        },
        -- foliage
        {
          { 255, 239, 198 },
          { 123, 189, 82 },
          { 66, 123, 41 },
          { 58, 58, 58 },
        },
        -- water / windows
        {
          { 255, 239, 198 },
          { 99, 189, 230 },
          { 41, 115, 189 },
          { 58, 58, 58 },
        },
        -- yellow props
        {
          { 255, 239, 198 },
          { 255, 255, 82 },
          { 230, 148, 25 },
          { 58, 58, 58 },
        },
        -- wood walls / furniture
        {
          { 255, 239, 198 },
          { 189, 140, 74 },
          { 140, 99, 41 },
          { 58, 58, 58 },
        },
        -- sky / cool trim
        {
          { 255, 239, 198 },
          { 148, 189, 255 },
          { 99, 148, 230 },
          { 58, 58, 58 },
        },
        -- text
        {
          { 255, 255, 255 },
          { 255, 255, 255 },
          { 255, 255, 255 },
          { 0, 0, 0 },
        },
      },
    },

    -- Yellow spriteOrder is 82 entries; Red Advanced assignment is 72.
    -- Indices 60-69 are Yellow inserts (Pikachu, Jenny, mons, Jessie/James);
    -- Red's ball/fossil/snorlax/... shift to 70-81.
    spriteAssignment = {
      [0] = 0,
      [1] = 1,
      [2] = 3,
      [3] = "random",
      [4] = 0,
      [5] = "random",
      [6] = "random",
      [7] = "random",
      [8] = 0,
      [9] = "random",
      [10] = "random",
      [11] = "random",
      [12] = "random",
      [13] = "random",
      [14] = "random",
      [15] = 1,
      [16] = 1,
      [17] = "random",
      [18] = "random",
      [19] = "random",
      [20] = "random",
      [21] = 2,
      [22] = 1,
      [23] = 3,
      [24] = "random",
      [25] = "random",
      [26] = "random",
      [27] = "random",
      [28] = "random",
      [29] = 0,
      [30] = 3,
      [31] = 3,
      [32] = "random",
      [33] = "random",
      [34] = "random",
      [35] = "random",
      [36] = "random",
      [37] = "random",
      [38] = "random",
      [39] = "random",
      [40] = 0,
      [41] = 2,
      [42] = "random",
      [43] = "random",
      [44] = "random",
      [45] = "random",
      [46] = "random",
      [47] = "random",
      [48] = "random",
      [49] = "random",
      [50] = "random",
      [51] = "random",
      [52] = "random",
      [53] = "random",
      [54] = "random",
      [55] = 0,
      [56] = 1,
      [57] = 3,
      [58] = 0,
      [59] = 0,
      [60] = 4, -- SPRITE_PIKACHU
      [61] = 1, -- SPRITE_OFFICER_JENNY
      [62] = 3, -- SPRITE_SANDSHREW
      [63] = 2, -- SPRITE_ODDISH
      [64] = 2, -- SPRITE_BULBASAUR
      [65] = 8, -- SPRITE_JIGGLYPUFF
      [66] = 8, -- SPRITE_CLEFAIRY
      [67] = 8, -- SPRITE_CHANSEY
      [68] = 0, -- SPRITE_JESSIE
      [69] = 1, -- SPRITE_JAMES
      [70] = 0, -- SPRITE_POKE_BALL
      [71] = 0, -- SPRITE_FOSSIL
      [72] = 3, -- SPRITE_BOULDER
      [73] = 3, -- SPRITE_PAPER
      [74] = 0, -- SPRITE_POKEDEX
      [75] = 3, -- SPRITE_CLIPBOARD
      [76] = 0, -- SPRITE_SNORLAX
      [77] = 3, -- SPRITE_UNUSED_OLD_AMBER
      [78] = 3, -- SPRITE_OLD_AMBER
      [79] = "random",
      [80] = "random",
      [81] = 3, -- SPRITE_GAMBLER_ASLEEP
    },

    -- Group 4 is Pikachu yellow on Yellow Advanced (Red keeps its own [4]).
    spritePalettes = {
      [4] = {
        { 222, 255, 222 },
        { 255, 255, 0 },
        { 230, 115, 0 },
        { 0, 0, 0 },
      },
      -- pokered-gbc data/super_palettes.asm:149
      [8] = require("data.palettes_gbc").palettes.PINKMON,
    },
  },
}
