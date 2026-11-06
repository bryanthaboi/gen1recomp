package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
love = love or require("tests.love_stub")

local Json = require("src.link.Json")
local SyncState = require("src.sync.SyncState")
local SyncEngine = require("src.sync.SyncEngine")

local function scripted(routes)
  local t = { sent = {}, routes = routes, handles = {} }
  function t:begin(req)
    self.sent[#self.sent + 1] = req
    local path = req.url:match("^[^?]*"):gsub("^http://sync%.test", "")
    local route = self.routes[req.method .. " " .. path]
    local reply
    if type(route) == "function" then reply = route(req, self) else reply = route end
    reply = reply or { code = 404, body = '{"error":"no route"}' }
    self.handles[#self.sent] = {
      status = "ok", code = reply.code or 200,
      body = reply.body or Json.encode(reply.data or {}),
    }
    return #self.sent
  end
  function t:poll(handle) return self.handles[handle] end
  function t:release() end
  return t
end

local function pump(eng, times)
  for _ = 1, (times or 24) do eng:update(0.05) end
end

local function linkedState()
  local state = SyncState.defaults()
  state.account = "aa11bb22cc33dd44"
  state.deviceToken = "tok"
  state.deviceId = "dev1"
  state.code1, state.code2 = "11112222", "33334444"
  state.enabled = true
  state.revs["red/abc"] = 3
  return state
end

local function engine(routes, state, entries)
  local transport = scripted(routes)
  local eng = SyncEngine.new({
    baseUrl = "http://sync.test",
    transport = transport,
    state = state or linkedState(),
    saves = {
      list = function() return entries or {} end,
      remove = function() return "slot1" end,
      write = function() return "slot1" end,
    },
    persist = false,
    now = function() return 1700001000 end,
  })
  return eng, transport
end

local UNAUTH = { code = 401, body = '{"error":"unauthorized"}' }
local LOST = SyncEngine.ERROR_TEXT.unauthorized
local OK_STATE = { code = 200, body = '{"saves":{}}' }

local function sequence(transport, route, seq, after)
  transport.routes[route] = function()
    return table.remove(seq, 1) or after
  end
end

do
  local eng, transport = engine({ ["GET /sync/state"] = UNAUTH })
  eng:syncNow()
  pump(eng)
  T.eq(eng:linked(), true, "one 401 does not drop the link")
  T.eq(eng.state.account, "aa11bb22cc33dd44", "the stored account is kept after one 401")
  T.eq(SyncState.rev(eng.state, "red/abc"), 3, "revs are kept after one 401")
  T.eq(eng.phase, "error", "the first 401 reads as an error")
  T.eq(eng.status, "Sync failed: " .. LOST, "the first 401 shows the plain text")
  eng:syncNow()
  pump(eng)
  T.eq(#transport.sent, 2, "a manual retry right away is sent")
  T.eq(eng:linked(), true, "a second 401 inside one sync interval keeps the link")
  eng:update(SyncEngine.AUTO_INTERVAL + 1)
  pump(eng)
  T.eq(#transport.sent, 3, "the auto retry runs one sync interval after the first 401")
  T.eq(eng:linked(), false, "a 401 again one sync interval later drops the dead link")
  T.eq(eng.state.account, nil, "the stored account is cleared")
  T.eq(eng.state.deviceToken, nil, "the stored device token is cleared")
  T.eq(eng.client:isLinked(), false, "the client stops sending the dead credentials")
  T.eq(SyncState.rev(eng.state, "red/abc"), nil, "revs from the dead account are forgotten")
  T.eq(eng.state.code1, "11112222", "the first sync code is kept after the lost link")
  T.eq(eng.state.code2, "33334444", "the second sync code is kept after the lost link")
  T.eq(eng.codes and eng.codes.code1, SyncEngine.formatCodes(eng.state).code1,
    "the formatted codes are kept too")
  T.eq(eng.phase, "error", "the lost link reads as an error")
  T.eq(eng.status, LOST, "the status says the account is gone in plain words")
  T.eq(eng.status:find("unauthorized", 1, true), nil, "the raw server code is not shown")
  for _ = 1, 3 do
    eng:update(SyncEngine.AUTO_INTERVAL + 1)
    pump(eng, 4)
  end
  T.eq(#transport.sent, 3, "no auto retry follows a lost link")
end

do
  local eng, transport = engine({ ["GET /sync/state"] = UNAUTH })
  pump(eng, 2)
  eng:update(SyncEngine.AUTO_INTERVAL + 1)
  pump(eng)
  T.eq(#transport.sent, 1, "the auto sync that hits a 401 sends one request")
  T.eq(eng:linked(), true, "and keeps the link")
  eng:update(SyncEngine.AUTO_INTERVAL + 1)
  pump(eng)
  T.eq(#transport.sent, 2, "the next auto sync retries")
  T.eq(eng:linked(), false, "and its 401 unlinks the dead account")
  for _ = 1, 3 do
    eng:update(SyncEngine.AUTO_INTERVAL + 1)
    pump(eng, 4)
  end
  T.eq(#transport.sent, 2, "and the 300 second loop stops after it")
end

do
  local eng, transport = engine({ ["GET /sync/state"] = OK_STATE })
  sequence(transport, "GET /sync/state", { UNAUTH, OK_STATE }, UNAUTH)
  eng:syncNow()
  pump(eng)
  T.eq(eng:linked(), true, "after one 401")
  eng:update(SyncEngine.AUTO_INTERVAL + 1)
  pump(eng)
  T.eq(eng:linked(), true, "a good reply one interval later keeps the link")
  T.eq(eng.phase, "idle", "and sync settles again")
  eng:update(SyncEngine.AUTO_INTERVAL + 1)
  pump(eng)
  T.eq(eng:linked(), true, "a good reply resets the count, so the next lone 401 keeps the link")
end

do
  local SERVER = { code = 500, body = '{"error":"server_error"}' }
  local eng, transport = engine({ ["GET /sync/state"] = SERVER })
  eng:syncNow()
  pump(eng)
  for _ = 1, 3 do
    eng:update(SyncEngine.AUTO_INTERVAL + 1)
    pump(eng)
  end
  T.eq(#transport.sent, 4, "a server_error keeps the auto retry going")
  T.eq(eng:linked(), true, "a server_error never unlinks")
  T.eq(eng.state.code1, "11112222", "and keeps the codes")
  T.eq(eng.status, "Sync failed: " .. SyncEngine.ERROR_TEXT.server_error,
    "a server_error shows the plain explanation")
end

do
  local eng, transport = engine({
    ["GET /sync/state"] = OK_STATE,
    ["PUT /sync/save"] = UNAUTH,
  }, nil, { {
    version = "red", slot = "slot1", playthroughId = "new1",
    blob = 'return { player = { name = "ASH" } }',
    meta = { savedAt = 500, sessionStart = 400, playthroughId = "new1" },
  } })
  eng:syncNow()
  pump(eng, 60)
  T.eq(transport.sent[2] and transport.sent[2].method, "PUT", "the upload was attempted")
  T.eq(eng:linked(), true, "a lone 401 in the middle of an upload keeps the link")
  T.eq(eng.status, "Sync failed: " .. LOST, "with the plain status")
  T.eq(eng:busy(), false, "and nothing is left queued")
end

do
  local eng = engine({ ["GET /sync/state"] = { code = 401, body = "<html>401</html>" } })
  eng:syncNow()
  pump(eng)
  eng:update(SyncEngine.AUTO_INTERVAL + 1)
  pump(eng)
  T.eq(eng:linked(), true, "a 401 without the server's unauthorized code keeps the link")
  T.eq(eng.phase, "error", "and is still a failure")
end

do
  local eng, transport = engine({ ["POST /sync/unlink"] = UNAUTH })
  eng:unlink()
  pump(eng)
  T.eq(#transport.sent, 1, "unlink sends one request")
  T.eq(eng:linked(), false, "unlink on a dead account still clears local state at once")
  T.eq(eng.state.account, nil, "including the stored account")
  T.eq(eng:busy(), false, "and settles")
end

do
  local eng, transport = engine({ ["POST /sync/unlink"] = { code = 503, body = '{"error":"busy"}' } })
  eng:unlink()
  pump(eng)
  T.eq(eng:linked(), false, "unlink still forgets local state when the server is unreachable")
  T.eq(#transport.sent, 1, "after one request")
end

do
  local eng = engine({ ["POST /sync/link"] = { code = 400, body = '{"error":"bad_code"}' } },
    SyncState.defaults())
  eng:linkDevice("11112222", "33334444", "phone")
  pump(eng)
  T.eq(eng.error, "bad_code", "the raw server code stays on the engine")
  T.eq(eng.status, "Sync failed: " .. SyncEngine.ERROR_TEXT.bad_code,
    "a bad_code reply shows the plain explanation")
end

do
  local eng = engine({ ["POST /sync/link"] = { code = 429, body = '{"error":"rate_limited"}' } },
    SyncState.defaults())
  eng:linkDevice("11112222", "33334444", "phone")
  pump(eng)
  T.eq(eng.status, "Sync failed: " .. SyncEngine.ERROR_TEXT.rate_limited,
    "a rate limit shows the plain explanation")
end

do
  local eng = engine({ ["POST /sync/link"] = { code = 400, body = '{"error":"some_new_code"}' } },
    SyncState.defaults())
  eng:linkDevice("11112222", "33334444", "phone")
  pump(eng)
  T.eq(eng.status, "Sync failed: some_new_code", "an unmapped server code is passed through")
end

do
  local linkHits = 0
  local eng, transport = engine({
    ["POST /sync/link"] = function()
      linkHits = linkHits + 1
      return { code = 200, body = '{"account":"ffff0000ffff0000","deviceToken":"tok2"}' }
    end,
  })
  local ok = eng:linkDevice("1111-2222", "3333-4444", "phone")
  pump(eng)
  T.eq(ok, false, "linking again with this account's own codes does nothing")
  T.eq(linkHits, 0, "so the server gets no extra device")
  T.eq(#transport.sent, 0, "no request at all")
  T.eq(eng.state.account, "aa11bb22cc33dd44", "the current link is untouched")

  local ok2 = eng:linkDevice("55556666", "77778888", "phone")
  pump(eng)
  T.eq(ok2, false, "linking to other codes while linked is refused")
  T.eq(linkHits, 0, "and adds no device either")
  T.eq(eng.status, "Sync failed: " .. SyncEngine.ERROR_TEXT.already_linked,
    "with a status that says to unlink first")
  T.eq(eng:linked(), true, "the current link survives the refusal")
end

do
  local eng, transport = engine({
    ["POST /sync/link"] = { code = 200, body = '{"account":"ffff0000ffff0000","deviceToken":"tok2"}' },
    ["GET /sync/state"] = { code = 200, body = '{"saves":{}}' },
  })
  sequence(transport, "GET /sync/state", { UNAUTH, UNAUTH }, OK_STATE)
  eng:syncNow()
  pump(eng)
  eng:update(SyncEngine.AUTO_INTERVAL + 1)
  pump(eng)
  T.eq(eng:linked(), false, "after a lost link")
  eng:linkDevice(eng.state.code1, eng.state.code2, "phone")
  pump(eng)
  local link = transport.sent[3]
  local body = link and link.body or ""
  T.eq(link and link.method, "POST", "relinking with the kept codes sends a link request")
  T.eq(body:find("11112222", 1, true) ~= nil and body:find("33334444", 1, true) ~= nil, true,
    "with the codes this device kept")
  T.eq(eng:linked(), true, "relinking with the kept codes works without another device")
  T.eq(eng.state.account, "ffff0000ffff0000", "onto the account those codes name")
  T.eq(eng.phase, "idle", "and the next sync settles")
end

do
  local HostShell = require("src.core.HostShell")
  local MARK = "\n__gen1recomp_http__"
  local realPopen = io.popen
  local out
  io.popen = function(cmd)
    if cmd:find("--version", 1, true) then
      return { read = function() return "curl 8.7.1 (test)" end, close = function() return true end }
    end
    return { read = function() return out end, close = function() return true end }
  end
  local URL = "https://sync.147.182.215.255.sslip.io/sync/state"
  out = "curl: (6) Could not resolve host: sync.example" .. MARK .. "0"
  local _, err = HostShell.httpGet(URL, "ua", nil, 10)
  out = '{"message":"slow down"}' .. MARK .. "403"
  local _, err403 = HostShell.httpGet(URL, "ua", nil, 10)
  io.popen = realPopen
  local why, at = err:find("Could not resolve", 1, true), err:find(URL, 1, true)
  T.eq(why ~= nil and at ~= nil and why < at, true,
    "a transport error puts the reason before the URL: " .. tostring(err))
  local why403, at403 = err403:find("slow down", 1, true), err403:find(URL, 1, true)
  T.eq(why403 ~= nil and at403 ~= nil and why403 < at403, true,
    "an HTTP error puts the reason before the URL: " .. tostring(err403))
end

T.finish("sync lost link")
