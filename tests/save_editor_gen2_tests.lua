-- Headless Gold save-editor rules. Run from repo root:
--   luajit tests/save_editor_gen2_tests.lua
package.path = package.path .. ";./?.lua;./?/init.lua;./tools/save-editor/?.lua"
  .. ";./tools/save-editor/panels/?.lua"

local love_stub = require("tests.love_stub")
love = love_stub

local passed, failed = 0, 0

local function check(cond, msg)
  if cond then
    passed = passed + 1
  else
    failed = failed + 1
    print("FAIL: " .. msg)
  end
end

local function eq(a, b, msg)
  check(a == b, msg .. string.format(" (got %s, want %s)", tostring(a), tostring(b)))
end

print("== save editor gen2 tests ==")

local Gen = require("Gen")
local Catalog = require("Catalog")
local MonOps = require("MonOps")
local Ops = require("Ops")
local State = require("State")
local Save2 = require("src.core.gen2.Save")
local SaveData = require("src.core.SaveData")
local GameVersion = require("src.core.GameVersion")

local data = {
  pokemon = {
    CYNDAQUIL = {
      id = "CYNDAQUIL", name = "CYNDAQUIL", dex = 155,
      types = { "FIRE" },
      baseStats = {
        hp = 39, attack = 52, defense = 43, speed = 65,
        specialAttack = 60, specialDefense = 50,
      },
      catchRate = 45, baseExp = 65,
      growthRate = "MEDIUM_FAST",
      levelMoves = { { level = 1, move = "TACKLE" } },
      genderRatio = 31,
    },
    TOTODILE = {
      id = "TOTODILE", name = "TOTODILE", dex = 158,
      types = { "WATER" },
      baseStats = {
        hp = 50, attack = 65, defense = 64, speed = 43,
        specialAttack = 44, specialDefense = 48,
      },
      catchRate = 45, baseExp = 66,
      growthRate = "MEDIUM_FAST",
      levelMoves = { { level = 1, move = "SCRATCH" } },
      genderRatio = 31,
    },
  },
  moves = {
    TACKLE = { pp = 35 },
    SCRATCH = { pp = 35 },
  },
  items = {
    POTION = { pocket = "ITEM" },
    MASTER_BALL = { pocket = "BALL" },
    FLOWER_MAIL = { pocket = "ITEM" },
  },
  maps = {},
}

local function newState(version)
  version = version or "gold"
  local prior = GameVersion.get()
  GameVersion.set(version)
  local S = State.new()
  S.data = data
  S.cat = Catalog.build(data)
  S.save = Save2.newGame()
  S.version = version
  Gen.ensureBoxes(S.save)
  GameVersion.set(prior)
  return S
end

do
  GameVersion.set("gold")
  eq(Gen.of({ generation = 2 }), 2, "Gen.of generation field")
  eq(Gen.of({ version = "gold" }), 2, "Gen.of version gold")
  eq(Gen.of({ version = "silver" }), 2, "Gen.of version silver")
  eq(Gen.of(SaveData.newGame()), 1, "Gen.of gen1 newGame")
  eq(Gen.of(Save2.newGame()), 2, "Gen.of gold newGame")
end

do
  GameVersion.set("silver")
  eq(Save2.newGame().version, "silver", "a silver boot stamps silver")
  eq(Save2.newGame().player.name, "SILVER", "with silver's preset name")
  eq(Gen.of(Save2.newGame()), 2, "Gen.of silver newGame")
  GameVersion.set("gold")
end

do
  local S = newState()
  check(Ops.speciesUsable(S, "CYNDAQUIL"), "spa/spd species is usable")
  local S1 = State.new()
  S1.data = {
    pokemon = {
      PIDGEY = { baseStats = { hp = 40, attack = 45, defense = 40, speed = 56, special = 35 } },
      BROKEN = { baseStats = { hp = 1 } },
    },
  }
  check(Ops.speciesUsable(S1, "PIDGEY"), "gen1 special species is usable")
  check(not Ops.speciesUsable(S1, "BROKEN"), "partial record is not usable")
end

for _, version in ipairs({ "gold", "silver" }) do
  local S = newState(version)
  Ops.partyAdd(S)
  eq(#S.save.party, 1, "partyAdd on " .. version)
  local mon = S.save.party[1]
  eq(mon.species, "CYNDAQUIL", version .. " first catalog species")
  check(mon.experience ~= nil, version .. " mon has experience")
  check(mon.exp == nil or mon.experience ~= nil,
    version .. " does not rely on gen1 exp")
  check(mon.stats.specialAttack and mon.stats.specialDefense,
    version .. " stats have spa/spd")
  check(mon.happiness ~= nil, version .. " mon has happiness")
  eq(mon.ot, S.save.player.name, version .. " stampOT copies player name")

  Ops.setLevel(S, mon, 20)
  eq(mon.level, 20, version .. " setLevel 20")
  check(mon.experience > 0, version .. " experience resynced")

  Ops.setHappiness(S, mon, 200)
  eq(mon.happiness, 200, version .. " happiness 200")
  Ops.setPokerus(S, mon, 15)
  eq(mon.pokerus, 15, version .. " pokerus byte")
  Ops.setHeldItem(S, mon, "POTION")
  eq(mon.item, "POTION", version .. " held item")

  eq(mon.name, "CYNDAQUIL", version .. " new mon copies species display name")
  Ops.setSpecies(S, mon, "TOTODILE")
  eq(mon.species, "TOTODILE", version .. " setSpecies id")
  eq(mon.name, "TOTODILE", version .. " setSpecies rewrites the display name")
  check(mon.nickname == nil, version .. " setSpecies does not invent a nickname")
  eq(mon.types[1], "WATER", version .. " setSpecies rewrites copied types")
end

do
  local S = newState()
  Ops.partyAdd(S)
  Ops.partyAdd(S)
  local Mail = require("src.core.gen2.Mail")
  Mail.set(S.save, 1, Mail.entry("FLOWER_MAIL", "hi", "GOLD", 1, "CYNDAQUIL"))
  Mail.set(S.save, 2, Mail.entry("SURF_MAIL", "bye", "GOLD", 1, "CYNDAQUIL"))
  S.selectedParty = 1
  Ops.partyMove(S, 1)
  eq(Mail.state(S.save).party[1].message, "bye", "partyMove carries mail with the mon")
  eq(Mail.state(S.save).party[2].message, "hi", "partyMove swaps the other letter")
  S.selectedParty = 1
  check(Ops.partyRemove(S) == false, "partyRemove arms")
  check(Ops.partyRemove(S) == true, "partyRemove commits")
  eq(Mail.state(S.save).party[1].message, "hi", "partyRemove shifts leftover mail up")
  check(Mail.state(S.save).party[2] == nil, "partyRemove clears the vacated slot")
end

do
  local S = newState()
  Ops.partyAdd(S)
  local mon = S.save.party[1]
  local Mail = require("src.core.gen2.Mail")
  Ops.setHeldItem(S, mon, "FLOWER_MAIL")
  eq(mon.item, "FLOWER_MAIL", "held mail item")
  local letter = Mail.state(S.save).party[1]
  check(letter ~= nil, "giving mail writes sPartyMail")
  eq(letter.species, "CYNDAQUIL", "new letter stamps current species")
  Ops.setSpecies(S, mon, "TOTODILE")
  eq(Mail.state(S.save).party[1].species, "TOTODILE",
    "setSpecies updates the letter's species copy")
  Ops.setHeldItem(S, mon, "POTION")
  check(Mail.state(S.save).party[1] == nil, "non-mail held item drops the letter")
end

do
  local Mon = require("src.battle.gen2.Mon")
  local S = newState()
  local stale = Mon.new(data, "CYNDAQUIL", 5)
  stale.species = "TOTODILE"
  stale.name = "CYNDAQUIL"
  stale.types = { "FIRE" }
  S.save.dayCare = { man = { mon = stale }, lady = {} }
  Mon.syncSaveIdentity(S.save, data)
  eq(stale.name, "TOTODILE", "syncSaveIdentity rewrites Day-Care display name")
  eq(stale.types[1], "WATER", "syncSaveIdentity rewrites Day-Care types")
  eq(Mon.displayName({ nickname = nil, name = "ABRA", species = "RAYQUAZA" }),
    "ABRA", "displayName prefers the species copy over the id")
  eq(Mon.displayName({ nickname = "BOB", name = "ABRA", species = "RAYQUAZA" }),
    "BOB", "displayName prefers nickname")
end

do
  local S = newState()
  eq(Ops.boxCount(S), 14, "14 gold boxes")
  eq(Ops.boxCapacity(S), 20, "20 per box")
  Ops.boxAdd(S)
  eq(#Ops.boxes(S)[1], 1, "boxAdd into box 1")
end

do
  local S = newState()
  Ops.partyAdd(S)
  S.save.party[1].hp = 0
  Ops.partyAdd(S)
  S.selectedParty = 1
  S.selectedBox = 1
  local ok = Ops.deposit(S)
  check(ok, "deposit fainted mon while a healthy remains")
end

do
  local S = newState()
  Ops.partyAdd(S)
  Ops.partyAdd(S)
  S.selectedParty = 1
  S.selectedBox = 1
  local ok = Ops.deposit(S)
  check(ok, "deposit one of two healthy mons")
end

do
  local S = newState()
  Ops.partyAdd(S)
  S.selectedParty = 1
  S.selectedBox = 1
  local ok = Ops.deposit(S)
  check(not ok, "refuse depositing last healthy mon")
  check(S.status:lower():find("last", 1, true) or S.status:find("POKéMON")
      or S.status:find("POKEMON") or S.status:find("last"),
    "deposit refusal names the last-healthy rule: " .. tostring(S.status))
  eq(#S.save.party, 1, "party still has the mon")
end

do
  local S = newState()
  eq(Gen.money(S.save), 3000, "gold start money on player")
  Ops.addMoney(S, 1000)
  eq(S.save.player.money, 4000, "money writes player.money")
  check(S.save.money == nil or S.save.money ~= 4000, "does not write save.money")
  Ops.maxMoney(S)
  eq(S.save.player.money, 999999, "money cap")
  Ops.addCoins(S, 250)
  eq(S.save.player.coins, 250, "coins write player.coins")
end

do
  local S = newState()
  check(not Gen.hasBadge(S.save, "ZEPHYR"), "no zephyr yet")
  Ops.toggleBadge(S, "ZEPHYR")
  check(Gen.hasBadge(S.save, "ZEPHYR"), "zephyr earned")
  check(S.save.player.badges.ZEPHYR, "stored on player.badges")
  Ops.toggleBadge(S, "BOULDER")
  check(S.save.player.kantoBadges.BOULDER, "kanto badge store")
end

do
  local S = newState()
  Ops.dexOwned(S, "CYNDAQUIL", true)
  check(S.save.pokedex.caught.CYNDAQUIL, "dex writes caught")
  check(S.save.pokedex.owned == nil or S.save.pokedex.owned.CYNDAQUIL == nil,
    "does not write owned on gold")
  check(S.save.pokedex.seen.CYNDAQUIL, "owned implies seen")
  local _, owned = Ops.dexCounts(S)
  eq(owned, 1, "dexCounts reads caught")
end

do
  local S = newState()
  local name = "EVENT_BEAT_FALKNER"
  Ops.setFlag(S, name, true)
  check(Gen.getFlag(S.save, name), "gold EVENT_ sets bitfield")
  check(S.save.flags[name] == nil, "numeric flags are not string keys")
  Ops.setFlag(S, "MOD_EDITMON_GIFT", true)
  check(S.save.flags.MOD_EDITMON_GIFT, "mod flags stay named on gold")
end

do
  local S = newState()
  S.mapId = "NEW_BARK_TOWN"
  S.mapClickCell = { cx = 4, cy = 5 }
  Ops.setPlayerHere(S)
  eq(S.save.position.map, "NEW_BARK_TOWN", "position.map")
  eq(S.save.position.x, 4, "position.x")
  eq(S.save.position.y, 5, "position.y")
  check(S.save.player.map == nil or S.save.player.map ~= "NEW_BARK_TOWN",
    "does not write player.map on gold")
end

do
  local encoded = SaveData.encode(Save2.newGame())
  local back = SaveData.decode(encoded)
  eq(back.generation, 2, "round-trip keeps generation 2")
end

do
  local names = Catalog.goldEventList()
  local hasFalkner = false
  for _, n in ipairs(names) do
    if n == "EVENT_BEAT_FALKNER" then hasFalkner = true break end
  end
  check(hasFalkner, "gold event list includes EVENT_BEAT_FALKNER")
end

do
  local maps = Gen.maps({ gen2Maps = { AZALEA_GYM = true }, maps = { PALLET_TOWN = true } })
  check(maps.AZALEA_GYM, "Gen.maps includes gen2Maps")
  check(maps.PALLET_TOWN, "Gen.maps keeps Data:load maps beside gen2Maps")
  check(Gen.maps({ maps = { PALLET_TOWN = true } }).PALLET_TOWN,
    "Gen.maps falls back to maps")
  local mansion = Gen.maps({
    maps = {
      CELADON_MANSION_2F = { id = "CELADON_MANSION_2F", width = 4, height = 5 },
    },
    gen2Maps = {
      CELADON_MANSION_2F = { objects = { { name = "NPC" } } },
      BERRY_FARM = { id = "BERRY_FARM", width = 19, height = 12 },
    },
  })
  eq(mansion.CELADON_MANSION_2F.width, 4,
    "Gen.maps keeps extractor width under a gen2Maps objects patch")
  eq(mansion.CELADON_MANSION_2F.objects[1].name, "NPC",
    "Gen.maps still applies the gen2Maps patch fields")
  eq(mansion.BERRY_FARM.width, 19, "Gen.maps keeps mod maps only on gen2Maps")
  local bound = Gen.bindGoldData({ maps = { A = true }, tilesets = { T = true } })
  check(bound.gen2Maps == bound.maps, "bindGoldData aliases gen2Maps")
  check(bound.gen2Tilesets == bound.tilesets, "bindGoldData aliases gen2Tilesets")
  check(Gen.tilesets({ gen2Tilesets = { TILESET_GYM = true } }).TILESET_GYM,
    "Gen.tilesets prefers gen2Tilesets")

  -- bindGoldData bound gen2Palettes/gen2Icons/gen2Pokedex/gen2Landmarks/
  -- gen2Roofs/gen2Sprites through loadGen but never gen2Constants, so any
  -- mod reading mod.content.constants:get(...) under a save-editor Gold
  -- bootstrap saw an empty table where it expected the cart's ordered name
  -- lists.  loadGen falls back to require("data.generated.constants") when
  -- the ROM cache has nothing active, which is what a checkout with no
  -- ROM imported hits too -- stub that module the same way to prove the
  -- wiring without needing a real Gold extraction.
  package.loaded["data.generated.constants"] = { badges = { "ZEPHYR" } }
  local withConstants = Gen.bindGoldData({})
  package.loaded["data.generated.constants"] = nil
  check(withConstants.gen2Constants ~= nil,
    "bindGoldData populates gen2Constants")
  check(withConstants.gen2Constants and withConstants.gen2Constants.badges
    and withConstants.gen2Constants.badges[1] == "ZEPHYR",
    "gen2Constants carries the extractor's own name lists")
end

do
  local Map2 = require("src.world.gen2.Map")
  local MapPreview = require("src.world.gen2.MapPreview")
  local def = {
    id = "AZALEA_GYM", tileset = "TILESET_GYM",
    width = 1, height = 1, blocks = { 1 }, borderBlock = 1,
    warps = {}, environment = "INDOOR",
  }
  local tileset = {
    id = "TILESET_GYM",
    image = "assets/generated/tilesets/gym.png",
    tilesPerRow = 16,
    blocks = { { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 } },
  }
  local map = Map2.new(def, tileset)
  check(map.renderer == nil, "Map2 does not ship a renderer")
  local baker = MapPreview.baker({ tilesets = { TILESET_GYM = tileset } })
  local renderer = MapPreview.renderer(baker, map)
  check(renderer ~= nil and renderer.draw ~= nil,
    "MapPreview attaches a draw for a Gold map")
end

do
  local memfs = {
    files = {
      ["saves/gold/slot1.lua"] = 'return { version = "gold", generation = 2, player = { name = "GOLD" } }',
      ["options.lua"] = 'return { textSpeed = 3 }',
    },
    getInfo = function(self, path)
      return self.files[path] and { type = "file" } or nil
    end,
    read = function(self, path)
      return self.files[path]
    end,
    write = function(self, path, data)
      self.files[path] = data
      return true
    end,
    remove = function(self, path)
      self.files[path] = nil
      return true
    end,
  }
  local main, _, _ = SaveData.saveFilename("gold")
  check(main ~= nil, "saveFilename resolves for gold")
end

-- Gold's cache has no text_pointers / trainer_headers / field.  Data:load
-- used to throw in seedDefaults (self.field.boot) after filling pokemon
-- with provenance scalars.  That is the Android first-Edit CTD: the APK
-- cannot fall back to Red's source-tree copies the way a desktop checkout
-- can.
do
  GameVersion.set("gold")
  local Data = require("src.core.Data")
  Data.constants = {}
  Data.pokemon = { generation = 2, CYNDAQUIL = { dex = 155 } }
  Data.maps = {}
  Data.field = nil
  Data.trainer_headers = nil
  local ok, err = pcall(function() Data:seedDefaults() end)
  check(ok, "gold seedDefaults survives a Gold-shaped cache: " .. tostring(err))
  check(type(Data.field) == "table", "seedDefaults creates field when Gold omitted it")
  eq(Data.constants.dexSize, 155, "dexSize ignores pokemon.generation scalar")
  GameVersion.set("red")
end

print(string.format("save editor gen2 tests: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
