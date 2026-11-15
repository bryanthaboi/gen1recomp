local Rse = require("src.core.game3.rse.init")
local D = require("src.core.game3.rse.frontier.trainers")
local Util = require("src.core.game3.rse.frontier.util")

local bit = rawget(_G, "bit") or require("bit")

local Pyramid = {}

Pyramid.MANIFEST = "data/generated/gba/rse/pyramid/manifest.lua"

-- pokeemerald/include/constants/battle_pyramid.h:34
Pyramid.FUNC = {
  INIT = 0, GET_DATA = 1, SET_DATA = 2, SAVE = 3, SET_PRIZE = 4, GIVE_PRIZE = 5, SEED_FLOOR = 6, SET_ITEM = 7,
  HIDE_ITEM = 8, SET_TRAINERS = 9, SHOW_HINT_TEXT = 10, UPDATE_STREAK = 11, CURRENT_LOCATION = 12,
  UPDATE_LIGHT = 13, CLEAR_HELD_ITEMS = 14, SET_FLOOR_PALETTE = 15, START_MENU = 16, RESTORE_PARTY = 17,
}
-- pokeemerald/include/constants/battle_pyramid.h:53
Pyramid.DATA = {
  PRIZE = 0, WIN_STREAK = 1, WIN_STREAK_ACTIVE = 2, WIN_STREAK_50 = 3, WIN_STREAK_OPEN = 4,
  WIN_STREAK_ACTIVE_50 = 5, WIN_STREAK_ACTIVE_OPEN = 6, TRAINER_FLAGS = 7,
}
-- pokeemerald/include/constants/battle_pyramid.h:62
Pyramid.LIGHT = { SET_RADIUS = 0, INCR_RADIUS = 1 }
Pyramid.LOCATION = { NONE = 0, FLOOR = 1, TOP = 2 }
-- pokeemerald/include/constants/battle_pyramid.h:7
Pyramid.HINT = {
  EXIT_DIRECTION = 0, REMAINING_ITEMS = 1, REMAINING_TRAINERS = 2, EXIT_SHORT_REMAINING_TRAINERS = 3,
  EXIT_SHORT_REMAINING_ITEMS = 4, EXIT_MEDIUM_REMAINING_TRAINERS = 5, EXIT_MEDIUM_REMAINING_ITEMS = 6,
  EXIT_FAR_REMAINING_TRAINERS = 7, EXIT_FAR_REMAINING_ITEMS = 8,
}
-- pokeemerald/include/constants/battle_pyramid.h:4
Pyramid.TOTAL_ROUNDS = 20
Pyramid.PICKUP_ITEMS_PER_ROUND = 10
Pyramid.MAX_TRAINERS = 8
Pyramid.SQUARES_WIDE, Pyramid.SQUARES_HIGH = 4, 4
Pyramid.NUM_SQUARES = 16
Pyramid.SQUARE_SIZE = 8
Pyramid.OBJ_TRAINERS, Pyramid.OBJ_ITEMS = 0, 1
Pyramid.POS = { UNIFORM = 0, IN_AND_NEAR_ENTRANCE = 1, IN_AND_NEAR_EXIT = 2, NEAR_ENTRANCE = 3, NEAR_EXIT = 4 }
-- pokeemerald/src/battle_pyramid.c:41
Pyramid.NUM_LAYOUT_OFFSETS = 8
-- pokeemerald/include/constants/global.h:66
Pyramid.BAG_ITEMS_COUNT = 10
-- pokeemerald/include/constants/items.h:453
Pyramid.MAX_BAG_ITEM_CAPACITY = 99
-- pokeemerald/src/battle_pyramid.c:1131
Pyramid.MAX_LIGHT_RADIUS = 120
-- pokeemerald/src/battle_pyramid.c:1107
Pyramid.MAX_STREAK = 999
-- pokeemerald/src/battle_pyramid.c:942
Pyramid.LONG_STREAK = 41
-- pokeemerald/src/battle_pyramid.c:1405
Pyramid.WILD_HIGH_IV_STREAK = 140
-- pokeemerald/src/battle_pyramid.c:102
Pyramid.ABILITY_RANDOM = 2
-- pokeemerald/include/constants/vars.h:283
Pyramid.VAR_0x8000, Pyramid.VAR_0x8001, Pyramid.VAR_0x8007 = 0x8000, 0x8001, 0x8007
Pyramid.HIDDEN_COORD = 32767

Pyramid.FLOOR_MAP = "EM_BATTLE_FRONTIER_BATTLE_PYRAMID_FLOOR"
Pyramid.TOP_MAP = "EM_BATTLE_FRONTIER_BATTLE_PYRAMID_TOP"

local F = D.FACILITY
local cache = {}

function Pyramid.manifest()
  local GameVersion = require("src.core.GameVersion")
  local key = tostring(GameVersion.get())
  local hit = cache[key]
  if hit then return hit end
  local src = require("src.core.game3.dataset").cache():read(Pyramid.MANIFEST)
  if type(src) ~= "string" then error("pyramid: " .. Pyramid.MANIFEST .. " missing from the cache", 0) end
  local chunk = assert((loadstring or load)(src, "@" .. Pyramid.MANIFEST))
  if setfenv then setfenv(chunk, {}) end
  hit = chunk()
  cache[key] = hit
  return hit
end

function Pyramid.reset()
  cache = {}
  Pyramid._composed = nil
end

local function C(sess) return D.constants(sess) end
local function rng() return D.rng() end
local function specialVar(ctx, id) return Rse.specialVar(ctx, id) end
local function setSpecialVar(ctx, id, v) Rse.setSpecialVar(ctx, id, v) end
local function setResult(ctx, v) Util.setResult(ctx, v) end

local function zeros(n)
  local t = {}
  for i = 1, n do t[i] = 0 end
  return t
end

-- pokeemerald/include/global.h:439
function Pyramid.frontier(sess)
  local f = Util.frontier(sess)
  if type(f.pyramidRandoms) ~= "table" then f.pyramidRandoms = zeros(4) end
  f.pyramidTrainerFlags = tonumber(f.pyramidTrainerFlags) or 0
  f.pyramidLightRadius = tonumber(f.pyramidLightRadius) or 0
  if type(f.pyramidBag) ~= "table" then
    f.pyramidBag = { itemId = { zeros(Pyramid.BAG_ITEMS_COUNT), zeros(Pyramid.BAG_ITEMS_COUNT) },
      quantity = { zeros(Pyramid.BAG_ITEMS_COUNT), zeros(Pyramid.BAG_ITEMS_COUNT) } }
  end
  if type(f.trainerIds) ~= "table" then
    f.trainerIds = {}
    for i = 1, 20 do f.trainerIds[i] = 0xFFFF end
  end
  return f
end

local function lvlMode(sess) return tonumber(Util.frontier(sess).lvlMode) or 0 end
local function floorNum(sess) return tonumber(Util.frontier(sess).curChallengeBattleNum) or 0 end
local function streak(sess, lvl) return Util.get1(Util.frontier(sess).pyramidWinStreaks, lvl or lvlMode(sess)) end

local function streakFlag(lvl)
  return lvl ~= D.LVL.L50 and Util.STREAK.PYRAMID_OPEN or Util.STREAK.PYRAMID_50
end

-- pokeemerald/src/battle_pyramid.c:980
function Pyramid.round(sess)
  local r = math.floor(streak(sess) / D.STAGES_PER_CHALLENGE) % Pyramid.TOTAL_ROUNDS
  if r >= Pyramid.TOTAL_ROUNDS then r = Pyramid.TOTAL_ROUNDS - 1 end
  return r
end

-- pokeemerald/src/battle_pyramid.c:1423
function Pyramid.location(sess)
  sess = sess or Rse.session()
  local map = sess and sess.map
  if map == Pyramid.FLOOR_MAP then return Pyramid.LOCATION.FLOOR end
  if map == Pyramid.TOP_MAP then return Pyramid.LOCATION.TOP end
  return Pyramid.LOCATION.NONE
end

function Pyramid.inPyramid(sess)
  return Pyramid.location(sess) ~= Pyramid.LOCATION.NONE
end

-- pokeemerald/src/item.c:136
function Pyramid.bagActive(sess)
  sess = sess or Rse.session()
  if not (sess and Rse.isRse(sess)) then return false end
  if Pyramid.inPyramid(sess) then return true end
  local id = Rse.flagId("FLAG_STORING_ITEMS_IN_PYRAMID_BAG", sess)
  return id ~= nil and Rse.flag("FLAG_STORING_ITEMS_IN_PYRAMID_BAG", sess)
end

-- pokeemerald/src/battle_pyramid.c:1916
function Pyramid.floorTemplateId(sess)
  local f = Pyramid.frontier(sess)
  local man = Pyramid.manifest()
  local rand = (tonumber(f.pyramidRandoms[4]) or 0) % 100
  local floor = floorNum(sess)
  local start = (man.floorTemplateOffsets[floor + 1] or 0) + 1
  for i = start, #man.floorTemplateOptions do
    local opt = man.floorTemplateOptions[i]
    if rand < opt[1] then return opt[2] end
  end
  return 0
end

function Pyramid.floorTemplate(sess)
  return Pyramid.manifest().floorTemplates[Pyramid.floorTemplateId(sess) + 1]
end

local function s32(v)
  v = v % 4294967296
  if v >= 2147483648 then v = v - 4294967296 end
  return v
end

-- pokeemerald/src/battle_pyramid.c:1898
function Pyramid.layoutOffsets(sess)
  local f = Pyramid.frontier(sess)
  local r = f.pyramidRandoms
  local tpl = Pyramid.floorTemplate(sess)
  local out = {}
  local rand = s32((tonumber(r[1]) or 0) + (tonumber(r[2]) or 0) * 65536)
  for i = 0, Pyramid.NUM_SQUARES - 1 do
    local m = rand % Pyramid.NUM_LAYOUT_OFFSETS
    out[i + 1] = tpl.layoutOffsets[m + 1]
    rand = bit.arshift(rand, 3)
    if i == 7 then
      rand = s32((tonumber(r[3]) or 0) + (tonumber(r[4]) or 0) * 65536)
      rand = bit.arshift(rand, 8)
    end
  end
  return out
end

-- pokeemerald/src/battle_pyramid.c:1635
function Pyramid.entranceAndExit(sess)
  local r = Pyramid.frontier(sess).pyramidRandoms
  local n = Pyramid.NUM_SQUARES
  local entrance = (tonumber(r[4]) or 0) % n
  local exit = (tonumber(r[1]) or 0) % n
  if entrance == exit then
    entrance = ((tonumber(r[4]) or 0) + 1) % n
    exit = ((tonumber(r[1]) or 0) + n - 1) % n
  end
  return entrance, exit
end

local function mapIdForSquare(offset)
  return string.format("EM_BATTLE_PYRAMID_SQUARE%02d", offset + 1)
end
Pyramid.mapIdForSquare = mapIdForSquare

local looseDefs = {}

local function mapDef(mapId)
  local Runtime = package.loaded["src.core.game3.runtime"]
  local game = Runtime and Runtime._game
  local def = game and game.data and game.data.maps and game.data.maps[mapId]
  if not def then
    def = looseDefs[mapId] or {}
    looseDefs[mapId] = def
  end
  if not def.midLayout then
    require("src.core.game3.dataset").attachMidLayouts({ [mapId] = def })
  end
  return def
end
Pyramid.mapDef = mapDef

local function squareCells(offset)
  local def = mapDef(mapIdForSquare(offset))
  local L = def and def.midLayout
  if not L then error("pyramid: no layout for " .. mapIdForSquare(offset), 0) end
  return L
end

local function bundleEvents(mapId)
  local Space = package.loaded["src.core.game3.scripting.space"]
  local bundle = Space and (Space.bundle or (Space.ensureBundle and Space.ensureBundle(nil)))
  return bundle and bundle.events and bundle.events[mapId]
end

local function squareObjects(offset)
  local ev = bundleEvents(mapIdForSquare(offset))
  return ev and (ev.objects or ev.objectEvents) or {}
end

-- pokeemerald/src/battle_pyramid.c:1523
function Pyramid.composeLayout(sess, baseLayout, keepPosition)
  local LayoutNative = require("src.core.game3.layout_native")
  local exitMid = C(sess):require("metatile_labels", "METATILE_BattlePyramid_Exit")
  local floorMid = C(sess):require("metatile_labels", "METATILE_BattlePyramid_Floor")
  local offsets = Pyramid.layoutOffsets(sess)
  local entrance, exit = Pyramid.entranceAndExit(sess)
  local S = Pyramid.SQUARE_SIZE
  local W = S * Pyramid.SQUARES_WIDE
  local H = S * Pyramid.SQUARES_HIGH
  local cells = {}
  local px, py
  for i = 0, Pyramid.NUM_SQUARES - 1 do
    local src = squareCells(offsets[i + 1])
    local ox, oy = (i % Pyramid.SQUARES_WIDE) * S, math.floor(i / Pyramid.SQUARES_WIDE) * S
    for y = 0, S - 1 do
      for x = 0, S - 1 do
        local c = src.cells[y * src.width + x + 1]
          or error(("pyramid square %d has no cell at %d,%d"):format(i, x, y))
        local out = { mid = c.mid, coll = c.coll, elev = c.elev }
        if c.mid == exitMid and i ~= exit then
          if i == entrance and not keepPosition then px, py = ox + x, oy + y end
          out.mid = floorMid
        end
        cells[(oy + y) * W + ox + x + 1] = out
      end
    end
  end
  local layout = LayoutNative.fromDecoded({
    width = W, height = H, trueWidth = W, trueHeight = H,
    borderWidth = baseLayout and baseLayout.borderWidth or 1,
    borderHeight = baseLayout and baseLayout.borderHeight or 1,
    borderMids = baseLayout and baseLayout.borderMids or { 0 },
    cells = cells,
  }, Pyramid.FLOOR_MAP, baseLayout and baseLayout.pair)
  return layout, px, py
end

-- pokeemerald/src/battle_pyramid.c:1854
local function trySetAtCoords(sess, st, objType, x, y, offsets, squareId, objectEventId)
  local ball = C(sess):require("event_objects", "OBJ_EVENT_GFX_ITEM_BALL")
  local S = Pyramid.SQUARE_SIZE
  local sx, sy = (squareId % Pyramid.SQUARES_WIDE) * S, math.floor(squareId / Pyramid.SQUARES_WIDE) * S
  for _, obj in ipairs(squareObjects(offsets[squareId + 1])) do
    local gfx = tonumber(obj.graphicsId or obj.graphics) or 0
    local ok = obj.x == x and obj.y == y
    if ok and not ((objType == Pyramid.OBJ_TRAINERS and gfx ~= ball) or (objType == Pyramid.OBJ_ITEMS and gfx == ball)) then
      ok = false
    end
    if ok then
      local j = 0
      while j < objectEventId do
        local t = st.templates[j + 1]
        if t and t.x == x + sx and t.y == y + sy then break end
        j = j + 1
      end
      if j == objectEventId then
        local t = {}
        for k, v in pairs(obj) do t[k] = v end
        t.x, t.y = x + sx, y + sy
        t.localId, t.index = objectEventId + 1, objectEventId + 1
        if gfx ~= ball then
          local tid = Pyramid.uniqueTrainerId(sess, st, objectEventId)
          t.graphicsId = D.gfxId(sess, tid, F.PYRAMID)
          t.graphics = t.graphicsId
          t.trainerId = 0
          st.f.trainerIds[objectEventId + 1] = tid
        end
        st.templates[objectEventId + 1] = t
        return false
      end
    end
  end
  return true
end

-- pokeemerald/src/battle_pyramid.c:1824
local function trySetInSquare(sess, st, objType, offsets, squareId, objectEventId)
  if bit.band(tonumber(st.f.pyramidRandoms[1]) or 0, 1) ~= 0 then
    for y = 7, 0, -1 do
      for x = 7, 0, -1 do
        if not trySetAtCoords(sess, st, objType, x, y, offsets, squareId, objectEventId) then return false end
      end
    end
  else
    for y = 0, 7 do
      for x = 0, 7 do
        if not trySetAtCoords(sess, st, objType, x, y, offsets, squareId, objectEventId) then return false end
      end
    end
  end
  return true
end

-- pokeemerald/src/battle_pyramid.c:1488
function Pyramid.uniqueTrainerId(sess, st, objectEventId)
  local Tower = require("src.core.game3.rse.frontier.tower")
  local challengeNum = math.floor(streak(sess) / D.STAGES_PER_CHALLENGE)
  local floor = floorNum(sess)
  if floor == D.STAGES_PER_CHALLENGE then challengeNum = challengeNum + 1 end
  while true do
    local tid = Tower.randomScaledTrainerId(challengeNum, floor)
    local dup = false
    for i = 1, objectEventId do
      if st.f.trainerIds[i] == tid then dup = true break end
    end
    if not dup then return tid end
  end
end

local function counts(sess, objType)
  local tpl = Pyramid.floorTemplate(sess)
  if objType == Pyramid.OBJ_TRAINERS then return tpl.numTrainers, 0 end
  return tpl.numItems, tpl.numTrainers
end

-- pokeemerald/src/battle_pyramid.c:1647
local function placeUniformly(sess, st, objType, offsets)
  local r = st.f.pyramidRandoms
  local n = Pyramid.NUM_SQUARES
  local numObjects, start = counts(sess, objType)
  local squareId = (tonumber(r[3]) or 0) % n
  local bits = 0
  for i = 0, numObjects - 1 do
    repeat
      repeat
        local inR3 = bit.band(bit.lshift(1, squareId), tonumber(r[4]) or 0) ~= 0
        if bit.band(bits, 1) ~= 0 then
          if not inR3 then bits = bit.bor(bits, 2) end
        else
          if inR3 then bits = bit.bor(bits, 2) end
        end
        squareId = squareId + 1
        if squareId >= n then squareId = 0 end
        if squareId == (tonumber(r[3]) or 0) % n then
          if bit.band(bits, 1) ~= 0 then bits = bit.bor(bits, 6) else bits = bit.bor(bits, 1) end
        end
      until bit.band(bits, 2) ~= 0
    until not (bit.band(bits, 4) == 0 and trySetInSquare(sess, st, objType, offsets, squareId, start + i))
    bits = bit.band(bits, 1)
  end
end

local function nextBordered(squareId, idx)
  local row = Pyramid.manifest().borderedSquares[squareId + 1]
  idx = idx + 1
  if idx >= 4 or row[idx + 1] == -1 or row[idx + 1] == 0xFF then idx = 0 end
  return idx
end

local function bordered(squareId, idx)
  return Pyramid.manifest().borderedSquares[squareId + 1][idx + 1]
end

-- pokeemerald/src/battle_pyramid.c:1704
local function placeInAndNear(sess, st, objType, offsets, squareId)
  local numObjects, start = counts(sess, objType)
  local bIdx, r7, placed = 0, 0, 0
  for i = 0, numObjects - 1 do
    if r7 == 0 then
      if trySetInSquare(sess, st, objType, offsets, squareId, start + i) then r7 = 1 else placed = placed + 1 end
    end
    if bit.band(r7, 1) ~= 0 then
      if trySetInSquare(sess, st, objType, offsets, bordered(squareId, bIdx), start + i) then
        repeat
          bIdx = nextBordered(squareId, bIdx)
          r7 = r7 + 2
        until not (bit.rshift(r7, 1) ~= 4
          and trySetInSquare(sess, st, objType, offsets, bordered(squareId, bIdx), start + i))
        placed = placed + 1
      else
        bIdx = nextBordered(squareId, bIdx)
        placed = placed + 1
      end
    end
    if bit.rshift(r7, 1) == 4 then break end
    r7 = bit.band(r7, 1)
  end
  return math.floor(numObjects / 2) > placed
end

-- pokeemerald/src/battle_pyramid.c:1770
local function placeNear(sess, st, objType, offsets, squareId)
  local numObjects, start = counts(sess, objType)
  local bIdx, placed, r8 = 0, 0, 0
  for i = 0, numObjects - 1 do
    if trySetInSquare(sess, st, objType, offsets, bordered(squareId, bIdx), start + i) then
      repeat
        bIdx = nextBordered(squareId, bIdx)
        r8 = r8 + 1
      until not (r8 ~= 4 and trySetInSquare(sess, st, objType, offsets, bordered(squareId, bIdx), start + i))
      placed = placed + 1
    else
      bIdx = nextBordered(squareId, bIdx)
      placed = placed + 1
    end
    if r8 == 4 then break end
  end
  return math.floor(numObjects / 2) > placed
end

-- pokeemerald/src/battle_pyramid.c:1575
function Pyramid.loadObjectTemplates(sess)
  local f = Pyramid.frontier(sess)
  for i = 1, Pyramid.MAX_TRAINERS do f.trainerIds[i] = 0xFFFF end
  local tpl = Pyramid.floorTemplate(sess)
  local entrance, exit = Pyramid.entranceAndExit(sess)
  local offsets = Pyramid.layoutOffsets(sess)
  local st = { f = f, templates = {} }
  for objType = 0, 1 do
    local kind = objType == Pyramid.OBJ_TRAINERS and tpl.trainerPositions or tpl.itemPositions
    local P = Pyramid.POS
    if kind == P.UNIFORM then
      placeUniformly(sess, st, objType, offsets)
    elseif kind == P.IN_AND_NEAR_ENTRANCE then
      if placeInAndNear(sess, st, objType, offsets, entrance) then placeUniformly(sess, st, objType, offsets) end
    elseif kind == P.IN_AND_NEAR_EXIT then
      if placeInAndNear(sess, st, objType, offsets, exit) then placeUniformly(sess, st, objType, offsets) end
    elseif kind == P.NEAR_ENTRANCE then
      if placeNear(sess, st, objType, offsets, entrance) then placeUniformly(sess, st, objType, offsets) end
    elseif kind == P.NEAR_EXIT then
      if placeNear(sess, st, objType, offsets, exit) then placeUniformly(sess, st, objType, offsets) end
    end
  end
  local out = {}
  for i = 1, Pyramid.MAX_TRAINERS + 10 do
    if st.templates[i] then out[#out + 1] = st.templates[i] else break end
  end
  Pyramid.applyObjectScripts(sess, out)
  f.pyramidObjects = out
  return out
end

-- pokeemerald/src/battle_pyramid.c:1621
function Pyramid.injectScripts(extra)
  if type(extra) ~= "table" then return false end
  local Space = package.loaded["src.core.game3.scripting.space"] or require("src.core.game3.scripting.space")
  local b = Space.bundle or (Space.ensureBundle and Space.ensureBundle(nil))
  if not (b and b.scripts) then return false end
  if b._f4Injected and b._f4Injected[extra] then return true end
  for k, rows in pairs(extra.scripts or {}) do
    if rawget(b.scripts, k) == nil then b.scripts[k] = rows end
  end
  b.text = b.text or {}
  for k, ir in pairs(extra.text or {}) do
    if b.text[k] == nil then b.text[k] = ir end
  end
  b.movements = b.movements or {}
  for k, mv in pairs(extra.movements or {}) do
    if b.movements[k] == nil then b.movements[k] = mv end
  end
  b.labels = b.labels or {}
  for label, k in pairs(extra.labels or {}) do
    if b.labels[label] == nil then b.labels[label] = k end
  end
  b._f4Injected = b._f4Injected or setmetatable({}, { __mode = "k" })
  b._f4Injected[extra] = true
  return true
end

function Pyramid.scriptKey(label)
  local Space = package.loaded["src.core.game3.scripting.space"] or require("src.core.game3.scripting.space")
  local okM, man = pcall(Pyramid.manifest)
  if okM and man then Pyramid.injectScripts(man.extraScripts) end
  local okH, Hill = pcall(require, "src.core.game3.rse.trainer_hill")
  if okH and Hill and Hill.manifest then
    local okHm, hm = pcall(Hill.manifest)
    if okHm and hm then Pyramid.injectScripts(hm.extraScripts) end
  end
  local key = Space.scriptKey(label)
  if key then return key end
  local b = Space.bundle or (Space.ensureBundle and Space.ensureBundle(nil))
  local k = b and b.labels and b.labels[label]
  if k and b.scripts and b.scripts[k] then return k end
  return nil
end

-- pokeemerald/src/battle_pyramid.c:1621
function Pyramid.applyObjectScripts(sess, templates)
  local ball = C(sess):require("event_objects", "OBJ_EVENT_GFX_ITEM_BALL")
  local trainerKey = Pyramid.scriptKey("BattlePyramid_TrainerBattle")
  local itemKey = Pyramid.scriptKey("BattlePyramid_FindItemBall")
  for _, t in ipairs(templates) do
    local gfx = tonumber(t.graphicsId or t.graphics) or 0
    local key = (gfx ~= ball) and trainerKey or itemKey
    if key then t.scriptKey = key end
  end
end

function Pyramid.installObjects(sess, templates)
  local ev = bundleEvents(Pyramid.FLOOR_MAP)
  if not ev then return false end
  local rows = {}
  for i, t in ipairs(templates or {}) do
    local r = {}
    for k, v in pairs(t) do r[k] = v end
    rows[i] = r
  end
  ev.objects = rows
  return true
end

-- pokeemerald/src/overworld.c:836
function Pyramid.onMapLoad(sess, mapId, def, opts)
  sess = sess or Rse.session()
  if not (sess and Rse.isRse(sess)) or mapId ~= Pyramid.FLOOR_MAP or not def then return false end
  opts = opts or {}
  local Map = package.loaded["src.core.game3.map"]
  local via = opts.enterVia or (Map and Map._nextEnterVia)
  local continuing = via == "continue" or opts.initialLoad == true
  def._pyramidBase = def._pyramidBase or def.midLayout
  local layout, px, py = Pyramid.composeLayout(sess, def._pyramidBase, continuing)
  def.midLayout = layout
  def.width, def.height = layout.width, layout.height
  local f = Pyramid.frontier(sess)
  if continuing and type(f.pyramidObjects) == "table" and #f.pyramidObjects > 0 then
    Pyramid.applyObjectScripts(sess, f.pyramidObjects)
    Pyramid.installObjects(sess, f.pyramidObjects)
  else
    Pyramid.installObjects(sess, Pyramid.loadObjectTemplates(sess))
  end
  if px and not continuing then
    opts.x, opts.y = px, py
  end
  local Runtime = package.loaded["src.core.game3.runtime"]
  local game = Runtime and Runtime._game
  local Collision = package.loaded["src.core.game3.collision"]
  if Collision and Collision.bindMap and game then pcall(Collision.bindMap, game, mapId, def) end
  local FieldView = package.loaded["src.core.game3.field_view"]
  if FieldView then FieldView._nativeDirty = true end
  Pyramid._composed = { map = mapId, entrance = { px, py } }
  return true
end

-- pokeemerald/src/battle_pyramid.c:1308
function Pyramid.localIdToTrainerId(sess, localId)
  return tonumber(Pyramid.frontier(sess).trainerIds[(tonumber(localId) or 0)]) or 0xFFFF
end

-- pokeemerald/src/battle_pyramid.c:1313
function Pyramid.trainerFlag(sess, localId)
  local lid = tonumber(localId) or 0
  if lid < 1 then return false end
  return bit.band(Pyramid.frontier(sess).pyramidTrainerFlags, bit.lshift(1, lid - 1)) ~= 0
end

local function movementRaw(sess, name)
  return C(sess):require("movement", name)
end

-- pokeemerald/src/battle_pyramid.c:1328
function Pyramid.markBattled(sess, trainerId, localId)
  local f = Pyramid.frontier(sess)
  for i = 1, Pyramid.MAX_TRAINERS do
    if f.trainerIds[i] == trainerId then f.pyramidTrainerFlags = bit.bor(f.pyramidTrainerFlags, bit.lshift(1, i - 1)) end
  end
  local wander = movementRaw(sess, "MOVEMENT_TYPE_WANDER_AROUND")
  local Objects = package.loaded["src.core.game3.objects"]
  local eo = Objects and Objects.find and Objects.find(localId)
  local tpl
  for _, t in ipairs(f.pyramidObjects or {}) do
    if tonumber(t.localId) == tonumber(localId) then tpl = t end
  end
  if tpl then
    tpl.movementType = wander
    tpl.trainerType = 0
    if eo then tpl.x, tpl.y = eo.cellX, eo.cellY end
  end
  if eo then
    eo.trainerType = 0
    if Objects.setTrainerMovementType then Objects.setTrainerMovementType(eo, wander) end
    eo.homeX, eo.homeY = eo.cellX, eo.cellY
    if eo.def then
      eo.def.trainerType = 0
      eo.def.movementType = wander
      eo.def.x, eo.def.y = eo.cellX, eo.cellY
    end
  end
  Pyramid.installObjects(sess, f.pyramidObjects)
end

-- pokeemerald/src/battle_pyramid.c:840
function Pyramid.init(sess)
  local f = Pyramid.frontier(sess)
  local lvl = lvlMode(sess)
  f.challengeStatus = 0
  f.curChallengeBattleNum = 0
  f.challengePaused = 0
  if not Util.isWinStreakActive(sess, streakFlag(lvl)) then
    Util.set1(f.pyramidWinStreaks, lvl, 0)
    Pyramid.initBag(sess, lvl)
  end
  Pyramid.bagCursor = { cursor = 0, scroll = 0 }
  sess.frontierOpponentA = 0
  sess.battleOutcome = 0
end

-- pokeemerald/src/battle_pyramid.c:864
function Pyramid.getData(ctx, sess)
  local f = Pyramid.frontier(sess)
  local lvl = lvlMode(sess)
  local which = specialVar(ctx, Util.VAR_0x8005)
  local Dd = Pyramid.DATA
  local flags = tonumber(f.winStreakActiveFlags) or 0
  if which == Dd.PRIZE then setResult(ctx, tonumber(f.pyramidPrize) or 0)
  elseif which == Dd.WIN_STREAK then setResult(ctx, Util.get1(f.pyramidWinStreaks, lvl))
  elseif which == Dd.WIN_STREAK_ACTIVE then setResult(ctx, bit.band(flags, streakFlag(lvl)))
  elseif which == Dd.WIN_STREAK_50 then setResult(ctx, Util.get1(f.pyramidWinStreaks, D.LVL.L50))
  elseif which == Dd.WIN_STREAK_OPEN then setResult(ctx, Util.get1(f.pyramidWinStreaks, D.LVL.OPEN))
  elseif which == Dd.WIN_STREAK_ACTIVE_50 then setResult(ctx, bit.band(flags, Util.STREAK.PYRAMID_50))
  elseif which == Dd.WIN_STREAK_ACTIVE_OPEN then setResult(ctx, bit.band(flags, Util.STREAK.PYRAMID_OPEN))
  end
end

-- pokeemerald/src/battle_pyramid.c:897
function Pyramid.setData(ctx, sess)
  local f = Pyramid.frontier(sess)
  local lvl = lvlMode(sess)
  local which = specialVar(ctx, Util.VAR_0x8005)
  local v = specialVar(ctx, Util.VAR_0x8006)
  local Dd = Pyramid.DATA
  if which == Dd.PRIZE then f.pyramidPrize = v
  elseif which == Dd.WIN_STREAK then Util.set1(f.pyramidWinStreaks, lvl, v)
  elseif which == Dd.WIN_STREAK_ACTIVE then
    local flags = tonumber(f.winStreakActiveFlags) or 0
    if v ~= 0 then flags = bit.bor(flags, streakFlag(lvl)) else flags = bit.band(flags, bit.bnot(streakFlag(lvl))) end
    f.winStreakActiveFlags = flags
  elseif which == Dd.TRAINER_FLAGS then f.pyramidTrainerFlags = v % 256
  end
end

-- pokeemerald/src/battle_pyramid.c:931
function Pyramid.save(ctx, sess)
  local f = Util.frontier(sess)
  return Util.saveChallengeInPlace(sess, "VAR_TEMP_CHALLENGE_STATUS", function()
    f.challengeStatus = specialVar(ctx, Util.VAR_0x8005)
    Rse.setVar("VAR_TEMP_CHALLENGE_STATUS", 0, sess)
    f.challengePaused = 1
  end)
end

-- pokeemerald/src/battle_pyramid.c:940
function Pyramid.setPrize(sess)
  local f = Pyramid.frontier(sess)
  local man = Pyramid.manifest()
  local list = streak(sess) > Pyramid.LONG_STREAK and man.longStreakRewards or man.shortStreakRewards
  f.pyramidPrize = list[(rng().Random() % #list) + 1]
end

-- pokeemerald/src/battle_pyramid.c:948
function Pyramid.givePrize(ctx, adapters, sess)
  local f = Pyramid.frontier(sess)
  local Bag = require("src.core.game3.bag")
  local item = tonumber(f.pyramidPrize) or 0
  if item ~= 0 and Bag.add(sess.bag, item, 1) then
    local ItemsData = require("src.core.game3.items_data")
    Util.setStringVar(ctx, adapters, 1, ItemsData.displayName(item))
    f.pyramidPrize = 0
    setResult(ctx, 1)
  else
    setResult(ctx, 0)
  end
end

-- pokeemerald/src/battle_pyramid.c:962
function Pyramid.seedFloor(sess)
  local f = Pyramid.frontier(sess)
  for i = 1, 4 do f.pyramidRandoms[i] = rng().Random() end
  f.pyramidTrainerFlags = 0
  f.pyramidObjects = nil
end

-- pokeemerald/src/battle_pyramid.c:972
function Pyramid.setItem(ctx, sess)
  local f = Pyramid.frontier(sess)
  local man = Pyramid.manifest()
  local lvl = lvlMode(sess)
  local floor = floorNum(sess)
  local round = Pyramid.round(sess)
  local tpl = Pyramid.floorTemplate(sess)
  local lastTalked = specialVar(ctx, Util.VAR_LAST_TALKED)
  local itemIndex = lastTalked - tpl.numTrainers - 1
  local Rng = rng()
  local rand = tonumber(f.pyramidRandoms[math.floor(itemIndex / 2) + 1]) or 0
  Rng.SeedRng2(rand)
  for _ = 0, itemIndex do rand = Rng.Random2() % 100 end
  local slots = man.pickupItemSlots
  local i = (man.pickupItemOffsets[floor + 1] or 0) + 1
  while i <= #slots do
    if rand < slots[i][1] then break end
    i = i + 1
  end
  if i > #slots then i = #slots end
  local tables = lvl ~= D.LVL.L50 and man.pickupItemsOpen or man.pickupItems50
  setSpecialVar(ctx, Pyramid.VAR_0x8000, tables[round + 1][slots[i][2] + 1])
  setSpecialVar(ctx, Pyramid.VAR_0x8001, 1)
end

-- pokeemerald/src/battle_pyramid.c:1008
function Pyramid.hideItem(ctx, sess)
  local f = Pyramid.frontier(sess)
  local lastTalked = specialVar(ctx, Util.VAR_LAST_TALKED)
  for _, t in ipairs(f.pyramidObjects or {}) do
    if tonumber(t.localId) == lastTalked then
      t.x, t.y = Pyramid.HIDDEN_COORD, Pyramid.HIDDEN_COORD
      break
    end
  end
  Pyramid.installObjects(sess, f.pyramidObjects)
end

local function remainingItems(sess)
  local ball = C(sess):require("event_objects", "OBJ_EVENT_GFX_ITEM_BALL")
  local n = 0
  for _, t in ipairs(Pyramid.frontier(sess).pyramidObjects or {}) do
    if (tonumber(t.graphicsId or t.graphics) or 0) == ball and t.x ~= Pyramid.HIDDEN_COORD and t.y ~= Pyramid.HIDDEN_COORD then
      n = n + 1
    end
  end
  return n
end
Pyramid.remainingItems = remainingItems

local function remainingTrainers(sess)
  local n = Pyramid.floorTemplate(sess).numTrainers
  local flags = Pyramid.frontier(sess).pyramidTrainerFlags
  for i = 0, Pyramid.MAX_TRAINERS - 1 do
    if bit.band(flags, bit.lshift(1, i)) ~= 0 then n = n - 1 end
  end
  return n
end
Pyramid.remainingTrainers = remainingTrainers

-- pokeemerald/src/battle_pyramid.c:1230
function Pyramid.directionHint(sess, eo, minDistance, defaultType)
  local exitMid = C(sess):require("metatile_labels", "METATILE_BattlePyramid_Exit")
  local Map = package.loaded["src.core.game3.map"]
  local def = Map and Map._def
  local L = def and def.midLayout
  if not L then return defaultType, 0 end
  local ix = eo and (eo.def and tonumber(eo.def.x) or eo.homeX or eo.cellX) or 0
  local iy = eo and (eo.def and tonumber(eo.def.y) or eo.homeY or eo.cellY) or 0
  if eo and eo.homeX then ix, iy = eo.homeX, eo.homeY end
  for y = 0, 31 do
    for x = 0, 31 do
      if L:midAt(x, y) == exitMid then
        local dx, dy = x - ix, y - iy
        local idx = 0
        if dx >= minDistance or dx <= -minDistance or dy >= minDistance or dy <= -minDistance
            or defaultType == Pyramid.HINT.EXIT_DIRECTION then
          if dx > 0 and dy > 0 then idx = (dx >= dy) and 2 or 3
          elseif dx < 0 and dy < 0 then idx = (dx > dy) and 0 or 1
          elseif dx == 0 then idx = (dy > 0) and 3 or 0
          elseif dy == 0 then idx = (dx > 0) and 2 or 1
          elseif dx < 0 then idx = (dx + dy > 0) and 3 or 1
          else idx = (dx + dy >= 0) and 2 or 0
          end
          return Pyramid.HINT.EXIT_DIRECTION, idx
        end
        return defaultType, idx
      end
    end
  end
  return defaultType, 0
end

-- pokeemerald/src/battle_pyramid.c:1033
function Pyramid.hintText(sess, localId)
  local man = Pyramid.manifest()
  local H = Pyramid.HINT
  local tid = Pyramid.localIdToTrainerId(sess, localId)
  local fc = D.facilityClass(sess, tid, F.PYRAMID)
  local group = 0
  for _, row in ipairs(man.textGroups) do
    if row[1] == fc then group = row[2] break end
  end
  local Objects = package.loaded["src.core.game3.objects"]
  local eo = Objects and Objects.find and Objects.find(localId)
  local hintType = man.hintTextTypes[localId] or H.REMAINING_TRAINERS
  local idx = 0
  local steps = 0
  while steps < 4 do
    steps = steps + 1
    if hintType == H.EXIT_DIRECTION then
      hintType, idx = Pyramid.directionHint(sess, eo, 8, H.EXIT_DIRECTION)
      break
    elseif hintType == H.REMAINING_ITEMS then
      idx = remainingItems(sess)
      break
    elseif hintType == H.REMAINING_TRAINERS then
      idx = remainingTrainers(sess)
      break
    elseif hintType == H.EXIT_SHORT_REMAINING_TRAINERS then hintType = Pyramid.directionHint(sess, eo, 8, H.REMAINING_TRAINERS)
    elseif hintType == H.EXIT_SHORT_REMAINING_ITEMS then hintType = Pyramid.directionHint(sess, eo, 8, H.REMAINING_ITEMS)
    elseif hintType == H.EXIT_MEDIUM_REMAINING_TRAINERS then hintType = Pyramid.directionHint(sess, eo, 16, H.REMAINING_TRAINERS)
    elseif hintType == H.EXIT_MEDIUM_REMAINING_ITEMS then hintType = Pyramid.directionHint(sess, eo, 16, H.REMAINING_ITEMS)
    elseif hintType == H.EXIT_FAR_REMAINING_TRAINERS then hintType = Pyramid.directionHint(sess, eo, 24, H.REMAINING_TRAINERS)
    elseif hintType == H.EXIT_FAR_REMAINING_ITEMS then hintType = Pyramid.directionHint(sess, eo, 24, H.REMAINING_ITEMS)
    else break
    end
  end
  local list = man.postBattleTexts[group + 1][hintType + 1]
  local ref = list[idx + 1] or list[1]
  return ref.ir, hintType, idx
end

-- pokeemerald/src/battle_pyramid.c:1033
function Pyramid.showHint(ctx, adapters, sess)
  local ir = Pyramid.hintText(sess, specialVar(ctx, Util.VAR_LAST_TALKED))
  Util.showFieldMessage(ctx, adapters, ir)
end

-- pokeemerald/src/battle_pyramid.c:1103
function Pyramid.updateStreak(sess)
  local f = Pyramid.frontier(sess)
  local lvl = lvlMode(sess)
  local s = Util.get1(f.pyramidWinStreaks, lvl)
  if s < Pyramid.MAX_STREAK then s = s + 1 end
  Util.set1(f.pyramidWinStreaks, lvl, s)
  if s > Util.get1(f.pyramidRecordStreaks, lvl) then Util.set1(f.pyramidRecordStreaks, lvl, s) end
end

local function playSe(id)
  local okA, Audio = pcall(require, "src.core.game3.audio")
  if okA and Audio and Audio.playSe then pcall(Audio.playSe, id) end
end

local function fadeActive()
  local okF, Fade = pcall(require, "src.ui.game3.fade")
  return okF and Fade and Fade.isActive and Fade.isActive() or false
end

local function applyLight(sess)
  local FieldView = package.loaded["src.core.game3.field_view"]
  if FieldView and FieldView.setPyramidLightRadius then
    FieldView.setPyramidLightRadius(Pyramid.frontier(sess).pyramidLightRadius)
  end
end
Pyramid.applyLight = applyLight

-- pokeemerald/src/battle_pyramid.c:1118
function Pyramid.updateLight(ctx, sess)
  local f = Pyramid.frontier(sess)
  local mode = specialVar(ctx, Util.VAR_0x8006)
  if mode == Pyramid.LIGHT.SET_RADIUS then
    f.pyramidLightRadius = specialVar(ctx, Util.VAR_0x8005)
    applyLight(sess)
  elseif mode == Pyramid.LIGHT.INCR_RADIUS then
    local r = specialVar(ctx, Util.VAR_RESULT)
    if r == 0 then
      if not fadeActive() then
        if f.pyramidLightRadius >= Pyramid.MAX_LIGHT_RADIUS then
          f.pyramidLightRadius = Pyramid.MAX_LIGHT_RADIUS
        else
          playSe(specialVar(ctx, Pyramid.VAR_0x8007))
        end
        setResult(ctx, 1)
      end
    elseif r == 1 then
      local n = specialVar(ctx, Util.VAR_0x8005)
      if n ~= 0 then
        setSpecialVar(ctx, Util.VAR_0x8005, n - 1)
        f.pyramidLightRadius = f.pyramidLightRadius + 1
        if f.pyramidLightRadius > Pyramid.MAX_LIGHT_RADIUS then
          f.pyramidLightRadius = Pyramid.MAX_LIGHT_RADIUS
          setResult(ctx, 2)
        end
        applyLight(sess)
      else
        setResult(ctx, 2)
      end
    end
  end
end

local function heldItem(mon) return tonumber(mon and (mon.heldItem or mon.item)) or 0 end
local function setHeld(mon, item)
  if item == 0 then item = nil end
  mon.item, mon.heldItem = item, item
end

-- pokeemerald/src/battle_pyramid.c:1163
function Pyramid.clearHeldItems(sess)
  local sel = Util.frontier(sess).selectedPartyMons or {}
  for i, mon in ipairs(sess.party or {}) do
    for j = 1, D.MAX_PARTY_SIZE do
      if (tonumber(sel[j]) or 0) ~= 0 and sel[j] == i then setHeld(mon, 0) end
    end
  end
end

-- pokeemerald/src/battle_pyramid.c:1183
function Pyramid.setFloorPalette(sess)
  local pals = Pyramid.manifest().floorPalettes
  Pyramid.floorPalette = pals[floorNum(sess) + 1] or pals[1]
  local FieldView = package.loaded["src.core.game3.field_view"]
  if FieldView and FieldView.setBgPaletteOverride then
    pcall(FieldView.setBgPaletteOverride, 6, Pyramid.floorPalette)
  end
  return Pyramid.floorPalette
end

local function sameMoves(a, b, sketch)
  local out = {}
  for k = 1, 4 do
    local mv = b.moves and b.moves[k]
    local found = false
    for l = 1, 4 do
      if a.moves and a.moves[l] == mv then found = true break end
    end
    out[k] = found and mv or sketch
  end
  return out
end

-- pokeemerald/src/battle_pyramid.c:1198
function Pyramid.restoreParty(sess)
  local f = Util.frontier(sess)
  local saved = sess.savedPlayerParty or {}
  local sketch = C(sess):require("moves", "MOVE_SKETCH")
  local order = {}
  for i = 1, D.PARTY_SIZE do
    local partyIndex = (tonumber(f.selectedPartyMons[i]) or 0)
    local src = saved[partyIndex]
    if src then
      for j = 1, D.PARTY_SIZE do
        local mon = sess.party and sess.party[j]
        if mon and tonumber(mon.species) == tonumber(src.species) then
          local moves = sameMoves(src, mon, sketch)
          for k = 1, 4 do
            if mon.moves and mon.moves[k] and moves[k] ~= mon.moves[k] then mon.moves[k] = sketch end
          end
          saved[partyIndex] = mon
          order[j] = partyIndex
          break
        end
      end
    end
  end
  for i = 1, D.PARTY_SIZE do f.selectedPartyMons[i] = order[i] or 0 end
end

-- pokeemerald/src/battle_pyramid.c:1439
function Pyramid.pause(sess)
  if not Pyramid.inPyramid(sess) then return false end
  Pyramid.restoreParty(sess)
  Util.frontier(sess).challengeStatus = Util.CHALLENGE_STATUS.PAUSED
  Rse.setVar("VAR_TEMP_PLAYING_PYRAMID_MUSIC", 0, sess)
  require("src.core.game3.scripting.natives_frontier_story").loadPlayerParty(sess)
  return true
end

-- pokeemerald/src/field_specials.c:3873
function Pyramid.hint(streakValue)
  local r = math.floor((tonumber(streakValue) or 0) / D.STAGES_PER_CHALLENGE)
  return r - math.floor(r / Pyramid.TOTAL_ROUNDS) * Pyramid.TOTAL_ROUNDS
end

-- pokeemerald/src/battle_pyramid.c:1417
function Pyramid.runMultiplier(sess)
  return Pyramid.floorTemplate(sess or Rse.session()).runMultiplier
end

-- pokeemerald/src/battle_pyramid.c:1958
function Pyramid.pickupItemId(sess)
  sess = sess or Rse.session()
  local man = Pyramid.manifest()
  local round = math.floor(streak(sess) / D.STAGES_PER_CHALLENGE)
  if round >= Pyramid.TOTAL_ROUNDS then round = Pyramid.TOTAL_ROUNDS - 1 end
  local rand = rng().Random() % 100
  local i = 1
  while i <= #man.pickupPercentages do
    if man.pickupPercentages[i] > rand then break end
    i = i + 1
  end
  if i > Pyramid.PICKUP_ITEMS_PER_ROUND then i = Pyramid.PICKUP_ITEMS_PER_ROUND end
  local tables = lvlMode(sess) ~= D.LVL.L50 and man.pickupItemsOpen or man.pickupItems50
  return tables[round + 1][i]
end

-- pokeemerald/src/battle_pyramid.c:1471
function Pyramid.encounterMusic(sess, trainerId)
  local man = Pyramid.manifest()
  local Tp = require("src.core.game3.scripting.trainers").pack() or {}
  local fc = D.facilityClass(sess, trainerId, F.PYRAMID)
  local cls = Tp.facilityClassToTrainerClass and Tp.facilityClassToTrainerClass[fc]
  local code
  for _, row in ipairs(man.encounterMusic) do
    if row[1] == cls then code = row[2] break end
  end
  local Cc = C(sess)
  local name = Cc:name("trainer_classes", code or 0, "TRAINER_ENCOUNTER_MUSIC_")
  local song = name and Cc:song("MUS_ENCOUNTER_" .. name:sub(#"TRAINER_ENCOUNTER_MUSIC_" + 1))
  return song or Cc:song("MUS_ENCOUNTER_MALE")
end

-- pokeemerald/src/battle_pyramid.c:1456
function Pyramid.speech(sess, trainerId, which)
  return D.trainerSpeech(sess, trainerId, which, F.PYRAMID)
end

-- pokeemerald/src/battle_pyramid.c:1944
function Pyramid.initBag(sess, lvl)
  local f = Pyramid.frontier(sess)
  lvl = lvl or lvlMode(sess)
  f.pyramidBag.itemId[lvl + 1] = zeros(Pyramid.BAG_ITEMS_COUNT)
  f.pyramidBag.quantity[lvl + 1] = zeros(Pyramid.BAG_ITEMS_COUNT)
  local Cc = C(sess)
  Pyramid.bagAdd(sess, Cc:require("items", "ITEM_HYPER_POTION"), 1)
  Pyramid.bagAdd(sess, Cc:require("items", "ITEM_ETHER"), 1)
end

local function bagLists(sess)
  local f = Pyramid.frontier(sess)
  local lvl = lvlMode(sess)
  if lvl > 1 then lvl = 0 end
  f.pyramidBag.itemId[lvl + 1] = f.pyramidBag.itemId[lvl + 1] or zeros(Pyramid.BAG_ITEMS_COUNT)
  f.pyramidBag.quantity[lvl + 1] = f.pyramidBag.quantity[lvl + 1] or zeros(Pyramid.BAG_ITEMS_COUNT)
  return f.pyramidBag.itemId[lvl + 1], f.pyramidBag.quantity[lvl + 1]
end
Pyramid.bagLists = bagLists

local function toId(item)
  if type(item) == "number" then return item end
  return require("src.core.game3.items_data").toNumericId(item) or 0
end

-- pokeemerald/src/item.c:685
function Pyramid.bagHas(sess, itemId, count)
  itemId, count = toId(itemId), tonumber(count) or 1
  local items, qty = bagLists(sess)
  for i = 1, Pyramid.BAG_ITEMS_COUNT do
    if items[i] == itemId then
      if qty[i] >= count then return true end
      count = count - qty[i]
      if count == 0 then return true end
    end
  end
  return false
end

-- pokeemerald/src/item.c:707
function Pyramid.bagHasSpace(sess, itemId, count)
  itemId, count = toId(itemId), tonumber(count) or 1
  local items, qty = bagLists(sess)
  for i = 1, Pyramid.BAG_ITEMS_COUNT do
    if items[i] == itemId or items[i] == 0 then
      if qty[i] + count <= Pyramid.MAX_BAG_ITEM_CAPACITY then return true end
      count = qty[i] + count - Pyramid.MAX_BAG_ITEM_CAPACITY
      if count == 0 then return true end
    end
  end
  return false
end

-- pokeemerald/src/item.c:729
function Pyramid.bagAdd(sess, itemId, count)
  itemId, count = toId(itemId), tonumber(count) or 1
  local items, qty = bagLists(sess)
  local ni, nq = {}, {}
  for i = 1, Pyramid.BAG_ITEMS_COUNT do ni[i], nq[i] = items[i], qty[i] end
  for i = 1, Pyramid.BAG_ITEMS_COUNT do
    if ni[i] == itemId and nq[i] < Pyramid.MAX_BAG_ITEM_CAPACITY then
      nq[i] = nq[i] + count
      if nq[i] > Pyramid.MAX_BAG_ITEM_CAPACITY then
        count = nq[i] - Pyramid.MAX_BAG_ITEM_CAPACITY
        nq[i] = Pyramid.MAX_BAG_ITEM_CAPACITY
      else
        count = 0
      end
      if count == 0 then break end
    end
  end
  if count > 0 then
    for i = 1, Pyramid.BAG_ITEMS_COUNT do
      if ni[i] == 0 then
        ni[i], nq[i] = itemId, count
        if nq[i] > Pyramid.MAX_BAG_ITEM_CAPACITY then
          count = nq[i] - Pyramid.MAX_BAG_ITEM_CAPACITY
          nq[i] = Pyramid.MAX_BAG_ITEM_CAPACITY
        else
          count = 0
        end
        if count == 0 then break end
      end
    end
  end
  if count ~= 0 then return false end
  for i = 1, Pyramid.BAG_ITEMS_COUNT do items[i], qty[i] = ni[i], nq[i] end
  return true
end

-- pokeemerald/src/item.c:802
function Pyramid.bagRemove(sess, itemId, count, slot)
  itemId, count = toId(itemId), tonumber(count) or 1
  local items, qty = bagLists(sess)
  local i = slot or (((Pyramid.bagCursor or {}).cursor or 0) + ((Pyramid.bagCursor or {}).scroll or 0) + 1)
  if items[i] == itemId and qty[i] >= count then
    qty[i] = qty[i] - count
    if qty[i] == 0 then items[i] = 0 end
    return true
  end
  local ni, nq = {}, {}
  for k = 1, Pyramid.BAG_ITEMS_COUNT do ni[k], nq[k] = items[k], qty[k] end
  for k = 1, Pyramid.BAG_ITEMS_COUNT do
    if ni[k] == itemId then
      if nq[k] >= count then
        nq[k] = nq[k] - count
        count = 0
        if nq[k] == 0 then ni[k] = 0 end
      else
        count = count - nq[k]
        nq[k] = 0
        ni[k] = 0
      end
      if count == 0 then break end
    end
  end
  if count ~= 0 then return false end
  for k = 1, Pyramid.BAG_ITEMS_COUNT do items[k], qty[k] = ni[k], nq[k] end
  return true
end

function Pyramid.bagCount(sess, itemId)
  itemId = toId(itemId)
  local items, qty = bagLists(sess)
  local n = 0
  for i = 1, Pyramid.BAG_ITEMS_COUNT do
    if items[i] == itemId then n = n + qty[i] end
  end
  return n
end

-- pokeemerald/src/battle_pyramid_bag.c:768
function Pyramid.compactBag(sess)
  local items, qty = bagLists(sess)
  for i = 1, Pyramid.BAG_ITEMS_COUNT do
    if items[i] == 0 or qty[i] == 0 then items[i], qty[i] = 0, 0 end
  end
  for i = 1, Pyramid.BAG_ITEMS_COUNT - 1 do
    for j = i + 1, Pyramid.BAG_ITEMS_COUNT do
      if items[i] == 0 or qty[i] == 0 then
        items[i], items[j] = items[j], items[i]
        qty[i], qty[j] = qty[j], qty[i]
      end
    end
  end
end

-- pokeemerald/src/battle_pyramid_bag.c:1402
function Pyramid.tryStoreHeldItems(ctx, sess)
  local items, qty = bagLists(sess)
  local ni, nq = {}, {}
  for i = 1, Pyramid.BAG_ITEMS_COUNT do ni[i], nq[i] = items[i], qty[i] end
  for i = 1, D.PARTY_SIZE do
    local mon = sess.party and sess.party[i]
    local item = heldItem(mon)
    if item ~= 0 and not Pyramid.bagAdd(sess, item, 1) then
      for k = 1, Pyramid.BAG_ITEMS_COUNT do items[k], qty[k] = ni[k], nq[k] end
      setResult(ctx, 1)
      return
    end
  end
  for i = 1, D.PARTY_SIZE do
    local mon = sess.party and sess.party[i]
    if mon then setHeld(mon, 0) end
  end
  setResult(ctx, 0)
end

-- pokeemerald/src/party_menu.c:6307
function Pyramid.monsHaveHeldItem(sess)
  for i = 1, D.PARTY_SIZE do
    if heldItem(sess.party and sess.party[i]) ~= 0 then return true end
  end
  return false
end

-- pokeemerald/src/battle_pyramid.c:1344
function Pyramid.generateWildMon(sess, enc)
  local man = Pyramid.manifest()
  local Pokemon = require("src.core.game3.pokemon")
  local lvl = lvlMode(sess)
  local round = Pyramid.round(sess)
  local list = (lvl ~= D.LVL.L50 and man.wildMonsOpen or man.wildMons50)[round + 1]
  local id = (tonumber(enc.species) or 1) - 1
  local row = list[id + 1] or list[1]
  local Rng = rng()
  local level
  if lvl ~= D.LVL.L50 then
    local _, facilityLevel = D.facilityPtrs(sess, F.PYRAMID)
    level = facilityLevel - row.lvl - 5 + (Rng.Random() % 11)
  else
    level = row.lvl - 5 + (Rng.Random() % 11)
  end
  if level < 1 then level = 1 end
  if level > 100 then level = 100 end
  local personality = Rng.Random32()
  local mon = D.createMon(row.species, level, 0, personality, Rng.Random32())
  local ivs = mon.ivs
  for _, k in ipairs(D.STAT_KEYS) do ivs[k] = Rng.Random() % 32 end
  local abilityNum
  if row.abilityNum == 0 or row.abilityNum == 1 then
    abilityNum = row.abilityNum
  else
    local pair = Pokemon.abilities(row.species) or {}
    abilityNum = ((pair[2] or 0) ~= 0) and (personality % 2) or 0
  end
  mon.abilityNum = abilityNum
  local pair = Pokemon.abilities(row.species) or {}
  mon.ability = pair[abilityNum + 1] or pair[1] or 0
  mon.abilityId = mon.ability
  D.setMoves(mon, row.moves)
  -- pokeemerald/src/battle_pyramid.c:1405
  if Util.get1(Util.frontier(sess).pyramidWinStreaks, level) >= Pyramid.WILD_HIGH_IV_STREAK then
    local iv = (Rng.Random() % 17) + 15
    for _, k in ipairs(D.STAT_KEYS) do ivs[k] = iv end
  end
  Pokemon.applyStats(mon)
  mon.hp = mon.maxHp
  return {
    species = row.species, level = level, personality = personality, moves = mon.moves,
    ivs = mon.ivs, ability = mon.ability, abilityNum = abilityNum,
  }
end

local function wildHeader(sess)
  local Encounters = require("src.core.game3.encounters")
  Pyramid._wildExtra = Pyramid._wildExtra or Encounters.loadCacheFile("wild_extra.lua")
  local sets = Pyramid._wildExtra and Pyramid._wildExtra.headerSets
  local headers = sets and sets.pyramid
  return headers and headers[floorNum(sess) + 1]
end
Pyramid.wildHeader = wildHeader

-- pokeemerald/src/wild_encounter.c:552
function Pyramid.standardWildEncounter(sess, cur, prev)
  local Encounters = require("src.core.game3.encounters")
  local R = Encounters.rules()
  local Rng = rng()
  local header = wildHeader(sess)
  local land = header and header.land
  if not land then return nil end
  -- pokeemerald/src/wild_encounter.c:533
  if prev ~= cur and not (Rng.Random() % 100 < 60) then return nil end
  -- pokeemerald/src/wild_encounter.c:493
  if not (Rng.Random() % 2880 < R.encounterRate(land.rate, { pyramidFloor = true })) then return nil end
  local enc = R.tryGenerate(land, "land", false, true)
  if not enc then return nil end
  return Pyramid.generateWildMon(sess, enc)
end

-- pokeemerald/src/wild_encounter.c:716
function Pyramid.sweetScentWildEncounter(sess)
  local Encounters = require("src.core.game3.encounters")
  local header = wildHeader(sess)
  local land = header and header.land
  if not land then return false end
  local enc = Encounters.rules().tryGenerate(land, "land", false, false)
  if not enc then return false end
  enc = Pyramid.generateWildMon(sess, enc)
  if not enc then return false end
  return Pyramid.startWildBattle(sess, enc) ~= false
end

-- pokeemerald/src/battle_setup.c:402
function Pyramid.startWildBattle(sess, enc)
  local Runtime = package.loaded["src.core.game3.runtime"]
  local BattleBridge = require("src.core.game3.battle_bridge")
  Rse.setVar("VAR_TEMP_PLAYING_PYRAMID_MUSIC", 0, sess)
  sess.battleOutcome = 0
  return BattleBridge.startWild(Runtime and Runtime._mod, Runtime and Runtime._game, enc, {
    pyramid = true,
    frontier = true,
    scriptedLoss = true,
    done = function(result)
      sess.battleOutcome = require("src.core.game3.scripting.natives").outcome_to_code(result or "win")
    end,
  })
end

-- pokeemerald/src/field_control_avatar.c:517
function Pyramid.onStep(sess, x, y)
  sess = sess or Rse.session()
  if not (sess and sess.map == Pyramid.FLOOR_MAP) then return false end
  local Collision = require("src.core.game3.collision")
  local MB = require("src.core.game3.mb")
  local beh = Collision.behavior(x, y)
  if beh == nil or beh ~= MB.id("BATTLE_PYRAMID_WARP") then return false end
  local Space = package.loaded["src.core.game3.scripting.space"] or require("src.core.game3.scripting.space")
  local key = Pyramid.scriptKey("BattlePyramid_WarpToNextFloor")
  Pyramid._lastStep = { x = x, y = y, key = key }
  if not key then return false end
  return Space.startScript(key, nil) ~= false
end

local function trainerBattleType(row)
  local Opcodes = require("src.core.game3.scripting.opcodes")
  return Opcodes.active():trainerBattleType(tonumber(row.type) or 0)
end

-- pokeemerald/data/scripts/trainer_battle.inc:9
function Pyramid.trainerBattle(vm, row)
  local ctx = vm.ctx
  local a = vm.adapters or {}
  local sess = Rse.session()
  local Flags = require("src.core.game3.scripting.flags")
  local lastTalked = tonumber(Flags.getVar(vm.store, ctx, Util.VAR_LAST_TALKED)) or 0
  if Pyramid.trainerFlag(sess, lastTalked) then return false end
  local tid = Pyramid.localIdToTrainerId(sess, lastTalked)
  sess.frontierOpponentA = tid
  Rse.setVar("VAR_TEMP_PLAYING_PYRAMID_MUSIC", 0, sess)
  local okA, Audio = pcall(require, "src.core.game3.audio")
  if okA and Audio and Audio.playSong then pcall(Audio.playSong, Pyramid.encounterMusic(sess, tid)) end
  local Objects = package.loaded["src.core.game3.objects"]
  local eo = Objects and Objects.find and Objects.find(lastTalked)
  local P = require("src.core.game3.player")
  if eo and Objects.scriptFace then
    local dx, dy = P.cellX - eo.cellX, P.cellY - eo.cellY
    local dir = (math.abs(dx) > math.abs(dy)) and (dx > 0 and "right" or "left") or (dy > 0 and "down" or "up")
    pcall(Objects.scriptFace, eo, dir)
  end
  local party = {}
  D.fillTrainerParty(sess, tid, 0, 1, party, { facility = F.PYRAMID })
  local Tower = require("src.core.game3.rse.frontier.tower")
  local intro = Util.textBox(Pyramid.speech(sess, tid, 0), ctx)
  ctx.mode = "native"
  ctx.status = "waiting"
  local stage = "intro"
  local lost = false
  ctx.nativePoll = function() return false end
  local function begin()
    stage = "battle"
    Pyramid.markBattled(sess, tid, lastTalked)
    Tower.startBattle(ctx, a, sess, "pyramid", {
      party = party,
      transitionId = D.specialTransition(sess, "B_PYRAMID", party),
    })
    local inner = ctx.nativePoll
    ctx.nativePoll = function()
      if inner and not inner() then return false end
      local N = require("src.core.game3.scripting.natives")
      local code = tonumber(sess.battleOutcome) or 1
      lost = code == N.outcome_to_code("lose") or code == N.outcome_to_code("draw")
      if lost then
        ctx.status = "halted"
        return false
      end
      return true
    end
  end
  if a.openMessageAsync then
    a.openMessageAsync(intro, function() begin() end)
  else
    begin()
  end
  return true
end

function Pyramid.installTrainerBattleHook()
  if Pyramid._tbHooked then return true end
  local okO, OpsRse = pcall(require, "src.core.game3.scripting.ops_rse")
  if not (okO and OpsRse and OpsRse.HANDLERS) then return false end
  local H = OpsRse.HANDLERS
  local prev = H.trainerbattle
  H.trainerbattle = function(vm, row, B)
    local kind = trainerBattleType(row)
    if kind == "PYRAMID" and Pyramid.inPyramid() then return Pyramid.trainerBattle(vm, row) end
    local Hill = Rse.system("trainerHill")
    if kind == "HILL" and Hill and Hill.trainerBattle and Hill.inChallengeMap and Hill.inChallengeMap() then
      return Hill.trainerBattle(vm, row)
    end
    if prev then return prev(vm, row, B) end
    return B.base(vm, row)
  end
  Pyramid._tbHooked = true
  return true
end

Pyramid.installTrainerBattleHook()

Rse.register("pyramid", Pyramid)

return Pyramid
