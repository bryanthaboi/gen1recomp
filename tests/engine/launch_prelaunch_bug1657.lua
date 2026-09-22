
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Json = require("src.link.Json")
local SyncState = require("src.sync.SyncState")
local SyncEngine = require("src.sync.SyncEngine")
local Prelaunch = require("src.core.Prelaunch")

local function fakeFs(files)
  local fs = { files = files or {}, writes = 0, removes = 0 }
  fs.getInfo = function(name)
    return fs.files[name] and { type = "file" } or nil
  end
  fs.remove = function(name)
    fs.files[name] = nil
    fs.removes = fs.removes + 1
    return true
  end
  fs.write = function(name, data)
    fs.files[name] = data or ""
    fs.writes = fs.writes + 1
    return true
  end
  fs.isFused = function() return true end
  return fs
end

local function fakeCheck(seq)
  local c = { seq = seq, i = 0, started = 0, downloads = 0 }
  c.start = function() c.started = c.started + 1 end
  c.download = function() c.downloads = c.downloads + 1 end
  c.state = function()
    c.i = math.min(c.i + 1, #c.seq)
    return c.seq[c.i]
  end
  return c
end

local function stage(opts)
  local rec = { outcomes = {}, restarts = 0 }
  opts.done = function(outcome) rec.outcomes[#rec.outcomes + 1] = outcome end
  opts.restart = function() rec.restarts = rec.restarts + 1 end
  rec.stage = Prelaunch.new(opts)
  return rec
end

local function pump(rec, times, dt)
  for _ = 1, (times or 8) do
    if rec.stage then rec.stage:update(dt or 0.1) end
  end
end


do
  local rec = stage({ version = "red", tasks = {}, engine = false,
    fs = fakeFs() })
  eq(rec.stage, nil,
    "no tasks and no linked device means no stage at all: the shortcut boots "
    .. "on the same frame it always did")
end

do
  local rec = stage({ version = "red", tasks = { sync = false, update = true },
    allowUpdate = false, engine = false, fs = fakeFs() })
  eq(rec.stage, nil, "an --update that the platform cannot apply is not a stage")
end


do
  local fs = fakeFs()
  local c = fakeCheck({
    { status = "checking" },
    { status = "available", latest = "0.2.0" },
    { status = "downloading", progress = 0.5 },
    { status = "ready" },
    { status = "ready" },
  })
  local rec = stage({ version = "red", tasks = { update = true, sync = false },
    allowUpdate = true, check = c, engine = false, fs = fs })
  check(rec.stage ~= nil, "an --update shortcut gets a stage")
  eq(c.started, 1, "which starts exactly one forced check")

  pump(rec, 2)
  eq(c.downloads, 1, "an available release starts downloading")
  pump(rec, 1)
  check(rec.stage.status:find("50", 1, true) ~= nil,
    "and the stage shows the download percentage")

  pump(rec, 1)
  eq(rec.restarts, 1, "a ready payload restarts into Boot.run exactly once")
  eq(fs.files[Prelaunch.MARKER], "1", "leaving the one-shot marker behind")
  eq(#rec.outcomes, 1, "the stage reports once")
  eq(rec.outcomes[1], "restart", "and the outcome is the restart, not a boot")

  pump(rec, 4)
  eq(rec.restarts, 1, "further frames never restart a second time")
  eq(#rec.outcomes, 1, "nor report a second outcome")

  local again = stage({ version = "red", tasks = { update = true, sync = false },
    allowUpdate = true, check = c, engine = false, fs = fs })
  eq(again.stage, nil, "the marker skips the update stage exactly once")
  eq(fs.files[Prelaunch.MARKER], nil, "and is consumed on read")
end

do
  local c = fakeCheck({ { status = "uptodate" } })
  local rec = stage({ version = "red", tasks = { update = true, sync = false },
    allowUpdate = true, check = c, engine = false, fs = fakeFs() })
  pump(rec, 1)
  eq(rec.outcomes[1], "boot", "an up-to-date check boots without a prompt")
  eq(c.downloads, 0, "and downloads nothing")
end

do
  local c = fakeCheck({ { status = "needs_full", full = { url = "x" } } })
  local rec = stage({ version = "red", tasks = { update = true, sync = false },
    allowUpdate = true, check = c, engine = false, fs = fakeFs() })
  pump(rec, 1)
  eq(rec.outcomes[1], "boot",
    "a full-update requirement is never installed unattended: it boots")
end

do
  local c = fakeCheck({ { status = "checking" } })
  local rec = stage({ version = "red", tasks = { update = true, sync = false },
    allowUpdate = true, check = c, engine = false, fs = fakeFs() })
  pump(rec, 10, 1)
  eq(#rec.outcomes, 0, "a check still running inside the budget keeps waiting")
  pump(rec, Prelaunch.UPDATE_BUDGET + 2, 1)
  eq(rec.outcomes[1], "boot", "but a dead network cannot outlast the budget")
end

do
  local c = fakeCheck({ { status = "checking" } })
  local rec = stage({ version = "red", tasks = { update = true, sync = false },
    allowUpdate = true, check = c, engine = false, fs = fakeFs() })
  rec.stage:cancel()
  eq(rec.outcomes[1], "boot", "any button skips the stage straight into the game")
  pump(rec, 4)
  eq(#rec.outcomes, 1, "and the skipped stage stays finished")
end


local function scripted(routes)
  local t = { sent = {}, routes = routes, handles = {} }
  function t:begin(req)
    self.sent[#self.sent + 1] = req
    local path = req.url:match("^[^?]*"):gsub("^http://sync%.test", "")
    local route = self.routes[req.method .. " " .. path]
    local reply = (type(route) == "function" and route(req, self)) or route
      or { code = 404, body = '{"error":"no route"}' }
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

local function linkedState()
  local state = SyncState.defaults()
  state.account = "aa11bb22cc33dd44"
  state.deviceToken = "tok"
  state.enabled = true
  return state
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

local function syncEngine(routes, entries, state)
  local saves = fakeSaves(entries or {})
  local eng = SyncEngine.new({
    baseUrl = "http://sync.test",
    transport = scripted(routes),
    state = state or linkedState(),
    saves = saves,
    persist = false,
    now = function() return 1700001000 end,
  })
  return eng, saves
end

do
  local eng, saves = syncEngine({
    ["GET /sync/state"] = { code = 200,
      body = '{"saves":{"red/xyz":{"rev":4,"meta":{"savedAt":900}}}}' },
    ["GET /sync/save"] = { code = 200,
      body = '{"rev":4,"meta":{"savedAt":900},"blob":"return { player = {} }"}' },
  }, {})

  local rec = stage({ version = "red", tasks = {}, engine = eng,
    fs = fakeFs() })
  check(rec.stage ~= nil, "a linked, sync-enabled device gets a sync stage")
  eq(#saves.writes, 0, "which has not landed the newer save yet")
  pump(rec, 24)
  eq(#saves.writes, 1,
    "the newer remote save is pulled down before the game boots")
  eq(saves.writes[1].version, "red", "into the right game")
  eq(rec.outcomes[1], "boot", "and only then does the shortcut boot")
  check(eng.protectedKey == nil,
    "nothing is protected yet: Game has not loaded a playthrough")
end

do
  local eng = syncEngine({})
  local rec = stage({ version = "red", tasks = { sync = false }, engine = eng,
    fs = fakeFs() })
  eq(rec.stage, nil, "--no-sync means no stage even on a linked device")
end

do
  local state = linkedState()
  state.enabled = false
  local eng = syncEngine({}, {}, state)
  local rec = stage({ version = "red", tasks = { sync = true }, engine = eng,
    fs = fakeFs() })
  eq(rec.stage, nil, "sync switched off is honoured even by an explicit --sync")
end

do
  local eng = syncEngine({}, {}, SyncState.defaults())
  local rec = stage({ version = "red", tasks = { sync = true }, engine = eng,
    fs = fakeFs() })
  eq(rec.stage, nil, "an unlinked device has nothing to sync")
end

do
  local entry = {
    version = "red", slot = "slot1", playthroughId = "xyz",
    blob = "return { player = { name = 'ASH' } }",
    meta = { savedAt = 900, sessionStart = 800, playthroughId = "xyz",
             summary = { name = "ASH", badges = 2 } },
  }
  local eng = syncEngine({
    ["GET /sync/state"] = { code = 200,
      body = '{"saves":{"red/xyz":{"rev":9,"meta":{"savedAt":1200,'
        .. '"sessionStart":1100,"summary":{"name":"ASH","badges":5}}}}}' },
  }, { entry })

  local rec = stage({ version = "red", tasks = {}, engine = eng,
    fs = fakeFs() })
  pump(rec, 24)
  eq(eng.phase, "conflict", "two diverged copies raise a conflict")
  eq(rec.outcomes[1], "launcher",
    "which must reach the player in the launcher's modal, not be booted over")
end

do
  local eng = syncEngine({
    ["GET /sync/state"] = function() return { code = 200, body = "{" } end,
  }, {})
  local rec = stage({ version = "red", tasks = {}, engine = eng,
    fs = fakeFs() })
  pump(rec, 24)
  eq(rec.outcomes[1], "boot", "a sync that errors still boots the game")
end

do
  local f = assert(io.open("main.lua", "r"))
  local src = f:read("*a")
  f:close()
  local handler = src:match(
    "function love%.handlers%.intent_game.-\n(.-)\nend\n")
  check(handler ~= nil, "main.lua still defines the Android intent handler")
  handler = handler or ""
  check(handler:find("LaunchOptions.fromGame", 1, true) ~= nil,
    "an Android intent enters the shared launch request")
  check(src:find("tasks = request.tasks or {}", 1, true) ~= nil,
    "the shared request runs the same pre-boot stage a shortcut does")
  local optionsFile = assert(io.open("src/core/LaunchOptions.lua", "r"))
  local optionsSrc = optionsFile:read("*a")
  optionsFile:close()
  check(optionsSrc:find("tasks.update = false", 1, true) ~= nil,
    "legacy Android intents never run the update check")
  local bootAt = src:find("if not Prelaunch then bootAfterMods()", 1, true)
  check(bootAt ~= nil,
    "and boots on the same frame when there is no stage to run")
  check(src:find("if not wantsModUpdate(request) then return bootShortcut() end",
    1, true) ~= nil,
    "straight into the game unless the mods pass was asked for")
end

T.finish("shortcut pre-boot stage (#1657)")
