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
-- - 14-angle rotation model with 3-frame joy duty cycle (Right = frontflip, Left = backflip)
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
-- Pret metric audit (surfing_pikachu.asm):
--   Speed: init 0.25, max 2.0 (high byte cp $2), +1/128/frame, jump min GetSpeedDividedBy32 >= $a
--   Penalties: rough -0.25, hard -0.5, wipeout reset 0.25 (underflow guards at 0.25 / 0.5)
--   HP: $6000 BCD, -1/frame; course: 24 sections (distance byte cp $18); Big Kahuna at section $16
--   BG scroll: 1.5 px/frame; coast: 9.0 px/frame for 192 frames; crash $60 frames; landing splash $20/4
--   Flips: left cp $b, right cp $d; radness meter caps at $3; trick flags bits 0=left 1=right
--   Joypad: SurfingPikachu_GetJoypad_3FrameBuffer reloads hFrameCounter with $2 (1 sample + 2 blank frames)
--   Music tempo index: high byte of ((speed & $3ff) << 1) → tiers at speed 128/256/384/512
local SPEED_INITIAL        = 64   -- 0.25 * 256
local SPEED_MAX            = 512  -- 2.00 * 256 (SpeedUpPikachu: high byte cp $2)
local SPEED_ACCEL          = 2    -- 0.0078125 = 1/128 px/frame in 8.8 fixed
local SPEED_ROUGH_PENALTY  = 64   -- 0.25 * 256
local SPEED_HARD_PENALTY   = 128  -- 0.50 * 256
local PIKA_SPRITE_OFFSET = 16   -- sprite anchor above wSurfingMinigamePikachuObjectHeight
local SPEED_JUMP_MIN_DIV32 = 10   -- TryStartJump: GetSpeedDividedBy32 cp $a (speed >= 1.25)
local FLIP_LEFT_FRAMES     = 11   -- DPadAction .dLeft cp $b
local FLIP_RIGHT_FRAMES    = 13   -- DPadAction .dRight cp $d
local RADNESS_METER_MAX    = 3    -- IncreaseRadnessMeter cap
local JOY_FRAME_RELOAD     = 2    -- GetJoypad_3FrameBuffer: ld a, $2
local CRASH_FRAMES         = 96   -- UpdateCrashedPikachu initial timer $60
local COAST_FRAMES         = 192  -- WaitToShowResults routine delay
local GAME_OVER_DELAY      = 128  -- Game over before accepting A ($80)
local LANDING_SPLASH_FRAMES = 8   -- FIELD_C += 4 until cp $20
local RESULTS_FRAMESET_INIT = 0x0f -- InitResultsPikachu: frameset ID written to ANIM_OBJ_FRAME_SET
local RESULTS_BOB_CYCLE     = 64  -- UpdateResultsPikachu FIELD_C & $3f
local RESULTS_BOB_START     = 32  -- sine bob only when FIELD_C >= $20
local RESULTS_BOB_AMP       = 2   -- SurfingPikachu_Sine scale ($10 table; ~2px on screen)
local RESULTS_PIKA_BASES    = { 0xa0, 0xa3 } -- .ResultsPikachu OAM frame pair

-- Original constants (surfing_pikachu.asm)
local FLAT_WATER_Y = 116       -- OAM Y 0x74 = screen Y 100 (PIKA_Y = FLAT_WATER_Y - 16)
local PIKA_X = 68              -- Fixed screen X while riding (center 80, 24px pose)
local TOTAL_SECTIONS = 24      -- wSurfingMinigameDistance byte 0 reaches $18 (24)
local SECTION_ACC_MAX = 65536  -- 16-bit distance acc overflow (256px per section in 8.8 fixed)
local SECTION_PX = 256         -- pixels advanced per section (65536 >> 8)
local BG_HEIGHT = 128          -- Rows the BG shows; HP window covers the rest (y=128..144)
local COAST_SPEED_FIXED = 9 * 256       -- SurfingMinigame_CoastAfterGoal: 9.0 px/frame
local BG_SCROLL_STEP = 384                -- ScrollAndGenerateBGMap: 1.5 px/frame (8.8 fixed)
local RDIV_PER_FRAME = 17                 -- rDIV @ 16384 Hz ≈ 273 ticks per 59.7275 Hz frame (mod 256)
local COAST_X_OFFSET = 160              -- $a0 ahead of viewport (CoastAfterGoal)
local OUTRO_SCROLL_X_OFFSET = 224       -- TILEMAP_WIDTH_PX - 32 (ScrollToResultsScreen)
local OUTRO_SCROLL_START  = 144         -- hSCX $90 at results transition
local OUTRO_SCROLL_STEP   = 4           -- hSCX -= 4 per frame (36 frames total)
local FINISH_DISTANCE_FIXED = TOTAL_SECTIONS * SECTION_PX * 256
local MAP_COLS = 16              -- vBGMap0 metatile columns (256px / 16)
-- SurfingPikachuMinigame_InitStaticSpriteLayout cloud OAM X coords (9 sprites)
local CLOUD_SPRITE_X_INIT = { 32, 40, 48, 56, 64, 128, 136, 144, 152 }

local function scrollPx(self)
  return math.floor((self.scrollFixed or 0) / 256)
end

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

local function isOutroScroll(self)
  return self.routine == ROUTINE_WAIT_RESULTS or self.routine == ROUTINE_SCROLL_RESULTS
end

local function displayScx(self)
  return self.hScx or 0
end

-- SurfingMinigame_UpdateMusicTempo: index = high byte of ((speed & $3ff) << 1)
local function pretTempoTier(speedFixed)
  local lo = bit.band(speedFixed, 0xFF)
  local hi = bit.band(math.floor(speedFixed / 256), 3)
  local shifted = bit.band((lo + hi * 256) * 2, 0xFFFF)
  return math.min(4, math.floor(shifted / 256)) + 1
end

-- SurfingMinigame_GetSpeedDividedBy32 (speed * 8, high byte)
local function getSpeedDividedBy32(speedFixed)
  return math.floor((speedFixed * 8) / 256)
end

local function pikaSpriteYFromObjectHeight(objectHeightPx)
  return math.floor(objectHeightPx or FLAT_WATER_Y) - PIKA_SPRITE_OFFSET
end

-- SurfingMinigame_ReduceSpeedBy64 / ReduceSpeedBy128
local function reduceSpeedBy64(speedFixed)
  if speedFixed >= 256 then
    return speedFixed - SPEED_ROUGH_PENALTY
  elseif speedFixed >= SPEED_INITIAL then
    return speedFixed - SPEED_ROUGH_PENALTY
  end
  return 0
end

local function reduceSpeedBy128(speedFixed)
  if speedFixed >= 256 then
    return speedFixed - SPEED_HARD_PENALTY
  elseif speedFixed >= SPEED_HARD_PENALTY then
    return speedFixed - SPEED_HARD_PENALTY
  end
  return 0
end

local function jumpArcCombined(self)
  return (self.jumpArcMagnitude or 0) * 256 + (self.jumpArcFraction or 0)
end

local function setJumpArcCombined(self, value)
  if value < 0 then value = 0 end
  self.jumpArcMagnitude = math.floor(value / 256)
  self.jumpArcFraction = value % 256
end

local function applyJumpArcDelta(self, delta)
  setJumpArcCombined(self, jumpArcCombined(self) + delta)
end

local function applyJumpVerticalDelta(self, sign)
  local a = self.jumpArcMagnitude or 0
  if a == 0 and (self.jumpArcFraction or 0) == 0 then return end
  self.pikaSubY = (self.pikaSubY or 0) + (a * a) * 4
  local intDelta = math.floor(self.pikaSubY / 256)
  self.pikaSubY = self.pikaSubY % 256
  if sign < 0 then
    self.pikaY = self.pikaY - intDelta
  else
    self.pikaY = self.pikaY + intDelta
  end
end

-- pret GenerateBGMap write column: ((hSCX + XOffset) & $f0) / 16
local function mapColWrite(self)
  local xOffset = COAST_X_OFFSET
  if self.routine == ROUTINE_SCROLL_RESULTS then
    xOffset = OUTRO_SCROLL_X_OFFSET
  end
  local sum = (displayScx(self) + xOffset) % 256
  return math.floor(bit.band(sum, 0xF0) / 16) % MAP_COLS
end

local function mapColScreen(scx, screenCol)
  return (math.floor(scx / 16) + screenCol) % MAP_COLS
end

local function mapColAtX(scx, x)
  return math.floor((scx + x) / 16) % MAP_COLS
end

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

-- Intro title Pikachu (surfing_pikachu_oam.asm .IntroPikachu, frames $20-$23).
-- Each animation frame adds four to the VRAM tile base ($80, $84, $88, $8c);
-- relative tile ids use the usual 16-wide OBJ row stride ($10 per row).
local INTRO_PIKA_FRAME_BASE = { 0x80, 0x84, 0x88, 0x8c }
local INTRO_PIKA_OAM = {
  { dy = -12, dx = -16, tile = 0x03, xflip = true },
  { dy = -12, dx =  -8, tile = 0x02, xflip = true },
  { dy = -12, dx =   0, tile = 0x01, xflip = true },
  { dy = -12, dx =   8, tile = 0x00, xflip = true },
  { dy =  -4, dx = -16, tile = 0x13, xflip = true },
  { dy =  -4, dx =  -8, tile = 0x12, xflip = true },
  { dy =  -4, dx =   0, tile = 0x11, xflip = true },
  { dy =  -4, dx =   8, tile = 0x10, xflip = true },
  { dy =   4, dx = -16, tile = 0x23, xflip = true },
  { dy =   4, dx =  -8, tile = 0x22, xflip = true },
  { dy =   4, dx =   0, tile = 0x21, xflip = true },
  { dy =   4, dx =   8, tile = 0x20, xflip = true },
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
-- Title intro uses BG palette slot 1 (PalPacket_PikachusBeachTitle /
-- UnknownPacket_72751) so the logo's shade-2 pixels tint yellow, not sea blue.
local PIKACHUS_BEACH_TITLE_PAL = {
  { 255, 255, 255 },
  { 132, 132, 132 },
  { 255, 206, 74 },
  { 25, 25, 25 },
}

-- 5 Tempo tiers (117, 109, 101, 93, 85 from surfing_pikachu.asm)
local TEMPO_TIERS = { 1.0, 117 / 109, 117 / 101, 117 / 93, 117 / 85 }

function SurfingMinigame.new(game, onDone, skipTitle)
  local self = setmetatable({ game = game, onDone = onDone }, SurfingMinigame)
  self.routine = skipTitle and ROUTINE_RUN_GAME or ROUTINE_TITLE
  self.pikaState = PIKA_STATE_RIDING
  self.t = 0
  self.routineTimer = 0
  self.distanceFixed = 0        -- 16.8 fixed-point course progress (256 = 1 pixel)
  self.distanceSection = 0      -- wSurfingMinigameDistance byte 0 (pret big-endian)
  self.distanceAcc = 0          -- wSurfingMinigameDistance bytes 1-2 (16-bit, big-endian)
  self.scrollFixed = 0          -- BG scroll (hSCX); diverges from distance during outro coast
  self.speedFixed = SPEED_INITIAL -- 64 = 0.25 px/frame
  self.hp = 6000                -- starts at 6000 (60.00 seconds)
  self.radness = 0              -- accumulated trick stunt points
  self.totalScore = 0           -- tallied total score
  self.hiScore = (game and game.save and game.save.surfingHighScore) or 0
  self.newRecord = false
  self.currentPitch = 1.0
  self.isMinigame = true
  self.isFixedSpeed = true

  -- Hardware RNG simulation (pret never resets hRandomAdd/hRandomSub on minigame entry)
  self.rDiv = 0
  self.rAdd = 0x55
  self.rSub = 0xaa

  -- Wave height tracking: pret vBGMap0 (32 metatile columns, circular)
  self.waveFn = 0
  self.bgMap = {}
  for c = 0, MAP_COLS - 1 do
    self.bgMap[c] = { pat = WAVE_PATTERNS[0x00], hl = FLAT_WATER_Y, hr = FLAT_WATER_Y }
  end
  -- Linear cols mirror kept for unit tests only
  self.cols = {}
  for c = 0, 10 do
    self.cols[c] = { pat = WAVE_PATTERNS[0x00], hl = FLAT_WATER_Y, hr = FLAT_WATER_Y }
  end
  self.colTail = 10

  -- wSurfingMinigameWaveHeight (20 entries, shifted each GenerateBGMap)
  self.waveHeight = {}
  for i = 1, 20 do
    self.waveHeight[i] = FLAT_WATER_Y
  end
  self.bgMapReadTile = 0x0b -- wSurfingMinigameBGMapReadBuffer (updated each ReadBGMapBuffer)
  self.waveRandomValue = 0 -- wSurfingMinigameWaveRandomValue (Random each RunGame frame)

  -- Jumping, Arc Physics & Air Rotation
  self.pikaY = FLAT_WATER_Y - 16 -- integer screen Y of Pikachu (sea waterline)
  self.pikaSubY = 0             -- 8.8 subpixel carry (0..255)
  self.pikaYOffset = 0          -- sine offset (splash/bobbing)
  self.jumpArcMagnitude = 0     -- wSurfingMinigameJumpArcMagnitude (GetSpeedDividedBy32, >= 10)
  self.jumpArcFraction = 0      -- wSurfingMinigameJumpArcFraction (8.8 sub-byte)
  self.jumpDescending = false
  self.frameSet = 4             -- Starts at Frame 4 (flat horizontal ride)
  self.boardAngleOffset = 0     -- wobbling 0..2
  self.boardAngleDecreasing = false
  self.boardAngleTimer = 0
  self.crashTimer = 0
  self.landingTimer = 0

  -- Outro coast / results card (SurfingMinigame_WaitToShowResults .. WaitLast)
  self.hScx = 0                 -- hSCX register (8-bit, wraps)
  self.scxFrac = 0              -- wSurfingMinigameSCX fractional byte
  self.scxHi = 0                -- wSurfingMinigameSCXHi (zero-init WRAM; band 0 until hSCX >= $10)
  self.scxLast = 0              -- wSurfingMinigameSCX2 (last hSCX seen by GenerateBGMap)
  self.showResultsCard = false
  self.outroLines = { hp = false, rad = false, total = false, hiScore = false }

  -- SurfingPikachu_GetJoypad_3FrameBuffer (hJoy5 + hFrameCounter countdown)
  self.joyFrameCounter = 0
  self.joy5Left = false
  self.joy5Right = false
  self.rotCountLeft = 0
  self.rotCountRight = 0
  self.radnessMeter = 0         -- consecutive flips (capped at 3)
  self.trickFlags = 0           -- bit 0 = right flip (front), bit 1 = left flip (back)

  -- Sprites & Popups
  self.startBannerX = 224       -- slides from 224 to 80 (center)
  self.introPikaX = 80          -- intro Pikachu walks off-screen before the run
  self.ohNoBanner = false
  self.trickPopups = {}         -- { text = "+150", x, y, timer }
  self.waterSprays = {}         -- { x, y, timer }
  self.sprayTimer = 0
  self.cloudScrollFrac = 0      -- wSurfingMinigameCloudScrollFraction
  self.cloudSpriteX = {}
  for i, x in ipairs(CLOUD_SPRITE_X_INIT) do
    self.cloudSpriteX[i] = x
  end

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
  self.joyFrameCounter = 0
  self.joy5Left = false
  self.joy5Right = false
  self.rotCountLeft = 0
  self.rotCountRight = 0
  -- Title screen elapsed frames churn rDIV/LFSR like overworld play before entry.
  for _ = 1, self.t + math.floor(self.introPikaX / 2) do
    self:getGBRandom()
  end
  self:resetTempo()
  if self.game and self.game.input and self.game.input.clearPressed then
    self.game.input:clearPressed()
  end
end

-- Authentic Game Boy LFSR Random Number Generator (engine/math/random.asm Random_)
function SurfingMinigame:getGBRandom()
  local div1 = self.rDiv
  self.rDiv = (self.rDiv + 1) % 256
  local div2 = self.rDiv
  self.rAdd = (self.rAdd + div1) % 256
  self.rSub = (self.rSub - div2 + 256) % 256
  return self.rAdd
end

function SurfingMinigame:chooseSequence()
  local section = self.distanceSection or 0
  if section == 0x16 then
    self.waveFn = 0x6a
  elseif section < 0x16 then
    -- Random at selection time (when waveFn==0 column generates), not frame-start
    -- waveRandomValue. Fixed LFSR init otherwise phase-locks to two small sequences.
    local r = self:getGBRandom()
    if r ~= 0 then
      self.waveFn = SEQ_STARTS[bit.band(r - 1, 0x07) + 1]
    end
  end
  return WAVE_PATTERNS[0x00], FLAT_WATER_Y, FLAT_WATER_Y
end

-- SurfingMinigame_UpdatePikachuDistance (3-byte big-endian distance + section counter)
function SurfingMinigame:updatePikachuDistance()
  local acc = (self.distanceAcc or 0) + self.speedFixed
  while acc >= SECTION_ACC_MAX do
    acc = acc - SECTION_ACC_MAX
    self.distanceSection = (self.distanceSection or 0) + 1
  end
  self.distanceAcc = acc
  self.distanceFixed = self.distanceSection * SECTION_ACC_MAX + acc
end

function SurfingMinigame:moveClouds()
  -- SurfingMinigame_MoveClouds: add speed high byte to each cloud OAM X (8-bit wrap)
  local sum = (self.cloudScrollFrac or 0) + (self.speedFixed or 0)
  self.cloudScrollFrac = sum % 256
  local delta = math.floor(sum / 256)
  if delta == 0 then return end
  for i = 1, #CLOUD_SPRITE_X_INIT do
    self.cloudSpriteX[i] = (self.cloudSpriteX[i] + delta) % 256
  end
end

function SurfingMinigame:pushColumn()
  local pat, hl, hr

  if self.routine == ROUTINE_WAIT_RESULTS then
    -- CoastAfterGoal with wSurfingMinigameWaveRandomValue = 0 → flat slice
    pat, hl, hr = WAVE_PATTERNS[0x00], FLAT_WATER_Y, FLAT_WATER_Y
  elseif self.waveFn >= 0x74 then
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

  local col = { pat = pat, hl = hl, hr = hr }
  self.bgMap[mapColWrite(self)] = col

  -- Shift wSurfingMinigameWaveHeight left, append new column heights
  for i = 1, 18 do
    self.waveHeight[i] = self.waveHeight[i + 2]
  end
  self.waveHeight[19] = hl
  self.waveHeight[20] = hr

  if not isOutroScroll(self) then
    self.colTail = self.colTail + 1
    self.cols[self.colTail] = col
    self.cols[self.colTail - 24] = nil
  end
end

function SurfingMinigame:advanceScx(deltaFixed)
  local sum = (self.hScx or 0) * 256 + (self.scxFrac or 0) + deltaFixed
  self.hScx = math.floor(sum / 256) % 256
  self.scxFrac = sum % 256
end

-- SurfingMinigame_GenerateBGMap: new column only when hSCX changes and $f0 band changes
function SurfingMinigame:generateBgMapIfNeeded()
  local h = self.hScx or 0
  if h == self.scxLast then return end
  self.scxLast = h
  local band = bit.band(h, 0xF0)
  if band == self.scxHi then return end
  self.scxHi = band
  self:pushColumn()
end

-- Legacy linear buffer kept for unit tests; pret uses generateBgMapIfNeeded only.
function SurfingMinigame:generateAhead()
  self:generateBgMapIfNeeded()
end

local function columnAt(self, x)
  local scx = displayScx(self)
  return self.bgMap[mapColAtX(scx, x)]
end

-- SurfingMinigame_SetPikachuHeight: wave height with slope from prior BGMapReadBuffer
function SurfingMinigame:pikaObjectHeight(tileForSlope)
  local scx = displayScx(self)
  local idx = (bit.band(scx, 8) ~= 0) and 9 or 8
  local h = self.waveHeight[idx]
  local tile = tileForSlope or self.bgMapReadTile or 0x0b
  if tile == 0x06 or tile == 0x14 then
    return h - bit.band(scx, 7)
  elseif tile == 0x07 then
    return h + bit.band(scx, 7)
  end
  return h
end

local function pikaWaterY(self)
  return self:pikaObjectHeight(self.bgMapReadTile)
end

-- Get water surface Y for a screen X coordinate (X=80 under Pikachu center)
function SurfingMinigame:seaY(x)
  if x == 80 then
    return pikaWaterY(self)
  end
  local col = columnAt(self, x)
  if not col then return FLAT_WATER_Y end
  local scx = displayScx(self)
  local tile = math.floor((scx + x) / 8)
  return tile % 2 == 0 and col.hl or col.hr
end

-- Chr tile at Pikachu's object height (SurfingMinigame_ReadBGMapBuffer).
function SurfingMinigame:sampleBgTileAt(scx, objectHeightPx)
  local tile_col = math.floor((scx + 72) / 8)
  local tile_row = math.floor(objectHeightPx / 8)

  local col = self.bgMap[mapColAtX(scx, 72)]
  if not col or not col.pat then return 0x0b end

  local i = math.floor(tile_row / 2) + 1
  if i < 1 or i > 8 then return 0x0b end
  local mt = BG_METATILES[col.pat[i]]
  if not mt then return 0x0b end

  local sub_x = (tile_col % 2 == 0) and 0 or 1
  local sub_y = (tile_row % 2 == 0) and 0 or 1
  return mt[1 + sub_x + sub_y * 2] or 0x0b
end

function SurfingMinigame:getWaveTileUnderPika()
  return self.bgMapReadTile or 0x0b
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
  if f >= 8 or f < 1 then
    return "wipeout"
  end

  local tile = self:getWaveTileUnderPika()

  if tile == 0x06 then -- rising slope
    if f <= 3 then return "wipeout"
    elseif f == 4 then return "hard"
    elseif f == 5 or f == 7 then return "rough"
    elseif f == 6 then return "clean"
    else return "wipeout" end

  elseif tile == 0x07 then -- falling slope
    if f == 1 then return "rough"
    elseif f == 2 then return "clean"
    elseif f == 3 then return "rough"
    elseif f == 4 then return "hard"
    else return "wipeout" end

  elseif tile == 0x12 or tile == 0x14 then -- wave face / crest
    if f == 1 then return "wipeout"
    elseif f == 2 or f == 7 then return "hard"
    elseif f == 3 or f == 6 then return "rough"
    elseif f == 4 or f == 5 then return "clean"
    else return "wipeout" end

  else -- flat open water (every other metatile id)
    if f == 1 or f == 7 then return "wipeout"
    elseif f == 2 or f == 6 then return "hard"
    elseif f == 3 or f == 5 then return "rough"
    elseif f == 4 then return "clean"
    else return "wipeout" end
  end
end

function SurfingMinigame:updateTempo()
  local tier = pretTempoTier(self.speedFixed or SPEED_INITIAL)
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

-- Pret RunDelayTimer: count down routineTimer; return true when it hits zero.
local function outroDelayExpired(self)
  if self.routineTimer > 0 then
    self.routineTimer = self.routineTimer - 1
    return false
  end
  return true
end

function SurfingMinigame:beginResultsCard()
  self.showResultsCard = true
  self.outroLines = { hp = false, rad = false, total = false, hiScore = false }
  self:initResultsPikachu()
  self.speedFixed = 0
  -- DrawResultsScreen clears cloud OAM (sprites 5–13); hide parallax clouds on the beach card
  self.cloudSpriteX = nil
end

-- SurfingMinigame_InitResultsPikachu: flat results pose at shore Y, reset bob counter
function SurfingMinigame:initResultsPikachu()
  self.pikaState = PIKA_STATE_INIT_RESULTS
  self.frameSet = 4 -- flat ride (visible pose; pret writes frameset $0f to anim struct)
  self.pikaY = FLAT_WATER_Y - PIKA_SPRITE_OFFSET
  self.pikaSubY = 0
  self.pikaYOffset = 0
  self.resultsBobTimer = 0
end

-- SurfingMinigame_UpdateResultsPikachu (hi-score path only sets PIKA_STATE_RESULTS in pret)
function SurfingMinigame:updateResultsPikachu()
  self.resultsBobTimer = (self.resultsBobTimer or 0) + 2
  local phase = bit.band(self.resultsBobTimer, RESULTS_BOB_CYCLE - 1)
  if phase >= RESULTS_BOB_START then
    self.pikaYOffset = math.floor(
      math.sin((phase - RESULTS_BOB_START) / (RESULTS_BOB_CYCLE / 2) * math.pi * 2) * RESULTS_BOB_AMP
    )
  else
    self.pikaYOffset = 0
  end
end

function SurfingMinigame:drawResultsPikachu()
  if not (self.ob and self.oq) then return end
  local cx, cy = 80, self.pikaY + (self.pikaYOffset or 0)
  self.pikaScreenY = cy
  local toggle = math.floor(self.t / 8) % 2 + 1
  local base = RESULTS_PIKA_BASES[toggle]
  if not self.oq[base] then
    base = ANGLE_BASES[4][toggle]
  end
  self:draw3x3(base, cx, cy, false, false)
end

function SurfingMinigame:updateRiding()
  local tile = self.bgMapReadTile or 0x0b
  local subX = bit.band(displayScx(self), 7)

  -- SurfingMinigame_TryStartJump (before SpeedUpPikachu; uses pre-accel speed)
  if (subX >= 3 and subX <= 4) and tile == 0x14 and getSpeedDividedBy32(self.speedFixed) >= SPEED_JUMP_MIN_DIV32 then
    self.pikaState = PIKA_STATE_JUMPING
    self.jumpArcMagnitude = getSpeedDividedBy32(self.speedFixed)
    self.jumpArcFraction = 0
    self.pikaSubY = 0
    self.jumpDescending = false
    self.radnessMeter = 0
    self.trickFlags = 0
    self.rotCountLeft = 0
    self.rotCountRight = 0
    Sound.play(self.game.data, "Ledge_Jump")
    -- SurfingMinigame_UpdateSurfingFrame still runs on .startedJump
    if subX >= 3 and subX <= 4 then
      if tile == 0x06 or tile == 0x14 then
        self.frameSet = 6 + (self.boardAngleOffset - 1)
      elseif tile == 0x07 then
        self.frameSet = 2 + (self.boardAngleOffset - 1)
      end
      self.frameSet = math.max(1, math.min(14, self.frameSet))
    end
    return
  end

  -- SurfingMinigame_UpdateSurfingFrame (only updates frame when subX is 3..4)
  if subX >= 3 and subX <= 4 then
    if tile == 0x06 or tile == 0x14 then
      self.frameSet = 6 + (self.boardAngleOffset - 1)
    elseif tile == 0x07 then
      self.frameSet = 2 + (self.boardAngleOffset - 1)
    else
      self:updateBoardAngle()
      self.frameSet = 4
    end
    self.frameSet = math.max(1, math.min(14, self.frameSet))
  end

  -- SurfingMinigame_SpeedUpPikachu (+2/256 = +1/128 per frame up to max 512 = 2.0)
  if self.speedFixed < SPEED_MAX then
    self.speedFixed = math.min(SPEED_MAX, self.speedFixed + SPEED_ACCEL)
  end
  self:updateTempo()

  -- Water spray every 4 frames
  self.sprayTimer = self.sprayTimer + 1
  if self.sprayTimer % 4 == 0 then
    table.insert(self.waterSprays, { x = PIKA_X, y = self.pikaY, timer = 4 })
  end
end

function SurfingMinigame:updateBoardAngle()
  self.boardAngleTimer = (self.boardAngleTimer or 0) + 1
  if self.boardAngleTimer % 8 ~= 0 then return end
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

function SurfingMinigame:handleLanding()
  local result = self:evaluateLanding()
  if result == "wipeout" then
    self.pikaState = PIKA_STATE_CRASHED
    self.crashTimer = CRASH_FRAMES
    self.speedFixed = SPEED_INITIAL
    self.frameSet = 4
    Sound.play(self.game.data, "Faint_Fall")
  else
    if result == "rough" then
      self.speedFixed = reduceSpeedBy64(self.speedFixed)
    elseif result == "hard" then
      self.speedFixed = reduceSpeedBy128(self.speedFixed)
    end
    if self.routine == ROUTINE_RUN_GAME then
      self:calculateStuntPoints()
    end
    self.pikaState = PIKA_STATE_LANDING
    self.landingTimer = LANDING_SPLASH_FRAMES
    self.frameSet = 4
    Sound.play(self.game.data, "Cut")
  end
end

function SurfingMinigame:updateJumping()
  -- SurfingMinigame_DPadAction (hJoy5 sampled every 2 frames via GetJoypad)
  if self.routine == ROUTINE_RUN_GAME then
    if self.joy5Left then
      self.rotCountRight = 0
      self.rotCountLeft = self.rotCountLeft + 1
      if self.rotCountLeft >= FLIP_LEFT_FRAMES then
        self.rotCountLeft = 0
        self.radnessMeter = math.min(RADNESS_METER_MAX, self.radnessMeter + 1)
        self.trickFlags = bit.bor(self.trickFlags, 1)
        Sound.play(self.game.data, "Tink")
      end
      if self.frameSet >= 14 then
        self.frameSet = 1
      else
        self.frameSet = self.frameSet + 1
      end
    elseif self.joy5Right then
      self.rotCountLeft = 0
      self.rotCountRight = self.rotCountRight + 1
      if self.rotCountRight >= FLIP_RIGHT_FRAMES then
        self.rotCountRight = 0
        self.radnessMeter = math.min(RADNESS_METER_MAX, self.radnessMeter + 1)
        self.trickFlags = bit.bor(self.trickFlags, 2)
        Sound.play(self.game.data, "Tink")
      end
      if self.frameSet <= 1 then
        self.frameSet = 14
      else
        self.frameSet = self.frameSet - 1
      end
    end
  end

  -- SurfingMinigame_UpdatePikachuHeight (arc delta before velocity each phase)
  if not self.jumpDescending then
    if (self.jumpArcMagnitude or 0) == 0 and (self.jumpArcFraction or 0) == 0 then
      self.jumpDescending = true
    else
      applyJumpArcDelta(self, -128) -- -0.5 px/frame in 8.8 fixed
      applyJumpVerticalDelta(self, -1)
    end
  else
    local waveY = pikaSpriteYFromObjectHeight(self.pikaObjectHeightPx)
    if self.pikaY >= waveY then
      self.pikaY = waveY
      self.pikaSubY = 0
      self:handleLanding()
      return
    end

    applyJumpArcDelta(self, 128) -- +0.5 px/frame in 8.8 fixed
    applyJumpVerticalDelta(self, 1)

    if self.pikaY >= waveY then
      self.pikaY = waveY
      self.pikaSubY = 0
      self:handleLanding()
    end
  end
end

function SurfingMinigame:updateLanding()
  self.landingTimer = (self.landingTimer or 0) - 1

  -- pikaY already updated by SetPikachuHeight in tick (pre-scroll object height).

  -- Sine wave splash offset (FIELD_C 0..$20 by +4/frame)
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
  -- pikaY already updated by SetPikachuHeight in tick.
  if self.crashTimer <= 0 then
    self.pikaState = PIKA_STATE_RIDING
    self.frameSet = 4
  end
end

-- Single Game Boy hardware VBlank cycle tick (59.7275 Hz)
function SurfingMinigame:tick()
  local input = self.game and self.game.input
  self.t = self.t + 1
  self.rDiv = (self.rDiv + RDIV_PER_FRAME) % 256

  -- Title Screen State (auto-advances when intro Pikachu walks off-screen)
  if self.routine == ROUTINE_TITLE then
    if self.t % 2 == 0 then
      self.introPikaX = self.introPikaX + 1
    end
    if self.introPikaX >= 192 then
      self:startFromTitle()
    end
    return
  end

  -- SurfingPikachu_GetJoypad_3FrameBuffer: hJoy5 = hJoyHeld when hFrameCounter==0, then reload $2;
  -- VBlank decrements counter → 1 sample frame + 2 blank frames (3-frame duty cycle).
  if self.routine == ROUTINE_RUN_GAME then
    if (self.joyFrameCounter or 0) == 0 then
      self.joy5Left = input and input:isDown("left")
      self.joy5Right = input and input:isDown("right")
      self.joyFrameCounter = JOY_FRAME_RELOAD
    else
      self.joy5Left = false
      self.joy5Right = false
    end
  else
    self.joy5Left = false
    self.joy5Right = false
    self.joyFrameCounter = 0
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

  -- Slide START banner during RunGame (pret animates it while gameplay runs)
  if self.routine == ROUTINE_RUN_GAME and self.startBannerX > 80 then
    self.startBannerX = math.max(80, self.startBannerX - 4)
  end

  -- Routine state machine
  if self.routine == ROUTINE_START_GAME then
    -- SurfingMinigame_StartGame: spawn banner, inc routine; RunGame begins next frame
    self.routine = ROUTINE_RUN_GAME
    return
  elseif self.routine == ROUTINE_RUN_GAME then
    -- SurfingMinigame_RunGame: distance check first (cp $18)
    if (self.distanceSection or 0) >= TOTAL_SECTIONS then
      self.distanceSection = TOTAL_SECTIONS
      self.routine = ROUTINE_WAIT_RESULTS
      self.routineTimer = COAST_FRAMES
      self.scxHi = bit.band(self.hScx or 0, 0xF0)
      self.scxLast = self.hScx or 0
      self.waveFn = 0
      self:resetTempo()
      return
    end

    -- HP dead check before frame logic (pret or [hl] on wSurfingMinigamePikachuHP)
    if (self.hp or 0) <= 0 then
      self.routine = ROUTINE_GAME_OVER
      self.routineTimer = GAME_OVER_DELAY
      self.speedFixed = 0
      self.ohNoBanner = true
      Sound.play(self.game and self.game.data, "Faint_Fall")
      return
    end

    self.waveRandomValue = self:getGBRandom()

    -- Pret RunGame order: SetPikachuHeight, ReadBGMapBuffer, Scroll, Distance, Deduct1HP
    local objectHeight = self:pikaObjectHeight(self.bgMapReadTile)
    self.pikaObjectHeightPx = objectHeight
    if self.pikaState ~= PIKA_STATE_JUMPING then
      self.pikaY = pikaSpriteYFromObjectHeight(objectHeight)
      self.pikaSubY = 0
    end
    local preScrollScx = displayScx(self)
    self.bgMapReadTile = self:sampleBgTileAt(preScrollScx, objectHeight)

    self:advanceScx(BG_SCROLL_STEP)
    self:generateBgMapIfNeeded()

    self:updatePikachuDistance()
    self.scrollFixed = self.distanceFixed

    -- SurfingMinigame_Deduct1HP (after UpdatePikachuDistance)
    self.hp = self.hp - 1

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
    if self.routineTimer > 0 then
      -- RunDelayTimer then CoastAfterGoal (192 coast frames, not 193)
      self.routineTimer = self.routineTimer - 1
      self:advanceScx(COAST_SPEED_FIXED)
      self:generateBgMapIfNeeded()
      self:resetTempo()
    end

    if self.pikaState == PIKA_STATE_JUMPING then
      self:updateJumping()
    elseif self.pikaState == PIKA_STATE_LANDING then
      self:updateLanding()
    elseif self.pikaState == PIKA_STATE_CRASHED then
      self:updateCrashed()
    else
      local targetY = self:seaY(80)
      self.pikaY = math.floor(targetY) - 16
      self.pikaSubY = 0
      self.frameSet = 4
    end

    if self.routineTimer <= 0 then
      -- pret .doneDelay: enter results scroll immediately (no wait for landing/crash)
      self.routine = ROUTINE_SCROLL_RESULTS
      self.hScx = OUTRO_SCROLL_START
      self.scxFrac = 0
      self.scxHi = 0
      self.scxLast = 0
      self.waveFn = 0x72
      self.pikaState = PIKA_STATE_GAME_END
    end

  elseif self.routine == ROUTINE_SCROLL_RESULTS then
    if (self.hScx or 0) <= 0 then
      self.routine = ROUTINE_DRAW_RESULTS
      self.pikaState = PIKA_STATE_INIT_RESULTS
    else
      self.hScx = self.hScx - OUTRO_SCROLL_STEP
      self:generateBgMapIfNeeded()
      local targetY = self:seaY(80)
      self.pikaY = math.floor(targetY) - 16
      self.pikaSubY = 0
      self.frameSet = 4
    end

  elseif self.routine == ROUTINE_DRAW_RESULTS then
    -- DrawResultsScreenAndWait: one-shot static beach tilemap + textbox frame
    self:beginResultsCard()
    self.routineTimer = 32
    self.routine = ROUTINE_WRITE_HP_LEFT

  elseif self.routine == ROUTINE_WRITE_HP_LEFT then
    if outroDelayExpired(self) then
      self.outroLines.hp = true
      self.routineTimer = 64
      self.routine = ROUTINE_WRITE_RADNESS
    end

  elseif self.routine == ROUTINE_WRITE_RADNESS then
    if outroDelayExpired(self) then
      self.outroLines.rad = true
      self.routineTimer = 64
      self.routine = ROUTINE_WRITE_TOTAL
    end

  elseif self.routine == ROUTINE_WRITE_TOTAL then
    if outroDelayExpired(self) then
      self.outroLines.total = true
      self.routineTimer = 64
      self.routine = ROUTINE_ADD_HP_TOTAL
    end

  elseif self.routine == ROUTINE_ADD_HP_TOTAL then
    if not outroDelayExpired(self) then
      -- waiting before tally starts
    elseif self.hp > 0 then
      local step = math.min(self.hp, 99)
      self.hp = self.hp - step
      self.totalScore = self.totalScore + step
      Sound.play(self.game and self.game.data, "Press_AB")
    else
      self.routineTimer = 64
      self.routine = ROUTINE_ADD_RAD_TOTAL
    end

  elseif self.routine == ROUTINE_ADD_RAD_TOTAL then
    if not outroDelayExpired(self) then
      -- waiting before tally starts
    elseif self.radness > 0 then
      local step = math.min(self.radness, 99)
      self.radness = self.radness - step
      self.totalScore = self.totalScore + step
      Sound.play(self.game and self.game.data, "Press_AB")
    else
      self.newRecord = self.totalScore > ((self.game and self.game.save and self.game.save.surfingHighScore) or 0)
      if self.newRecord then
        if self.game and self.game.save then self.game.save.surfingHighScore = self.totalScore end
        self.outroLines.hiScore = true
        self.pikaState = PIKA_STATE_RESULTS
        Sound.play(self.game and self.game.data, "Get_Item1")
        Sound.playPikaCry(self.game and self.game.data, 34)
      else
        Sound.playPikaCry(self.game and self.game.data, 28)
      end
      self.routineTimer = GAME_OVER_DELAY
      self.routine = ROUTINE_WAIT_LAST
    end

  elseif self.routine == ROUTINE_WAIT_LAST then
    if outroDelayExpired(self) then
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

  if self.showResultsCard then
    if self.pikaState == PIKA_STATE_RESULTS then
      self:updateResultsPikachu()
    else
      self.pikaYOffset = 0
    end
  end

  -- Pret SurfingPikachuLoop calls MoveClouds every frame while gameplay is active
  if self.routine == ROUTINE_RUN_GAME
      or self.routine == ROUTINE_WAIT_RESULTS
      or self.routine == ROUTINE_GAME_OVER then
    self:moveClouds()
  end

  -- hFrameCounter decrements after game logic (VBlank)
  if self.routine == ROUTINE_RUN_GAME and (self.joyFrameCounter or 0) > 0 then
    self.joyFrameCounter = self.joyFrameCounter - 1
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
  local scx = displayScx(self)

  local function renderTiles()
    love.graphics.setColor(1, 1, 1, 1)
    if not self.bg then return end
    for i = 0, 10 do
      local col = self.bgMap[mapColScreen(scx, i)]
      local x = i * 16 - (scx % 16)
      if col then
        for row = 1, 8 do
          local mt = BG_METATILES[col.pat[row]]
          if mt then
            local y = (row - 1) * 16
            local function drawTile(tid, tx, ty)
              if tid ~= 0x00 and self.tq[tid] then
                love.graphics.draw(self.bg, self.tq[tid], tx, ty)
              end
            end
            drawTile(mt[1], x, y)
            drawTile(mt[2], x + 8, y)
            drawTile(mt[3], x, y + 8)
            drawTile(mt[4], x + 8, y + 8)
          end
        end
      end
    end
  end

  if self.bgCanvas and self.waveShader and not isOutroScroll(self) and not self.showResultsCard
      and love.graphics.setCanvas and love.graphics.getCanvas then
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

-- Draw intro title Pikachu (SurfingPikachu1Graphics3 via .IntroPikachu OAM)
function SurfingMinigame:drawIntroPikachu(cx, cy)
  if not (self.intro and self.iq) then return end
  local frame = math.floor(self.t / 7) % 4 + 1
  local vramBase = INTRO_PIKA_FRAME_BASE[frame]
  local sheetBase = vramBase - 0x80
  for _, sp in ipairs(INTRO_PIKA_OAM) do
    local tileId = sheetBase + sp.tile
    local q = self.iq[tileId]
    if q then
      local x = cx + sp.dx + (sp.xflip and 8 or 0)
      local y = cy + sp.dy
      if sp.xflip then
        love.graphics.draw(self.intro, q, x, y, 0, -1, 1)
      else
        love.graphics.draw(self.intro, q, x, y)
      end
    end
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

  -- Window tilemap (SurfingPikachuMinigame_DrawStaticTilemapLayout):
  -- row 0 cols 1-2: $15,$16 island; row 1 cols 1-9: $17,$18,$19×7;
  -- row 1 cols 12-13: $1b,$1c "HP:"; digits are OAM sprites at X=$80.
  if self.bg and self.tq then
    love.graphics.draw(self.bg, self.tq[0x15], 8, BG_HEIGHT)
    love.graphics.draw(self.bg, self.tq[0x16], 16, BG_HEIGHT)

    love.graphics.draw(self.bg, self.tq[0x17], 8, BG_HEIGHT + 8)
    love.graphics.draw(self.bg, self.tq[0x18], 16, BG_HEIGHT + 8)
    for i = 1, 7 do
      love.graphics.draw(self.bg, self.tq[0x19], 16 + i * 8, BG_HEIGHT + 8)
    end
    love.graphics.draw(self.bg, self.tq[0x1b], 96, BG_HEIGHT + 8)
    love.graphics.draw(self.bg, self.tq[0x1c], 104, BG_HEIGHT + 8)
  end

  -- Mini-Pikachu progress marker (tile $fe)
  -- Game Boy: initial OAM X = $50 (80) = screen X 72, decrements by 2 per section.
  local markerStartX = 72   -- OAM X $50 (80) minus 8-pixel OAM offset
  local markerX = markerStartX - (self.distanceSection or 0) * 2
  if self.ob and self.oq and self.oq[0xfe] then
    love.graphics.draw(self.ob, self.oq[0xfe], markerX, BG_HEIGHT + 6)
  end

  -- 4 HP countdown digits (OAM X $80..$98)
  local s = string.format("%04d", math.max(0, math.floor(self.hp)))
  for i = 1, 4 do
    local d = tonumber(s:sub(i, i)) or 0
    if self.ob and self.oq and self.oq[0xd0 + d] then
      love.graphics.draw(self.ob, self.oq[0xd0 + d], 128 + (i - 1) * 8, BG_HEIGHT + 8)
    else
      Font.draw(tostring(d), 128 + (i - 1) * 8, BG_HEIGHT + 8)
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

  -- Text lines appear as each Write* routine fires in pret
  if self.outroLines.hp then
    Font.draw(Strings("HP Left"), 16, 16)
    Font.draw(string.format("%04d", self.hp), 80, 16)
    Font.draw(Strings("Pts"), 120, 16)
  end

  if self.outroLines.rad then
    Font.draw(Strings("Radness"), 16, 32)
    Font.draw(string.format("%04d", self.radness), 80, 32)
    Font.draw(Strings("Pts"), 120, 32)
  end

  if self.outroLines.total then
    Font.draw(Strings("Total"), 16, 48)
    Font.draw(string.format("%04d", self.totalScore), 80, 48)
    Font.draw(Strings("Pts"), 120, 48)
  end

  if self.outroLines.hiScore then
    Font.draw(Strings("Hi-Score!!"), 48, 64)
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

  -- 2. Intro Pikachu paddling out (SurfingPikachu1Graphics3 / surf_1c.png)
  self:drawIntroPikachu(self.introPikaX, FLAT_WATER_Y)
end

function SurfingMinigame:draw()
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)

  if self.routine == ROUTINE_TITLE then
    self:drawTitleScreen()
    return
  end

  if self.showResultsCard then
    self:drawResultsOutro()
    self:drawResultsPikachu()
    self:drawHUD()
    return
  end

  -- Draw scrolling BG waves
  self:drawBackground()

  -- Parallax clouds (SurfingMinigame_MoveClouds: 9 OAM sprites, 8-bit X wrap)
  if self.ob and self.oq and self.cloudSpriteX then
    local wideTiles = { 0xec, 0xed, 0xed, 0xee, 0xef }
    for i, tid in ipairs(wideTiles) do
      local x = self.cloudSpriteX[i]
      if x < 168 then
        love.graphics.draw(self.ob, self.oq[tid], x, 12)
      end
    end
    local narrowTiles = { 0xec, 0xed, 0xee, 0xef }
    for i, tid in ipairs(narrowTiles) do
      local x = self.cloudSpriteX[i + 5]
      if x < 168 then
        love.graphics.draw(self.ob, self.oq[tid], x, 20)
      end
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

  -- "START" banner (slides in during early RunGame frames)
  if self.startBannerX > 80 then
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
  local beach = (game and game.data and P.pal(game.data, "PIKACHUS_BEACH")) or PIKACHUS_BEACH_PAL
  if self.routine == ROUTINE_TITLE then
    local title = (game and game.data and P.pal(game.data, "PIKACHUS_BEACH_TITLE"))
      or PIKACHUS_BEACH_TITLE_PAL
    -- SurfingMinigame_TitleTilemap at (4,0), 12x6; ATTR_BLK pal 1 over that rect.
    return { P.whole(beach), P.zone(title, 4, 0, 15, 5) }
  end
  return { P.whole(beach) }
end

return SurfingMinigame
