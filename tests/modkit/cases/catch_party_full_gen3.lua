package.path = "./?.lua;./?/init.lua;" .. package.path
_G.love = _G.love or require("tests.love_stub")

local T = require("tests.modkit")
local Catching = require("src.core.game3.battle.catching")
local Battle = require("src.core.game3.battle.init")
local Ui = require("src.core.game3.battle.ui")
local Pokemon = require("src.core.game3.pokemon")
local Storage = require("src.core.game3.storage")
local UnifiedCallbacks = require("src.mods.UnifiedCallbacks")
local Records = require("src.mods.UnifiedRecords")

Pokemon.name = function() return "WURMPLE" end
local G3 = require("src.mods.Gen3Compat")
G3.itemName = function() return "POKE_BALL" end
G3.speciesName = function() return "WURMPLE" end
require("src.core.game3.battle.battle_text").get = function(_, args) return args and args.opponentMon1 or "caught" end

local session
package.loaded["src.core.game3.runtime"] = { getSession = function() return session end }

local function newSession(version, n)
  session = { version = version, party = {}, flags = {}, vars = {}, name = "RED", trainerId = 1 }
  for i = 1, n do session.party[i] = { species = 16, level = 5, nickname = "" } end
  return session
end

local function boxed(s)
  return Storage.countTotalMons(Storage.ensure(s))
end

local function catch(version, n)
  local s = newSession(version, n)
  local foe = { species = 290, mon = { species = 290, level = 4, name = "WURMPLE", personality = 1 } }
  return Catching.storeCaught(s, foe, 4), s
end

T.eq(UnifiedCallbacks.supports("hooks", "catch.party_full", 3), true, "catch.party_full is supported in Gen 3")

local vanilla = T.sdk.loadNone({ generation = 3, data = T.sdk.gen3Data() })
do
  local res, s = catch("firered", 6)
  T.eq(res.location, "pc", "no mod: a 6/6 catch goes to the PC")
  T.eq(boxed(s), 1, "no mod: the PC holds the catch")
end
vanilla.release()

local FIXTURE = {
  ["mods/full_probe/manifest.json"] = [[{"id":"full_probe","name":"Full Probe","version":"1.0.0",
    "api":2,"games":["all"],"entry":"main.lua"}]],
  ["mods/full_probe/main.lua"] = [[
    local mod = ...
    mod.exports.calls, mod.exports.caught = 0, {}
    mod.exports.answer = true
    mod.hooks:wrap("catch.party_full", function(next, ctx)
      mod.exports.calls = mod.exports.calls + 1
      mod.exports.ctx = ctx
      mod.exports.vanilla = next(ctx)
      return mod.exports.answer
    end)
    mod.events:on("pokemon.caught", function(payload)
      mod.exports.caught[#mod.exports.caught + 1] = payload
    end)
  ]],
}

local pcPage, asked
Storage.pcTransferMessage = function() pcPage = true; return "transfer" end
Ui.askYesNo = function() asked = true end

for _, version in ipairs({ "firered", "emerald" }) do
  local run = T.sdk.loadMods({ "mods/full_probe" },
    { fs = T.sdk.memfs(FIXTURE), generation = 3, data = T.sdk.gen3Data() })
  T.eq(#run.errors, 0, version .. " probe loads clean (" .. tostring(run.errors[1]) .. ")")
  local probe = run.loader.exports.full_probe

  probe.answer, probe.calls = true, 0
  local res, s = catch(version, 6)
  T.eq(probe.calls, 1, version .. " claim: the hook ran once")
  T.eq(res.success, true, version .. " claim: the catch succeeds")
  T.eq(res.location, "mod", version .. " claim: the result's location is mod")
  T.eq(#s.party, 6, version .. " claim: the party is untouched")
  T.eq(boxed(s), 0, version .. " claim: nothing is boxed")
  T.eq(res.pending, nil, version .. " claim: nothing waits for the PC")
  T.eq(probe.vanilla, false, version .. " the vanilla link never claims")
  T.check(probe.ctx and probe.ctx.mon == res.mon, version .. " ctx.mon is the caught mon")
  T.eq(probe.ctx and probe.ctx.name, "WURMPLE", version .. " ctx.name is the shown name")
  T.eq(probe.ctx and probe.ctx.speciesId, 290, version .. " ctx.speciesId is numeric")
  T.eq(type(probe.ctx and probe.ctx.species), "string", version .. " ctx.species is a name")
  local last = probe.caught[#probe.caught]
  T.eq(last and last.destination, "mod", version .. " pokemon.caught reports destination mod")

  local deferred = Catching.storeCaught(newSession(version, 6),
    { species = 290, mon = { species = 290, level = 4, name = "WURMPLE" } }, 4, { deferPc = true })
  T.eq(deferred.location, "mod", version .. " claim: the animated path claims too")
  T.eq(deferred.pending, nil, version .. " claim: the animated path defers nothing")

  probe.calls = 0
  local roomy = catch(version, 3)
  T.eq(probe.calls, 0, version .. " a party with room never consults the hook")
  T.eq(roomy.location, "party", version .. " a party with room takes the catch")

  probe.answer = false
  local boxedRes, bs = catch(version, 6)
  T.eq(boxedRes.location, "pc", version .. " false: the catch goes to the PC")
  T.eq(boxed(bs), 1, version .. " false: the PC holds it")
  probe.answer = true

  pcPage, asked = nil, nil
  Ui.reset({ headless = false })
  newSession(version, 6)
  Battle._active, Battle._headless = true, false
  Battle._st = { session = session, enemy = { mon = { species = 290, name = "WURMPLE" } } }
  Battle.startPostCatchFlow({ success = true, location = "mod", firstTimeCaught = false,
    mon = { species = 290, name = "WURMPLE", nickname = "" } })
  T.eq(asked, nil, version .. " claim: no nickname question")
  T.eq(pcPage, nil, version .. " claim: no PC transfer page")
  T.eq(Battle._phase, "ending", version .. " claim: the catch ends")
  run.release()
end

local API3 = {
  ["mods/full_probe3/manifest.json"] = [[{"id":"full_probe3","name":"Full Probe 3","version":"1.0.0",
    "api":3,"games":["all"],"entry":"main.lua"}]],
  ["mods/full_probe3/main.lua"] = [[
    local mod = ...
    mod.exports.supported = mod:supports("hooks", "catch.party_full")
    mod.hooks:wrap("catch.party_full", function(next, ctx)
      mod.exports.species = ctx.mon.species
      return true
    end)
  ]],
}
for _, version in ipairs({ "firered", "emerald" }) do
  T.sdk.captureRuntime()
  local data = T.sdk.gen3Data()
  local loader = require("src.mods.Loader").new({ fs = T.sdk.memfs(API3), generation = 3, version = version })
  loader.game = { data = data }
  loader:load(data)
  T.eq(#loader.errors, 0, version .. " API 3 probe loads clean (" .. tostring(loader.errors[1]) .. ")")
  local p3 = loader.exports.full_probe3
  T.eq(p3.supported, true, version .. " API 3: mod:supports is true")
  local s = newSession(version, 6)
  local res = Catching.storeCaught(s, { species = 16, mon = { species = 16, level = 4, name = "PIDGEY" } }, 4)
  T.eq(res.location, "mod", version .. " API 3: a claim keeps the mon out of the PC")
  T.eq(p3.species, Records.id(16, "species", 3, data), version .. " API 3: ctx.mon.species is the portable id")
  T.sdk.restoreRuntime()
end

T.finish("catch.party_full Gen 3")
