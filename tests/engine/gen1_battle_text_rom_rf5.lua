package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()

local EffectRegistry = require("src.battle.EffectRegistry")
local MoveEffects = require("src.battle.MoveEffects")
local Status = require("src.battle.Status")
local StatusRegistry = require("src.battle.StatusRegistry")
local TrainerAI = require("src.battle.TrainerAI")
local WideBattle = require("src.battle.WideBattle")

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
  "src/battle/MoveEffects.lua", "src/battle/Status.lua", "src/battle/EffectRegistry.lua",
  "src/battle/TrainerAI.lua", "src/battle/StatusRegistry.lua", "src/battle/WideBattle.lua",
  "src/world/OverworldController.lua",
}

local CART_LINES = {
  "Enemy %s", "rose!", "fell!", "greatly", "ATTACK", "DEFENSE", "SPEED", "SPECIAL",
  "ACCURACY", "EVADE", "FIGHT", "ITEM", "BAIT", "THROW ROCK", "RUN", "BALL",
  "found\\n", "coins!", "Gyaoo!", "I like shorts", "BICYCLE", "POKéMON LEAGUE HQ",
  "POKéMON GYM", "Keep it up!", "Go right ahead!", "BOULDERBADGE", "That is the",
  "You don't have the", "LOG OFF", "HEAL", "CANCEL", "PROF.OAK's PC", "LEAGUE",
  "BILL'S PC", "SOMEONE'S PC", "'s PC", "hurt by", "Sucked health", "dream was eaten",
  "A blinding FLASH", "used\\nSTRENGTH", "move boulders", "POKéMON books",
  "POKéMON stuff", "elevator", "Bingo!", "electric", "TELEPORTER", "favorite",
  "got on", "hacked", "Accessed", "POKéDEX", "content", "POKéMON CENTER",
  "heal your", "We'll need", "fighting fit",
}

for _, file in ipairs(FILES) do
  local src = stripComments(readAll(file))
  local count = 0
  for call in src:gmatch('[Rr]omText(%b())') do
    if call:find('^%([^,]+,%s*"[%w_%.]+",%s*"') then count = count + 1 end
  end
  T.eq(count, 0, file .. " passes no literal romText fallback")
  T.check(not src:find("or%s+Strings%("), file .. " has no lookup-or-Strings fallback")
  local found = {}
  for lit in src:gmatch('Strings%("([^"]*)"') do
    for _, line in ipairs(CART_LINES) do
      if lit:find(line, 1, true) then found[#found + 1] = lit end
    end
  end
  T.eq(#found, 0, file .. " hand-types no cart line (" .. table.concat(found, " | ") .. ")")
end

local function with(overrides, fn)
  local saved = {}
  for k, v in pairs(overrides) do saved[k] = Data.text[k]; Data.text[k] = v end
  local ok, err = pcall(fn)
  for k in pairs(overrides) do Data.text[k] = saved[k] end
  if not ok then error(err, 0) end
end

local function errs(label, fn)
  local saved = Data.text[label]
  Data.text[label] = nil
  local ok, err = pcall(fn)
  Data.text[label] = saved
  return not ok and tostring(err):find(label .. " is not in the cache", 1, true) ~= nil
end

local function battler(name, isPlayer)
  return { name = name, isPlayer = isPlayer, stages = {}, curTypes = { "NORMAL" },
           mon = { hp = 40, stats = { hp = 64 } } }
end

local function newBattle()
  local battle = { data = Data, kind = "wild", rng = function(lo) return lo end }
  battle.player = battler("PLAYERMON", true)
  battle.enemy = battler("FOEMON", false)
  return battle
end

with({ EnemyText = "FX-FOE ", ["StatModTextStrings.1"] = "FX-ATK",
       ["StatModTextStrings.6"] = "FX-EVA" }, function()
  local battle = newBattle()
  T.eq(MoveEffects.changeStage(battle, battle.enemy, "attack", 1, false)[1],
    "FX-FOE FOEMON's\nFX-ATK rose!{PROMPT}",
    "a one-stage rise is _MonsStatsRoseText + StatModTextStrings + _RoseText")
  T.eq(MoveEffects.changeStage(battle, battle.enemy, "attack", 2, false)[1],
    "FX-FOE FOEMON's\nFX-ATK\ngreatly rose!{PROMPT}",
    "a two-stage rise scrolls _GreatlyRoseText onto the third line")
  T.eq(MoveEffects.changeStage(battle, battle.player, "evasion", -1, true)[1],
    "PLAYERMON's\nFX-EVA fell!{PROMPT}",
    "a one-stage drop is _MonsStatsFellText + _FellText")
  T.eq(MoveEffects.changeStage(battle, battle.player, "evasion", -2, true)[1],
    "PLAYERMON's\nFX-EVA\ngreatly fell!{PROMPT}",
    "a two-stage drop adds _GreatlyFellText")
  T.eq(EffectRegistry.displayName(Data, battle.enemy), "FX-FOE FOEMON",
    "EffectRegistry's enemy prefix is the cart's EnemyText")
  local ctx = EffectRegistry.makeCtx(battle, battle.player, battle.enemy, { id = "TACKLE" }, {})
  T.eq(ctx.displayName(battle.enemy), "FX-FOE FOEMON",
    "the record ctx keeps its one-argument displayName")
  local msgs = StatusRegistry.inflict(battle, battle.enemy, "PSN", {})
  T.check(msgs[1] and msgs[1]:find("FX-FOE FOEMON", 1, true) == 1,
    "StatusRegistry's enemy prefix is the cart's EnemyText")
end)

with({ EnemyText = "FX-FOE ", ["StatModTextStrings.3"] = "FX-SPD" }, function()
  local battle = newBattle()
  battle.trainer = { name = "FX TRAINER" }
  local msgs = TrainerAI.useItem(battle, "X_SPEED")
  T.eq(msgs[3], "FX-FOE FOEMON's\nFX-SPD rose!{PROMPT}",
    "the AI's X item line is _MonsStatsRoseText + _RoseText")
end)

with({ _HurtByPoisonText = "FX-PSN {TARGET}{PROMPT}" }, function()
  local battle = newBattle()
  battle.enemy.mon.status = "PSN"
  local msgs = Status.residualStatus(battle.enemy, battle.player, battle)
  T.eq(msgs[1], "FX-PSN FOEMON{PROMPT}", "poison damage reads _HurtByPoisonText")
end)

with({ _SuckedHealthText = "FX-SUCK {TARGET}{PROMPT}", EnemyText = "FX-FOE " }, function()
  local battle = newBattle()
  local said = {}
  local ctx = { battle = battle, user = battle.player, target = battle.enemy, totalDealt = 10,
                say = function(t) said[#said + 1] = t end }
  battle.drainNext = function() end
  MoveEffects.full.DRAIN_HP_EFFECT.afterDamage(ctx)
  T.eq(said[1], "FX-SUCK FX-FOE FOEMON{PROMPT}", "a drain move reads _SuckedHealthText")
end)

T.check(errs("_RoseText", function()
  local battle = newBattle()
  MoveEffects.changeStage(battle, battle.player, "attack", 1, false)
end), "a cache without _RoseText is an error")
T.check(errs("EnemyText", function()
  local battle = newBattle()
  MoveEffects.changeStage(battle, battle.enemy, "attack", 1, false)
end), "a cache without EnemyText is an error")
T.check(errs("_FastAsleepText", function()
  local battle = newBattle()
  battle.player.mon.status = "SLP"
  battle.player.sleepTurns = 3
  Status.beforeMove(battle.player, battle.rng, battle)
end), "a cache without _FastAsleepText is an error")
T.check(errs("StatModTextStrings.4", function()
  local battle = newBattle()
  battle.trainer = { name = "FX TRAINER" }
  TrainerAI.useItem(battle, "X_SPECIAL")
end), "a cache without StatModTextStrings is an error")

local menu = WideBattle.menuCells(Data.text.BattleMenuText, 6)
T.eq(menu[1][1] .. "|" .. menu[1][2] .. "|" .. menu[2][1] .. "|" .. menu[2][2],
  "FIGHT|<PK><MN>|ITEM|RUN", "the wide battle menu is BattleMenuText, split at its column")
local safari = WideBattle.menuCells(Data.text.SafariZoneBattleMenuText, 12)
T.eq(safari[1][1] .. "|" .. safari[1][2] .. "|" .. safari[2][1] .. "|" .. safari[2][2],
  "BALL×|BAIT|THROW ROCK|RUN", "the wide safari menu is SafariZoneBattleMenuText")

local OW = require("src.world.OverworldController")
local function setUpvalue(fn, name, value)
  for i = 1, 200 do
    local key = debug.getupvalue(fn, i)
    if key == name then debug.setupvalue(fn, i, value) return true end
    if not key then return false end
  end
end

local pushed
local function coinGame(coins)
  local save = require("src.core.SaveData").newGame()
  save.player.name = "FXPLAYER"
  save.inventory = { COIN_CASE = 1 }
  save.coins = coins
  pushed = {}
  return { data = Data, save = save,
           stack = { push = function(_, b) pushed[#pushed + 1] = b end } }
end
local savedCoins = Data.field.hiddenCoins
Data.field.hiddenCoins = { FIX_TOWN = { { x = 5, y = 5, coins = 20 } } }
local coinOw = setmetatable({ map = { id = "FIX_TOWN" } }, { __index = OW })
T.check(setUpvalue(OW.tryHiddenObject, "TextBox",
  { new = function(_, text) return { text = text } end,
    soundOpts = function() return {} end }), "TextBox upvalue on tryHiddenObject")
with({ _FoundHiddenCoinsText = "FX-COINS {PLAYER} {NUM:hCoins, 2}{DONE}",
       _FoundHiddenCoins2Text = "FX-COINS2 {PLAYER} {NUM:hCoins, 2}{DONE}",
       _DroppedHiddenCoinsText = "\fFX-DROPPED{DONE}" }, function()
  setUpvalue(OW.tryHiddenObject, "Game", coinGame(10))
  coinOw:tryHiddenObject(5, 5)
  T.eq(pushed[1] and pushed[1].text, "FX-COINS FXPLAYER 20{DONE}",
    "hidden coins read _FoundHiddenCoinsText")
  setUpvalue(OW.tryHiddenObject, "Game", coinGame(9990))
  coinOw:tryHiddenObject(5, 5)
  T.eq(pushed[1] and pushed[1].text, "FX-COINS2 FXPLAYER 20\fFX-DROPPED{DONE}",
    "a full COIN CASE reads _FoundHiddenCoins2Text + _DroppedHiddenCoinsText")
end)
Data.field.hiddenCoins = savedCoins

local menuItems
package.loaded["src.ui.Menu"] = { new = function(_, items) menuItems = items return {} end }
local pcGame = coinGame(0)
pcGame.save.flags = { EVENT_GOT_POKEDEX = true }
setUpvalue(OW.openPC, "Game", pcGame)
setUpvalue(OW.openPC, "TextBox", { new = function(_, text, onDone) return { text = text, onDone = onDone } end })
with({ SomeonesPCText = "FX-SOMEONE", PlayersPCText = "FX-OWN", OaksPCText = "FX-OAK",
       LogOffPCText = "FX-LOGOFF" }, function()
  setmetatable({}, { __index = OW }):openPC(function() end)
  pushed[1].onDone()
  local labels = {}
  for i, item in ipairs(menuItems or {}) do labels[i] = item.label end
  T.eq(table.concat(labels, "|"), "FX-SOMEONE|FXPLAYERFX-OWN|FX-OAK|FX-LOGOFF",
    "the PC rows are SomeonesPCText, name + PlayersPCText, OaksPCText and LogOffPCText")
end)

local src = stripComments(readAll("src/world/OverworldController.lua"))
T.check(src:find('"TwoOptionMenuStrings.HealCancelMenu"', 1, true) ~= nil,
  "the nurse's HEAL / CANCEL rows come from TwoOptionMenuStrings.HealCancelMenu")
T.check(src:find('"_Route18Gate1FGuardYouNeedABicycleText"', 1, true) ~= nil,
  "the Cycling Road refusal is the cart's own bicycle line")

T.finish("gen1_battle_text_rom_rf5")
