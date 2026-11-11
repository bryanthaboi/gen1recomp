package.path = "./?.lua;./?/init.lua;" .. package.path
_G.love = _G.love or require("tests.love_stub")

local T = require("tests.modkit")
local Battle = require("src.core.game3.battle.init")
local Ui = require("src.core.game3.battle.ui")
local Dex = require("src.ui.game3.rse.pokedex")
local Pokemon = require("src.core.game3.pokemon")
local Text = require("src.core.game3.battle.battle_text")
local Pal = require("src.core.game3.pal_fade")
local UnifiedCallbacks = require("src.mods.UnifiedCallbacks")
local Records = require("src.mods.UnifiedRecords")

Text.get = function(_, args) return args and args.opponentMon1 or "caught" end
Pokemon.name = function() return "WURMPLE" end
Pokemon.speciesFromNational = function() return 290 end
Pokemon.picSpecies = function(sp) return sp end
Pokemon.frontPic = function() return { image = {} } end

local dexOpts, registration, answer, namingOpts, gave, pcName
Dex.showCaughtMon = function(_, opts) dexOpts = opts end
Ui.askYesNo = function(_, cb) answer = cb end
package.loaded["src.ui.game3.naming"] = {
  open = function(opts) namingOpts = opts end,
  isOpen = function() return namingOpts ~= nil end,
  monTitle = function(name) return name end,
}
package.loaded["src.ui.game3.pokedex"] = { showRegistration = function(_, opts) registration = opts end }
package.loaded["src.core.game3.battle.catching"] = {
  givePending = function(_, res) gave = res.mon; res.pending = nil; return true end,
}
local Storage = require("src.core.game3.storage")
Storage.pcTransferMessage = function(_, name) pcName = name; return "transfer" end

local function begin(version, first, location, species)
  dexOpts, registration, answer, namingOpts, gave, pcName = nil, nil, nil, nil, nil, nil
  Ui.reset({ headless = false })
  species = species or 290
  local mon = { species = species, name = "WURMPLE", nickname = "", personality = 0x10001, otId = 123, otSecretId = 0 }
  local enemyMon = { species = species, name = "WURMPLE", personality = 0x10001, otId = 0, otSecretId = 0 }
  local session = { version = version, party = {}, flags = {}, vars = {} }
  package.loaded["src.core.game3.runtime"] = { getSession = function() return session end }
  Battle._active, Battle._headless = true, false
  Battle._st = { session = session, enemy = { mon = enemyMon } }
  local res = { mon = mon, firstTimeCaught = first, location = location or "party", pending = location == "pc" }
  Battle.startPostCatchFlow(res)
  return mon, res
end

local function settle()
  Battle._headless = true
  for _ = 1, 60 do Battle.update(1 / 60, {}) end
  Battle._headless = false
end

local function leaveDex(version)
  if version == "emerald" then
    local sprite = { img = {}, x = 92, y = 80, x2 = 0, y2 = 0 }
    Dex.Host._s = { pal = Pal.new(), caught = { dexNum = 265, personality = dexOpts.personality,
      otId = dexOpts.otId, otSecretId = dexOpts.otSecretId, shiny = dexOpts.shiny,
      mon = sprite, onDone = dexOpts.onDone } }
    Dex.tasks.caughtExit(Dex.Host._s)
  else
    registration.onDone()
  end
  settle()
end

local FIXTURE = {
  ["mods/name_probe/manifest.json"] = [[{"id":"name_probe","name":"Name Probe","version":"1.0.0",
    "api":2,"games":["all"],"entry":"main.lua"}]],
  ["mods/name_probe/main.lua"] = [[
    local mod = ...
    mod.exports.calls = 0
    mod.exports.nickname = "SPIKE"
    mod.hooks:wrap("catch.nickname", function(next, mon, ctx)
      mod.exports.calls = mod.exports.calls + 1
      mod.exports.mon, mod.exports.ctx = mon, ctx
      if mod.exports.nickname ~= nil then return mod.exports.nickname end
      return next(mon, ctx)
    end)
  ]],
}

for gen = 1, 3 do
  T.eq(UnifiedCallbacks.supports("hooks", "catch.nickname", gen), true, "catch.nickname is supported in Gen " .. gen)
end

for _, version in ipairs({ "firered", "emerald" }) do
  local vanilla = T.sdk.loadNone({ generation = 3, data = T.sdk.gen3Data() })
  begin(version, false)
  T.eq(Battle._phase, "catch_nickname_prompt", version .. " no mod: the question is asked")
  T.check(answer ~= nil, version .. " no mod: the yes/no is open")
  answer(true)
  namingOpts.onDone("BUG")
  vanilla.release()

  local run = T.sdk.loadMods({ "mods/name_probe" },
    { fs = T.sdk.memfs(FIXTURE), generation = 3, data = T.sdk.gen3Data() })
  T.eq(#run.errors, 0, version .. " probe loads clean (" .. tostring(run.errors[1]) .. ")")
  local probe = run.loader.exports.name_probe

  local mon = begin(version, false)
  T.eq(answer, nil, version .. " SPIKE: no yes/no")
  T.eq(Battle._phase, "ending", version .. " SPIKE: the party catch ends")
  T.eq(mon.nickname, "SPIKE", version .. " SPIKE: the mon is named")
  T.eq(probe.calls, 1, version .. " SPIKE: the hook ran once")
  T.check(probe.mon == mon, version .. " SPIKE: the hook got the caught mon")
  T.eq(probe.ctx and probe.ctx.name, "WURMPLE", version .. " SPIKE: ctx.name is the shown name")
  T.eq(probe.ctx and probe.ctx.speciesId, 290, version .. " SPIKE: ctx.speciesId is numeric")
  T.eq(type(probe.ctx and probe.ctx.species), "string", version .. " SPIKE: ctx.species is a name")
  T.check(probe.ctx and probe.ctx.battle == Battle._st, version .. " SPIKE: ctx.battle is the battle")

  local pcMon, pcRes = begin(version, false, "pc")
  T.eq(answer, nil, version .. " PC: no yes/no")
  T.eq(gave, pcMon, version .. " PC: the named mon is deposited")
  T.eq(pcMon.nickname, "SPIKE", version .. " PC: the deposited mon is named")
  T.eq(Battle._phase, "catch_pc_msg", version .. " PC: the transfer page shows")
  T.eq(pcName, "SPIKE", version .. " PC: the transfer page names SPIKE")
  T.eq(pcRes.pending, nil, version .. " PC: the pending mon was given")

  probe.calls = 0
  local first = begin(version, true)
  T.eq(probe.calls, 0, version .. " first catch: the hook waits for the dex page")
  T.eq(Battle._phase, "pokedex_reg", version .. " first catch: the dex page is up")
  leaveDex(version)
  T.eq(probe.calls, 1, version .. " first catch: the hook runs after the dex page")
  T.eq(answer, nil, version .. " first catch: no yes/no")
  T.eq(first.nickname, "SPIKE", version .. " first catch: the mon is named")
  T.check(Battle._phase == "ending" or Battle._phase == nil, version .. " first catch: the catch ends")

  probe.nickname = false
  local kept = begin(version, false)
  T.eq(answer, nil, version .. " false: no yes/no")
  T.eq(Battle._phase, "ending", version .. " false: the catch ends")
  T.eq(kept.nickname, "", version .. " false: the species name stays")
  local keptPc = begin(version, false, "pc")
  T.eq(pcName, "WURMPLE", version .. " false: the transfer page names the species")
  T.eq(keptPc.nickname, "", version .. " false: the boxed mon keeps the species name")

  probe.nickname = "TOOLONGFORTHEGRID"
  T.eq(begin(version, false).nickname, "TOOLONGFOR", version .. " a long name is clipped to ten")
  probe.nickname = ("\195\137"):rep(12)
  T.eq(begin(version, false).nickname, ("\195\137"):rep(10), version .. " the clip counts characters")
  probe.nickname = ""
  local blank = begin(version, false)
  T.eq(answer, nil, version .. " empty string: no yes/no")
  T.eq(blank.nickname, "", version .. " empty string: nothing is named")

  probe.nickname = nil
  local asked = begin(version, false)
  T.eq(Battle._phase, "catch_nickname_prompt", version .. " falling through asks as usual")
  answer(true)
  namingOpts.onDone("BUG")
  T.eq(asked.nickname, "BUG", version .. " the naming screen still names the mon")
  T.eq(Battle._phase, "ending", version .. " and the catch ends")
  run.release()
end

local API3 = {
  ["mods/name_probe3/manifest.json"] = [[{"id":"name_probe3","name":"Name Probe 3","version":"1.0.0",
    "api":3,"games":["all"],"entry":"main.lua"}]],
  ["mods/name_probe3/main.lua"] = [[
    local mod = ...
    mod.exports.supported = mod:supports("hooks", "catch.nickname")
    mod.hooks:wrap("catch.nickname", function(next, mon, ctx)
      mod.exports.species, mod.exports.name, mod.exports.ctxSpecies = mon.species, ctx.name, ctx.species
      return "SPIKE"
    end)
  ]],
}
for _, version in ipairs({ "firered", "emerald" }) do
  T.sdk.captureRuntime()
  local data = T.sdk.gen3Data()
  local loader = require("src.mods.Loader").new({ fs = T.sdk.memfs(API3), generation = 3,
    version = version })
  loader.game = { data = data }
  loader:load(data)
  T.eq(#loader.errors, 0, version .. " API 3 probe loads clean (" .. tostring(loader.errors[1]) .. ")")
  local p3 = loader.exports.name_probe3
  T.eq(p3.supported, true, version .. " API 3: mod:supports is true")
  local mon = begin(version, false, "party", 16)
  T.eq(p3.species, Records.id(16, "species", 3, data), version .. " API 3: mon.species is the portable id")
  T.eq(type(p3.species), "string", version .. " API 3: the portable id is not the native number")
  T.eq(p3.name, "WURMPLE", version .. " API 3: ctx.name is the shown name")
  T.eq(mon.nickname, "SPIKE", version .. " API 3: a string still names the mon")
  T.eq(Battle._phase, "ending", version .. " API 3: no question")
  T.sdk.restoreRuntime()
end

T.finish("catch.nickname Gen 3")
