local U = require("tests.drivers.util")

local SEAT = tonumber(os.getenv("G3MG_SEAT") or "0") or 0
local SYNC = os.getenv("G3MG_SYNC_DIR") or ((os.getenv("TMPDIR") or "/tmp") .. "/g3crush")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or ".bazinga/BSA/09-23-26-03-gen3online/shots/minigames"
local TAG = "g3mg_crush_seat" .. SEAT
local NAMES = { [0] = "RED", [1] = "BLUE", [2] = "LEAF" }
-- pokefirered/include/constants/items.h:137
local BERRIES = { [0] = 140, [1] = 141, [2] = 142 }

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. TAG .. " " .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function now() return love.timer.getTime() end

local function writeFile(path, text)
  local fh = io.open(path, "w")
  if not fh then return false end
  fh:write(text)
  fh:close()
  return true
end

local function readFile(path)
  local fh = io.open(path, "r")
  if not fh then return nil end
  local text = fh:read("*a")
  fh:close()
  return text
end

return function(game)
  print("PASS " .. TAG .. " driver_started")
  local Client

  local function finish()
    if failures == 0 then
      print("PASS " .. TAG .. " relay_berry_crush")
      love.event.quit(0)
    else
      print("FAIL " .. TAG .. " relay_berry_crush failures=" .. failures)
      love.event.quit(1)
    end
  end

  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = NAMES[SEAT] })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Bag = require("src.core.game3.bag")
  local ArenaData = require("src.online.ArenaData")
  local MG = require("src.core.game3.minigames.common")
  local G = require("src.core.game3.minigames.berry_crush")
  local Sim = G.Sim
  local Pouch = require("src.ui.game3.minigames.berry_crush.pouch")
  Client = require("src.online.Client")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end
  local g3 = Runtime._game or game
  session.name = NAMES[SEAT]
  session.trainerId = 0x1000 + SEAT
  session.berryPowder = 0
  Bag.add(session.bag, BERRIES[SEAT], 2)
  local avatar = { name = NAMES[SEAT], trainerId = session.trainerId, gender = SEAT == 2 and 1 or 0,
    version = "firered" }

  local function waitUntil(pred, seconds)
    local deadline = now() + (seconds or 10)
    while not pred() do
      if now() > deadline then return false end
      U.wait(1)
    end
    return true
  end

  local profile, why = ArenaData.liveProfile3(g3, "g3_link")
  if not result(profile ~= nil, "live Gen 3 profile (" .. tostring(why) .. ")") then return finish() end
  local okC, errC = Client.connect({ name = NAMES[SEAT], profiles = { profile },
    presence = { where = "game", status = "busy" } })
  result(okC, "Client.connect " .. tostring(os.getenv("POKEPORT_RELAY_ADDR")) .. " " .. tostring(errC))
  if not result(waitUntil(function() return Client.state() == "online" end, 10), "online on the relay") then
    return finish()
  end

  local leaderFile = SYNC .. "/leader.txt"
  if SEAT == 0 then
    Client.openGroup("minigame_crush", profile, avatar)
    if not result(waitUntil(function() return Client.group() ~= nil end, 10), "group_open answered") then
      return finish()
    end
    writeFile(leaderFile, Client.you().id)
    local sentStart, accepted = false, {}
    local started = waitUntil(function()
      local g = Client.group()
      for _, p in ipairs(g and g.pending or {}) do
        if not accepted[p.id] then
          accepted[p.id] = true
          Client.acceptGroup(p.id, true)
        end
      end
      if g and #(g.members or {}) >= 3 and not sentStart then
        sentStart = true
        Client.startGroup()
      end
      local room = Client.room()
      return room ~= nil and room.stage == "battling" and room.match ~= nil
    end, 60)
    if not result(started, "three members accepted and the group started") then return finish() end
  else
    local leaderId
    waitUntil(function()
      leaderId = readFile(leaderFile)
      return leaderId ~= nil and leaderId ~= ""
    end, 30)
    if not result(leaderId ~= nil, "found the leader id") then return finish() end
    if SEAT == 2 then
      result(waitUntil(function() return readFile(SYNC .. "/joined1.txt") ~= nil end, 30), "seat 1 joined first")
    end
    Client.joinGroup(leaderId, profile, avatar)
    if SEAT == 1 then
      local accepted = waitUntil(function()
        local g = Client.group()
        for _, m in ipairs(g and g.members or {}) do
          if m.id == Client.you().id then return true end
        end
        return false
      end, 30)
      result(accepted, "seat 1 accepted into the group")
      writeFile(SYNC .. "/joined1.txt", "1")
    end
    local started = waitUntil(function()
      local room = Client.room()
      return room ~= nil and room.stage == "battling" and room.match ~= nil
    end, 60)
    if not result(started, "joined and the group started") then return finish() end
  end

  local room = Client.room()
  result(room.intent == "minigame" and room.origin == "group", "group-origin minigame room")
  local players = {}
  for _, p in ipairs(room.players or {}) do
    players[#players + 1] = { id = p.id, name = p.name, seat = p.seat, trainerId = 0, gender = 0 }
  end
  local exitResult
  MG.launch({ game = "crush", session = Client.roomSession(), seat = Client.seat(), seats = room.seats,
    players = players, seed = room.seed, returnToMap = false,
    onExit = function(r) exitResult = r end })
  local mine = MG.match()
  if not result(mine ~= nil, "MG running Berry Crush") then return finish() end
  result(waitUntil(function() return mine.phase ~= "ready" end, 20), "every seat readied, start received")
  local function sim() return mine.sim end
  local function stage() return sim() and sim().stage end

  local lastTap = 0
  local function tapEvery(interval)
    if now() - lastTap >= interval then
      lastTap = now()
      U.tap(game, "a")
    else
      U.wait(1)
    end
  end

  result(waitUntil(function() return stage() == "ask" and sim().printer and sim().printer.prompt end, 20),
    "Are you ready to BERRY-CRUSH? waits for A")
  U.tap(game, "a")
  result(waitUntil(function() return Pouch.isOpen() end, 20), "the Berry Pouch opened")
  waitUntil(function() return false end, 0.5)
  U.tap(game, "a")
  result(waitUntil(function() return not Pouch.isOpen() end, 5), "picked a berry")
  result(Bag.get(session.bag, BERRIES[SEAT]) == 1, "one berry used")
  result(waitUntil(function() return stage() == "play" end, 40), "berries dropped, lid, countdown, playing")

  if SEAT == 0 then
    local deadline = now() + 20
    while now() < deadline and not (sim().A.tp >= 40) do tapEvery(0.1) end
    result(mine:isLeader(), "seat 0 led the game (" .. tostring(sim().A.tp) .. " presses)")
    print("PASS " .. TAG .. " relay_berry_crush (dropping without a goodbye)")
    love.event.quit(0)
    return
  end

  local migrated = waitUntil(function()
    tapEvery(0.08 + SEAT * 0.03)
    return mine.leader == 1 and mine.epoch > 1
  end, 30)
  result(migrated, "leadership migrated to seat 1 (epoch " .. tostring(mine.epoch) .. ")")
  local function seat0Gone()
    local s = sim()
    for p = 1, s.n do
      if s:seatOf(p) == 0 then return s.A.gone[p] == true end
    end
    return false
  end
  result(waitUntil(function()
    tapEvery(0.08 + SEAT * 0.03)
    return seat0Gone()
  end, 5), "seat 0 is marked gone and its name box is removed")
  if SEAT == 1 then
    result(mine:isLeader(), "seat 1 leads")
    U.still(game, DIR .. "/g3mg_berry_crush_relay_migrated.png")
  end
  local ended = waitUntil(function()
    tapEvery(0.08 + SEAT * 0.03)
    return sim().stage ~= "play" and sim().stage ~= "waitplay"
  end, 60)
  result(ended, "the crusher reached the bottom (stage " .. tostring(sim().stage) .. ")")
  local answered = false
  local done = waitUntil(function()
    local s = sim()
    if s.stage == "yesno" and s.sf > 10 and not answered then
      if SEAT == 1 and s.yesNo == 0 then
        U.tap(game, "down")
      else
        answered = true
        U.tap(game, "a")
      end
    elseif (s.stage == "results" and s.sub == 2 and s.cnt == 0) or (s.printer and s.printer.prompt) then
      tapEvery(0.3)
    else
      U.wait(1)
    end
    return exitResult ~= nil
  end, 90)
  result(done, "results pages, powder, save, play again, then exit (" .. tostring(exitResult) .. ")")
  result(sim().answer == (SEAT == 1 and Sim.ANSWER.NO or Sim.ANSWER.YES), "answered " .. tostring(sim().answer))
  if not mine.result then return finish() end
  local rows = {}
  local res = sim().res or {}
  for p = 1, sim().n do
    rows[#rows + 1] = string.format("%d:%d:%d", p, res.presses and res.presses[p] or -1, res.random and res.random[p] or -1)
  end
  local mineText = table.concat(rows, ",")
  writeFile(SYNC .. "/result" .. SEAT .. ".txt", mineText)
  local other = SEAT == 1 and 2 or 1
  local theirs
  waitUntil(function()
    theirs = readFile(SYNC .. "/result" .. other .. ".txt")
    return theirs ~= nil and theirs ~= ""
  end, 30)
  result(theirs == mineText, "seats 1 and 2 agree on the results (" .. mineText .. ")")
  result((res.powder or 0) > 0 and session.berryPowder == res.powder, "Berry Powder " .. tostring(session.berryPowder))
  result(session.berryCrushPressingSpeeds and session.berryCrushPressingSpeeds[2] == res.speed, "record written")
  result(exitResult == "done", "onExit(done)")
  result(Client.room() == nil, "left the room")
  pcall(Client.disconnect)
  finish()
end
