-- Gen 3 catch mechanics (pret pokeball.c / battle_script_commands.c).
--
-- Pure functions for catch calculations, ball multipliers, shake factor math,
-- and caught Pokémon persistence into party or PC storage.
--
-- Emits battle.ball_thrown and pokemon.caught; the roll is hooked as catch.rate.

local ItemsData = require("src.core.game3.items_data")
local Pokemon = require("src.core.game3.pokemon")
local Types = require("src.core.game3.battle.types")
local Dex = require("src.core.game3.dex")
local ModRuntime = require("src.mods.Runtime")

local Catching = {}

-- Ball catch bonuses (bonus × 10):
-- Master = 255 (instant catch), Ultra = 20, Great/Safari = 15, Poke/Premier/Luxury = 10
Catching.BALL_BONUS = {
  [1] = 255, -- MASTER_BALL
  [2] = 20,  -- ULTRA_BALL
  [3] = 15,  -- GREAT_BALL
  [4] = 10,  -- POKE_BALL
  [5] = 15,  -- SAFARI_BALL
  [6] = 10,  -- NET_BALL (default; conditional boost 30)
  [7] = 10,  -- DIVE_BALL (default; conditional boost 35)
  [8] = 10,  -- NEST_BALL (conditional boost based on level)
  [9] = 10,  -- REPEAT_BALL (conditional boost 30 if owned)
  [10] = 10, -- TIMER_BALL (conditional boost based on turns)
  [11] = 10, -- LUXURY_BALL
  [12] = 10, -- PREMIER_BALL
}

local function roll_rng(rng, lo, hi)
  lo = lo or 0
  hi = hi or 255
  if type(rng) == "function" then
    local ok, v = pcall(rng, lo, hi)
    if ok and type(v) == "number" then return v end
  elseif type(rng) == "table" and type(rng.random) == "function" then
    local ok, v = pcall(rng.random, rng, lo, hi)
    if ok and type(v) == "number" then return v end
  end
  local okR, Rng = pcall(require, "src.core.game3.rng")
  if okR and Rng and Rng.compat then
    return Rng.compat(lo, hi)
  end
  return math.random(lo, hi)
end

-- pokefirered/src/battle_script_commands.c:9471
function Catching.targetFor(st, attackerId)
  local id = (tonumber(attackerId) or 0)
  local t = (id % 2 == 0) and (id + 1) or (id - 1)
  if t == 1 or not st then return st and st.enemy end
  return st.battlers and st.battlers[t] or st.enemy
end

function Catching.isBall(id)
  local num = ItemsData.toNumericId(id) or tonumber(id)
  return num and num >= 1 and num <= 12
end

--- Evaluate effective ball multiplier (bonus × 10) for a given foe and battle state.
function Catching.ballMultiplier(itemId, foeBattler, st, session)
  local num = ItemsData.toNumericId(itemId) or tonumber(itemId) or 4
  if num == 1 then return 255 end
  local mult = Catching.BALL_BONUS[num] or 10
  local mon = foeBattler and foeBattler.mon
  local level = tonumber(mon and mon.level) or 50

  if num == 6 then -- NET BALL: 3x if Water or Bug
    local t1 = foeBattler and foeBattler.type1
    local t2 = foeBattler and foeBattler.type2
    local WATER = Types.ID and Types.ID.WATER or 11
    local BUG = Types.ID and Types.ID.BUG or 7
    if t1 == WATER or t2 == WATER or t1 == BUG or t2 == BUG then
      mult = 30
    end
  elseif num == 7 then -- DIVE BALL: 3.5x in water/surf
    local terrain = st and st.terrain
    if terrain == "water" or terrain == "surf" or terrain == "underwater" then
      mult = 35
    end
  elseif num == 8 then -- NEST BALL: (40 - level) / 10 for level < 40, clamped to min 1.0 (10)
    if level < 40 then
      mult = math.max(10, (40 - level))
    end
  elseif num == 9 then -- REPEAT BALL: 3x if already caught in Pokédex
    local species = foeBattler and (foeBattler.species or (foeBattler.mon and foeBattler.mon.species))
    local dex = (session and session.dex)
    if not dex then
      local okR, Runtime = pcall(require, "src.core.game3.runtime")
      if okR and Runtime and Runtime.getSession then
        local s = Runtime.getSession()
        dex = s and s.dex
      end
    end
    if species and dex and Dex.isCaught(dex, species) then
      mult = 30
    end
  elseif num == 10 then -- TIMER BALL: min(40, 10 + turns)
    local turns = (st and (st.turn or st.turnCount)) or 1
    mult = math.min(40, 10 + turns)
  end

  return mult
end

--- Calculate catch odds 'a' (0..255).
-- Formula: a = floor(((3 * maxHP - 2 * HP) * catchRate * ballBonus) / (3 * maxHP)) * statusBonus
function Catching.catchOdds(itemId, foeBattler, st, session)
  local num = ItemsData.toNumericId(itemId) or tonumber(itemId) or 4
  if num == 1 then return 255 end

  local species = foeBattler and (foeBattler.species or (foeBattler.mon and foeBattler.mon.species))
  local meta = species and Pokemon.speciesMeta(species)
  local catchRate = (meta and tonumber(meta.catchRate)) or 45

  local mon = foeBattler and foeBattler.mon
  local hp = math.max(1, tonumber(mon and mon.hp) or 1)
  local maxHp = math.max(1, tonumber(mon and mon.maxHp) or hp)

  local mult = Catching.ballMultiplier(itemId, foeBattler, st, session)
  local baseOdds = math.floor(((maxHp * 3 - hp * 2) * catchRate * mult / 10) / (3 * maxHp))
  baseOdds = math.max(1, baseOdds)

  local status = foeBattler and (foeBattler.status or (mon and mon.status))
  local odds = baseOdds
  if status then
    local s = tostring(status):upper()
    if s == "SLP" or s == "SLEEP" or s == "FRZ" or s == "FREEZE" then
      odds = math.floor(baseOdds * 2)
    elseif s == "PSN" or s == "TOX" or s == "BRN" or s == "PAR"
        or s == "POISON" or s == "BURN" or s == "PARALYSIS" then
      odds = math.floor(baseOdds * 15 / 10)
    end
  end

  return math.max(1, math.min(255, odds))
end

local function vanilla_catch(itemId, foeBattler, st, session, rng)
  local num = ItemsData.toNumericId(itemId) or tonumber(itemId) or 4
  if num == 1 then
    return true, 4
  end

  local odds = Catching.catchOdds(itemId, foeBattler, st, session)

  if odds >= 255 then
    return true, 4
  end

  -- pret GBA shake check threshold 'b'
  -- b = floor(1048560 / sqrt(sqrt(16711680 / a)))
  local shakeOdds = math.floor(1048560 / math.sqrt(math.sqrt(16711680 / odds)))
  local shakes = 0

  for _ = 1, 4 do
    local r = roll_rng(rng, 0, 65535)
    if r < shakeOdds then
      shakes = shakes + 1
    else
      return false, shakes
    end
  end

  return true, 4
end

local function battle_state(st)
  if st then return st end
  local B = package.loaded["src.core.game3.battle.init"] or package.loaded["src.core.game3.battle"]
  return B and B.getState and B.getState() or nil
end

--- Attempt to catch the foe.
-- Returns: caught (bool), shakes (0..4).
-- pokefirered/src/battle_script_commands.c:9463
function Catching.tryCatch(itemId, foeBattler, st, session, rng)
  local caught, shakes
  if ModRuntime.wantsHook("catch.rate") then
    local G3 = require("src.mods.Gen3Compat")
    local mon = foeBattler and foeBattler.mon
    local species = foeBattler and (foeBattler.species or (mon and (mon.species or mon.speciesId)))
    local ballNum = ItemsData.toNumericId(itemId) or tonumber(itemId) or 4
    caught, shakes = ModRuntime.call("catch.rate", function(b, _, _, o)
      local id = (b ~= nil and G3.itemId(b)) or ballNum
      return vanilla_catch(id, o.target, st, o.session, o.rng)
    end, G3.itemName(ballNum) or "POKE_BALL", mon, G3.speciesView(species), {
      battle = battle_state(st), target = foeBattler, session = session, rng = rng,
      ballId = ballNum, species = G3.speciesName(species), speciesId = tonumber(species),
      rate = Catching.catchOdds(itemId, foeBattler, st, session),
    })
    caught = caught and true or false
    shakes = tonumber(shakes) or (caught and 4 or 0)
  else
    caught, shakes = vanilla_catch(itemId, foeBattler, st, session, rng)
  end
  if ModRuntime.wants("battle.ball_thrown") then
    local G3 = require("src.mods.Gen3Compat")
    local mon = foeBattler and foeBattler.mon
    local species = foeBattler and (foeBattler.species or (mon and (mon.species or mon.speciesId)))
    local ballNum = ItemsData.toNumericId(itemId) or tonumber(itemId) or 4
    ModRuntime.emit("battle.ball_thrown", {
      battle = battle_state(st), ball = G3.itemName(ballNum), ballId = ballNum,
      caught = caught, shakes = shakes, mon = mon, target = foeBattler,
      species = G3.speciesName(species), speciesId = tonumber(species),
    })
  end
  return caught, shakes
end

local function clone_mon(mon)
  if type(mon) ~= "table" then return nil end
  local copy = {}
  for k, v in pairs(mon) do
    if type(v) == "table" then
      local inner = {}
      for ik, iv in pairs(v) do inner[ik] = iv end
      copy[k] = inner
    else
      copy[k] = v
    end
  end
  return copy
end

--- Store a caught Pokémon into session party or PC.
-- Marks Pokédex as caught, tracks firstTimeCaught, and returns result info.
function Catching.storeCaught(session, foeBattler, ballId)
  if not session or not foeBattler or not foeBattler.mon then
    return { success = false, location = nil, firstTimeCaught = false, mon = nil }
  end

  session.party = session.party or {}
  session.dex = session.dex or Dex.new()

  local mon = clone_mon(foeBattler.mon)
  local otName = session.name or session.playerName or "RED"
  local trainerId = session.trainerId or session.id or session.playerId or 12345
  mon.ot = otName
  mon.otName = otName
  mon.otId = trainerId
  mon.pokeball = ItemsData.toNumericId(ballId) or 4
  mon.nickname = mon.nickname or ""
  local species = foeBattler.species or mon.species or mon.speciesId
  mon.species = species
  mon.speciesId = species
  if not mon.name or mon.name == "" then
    mon.name = Pokemon.name(species) or "POKéMON"
  end

  local wasCaught = Dex.registerCapture(session.dex, species)
  local firstTimeCaught = not wasCaught

  local location = "party"
  local boxId, boxSlot
  if #session.party < 6 then
    session.party[#session.party + 1] = mon
    location = "party"
  else
    local Storage = require("src.core.game3.storage")
    local ok, bId, sId = Storage.depositCaught(session, mon)
    if ok then
      location = "pc"
      boxId = bId
      boxSlot = sId
    else
      return {
        success = false,
        reason = "storage_full",
        location = nil,
        firstTimeCaught = false,
        mon = nil,
      }
    end
  end

  -- pokefirered/src/battle_script_commands.c:9617
  if ModRuntime.wants("pokemon.caught") then
    local G3 = require("src.mods.Gen3Compat")
    local R = package.loaded["src.core.game3.runtime"]
    ModRuntime.emit("pokemon.caught", {
      battle = battle_state(nil), mon = mon, species = G3.speciesName(species),
      speciesId = tonumber(species), isNew = firstTimeCaught,
      ball = G3.itemName(mon.pokeball), ballId = mon.pokeball,
      destination = location == "pc" and "box" or "party",
      box = boxId, slot = boxSlot, game = R and R._game or nil,
    })
  end

  return {
    success = true,
    location = location,
    firstTimeCaught = firstTimeCaught,
    mon = mon,
    box = boxId,
    slot = boxSlot,
  }
end

return Catching
