-- FRLG trainer prize money (pret Cmd_getmoneyreward / gTrainerMoneyTable).

local Trainers = require("src.core.game3.scripting.trainers")

local Prize = {}

Prize.MAX_MONEY = 999999

-- pret battle_main.c gTrainerMoneyTable (classId → payout factor).
-- Unknown classes fall through to terminator value 5.
local CLASS_MONEY = {
  [84] = 25, -- LEADER
  [87] = 25, -- ELITE_FOUR
  [97] = 25, -- PKMN_PROF
  [81] = 4,  -- RIVAL_EARLY
  [89] = 9,  -- RIVAL_LATE
  [90] = 25, -- CHAMPION
  [57] = 4,  -- YOUNGSTER
  [58] = 3,  -- BUG_CATCHER
  [65] = 9,  -- HIKER
  [79] = 6,  -- BIRD_KEEPER
  [62] = 5,  -- PICNICKER
  [64] = 6,  -- SUPER_NERD
  [69] = 9,  -- FISHERMAN
  [85] = 8,  -- TEAM_ROCKET
  [59] = 4,  -- LASS
  [73] = 18, -- BEAUTY
  [80] = 6,  -- BLACK_BELT
  [71] = 6,  -- CUE_BALL
  [91] = 8,  -- CHANNELER
  [76] = 6,  -- ROCKER
  [88] = 18, -- GENTLEMAN
  [67] = 22, -- BURGLAR
  [70] = 1,  -- SWIMMER_M
  [68] = 12, -- ENGINEER
  [77] = 10, -- JUGGLER
  [60] = 8,  -- SAILOR
  [86] = 9,  -- COOLTRAINER
  [63] = 12, -- POKEMANIAC
  [78] = 10, -- TAMER
  [61] = 5,  -- CAMPER
  [75] = 5,  -- PSYCHIC
  [66] = 5,  -- BIKER
  [72] = 18, -- GAMER
  [82] = 12, -- SCIENTIST
  [99] = 6,  -- CRUSH_GIRL
  [100] = 1, -- TUBER
  [101] = 7, -- PKMN_BREEDER
  [102] = 9, -- PKMN_RANGER
  [103] = 7, -- AROMA_LADY
  [104] = 12, -- RUIN_MANIAC
  [105] = 50, -- LADY
  [106] = 4, -- PAINTER
  [92] = 3,  -- TWINS
  [94] = 7,  -- YOUNG_COUPLE
  [96] = 1,  -- SIS_AND_BRO
  [93] = 6,  -- COOL_COUPLE
  [95] = 6,  -- CRUSH_KIN
  [74] = 1,  -- SWIMMER_F
  [98] = 1,  -- PLAYER
  [24] = 25, -- RS_LEADER
  [23] = 25, -- RS_ELITE_FOUR
  [49] = 4,  -- RS_LASS
  [29] = 4,  -- RS_YOUNGSTER
  [44] = 15, -- PKMN_TRAINER
  [51] = 10, -- RS_HIKER
  [12] = 20, -- RS_BEAUTY
  [31] = 10, -- RS_FISHERMAN
  [11] = 50, -- RS_LADY
  [32] = 10, -- TRIATHLETE
  [3] = 5,   -- TEAM_AQUA
  [40] = 3,  -- RS_TWINS
  [38] = 2,  -- RS_SWIMMER_F
  [50] = 4,  -- RS_BUG_CATCHER
  [25] = 5,  -- SCHOOL_KID
  [13] = 50, -- RICH_BOY
  [26] = 4,  -- SR_AND_JR
  [16] = 8,  -- RS_BLACK_BELT
  [7] = 1,   -- RS_TUBER_F
  [10] = 6,  -- HEX_MANIAC
  [45] = 10, -- RS_PKMN_BREEDER
  [48] = 5,  -- TEAM_MAGMA
  [6] = 12,  -- INTERVIEWER
  [8] = 1,   -- RS_TUBER_M
  [52] = 8,  -- RS_YOUNG_COUPLE
  [17] = 8,  -- GUITARIST
  [22] = 20, -- RS_GENTLEMAN
  [30] = 50, -- RS_CHAMPION
  [47] = 20, -- MAGMA_LEADER
  [36] = 6,  -- BATTLE_GIRL
  [15] = 2,  -- RS_SWIMMER_M
  [27] = 20, -- POKEFAN
  [28] = 10, -- EXPERT
  [33] = 12, -- DRAGON_TAMER
  [34] = 8,  -- RS_BIRD_KEEPER
  [35] = 3,  -- NINJA_BOY
  [37] = 10, -- PARASOL_LADY
  [20] = 15, -- BUG_MANIAC
  [41] = 8,  -- RS_SAILOR
  [43] = 15, -- COLLECTOR
  [46] = 12, -- RS_PKMN_RANGER
  [56] = 10, -- MAGMA_ADMIN
  [4] = 10,  -- RS_AROMA_LADY
  [5] = 15,  -- RS_RUIN_MANIAC
  [9] = 12,  -- RS_COOLTRAINER
  [14] = 15, -- RS_POKEMANIAC
  [18] = 8,  -- KINDLER
  [19] = 4,  -- RS_CAMPER
  [39] = 4,  -- RS_PICNICKER
  [21] = 6,  -- RS_PSYCHIC
  [54] = 3,  -- RS_SIS_AND_BRO
  [53] = 10, -- OLD_COUPLE
  [55] = 10, -- AQUA_ADMIN
  [2] = 20,  -- AQUA_LEADER
  [83] = 25, -- BOSS
}

Prize.CLASS_MONEY = CLASS_MONEY
Prize.DEFAULT_CLASS_VALUE = 5

function Prize.classValue(classId)
  classId = tonumber(classId)
  if classId == nil then return Prize.DEFAULT_CLASS_VALUE end
  return CLASS_MONEY[classId] or Prize.DEFAULT_CLASS_VALUE
end

--- pret: 4 * lastMonLevel * moneyMultiplier * (double ? 2 : 1) * classValue
function Prize.calc(trainerId, opts)
  opts = opts or {}
  local info = Trainers.info(trainerId) or {}
  local classId = opts.class or info.class
  local lastLevel = tonumber(opts.lastLevel)
    or tonumber(info.lastLevel)
    or tonumber(opts.level)
    or 1
  if lastLevel < 1 then lastLevel = 1 end
  local mult = tonumber(opts.moneyMultiplier) or 1
  if mult < 1 then mult = 1 end
  local doubleMult = opts.double and 2 or 1
  local value = Prize.classValue(classId)
  return 4 * lastLevel * mult * doubleMult * value
end

function Prize.apply(session, amount)
  amount = math.max(0, math.floor(tonumber(amount) or 0))
  if not session or amount <= 0 then return 0, tonumber(session and session.money) or 0 end
  local money = tonumber(session.money) or 0
  local nextMoney = money + amount
  if nextMoney > Prize.MAX_MONEY then nextMoney = Prize.MAX_MONEY end
  local gained = nextMoney - money
  session.money = nextMoney
  return gained, nextMoney
end

--- Award trainer prize into session; returns amount gained (0 if wild/none).
function Prize.awardTrainerWin(session, trainerId, opts)
  if not trainerId then return 0 end
  local amount = Prize.calc(trainerId, opts)
  local gained = Prize.apply(session, amount)
  return gained
end

function Prize.moneyMessage(playerName, amount)
  playerName = playerName or "PLAYER"
  amount = math.floor(tonumber(amount) or 0)
  return playerName .. " got ¥" .. tostring(amount) .. "\nfor winning!"
end

-- pokefirered/src/battle_script_commands.c:7064
function Prize.payDay(session, coins, opts)
  opts = opts or {}
  coins = math.floor(tonumber(coins) or 0)
  if coins <= 0 or opts.link then return 0 end
  local mult = tonumber(opts.moneyMultiplier) or 1
  if mult < 1 then mult = 1 end
  local bonus = coins * mult
  Prize.apply(session, bonus)
  return bonus
end

-- pokefirered/src/battle_message.c:178
function Prize.payDayMessage(playerName, amount)
  playerName = playerName or "PLAYER"
  amount = math.floor(tonumber(amount) or 0) % 65536
  return playerName .. " picked up\n¥" .. tostring(amount) .. "!"
end

Prize.ABILITY_PICKUP = 53

-- pokefirered/src/battle_script_commands.c:772
Prize.PICKUP_ITEMS = {
  { 139, 15 }, { 133, 25 }, { 134, 35 }, { 135, 45 }, { 136, 55 }, { 137, 65 },
  { 140, 75 }, { 298, 80 }, { 69, 85 }, { 68, 90 }, { 110, 95 }, { 163, 96 },
  { 164, 97 }, { 165, 98 }, { 166, 99 }, { 167, 1 },
}

local function no_item(v)
  return v == nil or v == 0 or v == "" or v == "NONE"
end

-- pokefirered/src/battle_script_commands.c:9261
function Prize.pickup(party, random)
  local picked = {}
  if type(party) ~= "table" then return picked end
  random = random or require("src.core.game3.rng").Random
  local Pokemon = require("src.core.game3.pokemon")
  for i = 1, 6 do
    local mon = party[i]
    if type(mon) == "table" then
      local species = Pokemon.speciesOf and Pokemon.speciesOf(mon) or tonumber(mon.species)
      local ability = tonumber(mon.abilityId) or tonumber(mon.ability)
      if not ability and species and Pokemon.abilityId then
        ability = Pokemon.abilityId(species, mon.personality or 0)
      end
      if ability == Prize.ABILITY_PICKUP and species and species ~= 0
        and not (mon.isEgg or mon.egg)
        and no_item(mon.item) and no_item(mon.heldItem)
        and random() % 10 == 0 then
        local r = random() % 100
        local j = 1
        while j <= 15 and not (Prize.PICKUP_ITEMS[j][2] > r) do
          j = j + 1
        end
        local itemId = Prize.PICKUP_ITEMS[j][1]
        mon.item = itemId
        mon.heldItem = itemId
        picked[#picked + 1] = { slot = i, item = itemId }
      end
    end
  end
  return picked
end

return Prize
