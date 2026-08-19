package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
love = love or require("tests.love_stub")

local Json = require("src.link.Json")
local SyncClient = require("src.sync.SyncClient")

local function recorder()
  local t = { sent = {}, replies = {}, released = 0 }
  function t:begin(req)
    self.sent[#self.sent + 1] = req
    return #self.sent
  end
  function t:poll(handle)
    local reply = self.replies[handle]
    if not reply then return { status = "pending" } end
    return reply
  end
  function t:release() self.released = self.released + 1 end
  function t:answer(handle, code, body)
    self.replies[handle] = { status = "ok", code = code, body = body }
  end
  function t:fail(handle, err)
    self.replies[handle] = { status = "error", err = err }
  end
  return t
end

local function client(transport)
  return SyncClient.new({ baseUrl = "http://sync.test/", transport = transport })
end

do
  T.eq(SyncClient.normalizeCode("1234-5678"), "12345678",
    "a dashed code normalizes to digits")
  T.eq(SyncClient.normalizeCode(" 1234 5678 "), "12345678",
    "and so does a spaced one")
  T.eq(SyncClient.normalizeCode("1234567"), nil, "seven digits is not a code")
  T.eq(SyncClient.normalizeCode("123456789"), nil, "nor is nine")
  T.eq(SyncClient.normalizeCode("abcdefgh"), nil, "nor letters")
  T.eq(SyncClient.formatCode("12345678"), "1234-5678",
    "codes present as two groups of four")
  T.eq(SyncClient.formatCode("nope"), nil, "a bad code has no presentation")
end

do
  local t = recorder()
  local c = client(t)
  T.eq(c:isLinked(), false, "a new client is not linked")

  local handle = c:create("laptop")
  local req = t.sent[1]
  T.eq(req.method, "POST", "create posts")
  T.eq(req.url, "http://sync.test/sync/create", "to /sync/create")
  T.eq(req.headers["x-sync-account"], nil,
    "and carries no auth header before there is an account")
  T.eq(Json.decode(req.body).device, "laptop", "the device label rides along")

  t:answer(handle, 200,
    '{"account":"aa11","code1":"11112222","code2":"33334444","deviceToken":"tok"}')
  local res = c:poll(handle)
  T.eq(res.status, "ok", "a 200 with JSON reads as ok")
  T.eq(res.data.account, "aa11", "and the account comes back decoded")

  c:setAuth(res.data.account, res.data.deviceToken)
  T.eq(c:isLinked(), true, "storing the token links the client")

  local stateHandle = c:fetchState()
  local stateReq = t.sent[2]
  T.eq(stateReq.method, "GET", "state is a GET")
  T.eq(stateReq.headers["x-sync-account"], "aa11", "with the account header")
  T.eq(stateReq.headers["x-sync-token"], "tok", "and the device token header")
  T.eq(stateReq.body, nil, "and no body")
  T.eq(c:poll(stateHandle).status, "pending", "an unanswered request is pending")

  local bad, err = c:link("123", "456", "phone")
  T.eq(bad, nil, "a short code never reaches the network")
  T.check(tostring(err):find("8 digits", 1, true) ~= nil,
    "and says what a code looks like")
  T.eq(#t.sent, 2, "no request was sent for the bad codes")
end

do
  local t = recorder()
  local c = client(t)
  c:setAuth("aa11", "tok")

  local handle = c:putSave({ version = "red", slot = "slot1",
    meta = { savedAt = 100, sessionStart = 50 }, blob = "return {}",
    baseRev = 4 })
  local req = t.sent[1]
  T.eq(req.method, "PUT", "a save upload is a PUT")
  T.eq(req.url, "http://sync.test/sync/save", "to /sync/save")
  local body = Json.decode(req.body)
  T.eq(body.version, "red", "the version rides in the body")
  T.eq(body.baseRev, 4, "with the rev the client last synced")
  T.eq(body.meta.sessionStart, 50, "and the session start in the meta")

  t:answer(handle, 409,
    '{"conflict":true,"rev":9,"remoteMeta":{"savedAt":200,"sessionStart":60}}')
  local res = c:poll(handle)
  T.eq(res.status, "error", "a 409 is not a success")
  T.eq(res.code, 409, "the status code is reported")
  T.eq(res.data.remoteMeta.savedAt, 200,
    "and the conflict body is still readable")

  local tooBig, why = c:putSave({ version = "red", slot = "slot1",
    blob = string.rep("x", SyncClient.MAX_BLOB + 1) })
  T.eq(tooBig, nil, "an oversized save is refused before it is sent")
  T.check(tostring(why):find("too large", 1, true) ~= nil,
    "with a reason the UI can show")

  local getHandle = c:getSave("red", "abc def")
  T.eq(t.sent[2].url, "http://sync.test/sync/save?id=abc%20def&version=red",
    "a download escapes its query parameters")
  t:answer(getHandle, 200, '{"meta":{"savedAt":200},"blob":"return {}","rev":9}')
  T.eq(c:poll(getHandle).data.rev, 9, "the download reports the served rev")
end

do
  local t = recorder()
  local c = client(t)
  c:setAuth("aa11", "tok")

  local h1 = c:fetchState()
  t:fail(h1, "no route to host")
  local res = c:poll(h1)
  T.eq(res.status, "error", "a transport failure is an error")
  T.check(res.err:find("no route", 1, true) ~= nil, "and keeps the reason")

  local h2 = c:fetchState()
  t:answer(h2, 200, "<html>nope</html>")
  local html = c:poll(h2)
  T.eq(html.status, "error", "an HTML reply is not a sync reply")
  T.check(html.err:find("HTML", 1, true) ~= nil, "and says so")

  local h3 = c:fetchState()
  t:answer(h3, 401, '{"error":"bad_token"}')
  local denied = c:poll(h3)
  T.eq(denied.status, "error", "a 401 is an error")
  T.eq(denied.err, "bad_token", "carrying the server's own reason")

  local h4 = c:fetchState()
  t:answer(h4, 200, '{"ok":true,"error":"stale"}')
  T.eq(c:poll(h4).status, "error",
    "an error field in a 200 body still fails the call")

  c:clearAuth()
  local nope, err = c:fetchState()
  T.eq(nope, nil, "an unlinked client refuses an authenticated call")
  T.check(tostring(err):find("not linked", 1, true) ~= nil,
    "and says the device is not linked")
end

do
  local t = recorder()
  local c = client(t)
  c:setAuth("aa11", "tok")

  local handle = c:fetchShare("ab3d9k")
  T.eq(t.sent[1].headers["x-sync-token"], nil,
    "reading a share code needs no auth")
  T.eq(t.sent[1].url, "http://sync.test/sync/modshare?code=AB3D9K",
    "and the code is upper-cased in the query")
  t:answer(handle, 200, '{"manifest":{"rev":1,"mods":[],"indexes":[]}}')
  T.eq(c:poll(handle).data.manifest.rev, 1, "the shared manifest decodes")

  local bad, err = c:fetchShare("12")
  T.eq(bad, nil, "a short share code never reaches the network")
  T.check(tostring(err):find("6 characters", 1, true) ~= nil,
    "and says how long one is")
end

T.finish("sync_client")
