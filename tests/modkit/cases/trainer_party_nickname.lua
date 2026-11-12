package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.modkit")
local Fixtures = require("tests.modkit").fixtures
local BattleState = require("src.battle.BattleState")
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")

local FIXTURE = {
  ["mods/party_nick/manifest.json"] = [[{
    "id": "party_nick",
    "name": "Party Nickname Probe",
    "version": "1.0.0",
    "entry": "main.lua",
    "api": 2,
    "games": ["gen1", "gen2", "gen3"]
  }]],
  ["mods/party_nick/main.lua"] = [[
    local mod = ...
    mod.hooks:wrap("trainer.party", function(next, class, index, party)
      local rows = next(class, index, party)
      local names = mod.exports.names
      if not names then return rows end
      local out = {}
      for i, row in ipairs(rows) do
        local copy = {}
        for k, v in pairs(row) do copy[k] = v end
        copy.nickname = names[i]
        out[i] = copy
      end
      return out
    end)
  ]],
}

local function battleFor(data)
  local save = SaveData.newGame()
  save.party = { Pokemon.new(data, "FIXMON_B", 20) }
  SaveData.validate(save, data)
  return BattleState.newTrainer({ data = data, save = save }, "OPP_FIX_YOUNGSTER", 1)
end

local data = Fixtures.fresh()
local vanilla = T.sdk.loadNone({})
local plain = battleFor(data)
T.eq(plain.enemyParty[1].nickname, nil, "gen 1, no mod: the enemy mon has no nickname")
T.eq(plain.enemy.name, data.pokemon.FIXMON_A.name, "gen 1, no mod: the battler shows the species name")
vanilla.release()

local run = T.sdk.loadMods({ "mods/party_nick" }, { fs = T.sdk.memfs(FIXTURE), data = data })
T.eq(#run.errors, 0, "the probe loads clean (" .. tostring(run.errors[1]) .. ")")
local probe = run.loader.exports.party_nick

probe.names = { "SPIKE", "TOOLONGFORTHEGRID" }
local named = battleFor(data)
T.eq(named.enemyParty[1].nickname, "SPIKE", "gen 1: the lead takes the row's nickname")
T.eq(named.enemy.name, "SPIKE", "gen 1: the battler shows it")
T.eq(named.enemyParty[2].nickname, "TOOLONGFOR", "gen 1: a long name is clipped to ten")
T.eq(data.trainers.OPP_FIX_YOUNGSTER.parties[1][1].nickname, nil, "gen 1: the trainer data is not written")

probe.names = { ("\195\137"):rep(12) }
T.eq(battleFor(data).enemyParty[1].nickname, ("\195\137"):rep(10), "gen 1: the clip counts characters")

probe.names = { "" }
local blank = battleFor(data)
T.eq(blank.enemyParty[1].nickname, nil, "gen 1: an empty nickname names nothing")
T.eq(blank.enemy.name, data.pokemon.FIXMON_A.name, "gen 1: the species name stays")

run.release()

local Cache = require("tests.game3_cache")
local cacheRoot = Cache.mount("scripts/events.lua", { native = true })
if not cacheRoot then
  print("[skip] trainer.party nicknames, gen 3 half: " .. tostring(Cache.reason))
  T.finish("trainer.party nicknames")
  return
end
local Space = require("src.core.game3.scripting.space")
local ExtractScripts = require("src.import.gba.extract_scripts")
Space.bundle = ExtractScripts.loadBundle(Cache.cache(), cacheRoot, { allowIncomplete = true })

local BattleBridge = require("src.core.game3.battle_bridge")
local Battle = require("src.core.game3.battle")
local State = require("src.core.game3.battle.state")
local Dataset = require("src.core.game3.dataset")
local Runtime = require("src.core.game3.runtime")
local Party = require("src.core.game3.party")
local Trainers = require("src.core.game3.scripting.trainers")

local game = { data = {} }
Dataset.hydrate(game)
local session = { map = "FR_PALLET_TOWN", x = 12, y = 20, facing = "down", flags = {}, vars = {}, party = {}, name = "RED" }
game.session = session
Runtime.start(nil, game, session, { reason = "new_game" })
Party.giveMon(session, 150, 70)

local trainerId
for id = 1, 900 do
  local foe = Trainers.foeFromId(id)
  if foe and foe.party and #foe.party >= 2 and not foe.doubleBattle then trainerId = id break end
end
T.check(trainerId ~= nil, "gen 3: found a trainer with two Pokemon")

local function startGen3()
  local ok = BattleBridge.start(nil, game, Trainers.foeFromId(trainerId),
    { trainerId = trainerId, headless = true, autoFight = false, fade = false })
  T.check(ok, "gen 3: the trainer battle starts")
  local st = Battle.getState()
  local lead, second = st and st.enemy, st and st.foeParty and st.foeParty[2]
  local leadName = lead and State.displayName(lead)
  local leadNick = lead and lead.mon and lead.mon.nickname
  Battle.runToEnd()
  if Battle.isActive() then BattleBridge.finishPending("win") end
  return leadNick, leadName, second and second.nickname
end

local run3 = T.sdk.loadMods({ "mods/party_nick" }, { fs = T.sdk.memfs(FIXTURE), data = game.data, generation = 3 })
T.eq(#run3.errors, 0, "gen 3: the probe loads clean (" .. tostring(run3.errors[1]) .. ")")
local probe3 = run3.loader.exports.party_nick
local plainNick = startGen3()
T.check(plainNick == nil or plainNick == "", "gen 3, names unset: the lead has no nickname")
probe3.names = { "SPIKE", "BLAZE" }
local leadNick, leadName, secondNick = startGen3()
T.eq(leadNick, "SPIKE", "gen 3: the lead takes the row's nickname")
T.eq(leadName, "SPIKE", "gen 3: the battle shows it")
T.eq(secondNick, "BLAZE", "gen 3: the next slot keeps its own")
run3.release()

T.finish("trainer.party nicknames")
