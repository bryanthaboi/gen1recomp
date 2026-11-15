local Rse = require("src.core.game3.rse.init")

local bit = rawget(_G, "bit") or require("bit")

local Hill = {}

Hill.MANIFEST = "data/generated/gba/rse/trainer_hill/manifest.lua"

-- pokeemerald/include/constants/trainer_hill.h:22
Hill.FUNC = {
  START = 0, GET_OWNER_STATE = 1, GIVE_PRIZE = 2, CHECK_FINAL_TIME = 3, RESUME_TIMER = 4, SET_LOST = 5,
  GET_CHALLENGE_STATUS = 6, GET_CHALLENGE_TIME = 7, GET_ALL_FLOORS_USED = 8, GET_IN_EREADER_MODE = 9,
  IN_CHALLENGE = 10, POST_BATTLE_TEXT = 11, SET_ALL_TRAINER_FLAGS = 12, GET_GAME_SAVED = 13, SET_GAME_SAVED = 14,
  CLEAR_GAME_SAVED = 15, GET_WON = 16, SET_MODE = 17,
}
-- pokeemerald/include/constants/trainer_hill.h:4
Hill.MAP = { F1 = 1, F2 = 2, F3 = 3, F4 = 4, ROOF = 5, ENTRANCE = 6 }
Hill.MODE = { NORMAL = 0, VARIETY = 1, UNIQUE = 2, EXPERT = 3 }
Hill.NUM_MODES = 4
Hill.NUM_FLOORS = 4
Hill.PRIZE_LISTS = 10
-- pokeemerald/include/constants/trainer_hill.h:41
Hill.TEXT = { INTRO = 2, PLAYER_LOST = 3, PLAYER_WON = 4, AFTER = 5 }
-- pokeemerald/include/constants/trainer_hill.h:51
Hill.STATUS = { LOST = 0, ECARD_SCANNED = 1, NORMAL = 2 }
Hill.TRAINERS_PER_FLOOR = 2
Hill.NUM_TRAINERS = 8
-- pokeemerald/include/constants/trainer_hill.h:61
Hill.FLOOR_WIDTH = 16
Hill.FLOOR_HEIGHT_MAIN = 16
Hill.FLOOR_HEIGHT_MARGIN = 5
-- pokeemerald/src/trainer_hill.c:35
Hill.MAX_TIME = 215999
-- pokeemerald/include/fieldmap.h:6
Hill.NUM_METATILES_IN_PRIMARY = 512
-- pokeemerald/src/trainer_hill.c:680
Hill.ELEVATION_DEFAULT = 3
-- pokeemerald/include/constants/vars.h:287
Hill.VAR_0x8004, Hill.VAR_0x8005, Hill.VAR_RESULT, Hill.VAR_LAST_TALKED = 0x8004, 0x8005, 0x800D, 0x800F

Hill.MAPS = {
  EM_TRAINER_HILL_1F = Hill.MAP.F1, EM_TRAINER_HILL_2F = Hill.MAP.F2, EM_TRAINER_HILL_3F = Hill.MAP.F3,
  EM_TRAINER_HILL_4F = Hill.MAP.F4, EM_TRAINER_HILL_ROOF = Hill.MAP.ROOF, EM_TRAINER_HILL_ENTRANCE = Hill.MAP.ENTRANCE,
}

local cache = {}

function Hill.manifest()
  local GameVersion = require("src.core.GameVersion")
  local key = tostring(GameVersion.get())
  local hit = cache[key]
  if hit then return hit end
  local src = require("src.core.game3.dataset").cache():read(Hill.MANIFEST)
  if type(src) ~= "string" then error("trainer_hill: " .. Hill.MANIFEST .. " missing from the cache", 0) end
  local chunk = assert((loadstring or load)(src, "@" .. Hill.MANIFEST))
  if setfenv then setfenv(chunk, {}) end
  hit = chunk()
  cache[key] = hit
  return hit
end

local function D() return require("src.core.game3.rse.frontier.trainers") end
local function Util() return require("src.core.game3.rse.frontier.util") end
local function C(sess) return D().constants(sess) end
local function specialVar(ctx, id) return Rse.specialVar(ctx, id) end
local function setResult(ctx, v) Rse.setSpecialVar(ctx, Hill.VAR_RESULT, v) end

-- pokeemerald/include/global.h:865
function Hill.newState()
  return {
    timer = 0, bestTime = 0, mode = 0, spokeToOwner = 0, hasLost = 0, receivedPrize = 0, checkedFinalTime = 0,
    maybeECardScanDuringChallenge = 0, field_3D6E_0f = 0, unk_3D6C = 0,
  }
end

function Hill.state(sess)
  sess = sess or Rse.session()
  if type(sess.trainerHill) ~= "table" then sess.trainerHill = Hill.newState() end
  local h = sess.trainerHill
  for k, v in pairs(Hill.newState()) do
    if h[k] == nil then h[k] = v end
  end
  if type(sess.trainerHillTimes) ~= "table" then
    sess.trainerHillTimes = {}
    for i = 1, Hill.NUM_MODES do sess.trainerHillTimes[i] = Hill.MAX_TIME end
  end
  return h
end

-- pokeemerald/src/trainer_hill.c:280
function Hill.resetResults(sess)
  local f = Util().frontier(sess)
  f.savedGame = 0
  f.unk_EF9 = 0
  local h = Hill.state(sess)
  h.bestTime = 0
  for i = 1, Hill.NUM_MODES do sess.trainerHillTimes[i] = Hill.MAX_TIME end
end

Hill.SAVE_FIELDS = { "trainerHill", "trainerHillTimes" }

local okS, SaveSections = pcall(require, "src.core.game3.save_sections")
if okS and SaveSections then
  SaveSections.register("trainerHill", SaveSections.fields(Hill.SAVE_FIELDS, function(session)
    session.trainerHill = Hill.newState()
    session.trainerHillTimes = nil
    Hill.state(session)
    Hill.resetResults(session)
  end))
end

-- pokeemerald/src/trainer_hill.c:750
function Hill.mapId(sess)
  sess = sess or Rse.session()
  return (sess and Hill.MAPS[sess.map]) or 0
end

-- pokeemerald/src/trainer_hill.c:735
function Hill.inHill(sess)
  local id = Hill.mapId(sess)
  return id >= Hill.MAP.F1 and id <= Hill.MAP.F4
end

local function floorId(sess)
  return Hill.mapId(sess) - Hill.MAP.F1
end
Hill.floorId = floorId

function Hill.challenge(sess)
  local h = Hill.state(sess)
  local m = Hill.manifest()
  return m.challenges[(tonumber(h.mode) or 0) + 1] or m.challenges[1]
end

function Hill.floor(sess, id)
  return Hill.challenge(sess).floors[(id or floorId(sess)) + 1]
end

-- pokeemerald/src/trainer_hill.c:554
function Hill.inChallenge(sess)
  sess = sess or Rse.session()
  if not sess then return false end
  if Rse.var("VAR_TRAINER_HILL_IS_ACTIVE", sess) == 0 then return false end
  if (tonumber(Hill.state(sess).spokeToOwner) or 0) ~= 0 then return false end
  return Hill.mapId(sess) ~= 0
end

function Hill.inChallengeMap()
  local sess = Rse.session()
  return sess ~= nil and Hill.inHill(sess)
end

local function counter()
  local Runtime = package.loaded["src.core.game3.runtime"]
  return Runtime and tonumber(Runtime._vblankCounter) or 0
end

-- pokeemerald/src/main.c:418
function Hill.setTimerRunning(sess, on)
  local h = Hill.state(sess)
  Hill.syncTimer(sess)
  if on then
    Hill._timer = { sess = sess, base = tonumber(h.timer) or 0, mark = counter() }
  else
    Hill._timer = nil
  end
end

-- pokeemerald/src/main.c:349
function Hill.syncTimer(sess)
  local t = Hill._timer
  if not t then return end
  local h = Hill.state(t.sess)
  local v = t.base + math.max(0, counter() - t.mark)
  if v > 0xFFFFFFFF then v = 0xFFFFFFFF end
  h.timer = v
end

function Hill.timerRunning()
  return Hill._timer ~= nil
end

function Hill.addFrames(n)
  local t = Hill._timer
  if t then t.base = t.base + (tonumber(n) or 0) end
end

-- pokeemerald/src/trainer_hill.c:396
function Hill.start(sess)
  local h = Hill.state(sess)
  h.field_3D6E_0f = 0
  h.unk_3D6C = 0
  h.timer = 0
  Hill.setTimerRunning(sess, true)
  h.timer = 0
  Hill._timer.base = 0
  h.spokeToOwner = 0
  h.checkedFinalTime = 0
  h.maybeECardScanDuringChallenge = 0
  Util().frontier(sess).trainerFlags = 0
  sess.battleOutcome = 0
  h.receivedPrize = 0
end

-- pokeemerald/src/trainer_hill.c:415
function Hill.getOwnerState(ctx, sess)
  Hill.setTimerRunning(sess, false)
  local h = Hill.state(sess)
  local r = 0
  if (tonumber(h.spokeToOwner) or 0) ~= 0 then r = r + 1 end
  if (tonumber(h.receivedPrize) or 0) ~= 0 and (tonumber(h.checkedFinalTime) or 0) ~= 0 then r = r + 1 end
  setResult(ctx, r)
  h.spokeToOwner = 1
end

-- pokeemerald/src/trainer_hill.c:1000
function Hill.prizeListId(sess, allowTMs)
  local id = 0
  for _, fl in ipairs(Hill.challenge(sess).floors) do
    id = bit.bxor(id, bit.band(fl.trainerNum1, 0x1F))
    id = bit.bxor(id, bit.band(fl.trainerNum2, 0x1F))
  end
  local modBy = allowTMs and Hill.PRIZE_LISTS or (Hill.PRIZE_LISTS / 2)
  return id % modBy
end

-- pokeemerald/src/trainer_hill.c:1026
function Hill.prizeItemId(sess)
  local m = Hill.manifest()
  local ch = Hill.challenge(sess)
  local h = Hill.state(sess)
  local sum = 0
  for i = 1, Hill.NUM_FLOORS do
    sum = sum + ch.floors[i].trainerNum1 + ch.floors[i].trainerNum2
  end
  local setId = math.floor(sum / 256) % #m.prizeListSets
  local i
  if Rse.flag("FLAG_SYS_GAME_CLEAR", sess) and ch.numTrainers == Hill.NUM_TRAINERS then
    i = Hill.prizeListId(sess, true)
  else
    i = Hill.prizeListId(sess, false)
  end
  if (tonumber(h.mode) or 0) == Hill.MODE.EXPERT then i = (i + 1) % Hill.PRIZE_LISTS end
  local list = m.prizeListSets[setId + 1][i + 1]
  local minutes = math.floor((tonumber(h.timer) or 0) / 3600)
  local id
  if minutes < 12 then id = 0
  elseif minutes < 13 then id = 1
  elseif minutes < 14 then id = 2
  elseif minutes < 16 then id = 3
  elseif minutes < 18 then id = 4
  else id = 5 end
  return list[id + 1]
end

-- pokeemerald/src/trainer_hill.c:427
function Hill.givePrize(ctx, adapters, sess)
  local h = Hill.state(sess)
  local item = Hill.prizeItemId(sess)
  local Bag = require("src.core.game3.bag")
  if Hill.challenge(sess).numFloors ~= Hill.NUM_FLOORS or (tonumber(h.receivedPrize) or 0) ~= 0 then
    setResult(ctx, 2)
  elseif Bag.add(sess.bag, item, 1) then
    local ItemsData = require("src.core.game3.items_data")
    Util().setStringVar(ctx, adapters, 2, ItemsData.displayName(item))
    h.receivedPrize = 1
    Util().frontier(sess).unk_EF9 = 0
    setResult(ctx, 0)
  else
    setResult(ctx, 1)
  end
  Hill.lastPrize = item
end

-- pokeemerald/src/trainer_hill.c:450
function Hill.checkFinalTime(ctx, sess)
  local h = Hill.state(sess)
  Hill.syncTimer(sess)
  if (tonumber(h.checkedFinalTime) or 0) ~= 0 then
    setResult(ctx, 2)
  elseif (tonumber(h.bestTime) or 0) > (tonumber(h.timer) or 0) then
    h.bestTime = h.timer
    sess.trainerHillTimes[(tonumber(h.mode) or 0) + 1] = h.bestTime
    setResult(ctx, 0)
  else
    setResult(ctx, 1)
  end
  h.checkedFinalTime = 1
end

-- pokeemerald/src/trainer_hill.c:470
function Hill.resumeTimer(sess)
  local h = Hill.state(sess)
  if (tonumber(h.spokeToOwner) or 0) == 0 then
    if (tonumber(h.timer) or 0) >= Hill.MAX_TIME then
      h.timer = Hill.MAX_TIME
    elseif not Hill.timerRunning() then
      Hill.setTimerRunning(sess, true)
    end
  end
end

-- pokeemerald/src/trainer_hill.c:486
function Hill.getStatus(ctx, sess)
  local h = Hill.state(sess)
  if (tonumber(h.hasLost) or 0) ~= 0 then
    h.hasLost = 0
    setResult(ctx, Hill.STATUS.LOST)
  elseif (tonumber(h.maybeECardScanDuringChallenge) or 0) ~= 0 then
    h.maybeECardScanDuringChallenge = 0
    setResult(ctx, Hill.STATUS.ECARD_SCANNED)
  else
    setResult(ctx, Hill.STATUS.NORMAL)
  end
end

-- pokeemerald/src/trainer_hill.c:507
function Hill.timeParts(frames)
  local total = tonumber(frames) or 0
  if total >= Hill.MAX_TIME then total = Hill.MAX_TIME end
  local minutes = math.floor(total / 3600)
  total = total % 3600
  local seconds = math.floor(total / 60)
  total = total % 60
  local fraction = math.floor(total * 168 / 100)
  return minutes, seconds, fraction
end

-- pokeemerald/src/trainer_hill.c:507
function Hill.bufferTime(ctx, adapters, sess)
  Hill.syncTimer(sess)
  local m, s, f = Hill.timeParts(Hill.state(sess).timer)
  Util().setStringVar(ctx, adapters, 1, string.format("%2d", m))
  Util().setStringVar(ctx, adapters, 2, string.format("%2d", s))
  Util().setStringVar(ctx, adapters, 3, string.format("%02d", f))
end

-- pokeemerald/src/trainer_hill.c:529
function Hill.allFloorsUsed(ctx, adapters, sess)
  local ch = Hill.challenge(sess)
  if ch.numFloors ~= Hill.NUM_FLOORS then
    Util().setStringVar(ctx, adapters, 1, tostring(ch.numFloors))
    setResult(ctx, 0)
  else
    setResult(ctx, 1)
  end
end

-- pokeemerald/src/trainer_hill.c:347
function Hill.trainer(sess, localId, id)
  local fl = Hill.floor(sess, id)
  return fl and fl.trainers[(tonumber(localId) or 1)]
end

-- pokeemerald/src/trainer_hill.c:369
function Hill.trainerText(sess, which, localId)
  local t = Hill.trainer(sess, localId)
  if not t then return {} end
  local key = ({ [Hill.TEXT.INTRO] = "speechBefore", [Hill.TEXT.PLAYER_LOST] = "speechWin",
    [Hill.TEXT.PLAYER_WON] = "speechLose", [Hill.TEXT.AFTER] = "speechAfter" })[which]
  return D().speechToString(t[key])
end

-- pokeemerald/src/trainer_hill.c:854
function Hill.postBattleText(ctx, adapters, sess)
  local ir = Hill.trainerText(sess, Hill.TEXT.AFTER, specialVar(ctx, Hill.VAR_LAST_TALKED))
  Util().showFieldMessage(ctx, adapters, ir)
end

-- pokeemerald/src/trainer_hill.c:993
function Hill.setMode(ctx, sess)
  local h = Hill.state(sess)
  local mode = specialVar(ctx, Hill.VAR_0x8005)
  h.mode = mode
  h.bestTime = sess.trainerHillTimes[mode + 1] or Hill.MAX_TIME
end

-- pokeemerald/src/trainer_hill.c:814
function Hill.trainerFlag(sess, localId, id)
  local bitId = (tonumber(localId) or 1) - 1 + (id or floorId(sess)) * Hill.TRAINERS_PER_FLOOR
  return bit.band(tonumber(Util().frontier(sess).trainerFlags) or 0, bit.lshift(1, bitId)) ~= 0
end

-- pokeemerald/src/trainer_hill.c:822
function Hill.setTrainerFlag(sess, localId)
  local f = Util().frontier(sess)
  local bitId = (tonumber(localId) or 1) - 1 + floorId(sess) * Hill.TRAINERS_PER_FLOOR
  f.trainerFlags = bit.bor(tonumber(f.trainerFlags) or 0, bit.lshift(1, bitId)) % 256
end

-- pokeemerald/src/trainer_hill.c:945
function Hill.setAllTrainerFlags(sess)
  Util().frontier(sess).trainerFlags = 0xFF
end

-- pokeemerald/src/trainer_hill.c:685
function Hill.composeLayout(sess, def)
  local LayoutNative = require("src.core.game3.layout_native")
  local base = def._hillBase or def.midLayout
  def._hillBase = base
  local fl = Hill.floor(sess)
  local W = Hill.FLOOR_WIDTH
  local H = Hill.FLOOR_HEIGHT_MAIN + Hill.FLOOR_HEIGHT_MARGIN
  local cells = {}
  for y = 0, Hill.FLOOR_HEIGHT_MARGIN - 1 do
    for x = 0, W - 1 do
      local c = base.cells[y * base.width + x + 1]
        or error(("trainer hill base layout has no cell at %d,%d"):format(x, y))
      cells[y * W + x + 1] = { mid = c.mid, coll = c.coll, elev = c.elev }
    end
  end
  for y = 0, Hill.FLOOR_HEIGHT_MAIN - 1 do
    local row = tonumber(fl.map.collision[y + 1])
      or error(("trainer hill floor has no collision row %d"):format(y))
    for x = 0, W - 1 do
      local impassable = bit.band(bit.rshift(row, 15 - x), 1)
      cells[(y + Hill.FLOOR_HEIGHT_MARGIN) * W + x + 1] = {
        mid = (fl.map.metatiles[y * W + x + 1]
          or error(("trainer hill floor has no metatile at %d,%d"):format(x, y))) + Hill.NUM_METATILES_IN_PRIMARY,
        coll = impassable, elev = Hill.ELEVATION_DEFAULT,
      }
    end
  end
  return LayoutNative.fromDecoded({
    width = W, height = H, trueWidth = W, trueHeight = H,
    borderWidth = base.borderWidth, borderHeight = base.borderHeight, borderMids = base.borderMids,
    cells = cells,
  }, def.mapId or base.mapId, base.pair)
end

-- pokeemerald/src/trainer_hill.c:631
function Hill.objectTemplates(sess)
  local m = Hill.manifest()
  local fl = Hill.floor(sess)
  local f = Util().frontier(sess)
  local key = require("src.core.game3.rse.frontier.pyramid").scriptKey("TrainerHill_EventScript_TrainerBattle")
  local faceUp = C(sess):require("movement", "MOVEMENT_TYPE_FACE_UP")
  local tpl = m.objectTemplate
  local out = {}
  for i = 1, Hill.TRAINERS_PER_FLOOR do f.trainerIds[i] = 0xFFFF end
  for i = 0, Hill.TRAINERS_PER_FLOOR - 1 do
    local t = fl.trainers[i + 1]
    local bits = i * 4
    local coords = fl.map.trainerCoords[i + 1]
    local gfx = D().facilityClassToGfx(t.facilityClass)
    local battled = Hill.trainerFlag(sess, i + 1)
    local range = bit.band(bit.rshift(fl.map.trainerRanges, bits), 0xF)
    out[i + 1] = {
      localId = i + 1, index = i + 1, kind = 0,
      graphics = gfx, graphicsId = gfx,
      x = bit.band(coords, 0xF), y = bit.band(bit.rshift(coords, 4), 0xF) + Hill.FLOOR_HEIGHT_MARGIN,
      elevation = tpl.elevation,
      movementType = bit.band(bit.rshift(fl.map.trainerDirections, bits), 0xF) + faceUp,
      rangeX = tpl.rangeX, rangeY = tpl.rangeY,
      trainerType = battled and 0 or tpl.trainerType,
      sight = range, trainerRange = range,
      scriptKey = key, flag = 0, trainerId = 0,
    }
    f.trainerIds[i + 1] = i + 1
  end
  return out
end

local function bundleEvents(mapId)
  local Space = package.loaded["src.core.game3.scripting.space"]
  local bundle = Space and (Space.bundle or (Space.ensureBundle and Space.ensureBundle(nil)))
  return bundle and bundle.events and bundle.events[mapId]
end

-- pokeemerald/src/overworld.c:838
function Hill.onMapLoad(sess, mapId, def, opts)
  sess = sess or Rse.session()
  if not (sess and Rse.isRse(sess) and def) then return false end
  local id = Hill.MAPS[mapId]
  if not id or id < Hill.MAP.F1 or id > Hill.MAP.F4 then return false end
  local prevMap = sess.map
  sess.map = mapId
  local layout = Hill.composeLayout(sess, def)
  def.midLayout = layout
  def.width, def.height = layout.width, layout.height
  local ev = bundleEvents(mapId)
  if ev then ev.objects = Hill.objectTemplates(sess) end
  sess.map = prevMap
  local Runtime = package.loaded["src.core.game3.runtime"]
  local game = Runtime and Runtime._game
  local Collision = package.loaded["src.core.game3.collision"]
  if Collision and Collision.bindMap and game then pcall(Collision.bindMap, game, mapId, def) end
  local FieldView = package.loaded["src.core.game3.field_view"]
  if FieldView then FieldView._nativeDirty = true end
  return true
end

-- pokeemerald/src/trainer_hill.c:860
function Hill.party(sess, localId)
  local m = Hill.manifest()
  local t = Hill.trainer(sess, localId)
  local level = D().highestPartyLevel(sess.party)
  local party = {}
  for slot = 1, 3 do
    local idx = m.partySlots[localId][slot]
    local src = t.mons[idx + 1]
    local mon = D().battleTowerMon(src, true, level)
    party[#party + 1] = mon
  end
  return party
end

-- pokeemerald/src/trainer_hill.c:905
function Hill.encounterMusic(sess, localId)
  local m = Hill.manifest()
  local t = Hill.trainer(sess, localId)
  local Tp = require("src.core.game3.scripting.trainers").pack() or {}
  local cls = Tp.facilityClassToTrainerClass and Tp.facilityClassToTrainerClass[t and t.facilityClass or 0]
  local code = 0
  for _, row in ipairs(m.classMusic) do
    if row[1] == cls then code = row[2] break end
  end
  local Cc = C(sess)
  local name = Cc:name("trainer_classes", code, "TRAINER_ENCOUNTER_MUSIC_")
  return name and Cc:song("MUS_ENCOUNTER_" .. name:sub(#"TRAINER_ENCOUNTER_MUSIC_" + 1)) or Cc:song("MUS_ENCOUNTER_MALE")
end

-- pokeemerald/src/trainer_hill.c:296
function Hill.foe(sess, localId, party)
  local t = Hill.trainer(sess, localId)
  local Tp = require("src.core.game3.scripting.trainers").pack() or {}
  local classId = Tp.facilityClassToTrainerClass and Tp.facilityClassToTrainerClass[t.facilityClass] or 0
  local lead = party[1] or {}
  return {
    party = party,
    trainerName = t.name,
    trainerClass = classId,
    trainerClassName = D().className(sess, classId),
    trainerPicId = Tp.facilityClassToPic and Tp.facilityClassToPic[t.facilityClass] or 0,
    species = lead.species, level = lead.level, ivs = lead.ivs, evs = lead.evs, item = lead.item,
    moves = lead.moves, personality = lead.personality, nature = lead.nature, ability = lead.ability,
    gender = lead.gender, pp = lead.pp,
  }
end

local function plain(ir)
  return require("src.core.game3.scripting.text_ir").toPlain(ir, {})
end

-- pokeemerald/src/battle_setup.c:1306
function Hill.startBattle(ctx, adapters, sess, localId, onDone)
  local Runtime = package.loaded["src.core.game3.runtime"]
  local BattleBridge = require("src.core.game3.battle_bridge")
  local BP = require("src.core.game3.battle.profile")
  local N = require("src.core.game3.scripting.natives")
  local party = Hill.party(sess, localId)
  local foe = Hill.foe(sess, localId, party)
  local p = BP.get(sess)
  local Tower = require("src.core.game3.rse.frontier.tower")
  local opts = {
    wild = false,
    trainerHill = true,
    aiFlags = Tower.aiFlags(sess),
    trainerItems = { 0, 0, 0, 0 },
    scriptedLoss = true,
    trainerName = foe.trainerName,
    trainerPicId = foe.trainerPicId,
    defeatText = plain(Hill.trainerText(sess, Hill.TEXT.PLAYER_WON, localId)),
    victoryText = plain(Hill.trainerText(sess, Hill.TEXT.PLAYER_LOST, localId)),
    transitionId = D().specialTransition(sess, "TRAINER_HILL", party),
    song = BP.battleSong(p, { trainerClass = foe.trainerClass }),
    frontierTrainer = { class = foe.trainerClass, className = foe.trainerClassName, name = foe.trainerName,
      pic = foe.trainerPicId },
  }
  Hill.setTrainerFlag(sess, localId)
  sess.battleOutcome = 0
  opts.done = function(result)
    local code = N.outcome_to_code(result or "win")
    sess.battleOutcome = code
    if ctx then ctx.lastBattleOutcome = code end
    Rse.setSpecialVar(ctx, Hill.VAR_RESULT, code)
    if onDone then onDone(code) end
  end
  local ok, err = BattleBridge.start(Runtime and Runtime._mod, Runtime and Runtime._game, foe, opts)
  if not ok then
    local msg = "[game3] trainer hill battle did not start (" .. tostring(err) .. ")"
    if adapters and adapters.log then adapters.log(msg) else print(msg) end
    if onDone then onDone(nil) end
  end
  return ok
end

local function markTemplate(sess, localId)
  local ev = bundleEvents(sess.map)
  for _, t in ipairs(ev and ev.objects or {}) do
    if tonumber(t.localId) == tonumber(localId) then t.trainerType = 0 end
  end
  local Objects = package.loaded["src.core.game3.objects"]
  local eo = Objects and Objects.find and Objects.find(localId)
  if eo then
    eo.trainerType = 0
    if eo.def then eo.def.trainerType = 0 end
  end
end

-- pokeemerald/data/scripts/trainer_battle.inc:9
function Hill.trainerBattle(vm, row)
  local ctx = vm.ctx
  local a = vm.adapters or {}
  local sess = Rse.session()
  local Flags = require("src.core.game3.scripting.flags")
  local localId = tonumber(Flags.getVar(vm.store, ctx, Hill.VAR_LAST_TALKED)) or 0
  if Hill.trainerFlag(sess, localId) then return false end
  local okA, Audio = pcall(require, "src.core.game3.audio")
  if okA and Audio and Audio.playSong then pcall(Audio.playSong, Hill.encounterMusic(sess, localId)) end
  local Objects = package.loaded["src.core.game3.objects"]
  local eo = Objects and Objects.find and Objects.find(localId)
  local P = require("src.core.game3.player")
  if eo and Objects.scriptFace then
    local dx, dy = P.cellX - eo.cellX, P.cellY - eo.cellY
    local dir = (math.abs(dx) > math.abs(dy)) and (dx > 0 and "right" or "left") or (dy > 0 and "down" or "up")
    pcall(Objects.scriptFace, eo, dir)
  end
  local intro = Util().textBox(Hill.trainerText(sess, Hill.TEXT.INTRO, localId), ctx)
  ctx.mode = "native"
  ctx.status = "waiting"
  local finished, lost = false, false
  ctx.nativePoll = function()
    if not finished then return false end
    if lost then
      ctx.status = "halted"
      return false
    end
    return true
  end
  local function begin()
    markTemplate(sess, localId)
    local N = require("src.core.game3.scripting.natives")
    Hill.startBattle(ctx, a, sess, localId, function(code)
      lost = code == N.outcome_to_code("lose") or code == N.outcome_to_code("draw")
      finished = true
      local Space = package.loaded["src.core.game3.scripting.space"]
      if Space and Space.vm then Space.vm:tick() end
    end)
  end
  if a.openMessageAsync then
    a.openMessageAsync(intro, begin)
  else
    begin()
  end
  return true
end

Rse.register("trainerHill", Hill)

return Hill
