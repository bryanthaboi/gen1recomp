local RomText = require("src.core.game3.rom_text")

local Union = {}

-- pokefirered/include/constants/union_room.h:21
Union.ACTIVITY = {
  NONE = 0,
  BATTLE_SINGLE = 1,
  BATTLE_DOUBLE = 2,
  BATTLE_MULTI = 3,
  TRADE = 4,
  CHAT = 5,
  CARD = 8,
  POKEMON_JUMP = 9,
  BERRY_CRUSH = 10,
  BERRY_PICK = 11,
  SEARCH = 12,
  SPIN_TRADE = 13,
  ITEM_TRADE = 14,
  RECORD_CORNER = 15,
  BERRY_BLENDER = 16,
  ACCEPT = 17,
  DECLINE = 18,
  NPCTALK = 19,
  PLYRTALK = 20,
  WONDER_CARD = 21,
  WONDER_NEWS = 22,
}

-- pokefirered/include/constants/union_room.h:49
Union.IN_UNION_ROOM = 0x40
-- pokefirered/include/constants/union_room.h:8
Union.MAX_LEADERS = 8
-- pokefirered/include/constants/union_room.h:15
Union.MAX_LEVEL = 30

-- pokefirered/include/constants/union_room.h:51
Union.LINK_GROUP = {
  SINGLE_BATTLE = 0,
  DOUBLE_BATTLE = 1,
  MULTI_BATTLE = 2,
  TRADE = 3,
  POKEMON_JUMP = 4,
  BERRY_CRUSH = 5,
  BERRY_PICKING = 6,
  WONDER_CARD = 7,
  WONDER_NEWS = 8,
  UNION_ROOM_RESUME = 9,
  UNION_ROOM_INIT = 10,
}

-- pokefirered/src/data/union_room.h:43
Union.GROUP_ACTIVITY = {
  [0] = { activity = Union.ACTIVITY.BATTLE_SINGLE, min = 0, max = 2 },
  [1] = { activity = Union.ACTIVITY.BATTLE_DOUBLE, min = 0, max = 2 },
  [2] = { activity = Union.ACTIVITY.BATTLE_MULTI, min = 0, max = 4 },
  [3] = { activity = Union.ACTIVITY.TRADE, min = 0, max = 2 },
  [4] = { activity = Union.ACTIVITY.POKEMON_JUMP, min = 2, max = 5 },
  [5] = { activity = Union.ACTIVITY.BERRY_CRUSH, min = 2, max = 5 },
  [6] = { activity = Union.ACTIVITY.BERRY_PICK, min = 3, max = 5 },
  [7] = { activity = Union.ACTIVITY.SPIN_TRADE, min = 3, max = 5 },
  [8] = { activity = Union.ACTIVITY.ITEM_TRADE, min = 3, max = 5 },
}

-- pokefirered/src/data/union_room.h:175
Union.INVITE_ITEMS = {
  { key = "GREETINGS", activity = Union.ACTIVITY.CARD, union = false, min = 0, max = 2 },
  { key = "BATTLE", activity = Union.ACTIVITY.BATTLE_SINGLE, union = true, min = 0, max = 2 },
  { key = "CHAT", activity = Union.ACTIVITY.CHAT, union = true, min = 0, max = 2 },
  { key = "EXIT", activity = Union.ACTIVITY.NONE, union = true },
}

-- pokefirered/src/data/union_room.h:1 sLinkGroupActivityNameTexts
Union.ACTIVITY_NAMES = RomText.lazy({
  [1] = "sLinkGroupActivityNameTexts[1]",
  [2] = "sLinkGroupActivityNameTexts[2]",
  [3] = "sLinkGroupActivityNameTexts[3]",
  [4] = "sLinkGroupActivityNameTexts[4]",
  [5] = "sLinkGroupActivityNameTexts[5]",
  [8] = "sLinkGroupActivityNameTexts[8]",
  [12] = "sLinkGroupActivityNameTexts[12]",
})

-- pokefirered/src/union_room_player_avatar.c:97
Union.LOCAL_IDS = { 9, 8, 7, 2, 6, 5, 4, 3 }
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

-- pokefirered/include/constants/flags.h:115
Union.FLAG_HIDE_PLAYER_1 = 0x63
-- pokefirered/include/constants/vars.h:28
Union.VAR_OBJ_GFX_ID_0 = 0x4010
-- pokefirered/include/constants/union_room.h:82
Union.INTERACT_ATTENDANT = 9
Union.INTERACT_START_MENU = 10

Union.MAP = "FR_UNION_ROOM"
Union.RESPONSE_SECONDS = 3

Union.MSG = {
  HELLO = "game3_union_hello",
  BYE = "game3_union_bye",
  REQUEST = "game3_union_request",
  RESPONSE = "game3_union_response",
}

-- pokefirered/src/union_room_player_avatar.c:566
Union.REFRESH_FRAMES = 300
Union.AWAIT_ROOM_SECONDS = 20
Union.CARD_WAIT_SECONDS = 3

Union.WIRE_NAMES = {
  [Union.ACTIVITY.BATTLE_SINGLE] = "battle_single",
  [Union.ACTIVITY.BATTLE_DOUBLE] = "battle_double",
  [Union.ACTIVITY.BATTLE_MULTI] = "battle_multi",
  [Union.ACTIVITY.TRADE] = "trade",
  [Union.ACTIVITY.CHAT] = "chat",
  [Union.ACTIVITY.CARD] = "card",
  [Union.ACTIVITY.POKEMON_JUMP] = "minigame_jump",
  [Union.ACTIVITY.BERRY_CRUSH] = "minigame_crush",
  [Union.ACTIVITY.BERRY_PICK] = "minigame_pick",
}

Union.state = "off"
Union.players = {}
Union.partnerId = nil
Union.activity = nil
Union.lastResult = nil
Union._name = nil
Union._pump = nil
Union._spawned = {}
Union._trade = nil
Union.relay = false
Union.memberIds = {}
Union.invite = nil
Union.incoming = nil
Union.direct = {}
Union._refresh = 0
Union._refreshTimer = 0
Union._answered = {}
Union._await = nil
Union._objs = {}
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

local function flags()
  return require("src.core.game3.scripting.flags")
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

function Union.onUnionRoomMap()
  return link().currentMap() == Union.MAP
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

-- pokefirered/src/union_room_player_avatar.c:134
function Union.memberCoords(slot, member)
  local data = Union.avatarData()
  local c = data.leader_coords[slot]
  local o = data.group_offsets[(member or 0) + 1]
  return c[1] + o[1], c[2] + o[2]
end

-- pokefirered/src/union_room_player_avatar.c:448
function Union.memberFacing(member, activity)
  if (member or 0) ~= 0 then return Union.avatarData().member_facing[member + 1] end
  local raw = math.floor(tonumber(activity) or 0)
  if raw == Union.ACTIVITY.CHAT + Union.IN_UNION_ROOM then return Union.DIR.SOUTH end
  return Union.DIR.EAST
end

-- pokefirered/src/union_room_player_avatar.c:169 CreateUnionRoomPlayerObjectEvent
function Union.spawnLeader(slot, player)
  if not (slot and slot >= 1 and slot <= Union.MAX_LEADERS) then return false end
  local L = link()
  local store = L.store()
  local F = flags()
  local gfx = Union.graphicsIdFor(player and player.gender, player and player.trainerId)
  F.setVar(store, nil, Union.VAR_OBJ_GFX_ID_0 + (slot - 1), gfx)
  -- pokefirered/src/union_room_player_avatar.c:159 ShowUnionRoomPlayer
  F.setFlag(store, nil, Union.FLAG_HIDE_PLAYER_1 + (slot - 1), false)
  local Objects = objects()
  if Objects then
    if Objects.addObject then Objects.addObject(Union.LOCAL_IDS[slot]) end
    if Objects.refreshGraphics then Objects.refreshGraphics() end
  end
  Union._spawned[slot] = true
  return true
end

-- pokefirered/src/union_room_player_avatar.c:174 RemoveUnionRoomPlayerObjectEvent
function Union.despawnLeader(slot)
  if not (slot and slot >= 1 and slot <= Union.MAX_LEADERS) then return false end
  local L = link()
  local F = flags()
  -- pokefirered/src/union_room_player_avatar.c:154 HideUnionRoomPlayer
  F.setFlag(L.store(), nil, Union.FLAG_HIDE_PLAYER_1 + (slot - 1), true)
  local Objects = objects()
  if Objects and Objects.removeObject then Objects.removeObject(Union.LOCAL_IDS[slot]) end
  Union._spawned[slot] = nil
  return true
end

local function avatarLive(slot)
  local Objects = objects()
  local eo = Objects and Objects.find and Objects.find(Union.LOCAL_IDS[slot])
  return eo ~= nil and eo.visible == true
end

-- pokefirered/src/union_room_player_avatar.c:367 Task_AnimateUnionRoomPlayers
function Union.refreshAvatars()
  if not Union.onUnionRoomMap() then return 0 end
  local n = 0
  for slot = 1, Union.MAX_LEADERS do
    if Union.players[slot] and not avatarLive(slot) then
      Union.spawnLeader(slot, Union.players[slot])
      n = n + 1
    end
  end
  return n
end

function Union.despawnAll()
  for slot = 1, Union.MAX_LEADERS do
    if Union._spawned[slot] then Union.despawnLeader(slot) end
  end
  Union._objs = {}
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

local function leaderObj(slot)
  Union._objs = Union._objs or {}
  local o = Union._objs[slot]
  if not o then
    o = { state = 0, anim = 0, sched = nil, y2 = 0 }
    Union._objs[slot] = o
  end
  return o
end

Union.leaderObj = leaderObj

local function setRaise(slot, y2)
  local Objects = objects()
  local eo = Objects and Objects.find and Objects.find(Union.LOCAL_IDS[slot])
  if eo then eo.raiseY = y2 end
end

-- pokefirered/src/union_room_player_avatar.c:265
local function animateSpawn(slot, o)
  if o.anim == 0 then
    if not playerStandingStill() then return false end
    local x, y = Union.memberCoords(slot, 0)
    if playerOn(x, y) then return false end
    Union.spawnLeader(slot, o.player)
    o.y2 = -Union.FLY_HEIGHT
    setRaise(slot, o.y2)
    o.anim = 1
    return false
  end
  o.y2 = math.min(0, o.y2 + Union.FLY_STEP)
  setRaise(slot, o.y2)
  if o.y2 >= 0 then
    o.anim = 0
    return true
  end
  return false
end

-- pokefirered/src/union_room_player_avatar.c:236
local function animateDespawn(slot, o)
  if o.anim == 0 then
    o.y2 = 0
    o.anim = 1
    flags().setFlag(link().store(), nil, Union.FLAG_HIDE_PLAYER_1 + (slot - 1), true)
  end
  o.y2 = o.y2 - Union.FLY_STEP
  setRaise(slot, o.y2)
  if o.y2 <= -Union.FLY_HEIGHT then
    Union.despawnLeader(slot)
    o.anim = 0
    return true
  end
  return false
end

-- pokefirered/src/union_room_player_avatar.c:325
function Union.animatePlayer(slot)
  local o = leaderObj(slot)
  if o.state == 0 then
    if o.sched ~= "in" then
      o.sched = nil
      return
    end
    o.state, o.anim = 2, 0
  end
  if o.state == 2 then
    if o.sched == "out" then
      o.state, o.anim = 0, 0
      if Union._spawned[slot] then Union.despawnLeader(slot) end
    elseif animateSpawn(slot, o) then
      o.state = 1
    end
  elseif o.state == 1 then
    if o.sched == "out" then
      o.state, o.anim = 3, 0
      if animateDespawn(slot, o) then o.state = 0 end
    end
  elseif o.state == 3 then
    if animateDespawn(slot, o) then o.state = 0 end
  end
  o.sched = nil
end

-- pokefirered/src/union_room_player_avatar.c:300
function Union.scheduleLeaderIn(slot, player)
  local o = leaderObj(slot)
  o.sched = "in"
  o.player = player
end

-- pokefirered/src/union_room_player_avatar.c:313
function Union.scheduleLeaderOut(slot)
  leaderObj(slot).sched = "out"
end

local function vobjId(slot, member)
  return Union.VOBJ_BASE + (slot - 1) * Union.GROUP_SIZE + member
end

Union.vobjId = vobjId

function Union.vobj(slot, member)
  Union._vobjs = Union._vobjs or {}
  return Union._vobjs[vobjId(slot, member)]
end

function Union.vobjVisible(slot, member)
  local v = Union.vobj(slot, member)
  return v ~= nil and v.visible == true
end

-- pokefirered/src/union_room_player_avatar.c:463
function Union.spawnMember(slot, member, gfx, activity)
  Union._vobjs = Union._vobjs or {}
  local id = vobjId(slot, member)
  local v = Union._vobjs[id]
  if not v then
    v = { slot = slot, member = member, visible = false, y2 = 0 }
    Union._vobjs[id] = v
  end
  if not v.visible or v.anim == "out" then
    v.visible = true
    v.anim = "in"
    v.y2 = -Union.FLY_HEIGHT
  end
  v.gfx = gfx
  v.dir = Union.memberFacing(member, activity)
  v.x, v.y = Union.memberCoords(slot, member)
  Union._vobjDirty = true
end

-- pokefirered/src/union_room_player_avatar.c:478
function Union.despawnMember(slot, member)
  local v = Union.vobj(slot, member)
  if v and v.visible and v.anim ~= "out" then
    v.anim = "out"
    v.y2 = v.y2 or 0
    Union._vobjDirty = true
  end
end

-- pokefirered/src/event_object_movement.c:9354
function Union.animateVobjs()
  local dirty = Union._vobjDirty
  for _, v in pairs(Union._vobjs or {}) do
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
      end
      dirty = true
    end
  end
  if not dirty then return end
  Union._vobjDirty = false
  local okV, VirtualObjects = pcall(require, "src.core.game3.virtual_objects")
  if not okV then return end
  VirtualObjects.clear()
  local ids = {}
  for id, v in pairs(Union._vobjs or {}) do
    if v.visible then ids[#ids + 1] = id end
  end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local v = Union._vobjs[id]
    local rec = VirtualObjects.spawn(id, v.gfx, v.x, v.y, 3, v.dir)
    if rec then
      rec.y2 = v.y2
      rec.solid = v.anim ~= "out"
    end
  end
end

-- pokefirered/src/union_room_player_avatar.c:486
function Union.assembleGroup(slot, p)
  if not Union.vobjVisible(slot, 0) then
    local x, y = Union.memberCoords(slot, 0)
    if playerOn(x, y) then return end
    Union.spawnMember(slot, 0, Union.graphicsIdFor(p.gender, p.trainerId), p.activity)
  end
  for i = 1, Union.GROUP_SIZE - 1 do
    local partner = p.partners and p.partners[i]
    if not partner then
      Union.despawnMember(slot, i)
    else
      local x, y = Union.memberCoords(slot, i)
      if not playerOn(x, y) then
        Union.spawnMember(slot, i, Union.graphicsIdFor(partner.gender, partner.trainerId), p.activity)
      end
    end
  end
end

-- pokefirered/src/union_room_player_avatar.c:510
function Union.spawnGroup(slot, p)
  local raw = math.floor(tonumber(p.activity) or 0) % Union.IN_UNION_ROOM
  if raw == Union.ACTIVITY.NONE or raw == Union.ACTIVITY.PLYRTALK or raw == Union.ACTIVITY.SEARCH then
    Union.scheduleLeaderIn(slot, p)
    for i = 0, Union.GROUP_SIZE - 1 do Union.despawnMember(slot, i) end
  else
    Union.scheduleLeaderOut(slot)
    Union.assembleGroup(slot, p)
  end
end

-- pokefirered/src/union_room_player_avatar.c:544
function Union.despawnGroup(slot)
  Union.scheduleLeaderOut(slot)
  for i = 0, Union.GROUP_SIZE - 1 do Union.despawnMember(slot, i) end
end

-- pokefirered/src/union_room_player_avatar.c:552
function Union.updatePlayerSprites()
  Union._refreshTimer = 0
  for slot = 1, Union.MAX_LEADERS do
    local p = Union.players[slot]
    if p and p.gone then
      Union.despawnGroup(slot)
      Union.players[slot] = nil
      Union.memberIds[slot] = nil
      if Union.partnerId == slot then Union.partnerId = nil end
    elseif p then
      Union.spawnGroup(slot, p)
    end
  end
end

-- pokefirered/src/union_room_player_avatar.c:566
function Union.scheduleRefresh()
  Union._refreshTimer = Union.REFRESH_FRAMES
end

-- pokefirered/src/union_room_player_avatar.c:571
function Union.handleRefresh()
  Union._refreshTimer = (Union._refreshTimer or 0) + 1
  if Union._refreshTimer > Union.REFRESH_FRAMES then Union.updatePlayerSprites() end
end

function Union.animateAll()
  for slot = 1, Union.MAX_LEADERS do Union.animatePlayer(slot) end
  Union.animateVobjs()
end

-- pokefirered/src/union_room_player_avatar.c:577
function Union.tryInteractWithMember()
  if not playerStandingStill() then return nil end
  local P = playerMod()
  local d = P and ({ down = { 0, 1 }, up = { 0, -1 }, left = { -1, 0 }, right = { 1, 0 } })[P.facing or "down"]
  if not d then return nil end
  local fx, fy = (tonumber(P.cellX) or 0) + d[1], (tonumber(P.cellY) or 0) + d[2]
  for slot = 1, Union.MAX_LEADERS do
    local p = Union.players[slot]
    for member = 0, Union.GROUP_SIZE - 1 do
      local v = Union.vobj(slot, member)
      if v and v.visible and v.anim == nil and p and not p.gone and v.x == fx and v.y == fy then
        local opp = Union.avatarData().opposite_facing[(Union.FACE_DIR[P.facing] or 1) + 1]
        v.dir = opp
        Union._vobjDirty = true
        return slot, member
      end
    end
  end
  return nil
end

-- pokefirered/src/union_room_player_avatar.c:621
function Union.updateMemberFacing(slot, member)
  local v = slot and Union.vobj(slot, member or 0)
  local p = slot and Union.players[slot]
  if not (v and p) then return end
  v.dir = Union.memberFacing(member or 0, p.activity)
  Union._vobjDirty = true
end

function Union.playerAt(slot)
  return Union.players[slot]
end

function Union.playerCount()
  local n = 0
  for slot = 1, Union.MAX_LEADERS do
    if Union.players[slot] then n = n + 1 end
  end
  return n
end

function Union.list()
  local out = {}
  for slot = 1, Union.MAX_LEADERS do
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

local function addPlayer(hello)
  for slot = 1, Union.MAX_LEADERS do
    local p = Union.players[slot]
    if p and p.trainerId == hello.trainerId and p.name == hello.name then
      p.activity = hello.activity or p.activity
      return slot, false
    end
  end
  for slot = 1, Union.MAX_LEADERS do
    if not Union.players[slot] then
      Union.players[slot] = {
        name = hello.name,
        gender = tonumber(hello.gender) or 0,
        trainerId = tonumber(hello.trainerId) or 0,
        activity = tonumber(hello.activity) or Union.ACTIVITY.SEARCH,
      }
      return slot, true
    end
  end
  return nil, false
end

Union.addPlayer = addPlayer

function Union.removePlayer(slot)
  if not Union.players[slot] then return false end
  Union.players[slot] = nil
  Union.memberIds[slot] = nil
  Union.despawnLeader(slot)
  if Union.partnerId == slot then Union.partnerId = nil end
  return true
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
  if Union.state ~= "off" then return false end
  Union.players = {}
  Union._spawned = {}
  local lk = link().link
  if lk and lk.isOpen and lk:isOpen() then
    -- pokefirered/src/union_room.c:3536 Task_InitUnionRoom
    Union.state = "search"
    Union.startPump()
  end
  return false
end

-- pokefirered/src/union_room.c:2579 RunUnionRoom
function Union.run(ctx, adapters)
  link().setResult(ctx, 0)
  if Union.state ~= "off" and Union.state ~= "search" and Union.onUnionRoomMap() then
    if Union.relay then
      Union._objs = {}
      Union._spawned = {}
      Union._vobjDirty = true
      Union.scheduleRefresh()
    end
    Union.startPump()
    return false
  end
  Union.players = {}
  Union._spawned = {}
  Union._objs = {}
  Union._vobjs = {}
  Union.flow = nil
  Union._refreshTimer = 0
  Union.memberIds = {}
  Union.partnerId = nil
  Union.activity = nil
  Union.lastResult = nil
  Union._name = nil
  Union.invite = nil
  Union.incoming = nil
  Union._await = nil
  Union.state = "init"
  local L = link()
  Union.relay = L.adapterConnected()
  if Union.relay then
    L.clientCall("joinPlaza", "union", L.liveProfile(), L.avatar())
    L.setStatus("idle")
    Union._refresh = 0
    Union._synced = false
  end
  L.setResult(ctx, 0)
  Union.startPump()
  return false
end

function Union.stop(reason)
  if Union.state == "off" then return false end
  local L = link()
  if Union.relay then
    if Union.incoming then L.clientCall("replyInvite", Union.incoming.id, false) end
    L.clientCall("leavePlaza", "union")
    L.setStatus("busy")
    Union.relay = false
    Union.invite = nil
    Union.incoming = nil
    Union._await = nil
  else
    local lk = L.link
    if lk and lk.isOpen and lk:isOpen() then
      lk:send({ type = Union.MSG.BYE, reason = tostring(reason or "left") })
    end
  end
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

local function chooserOpen()
  local s = screen()
  return s and s.isOpen and s.isOpen() and s.mode == "activity"
end

-- pokefirered/src/union_room.c:4565 HasAtLeastTwoMonsOfLevel30OrLower
function Union.hasTwoMonsUnderLevelCap()
  local s = link().session()
  local party = (s and s.party) or {}
  local n = 0
  for i = 1, 6 do
    local mon = party[i]
    local species = mon and (tonumber(mon.species) or 0) or 0
    if species ~= 0 and not mon.isEgg and (tonumber(mon.level) or 0) <= Union.MAX_LEVEL then
      n = n + 1
    end
  end
  return n >= 2
end

local function sendRequest(activity)
  if Union.relay then return Union.sendInvite(activity) end
  local lk = link().link
  if lk and lk.isOpen and lk:isOpen() then
    lk:send({ type = Union.MSG.REQUEST, activity = activity, name = localPlayer().name })
    return true
  end
  return false
end

-- pokefirered/src/union_room.c:2896 UR_STATE_HANDLE_DO_SOMETHING_PROMPT_INPUT
function Union.chooseActivity(index)
  local item = Union.INVITE_ITEMS[tonumber(index) or 0]
  if not item then return false end
  local M = message()
  if item.activity == Union.ACTIVITY.NONE then
    Union.activity = nil
    if Union.relay and M and M.show then
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
  if activity == (Union.ACTIVITY.BATTLE_SINGLE + Union.IN_UNION_ROOM)
      and not Union.hasTwoMonsUnderLevelCap() then
    Union.activity = nil
    Union.lastResult = "need_two_mons"
    if Union.relay and M and M.show then
      return Union.runFlow({
        Union.sayStep(RomText.ascii("gText_UR_NeedTwoMonsOfLevel30OrLower1")),
        Union.doStep(function() Union.doSomethingPrompt(false) end),
      }, "do_something_prompt")
    end
    Union.state = "do_something_prompt"
    if M and M.show then
      M.show(RomText.ascii("gText_UR_NeedTwoMonsOfLevel30OrLower1"))
    end
    return false
  end
  Union.activity = activity
  Union._role = "child"
  local sent = sendRequest(activity)
  Union.state = sent and "send_activity_request" or "print_and_exit"
  if sent and Union.relay and M and M.show then
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

local DELTA = { down = { 0, 1 }, up = { 0, -1 }, left = { -1, 0 }, right = { 1, 0 } }

function Union.slotForLocalId(localId)
  for slot = 1, Union.MAX_LEADERS do
    if Union.LOCAL_IDS[slot] == localId then return slot end
  end
  return nil
end

-- pokefirered/src/union_room.c:2757 TryInteractWithUnionRoomMember
function Union.facingMemberSlot()
  local Player = package.loaded["src.core.game3.player"]
  local Objects = objects()
  if not (Player and Objects and Objects.at) then return nil end
  local d = DELTA[Player.facing or "down"]
  if not d then return nil end
  local eo = Objects.at((tonumber(Player.cellX) or 0) + d[1], (tonumber(Player.cellY) or 0) + d[2])
  if not eo then return nil end
  -- pokefirered/include/constants/event_objects.h:72
  if tonumber(eo.graphicsId) == 66 then return Union.INTERACT_ATTENDANT end
  local slot = Union.slotForLocalId(tonumber(eo.localId))
  if slot and Union._spawned[slot] then return slot end
  return nil
end

local function pressedA()
  local game = link().game()
  local input = game and game.input
  if not (input and input.wasPressed) then return false end
  return input:wasPressed("a") and true or false
end

-- pokefirered/src/union_room.c:2734 UR_STATE_MAIN
local function pollInteraction(ctx)
  local L = link()
  local result = L.getVar(ctx, L.VAR_RESULT)
  if result == 0 and pressedA() then
    local slot = Union.facingMemberSlot()
    if slot then
      local okA, Audio = pcall(require, "src.core.game3.audio")
      local okS, SE = pcall(require, "src.core.game3.se_ids")
      if okA and okS and Audio.playSe then pcall(Audio.playSe, SE.SE_SELECT) end
      result = slot
    end
  end
  if result == 0 then return false end
  L.setVar(ctx, L.VAR_RESULT, 0)
  if result == Union.INTERACT_ATTENDANT then
    Union.state = "interact_with_attendant"
    return true
  end
  if result == Union.INTERACT_START_MENU then return false end
  local slot = result
  if not Union.players[slot] then
    Union.state = "print_and_exit"
    return true
  end
  Union.partnerId = slot
  Union.state = "do_something_prompt"
  return true
end

-- pokefirered/src/union_room.c:2647 Task_RunUnionRoom
function Union.update(dt)
  if Union.state == "off" then return false end
  local L = link()
  local ctx = select(1, L.vmCtx())
  local lk = L.link

  if Union.state ~= "search" and not Union.onUnionRoomMap() then
    Union.stop("left_union_room")
    return false
  end

  if Union.relay then return Union.relayUpdate(dt, ctx) end
  if lk and lk.isOpen and lk:isOpen() then
    local hello = lk:take(Union.MSG.HELLO)
    while hello do
      local slot, isNew = addPlayer(hello)
      if slot and isNew then
        if Union.state ~= "search" then Union.spawnLeader(slot, Union.players[slot]) end
        Union.noteUnionRoomPlayer(Union.players[slot].name)
      end
      hello = lk:take(Union.MSG.HELLO)
    end
    if lk:take(Union.MSG.BYE) then
      for slot = Union.MAX_LEADERS, 1, -1 do
        if Union.players[slot] then Union.removePlayer(slot) end
      end
    end
    local request = lk:take(Union.MSG.REQUEST)
    if request and Union.state == "main" then
      Union.activity = tonumber(request.activity)
      Union._requestName = request.name
      Union.state = "player_contacted_you"
    end
    local response = lk:take(Union.MSG.RESPONSE)
    if response then
      Union._waited = nil
      Union.lastResult = response.accept and "accepted" or "declined"
      Union.state = response.accept and "start_activity" or "print_and_exit"
    end
  elseif Union.state ~= "init" and Union.state ~= "search" then
    for slot = Union.MAX_LEADERS, 1, -1 do
      if Union.players[slot] then Union.removePlayer(slot) end
    end
  end

  -- pokefirered/src/union_room.c:2795 HandleUnionRoomPlayerRefresh
  if Union.state ~= "search" then Union.refreshAvatars() end

  if Union.state == "search" then
    if not (lk and lk.isOpen and lk:isOpen()) then
      Union.state = "off"
      return false
    end
  elseif Union.state == "init" then
    -- pokefirered/src/union_room.c:2674 UR_STATE_INIT_LINK
    Union.announce()
    Union.state = "main"
  elseif Union.state == "main" then
    pollInteraction(ctx)
  elseif Union.state == "player_contacted_you" then
    Union.askActivityRequest()
  elseif Union.state == "handle_activity_request" then
    local M = message()
    local okC, Choice = pcall(require, "src.ui.game3.choice")
    Union.offerYesNo()
    local waiting = (M and M.isOpen and M.isOpen())
      or (okC and Choice and Choice.isOpen and Choice.isOpen())
    if not waiting then Union.answerRequest(false) end
  elseif Union.state == "do_something_prompt" then
    if not chooserOpen() then
      local s = screen()
      if s then
        s.showActivities(Union.INVITE_ITEMS, {
          partner = Union.players[Union.partnerId or 0],
          onChoose = function(index) Union.chooseActivity(index) end,
          onCancel = function() Union.cancelActivity() end,
        })
        Union.state = "handle_do_something_prompt_input"
      else
        Union.state = "main"
      end
    end
  elseif Union.state == "handle_do_something_prompt_input" then
    if not chooserOpen() then Union.state = "main" end
  elseif Union.state == "interact_with_attendant" then
    -- pokefirered/src/union_room.c:3373 UR_STATE_CHECK_TRADING_BOARD
    local s = screen()
    if s then
      s.showPlayers(Union.list(), {
        mode = "board",
        onPoll = function() return Union.list() end,
        -- pokefirered/src/union_room.c:3485 UR_STATE_TRADE_SELECT_MON
        onConfirm = function(slot)
          if not Union.chooseMonForTradingBoard(slot) then Union.state = "main" end
        end,
        onCancel = function() Union.state = "main" end,
      })
      Union.state = "check_trading_board"
    else
      Union.state = "main"
    end
  elseif Union.state == "check_trading_board" then
    local s = screen()
    if not (s and s.isOpen and s.isOpen()) then Union.state = "main" end
  elseif Union.state == "send_activity_request" and Union.relay then
    Union.pollInvite()
  elseif Union.state == "await_room" then
    Union.pollAwaitRoom(dt)
  elseif Union.state == "await_link" then
    Union.pollAwaitLink(dt)
  elseif Union.state == "send_activity_request" then
    -- pokefirered/src/union_room.c:2937 UR_STATE_TRAINER_APPEARS_BUSY
    Union._waited = (Union._waited or 0) + (tonumber(dt) or 0)
    if Union._waited >= Union.RESPONSE_SECONDS then
      Union._waited = nil
      Union.lastResult = "busy"
      local M = message()
      if M and M.show then
        M.show(RomText.ascii("gText_UR_TrainerAppearsBusy"))
      end
      Union.state = "print_and_exit"
    end
  elseif Union.state == "start_activity" then
    Union.startActivity()
  elseif Union.state == "in_activity" then
    local raw = math.floor(tonumber(Union.activity) or 0)
    if raw % Union.IN_UNION_ROOM == Union.ACTIVITY.CHAT then
      -- pokefirered/src/union_room.c:1949 EnterUnionRoomChat
      if not chat().isActive() then
        Union.activity = nil
        Union.partnerId = nil
        Union.state = "main"
      end
    elseif raw % Union.IN_UNION_ROOM == Union.ACTIVITY.CARD then
      -- pokefirered/src/union_room.c:1954 CB2_ShowCard
      local okC, TrainerCard = pcall(require, "src.ui.game3.trainer_card")
      local open = okC and TrainerCard and TrainerCard.isOpen and TrainerCard.isOpen()
      if not open then
        Union.activity = nil
        Union.partnerId = nil
        Union.state = "main"
      end
    elseif raw % Union.IN_UNION_ROOM == Union.ACTIVITY.TRADE then
      -- pokefirered/src/union_room.c:1713 Task_StartUnionRoomTrade
      local LT = linkTrade()
      if not LT.isActive() then
        Union.activity = nil
        Union.partnerId = nil
        Union.state = "main"
      end
    else
      local LB = battle()
      if LB.state == "setup" then
        LB.pumpUnionSetup()
      elseif LB.state ~= "battle" then
        Union.activity = nil
        Union.partnerId = nil
        Union.state = "main"
      end
    end
  elseif Union.state == "print_and_exit" then
    Union.activity = nil
    Union.partnerId = nil
    Union.state = "main"
  end

  return true
end

-- pokefirered/src/union_room.c:1832 WarpForCableClubActivity
Union.COLOSSEUM_2P = { map = "FR_BATTLE_COLOSSEUM_2P", x = 6, y = 8 }
Union.COLOSSEUM_4P = { map = "FR_BATTLE_COLOSSEUM_4P", x = 5, y = 8 }
Union.TRADE_CENTER = { map = "FR_TRADE_CENTER", x = 5, y = 8 }

function Union.warpForCableClubActivity(dest, linkService, opts)
  opts = opts or {}
  local L = link()
  local ctx, adapters = L.vmCtx()
  L.setVar(ctx, L.VAR_0x8004, linkService)
  L.setVar(ctx, L.VAR_CABLE_CLUB_STATE, linkService)
  if linkService ~= L.USING.TRADE_CENTER then
    -- pokefirered/src/union_room.c:1901
    L.callSpecial(ctx, adapters, 0x00)
    L.callSpecial(ctx, adapters, 0x27)
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
  local warpOpts = Union.relay and { onDone = function() end } or nil
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
    if Union.relay then Union.prepareBoardTrade() end
    if linkTrade().startUnionRoomTrade(function() Union.state = "main" end) then
      Union.state = "in_activity"
      return true
    end
  elseif act == Union.ACTIVITY.TRADE then
    -- pokefirered/src/union_room.c:1928 WarpForCableClubActivity MAP_TRADE_CENTER
    Union.stop()
    Union.warpForCableClubActivity(Union.TRADE_CENTER, L.USING.TRADE_CENTER, warpOpts)
    return true
  elseif act == Union.ACTIVITY.CHAT and Union.relay then
    -- pokefirered/src/union_room.c:1949
    local rs = Union._chatSession or L.clientCall("roomSession")
    if rs then return Union.enterChat(rs) end
  elseif act == Union.ACTIVITY.CHAT then
    -- pokefirered/src/union_room.c:1949 EnterUnionRoomChat
    if chat().start({ onDone = function()
      Union.activity = nil
      Union.partnerId = nil
      Union.state = "main"
    end }) then
      Union.state = "in_activity"
      return true
    end
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
  for slot = 1, Union.MAX_LEADERS do
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
      if not item or item.id == 8 then return Union.toMain() end
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
  if Union.relay then
    local inv = Union.incoming
    Union.incoming = nil
    local raw = math.floor(tonumber(Union.activity) or 0) % Union.IN_UNION_ROOM
    local M = message()
    local shown = inv and M and M.show and type(love) == "table" and love.graphics
    -- pokefirered/src/union_room.c:3178
    if accept and raw == Union.ACTIVITY.BATTLE_SINGLE and Union.activity >= Union.IN_UNION_ROOM
        and not Union.hasTwoMonsUnderLevelCap() then
      if inv then link().clientCall("replyInvite", inv.id, false) end
      Union.lastResult = "need_two_mons"
      Union.activity = nil
      if shown then return Union.printAndExit(RomText.ascii("gText_UR_NeedTwoMonsOfLevel30OrLower2")) end
      Union.state = "main"
      return true
    end
    if inv then link().clientCall("replyInvite", inv.id, accept and true or false) end
    Union.lastResult = accept and "accepted" or "declined"
    if accept and inv then
      Union._role = "parent"
      Union.flow = nil
      Union.beginAwaitRoom(nil)
    else
      Union.activity = nil
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
  local lk = link().link
  if lk and lk.isOpen and lk:isOpen() then
    lk:send({ type = Union.MSG.RESPONSE, accept = accept and true or false })
  end
  Union.state = accept and "start_activity" or "main"
  Union.lastResult = accept and "accepted" or "declined"
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
  local spec = Union.GROUP_ACTIVITY[group] or Union.GROUP_ACTIVITY[0]
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
  for slot = 1, Union.MAX_LEADERS do
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
  local act = g and Union.GROUP_WIRE_ACTIVITY[g.activity] or nil
  if not act then act = Union.STATUS_ACTIVITY[m.status] end
  if not act then act = Union.ACTIVITY.NONE end
  return act + Union.IN_UNION_ROOM
end

local function avatarRow(m)
  local av = type(m.avatar) == "table" and m.avatar or {}
  return {
    id = m.id,
    name = av.name or m.name,
    gender = tonumber(av.gender) or 0,
    trainerId = tonumber(av.trainerId) or 0,
  }
end

local function partnerSig(list)
  local out = {}
  for i, p in ipairs(list or {}) do out[i] = tostring(p.id) end
  return table.concat(out, ",")
end

-- pokefirered/src/union_room.c:2781
function Union.syncPlaza()
  local plaza = link().clientCall("plaza")
  if type(plaza) ~= "table" then return false end
  local me = myId()
  local mySlot = tonumber(plaza.you)
  local members, present = {}, {}
  for _, m in ipairs(type(plaza.members) == "table" and plaza.members or {}) do
    if type(m) == "table" and m.id ~= nil and m.id ~= me
        and not (mySlot and tonumber(m.slot) == mySlot) then
      members[#members + 1] = m
      present[m.id] = m
    end
  end
  table.sort(members, function(a, b) return (tonumber(a.slot) or 99) < (tonumber(b.slot) or 99) end)
  local partnerOf = {}
  for _, m in ipairs(members) do
    local g = type(m.group) == "table" and m.group or nil
    if g and g.leader ~= nil and g.leader ~= m.id and present[g.leader] then partnerOf[m.id] = g.leader end
  end
  local leaders, partners = {}, {}
  for _, m in ipairs(members) do
    if not partnerOf[m.id] then
      leaders[m.id] = m
      local list = {}
      local g = type(m.group) == "table" and m.group or nil
      for _, id in ipairs(g and type(g.members) == "table" and g.members or {}) do
        if partnerOf[id] == m.id and present[id] and #list < Union.GROUP_SIZE - 1 then
          list[#list + 1] = avatarRow(present[id])
        end
      end
      partners[m.id] = list
    end
  end
  local changed, fresh = false, false
  for slot = 1, Union.MAX_LEADERS do
    local p = Union.players[slot]
    if p and not p.gone and not leaders[p.id] then p.gone = true end
  end
  for _, m in ipairs(members) do
    if leaders[m.id] then
      local slot = Union.slotForId(m.id)
      local p = slot and Union.players[slot] or nil
      local activity = Union.memberActivity(m)
      if p then
        if p.gone or p.activity ~= activity or partnerSig(p.partners) ~= partnerSig(partners[m.id]) then
          changed = true
        end
        p.gone = nil
        p.board = m.board
        p.recruiting = m.recruiting
        p.status = m.status
        p.group = m.group
        p.activity = activity
        p.partners = partners[m.id]
      elseif not slot then
        for s = 1, Union.MAX_LEADERS do
          if not Union.players[s] then
            slot = s
            break
          end
        end
        if slot then
          local row = avatarRow(m)
          row.activity = activity
          row.board = m.board
          row.recruiting = m.recruiting
          row.status = m.status
          row.group = m.group
          row.partners = partners[m.id]
          Union.memberIds[slot] = m.id
          Union.players[slot] = row
          Union.noteUnionRoomPlayer(row.name)
          fresh, changed = true, true
        end
      end
    end
  end
  -- pokefirered/src/union_room.c:2783
  if fresh and Union._synced then playSe("SE_NOTE_C") end
  if changed then Union.scheduleRefresh() end
  Union._synced = true
  return true
end

-- pokefirered/src/union_room.c:3106
function Union.pollIncoming()
  local L = link()
  if Union.state == "init" or Union.state == "search" then return end
  for _, inv in ipairs(L.clientCall("invites") or {}) do
    local id = type(inv) == "table" and inv.id or nil
    if id ~= nil and not Union._answered[id] then
      Union._answered[id] = true
      local activity = Union.activityForInvite(inv.activity, inv.detail)
      if Union.state == "main" and not Union.incoming and activity then
        local from = type(inv.from) == "table" and inv.from or {}
        Union.incoming = inv
        Union._lastIncoming = inv
        Union.activity = activity
        Union._requestName = from.name
        Union.partnerId = Union.slotForId(from.id)
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
  if not L.online() then
    for slot = Union.MAX_LEADERS, 1, -1 do
      local p = Union.players[slot]
      if p and not p.gone then p.gone = true end
    end
    Union.handleRefresh()
    Union.animateAll()
    return
  end
  Union.syncPlaza()
  Union.handleRefresh()
  Union.animateAll()
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
  Union.state = "main"
  Union.releaseScript()
end

-- pokefirered/src/union_room.c:3455
function Union.printAndExit(text, slot, member)
  return Union.runFlow(stepsOf(
    Union.sayStep(text),
    Union.doStep(function()
      Union.updateMemberFacing(slot, member)
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
-- pokefirered/src/union_room_message.c:205
Union.CONTACTED_TEXTS = { [0] = "sText_SomebodyHasContactedYou", [1] = "sText_PlayerHasContactedYou" }

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

-- pokefirered/src/union_room.c:2805
function Union.talkTo(slot, member)
  member = member or 0
  local p = Union.players[slot]
  if not p or p.gone then
    return Union.printAndExit(RomText.ascii("gText_UR_TrainerAppearsBusy"), slot, member)
  end
  Union.partnerId = slot
  Union._partner = p
  local raw = math.floor(tonumber(p.activity) or 0) % Union.IN_UNION_ROOM
  local idle = raw == Union.ACTIVITY.NONE or raw == Union.ACTIVITY.PLYRTALK or raw == Union.ACTIVITY.SEARCH
  if member == 0 and idle then return Union.doSomethingPrompt(false) end
  local who = member == 0 and p or (p.partners and p.partners[member]) or p
  local g = genderIndex(who)
  local ctx = textCtx({ stringVars = { who.name or "" } })
  if member == 0 and raw == Union.ACTIVITY.CHAT and #(p.partners or {}) < Union.GROUP_SIZE - 1 then
    local met = Union.metBefore(p) and 1 or 0
    return Union.runFlow(stepsOf(
      Union.stayStep(RomText.ascii(Union.JOIN_CHAT_TEXTS[met][g], ctx)),
      Union.yesNoStep(function(yes)
        if yes then return Union.joinChat(slot) end
        Union.printAndExit(RomText.ascii(RomText.key("gTexts_UR_DeclineChat", g), ctx), slot, member)
      end)
    ), "recv_join_chat_request")
  end
  return Union.printAndExit(Union.reactionText(p.activity, g, who.name), slot, member)
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
  Union.armScriptWait(ctx)
  local result = Union._scriptResult or L.getVar(ctx, L.VAR_RESULT)
  Union._scriptResult = nil
  if result ~= 0 then
    L.setVar(ctx, L.VAR_RESULT, 0)
    if result == Union.INTERACT_ATTENDANT then return Union.attendant() end
    if result >= 1 and result <= Union.MAX_LEADERS then return Union.talkTo(result, 0) end
    Union.releaseScript()
    return
  end
  if Union._held and not Union.flow then Union.releaseScript() end
  local Hud = package.loaded["src.ui.game3.hud"]
  if Hud and Hud.busy and Hud.busy() then return end
  if not pressedA() then return end
  local slot, member = Union.tryInteractWithMember()
  if slot then
    playSe("SE_SELECT")
    return Union.talkTo(slot, member)
  end
  if Union.facingTradingBoard() then return Union.checkTradingBoard() end
end

function Union.facingTradingBoard()
  local P = playerMod()
  if not P or P.moving then return false end
  local d = ({ down = { 0, 1 }, up = { 0, -1 }, left = { -1, 0 }, right = { 1, 0 } })[P.facing or "down"]
  if not d then return false end
  return (tonumber(P.cellX) or 0) + d[1] == Union.TRADING_BOARD.x
    and (tonumber(P.cellY) or 0) + d[2] == Union.TRADING_BOARD.y
end

-- pokefirered/src/union_room.c:3148
function Union.contactedYou()
  local inv = Union.incoming or {}
  local from = type(inv.from) == "table" and inv.from or {}
  local p = Union.partnerRow() or { name = from.name, trainerId = from.avatar and from.avatar.trainerId }
  local met = Union.metBefore(p) and 1 or 0
  local ctx = textCtx({ stringVars = { from.name or "" } })
  return Union.runFlow(stepsOf(
    Union.pauseStep(RomText.ascii(Union.CONTACTED_TEXTS[met], ctx), 60),
    Union.doStep(function()
      Union.state = "handle_activity_request"
      Union._asked = true
    end),
    Union.stayStep(Union.requestPrompt()),
    Union.yesNoStep(function(yes) Union.answerRequest(yes) end)
  ), "player_contacted_you")
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
  if st == "init" or st == "search" then
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
  if Union.relay and M and M.show then return Union.printAndExit(text) end
  if M and M.show then M.show(text) end
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
  if Union.relay and M and M.show and type(love) == "table" and love.graphics then
    if raw == Union.ACTIVITY.CARD then return Union.cardFlow() end
    return Union.printStartActivity()
  end
  Union.state = "start_activity"
end

-- pokefirered/src/union_room.c:4700
function Union.cardText(card, isParent)
  card = type(card) == "table" and card or {}
  local LB = battle()
  local who = { trainerId = tonumber(card.trainerId) or 0, gender = (card.gender == 1 or card.gender == "female") and 1 or 0 }
  local okC, classId = pcall(LB.unionRoomTrainerClass, who)
  local className = okC and classId and RomText.plain(RomText.key("gTrainerClassNames", classId)) or ""
  local stars = math.max(0, math.min(4, math.floor(tonumber(card.stars) or 0)))
  local minutes = math.max(0, math.min(59, math.floor(tonumber(card.playTimeMinutes) or 0)))
  local dyn1 = {
    [0] = className,
    [1] = tostring(card.name or ""),
    [2] = RomText.plain(RomText.key("gTexts_UR_CardColor", stars)),
    [3] = tostring(math.floor(tonumber(card.caughtMonsCount) or 0)),
    [4] = tostring(math.min(999, math.floor(tonumber(card.playTimeHours) or 0))),
    [5] = string.format("%02d", minutes),
  }
  local page1 = RomText.ascii("gText_UR_TrainerCardInfoPage1", textCtx({ dynamic = dyn1 }))
  local words = {}
  local okE, EasyChat = pcall(require, "src.core.game3.easy_chat_text")
  for i = 1, 4 do
    local id = type(card.easyChatProfile) == "table" and tonumber(card.easyChatProfile[i]) or nil
    local ok, w = false, nil
    if okE and id then ok, w = pcall(EasyChat.word, id) end
    words[i] = ok and w or ""
  end
  local dyn2 = {
    [0] = tostring(math.min(9999, math.floor(tonumber(card.linkBattleWins) or 0))),
    [1] = tostring(card.name or ""),
    [2] = tostring(math.min(9999, math.floor(tonumber(card.linkBattleLosses) or 0))),
    [3] = tostring(math.floor(tonumber(card.pokemonTrades) or 0)),
    [4] = words[1], [5] = words[2], [6] = words[3], [7] = words[4],
  }
  local page2 = RomText.ascii("gText_UR_TrainerCardInfoPage2", textCtx({ dynamic = dyn2 }))
  local tail
  if isParent then
    tail = RomText.ascii("gText_UR_FinishedCheckingPlayersTrainerCard", textCtx({ dynamic = dyn2 }))
  else
    tail = RomText.ascii(RomText.key("gTexts_UR_GladToMeetYou", who.gender), textCtx({ dynamic = dyn2 }))
  end
  return page1 .. page2 .. tail
end

-- pokefirered/src/union_room.c:2999
function Union.cardFlow()
  local L = link()
  local card = L.peerCard or {}
  local isParent = Union._role ~= "child"
  local Strings = require("src.core.Strings")
  local viewing = false
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
  return Union.runFlow({
    Union.sayStep(Union.cardText(card, isParent)),
    Union.stayStep(Strings("Would you like to see the TRAINER CARD?")),
    Union.yesNoStep(function(yes)
      if not yes then return finish() end
      local okC, TrainerCard = pcall(require, "src.ui.game3.trainer_card")
      if not (okC and TrainerCard.show) then return finish() end
      viewing = true
      TrainerCard.show({ session = card, onClose = function() viewing = false end })
      Union.runFlow({
        Union.waitStep(function() return not viewing end),
        Union.doStep(finish),
      }, "card_view")
    end),
  }, "card_info")
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
function Union.armCableClub(ctx, group)
  local dest, service = Union.directDest(group)
  local started, finished = false, false
  local function warpTask()
    if not started then
      started = true
      Union.warpForCableClubActivity(dest, service, {
        cableClubWarp = true,
        onDone = function() finished = true end,
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
  local function poll()
    if done then return true end
    if Union.matchStarted(L.clientCall("room")) then
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

function Union.directModes(ctx, _row, done)
  local L = link()
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

function Union.directRows(wire)
  local out = {}
  for _, e in ipairs(link().clientCall("directEntries", wire) or {}) do
    if type(e) == "table" then
      local av = type(e.avatar) == "table" and e.avatar or {}
      if e.kind == "room" and e.room ~= nil then
        out[#out + 1] = { key = "r:" .. tostring(e.room), kind = "room", room = e.room, id = e.host,
          name = av.name or e.name, trainerId = av.trainerId, gender = av.gender, locked = e.locked == true }
      elseif e.kind == "player" and e.id ~= nil and wire ~= "battle_multi" then
        out[#out + 1] = { key = "p:" .. tostring(e.id), kind = "player", id = e.id,
          name = av.name or e.name, trainerId = av.trainerId, gender = av.gender }
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
  L.clientCall("directList", wire, profile)
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
  local function success()
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
  local function notice(text)
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
    if row.kind == "player" then
      st.phase, st.row = "inviting", row
      if D then D.setFrozen(true) end
      st.handle = L.clientCall("invite", row.id, wire, { ruleset = ruleset }, profile)
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
    cancel = function() L.clientCall("leaveDirect") end,
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
      Union.finishMinigameLinkup(ctx, group)
      return true
    end
    if not L.online() then return finish(L.LINKUP.CONNECTION_ERROR) end
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
      Union.finishMinigameLinkup(ctx, group)
      return true
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

function Union.reset()
  Union.stop("reset")
  Union.state = "off"
  Union.players = {}
  Union._spawned = {}
  Union.memberIds = {}
  Union.partnerId = nil
  Union.activity = nil
  Union.lastResult = nil
  Union._name = nil
  Union._pump = nil
  Union._trade = nil
  Union._waited = nil
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
  Union._objs = {}
  Union._vobjs = {}
  Union._vobjDirty = false
  Union._refreshTimer = 0
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
  local Screen = package.loaded["src.ui.game3.union_room"]
  if Screen and Screen.reset then Screen.reset() end
  local LinkMenu = package.loaded["src.ui.game3.link_menu"]
  if LinkMenu and LinkMenu.Direct then LinkMenu.Direct.reset() end
  local PinEntry = package.loaded["src.ui.game3.pin_entry"]
  if PinEntry then PinEntry.reset() end
  chat().reset()
end

return Union
