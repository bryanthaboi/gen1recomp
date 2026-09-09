local SyncClient = require("src.sync.SyncClient")
local SyncState = require("src.sync.SyncState")
local SyncMods = require("src.sync.SyncMods")

local SyncEngine = {}
SyncEngine.__index = SyncEngine

SyncEngine.UPLOAD_DEBOUNCE = 5
SyncEngine.AUTO_INTERVAL = 300
SyncEngine.RESUME_MIN_GAP = 60
SyncEngine.MAX_STEPS_PER_UPDATE = 8

local IDLE_STATUS = "Ready"
local UNLINKED_STATUS = "Not set up"

local function unixSeconds(v)
  local n = tonumber(v)
  if not n or n ~= n or n <= 0 or n == math.huge or n == -math.huge then
    return nil
  end
  return n
end

SyncEngine.unixSeconds = unixSeconds

local function saveApi()
  return require("src.core.SaveData")
end

local function gameVersions()
  return require("src.core.GameVersion").ORDER
end

local CART_PREFIX = "cart_"

local function cartOfScope(key)
  if type(key) ~= "string" then return nil end
  if key:sub(1, #CART_PREFIX) ~= CART_PREFIX then return nil end
  local id = key:sub(#CART_PREFIX + 1)
  if id == "" then return nil end
  return id
end

local function safeCartId(id)
  if type(id) ~= "string" or id == "" or #id > 64 then return nil end
  if not id:match("^[%w_%-]+$") then return nil end
  return id
end

local function blobCart(save)
  local meta = type(save) == "table" and save.meta or nil
  return safeCartId(type(meta) == "table" and meta.cartId or nil)
end

local function cartInstalled(options, cartId)
  local reg = type(options) == "table" and options.carts or nil
  if type(reg) == "table" and type(reg[cartId]) == "table" then return true end
  local ok, CartStore = pcall(require, "src.carts.CartStore")
  if not ok or type(CartStore) ~= "table" then return false end
  local fs = love and love.filesystem
  if type(fs) ~= "table" or type(fs.getInfo) ~= "function" then return false end
  local okInfo, info = pcall(fs.getInfo, CartStore.fileFor(cartId))
  return okInfo and info ~= nil
end

local function syncScopes()
  local SaveData = saveApi()
  local out = {}
  for _, version in ipairs(gameVersions()) do
    out[#out + 1] = { key = version, version = version }
  end
  local ok, ids = pcall(SaveData.cartsWithSlots)
  if not ok or type(ids) ~= "table" then return out end
  local okOpts, options = pcall(SaveData.loadOptions)
  local reg = (okOpts and type(options) == "table"
    and type(options.carts) == "table") and options.carts or {}
  for _, id in ipairs(ids) do
    local row = type(reg[id]) == "table" and reg[id] or nil
    out[#out + 1] = { key = CART_PREFIX .. id, cart = id,
                      version = row and row.base or nil }
  end
  return out
end

local function wireVersion(save, scope)
  local GameVersion = require("src.core.GameVersion")
  if not scope.cart and type(scope.version) == "string"
      and GameVersion.VERSIONS[scope.version] then
    return scope.version
  end
  local v = type(save) == "table" and save.version or nil
  if type(v) == "string" and GameVersion.VERSIONS[v] then return v end
  if type(scope.version) == "string" and GameVersion.VERSIONS[scope.version] then
    return scope.version
  end
  return GameVersion.get()
end

local function slotForPlaythrough(options, version, playthroughId)
  local root = (type(options) == "table" and type(options.playthroughIds) == "table")
    and options.playthroughIds or {}
  local byVersion = type(root[version]) == "table" and root[version] or nil
  for slotId, id in pairs(byVersion or {}) do
    if id == playthroughId then return version, slotId end
  end
  local bestKey, bestSlot
  for key, byScope in pairs(root) do
    if key ~= version and cartOfScope(key) and type(byScope) == "table" then
      for slotId, id in pairs(byScope) do
        if id == playthroughId and slotId ~= "legacy"
            and (bestKey == nil or key < bestKey) then
          bestKey, bestSlot = key, slotId
        end
      end
    end
  end
  return bestKey, bestSlot
end

local function slotKey(scopeKey, slotId)
  local SaveData = saveApi()
  local cart = cartOfScope(scopeKey)
  local source
  if cart then
    source = SaveData.readCartSlotSource(cart, slotId)
  else
    source = SaveData.readSlotSource(scopeKey, slotId)
  end
  local save = source and SaveData.decode(source)
  if type(save) ~= "table" then return nil end
  local id
  local scope = { key = scopeKey, cart = cart, version = scopeKey }
  if cart then
    id = SaveData.cartSlotPlaythroughId(cart, slotId, save)
    local okOpts, options = pcall(SaveData.loadOptions)
    local reg = (okOpts and type(options) == "table"
      and type(options.carts) == "table") and options.carts[cart] or nil
    scope.version = type(reg) == "table" and reg.base or nil
  else
    id = SaveData.slotPlaythroughId(scopeKey, slotId, save)
  end
  if not id then return nil end
  return SyncState.key(wireVersion(save, scope), id)
end

function SyncEngine.defaultSaves()
  return {
    keyForSlot = slotKey,

    remove = function(version, playthroughId)
      local SaveData = saveApi()
      local options = SaveData.loadOptions()
      local scopeKey, slotId = slotForPlaythrough(options, version, playthroughId)
      if not slotId then return false, "no such save" end
      local cart = cartOfScope(scopeKey)
      local ok, err
      if cart then
        ok, err = SaveData.deleteCartSlot(cart, slotId)
      else
        ok, err = SaveData.deleteSlot(scopeKey, slotId)
      end
      if not ok then return nil, err or "could not delete the save" end
      options = SaveData.loadOptions()
      if type(options.playthroughIds) == "table"
          and type(options.playthroughIds[scopeKey]) == "table" then
        options.playthroughIds[scopeKey][slotId] = nil
        SaveData.saveOptions(options)
      end
      return slotId, cart
    end,

    list = function()
      local SaveData = saveApi()
      local out = {}
      for _, scope in ipairs(syncScopes()) do
        local slots = scope.cart and SaveData.listCartSlots(scope.cart)
          or SaveData.listSlots(scope.version)
        for _, slot in ipairs(slots) do
          if slot.exists then
            local source
            if scope.cart then
              source = SaveData.readCartSlotSource(scope.cart, slot.id)
            else
              source = SaveData.readSlotSource(scope.version, slot.id)
            end
            local save = source and SaveData.decode(source)
            if type(save) == "table" then
              local meta = type(save.meta) == "table" and save.meta or {}
              local id
              if scope.cart then
                id = SaveData.cartSlotPlaythroughId(scope.cart, slot.id, save)
              else
                id = SaveData.slotPlaythroughId(scope.version, slot.id, save)
              end
              if id then
                local name, summary = SaveData.slotSummary(save)
                out[#out + 1] = {
                  version = wireVersion(save, scope),
                  cart = scope.cart,
                  slot = slot.id,
                  playthroughId = id,
                  blob = source,
                  meta = {
                    savedAt = unixSeconds(meta.savedAt)
                      or unixSeconds(save.savedAt),
                    sessionStart = unixSeconds(meta.sessionStart),
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
      local scopeKey, slotId, created
      if mode == "new" then
        save.meta = type(save.meta) == "table" and save.meta or {}
        save.meta.playthroughId = SaveData.newPlaythroughId()
      else
        scopeKey, slotId = slotForPlaythrough(options, version, playthroughId)
      end
      if not slotId then
        local cartId = blobCart(save)
        if cartId then
          if not cartInstalled(options, cartId) then
            return false, ("install the \"%s\" cart to receive its save")
              :format(cartId)
          end
          scopeKey = CART_PREFIX .. cartId
        else
          scopeKey = version
        end
      end
      local cart = cartOfScope(scopeKey)
      if not slotId then
        if cart then
          slotId = SaveData.createCartSlot(cart)
        else
          slotId = SaveData.createSlot(version)
        end
        if not slotId then return nil, "could not make a save slot" end
        created = true
      end
      local ok, err
      if cart then
        ok, err = SaveData.writeCartSlot(cart, slotId, save)
      else
        ok, err = SaveData.writeSlot(version, slotId, save)
      end
      if not ok then return nil, err or "could not write the save" end
      options = SaveData.loadOptions()
      options.playthroughIds = options.playthroughIds or {}
      options.playthroughIds[scopeKey] = options.playthroughIds[scopeKey] or {}
      options.playthroughIds[scopeKey][slotId] =
        save.meta and save.meta.playthroughId or playthroughId
      SaveData.saveOptions(options)
      return slotId, created == true, cart
    end,
  }
end

function SyncEngine.overlaps(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  local aStart, aEnd = unixSeconds(a.sessionStart), unixSeconds(a.savedAt)
  local bStart, bEnd = unixSeconds(b.sessionStart), unixSeconds(b.savedAt)
  if not (aStart and aEnd and bStart and bEnd) then return false end
  return aStart <= bEnd and bStart <= aEnd
end

-- Inline, under .meta, or under .remoteMeta, depending on the endpoint.
function SyncEngine.metaOf(row)
  if type(row) ~= "table" then return nil end
  if type(row.meta) == "table" then return row.meta end
  if type(row.remoteMeta) == "table" then return row.remoteMeta end
  return row
end

-- Gen 2 stores playTime as a table, so meta.playTime is nil on a Gold save
-- and summary.timeText is the only field that survives.
local function playedMinutes(meta)
  if type(meta) ~= "table" then return nil end
  local summary = type(meta.summary) == "table" and meta.summary or nil
  local text = summary and summary.timeText
  if type(text) == "string" then
    local hours, minutes = text:match("^(%d+):(%d%d)$")
    if hours then return tonumber(hours) * 60 + tonumber(minutes) end
  end
  local seconds = tonumber(meta.playTime)
  if seconds and seconds > 0 then return math.floor(seconds / 60) end
  return nil
end

-- Same minute of playtime means the same point in the playthrough, so there
-- is no fork.  Unknown playtime on either side is NOT a match.
function SyncEngine.samePlaytime(a, b)
  local left, right = playedMinutes(a), playedMinutes(b)
  return left ~= nil and left == right
end

function SyncEngine.sameProgress(a, b)
  if SyncEngine.samePlaytime(a, b) then return true end
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  local left = type(a.summary) == "table" and a.summary or nil
  local right = type(b.summary) == "table" and b.summary or nil
  if not (left and right) then return false end
  if type(left.name) ~= "string" or left.name == "" then return false end
  return left.name == right.name and left.badges == right.badges
    and left.timeText == right.timeText and left.dexCount == right.dexCount
end

function SyncEngine.displayMeta(meta)
  if type(meta) ~= "table" then return meta end
  local out = {}
  for k, v in pairs(meta) do out[k] = v end
  out.savedAt = unixSeconds(meta.savedAt)
  out.sessionStart = unixSeconds(meta.sessionStart)
  return out
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
  eng.codes = SyncEngine.formatCodes(eng.state)
  eng.modPlan = nil
  eng.shareCode = nil
  eng.clock = 0
  eng.autoAt = SyncEngine.AUTO_INTERVAL
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
  if type(self.skipped) == "table" and #self.skipped > 0 then
    self.status = self.skipped[1]
  end
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

function SyncEngine:noteSaveDeleted(key)
  if type(key) ~= "string" or key == "" then return false end
  local rev = SyncState.rev(self.state, key)
  SyncState.forget(self.state, key)
  if rev == nil or not self:linked() then
    self:_persist()
    return false
  end
  SyncState.markDeleted(self.state, key, rev, self.now())
  self:_persist()
  if self.state.enabled then
    self.uploadAt = self.clock + SyncEngine.UPLOAD_DEBOUNCE
  end
  return true
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
  if self.clock >= self.autoAt and not self:busy()
      and (self.phase == "idle" or self.phase == "error")
      and self.state.enabled and self:linked() then
    self:syncNow()
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

function SyncEngine.formatCodes(state)
  if type(state) ~= "table" then return nil end
  local a = SyncClient.formatCode(state.code1)
  local b = SyncClient.formatCode(state.code2)
  if not a or not b then return nil end
  return { code1 = a, code2 = b }
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
    eng.state.code1 = SyncClient.normalizeCode(data.code1)
    eng.state.code2 = SyncClient.normalizeCode(data.code2)
    eng.codes = SyncEngine.formatCodes(eng.state) or {
      code1 = tostring(data.code1 or ""),
      code2 = tostring(data.code2 or ""),
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
    eng:syncNow()
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
    eng.state.code1, eng.state.code2 = a, b
    eng.codes = SyncEngine.formatCodes(eng.state)
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
  if self:busy() then self:cancel() end
  self.phase = "checking"
  self.status = "Unlinking this device..."
  self.error = nil
  local handle, err = self.client:unlink(self.state.deviceId)
  if not handle then
    self:_forgetLocal()
    return true
  end
  return self:_request(handle, err, function(eng)
    eng:_forgetLocal()
  end, function(eng)
    eng:_forgetLocal()
    return true
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

function SyncEngine:reissueCodes()
  if not self:linked() then return false, "this device is not linked" end
  if self:busy() then return false, "sync is busy" end
  self.phase = "checking"
  self.status = "Fetching new sync codes..."
  self.error = nil
  local handle, err = self.client:reissueCodes()
  return self:_request(handle, err, function(eng, res)
    local data = res.data or {}
    local a = SyncClient.normalizeCode(data.code1)
    local b = SyncClient.normalizeCode(data.code2)
    if not a or not b then
      eng:_fail("the server sent an unexpected reply")
      return
    end
    eng.state.code1, eng.state.code2 = a, b
    eng.codes = SyncEngine.formatCodes(eng.state)
    eng.phase = "idle"
    eng.status = "New sync codes issued, the old pair no longer links"
    eng:_persist()
  end)
end

function SyncEngine:setEnabled(enabled)
  self.state.enabled = enabled and true or false
  self:_persist()
  return self.state.enabled
end

function SyncEngine:protectPlaythrough(version, playthroughId)
  self.protectedKey = SyncState.key(version, playthroughId)
end

function SyncEngine:noteResumed()
  if not (self.state.enabled and self:linked()) then return end
  if self:busy() or self.phase == "conflict" then return end
  if self.now() - (tonumber(self.state.lastSyncAt) or 0)
      < SyncEngine.RESUME_MIN_GAP then
    return
  end
  self:syncNow()
end

function SyncEngine:syncNow()
  if not self:linked() then return false, "this device is not linked" end
  if self.pending then return false, "sync is busy" end
  self.autoAt = self.clock + SyncEngine.AUTO_INTERVAL
  self.queue = {}
  self.conflicts = {}
  self.skipped = nil
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
  local tombs = type(remoteState.deleted) == "table" and remoteState.deleted or {}
  local locals = self.saves.list() or {}
  local seen = {}
  for _, entry in ipairs(locals) do
    local key = SyncState.key(entry.version, entry.playthroughId)
    if key then
      seen[key] = true
      SyncState.clearDeleted(self.state, key)
      local row = remote[key]
      local knownRev = SyncState.rev(self.state, key)
      local stamp = unixSeconds(SyncState.stamp(self.state, key))
      local liveStamp = unixSeconds(entry.meta and entry.meta.savedAt)
      local localChanged
      if liveStamp == nil and stamp == nil then
        localChanged = knownRev == nil
      else
        localChanged = liveStamp ~= stamp
      end
      local remoteRev = row and tonumber(row.rev)
      local remoteChanged = row ~= nil and remoteRev ~= knownRev
      local tomb = not row and type(tombs[key]) == "table" and tombs[key] or nil
      local buried = tomb ~= nil and knownRev ~= nil
        and (tonumber(tomb.rev) or 0) >= knownRev
        and not (localChanged and liveStamp
          and liveStamp > (unixSeconds(tomb.deletedAt) or 0))
      if buried then
        self:_removeLocal(entry, key, tomb)
      elseif not row then
        self:_queueUpload(entry, key, false)
      elseif localChanged and remoteChanged then
        if SyncEngine.sameProgress(entry.meta, SyncEngine.metaOf(row)) then
          self:_queueUpload(entry, key, true)
        else
          self:_addConflict(entry, key, row)
        end
      elseif localChanged then
        self:_queueUpload(entry, key, false)
      elseif remoteChanged and key ~= self.protectedKey then
        self:_queueDownload(key, entry.version, entry.playthroughId, "replace")
      end
    end
  end
  for key, pending in pairs(self.state.pendingDeletes or {}) do
    local row = remote[key]
    if not seen[key] then
      if row and (tonumber(row.rev) or 0) > (tonumber(pending.rev) or 0) then
        SyncState.clearDeleted(self.state, key)
      else
        seen[key] = true
        self:_queueDelete(key, pending.rev)
      end
    end
  end
  for key, row in pairs(remote) do
    if not seen[key] and key ~= self.protectedKey then
      local version, id = SyncState.splitKey(key)
      if version and id then
        self:_queueDownload(key, version, id, "replace", tonumber(row.rev))
      end
    end
  end
  if #self.queue == 0 then self:_finish() end
end

function SyncEngine:_removeLocal(entry, key, tomb)
  if key == self.protectedKey then return end
  local slotId, cartId
  if type(self.saves.remove) == "function" then
    slotId, cartId = self.saves.remove(entry.version, entry.playthroughId)
  end
  SyncState.forget(self.state, key)
  if slotId then
    self.lastDownloads = self.lastDownloads or {}
    self.lastDownloads[#self.lastDownloads + 1] = {
      version = entry.version,
      cart = cartId or entry.cart,
      slot = slotId,
      removed = true,
      device = type(tomb.device) == "string" and tomb.device ~= ""
        and tomb.device or nil,
    }
    self.changed = true
  end
end

function SyncEngine:_queueDelete(key, rev)
  self:_enqueue(function(eng)
    eng.phase = "uploading"
    eng.status = "Removing deleted saves..."
    local version, id = SyncState.splitKey(key)
    local handle, err = eng.client:deleteSave(version, id, rev)
    eng:_request(handle, err, function(e)
      SyncState.clearDeleted(e.state, key)
      SyncState.forget(e.state, key)
      e:_persist()
      if not e:busy() then e:_finish() end
    end)
  end)
end

function SyncEngine:_addConflict(entry, key, row)
  local remoteMeta = SyncEngine.displayMeta(SyncEngine.metaOf(row))
  self.conflicts[#self.conflicts + 1] = {
    key = key,
    version = entry.version,
    playthroughId = entry.playthroughId,
    slot = entry.slot,
    entry = entry,
    localMeta = SyncEngine.displayMeta(entry.meta),
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
        unixSeconds(entry.meta and entry.meta.savedAt))
      e:_persist()
      if not e:busy() then e:_finish() end
    end, function(e, res)
      if res.code == 409 then
        local row = res.data or {}
        -- Retried with force only once: a forced write that still 409s is a
        -- real refusal, and retrying it would spin.
        if not force
            and SyncEngine.sameProgress(entry.meta, SyncEngine.metaOf(row)) then
          e:_queueUpload(entry, key, true)
        else
          e:_addConflict(entry, key, row)
        end
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
      local slotId, detail, cartId =
        e.saves.write(version, playthroughId, data.blob, mode)
      if slotId == false then
        e.skipped = e.skipped or {}
        e.skipped[#e.skipped + 1] =
          tostring(detail or "this save was skipped")
        if not e:busy() then e:_finish() end
        return
      end
      if not slotId then
        e:_fail(detail or "could not write the downloaded save")
        return
      end
      local created = detail == true
      local meta = type(data.meta) == "table" and data.meta or {}
      if mode ~= "new" then
        SyncState.setRev(e.state, key, tonumber(data.rev) or knownRev,
          unixSeconds(meta.savedAt))
      end
      e.lastDownloads = e.lastDownloads or {}
      e.lastDownloads[#e.lastDownloads + 1] = {
        version = version,
        cart = cartId,
        slot = slotId,
        created = created,
        device = type(meta.device) == "string" and meta.device ~= ""
          and meta.device or nil,
      }
      e.changed = true
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

function SyncEngine:uploadMods(includeOptions)
  if not self:linked() then return false, "this device is not linked" end
  if self:busy() then return false, "sync is busy" end
  local manifest = SyncMods.build(self.modDeps, includeOptions)
  self.phase = "uploading"
  self.status = includeOptions and "Uploading the mod list and options..."
    or "Uploading the mod list..."
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
    eng:_takeModPlan(SyncMods.plan(manifest, eng.modDeps))
  end)
end

function SyncEngine:shareMods(includeOptions)
  if not self:linked() then return false, "this device is not linked" end
  if self:busy() then return false, "sync is busy" end
  local manifest = SyncMods.build(self.modDeps, includeOptions)
  self.phase = "uploading"
  self.status = includeOptions and "Sharing the mod list and options..."
    or "Sharing the mod list..."
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
    eng:_takeModPlan(SyncMods.plan(manifest, eng.modDeps))
  end)
end

function SyncEngine:_takeModPlan(plan)
  self.modPlan = plan
  self.phase = "idle"
  if SyncMods.planHasOptions(plan) then
    self.status = ("This list carries options for %d mods.")
      :format(#plan.options)
  elseif SyncMods.planEmpty(plan) then
    self.status = "Mods already match"
  else
    self.status = "Mod changes ready to apply"
  end
end

function SyncEngine:modOptionsAsk()
  local plan = self.modPlan
  if not SyncMods.planHasOptions(plan) then return nil end
  if plan.applyOptions ~= nil then return nil end
  return SyncMods.optionModIds(plan)
end

function SyncEngine:answerModOptions(importThem)
  local plan = self.modPlan
  if not SyncMods.planHasOptions(plan) then return false end
  SyncMods.answerOptions(plan, importThem)
  self.status = plan.applyOptions
    and "Their mod options will be imported too"
    or "Their mod options will be skipped"
  return plan.applyOptions
end

function SyncEngine:applyModPlan(progress)
  if not self.modPlan then return false, "no mod plan" end
  if self.modApply then return false, "the mods are already being applied" end
  self.modPlan.applyOptions = self.modPlan.applyOptions == true
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
