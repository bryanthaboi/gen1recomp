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
  checkEq(mon.moves[1].moveId, 57, "move 1 set to Surf (57)")
  check(mon.moves[1].pp > 0, "move 1 PP initialized")

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
  checkEq(rawMon.species, "BULBASAUR", "hydrateMon normalizes numeric species to BULBASAUR")
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
  checkEq(mon.species, "CHARMANDER", "Ops.setSpecies updates to CHARMANDER")
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
  checkEq(save.inventory["POTION"], 1, "POTION added to bag x1")
  check(save.bag ~= nil and save.bag.stacks ~= nil, "save.bag updated")

  -- Adjust bag quantity
  Ops.bagAdjust(S, "POTION", 4)
  checkEq(save.inventory["POTION"], 5, "POTION adjusted to x5")

  -- Max bag stack
  Ops.bagMax(S, "POTION")
  checkEq(save.inventory["POTION"], Ops.STACK_MAX, "POTION maxed to 99")

  -- Drop bag item
  Ops.bagDrop(S, "POTION")
  checkEq(save.inventory["POTION"], nil, "POTION dropped from bag")

  -- PC operations
  Ops.addToPc(S, "POKE_BALL")
  checkEq(save.pcItems["POKE_BALL"], 1, "POKE_BALL added to PC x1")
  check(save.storage ~= nil and #save.storage.items > 0, "save.storage.items synced")

  Ops.pcAdjust(S, "POKE_BALL", 9)
  checkEq(save.pcItems["POKE_BALL"], 10, "POKE_BALL adjusted to x10 in PC")

  Ops.pcMax(S, "POKE_BALL")
  checkEq(save.pcItems["POKE_BALL"], Ops.STACK_MAX, "POKE_BALL maxed in PC")

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
  S.save.inventory["POTION"] = { qty = 10 }
  S.save.pcItems[1] = { id = 4, qty = 20 }
  check(pcall(Ops.bagCanMax, S), "Ops.bagCanMax handles table entries in inventory without error")
  check(pcall(Ops.pcCanMax, S), "Ops.pcCanMax handles table entries in pcItems without error")
  local okT, errT = pcall(App.draw)
  check(okT, "App.draw renders with table-typed items: " .. tostring(errT))

  App.unload()
  _G.love = prevLove
end

print(string.format("save editor gen3 tests: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
