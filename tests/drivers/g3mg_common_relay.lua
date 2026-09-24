local U = require("tests.drivers.util")

local SEAT = tonumber(os.getenv("G3MG_SEAT") or "0") or 0
local SYNC = os.getenv("G3MG_SYNC_DIR") or ((os.getenv("TMPDIR") or "/tmp") .. "/g3mg")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or ".bazinga/BSA/09-23-26-03-gen3online/shots/minigames"
local TAG = "g3mg_seat" .. SEAT
local NAMES = { [0] = "RED", [1] = "BLUE", [2] = "LEAF" }
local CHARMANDER = 4

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

local Stub = { MIN = 2, MAX = 5, END_FRAME = 900 }
Stub.__index = Stub

function Stub.loadArt() return {} end

function Stub.new(ctx)
  return setmetatable({ ctx = ctx, f = 0, scores = { 0, 0, 0, 0, 0 }, last = { 0, 0, 0, 0, 0 },
    presses = 0, becameLeader = 0 }, Stub)
end

function Stub:leaderStep(inputs, present)
  for s = 0, 4 do
    local i = inputs[s + 1]
    if present[s + 1] and type(i) == "number" and i > self.last[s + 1] then
      self.scores[s + 1] = self.scores[s + 1] + (i - self.last[s + 1])
      self.last[s + 1] = i
    end
  end
  self.f = self.f + 1
end

function Stub:snapshot()
  return { f = self.f, sc = { unpack(self.scores) }, la = { unpack(self.last) } }
end

function Stub:applySnapshot(s)
  self.f = s.f
  for i = 1, 5 do
    self.scores[i] = s.sc[i] or 0
    self.last[i] = s.la[i] or 0
  end
end

function Stub:localInput(input)
  if input and input:wasPressed("a") then self.presses = self.presses + 1 end
  return self.presses
end

function Stub:predict(i) self.predicted = i end

function Stub:becomeLeader(last)
  if last then self:applySnapshot(last) end
  self.becameLeader = self.becameLeader + 1
end

function Stub:update() end

function Stub:draw()
  local FrlgFont = require("src.ui.game3.frlg_font")
  local y = 16
  for _, p in ipairs(self.ctx.players) do
    FrlgFont.draw(string.format("%s %d", p.name or "?", self.scores[p.seat + 1] or 0), 24, y,
      { colors = p.seat == self.ctx.seat and FrlgFont.COLOR.GREEN or FrlgFont.COLOR.WHITE })
    y = y + 16
  end
  FrlgFont.draw(tostring(self.f), 200, 136, { colors = FrlgFont.COLOR.WHITE })
end

function Stub:finished() return self.f >= Stub.END_FRAME end

function Stub:results()
  local results, powder = {}, {}
  for _, p in ipairs(self.ctx.players) do
    local sc = self.scores[p.seat + 1]
    results[#results + 1] = { seat = p.seat, score = sc, stats = { presses = sc } }
    powder[#powder + 1] = { seat = p.seat, amount = sc }
  end
  return { results = results, powder = powder }
end

function Stub.applyResults(session, res, mySeat)
  local Records = require("src.ui.game3.minigame_records")
  for _, r in ipairs(res.results) do
    if r.seat == mySeat then Records.updatePokemonJump(session, r.score, r.score, 0) end
  end
end

return function(game)
  print("PASS " .. TAG .. " driver_started")
  local Client

  local function finish()
    if failures == 0 then
      print("PASS " .. TAG .. " relay_minigame")
      love.event.quit(0)
    else
      print("FAIL " .. TAG .. " relay_minigame failures=" .. failures)
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
  local Party = require("src.core.game3.party")
  local ArenaData = require("src.online.ArenaData")
  local MG = require("src.core.game3.minigames.common")
  Client = require("src.online.Client")
  package.loaded[MG.GAMES.jump] = Stub

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end
  local g3 = Runtime._game or game
  session.name = NAMES[SEAT]
  session.trainerId = 0x1000 + SEAT
  session.party = {}
  Party.giveMon(session, CHARMANDER, 10 + SEAT)
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
    Client.openGroup("minigame_jump", profile, avatar)
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
  result(room.leader == 0, "relay leader seat 0")
  result(Client.seat() == SEAT, "seat " .. tostring(Client.seat()))
  local players = {}
  for _, p in ipairs(room.players or {}) do
    players[#players + 1] = { id = p.id, name = p.name, seat = p.seat, trainerId = 0, gender = 0 }
  end
  local exitResult
  MG.partySlot = 0
  MG.launch({ game = "jump", session = Client.roomSession(), seat = Client.seat(), seats = room.seats,
    players = players, seed = room.seed, partySlot = 0, returnToMap = false,
    onExit = function(r) exitResult = r end })
  local mine = MG.match()
  if not result(mine ~= nil, "MG running") then return finish() end
  result(waitUntil(function() return mine.phase ~= "ready" end, 20), "every seat readied, start received")
  local names = {}
  for _, p in ipairs(mine.startPlayers or {}) do names[#names + 1] = p.name end
  print("[driver] " .. TAG .. " start players: " .. table.concat(names, ","))
  result(#(mine.startPlayers or {}) == 3, "three players in game3_mg_start")
  result(waitUntil(function() return mine.phase == "play" end, 10), "countdown done, playing")
  if SEAT == 1 then
    U.wait(30)
    U.shot(game, DIR .. "/g3mg_common_relay_play.png")
  end

  local tapUntil = function(pred, seconds)
    local deadline = now() + seconds
    local n = 0
    while not pred() and now() < deadline do
      n = n + 1
      if n % (4 + SEAT) == 0 then U.tap(game, "a") else U.wait(1) end
    end
    return pred()
  end

  if SEAT == 0 then
    tapUntil(function() return false end, 4)
    result(mine:isLeader(), "seat 0 led the game")
    print("PASS " .. TAG .. " relay_minigame (dropping without a goodbye)")
    love.event.quit(0)
    return
  end

  local migrated = tapUntil(function() return mine:isLeader() or mine.leader == 1 and mine.epoch > 1 end, 20)
  result(migrated, "leadership migrated to seat 1 after the leader went offline")
  result(mine.leader == 1, "leader is seat 1 (epoch " .. tostring(mine.epoch) .. ")")
  if SEAT == 1 then
    result(mine.sim.becameLeader == 1, "seat 1 ran sim:becomeLeader")
    U.shot(game, DIR .. "/g3mg_common_relay_migrated.png")
  end
  local done = tapUntil(function() return mine.phase == "results" or mine.phase == "done" or mine.phase == "error" end, 40)
  result(done and mine.result ~= nil, "results arrived (phase " .. tostring(mine.phase) .. " why " .. tostring(mine.why) .. ")")
  if not mine.result then return finish() end
  local rows = {}
  for _, r in ipairs(mine.result.results) do
    rows[#rows + 1] = string.format("%d:%d:%d", r.seat, r.score, r.stats and r.stats.presses or -1)
  end
  local mineJson = table.concat(rows, ",")
  writeFile(SYNC .. "/result" .. SEAT .. ".json", mineJson)
  local other = SEAT == 1 and 2 or 1
  local theirs
  waitUntil(function()
    theirs = readFile(SYNC .. "/result" .. other .. ".json")
    return theirs ~= nil and theirs ~= ""
  end, 20)
  result(theirs == mineJson, "seats 1 and 2 agree on the results")
  local myScore = 0
  for _, r in ipairs(mine.result.results) do if r.seat == SEAT then myScore = r.score end end
  result(myScore > 0, "scored " .. myScore)
  result((session.berryPowder or 0) == myScore, "Berry Powder " .. tostring(session.berryPowder))
  result(session.pokemonJumpRecords and session.pokemonJumpRecords.bestJumpScore == myScore, "record written")
  result(waitUntil(function() return exitResult ~= nil end, 10), "MG exited: " .. tostring(exitResult))
  result(exitResult == "done", "onExit(done)")
  result(Client.room() == nil, "left the room")
  pcall(Client.disconnect)
  finish()
end
