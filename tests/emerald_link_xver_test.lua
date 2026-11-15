package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local Cache = require("tests.game3_cache")
local ROOTS = {}
for _, v in ipairs({ "firered", "leafgreen", "emerald" }) do
  ROOTS[v] = Cache.gameDir(v)
  if not ROOTS[v] then
    print("[skip] emerald_link_xver_test: " .. tostring(Cache.reason))
    os.exit(0)
  end
  print("[info] " .. v .. " cache at " .. ROOTS[v])
end

local T = require("tests.harness")
T.verbose = true
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")
local Profile = require("src.core.game3.profile")
Profile.reset()
GameVersion.set("emerald")
Cache.mount("emerald")
require("src.import.gba.versions").select("emerald")
require("src.core.game3.song_ids").select("emerald")
local Pokemon = require("src.core.game3.pokemon")
Pokemon.install(nil)

local function reader(root)
  local cache = Cache.cache(root .. "/data/generated/gba")
  return function(rel) return cache:read(rel) end
end

local Fingerprint = require("src.link.Fingerprint")
local Game3Link = require("src.link.Game3Link")
local Json = require("src.link.Json")
local Wire = require("src.link.Wire")
local HostRules = require("src.core.game3.link.host_rules")

local INPUTS = {}
for v, root in pairs(ROOTS) do INPUTS[v] = Fingerprint.gen3Inputs(reader(root)) end

local KINESIS, NATURE_POWER, SNATCH, PSYCHIC, BODY_SLAM, THUNDERBOLT, CROSS_CHOP = 134, 267, 289, 94, 34, 85, 238
local DIFF = { KINESIS, NATURE_POWER, SNATCH }
local FAMILY = { firered = "frlg", leafgreen = "frlg", emerald = "rse" }

print("[test] 1. the three battle_moves.h rows differ, the rest of the surface does not")
local frM, emM, lgM = INPUTS.firered.moves, INPUTS.emerald.moves, INPUTS.leafgreen.moves
check(frM[NATURE_POWER].accuracy ~= emM[NATURE_POWER].accuracy, "NATURE_POWER accuracy differs FR/EM")
check(frM[KINESIS].flags ~= emM[KINESIS].flags, "KINESIS flags differ FR/EM")
check(frM[SNATCH].flags ~= emM[SNATCH].flags, "SNATCH flags differ FR/EM")
local diffRows = 0
for id, row in pairs(frM) do
  for _, f in ipairs(Fingerprint.GEN3_MOVE_FIELDS) do
    if emM[id] == nil or emM[id][f] ~= row[f] then diffRows = diffRows + 1 break end
  end
end
eq(diffRows, 3, "exactly three move rows differ")
eq(Fingerprint.movesGen3Of(lgM), Fingerprint.movesGen3Of(frM), "LeafGreen's rows are FireRed's")
local function dataOf(v) return { generation = 3, gen3Inputs = INPUTS[v] } end
eq(Fingerprint.coreGen3(dataOf("firered")), Fingerprint.coreGen3(dataOf("emerald")), "the non-move surface is identical")
check(Fingerprint.compute(dataOf("firered"), {}, 3) ~= Fingerprint.compute(dataOf("emerald"), {}, 3),
  "the full fingerprints still differ")

print("[test] 2. the handshake pairs cross-family battles on host rules")
local function hello(v, linkType)
  local s = { version = v, name = "P", trainerId = 1, gender = 0, dex = {}, store = { flags = {}, vars = {} } }
  return Game3Link.hello({ version = v, data = dataOf(v), session = s, save = { player = { name = "P" } } }, linkType,
    { session = s })
end
local LT = Game3Link.LINKTYPE
local frH, emH, lgH = hello("firered", LT.SINGLE_BATTLE), hello("emerald", LT.SINGLE_BATTLE), hello("leafgreen", LT.SINGLE_BATTLE)
local function sane(h) return Wire.sanitize(Json.decode(Json.encode(h))) end
eq(sane(frH).game3.core, frH.game3.core, "Wire carries the core digest")
eq(sane(frH).game3.moves, frH.game3.moves, "Wire carries the moves digest")
local verdict, why, cross, hosted = Game3Link.decideOne(emH, sane(frH), LT.SINGLE_BATTLE)
eq(verdict, "full", "EM sees FR: a battle pairs (" .. tostring(why) .. ")")
eq(cross, true, "cross-family")
eq(hosted, true, "on host rules")
verdict, why, cross, hosted = Game3Link.decideOne(frH, sane(emH), LT.DOUBLE_BATTLE)
eq(verdict, "full", "FR sees EM: a double pairs (" .. tostring(why) .. ")")
eq(hosted, true, "on host rules")
verdict, why, cross, hosted = Game3Link.decideOne(frH, sane(lgH), LT.SINGLE_BATTLE)
eq(verdict, "full", "FR<->LG pairs as today")
eq(hosted, false, "FR<->LG needs no host rules")
eq(cross, false, "FR<->LG is one family")
local modded = sane(emH)
modded.linkModified = true
verdict, why = Game3Link.decideOne(frH, modded, LT.SINGLE_BATTLE)
eq(verdict, "refused", "a link-modifying mod still fails closed")
local otherCore = sane(emH)
otherCore.game3.core = ("0"):rep(16)
verdict, why = Game3Link.decideOne(frH, otherCore, LT.SINGLE_BATTLE)
eq(verdict, "refused", "a different species/ability/item surface is refused")
eq(why, "fingerprint_mismatch", "as a fingerprint mismatch")

print("[test] 3. the host rules block round-trips and is checked")
do
  local block = { version = "firered", rules = Fingerprint.rulesGen3("firered"), moves = Fingerprint.movesGen3Of(frM), rows = {} }
  local ids = {}
  for id in pairs(frM) do ids[#ids + 1] = id end
  table.sort(ids)
  for _, id in ipairs(ids) do block.rows[#block.rows + 1] = HostRules.encodeRow(id, frM[id]) end
  local wired = Wire.sanitize(Json.decode(Json.encode({ type = "game3_battle_setup", hostRules = block, party = {} })))
  local decoded, err = HostRules.decode(wired.hostRules, frH.game3.moves)
  check(decoded ~= nil, "a FireRed block decodes after Wire.sanitize: " .. tostring(err))
  eq(decoded and decoded.rows[NATURE_POWER].accuracy, frM[NATURE_POWER].accuracy, "FireRed NATURE_POWER accuracy arrives")
  local _, bad = HostRules.decode(wired.hostRules, emH.game3.moves)
  eq(bad, "host_rules_rows", "rows that don't match the host hello are refused")
  wired.hostRules.rules = Fingerprint.rulesGen3("emerald")
  _, bad = HostRules.decode(wired.hostRules)
  eq(bad, "host_rules_mismatch", "a rules digest that doesn't match the named game is refused")
end

print("[test] 4. cross-version link battles over the relay")
local H = require("tests.link3_harness")
H.SHARED["src.core.game3.battle.moves"] = nil
local ExtractScripts = require("src.import.gba.extract_scripts")
H.bundle = ExtractScripts.loadBundle(Cache.cache(), ROOTS.emerald .. "/data/generated/gba", { allowIncomplete = true })

local function mon(species, moves)
  return H.legal({ species = species, level = 50, moves = moves, personality = 0,
    ivs = { hp = 20, atk = 20, def = 20, spe = 20, spa = 20, spd = 20 },
    evs = { hp = 0, atk = 0, def = 0, spe = 0, spa = 0, spd = 0 }, item = 0 })
end

local function partyA()
  return H.pack({ mon(65, { KINESIS, NATURE_POWER, SNATCH, PSYCHIC }), mon(143, { NATURE_POWER, KINESIS, SNATCH, BODY_SLAM }) })
end
local function partyB()
  return H.pack({ mon(94, { KINESIS, NATURE_POWER, SNATCH, THUNDERBOLT }), mon(68, { SNATCH, NATURE_POWER, KINESIS, CROSS_CHOP }) })
end

local function moveNum(m)
  if type(m) == "table" then m = m.id or m.move or m.num end
  return tonumber(m)
end

local function observe(w, st)
  local BP = require("src.core.game3.battle.profile")
  local Moves = require("src.core.game3.battle.moves")
  w.seen = w.seen or {
    hostRules = st.hostRules,
    family = BP.of(st).family,
    rulesFrom = BP.of(st).rulesFrom,
    focusPunch = BP.rule(st, "obedienceFocusPunchExempt"),
    npAcc = Moves.get(NATURE_POWER).accuracy,
    kinesisFlags = Moves.get(KINESIS).flags,
    snatchFlags = Moves.get(SNATCH).flags,
  }
end

local function usedMove(w, mon0, slot)
  w.used = w.used or {}
  local id = mon0.moves and moveNum(mon0.moves[slot])
  if id then w.used[id] = true end
end

local function singles(w, st)
  observe(w, st)
  local m = st.player and st.player.mon or {}
  local usable = {}
  for i = 1, 4 do
    if m.moves and m.moves[i] and (tonumber(m.pp and m.pp[i]) or 0) > 0 then usable[#usable + 1] = i end
  end
  local slot = usable[((st.turn or 0) % math.max(1, #usable)) + 1] or 1
  usedMove(w, m, slot)
  w.Ui._pendingCommand = w.Commands.playerAction(st, 1, slot)
end

local function doubles(w, st)
  observe(w, st)
  local sel = w.Battle._dblSel
  if not (sel and sel.active) then return end
  local id = sel.active
  local b = w.State.battler(st, id)
  local m = b and b.mon or {}
  local usable = {}
  for i = 1, 4 do
    if m.moves and m.moves[i] and (tonumber(m.pp and m.pp[i]) or 0) > 0 then usable[#usable + 1] = i end
  end
  local slot = usable[(((st.turn or 0) + id) % math.max(1, #usable)) + 1] or 1
  usedMove(w, m, slot)
  local target = w.State.isPresent(st, 1) and 1 or 3
  w.Ui._pendingCommand = w.Commands.playerAction(st, 1, slot, id, target)
end

local seq = 0
local function world(v, name, tid, gender)
  seq = seq + 1
  local w = H.newWorld(name .. seq, { name = name, trainerId = tid, gender = gender, party = {}, bag = {}, version = v },
    { cacheRoot = ROOTS[v] .. "/data/generated/gba" })
  w.version = v
  w.game.version = v
  w.game.data = { maps = {}, generation = 3, gen3Inputs = INPUTS[v] }
  H.run(w, function()
    require("src.core.GameVersion").set("emerald")
    require("src.core.game3.song_ids").select("emerald")
    require("src.core.game3.battle.moves").loadRomPack()
  end)
  return w
end

local MIRROR = { win = "lose", lose = "win", draw = "draw" }

local function match(hostV, guestV, mode, seed)
  local label = ("%s host vs %s guest (%s)"):format(hostV, guestV, mode)
  print("[info] " .. label)
  local relay = H.relay({ seed = seed, seats = 2, roomSeed = seed })
  local w0 = world(hostV, "HOST", 0x1234, 0)
  local w1 = world(guestV, "GUEST", 0x5678, 1)
  local l0 = H.attachSeat(w0, relay, 0, { mode = mode, myParty = partyA(), profile = { rule = {} } })
  local l1 = H.attachSeat(w1, relay, 1, { mode = mode, myParty = partyB(), profile = { rule = {} } })
  local policy = mode == "double" and doubles or singles
  local frames = 0
  while frames < 30000 do
    frames = frames + 1
    H.step(w0, policy)
    H.step(w1, policy)
    relay:tick()
    if w0.result and w1.result then break end
  end
  local same = hostV == guestV or FAMILY[hostV] == FAMILY[guestV]
    and Fingerprint.movesGen3Of(INPUTS[hostV].moves) == Fingerprint.movesGen3Of(INPUTS[guestV].moves)
  eq(H.run(w0, function() return l0.hostRules end), not same, label .. ": host link hostRules")
  eq(H.run(w1, function() return l1.hostRules end), not same, label .. ": guest link hostRules")
  local setupBytes, carried = 0, false
  for _, row in ipairs(relay.log) do
    if row.msg.type == "game3_battle_setup" then
      setupBytes = math.max(setupBytes, #Json.encode(row.msg))
      if row.seat == 0 and row.msg.hostRules then carried = true end
    end
  end
  eq(carried, not same, label .. ": the host setup carries its rules block only when needed")
  check(setupBytes < 32768, label .. ": setup fits the relay's 32768-byte cap (" .. setupBytes .. ")")
  check(w0.result ~= nil and w1.result ~= nil, label .. ": both seats finished (" .. frames .. " frames)")
  eq(MIRROR[w0.result], w1.result, label .. ": the results mirror (" .. tostring(w0.result) .. "/" .. tostring(w1.result) .. ")")
  eq(H.run(w0, function() return w0.LB.endReason end), nil, label .. ": seat 0 saw no desync")
  eq(H.run(w1, function() return w1.LB.endReason end), nil, label .. ": seat 1 saw no desync")
  local h0 = H.run(w0, function() return w0.LB._myHashes end) or {}
  local h1 = H.run(w1, function() return w1.LB._myHashes end) or {}
  local n, ok = 0, true
  for turn, v in pairs(h0) do
    if h1[turn] ~= nil then
      n = n + 1
      if h1[turn] ~= v then ok = false end
    end
  end
  check(ok and n >= 3, label .. ": every turn's digest matched across seats (" .. n .. " turns)")
  local hostRow = INPUTS[hostV].moves
  for _, w in ipairs({ w0, w1 }) do
    local s = w.seen or {}
    local who = (w == w0) and "host" or "guest"
    eq(s.family, FAMILY[hostV], label .. ": " .. who .. " ran on the host's battle family")
    eq(s.npAcc, hostRow[NATURE_POWER].accuracy, label .. ": " .. who .. " NATURE_POWER accuracy is the host's")
    eq(s.kinesisFlags, hostRow[KINESIS].flags, label .. ": " .. who .. " KINESIS flags are the host's")
    eq(s.snatchFlags, hostRow[SNATCH].flags, label .. ": " .. who .. " SNATCH flags are the host's")
    eq(s.focusPunch, FAMILY[hostV] == "frlg", label .. ": " .. who .. " Focus Punch obedience rule is the host's")
  end
  eq(w1.seen and w1.seen.hostRules, (not same) and hostV or nil, label .. ": guest battle state names the host game")
  for _, id in ipairs(DIFF) do
    check((w0.used or {})[id] and (w1.used or {})[id], label .. ": both seats used move " .. id)
  end
  eq(H.run(w1, function() return require("src.core.game3.battle.moves").get(NATURE_POWER).accuracy end),
    INPUTS[guestV].moves[NATURE_POWER].accuracy, label .. ": the guest's own rows are back after the battle")
end

match("firered", "emerald", "single", 0x4242)
match("emerald", "firered", "single", 0x1717)
match("firered", "emerald", "double", 0x5A5A)
match("leafgreen", "emerald", "single", 0x2323)
match("emerald", "leafgreen", "single", 0x3131)
match("firered", "leafgreen", "single", 0x6464)

print("[test] 5. the host rows decide the outcome (MAGIC_COAT vs KINESIS)")
local MAGIC_COAT, MIRROR_MOVE = 277, 119
local function coatMatch(sabotage)
  local relay = H.relay({ seed = 0x7777, seats = 2, roomSeed = 0x7777 })
  local w0 = world("firered", "HOST", 0x1234, 0)
  local w1 = world("emerald", "GUEST", 0x5678, 1)
  if sabotage then
    H.run(w1, function()
      w1.LB.applyHostRules = function()
        require("src.core.game3.link.host_rules").clear()
        return nil
      end
    end)
  end
  local a = H.pack({ mon(65, { KINESIS, KINESIS, KINESIS, KINESIS }) })
  local b = H.pack({ mon(143, { MAGIC_COAT, MAGIC_COAT, MIRROR_MOVE, BODY_SLAM }) })
  H.attachSeat(w0, relay, 0, { mode = "single", myParty = a, profile = { rule = {} } })
  H.attachSeat(w1, relay, 1, { mode = "single", myParty = b, profile = { rule = {} } })
  local frames = 0
  while frames < 30000 do
    frames = frames + 1
    H.step(w0, singles)
    H.step(w1, singles)
    relay:tick()
    if w0.result and w1.result then break end
  end
  local h0 = H.run(w0, function() return w0.LB._myHashes end) or {}
  local h1 = H.run(w1, function() return w1.LB._myHashes end) or {}
  local n, same = 0, true
  for turn, v in pairs(h0) do
    if h1[turn] ~= nil then
      n = n + 1
      if h1[turn] ~= v then same = false end
    end
  end
  local reason = H.run(w1, function() return w1.LB.endReason end) or H.run(w0, function() return w0.LB.endReason end)
  return same and reason == nil, n, reason
end
local okHost, nHost = coatMatch(false)
check(okHost and nHost >= 1, "on the host's rows both seats agree when KINESIS meets MAGIC_COAT (" .. nHost .. " turns)")
local okOwn, _, why = coatMatch(true)
check(not okOwn, "a guest that ignored the host rows would desync (" .. tostring(why) .. ")")

T.finish("emerald_link_xver")
