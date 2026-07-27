-- Save-slot backend (src/core/SaveData.lua): legacy migration, the slot
-- registry in options.lua, listSlots/setActiveSlot/createSlot, and the
-- active-slot resolution behind saveNames/save/load.  Self-contained: it
-- installs the love stub only for a swappable in-memory filesystem, the
-- same way tests/mod_save_tests isolates its save round-trips.

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
love = love or require("tests.love_stub")

local SaveSerializer = require("src.core.SaveSerializer")
local SaveData = require("src.core.SaveData")
local GameVersion = require("src.core.GameVersion")

local realFS = love.filesystem

-- an isolated love.filesystem: keys are full paths, so "saves/red/slot1.lua"
-- needs no directory support (createDirectory is deliberately absent, which
-- is exactly what the ensureParentDir no-op path handles)
local function memfs(files)
  return {
    files = files,
    write = function(path, content) files[path] = content return true end,
    read = function(path) return files[path] end,
    remove = function(path) files[path] = nil return true end,
    getInfo = function(path)
      if files[path] then return { type = "file" } end
      return nil
    end,
  }
end

-- a fresh filesystem + cleared process globals: each scenario is a first boot
local function fresh()
  local files = {}
  love.filesystem = memfs(files)
  SaveData.resetSlotState()
  GameVersion.set("red")
  return files
end

-- a minimal but fully decodable Red save
local function legacySave(name, dexOwned, badges, playTime)
  local owned = {}
  for _, id in ipairs(dexOwned or {}) do owned[id] = true end
  local inv = {}
  for _, id in ipairs(badges or {}) do inv[id] = true end
  return {
    version = "red",
    player = { name = name, map = "PALLET_TOWN", x = 1, y = 1 },
    pokedex = { seen = {}, owned = owned },
    inventory = inv,
    playTime = playTime or 0,
  }
end

-- ---------------------------------------------- slotSummary (pure)

do
  local name, meta = SaveData.slotSummary(
    legacySave("ASH", { "PIKACHU", "PIDGEY", "RATTATA" },
               { "BOULDERBADGE", "CASCADEBADGE" }, 3661))
  T.eq(name, "ASH", "slotSummary reads the player name")
  T.eq(meta.dexCount, 3, "slotSummary counts owned dex entries")
  T.eq(meta.badges, 2, "slotSummary counts vanilla badges from inventory")
  T.eq(meta.timeText, "1:01", "slotSummary formats playTime as H:MM")

  local n2, m2 = SaveData.slotSummary(nil)
  T.eq(n2, nil, "slotSummary of an empty slot has no name")
  T.eq(m2, nil, "slotSummary of an empty slot has no meta")
end

-- ---------------------------------------------- legacy migration happy path

do
  local files = fresh()
  files["save.lua"] = SaveSerializer.encode(
    legacySave("RED", { "BULBASAUR", "CHARMANDER" }, { "BOULDERBADGE" }, 7325))

  local slots = SaveData.listSlots("red")
  T.eq(#slots, 1, "legacy save migrates into exactly one slot")
  T.eq(slots[1].id, "slot1", "the migrated slot is slot1")
  T.eq(slots[1].exists, true, "the migrated slot reports a save present")
  T.eq(slots[1].name, "RED", "the migrated slot surfaces the player name")
  T.eq(slots[1].meta.badges, 1, "migrated slot meta carries the badge count")
  T.eq(slots[1].meta.dexCount, 2, "migrated slot meta carries the dex count")
  T.eq(slots[1].meta.timeText, "2:02", "migrated slot meta carries the time")

  T.eq(files["save.lua"], nil, "the flat legacy file is removed after migration")
  T.check(files["saves/red/slot1.lua"] ~= nil, "the slot file now holds the save")

  local opts = SaveSerializer.decode(files["options.lua"])
  T.eq(opts.saveSlots.red.active, "slot1", "options registers slot1 as active")
  T.eq(opts.saveSlots.red.list[1], "slot1", "options lists the migrated slot")

  -- load() now resolves the active slot and reads the migrated save
  local loaded = SaveData.load("red")
  T.check(loaded and loaded.player.name == "RED", "load reads the active slot")
end

-- ---------------------------------------------- migration idempotence

do
  local files = fresh()
  files["save.lua"] = SaveSerializer.encode(legacySave("ONCE", { "MEW" }, {}, 0))
  SaveData.listSlots("red")               -- first boot: migrates
  local slotBytes = files["saves/red/slot1.lua"]

  -- a second boot: registry exists, no flat file, so nothing re-migrates
  SaveData.resetSlotState()
  local slots = SaveData.listSlots("red")
  T.eq(#slots, 1, "a re-boot does not duplicate the migrated slot")
  T.eq(files["save.lua"], nil, "no flat file reappears on re-boot")
  T.eq(files["saves/red/slot1.lua"], slotBytes, "the slot bytes are untouched")
  local opts = SaveSerializer.decode(files["options.lua"])
  T.eq(#opts.saveSlots.red.list, 1, "the registry still lists exactly one slot")
end

-- ---------------------------------------------- mixed real / empty slots

do
  local files = fresh()
  files["save.lua"] = SaveSerializer.encode(
    legacySave("REAL", { "EEVEE" }, { "BOULDERBADGE" }, 60))
  SaveData.listSlots("red")               -- slot1 = the migrated real save
  local empty = SaveData.createSlot("red")
  T.eq(empty, "slot2", "createSlot allocates slot2 alongside the migrated slot1")

  local slots = SaveData.listSlots("red")
  T.eq(#slots, 2, "both the real and empty slots are listed")
  T.eq(slots[1].exists, true, "the migrated slot still reports a save")
  T.eq(slots[1].name, "REAL", "the real slot keeps its name")
  T.eq(slots[2].exists, false, "the freshly created slot is empty")
  T.eq(slots[2].name, nil, "an empty slot has no name")
  T.eq(slots[2].meta, nil, "an empty slot has no meta")
end

-- ---------------------------------------------- setActiveSlot persistence

do
  local files = fresh()
  SaveData.createSlot("red")              -- slot1
  SaveData.createSlot("red")              -- slot2
  SaveData.setActiveSlot("red", "slot2")

  local opts = SaveSerializer.decode(files["options.lua"])
  T.eq(opts.saveSlots.red.active, "slot2", "setActiveSlot persists the active id")
  T.eq(opts.saveSlots.red.list[1], "slot1", "the slot list is preserved")
  T.eq(opts.saveSlots.red.list[2], "slot2", "the target slot stays in the list")

  -- selecting a slot that was never registered adds it
  SaveData.setActiveSlot("red", "slot7")
  opts = SaveSerializer.decode(files["options.lua"])
  T.eq(opts.saveSlots.red.active, "slot7", "an unregistered active slot is added")
  T.eq(opts.saveSlots.red.list[3], "slot7", "the added slot lands in the list")
end

-- ---------------------------------------------- createSlot id allocation

do
  fresh()
  T.eq(SaveData.createSlot("red"), "slot1", "first slot is slot1")
  T.eq(SaveData.createSlot("red"), "slot2", "second slot is slot2")
  T.eq(SaveData.createSlot("red"), "slot3", "ids increment past the highest")
end

-- ---------------------------------------------- deleteSlot

do
  local files = fresh()
  local a = SaveData.createSlot("red")
  local b = SaveData.createSlot("red")
  SaveData.setActiveSlot("red", b)
  local save = SaveData.newGame()
  save.player.name = "KEEP"
  T.check(SaveData.writeSlot("red", a, save), "seed slot1 with a save")
  save.player.name = "GONE"
  T.check(SaveData.writeSlot("red", b, save), "seed slot2 with a save")

  local ok, err = SaveData.deleteSlot("red", b)
  T.check(ok, "deleteSlot removes the active slot: " .. tostring(err))
  T.eq(files["saves/red/slot2.lua"], nil, "slot2's file is gone")
  T.check(files["saves/red/slot1.lua"] ~= nil, "the other slot's file stays")
  local opts = SaveSerializer.decode(files["options.lua"])
  T.eq(opts.saveSlots.red.active, a, "active falls back to the remaining slot")
  T.eq(#opts.saveSlots.red.list, 1, "the deleted id is dropped from the list")
  T.eq(opts.saveSlots.red.list[1], a, "only slot1 remains registered")

  ok = SaveData.deleteSlot("red", a)
  T.check(ok, "deleting the last slot succeeds")
  opts = SaveSerializer.decode(files["options.lua"])
  T.eq(#opts.saveSlots.red.list, 0, "the registry list is empty")
  T.eq(opts.saveSlots.red.active, nil, "active clears when no slots remain")
  T.eq(#SaveData.listSlots("red"), 0, "listSlots reports an empty install")

  local bad, badErr = SaveData.deleteSlot("red", "slot99")
  T.check(not bad, "deleting an unknown slot fails")
  T.check(tostring(badErr):find("not registered", 1, true) ~= nil,
    "unknown-slot error is user-presentable")
end

-- ---------------------------------------------- saveNames follows the slot

do
  local files = fresh()
  SaveData.createSlot("red")              -- slot1
  SaveData.createSlot("red")              -- slot2
  SaveData.setActiveSlot("red", "slot2")

  local save = SaveData.newGame()
  save.player.name = "SLOT2"
  T.check(SaveData.save(save), "save writes to the active slot")
  T.check(files["saves/red/slot2.lua"] ~= nil, "bytes land in slot2's file")
  T.eq(files["saves/red/slot1.lua"], nil, "slot1 is untouched by a slot2 save")
  T.eq(files["save.lua"], nil, "no flat file is written once a slot is active")

  local loaded = SaveData.load("red")
  T.check(loaded and loaded.player.name == "SLOT2", "load reads back from slot2")
end

-- ---------------------------------------------- a version with no slots

do
  local files = fresh()
  local slots = SaveData.listSlots("red")
  T.eq(#slots, 0, "a fresh install with no legacy save lists no slots")

  -- with nothing registered, save/load use the flat legacy path, exactly
  -- as they did before slots existed
  local save = SaveData.newGame()
  save.player.name = "FLAT"
  T.check(SaveData.save(save), "a slotless version saves to the flat file")
  T.check(files["save.lua"] ~= nil, "the flat save.lua is written")
  T.eq(files["saves/red/slot1.lua"], nil, "no slot directory is created")

  local loaded = SaveData.load("red")
  T.check(loaded and loaded.player.name == "FLAT", "load reads the flat file")

  T.eq(SaveData.saveFilename("red"), "save.lua",
    "saveFilename still resolves the flat name with no slot in use")
end

love.filesystem = realFS

T.finish("save_slots")
