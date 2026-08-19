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
    if type(route) == "function" then
      reply = route(req, self)
    else
      reply = route
    end
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
  state.enabled = true
  return state
end

local function saveEntry(version, id, savedAt, sessionStart, slot)
  return {
    version = version, slot = slot or "slot1", playthroughId = id,
    blob = "return { player = { name = 'ASH' } }",
    meta = { savedAt = savedAt, sessionStart = sessionStart,
             playthroughId = id, summary = { name = "ASH", badges = 2 } },
  }
end

local function fakeSaves(entries)
  local writes = {}
  return {
    writes = writes,
    list = function() return entries end,
    write = function(version, id, blob, mode)
      writes[#writes + 1] = { version = version, playthroughId = id,
                              blob = blob, mode = mode }
      return mode == "new" and "slot9" or "slot1"
    end,
  }
end

local function engine(routes, entries, state)
  local saves = fakeSaves(entries or {})
  local transport = scripted(routes)
  local eng = SyncEngine.new({
    baseUrl = "http://sync.test",
    transport = transport,
    state = state or linkedState(),
    saves = saves,
    persist = false,
    now = function() return 1700001000 end,
  })
  return eng, transport, saves
end

do
  T.eq(SyncEngine.overlaps({ sessionStart = 10, savedAt = 20 },
                           { sessionStart = 15, savedAt = 30 }), true,
    "two sessions that ran over the same minutes overlap")
  T.eq(SyncEngine.overlaps({ sessionStart = 10, savedAt = 20 },
                           { sessionStart = 21, savedAt = 30 }), false,
    "a session that started after the other ended does not")
  T.eq(SyncEngine.overlaps({ savedAt = 20 }, { sessionStart = 1, savedAt = 30 }),
    false, "a save with no session start cannot claim an overlap")
end

do
  local eng, transport = engine({
    ["POST /sync/create"] = { code = 200, body =
      '{"account":"aa11","code1":"11112222","code2":"33334444","deviceToken":"tok"}' },
  }, {}, SyncState.defaults())

  T.eq(eng:linked(), false, "a fresh engine is not linked")
  T.eq(eng.status, "Not set up", "and says so")

  eng:createAccount("laptop")
  pump(eng, 3)
  T.eq(eng:linked(), true, "creating an account links this device")
  T.eq(eng.state.account, "aa11", "and stores the account id")
  T.eq(eng.codes.code1, "1111-2222", "the first code is shown grouped")
  T.eq(eng.codes.code2, "3333-4444", "and so is the second")
  T.eq(eng.state.code1, nil, "codes never enter the persisted state")
  T.eq(eng.phase, "idle", "and the engine settles")
  T.eq(#transport.sent, 1, "one request was made")
end

do
  local eng, transport = engine({
    ["POST /sync/link"] = { code = 200,
      body = '{"account":"aa11","deviceToken":"tok"}' },
    ["GET /sync/state"] = { code = 200, body = '{"saves":{}}' },
    ["PUT /sync/save"] = { code = 200, body = '{"ok":true,"rev":1}' },
  }, { saveEntry("red", "abc", 500, 400) }, SyncState.defaults())

  eng:linkDevice("1111-2222", "3333 4444", "phone")
  pump(eng)
  T.eq(eng:linked(), true, "linking with both codes links the device")
  T.eq(transport.sent[2].url, "http://sync.test/sync/state",
    "and a sync starts immediately")
  T.eq(transport.sent[3].method, "PUT",
    "the local save the server has never seen is uploaded")
  T.eq(SyncState.rev(eng.state, "red/abc"), 1, "the served rev is remembered")
  T.eq(SyncState.stamp(eng.state, "red/abc"), 500,
    "along with the savedAt that was uploaded")
  T.eq(eng.phase, "idle", "and the engine settles")
  T.eq(eng.state.lastSyncAt, 1700001000, "the sync time is stamped")
end

do
  local eng, transport = engine({}, {}, SyncState.defaults())
  eng:linkDevice("12", "34", "phone")
  T.eq(#transport.sent, 0, "a malformed code pair is refused locally")
  T.eq(eng.phase, "error", "and the engine reports the problem")
  T.check(eng.status:find("8 digits", 1, true) ~= nil,
    "with copy that says what a code is")
end

do
  local eng, transport, saves = engine({
    ["GET /sync/state"] = { code = 200,
      body = '{"saves":{"gold/xyz":{"rev":4,"meta":{"savedAt":900}}}}' },
    ["GET /sync/save"] = { code = 200,
      body = '{"rev":4,"meta":{"savedAt":900},"blob":"return { player = {} }"}' },
  }, {})

  eng:syncNow()
  pump(eng)
  T.eq(#saves.writes, 1, "the remote-only save is written locally")
  T.eq(saves.writes[1].version, "gold", "into the right game")
  T.eq(saves.writes[1].mode, "replace", "as that playthrough's slot")
  T.eq(SyncState.rev(eng.state, "gold/xyz"), 4, "and its rev is remembered")
  T.eq(eng.phase, "idle", "the engine settles")
  T.eq(transport.sent[2].url, "http://sync.test/sync/save?id=xyz&version=gold",
    "the download names the playthrough, not the slot")
end

do
  local state = linkedState()
  SyncState.setRev(state, "red/abc", 7, 500)
  local eng, transport = engine({
    ["GET /sync/state"] = { code = 200,
      body = '{"saves":{"red/abc":{"rev":7,"meta":{"savedAt":500}}}}' },
  }, { saveEntry("red", "abc", 500, 400) }, state)

  eng:syncNow()
  pump(eng)
  T.eq(#transport.sent, 1, "an unchanged save is neither uploaded nor downloaded")
  T.eq(eng.phase, "idle", "and the sync ends idle")
end

local function conflictEngine()
  local state = linkedState()
  SyncState.setRev(state, "red/abc", 7, 500)
  return engine({
    ["GET /sync/state"] = { code = 200,
      body = '{"saves":{"red/abc":{"rev":9,"meta":{"savedAt":760,' ..
             '"sessionStart":600,"summary":{"name":"BLUE","badges":4}}}}}' },
    ["PUT /sync/save"] = { code = 200, body = '{"ok":true,"rev":10}' },
    ["GET /sync/save"] = { code = 200,
      body = '{"rev":9,"meta":{"savedAt":760},"blob":"return { player = {} }"}' },
  }, { saveEntry("red", "abc", 700, 650) }, state)
end

do
  local eng, transport = conflictEngine()
  eng:syncNow()
  pump(eng)
  T.eq(eng.phase, "conflict", "both sides changing is a conflict")
  T.eq(#eng.conflicts, 1, "one conflict is raised")
  T.eq(eng.conflicts[1].overlap, true,
    "the two sessions ran over the same minutes")
  T.eq(eng.status, "These saves were played at the same time.",
    "and the status is the wording the player was promised")
  T.eq(eng.conflicts[1].remoteMeta.summary.name, "BLUE",
    "the other device's save is summarized for the prompt")
  T.eq(#transport.sent, 1, "nothing is uploaded while the player decides")
  T.eq(#eng.state.pendingConflicts, 1, "the conflict survives in the state")
end

do
  local eng, transport = conflictEngine()
  eng:syncNow()
  pump(eng)
  eng:resolveConflict("red/abc", "local")
  pump(eng)
  local put = transport.sent[2]
  T.eq(put.method, "PUT", "keep this device uploads")
  T.eq(Json.decode(put.body).force, true, "with the force flag")
  T.eq(SyncState.rev(eng.state, "red/abc"), 10, "and adopts the new rev")
  T.eq(eng.phase, "idle", "the conflict is cleared")
  T.eq(#eng.state.pendingConflicts, 0, "and dropped from the state")
end

do
  local eng, transport, saves = conflictEngine()
  eng:syncNow()
  pump(eng)
  eng:resolveConflict("red/abc", "remote")
  pump(eng)
  T.eq(transport.sent[2].method, "GET", "keep the other device downloads")
  T.eq(#saves.writes, 1, "and writes it locally")
  T.eq(saves.writes[1].mode, "replace", "over this playthrough's slot")
  T.eq(SyncState.rev(eng.state, "red/abc"), 9, "adopting the remote rev")
  T.eq(eng.phase, "idle", "the conflict is cleared")
end

do
  local eng, transport, saves = conflictEngine()
  eng:syncNow()
  pump(eng)
  eng:resolveConflict("red/abc", "both")
  pump(eng)
  T.eq(#saves.writes, 1, "keep both imports the other save")
  T.eq(saves.writes[1].mode, "new", "into a new slot")
  local put = transport.sent[3]
  T.eq(put.method, "PUT", "and still uploads this device's save")
  T.eq(Json.decode(put.body).force, true, "forcing past the stale rev")
  T.eq(eng.phase, "idle", "the conflict is cleared")
end

do
  local eng = engine({
    ["GET /sync/state"] = { code = 200, body = '{"saves":{}}' },
    ["PUT /sync/save"] = { code = 409, body =
      '{"conflict":true,"rev":3,"remoteMeta":{"savedAt":710,"sessionStart":600}}' },
  }, { saveEntry("red", "abc", 700, 650) })

  eng:syncNow()
  pump(eng)
  T.eq(eng.phase, "conflict", "a 409 on upload becomes a conflict, not an error")
  T.eq(eng.conflicts[1].overlap, true, "with the overlap worked out")
end

do
  local eng = engine({
    ["GET /sync/state"] = function()
      return { code = 500, body = '{"error":"server on fire"}' }
    end,
  }, {})
  eng:syncNow()
  pump(eng, 3)
  T.eq(eng.phase, "error", "a server error stops the sync")
  T.check(eng.status:find("server on fire", 1, true) ~= nil,
    "and shows what the server said")
end

do
  local eng, transport = engine({
    ["GET /sync/state"] = { code = 200, body = '{"saves":{}}' },
    ["PUT /sync/save"] = { code = 200, body = '{"ok":true,"rev":1}' },
  }, { saveEntry("red", "abc", 500, 400) })

  eng:noteSaveWritten()
  eng:update(1)
  T.eq(#transport.sent, 0, "an in-game save does not sync straight away")
  eng:update(SyncEngine.UPLOAD_DEBOUNCE)
  T.eq(#transport.sent, 1, "it syncs once the debounce has passed")
  pump(eng)
  T.eq(transport.sent[2].method, "PUT", "and the save goes up")
end

do
  local eng, transport = engine({}, { saveEntry("red", "abc", 500, 400) })
  eng:setEnabled(false)
  eng:noteSaveWritten()
  eng:update(60)
  T.eq(#transport.sent, 0, "with sync off an in-game save uploads nothing")
end

do
  local eng = engine({
    ["POST /sync/create"] = { code = 200, body =
      '{"account":"aa11","code1":"11112222","code2":"33334444",' ..
      '"deviceToken":"tok","device":"0a1b2c3d"}' },
  }, {}, SyncState.defaults())
  eng:createAccount("laptop")
  pump(eng, 3)
  T.eq(eng.state.deviceId, "0a1b2c3d",
    "creating an account records the id the server gave this device")
  T.eq(SyncState.sanitize(eng.state).deviceId, "0a1b2c3d",
    "and it survives being persisted")
end

do
  local eng = engine({
    ["POST /sync/link"] = { code = 200,
      body = '{"account":"aa11","deviceToken":"tok","device":"beefcafe"}' },
    ["GET /sync/state"] = { code = 200, body = '{"saves":{}}' },
  }, {}, SyncState.defaults())
  eng:linkDevice("11112222", "33334444", "phone")
  pump(eng)
  T.eq(eng.state.deviceId, "beefcafe", "so does linking a second device")
end

do
  local state = linkedState()
  state.deviceId = "0a1b2c3d"
  local eng, transport = engine({
    ["POST /sync/unlink"] = { code = 200, body = '{"ok":true,"devices":1}' },
  }, {}, state)

  eng:unlink()
  T.eq(eng:linked(), true, "unlink waits for the server before forgetting")
  local sent = transport.sent[1]
  T.eq(sent.url, "http://sync.test/sync/unlink", "it asks the server first")
  T.eq(Json.decode(sent.body).device, "0a1b2c3d",
    "naming the device id the server knows, not the platform label")
  pump(eng, 3)
  T.eq(eng:linked(), false, "and only then drops the credentials")
  T.eq(eng.status, "Not set up", "reporting the device as unlinked")
end

do
  local state = linkedState()
  state.deviceId = "0a1b2c3d"
  local eng = engine({
    ["POST /sync/unlink"] = { code = 500, body = '{"error":"nope"}' },
  }, {}, state)
  eng:unlink()
  pump(eng, 3)
  T.eq(eng.phase, "error", "a failed revocation is surfaced")
  T.eq(eng:linked(), true,
    "and the device stays linked rather than lying about it")
end

do
  local state = linkedState()
  state.deviceId = "0a1b2c3d"
  local eng = engine({
    ["POST /sync/unlink"] = { code = 401, body = '{"error":"unauthorized"}' },
  }, {}, state)
  eng:unlink()
  pump(eng, 3)
  T.eq(eng:linked(), false,
    "a token the server already revoked is dropped rather than stuck forever")
end

do
  local state = linkedState()
  state.deviceId = "0a1b2c3d"
  local eng, transport = engine({
    ["POST /sync/unlink"] = { code = 200, body = '{"ok":true,"devices":1}' },
    ["GET /sync/state"] = { code = 200, body = '{"saves":{}}' },
  }, {}, state)
  eng:unlinkDevice("99998888")
  T.eq(Json.decode(transport.sent[1].body).device, "99998888",
    "another device is revoked by its id")
  pump(eng, 3)
  T.eq(eng:linked(), true, "without logging this device out")
end

do
  local state = linkedState()
  state.deviceId = "0a1b2c3d"
  local eng = engine({
    ["GET /sync/state"] = { code = 200, body =
      '{"saves":{},"devices":[{"id":"0a1b2c3d","label":"OS X","current":true},' ..
      '{"id":"99998888","label":"Android"}]}' },
  }, {}, state)
  eng:syncNow()
  pump(eng)
  T.eq(#eng.devices, 2, "the linked devices are kept for the modal to show")
  T.eq(eng.devices[1].current, true, "this device is marked")
  T.eq(eng.devices[2].label, "Android", "and the others are named")
end

do
  local eng = conflictEngine()
  eng:syncNow()
  pump(eng)
  eng:syncNow()
  pump(eng)
  eng:syncNow()
  pump(eng)
  T.eq(#eng.state.pendingConflicts, 1,
    "syncing again over the same conflict does not stack up rows")
  T.eq(#eng.conflicts, 1, "and the prompt still has exactly one to answer")
end

do
  local eng = engine({}, {})
  local order, seen = {}, {}
  eng.modDeps = {
    installed = function() return {} end,
    indexes = function() return {} end,
    addIndex = function(url) order[#order + 1] = "index" return { feed = url } end,
    findEntry = function() return nil end,
    install = function(entry) order[#order + 1] = "install:" .. entry.id return true end,
    setEnabled = function(id) order[#order + 1] = "enable:" .. id return true end,
  }
  eng.modPlan = {
    indexes = { "https://mods.example/i.json" },
    toInstall = { { id = "beta", entry = { id = "beta" } } },
    toEnable = { { id = "beta", version = "red" } },
    missing = {},
  }
  eng:applyModPlan(function(done, total, label, finished)
    seen[#seen + 1] = ("%d/%d %s"):format(done, total, tostring(finished))
  end)
  T.eq(#order, 0, "starting an apply installs nothing on the spot")
  T.eq(eng:busy(), true, "the launcher can see it is working")
  eng:update(0.016)
  T.eq(#order, 1, "one step runs per frame, so the progress line can draw")
  eng:update(0.016)
  eng:update(0.016)
  T.eq(#order, 3, "until the whole plan has run")
  T.eq(order[3], "enable:beta", "in plan order")
  T.eq(eng.modApply, nil, "the job is done")
  T.eq(eng.modPlan, nil, "and the plan is spent")
  T.eq(eng.status, "Mods applied", "the status says so")
  T.eq(seen[#seen], "3/3 true", "and the last progress call reports the end")
end

do
  local eng = engine({}, {})
  eng.modDeps = {
    installed = function() return {} end,
    indexes = function() return {} end,
    addIndex = function() return true end,
    findEntry = function() return nil end,
    install = function() return nil, "download failed" end,
    setEnabled = function() return true end,
  }
  eng.modPlan = { indexes = {}, toInstall = { { id = "beta", entry = { id = "beta" } } },
                  toEnable = {}, missing = {} }
  eng:applyModPlan()
  eng:update(0.016)
  T.eq(eng.modApply, nil, "a failing step still ends the job")
  T.check(eng.status:find("download failed", 1, true) ~= nil,
    "and the failure reaches the status line")
end

T.finish("sync_engine")
