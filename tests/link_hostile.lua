-- Hostile link traffic: every message type this build reads, with every
-- field replaced by every wrong Lua type, driven through the real Session
-- choke point and then into the real consumers (trade session, link battle,
-- spectator battle, tournament screen -- including its draw).
--
-- The three payloads from the "How to Troll Pokemon Players" writeup are
-- rows in the table below: action.slot as a table, hash.parts as a number,
-- and pick.index out of range.
--
-- Self-contained; run directly or via run_link_tests.lua:
--   luajit tests/link_hostile.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local Data = require("src.core.Data")
if not Data.pokemon then Data:load() end
local Font = require("src.render.Font")
Font.load(Data)

local Input = require("src.core.Input")
Input:init()

local Json = require("src.link.Json")
local LinkBattle = require("src.link.LinkBattle")
local Net = require("src.link.Net")
local Pokemon = require("src.pokemon.Pokemon")
local Protocol = require("src.link.Protocol")
local Session = require("src.link.Session")
local Tournament = require("src.link.Tournament")
local Wire = require("src.link.Wire")

local failures = 0
local function check(cond, msg)
  if cond then
    print("ok   " .. msg)
  else
    failures = failures + 1
    print("FAIL " .. msg)
  end
end

-- ---------------------------------------------------------------- corpus

local HOSTILE = { {}, { 1, 2, 3 }, { type = "x" }, 0, -1, 123, 1.5,
                  math.huge, "s", "", true, false }

local function copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, val in pairs(v) do out[k] = copy(val) end
  return out
end

local packedMon = Protocol.packMon(Pokemon.new(Data, "PIKACHU", 12))

local TEMPLATES = {
  { type = "hello", protocol = 2, name = "RED", mode = "battle",
    engineVersion = "1.0.0", apiVersion = "1", generation = 1,
    fingerprint = "abc123", linkModified = false,
    mods = { { id = "demo", version = "1.0", affectsLink = true } } },
  { type = "records", pokemon = { PIKACHU = "a" }, moves = { TACKLE = "b" },
    heldItems = { BERRY = "c" } },
  { type = "party", mons = { copy(packedMon) }, seed = 1234, forceLevel = 50 },
  { type = "pick", index = 1 },
  { type = "confirm", ok = true },
  { type = "action", kind = "move", slot = 1, index = 1 },
  { type = "hash", turn = 1, value = "v",
    parts = { actives = "a", volatile = "b", bench = "c" } },
  { type = "replace", index = 1 },
  { type = "bye" },
  { type = "forfeit" },
  { type = "spectate", side = "host",
    msg = { type = "action", kind = "move", slot = 1 } },
  { type = "hosted", code = "ABCDEF" },
  { type = "paired" },
  { type = "peer_gone" },
  { type = "join_error", reason = "not_found" },
  { type = "tournament_hosted", code = "ABCDEF", turnLimit = 6,
    requiredPartySize = 3, minLevel = 5, maxLevel = 50, forceLevel = 50,
    participating = true },
  { type = "tournament_host_error", reason = "party_ineligible",
    requiredPartySize = 3, minLevel = 5, maxLevel = 50 },
  { type = "tournament_join_error", reason = "party_ineligible",
    requiredPartySize = 3, minLevel = 5, maxLevel = 50 },
  { type = "tournament_roster", players = { "RED", "BLUE" },
    spectators = { "GREEN" }, turnLimit = 6, requiredPartySize = 3,
    minLevel = 5, maxLevel = 50, forceLevel = 50 },
  { type = "bracket_update", tournament = { code = "ABCDEF", turnLimit = 6,
    requiredPartySize = 3, minLevel = 5, maxLevel = 50, status = "active",
    round = 1, champion = "RED",
    rounds = { { round = 1, matches = { { a = "RED", b = "BLUE",
      winner = "RED", bye = false, state = "live" } } } } } },
  { type = "match_start", opponent = "BLUE", round = 1, turnLimit = 6,
    role = "host" },
  { type = "match_start_spectate", round = 1, playerHost = "RED",
    playerGuest = "BLUE" },
  { type = "tournament_bye", round = 1 },
  { type = "tournament_over", champion = "RED" },
  { type = "a_type_this_build_has_never_heard_of", payload = { n = 1 } },
}

local NESTED = {
  { "hash", { "parts", "actives" } },
  { "party", { "mons", 1 } },
  { "party", { "mons", 1, "dvs" } },
  { "party", { "mons", 1, "moves" } },
  { "party", { "mons", 1, "moves", 1 } },
  { "party", { "mons", 1, "nickname" } },
  { "party", { "mons", 1, "level" } },
  { "party", { "mons", 1, "otId" } },
  { "hello", { "mods", 1 } },
  { "spectate", { "msg" } },
  { "spectate", { "msg", "slot" } },
  { "bracket_update", { "tournament", "rounds" } },
  { "bracket_update", { "tournament", "rounds", 1, "matches" } },
  { "bracket_update", { "tournament", "rounds", 1, "matches", 1, "a" } },
  { "tournament_roster", { "players", 1 } },
}

local function templateFor(kind)
  for _, t in ipairs(TEMPLATES) do
    if t.type == kind then return t end
  end
end

local function setPath(root, path, value)
  local node = root
  for i = 1, #path - 1 do
    node = node[path[i]]
    if type(node) ~= "table" then return false end
  end
  node[path[#path]] = value
  return true
end

local corpus = {}
local function add(msg) corpus[#corpus + 1] = msg end

add(false); add(true); add(123); add("string"); add({}); add({ 1, 2, 3 })
add({ type = 5 }); add({ type = {} }); add({ type = true })
add({ type = ("x"):rep(4096) })

for _, template in ipairs(TEMPLATES) do
  add(copy(template))
  for key in pairs(template) do
    if key ~= "type" then
      for _, bad in ipairs(HOSTILE) do
        local m = copy(template)
        m[key] = copy(bad)
        add(m)
      end
      local missing = copy(template)
      missing[key] = nil
      add(missing)
    end
  end
end

for _, row in ipairs(NESTED) do
  local template = templateFor(row[1])
  for _, bad in ipairs(HOSTILE) do
    local m = copy(template)
    if setPath(m, row[2], copy(bad)) then add(m) end
  end
  local m = copy(template)
  if setPath(m, row[2], nil) then add(m) end
end

print(("hostile corpus: %d messages"):format(#corpus))

-- ---------------------------------------------------------------- session

local function fakeTransport(inbox)
  local transport = { paired = true, closed = false, error = nil,
                      inbox = inbox, sent = {} }
  function transport:update() end
  function transport:poll()
    local messages = self.inbox
    self.inbox = {}
    return messages
  end
  function transport:send(m) table.insert(self.sent, m) end
  function transport:close() self.closed = true end
  return transport
end

local transport = fakeTransport(copy(corpus))
local session = Session.new(transport, { role = "guest", kind = "link" })
local okUpdate, updateErr = pcall(session.update, session)
check(okUpdate, "the whole hostile corpus goes through Session without throwing"
      .. (okUpdate and "" or (": " .. tostring(updateErr))))
check(session:getFailure() == nil,
      "a hostile peer cannot latch a terminal failure on the session")
check(session:getStatus() == "paired", "the session is still usable afterwards")
local survivors = session:poll()
check(#survivors > 0, "well-formed messages still get through")
check(session.dropped > 0, "malformed messages are counted as dropped")

for _, msg in ipairs(survivors) do
  if type(msg.type) ~= "string" then
    check(false, "every delivered message has a string type")
    break
  end
end
check(true, "every delivered message has a string type")

for _, msg in ipairs(survivors) do
  local ok = pcall(Json.encode, msg)
  if not ok then
    check(false, "every delivered message is still encodable (" .. msg.type .. ")")
    break
  end
end
check(true, "every delivered message is still encodable")

-- ---------------------------------------------------------------- consumers

local function makeFakeGame(species, name)
  local save = require("src.core.SaveData").newGame()
  save.player.name = name or "RED"
  table.insert(save.party, Pokemon.new(Data, species, 20))
  local stack = { list = {} }
  function stack:push(s, ...)
    table.insert(self.list, s)
    if s.enter then s:enter(...) end
  end
  function stack:pop() return table.remove(self.list) end
  function stack:top() return self.list[#self.list] end
  function stack:update(dt)
    local t = self:top()
    if t and t.update then t:update(dt) end
  end
  return { data = Data, input = Input, stack = stack, save = save }
end

do
  local crashed
  for _, msg in ipairs(survivors) do
    local party = { Pokemon.new(Data, "KADABRA", 30) }
    local t = Protocol.TradeSession.new(Data, party)
    local ok, err = pcall(function()
      t:handle({ type = "party", mons = Protocol.packParty({
        Pokemon.new(Data, "MACHOKE", 32) }) })
      t:handle(msg)
      t:pick(1)
      t:handle(msg)
      t:confirm(true)
      t:handle(msg)
      if t.stage == "done" then t:apply(nil) end
    end)
    if not ok then crashed = ("%s: %s"):format(tostring(msg.type), tostring(err)) end
    if crashed then break end
  end
  check(not crashed, "the trade session survives every hostile message"
        .. (crashed and (": " .. crashed) or ""))
end

do
  local party = { Pokemon.new(Data, "KADABRA", 30) }
  local t = Protocol.TradeSession.new(Data, party)
  t:handle({ type = "party",
             mons = Protocol.packParty({ Pokemon.new(Data, "MACHOKE", 32) }) })
  t:pick(1)
  t:handle(Wire.sanitize({ type = "pick", index = 0 }))
  t:confirm(true)
  t:handle(Wire.sanitize({ type = "confirm", ok = true }))
  check(t.stage ~= "done", "an out-of-range pick never reaches a committed trade")
  check(t.stage == "cancelled", "...it cancels the trade instead")
end

do
  local gameA = makeFakeGame("CHARIZARD", "RED")
  local gameB = makeFakeGame("BLASTOISE", "BLUE")
  local netA, netB = Net.loopbackPair()
  local battleA = LinkBattle.newHost(gameA, netA, {
    myParty = Protocol.packParty(gameA.save.party),
    theirParty = Protocol.packParty(gameB.save.party),
    theirName = "BLUE", seed = 4242 })
  gameA.stack:push(battleA)
  local crashed
  for _, msg in ipairs(survivors) do
    table.insert(netA.inbox, copy(msg))
    local ok, err = pcall(function()
      Input.pressed = {}
      gameA.stack:update(1 / 60)
    end)
    if not ok then
      crashed = ("%s: %s"):format(tostring(msg.type), tostring(err))
      break
    end
  end
  check(not crashed, "a link battle survives every hostile message"
        .. (crashed and (": " .. crashed) or ""))
end

do
  local gameSpec = makeFakeGame("RATTATA", "WATCHER")
  local specInbox = {}
  local specNet = {
    closed = false,
    update = function() end,
    poll = function()
      local msgs = specInbox
      specInbox = {}
      return msgs
    end,
    send = function() end,
    close = function() end,
  }
  local battle = LinkBattle.newSpectator(gameSpec, specNet, {
    hostParty = Protocol.packParty(makeFakeGame("CHARIZARD").save.party),
    guestParty = Protocol.packParty(makeFakeGame("BLASTOISE").save.party),
    hostName = "RED", guestName = "BLUE", seed = 99 })
  gameSpec.stack:push(battle)
  local crashed
  for _, msg in ipairs(corpus) do
    for _, side in ipairs({ "host", "guest", 5, {} }) do
      local wrapped = Wire.sanitize({ type = "spectate", side = side,
                                      msg = copy(msg) })
      if wrapped then table.insert(specInbox, wrapped) end
    end
    local ok, err = pcall(function()
      Input.pressed = {}
      gameSpec.stack:update(1 / 60)
    end)
    if not ok then
      crashed = tostring(err)
      break
    end
  end
  check(not crashed, "a spectator battle survives every hostile envelope"
        .. (crashed and (": " .. crashed) or ""))
end

do
  local game = makeFakeGame("PIKACHU", "RED")
  local exits = 0
  local t = setmetatable({
    game = game,
    stage = "bracket",
    index = 1,
    settingsIndex = 1,
    settings = { turnLimit = 6, requiredPartySize = 3, minLevel = "ANY",
                 maxLevel = "ANY", forceLevel = "ANY", participating = true },
    roster = {},
    spectatorRoster = {},
    isCreator = false,
    net = { send = function() end, close = function() end,
            take = function() return nil end,
            poll = function() return {} end,
            hasPending = function() return false end },
  }, Tournament)
  t.exitWith = function(self) exits = exits + 1 end
  local crashed
  for _, msg in ipairs(survivors) do
    local ok, err = pcall(function()
      t:handleMessage(msg)
      t:draw()
    end)
    if not ok then
      crashed = ("%s: %s"):format(tostring(msg.type), tostring(err))
      break
    end
    if type(t.roster) ~= "table" or type(t.spectatorRoster) ~= "table" then
      crashed = ("%s left a non-table roster"):format(tostring(msg.type))
      break
    end
  end
  check(not crashed, "the tournament screen survives every hostile message"
        .. (crashed and (": " .. crashed) or ""))
end

-- ---------------------------------------------------------------- json
do
  local deep = ("["):rep(4096) .. ("]"):rep(4096)
  local value, err = Json.decode(deep)
  check(value == nil and err ~= nil, "a deeply nested document is refused")
  local long = '{"type":"hello","name":"' .. ("x"):rep(1024) .. '"}'
  check(Json.decode(long, 256) == nil, "a document past the caller's cap is refused")
  check(Json.decode(long) ~= nil, "...and the cap is opt-in for other callers")
end

-- ---------------------------------------------------------------- net caps
do
  local n = Net.new()
  n.rxBuf = ("x"):rep(Net.MAX_LINE + 1)
  n:drainLines()
  check(n.closed and n.error ~= nil,
        "a peer that never sends a newline closes the connection")
  check(#n.rxBuf == 0, "...and the buffer is released")
end

print(("\nlink hostile: %d messages, %d failures"):format(#corpus, failures))
assert(failures == 0, failures .. " hostile-input failure(s)")
return true
