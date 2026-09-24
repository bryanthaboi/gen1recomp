-- Scripted ONLINE tab states for the launcher screenshot harness.  Armed once
-- by OnlinePanel from POKEPORT_ONLINE_SHOT.
--
--   POKEPORT_LAUNCHER_TAB=online POKEPORT_ONLINE_SHOT=play \
--   POKEPORT_WIN=1280x800 POKEPORT_LAUNCHER_SHOT=/tmp/play.png love .
--
-- States: home, play, play-full, play-hosting,
--         host-game, host-save, host-team, host-rules, host-visibility,
--         host-summary, pc-picker,
--         tour-game, tour-save, tour-playing, tour-team, tour-rules,
--         tour-shotclock, tour-spectators, tour-summary,
--         join-summary, join-team, trade-role, trade-summary,
--         room, room-result, room-trade, watch, tournament,
--         tournament-lobby, trade, trade-local, trade-pc, trade-remote,
--         trade-cross, trade-pc-picked, trade-pc-commit (writes both saves),
--         trade-modal, trade-modal-done, trade-commit (writes both saves).

local function Client()
  return require("src.online.Client")
end

local PROFILE = {
  engine = 1, version = "red", engineVersion = "1.2.3", apiVersion = 4,
  fingerprint = "shot", rulesetId = "gen1_faithful", kind = "vanilla",
  rule = { partySize = 3 },
}

local NAMES = { "RED", "BLUE", "GREEN", "LEAF", "ETHAN", "LYRA", "SILVER",
                "KRIS", "GOLD", "MAY", "BRENDAN", "WALLY" }

local function fakeLobby(count, myProfile)
  local rows = {}
  for i = 1, count do
    local profile = {}
    for key, value in pairs(myProfile or PROFILE) do profile[key] = value end
    if i % 5 == 0 then profile.fingerprint = "other" end
    if i % 7 == 0 then
      profile.kind = "cart"
      profile.cart = { id = "kanto", version = "1.0.0", hash = "abc" }
    end
    local tour = i % 11 == 0
    rows[i] = {
      id = "e" .. i,
      open = true,
      spectators = i % 4,
      room = not tour and ("r%016x"):format(i) or nil,
      tour = tour and ("t%016x"):format(i) or nil,
      locked = not tour and i % 8 == 0 or nil,
      name = NAMES[((i - 1) % #NAMES) + 1] .. "#" .. (100 + i),
      verified = i % 3 == 0,
      intent = tour and "tournament" or "battle",
      note = (i % 4 == 0) and "first to three" or nil,
      profile = profile,
      stage = (i % 6 == 0) and "battling" or "waiting",
    }
  end
  return rows
end

local function goOnline(OnlinePanel, imp, count)
  local client = Client()
  client.state = function() return "online" end
  client.you = function()
    return { id = "me", name = "RED#417", verified = true }
  end
  client.serverTime = function() return 1000 end
  local cached, cachedKey
  local function lobby()
    local mine = OnlinePanel.myProfile(imp)
    local key = tostring(mine and mine.fingerprint)
    if key ~= cachedKey then
      cachedKey = key
      cached = fakeLobby(count, mine or PROFILE)
    end
    return cached
  end
  client.lobby = lobby
  client.openRooms = function()
    local out = {}
    for _, entry in ipairs(lobby()) do
      if entry.open and entry.intent ~= "tournament" then
        out[#out + 1] = entry
      end
    end
    return out
  end
  client.watchable = function()
    local out = {}
    for _, entry in ipairs(lobby()) do
      if entry.stage == "battling" or entry.intent == "tournament" then
        out[#out + 1] = entry
      end
    end
    return out
  end
  client.counts = function()
    return { players = count + 3, openRooms = #client.openRooms() }
  end
  return client
end

local ROOM = {
  room = ("r%016x"):format(0xab2cd3), host = "me", stage = "waiting", intent = "battle",
  profile = PROFILE,
  players = {
    { id = "me", name = "RED#417", verified = true, ready = false },
    { id = "p2", name = "BLUE#221", ready = true },
  },
  spectators = { { id = "s1", name = "GREEN#009" } },
  deadlines = { ready = 61000 },
}

local TOUR = {
  tour = ("t%016x"):format(0x234), code = "TRN234", creator = "me", stage = "running", round = 2, shotClock = 6,
  players = {
    { id = "me", name = "RED#417", verified = true, online = true },
    { id = "p2", name = "BLUE#221", online = true },
    { id = "p3", name = "GREEN#009", online = false, eliminated = true },
    { id = "p4", name = "LEAF#712", online = true },
  },
  spectators = { { id = "s1", name = "WATCH" } },
  profile = PROFILE, rule = { partySize = 3 },
  bracket = {
    { round = 1, matches = {
        { match = "m1", a = "me", b = "p3", winner = "me", how = "agreed",
          state = "done" },
        { match = "m2", a = "p2", b = "p4", winner = "p2", how = "reported",
          state = "done" } } },
    { round = 2, matches = {
        { match = "m3", a = "me", b = "p2", state = "live" } } },
  },
  live = "m3",
  deadlines = { shot = 7000 },
}

-- ------------------------------------------------------------------ trade

local function peerParty(entry)
  if not entry then return {} end
  local TeamPick = require("src.online.TeamPick")
  local ok, slot = pcall(TeamPick.readSlot, entry.version, entry.slotId,
    entry.cartId)
  if not ok or type(slot) ~= "table" then return {} end
  return slot.party or {}
end

local function scriptedLink(party)
  local Protocol = require("src.link.Protocol")
  local inbox = {}
  return {
    seat = function() return 0 end,
    send = function(_, msg)
      if type(msg) ~= "table" then return end
      if msg.type == "party" then
        inbox[#inbox + 1] = { type = "party",
                              mons = Protocol.packParty(party) }
      elseif msg.type == "pick" then
        inbox[#inbox + 1] = { type = "pick", index = 1 }
      elseif msg.type == "confirm" then
        inbox[#inbox + 1] = { type = "confirm", ok = msg.ok }
      end
    end,
    poll = function()
      local out = inbox
      inbox = {}
      return out
    end,
    close = function() end,
  }
end

local function remoteShot(OnlinePanel, imp, rows)
  local st = OnlinePanel.state(imp)
  local tr = OnlinePanel.tradeState(imp)
  local entry = rows[1]
  if not entry then return end
  tr.mode, tr.chosen = "remote", true
  st.version, st.slotId, st.cartId = entry.version, entry.slotId, entry.cartId
  local Trade = require("src.online.Trade")
  local handle = Trade.openSlot(entry.version, entry.slotId, entry.cartId)
  if not handle then return end
  local remote = Trade.remote(handle, scriptedLink(peerParty(rows[2] or rows[1])),
    { peerName = "BLUE" })
  if not remote then return end
  tr.remote, tr.peerName = remote, "BLUE"
  remote:start()
  remote:update()
  remote:pick(1)
  remote:update()
end

local function tradeablePair(OnlinePanel, imp, pickA, pickB)
  local tr = OnlinePanel.tradeState(imp)
  local a = OnlinePanel.tradeSideView(imp, "a")
  local b = OnlinePanel.tradeSideView(imp, "b")
  local partyA = (a and a.handle and a.handle.party) or {}
  local partyB = (b and b.handle and b.handle.party) or {}
  for i = 1, #partyA do
    for j = 1, #partyB do
      tr.picks.a = pickA or i
      tr.picks.b = pickB or j
      tr.plan, tr.lines, tr.convertLines = nil, nil, nil
      if OnlinePanel.tradeModalPreview(imp) then return true end
      if pickA and pickB then return false end
    end
  end
  return false
end

local function envPick(name)
  local raw = os.getenv(name)
  if not raw or raw == "" then return nil end
  local box, index = raw:match("^box:(%d+):(%d+)$")
  if box then
    return { where = "box", box = tonumber(box), index = tonumber(index) }
  end
  return tonumber(raw)
end

local function localShot(OnlinePanel, imp, want, rows)
  local tr = OnlinePanel.tradeState(imp)
  tr.mode, tr.chosen = "local", true
  local second = rows[2]
  local wantCross = want == "trade-cross" or want:sub(1, 11) == "trade-modal"
    or want == "trade-commit"
  if wantCross and rows[1] then
    for _, row in ipairs(rows) do
      if row.generation ~= rows[1].generation then
        second = row
        break
      end
    end
  end
  OnlinePanel.tradeSetSide(imp, "a", rows[1])
  OnlinePanel.tradeSetSide(imp, "b", second)
  local pickA = envPick("POKEPORT_ONLINE_PICK_A")
  local pickB = envPick("POKEPORT_ONLINE_PICK_B")
  OnlinePanel.tradePick(imp, "a", pickA or 1)
  OnlinePanel.tradePick(imp, "b", pickB or 1)
  if want ~= "trade-modal" and want ~= "trade-modal-done"
      and want ~= "trade-commit" then
    OnlinePanel.tradePreview(imp)
    return
  end
  if not tradeablePair(OnlinePanel, imp, pickA, pickB) then
    print("[shot] no pair this cache can trade: " ..
      tostring(OnlinePanel.tradeState(imp).status))
    return
  end
  if want == "trade-commit" then
    OnlinePanel.tradeModalConfirm(imp)
    return
  end
  if want ~= "trade-modal-done" then return end
  local mo = OnlinePanel.tradeModal(imp)
  if not mo then return end
  mo.view, mo.ok, mo.message = "result", true, "Traded."
  mo.resultLines = OnlinePanel.tradeResultLines(
    OnlinePanel.tradeState(imp).plan, mo.labels)
end

-- ----------------------------------------------------------------- states

local function firstSlot(OnlinePanel, imp)
  local st = OnlinePanel.state(imp)
  local version = OnlinePanel.selectedVersion(imp)
  for _, row in ipairs(OnlinePanel.slotsIn(imp, version, nil)) do
    if row.exists then
      st.slotId = row.id
      return row.id
    end
  end
  return nil
end

local STATES = {}

local function ready(OnlinePanel, imp, picks)
  local st = OnlinePanel.state(imp)
  firstSlot(OnlinePanel, imp)
  st.setupDone = true
  st.team = {}
  local pick = OnlinePanel.readTeamSlot(imp)
  if pick then
    require("src.online.OnlineSprites").prime(
      OnlinePanel.selectedVersion(imp), pick.party)
    for index = 1, math.min(picks or 2, #pick.party) do
      OnlinePanel.toggleTeam(st.team, index)
    end
    st.focusMon = OnlinePanel.refKey(st.team[1])
  end
  OnlinePanel.invalidate(imp)
  return st
end

function STATES.home(OnlinePanel, imp)
  goOnline(OnlinePanel, imp, 6)
  OnlinePanel.home(imp)
end

function STATES.play(OnlinePanel, imp)
  goOnline(OnlinePanel, imp, 6)
  ready(OnlinePanel, imp, 3)
  OnlinePanel.state(imp).note = "first to three"
  OnlinePanel.home(imp)
  OnlinePanel.go(imp, "play")
end

STATES["play-full"] = function(OnlinePanel, imp)
  goOnline(OnlinePanel, imp, 50)
  ready(OnlinePanel, imp, 3)
  OnlinePanel.home(imp)
  OnlinePanel.go(imp, "play")
end

STATES["play-hosting"] = function(OnlinePanel, imp)
  local client = goOnline(OnlinePanel, imp, 6)
  client.room = function() return ROOM end
  ready(OnlinePanel, imp, 3)
  OnlinePanel.home(imp)
  OnlinePanel.go(imp, "play")
  OnlinePanel.refresh(imp)
end

local function wizardAt(OnlinePanel, imp, kind, step, picks)
  goOnline(OnlinePanel, imp, 4)
  ready(OnlinePanel, imp, picks or 2)
  OnlinePanel.home(imp)
  OnlinePanel.go(imp, "play")
  OnlinePanel.startWizard(imp, kind)
  OnlinePanel.wizardTo(imp, step)
  OnlinePanel.refresh(imp)
end

local HOST_STEPS = { "game", "save", "team", "rules", "visibility", "summary" }
for _, step in ipairs(HOST_STEPS) do
  STATES["host-" .. step] = function(O, imp)
    wizardAt(O, imp, "hostBattle", step)
  end
end

local TOUR_STEPS = { "game", "save", "playing", "team", "rules", "shotclock",
                     "spectators", "summary" }
for _, step in ipairs(TOUR_STEPS) do
  STATES["tour-" .. step] = function(O, imp)
    wizardAt(O, imp, "hostTournament", step)
  end
end

STATES["join-summary"] = function(OnlinePanel, imp)
  goOnline(OnlinePanel, imp, 4)
  ready(OnlinePanel, imp, 3)
  OnlinePanel.home(imp)
  OnlinePanel.go(imp, "play")
  OnlinePanel.startJoin(imp, { room = ROOM.room }, { partySize = 3 })
  OnlinePanel.refresh(imp)
end

STATES["join-team"] = function(OnlinePanel, imp)
  STATES["join-summary"](OnlinePanel, imp)
  OnlinePanel.wizardTo(imp, "team")
  OnlinePanel.refresh(imp)
end

STATES["trade-role"] = function(OnlinePanel, imp)
  goOnline(OnlinePanel, imp, 4)
  ready(OnlinePanel, imp, 1)
  OnlinePanel.home(imp)
  OnlinePanel.go(imp, "trade")
  OnlinePanel.tradeState(imp).chosen = true
  OnlinePanel.tradeMode(imp, "remote")
  OnlinePanel.startWizard(imp, "tradeRemote")
  OnlinePanel.wizardTo(imp, "role")
  OnlinePanel.refresh(imp)
end

STATES["trade-summary"] = function(OnlinePanel, imp)
  STATES["trade-role"](OnlinePanel, imp)
  OnlinePanel.wizardTo(imp, "summary")
  OnlinePanel.refresh(imp)
end

STATES["pc-picker"] = function(OnlinePanel, imp)
  wizardAt(OnlinePanel, imp, "hostBattle", "team")
  OnlinePanel.pcOpen(imp)
  OnlinePanel.update(imp, 1 / 60)
  OnlinePanel.refresh(imp)
end

function STATES.room(OnlinePanel, imp)
  local client = goOnline(OnlinePanel, imp, 4)
  client.room = function() return ROOM end
  ready(OnlinePanel, imp, 3)
  OnlinePanel.home(imp)
  OnlinePanel.go(imp, "play")
  OnlinePanel.go(imp, "room")
end

STATES["room-result"] = function(OnlinePanel, imp)
  STATES.room(OnlinePanel, imp)
  OnlinePanel.lastResult = "win"
end

STATES["room-refused"] = function(OnlinePanel, imp)
  local client = goOnline(OnlinePanel, imp, 4)
  client.room = function() return nil end
  ready(OnlinePanel, imp, 3)
  OnlinePanel.home(imp)
  OnlinePanel.go(imp, "play")
  OnlinePanel.go(imp, "room")
  local st = OnlinePanel.state(imp)
  st.status, st.statusOk = "Your game doesn't match the room. " ..
    "(game version differs: the room has crystal, you have red)", false
end

STATES["room-trade"] = function(OnlinePanel, imp)
  local client = goOnline(OnlinePanel, imp, 4)
  client.room = function()
    return { room = ("r%016x"):format(0x7292), host = "me", stage = "waiting",
             intent = "trade", profile = PROFILE,
             players = { { id = "me", name = "RED#417", verified = true } },
             spectators = {} }
  end
  ready(OnlinePanel, imp, 1)
  OnlinePanel.home(imp)
  OnlinePanel.go(imp, "trade")
  OnlinePanel.go(imp, "room")
end

function STATES.watch(OnlinePanel, imp)
  goOnline(OnlinePanel, imp, 14)
  OnlinePanel.home(imp)
  OnlinePanel.go(imp, "watch")
end

function STATES.tournament(OnlinePanel, imp)
  local client = goOnline(OnlinePanel, imp, 4)
  client.tournament = function() return TOUR end
  OnlinePanel.home(imp)
  OnlinePanel.go(imp, "tournament")
end

STATES["tournament-lobby"] = function(OnlinePanel, imp)
  goOnline(OnlinePanel, imp, 4)
  OnlinePanel.home(imp)
  OnlinePanel.go(imp, "tournament")
end

STATES["trade-pc"] = function(OnlinePanel, imp)
  OnlinePanel.home(imp)
  OnlinePanel.go(imp, "trade")
  local tr = OnlinePanel.tradeState(imp)
  tr.mode, tr.chosen = "local", true
  local rows = OnlinePanel.tradeSlots(imp)
  OnlinePanel.tradeSetSide(imp, "a", rows[1])
  OnlinePanel.tradeSetSide(imp, "b", rows[2])
  local view = OnlinePanel.tradeSideView(imp, "a")
  local handle = view and view.handle or nil
  if not handle then return end
  if #OnlinePanel.tradeBoxRows(imp, "a") == 0 and handle.party[1] then
    handle.save.boxes = type(handle.save.boxes) == "table"
      and handle.save.boxes or {}
    handle.save.boxes[2] = { handle.party[1] }
    handle.boxes = handle.save.boxes
  end
  for _, side in ipairs({ "a", "b" }) do
    if OnlinePanel.pcOpen(imp, { side = side }) then
      OnlinePanel.refresh(imp)
      local row = OnlinePanel.pcRows(imp)[1]
      if row then OnlinePanel.pcPick(imp, row) else OnlinePanel.pcClose(imp) end
    end
  end
  OnlinePanel.pcOpen(imp, { side = "a" })
  OnlinePanel.update(imp, 1 / 60)
  OnlinePanel.refresh(imp)
end

STATES["trade-pc-picked"] = function(OnlinePanel, imp)
  STATES["trade-pc"](OnlinePanel, imp)
  OnlinePanel.pcClose(imp)
  OnlinePanel.refresh(imp)
end

STATES["trade-pc-commit"] = function(OnlinePanel, imp)
  OnlinePanel.home(imp)
  OnlinePanel.go(imp, "trade")
  local tr = OnlinePanel.tradeState(imp)
  tr.mode, tr.chosen = "local", true
  local rows = OnlinePanel.tradeSlots(imp)
  local a, b = rows[1], nil
  for _, row in ipairs(rows) do
    if a and row.generation == a.generation
        and not OnlinePanel.sameSlot(row, a) then
      b = row
      break
    end
  end
  if not (a and b) then
    print("[shot] no same-generation pair on this machine")
    return
  end
  OnlinePanel.tradeSetSide(imp, "a", a)
  OnlinePanel.tradeSetSide(imp, "b", b)
  if not OnlinePanel.pcOpen(imp, { side = "a" }) then
    print("[shot] the PC popup would not open")
    return
  end
  OnlinePanel.refresh(imp)
  local want = envPick("POKEPORT_ONLINE_PICK_A")
  local picked
  for _, row in ipairs(OnlinePanel.pcRows(imp)) do
    if not want or (row.ref.box == want.box and row.ref.index == want.index) then
      picked = row
      break
    end
  end
  if not picked then
    print("[shot] nothing in that save's PC")
    OnlinePanel.pcClose(imp)
    return
  end
  print("[shot] from the PC: " .. tostring(picked.label) .. " (" ..
    tostring(picked.source) .. ")")
  OnlinePanel.pcPick(imp, picked)
  OnlinePanel.tradePick(imp, "b", envPick("POKEPORT_ONLINE_PICK_B") or 1)
  OnlinePanel.refresh(imp)
  if not OnlinePanel.tradeModalPreview(imp) then
    print("[shot] preview refused: " .. tostring(tr.status))
    return
  end
  OnlinePanel.tradeModalConfirm(imp)
  print("[shot] trade-pc-commit: " .. tostring(tr.status))
end

function STATES.trade(OnlinePanel, imp)
  OnlinePanel.home(imp)
  OnlinePanel.go(imp, "trade")
  OnlinePanel.tradeState(imp).chosen = false
end

local function armDemo(module, OnlinePanel, imp)
  local ok, err = xpcall(function()
    return require(module)(OnlinePanel, imp)
  end, debug.traceback)
  if not ok then print("[demo] ARM ERROR " .. tostring(err)) end
end

STATES["demo-host"] = function(OnlinePanel, imp)
  return armDemo("tests.drivers.online_demo_host", OnlinePanel, imp)
end

STATES["demo-guest"] = function(OnlinePanel, imp)
  return armDemo("tests.drivers.online_demo_guest", OnlinePanel, imp)
end

return function(OnlinePanel, imp, want)
  if os.getenv("POKEPORT_REDUCE_MOTION") ~= "0" then
    require("src.ui.kit.Transition").reduceMotion = true
  end
  local run = STATES[want]
  if run then return run(OnlinePanel, imp) end
  OnlinePanel.home(imp)
  OnlinePanel.go(imp, "trade")
  local rows = OnlinePanel.tradeSlots(imp)
  if want == "trade-remote" then return remoteShot(OnlinePanel, imp, rows) end
  return localShot(OnlinePanel, imp, want, rows)
end
