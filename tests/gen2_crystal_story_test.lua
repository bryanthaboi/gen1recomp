-- The Crystal story specials -- BeastsCheck, GiveDratini, GiveOddEgg and the
-- Ilex Forest shrine pair -- plus the roamer roster difference that makes the
-- Tin Tower Suicune catchable.
-- Self-contained: `luajit tests/gen2_crystal_story_test.lua`; also dofile'd by
-- tests/run_tests.lua.  The cache half SKIPs when no crystal cache is present.
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 crystal story")
local check, eq = S.check, S.eq

love = require("tests.love_stub")

local GameVersion = require("src.core.GameVersion")
local Mon = require("src.battle.gen2.Mon")
local Roamers = require("src.core.gen2.Roamers")
local Save = require("src.core.gen2.Save")
local Specials = require("src.script.gen2.Specials")

local H = Specials.HANDLERS
local priorVersion = GameVersion.get()
local priorRandom = Specials.random

-- ---- fixtures -------------------------------------------------------------

-- pokecrystal/data/pokemon/base_stats/*.asm, the seven Odd Egg species plus
-- the Dragon Shrine's Dratini.
local BASE = {
  PICHU = { 20, 40, 15, 60, 35, 35, "GROWTH_MEDIUM_FAST" },
  CLEFFA = { 50, 25, 28, 15, 45, 55, "GROWTH_FAST" },
  IGGLYBUFF = { 90, 30, 15, 15, 40, 20, "GROWTH_FAST" },
  SMOOCHUM = { 45, 30, 15, 65, 85, 65, "GROWTH_MEDIUM_FAST" },
  MAGBY = { 45, 75, 37, 83, 70, 55, "GROWTH_MEDIUM_FAST" },
  ELEKID = { 45, 63, 37, 95, 65, 55, "GROWTH_MEDIUM_FAST" },
  TYROGUE = { 35, 35, 35, 35, 35, 35, "GROWTH_MEDIUM_FAST" },
  DRATINI = { 41, 64, 45, 50, 50, 50, "GROWTH_SLOW" },
  RAIKOU = { 90, 85, 75, 115, 115, 100, "GROWTH_SLOW" },
  ENTEI = { 115, 115, 85, 100, 90, 75, "GROWTH_SLOW" },
  SUICUNE = { 100, 75, 115, 85, 90, 115, "GROWTH_SLOW" },
}

-- pokecrystal/data/moves/moves.asm, the PP byte of every move these two
-- routines hand out.
local MOVE_PP = {
  THUNDERSHOCK = 30, CHARM = 20, DIZZY_PUNCH = 10, POUND = 35, SING = 15,
  LICK = 30, EMBER = 25, QUICK_ATTACK = 30, LEER = 30, TACKLE = 35,
  WRAP = 20, THUNDER_WAVE = 20, TWISTER = 20, EXTREMESPEED = 5,
}

-- pokecrystal/data/growth_rates.asm MEDIUM_FAST, FAST and SLOW.
local GROWTH = {
  GROWTH_MEDIUM_FAST = { numerator = 1, denominator = 1, squared = 0,
    linear = 0, constant = 0 },
  GROWTH_FAST = { numerator = 4, denominator = 5, squared = 0, linear = 0,
    constant = 0 },
  GROWTH_SLOW = { numerator = 5, denominator = 4, squared = 0, linear = 0,
    constant = 0 },
}

local INDEX = { PICHU = 172, CLEFFA = 173, IGGLYBUFF = 174, SMOOCHUM = 238,
  MAGBY = 240, ELEKID = 239, TYROGUE = 236, DRATINI = 147, RAIKOU = 243,
  ENTEI = 244, SUICUNE = 245 }

local DATA = { pokemon = { growthRates = GROWTH }, moves = {} }
for id, row in pairs(BASE) do
  DATA.pokemon[id] = {
    id = id, index = INDEX[id], name = id,
    baseStats = { hp = row[1], attack = row[2], defense = row[3],
      speed = row[4], specialAttack = row[5], specialDefense = row[6] },
    types = { "NORMAL", "NORMAL" },
    growthRate = row[7],
    genderRatio = 127,
    eggGroups = { "EGG_GROUND", "EGG_GROUND" },
    eggSteps = 20,
    evolutions = {},
    levelMoves = { { level = 1, move = "TACKLE" } },
  }
end
for id, pp in pairs(MOVE_PP) do DATA.moves[id] = { id = id, pp = pp } end

local ITEM_INDEX = { EGG_TICKET = 129, GS_BALL = 115 }

-- The World hook table a handler sees, with only the rows these five need.
local function makeVm(opts)
  opts = opts or {}
  local record = opts.save
  local tossed = {}
  local vars = opts.vars or {}
  local vm = {
    scriptVar = opts.scriptVar or 0,
    battleOutcome = opts.battleOutcome,
    tossed = tossed,
    vars = vars,
    readVarFn = function(id) return vars[id] or 0 end,
    writeVarFn = function(id, value) vars[id] = value end,
    specials = {
      save = function() return record end,
      data = function() return DATA end,
      party = function() return (record and record.party) or {} end,
      monIndex = function(species)
        local def = DATA.pokemon[species]
        return def and def.index or nil
      end,
      monName = function(index)
        for id, def in pairs(DATA.pokemon) do
          if def.index == index then return def.name end
        end
        return nil
      end,
      itemIndex = function(id) return ITEM_INDEX[id] end,
      takeItem = function(index, qty)
        tossed[#tossed + 1] = { index = index, qty = qty }
        return true
      end,
    },
  }
  return vm
end

local function newSave()
  return { version = "crystal", player = { name = "CHRIS", id = 30000 },
    party = {}, boxes = {} }
end

-- ---- BeastsCheck ----------------------------------------------------------
-- pokecrystal/engine/pokemon/search_owned.asm:1

do
  local record = newSave()
  local function beast(species, opts)
    opts = opts or {}
    return { species = species, level = 40,
      ot = opts.ot or "CHRIS", otId = opts.otId or 30000 }
  end

  local vm = makeVm({ save = record })
  H.BeastsCheck(vm)
  eq(vm.scriptVar, 0, "BeastsCheck is FALSE with an empty party")

  record.party = { beast("RAIKOU"), beast("ENTEI") }
  H.BeastsCheck(vm)
  eq(vm.scriptVar, 0, "two of three is still FALSE")

  -- CheckOwnMonAnywhere walks the PC after the party (:80 onward).
  record.boxes = { box1 = { beast("SUICUNE") } }
  H.BeastsCheck(vm)
  eq(vm.scriptVar, 1, "the third one counts from a PC box")

  record.boxes.box1[1].otId = 9999
  H.BeastsCheck(vm)
  eq(vm.scriptVar, 0, "a traded beast fails the trainer-ID check")

  record.boxes.box1[1].otId = 30000
  record.boxes.box1[1].ot = "ETHAN"
  H.BeastsCheck(vm)
  eq(vm.scriptVar, 0, "and a traded beast fails the OT-name check")

  record.boxes.box1[1].ot = "CHRIS"
  H.BeastsCheck(vm)
  eq(vm.scriptVar, 1, "all three owned answers TRUE")
  eq(vm.scriptVar, 1, "and re-running it is stable")
end

-- ---- GiveDratini ----------------------------------------------------------
-- pokecrystal/engine/events/dratini.asm:1

local function dratini(nickname)
  local mon = Mon.new(DATA, "DRATINI", 15, {})
  mon.nickname = nickname
  mon.moves = {
    { id = "WRAP", pp = 20, maxPp = 20 },
    { id = "LEER", pp = 30, maxPp = 30 },
    { id = "THUNDER_WAVE", pp = 20, maxPp = 20 },
    { id = "TWISTER", pp = 20, maxPp = 20 },
  }
  return mon
end

local function moveIds(mon)
  local out = {}
  for _, move in ipairs(mon.moves or {}) do out[#out + 1] = move.id end
  return table.concat(out, ",")
end

do
  local record = newSave()
  record.party = { { species = "CHIKORITA" }, dratini("FIRST"),
    dratini("LAST") }
  local vm = makeVm({ save = record, scriptVar = 0 })
  H.GiveDratini(vm)
  eq(moveIds(record.party[3]), "WRAP,THUNDER_WAVE,TWISTER,EXTREMESPEED",
    "scriptVar 0 gives .Moveset0, Extremespeed and all")
  eq(moveIds(record.party[2]), "WRAP,LEER,THUNDER_WAVE,TWISTER",
    "and only the LAST Dratini in the party is touched")
  eq(record.party[3].moves[4].pp, 5,
    "the new move's PP comes out of the move table")
  eq(record.party[3].moves[4].maxPp, 5, "and so does its max PP")

  local plain = newSave()
  plain.party = { dratini("ONLY") }
  local vm2 = makeVm({ save = plain, scriptVar = 1 })
  H.GiveDratini(vm2)
  eq(moveIds(plain.party[1]), "WRAP,LEER,THUNDER_WAVE,TWISTER",
    "scriptVar 1 gives .Moveset1, the plain level 15 set")

  local untouched = newSave()
  untouched.party = { dratini("ONLY") }
  local vm3 = makeVm({ save = untouched, scriptVar = 2 })
  H.GiveDratini(vm3)
  eq(moveIds(untouched.party[1]), "WRAP,LEER,THUNDER_WAVE,TWISTER",
    "`cp $2 / ret nc` leaves the party alone")

  local none = newSave()
  none.party = { { species = "CHIKORITA", moves = {} } }
  local vm4 = makeVm({ save = none, scriptVar = 0 })
  H.GiveDratini(vm4)
  eq(#none.party[1].moves, 0, "a party with no Dratini is left alone")
end

-- ---- GiveOddEgg -----------------------------------------------------------
-- pokecrystal/engine/events/odd_egg.asm:1

-- pokecrystal/data/events/odd_eggs.asm:14-33 run through the macro at :5:
-- cumulative percent * $ffff / 100.
local ODD_EGG_PROBABILITIES = { 5242, 5898, 16383, 18349, 28835, 30801, 39976,
  41287, 47840, 49151, 57015, 58326, 64879, 65535 }

-- pokecrystal/data/events/odd_eggs.asm:37 OddEggs, row by row.
local ODD_EGG_ROWS = {
  { "PICHU", 2048, { 0, 0, 0, 0 }, { "THUNDERSHOCK", "CHARM", "DIZZY_PUNCH" },
    { 17, 9, 6, 11, 8, 8 } },
  { "PICHU", 256, { 2, 10, 10, 10 }, { "THUNDERSHOCK", "CHARM", "DIZZY_PUNCH" },
    { 17, 9, 7, 12, 9, 9 } },
  { "CLEFFA", 4096, { 0, 0, 0, 0 }, { "POUND", "CHARM", "DIZZY_PUNCH" },
    { 20, 7, 7, 6, 9, 10 } },
  { "CLEFFA", 768, { 2, 10, 10, 10 }, { "POUND", "CHARM", "DIZZY_PUNCH" },
    { 20, 7, 8, 7, 10, 11 } },
  { "IGGLYBUFF", 4096, { 0, 0, 0, 0 }, { "SING", "CHARM", "DIZZY_PUNCH" },
    { 24, 8, 6, 6, 9, 7 } },
  { "IGGLYBUFF", 768, { 2, 10, 10, 10 }, { "SING", "CHARM", "DIZZY_PUNCH" },
    { 24, 8, 7, 7, 10, 8 } },
  { "SMOOCHUM", 3584, { 0, 0, 0, 0 }, { "POUND", "LICK", "DIZZY_PUNCH" },
    { 19, 8, 6, 11, 13, 11 } },
  { "SMOOCHUM", 512, { 2, 10, 10, 10 }, { "POUND", "LICK", "DIZZY_PUNCH" },
    { 19, 8, 7, 12, 14, 12 } },
  { "MAGBY", 2560, { 0, 0, 0, 0 }, { "EMBER", "DIZZY_PUNCH" },
    { 19, 12, 8, 13, 12, 10 } },
  { "MAGBY", 512, { 2, 10, 10, 10 }, { "EMBER", "DIZZY_PUNCH" },
    { 19, 12, 9, 14, 13, 11 } },
  { "ELEKID", 3072, { 0, 0, 0, 0 }, { "QUICK_ATTACK", "LEER", "DIZZY_PUNCH" },
    { 19, 11, 8, 14, 11, 10 } },
  { "ELEKID", 512, { 2, 10, 10, 10 }, { "QUICK_ATTACK", "LEER", "DIZZY_PUNCH" },
    { 19, 11, 9, 15, 12, 11 } },
  { "TYROGUE", 2560, { 0, 0, 0, 0 }, { "TACKLE", "DIZZY_PUNCH" },
    { 18, 8, 8, 8, 8, 8 } },
  { "TYROGUE", 256, { 2, 10, 10, 10 }, { "TACKLE", "DIZZY_PUNCH" },
    { 18, 8, 9, 9, 9, 9 } },
}

-- Specials.random(n) is 1..n, so `roll` is the Random WORD the routine reads.
local function pinRoll(roll)
  Specials.random = function(n)
    if n == 0x10000 then return roll + 1 end
    return priorRandom(n)
  end
end

do
  local wrong = {}
  for index, row in ipairs(ODD_EGG_ROWS) do
    local record = newSave()
    -- The lowest roll that lands in this bucket: one past the previous
    -- cumulative probability.
    local roll = (index == 1) and 0 or (ODD_EGG_PROBABILITIES[index - 1] + 1)
    pinRoll(roll)
    local vm = makeVm({ save = record })
    H.GiveOddEgg(vm)
    local egg = record.party[1]
    local label = "row " .. index .. " (" .. row[1] .. ")"
    if not egg then
      wrong[#wrong + 1] = label .. ": no egg"
    else
      if egg.species ~= row[1] then
        wrong[#wrong + 1] = label .. ": species " .. tostring(egg.species)
      end
      if egg.otId ~= row[2] then
        wrong[#wrong + 1] = label .. ": otId " .. tostring(egg.otId)
      end
      local dvs = egg.dvs or {}
      if dvs.attack ~= row[3][1] or dvs.defense ~= row[3][2]
          or dvs.speed ~= row[3][3] or dvs.special ~= row[3][4] then
        wrong[#wrong + 1] = label .. ": DVs"
      end
      if moveIds(egg) ~= table.concat(row[4], ",") then
        wrong[#wrong + 1] = label .. ": moves " .. moveIds(egg)
      end
      for slot, id in ipairs(row[4]) do
        if egg.moves[slot].pp ~= MOVE_PP[id] then
          wrong[#wrong + 1] = label .. ": pp " .. id
        end
      end
      local stats = egg.stats or {}
      local want = row[5]
      if stats.hp ~= want[1] or stats.attack ~= want[2]
          or stats.defense ~= want[3] or stats.speed ~= want[4]
          or stats.specialAttack ~= want[5]
          or stats.specialDefense ~= want[6] then
        wrong[#wrong + 1] = label .. ": stats"
      end
      -- The struct's stat words are the Gen 2 formula's own output; if these
      -- two ever disagree the transcription above is wrong, not the formula.
      local computed = Mon.stats(DATA.pokemon[row[1]].baseStats, egg.dvs, 5, {})
      if computed.hp ~= want[1] or computed.attack ~= want[2]
          or computed.defense ~= want[3] or computed.speed ~= want[4]
          or computed.specialAttack ~= want[5]
          or computed.specialDefense ~= want[6] then
        wrong[#wrong + 1] = label .. ": Mon.stats disagrees with the table"
      end
    end
  end
  eq(table.concat(wrong, " | "), "",
    "all 14 OddEggs rows come out byte for byte")

  -- The bucket boundary is inclusive: `cp e / jr z, .done`.
  pinRoll(ODD_EGG_PROBABILITIES[1])
  local edge = newSave()
  H.GiveOddEgg(makeVm({ save = edge }))
  eq(edge.party[1].otId, 2048, "a roll EQUAL to the probability stays in row 1")
  pinRoll(ODD_EGG_PROBABILITIES[1] + 1)
  local over = newSave()
  H.GiveOddEgg(makeVm({ save = over }))
  eq(over.party[1].otId, 256, "and one past it falls into row 2")

  -- The last entry is $ffff, which is the loop's own break: every roll above
  -- the 99% mark lands there.
  pinRoll(0xffff)
  local last = newSave()
  H.GiveOddEgg(makeVm({ save = last }))
  eq(last.party[1].species, "TYROGUE", "the $ffff row takes the top of the range")
  eq(last.party[1].otId, 256, "and it is the shiny Tyrogue")
end

do
  pinRoll(0)
  local record = newSave()
  local vm = makeVm({ save = record })
  H.GiveOddEgg(vm)
  local egg = record.party[1]
  eq(egg.isEgg, true, "the Odd Egg arrives as an EGG")
  eq(egg.nickname, "EGG", "wOddEggName is its nickname")
  eq(egg.ot, "ODD", "and wTempOddEggNickname is its OT name")
  eq(egg.otName, "ODD", "on both OT fields")
  eq(egg.otId, 2048, "the OT ID is the struct's, not the player's")
  eq(egg.eggSteps, 20, "20 step cycles to hatch")
  eq(egg.hp, 0, "an egg is carried at zero HP")
  eq(egg.level, 5, "at level 5")
  eq(egg.experience, 125,
    "and with the struct's 125 exp, not the curve's own value")
  eq(#vm.tossed, 1, "the EGG TICKET is tossed")
  eq(vm.tossed[1].index, 129, "by its item index")
  eq(vm.tossed[1].qty, 1, "one of them")

  -- CLEFFA is GROWTH_FAST, so 125 is more than level 5 costs: the copied
  -- struct really does overshoot the curve.
  pinRoll(ODD_EGG_PROBABILITIES[2] + 1)
  local cleffa = newSave()
  H.GiveOddEgg(makeVm({ save = cleffa }))
  eq(cleffa.party[1].species, "CLEFFA", "the Cleffa bucket")
  eq(cleffa.party[1].experience, 125, "carries 125 exp too")
  eq(Mon.experienceForLevel(GROWTH.GROWTH_FAST, 5), 100,
    "even though its own curve wants 100")

  -- The second row of every pair is the classic shiny DV set.
  pinRoll(ODD_EGG_PROBABILITIES[1] + 1)
  local shiny = newSave()
  H.GiveOddEgg(makeVm({ save = shiny }))
  eq(shiny.party[1].shiny, true, "the 2/10/10/10 rows are shiny")

  -- pokecrystal/maps/DayCare.asm:31-32 is the party-full guard, so a full
  -- party must not grow a seventh slot here.
  local full = newSave()
  for i = 1, 6 do full.party[i] = { species = "CHIKORITA" } end
  local vmFull = makeVm({ save = full })
  H.GiveOddEgg(vmFull)
  eq(#full.party, 6, "a full party gets no Odd Egg")
  eq(#vmFull.tossed, 0, "and keeps its EGG TICKET")
end

Specials.random = priorRandom

-- ---- the Ilex Forest shrine -----------------------------------------------
-- pokecrystal/engine/events/celebi.asm:9 and :301

do
  local record = newSave()
  local vm = makeVm({ save = record })
  H.CelebiShrineEvent(vm)
  eq(vm.vars[0x03], 11,
    "CelebiShrineEvent leaves BATTLETYPE_CELEBI in VAR_BATTLETYPE")
  eq(vm.celebiArmed, true, "and arms the result bit for the battle to come")

  vm.battleOutcome = "caught"
  H.CheckCaughtCelebi(vm)
  eq(vm.scriptVar, 1, "catching it in that battle answers TRUE")
  eq(Save.crystalState(record).celebiCaught, true, "and is recorded")
  eq(vm.celebiArmed, nil, "the arming is one battle long")

  local ran = newSave()
  local vm2 = makeVm({ save = ran, battleOutcome = "run" })
  H.CelebiShrineEvent(vm2)
  H.CheckCaughtCelebi(vm2)
  eq(vm2.scriptVar, 0, "running from it answers FALSE")
  eq(Save.crystalState(ran).celebiCaught, false, "and records nothing")

  local won = newSave()
  local vm3 = makeVm({ save = won, battleOutcome = "win" })
  H.CelebiShrineEvent(vm3)
  H.CheckCaughtCelebi(vm3)
  eq(vm3.scriptVar, 0, "and knocking it out answers FALSE")

  -- pokecrystal/engine/items/item_effects.asm:542 gates the bit on the battle
  -- type, so an ordinary catch never sets it.
  local other = newSave()
  local vm4 = makeVm({ save = other, battleOutcome = "caught" })
  H.CheckCaughtCelebi(vm4)
  eq(vm4.scriptVar, 0, "a catch in a NORMAL battle does not count")
  eq(Save.crystalState(other).celebiCaught, false, "and records nothing")
end

-- ---- the beasts that roam -------------------------------------------------
-- pokegold/data/wild/flee_mons.asm:34 against pokecrystal's:34

do
  GameVersion.set("gold")
  eq(Roamers.ALWAYS_FLEE.RAIKOU, true, "Gold: Raikou always flees")
  eq(Roamers.ALWAYS_FLEE.ENTEI, true, "Gold: Entei always flees")
  eq(Roamers.ALWAYS_FLEE.SUICUNE, true, "Gold: Suicune always flees")

  GameVersion.set("silver")
  eq(Roamers.ALWAYS_FLEE.SUICUNE, true, "Silver rides the same list")

  GameVersion.set("crystal")
  eq(Roamers.ALWAYS_FLEE.RAIKOU, true, "Crystal keeps Raikou on the list")
  eq(Roamers.ALWAYS_FLEE.ENTEI, true, "and Entei")
  eq(Roamers.ALWAYS_FLEE.SUICUNE, nil,
    "but drops Suicune, so the Tin Tower battle can be fought")
  eq(Roamers.ALWAYS_FLEE.PIDGEY, nil, "a mon on no list still never flees")

  eq(Roamers.alwaysFleeMons("gold").SUICUNE, true,
    "the accessor answers per version id")
  eq(Roamers.alwaysFleeMons("crystal").SUICUNE, nil, "independently of the boot")
  GameVersion.set(priorVersion)
end

-- Crystal seeds two roam structs, so the third slot the encounter roll can
-- pick is always empty -- pokecrystal/engine/overworld/wildmons.asm:493.
do
  local twoRow = { roamMons = {
    { species = "RAIKOU", level = 40, map = "ROUTE_42" },
    { species = "ENTEI", level = 40, map = "ROUTE_37" },
  } }
  local record = { version = "crystal" }
  Roamers.init(record, { encounters = twoRow })
  eq(#record.roamers, 2, "a Crystal cache seeds two roamers")
  eq(record.roamers[1].species, "RAIKOU", "Raikou in slot 1")
  eq(record.roamers[2].species, "ENTEI", "Entei in slot 2")
  eq(record.roamers[3], nil, "and nothing in Suicune's old slot")

  -- CheckEncounterRoamMon's `and %11 / jr z / dec a` picks slot 1, 2 or 3.
  local hits = { 0, 0, 0 }
  for value = 0, 99 do
    local hit = Roamers.checkEncounter(record, "ROUTE_42", false,
      function() return value end)
    if hit then hits[hit.index] = hits[hit.index] + 1 end
  end
  check(hits[1] > 0, "slot 1 is still reachable on its own route")
  eq(hits[3], 0, "slot 3 never produces an encounter on Crystal")
end

-- ------------------------------------------------------------ cache-gated

local cache = os.getenv("CRYSTAL_CACHE")
if not cache then
  local home = os.getenv("HOME") or ""
  for _, dir in ipairs({ "crystal-dev", "lead-card" }) do
    local candidate = home .. "/Library/Application Support/LOVE/" .. dir
      .. "/crystal"
    local probe = io.open(candidate .. "/data/generated/constants.lua", "r")
    if probe then
      probe:close()
      cache = candidate
      break
    end
  end
end

local constantsFile = cache and io.open(cache .. "/data/generated/constants.lua",
  "r")
if not constantsFile then
  check(true, "crystal cache absent : SKIP")
  S.finish()
  return
end
constantsFile:close()

local function loadLua(rel)
  local chunk = loadfile(cache .. "/" .. rel)
  if not chunk then return nil end
  local ok, value = pcall(chunk)
  return ok and value or nil
end

local constants = loadLua("data/generated/constants.lua")
local scripts = loadLua("data/generated/scripts.lua")
local encounters = loadLua("data/generated/encounters.lua")
check(constants ~= nil and scripts ~= nil, "the crystal cache loads")

-- Every handler above has to be a name the cache's own SpecialsPointers row
-- resolves to, and one an extracted script really calls.
local order = constants.specialOrder or {}
local calls = {}
for _, list in pairs(scripts) do
  if type(list) == "table" then
    for _, row in ipairs(list) do
      if type(row) == "table" and row.op == "special" then
        local name = order[(row.id or 0) + 1]
        if name then calls[name] = (calls[name] or 0) + 1 end
      end
    end
  end
end

for _, name in ipairs({ "BeastsCheck", "GiveDratini", "GiveOddEgg",
    "CelebiShrineEvent", "CheckCaughtCelebi" }) do
  check(Specials.HANDLERS[name] ~= nil, name .. " is a handler, not a stub")
  check((calls[name] or 0) > 0,
    name .. " is called by an extracted Crystal script")
end

-- pokecrystal/mobile/mobile_46.asm:6793: TradeCornerHoldMon lives in the
-- Mobile System GB bank and no map script reaches it.
eq(calls.TradeCornerHoldMon, nil,
  "TradeCornerHoldMon is never called from a script")
check(Specials.STUBS.TradeCornerHoldMon ~= nil,
  "so it stays a documented stub")

eq(#(encounters and encounters.roamMons or {}), 2,
  "the Crystal cache carries two roamMons rows")
local roamNames = {}
for _, row in ipairs((encounters and encounters.roamMons) or {}) do
  roamNames[#roamNames + 1] = row.species
end
eq(table.concat(roamNames, ","), "RAIKOU,ENTEI",
  "Raikou and Entei, with Suicune off the roam list")

S.finish()
