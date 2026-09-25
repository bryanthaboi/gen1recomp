package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
love = love or require("tests.love_stub")

local SaveData = require("src.core.SaveData")
local GameVersion = require("src.core.GameVersion")
local SyncEngine = require("src.sync.SyncEngine")

local realFS = love.filesystem

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

local function fresh()
  local files = {}
  love.filesystem = memfs(files)
  SaveData.resetSlotState()
  GameVersion.set("red")
  return files
end

do
  local plain = SaveData.buildMeta({})
  T.eq(plain.modCount, 0, "vanilla saves explicitly record zero mods")
  local modded = SaveData.buildMeta({ { id = "one" }, { id = "two" } })
  T.eq(modded.modCount, 2, "the count reflects the mods that wrote the save")
  T.eq(SaveData.buildMeta(nil, modded).modCount, 2,
    "a headless rewrite preserves the saved mod count")
  T.eq(SaveData.buildMeta({}, modded).modCount, 0,
    "disabling all mods clears the previous count")
  T.check(type(plain.savedAt) == "number", "a save still records when it ended")
  T.eq(plain.sessionStart, nil,
    "and records no session start when nobody supplied one")

  local started = os.time() - 600
  local meta = SaveData.buildMeta({}, nil, started)
  T.eq(meta.sessionStart, started, "the session start is stamped when given")
  T.check(meta.savedAt >= meta.sessionStart,
    "and savedAt is the end of that session")

  local carried = SaveData.buildMeta({}, { sessionStart = started })
  T.eq(carried.sessionStart, started,
    "a rewrite with no session keeps the previous start")

  local future = SaveData.buildMeta({}, nil, os.time() + 9999)
  T.check(future.sessionStart <= future.savedAt,
    "a clock that ran backwards cannot start a session after it ended")

  local nan = SaveData.buildMeta({}, nil, 0 / 0)
  T.eq(nan.sessionStart, nil, "a NaN session start is refused")

  local kept = SaveData.buildMeta(nil, { playthroughId = "abc", mods = {},
                                         sessionStart = 42 })
  T.eq(kept.playthroughId, "abc", "the playthrough id still rides on the meta")
  T.eq(kept.sessionStart, 42, "next to the session start")
end

do
  local files = fresh()
  T.eq(SaveData.readSlotSource("red", "slot1"), nil,
    "an empty slot has no bytes to upload")

  local save = SaveData.newGame()
  save.player.name = "ASH"
  save.meta = SaveData.buildMeta({}, { playthroughId = "abc" }, os.time() - 60)
  T.check(SaveData.writeSlot("red", "slot1", save), "a slot write lands")

  local source = SaveData.readSlotSource("red", "slot1")
  T.check(type(source) == "string" and #source > 0, "the raw bytes read back")
  local decoded = SaveData.decode(source)
  T.eq(decoded.player.name, "ASH", "and decode to the same save")
  T.eq(decoded.meta.playthroughId, "abc", "carrying the playthrough id")

  files["saves/red/slot1.lua"] = "this is not a save"
  T.eq(SaveData.readSlotSource("red", "slot1"), nil,
    "a corrupt slot never hands undecodable bytes to the uploader")

  files["saves/red/slot1.lua.bak"] = source
  T.eq(SaveData.readSlotSource("red", "slot1"), source,
    "and the backup copy is used instead")

  T.eq(SaveData.readSlotSource("nosuchgame", "slot1"), nil,
    "an unknown version has no slots to read")
end

do
  fresh()
  local provider = SyncEngine.defaultSaves()
  T.eq(#provider.list(), 0, "a fresh install has nothing to sync")

  local slotId = SaveData.createSlot("red")
  local save = SaveData.newGame()
  save.player.name = "ASH"
  save.meta = SaveData.buildMeta({}, { playthroughId = "abc" }, os.time() - 120)
  SaveData.writeSlot("red", slotId, save)

  local entries = provider.list()
  T.eq(#entries, 1, "a written slot becomes one sync entry")
  T.eq(entries[1].version, "red", "keyed by its game")
  T.eq(entries[1].playthroughId, "abc", "and its playthrough id")
  T.eq(entries[1].slot, slotId, "remembering which slot it came from")
  T.eq(entries[1].meta.summary.name, "ASH",
    "with the launcher summary the conflict prompt shows")
  T.check(entries[1].meta.sessionStart ~= nil, "and the session start")
  T.eq(entries[1].meta.modCount, 0, "sync metadata explicitly reports vanilla")
  T.eq(SaveData.decode(entries[1].blob).meta.modCount, 0,
    "the saved blob also carries the count")
  T.check(entries[1].blob:find("ASH", 1, true) ~= nil,
    "the blob is the encoded save itself")

  save.meta.mods = { { id = "one" }, { id = "two" } }
  save.meta.modCount = nil
  SaveData.writeSlot("red", slotId, save)
  T.eq(provider.list()[1].meta.modCount, 2,
    "older saves derive their sync count from their own mod list")
  save.meta.modCount = 99
  SaveData.writeSlot("red", slotId, save)
  T.eq(provider.list()[1].meta.modCount, 2,
    "a stale count cannot override the saved mod list")

  local other = SaveData.newGame()
  other.player.name = "BLUE"
  other.meta = SaveData.buildMeta({}, { playthroughId = "xyz" }, os.time() - 30)
  local newSlot = provider.write("red", "xyz", SaveData.encode(other), "new")
  T.check(newSlot ~= nil and newSlot ~= slotId,
    "keep both imports the other device's save into a new slot")
  local after = provider.list()
  T.eq(#after, 2, "and both playthroughs are now local")
  local ids = {}
  for _, entry in ipairs(after) do ids[entry.playthroughId] = true end
  T.eq(ids["abc"], true, "this device's playthrough is untouched")
  T.eq(ids["xyz"], nil,
    "and the imported copy gets its own identity so the two never merge")
end

do
  local source = assert(io.open("src/core/Game.lua")):read("*a")
  T.check(source:find("self.sessionStartedAt = os.time()", 1, true) ~= nil,
    "Game stamps when a play session began")
  T.check(source:find("self.sessionStartedAt)", 1, true) ~= nil,
    "and hands it to buildMeta when the save is written")
  local _, stamps = source:gsub("self%.sessionStartedAt = os%.time%(%)", "")
  T.eq(stamps, 3,
    "boot, NEW GAME and CONTINUE each start a session")
end

do
  fresh()
  local Game = require("src.core.Game")
  local notes, pumped = 0, 0
  SyncEngine._shared = {
    state = { enabled = true },
    linked = function() return true end,
    busy = function() return false end,
    noteSaveWritten = function() notes = notes + 1 end,
    update = function(_, dt) pumped = pumped + dt end,
  }
  local game = setmetatable({ save = SaveData.newGame(),
    sessionStartedAt = os.time() - 60 }, { __index = Game })
  T.eq(Game.writeSave(game), true, "an in-game save still writes")
  T.eq(notes, 1, "and tells the sync engine, so the 5s debounce can start")
  Game.updateSync(game, 0.5)
  T.eq(pumped, 0.5, "the running game pumps the engine, not only the launcher")

  SyncEngine._shared = {
    state = { enabled = false },
    linked = function() return false end,
    busy = function() return false end,
    noteSaveWritten = function() notes = notes + 1 end,
    update = function() pumped = pumped + 1 end,
  }
  game._syncOff, game._syncEngineRef = nil, nil
  Game.updateSync(game, 0.5)
  T.eq(pumped, 0.5, "with sync off the engine is left alone")
  SyncEngine.forgetShared()
end

local function onDisk(files, slot)
  local body = files["saves/red/" .. slot .. ".lua"]
  return body and SaveData.decode(body) or nil
end

do
  local files = fresh()
  local Game = require("src.core.Game")
  local slot = SaveData.createSlot("red")
  SaveData.setActiveSlot("red", slot)
  local save = SaveData.newGame()
  save.player.name = "ASH"
  save.meta = SaveData.buildMeta({}, save.meta, os.time() - 60)
  T.check(SaveData.writeSlot("red", slot, save), "a slot is written without an identity stamp")
  local mapped = SaveData.slotPlaythroughId("red", slot, save)
  T.check(type(mapped) == "string" and #mapped == 32,
    "a launcher sync listing mints the slot's identity into the mapping")
  T.eq(onDisk(files, slot).meta.playthroughId, nil,
    "while the progress file still carries none")

  local protected = {}
  SyncEngine._shared = {
    state = { enabled = true },
    linked = function() return true end,
    busy = function() return false end,
    noteSaveWritten = function() end,
    update = function() end,
    protectPlaythrough = function(_, version, id)
      protected.version, protected.id = version, id
    end,
  }
  local loaded = SaveData.load("red")
  T.eq(loaded and loaded.player.name, "ASH", "CONTINUE loads that slot")
  local game = setmetatable({ save = loaded }, { __index = Game })
  T.check(Game.syncEngine(game) ~= nil, "the running game reaches the engine")
  T.eq(protected.version, "red", "and protects its own game")
  T.eq(protected.id, mapped,
    "under the mapped identity, so an in-game sync cannot replace the slot it is playing")
  T.eq(onDisk(files, slot).meta.playthroughId, nil,
    "loading never rewrites the progress bytes")
  SyncEngine.forgetShared()
end

do
  local files = fresh()
  local Game = require("src.core.Game")
  local slot = SaveData.createSlot("red")
  SaveData.setActiveSlot("red", slot)
  local provider = SyncEngine.defaultSaves()
  local protected, busy, listed = {}, false, 0
  SyncEngine._shared = {
    state = { enabled = true },
    linked = function() return true end,
    busy = function() return busy end,
    noteSaveWritten = function() busy = true end,
    update = function()
      if busy then
        listed = listed + #provider.list()
        busy = false
      end
    end,
    protectPlaythrough = function(_, version, id)
      protected.version, protected.id = version, id
    end,
  }
  local game = setmetatable({ save = SaveData.newGame(),
    sessionStartedAt = os.time() - 60 }, { __index = Game })
  game.save.player.name = "ASH"
  Game.updateSync(game, 0.1)
  T.eq(protected.id, nil, "an unsaved New Game protects no key")

  T.eq(Game.writeSave(game), true, "the first in-game save lands")
  T.eq(game.save.meta.playthroughId, nil, "with no identity yet")
  T.eq(onDisk(files, slot).meta.playthroughId, nil, "on disk either")
  Game.updateSync(game, 0.1)
  T.eq(listed, 1, "the debounced upload lists the new slot")
  local mapped = SaveData.loadOptions().playthroughIds.red[slot]
  T.check(type(mapped) == "string" and #mapped == 32,
    "and mints its identity into the mapping")
  T.eq(game.save.meta.playthroughId, mapped,
    "the running save adopts the identity the sync minted for its slot")
  Game.syncEngine(game)
  T.eq(protected.id, mapped,
    "so the next sync cannot replace the slot under the running game")
  T.eq(onDisk(files, slot).meta.playthroughId, nil,
    "adopting rewrites nothing on disk until the next SAVE")

  local title = setmetatable({ save = SaveData.newGame() }, { __index = Game })
  busy = true
  Game.updateSync(title, 0.1)
  T.eq(title.save.meta.playthroughId, nil,
    "an unsaved skeleton never takes the slot's identity")
  Game.syncEngine(title)
  T.eq(protected.id, nil,
    "and leaves the slot open for a download at the title")
  SyncEngine.forgetShared()
end

love.filesystem = realFS

T.finish("sync_session_meta")
