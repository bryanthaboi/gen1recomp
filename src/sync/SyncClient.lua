local Json = require("src.link.Json")

local SyncClient = {}
SyncClient.__index = SyncClient

SyncClient.DEFAULT_URL = os.getenv("POKEPORT_SYNC_URL")
  or "https://sync.147.182.215.255.sslip.io"
SyncClient.MAX_BLOB = 2 * 1024 * 1024
SyncClient.MAX_RESPONSE = 4 * 1024 * 1024
SyncClient.TIMEOUT = 25

function SyncClient.normalizeCode(code)
  if type(code) ~= "string" and type(code) ~= "number" then return nil end
  local digits = tostring(code):gsub("[^%d]", "")
  if #digits ~= 8 then return nil end
  return digits
end

function SyncClient.formatCode(code)
  local digits = SyncClient.normalizeCode(code)
  if not digits then return nil end
  return digits:sub(1, 4) .. "-" .. digits:sub(5, 8)
end

local function escape(s)
  return (tostring(s):gsub("[^%w%-%._~]", function(c)
    return ("%%%02X"):format(c:byte())
  end))
end

local function query(params)
  local names = {}
  for name in pairs(params or {}) do names[#names + 1] = tostring(name) end
  table.sort(names)
  local out = {}
  for _, name in ipairs(names) do
    out[#out + 1] = escape(name) .. "=" .. escape(params[name])
  end
  if #out == 0 then return "" end
  return "?" .. table.concat(out, "&")
end

function SyncClient.new(opts)
  opts = opts or {}
  local base = opts.baseUrl or SyncClient.DEFAULT_URL
  base = tostring(base):gsub("/+$", "")
  local transport = opts.transport
  if not transport then
    transport = require("src.sync.SyncTransport").new()
  end
  return setmetatable({
    baseUrl = base,
    transport = transport,
    account = opts.account,
    token = opts.token,
  }, SyncClient)
end

function SyncClient:setAuth(account, token)
  self.account = type(account) == "string" and account ~= "" and account or nil
  self.token = type(token) == "string" and token ~= "" and token or nil
end

function SyncClient:clearAuth()
  self.account, self.token = nil, nil
end

function SyncClient:isLinked()
  return self.account ~= nil and self.token ~= nil
end

function SyncClient:send(method, path, body, opts)
  opts = opts or {}
  local headers = { ["Accept"] = "application/json" }
  local payload
  if body ~= nil then
    local ok, encoded = pcall(Json.encode, body)
    if not ok then return nil, "could not encode the request" end
    payload = encoded
    headers["Content-Type"] = "application/json"
  end
  if not opts.noAuth then
    if not self:isLinked() then return nil, "this device is not linked" end
    headers["x-sync-account"] = self.account
    headers["x-sync-token"] = self.token
  end
  local url = self.baseUrl .. path .. query(opts.params)
  local handle = self.transport:begin({
    url = url, method = method, body = payload, headers = headers,
    maxSeconds = opts.maxSeconds or SyncClient.TIMEOUT,
  })
  if handle == nil then return nil, "no network transport" end
  return handle
end

function SyncClient:poll(handle)
  if handle == nil then return { status = "error", err = "no request" } end
  local res = self.transport:poll(handle)
  if res.status == "pending" then return { status = "pending" } end
  if res.status ~= "ok" then
    return { status = "error", err = res.err or "sync request failed" }
  end
  local raw = res.body or ""
  local code = tonumber(res.code) or 0
  if #raw > SyncClient.MAX_RESPONSE then
    return { status = "error", code = code, err = "the reply was too large" }
  end
  local data, decodeErr = Json.decode(raw, SyncClient.MAX_RESPONSE)
  if type(data) ~= "table" then
    local why = Json.describeUnexpected(raw) or decodeErr or "unreadable reply"
    if code >= 400 then
      return { status = "error", code = code,
        err = ("the server answered %d"):format(code) }
    end
    return { status = "error", code = code, err = why }
  end
  if code >= 400 or data.error then
    local err = data.error
    if type(err) ~= "string" or err == "" then
      err = ("the server answered %d"):format(code)
    end
    return { status = "error", code = code, data = data, err = err }
  end
  return { status = "ok", code = code, data = data }
end

function SyncClient:release(handle)
  if handle ~= nil then self.transport:release(handle) end
end

function SyncClient:create(deviceLabel)
  return self:send("POST", "/sync/create",
    { device = deviceLabel or "device" }, { noAuth = true })
end

function SyncClient:link(code1, code2, deviceLabel)
  local a = SyncClient.normalizeCode(code1)
  local b = SyncClient.normalizeCode(code2)
  if not a or not b then return nil, "both codes are 8 digits" end
  return self:send("POST", "/sync/link",
    { code1 = a, code2 = b, device = deviceLabel or "device" },
    { noAuth = true })
end

function SyncClient:fetchState()
  return self:send("GET", "/sync/state")
end

function SyncClient:putSave(entry)
  if type(entry) ~= "table" then return nil, "missing save entry" end
  if type(entry.blob) ~= "string" or entry.blob == "" then
    return nil, "missing save data"
  end
  if #entry.blob > SyncClient.MAX_BLOB then
    return nil, "this save is too large to sync"
  end
  return self:send("PUT", "/sync/save", {
    version = entry.version,
    slot = entry.slot,
    meta = entry.meta,
    blob = entry.blob,
    baseRev = entry.baseRev,
    force = entry.force and true or nil,
  })
end

function SyncClient:getSave(version, id)
  return self:send("GET", "/sync/save", nil,
    { params = { version = version, id = id } })
end

function SyncClient:putMods(manifest)
  return self:send("PUT", "/sync/mods", { manifest = manifest })
end

function SyncClient:getMods()
  return self:send("GET", "/sync/mods")
end

function SyncClient:shareMods(manifest)
  return self:send("POST", "/sync/modshare", { manifest = manifest })
end

function SyncClient:fetchShare(code)
  local trimmed = tostring(code or ""):gsub("%s", ""):upper()
  if not trimmed:match("^[A-Z2-9]+$") or #trimmed ~= 6 then
    return nil, "share codes are 6 characters"
  end
  return self:send("GET", "/sync/modshare", nil,
    { noAuth = true, params = { code = trimmed } })
end

function SyncClient:unlink(device)
  return self:send("POST", "/sync/unlink", { device = device })
end

return SyncClient
