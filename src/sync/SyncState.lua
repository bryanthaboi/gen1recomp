local SaveData = require("src.core.SaveData")

local SyncState = {}

SyncState.KEY = "saveSync"

function SyncState.defaults()
  return {
    enabled = false,
    lastSyncAt = 0,
    revs = {},
    stamps = {},
    pendingConflicts = {},
  }
end

local function str(v)
  if type(v) == "string" and v ~= "" then return v end
  return nil
end

local function num(v)
  local n = tonumber(v)
  if type(n) ~= "number" or n ~= n or n == math.huge or n == -math.huge then
    return nil
  end
  return n
end

function SyncState.sanitize(raw)
  local out = SyncState.defaults()
  if type(raw) ~= "table" then return out end
  out.enabled = raw.enabled == true
  out.account = str(raw.account)
  out.deviceToken = str(raw.deviceToken)
  out.deviceId = str(raw.deviceId)
  out.deviceLabel = str(raw.deviceLabel)
  out.lastSyncAt = num(raw.lastSyncAt) or 0
  if type(raw.revs) == "table" then
    for key, rev in pairs(raw.revs) do
      local n = num(rev)
      if type(key) == "string" and n then out.revs[key] = n end
    end
  end
  if type(raw.stamps) == "table" then
    for key, at in pairs(raw.stamps) do
      local n = num(at)
      if type(key) == "string" and n then out.stamps[key] = n end
    end
  end
  if type(raw.pendingConflicts) == "table" then
    for _, row in ipairs(raw.pendingConflicts) do
      if type(row) == "table" and str(row.key) then
        out.pendingConflicts[#out.pendingConflicts + 1] = {
          key = row.key,
          version = str(row.version),
          playthroughId = str(row.playthroughId),
          overlap = row.overlap == true,
        }
      end
    end
  end
  return out
end

function SyncState.load(fs)
  local opts = SaveData.loadOptions(fs)
  return SyncState.sanitize(opts and opts[SyncState.KEY])
end

function SyncState.save(state, fs)
  local opts = SaveData.loadOptions(fs)
  opts[SyncState.KEY] = SyncState.sanitize(state)
  SaveData.saveOptions(opts, fs)
  return opts[SyncState.KEY]
end

function SyncState.update(fn, fs)
  local state = SyncState.load(fs)
  fn(state)
  return SyncState.save(state, fs)
end

function SyncState.clear(fs)
  return SyncState.save(SyncState.defaults(), fs)
end

function SyncState.linked(state)
  return type(state) == "table" and str(state.account) ~= nil
    and str(state.deviceToken) ~= nil
end

function SyncState.key(version, playthroughId)
  if type(version) ~= "string" or version == "" then return nil end
  if type(playthroughId) ~= "string" or playthroughId == "" then return nil end
  return version .. "/" .. playthroughId
end

function SyncState.splitKey(key)
  if type(key) ~= "string" then return nil end
  local version, id = key:match("^([^/]+)/(.+)$")
  return version, id
end

function SyncState.rev(state, key)
  if type(state) ~= "table" or type(state.revs) ~= "table" then return nil end
  return state.revs[key]
end

function SyncState.stamp(state, key)
  if type(state) ~= "table" or type(state.stamps) ~= "table" then return nil end
  return state.stamps[key]
end

function SyncState.setRev(state, key, rev, savedAt)
  if type(state) ~= "table" or type(key) ~= "string" then return end
  state.revs = state.revs or {}
  state.stamps = state.stamps or {}
  state.revs[key] = num(rev)
  state.stamps[key] = num(savedAt)
end

function SyncState.forget(state, key)
  if type(state) ~= "table" or type(key) ~= "string" then return end
  if type(state.revs) == "table" then state.revs[key] = nil end
  if type(state.stamps) == "table" then state.stamps[key] = nil end
end

return SyncState
