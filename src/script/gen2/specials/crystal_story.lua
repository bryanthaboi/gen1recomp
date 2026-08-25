-- ../pokecrystal/data/events/special_pointers.asm:141 GiveOddEgg, :148
-- OmanyteChamber, :157 HoOhChamber, :159 CelebiShrineEvent, :160
-- CheckCaughtCelebi, :164 GiveDratini, :166 BeastsCheck.

local Specials = require("src.script.gen2.Specials")
local Mon = require("src.battle.gen2.Mon")
local UnownWords = require("src.world.gen2.UnownWords")

local S = Specials.shared
local M = {}

-- ../pokecrystal/constants/script_constants.asm:51 VAR_BATTLETYPE.
local VAR_BATTLETYPE = 0x03
-- ../pokecrystal/constants/battle_constants.asm:102 BATTLETYPE_CELEBI.
local BATTLETYPE_CELEBI = 11

-- ../pokecrystal/engine/pokemon/search_owned.asm:6, :11, :16 -- the order the
-- routine writes into wScriptVar before each CheckOwnMonAnywhere.
local BEASTS = { "RAIKOU", "ENTEI", "SUICUNE" }

-- ../pokecrystal/engine/pokemon/search_owned.asm:1; MonCheck is
-- CheckOwnMonAnywhere (:48) with the answer already written.
M.BeastsCheck = function(vm)
  local monCheck = Specials.HANDLERS.MonCheck
  local h = S.hooks(vm)
  for _, name in ipairs(BEASTS) do
    vm.scriptVar = (h.monIndex and h.monIndex(name)) or name
    monCheck(vm)
    if vm.scriptVar ~= S.TRUE then
      S.answer(vm, S.FALSE)
      return
    end
  end
  S.answer(vm, S.TRUE)
end

-- ../pokecrystal/engine/events/dratini.asm:72 .Moveset0, :79 .Moveset1.
local DRATINI = "DRATINI"
local DRATINI_MOVESETS = {
  [0] = { "WRAP", "THUNDER_WAVE", "TWISTER", "EXTREMESPEED" },
  [1] = { "WRAP", "LEER", "THUNDER_WAVE", "TWISTER" },
}

-- ../pokecrystal/engine/events/dratini.asm:1: `cp $2 / ret nc`, then :16
-- .CheckForDratini walks the party BACKWARDS from the last slot.
M.GiveDratini = function(vm)
  local set = DRATINI_MOVESETS[vm.scriptVar or 0]
  if not set then return end
  local list = S.party(vm)
  local target
  for index = #list, 1, -1 do
    local mon = list[index]
    if mon and mon.species == DRATINI then
      target = mon
      break
    end
  end
  if not target then return end
  -- ../pokecrystal/engine/events/dratini.asm:54: each new move's PP comes from
  -- Moves + MOVE_PP, so a PP Up on the replaced slot is dropped.
  local defs = S.data(vm)
  local moves = defs and defs.moves
  target.moves = target.moves or {}
  for index, id in ipairs(set) do
    local pp = (moves and moves[id] and moves[id].pp) or 0
    target.moves[index] = { id = id, pp = pp, maxPp = pp }
  end
end

-- ../pokecrystal/data/events/odd_eggs.asm:14-33, the `odd_egg_prob` arguments in
-- order; the macro (:5) accumulates them and stores total * $ffff / 100.
local ODD_EGG_PERCENTS = { 8, 1, 16, 3, 16, 3, 14, 2, 10, 2, 12, 2, 10, 1 }

local ODD_EGG_PROBABILITIES = {}
do
  local total = 0
  for index, percent in ipairs(ODD_EGG_PERCENTS) do
    total = total + percent
    ODD_EGG_PROBABILITIES[index] = math.floor(total * 0xffff / 100)
  end
end

-- ../pokecrystal/data/events/odd_eggs.asm:37 OddEggs, one row per
-- NICKNAMED_MON_STRUCT.
local ODD_EGGS = {
  { species = "PICHU", otId = 2048, experience = 125, level = 5, eggSteps = 20,
    moves = { "THUNDERSHOCK", "CHARM", "DIZZY_PUNCH" },
    pp = { 30, 20, 10 },
    dvs = { attack = 0, defense = 0, speed = 0, special = 0 },
    stats = { hp = 17, attack = 9, defense = 6, speed = 11,
      specialAttack = 8, specialDefense = 8 } },
  { species = "PICHU", otId = 256, experience = 125, level = 5, eggSteps = 20,
    moves = { "THUNDERSHOCK", "CHARM", "DIZZY_PUNCH" },
    pp = { 30, 20, 10 },
    dvs = { attack = 2, defense = 10, speed = 10, special = 10 },
    stats = { hp = 17, attack = 9, defense = 7, speed = 12,
      specialAttack = 9, specialDefense = 9 } },
  { species = "CLEFFA", otId = 4096, experience = 125, level = 5, eggSteps = 20,
    moves = { "POUND", "CHARM", "DIZZY_PUNCH" },
    pp = { 35, 20, 10 },
    dvs = { attack = 0, defense = 0, speed = 0, special = 0 },
    stats = { hp = 20, attack = 7, defense = 7, speed = 6,
      specialAttack = 9, specialDefense = 10 } },
  { species = "CLEFFA", otId = 768, experience = 125, level = 5, eggSteps = 20,
    moves = { "POUND", "CHARM", "DIZZY_PUNCH" },
    pp = { 35, 20, 10 },
    dvs = { attack = 2, defense = 10, speed = 10, special = 10 },
    stats = { hp = 20, attack = 7, defense = 8, speed = 7,
      specialAttack = 10, specialDefense = 11 } },
  { species = "IGGLYBUFF", otId = 4096, experience = 125, level = 5,
    eggSteps = 20,
    moves = { "SING", "CHARM", "DIZZY_PUNCH" },
    pp = { 15, 20, 10 },
    dvs = { attack = 0, defense = 0, speed = 0, special = 0 },
    stats = { hp = 24, attack = 8, defense = 6, speed = 6,
      specialAttack = 9, specialDefense = 7 } },
  { species = "IGGLYBUFF", otId = 768, experience = 125, level = 5,
    eggSteps = 20,
    moves = { "SING", "CHARM", "DIZZY_PUNCH" },
    pp = { 15, 20, 10 },
    dvs = { attack = 2, defense = 10, speed = 10, special = 10 },
    stats = { hp = 24, attack = 8, defense = 7, speed = 7,
      specialAttack = 10, specialDefense = 8 } },
  { species = "SMOOCHUM", otId = 3584, experience = 125, level = 5,
    eggSteps = 20,
    moves = { "POUND", "LICK", "DIZZY_PUNCH" },
    pp = { 35, 30, 10 },
    dvs = { attack = 0, defense = 0, speed = 0, special = 0 },
    stats = { hp = 19, attack = 8, defense = 6, speed = 11,
      specialAttack = 13, specialDefense = 11 } },
  { species = "SMOOCHUM", otId = 512, experience = 125, level = 5,
    eggSteps = 20,
    moves = { "POUND", "LICK", "DIZZY_PUNCH" },
    pp = { 35, 30, 10 },
    dvs = { attack = 2, defense = 10, speed = 10, special = 10 },
    stats = { hp = 19, attack = 8, defense = 7, speed = 12,
      specialAttack = 14, specialDefense = 12 } },
  { species = "MAGBY", otId = 2560, experience = 125, level = 5, eggSteps = 20,
    moves = { "EMBER", "DIZZY_PUNCH" },
    pp = { 25, 10 },
    dvs = { attack = 0, defense = 0, speed = 0, special = 0 },
    stats = { hp = 19, attack = 12, defense = 8, speed = 13,
      specialAttack = 12, specialDefense = 10 } },
  { species = "MAGBY", otId = 512, experience = 125, level = 5, eggSteps = 20,
    moves = { "EMBER", "DIZZY_PUNCH" },
    pp = { 25, 10 },
    dvs = { attack = 2, defense = 10, speed = 10, special = 10 },
    stats = { hp = 19, attack = 12, defense = 9, speed = 14,
      specialAttack = 13, specialDefense = 11 } },
  { species = "ELEKID", otId = 3072, experience = 125, level = 5, eggSteps = 20,
    moves = { "QUICK_ATTACK", "LEER", "DIZZY_PUNCH" },
    pp = { 30, 30, 10 },
    dvs = { attack = 0, defense = 0, speed = 0, special = 0 },
    stats = { hp = 19, attack = 11, defense = 8, speed = 14,
      specialAttack = 11, specialDefense = 10 } },
  { species = "ELEKID", otId = 512, experience = 125, level = 5, eggSteps = 20,
    moves = { "QUICK_ATTACK", "LEER", "DIZZY_PUNCH" },
    pp = { 30, 30, 10 },
    dvs = { attack = 2, defense = 10, speed = 10, special = 10 },
    stats = { hp = 19, attack = 11, defense = 9, speed = 15,
      specialAttack = 12, specialDefense = 11 } },
  { species = "TYROGUE", otId = 2560, experience = 125, level = 5,
    eggSteps = 20,
    moves = { "TACKLE", "DIZZY_PUNCH" },
    pp = { 35, 10 },
    dvs = { attack = 0, defense = 0, speed = 0, special = 0 },
    stats = { hp = 18, attack = 8, defense = 8, speed = 8,
      specialAttack = 8, specialDefense = 8 } },
  { species = "TYROGUE", otId = 256, experience = 125, level = 5, eggSteps = 20,
    moves = { "TACKLE", "DIZZY_PUNCH" },
    pp = { 35, 10 },
    dvs = { attack = 2, defense = 10, speed = 10, special = 10 },
    stats = { hp = 18, attack = 8, defense = 9, speed = 9,
      specialAttack = 9, specialDefense = 9 } },
}

-- ../pokecrystal/engine/events/odd_egg.asm:93 `.Odd` is the OT NAME
-- (../pokecrystal/mobile/mobile_46.asm:7561); wOddEggName ("EGG") is the nickname.
local ODD_EGG_OT = "ODD"
local ODD_EGG_NICKNAME = "EGG"
local EGG_TICKET = "EGG_TICKET"

-- ../pokecrystal/engine/events/odd_egg.asm:5-38, one Random word against the
-- cumulative table; the $ffff break is :17.
local function oddEggIndex(roll)
  for index = 1, #ODD_EGG_PROBABILITIES do
    local probability = ODD_EGG_PROBABILITIES[index]
    if probability >= 0xffff then return index end
    if roll <= probability then return index end
  end
  return #ODD_EGG_PROBABILITIES
end

-- ../pokecrystal/engine/events/odd_egg.asm:40-48, NICKNAMED_MON_STRUCT_LENGTH
-- bytes copied verbatim.
local function buildOddEgg(data, row, save)
  if not (data and row) then return nil end
  local moves = {}
  for index, id in ipairs(row.moves) do
    local pp = row.pp[index] or 0
    moves[index] = { id = id, pp = pp, maxPp = pp }
  end
  local dvs = {
    attack = row.dvs.attack, defense = row.dvs.defense,
    speed = row.dvs.speed, special = row.dvs.special,
  }
  local egg = Mon.new(data, row.species, row.level, {
    dvs = dvs,
    moves = moves,
    -- ../pokecrystal/data/events/odd_eggs.asm:57 `bigdw 0 ; HP`
    hp = 0,
    nickname = ODD_EGG_NICKNAME,
  })
  if not egg then return nil end
  egg.experience = row.experience
  egg.stats = {
    hp = row.stats.hp, attack = row.stats.attack,
    defense = row.stats.defense, speed = row.stats.speed,
    specialAttack = row.stats.specialAttack,
    specialDefense = row.stats.specialDefense,
  }
  egg.maxHp = row.stats.hp
  egg.hp = 0
  -- ../pokecrystal/mobile/mobile_46.asm:7528 writes EGG into wPartySpecies while the struct
  -- keeps the hatchling's own species.
  egg.isEgg = true
  -- ../pokecrystal/data/events/odd_eggs.asm:53 `db 20 ; Step cycles to hatch`,
  -- the byte MON_HAPPINESS holds while the thing is an egg.
  egg.eggSteps = row.eggSteps
  egg.ot = ODD_EGG_OT
  egg.otName = ODD_EGG_OT
  egg.otId = row.otId
  if save then Mon.stampOT(save, egg) end
  return egg
end

-- ../pokecrystal/engine/events/odd_egg.asm:1.  The party-full refusal is the
-- caller's (../pokecrystal/maps/DayCare.asm:31-32), not the routine's.
M.GiveOddEgg = function(vm)
  local record = S.save(vm)
  local data = S.data(vm)
  if not (record and data) then return end
  local party = record.party or {}
  record.party = party
  if #party >= Mon.PARTY_SIZE then return end
  local row = ODD_EGGS[oddEggIndex(Specials.random(0x10000) - 1)]
  local egg = buildOddEgg(data, row, record)
  if not egg then return end
  -- ../pokecrystal/engine/events/odd_egg.asm:50-57 TossItem on the EGG TICKET,
  -- ahead of the party write.
  local h = S.hooks(vm)
  local ticket = h.itemIndex and h.itemIndex(EGG_TICKET)
  if ticket and h.takeItem then h.takeItem(ticket, 1) end
  party[#party + 1] = egg
end

-- ../pokecrystal/engine/events/unown_walls.asm:1, run by
-- ../pokecrystal/maps/RuinsOfAlphHoOhChamber.asm:10.
M.HoOhChamber = function(vm)
  if not UnownWords.leadIsHoOh(S.party(vm)) then return end
  UnownWords.openWall(vm.events, "HO_OH")
end

-- ../pokecrystal/engine/events/unown_walls.asm:13, run by
-- ../pokecrystal/maps/RuinsOfAlphOmanyteChamber.asm:10; :25 CheckItem then :38
-- MON_ITEM.
M.OmanyteChamber = function(vm)
  if UnownWords.wallOpened(vm.events, "OMANYTE") then return end
  local h = S.hooks(vm)
  local index = h.itemIndex and h.itemIndex(UnownWords.WATER_STONE)
  local inPack = index and h.hasItem and h.hasItem(index)
  if not inPack and not UnownWords.waterStoneSlot(S.party(vm)) then return end
  UnownWords.openWall(vm.events, "OMANYTE")
end

-- ../pokecrystal/engine/events/celebi.asm:9; :296 CelebiEvent_SetBattleType is
-- the only state it leaves, and src/world/gen2/World.lua:6161 clears that.
M.CelebiShrineEvent = function(vm)
  if vm.writeVarFn then vm.writeVarFn(VAR_BATTLETYPE, BATTLETYPE_CELEBI) end
  vm.celebiArmed = true
end

-- ../pokecrystal/engine/events/celebi.asm:301 reads the bit
-- ../pokecrystal/engine/items/item_effects.asm:545 sets, gated on :542.
M.CheckCaughtCelebi = function(vm)
  local caught = vm.celebiArmed == true and vm.battleOutcome == "caught"
  vm.celebiArmed = nil
  if caught then
    local record = S.save(vm)
    if record then
      local Save = require("src.core.gen2.Save")
      Save.crystalState(record).celebiCaught = true
    end
  end
  S.answer(vm, caught and S.TRUE or S.FALSE)
end

return M
