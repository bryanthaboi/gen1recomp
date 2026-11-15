-- Headless Gen 2 save-editor rules. Run from repo root:
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
local EventFlagOrder = require("tests.fixture_data.gen2_event_flag_order")
require("Gen2Flags").setSource(function(engine)
  return { eventFlagOrder = EventFlagOrder[engine] }
end)
local Save2 = require("src.core.gen2.Save")
local Bag = require("src.inventory.Bag")
local SaveData = require("src.core.SaveData")
local GameVersion = require("src.core.GameVersion")

local data = {
  text = require("tests.fixture_data.gen2_rom_text_s7_e"),
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
    POTION = { pocket = "ITEM", index = 20, name = "POTION" },
    MASTER_BALL = { pocket = "BALL", index = 1, name = "MASTER BALL" },
    FLOWER_MAIL = { pocket = "ITEM", index = 8, name = "FLOWER MAIL" },
    BICYCLE = { pocket = "KEY_ITEM", index = 6, name = "BICYCLE" },
    HM_01 = { pocket = "TM_HM", index = 249, name = "HM01" },
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
  eq(Gen.of({ version = "crystal" }), 2, "Gen.of version crystal")
  eq(Gen.of(SaveData.newGame()), 1, "Gen.of gen1 newGame")
  eq(Gen.of(Save2.newGame()), 2, "Gen.of gold newGame")
end

do
  GameVersion.set("silver")
  eq(Save2.newGame().version, "silver", "a silver boot stamps silver")
  local silverText = require("tests.fixture_data.gen2_rom_text_s7_c").text({ ["PlayerNameArray#1"] = "SILVER" })
  eq(Save2.newGame({ data = { text = silverText } }).player.name, "SILVER",
    "with silver's preset name from the cache")
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

for _, version in ipairs({ "gold", "silver", "crystal" }) do
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
  eq(S.status, "No more usable <PK><MN>!",
    "deposit refusal is PCString_NoMoreUsablePKMN")
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
  Ops.maxCoins(S)
  eq(S.save.player.coins, Ops.COIN_MAX, "maxCoins fills the case on player.coins")
  eq(S.save.coins, nil, "Gen 2 coins never land on save.coins")
end

do
  -- (ram/wram.asm:3115 wKeyItems, engine/items/tmhm.asm:390)
  local S = newState()
  Ops.addToBag(S, "POTION")
  Ops.addToBag(S, "MASTER_BALL")
  Ops.addToBag(S, "BICYCLE")
  Ops.addToBag(S, "HM_01")

  check(Ops.itemStacks(S, "POTION") == true, "an ITEM pocket row stacks")
  check(Ops.itemStacks(S, "MASTER_BALL") == true, "a BALL pocket row stacks")
  check(Ops.itemStacks(S, "BICYCLE") == false, "a KEY_ITEM pocket row does not")
  check(Ops.itemStacks(S, "HM_01") == false, "a Gen 2 HM prints no count either")
  S.dirty = false
  check(Ops.bagMax(S, "BICYCLE") == false, "bagMax refuses a Gen 2 key item")
  check(Ops.bagMax(S, "HM_01") == false, "bagMax refuses a Gen 2 HM")
  check(S.dirty == false, "a refused bagMax does not dirty the save")

  check(Ops.bagMaxAll(S) ~= false, "bagMaxAll fills the stackable pockets")
  eq(S.save.inventory.POTION, Ops.STACK_MAX, "the ITEM row is maxed")
  eq(S.save.inventory.MASTER_BALL, Ops.STACK_MAX, "the BALL row is maxed")
  eq(S.save.inventory.BICYCLE, 1, "the KEY_ITEM row is untouched")
  eq(S.save.inventory.HM_01, 1, "the HM row is untouched")
end

do
  -- (constants/item_data_constants.asm:41)
  local S = newState()
  Ops.addToBag(S, "MASTER_BALL")
  Ops.addToBag(S, "BICYCLE")
  Ops.addToBag(S, "POTION")
  Ops.addToBag(S, "FLOWER_MAIL")
  Ops.addToBag(S, "HM_01")

  check(Ops.bagSort(S, "index") ~= false, "bagSort runs on a gen2 bag")
  local order = Bag.order(S.save, S.data)
  local rank = { ITEM = 1, BALL = 2, KEY_ITEM = 3, TM_HM = 4 }
  local grouped = true
  for i = 2, #order do
    if rank[Bag.pocketOf(order[i - 1], S.data)]
        > rank[Bag.pocketOf(order[i], S.data)] then
      grouped = false
    end
  end
  check(grouped, "a sorted gen2 bag follows the PACK's own pocket order")
  eq(order[1], "FLOWER_MAIL", "the ITEM pocket sorts by item number inside itself")
  eq(order[2], "POTION", "and keeps the rest of that pocket in number order")
  eq(order[3], "MASTER_BALL", "the BALL pocket follows the ITEM pocket")
  eq(order[4], "BICYCLE", "then the KEY_ITEM pocket")
  eq(order[#order], "HM_01", "and the TM/HM pocket comes last")
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
  local g = love.graphics
  local original = { push = g.push, pop = g.pop, clear = g.clear, draw = g.draw, setScissor = g.setScissor }
  local clip, stack, clippedDraws = { 10, 186, 297, 328 }, {}, 0
  g.push = function(mode)
    stack[#stack + 1] = { clip = clip }
    original.push(mode)
  end
  g.pop = function()
    clip = stack[#stack].clip
    stack[#stack] = nil
    original.pop()
  end
  g.setScissor = function(x, y, w, h) clip = x and { x, y, w, h } or nil end
  g.clear = function(...)
    check(clip == nil, "map canvas clear ignores the editor's screen clip")
    original.clear(...)
  end
  g.draw = function(...)
    if clip then clippedDraws = clippedDraws + 1 end
    original.draw(...)
  end
  g.setColor(0.2, 0.3, 0.4, 0.5)
  local renderer = MapPreview.renderer(baker, map)
  check(clippedDraws == 0, "all preview tiles render without the editor's screen clip")
  check(clip and clip[1] == 10 and clip[2] == 186 and clip[3] == 297 and clip[4] == 328,
    "preview bake restores the editor's clipping region")
  local r, green, b, a = g.getColor()
  check(r == 0.2 and green == 0.3 and b == 0.4 and a == 0.5,
    "preview bake restores the caller's graphics color")
  for key, fn in pairs(original) do g[key] = fn end
  check(renderer ~= nil and renderer.draw ~= nil,
    "MapPreview attaches a draw for a Gold map")
  local S = newState("gold")
  S.data.maps, S.data.tilesets = { AZALEA_GYM = def }, { TILESET_GYM = tileset }
  S.mapId, S.mapSection, S.tab = "AZALEA_GYM", "view", "map"
  local Kit, Browser = require("Kit"), require("MapBrowser")
  local dimensions = g.getDimensions
  local width, height = 320, 568
  g.getDimensions = function() return width, height end
  Kit.layout(width, height); Kit.beginFrame(-1, -1, false, 0)
  Browser.draw(S, Kit, 10, 180, 300, 330)
  Kit.endFrame()
  local first = S._g2MapBaker.mapImages.AZALEA_GYM
  check(first and not first.released, "phone view creates a live preview canvas")
  width, height = 640, 360
  Kit.layout(width, height); Kit.beginFrame(-1, -1, false, 0)
  Browser.draw(S, Kit, 10, 10, 620, 300)
  Kit.endFrame()
  check(first.released, "resize retires the canvas whose pixels can be cleared by the window")
  check(S._g2MapBaker.mapImages.AZALEA_GYM ~= first,
    "resized viewer redraws the map into a fresh canvas")
  g.getDimensions = dimensions
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

do
  GameVersion.set("red")
  local NameText = require("tests.fixture_data.gen2_rom_text_s7_c")
  local crystalData = { text = NameText.text(nil, "crystal") }
  local silverData = { text = NameText.text({ ["PlayerNameArray#1"] = "SILVER" }) }
  local goldData = { text = NameText.text() }
  local crystal = Gen.newGame("crystal", crystalData)
  eq(crystal.version, "crystal", "Gen.newGame('crystal') stamps crystal")
  eq(crystal.generation, 2, "crystal stub is generation 2")
  eq(crystal.player.name, "CHRIS", "crystal stub takes MalePlayerNameArray#1 from the cache")
  eq(Gen.newGame("silver", silverData).version, "silver", "Gen.newGame('silver') stamps silver")
  eq(Gen.newGame("silver", silverData).player.name, "SILVER", "silver stub takes PlayerNameArray#1")
  eq(Gen.newGame("gold", goldData).player.name, "GOLD", "gold stub takes PlayerNameArray#1")
  eq(Gen.newGame("gold", { text = NameText.text({ ["PlayerNameArray#1"] = "ORO" }) }).player.name,
    "ORO", "a localized cache's first preset name is the stub's name")
  eq(Gen.newGame("blue").version, "blue", "Gen.newGame('blue') stamps blue")
  eq(Gen.newGame("yellow").version, "yellow", "Gen.newGame('yellow') stamps yellow")
  eq(Gen.newGame(nil).version, "red", "no version falls back to the active game")
  eq(Gen.newGame("nonsense").version, "red", "an unknown id is ignored")
end

do
  local crystal = Gen.newGame("crystal")
  local gold = Gen.newGame("gold")
  eq(Gen.versionOf(crystal), "crystal", "versionOf reads the save")
  eq(Gen.engineOf(crystal), "crystal", "crystal saves are the crystal lineage")
  eq(Gen.engineOf(gold), "gs", "gold saves are the gs lineage")
  eq(Gen.engineOf(Gen.newGame("silver")), "gs", "silver saves are the gs lineage")
  eq(Gen.editionLabel(crystal), "CRYSTAL", "edition label follows the save")
  eq(Gen.editionLabel(gold), "GOLD", "gold still labels GOLD")
  check(Gen.hasCaughtData(crystal), "crystal has caught data")
  check(not Gen.hasCaughtData(gold), "gold has no caught data")
  check(not Gen.hasCaughtData(SaveData.newGame()), "gen 1 has no caught data")
  check(Gen.hasPlayerGender(crystal), "crystal has a player gender")
  check(not Gen.hasPlayerGender(gold), "gold has no player gender")
end

do
  local Gen2Flags = require("Gen2Flags")
  local gs = Gen2Flags.byName("gs")
  local crys = Gen2Flags.byName("crystal")
  eq(gs.EVENT_BEAT_FALKNER, crys.EVENT_BEAT_FALKNER,
    "a shared event keeps one id in both lineages")
  check(gs.EVENT_BEAT_FALKNER ~= nil, "the gs table is populated")
  eq(gs.EVENT_GOT_RAINBOW_WING, 120, "Gold's EVENT_GOT_RAINBOW_WING")
  eq(crys.EVENT_GOT_RAINBOW_WING, 822, "Crystal renumbers EVENT_GOT_RAINBOW_WING")
  eq(gs.EVENT_TIN_TOWER_1F_SUICUNE, nil, "a Crystal-only event is absent on gs")
  eq(crys.EVENT_TIN_TOWER_1F_SUICUNE, 1970, "and resolves on crystal")
  eq(crys.EVENT_WADE_READY_FOR_REMATCH, nil, "a retired Gold event is absent on crystal")
  check(gs.EVENT_WADE_READY_FOR_REMATCH ~= nil, "and still resolves on gs")
  check(Gen2Flags.byName("crystal") == crys, "byName caches per lineage")
  check(Gen2Flags.byName("gold") == gs, "an unknown lineage reads as gs")
  local asked = {}
  Gen2Flags.setSource(function(engine)
    asked[#asked + 1] = engine
    return { eventFlagOrder = { [62] = "EVENT_FROM_THE_CACHE", [63] = false } }
  end)
  eq(Gen2Flags.byName("crystal").EVENT_FROM_THE_CACHE, 61,
    "names come from the cache's eventFlagOrder, index - 1")
  eq(asked[1], "crystal", "asked for the save's own lineage")
  Gen2Flags.setSource(function() return nil end)
  check(not pcall(Gen2Flags.byName, "gs"), "no cache for the lineage is an error, not an empty list")
  Gen2Flags.setSource(function(engine) return { eventFlagOrder = EventFlagOrder[engine] } end)
end

do
  local crystalNames = Catalog.gen2EventList("crystal")
  local goldNames = Catalog.goldEventList()
  local function has(list, name)
    for _, n in ipairs(list) do if n == name then return true end end
    return false
  end
  check(has(crystalNames, "EVENT_TIN_TOWER_1F_SUICUNE"),
    "the crystal event list names Crystal's own flags")
  check(not has(crystalNames, "EVENT_WADE_READY_FOR_REMATCH"),
    "the crystal event list drops Gold's retired flags")
  check(has(goldNames, "EVENT_WADE_READY_FOR_REMATCH"),
    "the gold event list keeps them")
  check(has(goldNames, "EVENT_BEAT_FALKNER"), "gold event list still has Falkner")
  check(#crystalNames > #goldNames, "Crystal has more event flags than Gold")
end

do
  local S = newState("crystal")
  local name = "EVENT_TIN_TOWER_1F_SUICUNE"
  Ops.setFlag(S, name, true)
  check(Gen.getFlag(S.save, name), "a Crystal-only event reads back set")
  eq(S.save.flags[name], nil, "and never lands as a string key")
  check(next(S.save.events) ~= nil, "it wrote the numeric bitfield")

  local G = newState("gold")
  Ops.setFlag(G, name, true)
  eq(G.save.flags[name], true, "the same name on Gold has no id and stays named")

  local moved = newState("crystal")
  Ops.setFlag(moved, "EVENT_GOT_RAINBOW_WING", true)
  local Events2 = require("src.world.gen2.Events")
  local ev = Events2.new()
  ev:restore(moved.save.events)
  check(ev:get(822), "EVENT_GOT_RAINBOW_WING sets Crystal's bit 822")
  check(not ev:get(120), "not Gold's bit 120")
end

do
  local S = newState("crystal")
  Ops.partyAdd(S)
  local mon = S.save.party[1]

  check(Ops.setCaughtTime(S, mon, 2), "caught time set")
  eq(mon.caughtTime, 2, "caught time DAY")
  check(S.dirty, "caught time dirties the save")
  check(not Ops.setCaughtTime(S, mon, 2), "re-setting the same time only says")
  Ops.setCaughtTime(S, mon, 9)
  eq(mon.caughtTime, 3, "caught time clamps to NITE")
  Ops.setCaughtTime(S, mon, -1)
  eq(mon.caughtTime, 0, "caught time clamps to unknown")

  Ops.setCaughtLevel(S, mon, 40)
  eq(mon.caughtLevel, 40, "caught level 40")
  Ops.setCaughtLevel(S, mon, 99)
  eq(mon.caughtLevel, 63, "caught level clamps to CAUGHT_LEVEL_MASK")

  Ops.setCaughtLocation(S, mon, 12)
  eq(mon.caughtLocation, 12, "caught location 12")
  Ops.setCaughtLocation(S, mon, -1)
  eq(mon.caughtLocation, 127, "stepping below 0 wraps to LANDMARK_EVENT")
  Ops.setCaughtLocation(S, mon, 128)
  eq(mon.caughtLocation, 0, "and stepping past the mask wraps back to unknown")

  Ops.setCaughtByGender(S, mon, "girl")
  eq(mon.caughtByGender, "girl", "caught by girl")
  Ops.setCaughtByGender(S, mon, "none")
  eq(mon.caughtByGender, nil, "caught by clears to nil, the Gold-save value")

  local Mon = require("src.battle.gen2.Mon")
  Ops.setCaughtTime(S, mon, 3)
  Ops.setCaughtLevel(S, mon, 20)
  Ops.setCaughtLocation(S, mon, 5)
  Ops.setCaughtByGender(S, mon, "girl")
  local byte0, byte1 = Mon.packCaughtData(mon)
  eq(byte0, 3 * 0x40 + 20, "the editor's fields pack into byte 0")
  eq(byte1, 0x80 + 5, "and into byte 1")
end

do
  local G = newState("gold")
  Ops.partyAdd(G)
  local mon = G.save.party[1]
  G.dirty = false
  check(not Ops.setCaughtTime(G, mon, 2), "Gold refuses caught time")
  eq(mon.caughtTime, nil, "and writes nothing")
  check(not Ops.setCaughtLevel(G, mon, 20), "Gold refuses caught level")
  check(not Ops.setCaughtLocation(G, mon, 5), "Gold refuses caught location")
  check(not Ops.setCaughtByGender(G, mon, "boy"), "Gold refuses caught gender")
  check(not G.dirty, "a refused caught edit never dirties")
end

do
  local S = newState("crystal")
  eq(Gen.playerGender(S.save), "male", "a new Crystal save starts male")
  check(Ops.setPlayerGender(S, "female"), "player gender set")
  eq(S.save.player.gender, "female", "written to save.player.gender")
  check(not Ops.setPlayerGender(S, "female"), "re-setting the same gender only says")
  Ops.setPlayerGender(S, "male")
  eq(Gen.playerGender(S.save), "male", "and back")

  local G = newState("gold")
  check(not Ops.setPlayerGender(G, "female"), "Gold refuses a gender change")
  eq(G.save.player.gender, "male", "Gold's field is left alone")
end

do
  local landmarks = {
    gen2Landmarks = {
      landmarks = {
        LANDMARK_AZALEA_TOWN = { id = "LANDMARK_AZALEA_TOWN", index = 12,
                                 name = "AZALEA TOWN" },
        LANDMARK_BURNED_TOWER = { id = "LANDMARK_BURNED_TOWER", index = 24,
                                  name = "BURNED\nTOWER" },
      },
    },
  }
  eq(Gen.landmarkName(landmarks, 12), "AZALEA TOWN", "landmark by index")
  eq(Gen.landmarkName(landmarks, 24), "BURNED TOWER", "two-line names flatten")
  eq(Gen.landmarkName(landmarks, 0), "UNKNOWN", "0 reads as unknown")
  eq(Gen.landmarkName(landmarks, 0x7e), "GIFT", "LANDMARK_GIFT")
  eq(Gen.landmarkName(landmarks, 0x7f), "EVENT", "LANDMARK_EVENT")
  eq(Gen.landmarkName(landmarks, 99), "#99", "an unmapped index shows its number")
end

do
  local Kit = require("Kit")
  local MonEditor = require("MonEditor")
  local ItemsPanel = require("Items")

  local function clipped(r)
    local x1, y1, x2, y2 = r.x, r.y, r.x + r.w, r.y + r.h
    if r.clip then
      x1 = math.max(x1, r.clip.x); y1 = math.max(y1, r.clip.y)
      x2 = math.min(x2, r.clip.x + r.clip.w); y2 = math.min(y2, r.clip.y + r.clip.h)
    end
    if x2 - x1 <= 1 or y2 - y1 <= 1 then return nil end
    return x1, y1, x2, y2
  end

  local function overlap(a, b)
    local ax1, ay1, ax2, ay2 = clipped(a)
    if not ax1 then return false end
    local bx1, by1, bx2, by2 = clipped(b)
    if not bx1 then return false end
    return math.min(ax2, bx2) - math.max(ax1, bx1) > 1
       and math.min(ay2, by2) - math.max(ay1, by1) > 1
  end

  local function auditFrame(label, W, H)
    local controls = {}
    for _, r in ipairs(Kit.audit or {}) do
      if r.class == "control" then controls[#controls + 1] = r end
    end
    check(#controls > 0, label .. ": the frame dispatched controls at all")
    local collisions, escapes = 0, 0
    for i = 1, #controls do
      local a = controls[i]
      local x1, y1, x2, y2 = clipped(a)
      if x1 and (x1 < -0.5 or y1 < -0.5 or x2 > W + 0.5 or y2 > H + 0.5) then
        escapes = escapes + 1
        print(("  escape: %s (%.0f,%.0f %.0fx%.0f)")
          :format(a.label, a.x, a.y, a.w, a.h))
      end
      for j = i + 1, #controls do
        if overlap(a, controls[j]) then
          collisions = collisions + 1
          print(("  overlap: '%s' vs '%s' at (%.0f,%.0f) / (%.0f,%.0f)")
            :format(a.label, controls[j].label, a.x, a.y,
              controls[j].x, controls[j].y))
        end
      end
    end
    check(collisions == 0, label .. ": no two controls overlap")
    check(escapes == 0, label .. ": every control stays inside the panel")
  end

  local sizes = { { 420, 700 }, { 640, 768 }, { 1280, 720 } }
  for _, version in ipairs({ "gold", "crystal" }) do
    for _, size in ipairs(sizes) do
      local W, H = size[1], size[2]
      local S = newState(version)
      Ops.partyAdd(S)
      Ops.selectParty(S, 1)
      Ops.addToBag(S, S.cat.items[1])
      Ops.addToPc(S, S.cat.items[2])
      Kit.layout(W, H)
      for _, panel in ipairs({ { "inspector", MonEditor }, { "items", ItemsPanel } }) do
        local label = ("%s %dx%d %s"):format(version, W, H, panel[1])
        Kit.beginFrame(-100, -100, false, 0)
        Kit.audit = {}
        local ok, err = pcall(panel[2].draw, S, Kit, 0, 0, W, H)
        check(ok, label .. " draws: " .. tostring(err))
        if ok then
          Kit.beginFrame(-100, -100, false, 0)
          Kit.audit = {}
          ok, err = pcall(panel[2].draw, S, Kit, 0, 0, W, H)
          check(ok, label .. " redraws: " .. tostring(err))
        end
        if ok then auditFrame(label, W, H) end
        Kit.audit = nil
      end
    end
  end

  local S = newState("crystal")
  Ops.partyAdd(S)
  Ops.selectParty(S, 1)
  Kit.layout(1280, 720)
  Kit.beginFrame(-100, -100, false, 0)
  Kit.audit = {}
  S.monSection="origin"
  MonEditor.draw(S, Kit, 0, 0, 1280, 720)
  local timeChoice=false
  for _, r in ipairs(Kit.audit) do if r.id == "choice-caughtTime" then timeChoice=true end end
  Kit.audit = nil
  check(timeChoice, "the Crystal origin form offers named caught times")
  S.inspectorScroll=300
  Kit.audit={}
  MonEditor.draw(S,Kit,0,0,1280,720)
  local caughtGender=false
  for _,r in ipairs(Kit.audit) do if r.id == "caught-by-boy" then caughtGender=true end end
  Kit.audit=nil
  check(caughtGender,"and the caught-by gender control")

  local G = newState("gold")
  Ops.partyAdd(G)
  Ops.selectParty(G, 1)
  Kit.beginFrame(-100, -100, false, 0)
  Kit.audit = {}
  MonEditor.draw(G, Kit, 0, 0, 1280, 720)
  local goldLabels = {}
  for _, r in ipairs(Kit.audit) do goldLabels[r.label] = true end
  Kit.audit = nil
  check(not goldLabels.MORN, "the Gold inspector has no caught row")

  local function itemsLabels(state)
    Kit.beginFrame(-100, -100, false, 0)
    Kit.audit = {}
    ItemsPanel.draw(state, Kit, 0, 0, 1280, 720)
    local seen = {}
    for _, r in ipairs(Kit.audit) do seen[r.label] = true end
    Kit.audit = nil
    return seen
  end
  Kit.audit={}
  require("Trainer").draw(S,Kit,0,0,1280,720)
  local trainerGender=false
  for _,r in ipairs(Kit.audit) do if r.label=="FEMALE" then trainerGender=true end end
  Kit.audit=nil
  check(trainerGender,"the Crystal Trainer tab carries the gender control")
  check(not itemsLabels(G).GIRL, "the Gold Items tab does not")

  local function bottomOverflow(state)
    local H = 380
    Kit.layout(640, H)
    state.inspectorScroll = 100000
    for _ = 1, 2 do
      Kit.beginFrame(-100, -100, false, 0)
      Kit.audit = {}
      MonEditor.draw(state, Kit, 0, 0, 640, H)
    end
    local lowest = 0
    for _, r in ipairs(Kit.audit) do
      if r.class == "control" then lowest = math.max(lowest, r.y + r.h) end
    end
    Kit.audit = nil
    return math.floor(lowest - H + 0.5)
  end
  local goldOver = bottomOverflow(G)
  local over = bottomOverflow(S)
  check(over <= 0 and over >= -60,
    "the caught rows are fully counted in the inspector's scroll height (" .. over .. ")")
  check(goldOver <= 4, ("the inspector reaches its last control (%d px short)")
    :format(goldOver))
end

local function readable(path)
  local fh = io.open(path, "r")
  if not fh then return false end
  fh:close()
  return true
end

do
  local goldAsm = (os.getenv("POKEGOLD") or "../pokegold")
    .. "/constants/event_flags.asm"
  local crystalAsm = (os.getenv("POKECRYSTAL") or "../pokecrystal")
    .. "/constants/event_flags.asm"
  if readable(goldAsm) and readable(crystalAsm) and readable("tools/goldwalk/flags.lua") then
    local Flags = dofile("tools/goldwalk/flags.lua")
    for engine, path in pairs({ gs = goldAsm, crystal = crystalAsm }) do
      local pret = Flags.parse(path)
      local fixture = require("Gen2Flags").byName(engine)
      local wrong, n, m = 0, 0, 0
      for name, id in pairs(pret) do
        n = n + 1
        if fixture[name] ~= id then wrong = wrong + 1 end
      end
      for _ in pairs(fixture) do m = m + 1 end
      eq(wrong, 0, engine .. ": the event flag fixture is pret's whole list")
      eq(m, n, engine .. ": and nothing more")
    end
  else
    check(true, "pokegold / pokecrystal absent : fixture cross-check SKIPPED")
  end
  local CacheConstants = require("tests.cache_gen2_constants")
  local FlagIds = require("src.core.gen2.FlagIds")
  for engine, version in pairs({ gs = "gold", crystal = "crystal" }) do
    local constants = CacheConstants.load(version)
    if constants and constants.eventFlagOrder then
      local fromCache = FlagIds.events(constants)
      local fixture = require("Gen2Flags").byName(engine)
      local wrong = 0
      for name, id in pairs(fromCache) do if fixture[name] ~= id then wrong = wrong + 1 end end
      for name, id in pairs(fixture) do if fromCache[name] ~= id then wrong = wrong + 1 end end
      eq(wrong, 0, version .. ": the cache's eventFlagOrder is the fixture's")
    else
      check(true, version .. " cache absent or older than eventFlagOrder : SKIPPED")
    end
  end
end

do
  local Gen2Flags = require("Gen2Flags")
  local cache = os.getenv("CRYSTAL_CACHE")
    or require("tests.cache_gen2_constants").root("crystal") or ""
  local initialPath = cache .. "/data/generated/initial_events.lua"
  local stdScripts = (os.getenv("POKECRYSTAL") or "../pokecrystal")
    .. "/engine/events/std_scripts.asm"
  if readable(initialPath) and readable(stdScripts) then
    local Flags = dofile("tools/goldwalk/flags.lua")
    local romIds = assert(loadfile(initialPath))().flags
    -- InitializeEventsScript sets EVENT_AZALEA_TOWN_KURT twice in a row
    -- (../pokecrystal/engine/events/std_scripts.asm:575-576).
    local names = {}
    for _, n in ipairs(Flags.setEventsOf(stdScripts, "InitializeEventsScript")) do
      if names[#names] ~= n then names[#names + 1] = n end
    end
    local byName = Gen2Flags.byName("crystal")
    eq(#names, #romIds, "InitializeEventsScript sets as many flags as the cart")
    local mismatches, lo, hi = 0, math.huge, -math.huge
    for i, name in ipairs(names) do
      local got = romIds[i]
      if got then lo, hi = math.min(lo, got), math.max(hi, got) end
      if byName[name] ~= got then
        mismatches = mismatches + 1
        if mismatches <= 5 then
          print(("  #%d %s table=%s cart=%s")
            :format(i, name, tostring(byName[name]), tostring(got)))
        end
      end
    end
    eq(mismatches, 0,
      ("crystal names == cart ids across %d..%d"):format(lo, hi))
  else
    check(true, "crystal cache absent : cart cross-check SKIPPED")
  end
end

for _, version in ipairs({ "gold", "silver", "crystal" }) do
  local S = newState(version)
  S.data = require("src.mods.Merge").deepCopy(data)
  S.data.maps = { ROUTE_29 = { landmark = 3 } }
  S.data.encounters = {
    grass = { ROUTE_29 = { slots = { NITE = { { species = "TOTODILE", level = 5 } } } } },
    fishGroups = { NO_MAP = { { species = "CYNDAQUIL", level = 90 } } },
  }
  Ops.partyAdd(S)
  local mon = S.save.party[1]
  Ops.setHeldItem(S, mon, "FLOWER_MAIL")
  mon.level, mon.hp, mon.dvs.attack, mon.statExp.hp, mon.pokerus = 110, -10, 20, 999999, 255
  check(Ops.fixMonErrors(S, mon), version .. " repairs malformed properties")
  eq(require("Legality").mon(S, mon).errors, 0, version .. " repaired values pass validator")
  check(Ops.maxMon(S, mon), version .. " max out succeeds")
  eq(mon.level, 100, version .. " max reaches level 100")
  eq(mon.happiness, 255, version .. " max fills friendship")
  eq(mon.statExp.hp, 65535, version .. " max fills stat experience")
  eq(mon.dvs.attack, 15, version .. " max fills DVs")
  eq(require("Legality").mon(S, mon).errors, 0, version .. " maxed values pass validator")
  check(Ops.randomizeMon(S, mon), version .. " randomize succeeds with native DV properties")
  eq(mon.species, "TOTODILE", version .. " randomize uses available encounters")
  eq(mon.level, 5, version .. " randomize uses encounter level")
  if version == "crystal" then
    eq(mon.caughtLocation, 3, "Crystal randomize keeps the encounter landmark")
    eq(mon.caughtTime, 3, "Crystal randomize keeps the nighttime slot")
  end
  eq(require("Legality").mon(S, mon).errors, 0, version .. " random values pass validator")
  eq(require("src.core.gen2.Mail").state(S.save).party[1], nil,
    version .. " randomize clears the replaced held mail")
end

print(string.format("save editor gen2 tests: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
