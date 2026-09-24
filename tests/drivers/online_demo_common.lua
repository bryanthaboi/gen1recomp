-- Shared body for the two-window live-relay demo drivers.
--
-- Armed by OnlinePanel's POKEPORT_ONLINE_SHOT hook (see online_shot.lua's
-- demo-host / demo-guest states), so the real launcher ONLINE tab is on
-- screen and every panel call below is the one the buttons make.  A
-- coroutine wrapped around love.update keeps driving after the launcher
-- hands off to the arena, then stops and leaves the window open.
--
--   POKEPORT_IDENTITY=pokemon-love2d-demo-a POKEPORT_LAUNCHER_TAB=online \
--     POKEPORT_ONLINE_SHOT=demo-host love .

local Demo = {}

local SCRATCH = os.getenv("POKEPORT_DEMO_DIR") or "/tmp/pokeport_demo"
local SHOT_DIR = os.getenv("POKEPORT_DEMO_SHOTS") or (SCRATCH .. "/shots")
local CODE_FILE = os.getenv("POKEPORT_DEMO_CODE") or (SCRATCH .. "/demo_code.txt")
local TAP_EVERY = tonumber(os.getenv("POKEPORT_DEMO_TAP") or "") or 45

local function log(...)
  local parts = { "[demo]" }
  for i = 1, select("#", ...) do
    parts[#parts + 1] = tostring((select(i, ...)))
  end
  print(table.concat(parts, " "))
  pcall(function() io.stdout:flush() end)
end

Demo.log = log

local function Client()
  return require("src.online.Client")
end

local function mkdir(path)
  os.execute('mkdir -p "' .. path .. '" 2>/dev/null')
end

local function readCode()
  local f = io.open(CODE_FILE, "rb")
  if not f then return nil end
  local body = f:read("*a")
  f:close()
  body = tostring(body or ""):gsub("%s+", "")
  if not body:match("^r[0-9a-f]+$") or #body ~= 17 then return nil end
  return body
end

local function writeCode(roomId)
  mkdir(SCRATCH)
  local f = io.open(CODE_FILE, "wb")
  if not f then return false end
  f:write(roomId)
  f:close()
  return true
end

local function partyLine(mon)
  if type(mon) ~= "table" then return "?" end
  return ("%s Lv%s hp%s"):format(tostring(mon.species), tostring(mon.level),
    tostring(mon.hp))
end

-- ------------------------------------------------------------------ driver

function Demo.run(OnlinePanel, imp, opts)
  if Demo._armed then return end
  Demo._armed = true

  mkdir(SHOT_DIR)
  local prefix = opts.prefix
  local shotN = 0

  local co
  local function wait(n)
    for _ = 1, (n or 1) do coroutine.yield() end
  end

  local function shot(tag)
    shotN = shotN + 1
    local path = ("%s/%s_%d_%s.png"):format(SHOT_DIR, prefix, shotN, tag)
    love.graphics.captureScreenshot(function(imagedata)
      local ok, encoded = pcall(function() return imagedata:encode("png") end)
      if not ok then return end
      local f = io.open(path, "wb")
      if f then
        f:write(encoded:getString())
        f:close()
      end
    end)
    wait(20)
    local f = io.open(path, "rb")
    if f then
      f:close()
      log("shot", path)
    else
      log("FAIL shot did not reach disk", path)
    end
    return path
  end

  local function waitFor(fn, frames, what)
    for _ = 1, (frames or 3600) do
      local ok, hit = pcall(fn)
      if ok and hit then return true end
      coroutine.yield()
    end
    log("TIMEOUT waiting for", what)
    return false
  end

  local body = function()
    wait(30)
    if love.window and love.window.setMode then
      local w, h = (os.getenv("POKEPORT_DEMO_WIN") or "900x700")
        :match("^(%d+)x(%d+)$")
      if w then
        pcall(love.window.setMode, tonumber(w), tonumber(h),
          { resizable = true })
      end
    end

    local st = OnlinePanel.state(imp)
    st.name = opts.name
    st.version = "red"
    st.cartId = nil
    st.kind = "vanilla"
    st.slotId = opts.slotId
    st.public = true
    st.note = opts.note or ""
    st.setupDone = true
    st.team = {}
    for _, index in ipairs(opts.team) do
      OnlinePanel.toggleTeam(st.team, index, 6)
    end
    OnlinePanel.invalidate(imp)

    local pick, why = OnlinePanel.readTeamSlot(imp)
    if not pick then
      log("FAIL cannot read", opts.slotId, tostring(why))
      return
    end
    log("identity", tostring(os.getenv("POKEPORT_IDENTITY")))
    log("save", opts.slotId, "trainer", tostring(pick.trainerName))
    for _, index in ipairs(opts.team) do
      log("  team", index, partyLine(pick.party[index]))
    end

    OnlinePanel.home(imp)
    OnlinePanel.go(imp, "play")
    waitFor(function() return OnlinePanel.myProfile(imp) ~= nil end, 900,
      "the arena profile")

    local Net = require("src.link.Net")
    log("relay", tostring(Net.defaultRelayAddress()), "as", opts.name)
    OnlinePanel.doConnect(imp)
    if not waitFor(function() return Client().state() == "online" end, 3600,
        "the relay to accept the connection") then
      log("FAIL relay refused:", tostring(Client().error()),
        "state:", tostring(Client().state()))
      shot("connect_failed")
      return
    end
    log("online as", tostring((Client().you() or {}).name))
    wait(40)
    shot("connect")

    if opts.role == "host" then
      os.remove(CODE_FILE)
      OnlinePanel.startWizard(imp, "hostBattle")
      for _, step in ipairs({ "game", "save", "team", "rules", "visibility",
                              "summary" }) do
        OnlinePanel.wizardTo(imp, step)
        wait(30)
      end
      log("rule partySize", tostring(OnlinePanel.ruleFor(imp).partySize))
      if not OnlinePanel.wizardNext(imp) then
        log("FAIL hosting refused:", tostring(st.status))
        return
      end
      if not waitFor(function() return Client().room() ~= nil end, 3600,
          "the room to open") then
        log("FAIL no room:", tostring(st.status))
        return
      end
      local roomId = Client().room().room
      log("ROOM", roomId)
      writeCode(roomId)
      wait(60)
      shot("room")
      if not waitFor(function()
        local room = Client().room()
        return room and #(room.players or {}) >= 2
      end, 60 * 60 * 4, "the guest to join") then
        return
      end
      log("guest joined")
    else
      log("waiting for the host's room id at", CODE_FILE)
      local roomId
      if not waitFor(function()
        roomId = readCode()
        return roomId ~= nil
      end, 60 * 60 * 4, "the host's room id") then
        return
      end
      log("ROOM", roomId)
      if not OnlinePanel.startJoin(imp, { room = roomId },
          { partySize = #opts.team }, "player") then
        log("FAIL join wizard refused:", tostring(st.status))
        return
      end
      for _, step in ipairs({ "game", "save", "team", "summary" }) do
        OnlinePanel.wizardTo(imp, step)
        wait(30)
      end
      if not OnlinePanel.wizardNext(imp) then
        log("FAIL join refused:", tostring(st.status))
        return
      end
      if not waitFor(function() return Client().room() ~= nil end, 3600,
          "the room to answer") then
        log("FAIL not in a room:", tostring(st.status))
        return
      end
      log("joined room", tostring(Client().room().room))
      wait(60)
      shot("room")
    end

    wait(60)
    if not OnlinePanel.sendReady(imp) then
      log("FAIL READY refused:", tostring(st.status))
      return
    end
    log("READY sent")

    local GameMod
    if not waitFor(function()
      local ok, mod = pcall(require, "src.core.Game")
      if not ok or type(mod) ~= "table" then return false end
      if not (mod.linkSession and mod.stack and mod.stack.top) then
        return false
      end
      GameMod = mod
      return mod.stack:top() ~= nil
    end, 60 * 60 * 3, "the arena to boot") then
      log("FAIL the arena never booted")
      return
    end
    log("arena booted, battling")
    wait(180)
    shot("first_turn")

    local frames, midShot = 0, false
    while OnlinePanel.lastResult == nil do
      frames = frames + 1
      if frames % TAP_EVERY == 0 then
        local input = GameMod.input
        if input and input.pressQueue then
          table.insert(input.pressQueue, "a")
        end
      end
      if not midShot and frames > 900 then
        midShot = true
        shot("mid_battle")
      end
      if frames > 60 * 60 * 8 then
        log("FAIL the battle never finished")
        break
      end
      coroutine.yield()
    end

    log("RESULT", tostring(OnlinePanel.lastResult))
    shot("result")
    wait(300)
    shot("room_screen")
    log("DEMO COMPLETE - window left open, no further input")
    while true do coroutine.yield() end
  end

  co = coroutine.create(body)
  local base = love.update
  love.update = function(dt)
    base(dt)
    if coroutine.status(co) == "suspended" then
      local ok, err = coroutine.resume(co)
      if not ok then log("DRIVER ERROR", tostring(err)) end
    end
  end
  log("armed", opts.role, "shots ->", SHOT_DIR)
end

return Demo
