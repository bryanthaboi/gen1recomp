package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local before = os.getenv("POKEPORT_SYNC_ENGINE_FILE")
if before then package.loaded["src.sync.SyncEngine"] = assert(loadfile(before))() end
local Engine = require("src.sync.SyncEngine")
local State = require("src.sync.SyncState")
local SaveData = require("src.core.SaveData")
local Serializer = require("src.core.SaveSerializer")
local Client = require("src.sync.SyncClient")
local Json = require("src.link.Json")
local T = require("tests.harness").suite("H14 content conflict")

local function copy(v)
  if type(v) ~= "table" then return v end
  local out = {}; for k, x in pairs(v) do out[k] = copy(x) end; return out
end

local function save(version, at)
  local gen = (version == "red" or version == "yellow") and 1
    or (version == "gold" or version == "crystal") and 2 or 3
  return { version = version, generation = gen, player = { name = "ASH" },
    party = { { species = "PIKACHU", level = 5 } }, inventory = { POTION = 1 },
    playTime = gen == 1 and 13561 or { hours = 3, minutes = 46, seconds = 1, frames = 0 },
    pokedex = { owned = {}, caught = {} }, badges = {},
    meta = { playthroughId = "same-id", savedAt = at, sessionStart = at - 100,
      mods = {}, modCount = 0, format = 1, engine = "fixture" } }
end

local function actualEntry(blob, version)
  local names = { "listSlots", "readSlotSource", "loadOptions", "cartsWithSlots" }
  local old = {}; for _, name in ipairs(names) do old[name] = SaveData[name] end
  SaveData.listSlots = function(v) return v == version and { { exists = true, id = "slot1" } } or {} end
  SaveData.readSlotSource = function() return blob end
  SaveData.loadOptions = function() return { playthroughIds = { [version] = { slot1 = "same-id" } } } end
  SaveData.cartsWithSlots = function() return {} end
  local ok, entries = pcall(Engine.defaultSaves().list)
  for _, name in ipairs(names) do SaveData[name] = old[name] end
  assert(ok, entries); assert(#entries == 1); return entries[1]
end

local function pump(e, n) for _ = 1, n or 30 do e:update(0.01) end end

local function scenario(version, opts)
  opts = opts or {}
  local left = opts.left and copy(opts.left) or save(version, 1700000700)
  left.meta.savedAt, left.meta.sessionStart = 1700000700, 1700000600
  local right = copy(left); right.meta.savedAt = 1700000760; right.meta.sessionStart = 1700000660
  if opts.mutate then opts.mutate(right, left) end
  local localBlob = Serializer.encode(left)
  local remoteBlob = opts.raw or Serializer.encode(right)
  local entry = actualEntry(localBlob, version)
  local remoteMeta = copy(entry.meta); remoteMeta.savedAt = 1700000760
  if opts.summary then opts.summary(remoteMeta.summary, entry.meta.summary) end
  local key = State.key(version, "same-id")
  local state = State.defaults(); state.account, state.deviceToken, state.enabled = "fixture", "token", true
  State.setRev(state, key, 7, 1700000500)
  local server = { rev = opts.race and 7 or 9, blob = remoteBlob, meta = remoteMeta }
  local transport = { sent = {}, handles = {}, gets = 0, puts = 0, hold = opts.hold }
  function transport:begin(req)
    self.sent[#self.sent + 1] = req
    local path = req.url:match("^[^?]*"):gsub("^http://memory%.test", "")
    local code, body = 200, {}
    if req.method == "GET" and path == "/sync/state" then
      body = { saves = { [key] = { rev = server.rev, meta = server.meta } } }
    elseif req.method == "GET" and path == "/sync/save" then
      self.gets = self.gets + 1
      if opts.noHandle then return nil, "offline" end
      code = opts.getCode or 200
      body = opts.getReply or { rev = opts.fetchRev or server.rev, meta = server.meta, blob = server.blob }
      if opts.afterGet then opts.afterGet(server, entry) end
    elseif req.method == "PUT" and path == "/sync/save" then
      self.puts = self.puts + 1
      local payload = assert(Json.decode(req.body))
      if opts.race and self.puts == 1 then server.rev = 9 end
      if opts.forceRefusal or (payload.baseRev ~= server.rev and not payload.force) then
        code, body = 409, { rev = server.rev, remoteMeta = server.meta }
      else
        server.blob, server.meta, server.rev = payload.blob, payload.meta, server.rev + 1
        body = { rev = server.rev }
      end
    else error(req.method .. " " .. path) end
    local h = #self.sent
    self.handles[h] = { status = "ok", code = code, body = Json.encode(body),
      pause = (req.method == "GET" and path == "/sync/save") or (opts.holdPut and req.method == "PUT") }
    return h
  end
  function transport:poll(h)
    if self.hold and self.handles[h].pause then return { status = "pending" } end
    return self.handles[h]
  end
  function transport:release(h) self.released = h end
  local writes = {}
  local e = Engine.new({ state = state, transport = transport, baseUrl = "http://memory.test",
    saves = { list = function() return { entry } end, write = function(_, _, blob, mode)
      writes[#writes + 1] = { blob = blob, mode = mode }; return "slot1" end },
    persist = false, now = function() return 1700001000 end })
  e:syncNow(); pump(e)
  return { e = e, server = server, transport = transport, state = state, key = key,
    entry = entry, left = left, right = right, remoteBlob = remoteBlob, localBlob = localBlob, writes = writes }
end

local function noForce(r, label)
  local forced = false
  for _, req in ipairs(r.transport.sent) do
    if req.method == "PUT" and Json.decode(req.body).force then forced = true end
  end
  T.eq(forced, false, label .. " never forces automatically")
end

local function conflict(r, label, puts)
  T.eq(r.e.phase, "conflict", label .. " asks for a choice")
  T.eq(#r.e.conflicts, 1, label .. " keeps one conflict")
  T.eq(#r.state.pendingConflicts, 1, label .. " tracks the unresolved conflict")
  T.eq(r.server.blob, r.remoteBlob, label .. " preserves remote bytes")
  T.eq(r.transport.puts, puts or 0, label .. " stops automatic writes")
  T.eq(r.transport.gets, 1, label .. " fetches real remote contents")
  noForce(r, label)
end

local function equal(r, label, puts)
  T.eq(r.e.phase, "idle", label .. " finishes without a prompt")
  T.eq(#r.e.conflicts, 0, label .. " has no conflict")
  T.eq(r.server.blob, r.remoteBlob, label .. " preserves the remote serialized copy")
  T.eq(r.transport.puts, puts or 0, label .. " performs no replacement PUT")
  T.eq(r.transport.gets, 1, label .. " verifies remote contents")
  T.eq(State.rev(r.state, r.key), 9, label .. " adopts the verified revision")
  T.eq(State.stamp(r.state, r.key), 1700000700, label .. " remembers the compared local stamp")
  T.eq(#r.writes, 0, label .. " needs no local write")
  noForce(r, label)
end

for _, v in ipairs({ "red", "yellow", "gold", "crystal", "emerald" }) do
  conflict(scenario(v, { mutate = function(s) s.party[1].species = "EEVEE"; s.inventory.POTION = 2 end }), v .. " same-summary party/items")
  conflict(scenario(v, { mutate = function(s) s.inventory.POTION = 2 end,
    summary = function(s) s.name = "BLUE"; s.badges = 8 end }), v .. " same-minute different summary")
  conflict(scenario(v, { race = true, mutate = function(s) s.inventory.POTION = 2 end }), v .. " 409 content fork", 1)
  equal(scenario(v), v .. " write/session timestamps only")
  equal(scenario(v, { summary = function(s) s.name = "BLUE"; s.badges = 8 end }), v .. " equal contents despite stale summary")
  equal(scenario(v, { race = true }), v .. " 409 equal contents", 1)
  conflict(scenario(v, { mutate = function(s)
    if type(s.playTime) == "number" then s.playTime = s.playTime + 1 else s.playTime.seconds = 2 end
  end }), v .. " one gameplay second")
end

local function produced(version)
  local Version = require("src.core.GameVersion")
  local oldFS, oldVersion = love.filesystem, Version.get()
  local Space, Dataset, Extract, oldBundle, oldOverride, oldRoot, oldNativeRoot
  if version == "emerald" then
    local Cache = require("tests.game3_cache")
    local cacheRoot = Cache.root("emerald", "scripts/scripts.lua")
    if not cacheRoot then
      print("[skip] H14 actual-produced Emerald controls: " .. tostring(Cache.reason))
      return nil
    end
    Space = require("src.core.game3.scripting.space")
    Dataset = require("src.core.game3.dataset")
    Extract = require("src.import.gba.extract_island1")
    oldBundle, oldOverride = Space.bundle, Dataset.cacheRootOverride
    oldRoot, oldNativeRoot = Extract.CACHE_ROOT, Extract.NATIVE_ROOT
    Space.bundle, Dataset.cacheRootOverride = nil, cacheRoot
  end
  local files = {}
  love.filesystem = {
    write = function(path, body) files[path] = body; return true end,
    read = function(path) return files[path] end,
    remove = function(path) files[path] = nil; return true end,
    getInfo = function(path) return files[path] and { type = "file" } or nil end,
    createDirectory = function() return true end,
  }
  SaveData.resetSlotState(); Version.set(version)
  local ok, value = pcall(function()
    local s, writer
    if version == "gold" or version == "silver" or version == "crystal" then
      local Gen2 = require("src.core.gen2.Save")
      s, writer = Gen2.newGame({ playerName = "ASH", trainerId = 1 }), Gen2.save
    else
      local Schema = require("src.core.game3.save_schema_firered")
      s = Schema.toSaveTable(Schema.newGame({ version = version, name = "ASH", trainerIdLower = 1, rngSeed = 1 }))
      if Space then
        T.check(Space.bundle and Space.bundle.fromCache == true, "Emerald actual producer executes the isolated imported bundle")
        T.check(Space.bundle.scripts.EventScript_ResetAllMapFlags ~= nil, "Emerald actual reset entrypoint comes from that bundle")
      end
      SaveData.setActiveSlot(version, assert(SaveData.createSlot(version)))
      writer = SaveData.save
    end
    s.meta = SaveData.buildMeta({}, { playthroughId = "same-id" }, 1700000600)
    T.check(writer(s), version .. " actual save writer succeeds in memory")
    local slot = SaveData.activeSlot(version) or "legacy"
    local blob = assert(SaveData.readSlotSource(version, slot))
    local decoded = assert(SaveData.decode(blob))
    T.eq(decoded.meta.playthroughId, "same-id", version .. " saved-file identity survives actual writer")
    if decoded.generation == 3 then
      T.eq(decoded.player, nil, version .. " native save has root name rather than Gen1 player")
      T.eq(decoded.name, "ASH", version .. " native root trainer name survives")
      T.check(type(decoded.bag) == "table", version .. " native pocket bag survives")
    else
      T.eq(decoded.player.name, "ASH", version .. " Gen2 player survives actual writer")
      T.check(type(decoded.savedAt) == "number", version .. " Gen2 writer stamps legacy top-level timestamp")
    end
    return decoded
  end)
  love.filesystem = oldFS; SaveData.resetSlotState(); Version.set(oldVersion)
  if Space then
    Space.bundle, Dataset.cacheRootOverride = oldBundle, oldOverride
    Extract.CACHE_ROOT, Extract.NATIVE_ROOT = oldRoot, oldNativeRoot
    Dataset.invalidateManifestCache()
    T.eq(Space.bundle, oldBundle, "Emerald producer restores the previous script bundle")
    T.eq(Dataset.cacheRootOverride, oldOverride, "Emerald producer restores the previous cache override")
    T.eq(Extract.CACHE_ROOT, oldRoot, "Emerald producer restores the previous extract root")
    T.eq(Extract.NATIVE_ROOT, oldNativeRoot, "Emerald producer restores the previous native root")
    T.eq(Version.get(), oldVersion, "Emerald producer restores the previous edition")
  end
  assert(ok, value); return value
end

for _, version in ipairs({ "gold", "silver", "crystal", "firered", "leafgreen", "emerald" }) do
  local value = produced(version)
  if value then
    equal(scenario(version, { left = value }), version .. " actual producer equality")
    equal(scenario(version, { left = value, race = true }), version .. " actual producer 409 equality", 1)
    conflict(scenario(version, { left = value, mutate = function(s)
      if s.generation == 3 then s.money = s.money + 1 else s.player.money = s.player.money + 1 end
    end }), version .. " actual producer same-summary money fork")
    conflict(scenario(version, { left = value, race = true, mutate = function(s)
      if s.generation == 3 then s.money = s.money + 1 else s.player.money = s.player.money + 1 end
    end }), version .. " actual producer 409 money fork", 1)
  end
end

do
  local nested = string.rep("{next=", 140) .. "{}" .. string.rep("}", 140)
  local raw = 'return {player={name="ASH"},future=' .. nested .. '}'
  T.eq(SaveData.decode(raw), nil, "actual restricted decoder rejects nesting beyond128")
  conflict(scenario("red", { raw = raw }), "excessively nested remote save")
  T.eq(SaveData.decode('return {player={name="ASH"},future=player}'), nil,
    "actual restricted decoder rejects references rather than producing cycles")
end

for _, change in ipairs({
  { "unknown field", function(s) s.future = { value = 1 } end },
  { "mods", function(s) s.meta.mods = { { id = "other", version = "1" } } end },
  { "format", function(s) s.meta.format = 2 end },
  { "engine", function(s) s.meta.engine = "other" end },
  { "cart", function(s) s.meta.cartId = "other" end },
  { "identity", function(s) s.meta.playthroughId = "other" end },
  { "raw cartridge bytes", function(s) s.rawImport = "bytes" end },
  { "nested savedAt", function(s) s.party[1].savedAt = 5 end },
  { "top sessionStart", function(s) s.sessionStart = 5 end },
  { "createdAt", function(s) s.meta.createdAt = 5 end },
  { "typed value", function(s) s.inventory.POTION = "1" end },
}) do conflict(scenario("red", { mutate = change[2] }), change[1]) end

equal(scenario("gold", { mutate = function(s, left) s.savedAt = 3; left.savedAt = 5 end }), "legacy Gen2 write timestamp")
conflict(scenario("red", { mutate = function(s) s.party[1].species = "EEVEE" end,
  summary = function(a,b) a.timeText = nil; b.timeText = nil end }), "unknown displayed time")

for _, raw in ipairs({ "return {}", "return {player=false}", "return {player={name='ASH'},meta=false}",
  "return os.execute('echo forbidden')", "return {player={name='ASH'}} trailing", "" }) do
  conflict(scenario("red", { raw = raw }), "invalid remote blob " .. #raw)
end
do
  local maximum = Client.MAX_BLOB; Client.MAX_BLOB = 1024
  local r = scenario("red", { raw = string.rep(" ", Client.MAX_BLOB + 1) })
  Client.MAX_BLOB = maximum
  conflict(r, "remote blob over the configured size boundary")
end
for _, opts in ipairs({ { noHandle = true }, { getCode = 503 }, { getReply = {} },
  { fetchRev = 8 }, { fetchRev = 0 }, { fetchRev = 9.5 } }) do
  conflict(scenario("red", opts), "unverified remote response")
end

do
  local r = scenario("red", { raw = "return {inventory={POTION=1},badges={},pokedex={caught={},owned={}}," ..
    'party={[1]={level=5,species="PIKACHU"}},player={name="ASH"},generation=1,version="red",playTime=13561,' ..
    'meta={engine="fixture",format=1,modCount=0,mods={},playthroughId="same-id",savedAt=1700000760,sessionStart=1700000660}}' })
  equal(r, "different serialization ordering")
end

for _, choice in ipairs({ "local", "remote", "both" }) do
  local r = scenario("red", { mutate = function(s) s.inventory.POTION = 2 end })
  if #r.e.conflicts > 0 then
    T.check(r.e:resolveConflict(r.key, choice), choice .. " explicit choice remains available")
    pump(r.e)
    T.eq(r.e.phase, "idle", choice .. " finishes")
    if choice ~= "local" then
      T.eq(r.writes[1].blob, r.remoteBlob, choice .. " preserves exact remote data")
      T.eq(r.writes[1].mode, choice == "both" and "new" or "replace", choice .. " local write mode")
    end
    if choice ~= "remote" then
      T.eq(r.server.blob, r.localBlob, choice .. " uploads only after user selection")
      T.eq(Json.decode(r.transport.sent[#r.transport.sent].body).force, true, choice .. " explicit force remains")
    end
  else T.check(false, choice .. " divergent contents must first be presented") end
end

do
  local r = scenario("red", { hold = true })
  T.eq(r.transport.gets, 1, "comparison can remain pending")
  local later = save("red", 1700000800); later.inventory.POTION = 3
  r.entry.blob = Serializer.encode(later); r.entry.meta.savedAt = 1700000800
  r.transport.hold = false; pump(r.e)
  T.eq(State.stamp(r.state, r.key), 1700000700, "late local save cannot change the compared snapshot stamp")
  r.e:syncNow(); pump(r.e)
  T.eq(r.transport.puts, 1, "later local save remains detectable on the next sync")
  T.eq(State.stamp(r.state, r.key), 1700000800, "later save is tracked only after its own ordinary upload")
end
do
  local opts = { holdPut = true }
  local r = scenario("red", opts)
  local nextSave = save("red", 1700000800); nextSave.inventory.POTION = 3
  r.entry.blob = Serializer.encode(nextSave); r.entry.meta.savedAt = 1700000800
  r.transport.hold = true; r.e:syncNow(); pump(r.e)
  T.eq(r.transport.puts, 1, "ordinary upload can remain pending")
  nextSave.inventory.POTION = 4; nextSave.meta.savedAt = 1700000900
  r.entry.blob = Serializer.encode(nextSave); r.entry.meta.savedAt = 1700000900
  r.transport.hold = false; pump(r.e)
  T.eq(State.stamp(r.state, r.key), 1700000800, "pending upload adopts only its own captured stamp")
  T.eq(Serializer.decode(r.server.blob).inventory.POTION, 3, "pending upload carries only its captured contents")
  r.e:syncNow(); pump(r.e)
  T.eq(r.transport.puts, 2, "save made during pending upload remains detectable")
  T.eq(State.stamp(r.state, r.key), 1700000900, "later snapshot gets its own revision stamp")
end
do
  local r = scenario("red", { afterGet = function(server)
    server.rev = 10; server.blob = Serializer.encode(save("red", 1700000900))
    server.meta = copy(server.meta); server.meta.savedAt = 1700000900
  end })
  T.eq(State.rev(r.state, r.key), 9, "adopted revision is the one whose contents were fetched")
  T.eq(r.transport.puts, 0, "remote advancement after verification is never force-overwritten")
  r.e:syncNow(); pump(r.e)
  T.eq(#r.writes, 1, "the later remote revision remains detectable")
  T.eq(State.rev(r.state, r.key), 10, "next sync adopts the later downloaded revision")
end
do
  local r = scenario("red", { hold = true })
  r.e:cancel(); r.transport.hold = false; pump(r.e)
  T.eq(State.rev(r.state, r.key), 7, "cancelled comparison cannot adopt a revision")
  T.eq(r.transport.puts, 0, "cancelled comparison cannot write")
end
do
  local r = scenario("red", { mutate = function(s) s.inventory.POTION = 2 end, forceRefusal = true })
  if #r.e.conflicts > 0 then r.e:resolveConflict(r.key, "local"); pump(r.e) end
  T.eq(r.transport.puts, 1, "a refused explicit force is not retried")
  T.eq(r.transport.gets, 1, "a refused explicit force does not enter automatic equality handling")
  T.eq(r.e.phase, "conflict", "explicit force refusal remains a conflict")
end
T.finish()
