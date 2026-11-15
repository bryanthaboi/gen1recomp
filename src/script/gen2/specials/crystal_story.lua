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

local DRATINI = "DRATINI"

local function eventTable(vm, key)
  local data = S.data(vm)
  local tables = data and data.gen2EventTables
  local value = tables and tables[key]
  if value == nil then error("events.lua has no " .. key, 2) end
  return value
end

-- ../pokecrystal/engine/events/dratini.asm:1: `cp $2 / ret nc`, then :16
-- .CheckForDratini walks the party BACKWARDS from the last slot.
M.GiveDratini = function(vm)
  local set = eventTable(vm, "dratiniMovesets")[(vm.scriptVar or 0) + 1]
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

local EGG_TICKET = "EGG_TICKET"

-- ../pokecrystal/engine/events/odd_egg.asm:5-38, one Random word against the
-- cumulative table; the $ffff break is :17.
local function oddEggIndex(rows, roll)
  for index, row in ipairs(rows) do
    if row.probability >= 0xffff then return index end
    if roll <= row.probability then return index end
  end
  return #rows
end

-- ../pokecrystal/engine/events/odd_egg.asm:40-48, :82-90,
-- ../pokecrystal/mobile/mobile_46.asm:7561
local function buildOddEgg(data, row, ot, save)
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
    hp = row.hp,
    item = row.item,
    nickname = row.nickname,
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
  egg.hp = row.hp
  -- ../pokecrystal/mobile/mobile_46.asm:7528 writes EGG into wPartySpecies while the struct
  -- keeps the hatchling's own species.
  egg.isEgg = true
  -- ../pokecrystal/data/events/odd_eggs.asm:53 `db 20 ; Step cycles to hatch`,
  -- the byte MON_HAPPINESS holds while the thing is an egg.
  egg.eggSteps = row.eggSteps
  egg.ot = ot
  egg.otName = ot
  egg.otId = row.otId
  if save then Mon.stampOT(save, egg) end
  return egg
end

-- ../pokecrystal/engine/events/odd_egg.asm:1.  The party-full refusal is the
-- caller's (../pokecrystal/maps/DayCare.asm:31-32), not the routine's.
M.GiveOddEgg = function(vm)
  local oddEggs = eventTable(vm, "oddEggs")
  local record = S.save(vm)
  local data = S.data(vm)
  if not record then return end
  local party = record.party or {}
  record.party = party
  if #party >= Mon.PARTY_SIZE then return end
  local row = oddEggs.rows[oddEggIndex(oddEggs.rows, Specials.random(0x10000) - 1)]
  local egg = buildOddEgg(data, row, oddEggs.ot, record)
  if not egg then return end
  local h = S.hooks(vm)
  local world = h.world
  egg = require("src.core.gen2.Gift").giveEgg(data,
    { game = world and world.game, save = record, world = world, runner = vm }, record, egg)
  -- ../pokecrystal/engine/events/odd_egg.asm:50-57 TossItem on the EGG TICKET,
  -- ahead of the party write.
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
