local RomText = require("src.core.game3.link.family").romText()

local Union = {}

local Family = require("src.core.game3.link.family")

local activityRows = {}

-- pokeemerald/include/constants/union_room.h:20
Union.ACTIVITY = setmetatable({}, {
  __index = function(_, k)
    local version = Family.activeVersion()
    local row = activityRows[version]
    if not row then
      row = Family.activity(version)
      activityRows[version] = row
    end
    return row[k]
  end,
})

-- pokefirered/include/constants/union_room.h:49
Union.IN_UNION_ROOM = 0x40
-- pokefirered/include/constants/union_room.h:51
Union.LINK_GROUP = {
  SINGLE_BATTLE = 0,
  DOUBLE_BATTLE = 1,
  MULTI_BATTLE = 2,
  TRADE = 3,
  POKEMON_JUMP = 4,
  BERRY_CRUSH = 5,
  BERRY_PICKING = 6,
  UNION_ROOM_RESUME = 9,
  UNION_ROOM_INIT = 10,
  -- pokeemerald/include/constants/union_room.h:70
  RECORD_CORNER = 12,
  BERRY_BLENDER = 13,
  COOL_CONTEST = 15,
  BEAUTY_CONTEST = 16,
  CUTE_CONTEST = 17,
  SMART_CONTEST = 18,
  TOUGH_CONTEST = 19,
  BATTLE_TOWER = 20,
  BATTLE_TOWER_OPEN = 21,
}

Union.Family = Family

local groupRows = {}

-- pokeemerald/src/data/union_room.h:641
Union.GROUP_ACTIVITY = setmetatable({}, {
  __index = function(_, group)
    local version = Family.activeVersion()
    local key = version .. "|" .. tostring(group)
    local row = groupRows[key]
    if row == nil then
      local g = Family.groupActivity(version, group)
      row = g and { activity = g.activity, min = g.min, max = g.max, name = g.name } or false
      groupRows[key] = row
    end
    return row or nil
  end,
})

function Union.activities(version)
  return Family.activity(version)
end

-- pokefirered/src/data/union_room.h:175
Union.INVITE_ITEMS = {
  { key = "GREETINGS", activity = Union.ACTIVITY.CARD, union = false, min = 0, max = 2 },
  { key = "BATTLE", activity = Union.ACTIVITY.BATTLE_SINGLE, union = true, min = 0, max = 2 },
  { key = "CHAT", activity = Union.ACTIVITY.CHAT, union = true, min = 0, max = 2 },
  { key = "EXIT", activity = Union.ACTIVITY.NONE, union = true },
}

Union.ACTIVITY_NAME_IDS = {
  -- pokefirered/src/data/union_room.h:1
  frlg = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 21, 22 },
  -- pokeemerald/src/data/union_room.h:592
  rse = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 14, 15, 16, 21, 22, 23, 24, 25, 26, 27, 28 },
}
Union.ACTIVITY_NAMES = setmetatable({}, {
  __index = function(_, raw)
    raw = tonumber(raw)
    for _, id in ipairs(Union.ACTIVITY_NAME_IDS[Family.of()] or {}) do
      if id == raw then return RomText.plain(RomText.key("sLinkGroupActivityNameTexts", id)) end
    end
    return nil
  end,
})

Union.AVATARS_FILE = "data/generated/gba/union_room/avatars.lua"
-- pokefirered/include/constants/global.h:110
Union.DIR = { NONE = 0, SOUTH = 1, NORTH = 2, WEST = 3, EAST = 4 }
Union.FACE_NAME = { [1] = "down", [2] = "up", [3] = "left", [4] = "right" }
Union.FACE_DIR = { down = 1, up = 2, left = 3, right = 4 }
-- pokefirered/include/link.h:7
Union.GROUP_SIZE = 5
-- pokefirered/src/event_object_movement.c:9316
Union.FLY_HEIGHT = 160
Union.FLY_STEP = 8
Union.VOBJ_BASE = 0x40
-- pokefirered/src/union_room.c:4255
Union.TRADING_BOARD = { x = 2, y = 1 }
-- pokefirered/include/constants/species.h:421
Union.SPECIES_EGG = 412

-- pokefirered/src/union_room_player_avatar.c:33
function Union.avatarData()
  if Union._avatars then return Union._avatars end
  local rel = Union.AVATARS_FILE
  local src = assert(require("src.core.game3.dataset").cache():read(rel), "no " .. rel .. " in the cache")
  Union._avatars = assert(load(src, "@" .. rel, "t", {}))()
  return Union._avatars
end

-- pokefirered/include/constants/union_room.h:82
Union.INTERACT_ATTENDANT = 9
Union.INTERACT_START_MENU_BY_FAMILY = {
  frlg = 10,
  -- pokeemerald/include/constants/union_room.h:100
  rse = 11,
}

setmetatable(Union, {
  __index = function(_, k)
    if k == "MAP" then return Family.mapId(nil, "unionRoom") end
    if k == "INTERACT_START_MENU" then
      return rawget(Union, "INTERACT_START_MENU_BY_FAMILY")[Family.of()]
    end
    return nil
  end,
})

Union.MSG = {
  HELLO = "game3_union_hello",
}

Union.AWAIT_ROOM_SECONDS = 20
Union.CARD_WAIT_SECONDS = 3

Union.WIRE_NAMES = setmetatable({}, {
  __index = function(_, activity)
    return Family.wireForActivity(nil, activity)
  end,
})

Union.state = "off"
Union.players = {}
Union.partnerId = nil
Union.activity = nil
Union.lastResult = nil
Union._name = nil
Union._pump = nil
Union._trade = nil
Union.relay = false
Union.memberIds = {}
Union.invite = nil
Union.incoming = nil
Union.direct = {}
Union._refresh = 0
Union._answered = {}
Union._await = nil
Union._vobjs = {}
Union._vobjDirty = false
Union.flow = nil

local function link()
  return require("src.core.game3.link")
end

local function battle()
  return require("src.core.game3.link.battle")
end

local function linkTrade()
  return require("src.core.game3.link.trade")
end

local function chat()
  return require("src.core.game3.link.chat")
end

local function screen()
  local ok, mod = pcall(require, "src.ui.game3.union_room")
  return ok and mod or nil
end

local function message()
  local ok, mod = pcall(require, "src.ui.game3.message")
  return ok and mod or nil
end

local function objects()
  return package.loaded["src.core.game3.objects"]
end

local function ctxOf(extra)
  return Union.textCtx(extra)
end

local function sfx(name)
  return Union.playSe(name)
end

function Union.isActive()
  return Union.state ~= "off"
end

local function plazaMap()
  return require("src.core.game3.link.union_plaza_map")
end

Union.plazaMap = plazaMap

function Union.isRs()
  return Family.isRubySapphire(Family.activeVersion())
end

function Union.isUnionMap(id)
  if type(id) ~= "string" then return false end
  if Union.isRs() then return id == plazaMap().MAP_ID end
  if not Family.hasWireless() then return false end
  return id == Union.MAP or id == plazaMap().MAP_ID
end

function Union.onUnionRoomMap()
  return Union.isUnionMap(link().currentMap())
end

function Union.capacity()
  return plazaMap().CAP
end

-- pokefirered/src/union_room.c:114 URTRADE_STATE_*
Union.URTRADE = { NONE = 0, REGISTERING = 1, OFFERING = 2 }

-- pokefirered/src/union_room.c:4583 ResetUnionRoomTrade
function Union.resetTrade()
  Union._trade = {
    state = 0,
    type = 0,
    playerPersonality = 0,
    playerSpecies = 0,
    playerLevel = 0,
    species = 0,
    level = 0,
    personality = 0,
  }
  return Union._trade
end

function Union.trade()
  if not Union._trade then Union.resetTrade() end
  return Union._trade
end

local function localPlayer()
  local s = link().session()
  return {
    name = (s and (s.name or s.playerName)) or "RED",
    gender = tonumber(s and s.gender) or 0,
    trainerId = tonumber(s and s.trainerId) or 0,
    activity = Union.ACTIVITY.SEARCH,
  }
end

Union.localPlayer = localPlayer

-- pokefirered/src/union_room_player_avatar.c:129 GetUnionRoomPlayerGraphicsId
function Union.graphicsIdFor(gender, trainerId)
  local ids = Union.avatarData().gfx_ids
  local row = tonumber(gender) == 1 and ids.female or ids.male
  return row[((tonumber(trainerId) or 0) % 8) + 1]
end

function Union.gfxFor(p)
  if Union.isRs() then
    -- pokeruby/src/overworld.c:2726
    return (Family.linkPlayerGfx(nil, p.game, p.gender))
  end
  return Union.graphicsIdFor(p.gender, p.trainerId)
end

function Union.foreignEntry(p)
  local f = Union.foreignAvatar(p)
  return require("src.online.union.Avatars").resolve(f, f.host)
end

function Union.isForeign(p)
  return type(p) == "table" and (p.sourceGen == 1 or p.sourceGen == 2)
end

function Union.foreignAvatar(p)
  return { game = p.game, gen = p.sourceGen, gender = p.gender, style = p.style,
           trainerId = p.trainerId, name = p.name, id = p.id, host = { version = Family.activeVersion() } }
end

-- pokefirered/src/union_room_player_avatar.c:448
function Union.memberFacing(member, activity)
  if (member or 0) ~= 0 then return Union.avatarData().member_facing[member + 1] end
  local raw = math.floor(tonumber(activity) or 0)
  if raw == Union.ACTIVITY.CHAT + Union.IN_UNION_ROOM then return Union.DIR.SOUTH end
  return Union.DIR.EAST
end

function Union.despawnAll()
  if next(Union._vobjs or {}) then
    Union._vobjs = {}
    local VirtualObjects = package.loaded["src.core.game3.virtual_objects"]
    if VirtualObjects then VirtualObjects.clear() end
  end
end

local function playerMod()
  return package.loaded["src.core.game3.player"]
end

local function playerStandingStill()
  local P = playerMod()
  return not (P and P.moving)
end

local function playerOn(x, y)
  local P = playerMod()
  if not P then return false end
  if tonumber(P.cellX) == x and tonumber(P.cellY) == y then return true end
  return P.moving and tonumber(P.targetX) == x and tonumber(P.targetY) == y or false
end

local function plazaVobjId(slot)
  return Union.VOBJ_BASE + slot
end

Union.vobjId = plazaVobjId

function Union.vobj(slot)
  return Union._vobjs and Union._vobjs[plazaVobjId(slot)] or nil
end

function Union.vobjVisible(slot)
  local v = Union.vobj(slot)
  return v ~= nil and v.visible == true
end

local function facingDir(facing)
  if type(facing) == "number" then return facing end
  return Union.FACE_DIR[facing] or Union.DIR.SOUTH
end

function Union.cellFor(slot)
  local x, y, facing = plazaMap().cellFor(slot)
  return x, y, facingDir(facing)
end

local function idleActivity(activity)
  local raw = math.floor(tonumber(activity) or 0) % Union.IN_UNION_ROOM
  return raw == Union.ACTIVITY.NONE or raw == Union.ACTIVITY.PLYRTALK or raw == Union.ACTIVITY.SEARCH
end

Union.idleActivity = idleActivity

function Union.cellFacing(slot, p)
  if p and not idleActivity(p.activity) then return Union.memberFacing(0, p.activity) end
  local _, _, dir = Union.cellFor(slot)
  return dir
end

-- pokefirered/src/union_room_player_avatar.c:463
function Union.showAvatar(slot, p)
  local vobjs = Union._vobjs
  local id = plazaVobjId(slot)
  local v = vobjs[id]
  if not v then
    v = { slot = slot, member = 0, visible = false, y2 = 0 }
    vobjs[id] = v
  end
  local x, y = Union.cellFor(slot)
  if not v.visible or v.anim == "out" then
    if playerOn(x, y) then
      v.waiting = true
      Union._avatarWaiting = true
      return false
    end
    v.visible = true
    v.anim = "in"
    v.y2 = -Union.FLY_HEIGHT
  end
  v.waiting = nil
  if Union.isForeign(p) then
    v.foreign = Union.foreignAvatar(p)
    v.gfx = nil
  else
    v.foreign = nil
    v.gfx = Union.gfxFor(p)
  end
  v.x, v.y = x, y
  if Union._talkSlot ~= slot then v.dir = Union.cellFacing(slot, p) end
  Union._vobjDirty = true
  return true
end

-- pokefirered/src/union_room_player_avatar.c:478
function Union.hideAvatar(slot)
  local v = Union.vobj(slot)
  if not v then return end
  v.waiting = nil
  if v.visible and v.anim ~= "out" then
    v.anim = "out"
    v.y2 = v.y2 or 0
    Union._vobjDirty = true
  end
end

function Union.retryWaitingAvatars()
  if not playerStandingStill() then return end
  local waiting = false
  for slot = 1, Union.capacity() do
    local v = Union.vobj(slot)
    if v and v.waiting then
      local p = Union.players[slot]
      if p and not p.gone then
        if not Union.showAvatar(slot, p) then waiting = true end
      else
        v.waiting = nil
      end
    end
  end
  Union._avatarWaiting = waiting
end

Union.WANDER = true
Union.WANDER_NEAR_PLAYER = 2

local function wanderMod()
  return require("src.core.game3.link.plaza_wander")
end

local STATUS_KIND = { chatting = "chat", trading = "trade", battling = "battle" }

function Union.memberStatusKind(p)
  if type(p) ~= "table" then return nil end
  local kind = STATUS_KIND[p.status]
  if kind or p.status ~= nil then return kind end
  local raw = math.floor(tonumber(p.activity) or 0) % Union.IN_UNION_ROOM
  local A = Union.ACTIVITY
  if raw == A.CHAT or raw == A.CARD then return "chat" end
  if raw == A.TRADE or raw == A.SPIN_TRADE then return "trade" end
  if raw == A.BATTLE_SINGLE or raw == A.BATTLE_DOUBLE or raw == A.BATTLE_MULTI then return "battle" end
  return nil
end

function Union.memberIdle(p)
  if type(p) ~= "table" or p.gone then return false end
  if p.status ~= nil and p.status ~= "idle" then return false end
  return idleActivity(p.activity)
end

local ENTER_OPTS = { surfing = false, elevation = 3 }

function Union.wanderWalkable(x, y, fromX, fromY, dir)
  local Coll = package.loaded["src.core.game3.collision"]
  if not (Coll and Coll._mapId == plazaMap().MAP_ID and Coll.canEnter) then return false end
  if Coll.inBounds and not Coll.inBounds(x, y) then return false end
  if Coll.isWater and Coll.isWater(x, y) then return false end
  ENTER_OPTS.fromX, ENTER_OPTS.fromY, ENTER_OPTS.dir = fromX, fromY, dir
  local ok = Coll.canEnter(link().game(), x, y, ENTER_OPTS)
  return ok == true
end

local function wanderCellFree(x, y, fromX, fromY, dir)
  if playerOn(x, y) then return false end
  local Obj = objects()
  if Obj and Obj.blocks and Obj.blocks(x, y) then return false end
  return Union.wanderWalkable(x, y, fromX or x, fromY or y, dir)
end

local function playerNear(x, y)
  local P = playerMod()
  if not P then return false end
  local near = Union.WANDER_NEAR_PLAYER
  local px, py = tonumber(P.cellX), tonumber(P.cellY)
  if px and py and math.abs(px - x) <= near and math.abs(py - y) <= near then return true end
  if not P.moving then return false end
  px, py = tonumber(P.targetX), tonumber(P.targetY)
  return px ~= nil and py ~= nil and math.abs(px - x) <= near and math.abs(py - y) <= near
end

local WANDER_ENV = { free = wanderCellFree }

function Union.tickWander()
  local dirty = false
  local onPlaza = Union.WANDER and link().currentMap() == plazaMap().MAP_ID
  for slot = 1, Union.capacity() do
    local v = Union.vobj(slot)
    local p = Union.players[slot]
    if v and v.visible then
      local w = v.wander
      if not w or w.homeX ~= v.x or w.homeY ~= v.y then
        w = wanderMod().new(slot * 7919 + (tonumber(p and p.trainerId) or 0) + 1, v.x, v.y)
        v.wander = w
      end
      if v.anim == nil then
        WANDER_ENV.frozen = Union._talkSlot == slot or Union.partnerId == slot
        WANDER_ENV.canWander = onPlaza and Union.memberIdle(p) and not playerNear(v.x, v.y)
        if wanderMod().tick(w, WANDER_ENV) then dirty = true end
      end
    elseif v then
      v.wander = nil
    end
  end
  return dirty
end

function Union.avatarCell(slot)
  local v = Union.vobj(slot)
  if not v then return nil end
  local w = v.wander
  if w then return w.x, w.y, w.moving end
  return v.x, v.y, false
end

function Union.slotAtCell(x, y)
  for slot = 1, Union.capacity() do
    local v = Union.vobj(slot)
    if v and v.visible then
      local cx, cy, moving = Union.avatarCell(slot)
      if cx == x and cy == y and not moving then return slot end
    end
  end
  return nil
end

-- pokefirered/src/event_object_movement.c:9354
function Union.animateVobjs()
  local dirty = Union._vobjDirty
  local vobjs = Union._vobjs
  if Union.tickWander() then dirty = true end
  for _, v in pairs(vobjs) do
    if v.anim == "in" then
      v.y2 = math.min(0, v.y2 + Union.FLY_STEP)
      if v.y2 >= 0 then v.anim = nil end
      dirty = true
    elseif v.anim == "out" then
      v.y2 = v.y2 - Union.FLY_STEP
      if v.y2 <= -Union.FLY_HEIGHT then
        v.visible = false
        v.anim = nil
        v.y2 = 0
        Union._vobjRebuild = true
      end
      dirty = true
    end
  end
  if not dirty then return end
  Union._vobjDirty = false
  local VirtualObjects = package.loaded["src.core.game3.virtual_objects"]
  if not VirtualObjects then
    local okV, mod = pcall(require, "src.core.game3.virtual_objects")
    if not okV then return end
    VirtualObjects = mod
  end
  if Union._vobjRebuild then
    Union._vobjRebuild = false
    VirtualObjects.clear()
  end
  for id, v in pairs(vobjs) do
    if v.visible then
      local rec = VirtualObjects.get(id) or VirtualObjects.spawn(id, v.gfx, v.x, v.y, 3, v.dir)
      if rec then
        local w = v.wander
        rec.graphicsId = v.gfx
        rec.foreign = v.foreign
        rec.x, rec.y = v.x, v.y
        rec.direction = v.dir
        rec.prevX, rec.prevY, rec.px, rec.py, rec.moving = nil, nil, nil, nil, nil
        if w then
          rec.x, rec.y = w.x, w.y
          if w.facing and Union._talkSlot ~= v.slot then rec.direction = Union.FACE_DIR[w.facing] or v.dir end
          if w.moving then
            rec.prevX, rec.prevY, rec.px, rec.py, rec.moving = w.prevX, w.prevY, w.px, w.py, true
            rec.targetX, rec.targetY = w.x, w.y
          else
            rec.targetX, rec.targetY = nil, nil
          end
          rec.animClock, rec.stepFrames, rec.stepFlip = w.animClock, wanderMod().STEP_FRAMES, w.stepFlip
        end
        rec.y2 = v.y2
        rec.solid = v.anim ~= "out"
      end
    end
  end
end

function Union.refreshPlaza()
  for slot = 1, Union.capacity() do
    local p = Union.players[slot]
    if p and p.gone then
      Union.hideAvatar(slot)
      Union.players[slot] = nil
      Union.memberIds[slot] = nil
      if Union.partnerId == slot then Union.partnerId = nil end
    elseif p then
      Union.showAvatar(slot, p)
    end
  end
end

function Union.animateAll()
  if Union._avatarWaiting then Union.retryWaitingAvatars() end
  Union.animateVobjs()
end

local FACING_DELTA = { down = { 0, 1 }, up = { 0, -1 }, left = { -1, 0 }, right = { 1, 0 } }

-- pokefirered/src/union_room_player_avatar.c:577
function Union.tryInteractWithMember()
  if not playerStandingStill() then return nil end
  local P = playerMod()
  local d = P and FACING_DELTA[P.facing or "down"]
  if not d then return nil end
  local fx, fy = (tonumber(P.cellX) or 0) + d[1], (tonumber(P.cellY) or 0) + d[2]
  local slot = Union.slotAtCell(fx, fy)
  if not slot then return nil end
  local p = Union.players[slot]
  local v = Union.vobj(slot)
  if not (v and v.visible and v.anim == nil and p and not p.gone) then return nil end
  if Union.isRs() then
    v.dir = Union.FACE_DIR[wanderMod().OPPOSITE[P.facing or "down"]] or Union.DIR.SOUTH
  else
    v.dir = Union.avatarData().opposite_facing[(Union.FACE_DIR[P.facing] or 1) + 1]
  end
  Union._talkSlot = slot
  Union._vobjDirty = true
  return slot, 0
end

-- pokefirered/src/union_room_player_avatar.c:621
function Union.updateMemberFacing(slot)
  if slot == nil or Union._talkSlot == slot then Union._talkSlot = nil end
  local v = slot and Union.vobj(slot)
  local p = slot and Union.players[slot]
  if not (v and p) then return end
  v.dir = Union.cellFacing(slot, p)
  Union._vobjDirty = true
end

function Union.playerAt(slot)
  return Union.players[slot]
end

function Union.playerCount()
  local n = 0
  for slot = 1, Union.capacity() do
    if Union.players[slot] then n = n + 1 end
  end
  return n
end

function Union.list()
  local out = {}
  for slot = 1, Union.capacity() do
    local p = Union.players[slot]
    if p then out[#out + 1] = { slot = slot, name = p.name, activity = p.activity } end
  end
  return out
end

-- pokefirered/src/union_room.c:403 LL_STATE_INIT reads the partners the link layer already has
function Union.groupList()
  local out = Union.list()
  local lk = link().link
  if not (lk and lk.isOpen and lk:isOpen() and lk.players) then return out end
  for _, p in ipairs(lk:players()) do
    local name = (not p.isLocal) and p.name or nil
    if name then
      local seen = false
      for _, row in ipairs(out) do
        if row.name == name then seen = true end
      end
      if not seen then
        out[#out + 1] = { slot = nil, name = name, activity = Union.activity }
      end
    end
  end
  return out
end

-- pokefirered/src/union_room.c:3582
function Union.noteUnionRoomPlayer(name)
  if type(name) ~= "string" or name == "" then return false end
  if Union._name then return false end
  Union._name = name
  return true
end

-- pokefirered/src/union_room.c:3606 BufferUnionRoomPlayerName
function Union.bufferPlayerName(ctx, adapters)
  local name = Union._name
  if not name then
    link().setResult(ctx, 0)
    return false, 0
  end
  Union._name = nil
  if adapters and adapters.setStringVar then
    adapters.setStringVar(1, name)
  elseif ctx then
    ctx.stringVars = ctx.stringVars or {}
    ctx.stringVars[1] = name
  end
  link().setResult(ctx, 1)
  return false, 1
end

function Union.announce()
  local L = link()
  local lk = L.link
  if not (lk and lk.isOpen and lk:isOpen()) then return false end
  local me = localPlayer()
  me.type = Union.MSG.HELLO
  me.activity = Union.ACTIVITY.SEARCH + Union.IN_UNION_ROOM
  lk:send(me)
  return true
end

-- pokefirered/src/union_room.c:3515 InitUnionRoom
function Union.init(ctx)
  Union._name = nil
  return false
end

-- pokefirered/src/union_room.c:2579 RunUnionRoom
function Union.run(ctx, adapters)
  link().setResult(ctx, 0)
  if Union.state ~= "off" and Union.onUnionRoomMap() then
    Union._vobjDirty = true
    Union._vobjRebuild = true
    Union.startPump()
    return false
  end
  Union.players = {}
  Union._vobjs = {}
  Union._vobjDirty = false
  Union._vobjRebuild = false
  Union._avatarWaiting = false
  Union._plazaSynced = false
  Union._plazaInstance, Union._plazaRev = nil, nil
  Union._offlineSince, Union._offlineWiped = nil, nil
  Union._upgradeShown = nil
  Union._serverOutdated = nil
  Union.flow = nil
  Union.memberIds = {}
  Union.partnerId = nil
  Union.activity = nil
  Union.lastResult = nil
  Union._name = nil
  Union.invite = nil
  Union.incoming = nil
  Union._await = nil
  Union._xg = nil
  Union._xgSession = nil
  Union.state = "init"
  local L = link()
  Union.relay = true
  Union.hookJoinErrors()
  local Participant = require("src.online.union.Participant")
  L.clientCall("joinPlaza", "union", L.liveProfile(), Participant.wireAvatar(L.avatar()), plazaMap().CAP,
    { xgen = require("src.online.Protocol2").XGEN, caps = Union.caps() })
  L.setStatus("idle")
  Union._refresh = 0
  Union._synced = false
  L.setResult(ctx, 0)
  Union.startPump()
  return false
end

function Union.caps()
  local L = link()
  local game = L.game()
  local memo = Union._capsMemo
  if memo and memo.game == game and memo.version == L.version() then return memo.caps end
  local Caps = require("src.online.union.Caps")
  local ok, caps = pcall(Caps.compute, { version = L.version(), game = game })
  if not ok or type(caps) ~= "table" then caps = Caps.compute({ version = L.version(), gameplayMods = true }) end
  Union._capsMemo = { game = game, version = L.version(), caps = caps }
  return caps
end

Union.JOIN_ERRORS = { bad_profile = true, bad_avatar = true, bad_caps = true }

function Union.hookJoinErrors()
  if Union._onJoinError then return end
  Union._onJoinError = function(e)
    if type(e) ~= "table" or e.scope ~= "join" or not Union.JOIN_ERRORS[e.reason] then return end
    if Union.state ~= "off" then Union._serverOutdated = e.reason end
  end
  link().clientCall("on", "error", Union._onJoinError)
end

function Union.unhookJoinErrors()
  if not Union._onJoinError then return end
  link().clientCall("off", "error", Union._onJoinError)
  Union._onJoinError = nil
end

function Union.stop(reason)
  if Union.state == "off" then return false end
  local L = link()
  if Union._xgSession then Union.endXg(Union._xgSession, "left") end
  Union.unhookJoinErrors()
  if Union.incoming then L.clientCall("replyInvite", Union.incoming.id, false) end
  L.clientCall("leavePlaza", "union")
  L.setStatus("busy")
  Union.relay = false
  Union.invite = nil
  Union.incoming = nil
  Union._await = nil
  local s = screen()
  if s and s.isOpen and s.isOpen() then s.close() end
  Union.flow = nil
  Union.disarmScriptWait(select(1, L.vmCtx()))
  Union._held = nil
  Union._scriptResult = nil
  Union.despawnAll()
  Union.players = {}
  Union.memberIds = {}
  Union.partnerId = nil
  Union._partner = nil
  Union.state = "off"
  Union._name = nil
  return true
end

-- pokefirered/src/union_room.c:2896 UR_STATE_HANDLE_DO_SOMETHING_PROMPT_INPUT
function Union.chooseActivity(index)
  local item = Union.INVITE_ITEMS[tonumber(index) or 0]
  if not item then return false end
  local M = message()
  if item.activity == Union.ACTIVITY.NONE then
    Union.activity = nil
    if M and M.show then
      -- pokefirered/src/union_room.c:2916
      local p = Union.partnerRow() or {}
      local text = RomText.ascii(RomText.key("gTexts_UR_IfYouWantToDoSomething", tonumber(p.gender) == 1 and 1 or 0))
      Union.partnerId = nil
      return Union.printAndExit(text)
    end
    Union.partnerId = nil
    Union.state = "main"
    return true
  end
  local activity = item.union and (item.activity + Union.IN_UNION_ROOM) or item.activity
  Union.activity = activity
  Union._role = "child"
  local sent = Union.sendInvite(activity)
  Union.state = sent and "send_activity_request" or "print_and_exit"
  if sent and M and M.show then
    -- pokefirered/src/union_room.c:2941
    local p = Union.partnerRow() or {}
    local g = tonumber(p.gender) == 1 and 1 or 0
    local key = RomText.key("gTexts_UR_WaitOrShowCard", g, Union.waitTextIndex(activity))
    if RomText.has(key) then M.show(RomText.ascii(key, Union.textCtx()), { stay = true }) end
  end
  return true
end

function Union.cancelActivity()
  Union.activity = nil
  Union.partnerId = nil
  Union.state = "main"
  return true
end

local function pressedB()
  local game = link().game()
  local input = game and game.input
  if not (input and input.wasPressed) then return false end
  return input:wasPressed("b") and true or false
end

local function pressedA()
  local game = link().game()
  local input = game and game.input
  if not (input and input.wasPressed) then return false end
  return input:wasPressed("a") and true or false
end

-- pokefirered/src/union_room.c:2647 Task_RunUnionRoom
function Union.update(dt)
  if Union.state == "off" then return false end
  if not Union.onUnionRoomMap() then
    Union.stop("left_union_room")
    return false
  end
  return Union.relayUpdate(dt, select(1, link().vmCtx()))
end

-- pokefirered/src/union_room.c:1832 WarpForCableClubActivity
local DEST_MT = {
  __index = function(t, k)
    if k == "map" then return Family.mapId(nil, rawget(t, "key")) end
    return nil
  end,
}
Union.COLOSSEUM_2P = setmetatable({ key = "colosseum2P", x = 6, y = 8 }, DEST_MT)
Union.COLOSSEUM_4P = setmetatable({ key = "colosseum4P", x = 5, y = 8 }, DEST_MT)
Union.TRADE_CENTER = setmetatable({ key = "tradeCenter", x = 5, y = 8 }, DEST_MT)
-- pokeemerald/src/union_room.c:1705
Union.RECORD_CORNER = setmetatable({ key = "recordCorner", x = 8, y = 9 }, DEST_MT)

function Union.warpForCableClubActivity(dest, linkService, opts)
  opts = opts or {}
  local L = link()
  local ctx, adapters = L.vmCtx()
  L.setVar(ctx, L.VAR_0x8004, linkService)
  L.setVar(ctx, L.VAR_CABLE_CLUB_STATE, linkService)
  if linkService ~= L.USING.TRADE_CENTER and linkService ~= L.USING.RECORD_CORNER then
    -- pokefirered/src/union_room.c:1901
    L.callSpecialNamed(ctx, adapters, "HealPlayerParty")
    L.callSpecialNamed(ctx, adapters, "SavePlayerParty")
    L.loadPlayerBag()
  end
  local s = L.session()
  if s then
    if opts.cableClubWarp then
      s.dynamicWarp = nil
      -- pokefirered/src/union_room.c:1838
      L.setCableClubWarp(ctx)
    end
    if not s.dynamicWarp or not opts.cableClubWarp then
      -- pokefirered/src/overworld.c:605
      local px, py = L.playerCell()
      s.dynamicWarp = { map = L.currentMap(), warpId = -1, x = px, y = py }
    end
  end
  local Warp = package.loaded["src.core.game3.warp"]
  local rt = package.loaded["src.core.game3.runtime"]
  if opts.onDone and Warp and Warp.scripted and rt and rt.isActive and rt.isActive() then
    -- pokefirered/src/union_room.c:1840
    Warp.scripted(rt._mod, L.game(), "warpsilent", dest.map, dest.x, dest.y, nil, opts.onDone)
    return true
  end
  local warped = L.warpToDest(ctx, adapters, { map = dest.map, warpId = -1, x = dest.x, y = dest.y })
  if opts.onDone then opts.onDone() end
  return warped
end

-- pokefirered/src/union_room.c:1892 UR_STATE_START_ACTIVITY
function Union.startActivity()
  Union.releaseScript()
  local raw = math.floor(tonumber(Union.activity) or 0)
  local act = raw % Union.IN_UNION_ROOM
  local inRoom = raw >= Union.IN_UNION_ROOM
  local L = link()
  local warpOpts = { onDone = function() end }
  if act == Union.ACTIVITY.BATTLE_SINGLE and inRoom then
    -- pokefirered/src/union_room.c:1811 StartUnionRoomBattle
    if battle().startUnionRoomBattle() then
      Union.state = "in_activity"
      return true
    end
  elseif act == Union.ACTIVITY.BATTLE_SINGLE then
    Union.stop()
    Union.warpForCableClubActivity(Union.COLOSSEUM_2P, L.USING.SINGLE_BATTLE, warpOpts)
    return true
  elseif act == Union.ACTIVITY.BATTLE_DOUBLE then
    Union.stop()
    Union.warpForCableClubActivity(Union.COLOSSEUM_2P, L.USING.DOUBLE_BATTLE, warpOpts)
    return true
  elseif act == Union.ACTIVITY.BATTLE_MULTI then
    Union.stop()
    Union.warpForCableClubActivity(Union.COLOSSEUM_4P, L.USING.MULTI_BATTLE, warpOpts)
    return true
  elseif act == Union.ACTIVITY.TRADE and inRoom then
    -- pokefirered/src/union_room.c:1936 Task_StartUnionRoomTrade
    Union.prepareBoardTrade()
    if linkTrade().startUnionRoomTrade(function() Union.state = "main" end) then
      Union.state = "in_activity"
      return true
    end
  elseif act == Union.ACTIVITY.TRADE then
    -- pokefirered/src/union_room.c:1928 WarpForCableClubActivity MAP_TRADE_CENTER
    Union.stop()
    Union.warpForCableClubActivity(Union.TRADE_CENTER, L.USING.TRADE_CENTER, warpOpts)
    return true
  elseif act == Union.ACTIVITY.CHAT then
    -- pokefirered/src/union_room.c:1949
    local rs = Union._chatSession or L.clientCall("roomSession")
    if rs then return Union.enterChat(rs) end
  elseif act == Union.ACTIVITY.CARD then
    -- pokefirered/src/union_room.c:1954 CB2_ShowCard
    if Union.showPartnerCard() then
      Union.state = "in_activity"
      return true
    end
  end
  Union.state = "print_and_exit"
  return false
end

function Union.noteLeftRoom(id)
  if id == nil then
    local room = link().clientCall("room")
    id = type(room) == "table" and room.room or nil
  end
  if id ~= nil then
    Union._leftRooms = Union._leftRooms or {}
    Union._leftRooms[id] = true
  end
end

-- pokefirered/src/union_room.c:1949
function Union.enterChat(rs)
  local L = link()
  Union._chatSession = nil
  local partner = Union.partnerRow()
  local function begin()
    local ok = chat().start({
      session = rs,
      onDone = function()
        Union.noteLeftRoom(rs.target)
        if not rs.left then pcall(rs.close, rs) end
        L.setStatus("idle")
        if partner then Union.recordMet(partner) end
        Union.activity = nil
        Union.partnerId = nil
        Union._joining = nil
        Union.state = "main"
      end,
    })
    if ok then
      Union.state = "in_activity"
    else
      if not rs.left then pcall(rs.close, rs) end
      Union.toMain()
    end
  end
  local okF, Fade = pcall(require, "src.ui.game3.fade")
  if okF and Fade.begin and Fade.MODE and type(love) == "table" and love.graphics then
    Union.state = "entering_chat"
    Fade.begin(Fade.MODE.TO_BLACK, 1, begin)
  else
    begin()
  end
  return true
end

-- pokefirered/src/union_room.c:4618
function Union.prepareBoardTrade()
  local record = Union.trade()
  if linkTrade().isLeader() then
    Union._savedReg = { record.playerSpecies, record.playerLevel, record.playerPersonality }
    record.playerSpecies, record.playerLevel, record.playerPersonality = record.species, record.level, record.personality
  else
    Union._savedReg = nil
    record.species, record.level, record.personality = record.playerSpecies, record.playerLevel, record.playerPersonality
  end
end

-- pokefirered/src/union_room.c:2791
function Union.finishBoardTrade()
  local L = link()
  local saved = Union._savedReg
  Union._savedReg = nil
  if saved then
    local record = Union.trade()
    record.playerSpecies, record.playerLevel, record.playerPersonality = saved[1], saved[2], saved[3]
    record.species, record.level, record.personality = 0, 0, 0
    return
  end
  Union.resetTrade()
  L.clientCall("setPresence", { board = false })
end

-- pokefirered/src/union_room.c:3264
function Union.attendant()
  local record = Union.trade()
  sfx("SE_PC_LOGIN")
  local species = tonumber(record.playerSpecies) or 0
  if species == 0 then return Union.registerPrompt() end
  local text
  if species == Union.SPECIES_EGG then
    text = RomText.ascii("gText_UR_CancelRegistrationOfEgg")
  else
    local okP, Pokemon = pcall(require, "src.core.game3.pokemon")
    local okN, name = false, nil
    if okP and Pokemon.name then okN, name = pcall(Pokemon.name, species) end
    text = RomText.ascii("gText_UR_CancelRegistrationOfMon",
      ctxOf({ stringVars = { okN and name or "", tostring(record.playerLevel or 0) } }))
  end
  return Union.runFlow({
    Union.stayStep(text),
    Union.yesNoStep(function(yes)
      if not yes then return Union.toMain() end
      Union.cancelRegistration()
      link().clientCall("setPresence", { board = false })
      Union.runFlow({
        Union.sayStep(RomText.ascii("gText_UR_RegistrationCanceled2")),
        Union.doStep(Union.toMain),
      }, "cancel_registration")
    end),
  }, "cancel_registration_prompt")
end

-- pokefirered/src/union_room.c:3284
function Union.registerPrompt(skipText)
  local steps = {}
  if not skipText then steps[#steps + 1] = Union.stayStep(RomText.ascii("gText_UR_RegisterMonAtTradingBoard", ctxOf())) end
  steps[#steps + 1] = Union.doStep(function()
    local s = screen()
    if not s then return Union.toMain() end
    Union.state = "register_prompt_input"
    s.showRegister({
      onChoose = function(_, item)
        local id = item and item.id
        if id == 1 then return Union.registerSelectMon() end
        if id == 2 then
          return Union.runFlow({
            Union.stayStep(RomText.ascii("gText_UR_TradingBoardInfo", ctxOf())),
            Union.doStep(function() Union.registerPrompt(true) end),
          }, "register_info")
        end
        local M = message()
        if M and M.isOpen() then M.close() end
        Union.toMain()
      end,
      onCancel = function()
        local M = message()
        if M and M.isOpen() then M.close() end
        Union.toMain()
      end,
    })
  end)
  return Union.runFlow(steps, "register_prompt")
end

local function choosePartyMon(done)
  local okP, PartyMenu = pcall(require, "src.ui.game3.party_menu")
  if not (okP and type(PartyMenu) == "table" and PartyMenu.show) then
    done(nil)
    return false
  end
  local s = link().session()
  PartyMenu.show(s and s.party, nil, {
    mode = "choose",
    session = s,
    onSelect = function(slot)
      PartyMenu.close()
      done(slot)
    end,
  })
  return true
end

Union.choosePartyMon = choosePartyMon

-- pokefirered/src/union_room.c:3320
function Union.registerSelectMon()
  local picked, slot = false, nil
  return Union.runFlow({
    Union.sayStep(RomText.ascii("gText_UR_WhichMonWillYouOffer")),
    Union.doStep(function()
      choosePartyMon(function(s)
        picked, slot = true, s
      end)
    end),
    Union.waitStep(function() return picked end),
    Union.doStep(function()
      if not slot then
        Union.resetTrade()
        return Union.printAndExit(RomText.ascii("gText_UR_RegistrationCanceled"))
      end
      local ok = Union.registerForTradingBoard(slot, 0)
      local record = Union.trade()
      if ok and record.playerSpecies == Union.SPECIES_EGG then return Union.registerComplete() end
      Union.registerRequestType()
    end),
  }, "register_select_mon")
end

-- pokefirered/src/union_room.c:3328
function Union.registerRequestType()
  return Union.runFlow({
    Union.stayStep(RomText.ascii("gText_UR_ChooseRequestedMonType")),
    Union.doStep(function()
      local s = screen()
      if not s then return Union.toMain() end
      Union.state = "register_request_type"
      local function cancel()
        Union.resetTrade()
        local M = message()
        if M and M.isOpen() then M.close() end
        Union.printAndExit(RomText.ascii("gText_UR_RegistrationCanceled"))
      end
      s.showTypes({
        onChoose = function(_, item)
          if not item or item.id == s.TYPE_EXIT then return cancel() end
          Union.trade().type = item.id
          local M = message()
          if M and M.isOpen() then M.close() end
          Union.registerComplete()
        end,
        onCancel = cancel,
      })
    end),
  }, "register_request_type")
end

-- pokefirered/src/union_room.c:3347
function Union.registerComplete()
  local record = Union.trade()
  link().clientCall("setPresence", { board = {
    species = tonumber(record.playerSpecies) or 0,
    level = tonumber(record.playerLevel) or 0,
    wantType = tonumber(record.type) or 0,
  } })
  Union.lastResult = "registered"
  return Union.printAndExit(RomText.ascii("gText_UR_RegistraionCompleted"))
end

-- pokefirered/src/union_room.c:4400
function Union.boardOffers()
  local out = {}
  for slot = 1, Union.capacity() do
    local p = Union.players[slot]
    local b = p and not p.gone and type(p.board) == "table" and p.board or nil
    if b and (tonumber(b.species) or 0) ~= 0 then
      out[#out + 1] = { slot = slot, name = p.name, species = tonumber(b.species) or 0,
        level = tonumber(b.level) or 0, wantType = tonumber(b.wantType) or 0 }
    end
  end
  return out
end

-- pokefirered/src/union_room.c:4422
function Union.requestedTradeInParty(wantType, species)
  local s = link().session()
  local party = (s and s.party) or {}
  if tonumber(species) == Union.SPECIES_EGG then
    for i = 1, 6 do
      if party[i] and party[i].isEgg then return "match" end
    end
    return "noegg"
  end
  local okP, Pokemon = pcall(require, "src.core.game3.pokemon")
  for i = 1, 6 do
    local mon = party[i]
    if mon and not mon.isEgg and okP and Pokemon.types then
      local ok, t1, t2 = pcall(Pokemon.types, tonumber(mon.species) or 0)
      if type(t1) == "table" then t1, t2 = t1[1], t1[2] end
      if ok and (tonumber(t1) == tonumber(wantType) or tonumber(t2) == tonumber(wantType)) then return "match" end
    end
  end
  return "notype"
end

-- pokefirered/src/union_room.c:3373
function Union.checkTradingBoard()
  sfx("SE_PC_LOGIN")
  return Union.runFlow({
    Union.stayStep(RomText.ascii("gText_UR_XCheckedTradingBoard", ctxOf({ stringVars = { Union.sessionName() } }))),
    Union.doStep(function()
      local M = message()
      if M and M.isOpen() then M.close() end
      Union.openTradingBoard()
    end),
  }, "check_trading_board")
end

-- pokefirered/src/union_room.c:3381
function Union.openTradingBoard()
  local s = screen()
  if not s then return Union.toMain() end
  local record = Union.trade()
  local own
  if (tonumber(record.playerSpecies) or 0) ~= 0 then
    own = { name = Union.sessionName(), species = record.playerSpecies, level = record.playerLevel,
      wantType = record.type }
  end
  local offers = Union.boardOffers()
  Union.state = "trading_board"
  s.showBoard({
    own = own,
    offers = offers,
    onChoose = function(_, item)
      if not item or item.id == s.BOARD_EXIT then return Union.toMain() end
      local entry = item.entry
      if not entry then return Union.toMain() end
      Union.boardPick(entry)
    end,
    onCancel = function() Union.toMain() end,
  })
end

function Union.boardPick(entry)
  local p = Union.players[entry.slot]
  local ctx = ctxOf({ stringVars = { entry.name or "" } })
  local r = Union.requestedTradeInParty(entry.wantType, entry.species)
  if r == "notype" or r == "noegg" then
    ctx.stringVars[2] = RomText.plain(RomText.key("gTypeNames", entry.wantType))
    local key = r == "noegg" and "gText_UR_DontHaveEggTrainerWants" or "gText_UR_DontHaveTypeTrainerWants"
    return Union.runFlow({
      Union.sayStep(RomText.ascii(key, ctx)),
      Union.doStep(Union.openTradingBoard),
    }, "trading_board_refused")
  end
  Union.partnerId = entry.slot
  Union._partner = p
  return Union.runFlow({
    Union.stayStep(RomText.ascii("gText_UR_AskTrainerToMakeTrade", ctx)),
    Union.yesNoStep(function(yes)
      if not yes then return Union.toMain() end
      if p and (tonumber(p.sourceGen) or 3) ~= 3 then
        for i, item in ipairs(Union.XG_ITEMS) do
          if item.wire == "xg_trade" then return Union.chooseXg(i) end
        end
      end
      Union.boardOffer(entry)
    end),
  }, "trade_prompt")
end

-- pokefirered/src/union_room.c:3435
function Union.boardOffer(entry)
  local picked, slot = false, nil
  return Union.runFlow({
    Union.sayStep(RomText.ascii("gText_UR_WhichMonWillYouOffer")),
    Union.doStep(function()
      choosePartyMon(function(s)
        picked, slot = true, s
      end)
    end),
    Union.waitStep(function() return picked end),
    Union.doStep(function()
      if not slot then return Union.toMain() end
      if not Union.offerTradeTo(entry.slot, slot) then return Union.toMain() end
      Union.sendBoardInvite(entry)
    end),
  }, "trade_select_mon")
end

-- pokefirered/src/union_room.c:3448
function Union.sendBoardInvite(entry)
  local L = link()
  local record = Union.trade()
  local p = Union.players[entry.slot]
  if not (p and p.id) then return Union.printAndExit(RomText.ascii("gText_UR_TrainerAppearsBusy")) end
  Union.activity = Union.ACTIVITY.TRADE + Union.IN_UNION_ROOM
  Union._role = "child"
  local profile = L.liveProfile(Union.rulesetFor("trade"))
  Union.invite = L.clientCall("invite", p.id, "trade", { ruleset = Union.rulesetFor("trade"), board = {
    species = tonumber(record.species) or 0,
    level = tonumber(record.level) or 0,
    personality = tonumber(record.personality) or 0,
  } }, profile)
  Union.flow = nil
  Union.state = "send_activity_request"
  local M = message()
  if M and M.show then
    M.show(RomText.ascii(RomText.key("gTexts_UR_CommunicatingWait", 2), ctxOf({ stringVars = { p.name or "" } })),
      { stay = true })
  end
  return true
end

-- pokefirered/src/union_room.c:1863 CreateTrainerCardInBuffer
function Union.showPartnerCard()
  local L = link()
  L.sendTrainerCard()
  local card = L.peerCard or L.localTrainerCard()
  local okC, TrainerCard = pcall(require, "src.ui.game3.trainer_card")
  if okC and type(TrainerCard) == "table" and TrainerCard.show
      and type(love) == "table" and love.graphics then
    TrainerCard.show({
      session = card,
      onClose = function()
        Union.activity = nil
        Union.partnerId = nil
        Union.state = "main"
      end,
    })
    Union.lastResult = "card_shown"
    return true
  end
  Union.lastResult = card and "card_shown" or nil
  return card ~= nil
end

-- pokefirered/src/union_room.c:4486
function Union.requestPrompt()
  local raw = math.floor(tonumber(Union.activity) or 0) % Union.IN_UNION_ROOM
  if raw == Union.ACTIVITY.BATTLE_SINGLE then return RomText.ascii("gText_UR_BattleChallenge") end
  if raw == Union.ACTIVITY.CHAT then return RomText.ascii("gText_UR_ChatInvitation") end
  if raw == Union.ACTIVITY.CARD then return RomText.ascii("gText_UR_ShowTrainerCard") end
  if raw == Union.ACTIVITY.TRADE then
    local inv = Union.incoming or Union._lastIncoming or {}
    local board = type(inv.detail) == "table" and type(inv.detail.board) == "table" and inv.detail.board or {}
    local record = Union.trade()
    local offered = tonumber(board.species) or 0
    if offered == Union.SPECIES_EGG then return RomText.ascii("gText_UR_OfferToTradeEgg") end
    local okP, Pokemon = pcall(require, "src.core.game3.pokemon")
    local function name(sp)
      local ok, n = false, nil
      if okP and Pokemon.name then ok, n = pcall(Pokemon.name, sp) end
      return ok and n or ""
    end
    return RomText.ascii("gText_UR_OfferToTradeMon", { dynamic = {
      [0] = tostring(record.playerLevel or 0), [1] = name(record.playerSpecies),
      [2] = tostring(tonumber(board.level) or 0), [3] = name(offered),
    } })
  end
  local Strings = require("src.core.Strings")
  local what = Union.ACTIVITY_NAMES[raw]
  local who = Union._requestName or Strings("The TRAINER")
  if not what then
    -- pokefirered/src/union_room_message.c:88
    return RomText.ascii("gText_UR_PlayerContactedYouAddToMembers", { stringVars = { "", who } })
  end
  return RomText.ascii("gText_UR_PlayerContactedYouForXAccept", { stringVars = { what, who } })
end

-- pokefirered/src/union_room.c:3148 UR_STATE_RECV_ACTIVITY_REQUEST
function Union.askActivityRequest()
  local M = message()
  local okC, Choice = pcall(require, "src.ui.game3.choice")
  if not (M and M.show and okC and Choice and Choice.yesNo
      and type(love) == "table" and love.graphics) then
    -- pokefirered/src/union_room.c:3205 the peer is answered either way
    Union.answerRequest(false)
    return false
  end
  Union.state = "handle_activity_request"
  Union._asked = false
  M.show(Union.requestPrompt(), { stay = true })
  return true
end

-- pokefirered/src/union_room.c:3152
function Union.offerYesNo()
  local M = message()
  local okC, Choice = pcall(require, "src.ui.game3.choice")
  if Union._asked or not (M and M.isWaiting and M.isWaiting() and okC and Choice) then return false end
  if Choice.isOpen() then return false end
  Union._asked = true
  Choice.yesNo(function(yes)
    M.close()
    Union.answerRequest(yes and true or false)
  end)
  return true
end

-- pokefirered/src/union_room.c:3148
function Union.answerRequest(accept)
  local inv = Union.incoming
  Union.incoming = nil
  local raw = math.floor(tonumber(Union.activity) or 0) % Union.IN_UNION_ROOM
  local M = message()
  local shown = inv and M and M.show and type(love) == "table" and love.graphics
  if inv then link().clientCall("replyInvite", inv.id, accept and true or false) end
  Union.lastResult = accept and "accepted" or "declined"
  if accept and inv then
    Union._role = "parent"
    Union.flow = nil
    Union.beginAwaitRoom(nil)
  else
    Union.activity = nil
    if shown and Union._xg then return Union.printAndExit(Union.xgText("you_declined")) end
    if shown then
      -- pokefirered/src/union_room.c:887
      local key = (raw == Union.ACTIVITY.CHAT or raw == Union.ACTIVITY.CARD)
        and "gText_UR_OfferDeclined2" or "gText_UR_OfferDeclined1"
      return Union.printAndExit(RomText.ascii(key))
    end
    Union.flow = nil
    Union.state = "main"
  end
  return true
end

-- pokefirered/src/union_room.c:3320 UR_STATE_REGISTER_SELECT_MON
function Union.registerForTradingBoard(slot, requestedType)
  local record = Union.trade()
  record.state = Union.URTRADE.REGISTERING
  local isEgg = linkTrade().registerTradeMonAndGetIsEgg(slot)
  record.state = Union.URTRADE.NONE
  if not isEgg then
    -- pokefirered/src/union_room.c:3341 UR_STATE_REGISTER_REQUEST_TYPE
    local wanted = tonumber(requestedType)
    if not wanted then return false, "needs_type" end
    record.type = wanted
  end
  Union.lastResult = "registered"
  return true, record
end

-- pokefirered/src/union_room.c:3329 ResetUnionRoomTrade on a canceled registration
function Union.cancelRegistration()
  Union.resetTrade()
  Union.lastResult = "registration_canceled"
  return true
end

-- pokefirered/src/union_room.c:3443 ChooseMonForTradingBoard
function Union.chooseMonForTradingBoard(boardSlot)
  local okP, PartyMenu = pcall(require, "src.ui.game3.party_menu")
  if not (okP and PartyMenu and PartyMenu.show and love and love.graphics) then
    return false
  end
  local s = link().session()
  Union.state = "trade_select_mon"
  PartyMenu.show(s and s.party, nil, {
    mode = "choose",
    session = s,
    onSelect = function(slot)
      PartyMenu.close()
      if not slot then
        Union.state = "main"
        return
      end
      if not Union.offerTradeTo(boardSlot, slot) then Union.state = "main" end
    end,
  })
  return true
end

-- pokefirered/src/union_room.c:3485 UR_STATE_TRADE_SELECT_MON
function Union.offerTradeTo(boardSlot, partySlot)
  local record = Union.trade()
  record.state = Union.URTRADE.OFFERING
  record.offerPlayerId = tonumber(boardSlot)
  if not linkTrade().registerTradeMon(partySlot) then
    record.state = Union.URTRADE.NONE
    return false, "no_mon"
  end
  record.state = Union.URTRADE.NONE
  Union.partnerId = tonumber(boardSlot)
  -- pokefirered/src/union_room.c:3449 sPlayerCurrActivity = ACTIVITY_TRADE | IN_UNION_ROOM
  Union.activity = Union.ACTIVITY.TRADE + Union.IN_UNION_ROOM
  Union.state = "start_activity"
  return true
end

function Union.startPump()
  Union._pump = link().startPump()
  return Union._pump
end

local function linkupResult(ctx, value)
  local L = link()
  L.setResult(ctx, value)
  return value
end

-- pokefirered/src/union_room.c:382 TryBecomeLinkLeader
function Union.tryBecomeLinkLeader(ctx, adapters)
  return Union.linkGroupFlow(ctx, adapters, "leader")
end

-- pokefirered/src/union_room.c:1126 TryJoinLinkGroup
function Union.tryJoinLinkGroup(ctx, adapters)
  return Union.linkGroupFlow(ctx, adapters, "group")
end

function Union.linkGroupFlow(ctx, adapters, role)
  local L = link()
  local group = L.getVar(ctx, L.VAR_0x8004)
  -- pokeemerald/src/union_room.c:397
  if Family.of() == "rse" and Family.hasWireless() and group == Union.LINK_GROUP.BATTLE_TOWER then
    local okU, Util = pcall(require, "src.core.game3.rse.frontier.util")
    local okD, D = pcall(require, "src.core.game3.rse.frontier.trainers")
    local f = okU and Util.frontier and Util.frontier(L.session()) or nil
    if okD and type(f) == "table" and D.LVL and f.lvlMode == D.LVL.OPEN then
      group = group + 1
      L.setVar(ctx, L.VAR_0x8004, group)
    end
  end
  local spec = Union.GROUP_ACTIVITY[group]
  if not spec and not Family.hasWireless() then return false, linkupResult(ctx, L.LINKUP.FAILED) end
  spec = spec or Union.GROUP_ACTIVITY[0]
  Union.activity = spec.activity
  linkupResult(ctx, L.LINKUP.ONGOING)
  if L.adapterConnected() then
    return Union.relayGroupFlow(ctx, adapters, group, role)
  end
  local s = screen()
  if not s then
    return false, linkupResult(ctx, L.LINKUP.FAILED)
  end
  -- pokefirered/src/union_room.c:391 LL_STATE_INIT tells the other machines this group exists
  Union.announce()
  local Natives = require("src.core.game3.scripting.natives")
  return Natives.yieldHost(ctx, adapters, function(done)
    s.showPlayers(Union.groupList(), {
      mode = role,
      capacity = spec,
      onPoll = function() return Union.groupList() end,
      onConfirm = function(picked)
        Union.partnerId = picked
        linkupResult(ctx, L.LINKUP.SUCCESS)
        done()
      end,
      onCancel = function()
        linkupResult(ctx, L.LINKUP.FAILED)
        done()
      end,
    })
  end)
end

local function natives()
  return require("src.core.game3.scripting.natives")
end

local function choice()
  local ok, Choice = pcall(require, "src.ui.game3.choice")
  return ok and type(Choice) == "table" and Choice or nil
end

local function playSe(name)
  local okA, Audio = pcall(require, "src.core.game3.audio")
  local okS, SE = pcall(require, "src.core.game3.se_ids")
  if okA and okS and Audio.playSe and SE[name] then pcall(Audio.playSe, SE[name]) end
end

Union.playSe = playSe

function Union.rulesetFor(wire)
  return require("src.online.Protocol2").ACTIVITY_RULESET[wire]
end

function Union.wireFor(activity)
  local raw = math.floor(tonumber(activity) or 0)
  return Union.WIRE_NAMES[raw % Union.IN_UNION_ROOM]
end

-- pokefirered/src/union_room.c:3148
function Union.activityForInvite(wire, detail)
  local A, U = Union.ACTIVITY, Union.IN_UNION_ROOM
  if wire == "battle_single" then return A.BATTLE_SINGLE + U end
  if wire == "battle_double" then return A.BATTLE_DOUBLE end
  if wire == "chat" then return A.CHAT + U end
  if wire == "card" then return A.CARD end
  if wire == "xg_battle" then return A.BATTLE_SINGLE + U end
  if wire == "xg_trade" then return A.TRADE + U end
  if wire == "trade" then
    if type(detail) == "table" and type(detail.board) == "table" then return A.TRADE + U end
    return A.TRADE
  end
  return nil
end

function Union.linkTypeFor(activity)
  local Game3Link = require("src.link.Game3Link")
  local raw = math.floor(tonumber(activity) or 0) % Union.IN_UNION_ROOM
  if raw == Union.ACTIVITY.TRADE then return Game3Link.LINKTYPE.TRADE_SETUP end
  return Game3Link.LINKTYPE.BATTLE
end

function Union.slotForId(id)
  if id == nil then return nil end
  for slot = 1, Union.capacity() do
    if Union.memberIds[slot] == id then return slot end
  end
  return nil
end

local function myId()
  local you = link().clientCall("you")
  return type(you) == "table" and you.id or nil
end

-- pokefirered/include/constants/union_room.h:21
Union.STATUS_ACTIVITY = {
  chatting = Union.ACTIVITY.CHAT,
  battling = Union.ACTIVITY.BATTLE_SINGLE,
  trading = Union.ACTIVITY.TRADE,
  busy = Union.ACTIVITY.NPCTALK,
}
Union.GROUP_WIRE_ACTIVITY = {
  chat = Union.ACTIVITY.CHAT,
  card = Union.ACTIVITY.CARD,
  trade = Union.ACTIVITY.TRADE,
  battle_single = Union.ACTIVITY.BATTLE_SINGLE,
  battle_double = Union.ACTIVITY.BATTLE_SINGLE,
}

function Union.memberActivity(m)
  local g = type(m.group) == "table" and m.group or nil
  local act = g and (Union.GROUP_WIRE_ACTIVITY[g.activity] or Family.activityForWire(nil, g.activity)) or nil
  if not act then act = Union.STATUS_ACTIVITY[m.status] end
  if not act then act = Union.ACTIVITY.NONE end
  return act + Union.IN_UNION_ROOM
end

local function avatarRow(m)
  local av = type(m.avatar) == "table" and m.avatar or {}
  local part = require("src.online.union.Participant").fromMember(m)
  return {
    id = m.id,
    name = av.name or m.name,
    gender = tonumber(av.gender) or 0,
    trainerId = tonumber(av.trainerId) or 0,
    game = part and part.game or av.version,
    sourceGen = part and part.gen or 3,
    legacy = part == nil or part.legacy,
    style = part and part.style or nil,
  }
end

Union.avatarRow = avatarRow

local NO_MEMBERS = {}

-- pokefirered/src/union_room.c:2781
Union.GONE_GRACE_SECONDS = 1.5

function Union.syncPlaza()
  local plaza = link().clientCall("plaza")
  if type(plaza) ~= "table" then return false end
  if Union._plazaSynced and plaza.instance == Union._plazaInstance and plaza.rev == Union._plazaRev then
    return false
  end
  Union._plazaSynced = true
  Union._plazaInstance, Union._plazaRev = plaza.instance, plaza.rev
  Union.plazaBuilds = (Union.plazaBuilds or 0) + 1
  local me = myId()
  local mySlot = tonumber(plaza.you)
  local cap = Union.capacity()
  local gen = (Union._plazaGen or 0) + 1
  Union._plazaGen = gen
  local fresh = false
  local members = type(plaza.members) == "table" and plaza.members or NO_MEMBERS
  for i = 1, #members do
    local m = members[i]
    local slot = type(m) == "table" and tonumber(m.slot) or nil
    if slot and m.id ~= nil and (m.id == me or slot == mySlot) then
      local av = type(m.avatar) == "table" and m.avatar or nil
      if not (av and av.gen ~= nil) and not Union._serverOutdated then Union._serverOutdated = "legacy_shard" end
    end
    if slot and slot >= 1 and slot <= cap and m.id ~= nil and m.id ~= me and slot ~= mySlot then
      local p = Union.players[slot]
      if p and p.id ~= m.id then
        Union.hideAvatar(slot)
        p = nil
      end
      if not p then
        p = avatarRow(m)
        Union.players[slot] = p
        Union.memberIds[slot] = m.id
        Union.noteUnionRoomPlayer(p.name)
        fresh = true
      end
      p.gen = gen
      p.gone = nil
      p.online = m.online
      p.status = m.status
      p.group = m.group
      p.board = m.board
      p.activity = Union.memberActivity(m)
    end
  end
  for slot = 1, cap do
    local p = Union.players[slot]
    if p and p.gen ~= gen then p.gone = true end
  end
  -- pokefirered/src/union_room.c:2783
  if fresh and Union._synced then playSe("SE_NOTE_C") end
  Union._synced = true
  Union.refreshPlaza()
  return true
end

function Union.plazaOffline()
  local now = Union.clock()
  Union._plazaSynced = false
  Union._offlineSince = Union._offlineSince or now
  if Union._offlineWiped or now - Union._offlineSince < Union.GONE_GRACE_SECONDS then return end
  Union._offlineWiped = true
  for slot = 1, Union.capacity() do
    local p = Union.players[slot]
    if p then p.gone = true end
  end
  Union.refreshPlaza()
end

function Union.checkUpgrade()
  if Union._upgradeShown or Union.state ~= "main" or Union.flow then return end
  local up = link().clientCall("upgradeRequired")
  local text
  if up then
    text = require("src.online.Protocol2").upgradeText(up)
  elseif Union._serverOutdated then
    text = Union.xgText("server_outdated")
  else
    return
  end
  Union._upgradeShown = true
  local M = message()
  if M and M.show then Union.printAndExit(text) end
end

-- pokefirered/src/union_room.c:3106
function Union.pollIncoming()
  local L = link()
  if Union.state == "init" then return end
  for _, inv in ipairs(L.clientCall("invites") or {}) do
    local id = type(inv) == "table" and inv.id or nil
    if id ~= nil and not Union._answered[id] then
      Union._answered[id] = true
      local activity = Union.activityForInvite(inv.activity, inv.detail)
      local xg = require("src.online.Protocol2").XG_ACTIVITIES[inv.activity or ""] and inv.activity or nil
      if Union.isRs() and not xg then activity = nil end
      if Union.state == "main" and not Union.incoming and activity then
        local from = type(inv.from) == "table" and inv.from or {}
        Union.incoming = inv
        Union._lastIncoming = inv
        Union.activity = activity
        Union._xg = xg
        Union._requestName = type(from.avatar) == "table" and from.avatar.name or from.name
        Union.partnerId = Union.slotForId(from.id)
        if xg and not Union.partnerId then
          Union._partner = avatarRow({ id = from.id, name = from.name, slot = 1, avatar = from.avatar })
        end
        playSe("SE_DING_DONG")
        Union.state = "player_contacted_you"
      else
        L.clientCall("replyInvite", id, false)
      end
    end
  end
end

function Union.relayTick(_dt)
  local L = link()
  if not package.loaded["src.ui.game3.link_tags"] then pcall(require, "src.ui.game3.link_tags") end
  if not L.online() then
    Union.plazaOffline()
    Union.animateAll()
    Union.checkUpgrade()
    return
  end
  Union._offlineSince, Union._offlineWiped = nil, nil
  Union.syncPlaza()
  Union.animateAll()
  if Union._serverOutdated and not Union._upgradeShown then Union.checkUpgrade() end
  Union.pollIncoming()
  if Union.state == "main" and L.link then
    Union.noteLeftRoom()
    L.closeLink("activity_done")
    L.setStatus("idle")
  end
end

local function M()
  return message()
end

local function stepsOf(...)
  return { ... }
end

-- pokefirered/src/union_room.c:2611
function Union.runFlow(steps, stateName)
  Union.flow = { steps = steps, i = 1, started = false }
  if stateName then Union.state = stateName end
  return true
end

function Union.stepFlow()
  local guard = 0
  while guard < 16 do
    guard = guard + 1
    local f = Union.flow
    if not f then return end
    local step = f.steps[f.i]
    if not step then
      if Union.flow == f then Union.flow = nil end
      return
    end
    if not f.started then
      f.started = true
      if step.start then step.start() end
      if Union.flow ~= f then return end
    end
    if step.poll and not step.poll() then return end
    if Union.flow ~= f then return end
    f.i = f.i + 1
    f.started = false
  end
end

function Union.doStep(fn)
  return { start = fn }
end

function Union.sayStep(text)
  return {
    start = function() M().show(text) end,
    poll = function() return not M().isOpen() end,
  }
end

local function lastPageWaiting()
  local Mo = M()
  if not (Mo.isOpen() and Mo.isWaiting()) then return false end
  return (Mo._page or 1) >= #(Mo._pages or {})
end

Union.lastPageWaiting = lastPageWaiting

function Union.stayStep(text)
  return {
    start = function() M().show(text, { stay = true }) end,
    poll = lastPageWaiting,
  }
end

-- pokefirered/src/union_room_message.c:202
function Union.pauseStep(text, frames)
  local n = 0
  return {
    start = function() M().show(text, { stay = true }) end,
    poll = function()
      if not M().isWaiting() then return false end
      n = n + 1
      if n < (frames or 60) then return false end
      M().close()
      return true
    end,
  }
end

-- pokefirered/src/union_room.c:3870
function Union.yesNoStep(cb)
  local asked, answered = false, false
  return {
    poll = function()
      if answered then return true end
      local Choice = choice()
      if not asked and lastPageWaiting() and Choice and not Choice.isOpen() then
        asked = true
        -- pokefirered/src/new_menu_helpers.c:48
        Choice.yesNo(function(yes)
          answered = true
          M().close()
          cb(yes and true or false)
        end, { left = 21, top = 9 })
      end
      return answered
    end,
  }
end

function Union.waitStep(fn)
  return { poll = fn }
end

function Union.toMain()
  Union.flow = nil
  Union.activity = nil
  Union._xg = nil
  Union.state = "main"
  if Union._talkSlot then Union.updateMemberFacing(Union._talkSlot) end
  Union.releaseScript()
end

-- pokefirered/src/union_room.c:3455
function Union.printAndExit(text, slot)
  return Union.runFlow(stepsOf(
    Union.sayStep(text),
    Union.doStep(function()
      Union.updateMemberFacing(slot)
      Union.toMain()
    end)
  ), "print_and_exit")
end

function Union.sessionName()
  return localPlayer().name
end

local function textCtx(extra)
  local ctx = { playerName = Union.sessionName(), stringVars = {} }
  for k, v in pairs(extra or {}) do ctx[k] = v end
  return ctx
end

Union.textCtx = textCtx

-- pokefirered/src/link_rfu_3.c:1178
function Union.metBefore(p)
  local s = link().session()
  local rec = type(s) == "table" and type(s.trainerNameRecords) == "table" and s.trainerNameRecords or {}
  for _, r in ipairs(rec) do
    if type(r) == "table" and r.name == (p and p.name) and tonumber(r.trainerId) == tonumber(p and p.trainerId) then
      return true
    end
  end
  return false
end

-- pokefirered/src/link_rfu_3.c:1121
function Union.recordMet(p)
  local s = link().session()
  if type(s) ~= "table" or type(p) ~= "table" or not p.name then return end
  if type(s.trainerNameRecords) ~= "table" then s.trainerNameRecords = {} end
  local rec = s.trainerNameRecords
  for i = #rec, 1, -1 do
    local r = rec[i]
    if type(r) ~= "table" or (r.name == p.name and tonumber(r.trainerId) == tonumber(p.trainerId)) then
      table.remove(rec, i)
    end
  end
  table.insert(rec, 1, { name = p.name, trainerId = tonumber(p.trainerId) or 0 })
  while #rec > 20 do table.remove(rec) end
end

local function genderIndex(p)
  return tonumber(p and p.gender) == 1 and 1 or 0
end

local function pick(list)
  return list[math.random(#list)]
end

-- pokefirered/src/union_room.c:4295
function Union.reactionText(activity, gender, name)
  local raw = math.floor(tonumber(activity) or 0) % Union.IN_UNION_ROOM
  local g = gender == 1 and 1 or 0
  local ctx = textCtx({ stringVars = { name or "" } })
  if raw == Union.ACTIVITY.BATTLE_SINGLE then
    return RomText.ascii(RomText.key("gTexts_UR_BattleReaction", g, pick({ 0, 1, 2, 3 })), ctx)
  elseif raw == Union.ACTIVITY.TRADE then
    return RomText.ascii(RomText.key("gTexts_UR_TradeReaction", g, pick({ 0, 1 })), ctx)
  elseif raw == Union.ACTIVITY.CHAT then
    return RomText.ascii(RomText.key("gTexts_UR_ChatReaction", g, pick({ 0, 1, 2, 3 })), ctx)
  elseif raw == Union.ACTIVITY.CARD then
    return RomText.ascii(RomText.key("gTexts_UR_TrainerCardReaction", g, pick({ 0, 1 })), ctx)
  end
  return RomText.ascii("gText_UR_TrainerAppearsBusy", ctx)
end

-- pokefirered/src/union_room_message.c:243
Union.JOIN_CHAT_TEXTS = {
  [0] = { [0] = "sText_JoinChatMale", [1] = "sText_JoinChatFemale" },
  [1] = { [0] = "sText_PlayerJoinChatMale", [1] = "sText_PlayerJoinChatFemale" },
}
-- pokefirered/src/union_room_message.c:176
Union.HI_TEXTS = {
  [0] = { [0] = "sText_HiDoSomethingMale", [1] = "sText_HiDoSomethingFemale" },
  [1] = { [0] = "sText_HiDoSomethingAgainMale", [1] = "sText_HiDoSomethingAgainFemale" },
}
-- pokefirered/src/union_room_message.c:284
Union.START_TEXTS = {
  [0] = {
    [0] = { "sText_BattleWillBeStarted", "sText_EnteringChat", "sText_TradeWillBeStarted" },
    [1] = { "sText_BattleWillBeStarted", "sText_EnteringChat", "sText_TradeWillBeStarted" },
  },
  [1] = {
    [0] = { "sText_DoneWaitingBattleMale", "sText_DoneWaitingChatMale", "sText_TradeWillBeStarted" },
    [1] = { "sText_DoneWaitingBattleFemale", "sText_DoneWaitingChatFemale", "sText_TradeWillBeStarted" },
  },
}
-- pokefirered/src/union_room.c:4272
function Union.waitTextIndex(activity)
  local raw = math.floor(tonumber(activity) or 0) % Union.IN_UNION_ROOM
  if raw == Union.ACTIVITY.CHAT then return 1 end
  if raw == Union.ACTIVITY.TRADE then return 2 end
  if raw == Union.ACTIVITY.CARD then return 3 end
  return 0
end

function Union.partnerRow()
  return Union.players[Union.partnerId or 0] or Union._partner
end

-- pokefirered/src/union_room.c:2891
function Union.doSomethingPrompt(again)
  local p = Union.partnerRow() or {}
  local met = (again or Union.metBefore(p)) and 1 or 0
  local text = RomText.ascii(Union.HI_TEXTS[met][genderIndex(p)], textCtx({ stringVars = { p.name or "" } }))
  return Union.runFlow(stepsOf(
    Union.stayStep(text),
    Union.doStep(function()
      local s = screen()
      if not s then return Union.toMain() end
      Union.state = "handle_do_something_prompt_input"
      s.showActivities(Union.INVITE_ITEMS, {
        partner = p,
        onChoose = function(index) Union.chooseActivity(index) end,
        onCancel = function() Union.chooseActivity(#Union.INVITE_ITEMS) end,
      })
    end)
  ), "do_something_prompt")
end

function Union.chatHasRoom(p)
  local g = type(p.group) == "table" and p.group or nil
  local seats = g and type(g.members) == "table" and #g.members or 0
  return seats < Union.GROUP_SIZE
end

-- pokefirered/src/union_room.c:2805
function Union.talkTo(slot)
  local p = Union.players[slot]
  if p and not p.gone and Union.usesXg(p) then return Union.xgTalk(slot) end
  if Union.isRs() then return Union.printAndExit(Union.xgText("busy", p), slot) end
  if not p or p.gone then
    return Union.printAndExit(RomText.ascii("gText_UR_TrainerAppearsBusy"), slot)
  end
  Union.partnerId = slot
  Union._partner = p
  local raw = math.floor(tonumber(p.activity) or 0) % Union.IN_UNION_ROOM
  if idleActivity(p.activity) then return Union.doSomethingPrompt(false) end
  local g = genderIndex(p)
  local ctx = textCtx({ stringVars = { p.name or "" } })
  if raw == Union.ACTIVITY.CHAT and Union.chatHasRoom(p) then
    local met = Union.metBefore(p) and 1 or 0
    return Union.runFlow(stepsOf(
      Union.stayStep(RomText.ascii(Union.JOIN_CHAT_TEXTS[met][g], ctx)),
      Union.yesNoStep(function(yes)
        if yes then return Union.joinChat(slot) end
        Union.printAndExit(RomText.ascii(RomText.key("gTexts_UR_DeclineChat", g), ctx), slot)
      end)
    ), "recv_join_chat_request")
  end
  return Union.printAndExit(Union.reactionText(p.activity, g, p.name), slot)
end

Union.XG_ITEMS = {
  { key = "XG_BATTLE", wire = "xg_battle", activity = "BATTLE_SINGLE" },
  { key = "XG_TRADE", wire = "xg_trade", activity = "TRADE" },
  { key = "EXIT" },
}

function Union.gameName(version)
  local info = require("src.core.GameVersion").VERSIONS[version or ""]
  return info and tostring(info.label or version):upper() or ""
end

local function nameList(versions)
  local names = {}
  for _, v in ipairs(versions or {}) do names[#names + 1] = Union.gameName(v) end
  local Strings = require("src.core.Strings")
  if #names <= 1 then return names[1] or "" end
  return Strings("%s or %s", table.concat(names, ", ", 1, #names - 1), names[#names])
end

function Union.xgText(key, p, extra)
  local Strings = require("src.core.Strings")
  p = type(p) == "table" and p or {}
  local name, game = tostring(p.name or ""), Union.gameName(p.game)
  if key == "talk" then return Strings("%s from POKéMON %s is here.\nWhat would you like to do?", name, game) end
  if key == "standin" then
    return Strings("Import POKéMON %s to see how %s really looks.", nameList(extra), name)
  end
  if key == "wait_battle" then return Strings("Waiting for %s to answer\nthe battle request...", name) end
  if key == "wait_trade" then return Strings("Waiting for %s to answer\nthe trade request...", name) end
  if key == "declined_battle" then return Strings("%s turned down the battle.", name) end
  if key == "declined_trade" then return Strings("%s turned down the trade.", name) end
  if key == "busy" then return Strings("%s seems to be busy right now.", name) end
  if key == "link_lost" then return Strings("The link with %s was lost.", name) end
  if key == "ask_battle" then return Strings("%s from POKéMON %s wants to battle!\nWill you accept?", name, game) end
  if key == "ask_trade" then return Strings("%s from POKéMON %s wants to trade!\nWill you accept?", name, game) end
  if key == "you_declined" then return Strings("You turned down the request.") end
  if key == "preparing_battle" then return Strings("Getting ready to battle %s...", name) end
  if key == "preparing_trade" then return Strings("Getting ready to trade with %s...", name) end
  if key == "unavailable" then
    return Strings("Battles and trades between different games aren't open yet. The request was canceled.")
  end
  if key == "peer_canceled" then return Strings("%s canceled the request.", name) end
  if key == "canceled" then return Strings("The request was canceled.") end
  if key == "blocked" then return Strings("Your games can't link up for this. The request was canceled.") end
  if key == "server_outdated" then
    return Strings("The UNION ROOM server needs an update before trainers from other games can join you.")
  end
  if key == "goodbye" then return Strings("See you around!") end
  if key == "label_battle" then return Strings("BATTLE") end
  if key == "label_trade" then return Strings("TRADE") end
  if key == "label_exit" then return Strings("EXIT") end
  return ""
end

function Union.xgItems()
  local s = screen()
  local out = {}
  for i, item in ipairs(Union.XG_ITEMS) do
    local label
    if item.wire == "xg_trade" then
      label = Union.xgText("label_trade")
    elseif not Union.isRs() and s and s.labelFor then
      label = s.labelFor({ key = item.wire and "BATTLE" or "EXIT" })
    else
      label = Union.xgText(item.wire and "label_battle" or "label_exit")
    end
    out[i] = { key = item.key, wire = item.wire, activity = item.activity, label = label }
  end
  return out
end

function Union.usesXg(p)
  if type(p) ~= "table" then return false end
  if Union.isRs() then return true end
  return Union.isForeign(p) or Family.isRubySapphire(p.game)
end

function Union.xgTalk(slot)
  local p = Union.players[slot]
  Union.partnerId = slot
  Union._partner = p
  if not Union.memberIdle(p) then return Union.printAndExit(Union.xgText("busy", p), slot) end
  local steps = {}
  if Union.isForeign(p) then
    local entry = Union.foreignEntry(p)
    if entry.standin or entry.hostStandin then steps[#steps + 1] = Union.sayStep(Union.xgText("standin", p, entry.need)) end
  end
  steps[#steps + 1] = Union.stayStep(Union.xgText("talk", p))
  steps[#steps + 1] = Union.doStep(function()
    local s = screen()
    if not s then return Union.toMain() end
    Union.state = "handle_do_something_prompt_input"
    s.showActivities(Union.xgItems(), {
      partner = p,
      onChoose = function(index) Union.chooseXg(index) end,
      onCancel = function() Union.chooseXg(#Union.XG_ITEMS) end,
    })
  end)
  return Union.runFlow(steps, "do_something_prompt")
end

function Union.chooseXg(index)
  local item = Union.XG_ITEMS[tonumber(index) or 0]
  local p = Union.partnerRow() or {}
  local M = message()
  if not (item and item.wire) then
    Union.activity = nil
    Union.partnerId = nil
    if Union.isRs() then return Union.printAndExit(Union.xgText("goodbye", p)) end
    -- pokefirered/src/union_room.c:2916
    local text = RomText.ascii(RomText.key("gTexts_UR_IfYouWantToDoSomething", tonumber(p.gender) == 1 and 1 or 0))
    return Union.printAndExit(text)
  end
  local L = link()
  Union.activity = Union.ACTIVITY[item.activity] + Union.IN_UNION_ROOM
  Union._xg = item.wire
  Union._role = "child"
  Union.invite = p.id ~= nil and L.clientCall("invite", p.id, item.wire, {}, L.liveProfile()) or nil
  if not Union.invite then return Union.printAndExit(Union.xgText("busy", p)) end
  Union.state = "send_activity_request"
  if M and M.show then
    M.show(Union.xgText(item.wire == "xg_trade" and "wait_trade" or "wait_battle", p), { stay = true })
  end
  return true
end

function Union.xgMode()
  return require("src.online.Protocol2").XG_ACTIVITIES[Union._xg or ""]
end

Union.xgScreens = { battle = nil, trade = nil }

local XgActivity = {}
XgActivity.__index = XgActivity
Union.XgActivity = XgActivity

local function xgPeer(roomInfo, mySeat, partner)
  for _, row in ipairs(type(roomInfo.players) == "table" and roomInfo.players or {}) do
    if type(row) == "table" and row.seat ~= nil and row.seat ~= mySeat then
      local av = type(row.avatar) == "table" and row.avatar or {}
      return { id = row.id, name = av.name or row.name or "?", gen = row.gen, game = av.version, seat = row.seat }
    end
  end
  partner = type(partner) == "table" and partner or {}
  return { id = partner.id, name = partner.name or "?", gen = partner.sourceGen, game = partner.game }
end

function XgActivity:release()
  if Union._xgSession == self then Union._xgSession = nil end
  Union.noteLeftRoom(self.roomId)
  link().setStatus("idle")
end

function XgActivity:finish(why, text)
  if self.done or self.state == "done" then return end
  local Flow = require("src.ui.union.Flow")
  if why == "go" and not self.launched then
    self.state = "battle"
    if Flow.launch(self, 3) then return end
    why, text = "error", require("src.ui.g3u.Launch").resultText(3, "error")
  end
  self.why = why
  self.state = "done"
  Flow.leaveRoom(self)
  self:release()
  local M = message()
  if M and M.isOpen and M.isOpen() then M.close() end
  Union.partnerId = nil
  self.done = true
  if text and M and M.show then return Union.printAndExit(text) end
  Union.toMain()
end

function XgActivity:cancel(why)
  local prep = self.prep
  if prep then
    if prep:open() then prep:cancel(why or "cancel") end
    prep:leave()
  end
  self:finish(why or "cancel", Union.xgText("canceled", self.peer))
end

function XgActivity:abort(why)
  if self.done then return end
  local prep = self.prep
  if prep and prep:open() then
    prep:cancel(why or "left")
    prep:leave()
  end
  self.state = "done"
  self.why = why or "left"
  self.done = true
  self:release()
end

function XgActivity:handle(e)
  if e.kind == "closed" then
    local mine = e.seat ~= nil and e.seat == self.prep:seat()
    if mine then return self:finish("closed", Union.xgText("canceled", self.peer)) or true end
    playSe("SE_FAILURE")
    self:finish("peer", Union.xgText("peer_canceled", self.peer))
    return true
  end
  if e.kind == "blocked" then
    self.prep:cancel("blocked")
    self.prep:leave()
    self:finish("blocked", Union.xgText("blocked", self.peer))
    return true
  end
  return false
end

function XgActivity:tick(dt)
  if self.done or self.state == "done" or self.state == "screen" or self.state == "battle" then return end
  local prep = self.prep
  if not prep then return self:finish("gone", Union.xgText("link_lost", self.peer)) end
  for _, e in ipairs(prep:poll()) do
    if self:handle(e) then return end
  end
  local screen = Union.xgScreens[self.mode]
  if not screen then
    self.t = (self.t or 0) + (tonumber(dt) or 0)
    if self.t >= Union.XG_NOTICE_SECONDS then
      if prep:open() then prep:cancel("unavailable") end
      prep:leave()
      return self:finish("unavailable", Union.xgText("unavailable", self.peer))
    end
    return
  end
  if prep.state == "prep" and self.state == "preparing" then
    self.state = "screen"
    local M = message()
    if M and M.isOpen and M.isOpen() then M.close() end
    screen(self)
    return
  end
  if pressedB() then self:cancel("cancel") end
end

Union.XG_NOTICE_SECONDS = 1

function Union.beginXg(roomInfo, mode)
  local L = link()
  if not Union.xgInstalled then
    Union.xgInstalled = true
    require("src.ui.union.Flow").install({ screens = Union.xgScreens })
  end
  Union._await = nil
  roomInfo = type(roomInfo) == "table" and roomInfo or {}
  mode = mode or roomInfo.mode or (type(roomInfo.xg) == "table" and roomInfo.xg.mode) or "battle"
  mode = mode == "trade" and "trade" or "battle"
  local client = L.client()
  local prep
  if client and roomInfo.room ~= nil then
    local Room = require("src.online.union.Room")
    prep = require("src.online.union.Prep").new(Room.adapter(client, roomInfo.room), { mode = mode })
  end
  local mySeat = client and client.seat and client.seat() or nil
  local act = setmetatable({
    game = L.game(), room = roomInfo, roomId = roomInfo.room, mode = mode, prep = prep,
    peer = xgPeer(roomInfo, mySeat, Union.partnerRow()), state = "preparing", done = false, why = nil,
    role = Union._role, wire = Union._xg,
  }, XgActivity)
  Union._xgSession = act
  Union.state = "xg_prep"
  local M = message()
  if M and M.show then
    M.show(Union.xgText(mode == "trade" and "preparing_trade" or "preparing_battle", act.peer), { stay = true })
  end
  return act
end

function Union.endXg(act, why)
  act = act or Union._xgSession
  if not act then return false end
  act:abort(why)
  return true
end

function Union.xgFail(key)
  local p = Union.partnerRow() or {}
  Union._await = nil
  Union.invite = nil
  local M = message()
  if M and M.isOpen and M.isOpen() then M.close() end
  if M and M.show then return Union.printAndExit(Union.xgText(key, p)) end
  Union.state = "print_and_exit"
end


-- pokefirered/src/union_room.c:3027
function Union.joinChat(slot)
  local L = link()
  local p = Union.players[slot] or Union._partner
  local profile = L.liveProfile(Union.rulesetFor("chat"))
  Union.activity = Union.ACTIVITY.CHAT + Union.IN_UNION_ROOM
  Union._role = "child"
  Union._joining = true
  Union.invite = L.clientCall("invite", p and p.id, "chat", { join = true }, profile)
  Union.flow = nil
  Union.state = "send_activity_request"
  return true
end

-- pokefirered/data/maps/UnionRoom/scripts.inc:26
function Union.scriptWaitTask()
  if not Union._held then
    local L = link()
    local c = L.vmCtx()
    Union._held = { result = L.getVar(c, L.VAR_RESULT) }
    Union._scriptResult = Union._held.result
  end
  if Union._held.release then
    Union._held = nil
    return true
  end
  return false
end

-- pokefirered/src/union_room.c:4655
function Union.releaseScript()
  if Union._held then Union._held.release = true end
end

function Union.armScriptWait(ctx)
  if not ctx or Union._held then return end
  if ctx.stateWait == nil then ctx.stateWait = Union.scriptWaitTask end
end

function Union.disarmScriptWait(ctx)
  if ctx and ctx.stateWait == Union.scriptWaitTask then ctx.stateWait = nil end
  if Union._held then Union._held.release = true end
end

function Union.pollMain(ctx)
  local L = link()
  if Union.isRs() then
    local Hud = package.loaded["src.ui.game3.hud"]
    if Hud and Hud.busy and Hud.busy() then return end
    if not pressedA() then return end
    local slot = Union.tryInteractWithMember()
    if not slot then return end
    playSe("SE_SELECT")
    return Union.talkTo(slot)
  end
  Union.armScriptWait(ctx)
  local result = Union._scriptResult or L.getVar(ctx, L.VAR_RESULT)
  Union._scriptResult = nil
  if result ~= 0 then
    L.setVar(ctx, L.VAR_RESULT, 0)
    if result == Union.INTERACT_ATTENDANT then return Union.attendant() end
    Union.releaseScript()
    return
  end
  if Union._held and not Union.flow then Union.releaseScript() end
  local Hud = package.loaded["src.ui.game3.hud"]
  if Hud and Hud.busy and Hud.busy() then return end
  if not pressedA() then return end
  local slot = Union.tryInteractWithMember()
  if slot then
    playSe("SE_SELECT")
    return Union.talkTo(slot)
  end
  if Union.facingTradingBoard() then return Union.checkTradingBoard() end
end

function Union.facingTradingBoard()
  local P = playerMod()
  if not P or P.moving then return false end
  local d = FACING_DELTA[P.facing or "down"]
  if not d then return false end
  local board = plazaMap().TRADING_BOARD or Union.TRADING_BOARD
  return (tonumber(P.cellX) or 0) + d[1] == board.x
    and (tonumber(P.cellY) or 0) + d[2] == board.y
end

-- pokefirered/src/union_room.c:3148
function Union.contactedYou()
  local inv = Union.incoming or {}
  local from = type(inv.from) == "table" and inv.from or {}
  local name = Union._requestName or from.name or ""
  Union.state = "handle_activity_request"
  Union._asked = true
  if Union._xg then
    local p = Union.partnerRow() or { name = name }
    return Union.runFlow(stepsOf(
      Union.stayStep(Union.xgText(Union._xg == "xg_trade" and "ask_trade" or "ask_battle", p)),
      Union.yesNoStep(function(yes) Union.answerRequest(yes) end)
    ), "handle_activity_request")
  end
  -- pokefirered/src/union_room.c:4486 GetChatLeaderActionRequestMessage
  local steps = stepsOf(Union.stayStep(Union.requestPrompt()))
  steps[#steps + 1] = Union.yesNoStep(function(yes) Union.answerRequest(yes) end)
  return Union.runFlow(steps, "handle_activity_request")
end

-- pokefirered/src/union_room.c:4467
function Union.startText()
  local raw = math.floor(tonumber(Union.activity) or 0) % Union.IN_UNION_ROOM
  local idx = raw == Union.ACTIVITY.CHAT and 2 or raw == Union.ACTIVITY.TRADE and 3 or 1
  local mp = Union._role == "child" and 1 or 0
  local p = Union.partnerRow() or {}
  local key = Union.START_TEXTS[mp][genderIndex(p)][idx]
  return RomText.ascii(key, textCtx())
end

-- pokefirered/src/union_room.c:1713
function Union.pollInActivity()
  local raw = math.floor(tonumber(Union.activity) or 0) % Union.IN_UNION_ROOM
  if raw == Union.ACTIVITY.CHAT then
    if not chat().isActive() then Union.toMain() end
  elseif raw == Union.ACTIVITY.CARD then
    local okC, TrainerCard = pcall(require, "src.ui.game3.trainer_card")
    if not (okC and TrainerCard.isOpen and TrainerCard.isOpen()) then Union.toMain() end
  elseif raw == Union.ACTIVITY.TRADE then
    if not linkTrade().isActive() then
      Union.finishBoardTrade()
      Union.noteLeftRoom()
      link().closeLink("trade_done")
      Union.partnerId = nil
      Union.toMain()
    end
  else
    local LB = battle()
    if LB.state == "setup" then
      LB.pumpUnionSetup()
    elseif LB.state ~= "battle" then
      Union.partnerId = nil
      Union.toMain()
    end
  end
end

local SCREEN_STATES = {
  handle_do_something_prompt_input = true,
  register_prompt_input = true,
  register_request_type = true,
  trading_board = true,
}

-- pokefirered/src/union_room.c:2647
function Union.relayUpdate(dt, ctx)
  Union.relayTick(dt)
  if Union.flow then
    Union.stepFlow()
    if Union.flow then return true end
  end
  local st = Union.state
  if st == "init" then
    Union.state = "main"
  elseif st == "main" then
    Union.pollMain(ctx)
  elseif st == "player_contacted_you" then
    Union.contactedYou()
  elseif st == "send_activity_request" then
    Union.pollInvite()
  elseif st == "await_room" then
    Union.pollAwaitRoom(dt)
  elseif st == "await_link" then
    Union.pollAwaitLink(dt)
  elseif st == "start_activity" then
    Union.startActivity()
  elseif st == "in_activity" then
    Union.pollInActivity()
  elseif st == "xg_prep" then
    if Union._xgSession then Union._xgSession:tick(dt) else Union.toMain() end
  elseif st == "print_and_exit" then
    local Mo = message()
    if not (Mo and Mo.isOpen and Mo.isOpen()) then Union.toMain() end
  elseif SCREEN_STATES[st] then
    local s = screen()
    if not (s and s.isOpen and s.isOpen()) then Union.toMain() end
  end
  if Union.flow then Union.stepFlow() end
  return true
end

-- pokefirered/src/union_room.c:3230
function Union.printStartActivity()
  return Union.runFlow(stepsOf(
    Union.pauseStep(Union.startText(), 60),
    Union.doStep(function()
      Union.flow = nil
      Union.state = "start_activity"
    end)
  ), "start_activity_msg")
end

function Union.sendInvite(activity)
  local L = link()
  local p = Union.players[Union.partnerId or 0]
  local wire = Union.wireFor(activity)
  if not (p and p.id ~= nil and wire) then return false end
  local ruleset = Union.rulesetFor(wire)
  Union.invite = L.clientCall("invite", p.id, wire, { ruleset = ruleset }, L.liveProfile(ruleset))
  return Union.invite ~= nil
end

-- pokefirered/src/union_room.c:4448
function Union.rejectText(activity, gender)
  local raw = math.floor(tonumber(activity) or 0) % Union.IN_UNION_ROOM
  local g = tonumber(gender) == 1 and 1 or 0
  if raw == Union.ACTIVITY.BATTLE_SINGLE then
    return RomText.ascii(RomText.key("gTexts_UR_BattleDeclined", g))
  elseif raw == Union.ACTIVITY.CHAT then
    return RomText.ascii(RomText.key("gTexts_UR_ChatDeclined", g))
  elseif raw == Union.ACTIVITY.TRADE then
    return RomText.ascii("gText_UR_TradeOfferRejected")
  elseif raw == Union.ACTIVITY.CARD then
    return RomText.ascii(RomText.key("gTexts_UR_ShowTrainerCardDeclined", g))
  end
  return RomText.ascii("gText_UR_TrainerAppearsBusy")
end

function Union.pollInvite()
  local h = Union.invite
  if not h then
    Union.state = "print_and_exit"
    return
  end
  if h.state == "accepted" or h.why == "accepted" or h.why == "crossed" then
    Union.invite = nil
    Union.lastResult = "accepted"
    Union.beginAwaitRoom(h.room)
    return
  end
  local dropped = false
  if h.state ~= "closed" then
    local cs = link().connectState()
    if cs ~= "error" and cs ~= "offline" then return end
    dropped = true
  end
  Union.invite = nil
  local M = message()
  local text
  local p = Union.partnerRow()
  if Union._xg then
    Union._joining = nil
    Union.lastResult = (not dropped and h.why == "declined") and "declined" or "busy"
    if dropped then return Union.xgFail("link_lost") end
    if h.why == "declined" then return Union.xgFail(Union._xg == "xg_trade" and "declined_trade" or "declined_battle") end
    return Union.xgFail("busy")
  end
  if dropped then
    Union._joining = nil
    Union.lastResult = "busy"
    -- pokefirered/src/union_room.c:2963
    text = RomText.ascii("gText_UR_TrainerBattleBusy")
  elseif Union._joining then
    Union._joining = nil
    Union.lastResult = h.why == "declined" and "declined" or "busy"
    -- pokefirered/src/union_room.c:3074
    text = RomText.ascii(RomText.key("gTexts_UR_ChatDeclined", tonumber(p and p.gender) == 1 and 1 or 0))
  elseif h.why == "declined" then
    Union.lastResult = "declined"
    text = Union.rejectText(Union.activity, p and p.gender)
  else
    Union.lastResult = "busy"
    -- pokefirered/src/union_room.c:2937
    text = RomText.ascii("gText_UR_TrainerAppearsBusy")
  end
  if M and M.isOpen and M.isOpen() then M.close() end
  if M and M.show then return Union.printAndExit(text) end
  Union.state = "print_and_exit"
end

function Union.matchStarted(room)
  return type(room) == "table" and room.stage == "battling" and room.match ~= nil
end

function Union.beginAwaitRoom(roomId)
  Union._await = { room = roomId, t = 0 }
  Union.state = "await_room"
end

local function failActivity(key)
  local L = link()
  L.closeLink("activity_failed")
  Union._await = nil
  local M = message()
  if M and M.show and key then M.show(RomText.ascii(key)) end
  Union.state = "print_and_exit"
end

function Union.pollAwaitRoom(dt)
  local L = link()
  local a = Union._await or { t = 0 }
  Union._await = a
  a.t = a.t + (tonumber(dt) or 0)
  local room = L.clientCall("room")
  local id = type(room) == "table" and room.room or nil
  local stale = id ~= nil and Union._leftRooms and Union._leftRooms[id]
  if Union._xg then
    if room and not stale and room.intent == "xg" and (a.room == nil or id == a.room) then
      return Union.beginXg(room, Union.xgMode())
    end
    if not L.online() or a.t >= Union.AWAIT_ROOM_SECONDS then return Union.xgFail("busy") end
    return
  end
  if room and not stale and (a.room == nil or id == a.room) and Union.matchStarted(room) then
    local M = message()
    if M and M.isOpen and M.isOpen() then M.close() end
    local raw = math.floor(tonumber(Union.activity) or 0) % Union.IN_UNION_ROOM
    if raw == Union.ACTIVITY.CHAT then
      Union._await = nil
      Union._chatSession = L.clientCall("roomSession")
      if not Union._chatSession then return failActivity("gText_UR_LinkWithFriendDropped") end
      if M and M.show and type(love) == "table" and love.graphics then return Union.printStartActivity() end
      Union.state = "start_activity"
      return
    end
    if L.openRelay({ linkType = Union.linkTypeFor(Union.activity) }) then
      a.t = 0
      Union.state = "await_link"
      return
    end
    return failActivity("gText_UR_LinkWithFriendDropped")
  end
  if not L.online() or a.t >= Union.AWAIT_ROOM_SECONDS then
    return failActivity("gText_UR_TrainerAppearsBusy")
  end
end

function Union.pollAwaitLink(dt)
  local L = link()
  local a = Union._await or { t = 0 }
  Union._await = a
  a.t = a.t + (tonumber(dt) or 0)
  local lk = L.link
  if not (lk and lk:isOpen()) then return failActivity("gText_UR_LinkWithFriendDropped") end
  if not lk:isReady() then return end
  local raw = math.floor(tonumber(Union.activity) or 0) % Union.IN_UNION_ROOM
  -- pokefirered/src/union_room.c:1863
  if raw == Union.ACTIVITY.CARD and not L.peerCard and a.t < Union.CARD_WAIT_SECONDS then return end
  Union._await = nil
  local M = message()
  if M and M.show and type(love) == "table" and love.graphics then
    if raw == Union.ACTIVITY.CARD then return Union.cardFlow() end
    return Union.printStartActivity()
  end
  Union.state = "start_activity"
end

-- pokefirered/src/union_room.c:2999
function Union.cardFlow()
  local L = link()
  local card = L.peerCard or {}
  local isParent = Union._role ~= "child"
  local function finish()
    Union.recordMet(Union.partnerRow() or { name = card.name, trainerId = card.trainerId })
    Union.noteLeftRoom()
    L.closeLink("card_done")
    L.setStatus("idle")
    Union.lastResult = "card_shown"
    if isParent then return Union.toMain() end
    return Union.doSomethingPrompt(true)
  end
  Union.lastResult = "card_shown"
  local okC, TrainerCard = pcall(require, "src.ui.game3.trainer_card")
  if not (okC and TrainerCard.show) then return finish() end
  local viewing = true
  TrainerCard.show({ session = card, onClose = function() viewing = false end })
  return Union.runFlow({
    Union.waitStep(function() return not viewing end),
    Union.doStep(finish),
  }, "card_view")
end

function Union.partyPreview()
  local s = link().session()
  local out = {}
  for i = 1, 6 do
    local mon = s and s.party and s.party[i]
    local species = mon and not mon.isEgg and tonumber(mon.species) or nil
    if species and species > 0 then out[#out + 1] = species end
  end
  return out
end

-- pokefirered/src/union_room.c:1872
function Union.directDest(group)
  local L = link()
  local LT = require("src.link.Game3Link").LINKTYPE
  if group == Union.LINK_GROUP.SINGLE_BATTLE then
    return Union.COLOSSEUM_2P, L.USING.SINGLE_BATTLE, LT.BATTLE
  elseif group == Union.LINK_GROUP.DOUBLE_BATTLE then
    return Union.COLOSSEUM_2P, L.USING.DOUBLE_BATTLE, LT.BATTLE
  elseif group == Union.LINK_GROUP.MULTI_BATTLE then
    return Union.COLOSSEUM_4P, L.USING.MULTI_BATTLE, LT.BATTLE
  end
  return Union.TRADE_CENTER, L.USING.TRADE_CENTER, LT.TRADE_SETUP
end

-- pokefirered/src/union_room.c:1975
Union.COLOSSEUM_SEATS_BY_FAMILY = {
  -- pokefirered/data/maps/BattleColosseum_2P/map.json coord_events
  frlg = {
    [0] = { x = 3, y = 5, script = "BattleColosseum_2P_EventScript_PlayerSpot0" },
    [1] = { x = 10, y = 5, script = "BattleColosseum_2P_EventScript_PlayerSpot1" },
  },
  -- pokeemerald/data/maps/BattleColosseum_2P/map.json coord_events
  rse = {
    [0] = { x = 3, y = 5, script = "EventScript_BattleColosseum_2P_PlayerSpot0" },
    [1] = { x = 10, y = 5, script = "EventScript_BattleColosseum_2P_PlayerSpot1" },
  },
}
Union.COLOSSEUM_SEATS = setmetatable({}, {
  __index = function(_, seat)
    if Family.isRubySapphire(Family.activeVersion()) then
      return ({
        [0] = { x = 3, y = 5, script = "SingleBattleColosseum_EventScript_1A436F" },
        [1] = { x = 10, y = 5, script = "SingleBattleColosseum_EventScript_1A4379" },
      })[seat]
    end
    local rows = Union.COLOSSEUM_SEATS_BY_FAMILY[Family.of()] or Union.COLOSSEUM_SEATS_BY_FAMILY.frlg
    return rows[seat]
  end,
})
Union.PARTNER_LOCAL_ID = 30

local function seatPath(fromX, fromY, toX, toY, lead)
  local C = require("src.core.game3.scripting.movement").CMD
  local out = {}
  local function add(cmd, n) for _ = 1, math.max(0, n) do out[#out + 1] = cmd end end
  add(C.DELAY_16, lead or 0)
  local midY = lead and fromY - 1 or toY
  add(C.WALK_UP, fromY - midY)
  add(C.WALK_LEFT, fromX - toX)
  add(C.WALK_RIGHT, toX - fromX)
  add(C.WALK_UP, midY - toY)
  out[#out + 1] = C.STEP_END
  return out
end

function Union.walkToSeats()
  local L = link()
  local lk = L.link
  if not (lk and lk:isOpen()) then return false end
  local seat = tonumber(lk.seat) or 0
  local mine, theirs = Union.COLOSSEUM_SEATS[seat], Union.COLOSSEUM_SEATS[1 - seat]
  if not (mine and theirs) then return false end
  local ctx, adapters = L.vmCtx()
  if not (ctx and adapters) then return false end
  local Movement = require("src.core.game3.scripting.movement")
  local px, py = L.playerCell()
  local Objects = objects()
  local g3 = type(lk.peerHello) == "table" and type(lk.peerHello.game3) == "table" and lk.peerHello.game3 or {}
  if Objects and type(Objects._defs) == "table" and Objects.addObject then
    Objects._defs[#Objects._defs + 1] = {
      localId = Union.PARTNER_LOCAL_ID, x = px, y = py, facing = "up",
      graphicsId = (Family.linkPlayerGfx(nil, g3.version, g3.gender)),
    }
    if Objects.addObject(Union.PARTNER_LOCAL_ID) then
      Movement.start(ctx, Union.PARTNER_LOCAL_ID, seatPath(px, py, theirs.x, theirs.y, 2), adapters)
    end
  end
  local walk = Movement.start(ctx, Movement.LOCALID_PLAYER, seatPath(px, py, mine.x, mine.y), adapters)
  local Space = require("src.core.game3.scripting.space")
  require("src.core.game3.task").spawn(function()
    Movement.tick(ctx, adapters)
    if not walk.done then return false end
    if Space.vm and Space.vm:isRunning() then return false end
    Space.startScript(mine.script)
    return true
  end, { frames = 1200 })
  return true
end

function Union.seatAfterWarp(mapId)
  local Space = require("src.core.game3.scripting.space")
  require("src.core.game3.task").spawn(function()
    if Space.mapId ~= mapId then return false end
    if Space.vm and Space.vm:isRunning() then return false end
    Union.walkToSeats()
    return true
  end, { frames = 600 })
end

function Union.armCableClub(ctx, group)
  local dest, service = Union.directDest(group)
  local started, finished = false, false
  local function warpTask()
    if not started then
      started = true
      Union.warpForCableClubActivity(dest, service, {
        cableClubWarp = true,
        onDone = function()
          finished = true
          if dest == Union.COLOSSEUM_2P then Union.seatAfterWarp(dest.map) end
        end,
      })
    end
    return finished
  end
  natives().awaitState(ctx, function()
    ctx.stateWait = warpTask
    return true
  end)
end

local function directUi()
  local ok, LinkMenu = pcall(require, "src.ui.game3.link_menu")
  return ok and type(LinkMenu) == "table" and LinkMenu.Direct or nil
end

local function pinEntry()
  return require("src.ui.game3.pin_entry")
end

local function roomCount()
  local room = link().clientCall("room")
  return type(room) == "table" and type(room.players) == "table" and #room.players or 0
end

function Union.waitForMatch(ctx, adapters, spec)
  local L = link()
  local M = message()
  local D = directUi()
  natives().yieldHost(ctx, adapters, function() end)
  -- pokefirered/src/cable_club.c:833
  if M and M.show then M.show(RomText.ascii("CableClub_Text_PleaseWaitBCancel"), { stay = true }) end
  local done = false
  local function finish(code)
    if D then D.close() end
    if M and M.isOpen and M.isOpen() then M.close() end
    if code then linkupResult(ctx, code) end
    done = true
    return true
  end
  local function cancel()
    spec.cancel()
    L.setStatus("busy")
    return finish(L.LINKUP.FAILED)
  end
  local refused = nil
  local function poll()
    if done then return true end
    if refused then
      if refused.closed then
        L.setStatus("busy")
        return finish(L.LINKUP.FAILED)
      end
      return false
    end
    local room = L.clientCall("room")
    if Union.matchStarted(room) then
      local text = spec.refuse and spec.refuse(room)
      if text then
        spec.cancel()
        refused = {}
        if D then D.close() end
        if M and M.show then
          M.show(text, { done = function() refused.closed = true end })
        else
          refused.closed = true
        end
        return false
      end
      finish(nil)
      spec.onMatch()
      return true
    end
    if not L.online() then
      spec.cancel()
      return finish(L.LINKUP.CONNECTION_ERROR)
    end
    if D and D.isOpen() then
      -- pokefirered/src/cable_club.c:102
      D.setCount(roomCount())
    elseif L.inputPressed("b") then
      return cancel()
    end
    return false
  end
  if D then
    D.show({ onUpdate = poll })
    D.showWait({ onCancel = cancel })
  end
  ctx.nativePoll = poll
  return true
end

-- pokefirered/include/constants/menu.h:70
Union.MULTICHOICE_JOIN_OR_LEAD = 63

-- pokefirered/src/union_room.c:902
function Union.askedToJoinText(wire, name)
  local key = wire == "battle_multi" and "gText_UR_PlayerHasBeenAskedToRegisterYouPleaseWait"
    or "gText_UR_AwaitingPlayersResponse"
  return RomText.ascii(key, { stringVars = { name or "" } })
end

Union.JOIN_OR_LEAD_LIST = {
  frlg = 63,
  -- pokeemerald/include/constants/script_menu.h:92
  rse = 81,
}

function Union.directModes(ctx, row, done)
  local L = link()
  local listId = type(row) == "table" and tonumber(row.listId or row[3]) or nil
  if listId and listId ~= (Union.JOIN_OR_LEAD_LIST[Family.of()] or Union.MULTICHOICE_JOIN_OR_LEAD) then
    return false
  end
  local group = tonumber(L.getVar(ctx, L.VAR_0x8004)) or -1
  if group < Union.LINK_GROUP.SINGLE_BATTLE or group > Union.LINK_GROUP.TRADE then return false end
  if not L.adapterConnected() then return false end
  local D = directUi()
  local M = message()
  local Choice = choice()
  if not (D and M and Choice) then return false end
  local Strings = require("src.core.Strings")
  local prompt = Strings("AUTO or CHOOSE finds a partner.\nSET PIN hosts a private room.")
  M.show(prompt, { stay = true, speed = 0 })
  local ask = nil
  Union.direct = {}
  local function finish(sel, direct)
    Union.direct = direct or {}
    D.close()
    done(sel)
  end
  local menu
  local function restorePrompt()
    if prompt then M.show(prompt, { stay = true, speed = 0 }) end
  end
  local function question(text, cb)
    M.show(text, { stay = true })
    ask = cb
  end
  local function setPin()
    D.view = "none"
    if M.isOpen() then M.close() end
    pinEntry().show({
      mode = "set",
      onDone = function(pin)
        if not pin then
          restorePrompt()
          return menu(3)
        end
        question(Strings("Use this PIN?"), function(yes)
          if not yes then return setPin() end
          question(Strings("Let AUTO players join?"), function(auto)
            M.close()
            finish(1, { mode = "pin", pin = pin, auto = auto and true or false })
          end)
        end)
      end,
    })
  end
  menu = function(cursor)
    D.showModes({
      cursor = cursor,
      onChoose = function(key)
        if key == "auto" or key == "choose" then return finish(0, { mode = key }) end
        if key == "pin" then return setPin() end
        finish(2)
      end,
      onCancel = function() finish(127) end,
    })
  end
  D.show({
    onUpdate = function()
      if ask and M.isWaiting() and not Choice.isOpen() then
        local cb = ask
        ask = nil
        -- pokefirered/src/scrcmd.c:1411
        Choice.yesNo(function(yes) cb(yes) end, { left = 20, top = 8 })
      end
    end,
  })
  menu(1)
  return true
end

-- pokeemerald/src/union_room.c:1266 IsTryingToTradeAcrossVersionTooSoon
function Union.tradeReadyWith(partner)
  if type(partner) ~= "table" or not Family.isGame3(partner.version) then return Family.UR_TRADE.READY end
  local s = link().session() or {}
  return Family.tradeAcrossVersionTooSoon(Family.of(), {
    trading = true,
    partnerVersion = Family.cartVersion(partner.version),
    specialSaveWarpFlags = s.specialSaveWarpFlags,
    partnerCanLinkNationally = partner.canLinkNationally == true,
  })
end

function Union.roomPartnerAvatar(room)
  local me = myId()
  for _, p in ipairs(type(room) == "table" and type(room.players) == "table" and room.players or {}) do
    if type(p) == "table" and p.id ~= me and type(p.avatar) == "table" then return p.avatar end
  end
  return nil
end

Union.GROUP_JOIN_TICKS = 600

function Union.directRows(wire)
  local out = {}
  for _, e in ipairs(link().clientCall("directEntries", wire) or {}) do
    if type(e) == "table" then
      local av = type(e.avatar) == "table" and e.avatar or {}
      if e.kind == "room" and e.room ~= nil then
        out[#out + 1] = { key = "r:" .. tostring(e.room), kind = "room", room = e.room, id = e.host,
          name = av.name or e.name, trainerId = av.trainerId, gender = av.gender, locked = e.locked == true,
          version = av.version, canLinkNationally = av.canLinkNationally == true }
      elseif e.kind == "player" and e.id ~= nil and wire ~= "battle_multi" then
        out[#out + 1] = { key = "p:" .. tostring(e.id), kind = "player", id = e.id,
          name = av.name or e.name, trainerId = av.trainerId, gender = av.gender, version = av.version,
          canLinkNationally = av.canLinkNationally == true }
      elseif e.kind == "group" and e.leader ~= nil
          and (tonumber(e.joined) or 0) < (tonumber(e.max) or 2) then
        out[#out + 1] = { key = "g:" .. tostring(e.leader), kind = "group", id = e.leader, leader = e.leader,
          name = av.name or e.name, trainerId = av.trainerId, gender = av.gender,
          version = av.version or e.version, canLinkNationally = av.canLinkNationally == true }
      end
    end
  end
  return out
end

-- pokefirered/src/union_room.c:1146
function Union.chooseDirect(ctx, adapters, group, _direct)
  local L = link()
  local D = directUi()
  local M = message()
  local Strings = require("src.core.Strings")
  local wire = Union.wireFor(Union.GROUP_ACTIVITY[group].activity)
  local ruleset = Union.rulesetFor(wire)
  local profile = L.liveProfile(ruleset)
  local _, _, linkType = Union.directDest(group)
  local st = { phase = "list", done = false }
  Union._choose = st
  natives().yieldHost(ctx, adapters, function() end)
  L.clientCall("directList", wire, profile, L.avatar())
  L.setStatus("idle")
  -- pokefirered/src/union_room.c:1169
  local prompt = RomText.ascii(RomText.key("gTexts_UR_ChooseTrainer", group))
  local function showPrompt()
    if M then M.show(prompt, { stay = true }) end
  end
  local function finish(code)
    L.clientCall("directList", nil)
    if D then D.close() end
    if M and M.isOpen() then M.close() end
    if code then linkupResult(ctx, code) end
    st.done = true
    if Union._choose == st then Union._choose = nil end
    return true
  end
  local notice
  local function success()
    local ready = wire == "trade" and Union.tradeReadyWith(Union.roomPartnerAvatar(L.clientCall("room")))
      or Family.UR_TRADE.READY
    if ready ~= Family.UR_TRADE.READY then
      L.clientCall("leaveRoom")
      return notice(RomText.ascii(RomText.key("gTexts_UR_CantTransmitToTrainer", ready - 1)))
    end
    finish(nil)
    if not L.openRelay({ linkType = linkType }) then
      linkupResult(ctx, L.LINKUP.CONNECTION_ERROR)
      return true
    end
    L.setStatus("busy")
    linkupResult(ctx, L.LINKUP.SUCCESS)
    Union.armCableClub(ctx, group)
    return true
  end
  local function backToList()
    st.phase, st.handle, st.pending, st.row = "list", nil, nil, nil
    if D then
      D.setNotice(false)
      D.setFrozen(false)
    end
    showPrompt()
  end
  notice = function(text)
    st.phase = "notice"
    if D then D.setNotice(true) end
    if M then M.show(text, { done = function() if not st.done then backToList() end end }) end
  end
  local function joinRoom(row, pin)
    st.phase, st.row = "joining", row
    if D then D.setFrozen(true) end
    st.pending = L.clientCall("joinRoom", row.room, "player", profile, pin)
    if M then M.show(Union.askedToJoinText(wire, row.name), { stay = true }) end
  end
  local function askPin(row)
    if M and M.isOpen() then M.close() end
    st.phase, st.row = "pin", row
    if D then D.setFrozen(true) end
    local P = pinEntry()
    P.show({
      mode = "enter",
      onDone = function(pin)
        if st.done then return end
        if not pin then return backToList() end
        joinRoom(row, pin)
      end,
    })
  end
  local function pick(row)
    if st.phase ~= "list" or type(row) ~= "table" then return end
    -- pokefirered/src/union_room.c:1222
    playSe("SE_POKENAV_ON")
    if wire == "trade" then
      -- pokeemerald/src/union_room.c:1051
      local ready = Union.tradeReadyWith(row)
      if ready ~= Family.UR_TRADE.READY then
        return notice(RomText.ascii(RomText.key("gTexts_UR_CantTransmitToTrainer", ready - 1)))
      end
    end
    if row.kind == "player" then
      st.phase, st.row = "inviting", row
      if D then D.setFrozen(true) end
      st.handle = L.clientCall("invite", row.id, wire, { ruleset = ruleset }, profile)
      if M then M.show(Union.askedToJoinText(wire, row.name), { stay = true }) end
    elseif row.kind == "group" then
      st.phase, st.row, st.sawGroup, st.waited = "grouping", row, false, 0
      if D then D.setFrozen(true) end
      L.clientCall("joinGroup", row.leader, profile, L.avatar())
      if M then M.show(Union.askedToJoinText(wire, row.name), { stay = true }) end
    elseif row.locked then
      askPin(row)
    else
      joinRoom(row, nil)
    end
  end
  local busy = RomText.ascii("gText_UR_TrainerAppearsBusy")
  local function leave()
    if st.done or st.phase ~= "seated" then return end
    L.clientCall("leaveRoom")
    L.setStatus("busy")
    finish(L.LINKUP.FAILED)
  end
  local function poll()
    if st.done then return true end
    if Union.matchStarted(L.clientCall("room")) then return success() end
    if not L.online() then return finish(L.LINKUP.CONNECTION_ERROR) end
    if st.phase == "inviting" then
      local h = st.handle
      if type(h) ~= "table" then
        notice(busy)
      elseif h.state == "closed" and h.why ~= "accepted" and h.why ~= "crossed" then
        local row = st.row or {}
        notice(h.why == "declined" and Union.rejectText(Union.GROUP_ACTIVITY[group].activity, row.gender) or busy)
      end
    elseif st.phase == "grouping" then
      local g = L.clientCall("group")
      st.waited = st.waited + 1
      if type(g) == "table" and g.leader == st.row.leader then
        st.sawGroup = true
      elseif st.sawGroup or st.waited > Union.GROUP_JOIN_TICKS then
        L.clientCall("leaveGroup")
        notice(st.sawGroup and Union.rejectText(Union.GROUP_ACTIVITY[group].activity, st.row.gender) or busy)
      end
    elseif st.phase == "joining" then
      local p = st.pending
      if type(p) ~= "table" then
        notice(busy)
      elseif p.done and p.reason ~= nil then
        if p.reason == "bad_pin" then
          notice(Strings("The PIN didn't match."))
        elseif p.reason == "pin_required" then
          askPin(st.row)
        elseif p.reason == "pin_locked" then
          notice(Strings("Too many tries. Please try again later."))
        else
          notice(busy)
        end
      elseif p.done then
        st.phase = "seated"
        if D then
          D.setLeave(leave)
          D.setCount(roomCount())
        end
      elseif D then
        D.setCount(roomCount())
      end
    elseif st.phase == "seated" then
      local room = L.clientCall("room")
      if type(room) == "table" then
        st.sawRoom = true
        if D then D.setCount(roomCount()) end
      elseif st.sawRoom then
        st.sawRoom = nil
        -- pokefirered/src/union_room.c:1471
        notice(RomText.ascii(RomText.key("gTexts_UR_PlayerDisconnected", 2)))
      end
    end
    return false
  end
  if D then
    D.show({ onUpdate = poll })
    D.showChoose({
      me = L.avatar(),
      rows = function() return Union.directRows(wire) end,
      onPick = pick,
      onCancel = function()
        L.setStatus("busy")
        finish(L.LINKUP.FAILED)
      end,
    })
  end
  showPrompt()
  ctx.nativePoll = poll
  return true
end

-- pokefirered/src/union_room.c:1126
function Union.directFlow(ctx, adapters, group, role)
  local L = link()
  local wire = Union.wireFor(Union.GROUP_ACTIVITY[group].activity)
  local d = Union.direct or {}
  Union.direct = {}
  local mode = d.mode or (role == "leader" and "host" or "auto")
  if mode == "choose" and type(Union.chooseDirect) == "function" then
    return Union.chooseDirect(ctx, adapters, group, d)
  end
  local ruleset = Union.rulesetFor(wire)
  local opts = {
    activity = wire,
    ruleset = ruleset,
    profile = L.liveProfile(ruleset),
    avatar = L.avatar(),
    preview = Union.partyPreview(),
  }
  if mode == "pin" then
    opts.pin = d.pin
    opts.auto = d.auto and true or false
  elseif mode == "host" then
    opts.auto = false
  else
    opts.auto = true
  end
  L.clientCall("queueDirect", opts)
  L.setStatus("idle")
  local _, _, linkType = Union.directDest(group)
  return Union.waitForMatch(ctx, adapters, {
    cancel = function()
      L.clientCall("leaveDirect")
      if type(L.clientCall("group")) == "table" then L.clientCall("leaveGroup") end
    end,
    refuse = function(room)
      if wire ~= "trade" then return nil end
      local ready = Union.tradeReadyWith(Union.roomPartnerAvatar(room))
      if ready == Family.UR_TRADE.READY then return nil end
      L.clientCall("leaveRoom")
      return RomText.ascii(RomText.key("gTexts_UR_CantTransmitToTrainer", ready - 1))
    end,
    onMatch = function()
      if not L.openRelay({ linkType = linkType }) then
        linkupResult(ctx, L.LINKUP.CONNECTION_ERROR)
        return
      end
      L.setStatus("busy")
      linkupResult(ctx, L.LINKUP.SUCCESS)
      Union.armCableClub(ctx, group)
    end,
  })
end

local function minigames()
  local ok, MG = pcall(require, "src.core.game3.minigames.common")
  if ok and type(MG) == "table" and type(MG.arm) == "function" then return MG end
  return nil
end

function Union.minigameSpec(group, MG)
  local L = link()
  local rs = L.clientCall("roomSession")
  local room = L.clientCall("room") or {}
  local avatars = {}
  for _, m in ipairs(Union._groupMembers or {}) do
    if type(m) == "table" and m.id ~= nil then avatars[m.id] = m.avatar or {} end
  end
  local players = {}
  for _, p in ipairs(type(room.players) == "table" and room.players or {}) do
    local av = avatars[p.id] or {}
    players[#players + 1] = {
      id = p.id, name = av.name or p.name, seat = tonumber(p.seat),
      trainerId = tonumber(av.trainerId) or 0, gender = tonumber(av.gender) or 0,
    }
  end
  table.sort(players, function(a, b) return (a.seat or 99) < (b.seat or 99) end)
  local function rsCall(name)
    if rs and type(rs[name]) == "function" then return rs[name](rs) end
    return nil
  end
  return {
    game = MG.GROUP_GAME and MG.GROUP_GAME[group],
    session = rs,
    seat = rsCall("seat"),
    seats = rsCall("seats") or #players,
    players = players,
    seed = rsCall("seed") or tonumber(room.seed),
    partySlot = MG.partySlot,
    onExit = function() L.setStatus("busy") end,
  }
end

-- pokefirered/src/union_room.c:1957
function Union.finishMinigameLinkup(ctx, group)
  local L = link()
  local MG = minigames()
  if not MG then
    L.clientCall("leaveRoom")
    return linkupResult(ctx, L.LINKUP.CONNECTION_ERROR)
  end
  local spec = Union.minigameSpec(group, MG)
  L.setStatus("busy")
  linkupResult(ctx, L.LINKUP.SUCCESS)
  natives().awaitState(ctx, function()
    MG.arm(ctx, spec)
    return true
  end)
  return L.LINKUP.SUCCESS
end

Union.LINK_GROUP_PROVIDERS = {
  "src.core.game3.scripting.natives_contest",
  "src.core.game3.scripting.natives_tower_rse",
}
-- pokeemerald/src/cable_club.c:482
Union.LINK_READY_TICKS = 600

function Union.linkGroupSpec(wire)
  local RseGroups = require("src.core.game3.link.rse_groups")
  local spec = RseGroups.get(wire)
  if spec then return spec end
  for _, name in ipairs(Union.LINK_GROUP_PROVIDERS) do
    if not package.loaded[name] then pcall(require, name) end
  end
  return RseGroups.get(wire)
end

function Union.linkTypeOf(spec)
  local v = type(spec) == "table" and spec.linkType or nil
  if type(v) == "string" then return require("src.link.Game3Link").LINKTYPE[v] end
  return tonumber(v)
end

-- pokeemerald/src/union_room.c:1600 WarpForCableClubActivity
function Union.armLinkRoom(ctx, dest, service)
  local started, finished = false, false
  natives().awaitState(ctx, function()
    if not started then
      started = true
      Union.warpForCableClubActivity(dest, service, {
        cableClubWarp = true,
        onDone = function() finished = true end,
      })
    end
    return finished
  end)
end

-- pokeemerald/src/union_room.c:1750 Task_RunScriptAndFadeToActivity
function Union.finishLinkGroup(ctx, adapters, group, wire, role, spec)
  local L = link()
  local linkType = Union.linkTypeOf(spec)
  if not (linkType and L.openRelay({ linkType = linkType })) then
    L.clientCall("leaveRoom")
    linkupResult(ctx, L.LINKUP.CONNECTION_ERROR)
    return true
  end
  L.setStatus("busy")
  local ticks = 0
  ctx.nativePoll = function()
    ticks = ticks + 1
    local lk = L.link
    if not (lk and lk:isOpen()) then
      linkupResult(ctx, L.LINKUP.CONNECTION_ERROR)
      return true
    end
    if not lk:isReady() then
      if ticks <= Union.LINK_READY_TICKS then return false end
      L.closeLink("linkup_timeout")
      linkupResult(ctx, L.LINKUP.CONNECTION_ERROR)
      return true
    end
    lk.linkType = linkType
    linkupResult(ctx, L.LINKUP.SUCCESS)
    if type(spec.dest) == "table" then
      Union.armLinkRoom(ctx, spec.dest, tonumber(spec.service) or L.USING[spec.service or ""])
    end
    if type(spec.onLinked) == "function" then
      local players = type(lk.players) == "function" and lk:players() or {}
      local ok, err = pcall(spec.onLinked, ctx, adapters, lk, {
        group = group, wire = wire, role = role, players = players, seat = tonumber(lk.seat),
      })
      if not ok and adapters and adapters.log then adapters.log("[game3/link] " .. wire .. " onLinked: " .. tostring(err)) end
    end
    return true
  end
  return false
end

function Union.finishGroupLinkup(ctx, adapters, group, wire, role)
  local spec = Union.linkGroupSpec(wire)
  if spec then return Union.finishLinkGroup(ctx, adapters, group, wire, role, spec) end
  Union.finishMinigameLinkup(ctx, group)
  return true
end

function Union.lobbyScreen()
  local ok, Lobby = pcall(require, "src.ui.game3.minigames.common_lobby")
  if ok and type(Lobby) == "table" and Lobby.showPlayers then return Lobby end
  return screen()
end

function Union.clock()
  if type(love) == "table" and love.timer and love.timer.getTime then return love.timer.getTime() end
  return os.clock()
end

-- pokefirered/src/union_room.c:382
function Union.groupLead(ctx, adapters, group, wire)
  local L = link()
  local s = Union.lobbyScreen()
  local M = message()
  local Choice = choice()
  local spec = Union.GROUP_ACTIVITY[group]
  local profile = L.liveProfile(Union.rulesetFor(wire))
  L.clientCall("openGroup", wire, profile, L.avatar())
  L.setStatus("idle")
  local phase, asked, askId, waited = "list", {}, nil, 0
  local done = false
  local poll
  local function rows()
    local g = L.clientCall("group")
    local out = {}
    if type(g) == "table" then
      Union._groupMembers = g.members
      for _, m in ipairs(type(g.members) == "table" and g.members or {}) do
        if tonumber(m.seat) ~= 0 then
          local av = type(m.avatar) == "table" and m.avatar or {}
          out[#out + 1] = { slot = #out + 1, id = m.id, name = av.name or m.name, activity = spec.activity,
            trainerId = tonumber(av.trainerId) or 0 }
        end
      end
      -- pokefirered/src/union_room.c:995
      for _, m in ipairs(type(g.pending) == "table" and g.pending or {}) do
        local av = type(m.avatar) == "table" and m.avatar or {}
        out[#out + 1] = { slot = #out + 1, id = m.id, name = av.name or m.name, activity = spec.activity,
          trainerId = tonumber(av.trainerId) or 0, pending = true }
      end
    end
    return out
  end
  local function finish(code)
    if s and s.isOpen() then s.close() end
    linkupResult(ctx, code)
    done = true
    return true
  end
  local function openList()
    phase = "list"
    s.showPlayers(rows(), {
      mode = "leader",
      capacity = { min = math.max(1, spec.min - 1), max = spec.max - 1 },
      group = { min = spec.min, max = spec.max },
      activity = spec.activity,
      onPoll = rows,
      onTick = function() poll() end,
      onConfirm = function()
        L.clientCall("startGroup")
        phase = "starting"
        waited = 0
      end,
      onCancel = function()
        L.clientCall("leaveGroup")
        L.setStatus("busy")
        finish(L.LINKUP.FAILED)
      end,
    })
  end
  natives().yieldHost(ctx, adapters, function() end)
  poll = function()
    if done then return true end
    if Union.matchStarted(L.clientCall("room")) then
      if s.isOpen() then s.close() end
      done = true
      return Union.finishGroupLinkup(ctx, adapters, group, wire, "leader")
    end
    if not L.online() then return finish(L.LINKUP.CONNECTION_ERROR) end
    if phase == "list" and (tonumber(spec.min) or 0) == 0 and M then
      local g = L.clientCall("group")
      local members = type(g) == "table" and type(g.members) == "table" and g.members or {}
      if #members >= (tonumber(spec.max) or 2) then
        -- pokefirered/src/union_room.c:602
        local last = members[#members]
        local av = type(last) == "table" and type(last.avatar) == "table" and last.avatar or {}
        if s.isOpen() then s.close() end
        M.show(RomText.ascii("gText_UR_AnOKWasSentToPlayer", { stringVars = { av.name or (last and last.name) or "" } }),
          { stay = true })
        phase, waited = "ok_sent", 0
        return false
      end
    end
    if phase == "ok_sent" then
      waited = waited + 1
      -- pokefirered/src/union_room.c:658
      if waited > 120 then
        if M.isOpen and M.isOpen() then M.close() end
        L.clientCall("startGroup")
        phase, waited = "starting", 0
      end
      return false
    end
    if phase == "list" then
      local g = L.clientCall("group")
      local pending = type(g) == "table" and type(g.pending) == "table" and g.pending[1] or nil
      if pending and pending.id ~= nil and not asked[pending.id] and M and Choice then
        asked[pending.id] = true
        askId = pending.id
        if s.isOpen() then s.close() end
        phase = "ask"
        local av = type(pending.avatar) == "table" and pending.avatar or {}
        -- pokefirered/src/union_room_message.c:88
        M.show(RomText.ascii("gText_UR_PlayerContactedYouAddToMembers",
          { stringVars = { "", av.name or pending.name or "" } }), { stay = true })
      end
    elseif phase == "ask" then
      if Union.lastPageWaiting() and not Choice.isOpen() then
        phase = "answer"
        -- pokefirered/src/new_menu_helpers.c:48
        Choice.yesNo(function(yes)
          M.close()
          L.clientCall("acceptGroup", askId, yes and true or false)
          openList()
        end, { left = 21, top = 9 })
      end
    elseif phase == "starting" then
      waited = waited + 1
      if waited > 300 then openList() end
    end
    return false
  end
  openList()
  ctx.nativePoll = poll
  return true
end

-- pokefirered/src/union_room.c:1146
function Union.groupJoin(ctx, adapters, group, wire)
  local L = link()
  local s = Union.lobbyScreen()
  local M = message()
  local spec = Union.GROUP_ACTIVITY[group]
  local profile = L.liveProfile(Union.rulesetFor(wire))
  L.clientCall("groupList", wire, profile)
  L.setStatus("idle")
  local phase, joinRows = "list", {}
  local seenAt, lostAt = nil, nil
  local done = false
  local poll
  local function rows()
    joinRows = {}
    for _, g in ipairs(L.clientCall("groups", wire) or {}) do
      if type(g) == "table" and g.leader ~= nil then
        local av = type(g.avatar) == "table" and g.avatar or {}
        joinRows[#joinRows + 1] = {
          slot = #joinRows + 1, leader = g.leader, name = av.name or g.name, activity = spec.activity,
          trainerId = tonumber(av.trainerId) or 0,
          started = (tonumber(g.joined) or 0) >= (tonumber(g.max) or spec.max),
        }
      end
    end
    return joinRows
  end
  local function finish(code)
    if s and s.isOpen() then s.close() end
    if M and M.isOpen and M.isOpen() then M.close() end
    L.clientCall("groupList", nil)
    if code then linkupResult(ctx, code) end
    done = true
    return true
  end
  local function openList()
    phase = "list"
    s.showPlayers(rows(), {
      mode = "group",
      capacity = spec,
      group = { min = spec.min, max = spec.max },
      activity = spec.activity,
      onPoll = rows,
      onTick = function() poll() end,
      onConfirm = function(slot)
        local row = joinRows[slot or 0]
        if not row then return openList() end
        L.clientCall("joinGroup", row.leader, profile, L.avatar())
        phase = "waiting"
        seenAt, lostAt = nil, nil
        if M and M.show then
          M.show(RomText.ascii("CableClub_Text_PleaseWaitBCancel"), { stay = true })
        end
      end,
      onCancel = function()
        L.setStatus("busy")
        finish(L.LINKUP.FAILED)
      end,
    })
  end
  natives().yieldHost(ctx, adapters, function() end)
  poll = function()
    if done then return true end
    if Union.matchStarted(L.clientCall("room")) then
      local g = L.clientCall("group")
      if type(g) == "table" then Union._groupMembers = g.members end
      finish(nil)
      return Union.finishGroupLinkup(ctx, adapters, group, wire, "group")
    end
    if not L.online() then return finish(L.LINKUP.CONNECTION_ERROR) end
    if phase == "waiting" then
      local g = L.clientCall("group")
      if type(g) == "table" then
        Union._groupMembers = g.members
        seenAt, lostAt = seenAt or Union.clock(), nil
      elseif seenAt and not lostAt then
        lostAt = Union.clock()
      end
      if L.inputPressed("b") or (lostAt and Union.clock() - lostAt > 2) then
        L.clientCall("leaveGroup")
        if M and M.close then M.close() end
        openList()
      end
    end
    return false
  end
  openList()
  ctx.nativePoll = poll
  return true
end

function Union.relayGroupFlow(ctx, adapters, group, role)
  local L = link()
  local spec = Union.GROUP_ACTIVITY[group]
  local wire = spec and Union.wireFor(spec.activity)
  if not wire then return false, linkupResult(ctx, L.LINKUP.FAILED) end
  if group <= Union.LINK_GROUP.TRADE then
    return Union.directFlow(ctx, adapters, group, role)
  end
  if not screen() then return false, linkupResult(ctx, L.LINKUP.FAILED) end
  if role == "leader" then return Union.groupLead(ctx, adapters, group, wire) end
  return Union.groupJoin(ctx, adapters, group, wire)
end

local RseGroups = require("src.core.game3.link.rse_groups")
-- pokeemerald/src/union_room.c:1705
RseGroups.register("record_corner", {
  linkType = "RECORD_MIX_BEFORE",
  dest = Union.RECORD_CORNER,
  service = "RECORD_CORNER",
})
-- pokeemerald/data/scripts/berry_blender.inc:694
RseGroups.register("berry_blender", {
  linkType = "BERRY_BLENDER_SETUP",
})

function Union.reset()
  Union.stop("reset")
  Union.state = "off"
  Union.players = {}
  Union.memberIds = {}
  Union.partnerId = nil
  Union.activity = nil
  Union.lastResult = nil
  Union._name = nil
  Union._pump = nil
  Union._trade = nil
  Union._requestName = nil
  Union.relay = false
  Union.invite = nil
  Union.incoming = nil
  Union.direct = {}
  Union._refresh = 0
  Union._answered = {}
  Union._await = nil
  Union._synced = false
  Union._groupMembers = nil
  Union._choose = nil
  Union._vobjs = {}
  Union._vobjDirty = false
  Union._vobjRebuild = false
  Union._avatarWaiting = false
  Union._plazaSynced = false
  Union._plazaInstance, Union._plazaRev = nil, nil
  Union._offlineSince, Union._offlineWiped = nil, nil
  Union._upgradeShown = nil
  Union.flow = nil
  Union._partner = nil
  Union._role = nil
  Union._joining = nil
  Union._chatSession = nil
  Union._savedReg = nil
  Union._lastIncoming = nil
  Union._held = nil
  Union._scriptResult = nil
  Union._leftRooms = nil
  Union._xg = nil
  Union._xgSession = nil
  Union._serverOutdated = nil
  Union._capsMemo = nil
  local Screen = package.loaded["src.ui.game3.union_room"]
  if Screen and Screen.reset then Screen.reset() end
  local LinkMenu = package.loaded["src.ui.game3.link_menu"]
  if LinkMenu and LinkMenu.Direct then LinkMenu.Direct.reset() end
  local PinEntry = package.loaded["src.ui.game3.pin_entry"]
  if PinEntry then PinEntry.reset() end
  chat().reset()
end

return Union
