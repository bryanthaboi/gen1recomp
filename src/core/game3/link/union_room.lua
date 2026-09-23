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
-- pokefirered/src/union_room_player_avatar.c:56
Union.COORDS = {
  { 4, 6 }, { 13, 8 }, { 10, 6 }, { 1, 8 }, { 13, 4 }, { 7, 4 }, { 1, 4 }, { 7, 8 },
}
-- pokefirered/src/union_room_player_avatar.c:33
Union.GFX_IDS = {
  [0] = { 41, 54, 39, 18, 19, 20, 25, 26 },
  [1] = { 42, 58, 40, 22, 23, 24, 28, 29 },
}

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

Union.state = "off"
Union.players = {}
Union.partnerId = nil
Union.activity = nil
Union.lastResult = nil
Union._name = nil
Union._pump = nil
Union._spawned = {}
Union._trade = nil

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
  local row = Union.GFX_IDS[tonumber(gender) == 1 and 1 or 0]
  return row[((tonumber(trainerId) or 0) % 8) + 1]
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
    Union.startPump()
    return false
  end
  Union.players = {}
  Union._spawned = {}
  Union.partnerId = nil
  Union.activity = nil
  Union.lastResult = nil
  Union._name = nil
  Union.state = "init"
  link().setResult(ctx, 0)
  Union.startPump()
  return false
end

function Union.stop(reason)
  if Union.state == "off" then return false end
  local lk = link().link
  if lk and lk.isOpen and lk:isOpen() then
    lk:send({ type = Union.MSG.BYE, reason = tostring(reason or "left") })
  end
  local s = screen()
  if s and s.isOpen and s.isOpen() then s.close() end
  Union.despawnAll()
  Union.players = {}
  Union.partnerId = nil
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
  if item.activity == Union.ACTIVITY.NONE then
    Union.activity = nil
    Union.partnerId = nil
    Union.state = "main"
    return true
  end
  local activity = item.union and (item.activity + Union.IN_UNION_ROOM) or item.activity
  if activity == (Union.ACTIVITY.BATTLE_SINGLE + Union.IN_UNION_ROOM)
      and not Union.hasTwoMonsUnderLevelCap() then
    Union.activity = nil
    Union.state = "do_something_prompt"
    Union.lastResult = "need_two_mons"
    local M = message()
    if M and M.show then
      M.show(RomText.ascii("gText_UR_NeedTwoMonsOfLevel30OrLower1"))
    end
    return false
  end
  Union.activity = activity
  Union.state = sendRequest(activity) and "send_activity_request" or "print_and_exit"
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

function Union.warpForCableClubActivity(dest, linkService)
  local L = link()
  local ctx, adapters = L.vmCtx()
  L.setVar(ctx, L.VAR_0x8004, linkService)
  L.setVar(ctx, L.VAR_CABLE_CLUB_STATE, linkService)
  -- pokefirered/src/union_room.c:1901 HealPlayerParty / SavePlayerParty / LoadPlayerBag
  L.callSpecial(ctx, adapters, 0x00)
  L.callSpecial(ctx, adapters, 0x27)
  L.loadPlayerBag()
  local s = L.session()
  if s then
    -- pokefirered/src/overworld.c:605 SetDynamicWarpWithCoords
    local px, py = L.playerCell()
    s.dynamicWarp = { map = L.currentMap(), warpId = -1, x = px, y = py }
  end
  return L.warpToDest(ctx, adapters, { map = dest.map, warpId = -1, x = dest.x, y = dest.y })
end

-- pokefirered/src/union_room.c:1892 UR_STATE_START_ACTIVITY
function Union.startActivity()
  local raw = math.floor(tonumber(Union.activity) or 0)
  local act = raw % Union.IN_UNION_ROOM
  local inRoom = raw >= Union.IN_UNION_ROOM
  local L = link()
  if act == Union.ACTIVITY.BATTLE_SINGLE and inRoom then
    -- pokefirered/src/union_room.c:1811 StartUnionRoomBattle
    if battle().startUnionRoomBattle() then
      Union.state = "in_activity"
      return true
    end
  elseif act == Union.ACTIVITY.BATTLE_SINGLE then
    Union.stop()
    Union.warpForCableClubActivity(Union.COLOSSEUM_2P, L.USING.SINGLE_BATTLE)
    return true
  elseif act == Union.ACTIVITY.BATTLE_DOUBLE then
    Union.stop()
    Union.warpForCableClubActivity(Union.COLOSSEUM_2P, L.USING.DOUBLE_BATTLE)
    return true
  elseif act == Union.ACTIVITY.BATTLE_MULTI then
    Union.stop()
    Union.warpForCableClubActivity(Union.COLOSSEUM_4P, L.USING.MULTI_BATTLE)
    return true
  elseif act == Union.ACTIVITY.TRADE and inRoom then
    -- pokefirered/src/union_room.c:1936 Task_StartUnionRoomTrade
    if linkTrade().startUnionRoomTrade(function() Union.state = "main" end) then
      Union.state = "in_activity"
      return true
    end
  elseif act == Union.ACTIVITY.TRADE then
    -- pokefirered/src/union_room.c:1928 WarpForCableClubActivity MAP_TRADE_CENTER
    Union.stop()
    Union.warpForCableClubActivity(Union.TRADE_CENTER, L.USING.TRADE_CENTER)
    return true
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

-- pokefirered/src/union_room_message.c:86 gText_UR_PlayerContactedYouForXAccept
function Union.requestPrompt()
  local Strings = require("src.core.Strings")
  local raw = math.floor(tonumber(Union.activity) or 0) % Union.IN_UNION_ROOM
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
  local text = Union.requestPrompt()
  M.show(text, function()
    Choice.yesNo(function(yes)
      M.close()
      Union.answerRequest(yes and true or false)
    end)
  end)
  return true
end

-- pokefirered/src/union_room.c:3148 UR_STATE_RECV_ACTIVITY_REQUEST
function Union.answerRequest(accept)
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

function Union.reset()
  Union.stop("reset")
  Union.state = "off"
  Union.players = {}
  Union._spawned = {}
  Union.partnerId = nil
  Union.activity = nil
  Union.lastResult = nil
  Union._name = nil
  Union._pump = nil
  Union._trade = nil
  Union._waited = nil
  Union._requestName = nil
  chat().reset()
end

return Union
