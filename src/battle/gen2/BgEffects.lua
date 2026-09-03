-- The Gen 2 battle-animation BACKGROUND effects.
--
-- pokegold engine/battle_anims/bg_effects.asm: five concurrent structs, each
-- of {function, jumptable index, battle turn, param}, and a jumptable of 53
-- effects that between them do all the shaking, flashing and sinking a Gen 2
-- battle animation is made of.  Objects (src/battle/gen2/AnimObjects.lua) are
-- OBJs; these are the BG layer.
--
-- The one mechanism worth understanding before reading any of it: almost
-- nothing here moves a sprite.  It writes wLYOverridesBackup, a per-scanline
-- value the LCD STAT interrupt copies into rSCX, rSCY or rBGP as the beam
-- passes.  BattleBGEffect_SetLCDStatCustoms1 picks the window -- scanlines
-- $00-$36 for the enemy's pic, $2f-$5e for the player's -- so "shake the
-- attacker" is "write the same SCX to every scanline the attacker occupies".
--
-- The port keeps that literally: `lyBackup` is 144 bytes, `lcdc` names the
-- register they land in, and src/ui/gen2/BattleAnimView.lua draws the BG layer
-- one scanline band at a time.  Modelling it as "move the mon pic" instead
-- would work for Tackle and then fall apart on Withdraw and Dig, which push a
-- GROWING number of rows off and leave the rest where they are.
--
-- Love-free, like AnimObjects.

local bit = require("bit")
local AnimObjects = require("src.battle.gen2.AnimObjects")

local u8, sra = AnimObjects.u8, AnimObjects.sra
local swap = AnimObjects.swap
local sine, cosine = AnimObjects.sine, AnimObjects.cosine

local BgEffects = {}

local NUM_EFFECTS = 5 -- NUM_BG_EFFECTS
local SCREEN_ROWS = 0x90 -- wLYOverridesBackup is $91 bytes

-- `dc a, b, c, d` packs four 2-bit shades into a DMG palette byte, high pair
-- first: `dc 3, 2, 1, 0` is %11100100 = $e4, the identity ramp.
local function dc(a, b, c, d) return a * 64 + b * 16 + c * 4 + d end

local NORMAL_PAL = dc(3, 2, 1, 0)

--------------------------------------------------------------------------

local Pool = {}
Pool.__index = Pool

local function newEffect()
  return { func = nil, jt = 0, turn = 0, param = 0, side = nil }
end

-- `env` is shared with the object pool: env.battleTurn is hBattleTurn, and
-- env.flying tells BGEffect_CheckFlyDigStatus whether the battler in question
-- is mid-Fly or mid-Dig (in which case ShowMon and the battler-pic objects
-- decline to draw a mon that is not on the field).
function BgEffects.new(constants, env)
  local self = setmetatable({}, Pool)
  self.env = env or {}
  self.effects = {}
  for slot = 1, NUM_EFFECTS do self.effects[slot] = newEffect() end
  self.order = (constants or {}).battleBgEffectOrder or {}
  self:reset()
  return self
end

function Pool:reset()
  for slot = 1, NUM_EFFECTS do self.effects[slot] = newEffect() end
  -- hSCX / hSCY: a whole-screen scroll, which is what the screen shakes use.
  self.scx, self.scy = 0, 0
  -- hLCDCPointer plus its window, and the per-scanline values themselves.
  self.lcdc, self.lyStart, self.lyEnd = nil, 0, 0
  self.lyBackup = {}
  for row = 0, SCREEN_ROWS do self.lyBackup[row] = 0 end
  -- wBGP / wOBP0 / wOBP1, as DMG palette bytes.
  self.bgp, self.obp0, self.obp1 = NORMAL_PAL, NORMAL_PAL, NORMAL_PAL
  -- Per-battler state the CGB paths write instead of touching wBGP: shade
  -- byte, hidden flag, lifted tile rows, and which BG square it is drawn at.
  self.monShade = { player = NORMAL_PAL, enemy = NORMAL_PAL }
  self.hidden = { player = false, enemy = false }
  self.liftedRows = { player = nil, enemy = nil }
  self.picSize = { player = nil, enemy = nil }
  self.slide = { player = 0, enemy = 0 }
  -- wSurfWaveBGEffect: the $40-byte rolling wave Surf keeps beside the
  -- overrides.  nil until InitSurfWaves lays one down.
  self.surfWave = nil
  -- The objects a BG effect asks the object pool to spawn, drained by the
  -- runner after each frame.
  self.spawns = {}
end

function Pool:activeCount()
  local count = 0
  for slot = 1, NUM_EFFECTS do
    if self.effects[slot].func then count = count + 1 end
  end
  return count
end

-- QueueBGEffect: first free struct wins; a full pool silently drops the
-- request, which is exactly what the carry return means to the caller.
function Pool:queue(effectId, jumptableIndex, turn, param)
  local name = effectId
  if type(effectId) == "number" then
    name = self.order[effectId + 1] or effectId
  end
  for slot = 1, NUM_EFFECTS do
    local st = self.effects[slot]
    if not st.func then
      st.func = name
      st.jt = u8(jumptableIndex or 0)
      st.turn = u8(turn or 0)
      st.param = u8(param or 0)
      st.side = nil
      return st
    end
  end
  return nil
end

-- BattleAnimCmd_IncBGEffect: bump the jumptable index of the first struct
-- running this effect.
function Pool:incEffect(effectId)
  local name = effectId
  if type(effectId) == "number" then
    name = self.order[effectId + 1] or effectId
  end
  for slot = 1, NUM_EFFECTS do
    local st = self.effects[slot]
    if st.func == name then
      st.jt = u8(st.jt + 1)
      return st
    end
  end
  return nil
end

--------------------------------------------------------------------------
-- Shared helpers
--------------------------------------------------------------------------

local function endEffect(st) st.func = nil end
local function incJt(st) st.jt = u8(st.jt + 1) end

-- BGEffect_CheckBattleTurn: non-zero means "the side this effect is aimed at
-- is the player's".  A struct's `turn` is BG_EFFECT_USER / BG_EFFECT_TARGET,
-- so the same effect id follows whichever battler is attacking.
function Pool:playerSide(st)
  return bit.bxor(bit.band(self.env.battleTurn or 0, 1), st.turn) ~= 0
end

function Pool:sideKey(st)
  return self:playerSide(st) and "player" or "enemy"
end

-- BGEffect_CheckFlyDigStatus: zero means "on the field".
function Pool:flyDig(st)
  local flying = self.env.flying or {}
  return flying[self:sideKey(st)] and true or false
end

function Pool:clearLYOverrides(value)
  value = value or 0
  for row = 0, SCREEN_ROWS do self.lyBackup[row] = value end
end

-- BattleBGEffect_SetLCDStatCustoms1: the window is the attacker's pic rows.
function Pool:setLCDStatCustoms1(register, st)
  self.lcdc = register
  if self:playerSide(st) then
    self.lyStart, self.lyEnd = 0x2f, 0x5e
  else
    self.lyStart, self.lyEnd = 0x00, 0x36
  end
end

-- engine/battle_anims/bg_effects.asm:2671
function Pool:setLCDStatCustoms2(register, st)
  self.lcdc = register
  if self:playerSide(st) then
    self.lyStart, self.lyEnd = 0x2d, 0x5e
  else
    self.lyStart, self.lyEnd = 0x00, 0x36
  end
end

function Pool:resetLCDStatCustom(st)
  self.lyStart, self.lyEnd = 0, 0
  self:clearLYOverrides(0)
  self.lcdc = nil
  endEffect(st)
end

function Pool:resetVideoHRAM()
  self.lcdc = nil
  self.bgp, self.obp1 = NORMAL_PAL, NORMAL_PAL
  self.lyStart, self.lyEnd = 0, 0
  self:clearLYOverrides(0)
end

-- BGEffect_FillLYOverridesBackup: the same value on every scanline in the
-- window.  `dec d; jr nz` after the first store, so a zero-width window would
-- run 256 times; the port refuses instead of wrapping the array.
function Pool:fillLY(value)
  local count = u8(self.lyEnd - self.lyStart)
  if count == 0 then count = 256 end
  for i = 0, count - 1 do
    local row = self.lyStart + i
    if row > SCREEN_ROWS then break end
    self.lyBackup[row] = u8(value)
  end
end

-- BGEffect_DisplaceLYOverridesBackup: the first `a` scanlines of the window
-- are scrolled to a blank part of the map ($90) and the rest are pushed down
-- by a + 1.  That is what makes Withdraw and Dig look like the mon sinking
-- rather than sliding.
function Pool:displaceLY(a)
  a = u8(a)
  local span = u8(self.lyEnd - self.lyStart)
  local rest = u8(span - a)
  local row = self.lyStart
  for _ = 1, (a == 0 and 256 or a) do
    if row > SCREEN_ROWS then return end
    self.lyBackup[row] = 0x90
    row = row + 1
  end
  local pushed = u8(0xff - a)
  for _ = 1, (rest == 0 and 256 or rest) do
    if row > SCREEN_ROWS then return end
    self.lyBackup[row] = pushed
    row = row + 1
  end
end

-- DeformScreen: a standing sine wave down the window.  It walks the FIRST
-- $80 entries of wLYOverridesBackup by their low address byte and writes only
-- the ones inside the window -- `cp c / jr nc` skips while lyStart >= c and
-- `cp c / jr c` skips once lyEnd < c, so the row written is strictly
-- lyStart < row <= lyEnd -- but the phase advances on EVERY iteration, window
-- or not.  So where the window sits decides which part of the wave lands on
-- it, and two effects with the same amplitude and offset but different
-- windows do not look alike.
--
-- `lb de, d, e` puts the AMPLITUDE in d and the phase step in e.
function Pool:deformScreen(amplitude, offset)
  local progress = 0
  for row = 0, 0x7f do
    if self.lyStart < row and row <= self.lyEnd and row <= SCREEN_ROWS then
      self.lyBackup[row] = sine(progress, amplitude)
    end
    progress = u8(progress + offset)
  end
end

-- InitSurfWaves: the same wave, into the $40-byte wSurfWaveBGEffect ring
-- rather than the overrides themselves.  Surf rotates that ring a step a frame
-- and copies it out, which is what makes the water ROLL instead of standing
-- still the way DeformScreen's does.
Pool.SURF_WAVE_LENGTH = 0x40

function Pool:initSurfWaves(amplitude, offset)
  local progress = 0
  self.surfWave = {}
  for index = 0, Pool.SURF_WAVE_LENGTH - 1 do
    self.surfWave[index] = sine(progress, amplitude)
    progress = u8(progress + offset)
  end
end

-- BattleBGEffect_Surf's `.RotatewSurfWaveBGEffect`: rotate the ring left one,
-- then paint scanlines $00-$5e from it -- zero at and below lyStart, the ring
-- (wrapping every $40 rows) above it.  The ring index advances on every
-- scanline including the zeroed ones, so the wave keeps its phase across the
-- boundary.
function Pool:rotateSurfWave()
  local wave = self.surfWave
  if not wave then return end
  local first = wave[0]
  for index = 0, Pool.SURF_WAVE_LENGTH - 2 do
    wave[index] = wave[index + 1]
  end
  wave[Pool.SURF_WAVE_LENGTH - 1] = first
  local ring = 0
  for row = 0, 0x5e do
    local value = 0
    if self.lyStart < row then value = wave[ring] end
    if row <= SCREEN_ROWS then self.lyBackup[row] = u8(value) end
    ring = bit.band(ring + 1, Pool.SURF_WAVE_LENGTH - 1)
  end
end

-- DeformWater: `count` PAIRS of scanlines either side of a centre at
-- lyStart + `progress`, each pair taking the next step of a sine whose angle
-- climbs by 4 a pair.  Both walkers start on the centre row, so it is written
-- twice and the figure is symmetric about it.  The two bounds checks are not
-- the same test: the downward walker stops once lyEnd < its row, the upward
-- one once lyStart >= its row.
function Pool:deformWater(count, amplitude, offset, progress)
  local down = self.lyStart + (progress or 0)
  local up = down
  local angle = u8(offset)
  for _ = 1, u8(count) do
    local value = sine(angle, amplitude)
    if self.lyEnd >= down then
      if down >= 0 and down <= SCREEN_ROWS then self.lyBackup[down] = value end
      down = down + 1
    end
    if self.lyStart < up then
      if up >= 0 and up <= SCREEN_ROWS then self.lyBackup[up] = value end
      up = up - 1
    end
    angle = u8(angle + 4)
  end
end

-- BattleBGEffect_WavyScreenFX: rotate the window's overrides up one row, the
-- old top row wrapping around to the bottom.  Every wobble effect is
-- DeformScreen once to lay the wave down and then this, once a frame, to make
-- it travel.
function Pool:wavyScreenFX()
  local span = u8(self.lyEnd - self.lyStart)
  if span == 0 then return end
  local first = self.lyBackup[self.lyStart] or 0
  for i = 0, span - 1 do
    local row = self.lyStart + i
    if row > SCREEN_ROWS then break end
    self.lyBackup[row] = self.lyBackup[row + 1] or 0
  end
  local last = self.lyStart + span
  if last <= SCREEN_ROWS then self.lyBackup[last] = first end
end

-- BattleBGEffect_GetFirstDMGPal / GetNextDMGPal walking a `dc` list.
-- $ff ends the effect (returns nil); $fe restarts the list from the top.
local function nextPal(st, pals)
  local index = st.param
  st.param = u8(st.param + 1)
  local value = pals[index + 1]
  if value == nil or value == 0xff then return nil end
  if value == 0xfe then
    -- Rewind and hand back the list's first entry.
    st.param = 0
    value = pals[1]
  end
  return value
end

-- BattleBGEffect_GetNthDMGPal: JT doubles as a per-step frame counter, and it
-- is reloaded from the struct's `turn` -- so the SAME field is the flash speed
-- here and the battler side everywhere else.
local function nthPal(st, pals)
  if st.jt ~= 0 then
    st.jt = st.jt - 1
    local index = st.param
    local value = pals[index + 1]
    if value == nil or value == 0xff then return nil end
    if value == 0xfe then
      st.param = 0
      value = pals[1]
    end
    return value
  end
  st.jt = st.turn
  return nextPal(st, pals)
end

--------------------------------------------------------------------------
-- The effects (BattleBGEffects jumptable)
--------------------------------------------------------------------------

local E = {}

E.BATTLE_BG_EFFECT_END = function(_, st) endEffect(st) end

-- BattleBGEffect_FlashContinue: `turn` is the flash duration, `param` the
-- number of flashes left, and the two palettes alternate.
local function flash(self, st, pals)
  if st.jt ~= 0 then
    st.jt = st.jt - 1
    return
  end
  st.jt = st.turn
  if st.param == 0 then
    endEffect(st)
    return
  end
  st.param = u8(st.param - 1)
  self.bgp = pals[bit.band(st.param, 1) + 1]
end

E.BATTLE_BG_EFFECT_FLASH_INVERTED = function(self, st)
  flash(self, st, { dc(3, 2, 1, 0), dc(0, 1, 2, 3) })
end

E.BATTLE_BG_EFFECT_FLASH_WHITE = function(self, st)
  flash(self, st, { dc(3, 2, 1, 0), dc(0, 0, 0, 0) })
end

local WHITE_HUES = { dc(3, 2, 1, 0), dc(3, 2, 0, 0), dc(3, 1, 0, 0), 0xff }
local BLACK_HUES = { dc(3, 2, 1, 0), dc(3, 3, 1, 0), dc(3, 3, 2, 0), 0xff }
local ALTERNATE_HUES = {
  dc(3, 2, 1, 0), dc(3, 3, 2, 0), dc(3, 3, 3, 0), dc(3, 3, 2, 0),
  dc(3, 2, 1, 0), dc(2, 1, 0, 0), dc(1, 0, 0, 0), dc(2, 1, 0, 0), 0xfe,
}

E.BATTLE_BG_EFFECT_WHITE_HUES = function(self, st)
  local value = nthPal(st, WHITE_HUES)
  if not value then
    endEffect(st)
    return
  end
  self.bgp = value
end

E.BATTLE_BG_EFFECT_BLACK_HUES = function(self, st)
  local value = nthPal(st, BLACK_HUES)
  if not value then
    endEffect(st)
    return
  end
  self.bgp = value
end

E.BATTLE_BG_EFFECT_ALTERNATE_HUES = function(self, st)
  local value = nthPal(st, ALTERNATE_HUES)
  if not value then
    endEffect(st)
    return
  end
  self.bgp, self.obp1 = value, value
end

local OB_GRAY_YELLOW = { dc(3, 2, 1, 0), dc(2, 1, 0, 0), 0xfe }
local OB_MID_GRAY_YELLOW = { dc(3, 2, 1, 0), dc(3, 1, 2, 0), 0xfe }
local BG_INVERTED = { dc(0, 1, 2, 3), dc(1, 2, 0, 3), dc(2, 0, 1, 3), 0xfe }

E.BATTLE_BG_EFFECT_CYCLE_OBPALS_GRAY_AND_YELLOW = function(self, st)
  local value = nthPal(st, OB_GRAY_YELLOW)
  if value then self.obp0 = value end
end

E.BATTLE_BG_EFFECT_CYCLE_MID_OBPALS_GRAY_AND_YELLOW = function(self, st)
  local value = nthPal(st, OB_MID_GRAY_YELLOW)
  if value then self.obp0 = value end
end

E.BATTLE_BG_EFFECT_CYCLE_BGPALS_INVERTED = function(self, st)
  local value = nthPal(st, BG_INVERTED)
  if value then self.bgp = value end
end

-- engine/battle_anims/bg_effects.asm:343
E.BATTLE_BG_EFFECT_HIDE_MON = function(self, st)
  local jt = st.jt
  if jt == 0 then
    incJt(st)
    self.hidden[self:sideKey(st)] = true
  elseif jt >= 1 and jt <= 3 then
    incJt(st)
  elseif jt == 4 then
    endEffect(st)
  end
end

-- BattleBGEffect_RunPicResizeScript: rows of {size, base tile, coord slot},
-- $ff ending, $fe clearing a box, $fd skipping the draw.  The sizes are the
-- six BG squares (6x6, 4x4, 2x2 for the player; 7x7, 5x5, 3x3 for the enemy),
-- which is how a mon grows into or shrinks out of the field.  Only the size
-- matters to this port -- the tile ids and the coord slot are the same pic in
-- the same box -- so the script is followed for its TIMING and its scale.
local PIC_RESIZE = {
  -- BattleBGEffect_ShowMon
  showPlayer = { 0 },
  showEnemy = { 3 },
  -- BattleBGEffect_EnterMon
  enterPlayer = { 2, 1, 0 },
  enterEnemy = { 5, 4, 3 },
  -- BattleBGEffect_ReturnMon: each step is preceded by a box clear, which is
  -- the -2 row, and the last -3 row leaves the field empty.
  returnPlayer = { 0, 1, 2, false },
  returnEnemy = { 3, 4, 5, false },
}

local function runPicResize(self, st, script)
  local side = self:sideKey(st)
  local jt = st.jt
  if jt == 0 then
    local step = script[st.param + 1]
    st.param = u8(st.param + 1)
    if step == nil then
      self.picSize[side] = nil
      endEffect(st)
      return
    end
    if step == false then
      self.picSize[side] = nil
      self.hidden[side] = true
    else
      self.picSize[side] = step
      self.hidden[side] = false
    end
    self.liftedRows[side] = nil
    incJt(st)
  elseif jt >= 1 and jt <= 2 then
    incJt(st)
  elseif jt == 3 then
    st.jt = 0
  elseif jt == 4 then
    self.picSize[side] = nil
    endEffect(st)
  end
end

E.BATTLE_BG_EFFECT_SHOW_MON = function(self, st)
  if self:flyDig(st) then
    endEffect(st)
    return
  end
  runPicResize(self, st, self:playerSide(st)
    and PIC_RESIZE.showPlayer or PIC_RESIZE.showEnemy)
end

E.BATTLE_BG_EFFECT_ENTER_MON = function(self, st)
  runPicResize(self, st, self:playerSide(st)
    and PIC_RESIZE.enterPlayer or PIC_RESIZE.enterEnemy)
end

E.BATTLE_BG_EFFECT_RETURN_MON = function(self, st)
  runPicResize(self, st, self:playerSide(st)
    and PIC_RESIZE.returnPlayer or PIC_RESIZE.returnEnemy)
end

-- BattleBGEffect_RemoveMon slides the pic's tilemap one column a frame
-- towards the edge it came from, eight or nine columns' worth.
E.BATTLE_BG_EFFECT_REMOVE_MON = function(self, st)
  local side = self:sideKey(st)
  local jt = st.jt
  if jt == 0 then
    incJt(st)
    st.param = self:playerSide(st) and 9 or 8
  elseif jt == 1 then
    self.slide[side] = self.slide[side] + (self:playerSide(st) and -8 or 8)
    incJt(st)
    st.param = u8(st.param - 1)
  elseif jt == 2 or jt == 3 then
    incJt(st)
  elseif jt == 4 then
    if st.param == 0 then
      self.slide[side] = 0
      self.hidden[side] = true
      endEffect(st)
      return
    end
    st.jt = 1
  end
end

-- The two battler-pic objects: the animation borrows the mon's own tiles as
-- an OBJ so it can be moved without touching the tilemap.
local function battlerObj(self, st, objectPlayer, objectEnemy, rows)
  local jt = st.jt
  if jt == 0 then
    if self:flyDig(st) then
      endEffect(st)
      return
    end
    incJt(st)
    local player = self:playerSide(st)
    self.spawns[#self.spawns + 1] = {
      object = player and objectPlayer or objectEnemy,
      x = player and (6 * 8) or (16 * 8 + 4),
      y = 8 * 8,
      param = 0,
    }
  elseif jt == 1 then
    incJt(st)
    -- engine/battle_anims/bg_effects.asm:448-465: the rows the OBJ now covers
    -- come out of the tilemap, and .five never puts them back.
    self.liftedRows[self:sideKey(st)] = rows[self:sideKey(st)]
  elseif jt >= 2 and jt <= 4 then
    incJt(st)
  elseif jt == 5 then
    endEffect(st)
  end
end

E.BATTLE_BG_EFFECT_BATTLEROBJ_1ROW = function(self, st)
  battlerObj(self, st, "BATTLE_ANIM_OBJ_PLAYERHEAD_1ROW",
    "BATTLE_ANIM_OBJ_ENEMYFEET_1ROW",
    { player = { 0, 1 }, enemy = { 6, 1 } })
end

E.BATTLE_BG_EFFECT_BATTLEROBJ_2ROW = function(self, st)
  battlerObj(self, st, "BATTLE_ANIM_OBJ_PLAYERHEAD_2ROW",
    "BATTLE_ANIM_OBJ_ENEMYFEET_2ROW",
    { player = { 0, 2 }, enemy = { 5, 2 } })
end

-- BGEffect_RapidCyclePals.  On a CGB the palette is applied to ONE battler
-- (the struct's side) rather than to the whole background, which is what the
-- per-mon fades want; the port keeps that and leaves wBGP alone.
local function rapidCyclePals(self, st, pals)
  local jt = st.jt
  if jt == 0 then
    -- engine/battle_anims/bg_effects.asm:2480-2494
    incJt(st)
    st.side = self:sideKey(st)
    st.turn = st.param
    st.param = 0
    return
  end
  local side = st.side or self:sideKey(st)
  if jt == 1 then
    if bit.band(st.turn, 0xf) ~= 0 then
      st.turn = u8(st.turn - 1)
      return
    end
    -- The low nybble is reloaded from the high one, which is the step delay.
    st.turn = bit.bor(swap(st.turn), st.turn)
    local value = nextPal(st, pals)
    if value == nil then
      -- engine/battle_anims/bg_effects.asm:2515-2519
      st.param = u8(st.param - 1)
      return
    end
    self.monShade[side] = value
    return
  end
  self.monShade[side] = NORMAL_PAL
  endEffect(st)
end

local RAPID_PALS = {
  BATTLE_BG_EFFECT_RAPID_FLASH = { 0xe4, 0x6c, 0xfe },
  BATTLE_BG_EFFECT_FADE_MON_TO_LIGHT = { 0xe4, 0x90, 0x40, 0xff },
  BATTLE_BG_EFFECT_FADE_MON_TO_BLACK = { 0xe4, 0xf8, 0xfc, 0xff },
  BATTLE_BG_EFFECT_FADE_MON_TO_LIGHT_REPEATING = { 0xe4, 0x90, 0x40, 0x90, 0xfe },
  BATTLE_BG_EFFECT_FADE_MON_TO_BLACK_REPEATING = { 0xe4, 0xf8, 0xfc, 0xf8, 0xfe },
  BATTLE_BG_EFFECT_CYCLE_MON_LIGHT_DARK_REPEATING =
    { 0xe4, 0xf8, 0xfc, 0xf8, 0xe4, 0x90, 0x40, 0x90, 0xfe },
  BATTLE_BG_EFFECT_FLASH_MON_REPEATING = { 0xe4, 0xfc, 0xe4, 0x00, 0xfe },
  BATTLE_BG_EFFECT_FADE_MON_TO_WHITE_WAIT_FADE_BACK = {
    0xe4, 0x90, 0x40, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x40, 0x90, 0xe4, 0xff,
  },
  BATTLE_BG_EFFECT_FADE_MON_FROM_WHITE = { 0x00, 0x40, 0x90, 0xe4, 0xff },
}

for name, pals in pairs(RAPID_PALS) do
  E[name] = function(self, st) rapidCyclePals(self, st, pals) end
end

-- BattleBGEffect_FadeMonsToBlackRepeating fades BOTH battlers, on opposite
-- halves of the same four-step ramp.
local FADE_BOTH = { 0xe4, 0xe4, 0xf8, 0x90, 0xfc, 0x40, 0xf8, 0x90 }

E.BATTLE_BG_EFFECT_FADE_MONS_TO_BLACK_REPEATING = function(self, st)
  local jt = st.jt
  if jt == 0 then
    incJt(st)
    st.param = 0
    return
  end
  if jt == 1 then
    local age = st.param
    st.param = u8(st.param + 1)
    if bit.band(age, 7) ~= 0 then return end
    -- Bits 3-4 pick the pair, doubled into a row index.
    local index = bit.rshift(bit.band(age, 0x18), 3) * 2
    local first = FADE_BOTH[index + 1] or NORMAL_PAL
    local second = FADE_BOTH[index + 2] or NORMAL_PAL
    if self:playerSide(st) then
      self.monShade.player, self.monShade.enemy = first, second
    else
      self.monShade.enemy, self.monShade.player = first, second
    end
    return
  end
  self.monShade.player, self.monShade.enemy = NORMAL_PAL, NORMAL_PAL
  endEffect(st)
end

-- BattleBGEffects_GetShakeAmount.  JT is the total frame count, PARAM's low
-- nybble the countdown to the next flip (reloaded from its high nybble) and
-- `turn` the amplitude, negated on every flip.  Returns nil once it is done.
local function shakeAmount(self, st)
  if st.jt == 0 then
    endEffect(st)
    return nil
  end
  st.jt = st.jt - 1
  if bit.band(st.param, 0xf) ~= 0 then
    st.param = u8(st.param - 1)
    return st.turn
  end
  st.param = bit.bor(swap(st.param), st.param)
  st.turn = u8(-st.turn)
  return st.turn
end

E.BATTLE_BG_EFFECT_SHAKE_SCREEN_X = function(self, st)
  self.scx = shakeAmount(self, st) or 0
end

E.BATTLE_BG_EFFECT_SHAKE_SCREEN_Y = function(self, st)
  self.scy = shakeAmount(self, st) or 0
end

-- Rollout shakes vertically and hands the negated amount to the first anim
-- object's Y offset, so the boulder rides the shake instead of floating over
-- it.  The cart's extra DelayFrame here is what makes Rollout's animation run
-- at half speed; RunBattleAnimScript skips its own frame delay to compensate.
E.BATTLE_BG_EFFECT_ROLLOUT = function(self, st)
  local amount = shakeAmount(self, st)
  if amount == nil or bit.band(amount, 0x80) ~= 0 then amount = 0 end
  self.scy = amount
  self.rolloutYOffset = u8(-amount)
end

E.BATTLE_BG_EFFECT_WOBBLE_SCREEN = function(self, st)
  if st.param >= 0x40 then
    self.scx = 0
    return
  end
  self.scx = sine(st.param, 6)
  st.param = u8(st.param + 2)
end

-- Withdraw: a growing number of the attacker's scanlines are pushed off, so
-- the mon appears to pull into its shell.  PARAM's low six bits are how far
-- to go and its top two the step.
E.BATTLE_BG_EFFECT_WITHDRAW = function(self, st)
  local jt = st.jt
  if jt == 0 then
    incJt(st)
    self:clearLYOverrides(0)
    self:setLCDStatCustoms1("SCY", st)
    self.lyEnd = u8(self.lyEnd + 1)
    st.turn = 1
  elseif jt == 1 then
    local limit = bit.band(st.param, 0x3f)
    if st.turn >= limit then return end
    self:displaceLY(st.turn)
    local step = bit.band(bit.rshift(st.param, 6), 3)
    st.turn = u8(st.turn + step)
  elseif jt == 2 then
    self:resetLCDStatCustom(st)
  end
end

-- Dig: the same displacement, but it pauses and then eats the pic two
-- scanlines at a time until the whole window is gone.
E.BATTLE_BG_EFFECT_DIG = function(self, st)
  local jt = st.jt
  if jt == 0 then
    incJt(st)
    self:clearLYOverrides(0)
    self:setLCDStatCustoms1("SCY", st)
    self.lyEnd = u8(self.lyEnd + 1)
    st.turn = 2
    st.param = 0
  elseif jt == 1 then
    if st.param ~= 0 then
      st.param = u8(st.param - 1)
      return
    end
    st.param = 0x10
    incJt(st)
  elseif jt == 2 then
    local span = u8(self.lyEnd - self.lyStart) - 1
    if span < st.turn then return end
    -- Every eighth scanline the effect steps back a state, which is the
    -- pause between digs.
    if bit.band(st.turn, 7) == 0 then st.jt = u8(st.jt - 1) end
    self:displaceLY(st.turn)
    st.turn = u8(st.turn + 2)
  elseif jt == 3 then
    self:resetLCDStatCustom(st)
  end
end

-- Tackle: the attacker's rows slide eight pixels towards the target and back.
-- `turn` is the signed step and `param` the distance travelled so far.
local function tackleMoveForward(self, st)
  if st.param == u8(-8) or st.param == 8 then incJt(st) end
  self:fillLY(st.param)
  st.param = u8(st.param + st.turn)
end

local function tackleReturn(self, st)
  if st.param == 0 then incJt(st) end
  self:fillLY(st.param)
  st.param = u8(st.param + u8(-st.turn))
end

local function tackleInit(self, st, backwards)
  incJt(st)
  self:clearLYOverrides(0)
  self:setLCDStatCustoms1("SCX", st)
  self.lyEnd = u8(self.lyEnd + 1)
  -- SCX scrolls the BACKGROUND, so a negative value moves the mon RIGHT: the
  -- player's back pic steps towards the enemy on -2, not +2.
  local forward = self:playerSide(st) and u8(-2) or 2
  if backwards then forward = self:playerSide(st) and 2 or u8(-2) end
  st.param = 0
  st.turn = forward
end

E.BATTLE_BG_EFFECT_TACKLE = function(self, st)
  local jt = st.jt
  if jt == 0 then
    tackleInit(self, st, false)
  elseif jt == 1 then
    tackleMoveForward(self, st)
  elseif jt == 2 then
    tackleReturn(self, st)
  elseif jt == 3 then
    self:resetLCDStatCustom(st)
  end
end

E.BATTLE_BG_EFFECT_VITAL_THROW = function(self, st)
  local jt = st.jt
  if jt == 0 then
    tackleInit(self, st, true)
  elseif jt == 1 then
    tackleMoveForward(self, st)
  elseif jt == 3 then
    tackleReturn(self, st)
  elseif jt == 4 then
    self:resetLCDStatCustom(st)
  end
end

E.BATTLE_BG_EFFECT_BETA_PURSUIT = function(self, st)
  local jt = st.jt
  if jt == 0 then
    tackleInit(self, st, true)
  elseif jt == 1 then
    tackleMoveForward(self, st)
  elseif jt == 2 then
    tackleReturn(self, st)
  elseif jt == 3 then
    self:resetLCDStatCustom(st)
  end
end

-- engine/battle_anims/bg_effects.asm:1444
E.BATTLE_BG_EFFECT_BODY_SLAM = function(self, st)
  local jt = st.jt
  if jt == 0 then
    incJt(st)
    self:clearLYOverrides(0)
    self:setLCDStatCustoms2("SCX", st)
    self.lyEnd = u8(self.lyEnd + 1)
    st.param = 0
    st.turn = self:playerSide(st) and u8(-2) or 2
  elseif jt == 1 then
    tackleMoveForward(self, st)
  elseif jt == 2 then
    tackleReturn(self, st)
  elseif jt == 3 then
    self:resetLCDStatCustom(st)
  end
end

E.BATTLE_BG_EFFECT_WOBBLE_MON = function(self, st)
  local jt = st.jt
  if jt == 0 then
    incJt(st)
    self:clearLYOverrides(0)
    self:setLCDStatCustoms1("SCX", st)
    self.lyEnd = u8(self.lyEnd + 1)
    st.param = 0
  elseif jt == 1 then
    self:fillLY(sine(st.param, 8))
    st.param = u8(st.param + 4)
  elseif jt == 2 then
    self:resetLCDStatCustom(st)
  end
end

-- Always the player's rows, and the window is written directly rather than
-- through SetLCDStatCustoms1 -- this is the wobble the player's own mon does
-- when it is confused, whoever is attacking.
E.BATTLE_BG_EFFECT_WOBBLE_PLAYER = function(self, st)
  local jt = st.jt
  if jt == 0 then
    incJt(st)
    self:clearLYOverrides(0)
    self.lcdc = "SCX"
    self.lyStart, self.lyEnd = 0, 0x37
    st.param = 0
  elseif jt == 1 then
    if st.param >= 0x40 then
      self:resetLCDStatCustom(st)
      return
    end
    self:fillLY(sine(st.param, 6))
    st.param = u8(st.param + 2)
  elseif jt == 2 then
    self:resetLCDStatCustom(st)
  end
end

-- Two sines an octave apart, which is what makes Flail read as thrashing
-- rather than swaying.
E.BATTLE_BG_EFFECT_FLAIL = function(self, st)
  local jt = st.jt
  if jt == 0 then
    incJt(st)
    self:clearLYOverrides(0)
    self:setLCDStatCustoms1("SCX", st)
    self.lyEnd = u8(self.lyEnd + 1)
    st.turn, st.param = 0, 0
  elseif jt == 1 then
    local wide = sine(st.param, 6)
    local narrow = sine(st.turn, 2)
    self:fillLY(u8(wide + narrow))
    st.turn = u8(st.turn + 8)
    st.param = u8(st.param + 2)
  elseif jt == 2 then
    self:resetLCDStatCustom(st)
  end
end

E.BATTLE_BG_EFFECT_VIBRATE_MON = function(self, st)
  local jt = st.jt
  if jt == 0 then
    incJt(st)
    self:clearLYOverrides(0)
    self:setLCDStatCustoms1("SCX", st)
    self.lyEnd = u8(self.lyEnd + 1)
    st.turn = 1
    st.param = 0x20
  elseif jt == 1 then
    if st.param == 0 then
      self:resetLCDStatCustom(st)
      return
    end
    st.param = u8(st.param - 1)
    -- Flips on the even frames only, so it buzzes at 30 Hz rather than 60.
    if bit.band(st.param, 1) ~= 0 then return end
    st.turn = u8(-st.turn)
    self:fillLY(st.turn)
  end
end

-- BounceDown: the attacker drops in on a cosine and settles, using the same
-- scanline displacement Withdraw does.
E.BATTLE_BG_EFFECT_BOUNCE_DOWN = function(self, st)
  local jt = st.jt
  if jt == 0 then
    incJt(st)
    self:clearLYOverrides(0)
    self:setLCDStatCustoms2("SCY", st)
    self.lyEnd = u8(self.lyEnd + 1)
    st.turn = 1
    st.param = 0x20
  elseif jt == 1 then
    if st.turn >= 0x38 then return end
    local height = u8(cosine(st.param, 0x10) + 0x10)
    self:displaceLY(u8(st.turn + height))
    st.param = u8(st.param + 2)
  elseif jt == 2 then
    self:resetLCDStatCustom(st)
  end
end

--------------------------------------------------------------------------
-- The screen-wide deformations
--------------------------------------------------------------------------
--
-- These thirteen are the ones that write a DIFFERENT value to every scanline
-- rather than the same one to a band, so they all sit on DeformScreen,
-- DeformWater or the surf ring above.  The shape of each is the ASM's; what
-- the port cannot reproduce is the CGB writing rSCX mid-frame at sub-pixel
-- timing, and none of these depend on that -- they depend on the ARRAY, which
-- is modelled exactly.

-- Surf.  `.zero` lays a 2-amplitude wave into the ring and falls through to
-- `.one` on the same frame (ASM fallthrough, not a jumptable branch), and
-- `.one` waits for hLCDCPointer: engine/battle_anims/functions.asm:1158.
E.BATTLE_BG_EFFECT_SURF = function(self, st)
  local jt = st.jt
  if jt == 0 then
    incJt(st)
    self:initSurfWaves(2, 2)
    jt = 1
  end
  if jt == 1 then
    if not self.lcdc then return end
    self:rotateSurfWave()
  elseif jt == 2 then
    self:resetLCDStatCustom(st)
  end
end

-- Whirlpool: the wave covers the WHOLE screen ($00-$5e) rather than one
-- battler's rows, and it scrolls vertically (rSCY), so the water rolls
-- top to bottom behind both mons.
E.BATTLE_BG_EFFECT_WHIRLPOOL = function(self, st)
  local jt = st.jt
  if jt == 0 then
    incJt(st)
    self:clearLYOverrides(0)
    self.lcdc = "SCY"
    self.lyStart, self.lyEnd = 0, 0x5e
    self:deformScreen(2, 2)
  elseif jt == 1 then
    self:wavyScreenFX()
  elseif jt == 2 then
    self:resetLCDStatCustom(st)
  end
end

-- The three water effects, which the Surf animation drives as a set: START
-- opens the window and ends itself immediately, WATER does the work, END puts
-- the registers back.
E.BATTLE_BG_EFFECT_START_WATER = function(self, st)
  self:clearLYOverrides(0)
  self:setLCDStatCustoms1("SCY", st)
  endEffect(st)
end

-- WATER is the one effect whose three struct fields are all something else:
-- PARAM is the sine phase (climbing 4 a frame), BATTLE_TURN is a frame
-- counter that doubles as the amplitude, and JT_INDEX is the Y position the
-- deformation is centred on.
--
-- `ld a, [hl]` then `inc [hl]` twice leaves `a` holding the PRE-increment
-- turn, and that is the count DeformWater is called with -- so the figure
-- grows two scanlines a frame from nothing until the counter passes $20.
E.BATTLE_BG_EFFECT_WATER = function(self, st)
  local offset = st.param
  st.param = u8(st.param + 4)
  -- (0xff XOR the high nibble) + 4: the amplitude SHRINKS as the counter
  -- climbs, so the wave is widest when it first appears.
  local amplitude = u8(bit.bxor(bit.rshift(bit.band(st.turn, 0xf0), 4), 0xff) + 4)
  local progress = st.jt
  local count = st.turn
  if count >= 0x20 then
    self:clearLYOverrides(0)
    endEffect(st)
    return
  end
  st.turn = u8(st.turn + 2)
  self:deformWater(count, amplitude, offset, progress)
end

E.BATTLE_BG_EFFECT_END_WATER = function(self, st)
  self:resetLCDStatCustom(st)
end

-- Psychic is hardcoded to the whole screen ($00-$5f) whichever side used it,
-- and only travels every FOURTH frame (`and $3 / ret nz`), which is what makes
-- it a slow ripple rather than Teleport's shimmer.
E.BATTLE_BG_EFFECT_PSYCHIC = function(self, st)
  local jt = st.jt
  if jt == 0 then
    incJt(st)
    self:clearLYOverrides(0)
    self.lcdc = "SCX"
    self.lyStart, self.lyEnd = 0, 0x5f
    self:deformScreen(6, 5)
    st.param = 0
  elseif jt == 1 then
    local counter = st.param
    st.param = u8(st.param + 1)
    if bit.band(counter, 3) ~= 0 then return end
    self:wavyScreenFX()
  elseif jt == 2 then
    self:resetLCDStatCustom(st)
  end
end

-- Teleport: the same wave as Psychic but only over the user's own rows, and
-- travelling every frame.
E.BATTLE_BG_EFFECT_TELEPORT = function(self, st)
  local jt = st.jt
  if jt == 0 then
    incJt(st)
    self:clearLYOverrides(0)
    self:setLCDStatCustoms1("SCX", st)
    self:deformScreen(6, 5)
  elseif jt == 1 then
    self:wavyScreenFX()
  elseif jt == 2 then
    self:resetLCDStatCustom(st)
  end
end

-- Night Shade takes its phase step from the struct's PARAM, so the same
-- effect id gives a long slow roll or a tight ripple depending on what the
-- script queued it with.
E.BATTLE_BG_EFFECT_NIGHT_SHADE = function(self, st)
  local jt = st.jt
  if jt == 0 then
    incJt(st)
    self:clearLYOverrides(0)
    self:setLCDStatCustoms1("SCY", st)
    self:deformScreen(2, st.param)
  elseif jt == 1 then
    self:wavyScreenFX()
  elseif jt == 2 then
    self:resetLCDStatCustom(st)
  end
end

-- Double Team's afterimage: alternate scanlines are pushed +n and -n, so the
-- pic reads as two copies of itself a few pixels apart.  `.UpdateLYOverrides`
-- writes the pair (e, -e) down the window and, on an odd-height window,
-- repeats `e` on the last row -- `srl a` leaves the odd bit in carry and
-- `ret nc` is what skips that store on an even one.
local function doubleTeamOverrides(self, value)
  local e = u8(value)
  local d = u8(-e)
  local span = u8(self.lyEnd - self.lyStart)
  local pairs_ = bit.rshift(span, 1)
  local odd = bit.band(span, 1) ~= 0
  local row = self.lyStart
  for _ = 1, pairs_ do
    if row > SCREEN_ROWS then return end
    self.lyBackup[row] = e
    row = row + 1
    if row > SCREEN_ROWS then return end
    self.lyBackup[row] = d
    row = row + 1
  end
  if odd and row <= SCREEN_ROWS then self.lyBackup[row] = e end
end

E.BATTLE_BG_EFFECT_DOUBLE_TEAM = function(self, st)
  local jt = st.jt
  if jt == 0 then
    incJt(st)
    self:clearLYOverrides(0)
    self:setLCDStatCustoms1("SCX", st)
    self.lyEnd = u8(self.lyEnd + 1)
    st.turn = 0
  elseif jt == 1 then
    -- Split apart, a pixel a frame, to $10.
    if st.param >= 0x10 then
      incJt(st)
      return
    end
    local value = st.param
    st.param = u8(st.param + 1)
    doubleTeamOverrides(self, value)
  elseif jt == 2 then
    -- Hold, wobbling about the current separation.  This state never advances
    -- itself; the script's own `incbgeffect` is what moves it on.
    local wobble = u8(sine(st.turn, 2) + st.param)
    doubleTeamOverrides(self, wobble)
    st.turn = u8(st.turn + 4)
  elseif jt == 3 then
    -- Come back together.  The test is `cp $ff`, so a PARAM that started at 0
    -- underflows to $ff and stops there rather than at zero.
    if st.param == 0xff then
      incJt(st)
      return
    end
    local value = st.param
    st.param = u8(st.param - 1)
    doubleTeamOverrides(self, value)
  elseif jt == 5 then
    self:resetLCDStatCustom(st)
  end
  -- jt 4 is a bare `ret`: the gap the script sits in between the two halves.
end

-- Acid Armor: the wave is laid down once and then the whole window is scrolled
-- DOWN one scanline a frame, with a blank row ($90) fed in at the top -- so
-- the mon melts into the floor instead of wobbling in place.  The two
-- fix-ups at the bottom clear the last two rows once their values are large
-- enough to be showing the pic's own bottom edge.
E.BATTLE_BG_EFFECT_ACID_ARMOR = function(self, st)
  local jt = st.jt
  if jt == 0 then
    incJt(st)
    self:clearLYOverrides(0)
    self:setLCDStatCustoms1("SCY", st)
    self:deformScreen(2, st.param)
    self.lyBackup[self.lyEnd] = 0
    self.lyBackup[self.lyEnd - 1] = 0
  elseif jt == 1 then
    for row = self.lyEnd, self.lyStart + 1, -1 do
      self.lyBackup[row] = self.lyBackup[row - 1] or 0
    end
    self.lyBackup[self.lyStart] = 0x90
    local last = self.lyBackup[self.lyEnd] or 0
    if last >= 1 and last ~= 0x90 then self.lyBackup[self.lyEnd] = 0 end
    local penultimate = self.lyBackup[self.lyEnd - 1] or 0
    if penultimate >= 2 and penultimate ~= 0x90 then
      self.lyBackup[self.lyEnd - 1] = 0
    end
  elseif jt == 2 then
    self:resetLCDStatCustom(st)
  end
end

-- Wave Deform: the amplitude ramps up to $20 in state 1 and back down to 0 in
-- state 2, at a fixed phase step of 4.  Neither ramp advances the state on its
-- own -- the script does -- so how far it gets is the script's business.
E.BATTLE_BG_EFFECT_WAVE_DEFORM_MON = function(self, st)
  local jt = st.jt
  if jt == 0 then
    incJt(st)
    self:clearLYOverrides(0)
    self:setLCDStatCustoms1("SCX", st)
  elseif jt == 1 then
    if st.param >= 0x20 then return end
    local amplitude = st.param
    st.param = u8(st.param + 1)
    self:deformScreen(amplitude, 4)
  elseif jt == 2 then
    if st.param == 0 then
      self:resetLCDStatCustom(st)
      return
    end
    local amplitude = st.param
    st.param = u8(st.param - 1)
    self:deformScreen(amplitude, 4)
  end
end

-- The two beta send-outs are `; unused` on the cart -- nothing queues them --
-- but they are in the jumptable, so a mod or a hand-written script can, and
-- an unimplemented entry would sit in the pool forever.
--
-- MON1 writes rBGP per scanline rather than a scroll register: every other
-- row of the window steps through $00 (all white), $40, $90 and $e4 (normal),
-- eight frames apart, so the pic fades in through a venetian blind.
local BETA_SEND_OUT_PALS = { 0x00, 0x40, 0x90, 0xe4 }

-- `.SetLYOverridesBackup`: every SECOND scanline, (lyEnd - lyStart) / 2 times.
local function betaBlind(self, value)
  local count = bit.rshift(u8(self.lyEnd - self.lyStart), 1)
  local row = self.lyStart
  for _ = 1, count do
    if row > SCREEN_ROWS then return end
    self.lyBackup[row] = u8(value)
    row = row + 2
  end
end

-- `.GetLYOverride`: PARAM counts up and its top bits index the palette list,
-- so each entry is held eight frames.  Past the end it returns nil, which is
-- the `cp $ff` the caller branches on.
local function betaPal(st)
  local index = bit.rshift(st.param, 3)
  st.param = u8(st.param + 1)
  return BETA_SEND_OUT_PALS[index + 1]
end

E.BATTLE_BG_EFFECT_BETA_SEND_OUT_MON1 = function(self, st)
  local jt = st.jt
  if jt == 0 then
    incJt(st)
    self:clearLYOverrides(0xe4)
    self:setLCDStatCustoms1("BGP", st)
    self.lyEnd = u8(self.lyEnd + 1)
    for row = self.lyStart, self.lyEnd - 1 do
      if row > SCREEN_ROWS then break end
      self.lyBackup[row] = 0
    end
    st.param = 0
    -- `.zero` falls into `.one`, which is a bare ret.
  elseif jt == 2 then
    local value = betaPal(st)
    if value then
      betaBlind(self, value)
      return
    end
    st.param = 0
    self.lyStart = u8(self.lyStart + 1)
    incJt(st)
  elseif jt == 3 then
    local value = betaPal(st)
    if not value then
      incJt(st)
      return
    end
    betaBlind(self, value)
    -- The second pass also fills the row the blind skipped at the bottom.
    self.lyBackup[self.lyEnd - 1] = u8(value)
  elseif jt == 5 then
    self:resetVideoHRAM()
    endEffect(st)
  end
  -- jt 1 and 4 are bare rets.
end

-- MON2 is a plain DeformScreen whose amplitude and phase step are the SAME
-- value, counted down from $40 in eighths -- so the wobble starts at 8 and
-- unwinds to nothing.
E.BATTLE_BG_EFFECT_BETA_SEND_OUT_MON2 = function(self, st)
  local jt = st.jt
  if jt == 0 then
    incJt(st)
    self:clearLYOverrides(0)
    self:setLCDStatCustoms1("SCX", st)
    st.turn = 0x40
  elseif jt == 1 then
    if st.turn == 0 then
      self:resetLCDStatCustom(st)
      return
    end
    local value = st.turn
    st.turn = u8(st.turn - 1)
    -- `ld a, [hl] / dec [hl] / srl a x3`: the PRE-decrement value, shifted.
    local amount = bit.band(bit.rshift(value, 3), 0x0f)
    self:deformScreen(amount, amount)
  end
end

-- Nothing is left unmodelled.  The name stays so a caller (and the tests) can
-- still ask, and so the answer is checkable rather than a claim in a comment.
local UNMODELLED = {}
local UNMODELLED_SET = {}
for _, name in ipairs(UNMODELLED) do UNMODELLED_SET[name] = true end

local DROPPED = {}
BgEffects.DROPPED = DROPPED
BgEffects.strict = os.getenv("POKEPORT_DEV") == "1"

local function dropUnknown(st)
  local name = st.func
  endEffect(st)
  if UNMODELLED_SET[name] then return end
  if not DROPPED[name] then
    DROPPED[name] = true
    DROPPED[#DROPPED + 1] = name
  end
  if BgEffects.strict then
    error("BgEffects: no entry for " .. tostring(name))
  end
end

--------------------------------------------------------------------------

-- ExecuteBGEffects: one pass over the five structs.
function Pool:playFrame()
  for slot = 1, NUM_EFFECTS do
    local st = self.effects[slot]
    if st.func then
      local fn = E[st.func]
      if fn then
        fn(self, st)
      else
        -- An id with no entry would otherwise sit in the pool forever and
        -- keep the animation from ending.
        dropUnknown(st)
      end
    end
  end
end

function Pool:takeSpawns()
  local spawns = self.spawns
  self.spawns = {}
  return spawns
end

BgEffects.EFFECTS = E
BgEffects.NUM_EFFECTS = NUM_EFFECTS
BgEffects.NORMAL_PAL = NORMAL_PAL
BgEffects.SCREEN_ROWS = SCREEN_ROWS
BgEffects.UNMODELLED = UNMODELLED

return BgEffects
