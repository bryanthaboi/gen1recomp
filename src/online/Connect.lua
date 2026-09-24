local Strings = require("src.core.Strings")

local Connect = {}

Connect.NAME_MIN = 3
Connect.NAME_MAX = 16

local BANNED = { [60] = true, [62] = true, [38] = true, [34] = true, [39] = true }

local S

local function blank()
  return {
    name = nil,
    ticket = nil, ticketState = "idle", ticketExpiresAt = nil,
    jobs = {},
    wanted = nil,
    err = nil,
    notice = nil,
    source = nil,
    relayAddress = nil,
  }
end

S = blank()

function Connect.reset()
  for _, job in pairs(S.jobs) do
    pcall(job.client.release, job.client, job.handle)
  end
  S = blank()
end

local function Client()
  return require("src.online.Client")
end

function Connect.sanitizeName(text)
  text = tostring(text or "")
  local out = {}
  for i = 1, #text do
    local b = text:byte(i)
    if b >= 32 and b <= 126 and not BANNED[b] then
      out[#out + 1] = string.char(b)
      if #out >= Connect.NAME_MAX then break end
    end
  end
  return (table.concat(out):gsub("^%s+", ""):gsub("%s+$", ""))
end

function Connect.nameValid(name)
  if type(name) ~= "string" then return false end
  local n = #name
  return n >= Connect.NAME_MIN and n <= Connect.NAME_MAX
    and name == Connect.sanitizeName(name)
end

function Connect.threeDigits(random)
  random = random or math.random
  return ("%03d"):format(random(0, 999))
end

function Connect.defaultName(trainerName, digits)
  local base = Connect.sanitizeName(trainerName)
  if base == "" then base = "PLAYER" end
  local suffix = "#" .. tostring(digits or "000")
  if #base + #suffix > Connect.NAME_MAX then
    base = base:sub(1, Connect.NAME_MAX - #suffix)
  end
  return base .. suffix
end

function Connect.storedName()
  local ok, SyncState = pcall(require, "src.sync.SyncState")
  if not ok then return nil end
  local loaded, state = pcall(SyncState.load)
  if not loaded or type(state) ~= "table" then return nil end
  return state.displayName
end

function Connect.persistName(name)
  local ok, SyncState = pcall(require, "src.sync.SyncState")
  if not ok then return false end
  return (pcall(SyncState.update, function(state) state.displayName = name end))
end

function Connect.linked()
  local ok, SyncState = pcall(require, "src.sync.SyncState")
  if not ok then return false end
  local loaded, state = pcall(SyncState.load)
  if not loaded then return false end
  return SyncState.linked(state) == true
end

function Connect.name()
  return S.name
end

function Connect.ensureName(trainerName, version)
  if S.name then return S.name end
  local stored = Connect.storedName()
  if Connect.nameValid(stored) then
    S.name = stored
    return S.name
  end
  if type(trainerName) == "function" then trainerName = trainerName(version) end
  S.name = Connect.defaultName(trainerName, Connect.threeDigits())
  Connect.persistName(S.name)
  return S.name
end

local function defaultSyncClient()
  local ok, SyncClient = pcall(require, "src.sync.SyncClient")
  if not ok then return nil end
  local made, client = pcall(SyncClient.new, {})
  if not made or type(client) ~= "table" then return nil end
  local loadedState, SyncState = pcall(require, "src.sync.SyncState")
  if loadedState then
    local got, state = pcall(SyncState.load)
    if got and type(state) == "table" then
      client:setAuth(state.account, state.deviceToken)
    end
  end
  return client
end

local function startJob(kind, begin, client)
  if S.jobs[kind] then return false, "busy" end
  client = client or defaultSyncClient()
  if not client then return false, "no network transport" end
  local ok, handle = pcall(begin, client)
  if not ok or handle == nil then return false, "no network transport" end
  S.jobs[kind] = { kind = kind, handle = handle, client = client }
  return true
end

Connect._startJob = startJob

function Connect.setName(text, opts)
  local name = Connect.sanitizeName(text)
  if not Connect.nameValid(name) then
    return false, Strings("Names are 3 to 16 characters.")
  end
  S.name = name
  Connect.persistName(name)
  if Connect.linked() then
    startJob("displayName", function(client)
      return client:setDisplayName(name)
    end, opts and opts.syncClient)
  end
  return true
end

local function doConnect(opts)
  opts = opts or {}
  S.wanted = nil
  local client = Client()
  local known, address = pcall(client.configure, {})
  if not known or address == nil then
    local Net = require("src.link.Net")
    pcall(client.configure,
      { relayAddress = opts.relayAddress or S.relayAddress or Net.defaultRelayAddress() })
  end
  local ok, err = client.connect({
    name = S.name,
    ticket = S.ticket,
    profiles = opts.profiles or {},
    presence = opts.presence,
  })
  if not ok then
    S.err = tostring(err or "the relay didn't answer")
  else
    S.err = nil
  end
  return ok, err
end

Connect.doConnect = doConnect

local LIVE = { online = true, connecting = true, reconnecting = true }

function Connect.start(opts)
  opts = opts or {}
  local client = Client()
  if opts.source then S.source = opts.source end
  if opts.relayAddress then S.relayAddress = opts.relayAddress end
  if LIVE[client.state()] then
    if opts.profiles and type(client.setProfiles) == "function" then
      pcall(client.setProfiles, opts.profiles)
    end
    if opts.presence and type(client.setPresence) == "function" then
      pcall(client.setPresence, opts.presence)
    end
    return true
  end
  S.err = nil
  Connect.ensureName(opts.trainerName, opts.version)
  if S.ticketState == "ok" and S.ticketExpiresAt
      and S.ticketExpiresAt <= os.time() * 1000 then
    S.ticket, S.ticketState, S.ticketExpiresAt = nil, "idle", nil
  end
  if Connect.linked() and S.ticketState ~= "ok"
      and S.ticketState ~= "unsupported" then
    S.wanted = opts
    if S.jobs.ticket then return true end
    S.ticketState = "pending"
    local name = S.name
    if startJob("ticket", function(sync)
      return sync:lobbyTicket(name)
    end, opts.syncClient) then
      return true
    end
    S.ticketState = "unsupported"
  end
  return doConnect(opts)
end

local function finished(job, res)
  if job.kind == "ticket" then
    if res.status == "ok" and type(res.data) == "table"
        and type(res.data.ticket) == "string" then
      S.ticket = res.data.ticket
      S.ticketExpiresAt = tonumber(res.data.expiresAt)
      S.ticketState = "ok"
    else
      S.ticket = nil
      S.ticketState = (res.code == 404) and "unsupported" or "failed"
      if res.code ~= 404 and res.err then
        S.notice = Strings("Sign-in didn't work: %s", tostring(res.err))
      end
    end
    if S.wanted then doConnect(S.wanted) end
  elseif job.kind == "displayName" then
    if res.status ~= "ok" and res.code ~= 404 then
      S.notice = Strings("The server kept your old name.")
    end
  end
end

function Connect.update(_dt)
  for kind, job in pairs(S.jobs) do
    local ok, res = pcall(job.client.poll, job.client, job.handle)
    if not ok then res = { status = "error", err = tostring(res) } end
    if type(res) ~= "table" then res = { status = "error" } end
    if res.status ~= "pending" then
      S.jobs[kind] = nil
      pcall(job.client.release, job.client, job.handle)
      finished(job, res)
    end
  end
end

function Connect.state()
  if S.jobs.ticket and S.wanted then return "ticket" end
  local state = Client().state()
  if LIVE[state] or state == "error" then return state end
  return "offline"
end

function Connect.busy()
  local state = Connect.state()
  return state == "ticket" or state == "connecting"
end

function Connect.upgradeText()
  local client = Client()
  if type(client.upgradeRequired) ~= "function" then return nil end
  local up = client.upgradeRequired()
  if not up then return nil end
  if type(up) == "table" and type(up.text) == "string" and up.text ~= "" then
    return up.text
  end
  return Strings("This build is too old for online play. Please update.")
end

function Connect.error()
  local up = Connect.upgradeText()
  if up then return up end
  if S.err then return S.err end
  local client = Client()
  if client.state() == "error" then
    local err = client.error()
    return err and tostring(err) or nil
  end
  return nil
end

function Connect.takeNotice()
  local notice = S.notice
  S.notice = nil
  return notice
end

function Connect.ticketState()
  return S.ticketState
end

function Connect.pending()
  return S.wanted ~= nil
end

function Connect.disconnect()
  S.wanted = nil
  S.err = nil
  Client().disconnect()
end

function Connect.setRelayAddress(address)
  S.relayAddress = address
end

return Connect
