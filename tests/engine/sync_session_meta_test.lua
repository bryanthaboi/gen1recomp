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
  T.check(entries[1].blob:find("ASH", 1, true) ~= nil,
    "the blob is the encoded save itself")

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

love.filesystem = realFS

T.finish("sync_session_meta")
