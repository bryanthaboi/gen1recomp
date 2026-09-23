-- Headless Gen 3 (FireRed) save-editor and launcher slot summary tests.
-- Run with: luajit tests/save_editor_gen3_tests.lua

package.path = package.path .. ";./?.lua;./?/init.lua;./tools/save-editor/?.lua"
  .. ";./tools/save-editor/panels/?.lua"

require("tests.love_stub")

local SaveData = require("src.core.SaveData")
local GameVersion = require("src.core.GameVersion")
local Gen = require("Gen")
local MonOps = require("MonOps")
local Catalog = require("Catalog")
local Ops = require("Ops")
local Flags = require("src.core.game3.scripting.flags")
local Schema = require("src.core.game3.save_schema_firered")

local passed = 0
local failed = 0

local function check(cond, msg)
  if cond then
    passed = passed + 1
  else
    failed = failed + 1
    print("FAIL: " .. tostring(msg))
  end
end

local function checkEq(actual, expected, msg)
  if actual == expected then
    passed = passed + 1
  else
    failed = failed + 1
    print(("FAIL: %s (got %s, want %s)"):format(tostring(msg), tostring(actual), tostring(expected)))
  end
end

print("== save editor gen3 tests ==")

-- --------------------------------------------------------------------------
-- 1. Launcher Slot Summary
-- --------------------------------------------------------------------------
do
  local save = {
    version = "firered",
    engine = "game3",
    generation = 3,
    name = "ASH",
    dex = {
      seen = { [1] = true, [4] = true, [7] = true, [25] = true },
      owned = { [1] = true, [4] = true, [25] = true },
    },
    playTime = { hours = 14, minutes = 25, seconds = 30 },
    flags = {
      [0x820] = true, -- BOULDER
      [0x821] = true, -- CASCADE
      [0x822] = true, -- THUNDER
    },
  }

  local name, meta = SaveData.slotSummary(save)
  checkEq(name, "ASH", "slotSummary derives player name")
  checkEq(meta.dexCount, 3, "slotSummary derives Gen 3 dex count from dex.owned")
  checkEq(meta.timeText, "14:25", "slotSummary formats Gen 3 playTime table")
  checkEq(meta.badges, 3, "slotSummary counts Gen 3 badges from flags")
end

-- Slot summary with string flag keys and playtime field
do
  local save = {
    version = "firered",
    playerName = "RED",
    dex = {
      caught = { ["BULBASAUR"] = true, ["CHARMANDER"] = true },
    },
    playtime = { hours = 2, minutes = 5, seconds = 0 },
    flags = {
      ["2080"] = true, -- 0x820
      ["2081"] = true, -- 0x821
      ["2082"] = true, -- 0x822
      ["2083"] = true, -- 0x823
      ["2084"] = true, -- 0x824
    },
  }

  local name, meta = SaveData.slotSummary(save)
  checkEq(name, "RED", "slotSummary derives playerName")
  checkEq(meta.dexCount, 2, "slotSummary derives dex count from dex.caught")
  checkEq(meta.timeText, "2:05", "slotSummary formats playtime")
  checkEq(meta.badges, 5, "slotSummary counts badges from string flag keys")
end

-- --------------------------------------------------------------------------
-- 2. Gen.of and Generation Helpers
-- --------------------------------------------------------------------------
do
  checkEq(Gen.of({ version = "firered" }), 3, "Gen.of returns 3 for version=firered")
  checkEq(Gen.of({ engine = "game3" }), 3, "Gen.of returns 3 for engine=game3")
  checkEq(Gen.of({ generation = 3 }), 3, "Gen.of returns 3 for generation=3")
  checkEq(Gen.of(nil, "firered"), 3, "Gen.of returns 3 for version arg firered")
  check(Gen.hasPlayerGender({ version = "firered" }), "Gen.hasPlayerGender true for FireRed")
  checkEq(Gen.boxCount({ version = "firered" }), 14, "Gen.boxCount returns 14 for FireRed")
  checkEq(Gen.boxCapacity({ version = "firered" }), 30, "Gen.boxCapacity returns 30 for FireRed")
end

-- --------------------------------------------------------------------------
-- 3. Data Binding (Gen.bindGame3Data)
-- --------------------------------------------------------------------------
require("tests.game3_cache").mountOrSkip("save_editor_gen3_tests")
local mockData = {}
Gen.bindGame3Data(mockData)

do
  check(type(mockData.pokemon) == "table", "bindGame3Data creates pokemon catalog")
  check(mockData.pokemon.BULBASAUR ~= nil or mockData.pokemon[1] ~= nil, "pokemon catalog has Bulbasaur")
  check(mockData.pokemon.CHARIZARD ~= nil or mockData.pokemon[6] ~= nil, "pokemon catalog has Charizard")

  check(type(mockData.moves) == "table", "bindGame3Data creates moves catalog")
  check(type(mockData.items) == "table", "bindGame3Data creates items catalog")
  check(type(mockData.game3Maps) == "table" or type(mockData.maps) == "table", "bindGame3Data creates maps catalog")
end

-- --------------------------------------------------------------------------
-- 4. Pokémon Creation & Editing with MonOps
-- --------------------------------------------------------------------------
do
  local mon = MonOps.create(mockData, 6, 50, 3) -- Charizard Lv50
  check(type(mon) == "table", "MonOps.create creates Gen 3 mon")
  checkEq(mon.level, 50, "mon level is 50")
  check(mon.stats ~= nil, "mon stats populated")
  check(mon.stats.hp > 0, "mon HP calculated")
  check(mon.stats.attack > 0, "mon attack calculated")
  check(mon.stats.defense > 0, "mon defense calculated")
  check(mon.stats.specialAttack > 0, "mon specialAttack calculated")
  check(mon.stats.specialDefense > 0, "mon specialDefense calculated")
  check(mon.stats.speed > 0, "mon speed calculated")
  check(#mon.moves > 0, "mon has default moves at Lv50")

  -- Set Level
  local prevHp = mon.stats.hp
  MonOps.setLevel(mockData, mon, 100, 3)
  checkEq(mon.level, 100, "mon level updated to 100")
  check(mon.stats.hp > prevHp, "Lv100 stats higher than Lv50")

  -- Set Species
  MonOps.setSpecies(mockData, mon, 9, 3) -- Blastoise
  checkEq(mon.speciesId, 9, "mon speciesId updated to 9")
  check(mon.name == "BLASTOISE" or mon.species == "BLASTOISE", "mon name updated to BLASTOISE")

  -- Set Move
  MonOps.setMove(mockData, mon, 1, 57) -- Surf
  checkEq(require("src.core.game3.pokemon").moveIdAt(mon, 1), 57, "move 1 set to Surf (57)")
  check(mon.pp[1] > 0, "move 1 PP initialized")

  -- Set DVs / IVs
  MonOps.setDv(mockData, mon, "attack", 15, 3)
  checkEq(mon.dvs.attack, 15, "mon attack DV set to 15")
  checkEq(mon.ivs.atk, 31, "mon attack IV mapped to 31")
end

-- --------------------------------------------------------------------------
-- 5. Badge Operations
-- --------------------------------------------------------------------------
do
  local save = Schema.newGame({ name = "RED" })
  local badgeIds = Gen.badgeIds(save, nil)
  checkEq(#badgeIds, 8, "Gen.badgeIds returns 8 Kanto badges")

  checkEq(Gen.hasBadge(save, "BOULDERBADGE"), false, "new game has no Boulder Badge")
  checkEq(Gen.hasBadge(save, "CASCADEBADGE"), false, "new game has no Cascade Badge")

  -- Toggle Boulder Badge ON
  local nowOn = Gen.toggleBadge(save, "BOULDERBADGE")
  checkEq(nowOn, true, "toggleBadge turns Boulder Badge ON")
  checkEq(Gen.hasBadge(save, "BOULDERBADGE"), true, "hasBadge confirms Boulder Badge ON")
  checkEq(Flags.hasBadge(save, "BOULDER"), true, "Flags.hasBadge confirms Boulder ON")

  -- Toggle Cascade Badge ON
  Gen.toggleBadge(save, "CASCADEBADGE")
  checkEq(Gen.hasBadge(save, "CASCADEBADGE"), true, "Cascade Badge ON")

  -- Slot summary badge count
  local _, meta = SaveData.slotSummary(save)
  checkEq(meta.badges, 2, "slotSummary reflects 2 badges earned")

  -- Toggle Boulder Badge OFF
  local nowOff = Gen.toggleBadge(save, "BOULDERBADGE")
  checkEq(nowOff, false, "toggleBadge turns Boulder Badge OFF")
  checkEq(Gen.hasBadge(save, "BOULDERBADGE"), false, "Boulder Badge is now OFF")

  local _, meta2 = SaveData.slotSummary(save)
  checkEq(meta2.badges, 1, "slotSummary reflects 1 badge earned")
end

-- --------------------------------------------------------------------------
-- 6. Map & Location Operations
-- --------------------------------------------------------------------------
do
  local save = Schema.newGame({ name = "RED" })
  local map, x, y, facing = Gen.playerMap(save)
  check(map ~= nil, "playerMap returns map")
  check(type(x) == "number", "playerMap returns numeric x")
  check(type(y) == "number", "playerMap returns numeric y")

  -- Move player to Pewter City
  Gen.setPlayerHere(save, "FR_PEWTER_CITY", 14, 25, "up")
  local newMap, nx, ny, nFacing = Gen.playerMap(save)
  checkEq(newMap, "FR_PEWTER_CITY", "setPlayerHere updates map to FR_PEWTER_CITY")
  checkEq(nx, 14, "setPlayerHere updates x to 14")
  checkEq(ny, 25, "setPlayerHere updates y to 25")
  checkEq(nFacing, "up", "setPlayerHere updates facing to up")
  checkEq(save.position.map, "FR_PEWTER_CITY", "save.position.map in sync")

  -- Ops.setLastHeal
  local state = { save = save, mapId = "FR_CERULEAN_CITY", mapClickCell = { cx = 19, cy = 17 } }
  Ops.setLastHeal(state)
  checkEq(save.healMap, "FR_CERULEAN_CITY", "Ops.setLastHeal updates save.healMap")
  checkEq(save.healX, 19, "Ops.setLastHeal updates save.healX")
  checkEq(save.healY, 17, "Ops.setLastHeal updates save.healY")
end

-- --------------------------------------------------------------------------
-- 7. Flags & Events
-- --------------------------------------------------------------------------
do
  local save = Schema.newGame({ name = "RED" })
  checkEq(Gen.getFlag(save, "FLAG_GOT_STARTER"), false, "FLAG_GOT_STARTER false initially")

  Gen.setFlag(save, "FLAG_GOT_STARTER", true)
  checkEq(Gen.getFlag(save, "FLAG_GOT_STARTER"), true, "Gen.getFlag reads set flag")

  Gen.setFlag(save, "FLAG_GOT_STARTER", false)
  checkEq(Gen.getFlag(save, "FLAG_GOT_STARTER"), false, "Gen.getFlag reads cleared flag")

  local events = Catalog.game3EventList()
  check(type(events) == "table", "Catalog.game3EventList returns table")
  check(#events > 50, "game3EventList contains many game3 flags")
end

-- --------------------------------------------------------------------------
-- 8. Money & Coins Operations
-- --------------------------------------------------------------------------
do
  local save = Schema.newGame({ name = "RED" })
  checkEq(Gen.money(save), 3000, "initial money is 3000")
  Gen.setMoney(save, 50000)
  checkEq(Gen.money(save), 50000, "setMoney updates money to 50000")
  checkEq(save.money, 50000, "save.money is 50000")

  checkEq(Gen.coins(save), 0, "initial coins is 0")
  Gen.setCoins(save, 9999)
  checkEq(Gen.coins(save), 9999, "setCoins updates coins to 9999")
  checkEq(save.coins, 9999, "save.coins is 9999")
end

-- --------------------------------------------------------------------------
-- 9. Gender Operations
-- --------------------------------------------------------------------------
do
  local save = Schema.newGame({ name = "RED", gender = 0 })
  checkEq(Gen.playerGender(save), "male", "gender 0 is male")
  Gen.setPlayerGender(save, "female")
  checkEq(Gen.playerGender(save), "female", "setPlayerGender updates to female")
  checkEq(save.gender, 1, "save.gender is 1")
end

-- --------------------------------------------------------------------------
-- 10. Save Encoding & Decoding Round-Trip
-- --------------------------------------------------------------------------
do
  local save = Schema.newGame({ name = "RED" })
  Gen.setMoney(save, 77777)
  Gen.setCoins(save, 500)
  Gen.setPlayerHere(save, "FR_CELADON_CITY", 20, 15, "right")
  Gen.toggleBadge(save, "RAINBOWBADGE")
  Gen.setFlag(save, "FLAG_SYS_POKEDEX_GET", true)

  local mon = MonOps.create(mockData, 25, 25, 3) -- Pikachu Lv25
  save.party = { mon }
  save.dex = { owned = { [25] = true }, seen = { [25] = true } }
  save.playTime = { hours = 5, minutes = 45, seconds = 12 }

  local encoded = SaveData.encode(save)
  check(type(encoded) == "string" and #encoded > 0, "SaveData.encode produces valid string")

  local decoded = SaveData.decode(encoded)
  check(type(decoded) == "table", "SaveData.decode decodes back to table")
  checkEq(decoded.money, 77777, "round-trip preserves money")
  checkEq(decoded.coins, 500, "round-trip preserves coins")
  checkEq(decoded.map, "FR_CELADON_CITY", "round-trip preserves map")
  checkEq(decoded.x, 20, "round-trip preserves x")
  checkEq(decoded.y, 15, "round-trip preserves y")
  checkEq(Gen.hasBadge(decoded, "RAINBOWBADGE"), true, "round-trip preserves Rainbow Badge")
  checkEq(Gen.getFlag(decoded, "FLAG_SYS_POKEDEX_GET"), true, "round-trip preserves Pokedex flag")

  local name, meta = SaveData.slotSummary(decoded)
  checkEq(name, "RED", "round-trip slotSummary name")
  checkEq(meta.dexCount, 1, "round-trip slotSummary dexCount")
  checkEq(meta.timeText, "5:45", "round-trip slotSummary timeText")
  checkEq(meta.badges, 1, "round-trip slotSummary badges")
end

-- --------------------------------------------------------------------------
-- 11. App.load Full Integration Test
-- --------------------------------------------------------------------------
do
  local prevLove = _G.love
  _G.love = _G.love or {}
  _G.love.filesystem = _G.love.filesystem or {
    getSaveDirectory = function() return "." end,
    getInfo = function() return nil end,
    getDirectoryItems = function() return {} end,
    read = function() return nil end,
    exists = function() return false end,
  }
  local App = require("tools.save-editor.App")
  local ok, err = pcall(App.load, nil, { version = "firered", slotId = "slot1", embedded = true })
  check(ok, "App.load runs without error on firered: " .. tostring(err))
  local S = App.getState()
  check(S ~= nil, "App state created")
  checkEq(Gen.of(S.save, S.version), 3, "App state save is Gen 3")
  check(type(S.cat) == "table", "App state has Catalog")
  check(#S.cat.species > 150, "App state catalog has all species")
  check(#S.cat.moves > 165, "App state catalog has all moves")
  check(#S.cat.items > 50, "App state catalog has all items")
  check(#S.events > 100, "App state has game3 events")
  App.unload()
  _G.love = prevLove
end

-- --------------------------------------------------------------------------
-- 12. Mon Hydration & Name Normalization with Numeric Species
-- --------------------------------------------------------------------------
do
  local rawMon = {
    species = 1, -- Bulbasaur numeric ID
    speciesId = 1,
    level = 5,
    ivs = { hp = 15, atk = 14, def = 13, spe = 12, spa = 11, spd = 10 },
  }
  Gen.hydrateMon(mockData, rawMon)
  checkEq(rawMon.species, 1, "hydrateMon preserves native numeric species")
  checkEq(rawMon.speciesId, 1, "hydrateMon preserves speciesId = 1")
  check(type(rawMon.dvs) == "table", "hydrateMon creates dvs table")
  checkEq(rawMon.dvs.attack, 7, "hydrateMon computes attack DV from IV")
  checkEq(rawMon.dvs.defense, 6, "hydrateMon computes defense DV from IV")
  check(rawMon.stats ~= nil and rawMon.stats.hp > 0, "hydrateMon computes valid stats")
end

-- --------------------------------------------------------------------------
-- 13. MonEditor & Species Usability Tests
-- --------------------------------------------------------------------------
do
  local S = {
    data = mockData,
    version = "firered",
    save = Schema.newGame({ name = "RED" }),
  }
  checkEq(Ops.speciesUsable(S, "BULBASAUR"), true, "BULBASAUR is usable in Gen 3")
  checkEq(Ops.speciesUsable(S, 1), true, "Numeric species 1 is usable in Gen 3")
  checkEq(Ops.speciesUsable(S, "CHARIZARD"), true, "CHARIZARD is usable in Gen 3")
  checkEq(Ops.speciesUsable(S, "MEWTWO"), true, "MEWTWO is usable in Gen 3")
  checkEq(Ops.speciesUsable(S, 384), true, "Rayquaza (384) is usable in Gen 3")

  local mon = MonOps.create(mockData, "BULBASAUR", 5, 3)
  S.editingMon = mon
  check(mon.dvs ~= nil, "created mon has dvs")

  -- Test MonOps.setSpecies
  Ops.setSpecies(S, mon, "CHARMANDER")
  checkEq(mon.species, 4, "Ops.setSpecies updates to numeric CHARMANDER")
  checkEq(mon.speciesId, 4, "Ops.setSpecies updates speciesId to 4")
end

-- --------------------------------------------------------------------------
-- 14. MapBrowser Gen 3 Map Adapter & inBounds Safety
-- --------------------------------------------------------------------------
do
  local save = Schema.newGame({ name = "RED" })
  local S = {
    data = mockData,
    version = "firered",
    save = save,
    mapId = "FR_PALLET_TOWN",
    mapZoom = 2,
    mapCamX = 0,
    mapCamY = 0,
  }
  local def = Gen.maps(mockData)[S.mapId]
  check(def ~= nil, "FR_PALLET_TOWN def exists in mockData")

  local mw = def.width or 20
  local mh = def.height or 18
  local midLayout = def.midLayout
  local map = {
    id = S.mapId,
    def = def,
    width = mw,
    height = mh,
    widthCells = mw,
    heightCells = mh,
    warps = def.warps or {},
    inBounds = function(self, cx, cy)
      return cx >= 0 and cx < self.width and cy >= 0 and cy < self.height
    end,
    warpAtCell = function(self, cx, cy)
      for _, w in ipairs(self.warps or {}) do
        if w.x == cx and w.y == cy then return { def = w } end
      end
      return nil
    end,
    tileAtCell = function(self, cx, cy)
      if midLayout and midLayout.midAt then
        return midLayout:midAt(cx, cy) or 0
      end
      return 0
    end,
  }

  check(map:inBounds(5, 5) == true, "inBounds true for (5,5)")
  check(map:inBounds(-1, 5) == false, "inBounds false for (-1,5)")
  check(map:inBounds(100, 100) == false, "inBounds false for (100,100)")
  check(map:tileAtCell(5, 5) ~= nil, "tileAtCell returns tile")
end

-- --------------------------------------------------------------------------
-- 15. Bag, PC, & Items Panel Operations
-- --------------------------------------------------------------------------
do
  local save = Schema.newGame({ name = "RED" })
  local S = {
    data = mockData,
    version = "firered",
    save = save,
    cat = Catalog.build(mockData, save, "firered"),
  }
  Gen.hydrateSave(mockData, save)
  check(type(save.inventory) == "table", "save.inventory initialized")
  check(type(save.pcItems) == "table", "save.pcItems initialized")

  -- Add to bag
  Ops.addToBag(S, "POTION")
  checkEq(save.inventory["13"], 1, "POTION added to bag x1")
  check(save.bag ~= nil and save.bag.stacks ~= nil, "save.bag updated")

  -- Adjust bag quantity
  Ops.bagAdjust(S, "POTION", 4)
  checkEq(save.inventory["13"], 5, "POTION adjusted to x5")

  -- Max bag stack
  Ops.bagMax(S, "POTION")
  checkEq(save.inventory["13"], 999, "POTION maxed to 999")

  -- Drop bag item
  Ops.bagDrop(S, "POTION")
  checkEq(save.inventory["13"], nil, "POTION dropped from bag")

  -- PC operations
  Ops.addToPc(S, "POKE_BALL")
  checkEq(save.pcItems["4"], 1, "POKE_BALL added to PC x1")
  check(save.storage ~= nil and #save.storage.items > 0, "save.storage.items synced")

  Ops.pcAdjust(S, "POKE_BALL", 9)
  checkEq(save.pcItems["4"], 10, "POKE_BALL adjusted to x10 in PC")

  Ops.pcMax(S, "POKE_BALL")
  checkEq(save.pcItems["4"], 999, "POKE_BALL maxed in PC")

  -- Test numeric item IDs in Bag.order, Bag.slots, and isBadge
  save.inventory[13] = 5 -- Potion numeric ID
  save.inventory[4] = 10 -- Poke Ball numeric ID
  save.inventory["BOULDERBADGE"] = true -- Badge string flag

  local Bag = require("src.inventory.Bag")
  checkEq(Bag.isBadge(13), false, "Bag.isBadge(13) is false")
  checkEq(Bag.isBadge("BOULDERBADGE"), true, "Bag.isBadge('BOULDERBADGE') is true")
  checkEq(Ops.isBadgeId(13), false, "Ops.isBadgeId(13) is false")
  checkEq(Ops.isBadgeId("BOULDERBADGE"), true, "Ops.isBadgeId('BOULDERBADGE') is true")

  local order = Bag.order(save, mockData)
  check(type(order) == "table", "Bag.order returns table with numeric IDs")
  checkEq(Bag.slots(save, mockData), 2, "Bag.slots counts 2 items excluding badge")
end

-- --------------------------------------------------------------------------
-- 16. Tab Transitions & Items Panel Drawing
-- --------------------------------------------------------------------------
do
  local prevLove = _G.love
  _G.love = _G.love or {}
  _G.love.filesystem = _G.love.filesystem or {
    getSaveDirectory = function() return "." end,
    getInfo = function() return nil end,
    getDirectoryItems = function() return {} end,
    read = function() return nil end,
    exists = function() return false end,
  }
  _G.love.graphics = _G.love.graphics or {
    getDimensions = function() return 1024, 768 end,
    setFont = function() end,
    setColor = function() end,
    rectangle = function() end,
    setScissor = function() end,
    getScissor = function() return nil end,
    push = function() end,
    pop = function() end,
    translate = function() end,
    scale = function() end,
    print = function() end,
    printf = function() end,
    draw = function() end,
  }
  _G.love.mouse = _G.love.mouse or {
    getPosition = function() return 100, 100 end,
    isDown = function() return false end,
  }

  local App = require("tools.save-editor.App")
  local ok, err = pcall(App.load, nil, { version = "firered", slotId = "slot1", embedded = true })
  check(ok, "App.load runs: " .. tostring(err))

  local S = App.getState()
  check(S ~= nil, "State exists")

  -- Add items to bag and PC
  Ops.addToBag(S, "POTION")
  Ops.addToBag(S, 4) -- Poke ball numeric ID
  Ops.addToPc(S, "MASTER_BALL")
  Ops.addToPc(S, 13) -- Potion numeric ID

  -- Switch to Boxes tab
  S.tab = "boxes"
  local okB, errB = pcall(App.draw)
  check(okB, "App.draw renders boxes tab without error: " .. tostring(errB))

  -- Switch from Boxes to Items tab
  S.tab = "items"
  local okI, errI = pcall(App.draw)
  check(okI, "App.draw renders items tab (wide) without error: " .. tostring(errI))

  -- Test stacked layout (narrow screen)
  _G.love.graphics.getDimensions = function() return 480, 800 end
  local okS, errS = pcall(App.draw)
  check(okS, "App.draw renders items tab (stacked) without error: " .. tostring(errS))

  -- Test sorting
  Ops.bagSort(S, "name")
  Ops.pcSort(S, "name")
  local okSort, errSort = pcall(App.draw)
  check(okSort, "App.draw renders after sorting items: " .. tostring(errSort))

  -- Test table-typed entries in save.inventory and save.pcItems
  S.save.inventory[1] = { id = 13, qty = 5 }
  S.save.inventory["13"] = { qty = 10 }
  S.save.pcItems[1] = { id = 4, qty = 20 }
  check(pcall(Ops.bagCanMax, S), "Ops.bagCanMax handles table entries in inventory without error")
  check(pcall(Ops.pcCanMax, S), "Ops.pcCanMax handles table entries in pcItems without error")
  local okT, errT = pcall(App.draw)
  check(okT, "App.draw renders with table-typed items: " .. tostring(errT))

  App.unload()
end

-- --------------------------------------------------------------------------
-- 15. MovePicker & Move Assignment Normalization
-- --------------------------------------------------------------------------
do
  local State = require("State")
  local MovePicker = require("MovePicker")
  local Kit = require("Kit")

  local S = State.new()
  S.data = mockData
  S.cat = Catalog.build(mockData)
  S.save = Schema.newGame({ version = "firered" })
  S.version = "firered"

  -- Create mon with numeric array moves (e.g. 57=SURF, 10=SCRATCH)
  local mon = MonOps.create(mockData, 6, 50, 3)
  mon.moves = { 57, 10, 0, 0 }
  S.save.party[1] = mon
  S.editingMon = mon

  -- Open MovePicker for slot 1 (which holds numeric 57)
  local okOpen = Ops.openMovePicker(S, Kit, 1)
  check(okOpen, "Ops.openMovePicker opens successfully with numeric moves")

  -- Draw MovePicker (must NOT crash with attempt to index a number value)
  local okDraw, errDraw = pcall(function()
    MovePicker.draw(S, Kit, 800, 600)
  end)
  check(okDraw, "MovePicker.draw renders with numeric moves without crashing: " .. tostring(errDraw))

  -- Move deduplication: attempting to assign SURF when move 1 is already 57
  local surfAssigned = Ops.setMove(S, mon, 1, "SURF")
  checkEq(surfAssigned, false, "Ops.setMove refuses assigning SURF when slot is already numeric 57 (Surf)")

  -- Assign a new move (e.g. FLAMETHROWER = 53 or FIRE BLAST = 126)
  local fbAssigned = Ops.setMove(S, mon, 1, "FIRE BLAST")
  check(fbAssigned, "Ops.setMove assigns FIRE BLAST")
  checkEq(mon.moves[1], 126, "mon.moves[1] updated to canonical numeric ID 126")

  Ops.closeMovePicker(S, Kit)
end

-- --------------------------------------------------------------------------
-- 16. SpeciesPicker Highlighting Normalization
-- --------------------------------------------------------------------------
do
  local State = require("State")
  local SpeciesPicker = require("SpeciesPicker")
  local Kit = require("Kit")

  local S = State.new()
  S.data = mockData
  S.cat = Catalog.build(mockData)
  S.save = Schema.newGame({ version = "firered" })
  S.version = "firered"

  local mon = MonOps.create(mockData, 6, 50, 3) -- Charizard (species = 6)
  S.editingMon = mon

  local okOpen = Ops.openSpeciesPicker(S, Kit)
  check(okOpen, "Ops.openSpeciesPicker opens")

  local okDraw, errDraw = pcall(function()
    SpeciesPicker.draw(S, Kit, 800, 600)
  end)
  check(okDraw, "SpeciesPicker.draw renders without crashing: " .. tostring(errDraw))

  Ops.closeSpeciesPicker(S, Kit)
end

-- --------------------------------------------------------------------------
-- 17. PID Generation and Mathematical Parity (Nature, Ability, Gender, Shiny)
-- --------------------------------------------------------------------------
do
  local SummaryData = require("src.core.game3.summary_data")
  local PokemonG3 = require("src.core.game3.pokemon")

  local species = 6 -- Charizard (87.5% male ratio)
  local otId = 12345
  local otSecretId = 54321

  -- 1. Test Adamant (3), Ability 1 (slot 0), Male, Non-Shiny
  local pid1 = MonOps.generatePid(species, otId, otSecretId, {
    nature = 3,
    ability = 0,
    gender = "M",
    shiny = false,
  })
  checkEq(pid1 % 25, 3, "generatePid produces requested Nature (Adamant = 3)")
  checkEq(pid1 % 2, 0, "generatePid produces requested Ability slot 0")
  checkEq(PokemonG3.gender(species, pid1), "M", "generatePid produces Male gender")
  checkEq(SummaryData.isShiny({ personality = pid1, otId = otId, otSecretId = otSecretId }), false, "generatePid produces non-shiny")

  -- 2. Test Modest (15), Ability 2 (slot 1), Female, Shiny
  local pid2 = MonOps.generatePid(species, otId, otSecretId, {
    nature = 15,
    ability = 1,
    gender = "F",
    shiny = true,
  })
  checkEq(pid2 % 25, 15, "generatePid produces requested Nature (Modest = 15)")
  checkEq(pid2 % 2, 1, "generatePid produces requested Ability slot 1")
  checkEq(PokemonG3.gender(species, pid2), "F", "generatePid produces Female gender")
  checkEq(SummaryData.isShiny({ personality = pid2, otId = otId, otSecretId = otSecretId }), true, "generatePid produces shiny")
end

-- --------------------------------------------------------------------------
-- 18. Pokédex Dual-Indexing and National Dex Toggle
-- --------------------------------------------------------------------------
do
  local State = require("State")
  local S = State.new()
  S.data = mockData
  S.cat = Catalog.build(mockData)
  S.save = Schema.newGame({ version = "firered" })
  S.version = "firered"

  -- Check initial state
  local seen, owned, total = Ops.dexCounts(S)
  check(seen == 0, "initial dex seen is 0")
  check(owned == 0, "initial dex owned is 0")

  -- Mark Bulbasaur seen
  Ops.dexSeen(S, "BULBASAUR", true)
  check(S.save.dex.seen["BULBASAUR"] == true, "dex.seen contains BULBASAUR string key")
  check(S.save.dex.seen[1] == true, "dex.seen contains species ID 1 numeric key")

  -- Mark Bulbasaur owned
  Ops.dexOwned(S, "BULBASAUR", true)
  check(S.save.dex.owned["BULBASAUR"] == true, "dex.owned contains BULBASAUR string key")
  check(S.save.dex.owned[1] == true, "dex.owned contains species ID 1 numeric key")

  seen, owned = Ops.dexCounts(S)
  checkEq(seen, 1, "dexCounts counts 1 seen (deduplicated)")
  checkEq(owned, 1, "dexCounts counts 1 owned (deduplicated)")

  -- National Dex toggle
  checkEq(S.save.dex.national, false, "National Dex initially false")
  Ops.toggleNationalDex(S)
  checkEq(S.save.dex.national, true, "National Dex toggled to true")
  checkEq(Flags.getFlag(S.save, nil, "FLAG_SYS_NATIONAL_DEX"), true, "FLAG_SYS_NATIONAL_DEX is true")

  Ops.toggleNationalDex(S)
  checkEq(S.save.dex.national, false, "National Dex toggled back to false")
  checkEq(Flags.getFlag(S.save, nil, "FLAG_SYS_NATIONAL_DEX"), false, "FLAG_SYS_NATIONAL_DEX is false")
end

-- --------------------------------------------------------------------------
-- 19. Gen 3 Pokémon Characteristics Operations (MonEditor / Ops)
-- --------------------------------------------------------------------------
do
  local State = require("State")
  local MonEditor = require("MonEditor")
  local Kit = require("Kit")

  local S = State.new()
  S.data = mockData
  S.cat = Catalog.build(mockData)
  S.save = Schema.newGame({ version = "firered" })
  S.version = "firered"

  local mon = MonOps.create(mockData, 6, 50, 3)
  S.save.party[1] = mon
  S.editingMon = mon

  -- Set Held Item
  Ops.setHeldItem(S, mon, "LEFTOVERS")
  check(mon.heldItem ~= nil, "mon heldItem set")
  Ops.setHeldItem(S, mon, nil)
  check(mon.heldItem == nil, "mon heldItem cleared")

  -- Set Happiness / Friendship
  Ops.setHappiness(S, mon, 200)
  checkEq(mon.friendship, 200, "mon friendship set to 200")

  -- Set Nature
  Ops.setNature(S, mon, 3) -- Adamant
  checkEq(mon.nature, 3, "mon nature set to Adamant (3)")
  checkEq(mon.personality % 25, 3, "mon personality matches Adamant modulo 25")
  check(tostring(S.status):find("nature set to ADAMANT", 1, true) ~= nil,
    "setNature status names the ROM nature text: " .. tostring(S.status))

  -- Set Ability
  Ops.setAbility(S, mon, 1) -- Slot 2
  checkEq(mon.personality % 2, 1, "mon personality has ability bit 1")

  -- Set Shiny
  Ops.setShiny(S, mon, true)
  check(require("src.core.game3.summary_data").isShiny(mon), "mon is shiny via PID math")

  -- Draw MonEditor
  local okDraw, errDraw = pcall(function()
    MonEditor.draw(S, Kit, 20, 20, 600, 700)
  end)
  check(okDraw, "MonEditor.draw renders Gen 3 characteristics without error: " .. tostring(errDraw))
end

-- --------------------------------------------------------------------------
-- 20. Gen 3 Event Categories & Variable Operations (Events panel / Ops / Gen3Flags)
-- --------------------------------------------------------------------------
do
  local State = require("State")
  local Events = require("panels.Events")
  local Gen3Flags = require("Gen3Flags")
  local Kit = require("Kit")

  local cats = Gen3Flags.categories()
  check(type(cats.story) == "table" and #cats.story > 0, "cats.story has flags")
  check(type(cats.trainers) == "table" and #cats.trainers > 0, "cats.trainers has trainers")
  check(type(cats.items) == "table" and #cats.items > 0, "cats.items has items")
  check(type(cats.toggles) == "table" and #cats.toggles > 0, "cats.toggles has toggles")
  check(type(cats.system) == "table" and #cats.system > 0, "cats.system has system flags")
  check(type(cats.vars) == "table" and #cats.vars > 0, "cats.vars has variables")

  local S = State.new()
  S.data = mockData
  S.cat = Catalog.build(mockData)
  S.save = Schema.newGame({ version = "firered" })
  S.version = "firered"
  S.events = Catalog.game3EventList()
  S.game3Events = cats

  -- 1. Story flags toggle
  Ops.setFlag(S, "FLAG_GOT_BICYCLE", true)
  checkEq(Gen.getFlag(S.save, "FLAG_GOT_BICYCLE"), true, "FLAG_GOT_BICYCLE set to true")
  Ops.setFlag(S, "FLAG_GOT_BICYCLE", false)
  checkEq(Gen.getFlag(S.save, "FLAG_GOT_BICYCLE"), false, "FLAG_GOT_BICYCLE set to false")

  -- 2. Trainer flags toggle (0x500 + trainerId)
  local tFlag = 0x500 + 89 -- TRAINER_YOUNGSTER_BEN (0x559 = 1369)
  Ops.setFlag(S, tFlag, true)
  checkEq(Gen.getFlag(S.save, tFlag), true, "TRAINER_YOUNGSTER_BEN flag set to true")

  -- Set up some VS Seeker / Rematch data
  S.save.vsSeeker = S.save.vsSeeker or {}
  S.save.vsSeeker.rematches = { [89] = true }
  S.save.trainerRematches = { [89] = 1 }
  S.save.vars = S.save.vars or {}
  S.save.vars[0x40AA] = 5

  -- Clear all trainers (two-click confirmation)
  Ops.clearTrainers(S) -- first click arms
  checkEq(S.armed, "clear-trainers", "Ops.clearTrainers armed on first click")
  Ops.clearTrainers(S) -- second click confirms
  checkEq(Gen.getFlag(S.save, tFlag), false, "TRAINER_YOUNGSTER_BEN flag cleared by Ops.clearTrainers")
  checkEq(next(S.save.vsSeeker.rematches), nil, "vsSeeker.rematches scrubbed by Ops.clearTrainers")
  checkEq(next(S.save.trainerRematches), nil, "trainerRematches scrubbed by Ops.clearTrainers")
  checkEq(S.save.vars[0x40AA], 0, "VAR_QLBAK_TRAINER_REMATCHES cleared by Ops.clearTrainers")

  -- 3. Item ball & hidden item flags toggle and bulk clear
  local itemFlag = 0x154 -- FLAG_HIDE_ROUTE2_ETHER
  local hiddenFlag = 0x3E8 -- FLAG_HIDDEN_ITEM_VIRIDIAN_FOREST_POTION
  Ops.setFlag(S, itemFlag, true)
  Ops.setFlag(S, hiddenFlag, true)
  checkEq(Gen.getFlag(S.save, itemFlag), true, "itemFlag set to true")
  checkEq(Gen.getFlag(S.save, hiddenFlag), true, "hiddenFlag set to true")

  Ops.clearItems(S) -- arms
  checkEq(S.armed, "clear-items", "Ops.clearItems armed on first click")
  Ops.clearItems(S) -- confirms
  checkEq(Gen.getFlag(S.save, itemFlag), false, "itemFlag cleared by Ops.clearItems")
  checkEq(Gen.getFlag(S.save, hiddenFlag), false, "hiddenFlag cleared by Ops.clearItems")

  -- 4. Object toggle flags
  local hideOak = 0x02C -- FLAG_HIDE_OAK_IN_PALLET_TOWN
  Ops.setFlag(S, hideOak, true)
  checkEq(Gen.getFlag(S.save, hideOak), true, "FLAG_HIDE_OAK_IN_PALLET_TOWN set to true")

  Ops.clearToggles(S) -- arms
  Ops.clearToggles(S) -- confirms
  checkEq(Gen.getFlag(S.save, hideOak), false, "FLAG_HIDE_OAK_IN_PALLET_TOWN cleared by Ops.clearToggles")

  -- 5. Variables get/set and bounds clamping
  local sceneVar = 0x4050 -- VAR_MAP_SCENE_PALLET_TOWN_OAK
  checkEq(Gen.getVar(S.save, sceneVar), 0, "initial sceneVar value is 0")
  Ops.setVar(S, sceneVar, 2)
  checkEq(Gen.getVar(S.save, sceneVar), 2, "sceneVar set to 2")

  -- 16-bit boundary safety tests
  Ops.setVar(S, sceneVar, -10)
  checkEq(Gen.getVar(S.save, sceneVar), 0, "negative value clamped to 0")
  Ops.setVar(S, sceneVar, 70000)
  checkEq(Gen.getVar(S.save, sceneVar), 65535, "large value clamped to 65535 (0xFFFF)")

  -- 6. Render all 6 sub-tabs in Events panel without error
  local subTabs = { "story", "trainers", "items", "toggles", "system", "vars" }
  for _, tab in ipairs(subTabs) do
    S.eventsTab = tab
    local okDraw, errDraw = pcall(function()
      Events.draw(S, Kit, 20, 20, 600, 700)
    end)
    check(okDraw, string.format("Events.draw renders sub-tab '%s' without error: %s", tab, tostring(errDraw)))
  end
end

do
  local App = require("tools.save-editor.App")
  local ready = Gen.game3CacheReady
  Gen.game3CacheReady = function() return false end
  local ok, err = pcall(App.load, nil, { version = "firered", slotId = "slot1", embedded = true })
  Gen.game3CacheReady = ready
  check(ok, "App.load with no FireRed cache does not raise: " .. tostring(err))
  local S = App.getState()
  check(S and S.missingCache and S.missingCache:find("No imported FireRed ROM cache", 1, true) ~= nil,
    "App.load with no FireRed cache names the missing cache")
  checkEq(S and S.status, S and S.missingCache, "missing-cache message is the status line")
  checkEq(S and S.allowSave, false, "missing-cache session cannot save")
  check(S and S.save == nil, "missing-cache session loads no save")
  local okD, errD = pcall(App.draw)
  check(okD, "App.draw renders the missing-cache screen: " .. tostring(errD))
  checkEq(App.save(), false, "App.save refuses with no FireRed cache")
  checkEq(App.reload(), false, "App.reload refuses with no FireRed cache")
  App.unload()
end

print(string.format("save editor gen3 tests: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end

