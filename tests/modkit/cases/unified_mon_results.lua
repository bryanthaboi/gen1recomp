package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.modkit")
local Loader = require("src.mods.Loader")
local ModRuntime = require("src.mods.Runtime")
local Version = require("src.core.GameVersion")
local Merge = require("src.mods.Merge")
local Logger = require("src.core.Logger")

local savedVersion = Version.get()
local savedRuntime = { ModRuntime.events, ModRuntime.hooks, ModRuntime.errors }

local ELIGIBILITY = [[
local mod = ...
local out = mod.exports
out.mode = "pass"
out.install = function()
  return mod.hooks:wrap("fieldmove.eligibility", function(next, moveId, ctx)
    if out.mode == "bound" then return ctx.party[2] end
    if out.mode == "raw" then return ctx.save.party[2] end
    if out.mode == "party" then return ctx.party end
    if out.mode == "ctx" then return ctx end
    if out.mode == "fresh" then return { species = out.species } end
    if out.mode == "fresh_after_next" then
      next(moveId, ctx)
      return { species = out.species, nickname = "FAKE", level = 5, hp = 10 }
    end
    return next(moveId, ctx)
  end)
end
]]

local TRAINER_PARTY = [[
local mod = ...
local out = mod.exports
out.mode = "pass"
mod.hooks:wrap("trainer.party", function(next, class, id, party)
  local result = next(class, id, party)
  if out.mode == "fresh_list" then return { { species = out.species, level = 7 } } end
  if out.mode == "append" then
    result[#result + 1] = { species = out.species, level = 7 }
    return result
  end
  if out.mode == "no_species" then return { { level = 7 } } end
  return result
end)
]]

local function files(id, body)
  return T.sdk.memfs({
    ["mods/" .. id .. "/manifest.json"] = '{"id":"' .. id .. '","name":"' .. id
      .. '","version":"1.0.0","api":3,"games":["all"],"entry":"main.lua"}',
    ["mods/" .. id .. "/main.lua"] = body,
  })
end

local function lastLog()
  return Logger.history[#Logger.history] or ""
end

local function rejected(label)
  T.check(lastLog():find("must return nil or a Pokemon from ctx.party", 1, true) ~= nil,
    label .. " logs the rejected result")
end

local function scenario(label, fn)
  local ok, err = xpcall(fn, debug.traceback)
  T.check(ok, label .. ": " .. tostring(err))
end

local function gen12Data()
  local data = T.fixtures.fresh()
  for name, index in pairs({ BULBASAUR = 1, PIKACHU = 25 }) do
    local def = Merge.deepCopy(data.pokemon.FIXMON_A)
    def.id, def.name, def.index, def.dex = name, name, index, index
    data.pokemon[name] = def
  end
  return data
end

for _, version in ipairs({ "red", "blue", "yellow" }) do
  scenario(version .. " eligibility results", function()
    local OW = require("src.world.OverworldController")
    local Pokemon = require("src.pokemon.Pokemon")
    Version.set(version)
    local data = gen12Data()
    local function mon(species, nickname)
      local m = Pokemon.new(data, species, 5)
      m.nickname, m.moves = nickname, { { id = "FIX_TACKLE", pp = 30 } }
      return m
    end
    local save = { version = version, player = { name = "RED" },
      inventory = { CASCADEBADGE = 1, SOULBADGE = 1 }, flags = {}, options = {},
      party = { mon("BULBASAUR", "BUD"), mon("PIKACHU", "SPARKY") } }
    local game = { data = data, save = save, phase = "field",
      stack = { push = function() end } }
    OW._setGameForTest(game)
    local ow = setmetatable({ player = { surfing = true } }, { __index = OW })
    local loader = Loader.new({ fs = files("elig", ELIGIBILITY), generation = 1, version = version })
    T.sdk.captureRuntime()
    loader.game = game
    T.eq(loader:load(data), true, version .. " eligibility mod loads")
    local out = loader.exports.elig
    out.species = "PIKACHU"
    out.install()

    out.mode = "raw"
    local picked = ow:partyKnows("SURF")
    T.eq(picked, save.party[2], version .. " a ctx.save party member maps back as itself")
    ow:syncSurfingPikachu()
    T.eq(ow.player.surfingPikachu, true, version .. " the raw Pikachu pick drives the surf sprite")

    for _, mode in ipairs({ "fresh", "fresh_after_next" }) do
      out.mode = mode
      T.eq(ow:partyKnows("SURF"), nil, version .. " " .. mode .. " table leaves the vanilla answer")
      rejected(version .. " " .. mode)
    end
    for _, mode in ipairs({ "fresh", "party", "ctx" }) do
      out.mode = mode
      if mode ~= "fresh" then
        T.eq(ow:partyKnows("SURF"), nil, version .. " " .. mode .. " view leaves the vanilla answer")
        rejected(version .. " " .. mode)
      end
      local ok, why = pcall(ow.trySurf, ow, 0, 0)
      T.check(ok, version .. " trySurf survives a " .. mode .. " eligibility result: " .. tostring(why))
      ok, why = pcall(ow.useStrengthFieldMove, ow, nil)
      T.check(ok, version .. " useStrengthFieldMove survives a " .. mode .. " eligibility result: " .. tostring(why))
    end
    T.sdk.restoreRuntime()
    OW._setGameForTest(require("src.core.Game"))
  end)
end

for _, version in ipairs({ "gold", "silver", "crystal" }) do
  scenario(version .. " eligibility results", function()
    local FieldMoves = require("src.world.gen2.FieldMoves")
    Version.set(version)
    local data = gen12Data()
    local function mon(species, nickname)
      return { species = species, nickname = nickname, level = 5, hp = 20, maxHp = 20,
        stats = { hp = 20, attack = 9, defense = 9, speed = 9, specialAttack = 9, specialDefense = 9 },
        dvs = { attack = 1, defense = 2, speed = 3, special = 4, hp = 5 }, experience = 135,
        happiness = 70, moves = { { id = "FIX_TACKLE", pp = 30, maxPp = 30 } } }
    end
    local save = { version = version, player = { name = "KRIS" },
      party = { mon("BULBASAUR", "BUD"), mon("PIKACHU", "SPARKY") } }
    local fieldCtx = { save = save, data = data }
    local loader = Loader.new({ fs = files("elig", ELIGIBILITY), generation = 2, version = version })
    T.sdk.captureRuntime()
    loader.game = { data = data, save = save }
    T.eq(loader:load(data), true, version .. " eligibility mod loads")
    local out = loader.exports.elig
    out.species = "PIKACHU"
    out.install()

    for _, mode in ipairs({ "bound", "raw" }) do
      out.mode = mode
      local picked = FieldMoves.partyMoveUser(save.party, "SURF", fieldCtx)
      T.eq(picked, save.party[2], version .. " " .. mode .. " pick is the native party member")
      T.eq(picked and FieldMoves.surfType(picked), "surf_pika", version .. " " .. mode .. " Pikachu pick surfs as Pikachu")
    end
    for _, mode in ipairs({ "fresh", "fresh_after_next", "party", "ctx" }) do
      out.mode = mode
      T.eq(FieldMoves.partyMoveUser(save.party, "SURF", fieldCtx), nil,
        version .. " " .. mode .. " table leaves the vanilla answer")
      rejected(version .. " " .. mode)
    end
    T.sdk.restoreRuntime()
  end)
end

for _, version in ipairs({ "firered", "leafgreen", "ruby", "sapphire", "emerald" }) do
  scenario(version .. " eligibility results", function()
    local Versions = require("src.import.gba.versions")
    local Profile = require("src.core.game3.profile")
    local Runtime = require("src.core.game3.runtime")
    local Pokemon = require("src.core.game3.pokemon")
    local Space = require("src.core.game3.scripting.space")
    local FieldMoves = require("src.core.game3.field_moves")
    Version.set(version)
    Versions.select(version)
    Profile.reset()
    local data = T.sdk.gen3Data()
    for key, value in pairs(data.gen3Pokemon) do Pokemon[key] = value end
    Pokemon._byName = { CHARMANDER = 4, PIDGEY = 16, MEW = 151 }
    Pokemon._national = { toNational = { [4] = 4, [16] = 16 } }
    local party = {
      { species = 16, nickname = "FIRST", moves = { 33 }, hp = 20, maxHp = 20,
        level = 5, personality = 0, ability = 0, otId = 42, exp = 135 },
      { species = 4, nickname = "SECOND", moves = { 33 }, hp = 20, maxHp = 20,
        level = 5, personality = 1, ability = 0, otId = 42, exp = 135 },
    }
    local session = { version = version, name = "RED", trainerId = 42, secretId = 0,
      party = party, map = "FR_OAKS_LAB", flags = {}, vars = {}, options = {} }
    local game = { data = data, session = session, save = { position = {}, party = party },
      options = session.options, phase = "field", input = {} }
    session.game = game
    local saved = { Runtime.active, Runtime.session, Runtime._game, Runtime._mod, Space.store }
    Runtime.active, Runtime.session, Runtime._game, Runtime._mod = true, session, game, nil
    Space.store = session
    local loader = Loader.new({ fs = files("elig", ELIGIBILITY), generation = 3,
      version = version, dev = true })
    T.sdk.captureRuntime()
    loader.game = game
    T.eq(loader:load(data), true, version .. " eligibility mod loads")
    local out = loader.exports.elig
    out.species = "CHARMANDER"
    out.install()
    local fieldCtx = { save = game.save, data = data, game = game }

    out.mode = "raw"
    local mon, slot = FieldMoves.partyMoveUser(party, 57, fieldCtx)
    T.eq(mon, party[2], version .. " a ctx.save party member maps back as itself")
    T.eq(slot, 1, version .. " the raw pick drives the native slot")
    out.mode = "fresh"
    mon, slot = FieldMoves.partyMoveUser(party, 57, fieldCtx)
    T.eq(mon, nil, version .. " a built table leaves the vanilla answer")
    T.eq(slot, 6, version .. " a built table keeps the native sentinel")
    rejected(version .. " fresh")
    for _, view in ipairs({ "party", "ctx" }) do
      out.mode = view
      mon, slot = FieldMoves.partyMoveUser(party, 57, fieldCtx)
      T.eq(mon, nil, version .. " a " .. view .. " view leaves the vanilla answer")
      T.eq(slot, 6, version .. " a " .. view .. " view keeps the native sentinel")
      rejected(version .. " " .. view)
    end
    T.sdk.restoreRuntime()
    Runtime.active, Runtime.session, Runtime._game, Runtime._mod, Space.store =
      saved[1], saved[2], saved[3], saved[4], saved[5]
  end)
end

local function trainerParty(generation, version, data, species, nativeRow, check)
  scenario(version .. " trainer.party rows a mod built", function()
    Version.set(version)
    if generation == 3 then require("src.import.gba.versions").select(version) end
    local loader = Loader.new({ fs = files("tp", TRAINER_PARTY), generation = generation, version = version })
    T.sdk.captureRuntime()
    loader.game = { data = data, save = { party = {} } }
    T.eq(loader:load(data), true, version .. " trainer.party mod loads")
    local out = loader.exports.tp
    out.species = species
    for _, mode in ipairs({ "fresh_list", "append" }) do
      out.mode = mode
      local result = ModRuntime.call("trainer.party", function(_, _, p) return p end, "RIVAL", 1, { nativeRow() })
      local row = type(result) == "table" and result[#result] or {}
      check(row, version .. " " .. mode)
      T.eq(row.speciesId, nil, version .. " " .. mode .. " row has no speciesId key")
      T.eq(row.level, 7, version .. " " .. mode .. " row keeps its level")
    end
    out.mode = "no_species"
    local result = ModRuntime.call("trainer.party", function(_, _, p) return p end, "RIVAL", 1, { nativeRow() })
    T.eq(#result, 1, version .. " a built row without species leaves the vanilla party")
    T.eq(result[1] and result[1].level, 5, version .. " a built row without species keeps the vanilla row")
    T.sdk.restoreRuntime()
  end)
end

for _, version in ipairs({ "red", "blue", "yellow" }) do
  local data = T.fixtures.fresh()
  trainerParty(1, version, data, "FIXMON_A", function() return { species = "FIXMON_A", level = 5 } end,
    function(row, label)
      T.eq(row.species, "FIXMON_A", label .. " row carries the native species key")
      local ok, why = pcall(require("src.pokemon.Pokemon").new, data, row.species, row.level)
      T.check(ok, label .. " row builds a Pokemon: " .. tostring(why))
    end)
end
for _, version in ipairs({ "gold", "silver", "crystal" }) do
  trainerParty(2, version, T.fixtures.fresh(), "FIXMON_A", function() return { species = "FIXMON_A", level = 5 } end,
    function(row, label) T.eq(row.species, "FIXMON_A", label .. " row carries the native species key") end)
end
trainerParty(3, "firered", T.sdk.gen3Data(), "MEW", function() return { species = 16, level = 5, heldItem = 0 } end,
  function(row, label) T.eq(row.species, 151, label .. " row carries the native species number") end)

Version.set(savedVersion)
ModRuntime.install(savedRuntime[1], savedRuntime[2], savedRuntime[3])
T.finish()
