package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.harness")
local GV = require("src.core.GameVersion")
require("src.core.game3.profile").reset()
GV.set("emerald")
local Dataset = require("src.core.game3.dataset")
local function emeraldRoot()
  local explicit = os.getenv("POKEPORT_GBA_CACHE")
  if explicit and explicit ~= "" then return explicit end
  local home, id = os.getenv("HOME"), os.getenv("POKEPORT_IDENTITY")
  if not (home and id and id ~= "") then return nil end
  for _, base in ipairs({ home .. "/Library/Application Support/LOVE/", home .. "/.local/share/love/" }) do
    local root = base .. id .. "/emerald/data/generated/gba"
    local f = io.open(root .. "/rse/contest_gfx/manifest.lua", "rb")
    if f then f:close() return root end
  end
  return nil
end
local cacheRoot = emeraldRoot() or require("tests.game3_cache").root("emerald", "rse/contest_gfx/manifest.lua")
if not cacheRoot then
  print("[skip] Emerald cache required: emerald_frontier_contest_save_test")
  os.exit(0)
end
Dataset.cacheRootOverride = cacheRoot
love = require("tests.love_stub")
require("src.import.gba.versions").select("emerald")
local C = require("src.core.game3.constants").of("emerald")
require("src.core.game3.pokemon").install(nil)
local Schema = require("src.core.game3.save_schema_firered")
local SaveData = require("src.core.SaveData")
local Space = require("src.core.game3.scripting.space")
local Runtime = require("src.core.game3.runtime")
local Game3 = require("src.core.Game3")
local Rse = require("src.core.game3.rse.init")
local Util = require("src.core.game3.rse.frontier.util")
local Story = require("src.core.game3.scripting.natives_frontier_story")
local D = require("src.core.game3.rse.frontier.trainers")
local Pike = require("src.core.game3.rse.frontier.pike")
local Pyramid = require("src.core.game3.rse.frontier.pyramid")
local Natives = require("src.core.game3.scripting.natives")
local NC = require("src.core.game3.scripting.natives_contest")
local Contest = require("src.core.game3.rse.contest")
local CU = require("src.core.game3.rse.contest_util")
local Results = require("src.ui.game3.rse.contest_results")
local Field = require("src.core.game3.field")
local Vm = require("src.core.game3.scripting.vm")
local Adapters = require("src.core.game3.scripting.adapters")
local function copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = copy(x) end
  return out
end
local files, failure, s, saveCalls, observed = {}, nil, nil, 0, nil
local oldFs, oldGet, oldGame, oldMod, oldPersist = SaveData.portableFs, Runtime.getSession, Runtime._game, Runtime._mod, Util.persist
SaveData.portableFs = function()
  return {
    getInfo = function(n) return files[n] and { type = "file" } or nil end,
    read = function(n) return files[n] end,
    write = function(n, body)
      if failure == "false" and n == SaveData.saveFilename("emerald") .. ".tmp" then return false, "injected write failure" end
      if failure == "throw" and n == SaveData.saveFilename("emerald") .. ".tmp" then error("injected write exception") end
      files[n] = body return true
    end,
    remove = function(n) files[n] = nil return true end,
    createDirectory = function() return true end,
  }
end
Runtime.getSession = function() return s end
local function fresh(map)
  failure, saveCalls, observed = nil, 0, nil
  Util.persist = oldPersist
  s = Schema.newGame({ version = "emerald", name = "SAVE", trainerId = 12345 })
  s.map, s.x, s.y = map or "EM_CONTEST_HALL", 7, 5
  s.party = {}
  for i, name in ipairs({ "SPECIES_PIKACHU", "SPECIES_SWAMPERT", "SPECIES_METAGROSS", "SPECIES_ZIGZAGOON" }) do
    s.party[i] = D.createMon(C:require("species", name), 30 + i, 10 + i, 123450 + i, 12345, { otName = "SAVE", moves = {} })
    s.party[i].nickname = "KEEP" .. i
  end
  Story.savePlayerParty(s)
  s.party = { copy(s.party[3]), copy(s.party[2]), copy(s.party[1]) }
  s.dynamicWarp = { map = "EM_LILYCOVE_CITY_CONTEST_LOBBY", warpId = 255, x = 17, y = 4 }
  s.continueGameWarp = { map = "EM_ROUTE110", x = 10, y = 11, warpId = 255 }
  s.specialSaveWarpFlags = 0xA0
  Space.store = { flags = s.flags, vars = s.vars }
  Runtime._mod = nil
  Runtime._game = { session = s, phase = "field", saveGame = function(game)
    saveCalls = saveCalls + 1
    local result = Game3.saveGame(game)
    observed = copy(game.save)
    return result
  end }
  return s
end
local function roundtrip(save)
  return Schema.fromSaveTable(assert(SaveData.decode(SaveData.encode(save))))
end
local function context()
  local ctx = { specialVars = {} }
  function ctx:getVar(id) return self.specialVars[id] or 0 end
  function ctx:setVar(id, value) self.specialVars[id] = value end
  return ctx
end
local function frame(screen, a)
  screen:frame({ new = a and { a = true } or {}, held = {}, rep = {} })
end
local function untilFrame(screen, predicate)
  for _ = 1, 250 do
    if predicate() then return true end
    frame(screen)
  end
  return predicate()
end
local function makeContest(link)
  local c = Contest.new({ category = 1, rank = 0, playerIndex = 0, linkFlags = link and 1 or 0, rng = function() return 1 end })
  for i = 0, 3 do
    c.mons[i] = Contest.copyMon(c.data.opponents[i])
    c.round1[i], c.round2[i], c.totals[i], c.standings[i] = 80 - i * 10, 40 - i * 5, 120 - i * 15, i
  end
  c.mons[0] = Contest.buildContestMon(CU.contestantFromMon(s.party[1], s))
  if link then c.link = { exchange = function() return nil end } end
  return c
end

fresh("EM_LILYCOVE_CITY_CONTEST_LOBBY")
s.x, s.y = 17, 4
NC.partyIndex = 0
local oldYield, oldCL, oldLink = Natives.yieldHost, package.loaded["src.core.game3.link.contest_link"], package.loaded["src.core.game3.link.init"]
Natives.yieldHost = function() return true end
local code, aborted = 0, 0
local transport = { RESULT = { OK = 0, ERROR = 1 }, FLAG = { IS_LINK = 1, IS_WIRELESS = 2 },
  newSession = function(_, opts) return { flags = opts.flags, abort = function() aborted = aborted + 1 end } end,
  flagsFor = require("src.core.game3.link.contest_link").flagsFor }
transport.beginTransfer = function(opts)
  return { session = opts.session, contest = { category = 1, rank = 0 }, step = function() return code end }
end
package.loaded["src.core.game3.link.contest_link"] = transport
package.loaded["src.core.game3.link.init"] = { link = { isOpen = function() return true end, isReady = function() return true end } }
for _, result in ipairs({ 0, 1 }) do
  code = result
  local ctx = context()
  local before = copy(s.dynamicWarp)
  T.eq(NC.contestLinkTransfer({ ctx = ctx, adapters = {} }), true, "actual contest transfer native schedules polling")
  T.eq(ctx.nativePoll(), true, "actual contest transfer poll finishes")
  if result == 0 then
    T.same(s.dynamicWarp, { map = s.map, warpId = 255, x = 17, y = 4 }, "link success captures exact producer location")
    T.same(roundtrip(Schema.toSaveTable(s)).dynamicWarp, s.dynamicWarp, "producer destination survives SaveData and schema restore")
  else
    T.same(s.dynamicWarp, before, "link failure retains previous destination")
    T.eq(aborted, 1, "failed link transfer aborts transport")
  end
end
Natives.yieldHost = oldYield
package.loaded["src.core.game3.link.contest_link"], package.loaded["src.core.game3.link.init"] = oldCL, oldLink

local hallId = assert(Rse.varId("VAR_CONTEST_HALL_STATE", s))
for _, fault in ipairs({ "none", "false", "throw", "persistThrow", "missingEntrance" }) do
  fresh()
  local c = makeContest(true)
  Rse.setVar(hallId, 3, s)
  s.specialSaveWarpFlags = 0xA1
  local party, backup = copy(s.party), copy(s.savedPlayerParty)
  assert(SaveData.save(Schema.toSaveTable(s)))
  local diskBefore = files[SaveData.saveFilename("emerald")]
  failure = fault ~= "none" and fault or nil
  if fault == "persistThrow" then Util.persist = function() error("injected persist exception") end end
  if fault == "missingEntrance" then s.dynamicWarp.x = nil end
  local screen = Results.new({ contest = c, session = s, headless = true })
  T.check(untilFrame(screen, function() return saveCalls > 0 or screen.linkSaveError ~= nil end), fault .. " reaches real results save action")
  T.eq(s.contestLinkResults[2][1], 1, fault .. " counts result once")
  T.eq(s.gameStats[35], 1, fault .. " counts link win once")
  T.eq(s.gameStats[36], nil, fault .. " does not count ordinary contest")
  local winners, stats = copy(s.contestWinners), copy(s.gameStats)
  local counts = copy(s.contestLinkResults)
  T.eq(Rse.var(hallId, s), 3, fault .. " restores live hall state")
  T.eq(s.specialSaveWarpFlags, fault == "missingEntrance" and 0xA1 or 0xA0, fault .. " clears only active transaction continue bit")
  T.same(s.party, party, fault .. " keeps active party without swapping")
  T.same(s.savedPlayerParty, backup, fault .. " preserves original backup")
  if fault ~= "none" then
    T.check(screen.linkSaveError ~= nil and screen.linkBoxShown == true, fault .. " exposes save error in actual results text box")
    T.eq(screen.standbyBeforeResults, nil, fault .. " blocks link standby after failure")
    T.eq(files[SaveData.saveFilename("emerald")], diskBefore, fault .. " preserves last successful file")
    local calls = saveCalls
    for _ = 1, 30 do frame(screen) end
    T.eq(saveCalls, calls, fault .. " waits for explicit retry input")
    frame(screen, true)
    T.check(screen.linkSaveError ~= nil, fault .. " failed explicit retry retains error")
    T.same(s.contestWinners, winners, fault .. " failed retry never shifts winner twice")
    T.same(s.gameStats, stats, fault .. " failed retry never increments stats twice")
    T.same(s.contestLinkResults, counts, fault .. " failed retry never increments place twice")
    failure, Util.persist = nil, oldPersist
    s.dynamicWarp.x = 17
    frame(screen, true)
  end
  T.eq(screen.linkResultsPersisted, true, fault .. " writes link results successfully")
  T.eq(screen.linkSaveError, nil, fault .. " clears error after successful retry")
  T.check(observed ~= nil, fault .. " actual game save captures source transaction")
  if observed then
    T.eq(observed.vars[hallId] or 0, 0, fault .. " disk save sees source hall state zero")
    T.eq(observed.specialSaveWarpFlags, 0xA1, fault .. " disk save sees temporary continue bit")
    T.same(observed.continueGameWarp, s.dynamicWarp, fault .. " disk save captures original lobby entry")
    T.same(observed.party, party, fault .. " disk writes active party unchanged")
  else
    T.check(false, fault .. " disk save sees source hall state zero")
    T.check(false, fault .. " disk save sees temporary continue bit")
    T.check(false, fault .. " disk save captures original lobby entry")
    T.check(false, fault .. " disk writes active party unchanged")
  end
  local restored = roundtrip(assert(SaveData.load("emerald")))
  T.eq(restored.map, "EM_LILYCOVE_CITY_CONTEST_LOBBY", fault .. " actual continue restores lobby")
  T.eq(restored.x, 17, fault .. " actual continue restores producer x")
  T.eq(restored.y, 4, fault .. " actual continue restores producer y")
  T.eq(restored.vars[hallId] or 0, 0, fault .. " continued hall state remains source zero")
  T.same(restored.contestWinners, winners, fault .. " persisted winner remains exact once")
  T.same(restored.contestLinkResults, counts, fault .. " persisted counts remain exact once")
  local calls = saveCalls
  for _ = 1, 30 do frame(screen, true) end
  T.eq(saveCalls, calls, fault .. " subsequent UI frames never save again")
  T.eq(Rse.var(hallId, s), 3, fault .. " successful retry retains actual runtime hall var")
  T.eq(s.vars[hallId], 3, fault .. " successful retry retains session hall var snapshot")
end
for _, row in ipairs({ { false, false }, { true, true } }) do
  fresh()
  local screen = Results.new({ contest = makeContest(row[1]), session = s, headless = true, noFieldHooks = row[2] })
  T.check(untilFrame(screen, function() return screen.linkResultsSaved or (s.gameStats and s.gameStats[36] == 1) end), "ordinary/presentation control reaches results")
  for _ = 1, 60 do frame(screen) end
  T.eq(saveCalls, 0, "ordinary contest and explicit presentation fixture do not auto-save")
end

Natives.bind("emerald")
local tempId = assert(Rse.varId("VAR_TEMP_CHALLENGE_STATUS", s))
for _, native in ipairs({ { "CallBattlePikeFunction", Pike.FUNC.SAVE, Pike, "EM_BATTLE_FRONTIER_BATTLE_PIKE_THREE_PATH_ROOM" },
  { "CallBattlePyramidFunction", Pyramid.FUNC.SAVE, Pyramid, Pyramid.FLOOR_MAP } }) do
  for _, fault in ipairs({ "none", "false", "throw", "persistThrow" }) do
    fresh(native[4])
    s.frontier.challengeStatus, s.frontier.challengePaused = 99, 0
    s.frontier.nestedWitness = { 11, 22 }
    Rse.setVar(tempId, 73, s)
    assert(SaveData.save(Schema.toSaveTable(s)))
    local diskBefore = files[SaveData.saveFilename("emerald")]
    local before, party, backup, dynamic, continuing = copy(s.frontier), copy(s.party), copy(s.savedPlayerParty), copy(s.dynamicWarp), copy(s.continueGameWarp)
    failure = fault ~= "none" and fault or nil
    if fault == "persistThrow" then Util.persist = function() error("injected persist exception") end end
    local finishMessage, messages, sounds, unfreezes = nil, 0, 0, 0
    local adapters = Adapters.stub({})
    adapters.listActiveLocalIds = function() return { 1 } end
    adapters.snapshotLocal = function() return { frozen = false } end
    adapters.freezeLocal = function() Field.locked = true end
    adapters.unfreezeLocal = function() unfreezes = unfreezes + 1 end
    adapters.playSe = function() sounds = sounds + 1 end
    adapters.closeMessage = function() end
    adapters.openMessageAsync = function(text, done)
      T.check(text:find("saved", 1, true) ~= nil, native[1] .. " reports concrete persistence failure")
      finishMessage, messages = done, messages + 1
    end
    local vm = Vm.new({ version = "emerald", store = Rse.store(), adapters = adapters, scripts = { save = {
      { op = "lockall" }, { op = "setvar", 0x8004, native[2] }, { op = "setvar", 0x8005, 2 },
      { op = "special", id = C:require("specials", native[1]) },
      { op = "playse", C:require("songs", "SE_SAVE") },
      { op = "setvar", 0x8004, Util.FUNC.SOFT_RESET },
      { op = "special", id = C:require("specials", "CallFrontierUtilFunc") }, { op = "end" },
    } } })
    local called, started = pcall(vm.start, vm, "save")
    T.check(called and started, native[1] .. " actual VM invokes save special without propagating exceptions")
    if fault == "none" then
      T.eq(messages, 0, native[1] .. " successful native save displays no error")
      T.eq(vm:isRunning(), false, native[1] .. " successful native save continues synchronous script")
      T.eq(sounds, 1, native[1] .. " successful save reaches success sound")
      T.eq(Runtime._game.softResetRequested, true, native[1] .. " successful save reaches actual reset native")
      local disk = assert(SaveData.load("emerald"))
      T.same(disk.party, party, native[1] .. " in-place native save writes exact current party")
      T.eq(disk.map, native[4], native[1] .. " keeps in-place map")
      T.eq(disk.x, 7, native[1] .. " keeps in-place x")
      T.eq(disk.y, 5, native[1] .. " keeps in-place y")
      T.eq(disk.frontier.challengeStatus, 2, native[1] .. " writes source requested status")
      T.eq(disk.frontier.challengePaused, 1, native[1] .. " writes paused source flag")
      T.eq(disk.vars[tempId] or 0, 0, native[1] .. " writes source temporary var zero")
      T.same(disk.continueGameWarp, continuing, native[1] .. " does not manufacture continue destination")
      T.eq(disk.specialSaveWarpFlags, 0xA0, native[1] .. " does not manufacture continue bit")
      T.eq(native[3].save(context(), s), true, native[1] .. " save function returns true after actual successful write")
    else
      T.eq(messages, 1, native[1] .. " failed write shows one error")
      T.eq(vm:isRunning(), true, native[1] .. " failed native waits for acknowledgment")
      T.eq(sounds, 0, native[1] .. " failure blocks success sound")
      T.eq(Runtime._game.softResetRequested, nil, native[1] .. " failure blocks reset")
      T.same(s.frontier, before, native[1] .. " failure restores complete pre-special Frontier state")
      T.eq(Rse.var(tempId, s), 73, native[1] .. " failure restores actual temporary var")
      T.eq(s.vars[tempId], 73, native[1] .. " failure restores session temporary var snapshot")
      T.eq(files[SaveData.saveFilename("emerald")], diskBefore, native[1] .. " failure preserves previous disk save")
      if finishMessage then finishMessage() end
      pcall(vm.tick, vm)
      T.eq(vm:isRunning(), false, native[1] .. " acknowledgment halts remaining script")
      T.eq(sounds, 0, native[1] .. " acknowledgment never plays success sound")
      T.eq(Runtime._game.softResetRequested, nil, native[1] .. " acknowledgment never resets")
      T.check(not Field.locked and unfreezes == 1, native[1] .. " failure unlocks and unfreezes field")
    end
    T.same(s.party, party, native[1] .. " preserves caller-side preceding party state")
    T.same(s.savedPlayerParty, backup, native[1] .. " preserves caller-side preceding backup")
    T.same(s.dynamicWarp, dynamic, native[1] .. " never consumes unrelated dynamic warp")
    T.same(s.continueGameWarp, continuing, native[1] .. " retains unrelated continue destination")
    T.eq(s.specialSaveWarpFlags, 0xA0, native[1] .. " retains all unrelated warp flags")
  end
end
Util.persist, SaveData.portableFs, Runtime.getSession, Runtime._game, Runtime._mod = oldPersist, oldFs, oldGet, oldGame, oldMod
T.finish("emerald_frontier_contest_save_test")
