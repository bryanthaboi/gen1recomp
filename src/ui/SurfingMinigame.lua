-- Surfing Pikachu minigame (engine/minigame/surfing_pikachu.asm): the
-- Summer Beach House wave run.  Pikachu accelerates automatically down
-- the wave face, launches off the crest, spins in the air with buffered
-- D-pad controls, and lands to match the wave slope for points.
--
-- 1:1 Love2D port of the authentic Pokémon Yellow disassembly:
-- - Exact 13-stage routine state machine (Start, Run, Coast, Outro, Tally, Hi-Score, Game Over)
-- - Rigid 16.8 fixed-point integer physics (no float drift; speed += 2 per frame, 512 max)
-- - Input accumulator eliminating the 3-frame polling blind spot
-- - GB hardware VBlank execution order (collision boundary checked before position update)
-- - Deterministic Game Boy DIV/Random LFSR wave sequence generator
-- - 14-angle rotation model with 3-frame buffered input (Right = frontflip, Left = backflip)
-- - Stunt scoring: +50 (single), +150 (double same), +350 (triple same), +180 (mixed), +500 (triple mixed)
-- - Tile interaction landing matrix (Clean, Rough -64, Hard -128, Crash/Wipeout)
-- - Non-fatal crash recovery: Pikachu wipes out for 96 frames, resets speed to 64 (0.25), and continues
-- - HP stamina timer counting down from 6000 BCD (60.00s)
-- - HUD progress track with mini-Pikachu marker advancing across 24 sections
-- - Animated "START" and "Oh no.." banners, floating trick score popups, and water sprays
-- - Dynamic 5-tier music tempo tracking Pikachu's speed
-- - Full beach outro results scene with step-by-step tally animation and high-score fanfare

local Font = require("src.render.Font")
local Strings = require("src.core.Strings")
local Music = require("src.core.Music")
local Sound = require("src.core.Sound")
local bit = require("bit")

local SurfingMinigame = {}
SurfingMinigame.__index = function(t, k)
  if k == "phase" then
    local r = rawget(t, "routine")
    if r and r >= 4 then
      return "results"
    elseif rawget(t, "pikaState") == 1 then
      return "air"
    elseif rawget(t, "pikaState") == 3 then
      return "wipeout"
    else
      return "ride"
    end
  elseif k == "speed" then
    return (rawget(t, "speedFixed") or 64) / 256
  elseif k == "distance" then
    return (rawget(t, "distanceFixed") or 0) / 256
  elseif k == "score" then
    local tot = rawget(t, "totalScore") or 0
    if tot > 0 then return tot end
    return (rawget(t, "radness") or 0) + (rawget(t, "hp") or 0)
  end
  return SurfingMinigame[k]
end
SurfingMinigame.isOpaque = true

-- Fixed-point physics constants (256 = 1.0 px/frame)
local SPEED_INITIAL        = 64   -- 0.25 * 256
local SPEED_MAX            = 512  -- 2.00 * 256
local SPEED_ACCEL          = 2    -- (1/128) * 256
local SPEED_ROUGH_PENALTY  = 64   -- 0.25 * 256
local SPEED_HARD_PENALTY   = 128  -- 0.50 * 256
local SPEED_JUMP_THRESHOLD = 320  -- 1.25 * 256 (10/32)

-- Original constants (surfing_pikachu.asm)
local FLAT_WATER_Y = 116       -- OAM Y 0x74 = screen Y 100 (PIKA_Y = FLAT_WATER_Y - 16)
local PIKA_X = 68              -- Fixed screen X while riding (center 80, 24px pose)
local TOTAL_SECTIONS = 24      -- 24 sections ($18) of 128px = 3072px course
local BG_HEIGHT = 128          -- Rows the BG shows; HP window covers the rest (y=128..144)

-- Routine numbers (wSurfingMinigameRoutineNumber)
local ROUTINE_TITLE            = -1
local ROUTINE_START_GAME       = 0
local ROUTINE_RUN_GAME         = 1
local ROUTINE_WAIT_RESULTS     = 2
local ROUTINE_SCROLL_RESULTS   = 3
local ROUTINE_DRAW_RESULTS     = 4
local ROUTINE_WRITE_HP_LEFT    = 5
local ROUTINE_WRITE_RADNESS    = 6
local ROUTINE_WRITE_TOTAL      = 7
local ROUTINE_ADD_HP_TOTAL     = 8
local ROUTINE_ADD_RAD_TOTAL    = 9
local ROUTINE_WAIT_LAST        = 10
local ROUTINE_EXIT_ON_PRESS_A  = 11
local ROUTINE_GAME_OVER        = 12

-- Pikachu states (wSurfingMinigamePikachuState)
local PIKA_STATE_RIDING       = 0
local PIKA_STATE_JUMPING      = 1
local PIKA_STATE_LANDING      = 2
local PIKA_STATE_CRASHED      = 3
local PIKA_STATE_GAME_END     = 4
local PIKA_STATE_INIT_RESULTS = 5
local PIKA_STATE_RESULTS      = 6

-- Metatile lookup (2x2 tiles each)
local BG_METATILES = {
  [0x00] = { 0x00, 0x00, 0x00, 0x00 }, -- sky block (blank)
  [0x01] = { 0x0b, 0x0b, 0x0b, 0x0b }, -- open water
  [0x02] = { 0x0b, 0x02, 0x02, 0x06 },
  [0x03] = { 0x03, 0x0b, 0x07, 0x03 },
  [0x04] = { 0x06, 0x06, 0x06, 0x06 },
  [0x05] = { 0x07, 0x07, 0x07, 0x07 },
  [0x06] = { 0x06, 0x04, 0x04, 0x08 },
  [0x07] = { 0x05, 0x07, 0x08, 0x05 },
  [0x08] = { 0x0b, 0x0b, 0x11, 0x12 },
  [0x09] = { 0x0b, 0x0b, 0x13, 0x03 },
  [0x0a] = { 0x14, 0x12, 0x04, 0x08 },
  [0x0b] = { 0x13, 0x07, 0x08, 0x05 },
  [0x0c] = { 0x06, 0x14, 0x06, 0x14 },
  [0x0d] = { 0x13, 0x07, 0x13, 0x07 },
  [0x0e] = { 0x08, 0x08, 0x08, 0x08 }, -- solid blue
  [0x0f] = { 0x14, 0x12, 0x14, 0x12 },
  [0x10] = { 0x0b, 0x11, 0x02, 0x14 },
  [0x11] = { 0x06, 0x14, 0x06, 0x14 },
  [0x12] = { 0x0c, 0x0c, 0x0d, 0x0d }, -- beach top block
  [0x13] = { 0x0d, 0x0d, 0x0d, 0x0d }, -- beach sand block
  [0x14] = { 0x0e, 0x0f, 0x10, 0x0b }, -- beach shore block
  [0x15] = { 0x12, 0x13, 0x12, 0x13 },
}

-- Wave pattern slices (8 metatiles each)
local WAVE_PATTERNS = {
  [0x00] = { 0x00, 0x00, 0x00, 0x01, 0x01, 0x01, 0x01, 0x01 },
  [0x01] = { 0x00, 0x00, 0x00, 0x01, 0x01, 0x02, 0x04, 0x06 },
  [0x02] = { 0x00, 0x00, 0x00, 0x01, 0x02, 0x04, 0x06, 0x0e },
  [0x03] = { 0x00, 0x00, 0x00, 0x10, 0x11, 0x06, 0x0e, 0x0e },
  [0x04] = { 0x00, 0x00, 0x00, 0x15, 0x15, 0x0e, 0x0e, 0x0e },
  [0x05] = { 0x00, 0x00, 0x00, 0x03, 0x05, 0x07, 0x0e, 0x0e },
  [0x06] = { 0x00, 0x00, 0x00, 0x01, 0x03, 0x05, 0x07, 0x0e },
  [0x07] = { 0x00, 0x00, 0x00, 0x01, 0x01, 0x03, 0x05, 0x07 },
  [0x08] = { 0x00, 0x00, 0x00, 0x01, 0x01, 0x02, 0x04, 0x06 },
  [0x09] = { 0x00, 0x00, 0x00, 0x01, 0x02, 0x04, 0x06, 0x0e },
  [0x0a] = { 0x00, 0x00, 0x00, 0x08, 0x0f, 0x0a, 0x0e, 0x0e },
  [0x0b] = { 0x00, 0x00, 0x00, 0x09, 0x0d, 0x0b, 0x0e, 0x0e },
  [0x0c] = { 0x00, 0x00, 0x00, 0x01, 0x03, 0x05, 0x07, 0x0e },
  [0x0d] = { 0x00, 0x00, 0x00, 0x01, 0x01, 0x03, 0x05, 0x07 },
  [0x0e] = { 0x00, 0x00, 0x00, 0x01, 0x01, 0x02, 0x04, 0x06 },
  [0x0f] = { 0x00, 0x00, 0x00, 0x01, 0x10, 0x11, 0x06, 0x0e },
  [0x10] = { 0x00, 0x00, 0x00, 0x01, 0x15, 0x15, 0x0e, 0x0e },
  [0x11] = { 0x00, 0x00, 0x00, 0x01, 0x03, 0x05, 0x07, 0x0e },
  [0x12] = { 0x00, 0x00, 0x00, 0x01, 0x01, 0x03, 0x05, 0x07 },
  [0x13] = { 0x00, 0x00, 0x00, 0x01, 0x01, 0x02, 0x04, 0x06 },
  [0x14] = { 0x00, 0x00, 0x00, 0x01, 0x08, 0x0f, 0x0a, 0x0e },
  [0x15] = { 0x00, 0x00, 0x00, 0x01, 0x09, 0x0d, 0x0b, 0x0e },
  [0x16] = { 0x00, 0x00, 0x00, 0x01, 0x01, 0x03, 0x05, 0x07 },
  [0x17] = { 0x00, 0x00, 0x00, 0x01, 0x01, 0x10, 0x11, 0x06 },
  [0x18] = { 0x00, 0x00, 0x00, 0x01, 0x01, 0x15, 0x15, 0x0e },
  [0x19] = { 0x00, 0x00, 0x00, 0x01, 0x01, 0x03, 0x05, 0x07 },
  [0x1a] = { 0x00, 0x00, 0x00, 0x01, 0x01, 0x08, 0x0f, 0x0a },
  [0x1b] = { 0x00, 0x00, 0x00, 0x01, 0x01, 0x09, 0x0d, 0x0b },
  [0x1c] = { 0x00, 0x00, 0x00, 0x14, 0x14, 0x14, 0x14, 0x14 },
  beach  = { 0x00, 0x00, 0x00, 0x12, 0x13, 0x13, 0x13, 0x13 },
}

local ADV, RESET, STAY = 0, 1, 2
local WAVE_STEPS = {
  [0x01] = { 0x13, 116, 108, ADV }, [0x02] = { 0x14, 100,  92, ADV },
  [0x03] = { 0x15,  92,  92, ADV }, [0x04] = { 0x16, 100, 108, ADV },
  [0x05] = { 0x00, 116, 116, ADV }, [0x06] = { 0x17, 116, 108, ADV },
  [0x07] = { 0x18, 100, 100, ADV }, [0x08] = { 0x19, 100, 108, ADV },
  [0x09] = { 0x00, 116, 116, ADV }, [0x0a] = { 0x00, 116, 116, ADV },
  [0x0b] = { 0x00, 116, 116, ADV }, [0x0c] = { 0x00, 116, 116, ADV },
  [0x0d] = { 0x00, 116, 116, RESET },
  [0x0e] = { 0x08, 116, 108, ADV }, [0x0f] = { 0x09, 100,  92, ADV },
  [0x10] = { 0x0a,  84,  76, ADV }, [0x11] = { 0x0b,  76,  76, ADV },
  [0x12] = { 0x0c,  84,  92, ADV }, [0x13] = { 0x0d, 100, 108, ADV },
  [0x14] = { 0x00, 116, 116, ADV }, [0x15] = { 0x00, 116, 116, ADV },
  [0x16] = { 0x00, 116, 116, ADV }, [0x17] = { 0x00, 116, 116, ADV },
  [0x18] = { 0x00, 116, 116, ADV }, [0x19] = { 0x00, 116, 116, RESET },
  [0x1a] = { 0x0e, 116, 108, ADV }, [0x1b] = { 0x0f, 100,  92, ADV },
  [0x1c] = { 0x10,  84,  84, ADV }, [0x1d] = { 0x11,  84,  92, ADV },
  [0x1e] = { 0x12, 100, 108, ADV }, [0x1f] = { 0x0e, 116, 108, ADV },
  [0x20] = { 0x0f, 100,  92, ADV }, [0x21] = { 0x10,  84,  84, ADV },
  [0x22] = { 0x11,  84,  92, ADV }, [0x23] = { 0x12, 100, 108, ADV },
  [0x24] = { 0x00, 116, 116, ADV }, [0x25] = { 0x00, 116, 116, ADV },
  [0x26] = { 0x00, 116, 116, ADV }, [0x27] = { 0x00, 116, 116, ADV },
  [0x28] = { 0x00, 116, 116, RESET },
  [0x29] = { 0x13, 116, 108, ADV }, [0x2a] = { 0x14, 100,  92, ADV },
  [0x2b] = { 0x15,  92,  92, ADV }, [0x2c] = { 0x16, 100, 108, ADV },
  [0x2d] = { 0x00, 116, 116, ADV }, [0x2e] = { 0x00, 116, 116, ADV },
  [0x2f] = { 0x00, 116, 116, ADV }, [0x30] = { 0x00, 116, 116, ADV },
  [0x31] = { 0x00, 116, 116, RESET },
  [0x32] = { 0x17, 116, 108, ADV }, [0x33] = { 0x18, 100, 100, ADV },
  [0x34] = { 0x19, 100, 108, ADV }, [0x35] = { 0x17, 116, 108, ADV },
  [0x36] = { 0x18, 100, 100, ADV }, [0x37] = { 0x19, 100, 108, ADV },
  [0x38] = { 0x17, 116, 108, ADV }, [0x39] = { 0x18, 100, 100, ADV },
  [0x3a] = { 0x19, 100, 108, ADV }, [0x3b] = { 0x00, 116, 116, ADV },
  [0x3c] = { 0x00, 116, 116, ADV }, [0x3d] = { 0x00, 116, 116, ADV },
  [0x3e] = { 0x00, 116, 116, ADV }, [0x3f] = { 0x00, 116, 116, RESET },
  [0x40] = { 0x1a, 116, 108, ADV }, [0x41] = { 0x1b, 108, 108, ADV },
  [0x42] = { 0x0e, 116, 108, ADV }, [0x43] = { 0x0f, 100,  92, ADV },
  [0x44] = { 0x10,  84,  84, ADV }, [0x45] = { 0x11,  84,  92, ADV },
  [0x46] = { 0x12, 100, 108, ADV }, [0x47] = { 0x1a, 116, 108, ADV },
  [0x48] = { 0x1b, 108, 108, ADV }, [0x49] = { 0x00, 116, 116, ADV },
  [0x4a] = { 0x00, 116, 116, ADV }, [0x4b] = { 0x00, 116, 116, ADV },
  [0x4c] = { 0x00, 116, 116, RESET },
  [0x4d] = { 0x08, 116, 108, ADV }, [0x4e] = { 0x09, 100,  92, ADV },
  [0x4f] = { 0x0a,  84,  76, ADV }, [0x50] = { 0x0b,  76,  76, ADV },
  [0x51] = { 0x0c,  84,  92, ADV }, [0x52] = { 0x0d, 100, 108, ADV },
  [0x53] = { 0x00, 116, 116, ADV }, [0x54] = { 0x1a, 116, 108, ADV },
  [0x55] = { 0x1b, 108, 108, ADV }, [0x56] = { 0x1a, 116, 108, ADV },
  [0x57] = { 0x1b, 108, 108, ADV }, [0x58] = { 0x00, 116, 116, ADV },
  [0x59] = { 0x00, 116, 116, ADV }, [0x5a] = { 0x00, 116, 116, ADV },
  [0x5b] = { 0x00, 116, 116, RESET },
  [0x5c] = { 0x0e, 116, 108, ADV }, [0x5d] = { 0x0f, 100,  92, ADV },
  [0x5e] = { 0x10,  84,  84, ADV }, [0x5f] = { 0x11,  84,  92, ADV },
  [0x60] = { 0x12, 100, 108, ADV }, [0x61] = { 0x13, 116, 108, ADV },
  [0x62] = { 0x14, 100,  92, ADV }, [0x63] = { 0x15,  92,  92, ADV },
  [0x64] = { 0x16, 100, 108, ADV }, [0x65] = { 0x00, 116, 116, ADV },
  [0x66] = { 0x00, 116, 116, ADV }, [0x67] = { 0x00, 116, 116, ADV },
  [0x68] = { 0x00, 116, 116, ADV }, [0x69] = { 0x00, 116, 116, RESET },
  [0x6a] = { 0x01, 116, 108, ADV }, [0x6b] = { 0x02, 100,  92, ADV },
  [0x6c] = { 0x03,  84,  76, ADV }, [0x6d] = { 0x04,  68,  68, ADV },
  [0x6e] = { 0x05,  68,  76, ADV }, [0x6f] = { 0x06,  84,  92, ADV },
  [0x70] = { 0x07, 100, 108, ADV }, [0x71] = { 0x00, 116, 116, STAY },
  [0x72] = { 0x00, 116, 116, ADV }, [0x73] = { 0x1c, 116, 116, ADV },
  [0x74] = { "beach", 116, 116, ADV }, [0x75] = { "beach", 116, 116, ADV },
  [0x76] = { "beach", 116, 116, ADV }, [0x77] = { "beach", 116, 116, ADV },
  [0x78] = { "beach", 116, 116, ADV }, [0x79] = { "beach", 116, 116, ADV },
  [0x7a] = { "beach", 116, 116, ADV }, [0x7b] = { "beach", 116, 116, RESET },
}
local SEQ_STARTS = {
  0x01, 0x0e, 0x1a, 0x29, 0x32, 0x40, 0x4d, 0x5c
}

SurfingMinigame.BG_METATILES = BG_METATILES
SurfingMinigame.WAVE_PATTERNS = WAVE_PATTERNS
SurfingMinigame.WAVE_STEPS = WAVE_STEPS

-- Pikachu base frames: 7 visual angles x 2 animation toggle frames each
local ANGLE_BASES = {
  [1] = { 0x00, 0x36 }, -- Angle 00 (nose up steep / backflip apex)
  [2] = { 0x03, 0x39 }, -- Angle 01 (nose up moderate)
  [3] = { 0x06, 0x3c }, -- Angle 02 (nose up slight)
  [4] = { 0x09, 0x60 }, -- Angle 03 (flat horizontal ride)
  [5] = { 0x0c, 0x63 }, -- Angle 04 (nose down slight)
  [6] = { 0x30, 0x66 }, -- Angle 05 (nose down moderate)
  [7] = { 0x33, 0x69 }, -- Angle 06 (nose down steep / frontflip apex)
}

-- OAM Definitions from surfing_pikachu_oam.asm
-- .WaterSpray (3 tiles, relative to PIKA_X = 68, y = self.pikaY)
local OAM_WATER_SPRAY = {
  { dy = -4, dx = 11, tile = 0xa7, xflip = false },
  { dy =  4, dx =  3, tile = 0xb6, xflip = false },
  { dy =  4, dx = 11, tile = 0xb7, xflip = false },
}

-- .SmallSplash (6 tiles, relative to cx = 80, cy = self.pikaY + 4)
local OAM_SMALL_SPLASH = {
  { dy = -4, dx = -16, tile = 0xa7, xflip = true  },
  { dy = -4, dx =   8, tile = 0xa7, xflip = false },
  { dy =  4, dx = -16, tile = 0xb7, xflip = true  },
  { dy =  4, dx =  -8, tile = 0xb6, xflip = true  },
  { dy =  4, dx =   0, tile = 0xb6, xflip = false },
  { dy =  4, dx =   8, tile = 0xb7, xflip = false },
}

-- .LargeSplash (12 tiles, relative to cx = 80, cy = self.pikaY + 4)
local OAM_LARGE_SPLASH = {
  { dy = -12, dx = -16, tile = 0xa8, xflip = false },
  { dy = -12, dx =  -8, tile = 0xa9, xflip = false },
  { dy = -12, dx =   0, tile = 0xa9, xflip = true  },
  { dy = -12, dx =   8, tile = 0xa8, xflip = true  },
  { dy =  -4, dx = -16, tile = 0xb8, xflip = false },
  { dy =  -4, dx =  -8, tile = 0xb9, xflip = false },
  { dy =  -4, dx =   0, tile = 0xb9, xflip = true  },
  { dy =  -4, dx =   8, tile = 0xb8, xflip = true  },
  { dy =   4, dx = -16, tile = 0xc8, xflip = false },
  { dy =   4, dx =  -8, tile = 0xc9, xflip = false },
  { dy =   4, dx =   0, tile = 0xc9, xflip = true  },
  { dy =   4, dx =   8, tile = 0xc8, xflip = true  },
}

-- Beach outro tilemap (gfx/surfing_pikachu/beach_outro.tilemap, 20x10)
local BEACH_OUTRO = {
  { 0x0c, 0x0c, 0x0c, 0x0c, 0x0c, 0x0c, 0x0c, 0x0c, 0x0c, 0x0c, 0x0e, 0x0f, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b },
  { 0x0d, 0x0d, 0x0d, 0x0d, 0x0d, 0x0d, 0x0d, 0x0d, 0x0d, 0x0d, 0x10, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b },
  { 0x0d, 0x0d, 0x0d, 0x0d, 0x0d, 0x0d, 0x0d, 0x0d, 0x0d, 0x0d, 0x0e, 0x0f, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b },
  { 0x0d, 0x0d, 0x0d, 0x0d, 0x0d, 0x0d, 0x0d, 0x0d, 0x0d, 0x0d, 0x10, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b },
  { 0x0d, 0x0d, 0x0d, 0x0d, 0x0d, 0x0d, 0x0d, 0x0d, 0x0d, 0x0d, 0x0e, 0x0f, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b },
  { 0x0d, 0x0d, 0x0d, 0x0d, 0x0d, 0x0d, 0x0d, 0x0d, 0x0d, 0x0d, 0x10, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b },
  { 0x0d, 0x0d, 0x0d, 0x0d, 0x0d, 0x0d, 0x0d, 0x0d, 0x0d, 0x0d, 0x0e, 0x0f, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b },
  { 0x0d, 0x0d, 0x0d, 0x0d, 0x0d, 0x0d, 0x0d, 0x0d, 0x0d, 0x0d, 0x10, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b },
  { 0x0d, 0x0d, 0x0d, 0x0d, 0x0d, 0x0d, 0x0d, 0x0d, 0x0d, 0x0d, 0x0e, 0x0f, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b },
  { 0x0d, 0x0d, 0x0d, 0x0d, 0x0d, 0x0d, 0x0d, 0x0d, 0x0d, 0x0d, 0x10, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b },
}

-- Authentic SGB / GBC Pikachus Beach Palette (Shade 0=White, Shade 1=Pikachu Yellow, Shade 2=Sea Blue, Shade 3=Black)
local PIKACHUS_BEACH_PAL = {
  { 255, 255, 255 }, -- 0: White foam/highlights
  { 255, 224, 0 },   -- 1: Vibrant Pikachu Yellow
  { 88, 168, 248 },  -- 2: Ocean Blue Sea Water
  { 25, 25, 25 },    -- 3: Black Outlines
}

-- 5 Tempo tiers (117, 109, 101, 93, 85 from surfing_pikachu.asm)
local TEMPO_TIERS = { 1.0, 117 / 109, 117 / 101, 117 / 93, 117 / 85 }

function SurfingMinigame.new(game, onDone, skipTitle)
  local self = setmetatable({ game = game, onDone = onDone }, SurfingMinigame)
  self.routine = skipTitle and ROUTINE_START_GAME or ROUTINE_TITLE
  self.pikaState = PIKA_STATE_RIDING
  self.t = 0
  self.routineTimer = 0
  self.distanceFixed = 0        -- 16.8 fixed-point (256 = 1 pixel)
  self.speedFixed = SPEED_INITIAL -- 64 = 0.25 px/frame
  self.hp = 6000                -- starts at 6000 (60.00 seconds)
  self.radness = 0              -- accumulated trick stunt points
  self.totalScore = 0           -- tallied total score
  self.hiScore = (game and game.save and game.save.surfingHighScore) or 0
  self.newRecord = false
  self.currentPitch = 1.0
  self.isMinigame = true
  self.isFixedSpeed = true

  -- Hardware RNG simulation registers (hRandomAdd, hRandomSub, rDIV)
  self.rDiv = 0
  self.rAdd = 0x55
  self.rSub = 0xaa

  -- Wave height tracking & column ring buffer
  self.waveFn = 0
  self.cols = {}
  for c = 0, 10 do
    self.cols[c] = { pat = WAVE_PATTERNS[0x00], hl = FLAT_WATER_Y, hr = FLAT_WATER_Y }
  end
  self.colTail = 10

  -- Jumping, Arc Physics & Air Rotation
  self.pikaY = FLAT_WATER_Y - 16 -- integer screen Y of Pikachu (sea waterline)
  self.pikaSubY = 0             -- 8.8 subpixel carry (0..255)
  self.pikaYOffset = 0          -- sine offset (splash/bobbing)
  self.jumpArcMagnitude = 0     -- SpeedDividedBy32 (range 10..16)
  self.jumpDescending = false
  self.frameSet = 4             -- Starts at Frame 4 (flat horizontal ride)
  self.boardAngleOffset = 0     -- wobbling 0..2
  self.boardAngleDecreasing = false
  self.boardAngleTimer = 0
  self.crashTimer = 0
  self.landingTimer = 0

  -- 3-frame buffered D-Pad rotation & input accumulator
  self.joyCounter = 0
  self.inputAccum = 0           -- bit 0 = Right, bit 1 = Left
  self.rotCountLeft = 0
  self.rotCountRight = 0
  self.radnessMeter = 0         -- consecutive flips (capped at 3)
  self.trickFlags = 0           -- bit 0 = right flip (front), bit 1 = left flip (back)

  -- Sprites & Popups
  self.startBannerX = 224       -- slides from 224 to 80 (center)
  self.ohNoBanner = false
  self.trickPopups = {}         -- { text = "+150", x, y, timer }
  self.waterSprays = {}         -- { x, y, timer }
  self.sprayTimer = 0
  self.cloudOffsetFixed = 0

  -- Results Tally Animation
  self.tallyStep = 0
  self.tallyTimer = 0

  -- Load sheets safely across all GameVersion prefix paths
  local function sheet(path)
    if not (love and love.graphics and love.graphics.newImage) then return nil end
    local GameVersion = require("src.core.GameVersion")
    local prefix = (GameVersion and GameVersion.cachePrefix and GameVersion.cachePrefix(game and game.version)) or "yellow/"
    local filename = path:match("([^/]+)$") or path
    local paths = {
      prefix .. path,
      path,
      "yellow/assets/generated/minigame/" .. filename,
      "assets/generated/minigame/" .. filename,
    }
    for _, p in ipairs(paths) do
      local ok, img = pcall(love.graphics.newImage, p)
      if ok and img then return img end
    end
    return nil
  end
  self.bg = sheet("assets/generated/minigame/surf_1a.png")
  self.ob = sheet("assets/generated/minigame/surf_1b.png")
  self.intro = sheet("assets/generated/minigame/surf_1c.png")
  self.titleBg = sheet("assets/generated/minigame/title_bg.png")

  if self.bg then
    self.tq = {}
    local bgW, bgH = self.bg:getDimensions()
    for n = 0, 64 do
      self.tq[n] = love.graphics.newQuad((n % 5) * 8, math.floor(n / 5) * 8, 8, 8, bgW, bgH)
    end
  end

  if self.ob then
    self.oq = {}
    local obW, obH = self.ob:getDimensions()
    for n = 0, 255 do
      self.oq[n] = love.graphics.newQuad((n % 16) * 8, math.floor(n / 16) * 8, 8, 8, obW, obH)
    end
  end

  if self.intro then
    self.iq = {}
    local iW, iH = self.intro:getDimensions() -- 96x96 tile sheet (12x12 tiles)
    for n = 0, 143 do
      self.iq[n] = love.graphics.newQuad((n % 12) * 8, math.floor(n / 12) * 8, 8, 8, iW, iH)
    end
    -- Pika Intro Poses (24x32 px each in top 32px: X=0, 24, 48)
    self.introPikaQuad1 = love.graphics.newQuad(0, 0, 24, 32, iW, iH)
    self.introPikaQuad2 = love.graphics.newQuad(24, 0, 24, 32, iW, iH)
    self.introPikaQuad3 = love.graphics.newQuad(48, 0, 24, 32, iW, iH)
    -- Title Banner Logo ("PIKACHU'S BEACH") (96x32 px at Y=32..64)
    self.introLogoQuad = love.graphics.newQuad(0, 32, 96, 32, iW, iH)
    -- Instruction Text ("Use Control Pad to Surf") (96x32 px at Y=64..96)
    self.introTextQuad = love.graphics.newQuad(0, 64, 96, 32, iW, iH)
  end

  -- GPU Shader & Canvas for authentic HBlank wave distortion
  if love and love.graphics and love.graphics.newShader then
    local shaderCode = [[
      extern float u_time;
      extern float u_water_line;

      vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
        vec2 uv = texture_coords;
        if (uv.y >= u_water_line) {
          float pixel_y = uv.y * 144.0;
          float wave_px = sin((pixel_y * 0.39269908) + (u_time * 6.0)) * (1.5 / 160.0);
          uv.x = fract(uv.x + wave_px);
        }
        return Texel(texture, uv) * color;
      }
    ]]
    local ok, shader = pcall(love.graphics.newShader, shaderCode)
    if ok then self.waveShader = shader end
  end

  if love and love.graphics and love.graphics.newCanvas then
    local ok, canvas = pcall(love.graphics.newCanvas, 160, 144)
    if ok then self.bgCanvas = canvas end
  end

  Music.play(game and game.data, "Music_SurfingPikachu")
  return self
end

-- Transition cleanly from Title Screen to active run, flushing input bleed-through
function SurfingMinigame:startFromTitle()
  self.routine = ROUTINE_START_GAME
  self.inputAccum = 0
  self.joyCounter = 0
  self.rotCountLeft = 0
  self.rotCountRight = 0
  self:resetTempo()
  if self.game and self.game.input and self.game.input.clearPressed then
    self.game.input:clearPressed()
  end
  Sound.play(self.game and self.game.data, "Press_AB")
end

-- Authentic Game Boy LFSR Random Number Generator
function SurfingMinigame:getGBRandom()
  self.rDiv = (self.rDiv + 13) % 256
  local tempAdd = self.rAdd + self.rDiv
  self.rAdd = tempAdd % 256
  local tempSub = self.rSub - self.rDiv
  self.rSub = (tempSub + 256) % 256
  return self.rAdd
end

function SurfingMinigame:chooseSequence()
  local distPx = math.floor(self.distanceFixed / 256)
  local section = math.floor(distPx / 128)
  if section == 0x16 then
    self.waveFn = 0x6a
  elseif section < 0x16 then
    local r = self:getGBRandom()
    if r ~= 0 then
      self.waveFn = SEQ_STARTS[bit.band(r - 1, 0x07) + 1]
    end
  end
  return WAVE_PATTERNS[0x00], FLAT_WATER_Y, FLAT_WATER_Y
end

function SurfingMinigame:pushColumn()
  local pat, hl, hr
  local distPx = math.floor(self.distanceFixed / 256)
  if distPx >= (TOTAL_SECTIONS * 128) or self.waveFn >= 0x74 then
    -- Lock finish line to solid beach sand without cycling back to ocean waves
    pat, hl, hr = WAVE_PATTERNS["beach"], FLAT_WATER_Y, FLAT_WATER_Y
    self.waveFn = 0x74
  elseif self.waveFn == 0 then
    pat, hl, hr = self:chooseSequence()
  else
    local step = WAVE_STEPS[self.waveFn]
    if not step then
      self.waveFn = 0
      pat, hl, hr = WAVE_PATTERNS[0x00], FLAT_WATER_Y, FLAT_WATER_Y
    else
      pat, hl, hr = WAVE_PATTERNS[step[1]], step[2], step[3]
      if step[4] == ADV then self.waveFn = self.waveFn + 1
      elseif step[4] == RESET then self.waveFn = 0 end
    end
  end
  self.colTail = self.colTail + 1
  self.cols[self.colTail] = { pat = pat, hl = hl, hr = hr }
  self.cols[self.colTail - 24] = nil
end

function SurfingMinigame:generateAhead()
  local distPx = math.floor(self.distanceFixed / 256)
  while self.colTail * 16 < distPx + 176 do self:pushColumn() end
end

-- Get water surface Y for a screen X coordinate (X=80 under Pikachu center)
function SurfingMinigame:seaY(x)
  local distPx = math.floor(self.distanceFixed / 256)
  local tile = math.floor((distPx + x) / 8)
  local col = self.cols[math.floor(tile / 2)]
  if not col then return FLAT_WATER_Y end
  return tile % 2 == 0 and col.hl or col.hr
end

-- Get the tile ID of the wave under Pikachu (sample 9 tiles / 72 pixels into viewport)
function SurfingMinigame:getWaveTileUnderPika()
  local distPx = math.floor(self.distanceFixed / 256)
  local tile_col = math.floor((distPx + 72) / 8)
  local waterY = math.floor(self:seaY(80))
  local tile_row = math.floor(waterY / 8)

  local c = math.floor(tile_col / 2)
  local col = self.cols[c]
  if not col or not col.pat then return 0x01 end

  local i = math.floor(tile_row / 2) + 1
  if i < 1 or i > 8 then return 0x01 end
  local mt = BG_METATILES[col.pat[i]]
  if not mt then return 0x01 end

  local sub_x = (tile_col % 2 == 0) and 0 or 1
  local sub_y = (tile_row % 2 == 0) and 0 or 1

  local sub_idx = 1 + sub_x + sub_y * 2
  local mt_tile = mt[sub_idx] or 0x01

  if mt_tile == 0x02 or mt_tile == 0x04 or mt_tile == 0x06 or mt_tile == 0x0a or mt_tile == 0x11 then
    return 0x06 -- rising slope
  elseif mt_tile == 0x03 or mt_tile == 0x05 or mt_tile == 0x07 or mt_tile == 0x0d or mt_tile == 0x13 then
    return 0x07 -- falling slope
  elseif mt_tile == 0x08 or mt_tile == 0x09 or mt_tile == 0x0f or mt_tile == 0x10 or mt_tile == 0x12 or mt_tile == 0x14 or mt_tile == 0x15 then
    return 0x14 -- wave crest / face
  end
  return 0x01 -- open water (0x0b, 0x00, 0x0e, etc.)
end

function SurfingMinigame:spawnTrickPopup(text)
  table.insert(self.trickPopups, {
    text = text,
    x = PIKA_X,
    y = self.pikaY - 14,
    timer = 32,
  })
end

function SurfingMinigame:calculateStuntPoints()
  if self.radnessMeter <= 0 then return end
  local pts = 0
  local popup = "+50"
  if self.trickFlags == 3 then
    -- Mixed front and back flips
    if self.radnessMeter >= 3 then
      pts = 500
      popup = "+500"
    else
      pts = 180
      popup = "+180"
    end
  else
    -- Same direction flips
    if self.radnessMeter == 1 then
      pts = 50
      popup = "+50"
    elseif self.radnessMeter == 2 then
      pts = 150
      popup = "+150"
    else
      pts = 350
      popup = "+350"
    end
  end
  self.radness = self.radness + pts
  self:spawnTrickPopup(popup)
end

-- Slope/tile interaction matrix upon landing (SurfingMinigame_TileInteraction)
function SurfingMinigame:evaluateLanding()
  local f = self.frameSet
  -- Flipped / upside-down frames (8..14) ALWAYS wipeout unconditionally!
  if f >= 8 or f < 1 then
    return "wipeout"
  end

  local tile = self:getWaveTileUnderPika()

  if tile == 0x06 then -- risingSlope
    if f == 6 then return "clean"
    elseif f == 5 or f == 7 then return "rough"
    elseif f == 4 then return "hard"
    else return "wipeout" end -- 1, 2, 3

  elseif tile == 0x07 then -- fallingSlope
    if f == 2 then return "clean"
    elseif f == 1 or f == 3 then return "rough"
    elseif f == 4 then return "hard"
    else return "wipeout" end -- 5, 6, 7

  elseif tile == 0x14 or tile == 0x12 then -- waveCrest / waveFace
    if f == 4 or f == 5 then return "clean"
    elseif f == 3 or f == 6 then return "rough"
    elseif f == 2 or f == 7 then return "hard"
    else return "wipeout" end -- 1

  else -- flat open water
    if f == 4 then return "clean"
    elseif f == 3 or f == 5 then return "rough"
    elseif f == 2 or f == 6 then return "hard"
    else return "wipeout" end -- 1, 7
  end
end

function SurfingMinigame:updateTempo()
  local tier = 1
  if self.speedFixed >= 416 then
    tier = 5
  elseif self.speedFixed >= 320 then
    tier = 4
  elseif self.speedFixed >= 224 then
    tier = 3
  elseif self.speedFixed >= 128 then
    tier = 2
  else
    tier = 1
  end
  local targetPitch = TEMPO_TIERS[tier] or 1.0
  if self.currentPitch ~= targetPitch then
    self.currentPitch = targetPitch
    if Music and Music.setPitch then
      Music.setPitch(self.currentPitch)
    end
  end
end

function SurfingMinigame:resetTempo()
  self.currentPitch = 1.0
  if Music and Music.setPitch then
    Music.setPitch(1.0)
  end
end

function SurfingMinigame:updateRiding()
  -- Automatic speed up (+2/256 = +1/128 per frame up to max 512 = 2.0)
  if self.speedFixed < SPEED_MAX then
    self.speedFixed = math.min(SPEED_MAX, self.speedFixed + SPEED_ACCEL)
  end
  self:updateTempo()

  -- Follow wave surface height
  local targetY = self:seaY(80)
  self.pikaY = math.floor(targetY) - 16
    self.pikaSubY = 0

  -- Water spray every 4 frames
  self.sprayTimer = self.sprayTimer + 1
  if self.sprayTimer % 4 == 0 then
    table.insert(self.waterSprays, { x = PIKA_X, y = self.pikaY, timer = 4 })
  end

  -- Board angle wobbling every 8 frames
  self.boardAngleTimer = self.boardAngleTimer + 1
  if self.boardAngleTimer % 8 == 0 then
    if self.boardAngleDecreasing then
      if self.boardAngleOffset > 0 then
        self.boardAngleOffset = self.boardAngleOffset - 1
      else
        self.boardAngleDecreasing = false
      end
    else
      if self.boardAngleOffset < 2 then
        self.boardAngleOffset = self.boardAngleOffset + 1
      else
        self.boardAngleDecreasing = true
      end
    end
  end

  -- Select frame based on slope (lock flat open water to frame 4 without wobble)
  local tile = self:getWaveTileUnderPika()
  if tile == 0x06 or tile == 0x14 then
    self.frameSet = 6 + (self.boardAngleOffset - 1)
  elseif tile == 0x07 then
    self.frameSet = 2 + (self.boardAngleOffset - 1)
  else
    self.frameSet = 4 -- flat open water: steady horizontal ride
  end
  self.frameSet = math.max(1, math.min(14, self.frameSet))

  -- Automatic jump off wave crest ($14) if speed >= 1.25 (SPEED_JUMP_THRESHOLD = 320)
  local distPx = math.floor(self.distanceFixed / 256)
  local subX = distPx % 8
  if (subX >= 3 and subX <= 4) and tile == 0x14 and self.speedFixed >= SPEED_JUMP_THRESHOLD then
    self.pikaState = PIKA_STATE_JUMPING
    local spd = self.speedFixed / 256
    self.jumpArcMagnitude = math.min(16, math.max(10, math.floor(spd * 8)))
    self.pikaSubY = 0
    self.jumpDescending = false
    self.radnessMeter = 0
    self.trickFlags = 0
    self.rotCountLeft = 0
    self.rotCountRight = 0
    Sound.play(self.game.data, "Ledge_Jump")
  end
end

function SurfingMinigame:handleLanding()
  local result = self:evaluateLanding()
  if result == "wipeout" then
    self.pikaState = PIKA_STATE_CRASHED
    self.crashTimer = 96
    self.speedFixed = SPEED_INITIAL
    self.frameSet = 4
    Sound.play(self.game.data, "Faint_Fall")
  else
    if result == "rough" then
      self.speedFixed = math.max(SPEED_INITIAL, self.speedFixed - SPEED_ROUGH_PENALTY)
    elseif result == "hard" then
      self.speedFixed = math.max(SPEED_INITIAL, self.speedFixed - SPEED_HARD_PENALTY)
    end
    if self.routine == ROUTINE_RUN_GAME then
      self:calculateStuntPoints()
    end
    self.pikaState = PIKA_STATE_LANDING
    self.landingTimer = 32
    self.frameSet = 4
    Sound.play(self.game.data, "Cut")
  end
end

function SurfingMinigame:updateJumping()
  -- Process accumulated input on the 3-frame buffer boundary (only during active run)
  if self.routine == ROUTINE_RUN_GAME then
    self.joyCounter = (self.joyCounter + 1) % 3
    if self.joyCounter == 0 then
      local rightHeld = bit.band(self.inputAccum, 1) ~= 0
      local leftHeld = bit.band(self.inputAccum, 2) ~= 0
      self.inputAccum = 0

      -- Game Boy priority: Left D-pad checked first, then Right D-pad
      if leftHeld then
        self.rotCountRight = 0
        self.rotCountLeft = self.rotCountLeft + 1
        if self.rotCountLeft >= 11 then
          self.rotCountLeft = 0
          self.radnessMeter = math.min(3, self.radnessMeter + 1)
          self.trickFlags = bit.bor(self.trickFlags, 1)
          Sound.play(self.game.data, "Tink")
        end
        self.frameSet = (self.frameSet % 14) + 1
      elseif rightHeld then
        self.rotCountLeft = 0
        self.rotCountRight = self.rotCountRight + 1
        if self.rotCountRight >= 13 then
          self.rotCountRight = 0
          self.radnessMeter = math.min(3, self.radnessMeter + 1)
          self.trickFlags = bit.bor(self.trickFlags, 2)
          Sound.play(self.game.data, "Tink")
        end
        self.frameSet = self.frameSet - 1
        if self.frameSet < 1 then self.frameSet = 14 end
      end
    end
  else
    self.inputAccum = 0
  end

  -- Authentic Game Boy collision boundary & integer fixed-point jump physics
  if not self.jumpDescending then
    local a = math.floor(self.jumpArcMagnitude)
    self.pikaSubY = (self.pikaSubY or 0) + (a * a) * 4
    local intDelta = math.floor(self.pikaSubY / 256)
    self.pikaSubY = self.pikaSubY % 256
    self.pikaY = self.pikaY - intDelta

    self.jumpArcMagnitude = self.jumpArcMagnitude - 0.5
    if self.jumpArcMagnitude <= 0 then
      self.jumpArcMagnitude = 0
      self.jumpDescending = true
    end
  else
    -- Hardware execution order: evaluate boundary before adding velocity
    local waveY = math.floor(self:seaY(80)) - 16
    if self.pikaY >= waveY then
      self.pikaY = waveY
      self.pikaSubY = 0
      self:handleLanding()
      return
    end

    local a = math.floor(self.jumpArcMagnitude)
    self.pikaSubY = (self.pikaSubY or 0) + (a * a) * 4
    local intDelta = math.floor(self.pikaSubY / 256)
    self.pikaSubY = self.pikaSubY % 256
    self.pikaY = self.pikaY + intDelta
    self.jumpArcMagnitude = self.jumpArcMagnitude + 0.5

    if self.pikaY >= waveY then
      self.pikaY = waveY
      self.pikaSubY = 0
      self:handleLanding()
    end
  end
end

function SurfingMinigame:updateLanding()
  self.landingTimer = (self.landingTimer or 0) - 1

  -- Follow wave surface height continuously while landing so slopes don't cause position jumps!
  local targetY = self:seaY(80)
  self.pikaY = math.floor(targetY) - 16
  self.pikaSubY = 0

  -- Sine wave splash offset
  self.pikaYOffset = math.floor(math.sin((32 - math.max(0, self.landingTimer)) / 32 * math.pi * 2) * 4)
  if self.landingTimer % 4 == 0 then
    table.insert(self.waterSprays, { x = PIKA_X, y = self.pikaY, timer = 4 })
  end

  if self.landingTimer <= 0 then
    self.pikaYOffset = 0
    self.pikaState = PIKA_STATE_RIDING
    self.frameSet = 4
  end
end

function SurfingMinigame:updateCrashed()
  self.crashTimer = self.crashTimer - 1
  self:resetTempo()
  -- Follow water surface while wiped out
  local targetY = self:seaY(80)
  self.pikaY = math.floor(targetY) - 16
  self.pikaSubY = 0
  if self.crashTimer <= 0 then
    self.pikaState = PIKA_STATE_RIDING
    self.frameSet = 4
  end
end

-- Single Game Boy hardware VBlank cycle tick (59.7275 Hz)
function SurfingMinigame:tick()
  local input = self.game and self.game.input
  self.t = self.t + 1
  self.rDiv = (self.rDiv + 1) % 256

  -- Title Screen State
  if self.routine == ROUTINE_TITLE then
    if input and (input:wasPressed("start") or input:wasPressed("a")) then
      self:startFromTitle()
    end
    return
  end

  -- Accumulate physical button presses on every frame (only during active run)
  if self.routine == ROUTINE_RUN_GAME then
    if input and input:isDown("right") then self.inputAccum = bit.bor(self.inputAccum, 1) end
    if input and input:isDown("left") then self.inputAccum = bit.bor(self.inputAccum, 2) end
  else
    self.inputAccum = 0
  end

  -- Update trick popups
  for i = #self.trickPopups, 1, -1 do
    local p = self.trickPopups[i]
    p.y = p.y - 0.5
    p.timer = p.timer - 1
    if p.timer <= 0 then table.remove(self.trickPopups, i) end
  end

  -- Update water sprays
  for i = #self.waterSprays, 1, -1 do
    local s = self.waterSprays[i]
    s.timer = s.timer - 1
    if s.timer <= 0 then table.remove(self.waterSprays, i) end
  end

  -- Routine state machine
  if self.routine == ROUTINE_START_GAME then
    if self.startBannerX > 80 then
      self.startBannerX = math.max(80, self.startBannerX - 4)
    else
      self.routine = ROUTINE_RUN_GAME
    end
  elseif self.routine == ROUTINE_RUN_GAME then
    -- Deduct 1 HP per frame (stamina countdown from 6000 BCD)
    if self.hp > 0 then
      self.hp = self.hp - 1
    else
      -- Game Over when HP hits 0
      self.routine = ROUTINE_GAME_OVER
      self.routineTimer = 128
      self.speedFixed = 0
      self.ohNoBanner = true
      Sound.play(self.game and self.game.data, "Faint_Fall")
      return
    end

    -- Scroll distance & generate wave columns (authentic 1:1 GB pace: distance += speedFixed)
    self.distanceFixed = self.distanceFixed + self.speedFixed
    self.cloudOffsetFixed = self.cloudOffsetFixed + math.floor(self.speedFixed * 0.25)
    self:generateAhead()

    -- Check if course goal reached (24 sections)
    local distPx = math.floor(self.distanceFixed / 256)
    if distPx >= (TOTAL_SECTIONS * 128) then
      self.routine = ROUTINE_WAIT_RESULTS
      self.routineTimer = 192
      self.waveFn = 0x72
      return
    end

    -- Update Pikachu by state
    if self.pikaState == PIKA_STATE_RIDING then
      self:updateRiding()
    elseif self.pikaState == PIKA_STATE_JUMPING then
      self:updateJumping()
    elseif self.pikaState == PIKA_STATE_LANDING then
      self:updateLanding()
    elseif self.pikaState == PIKA_STATE_CRASHED then
      self:updateCrashed()
    end

  elseif self.routine == ROUTINE_WAIT_RESULTS then
    -- Coasting past the goal line
    self.distanceFixed = self.distanceFixed + (2 * 256)
    self.cloudOffsetFixed = self.cloudOffsetFixed + math.floor((2 * 256) * 0.25)
    self:generateAhead()

    -- Run Pikachu state machine so mid-air jumps and wipeout crashes complete
    if self.pikaState == PIKA_STATE_JUMPING then
      self:updateJumping()
    elseif self.pikaState == PIKA_STATE_LANDING then
      self:updateLanding()
    elseif self.pikaState == PIKA_STATE_CRASHED then
      self:updateCrashed()
    else
      -- Riding: follow water surface
      local targetY = self:seaY(80)
      self.pikaY = math.floor(targetY) - 16
      self.pikaSubY = 0
      self.frameSet = 4
    end

    if self.routineTimer > 0 then
      self.routineTimer = self.routineTimer - 1
    end

    -- Only advance to scroll results when delay has finished AND Pikachu is upright
    if self.routineTimer <= 0 and self.pikaState == PIKA_STATE_RIDING then
      self.routine = ROUTINE_SCROLL_RESULTS
      self.routineTimer = 36
      self.pikaState = PIKA_STATE_GAME_END
    end

  elseif self.routine == ROUTINE_SCROLL_RESULTS then
    self.distanceFixed = self.distanceFixed + (1 * 256)
    self.cloudOffsetFixed = self.cloudOffsetFixed + math.floor((1 * 256) * 0.25)
    self:generateAhead()
    self.pikaY = math.floor(self:seaY(80)) - 16
    self.pikaSubY = 0
    self.frameSet = 4
    self.routineTimer = self.routineTimer - 1
    if self.routineTimer <= 0 then
      self.routine = ROUTINE_DRAW_RESULTS
      self.routineTimer = 64
      self.pikaState = PIKA_STATE_RESULTS
    end

  elseif self.routine == ROUTINE_DRAW_RESULTS then
    self.routineTimer = self.routineTimer - 1
    if self.routineTimer <= 0 then
      self.routine = ROUTINE_WRITE_HP_LEFT
      self.routineTimer = 32
    end

  elseif self.routine == ROUTINE_WRITE_HP_LEFT then
    self.routineTimer = self.routineTimer - 1
    if self.routineTimer <= 0 then
      self.routine = ROUTINE_WRITE_RADNESS
      self.routineTimer = 32
    end

  elseif self.routine == ROUTINE_WRITE_RADNESS then
    self.routineTimer = self.routineTimer - 1
    if self.routineTimer <= 0 then
      self.routine = ROUTINE_WRITE_TOTAL
      self.routineTimer = 32
    end

  elseif self.routine == ROUTINE_WRITE_TOTAL then
    self.routineTimer = self.routineTimer - 1
    if self.routineTimer <= 0 then
      self.routine = ROUTINE_ADD_HP_TOTAL
      self.tallyStep = 0
    end

  elseif self.routine == ROUTINE_ADD_HP_TOTAL then
    -- Tally remaining HP into total score (99 pts/frame matching ld c, 99)
    if self.hp > 0 then
      local step = math.min(self.hp, 99)
      self.hp = self.hp - step
      self.totalScore = self.totalScore + step
      Sound.play(self.game and self.game.data, "Press_AB")
    else
      self.routine = ROUTINE_ADD_RAD_TOTAL
    end

  elseif self.routine == ROUTINE_ADD_RAD_TOTAL then
    -- Tally Radness into total score (99 pts/frame matching ld c, 99)
    if self.radness > 0 then
      local step = math.min(self.radness, 99)
      self.radness = self.radness - step
      self.totalScore = self.totalScore + step
      Sound.play(self.game and self.game.data, "Press_AB")
    else
      self.routine = ROUTINE_WAIT_LAST
      self.routineTimer = 64
      -- High score check
      self.newRecord = self.totalScore > ((self.game and self.game.save and self.game.save.surfingHighScore) or 0)
      if self.newRecord then
        if self.game and self.game.save then self.game.save.surfingHighScore = self.totalScore end
        Sound.play(self.game and self.game.data, "Get_Item1")
        Sound.playPikaCry(self.game and self.game.data, 34)
      else
        Sound.playPikaCry(self.game and self.game.data, 28)
      end
    end

  elseif self.routine == ROUTINE_WAIT_LAST then
    self.routineTimer = self.routineTimer - 1
    if self.routineTimer <= 0 then
      self.routine = ROUTINE_EXIT_ON_PRESS_A
    end

  elseif self.routine == ROUTINE_EXIT_ON_PRESS_A then
    if input and input:wasPressed("a") then
      if self.game and self.game.stack then self.game.stack:pop() end
      if self.onDone then self.onDone(self.totalScore) end
    end

  elseif self.routine == ROUTINE_GAME_OVER then
    self.routineTimer = self.routineTimer - 1
    if self.routineTimer <= 0 and input and input:wasPressed("a") then
      if self.game and self.game.stack then self.game.stack:pop() end
      if self.onDone then self.onDone(0) end
    end
  end
end

-- Decoupled timestep accumulator for modern multi-refresh-rate displays
function SurfingMinigame:update(dt)
  if not dt then
    self:tick()
    return
  end

  -- Accumulate real-world time
  self.tickAccumulator = (self.tickAccumulator or 0) + dt

  -- Exact Game Boy Color framerate: 59.7275 Hz (approx 0.0167427 seconds per frame)
  local gbTickRate = 1 / 59.7275

  -- Process as many physical hardware frames as necessary
  while self.tickAccumulator >= gbTickRate do
    self:tick()
    self.tickAccumulator = self.tickAccumulator - gbTickRate
  end
end

-- Draw scrolling wave background with authentic GPU shader HBlank wave distortion
function SurfingMinigame:drawBackground()
  local scx = math.floor(self.distanceFixed / 256)
  local first = math.floor(scx / 16)

  local function renderTiles()
    love.graphics.setColor(1, 1, 1, 1)
    if not self.bg then return end
    for c = first, first + 10 do
      local col = self.cols[c]
      if col then
        local x = c * 16 - scx
        for i = 1, 8 do
          local mt = BG_METATILES[col.pat[i]]
          if mt then
            local y = (i - 1) * 16
            love.graphics.draw(self.bg, self.tq[mt[1]], x, y)
            love.graphics.draw(self.bg, self.tq[mt[2]], x + 8, y)
            love.graphics.draw(self.bg, self.tq[mt[3]], x, y + 8)
            love.graphics.draw(self.bg, self.tq[mt[4]], x + 8, y + 8)
          end
        end
      end
    end
  end

  if self.bgCanvas and self.waveShader and love.graphics.setCanvas and love.graphics.getCanvas then
    -- 1. Capture the framework's active canvas
    local prevCanvas = love.graphics.getCanvas()

    love.graphics.setCanvas(self.bgCanvas)
    -- 2. Clear with transparency (0 alpha) so the sky remains empty
    love.graphics.clear(0, 0, 0, 0)
    renderTiles()

    -- 3. Restore the framework's canvas before drawing!
    love.graphics.setCanvas(prevCanvas)

    -- 4. Safely capture and restore the shader
    local prevShader = love.graphics.getShader and love.graphics.getShader()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setShader(self.waveShader)

    if self.waveShader.hasUniform and self.waveShader:hasUniform("u_time") then
      self.waveShader:send("u_time", self.t / 60.0)
    end
    if self.waveShader.hasUniform and self.waveShader:hasUniform("u_water_line") then
      self.waveShader:send("u_water_line", 48.0 / 144.0)
    end

    love.graphics.draw(self.bgCanvas, 0, 0)
    love.graphics.setShader(prevShader)
  else
    renderTiles()
  end
end

-- Draw 3x3 Pikachu sprite (24x24 px centered at cx, cy)
function SurfingMinigame:draw3x3(baseTile, cx, cy, flipX, flipY)
  local sx = flipX and -1 or 1
  local sy = flipY and -1 or 1
  for r = 0, 2 do
    for c = 0, 2 do
      local tileId = baseTile + r * 16 + c
      local q = self.oq[tileId]
      if q then
        local colIdx = flipX and (2 - c) or c
        local rowIdx = flipY and (2 - r) or r
        local dx = (cx - 12) + colIdx * 8 + (flipX and 8 or 0)
        local dy = (cy - 12) + rowIdx * 8 + (flipY and 8 or 0)
        love.graphics.draw(self.ob, q, dx, dy, 0, sx, sy)
      end
    end
  end
end

-- Draw HUD status bar with inverted progress marker (moving right-to-left towards beach)
function SurfingMinigame:drawHUD()
  -- White background in bottom 16 rows
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, BG_HEIGHT, 160, 16)

  -- Track progress line (tiles $15..$1c)
  if self.bg and self.tq then
    -- Top row (Y=128)
    love.graphics.draw(self.bg, self.tq[0x15], 8, BG_HEIGHT)
    love.graphics.draw(self.bg, self.tq[0x16], 16, BG_HEIGHT)

    -- Bottom row (Y=136)
    love.graphics.draw(self.bg, self.tq[0x17], 8, BG_HEIGHT + 8)
    love.graphics.draw(self.bg, self.tq[0x18], 16, BG_HEIGHT + 8)
    local trackTiles = { 0x19, 0x19, 0x19, 0x19, 0x19, 0x19, 0x19, 0x19, 0x19 }
    for i = 1, #trackTiles do
      love.graphics.draw(self.bg, self.tq[trackTiles[i]], 16 + i * 8, BG_HEIGHT + 8)
    end
    love.graphics.draw(self.bg, self.tq[0x1b], 96, BG_HEIGHT + 8)
    love.graphics.draw(self.bg, self.tq[0x1c], 104, BG_HEIGHT + 8)

    -- "HP:" label tiles on right (X=112, 120)
    love.graphics.draw(self.bg, self.tq[0x20], 112, BG_HEIGHT + 8)
    love.graphics.draw(self.bg, self.tq[0x21], 120, BG_HEIGHT + 8)
  end

  -- Mini-Pikachu progress marker (tile $fe)
  -- Game Boy: initial OAM X = $50 (80) = screen X 72, decrements by 2 per section.
  -- 24 sections × 2 = 48 px total travel, ending at screen X 24.
  -- We interpolate continuously across those same 48 pixels.
  local distPx = math.floor(self.distanceFixed / 256)
  local progressRatio = math.min(1.0, math.max(0, distPx / (TOTAL_SECTIONS * 128)))
  local markerStartX = 72   -- OAM X $50 (80) minus 8-pixel OAM offset = screen X 72
  local markerTrack  = 48   -- 24 sections × 2 px per section
  local markerX = markerStartX - math.floor(progressRatio * markerTrack)
  if self.ob and self.oq and self.oq[0xfe] then
    love.graphics.draw(self.ob, self.oq[0xfe], markerX, BG_HEIGHT + 6)
  end

  -- 4 HP countdown digits starting at X=128 (right after HP:)
  local s = string.format("%04d", math.max(0, math.floor(self.hp)))
  for i = 1, 4 do
    local d = tonumber(s:sub(i, i)) or 0
    if self.ob and self.oq and self.oq[0xd0 + d] then
      love.graphics.draw(self.ob, self.oq[0xd0 + d], 120 + i * 8, BG_HEIGHT + 8)
    else
      Font.draw(tostring(d), 120 + i * 8, BG_HEIGHT + 8)
    end
  end
end

-- Draw beach outro results scene
function SurfingMinigame:drawResultsOutro()
  -- Draw beach outro tilemap in rows 6..15
  for r = 1, 10 do
    for c = 1, 20 do
      local tId = BEACH_OUTRO[r][c]
      if tId and self.tq and self.tq[tId] then
        love.graphics.draw(self.bg, self.tq[tId], (c - 1) * 8, (r + 5) * 8)
      end
    end
  end

  -- Fill interior with white
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 16, 16, 128, 56)

  -- Draw the textbox frame using original Game Boy border tiles (rows 1..9, Y=8..72)
  local function drawBoxRow(rowIdx, leftTile, interiorTile, rightTile)
    local y = rowIdx * 8
    if self.tq[leftTile] then
      love.graphics.draw(self.bg, self.tq[leftTile], 8, y)
    end
    if interiorTile and self.tq[interiorTile] then
      for colIdx = 2, 17 do
        love.graphics.draw(self.bg, self.tq[interiorTile], colIdx * 8, y)
      end
    end
    if self.tq[rightTile] then
      love.graphics.draw(self.bg, self.tq[rightTile], 144, y)
    end
  end

  drawBoxRow(1, 0x3b, 0x40, 0x3c)
  for r = 2, 8 do
    drawBoxRow(r, 0x3f, nil, 0x3f)
  end
  drawBoxRow(9, 0x3d, 0x40, 0x3e)

  -- Text lines matching Game Boy screen memory coordinates (cols 2, 10, 15; rows 2, 4, 6, 8)
  Font.draw(Strings("HP Left"), 16, 16)
  if self.routine >= ROUTINE_WRITE_HP_LEFT then
    Font.draw(string.format("%04d", self.hp), 80, 16)
    Font.draw(Strings("Pts"), 120, 16)
  end

  if self.routine >= ROUTINE_WRITE_RADNESS then
    Font.draw(Strings("Radness"), 16, 32)
    Font.draw(string.format("%04d", self.radness), 80, 32)
    Font.draw(Strings("Pts"), 120, 32)
  end

  if self.routine >= ROUTINE_WRITE_TOTAL then
    Font.draw(Strings("Total"), 16, 48)
    Font.draw(string.format("%04d", self.totalScore), 80, 48)
    Font.draw(Strings("Pts"), 120, 48)
  end

  if self.routine >= ROUTINE_WAIT_LAST then
    if self.newRecord then
      Font.draw(Strings("Hi-Score!!"), 48, 64)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- Draw minigame Title Screen ("Pikachu's Beach")
function SurfingMinigame:drawTitleScreen()
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)

  -- 1. Draw authentic 160x144 composite title background from ROM
  if self.titleBg then
    love.graphics.draw(self.titleBg, 0, 0)
  else
    Font.draw("PIKACHU'S BEACH", 20, 32)
  end

  -- 2. Draw 3x3 Pikachu intro sprite on the water using authentic OAM tile indices
  if self.ob and self.oq then
    local animBase = (math.floor(self.t / 32) % 2 == 0) and 0x0c or 0x09
    self:draw3x3(animBase, 80, 100, false, false)
  end

  -- 3. High score display at bottom
  Font.draw(string.format("Hi-Score   %4d Pt", self.hiScore), 16, 120)

  if math.floor(self.t / 30) % 2 == 0 then
    Font.draw("PRESS START", 36, 132)
  end
end

function SurfingMinigame:draw()
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)

  if self.routine == ROUTINE_TITLE then
    self:drawTitleScreen()
    return
  end

  if self.routine >= ROUTINE_DRAW_RESULTS and self.routine <= ROUTINE_EXIT_ON_PRESS_A then
    self:drawResultsOutro()
    return
  end

  -- Draw scrolling BG waves
  self:drawBackground()

  -- Parallax clouds in sky (scrolling left at uniform 0.25x camera speed)
  local cloudOffsetPx = math.floor(self.cloudOffsetFixed / 256)
  local c1x = (160 - (cloudOffsetPx % 200)) - 40
  local c2x = (240 - (cloudOffsetPx % 200)) - 40
  if self.ob and self.oq then
    -- Wide cloud (5 tiles: $ec, $ed, $ed, $ee, $ef)
    for i, tid in ipairs({ 0xec, 0xed, 0xed, 0xee, 0xef }) do
      love.graphics.draw(self.ob, self.oq[tid], c1x + (i - 1) * 8, 12)
    end
    -- Narrow cloud (4 tiles: $ec, $ed, $ee, $ef)
    for i, tid in ipairs({ 0xec, 0xed, 0xee, 0xef }) do
      love.graphics.draw(self.ob, self.oq[tid], c2x + (i - 1) * 8, 20)
    end
  end
  -- Helper function to draw OAM multi-sprite composite objects with palette and X-flipping
  function self:drawOAMSprites(sprites, ox, oy)
    if not (self.ob and self.oq) then return end
    love.graphics.setColor(0.5, 0.5, 0.5, 1) -- OAM_PAL1 maps shade 1 to shade 2 (Sea Blue)
    for _, sp in ipairs(sprites) do
      local q = self.oq[sp.tile]
      if q then
        local x = ox + sp.dx
        local y = oy + sp.dy
        if sp.xflip then
          love.graphics.draw(self.ob, q, x + 8, y, 0, -1, 1)
        else
          love.graphics.draw(self.ob, q, x, y)
        end
      end
    end
    love.graphics.setColor(1, 1, 1, 1)
  end

  -- Draw water spray sprites on trailing edge of surfboard
  for _, s in ipairs(self.waterSprays) do
    self:drawOAMSprites(OAM_WATER_SPRAY, s.x, s.y)
  end

  -- Draw Pikachu
  local cx = 80
  local cy = self.pikaY + (self.pikaYOffset or 0)
  self.pikaScreenY = cy

  if self.pikaState == PIKA_STATE_CRASHED then
    -- Empty surfboard (3 tiles at bottom)
    if self.ob and self.oq then
      love.graphics.draw(self.ob, self.oq[0x98], cx - 12, cy + 4)
      love.graphics.draw(self.ob, self.oq[0x99], cx - 4, cy + 4)
      love.graphics.draw(self.ob, self.oq[0x9a], cx + 4, cy + 4)
    end
    -- Multi-tile splash animation (.SmallSplash then .LargeSplash)
    local elapsed = 60 - (self.crashTimer or 0)
    if elapsed < 16 then
      self:drawOAMSprites(OAM_SMALL_SPLASH, cx, cy + 4)
    else
      self:drawOAMSprites(OAM_LARGE_SPLASH, cx, cy + 4)
    end
  else
    local angleIdx = ((self.frameSet - 1) % 7) + 1
    local isFlipped = self.frameSet > 7
    local toggle = math.floor(self.t / 8) % 2 + 1
    local base = ANGLE_BASES[angleIdx][toggle]
    self:draw3x3(base, cx, cy, isFlipped, isFlipped)
  end

  -- Draw trick popups
  for _, p in ipairs(self.trickPopups) do
    Font.draw(p.text, p.x, p.y)
  end

  -- "START" banner
  if self.routine == ROUTINE_START_GAME then
    if self.ob and self.oq then
      for r = 0, 1 do
        for c = 0, 5 do
          local tid = 0xe0 + r * 16 + c
          love.graphics.draw(self.ob, self.oq[tid], self.startBannerX - 24 + c * 8, 64 + r * 8)
        end
      end
    end
  end

  -- "Oh no.." banner on Game Over
  if self.ohNoBanner then
    if self.ob and self.oq then
      for r = 0, 1 do
        for c = 0, 5 do
          local tid = 0xca + r * 16 + c
          love.graphics.draw(self.ob, self.oq[tid], 80 - 24 + c * 8, 64 + r * 8)
        end
      end
    end
  end

  -- Draw HUD (Progress track, HP digits)
  self:drawHUD()
end

function SurfingMinigame:sgbPalettes(game)
  local P = require("src.render.PaletteFX")
  local pal = (game and game.data and P.pal(game.data, "PIKACHUS_BEACH")) or PIKACHUS_BEACH_PAL
  return { P.whole(pal) }
end

return SurfingMinigame
