local SyncClient = require("src.sync.SyncClient")
local SyncState = require("src.sync.SyncState")
local SyncMods = require("src.sync.SyncMods")

local SyncEngine = {}
SyncEngine.__index = SyncEngine

SyncEngine.UPLOAD_DEBOUNCE = 5
SyncEngine.AUTO_INTERVAL = 300
SyncEngine.MAX_STEPS_PER_UPDATE = 8

local IDLE_STATUS = "Ready"
local UNLINKED_STATUS = "Not set up"

local function saveApi()
  return require("src.core.SaveData")
end

local function gameVersions()
  return require("src.core.GameVersion").ORDER
end

local function slotForPlaythrough(options, version, playthroughId)
  local byVersion = options.playthroughIds and options.playthroughIds[version]
  for slotId, id in pairs(byVersion or {}) do
    if id == playthroughId then return slotId end
  end
  return nil
end

function SyncEngine.defaultSaves()
  return {
    list = function()
      local SaveData = saveApi()
      local options = SaveData.loadOptions()
      local out = {}
      for _, version in ipairs(gameVersions()) do
        for _, slot in ipairs(SaveData.listSlots(version)) do
          if slot.exists then
            local source = SaveData.readSlotSource(version, slot.id)
            local save = source and SaveData.decode(source)
            if type(save) == "table" then
              local meta = type(save.meta) == "table" and save.meta or {}
              local id = meta.playthroughId
              if type(id) ~= "string" or id == "" then
                local byVersion = options.playthroughIds
                  and options.playthroughIds[version]
                id = byVersion and byVersion[slot.id] or nil
              end
              if id then
                local name, summary = SaveData.slotSummary(save)
                out[#out + 1] = {
                  version = version,
                  slot = slot.id,
                  playthroughId = id,
                  blob = source,
                  meta = {
                    savedAt = tonumber(meta.savedAt),
                    sessionStart = tonumber(meta.sessionStart),
                    playthroughId = id,
                    format = meta.format,
                    engine = meta.engine,
                    playTime = tonumber(save.playTime),
                    summary = {
                      name = name,
                      badges = summary and summary.badges,
                      timeText = summary and summary.timeText,
                      dexCount = summary and summary.dexCount,
                    },
                  },
                }
              end
            end
          end
        end
      end
      return out
    end,

    write = function(version, playthroughId, blob, mode)
      local SaveData = saveApi()
      local save = SaveData.decode(blob)
      if type(save) ~= "table" then return nil, "the downloaded save is unreadable" end
      save.version = save.version or version
      local options = SaveData.loadOptions()
      local slotId
      if mode == "new" then
        save.meta = type(save.meta) == "table" and save.meta or {}
        save.meta.playthroughId = SaveData.newPlaythroughId()
      else
        slotId = slotForPlaythrough(options, version, playthroughId)
      end
      if not slotId then
        slotId = SaveData.createSlot(version)
        if not slotId then return nil, "could not make a save slot" end
      end
      local ok, err = SaveData.writeSlot(version, slotId, save)
      if not ok then return nil, err or "could not write the save" end
      options = SaveData.loadOptions()
      options.playthroughIds = options.playthroughIds or {}
      options.playthroughIds[version] = options.playthroughIds[version] or {}
      options.playthroughIds[version][slotId] =
        save.meta and save.meta.playthroughId or playthroughId
      SaveData.saveOptions(options)
      return slotId
    end,
  }
end

function SyncEngine.overlaps(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  local aStart, aEnd = tonumber(a.sessionStart), tonumber(a.savedAt)
  local bStart, bEnd = tonumber(b.sessionStart), tonumber(b.savedAt)
  if not (aStart and aEnd and bStart and bEnd) then return false end
  return aStart <= bEnd and bStart <= aEnd
end

function SyncEngine.new(opts)
  opts = opts or {}
  local eng = setmetatable({}, SyncEngine)
  eng.fs = opts.fs
  eng.state = opts.state or SyncState.load(eng.fs)
  eng.client = opts.client or SyncClient.new({
    baseUrl = opts.baseUrl, transport = opts.transport })
  eng.saves = opts.saves or SyncEngine.defaultSaves()
  eng.modDeps = opts.modDeps
  eng.now = opts.now or os.time
  eng.persist = opts.persist ~= false
  eng.phase = "idle"
  eng.error = nil
  eng.conflicts = {}
  eng.codes = nil
  eng.modPlan = nil
  eng.shareCode = nil
  eng.clock = 0
  eng.queue = {}
  eng.pending = nil
  eng.uploadAt = nil
  eng.client:setAuth(eng.state.account, eng.state.deviceToken)
  eng.status = eng:defaultStatus()
  return eng
end

function SyncEngine.shared(opts)
  if SyncEngine._shared == nil then
    local ok, eng = pcall(SyncEngine.new, opts or {})
    SyncEngine._shared = (ok and type(eng) == "table") and eng or false
  end
  return SyncEngine._shared or nil
end

function SyncEngine.forgetShared()
  SyncEngine._shared = nil
end

function SyncEngine:defaultStatus()
  if not SyncState.linked(self.state) then return UNLINKED_STATUS end
  return IDLE_STATUS
end

function SyncEngine:linked()
  return SyncState.linked(self.state)
end

function SyncEngine:busy()
  return self.pending ~= nil or #self.queue > 0 or self.modApply ~= nil
end

function SyncEngine:_persist()
  if not self.persist then return end
  SyncState.save(self.state, self.fs)
end

function SyncEngine:_fail(message)
  self.phase = "error"
  self.error = tostring(message or "sync failed")
  self.status = "Sync failed: " .. self.error
  self.queue = {}
  self.pending = nil
end

function SyncEngine:_finish()
  if #self.conflicts > 0 then
    self.phase = "conflict"
    local overlap = false
    for _, row in ipairs(self.conflicts) do
      if row.overlap then overlap = true end
    end
    self.status = overlap
      and "These saves were played at the same time."
      or "This save also changed on another device."
    return
  end
  self.phase = "idle"
  self.error = nil
  self.state.lastSyncAt = self.now()
  self.status = self:defaultStatus()
  self:_persist()
end

function SyncEngine:_request(handle, err, onOk, onErr)
  if not handle then
    self:_fail(err or "could not start the request")
    return false
  end
  self.pending = { handle = handle, onOk = onOk, onErr = onErr }
  return true
end

function SyncEngine:_enqueue(fn)
  self.queue[#self.queue + 1] = fn
end

function SyncEngine:cancel()
  if self.pending then self.client:release(self.pending.handle) end
  self.pending = nil
  self.queue = {}
  self.modApply = nil
  self.uploadAt = nil
  if self.phase ~= "conflict" then
    self.phase = "idle"
    self.status = self:defaultStatus()
  end
end

function SyncEngine:noteSaveWritten()
  if not (self.state.enabled and self:linked()) then return end
  self.uploadAt = self.clock + SyncEngine.UPLOAD_DEBOUNCE
end

function SyncEngine:update(dt)
  self.clock = self.clock + (tonumber(dt) or 0)
  if self.pending then
    local res = self.client:poll(self.pending.handle)
    if res.status == "pending" then return end
    local job = self.pending
    self.pending = nil
    self.client:release(job.handle)
    if res.status == "ok" then
      local ok, err = pcall(job.onOk, self, res)
      if not ok then self:_fail(err) end
    else
      local handled = false
      if job.onErr then
        local ok, result = pcall(job.onErr, self, res)
        if not ok then self:_fail(result) return end
        handled = result == true
      end
      if not handled then self:_fail(res.err) end
    end
  end
  if self.pending then return end
  if self.modApply then
    self:_stepModApply()
    return
  end
  if self.uploadAt and self.clock >= self.uploadAt and not self:busy() then
    self.uploadAt = nil
    if self.state.enabled and self:linked() then self:syncNow() end
  end
  local steps = 0
  while not self.pending and #self.queue > 0
      and steps < SyncEngine.MAX_STEPS_PER_UPDATE do
    steps = steps + 1
    local task = table.remove(self.queue, 1)
    local ok, err = pcall(task, self)
    if not ok then self:_fail(err) return end
    if not self.pending and #self.queue == 0 and self.phase ~= "error" then
      self:_finish()
    end
  end
end

function SyncEngine:createAccount(label)
  if self:busy() then return false, "sync is busy" end
  self.phase = "checking"
  self.status = "Creating a sync account..."
  self.error = nil
  local handle, err = self.client:create(label)
  return self:_request(handle, err, function(eng, res)
    local data = res.data or {}
    if type(data.account) ~= "string" or type(data.deviceToken) ~= "string" then
      eng:_fail("the server sent an unexpected reply")
      return
    end
    eng.codes = {
      code1 = SyncClient.formatCode(data.code1) or tostring(data.code1 or ""),
      code2 = SyncClient.formatCode(data.code2) or tostring(data.code2 or ""),
    }
    eng.state.account = data.account
    eng.state.deviceToken = data.deviceToken
    eng.state.deviceId = type(data.device) == "string" and data.device or nil
    eng.state.deviceLabel = label
    eng.state.enabled = true
    eng.client:setAuth(data.account, data.deviceToken)
    eng.phase = "idle"
    eng.status = "Sync account created"
    eng:_persist()
  end)
end

function SyncEngine:linkDevice(code1, code2, label)
  if self:busy() then return false, "sync is busy" end
  local a = SyncClient.normalizeCode(code1)
  local b = SyncClient.normalizeCode(code2)
  if not a or not b then
    self:_fail("both codes are 8 digits")
    return false, "both codes are 8 digits"
  end
  self.phase = "checking"
  self.status = "Linking this device..."
  self.error = nil
  local handle, err = self.client:link(a, b, label)
  return self:_request(handle, err, function(eng, res)
    local data = res.data or {}
    if type(data.account) ~= "string" or type(data.deviceToken) ~= "string" then
      eng:_fail("the server sent an unexpected reply")
      return
    end
    eng.state.account = data.account
    eng.state.deviceToken = data.deviceToken
    eng.state.deviceId = type(data.device) == "string" and data.device or nil
    eng.state.deviceLabel = label
    eng.state.enabled = true
    eng.client:setAuth(data.account, data.deviceToken)
    eng.status = "This device is linked"
    eng:_persist()
    eng:syncNow()
  end)
end

function SyncEngine:_forgetLocal()
  self.state = SyncState.defaults()
  self.client:clearAuth()
  self.codes = nil
  self.conflicts = {}
  self.devices = nil
  self.phase = "idle"
  self.status = UNLINKED_STATUS
  self:_persist()
end

function SyncEngine:unlink()
  if not self:linked() then
    self:_forgetLocal()
    return true
  end
  if self:busy() then return false, "sync is busy" end
  self.phase = "checking"
  self.status = "Unlinking this device..."
  self.error = nil
  local handle, err = self.client:unlink(self.state.deviceId)
  return self:_request(handle, err, function(eng)
    eng:_forgetLocal()
  end, function(eng, res)
    if res.code == 401 or res.code == 404 then
      eng:_forgetLocal()
      return true
    end
    return false
  end)
end

function SyncEngine:unlinkDevice(deviceId)
  if type(deviceId) ~= "string" or deviceId == "" then
    return false, "no such device"
  end
  if not self:linked() then return false, "this device is not linked" end
  if deviceId == self.state.deviceId then return self:unlink() end
  if self:busy() then return false, "sync is busy" end
  self.phase = "checking"
  self.status = "Unlinking that device..."
  self.error = nil
  local handle, err = self.client:unlink(deviceId)
  return self:_request(handle, err, function(eng)
    eng.status = "That device was unlinked"
    eng.phase = "idle"
    eng:syncNow()
  end)
end

function SyncEngine:setEnabled(enabled)
  self.state.enabled = enabled and true or false
  self:_persist()
  return self.state.enabled
end

function SyncEngine:syncNow()
  if not self:linked() then return false, "this device is not linked" end
  if self.pending then return false, "sync is busy" end
  self.queue = {}
  self.conflicts = {}
  self.state.pendingConflicts = {}
  self.phase = "checking"
  self.status = "Checking for changes..."
  self.error = nil
  local handle, err = self.client:fetchState()
  return self:_request(handle, err, function(eng, res)
    eng:_planFrom(res.data or {})
  end)
end

function SyncEngine:_planFrom(remoteState)
  self.devices = nil
  if type(remoteState.devices) == "table" then
    local list = {}
    for _, row in ipairs(remoteState.devices) do
      if type(row) == "table" and type(row.id) == "string" and row.id ~= "" then
        list[#list + 1] = {
          id = row.id,
          label = type(row.label) == "string" and row.label ~= "" and row.label
            or "device",
          createdAt = tonumber(row.createdAt),
          current = row.current == true or row.id == self.state.deviceId,
        }
      end
    end
    self.devices = list
  end
  local remote = type(remoteState.saves) == "table" and remoteState.saves or {}
  local locals = self.saves.list() or {}
  local seen = {}
  for _, entry in ipairs(locals) do
    local key = SyncState.key(entry.version, entry.playthroughId)
    if key then
      seen[key] = true
      local row = remote[key]
      local knownRev = SyncState.rev(self.state, key)
      local stamp = SyncState.stamp(self.state, key)
      local localChanged = stamp == nil
        or tonumber(entry.meta and entry.meta.savedAt) ~= stamp
      local remoteRev = row and tonumber(row.rev)
      local remoteChanged = row ~= nil and remoteRev ~= knownRev
      if not row then
        self:_queueUpload(entry, key, false)
      elseif localChanged and remoteChanged then
        self:_addConflict(entry, key, row)
      elseif localChanged then
        self:_queueUpload(entry, key, false)
      elseif remoteChanged then
        self:_queueDownload(key, entry.version, entry.playthroughId, "replace")
      end
    end
  end
  for key, row in pairs(remote) do
    if not seen[key] then
      local version, id = SyncState.splitKey(key)
      if version and id then
        self:_queueDownload(key, version, id, "replace", tonumber(row.rev))
      end
    end
  end
  if #self.queue == 0 then self:_finish() end
end

function SyncEngine:_addConflict(entry, key, row)
  local remoteMeta = row
  if type(row.meta) == "table" then
    remoteMeta = row.meta
  elseif type(row.remoteMeta) == "table" then
    remoteMeta = row.remoteMeta
  end
  self.conflicts[#self.conflicts + 1] = {
    key = key,
    version = entry.version,
    playthroughId = entry.playthroughId,
    slot = entry.slot,
    entry = entry,
    localMeta = entry.meta,
    remoteMeta = remoteMeta,
    remoteRev = tonumber(row.rev),
    overlap = SyncEngine.overlaps(entry.meta, remoteMeta),
  }
  local pending = self.state.pendingConflicts or {}
  self.state.pendingConflicts = pending
  for _, row in ipairs(pending) do
    if row.key == key then return end
  end
  pending[#pending + 1] = {
    key = key,
    version = entry.version,
    playthroughId = entry.playthroughId,
    overlap = SyncEngine.overlaps(entry.meta, remoteMeta),
  }
end

function SyncEngine:_queueUpload(entry, key, force)
  self:_enqueue(function(eng)
    eng.phase = "uploading"
    eng.status = "Uploading saves..."
    local handle, err = eng.client:putSave({
      version = entry.version,
      slot = entry.slot,
      meta = entry.meta,
      blob = entry.blob,
      baseRev = SyncState.rev(eng.state, key),
      force = force,
    })
    eng:_request(handle, err, function(e, res)
      local data = res.data or {}
      SyncState.setRev(e.state, key, tonumber(data.rev),
        entry.meta and entry.meta.savedAt)
      e:_persist()
      if not e:busy() then e:_finish() end
    end, function(e, res)
      if res.code == 409 then
        local row = res.data or {}
        e:_addConflict(entry, key, row)
        if not e:busy() then e:_finish() end
        return true
      end
      return false
    end)
  end)
end

function SyncEngine:_queueDownload(key, version, playthroughId, mode, knownRev)
  self:_enqueue(function(eng)
    eng.phase = "downloading"
    eng.status = "Downloading saves..."
    local handle, err = eng.client:getSave(version, playthroughId)
    eng:_request(handle, err, function(e, res)
      local data = res.data or {}
      if type(data.blob) ~= "string" or data.blob == "" then
        e:_fail("the server sent no save data")
        return
      end
      local slotId, writeErr = e.saves.write(version, playthroughId, data.blob, mode)
      if not slotId then
        e:_fail(writeErr or "could not write the downloaded save")
        return
      end
      if mode ~= "new" then
        local meta = type(data.meta) == "table" and data.meta or {}
        SyncState.setRev(e.state, key, tonumber(data.rev) or knownRev,
          tonumber(meta.savedAt))
      end
      e:_persist()
      if not e:busy() then e:_finish() end
    end)
  end)
end

function SyncEngine:resolveConflict(key, choice)
  local index
  for i, row in ipairs(self.conflicts) do
    if row.key == key then index = i break end
  end
  if not index then return false, "no such conflict" end
  local conflict = table.remove(self.conflicts, index)
  local kept = {}
  for _, row in ipairs(self.state.pendingConflicts or {}) do
    if row.key ~= key then kept[#kept + 1] = row end
  end
  self.state.pendingConflicts = kept

  if choice == "local" then
    SyncState.setRev(self.state, key, conflict.remoteRev, nil)
    self:_queueUpload(conflict.entry, key, true)
  elseif choice == "remote" then
    self:_queueDownload(key, conflict.version, conflict.playthroughId,
      "replace", conflict.remoteRev)
  elseif choice == "both" then
    self:_queueDownload(key, conflict.version, conflict.playthroughId,
      "new", conflict.remoteRev)
    SyncState.setRev(self.state, key, conflict.remoteRev, nil)
    self:_queueUpload(conflict.entry, key, true)
  else
    return false, "unknown resolution"
  end
  self.phase = "uploading"
  self.status = "Applying your choice..."
  return true
end

function SyncEngine:uploadMods()
  if not self:linked() then return false, "this device is not linked" end
  if self:busy() then return false, "sync is busy" end
  local manifest = SyncMods.build(self.modDeps)
  self.phase = "uploading"
  self.status = "Uploading the mod list..."
  local handle, err = self.client:putMods(manifest)
  return self:_request(handle, err, function(eng)
    eng.phase = "idle"
    eng.status = "Mod list synced"
  end)
end

function SyncEngine:fetchModPlan()
  if not self:linked() then return false, "this device is not linked" end
  if self:busy() then return false, "sync is busy" end
  self.phase = "downloading"
  self.status = "Reading the mod list..."
  local handle, err = self.client:getMods()
  return self:_request(handle, err, function(eng, res)
    local data = res.data or {}
    local manifest = type(data.manifest) == "table" and data.manifest or data
    eng.modPlan = SyncMods.plan(manifest, eng.modDeps)
    eng.phase = "idle"
    eng.status = SyncMods.planEmpty(eng.modPlan)
      and "Mods already match" or "Mod changes ready to apply"
  end)
end

function SyncEngine:shareMods()
  if not self:linked() then return false, "this device is not linked" end
  if self:busy() then return false, "sync is busy" end
  local manifest = SyncMods.build(self.modDeps)
  self.phase = "uploading"
  self.status = "Sharing the mod list..."
  local handle, err = self.client:shareMods(manifest)
  return self:_request(handle, err, function(eng, res)
    local data = res.data or {}
    eng.shareCode = type(data.code) == "string" and data.code or nil
    eng.phase = "idle"
    eng.status = eng.shareCode and ("Share code " .. eng.shareCode)
      or "The server sent no share code"
  end)
end

function SyncEngine:fetchShare(code)
  if self:busy() then return false, "sync is busy" end
  self.phase = "downloading"
  self.status = "Fetching that mod list..."
  local handle, err = self.client:fetchShare(code)
  return self:_request(handle, err, function(eng, res)
    local data = res.data or {}
    local manifest = type(data.manifest) == "table" and data.manifest or data
    eng.modPlan = SyncMods.plan(manifest, eng.modDeps)
    eng.phase = "idle"
    eng.status = SyncMods.planEmpty(eng.modPlan)
      and "Mods already match" or "Mod changes ready to apply"
  end)
end

function SyncEngine:applyModPlan(progress)
  if not self.modPlan then return false, "no mod plan" end
  if self.modApply then return false, "the mods are already being applied" end
  local steps = SyncMods.steps(self.modPlan, self.modDeps)
  if #steps == 0 then
    self.modPlan = nil
    self.status = "Mods already match"
    if progress then progress(0, 0, nil, true) end
    return true
  end
  self.modApply = { steps = steps, index = 0, failures = {},
                    progress = progress }
  self.phase = "applying"
  self.status = ("Applying mods... 0 of %d"):format(#steps)
  return true
end

function SyncEngine:applyingMods()
  return self.modApply ~= nil
end

function SyncEngine:_stepModApply()
  local job = self.modApply
  local step = job.steps[job.index + 1]
  job.index = job.index + 1
  local ok, res, why = pcall(step.run)
  if not ok then
    job.failures[#job.failures + 1] = tostring(res)
  elseif not res then
    job.failures[#job.failures + 1] = tostring(why or step.label)
  end
  local total = #job.steps
  local done = job.index >= total
  if not done then
    self.status = ("Applying mods... %d of %d"):format(job.index, total)
    if job.progress then
      pcall(job.progress, job.index, total, step.label, false)
    end
    return
  end
  self.modApply = nil
  self.modPlan = nil
  self.phase = "idle"
  if #job.failures > 0 then
    self.status = "Some mods could not be applied: "
      .. table.concat(job.failures, "; ")
  else
    self.status = "Mods applied"
  end
  if job.progress then
    pcall(job.progress, job.index, total, step.label, true)
  end
end

return SyncEngine
