-- The four Ruins of Alph secret chambers:
-- ../pokecrystal/engine/events/unown_walls.asm:1 HoOhChamber, :13
-- OmanyteChamber, :54 SpecialAerodactylChamber, :81 SpecialKabutoChamber.
--   CRYSTAL_CACHE="..." luajit tests/gen2_unown_chambers_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 unown chambers")
local check, eq = S.check, S.eq

love = require("tests.love_stub")

local Events = require("src.world.gen2.Events")
local Specials = require("src.script.gen2.Specials")
local UnownWords = require("src.world.gen2.UnownWords")

local function loadTable(path)
  local chunk = loadfile(path)
  return chunk and chunk() or nil
end

local function fakeVm(opts)
  opts = opts or {}
  local pack = opts.pack or {}
  return {
    scriptVar = 0,
    events = opts.events or Events.new(),
    specials = {
      party = function() return opts.party or {} end,
      itemIndex = function(id) return id == "WATER_STONE" and 24 or nil end,
      hasItem = function(index) return pack[index] == true end,
    },
  }
end

local WALLS = {
  { "HO_OH", 806 }, { "KABUTO", 807 },
  { "OMANYTE", 808 }, { "AERODACTYL", 809 },
}

-- ../pokecrystal/constants/event_flags.asm:486-489
do
  for _, row in ipairs(WALLS) do
    eq(UnownWords.WALL_OPENED[row[1]], row[2],
      "EVENT_WALL_OPENED_IN_" .. row[1] .. "_CHAMBER is flag " .. row[2])
  end
  local events = Events.new()
  check(not UnownWords.wallOpened(events, "OMANYTE"), "a fresh save has no wall open")
  check(UnownWords.openWall(events, "OMANYTE"), "the first SET_FLAG reports the change")
  check(UnownWords.wallOpened(events, "OMANYTE"), "and CHECK_FLAG reads it back")
  check(not UnownWords.openWall(events, "OMANYTE"), "a second one is a no-op")
  check(not UnownWords.wallOpened(events, "KABUTO"),
    "and it did not open any of the other three")
  check(not UnownWords.openWall(nil, "OMANYTE"), "no bitfield, no write")
  check(not UnownWords.openWall(Events.new(), "BETA"),
    "and a chamber the cart does not have has no flag to set")
end

-- ../pokecrystal/engine/events/unown_walls.asm:2-5 HoOhChamber
do
  check(UnownWords.leadIsHoOh({ { species = "HO_OH" } }),
    "Ho-Oh in the first slot is what the routine asks for")
  check(not UnownWords.leadIsHoOh({ { species = "LUGIA" }, { species = "HO_OH" } }),
    "Ho-Oh in the second slot is not: it reads wPartySpecies[0] only")
  check(not UnownWords.leadIsHoOh({ { species = "HO_OH", isEgg = true } }),
    "an egg holds EGG in wPartySpecies, not the hatchling's species")
  check(not UnownWords.leadIsHoOh({}), "and an empty party is not Ho-Oh")

  local vm = fakeVm({ party = { { species = "HO_OH" } } })
  Specials.ALL.HoOhChamber(vm)
  check(UnownWords.wallOpened(vm.events, "HO_OH"), "the handler opens the wall")
  eq(vm.scriptVar, 0, "and leaves wScriptVar alone: the scene's own checkevent reads the flag")

  vm = fakeVm({ party = { { species = "SUICUNE" } } })
  Specials.ALL.HoOhChamber(vm)
  check(not UnownWords.wallOpened(vm.events, "HO_OH"),
    "any other lead leaves it shut")

  vm = fakeVm({ party = { { species = "HO_OH" } } })
  Specials.ALL.HoOhChamber(vm)
  check(not UnownWords.wallOpened(vm.events, "OMANYTE"),
    "and it never touches the Omanyte bit")
end

-- ../pokecrystal/engine/events/unown_walls.asm:28-43 OmanyteChamber
do
  eq(UnownWords.waterStoneSlot({ { item = "WATER_STONE" } }), 1,
    "one held Water Stone is found")
  eq(UnownWords.waterStoneSlot(
    { { item = "WATER_STONE" }, {}, { item = "WATER_STONE" } }), 3,
    "and with two, the backwards walk stops at the LAST slot")
  check(UnownWords.waterStoneSlot({ { item = "FIRE_STONE" }, {} }) == nil,
    "no stone, no slot")
  check(UnownWords.waterStoneSlot(nil) == nil, "and no party is no slot")

  local vm = fakeVm({ pack = { [24] = true } })
  Specials.ALL.OmanyteChamber(vm)
  check(UnownWords.wallOpened(vm.events, "OMANYTE"),
    "CheckItem on the pack alone opens it")

  vm = fakeVm({ party = { {}, { item = "WATER_STONE" } } })
  Specials.ALL.OmanyteChamber(vm)
  check(UnownWords.wallOpened(vm.events, "OMANYTE"),
    "so does a Water Stone held by a party mon")

  vm = fakeVm({ party = { { item = "FIRE_STONE" } } })
  Specials.ALL.OmanyteChamber(vm)
  check(not UnownWords.wallOpened(vm.events, "OMANYTE"),
    "neither in the pack nor held leaves it shut")

  vm = fakeVm({})
  Specials.ALL.OmanyteChamber(vm)
  check(not UnownWords.wallOpened(vm.events, "OMANYTE"),
    "and an empty party with an empty pack does nothing")

  -- ../pokecrystal/engine/events/unown_walls.asm:14-20
  local seen = 0
  vm = fakeVm({})
  vm.specials.party = function() seen = seen + 1 return {} end
  UnownWords.openWall(vm.events, "OMANYTE")
  Specials.ALL.OmanyteChamber(vm)
  eq(seen, 0, "an already-open wall returns before the party is walked")
end

-- ../pokecrystal/engine/events/unown_walls.asm:54, :81, both reached from a
-- field move rather than from a `special`.
do
  local events = Events.new()
  check(not UnownWords.aerodactylChamber(events, "RUINS_OF_ALPH_KABUTO_CHAMBER"),
    "Flash in the wrong chamber returns no carry")
  check(not UnownWords.wallOpened(events, "AERODACTYL"), "and opens nothing")
  check(not UnownWords.aerodactylChamber(events, "DARK_CAVE_VIOLET_ENTRANCE"),
    "nor does Flash in an ordinary dark cave")
  check(UnownWords.aerodactylChamber(events, "RUINS_OF_ALPH_AERODACTYL_CHAMBER"),
    "in its own chamber it returns the carry FlashFunction jumps on")
  check(UnownWords.wallOpened(events, "AERODACTYL"), "and sets the bit")

  events = Events.new()
  check(not UnownWords.kabutoChamber(events, "RUINS_OF_ALPH_OMANYTE_CHAMBER"),
    "an escape rope elsewhere does nothing")
  check(not UnownWords.wallOpened(events, "KABUTO"), "and leaves the bit clear")
  check(UnownWords.kabutoChamber(events, "RUINS_OF_ALPH_KABUTO_CHAMBER"),
    "in the Kabuto chamber it fires")
  check(UnownWords.wallOpened(events, "KABUTO"), "and sets its own bit")
  check(not UnownWords.wallOpened(events, "AERODACTYL"),
    "with the Aerodactyl bit untouched")
end

-- data/events/special_pointers.asm:148 OmanyteChamber, :157 HoOhChamber
do
  for _, name in ipairs({ "OmanyteChamber", "HoOhChamber" }) do
    check(type(Specials.ALL[name]) == "function", name .. " is a handler")
    check(Specials.STUBS[name] == nil, name .. " is no longer a stub")
    eq(Specials.HANDLER_SOURCE[name], "specials/crystal_story.lua",
      "owned by this unit's module")
    check(Specials.SUPERSEDED_STUBS[name] ~= nil,
      "and its stub reason moved to SUPERSEDED_STUBS")
  end
end

local cache = os.getenv("CRYSTAL_CACHE")
if not cache then
  cache = (os.getenv("HOME") or "")
    .. "/Library/Application Support/LOVE/crystal-dev/crystal"
end

local maps = loadTable(cache .. "/data/generated/maps.lua")
local scripts = loadTable(cache .. "/data/generated/scripts.lua")
local consts = loadTable(cache .. "/data/generated/constants.lua")

-- ../pokecrystal/maps/RuinsOfAlphOmanyteChamber.asm:22-24, the
-- MAPCALLBACK_TILES callback that re-derives the flag numbers from the cart.
local specialId = {}
for id, name in pairs((consts or {}).specialOrder or {}) do
  specialId[name] = id - 1
end

if not (maps and scripts and consts) then
  check(true, "no cache: the chamber scripts are not walked (SKIP)")
elseif not specialId.OmanyteChamber then
  -- data/events/special_pointers.asm:124 `; Crystal only`
  check(true, "cache is not a Crystal one (SKIP)")
else
  -- ../pokecrystal/maps/RuinsOfAlphOmanyteChamber.asm:10 and
  -- RuinsOfAlphHoOhChamber.asm:10; the other two chambers have no `special`.
  local EXPECTED = {
    HO_OH = "HoOhChamber",
    OMANYTE = "OmanyteChamber",
    KABUTO = false,
    AERODACTYL = false,
  }
  for chamber, wantSpecial in pairs(EXPECTED) do
    local mapId = UnownWords.CHAMBER_MAPS[chamber]
    local def = maps[mapId]
    if not def then
      check(false, mapId .. " is in the cache")
    else
      local callback = (def.callbacks or {})[1]
      local rows = callback and scripts[callback.scriptKey]
      local first = rows and rows[1]
      eq(callback and callback.callback, "MAPCALLBACK_TILES",
        mapId .. " has its hidden-doors callback")
      eq(first and first.op, "checkevent", "which opens on a checkevent")
      eq(first and first.event, UnownWords.WALL_OPENED[chamber],
        "of the very flag " .. chamber .. "'s routine writes")

      local scene
      for _, entry in pairs(def.sceneScripts or {}) do
        if (entry.sceneId or 0) == 0 then scene = entry end
      end
      local sceneRows = scene and scripts[scene.scriptKey] or {}
      local got
      for _, row in ipairs(sceneRows) do
        if row.op == "special" then got = row.id end
      end
      if wantSpecial then
        eq(got, specialId[wantSpecial],
          mapId .. "'s check-wall scene runs " .. wantSpecial)
      else
        check(got == nil,
          mapId .. "'s check-wall scene runs no special: its trigger is a field move")
      end
      -- ../pokecrystal/maps/RuinsOfAlphOmanyteChamber.asm:11
      local read
      for _, row in ipairs(sceneRows) do
        if row.op == "checkevent" then read = row.event end
      end
      eq(read, UnownWords.WALL_OPENED[chamber],
        "and it reads the same flag straight afterwards")
    end
  end
end

S.finish()
