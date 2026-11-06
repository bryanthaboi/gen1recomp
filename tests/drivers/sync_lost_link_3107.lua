return function(game)
  local U = dofile("tests/drivers/util.lua")
  local SyncEngine = require("src.sync.SyncEngine")
  local SyncBox = require("src.sync.SyncBox")
  local SyncState = require("src.sync.SyncState")
  local ok = true
  local function check(label, cond)
    if not cond then ok = false end
    U.log(cond and "PASS" or "FAIL", label)
  end
  local dataDir = os.getenv("SYNC_PROBE_DATA")
  if not dataDir or dataDir == "" then
    U.log("FAIL", "SYNC_PROBE_DATA is not set")
    love.event.quit(1)
    return
  end
  local files = {}
  local memfs = {
    read = function(p) return files[p] end,
    getInfo = function(p) return files[p] and { type = "file" } or nil end,
    createDirectory = function() return true end,
    getDirectoryItems = function() return {} end,
    remove = function(p) files[p] = nil return true end,
    write = function(p, b) files[p] = b return true end,
  }
  local requests = 0
  local Fetch = require("src.net.Fetch")
  local transport = require("src.sync.SyncTransport").new(setmetatable({
    request = function(...) requests = requests + 1 return Fetch.request(...) end,
  }, { __index = Fetch }))
  local eng = SyncEngine.new({
    baseUrl = os.getenv("SYNC_PROBE_URL") or "http://127.0.0.1:18777",
    transport = transport,
    state = SyncState.defaults(), persist = false,
    saves = { list = function() return {} end },
    box = SyncBox.new(memfs),
  })
  local function settle(tag)
    local deadline = love.timer.getTime() + 8
    repeat
      eng:update(1 / 60)
      U.wait(1)
    until (not eng:busy() and eng.phase ~= "checking") or love.timer.getTime() > deadline
    U.log(("[%s] phase=%s linked=%s status=%s"):format(tag, eng.phase, tostring(eng:linked()), tostring(eng.status)))
  end

  eng:createAccount("lost3107"); settle("create")
  check("create on an empty install ends idle", eng.phase == "idle" and eng:linked())
  local account, c1, c2 = eng.state.account, eng.state.code1, eng.state.code2
  local accountFile = dataDir .. "/" .. tostring(account) .. ".json"
  local fh = io.open(accountFile, "r")
  check("account file exists on the local server", fh ~= nil)
  if fh then fh:close() end

  os.execute("chmod 000 '" .. accountFile .. "'")
  eng:syncNow(); settle("sync while the account file is unreadable")
  os.execute("chmod 600 '" .. accountFile .. "'")
  check("a server read error keeps this device linked", eng:linked())
  check("a server read error shows the server_error text",
    eng.status == "Sync failed: " .. SyncEngine.ERROR_TEXT.server_error)
  eng:syncNow(); settle("sync after the server recovers")
  check("sync works again once the server recovers", eng.phase == "idle" and eng:linked())

  os.remove(accountFile)
  eng:syncNow(); settle("sync after account removed")
  check("one 401 keeps this device linked", eng:linked())
  eng:update(SyncEngine.AUTO_INTERVAL + 1); settle("auto sync one interval later")
  check("a second 401 one interval later unlinks this device", not eng:linked())
  check("the sync codes survive the lost link", eng.state.code1 == c1 and eng.state.code2 == c2)
  check("the status explains the lost link", eng.status == SyncEngine.ERROR_TEXT.unauthorized)
  local before = requests
  for _ = 1, 3 do
    eng:update(SyncEngine.AUTO_INTERVAL + 1)
    U.wait(2)
  end
  check("no auto retry after the lost link", requests == before)

  eng:linkDevice(eng.state.code1, eng.state.code2, "lost3107"); settle("relink dead codes")
  check("relinking with the dead codes explains bad_code",
    eng.status == "Sync failed: " .. SyncEngine.ERROR_TEXT.bad_code)
  eng:createAccount("lost3107"); settle("create again")
  check("a new sync account recovers", eng.phase == "idle" and eng:linked())
  local n = requests
  eng:linkDevice(eng.state.code1, eng.state.code2, "lost3107"); settle("link while linked")
  check("linking while linked sends nothing", requests == n)
  love.event.quit(ok and 0 or 1)
end
