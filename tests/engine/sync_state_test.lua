package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
love = love or require("tests.love_stub")

local SaveData = require("src.core.SaveData")
local SyncState = require("src.sync.SyncState")

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
  return files
end

do
  local opts = SaveData.defaultOptions()
  T.check(type(opts.saveSync) == "table", "defaultOptions carries saveSync")
  T.eq(opts.saveSync.enabled, false, "sync is off until the player sets it up")
  T.check(type(opts.saveSync.revs) == "table", "and starts with no synced revs")
  T.eq(opts.saveSync.account, nil, "and no account")

  local state = SyncState.defaults()
  T.eq(SyncState.linked(state), false, "a default state is not linked")
  T.eq(state.lastSyncAt, 0, "and has never synced")
end

do
  local dirty = SyncState.sanitize({
    enabled = "yes",
    account = "aa11bb22cc33dd44",
    deviceToken = "tok",
    deviceLabel = "",
    lastSyncAt = 0 / 0,
    code1 = "12345678",
    code2 = "87654321",
    revs = { ["red/aaa"] = 4, [7] = 9, ["red/bad"] = "no" },
    stamps = { ["red/aaa"] = 1700 },
    pendingConflicts = { { key = "red/aaa", version = "red", overlap = true },
                         { nope = true } },
  })
  T.eq(dirty.enabled, false, "a non-boolean enabled reads as off")
  T.eq(dirty.account, "aa11bb22cc33dd44", "the account id survives")
  T.eq(dirty.deviceLabel, nil, "an empty device label is dropped")
  T.eq(dirty.lastSyncAt, 0, "a NaN lastSyncAt is refused")
  T.eq(dirty.code1, nil, "the first account code is never kept")
  T.eq(dirty.code2, nil, "nor the second")
  T.eq(dirty.revs["red/aaa"], 4, "numeric revs survive")
  T.eq(dirty.revs["red/bad"], nil, "a non-numeric rev is dropped")
  T.eq(dirty.revs[7], nil, "a non-string rev key is dropped")
  T.eq(dirty.stamps["red/aaa"], 1700, "the savedAt stamp survives")
  T.eq(#dirty.pendingConflicts, 1, "only well-formed conflicts are kept")
  T.eq(dirty.pendingConflicts[1].overlap, true, "with their overlap flag")
end

do
  local files = fresh()
  local state = SyncState.load()
  T.eq(SyncState.linked(state), false, "a first boot has no linked account")

  state.account = "aa11bb22cc33dd44"
  state.deviceToken = "feedface"
  state.deviceId = "0a1b2c3d"
  state.deviceLabel = "laptop"
  state.enabled = true
  state.code1 = "12345678"
  SyncState.setRev(state, SyncState.key("red", "abc"), 3, 1700000000)
  SyncState.save(state)

  T.check(files["options.lua"] ~= nil, "the state lands in options.lua")
  T.eq(files["options.lua"]:find("12345678", 1, true), nil,
    "the account codes are never written to disk")

  local back = SyncState.load()
  T.eq(SyncState.linked(back), true, "the linked account survives a reload")
  T.eq(back.deviceLabel, "laptop", "and the device label")
  T.eq(back.deviceId, "0a1b2c3d",
    "and the device id the server revokes tokens by")
  T.eq(SyncState.rev(back, "red/abc"), 3, "and the last synced rev")
  T.eq(SyncState.stamp(back, "red/abc"), 1700000000, "and the savedAt stamp")
  T.eq(back.code1, nil, "the code is gone from the reloaded state")

  local opts = SaveData.loadOptions()
  T.eq(opts.textSpeed, 3, "writing sync state leaves other options alone")

  SyncState.forget(back, "red/abc")
  T.eq(SyncState.rev(back, "red/abc"), nil, "forget drops the rev")
  T.eq(SyncState.stamp(back, "red/abc"), nil, "and the stamp")

  SyncState.clear()
  T.eq(SyncState.linked(SyncState.load()), false, "clear unlinks the device")
end

do
  T.eq(SyncState.key("red", "abc"), "red/abc", "keys join version and id")
  T.eq(SyncState.key("red", ""), nil, "an empty playthrough id has no key")
  T.eq(SyncState.key(nil, "abc"), nil, "and neither does a missing version")
  local version, id = SyncState.splitKey("gold/deadbeef")
  T.eq(version, "gold", "splitKey reads the version back")
  T.eq(id, "deadbeef", "and the playthrough id")
end

love.filesystem = realFS

T.finish("sync_state")
