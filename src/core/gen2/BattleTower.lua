-- ../pokecrystal/engine/events/battle_tower/battle_tower.asm:1 and
-- ../pokecrystal/engine/events/battle_tower/rules.asm:27.

local Breeding = require("src.core.gen2.Breeding")
local HallOfFame = require("src.core.gen2.HallOfFame")
local Mon = require("src.battle.gen2.Mon")
local Save = require("src.core.gen2.Save")

local BattleTower = {}

-- ../pokecrystal/constants/battle_tower_constants.asm:1-7
BattleTower.PARTY_LENGTH = 3
BattleTower.STREAK_LENGTH = 7
BattleTower.NUM_UNIQUE_MON = 21
BattleTower.NUM_UNIQUE_TRAINERS = 70
BattleTower.TRAINERDATALENGTH = 36

-- ../pokecrystal/constants/battle_tower_constants.asm:47 GS_BALL_AVAILABLE
BattleTower.GS_BALL_AVAILABLE = 0x0b

-- ../pokecrystal/constants/battle_tower_constants.asm:55-61
BattleTower.NO_CHALLENGE = 0
BattleTower.SAVED_AND_LEFT = 1
BattleTower.CHALLENGE_IN_PROGRESS = 2
BattleTower.WON_CHALLENGE = 3
BattleTower.RECEIVED_REWARD = 4

-- ../pokecrystal/constants/battle_tower_constants.asm:63-67
BattleTower.REWARD_QUANTITY = 5
BattleTower.MIN_REWARD = "HP_UP"
BattleTower.MAX_REWARD = "CALCIUM"
BattleTower.SKIPPED_REWARD = "LUCKY_PUNCH"
BattleTower.FALLBACK_REWARD = "POTION"

-- ../pokecrystal/engine/events/battle_tower/battle_tower.asm:1471-1492 bit 0,
-- :978-1008 bit 1 of sBattleTowerSaveFileFlags.
BattleTower.SAVEFILE_REGISTERED = 1
BattleTower.SAVEFILE_EXPLANATION = 2

-- ../pokecrystal/constants/battle_tower_constants.asm:11-43
BattleTower.ACTIONS = {
  CHECK_EXPLANATION_READ = 0,
  SET_EXPLANATION_READ = 1,
  GET_CHALLENGE_STATE = 2,
  SAVE_AND_QUIT = 3,
  CHALLENGECANCELED = 4,
  ACTION_05 = 5,
  ACTION_06 = 6,
  SAVELEVELGROUP = 7,
  LOADLEVELGROUP = 8,
  CHECKSAVEFILEISYOURS = 9,
  ACTION_0A = 10,
  GSBALL = 11,
  ACTION_0C = 12,
  ACTION_0D = 13,
  EGGTICKET = 14,
  ACTION_0F = 15,
  ACTION_10 = 16,
  ACTION_11 = 17,
  ACTION_12 = 18,
  ACTION_13 = 19,
  ACTION_14 = 20,
  ACTION_15 = 21,
  ACTION_16 = 22,
  ACTION_17 = 23,
  LEVEL_CHECK = 24,
  UBERS_CHECK = 25,
  RESETDATA = 26,
  GIVEREWARD = 27,
  ACTION_1C = 28,
  ACTION_1D = 29,
  CHOOSEREWARD = 30,
  SAVEOPTIONS = 31,
}
BattleTower.NUM_ACTIONS = 32

-- ../pokecrystal/ram/wram.asm:1703 wNrOfBeatenBattleTowerTrainers, which
-- ../pokecrystal/maps/BattleTowerBattleRoom.asm:38 reads back with `readmem`.
BattleTower.WRAM_NR_BEATEN = 0xcf64

-- ../pokecrystal/constants/battle_tower_constants.asm:49-53 `battletowertext`.
BattleTower.TEXT_INTRO = 1
BattleTower.TEXT_WIN = 2
BattleTower.TEXT_LOSS = 3

-- ../pokecrystal/engine/events/battle_tower/rules.asm:39-55, in the order
-- BattleTower_ExecuteJumptable prints them.
BattleTower.RULE_HEADER_TEXT = "_ExcuseMeYoureNotReadyText"
BattleTower.RULE_FAIL_TEXTS = {
  "_OnlyThreeMonMayBeEnteredText",
  "_TheMonMustAllBeDifferentKindsText",
  "_TheMonMustNotHoldTheSameItemsText",
  "_YouCantTakeAnEggText",
}
-- ../pokecrystal/engine/events/battle_tower/rules.asm:61-68
BattleTower.RULE_TAIL_TEXT = "_BattleTowerReturnWhenReadyText"
-- ../pokecrystal/engine/events/battle_tower/rules.asm:28-31 wStringBuffer2.
BattleTower.RULE_PARTY_COUNT_TEXT = "3"

-- ../pokecrystal/mobile/mobile_46.asm:3936-3958 BattleTower_UbersCheck.
BattleTower.UBERS = {
  MEWTWO = true, MEW = true, LUGIA = true, HO_OH = true, CELEBI = true,
}
BattleTower.UBER_MIN_LEVEL = 70

-- ../pokecrystal/mobile/mobile_46.asm:3869-3887 Strings_L10ToL100 and
-- Strings_Ll0ToL40.
BattleTower.MAX_LEVEL_GROUP = 10
BattleTower.PRE_HOF_LEVEL_GROUPS = 4

local function counter(value)
  return math.max(0, math.floor(tonumber(value) or 0))
end

-- ../pokecrystal/ram/sram.asm:147-172, on top of Save.battleTowerState.
function BattleTower.state(save)
  local tower = Save.battleTowerState(save)
  -- ../pokecrystal/ram/sram.asm:156 sBTChoiceOfLevelGroup
  tower.levelGroup = counter(tower.levelGroup)
  -- ../pokecrystal/ram/sram.asm:159 sBattleTowerSaveFileFlags
  tower.saveFileFlags = counter(tower.saveFileFlags) % 256
  -- ../pokecrystal/ram/sram.asm:158 sBTTrainers, $ff for an unused slot
  if type(tower.trainers) ~= "table" then tower.trainers = {} end
  -- ../pokecrystal/engine/events/battle_tower/battle_tower.asm:1449-1469 s5_aa8d
  if tower.reentry == nil then tower.reentry = false end
  return tower
end

-- ../pokecrystal/engine/events/battle_tower/battle_tower.asm:1471-1483 and
-- :984-989: `and 1` / `and 2`, so the answer is the MASKED byte, not a boolean.
function BattleTower.saveFileFlag(save, mask)
  local tower = BattleTower.state(save)
  return (math.floor(tower.saveFileFlags / mask) % 2 == 1) and mask or 0
end

function BattleTower.setSaveFileFlag(save, mask)
  local tower = BattleTower.state(save)
  if math.floor(tower.saveFileFlags / mask) % 2 == 0 then
    tower.saveFileFlags = tower.saveFileFlags + mask
  end
  return tower.saveFileFlags
end

-- ../pokecrystal/engine/events/battle_tower/battle_tower.asm:890-904
function BattleTower.resetTrainers(save)
  local tower = BattleTower.state(save)
  tower.trainers = {}
  tower.streak = 0
  return tower
end

-- ../pokecrystal/engine/events/battle_tower/battle_tower.asm:1016-1022
function BattleTower.setChallengeState(save, state)
  local tower = BattleTower.state(save)
  tower.challenge = counter(state)
  return tower.challenge
end

-- ../pokecrystal/engine/events/battle_tower/rules.asm:206-211
function BattleTower.partyCountOk(party)
  return #party == BattleTower.PARTY_LENGTH
end

-- ../pokecrystal/engine/events/battle_tower/rules.asm:218-277
-- CheckPartyValueIsUnique: eggs are skipped on both sides and a zero value
-- never collides, because `ld a, [hl] / and a / jr z, .next` drops it first.
local function valuesUnique(party, get)
  local count = #party
  for i = 1, count - 1 do
    local mon = party[i]
    if not Breeding.isEgg(mon) then
      local value = get(mon)
      if value ~= nil and value ~= 0 then
        for j = i + 1, count do
          local other = party[j]
          if not Breeding.isEgg(other) and get(other) == value then
            return false
          end
        end
      end
    end
  end
  return true
end

local function speciesOf(mon) return mon and mon.species or nil end
local function itemOf(mon) return mon and mon.item or nil end

-- ../pokecrystal/engine/events/battle_tower/rules.asm:213-216
function BattleTower.speciesUnique(party)
  return valuesUnique(party, speciesOf)
end

-- ../pokecrystal/engine/events/battle_tower/rules.asm:279-282
function BattleTower.itemsUnique(party)
  return valuesUnique(party, itemOf)
end

-- ../pokecrystal/engine/events/battle_tower/rules.asm:284-299
function BattleTower.partyHasEgg(party)
  for _, mon in ipairs(party) do
    if Breeding.isEgg(mon) then return true end
  end
  return false
end

-- ../pokecrystal/engine/events/battle_tower/rules.asm:27-37 and :94-103: every
-- check runs, the first failure prints the header first, and a tail line
-- follows any failure at all.  Returns the text labels in printing order.
function BattleTower.checkRules(party)
  party = party or {}
  local failed = {
    not BattleTower.partyCountOk(party),
    not BattleTower.speciesUnique(party),
    not BattleTower.itemsUnique(party),
    BattleTower.partyHasEgg(party),
  }
  local lines, any = {}, false
  for index = 1, #BattleTower.RULE_FAIL_TEXTS do
    if failed[index] then
      if not any then
        any = true
        lines[#lines + 1] = BattleTower.RULE_HEADER_TEXT
      end
      lines[#lines + 1] = BattleTower.RULE_FAIL_TEXTS[index]
    end
  end
  if any then lines[#lines + 1] = BattleTower.RULE_TAIL_TEXT end
  return lines, any
end

-- ../pokecrystal/mobile/mobile_46.asm:1156-1166: the Hall of Fame flag is what
-- opens rooms above L40, and the last row is always CANCEL.
function BattleTower.levelGroupCount(save)
  if HallOfFame.hasEntered(save) then return BattleTower.MAX_LEVEL_GROUP end
  return BattleTower.PRE_HOF_LEVEL_GROUPS
end

function BattleTower.levelGroupRows(save)
  local rows = {}
  for group = 1, BattleTower.levelGroupCount(save) do
    rows[group] = { group = group, level = group * 10 }
  end
  return rows
end

-- ../pokecrystal/mobile/mobile_46.asm:1264-1267 `dec a / and $fe / srl a`, the
-- BATTLE ROOM pair the hallway walks to (../pokecrystal/maps/BattleTowerHallway.asm:40-47).
function BattleTower.roomOf(group)
  return math.floor((math.max(1, counter(group)) - 1) / 2)
end

-- ../pokecrystal/mobile/mobile_46.asm:3892-3934 BattleTower_LevelCheck
function BattleTower.levelCheck(party, group)
  local cap = counter(group) * 10
  for _, mon in ipairs(party or {}) do
    if (tonumber(mon.level) or 0) > cap then return true end
  end
  return false
end

-- ../pokecrystal/mobile/mobile_46.asm:3936-3989 BattleTower_UbersCheck: below
-- the L70 rooms an uber under L70 is refused, and its name goes in wcd49.
function BattleTower.ubersCheck(party, group)
  if counter(group) >= BattleTower.UBER_MIN_LEVEL / 10 then return nil end
  for _, mon in ipairs(party or {}) do
    if BattleTower.UBERS[mon.species]
        and (tonumber(mon.level) or 0) < BattleTower.UBER_MIN_LEVEL then
      return mon.species
    end
  end
  return nil
end

-- ../pokecrystal/engine/events/battle_tower/battle_tower.asm:955-976: a
-- `maskbits` roll over HP_UP..CALCIUM that folds the overshoot back to the
-- bottom of the range and rerolls LUCKY_PUNCH.
function BattleTower.rollReward(order, random)
  if type(order) ~= "table" then return nil end
  local low, high
  for index, name in pairs(order) do
    if name == BattleTower.MIN_REWARD then low = index end
    if name == BattleTower.MAX_REWARD then high = index end
  end
  if not (low and high) then return nil end
  local span = high - low + 1
  local mask = 1
  while mask < span do mask = mask * 2 end
  for _ = 1, 64 do
    local roll = random(mask) % mask
    if roll >= span then roll = roll - span end
    local item = order[low + roll]
    if item ~= BattleTower.SKIPPED_REWARD then return item end
  end
  return order[low]
end

-- ../pokecrystal/engine/events/battle_tower/battle_tower.asm:906-933: five of
-- the reward only fit when the ITEM pocket has a free slot, or already holds
-- the reward with room for five more.  Otherwise the desk hands over a POTION,
-- which the script reads as "your PACK is stuffed full".
function BattleTower.rewardFits(slots, capacity, held)
  if counter(slots) < counter(capacity) then return true end
  if held == nil then return false end
  return counter(held) < 99 - BattleTower.REWARD_QUANTITY + 1
end

-- The opponent draw, all of it ../pokecrystal/engine/events/battle_tower/
-- load_trainer.asm, over RomExtractorGen2's Crystal-only `battleTower` block.

-- data/generated/trainers.lua `battleTower`, absent on Gold and Silver.
function BattleTower.roster(data)
  local trainers = data and (data.gen2Trainers or data.trainers)
  local roster = trainers and trainers.battleTower
  if type(roster) ~= "table" then return nil end
  if type(roster.trainers) ~= "table" or type(roster.groups) ~= "table" then
    return nil
  end
  return roster
end

-- ../pokecrystal/ram/sram.asm:162-173 sBTMonOfTrainers: the last team's three
-- species and the one before that's, which the draw refuses to repeat.
function BattleTower.prevTeams(save)
  local tower = BattleTower.state(save)
  local teams = tower.prevTeams
  if type(teams) ~= "table" then
    teams = {}
    tower.prevTeams = teams
  end
  if type(teams.prev) ~= "table" then teams.prev = {} end
  if type(teams.prevPrev) ~= "table" then teams.prevPrev = {} end
  return teams
end

-- ../pokecrystal/engine/events/battle_tower/load_trainer.asm:104-105 reads the
-- room back as `ld a, [wBTChoiceOfLvlGroup] / dec a`, so group 0 indexes
-- BEFORE the table; battle_tower.asm:1129-1141 is what can only save 1..10.
function BattleTower.opponentGroup(save, roster)
  local groups = (roster and roster.levelGroups) or BattleTower.MAX_LEVEL_GROUP
  local group = counter(BattleTower.state(save).levelGroup)
  if group < 1 then return 1 end
  if group > groups then return groups end
  return group
end

-- load_trainer.asm:24-38 and :101-166 reroll until the roll passes; one draw
-- from the survivors is the same distribution and cannot spin.  An empty
-- survivor set is where the cart's own loop would hang, so it draws unfiltered.
local function drawFiltered(count, random, accept)
  local pool = {}
  for index = 1, count do
    if accept(index) then pool[#pool + 1] = index end
  end
  if #pool == 0 then return random(count) end
  return pool[random(#pool)]
end

-- ../pokecrystal/engine/events/battle_tower/load_trainer.asm:22-60.  The roll
-- is refused while it names anybody already in sBTTrainers, and the winner is
-- written into the slot sNrOfBeatenBattleTowerTrainers points at.
function BattleTower.chooseTrainer(save, roster, random)
  local tower = BattleTower.state(save)
  -- :29-37, the ceiling read out of the cart: Crystal 1.0 masks with
  -- BATTLETOWER_NUM_UNIQUE_MON and can only ever draw the first 21 rows.
  local ceiling = counter(roster.sampleTrainers)
  if ceiling < 1 or ceiling > #roster.trainers then ceiling = #roster.trainers end
  local seen = {}
  for slot = 1, BattleTower.STREAK_LENGTH do
    local held = tonumber(tower.trainers[slot])
    if held then seen[held] = true end
  end
  local index = drawFiltered(ceiling, random, function(row)
    return not seen[row - 1]
  end)
  tower.trainers[math.min(counter(tower.streak), BattleTower.STREAK_LENGTH - 1)
    + 1] = index - 1
  return roster.trainers[index]
end

-- ../pokecrystal/engine/events/battle_tower/load_trainer.asm:94-208.  Three
-- draws out of the chosen level group, each refusing a species this team
-- already holds, an ITEM this team already holds, and any species from the
-- last two teams.  wBT_OTTrainer was zero-filled and its three item slots set
-- to $ff first (:7-17), which is why an unfilled slot collides with nothing.
function BattleTower.chooseTeam(save, roster, group, random)
  local rows = roster.groups[group] or {}
  local teams = BattleTower.prevTeams(save)
  local picked, species, items = {}, {}, {}
  for _ = 1, BattleTower.PARTY_LENGTH do
    local index = drawFiltered(#rows, random, function(row)
      local mon = rows[row]
      if not mon then return false end
      if species[mon.species] then return false end
      if mon.item ~= nil and items[mon.item] then return false end
      for _, seen in ipairs(teams.prev) do
        if seen == mon.species then return false end
      end
      for _, seen in ipairs(teams.prevPrev) do
        if seen == mon.species then return false end
      end
      return true
    end)
    local mon = rows[index]
    if not mon then break end
    picked[#picked + 1] = mon
    species[mon.species] = true
    if mon.item ~= nil then items[mon.item] = true end
  end
  -- :195-206, after all three: this team becomes sBTMonPrevTrainer and the
  -- one it displaces becomes sBTMonPrevPrevTrainer.
  local prev = {}
  for slot, mon in ipairs(picked) do prev[slot] = mon.species end
  teams.prevPrev = teams.prev
  teams.prev = prev
  return picked
end

-- The whole of `special LoadOpponentTrainerAndPokemon`, as one record.  The
-- cart keeps it in wBT_OTTrainer, which is WRAM bank 3 and is NOT saved --
-- only the sBTTrainers slot and the two previous teams this walk writes are.
function BattleTower.drawOpponent(data, save, random)
  local roster = BattleTower.roster(data)
  if not roster then return nil end
  local group = BattleTower.opponentGroup(save, roster)
  local trainer = BattleTower.chooseTrainer(save, roster, random)
  if not trainer then return nil end
  local rows = BattleTower.chooseTeam(save, roster, group, random)
  return {
    index = trainer.index,
    name = trainer.name,
    class = trainer.class,
    classId = trainer.classId,
    sprite = roster.classSprites and roster.classSprites[trainer.classId],
    group = group,
    rows = rows,
  }
end

-- ../pokecrystal/engine/events/battle_tower/battle_tower.asm:549-570
-- CopyBTTrainer_FromBT_OT_TowBT_OTTemp, which is the first thing
-- ReadBTTrainerParty does: the challenge is now in progress and the streak
-- counter steps BEFORE the battle, which is why beating the seventh opponent
-- leaves the counter on BATTLETOWER_STREAK_LENGTH.
function BattleTower.beginBattle(save)
  local tower = BattleTower.state(save)
  tower.challenge = BattleTower.CHALLENGE_IN_PROGRESS
  tower.streak = counter(tower.streak) + 1
  return tower.streak
end

-- ReadBTTrainerParty's .otpartymon_loop (battle_tower.asm:349-376) copies the
-- whole party_struct into wOTPartyMon, so nothing here is rolled: the stored
-- stats go on top of Mon.new's, which agree with them anyway.
-- The ROM nicknames never show: load_trainer.asm:171-190 overwrites each one
-- with GetPokemonName, so the rows carry none.
function BattleTower.battleParty(data, rows)
  local party = {}
  for _, row in ipairs(rows or {}) do
    local moves = nil
    if row.moves and #row.moves > 0 then
      moves = {}
      for slot, id in ipairs(row.moves) do
        local def = data and data.moves and data.moves[id]
        local max = (def and def.pp) or 0
        moves[slot] = {
          id = id,
          pp = (row.pp and row.pp[slot]) or max,
          maxPp = max,
        }
      end
    end
    local dvs = row.dvs or {}
    local statExp = row.statExp or {}
    local mon = Mon.new(data, row.species, row.level, {
      moves = moves,
      item = row.item,
      dvs = { attack = dvs.attack, defense = dvs.defense,
        speed = dvs.speed, special = dvs.special },
      statExp = { hp = statExp.hp, attack = statExp.attack,
        defense = statExp.defense, speed = statExp.speed,
        special = statExp.special },
      happiness = row.happiness,
    })
    if mon then
      if row.stats then
        mon.stats = {
          hp = row.stats.hp, attack = row.stats.attack,
          defense = row.stats.defense, speed = row.stats.speed,
          specialAttack = row.stats.specialAttack,
          specialDefense = row.stats.specialDefense,
        }
      end
      mon.maxHp = row.maxHp or mon.maxHp
      mon.hp = row.hp or mon.maxHp
      mon.experience = row.experience or mon.experience
      party[#party + 1] = mon
    end
  end
  return party
end

return BattleTower
