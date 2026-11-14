package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.modkit")
require("src.core.GameVersion").set("crystal")
local World = require("src.world.gen2.World")
local Vm = require("src.script.gen2.Vm")
local Events = require("src.world.gen2.Events")
local Specials = require("src.script.gen2.Specials")
local PrizeMenu = require("src.ui.gen2.PrizeMenu")
local Breeding = require("src.core.gen2.Breeding")
local UnifiedCallbacks = require("src.mods.UnifiedCallbacks")

local function species(id, index, eggSteps)
  return { id = id, index = index, name = id, catchRate = 45, baseExp = 50,
    baseStats = { hp = 40, attack = 40, defense = 40, speed = 40, specialAttack = 40, specialDefense = 40 },
    types = { "NORMAL", "NORMAL" }, growthRate = "GROWTH_MEDIUM_FAST", genderRatio = 127,
    eggGroups = { "EGG_GROUND", "EGG_GROUND" }, eggSteps = eggSteps or 20,
    levelMoves = { { level = 1, move = "TACKLE" } }, evolutions = {} }
end

local DATA = {
  pokemon = {
    growthRates = { GROWTH_MEDIUM_FAST = { numerator = 1, denominator = 1, squared = 0, linear = 0, constant = 0 } },
    RATTATA = species("RATTATA", 19), EEVEE = species("EEVEE", 133), TOGEPI = species("TOGEPI", 175, 10),
    SHUCKLE = species("SHUCKLE", 213), PICHU = species("PICHU", 172, 10), SPEAROW = species("SPEAROW", 21),
  },
  moves = { TACKLE = { id = "TACKLE", pp = 35 } }, items = {},
}

local function newSave(n)
  local save = { version = "gold", party = {}, boxes = {}, player = { name = "KRIS", id = 4242 },
    pokedex = { seen = {}, caught = {} } }
  for i = 1, n or 0 do save.party[i] = { species = "RATTATA", level = 5 } end
  return save
end

local function newWorld(save)
  local game = { data = DATA, save = save or newSave() }
  local world = setmetatable({ game = game }, { __index = World })
  game.world = world
  return world, game
end

do
  local seen
  local game = { data = T.fixtures.load(), save = require("src.core.SaveData").newGame(),
    stack = { push = function() end },
    mods = { events = { emit = function(_, name, gift)
      if name == "pokemon.before_give" then seen = gift end
    end } } }
  require("src.script.Commands").give_pokemon({ game = game, save = game.save }, "FIXMON_A", 5)
  T.eq(seen and seen.isEgg, false, "Gen 1: a script gift carries isEgg = false")
end

for _, gen in ipairs({ 1, 2, 3 }) do
  T.eq(UnifiedCallbacks.supports("events", "pokemon.before_give", gen), true,
    "pokemon.before_give is supported in Gen " .. gen)
end

local vanilla = T.sdk.loadNone({ generation = 2 })
do
  local world, game = newWorld()
  local mon, named = world:givePoke(133, 20, 0)
  T.eq(mon and mon.species, "EEVEE", "no mod: givepoke gives the script's species")
  T.eq(named, false, "no mod: a wild-arm gift is not pre-named")
  T.eq(game.save.party[1], mon, "no mod: the gift joins the party")
end
vanilla.release()

local FIXTURE = {
  ["mods/give_probe/manifest.json"] = [[{"id":"give_probe","name":"Give Probe","version":"1.0.0",
    "api":2,"games":["all"],"entry":"main.lua"}]],
  ["mods/give_probe/main.lua"] = [[
    local mod = ...
    local e = mod.exports
    e.gifts = {}
    mod.events:on("pokemon.before_give", function(gift)
      e.gifts[#e.gifts + 1] = { species = gift.species, level = gift.level, isEgg = gift.isEgg,
        nickname = gift.nickname, ctx = gift.ctx }
      if e.species then gift.species = e.species end
      if e.level then gift.level = e.level end
      if e.nickname ~= nil then gift.nickname = e.nickname end
    end)
  ]],
}

local run = T.sdk.loadMods({ "mods/give_probe" }, { fs = T.sdk.memfs(FIXTURE), generation = 2 })
T.eq(#run.errors, 0, "the probe loads clean (" .. tostring(run.errors[1]) .. ")")
local probe = run.loader.exports.give_probe
local function reset(species, level, nickname)
  probe.gifts, probe.species, probe.level, probe.nickname = {}, species, level, nickname
end
local function last() return probe.gifts[#probe.gifts] end

do
  reset("PICHU", 30)
  local world, game = newWorld()
  local mon, named = world:givePoke(133, 20, 0)
  T.eq(#probe.gifts, 1, "givepoke: the event fires once")
  T.eq(last().species, "EEVEE", "givepoke: gift.species is the native species")
  T.eq(last().level, 20, "givepoke: gift.level is the script's level")
  T.eq(last().isEgg, false, "givepoke: gift.isEgg is false")
  T.eq(last().nickname, nil, "givepoke: a wild-arm gift has no nickname")
  T.check(last().ctx and last().ctx.game == game, "givepoke: ctx.game is the game")
  T.check(last().ctx and last().ctx.world == world, "givepoke: ctx.world is the world")
  T.eq(mon and mon.species, "PICHU", "givepoke: the species rewrite holds")
  T.eq(mon and mon.level, 30, "givepoke: the level rewrite holds")
  T.eq(named, false, "givepoke: no nickname, no skip")
  T.eq(game.save.pokedex.caught.PICHU, true, "givepoke: the dex marks the given species")
  T.eq(game.save.pokedex.caught.EEVEE, nil, "givepoke: the dex leaves the script's species")
end

do
  reset(nil, nil, "SPIKE")
  local world = newWorld()
  local mon, named = world:givePoke(133, 20, 0)
  T.eq(mon.nickname, "SPIKE", "givepoke: gift.nickname names the mon")
  T.eq(named, true, "givepoke: a mod nickname skips the prompt")
  reset(nil, nil, "TOOLONGFORTHEGRID")
  T.eq(newWorld():givePoke(133, 20, 0).nickname, "TOOLONGFOR", "givepoke: a long name is clipped to ten")
  reset("NOT_A_MON", "x")
  local kept = newWorld():givePoke(133, 20, 0)
  T.eq(kept.species, "EEVEE", "givepoke: an unknown species keeps the script's")
  T.eq(kept.level, 20, "givepoke: a non-number level keeps the script's")
end

do
  reset()
  local mon = newWorld():givePoke(21, 10, 0, { nickname = "KENYA", otName = "RANDY" })
  T.eq(last().nickname, "KENYA", "trainer arm: gift.nickname carries the script's name")
  T.eq(mon.nickname, "KENYA", "trainer arm: the script's name stands")
end

local function runGive(nickname)
  reset(nil, nil, nickname)
  local world = newWorld()
  local asked = 0
  local vm = Vm.new({ generation = 2,
    ["s:eevee"] = { { op = "givepoke", species = 133, level = 20, item = 0, trainer = 0 }, { op = "end" } },
  }, {}, Events.new(), {
    givePoke = function(...) return world:givePoke(...) end,
    showText = function(_, onDone) onDone() end,
    yesorno = function(onChoose) asked = asked + 1; onChoose(false) end,
  })
  vm:start("s:eevee")
  for _ = 1, 20 do vm:update() end
  return asked, world.game.save.party[1]
end

do
  local asked, mon = runGive(nil)
  T.eq(asked, 1, "Vm givepoke: no mod nickname, the yes/no is asked")
  T.eq(mon and mon.species, "EEVEE", "Vm givepoke: the gift is given")
  asked, mon = runGive("SPIKE")
  T.eq(asked, 0, "Vm givepoke: a mod nickname skips the yes/no")
  T.eq(mon and mon.nickname, "SPIKE", "Vm givepoke: the mod nickname names the gift")
end

do
  reset(nil, 30)
  local world, game = newWorld()
  local record = game.save
  local vm = { scriptVar = 0, specials = {
    world = world,
    save = function() return record end,
    data = function() return DATA end,
    party = function() return record.party end,
  } }
  Specials.HANDLERS.GiveShuckle(vm)
  local mon = record.party[1]
  T.eq(last() and last().species, "SHUCKLE", "GiveShuckle: the event fires with SHUCKLE")
  T.eq(last() and last().level, 15, "GiveShuckle: at level 15")
  T.eq(last() and last().nickname, "SHUCKIE", "GiveShuckle: gift.nickname is SHUCKIE")
  T.eq(last() and last().isEgg, false, "GiveShuckle: not an egg")
  T.check(last() and last().ctx.runner == vm, "GiveShuckle: ctx.runner is the script")
  T.eq(mon and mon.level, 30, "GiveShuckle: the level rewrite holds")
  T.eq(mon and mon.nickname, "SHUCKIE", "GiveShuckle: SHUCKIE stays when the mod leaves it")
end

do
  reset("PICHU")
  local save = newSave(1)
  save.player.coins = 9999
  local game = { data = DATA, save = save }
  local result = PrizeMenu.buy(save, { kind = "mon" }, { id = "RATTATA", level = 15, cost = 100 }, DATA, nil, game)
  T.eq(result, "ok", "prize mon: the purchase goes through")
  T.eq(last() and last().species, "RATTATA", "prize mon: the event fires with the prize")
  T.check(last() and last().ctx.game == game, "prize mon: ctx.game is the game")
  T.eq(save.party[2] and save.party[2].species, "PICHU", "prize mon: the species rewrite holds")
  T.eq(save.pokedex.caught.PICHU, true, "prize mon: the dex marks the given species")
end

do
  reset("RATTATA", nil, "SPIKE")
  local world, game = newWorld(newSave(1))
  T.eq(world:giveEgg(175, 5), true, "giveegg: the egg is given")
  local egg = game.save.party[2]
  T.eq(last() and last().species, "TOGEPI", "giveegg: gift.species is the egg's species")
  T.eq(last() and last().isEgg, true, "giveegg: gift.isEgg is true")
  T.eq(last() and last().level, 5, "giveegg: gift.level is the egg's level")
  T.eq(egg and egg.species, "RATTATA", "giveegg: the species rewrite holds")
  T.eq(egg and egg.isEgg, true, "giveegg: it is still an egg")
  T.eq(egg and egg.nickname, "EGG", "giveegg: a mod nickname never names an egg")
  T.eq(egg and egg.hp, 0, "giveegg: the egg carries no HP")
end

do
  reset("RATTATA")
  local save = newSave(1)
  local dc = Breeding.dayCare(save)
  local egg = { species = "PICHU", level = 5, isEgg = true, nickname = "EGG", hp = 0, ot = "KRIS", otId = 4242,
    dvs = { attack = 2, defense = 10, speed = 10, special = 10 }, eggSteps = 7,
    moves = { { id = "CHARM", pp = 20, maxPp = 20 } } }
  dc.hasEgg, dc.egg = true, egg
  local ok, given = Breeding.collectEgg(DATA, save, {})
  T.eq(ok, true, "Day-Care: the egg is collected")
  T.eq(last() and last().species, "PICHU", "Day-Care: gift.species is the egg's species")
  T.eq(last() and last().isEgg, true, "Day-Care: gift.isEgg is true")
  T.eq(given and given.species, "RATTATA", "Day-Care: the species rewrite rebuilds the egg")
  T.eq(given and given.isEgg, true, "Day-Care: the rebuilt record is an egg")
  T.eq(given and given.otId, 4242, "Day-Care: the rebuilt egg keeps its OT id")
  T.eq(save.party[2], given, "Day-Care: the rebuilt egg joins the party")
  local d = given and given.dvs or {}
  T.eq(table.concat({ d.attack, d.defense, d.speed, d.special }, "/"), "2/10/10/10",
    "Day-Care: a species rewrite keeps the inherited DVs")
  T.eq(given and given.eggSteps, 20, "Day-Care: a species rewrite takes the new species' egg cycles")
  T.eq(given and given.moves[1] and given.moves[1].id, "TACKLE",
    "Day-Care: a species rewrite takes the new species' moves")
  reset(nil, 6)
  local saveL = newSave(1)
  local dcL = Breeding.dayCare(saveL)
  dcL.hasEgg, dcL.egg = true, egg
  local _, lv = Breeding.collectEgg(DATA, saveL, {})
  local dl = lv and lv.dvs or {}
  T.eq(lv and lv.level, 6, "Day-Care: the level rewrite holds")
  T.eq(table.concat({ dl.attack, dl.defense, dl.speed, dl.special }, "/"), "2/10/10/10",
    "Day-Care: a level rewrite keeps the inherited DVs")
  T.eq(lv and lv.eggSteps, 7, "Day-Care: a level rewrite keeps the egg counter")
  T.eq(lv and #lv.moves, 1, "Day-Care: a level rewrite keeps the egg's move count")
  T.eq(lv and lv.moves[1] and lv.moves[1].id, "CHARM", "Day-Care: a level rewrite keeps the egg moves")
  reset()
  local save2 = newSave(1)
  local dc2 = Breeding.dayCare(save2)
  dc2.hasEgg, dc2.egg = true, egg
  local _, same = Breeding.collectEgg(DATA, save2, {})
  T.check(same == egg, "Day-Care: an unchanged gift hands over the built record")
end

local function oddEgg(species, level)
  reset(species, level)
  local save = newSave(1)
  local vm = { scriptVar = 0, specials = {
    save = function() return save end,
    data = function() return DATA end,
    party = function() return save.party end,
    itemIndex = function() return 129 end,
    takeItem = function() return true end,
  } }
  local prior = Specials.random
  Specials.random = function(n) if n == 0x10000 then return 1 end return prior(n) end
  local okOdd, oddErr = pcall(Specials.HANDLERS.GiveOddEgg, vm)
  Specials.random = prior
  return okOdd, oddErr, save.party[2]
end

local function dvKey(mon)
  local d = mon and mon.dvs or {}
  return table.concat({ tostring(d.attack), tostring(d.defense), tostring(d.speed), tostring(d.special) }, "/")
end

local function moveKey(mon)
  local out = {}
  for i, m in ipairs(mon and mon.moves or {}) do out[i] = tostring(type(m) == "table" and m.id or m) end
  return table.concat(out, ",")
end

do
  local _, _, base = oddEgg(nil, nil)
  local okOdd, oddErr, egg = oddEgg("RATTATA", nil)
  T.check(okOdd, "Odd Egg: the special runs (" .. tostring(oddErr) .. ")")
  T.eq(last() and last().isEgg, true, "Odd Egg: gift.isEgg is true")
  T.eq(last() and last().species, "PICHU", "Odd Egg: gift.species is the egg's species")
  T.eq(egg and egg.species, "RATTATA", "Odd Egg: the species rewrite holds")
  T.eq(egg and egg.isEgg, true, "Odd Egg: it is still an egg")
  T.eq(dvKey(egg), dvKey(base), "Odd Egg: a species rewrite keeps the table DVs")
  T.eq(egg and egg.ot, base and base.ot, "Odd Egg: a species rewrite keeps the ODD trainer")
  local _, _, lv = oddEgg(nil, 6)
  T.eq(lv and lv.level, 6, "Odd Egg: the level rewrite holds")
  T.eq(dvKey(lv), dvKey(base), "Odd Egg: a level rewrite keeps the table DVs")
  T.eq(moveKey(lv), moveKey(base), "Odd Egg: a level rewrite keeps DIZZY_PUNCH")
  T.eq(lv and lv.eggSteps, base and base.eggSteps, "Odd Egg: a level rewrite keeps the egg counter")
end
run.release()

local API3 = {
  ["mods/give_probe3/manifest.json"] = [[{"id":"give_probe3","name":"Give Probe 3","version":"1.0.0",
    "api":3,"games":["all"],"entry":"main.lua"}]],
  ["mods/give_probe3/main.lua"] = [[
    local mod = ...
    mod.exports.supported = mod:supports("events", "pokemon.before_give")
    mod.events:on("pokemon.before_give", function(gift)
      mod.exports.species, mod.exports.isEgg = gift.species, gift.isEgg
      gift.species = mod.exports.target
      gift.nickname = "SPIKE"
    end)
  ]],
}
local loader = require("src.mods.Loader").new({ fs = T.sdk.memfs(API3), generation = 2, version = "crystal" })
T.sdk.captureRuntime()
local world, game = newWorld()
loader.game = game
loader:load(DATA)
T.eq(#loader.errors, 0, "API 3 probe loads clean (" .. tostring(loader.errors[1]) .. ")")
local p3 = loader.exports.give_probe3
local Records = require("src.mods.UnifiedRecords")
p3.target = Records.id("PICHU", "species", 2, DATA)
T.eq(p3.supported, true, "API 3: mod:supports is true on Gen 2")
local mon = world:givePoke(133, 20, 0)
T.eq(p3.species, Records.id("EEVEE", "species", 2, DATA), "API 3: gift.species is the portable id")
T.eq(p3.isEgg, false, "API 3: gift.isEgg is false")
T.eq(mon and mon.species, "PICHU", "API 3: a portable species rewrite lands as the native one")
T.eq(mon and mon.nickname, "SPIKE", "API 3: gift.nickname names the mon")
T.sdk.restoreRuntime()

T.finish("pokemon.before_give Gen 2")
