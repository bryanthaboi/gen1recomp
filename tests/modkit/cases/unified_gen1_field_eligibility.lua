package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.harness").suite("unified gen1 field eligibility")
local Sdk = require("tests.modkit.sdk")
local Fixtures = require("tests.modkit.fixtures")
local Version = require("src.core.GameVersion")
local Merge = require("src.mods.Merge")
local ModRuntime = require("src.mods.Runtime")
local OW = require("src.world.OverworldController")

local savedVersion = Version.get()
local savedRuntime = { ModRuntime.events, ModRuntime.hooks, ModRuntime.errors }

local files = {
  ["mods/field_probe/manifest.json"] = [[{"id":"field_probe","name":"Field probe","version":"1.0.0","api":3,"games":["gen1"],"entry":"main.lua"}]],
  ["mods/field_probe/main.lua"] = [[
    local mod = ...
    local out = mod.exports
    out.mode = "pass"
    out.install = function()
      return mod.hooks:wrap("fieldmove.eligibility", function(next, moveId, ctx)
        out.moveId, out.ctx = moveId, ctx
        local mon = next(moveId, ctx)
        if out.mode == "party" then return ctx.party and ctx.party[2] end
        return mon
      end)
    end
  ]],
}

local function mon(species, nickname, move)
  return { species = species, nickname = nickname, level = 5, hp = 20,
    stats = { hp = 20, attack = 9, defense = 9, speed = 9, special = 9 },
    moves = { { id = move, pp = 30 } } }
end

for _, version in ipairs({ "red", "blue", "yellow" }) do
  local run
  local ok, err = xpcall(function()
    Version.set(version)
    local data = Fixtures.fresh()
    for name, index in pairs({ BULBASAUR = 1, PIKACHU = 25 }) do
      local def = Merge.deepCopy(data.pokemon.FIXMON_A)
      def.id, def.name, def.index, def.dex = name, name, index, index
      data.pokemon[name] = def
    end
    local save = { version = version, player = { name = "RED" },
      inventory = { CASCADEBADGE = 1, SOULBADGE = 1 }, flags = {}, options = {},
      party = { mon("BULBASAUR", "BUD", "CUT"), mon("PIKACHU", "SPARKY", "FIX_TACKLE") } }
    local game = { data = data, save = save, phase = "field" }
    OW._setGameForTest(game)
    local ow = setmetatable({ player = { surfing = true } }, { __index = OW })

    run = Sdk.loadMods({ "mods/field_probe" }, {
      generation = 1, data = data, fs = Sdk.memfs(files),
    })
    run.loader.game = game
    local out = run.loader.exports.field_probe
    T.eq(#run.errors, 0, version .. " API 3 mod loads")
    local remove = out.install()

    out.mode = "pass"
    T.eq(ow:partyKnows("CUT"), save.party[1], version .. " observer keeps the native knower")
    T.eq(out.moveId, "CUT", version .. " public move id")
    T.eq(out.ctx.moveId, "CUT", version .. " ctx carries moveId")
    T.check(type(out.ctx.party) == "table", version .. " ctx carries the party")
    T.eq(out.ctx.party and out.ctx.party[2].species, "PIKACHU", version .. " ctx party is public")

    out.mode = "party"
    local picked = ow:partyKnows("SURF")
    T.eq(picked, save.party[2], version .. " ctx.party pick maps back to the native member")
    T.eq(picked and picked.nickname, "SPARKY", version .. " restored mon keeps its nickname")
    T.eq(picked and picked.species and data.pokemon[picked.species].name, "PIKACHU",
      version .. " restored mon resolves its species name")
    ow:syncSurfingPikachu()
    T.eq(ow.player.surfingPikachu, true, version .. " surfing Pikachu follows the hook's pick")

    remove()
    T.eq(ow:partyKnows("SURF"), nil, version .. " unsubscribe restores vanilla")
    T.eq(#run.errors, 0, version .. " callbacks raise no errors")
  end, debug.traceback)
  T.check(ok, version .. " gen1 eligibility scenario: " .. tostring(err))
  if run then run.release() end
  OW._setGameForTest(require("src.core.Game"))
end

Version.set(savedVersion)
ModRuntime.install(savedRuntime[1], savedRuntime[2], savedRuntime[3])
T.finish()
