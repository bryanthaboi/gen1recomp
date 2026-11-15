package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
require("src.render.Font").load(Data)

local BattleState = require("src.battle.BattleState")
local ItemEffects = require("src.inventory.ItemEffects")
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")

local function readAll(p)
  local f = assert(io.open(p, "rb"))
  local s = f:read("*a")
  f:close()
  return s
end

local function stripComments(s)
  local out = {}
  for line in (s .. "\n"):gmatch("(.-)\n") do
    out[#out + 1] = line:gsub("%-%-.*$", "")
  end
  return table.concat(out, "\n")
end

local FILES = {
  "src/battle/BattleState.lua", "src/link/LinkBattle.lua", "src/ui/g3u/Gen1Screen.lua",
  "src/inventory/ItemEffects.lua", "src/ui/BagMenu.lua", "src/ui/BoxMenu.lua",
  "src/ui/PartyMenu.lua", "src/ui/PlayerPC.lua", "src/ui/ShopMenu.lua",
  "src/ui/SlotMachine.lua", "src/ui/StartMenu.lua", "src/ui/MoveLearnMenu.lua",
  "src/ui/HallOfFame.lua", "src/ui/EvolutionState.lua", "src/ui/OakSpeech.lua",
  "src/ui/NamingScreen.lua", "src/script/Commands.lua",
}

local CART_LINES = {
  "wants\\nto fight!", "grew\\nto level", "about to use", "change POKéMON?",
  "useable POKéMON", "blacked\\nout!", "EXP. Points!", "Enemy %s", "rose!", "rose.",
  "fell!", "flew up high!", "dug a hole!", "is glowing!", "with-\\ndrew", "sent\\nout",
  "There's no will", "already out!", "Waiting...!", "WHICH TECHNIQUE?", "disabled!",
  "TYPE/", "NICKNAME?", "YOUR NAME?", "RIVAL's NAME?", "Now saving...", "Not this time!",
  "Bet how many", "One more", "Ran out of coins", "Not enough\\ncoins",
  "This isn't the", "Hello there!", "Is it OK to toss", "Threw away", "Toss %s?",
  "How many?", "too impor-", "No cycling", "can't get off", "learned\\n%s!",
  "What? There are", "Once released", "Choose a POKéMON.", "Bring out which",
  "Hi there!", "Thank you!", "anything to sell", "price on that", "enough money",
  "carry\\nany more", "SAVE the game?", "saved\\nthe game!", "Keep it up!",
  "POKéDEX Rating", "BADGE\\nis required", "FLY here", "use TELEPORT now",
}

for _, file in ipairs(FILES) do
  local src = stripComments(readAll(file))
  local count = 0
  for call in src:gmatch('[Rr]omText(%b())') do
    if call:find('^%([^,()]+,%s*"[%w_%.]+",%s*"') then count = count + 1 end
  end
  T.eq(count, 0, file .. " passes no literal romText fallback")
  T.check(not src:find(":romText(", 1, true), file .. " calls no BattleState:romText")
  local found = {}
  for lit in src:gmatch('Strings%("([^"]*)"') do
    for _, line in ipairs(CART_LINES) do
      if lit:find(line, 1, true) then found[#found + 1] = lit end
    end
  end
  T.eq(#found, 0, file .. " hand-types no cart line (" .. table.concat(found, " | ") .. ")")
end

T.eq(BattleState.romText, nil, "BattleState:romText is gone; romLine is the one battle text method")

local function newGame()
  local save = SaveData.newGame()
  save.player.name = "RED"
  save.party = { Pokemon.new(Data, "FIXMON_A", 5) }
  return { data = Data, save = save,
           stack = { top = function() return nil end,
                     push = function() end, pop = function() end } }
end

local function drain(battle)
  local rows = {}
  for _ = 1, 400 do
    local item = table.remove(battle.queue, 1)
    if not item then return rows end
    if item.text then rows[#rows + 1] = item.text end
    if item.fn then
      battle.nextInsert = 0
      pcall(item.fn)
    end
  end
  return rows
end

local function with(overrides, fn)
  local saved = {}
  for k, v in pairs(overrides) do saved[k] = Data.text[k]; Data.text[k] = v end
  local ok, err = pcall(fn)
  for k in pairs(overrides) do Data.text[k] = saved[k] end
  if not ok then error(err, 0) end
end

local function has(rows, needle)
  for _, r in ipairs(rows) do if r:find(needle, 1, true) then return true end end
  return false
end

with({ _TrainerWantsToFightText = "FX-INTRO {RAM:wTrainerName}{PROMPT}" }, function()
  local battle = BattleState.newTrainer(newGame(), "OPP_FIX_YOUNGSTER", 1)
  T.eq(battle.introText, "FX-INTRO FIX YOUNGSTER{PROMPT}",
    "the trainer intro is _TrainerWantsToFightText")
end)

with({ EnemyText = "FX-FOE " }, function()
  local battle = BattleState.newWild(newGame(), "FIXMON_C", 8)
  battle.enemy.rageMove = true
  battle:handleBuildingRage(battle.enemy)
  T.check(has(drain(battle), "FX-FOE " .. battle.enemy.name),
    "the enemy prefix is the cart's EnemyText")
end)

with({
  _GainedText = "FX-GAINED {RAM:wNameBuffer}\n{DONE}",
  _ExpPointsText = "FX-EXP {NUM:wExpAmountGained, 2, 4}{PROMPT}",
  _GrewLevelText = "FX-GREW {RAM:wNameBuffer} {NUM:wCurEnemyLevel, 1, 3}{DONE}",
}, function()
  local game = newGame()
  local battle = BattleState.newWild(game, "FIXMON_C", 60)
  battle.participants = { [battle.player.mon] = true }
  battle.queue = {}
  battle:awardExp()
  local rows = drain(battle)
  T.check(has(rows, "FX-GAINED " .. battle.player.name .. "\nFX-EXP "),
    "the exp line is _GainedText + _ExpPointsText")
  T.check(has(rows, "FX-GREW " .. battle.player.name .. " "),
    "the level-up line is _GrewLevelText")
end)

with({ _PlayerBlackedOutText2 = "FX-OUT {PLAYER}\fFX-BLACK {PLAYER}{PROMPT}" }, function()
  local game = newGame()
  local battle = BattleState.newWild(game, "FIXMON_C", 8)
  for _, mon in ipairs(game.save.party) do mon.hp = 0 end
  battle.queue = {}
  battle:playerMonFainted()
  local rows = drain(battle)
  T.check(has(rows, "FX-OUT RED") and has(rows, "FX-BLACK RED{PROMPT}"),
    "the blackout is _PlayerBlackedOutText2, paged at the cart's para")
end)

do
  local save = SaveData.newGame()
  local target = Pokemon.new(Data, "FIXMON_A", 10)
  with({ ["VitaminStats.4"] = "FX-SPD" }, function()
    local _, msgs = ItemEffects.use(Data, save, "CARBOS", target)
    T.check(msgs[1]:find("FX-SPD", 1, true) ~= nil, "a vitamin names its stat from VitaminStats")
  end)
  local vanilla = Data.text._PPRestoredText
  Data.text._PPRestoredText = nil
  local mon = Pokemon.new(Data, "FIXMON_A", 10)
  mon.moves[1].pp = 0
  T.check(not pcall(ItemEffects.use, Data, save, "ETHER", mon, nil, 1),
    "a cache without _PPRestoredText is an error, not an English literal")
  Data.text._PPRestoredText = vanilla
end

T.finish("gen1_battle_text_rom_rf4")
