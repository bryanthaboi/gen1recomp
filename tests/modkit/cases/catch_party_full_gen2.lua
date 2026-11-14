package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.modkit")
local UI = require("src.ui.gen2.BattleState")
local Boxes = require("src.core.gen2.Boxes")

local DATA = {
  pokemon = {
    RATTATA = { id = "RATTATA", index = 19, name = "RATTATA", catchRate = 255, baseExp = 51,
      baseStats = { hp = 30, attack = 56, defense = 35, speed = 72, specialAttack = 25, specialDefense = 35 },
      types = { "NORMAL", "NORMAL" }, growthRate = "GROWTH_MEDIUM_FAST", genderRatio = 127,
      levelMoves = {}, evolutions = {} },
    UNOWN = { id = "UNOWN", index = 201, name = "UNOWN", catchRate = 225, baseExp = 61,
      baseStats = { hp = 48, attack = 72, defense = 48, speed = 48, specialAttack = 72, specialDefense = 48 },
      types = { "PSYCHIC_TYPE", "PSYCHIC_TYPE" }, growthRate = "GROWTH_MEDIUM_FAST", genderRatio = 255,
      levelMoves = {}, evolutions = {} },
  },
  moves = {}, items = {}, type_chart = { types = {}, matchups = {} },
  text = { _BallSentToPCText = "{STRBUF} was\nsent to BILL's PC.{PROMPT}" },
}

local function newState(n)
  local save = { version = "crystal", party = {}, player = { name = "KRIS", id = 4242, gender = "female" },
    pokedex = { seen = {}, caught = {} } }
  for i = 1, n do save.party[i] = { species = "RATTATA", level = 5 } end
  local world = { tod = "DAY", maps = {}, map = { def = { id = "ROUTE_29", landmark = 2 } } }
  return setmetatable({
    save = save, queue = {}, battle = { timeOfDay = 1 },
    game = { save = save, data = DATA, world = world },
  }, { __index = UI })
end

local function count(state, kind)
  local n = 0
  for _, event in ipairs(state.queue) do if event.kind == kind then n = n + 1 end end
  return n
end

local function pcLine(state)
  for _, event in ipairs(state.queue) do
    if event.kind == "message" and tostring(event.text):find("BILL's PC", 1, true) then return true end
  end
  return false
end

local function boxed(save)
  local n = 0
  for i = 1, Boxes.NUM_BOXES do n = n + #Boxes.box(save, i) end
  return n
end

local function catch(n, species)
  local state = newState(n)
  local enemy = { species = species or "RATTATA", level = 4 }
  state:pushCaught(enemy, "POKE_BALL")
  return state, enemy
end

local vanilla = T.sdk.loadNone({ generation = 2 })
do
  local state, enemy = catch(6)
  T.eq(Boxes.box(state.save, state:currentBox())[1], enemy, "no mod: a 6/6 catch heads the box")
  T.check(pcLine(state), "no mod: the BILL's PC line is queued")
  T.eq(count(state, "ask-nickname"), 1, "no mod: the nickname is asked")
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

local run = T.sdk.loadMods({ "mods/full_probe" }, { fs = T.sdk.memfs(FIXTURE), generation = 2 })
T.eq(#run.errors, 0, "the probe loads clean (" .. tostring(run.errors[1]) .. ")")
local probe = run.loader.exports.full_probe

do
  local state, enemy = catch(6)
  T.eq(probe.calls, 1, "claim: the hook ran once")
  T.eq(#state.save.party, 6, "claim: the party is untouched")
  T.eq(boxed(state.save), 0, "claim: nothing is boxed")
  T.check(not pcLine(state), "claim: no BILL's PC line")
  T.eq(count(state, "ask-nickname"), 0, "claim: no nickname question")
  T.eq(count(state, "capture-clear"), 1, "claim: the capture still clears the field")
  T.eq(state.battle.boxFilled, nil, "claim: no box-full phone flag")
  T.eq(state.save.pokedex.caught.RATTATA, true, "claim: the dex still marks the catch")
  T.eq(probe.vanilla, false, "the vanilla link never claims")
  T.check(probe.ctx and probe.ctx.mon == enemy, "ctx.mon is the caught mon")
  T.check(probe.ctx and probe.ctx.battle == state, "ctx.battle is the battle screen")
  T.eq(probe.ctx and probe.ctx.name, "RATTATA", "ctx.name is the shown name")
  T.check(probe.ctx and probe.ctx.game == state.game, "ctx.game is the game")
  local last = probe.caught[#probe.caught]
  T.eq(last and last.destination, "mod", "pokemon.caught reports destination mod")
  T.check(last and last.mon == enemy, "pokemon.caught carries the claimed mon")
end

do
  local Unown = require("src.core.gen2.Unown")
  local state = catch(6, "UNOWN")
  T.eq(#Unown.dex(state.save), 0, "claim: a claimed Unown is not registered")
end

do
  probe.calls = 0
  local state = catch(3)
  T.eq(probe.calls, 0, "a party with room never consults the hook")
  T.eq(#state.save.party, 4, "a party with room takes the catch")
end

for _, answer in ipairs({ false, "nil" }) do
  probe.answer = answer ~= "nil" and answer or nil
  local state, enemy = catch(6)
  T.eq(Boxes.box(state.save, state:currentBox())[1], enemy, tostring(answer) .. ": the catch is boxed")
  T.check(pcLine(state), tostring(answer) .. ": the BILL's PC line is queued")
  local last = probe.caught[#probe.caught]
  T.eq(last and last.destination, "box", tostring(answer) .. ": pokemon.caught reports box")
end
run.release()

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
local loader = require("src.mods.Loader").new({ fs = T.sdk.memfs(API3), generation = 2, version = "crystal" })
T.sdk.captureRuntime()
local state = newState(6)
loader.game = state.game
loader:load(require("tests.modkit.fixtures").fresh())
T.eq(#loader.errors, 0, "API 3 probe loads clean (" .. tostring(loader.errors[1]) .. ")")
local p3 = loader.exports.full_probe3
T.eq(p3.supported, true, "API 3: mod:supports is true on Gen 2")
state:pushCaught({ species = "RATTATA", level = 4 }, "POKE_BALL")
T.eq(boxed(state.save), 0, "API 3: a claim keeps the mon out of the box")
T.eq(p3.species, require("src.mods.UnifiedRecords").id("RATTATA", "species", 2, DATA),
  "API 3: ctx.mon.species is the portable id")
T.sdk.restoreRuntime()

T.finish("catch.party_full Gen 2")
