local SyncClient = require("src.sync.SyncClient")
local SyncState = require("src.sync.SyncState")
local SyncMods = require("src.sync.SyncMods")
local SyncBox = require("src.sync.SyncBox")
local Work = require("src.sync.SyncWork")

local SyncEngine = {}
SyncEngine.__index = SyncEngine

SyncEngine.UPLOAD_DEBOUNCE = 5
SyncEngine.AUTO_INTERVAL = 300
SyncEngine.RESUME_MIN_GAP = 60
SyncEngine.MAX_STEPS_PER_UPDATE = 8

local IDLE_STATUS = "Ready"
local UNLINKED_STATUS = "Not set up"

SyncEngine.ERROR_TEXT = {
  unauthorized = "This device's sync account no longer exists on the server, or this device was unlinked. Link again with current codes or create a new sync account.",
  bad_code = "Those codes do not match a sync account. They may have been replaced on another device, or that account no longer exists.",
  too_many_devices = "That sync account already has as many devices as it can hold. Unlink one first.",
  rate_limited = "Too many tries for now. Wait a while and try again.",
  busy = "The sync server is busy. Try again in a minute.",
  server_error = "The sync server hit an error. Try again later.",
  storage_full = "This sync account is out of space. Delete some saves and try again.",
  too_many_saves = "This sync account holds as many saves as it can. Delete some and try again.",
  blob_too_large = "This save is too large to sync.",
  too_large = "That upload is too large for the sync server.",
  bad_display_name = "Display names are 3 to 16 characters.",
  already_linked = "This device is already linked. Unlink it first, then link with the new codes.",
}

function SyncEngine.describeError(err)
  local text = tostring(err or "sync failed")
  return SyncEngine.ERROR_TEXT[text] or text
end

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
    if id == playthroughId and tostring(slotId):match("^slot%d+$") then return version, slotId end
  end
  local bestKey, bestSlot
  for key, byScope in pairs(root) do
    if key ~= version and cartOfScope(key) and type(byScope) == "table" then
      for slotId, id in pairs(byScope) do
        if id == playthroughId and tostring(slotId):match("^slot%d+$")
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
                    -- Derive from the saved set, including older saves that
                    -- predate modCount, rather than this device's current mods.
                    modCount = #(type(meta.mods) == "table" and meta.mods or {}),
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

function SyncEngine.samePlaytime(a, b)
  local left, right = playedMinutes(a), playedMinutes(b)
  return left ~= nil and left == right
end

local function snapshot(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then return seen[value] end
  local out = {}; seen[value] = out
  for k, v in pairs(value) do out[k] = snapshot(v, seen) end
  return out
end

local function contents(blob, decoded)
  if type(blob) ~= "string" or blob == "" or #blob > SyncClient.MAX_BLOB then return nil end
  local ok, save = true, decoded
  if save == nil then ok, save = pcall(saveApi().decode, blob) end
  if not ok or type(save) ~= "table"
      or (save.meta ~= nil and type(save.meta) ~= "table") then return nil end
  local native = save.engine == "game3" and save.generation == 3
    and type(save.name) == "string" and type(save.party) == "table" and type(save.bag) == "table"
  if type(save.player) ~= "table" and not native then return nil end
  save.savedAt = nil
  if save.meta then save.meta.savedAt, save.meta.sessionStart = nil, nil end
  return save
end

local function equalValues(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do if not equalValues(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

local function sameContents(a, b)
  local decoded = {}
  for i, blob in ipairs({ a, b }) do
    decoded[i] = type(blob) == "string" and blob ~= "" and #blob <= SyncClient.MAX_BLOB
      and Work.call("decode", blob) or nil
  end
  local left, right = contents(a, decoded[1]), contents(b, decoded[2])
  return left ~= nil and right ~= nil and equalValues(left, right)
end

local function revision(value)
  local n = tonumber(value)
  if not n or n ~= n or n <= 0 or n == math.huge or n % 1 ~= 0 then return nil end
  return n
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
  if opts.box ~= nil then eng.box = opts.box
  elseif not opts.saves then eng.box = SyncBox.new(eng.fs) end
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
  return self.pending ~= nil or #self.queue > 0 or self.modApply ~= nil or self.working ~= nil
end

function SyncEngine:_step(rec)
  self.working = nil
  local ok, err = coroutine.resume(rec.co, self, rec.arg)
  if coroutine.status(rec.co) == "suspended" then
    self.working = rec
    return false
  end
  Work.abandon(rec.co)
  return true, ok, err
end

function SyncEngine:_run(fn, arg, task)
  return self:_step({ co = Work.spawn(fn), arg = arg, task = task })
end

function SyncEngine:_settle(rec, ok, err)
  if not ok then self:_fail(err) return false end
  if rec.task and not self.pending and not self.working and #self.queue == 0 and self.phase ~= "error" then
    self:_finish()
  end
  return true
end

function SyncEngine:_noteRecovery(notice)
  notice = notice or (self.box and self.box.recoveryNotice)
  if self.box then self.box.recoveryNotice = nil end
  if type(notice) == "string" and notice ~= "" then self.notice = notice end
end

function SyncEngine:takeNotice()
  local notice = self.shownNotice
  self.shownNotice = nil
  return notice
end

function SyncEngine:_persist()
  if not self.persist then return end
  SyncState.save(self.state, self.fs)
end

function SyncEngine:_fail(message)
  if self.working then
    Work.abandon(self.working.co)
    self.working = nil
  end
  self.phase = "error"
  self.error = tostring(message or "sync failed")
  self.status = "Sync failed: " .. SyncEngine.describeError(self.error)
  self.queue = {}
  self.pending = nil
end

function SyncEngine.lostLink(res)
  return type(res) == "table" and tonumber(res.code) == 401 and res.err == "unauthorized"
end

function SyncEngine:_lostLink()
  self:_fail("unauthorized")
  if not self.lostLinkAt then
    self.lostLinkAt = self.clock
    self.autoAt = self.clock + SyncEngine.AUTO_INTERVAL
    return
  end
  if self.clock - self.lostLinkAt < SyncEngine.AUTO_INTERVAL then return end
  self.lostLinkAt = nil
  self.uploadAt = nil
  self.modApply = nil
  local code1, code2 = self.state.code1, self.state.code2
  self:_forgetLocal()
  self.state.code1, self.state.code2 = code1, code2
  self.codes = SyncEngine.formatCodes(self.state)
  self:_persist()
  self.phase = "error"
  self.error = "unauthorized"
  self.status = SyncEngine.describeError("unauthorized")
end

function SyncEngine:_finish()
  if #self.conflicts > 0 then
    self.phase = "conflict"
    local overlap = false
    for _, row in ipairs(self.conflicts) do
      if row.overlap then overlap = true end
    end
    self.status = self.conflicts[1].box and "Box and its linked saves changed on another device." or overlap
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
  if self.notice then
    self.status, self.shownNotice, self.notice = self.notice, self.notice, nil
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
  if self.working then Work.abandon(self.working.co) end
  self.working = nil
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
  if self.box then
    local ok, why = self.box:markDeleted(key)
    if not ok then
      local known = SyncState.rev(self.state, key)
      SyncState.forget(self.state, key)
      if known ~= nil or self.box:owns(key) ~= false then SyncState.markDeleted(self.state, key, known or 0, self.now()) end
      self:_persist()
      self:_fail(why)
      if self.state.enabled and self:linked() then self.uploadAt = self.clock + SyncEngine.UPLOAD_DEBOUNCE end
      return nil, why
    end
  end
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
  if self.working then
    local rec = self.working
    local done, ok, err = self:_step(rec)
    if not done then return end
    if not self:_settle(rec, ok, err) then return end
  end
  if self.pending then
    local res = self.client:poll(self.pending.handle)
    if res.status == "pending" then return end
    local job = self.pending
    self.pending = nil
    self.client:release(job.handle)
    if res.status == "ok" then
      self.lostLinkAt = nil
      local done, ok, err = self:_run(job.onOk, res)
      if done and not ok then self:_fail(err) end
    elseif SyncEngine.lostLink(res) and self:linked() and not job.unlinking then
      self:_lostLink()
      return
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
  if self.pending or self.working then return end
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
  while not self.pending and not self.working and #self.queue > 0
      and steps < SyncEngine.MAX_STEPS_PER_UPDATE do
    steps = steps + 1
    local task = table.remove(self.queue, 1)
    local done, ok, err = self:_run(task, nil, true)
    if done and not self:_settle({ task = true }, ok, err) then return end
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
  if self:linked() then
    if a == self.state.code1 and b == self.state.code2 then
      self.phase, self.error = "idle", nil
      self.status = "This device is already linked to that sync account."
      return false, "already linked"
    end
    self:_fail("already_linked")
    return false, "already linked"
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
  self.lostLinkAt = nil
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
  local started = self:_request(handle, err, function(eng)
    eng:_forgetLocal()
  end, function(eng)
    eng:_forgetLocal()
    return true
  end)
  if started then self.pending.unlinking = true end
  return started
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
  local previous = self.protectedKey
  self.protectedKey = SyncState.key(version, playthroughId)
  if previous and not self.protectedKey and self.box and self._boxKeys and self._boxKeys[previous]
      and self.state.enabled and self:linked() then self.uploadAt = self.clock end
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
  if self.pending or self.working then return false, "sync is busy" end
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
  if self.box then
    local recovered, recoveryError, notice = self.box:recover()
    self:_noteRecovery(notice)
    if not recovered then self:_fail(recoveryError); return end
  end
  local locals = self.saves.list() or {}
  self._boxKeys, self._boxSaveRevs = {}, {}
  if self.box and not self:_planBox(remoteState, locals) then return end
  local seen = {}
  for _, entry in ipairs(locals) do
    local key = SyncState.key(entry.version, entry.playthroughId)
    if key and not self._boxKeys[key] then
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
        self:_queueComparison(entry, key, row)
      elseif localChanged then
        self:_queueUpload(entry, key, false)
      elseif remoteChanged and key ~= self.protectedKey then
        self:_queueDownload(key, entry.version, entry.playthroughId, "replace")
      end
    end
  end
  for key, pending in pairs(self.state.pendingDeletes or {}) do
    local row = remote[key]
    if not seen[key] and not self._boxKeys[key] then
      if row and (tonumber(row.rev) or 0) > (tonumber(pending.rev) or 0) then
        SyncState.clearDeleted(self.state, key)
      else
        seen[key] = true
        self:_queueDelete(key, pending.rev)
      end
    end
  end
  for key, row in pairs(remote) do
    if not seen[key] and not self._boxKeys[key] and key ~= self.protectedKey then
      local version, id = SyncState.splitKey(key)
      if version and id then
        self:_queueDownload(key, version, id, "replace", tonumber(row.rev))
      end
    end
  end
  if #self.queue == 0 then self:_finish() end
end

function SyncEngine:_planBox(remoteState, locals)
  local remote = type(remoteState.box) == "table" and remoteState.box or nil
  local extra = {}
  for _, key in ipairs(remote and remote.members or {}) do extra[key] = true end
  local current, why = self.box:snapshot(locals, self.state, extra)
  if not current then self:_fail(why); return false end
  if not current.exists and not remote then return true end
  if not (remoteState.capabilities and remoteState.capabilities.box == 1) then
    self:_fail("The sync server needs its Box update before this collection can sync.")
    return false
  end
  self._boxKeys = current.keys
  local remoteSaves, tombs = remoteState.saves or {}, remoteState.deleted or {}
  local saveChanged = false
  for key in pairs(self._boxKeys) do
    local row = remoteSaves[key] or tombs[key]
    self._boxSaveRevs[key] = row and tonumber(row.rev) or 0
    local known = self.state.pendingDeletes and self.state.pendingDeletes[key]
    known = known and known.rev or SyncState.rev(self.state, key)
    if row and self._boxSaveRevs[key] ~= known then saveChanged = true end
  end
  local changed = current.fingerprint ~= self.state.boxFingerprint
  local remoteRev = remote and tonumber(remote.rev) or 0
  local remoteChanged = remoteRev ~= (self.state.boxRev or 0) or saveChanged
  if remote and not current.exists then
    local dirty = false
    for _, entry in ipairs(locals) do
      local key = SyncState.key(entry.version, entry.playthroughId)
      if self._boxKeys[key] then
        dirty = dirty or SyncState.rev(self.state, key) == nil
          or unixSeconds(entry.meta and entry.meta.savedAt) ~= unixSeconds(SyncState.stamp(self.state, key))
      end
    end
    if dirty then self:_queueBoxComparison(current, remoteRev)
    else self:_queueBoxDownload(current.fingerprint) end
  elseif not remote and saveChanged then self:_queueBoxComparison(current, 0)
  elseif not remote then self:_queueBoxUpload(current)
  elseif changed and remoteChanged then self:_queueBoxComparison(current, remoteRev)
  elseif changed then self:_queueBoxUpload(current)
  elseif remoteChanged then self:_queueBoxDownload(current.fingerprint) end
  return true
end

function SyncEngine:_addBoxConflict(current, remote)
  self.conflicts[#self.conflicts + 1] = { box = true, key = SyncBox.KEY, version = "Box collection",
    entry = current, remote = remote, remoteRev = remote.rev,
    localMeta = { summary = { name = "Box", boxCount = current.payload.meta.count }, savedAt = unixSeconds(current.payload.meta.savedAt) },
    remoteMeta = { summary = { name = "Box", boxCount = remote.meta and remote.meta.count }, savedAt = unixSeconds(remote.meta and remote.meta.savedAt) },
    overlap = false }
  self.state.pendingConflicts[#self.state.pendingConflicts + 1] = { key = SyncBox.KEY, version = "Box collection" }
end

function SyncEngine:_queueBoxComparison(current, observedRev)
  self:_enqueue(function(eng)
    eng.phase, eng.status = "checking", "Checking Box and linked saves..."
    local handle, err = eng.client:getBox(eng._boxKeys)
    eng:_request(handle, err, function(e, res)
      local remote = res.data
      local valid, why = SyncBox.validate(remote)
      if not valid then e:_fail(why); return end
      if type(remote.rev) ~= "number" or remote.rev < observedRev then e:_fail("The cloud Box revision is stale."); return end
      if not next(current.missing) and SyncBox.fingerprint(remote) == current.fingerprint then
        local remembered, detail = e.box:remember(remote, e.saves.list(), e.state)
        if not remembered then e:_fail(detail); return end
        e:_acceptBox(remote.rev, remote.saves, current.fingerprint)
      else e:_addBoxConflict(current, remote) end
      if not e:busy() then e:_finish() end
    end)
  end)
end

function SyncEngine:_acceptBox(rev, rows, fingerprint)
  self.state.boxRev, self.state.boxFingerprint = rev, fingerprint
  for key, row in pairs(rows or {}) do
    SyncState.setRev(self.state, key, row.rev, unixSeconds(row.meta and row.meta.savedAt))
    SyncState.clearDeleted(self.state, key)
  end
  self:_persist()
end

function SyncEngine:_queueBoxUpload(planned, expectedRev, remote)
  self:_enqueue(function(eng)
    if eng.protectedKey and eng._boxKeys[eng.protectedKey] then
      eng.skipped = { "Box sync will finish after you return to the launcher." }; return
    end
    local current, why = eng.box:snapshot(eng.saves.list(), eng.state, eng._boxKeys)
    if not current then eng:_fail(why); return end
    if next(current.missing) then eng:_fail("A save linked to Box is missing. Receive the cloud collection before uploading."); return end
    for key in pairs(current.keys) do
      if not planned.keys[key] then eng:_fail("Box gained a linked save during sync. Sync again."); return end
    end
    local carried = {}
    for key in pairs(current.remoteOnly or {}) do
      local row = remote and type(remote.saves) == "table" and remote.saves[key]
      if type(row) ~= "table" then eng:_fail("Box gained a linked save on another device. Sync again."); return end
      carried[key] = row.deleted and { version = row.version, deleted = true }
        or { version = row.version, blob = row.blob, meta = row.meta }
    end
    if remote then
      local backup, backupError = eng.box:archive(remote)
      if not backup then eng:_fail(backupError); return end
    end
    local payload = current.payload
    for key, row in pairs(carried) do payload.saves[key] = row end
    payload.baseRev = expectedRev or eng.state.boxRev or 0
    for key, row in pairs(payload.saves) do
      row.baseRev = remote and remote.saves[key] and remote.saves[key].rev or eng._boxSaveRevs[key] or 0
    end
    eng.phase, eng.status = "uploading", "Uploading Box and linked saves..."
    local handle, err = eng.client:putBox(payload)
    eng:_request(handle, err, function(e, res)
      if not revision(res.data.rev) then e:_fail("The server did not confirm the Box revision."); return end
      local rows = {}
      for key, row in pairs(payload.saves) do
        local rev = res.data.revs and revision(res.data.revs[key])
        if not rev then e:_fail("The server did not confirm every linked save."); return end
        if not carried[key] then rows[key] = { rev = rev, meta = row.meta } end
      end
      local remembered, detail = e.box:remember(payload, e.saves.list(), e.state)
      if not remembered then e:_fail(detail); return end
      if detail == true then
        e.changed = true; e.lastDownloads = e.lastDownloads or {}
        e.lastDownloads[#e.lastDownloads + 1] = { box = true }
      end
      e:_acceptBox(res.data.rev, rows, current.fingerprint)
      if next(carried) and e.state.enabled then e.uploadAt = e.clock end
      if not e:busy() then e:_finish() end
    end, function(e, res)
      if res.code == 409 then
        e:_queueBoxComparison(current, tonumber(res.data and res.data.rev) or 0)
        return true
      end
      return false
    end)
  end)
end

function SyncEngine:_queueBoxDownload(expected, supplied)
  self:_enqueue(function(eng)
    if eng.protectedKey and eng._boxKeys[eng.protectedKey] then
      eng.skipped = { "Box sync will finish after you return to the launcher." }; return
    end
    local function apply(e, remote)
      local locals = e.saves.list()
      local downloads, why = e.box:apply(remote, locals, e.state, expected)
      if downloads == false then e.skipped = { why }; return end
      if not downloads then e:_fail(why); return end
      local current, err = e.box:snapshot(e.saves.list(), e.state)
      if not current then e:_fail(err); return end
      e.lastDownloads = e.lastDownloads or {}
      for _, row in ipairs(downloads) do e.lastDownloads[#e.lastDownloads + 1] = row end
      e.changed = true
      e:_acceptBox(remote.rev, remote.saves, current.fingerprint)
      if not e:busy() then e:_finish() end
    end
    eng.phase, eng.status = "downloading", "Downloading Box and linked saves..."
    local handle, err = eng.client:getBox(eng._boxKeys)
    eng:_request(handle, err, function(e, res)
      local remote = res.data
      if supplied then
        local same = remote.rev == supplied.rev
        for key, row in pairs(supplied.saves) do same = same and remote.saves and remote.saves[key] and remote.saves[key].rev == row.rev end
        if not same then
          local current, why = e.box:snapshot(e.saves.list(), e.state, e._boxKeys)
          if not current then e:_fail(why); return end
          e:_queueBoxComparison(current, remote.rev or 0); return
        end
      end
      apply(e, remote)
    end)
  end)
end

function SyncEngine:restoreBoxBackup(path)
  if not self.box then return nil, "Box storage is unavailable." end
  if self:busy() or #self.conflicts > 0 then return nil, "Finish the current sync before restoring Box." end
  local recovered, recoveryError, notice = self.box:recover()
  self:_noteRecovery(notice)
  if not recovered then return nil, recoveryError end
  local snapshot, backup = self.box:readBackup(path)
  if not snapshot then return nil, backup end
  local entries = self.saves.list()
  local current, err = self.box:snapshot(entries, self.state, snapshot.saves)
  if not current then return nil, err end
  local backupState = backup.state
  for key in pairs(current.keys) do
    local row, member = snapshot.saves[key], backupState.syncMembers and backupState.syncMembers[key]
    if not row or row.deleted and not (member and member.deleted) then
      return nil, "This backup predates another linked save. Restore a newer complete collection."
    end
  end
  for key in pairs(self._boxKeys or {}) do
    if not snapshot.saves[key] then return nil, "This backup predates another linked save. Restore a newer complete collection." end
  end
  if self.protectedKey and current.keys[self.protectedKey] then
    return nil, "Return to the launcher before restoring Box and its linked saves."
  end
  local downloads, failure = self.box:apply(snapshot, entries, self.state, current.fingerprint)
  if not downloads then return nil, failure end
  self.changed, self.lastDownloads = true, downloads
  self:noteSaveWritten()
  self.status = "Box and its linked saves were restored."
  if self.notice then
    self.status = self.notice .. " " .. self.status
    self.shownNotice, self.notice = self.notice, nil
  end
  return true
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

function SyncEngine:_newBoxMember(key)
  if not self.box or self._boxKeys and self._boxKeys[key] then return false end
  local owned, why = self.box:owns(key)
  if owned == nil or owned then
    self:_fail(why or "Box gained a linked save during sync. Checking the collection again.")
    if owned and self.state.enabled then self.uploadAt = self.clock end
    return true
  end
  return false
end

function SyncEngine:_queueDelete(key, rev)
  self:_enqueue(function(eng)
    if eng:_newBoxMember(key) then return end
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

function SyncEngine:_queueComparison(entry, key, row)
  entry, row = snapshot(entry), snapshot(row)
  self:_enqueue(function(eng)
    if eng:_newBoxMember(key) then return end
    eng.phase = "checking"
    eng.status = "Checking save contents..."
    local function conflict(e, data)
      data = type(data) == "table" and data or {}
      local meta = snapshot(SyncEngine.metaOf(row) or {})
      local fetchedMeta = type(data.meta) == "table" and data.meta
        or type(data.remoteMeta) == "table" and data.remoteMeta or {}
      for k, v in pairs(fetchedMeta) do meta[k] = v end
      e:_addConflict(entry, key, {
        rev = revision(data.rev) or row.rev,
        meta = meta,
      })
      if not e:busy() then e:_finish() end
    end
    local handle, err = eng.client:getSave(entry.version, entry.playthroughId)
    if not handle then conflict(eng) return end
    eng:_request(handle, err, function(e, res)
      local data = type(res.data) == "table" and res.data or {}
      if e:_newBoxMember(key) then return end
      local fetched, observed = revision(data.rev), revision(row.rev)
      if fetched and observed and fetched >= observed
          and sameContents(entry.blob, data.blob) then
        SyncState.setRev(e.state, key, fetched, unixSeconds(entry.meta and entry.meta.savedAt))
        e:_persist()
        if not e:busy() then e:_finish() end
      else conflict(e, data) end
    end, function(e, res)
      conflict(e, res.data)
      return true
    end)
  end)
end

function SyncEngine:_queueUpload(entry, key, force)
  entry = snapshot(entry)
  self:_enqueue(function(eng)
    if eng:_newBoxMember(key) then return end
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
        if not force then
          e:_queueComparison(entry, key, row)
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
    if eng:_newBoxMember(key) then return end
    eng.phase = "downloading"
    eng.status = "Downloading saves..."
    local handle, err = eng.client:getSave(version, playthroughId)
    eng:_request(handle, err, function(e, res)
      if e:_newBoxMember(key) then return end
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
  local proposed = self.conflicts[index]
  if not proposed.box and self:_newBoxMember(key) then return false, "This save is now linked to Box. Sync the complete collection." end
  if proposed.box and choice ~= "local" and choice ~= "remote" then return false, "Choose one complete Box collection and its linked saves." end
  local current
  if proposed.box then
    local why
    current, why = self.box:snapshot(self.saves.list(), self.state, self._boxKeys)
    if not current then return false, why end
    if current.fingerprint ~= proposed.entry.fingerprint then
      proposed.entry = current
      proposed.localMeta = { summary = { name = "Box", boxCount = current.payload.meta.count }, savedAt = unixSeconds(current.payload.meta.savedAt) }
      proposed.reviewMessage = "Box changed on this device. Review the updated collection before choosing. The other copy will be kept in a recovery backup."
      return false, proposed.reviewMessage
    end
  end
  local conflict = table.remove(self.conflicts, index)
  local kept = {}
  for _, row in ipairs(self.state.pendingConflicts or {}) do
    if row.key ~= key then kept[#kept + 1] = row end
  end
  self.state.pendingConflicts = kept

  if conflict.box then
    if choice == "local" then self:_queueBoxUpload(current, conflict.remoteRev, conflict.remote)
    else self:_queueBoxDownload(current.fingerprint, conflict.remote) end
  elseif choice == "local" then
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
