#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;" .. package.path

local SizeRecord = require("src.core.game3.pokemon_size_record")
local Std = require("src.core.game3.scripting.stdscripts")
local Natives = require("src.core.game3.scripting.natives")
local Flags = require("src.core.game3.scripting.flags")

local passed = 0
local failed = 0

local function check(cond, msg)
  if cond then
    passed = passed + 1
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function eq(a, b, msg)
  check(a == b, (msg or "equal") .. " (got " .. tostring(a) .. ", expected " .. tostring(b) .. ")")
end

local function makeSession()
  return {
    party = {},
    vars = {},
    stringVars = {},
    specialVars = {},
  }
end

local function makeCtx(session)
  return {
    session = session,
    stringVars = session.stringVars,
    specialVars = session.specialVars,
  }
end

print("=== 1. Size Hash and Size Calculation ===")
do
  local mon1 = {
    species = 129, -- Magikarp
    personality = 0x12345678,
    ivHp = 15,
    ivAtk = 10,
    ivDef = 5,
    ivSpd = 12,
    ivSpAtk = 8,
    ivSpDef = 4,
  }
  local hash1 = SizeRecord.getMonSizeHash(mon1)
  check(hash1 >= 0 and hash1 <= 0xFFFF, "hash is 16-bit unsigned (got " .. tostring(hash1) .. ")")

  -- Verify exact formula:
  -- atk ^ def = 10 ^ 5 = 15
  -- (15 * 15) ^ (0x78) = 225 ^ 120 = 153 (0x99)
  -- spAtk ^ spDef = 8 ^ 4 = 12
  -- (12 * 12) ^ (0x56) = 144 ^ 86 = 198 (0xC6)
  -- (153 << 8) | 198 = 39366 (0x99C6)
  eq(hash1, 39366, "hash1 exact formula value")

  -- Size calculation with b = 0 for Magikarp (height = 9 dm)
  -- var = 1, unk0 = 290, unk2 = 1, unk4 = 0 -> unk0 = 290
  -- size = floor(9 * 290 / 10) = 261 cm-tenths (26.1 cm)
  local size0 = SizeRecord.getMonSize(129, 0)
  eq(size0, 261, "Magikarp min size cm-tenths (b=0)")

  -- Format size: 261 * 100 / 254 = 102 -> 10.2 inches
  local str0 = SizeRecord.formatMonSizeRecord(size0)
  eq(str0, "10.2", "Magikarp formatted min size in inches")

  -- Heracross (height = 15 dm) with b = 0
  -- size = floor(15 * 290 / 10) = 435 cm-tenths (43.5 cm)
  -- format: 435 * 100 / 254 = 171 -> 17.1 inches
  local sizeHera0 = SizeRecord.getMonSize(214, 0)
  eq(sizeHera0, 435, "Heracross min size cm-tenths (b=0)")
  eq(SizeRecord.formatMonSizeRecord(sizeHera0), "17.1", "Heracross formatted min size in inches")
end

print("=== 2. New Game Initialization ===")
do
  local s = makeSession()
  local ctx = makeCtx(s)

  SizeRecord.setVar(s, ctx, SizeRecord.VAR_MAGIKARP_SIZE_RECORD, 500)
  SizeRecord.setVar(s, ctx, SizeRecord.VAR_HERACROSS_SIZE_RECORD, 500)

  SizeRecord.initMagikarpSizeRecord(s, ctx)
  SizeRecord.initHeracrossSizeRecord(s, ctx)

  eq(SizeRecord.getVar(s, ctx, SizeRecord.VAR_MAGIKARP_SIZE_RECORD), 0, "Magikarp size record init to 0")
  eq(SizeRecord.getVar(s, ctx, SizeRecord.VAR_HERACROSS_SIZE_RECORD), 0, "Heracross size record init to 0")
end

print("=== 3. GetMonSizeRecordInfo ===")
do
  local s = makeSession()
  local ctx = makeCtx(s)
  local adapters = {
    setStringVar = function(idx, val) s.stringVars[idx] = val end,
  }

  SizeRecord.setVar(s, ctx, SizeRecord.VAR_MAGIKARP_SIZE_RECORD, 0)
  SizeRecord.getMonSizeRecordInfo(s, ctx, adapters, SizeRecord.SPECIES_MAGIKARP, SizeRecord.VAR_MAGIKARP_SIZE_RECORD)
  eq(s.stringVars[1], "MAGIKARP", "StringVar1 has MAGIKARP")
  eq(s.stringVars[3], "10.2", "StringVar3 has 10.2")

  SizeRecord.setVar(s, ctx, SizeRecord.VAR_HERACROSS_SIZE_RECORD, 0)
  SizeRecord.getMonSizeRecordInfo(s, ctx, adapters, SizeRecord.SPECIES_HERACROSS, SizeRecord.VAR_HERACROSS_SIZE_RECORD)
  eq(s.stringVars[1], "HERACROSS", "StringVar1 has HERACROSS")
  eq(s.stringVars[3], "17.1", "StringVar3 has 17.1")
end

print("=== 4. CompareMonSize Logic ===")
do
  local s = makeSession()
  local ctx = makeCtx(s)
  local adapters = {
    setStringVar = function(idx, val) s.stringVars[idx] = val end,
  }

  local karpSmall = { species = 129, personality = 0x00000000, ivHp = 0, ivAtk = 0, ivDef = 0, ivSpd = 0, ivSpAtk = 0, ivSpDef = 0 }
  local karpBig = { species = 129, personality = 0xFFFFFFFF, ivHp = 15, ivAtk = 15, ivDef = 0, ivSpd = 15, ivSpAtk = 15, ivSpDef = 0 }
  local pikachu = { species = 25, personality = 0x12345678 }
  local egg = { species = 129, isEgg = true }

  s.party = { karpSmall, karpBig, pikachu, egg }

  -- Invalid slot
  local code = SizeRecord.compareMonSize(s, ctx, adapters, SizeRecord.SPECIES_MAGIKARP, SizeRecord.VAR_MAGIKARP_SIZE_RECORD, 6)
  eq(code, 0, "slot >= 6 returns 0 (cancel)")

  -- Non-matching species (Pikachu)
  code = SizeRecord.compareMonSize(s, ctx, adapters, SizeRecord.SPECIES_MAGIKARP, SizeRecord.VAR_MAGIKARP_SIZE_RECORD, 2)
  eq(code, 1, "wrong species returns 1")

  -- Egg
  code = SizeRecord.compareMonSize(s, ctx, adapters, SizeRecord.SPECIES_MAGIKARP, SizeRecord.VAR_MAGIKARP_SIZE_RECORD, 3)
  eq(code, 1, "egg returns 1")

  -- Big Magikarp against record 0 (init): should set record (status 3)
  SizeRecord.setVar(s, ctx, SizeRecord.VAR_MAGIKARP_SIZE_RECORD, 0)
  code = SizeRecord.compareMonSize(s, ctx, adapters, SizeRecord.SPECIES_MAGIKARP, SizeRecord.VAR_MAGIKARP_SIZE_RECORD, 1)
  eq(code, 3, "bigger mon sets new record (returns 3)")
  local updatedRecord = SizeRecord.getVar(s, ctx, SizeRecord.VAR_MAGIKARP_SIZE_RECORD)
  check(updatedRecord > 0, "VAR_MAGIKARP_SIZE_RECORD updated to new hash")

  -- Small Magikarp against updated big record: should return 2 (smaller)
  code = SizeRecord.compareMonSize(s, ctx, adapters, SizeRecord.SPECIES_MAGIKARP, SizeRecord.VAR_MAGIKARP_SIZE_RECORD, 0)
  eq(code, 2, "smaller mon returns 2")

  -- Big Magikarp again against its own record: should return 4 (tie)
  code = SizeRecord.compareMonSize(s, ctx, adapters, SizeRecord.SPECIES_MAGIKARP, SizeRecord.VAR_MAGIKARP_SIZE_RECORD, 1)
  eq(code, 4, "same size mon returns 4 (tie)")
end

print("=== 5. Specials Execution via Natives ===")
do
  local s = makeSession()
  local ctx = makeCtx(s)
  local Space = require("src.core.game3.scripting.space")
  Space.store = s

  local adapters = {
    setStringVar = function(idx, val) s.stringVars[idx] = val end,
  }

  local heraBig = { species = 214, personality = 0x55555555, ivHp = 15, ivAtk = 15, ivDef = 0, ivSpd = 15, ivSpAtk = 15, ivSpDef = 0 }
  s.party = { heraBig }

  -- Special 0x77: GetHeracrossSizeRecordInfo
  Natives.special(ctx, Std.SPECIAL.GetHeracrossSizeRecordInfo, adapters)
  eq(s.stringVars[1], "HERACROSS", "special 0x77 set HERACROSS")

  -- Special 0x78: CompareHeracrossSize (VAR_RESULT slot 0)
  Flags.setVar(s, ctx, 0x800D, 0)
  Natives.special(ctx, Std.SPECIAL.CompareHeracrossSize, adapters)
  eq(Flags.getVar(s, ctx, 0x800D), 3, "special 0x78 set new record (VAR_RESULT = 3)")

  -- Special 0x79: GetMagikarpSizeRecordInfo
  Natives.special(ctx, Std.SPECIAL.GetMagikarpSizeRecordInfo, adapters)
  eq(s.stringVars[1], "MAGIKARP", "special 0x79 set MAGIKARP")

  -- Special 0x7A: CompareMagikarpSize (slot 0 is Heracross -> returns 1)
  Flags.setVar(s, ctx, 0x800D, 0)
  Natives.special(ctx, Std.SPECIAL.CompareMagikarpSize, adapters)
  eq(Flags.getVar(s, ctx, 0x800D), 1, "special 0x7A slot 0 not Magikarp (VAR_RESULT = 1)")
end

print(string.format("\nTotal: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
