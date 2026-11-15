package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.harness")
local bit = require("bit")
local SaveData = require("src.core.SaveData")
local GameVersion = require("src.core.GameVersion")
require("src.core.game3.profile").reset()
GameVersion.set("emerald")
local Util = require("src.core.game3.rse.frontier.util")
local Story = require("src.core.game3.scripting.natives_frontier_story")
local Sections = require("src.core.game3.save_sections")
local function copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = copy(x) end
  return out
end
local oldPersist = Util.persist
local function protectedSave(sess, persist)
  Util.persist = persist
  local ok, result = pcall(Util.saveGameFrontier, sess)
  Util.persist = oldPersist
  return ok, result
end
local function state()
  return { version = "emerald", name = "RELOAD", trainerId = 12345, secretId = 4321,
    map = "EM_SLATEPORT_CITY_BATTLE_TENT_CORRIDOR", x = 3, y = 5, party = {}, flags = {}, vars = {},
    dynamicWarp = { map = "EM_SLATEPORT_CITY_BATTLE_TENT_LOBBY", x = 7, y = 8, warpId = 255 },
    continueGameWarp = { map = "EM_ROUTE110", x = 10, y = 11 }, specialSaveWarpFlags = 0xA1 }
end
local original = { { personality = 123, nickname = "ORIGINAL", ivs = { hp = 17 }, evs = { atk = 23 } } }
local rentals = { { personality = 987, nickname = "RENTAL", ivs = { hp = 3 }, evs = { atk = 252 } } }
local s = state()
s.party = copy(original)
Story.savePlayerParty(s)
s.party = copy(rentals)
local exported = {}
Sections.fields(Util.SAVE_FIELDS).export(s, exported)
local decoded = assert(SaveData.decode(SaveData.encode(exported)))
local restored = {}
Sections.fields(Util.SAVE_FIELDS).restore(decoded, restored)
T.same(restored.savedPlayerParty, original, "registered section preserves complete original backup through SaveData serializer")
for _, fail in ipairs({ false, "throw" }) do
  s = state()
  s.party, s.savedPlayerParty = copy(rentals), copy(original)
  local ok, result = protectedSave(s, function()
    T.same(s.party, original, "persistence sees original party")
    T.same(s.continueGameWarp, s.dynamicWarp, "persistence sees captured lobby destination")
    T.eq(s.specialSaveWarpFlags, 0xA1, "persistence sets only continue bit")
    if fail == "throw" then error("2638 injected write failure") end
    return false
  end)
  T.check(not ok or result == false, "failed persistence cannot report success")
  T.same(s.party, rentals, "failed persistence restores live rentals")
  T.same(s.savedPlayerParty, original, "failed persistence preserves original backup")
  T.eq(s.specialSaveWarpFlags, 0xA0, "failed persistence clears continue bit and preserves other bits")
  T.same(s.continueGameWarp, s.dynamicWarp, "failed persistence leaves inactive source destination bytes")
end
for _, missing in ipairs({ "dynamicWarp", "x", "savedPlayerParty" }) do
  s = state()
  s.party, s.savedPlayerParty = copy(rentals), copy(original)
  if missing == "x" then s.dynamicWarp.x = nil else s[missing] = nil end
  local before, calls = copy(s), 0
  local ok, result = protectedSave(s, function() calls = calls + 1 return true end)
  T.check(ok and result == false and calls == 0, "incomplete " .. missing .. " is rejected before writing")
  T.same(s, before, "incomplete " .. missing .. " leaves concrete session state intact")
end
local function emeraldRoot()
  local explicit = os.getenv("POKEPORT_GBA_CACHE")
  if explicit and explicit ~= "" then return explicit end
  local home, id = os.getenv("HOME"), os.getenv("POKEPORT_IDENTITY")
  if not (home and id and id ~= "") then return nil end
  for _, base in ipairs({ home .. "/Library/Application Support/LOVE/", home .. "/.local/share/love/" }) do
    local root = base .. id .. "/emerald/data/generated/gba"
    local f = io.open(root .. "/rse/frontier/manifest.lua", "rb")
    if f then f:close() return root end
  end
  return nil
end
local cacheRoot = emeraldRoot() or require("tests.game3_cache").root("emerald", "rse/frontier/manifest.lua")
local hasCache = cacheRoot ~= nil
if hasCache then
  require("src.core.game3.dataset").cacheRootOverride = cacheRoot
  require("src.import.gba.versions").select("emerald")
  local C = require("src.core.game3.constants").of("emerald")
  require("src.core.game3.pokemon").install(nil)
  local D = Util.D
  local Rse = require("src.core.game3.rse.init")
  local Runtime = require("src.core.game3.runtime")
  local Schema = require("src.core.game3.save_schema_firered")
  local Tents = require("src.core.game3.rse.frontier.tents")
  local Factory = require("src.core.game3.rse.frontier.factory")
  local ctx = { specialVars = { [0x8005] = 2 } }
  function ctx:getVar(id) return self.specialVars[id] or 0 end
  function ctx:setVar(id, value) self.specialVars[id] = value end
  local oldGet = Runtime.getSession
  Runtime.getSession = function() return s end
  original = {}
  local names = { "SPECIES_SWAMPERT", "SPECIES_BLAZIKEN", "SPECIES_SCEPTILE", "SPECIES_METAGROSS", "SPECIES_SALAMENCE", "SPECIES_ZIGZAGOON" }
  for i, name in ipairs(names) do
    local m = D.createMon(C:require("species", name), 35 + i, 10 + i, 200000 + i * 37, 12345,
      { otName = "RELOAD", moves = {} })
    D.setMoves(m, { C:require("moves", "MOVE_TACKLE"), C:require("moves", "MOVE_PROTECT") })
    D.setEvs(m, { i * 7, i * 9, i * 11, i * 13, i * 15, i * 17 })
    m.nickname, m.otSecretId, m.heldItem = "KEEP" .. i, 4321, C:require("items", "ITEM_ORAN_BERRY")
    m.ivs.hp, m.pp[1], m.friendship, m.markings = i + 4, i + 2, 100 + i, i
    require("src.core.game3.save_mon").normalize(m)
    Schema.ensureMonBall(m)
    original[i] = m
  end
  love = love or require("tests.love_stub")
  local oldFs, files, writeFault = SaveData.portableFs, {}, nil
  SaveData.portableFs = function()
    return {
      getInfo = function(n) return files[n] and { type = "file" } or nil end,
      read = function(n) return files[n] end,
      write = function(n, body)
        if writeFault and n == SaveData.saveFilename("emerald") .. ".tmp" then
          if writeFault == "throw" then error("2638 injected filesystem failure") end
          return false, "2638 injected filesystem failure"
        end
        files[n] = body
        return true
      end,
      remove = function(n) files[n] = nil return true end,
      createDirectory = function() return true end,
    }
  end
  local function roundtrip(sess)
    assert(SaveData.save(Schema.toSaveTable(sess)))
    return assert(SaveData.load("emerald"))
  end
  local function fresh()
    s = state()
    s.bag = require("src.core.game3.bag").new()
    s.party = copy(original)
    s.dex = { [1] = { seen = true, owned = true } }
    s.storage = require("src.core.game3.storage").new()
    Util.newGame(s)
    require("src.core.game3.scripting.space").store = { flags = s.flags, vars = s.vars }
    Rse.setVar("VAR_FRONTIER_FACILITY", D.FACILITY.FACTORY, s)
    Rse.setVar("VAR_FRONTIER_BATTLE_MODE", D.MODE.SINGLES, s)
    return s
  end
  fresh()
  s.specialSaveWarpFlags = 0xA0
  local ordinary = Schema.fromSaveTable(roundtrip(s))
  T.same(ordinary.party, original, "ordinary Emerald save preserves all original mon values")
  T.eq(ordinary.map, s.map, "ordinary save stays at current location")
  T.eq(ordinary.savedPlayerParty, nil, "ordinary and legacy saves do not invent a backup")
  s.map, s.x, s.y = s.dynamicWarp.map, 7, 8
  Tents.init(s)
  Story.savePlayerParty(s)
  s.frontier.lvlMode = D.LVL.TENT
  require("src.core.game3.rng").SeedRng(0x2638)
  Tents.generateRentalMons(s)
  Tents.generateOpponentMons(s)
  ctx.specialVars[0x8005] = 0
  Factory.setPlayerAndOpponentParties(ctx, s)
  rentals = copy(s.party)
  for _, m in ipairs(rentals) do
    require("src.core.game3.save_mon").normalize(m)
    Schema.ensureMonBall(m)
  end
  s.party = copy(rentals)
  s.map, s.x, s.y = "EM_SLATEPORT_CITY_BATTLE_TENT_CORRIDOR", 3, 5
  s.frontier.curChallengeBattleNum = 1
  local dex, storage = copy(s.dex), copy(s.storage)
  local direct = Schema.fromSaveTable(roundtrip(s))
  T.same(direct.party, rentals, "direct engine save retains active rentals")
  T.same(direct.savedPlayerParty, original, "direct engine save retains six full original identities and traits")
  Story.loadPlayerParty(direct)
  T.same(direct.party, original, "direct continue completion restores exact original six mons in order")
  T.same(direct.dex, dex, "rental reload leaves dex unchanged")
  T.same(direct.storage, storage, "rental reload leaves storage unchanged")
  if direct.savedPlayerParty then direct.savedPlayerParty[1].ivs.hp = 99 end
  T.eq(direct.party[1].ivs.hp, original[1].ivs.hp, "restored party and backup are not aliases")
  local disk
  Util.persist = function() disk = roundtrip(s) return true end
  ctx.specialVars[0x8005] = Util.CHALLENGE_STATUS.PAUSED
  T.check(Tents.save(ctx, s), "real Tent REST save succeeds")
  Util.persist = oldPersist
  T.same(disk.party, original, "REST disk party contains originals")
  T.same(disk.continueGameWarp, s.dynamicWarp, "REST disk continue destination is captured lobby")
  T.eq(bit.band(disk.specialSaveWarpFlags, 1), 1, "REST disk has continue bit")
  T.same(disk.frontier.rentalMons, s.frontier.rentalMons, "REST keeps saved rental data")
  T.eq(disk.frontier.curChallengeBattleNum, 1, "REST keeps challenge battle counter")
  T.same(s.party, rentals, "successful REST restores live rental party")
  T.eq(s.specialSaveWarpFlags, 0xA0, "successful REST clears live bit only")
  s = Schema.fromSaveTable(disk)
  T.eq(s.map, "EM_SLATEPORT_CITY_BATTLE_TENT_LOBBY", "REST continue resumes lobby")
  T.eq(s.x, 7, "REST continue keeps lobby x")
  T.eq(s.y, 8, "REST continue keeps lobby y")
  Story.savePlayerParty(s)
  ctx.specialVars[0x8005] = 0
  Factory.setPlayerAndOpponentParties(ctx, s)
  for _, m in ipairs(s.party) do
    require("src.core.game3.save_mon").normalize(m)
    Schema.ensureMonBall(m)
  end
  T.same(s.party, rentals, "real corridor resume rebuilds the same rentals")
  Story.loadPlayerParty(s)
  T.same(s.party, original, "REST resume completion restores exact original six mons")
  for i, name in ipairs({ "tents", "factory", "tower", "palace", "arena", "dome" }) do
    fresh()
    s.map, s.x, s.y = "EM_SLATEPORT_CITY_BATTLE_TENT_LOBBY", i + 1, i + 5
    require("src.core.game3.rse.frontier." .. name).init(s)
    local expected = { map = s.map, x = s.x, y = s.y, warpId = 255 }
    T.same(s.dynamicWarp, expected, name .. " initializer captures exact entry coordinates")
    s.map, s.x, s.y = "EM_SLATEPORT_CITY_BATTLE_TENT_CORRIDOR", 1, 2
    s.savedPlayerParty = copy(original)
    local ok, result = protectedSave(s, function() disk = roundtrip(s) return true end)
    T.check(ok and result, name .. " shared save succeeds")
    T.same(disk.continueGameWarp, expected, name .. " save uses initial location rather than current room")
    T.eq(s.specialSaveWarpFlags, 0xA0, name .. " save preserves other warp bits")
  end
  fresh()
  s.party, s.savedPlayerParty = copy(rentals), copy(original)
  local staleWarp, currentWarp = copy(s.dynamicWarp), copy(s.continueGameWarp)
  local common, calls = Util.saveGameFrontier, 0
  Util.saveGameFrontier = function() error("Pike must save in place") end
  Util.persist = function() calls = calls + 1 disk = roundtrip(s) return true end
  ctx.specialVars[0x8005] = Util.CHALLENGE_STATUS.PAUSED
  local ok, result = pcall(require("src.core.game3.rse.frontier.pike").save, ctx, s)
  Util.persist, Util.saveGameFrontier = oldPersist, common
  T.check(ok and result and calls == 1, "Pike invokes in-place persistence only")
  if calls == 1 then
    T.same(disk.party, rentals, "Pike writes active challenge party without original swap")
    T.same(disk.continueGameWarp, currentWarp, "Pike does not manufacture continue destination")
    T.same(disk.dynamicWarp, staleWarp, "Pike ignores stale unrelated dynamic warp")
    T.eq(disk.map, s.map, "Pike saves current map")
    T.eq(disk.x, s.x, "Pike saves current x")
    T.eq(disk.y, s.y, "Pike saves current y")
    T.eq(disk.frontier.challengePaused, 1, "Pike writes paused challenge state")
    T.eq(disk.specialSaveWarpFlags, 0xA1, "Pike preserves preexisting warp flags")
  end
  local Vm = require("src.core.game3.scripting.vm")
  local Adapters = require("src.core.game3.scripting.adapters")
  local Field = require("src.core.game3.field")
  local Natives = require("src.core.game3.scripting.natives")
  local Game3 = require("src.core.Game3")
  local oldGame, oldMod = Runtime._game, Runtime._mod
  Natives.bind("emerald")
  local nativeSaves = {
    { "CallSlateportTentFunction", Tents.SLATEPORT.SAVE, "VAR_TEMP_0" },
    { "CallFallarborTentFunction", Tents.FALLARBOR.SAVE, "VAR_TEMP_0" },
    { "CallVerdanturfTentFunction", Tents.VERDANTURF.SAVE, "VAR_TEMP_0" },
    { "CallBattleFactoryFunction", Factory.FUNC.SAVE, "VAR_TEMP_CHALLENGE_STATUS" },
    { "CallBattleTowerFunc", require("src.core.game3.rse.frontier.tower").FUNC.SAVE, "VAR_TEMP_0" },
    { "CallBattleArenaFunction", require("src.core.game3.rse.frontier.arena").FUNC.SAVE, "VAR_TEMP_CHALLENGE_STATUS" },
    { "CallBattlePalaceFunction", require("src.core.game3.rse.frontier.palace").FUNC.SAVE, "VAR_TEMP_CHALLENGE_STATUS" },
    { "CallBattleDomeFunction", require("src.core.game3.rse.frontier.dome").FUNC.SAVE, "VAR_TEMP_CHALLENGE_STATUS" },
  }
  for _, native in ipairs(nativeSaves) do
    for _, failure in ipairs({ "false", "throw", "missingWarp", "missingParty" }) do
      fresh()
      s.savedPlayerParty, s.party = copy(original), copy(rentals)
      s.specialSaveWarpFlags = 0xA0
      s.frontier.challengeStatus, s.frontier.challengePaused = 1, 0
      local tempId = assert(Rse.varId(native[3], s))
      Rse.setVar(tempId, 73, s)
      roundtrip(s)
      local diskBefore = files[SaveData.saveFilename("emerald")]
      if failure == "missingWarp" then s.dynamicWarp.x = nil
      elseif failure == "missingParty" then s.savedPlayerParty = nil
      else writeFault = failure end
      local frontierBefore, partyBefore, backupBefore = copy(s.frontier), copy(s.party), copy(s.savedPlayerParty)
      Runtime._game, Runtime._mod = { session = s, phase = "field", saveGame = Game3.saveGame }, nil
      local closed, finishMessage, sounds, unfreezes, logs = 0, nil, 0, 0, {}
      local adapters = Adapters.stub({})
      adapters.listActiveLocalIds = function() return { 1 } end
      adapters.snapshotLocal = function() return { frozen = false } end
      adapters.freezeLocal = function() Field.locked = true end
      adapters.unfreezeLocal = function() unfreezes = unfreezes + 1 end
      adapters.log = function(msg) logs[#logs + 1] = msg end
      adapters.playSe = function() sounds = sounds + 1 end
      adapters.closeMessage = function() closed = closed + 1 end
      adapters.openMessageAsync = function(text, done)
        T.check(type(text) == "string" and text:find("saved", 1, true) ~= nil, native[1] .. " presents concrete save error")
        finishMessage = done
      end
      local vm = Vm.new({ version = "emerald", store = Rse.store(), adapters = adapters, scripts = { save = {
        { op = "lockall" },
        { op = "setvar", 0x8004, native[2] },
        { op = "setvar", 0x8005, 2 },
        { op = "special", id = C:require("specials", native[1]) },
        { op = "playse", C:require("songs", "SE_SAVE") },
        { op = "setvar", 0x8004, Util.FUNC.SOFT_RESET },
        { op = "special", id = C:require("specials", "CallFrontierUtilFunc") },
        { op = "end" },
      } } })
      T.check(vm:start("save"), native[1] .. " real VM starts")
      T.check(vm:isRunning() and finishMessage ~= nil, native[1] .. " failure awaits message dismissal")
      T.eq(sounds, 0, native[1] .. " failure skips save-success sound")
      T.eq(Runtime._game.softResetRequested, nil, native[1] .. " failure skips frontier reset")
      T.same(s.frontier, frontierBefore, native[1] .. " failure rolls back all challenge save fields")
      T.eq(Rse.var(tempId, s), 73, native[1] .. " failure restores original temporary var")
      T.same(s.party, partyBefore, native[1] .. " failure restores current live rentals")
      T.same(s.savedPlayerParty, backupBefore, native[1] .. " failure preserves concrete original backup")
      T.eq(files[SaveData.saveFilename("emerald")], diskBefore, native[1] .. " failure leaves last successful save intact")
      if finishMessage then finishMessage() end
      vm:tick()
      T.check(not vm:isRunning() and vm.ctx.status == "shutdown", native[1] .. " failure ends through normal VM halt")
      T.check(not Field.locked and unfreezes == 1 and vm.ctx.lockKind == nil, native[1] .. " failure unfreezes objects and unlocks field")
      T.check(closed >= 2 and vm.ctx.messageOpen == false, native[1] .. " failure closes error message")
      T.eq(sounds, 0, native[1] .. " dismissed error still skips save-success sound")
      T.eq(Runtime._game.softResetRequested, nil, native[1] .. " dismissed error still skips reset")
      T.eq(#logs, 0, native[1] .. " known SAVE failure never reports an unported native")
      writeFault = nil
    end
    fresh()
    s.savedPlayerParty, s.party = copy(original), copy(rentals)
    s.specialSaveWarpFlags = 0xA0
    Runtime._game, Runtime._mod = { session = s, phase = "field", saveGame = Game3.saveGame }, nil
    local sounds = 0
    local adapters = Adapters.stub({})
    adapters.playSe = function() sounds = sounds + 1 end
    local vm = Vm.new({ version = "emerald", store = Rse.store(), adapters = adapters, scripts = { save = {
      { op = "setvar", 0x8004, native[2] },
      { op = "setvar", 0x8005, 2 },
      { op = "special", id = C:require("specials", native[1]) },
      { op = "playse", C:require("songs", "SE_SAVE") },
      { op = "setvar", 0x8004, Util.FUNC.SOFT_RESET },
      { op = "special", id = C:require("specials", "CallFrontierUtilFunc") },
      { op = "end" },
    } } })
    T.check(vm:start("save") and not vm:isRunning(), native[1] .. " successful save runs synchronous script tail")
    T.eq(sounds, 1, native[1] .. " success reaches sentinel save sound")
    T.eq(Runtime._game.softResetRequested, true, native[1] .. " success reaches real reset special")
    T.same(s.party, rentals, native[1] .. " success keeps live rentals")
    T.same(SaveData.load("emerald").party, original, native[1] .. " success writes exact original party")
  end
  Runtime._game, Runtime._mod = oldGame, oldMod
  Runtime.getSession, SaveData.portableFs = oldGet, oldFs
else
  print("SKIP ROM assertions: Emerald cache unavailable; section serialization and failure cleanup still exercised")
end
T.finish("emerald_tent_save_reload_2638_test")
