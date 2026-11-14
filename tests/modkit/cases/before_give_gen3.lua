package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.modkit")
local Sdk = require("tests.modkit.sdk")
local ModRuntime = require("src.mods.Runtime")
local Events = require("src.mods.Events")
local Hooks = require("src.mods.Hooks")
local Callbacks = require("src.mods.UnifiedCallbacks")
local Records = require("src.mods.UnifiedRecords")
local Version = require("src.core.GameVersion")
local Runtime = require("src.core.game3.runtime")
local Pokemon = require("src.core.game3.pokemon")
local Party = require("src.core.game3.party")
local Breeding = require("src.core.game3.breeding")
local Daycare = require("src.core.game3.daycare")
local Dex = require("src.core.game3.dex")
local Ops = require("src.core.game3.scripting.ops_a")
local Ctx = require("src.core.game3.scripting.ctx")
local Flags = require("src.core.game3.scripting.flags")

local savedRuntime = { ModRuntime.events, ModRuntime.hooks, ModRuntime.errors }
require("src.core.game3.rom_text").plain = function(key) return key end

local function setup(version)
  Version.set(version)
  ModRuntime.install(Events.new(), Hooks.new(), {})
  local data = Sdk.gen3Data()
  for key, value in pairs(data.gen3Pokemon) do Pokemon[key] = value end
  Pokemon._battleMoves = data.gen3Moves._rom
  Pokemon._tmhm = { machines = {}, learnsets = {} }
  Pokemon._national = { toNational = { [4] = 4, [5] = 5, [16] = 16 } }
  Pokemon._byName = { CHARMANDER = 4, CHARMELEON = 5, PIDGEY = 16 }
  local session = { version = version, name = "RED", trainerId = 4242, secretId = 0,
    party = {}, flags = {}, vars = {}, store = { flags = {}, vars = {} },
    dex = Dex.new(), mapSec = 1, map = "FR_TRADE_CENTER", gameStats = {} }
  local game = { data = data, session = session, phase = "field" }
  session.game = game
  Runtime.active, Runtime.session, Runtime._game = true, session, game
  local loader = { generation = 3, version = version, game = game,
    events = ModRuntime.events, hooks = ModRuntime.hooks }
  function loader:_game() return self.game end
  return session, Callbacks.new(loader, "give_probe"), data
end

local function makeMon(session, species, personality)
  local scratch = { party = {}, name = session.name, version = session.version,
    trainerId = session.trainerId, secretId = 0, mapSec = 1 }
  local _, _, mon = Party.giveMon(scratch, species, 5, "", { personality = personality })
  return mon
end

local function pair(session)
  local dc = Daycare.stateOf(session)
  dc[1] = makeMon(session, 4, 0)
  dc[2] = makeMon(session, 4, 254)
  dc.steps, dc.stepCounter = { 254, 254 }, 0
  dc.offspringPersonality, dc.eggPending = 0, true
  return dc
end

local function dispatch(row, adapters)
  local store = Flags.newStore()
  local ctx = Ctx.new({})
  local vm = { ctx = ctx, store = store, setPc = function() end, adapters = adapters }
  adapters.log = adapters.log or function() end
  if row.var then Flags.setVar(store, ctx, row.var, row.value) end
  Ops.dispatchUnhooked(vm, { op = row.op, [1] = row.var or row.value, [2] = row.level, [3] = 0 })
  return Flags.getVar(store, ctx, Ctx.VAR_RESULT), row.var and Flags.getVar(store, ctx, row.var)
end

T.eq(Callbacks.supports("events", "pokemon.before_give", 3), true, "pokemon.before_give is supported in Gen 3")

for _, version in ipairs({ "firered", "emerald" }) do
  local session = setup(version)
  local gifts, target = {}, nil
  ModRuntime.events:on("pokemon.before_give", function(gift)
    gifts[#gifts + 1] = { species = gift.species, speciesId = gift.speciesId, level = gift.level,
      isEgg = gift.isEgg, ctx = gift.ctx }
    if target then gift.species = target end
    gift.nickname = "SPIKE"
  end)

  local eggSpecies
  local _, var = dispatch({ op = "giveegg", var = 0x4001, value = 4 },
    { giveEggToPlayer = function(sp) eggSpecies = sp return 0 end })
  local g = gifts[#gifts]
  T.eq(#gifts, 1, version .. " giveegg: the event fires once")
  T.eq(g and g.isEgg, true, version .. " giveegg: gift.isEgg is true")
  T.eq(g and g.speciesId, 4, version .. " giveegg: gift.speciesId is the script's species")
  T.eq(g and g.species, "CHARMANDER", version .. " giveegg: gift.species is the species name")
  T.eq(g and g.level, 5, version .. " giveegg: gift.level is the hatch level")
  T.check(g and type(g.ctx) == "table", version .. " giveegg: gift.ctx is the script ctx")
  T.eq(eggSpecies, 4, version .. " giveegg: an untouched gift gives the script's egg")
  T.eq(var, 4, version .. " giveegg: an untouched gift leaves the var")

  target = 16
  _, var = dispatch({ op = "giveegg", var = 0x4001, value = 4 },
    { giveEggToPlayer = function(sp) eggSpecies = sp return 0 end })
  T.eq(eggSpecies, 16, version .. " giveegg: the species rewrite holds")
  T.eq(var, 16, version .. " giveegg: the species var follows the rewrite")

  target = nil
  local monNick
  dispatch({ op = "givemon", value = 4, level = 5 },
    { giveMonToPlayer = function(_, _, _, nick) monNick = nick return 0 end })
  T.eq(gifts[#gifts].isEgg, false, version .. " givemon: gift.isEgg is false")
  T.eq(monNick, "SPIKE", version .. " givemon: gift.nickname still names the gift")

  target = 16
  session.party = {}
  pair(session)
  local before = #gifts
  local egg = Breeding.giveEggFromDaycare(session)
  g = gifts[#gifts]
  T.eq(#gifts, before + 1, version .. " Day-Care: the event fires once")
  T.eq(g and g.isEgg, true, version .. " Day-Care: gift.isEgg is true")
  T.eq(g and g.speciesId, 4, version .. " Day-Care: gift.speciesId is the bred species")
  T.eq(egg and Pokemon.speciesOf(egg), 16, version .. " Day-Care: the species rewrite holds")
  T.eq(egg and egg.isEgg, true, version .. " Day-Care: the record is an egg")
  T.eq(session.party[1], egg, version .. " Day-Care: the egg joins the party")
end

do
  local session, api, data = setup("firered")
  local seen
  api.events:on("pokemon.before_give", function(gift)
    seen = { species = gift.species, isEgg = gift.isEgg }
    gift.species = Records.id(16, "species", 3, data)
  end)
  session.party = {}
  pair(session)
  local egg = Breeding.giveEggFromDaycare(session)
  T.eq(seen and seen.isEgg, true, "API 3: Day-Care gift.isEgg is true")
  T.eq(seen and seen.species, Records.id(4, "species", 3, data), "API 3: gift.species is the portable id")
  T.eq(egg and Pokemon.speciesOf(egg), 16, "API 3: a portable species rewrite lands as the native one")
end

ModRuntime.install(savedRuntime[1], savedRuntime[2], savedRuntime[3])
T.finish("pokemon.before_give Gen 3")
