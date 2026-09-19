package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local GameVersion = require("src.core.GameVersion")
local Manifest = require("src.mods.Manifest")
local ModTargets = require("src.mods.ModTargets")
local Schemas = require("src.mods.Schemas")

T.eq(GameVersion.generation("firered"), 3, "FireRed is Gen 3")
T.eq(table.concat(ModTargets.expand("gen3"), ","), "firered",
  "gen3 is every Gen 3 game")

local function manifest(extra)
  local raw = { id = "fix", name = "Fixture", version = "1.0.0",
                entry = "main.lua", api = 2 }
  for key, value in pairs(extra or {}) do raw[key] = value end
  return Manifest.validate(raw, "mods/fix")
end

T.check(ModTargets.supports(manifest({ games = { "gen3" } }), "firered"),
  "games = [gen3] claims FireRed")
T.check(ModTargets.supports(manifest({ games = { "firered" } }), "firered"),
  "games = [firered] claims FireRed")
T.check(not ModTargets.supports(manifest(), "firered"),
  "a manifest that says nothing is not a FireRed mod")
T.check(not ModTargets.supports(manifest({ gen2compat = true }), "firered"),
  "and gen2compat is not a Gen 3 claim")
T.eq(manifest({ games = { "gen3" } }).gen2compat, false,
  "a Gen 3 claim is not a Gen 2 claim either")

local ROUTED = {
  pokemon = "gen3Pokemon", moves = "gen3Moves", items = "gen3Items",
  encounters = "gen3Encounters", trainers = "gen3Trainers",
  text = "gen3Text", map_scripts = "gen3Scripts",
}

for name, path in pairs(ROUTED) do
  local spec = Schemas.REGISTRIES[name]
  T.check(spec ~= nil, "catalog still has registry: " .. name)
  T.eq(Schemas.targetFor(name, spec, 3), path,
    "available under Gen 3 at its Gen 3 path: " .. name)
  T.eq(Schemas.gatedFor(name, 3), false, "not gated under Gen 3: " .. name)
  T.eq(Schemas.targetFor(name, spec, 1), spec.target,
    "and Gen 1 is untouched by the routing: " .. name)
end

for _, name in ipairs({ "maps", "commands", "strings" }) do
  local spec = Schemas.REGISTRIES[name]
  T.eq(Schemas.targetFor(name, spec, 3), spec.target,
    "available under Gen 3 at its shared path: " .. name)
end

for _, name in ipairs({ "tilesets", "sprites", "type_chart", "statuses",
                        "move_effects", "balls", "ai_classes", "growth_rates",
                        "evolution_methods", "transitions", "rulesets",
                        "field", "text_pointers", "link_fields", "screens",
                        "tokens", "music", "sfx", "cries", "map_songs",
                        "audio", "font", "palettes", "icons", "battle_anims",
                        "held_items", "phone_contacts", "decorations",
                        "apricorns", "landmarks", "radio_channels",
                        "rom_text" }) do
  local spec = Schemas.REGISTRIES[name]
  T.check(spec ~= nil, "catalog still has registry: " .. name)
  T.eq(Schemas.targetFor(name, spec, 3), nil,
    "gated registry has no Gen 3 target: " .. name)
  T.eq(Schemas.gatedFor(name, 3), true, "gated under Gen 3: " .. name)
end

for name in pairs(Schemas.GEN3) do
  T.check(Schemas.REGISTRIES[name] ~= nil,
    "Schemas.GEN3 names a real registry: " .. name)
end

do
  local claimed = {}
  for name, spec in pairs(Schemas.REGISTRIES) do
    local path = Schemas.targetFor(name, spec, 3)
    if path then
      T.check(claimed[path] == nil or claimed[path] == name,
        ("two registries share one Gen 3 path (%s): %s and %s")
          :format(path, tostring(claimed[path]), name))
      claimed[path] = name
    end
  end
end

do
  local spec = Schemas.REGISTRIES.pokemon
  local gen3 = Schemas.shapeFor("pokemon", spec, 3)
  T.check(gen3 ~= spec, "Gen 3 gets a derived spec")
  T.eq(Schemas.shapeFor("pokemon", gen3, 3), gen3,
    "resolving a derived spec again is a no-op")
  T.check(gen3.fields.learnset ~= nil and gen3.fields.baseStats.fields.specialAttack ~= nil,
    "the Gen 3 species shape is folded onto `fields`")
  T.check(gen3.fields.eggMoves ~= nil,
    "the Gen 3 species shape carries the gEggMoves field")
  T.eq(gen3.gen3Fields, nil, "the gen3* keys are gone from the derived spec")
  T.eq(gen3.gen2Fields, nil, "and so are the gen2* keys")
  T.eq(gen3.target, "gen3Pokemon", "the derived spec carries the routed path")
  T.check(gen3.baseAt ~= nil and gen3.baseIds ~= nil and gen3.write ~= nil,
    "and reaches the numeric tables through baseAt/baseIds/write")
  local gen2 = Schemas.shapeFor("pokemon", spec, 2)
  T.eq(gen2.gen3Fields, nil, "a Gen 2 derived spec carries no gen3* keys")
  T.eq(gen2.baseAt, Schemas.REGISTRIES.pokemon.gen2BaseAt,
    "and keeps its own Gen 2 baseAt")
  local scripts = Schemas.shapeFor("map_scripts", Schemas.REGISTRIES.map_scripts, 3)
  T.eq(scripts.semantics, "record",
    "Gen 3 scripts are whole VM row lists, not compose chains")
end

for name, spec in pairs(Schemas.REGISTRIES) do
  if Schemas.hasGen3Shape(spec) then
    T.eq(Schemas.gatedFor(name, 3), false,
      "a registry with a Gen 3 shape is not gated: " .. name)
  end
end

do
  local G3 = Schemas.gen3View
  T.eq(G3.idOf("NIDORAN\226\153\128"), "NIDORAN_F", "female glyph id")
  T.eq(G3.idOf("NIDORAN\226\153\130"), "NIDORAN_M", "male glyph id")
  T.eq(G3.idOf("FARFETCH'D"), "FARFETCHD", "apostrophes drop")
  T.eq(G3.idOf("MR. MIME"), "MR_MIME", "punctuation folds to one underscore")
  T.eq(G3.idOf("HO-OH"), "HO_OH", "hyphens fold")
  T.eq(G3.idOf("POK\195\169 BALL"), "POKE_BALL", "the accented E folds")
  T.eq(G3.idOf("??????????"), nil, "a placeholder name has no id")
  local ir = G3.textIr("A\nB\n\nC")
  local kinds = {}
  for i, token in ipairs(ir) do kinds[i] = token.t end
  T.eq(table.concat(kinds, ","), "text,nl,text,para,text,eos",
    "a plain string becomes the VM's text IR")
end

local Catalog = T.catalog

local function isGen3Site(path)
  return path:match("game3") ~= nil or path:match("Game3") ~= nil
    or path:match("Gen3") ~= nil
end

local function isFacadeSite(path)
  return path:match("Gen3Compat") ~= nil or path:match("WorldAPI") ~= nil
    or path:match("BattleAPI") ~= nil
end

local GEN3_EVENTS = {
  "game.ready", "save.created", "save.loaded", "save.loading", "save.writing",
  "map.entered", "map.exited", "map.reloaded", "player.warped",
  "world.stepped", "world.interacted", "world.npc_spawned",
  "world.blacked_out", "world.block_replaced", "world.boulder_moved",
  "world.object_toggled",
  "flag.changed", "script.started", "script.ended",
  "pokemon.before_give", "pokemon.evolved",
  "battle.started", "battle.ended", "battle.turn_started", "battle.turn_ended",
  "battle.move_used", "battle.damage_dealt", "battle.status_inflicted",
  "battle.fainted", "battle.battler_switched", "battle.exp_gained",
  "battle.ball_thrown", "pokemon.caught", "pokemon.level_up",
  "pokemon.move_learned", "world.trainer_engaged",
  "intro.oak_speech.started", "intro.oak_speech.step",
  "intro.oak_speech.answered", "intro.oak_speech.finished",
}

local GEN3_HOOKS = {
  "encounter.roll", "encounter.species", "encounter.table",
  "movement.collision", "warp.destination", "world.talk", "item.use",
  "script.command", "save.write", "save.new_game",
  "ui.start_menu.items", "pokemon.sprite",
  "input.step", "input.key", "input.gamepad", "input.wheel", "render.hud",
  "trainer.party", "catch.rate", "exp.gain", "evolution.check",
  "battle.damage", "battle.crit", "battle.accuracy", "battle.charge_required",
  "battle.run", "battle.turn_order", "battle.enemy_action",
}

local function assertShared(name, sites, kind)
  local gen3, other = 0, 0
  for _, path in ipairs(sites) do
    if isGen3Site(path) then gen3 = gen3 + 1 else other = other + 1 end
  end
  T.check(gen3 > 0, ("FireRed raises the %s: %s"):format(kind, name))
  T.check(other > 0,
    ("the %s %s is shared, not a Gen 3 invention (no Gen 1 or Gen 2 site)")
      :format(kind, name))
end

for _, name in ipairs(GEN3_EVENTS) do
  assertShared(name, Catalog.eventSites(name), "event")
end
for _, name in ipairs(GEN3_HOOKS) do
  assertShared(name, Catalog.hookSites(name), "hook")
end

local function assertListed(names, catalogNames, sites, kind)
  local listed = {}
  for _, name in ipairs(names) do listed[name] = true end
  for _, name in ipairs(catalogNames) do
    if not Catalog.isModEvent(name) then
      local gen3, other = false, false
      for _, path in ipairs(sites(name)) do
        if isGen3Site(path) then gen3 = true else other = true end
      end
      if gen3 then
        T.check(other,
          ("%s %s is raised only from Gen 3 modules; Gen 3 reuses the "
            .. "Gen 1 / Gen 2 names and invents none"):format(kind, name))
        T.check(listed[name],
          ("%s %s has a Gen 3 site but is not in this gate's list; add it "
            .. "here and to docs/mod-api-gen3-compat.md"):format(kind, name))
      end
    end
  end
end

assertListed(GEN3_EVENTS, Catalog.events(), Catalog.eventSites, "event")
assertListed(GEN3_HOOKS, Catalog.hooks(), Catalog.hookSites, "hook")

for _, name in ipairs(Catalog.events()) do
  T.check(name:sub(1, 5) ~= "gen3.", "no generation-prefixed event: " .. name)
end
for _, name in ipairs(Catalog.hooks()) do
  T.check(name:sub(1, 5) ~= "gen3.", "no generation-prefixed hook: " .. name)
end

do
  local cache = {}
  local function sourceOf(path)
    if cache[path] == nil then
      local handle = io.open(path, "r")
      cache[path] = handle and handle:read("*a") or false
      if handle then handle:close() end
    end
    return cache[path] or nil
  end
  for _, name in ipairs(Catalog.events()) do
    for _, path in ipairs(Catalog.eventSites(name)) do
      if isGen3Site(path) and not isFacadeSite(path) then
        local body = sourceOf(path)
        T.check(body and body:find(('Runtime.wants("%s")'):format(name), 1, true),
          ("the Gen 3 emit of %s in %s is guarded by Runtime.wants")
            :format(name, path))
      end
    end
  end
end

local function files(...)
  local out = {}
  for _, set in ipairs({ ... }) do
    for path, body in pairs(set) do out[path] = body end
  end
  return out
end

local function fixture(id, games, body)
  local gamesJson = games and (',"games":["' .. table.concat(games, '","') .. '"]') or ""
  return {
    ["mods/" .. id .. "/manifest.json"] = ([[{
      "id": "%s", "name": "%s", "version": "1.0.0", "entry": "main.lua",
      "api": 2%s
    }]]):format(id, id, gamesJson),
    ["mods/" .. id .. "/main.lua"] = body,
  }
end

local function statusOf(run, id)
  for _, entry in ipairs(run.loader:status().available) do
    if entry.id == id then return entry end
  end
  return nil
end

local GEN1_ONLY = fixture("fix_gen1_only", nil, [[
  local mod = ...
  mod.content.pokemon:patch("MEW", { catchRate = 1 })
]])

local GEN3_READY = fixture("fix_gen3_ready", { "gen1", "gen3" }, [[
  local mod = ...
  mod.exports.api = mod
  local mew = mod.content.pokemon:get("MEW")
  mod.exports.mewIndex = mew and mew.index
  mod.exports.mewStats = mew and mew.baseStats.specialAttack
  local pidgey = mod.content.pokemon:get("PIDGEY")
  mod.exports.pidgeyEggMoves = pidgey and pidgey.eggMoves
  mod.exports.mewEggMoves = mew and mew.eggMoves
  local copy = {}
  for key, value in pairs(mew) do copy[key] = value end
  copy.spriteFront = mod.path .. "/front.png"
  mod.content.pokemon:override("MEW", copy)
  mod.content.pokemon:patch("CHARMANDER", {
    catchRate = 3,
    learnset = { { level = 1, move = "SURF" } },
    eggMoves = { "EMBER" },
    evolutions = { { method = "EVO_ITEM", item = "THUNDERSTONE",
                     species = "CHARMELEON" } },
  })
  mod.content.moves:patch("EMBER", { power = 50 })
  mod.content.items:patch("POTION", { price = 1 })
  mod.content.encounters:patch("FR_ROUTE_1", { land = { rate = 99 } })
  mod.content.trainers:patch("326", {
    party = { { species = "MEW", level = 7, moves = { "SURF" } } },
  })
  mod.content.text:override("Text_BootedUpPC", "HELLO")
  mod.content.map_scripts:override("EventScript_Fixture", { { op = "end" } })
  mod.content.transitions:register("FIXTURE_WIPE", { frames = 30 })
  mod.exports.species = {}
  for id in mod.content.pokemon:each() do mod.exports.species[#mod.exports.species + 1] = id end
]])

do
  local data = T.sdk.gen3Data()
  local run = T.sdk.loadMods({ "mods/fix_gen1_only", "mods/fix_gen3_ready" }, {
    fs = T.sdk.memfs(files(GEN1_ONLY, GEN3_READY)),
    data = data,
    generation = 3,
  })

  local skipped = statusOf(run, "fix_gen1_only")
  T.eq(skipped.state, "wrong_generation",
    "Gen 3: a mod that never claimed FireRed is not loaded")
  T.eq(skipped.error, nil, "Gen 3: and the skip is not a failure")
  T.eq(statusOf(run, "fix_gen3_ready").state, "loaded",
    "Gen 3: the declared mod loads (" .. tostring(run.errors[1]) .. ")")

  local exports = run.loader.exports.fix_gen3_ready or {}
  T.eq(exports.mewIndex, 151, "Gen 3: MEW resolves by name to species 151")
  T.eq(exports.mewStats, 100, "Gen 3: with the split special stats")
  T.eq(table.concat(exports.pidgeyEggMoves or {}, ","), "SCRATCH,TACKLE",
    "Gen 3: the species record carries its egg moves as move ids")
  T.eq(exports.mewEggMoves, nil,
    "Gen 3: a species with no gEggMoves entry carries no eggMoves field")
  local seen = {}
  for _, id in ipairs(exports.species or {}) do seen[id] = true end
  T.check(seen.NIDORAN_F and seen.CHARMANDER and not seen["?"],
    "Gen 3: each() yields name ids and skips placeholder species")

  local P = data.gen3Pokemon
  T.eq(P._speciesMeta[4].catchRate, 3, "Gen 3: a patch lands in the numeric meta table")
  T.eq(P._speciesMeta[151].catchRate, 45, "Gen 3: the skipped mod's patch left no trace")
  T.eq(P._learnsets[4][1][2], 57, "Gen 3: a learnset move name writes back as its number")
  T.eq(P._eggMoves[4][1], 52, "Gen 3: an egg move name writes back as its number")
  T.eq(P._evolutions[4][1].method, 7, "Gen 3: an evolution method writes back as EVO_ITEM")
  T.eq(P._evolutions[4][1].param, 96, "Gen 3: and its item as the item number")
  T.eq(P._evolutions[4][1].target, 5, "Gen 3: and its species as the species number")
  T.check(P.spriteOverrides and P.spriteOverrides[151]
    and P.spriteOverrides[151].front == "mods/fix_gen3_ready/front.png",
    "Gen 3: a sprite path override is recorded for the pic seeder")
  T.eq(P.spriteOverrides[151].back, nil, "Gen 3: the untouched back pic stays vanilla")

  T.eq(data.gen3Moves._rom[52].power, 50, "Gen 3: a move patch lands in the ROM row")
  T.eq(data.gen3Items._byId[13].price, 1, "Gen 3: an item patch lands in the item row")
  T.eq(data.gen3Encounters.FR_ROUTE_1.land.rate, 99, "Gen 3: an encounter patch lands")
  T.eq(data.gen3Encounters["3:19"].land.rate, 99,
    "Gen 3: and reaches the group:num alias of the same map")
  T.eq(data.gen3Encounters.FR_ROUTE_1.land.slots[1].species, 16,
    "Gen 3: encounter species stay numeric in the engine table")
  local rival = data.gen3Trainers.trainers[326]
  T.eq(rival.party[1].species, 151, "Gen 3: a trainer party species writes back as a number")
  T.eq(rival.party[1].moves[1], 57, "Gen 3: and its moves as numbers")
  T.eq(rival.partySize, 1, "Gen 3: partySize follows the party")
  local text = data.gen3Text.Text_BootedUpPC
  T.check(text[1].t == "text" and text[1].s == "HELLO" and text[2].t == "eos",
    "Gen 3: a string text override becomes the VM's IR")
  T.eq(data.gen3Scripts.EventScript_Fixture[1].op, "end",
    "Gen 3: a script override replaces the VM row list")

  T.check(data.transitions == nil or data.transitions.FIXTURE_WIPE == nil,
    "Gen 3: a gated registry merges nothing")
  local told = false
  for _, message in ipairs(run.errors) do
    if message:match("transitions") and message:match("Gen 3") then told = true end
  end
  T.check(told, "Gen 3: the dropped registration is reported in Gen 3's words")

  local api = exports.api
  T.check(api ~= nil, "Gen 3: the mod handed its api back for the facade check")
  if api then
    run.loader.game = {}
    local world = api.world
    T.eq(getmetatable(world), require("src.world.game3.WorldAPI"),
      "Gen 3: mod.world resolves to src.world.game3.WorldAPI")
    local battle = api.battle
    T.eq(getmetatable(battle), require("src.battle.game3.BattleAPI"),
      "Gen 3: mod.battle resolves to src.battle.game3.BattleAPI")
    run.loader.game = nil
  end
  run.release()
end

do
  local BAD = fixture("fix_refs", { "gen3" }, [[
    local mod = ...
    mod.content.pokemon:patch("PIDGEY", {
      evolutions = { { method = "EVO_LEVEL", level = 18, species = "PIDGEOTTO_TYPO" } },
    })
    mod.content.pokemon:patch("MEW", { learnset = { { level = 1, move = "NOT_A_MOVE" } } })
  ]])
  local run = T.sdk.loadMods({ "mods/fix_refs" }, {
    fs = T.sdk.memfs(BAD), data = T.sdk.gen3Data(), generation = 3,
  })
  local pokemon, moves = false, false
  for _, message in ipairs(run.errors) do
    if message:match("unresolved reference to pokemon") then pokemon = true end
    if message:match("unresolved reference to moves") then moves = true end
  end
  T.check(pokemon, "Gen 3: an evolution into an unknown species is reported")
  T.check(moves, "Gen 3: a learnset move that does not exist is reported")
  run.release()
end

do
  local GOOD = fixture("fix_refs_ok", { "firered" }, [[
    local mod = ...
    mod.content.pokemon:patch("PIDGEY", {
      evolutions = { { method = "EVO_LEVEL", level = 18, species = "CHARMELEON" } },
      itemRare = "POTION",
    })
  ]])
  local run = T.sdk.loadMods({ "mods/fix_refs_ok" }, {
    fs = T.sdk.memfs(GOOD), data = T.sdk.gen3Data(), generation = 3,
  })
  local dangling = {}
  for _, message in ipairs(run.errors) do
    if message:match("unresolved reference") then dangling[#dangling + 1] = message end
  end
  T.eq(#dangling, 0, "Gen 3: refs that resolve report nothing ("
    .. table.concat(dangling, "; ") .. ")")
  T.eq(statusOf(run, "fix_refs_ok").state, "loaded", "Gen 3: games = [firered] loads")
  run.release()
end

do
  local run = T.sdk.loadNone({ generation = 3, data = T.sdk.gen3Data() })
  local content = run.loader.content
  T.eq(content.balls:get("GREAT_BALL"), nil, "Gen 3 seeds none of Red's balls")
  T.eq(content.statuses:get("BRN"), nil, "Gen 3 seeds none of Red's statuses")
  T.eq(content.ai_classes:get("LAYER_1"), nil, "or Red's AI layers")
  T.eq(content.commands:get("show_text"), nil, "or Gen 1's row-list verbs")
  T.eq(run.data.statuses, nil, "a mod-free FireRed boot writes no Gen 1 namespace")
  T.eq(run.data.commands, nil, "and leaves data.commands absent")
  T.eq(#require("src.mods.Builtins").registries(3), 0,
    "the Gen 3 registrant list is empty")
  run.release()
end

do
  local PROBE = [[
    local mod = ...
    local function attempt(name)
      local ok, result = pcall(require, name)
      if ok then return nil end
      return tostring(result)
    end
    mod.exports.gen2Err = attempt("src.battle.gen2.Mon")
    mod.exports.game2Err = attempt("src.core.Game2")
    mod.exports.game3Err = attempt("src.core.game3.pokemon")
  ]]
  local FILES = fixture("fix_probe", { "all" }, PROBE)
  local onRed = T.sdk.loadMods({ "mods/fix_probe" },
    { fs = T.sdk.memfs(files(FILES)), data = {}, generation = 1 })
  local red = onRed.loader.exports.fix_probe or {}
  T.check(red.game3Err and red.game3Err:find("Gen 3 engine module", 1, true),
    "Gen 1: a Gen 3 engine module is refused: " .. tostring(red.game3Err))
  onRed.release()

  local onFireRed = T.sdk.loadMods({ "mods/fix_probe" },
    { fs = T.sdk.memfs(files(FILES)), data = T.sdk.gen3Data(), generation = 3 })
  local fr = onFireRed.loader.exports.fix_probe or {}
  T.check(fr.gen2Err and fr.gen2Err:find("Gen 2 engine module", 1, true),
    "Gen 3: a Gen 2 engine module is refused: " .. tostring(fr.gen2Err))
  T.check(fr.game2Err and fr.game2Err:find("src.core.Game2", 1, true),
    "Gen 3: and so is src.core.Game2")
  T.check(not (fr.game3Err and fr.game3Err:find("engine module and this is", 1, true)),
    "Gen 3: its own engine modules are not refused: " .. tostring(fr.game3Err))
  onFireRed.release()
end

T.finish("gate_gen3_mod_api")
