local Stack = require("src.ui.game3.stack")
local Window = require("src.ui.game3.window")
local FrlgFont = require("src.ui.game3.frlg_font")
local Chrome = require("src.ui.game3.chrome")
local RomText = require("src.core.game3.rom_text")

local Lobby = {}

Lobby.ID = "minigame_lobby"
-- pokefirered/src/data/union_room.h:27
Lobby.CANCEL_TEMPLATE = Window.template(0, 0, 30, 2)
-- pokefirered/src/data/union_room.h:56
Lobby.MEMBERS_TEMPLATE = Window.template(1, 3, 13, 10)
-- pokefirered/src/data/union_room.h:66
Lobby.MODE_TEMPLATE = Window.template(16, 3, 7, 4)
-- pokefirered/src/data/union_room.h:105
Lobby.GROUPS_TEMPLATE = Window.template(1, 3, 17, 10)
-- pokefirered/src/data/union_room.h:115
Lobby.NAME_ID_TEMPLATE = Window.template(20, 3, 7, 4)
-- pokefirered/src/data/union_room.h:84
Lobby.MAX_SHOWED = 5
Lobby.ROW_H = 16
Lobby.POLL_FRAMES = 30
-- pokefirered/include/constants/songs.h:11
Lobby.SE_WALL_HIT = 7
-- pokefirered/include/constants/songs.h:9
Lobby.SE_SELECT = 5

-- pokefirered/include/constants/union_room.h:30
Lobby.ACTIVITY_GROUP = { [9] = 4, [10] = 5, [11] = 6 }
-- pokefirered/src/data/union_room.h:44
Lobby.GROUP_CAPACITY = {
  [4] = { activity = 9, min = 2, max = 5 },
  [5] = { activity = 10, min = 2, max = 5 },
  [6] = { activity = 11, min = 3, max = 5 },
}

-- pokefirered/src/union_room.c:4079
Lobby.COLOR_CANCEL = { fg = FrlgFont.STDPAL[1], shadow = FrlgFont.STDPAL[3], bg = FrlgFont.STDPAL[2] }

local function reset(self)
  self.open = false
  self.mode = nil
  self.players = {}
  self.cursor = 1
  self.top = 1
  self.capacity = nil
  self.group = nil
  self.activity = nil
  self.groupId = nil
  self.me = nil
  self._onConfirm = nil
  self._onCancel = nil
  self._onPoll = nil
  self._onTick = nil
  self._pollWait = 0
  self._frames = 0
end

reset(Lobby)

local function se(id)
  pcall(function() require("src.core.game3.audio").playSe(id) end)
end

local function unionActivity()
  local Union = package.loaded["src.core.game3.link.union_room"]
  return Union and tonumber(Union.activity) or nil
end

local function sessionMe()
  local rt = package.loaded["src.core.game3.runtime"]
  local s = rt and rt.getSession and rt.getSession()
  if not s then return { name = "", trainerId = 0 } end
  return { name = tostring(s.name or ""), trainerId = (tonumber(s.trainerId) or 0) % 0x10000 }
end

local function resolveGroup(mode, opts, players)
  local activity = tonumber(opts.activity)
  if not activity and type(opts.capacity) == "table" then activity = tonumber(opts.capacity.activity) end
  if not activity and type(players) == "table" and type(players[1]) == "table" then
    activity = tonumber(players[1].activity)
  end
  activity = activity or unionActivity()
  local groupId = tonumber(opts.groupId) or (activity and Lobby.ACTIVITY_GROUP[activity % 0x40])
  local group = opts.group
  if type(group) ~= "table" then
    local cap = opts.capacity
    if type(cap) == "table" and mode == "leader" then
      group = { min = (tonumber(cap.min) or 0) + 1, max = (tonumber(cap.max) or 0) + 1 }
    elseif type(cap) == "table" then
      group = { min = tonumber(cap.min) or 0, max = tonumber(cap.max) or 0 }
    else
      group = Lobby.GROUP_CAPACITY[groupId or -1] or { min = 2, max = 5 }
    end
  end
  return activity, groupId, { min = tonumber(group.min) or 0, max = tonumber(group.max) or 0 }
end

function Lobby.isOpen()
  return Lobby.open and true or false
end

-- pokefirered/src/union_room.c:412
function Lobby.showPlayers(players, opts)
  opts = opts or {}
  local mode = (opts.mode == "leader") and "leader" or "group"
  local keepCursor = Lobby.open and Lobby.mode == mode
  local cursor = Lobby.cursor
  reset(Lobby)
  Lobby.mode = mode
  Lobby.players = type(players) == "table" and players or {}
  Lobby.capacity = opts.capacity
  Lobby.activity, Lobby.groupId, Lobby.group = resolveGroup(mode, opts, Lobby.players)
  Lobby.me = opts.me or sessionMe()
  Lobby._onConfirm = opts.onConfirm
  Lobby._onCancel = opts.onCancel
  Lobby._onPoll = opts.onPoll
  Lobby._onTick = opts.onTick
  if keepCursor then Lobby.cursor = math.max(1, math.min(cursor, math.max(1, #Lobby.players))) end
  -- pokefirered/src/union_room.c:1168
  local Message = package.loaded["src.ui.game3.message"]
  if Message and Message.isOpen and Message.isOpen() then Message.reset() end
  Lobby.open = true
  Stack.push(Lobby.ID, Lobby, { hideBelow = false, drawUnder = true })
  return true
end

function Lobby.close()
  if not Lobby.open then return false end
  Lobby.open = false
  Stack.pop(Lobby.ID)
  return true
end

function Lobby.reset()
  reset(Lobby)
  Stack.pop(Lobby.ID)
  return true
end

-- pokefirered/src/union_room.c:443
function Lobby.playerCount()
  if Lobby.mode == "leader" then return 1 + #Lobby.players end
  return #Lobby.players
end

function Lobby.rowCount()
  return #Lobby.players
end

-- pokefirered/src/union_room.c:324
function Lobby.capacityIndex(min, max)
  min, max = tonumber(min) or 0, tonumber(max) or 0
  if min == 0 and max == 2 then return 0 end
  if min == 0 and max == 4 then return 1 end
  if min == 2 and max == 5 then return 2 end
  if min == 3 and max == 5 then return 3 end
  return nil
end

function Lobby.modeText(count, group)
  group = group or Lobby.group or {}
  local k = Lobby.capacityIndex(group.min, group.max)
  count = tonumber(count) or Lobby.playerCount()
  if not k or count < 1 then return "" end
  local key = RomText.key("gTexts_UR_PlayersNeededOrMode", k, count - 1)
  if not RomText.has(key) then return "" end
  return RomText.plain(key)
end

function Lobby.activityName(activity)
  activity = tonumber(activity or Lobby.activity)
  if not activity then return "" end
  local key = RomText.key("sLinkGroupActivityNameTexts", activity % 0x40)
  if not RomText.has(key) then return "" end
  return RomText.plain(key)
end

-- pokefirered/src/union_room.c:449
function Lobby.awaitingText(count, group)
  group = group or Lobby.group or {}
  count = tonumber(count) or Lobby.playerCount()
  local vars = { stringVars = { Lobby.activityName() } }
  local min, max = tonumber(group.min) or 0, tonumber(group.max) or 0
  if min ~= 0 and count > min - 1 and max ~= 0 then
    return RomText.plain("gText_UR_AwaitingLinkPressStart", vars)
  end
  return RomText.plain("gText_UR_AwaitingCommunication", vars)
end

-- pokefirered/src/union_room.c:1168
function Lobby.chooseText()
  local id = Lobby.groupId
  if not id then return "" end
  local key = RomText.key("gTexts_UR_ChooseTrainer", id)
  if not RomText.has(key) then return "" end
  return RomText.plain(key)
end

function Lobby.message()
  if Lobby.mode == "leader" then return Lobby.awaitingText() end
  return Lobby.chooseText()
end

function Lobby.canStart()
  if Lobby.mode ~= "leader" then return false end
  local min, max = Lobby.group.min, Lobby.group.max
  return min ~= 0 and max ~= 0 and Lobby.playerCount() > min - 1
end

function Lobby.move(delta)
  local n = Lobby.rowCount()
  if Lobby.mode ~= "group" or n < 1 then return false end
  local c = Lobby.cursor + delta
  if c < 1 or c > n then return false end
  Lobby.cursor = c
  if c < Lobby.top then Lobby.top = c end
  if c > Lobby.top + Lobby.MAX_SHOWED - 1 then Lobby.top = c - Lobby.MAX_SHOWED + 1 end
  se(Lobby.SE_SELECT)
  return true
end

function Lobby.confirm()
  local cb = Lobby._onConfirm
  if Lobby.mode == "leader" then
    if not Lobby.canStart() then return false end
    Lobby.close()
    if cb then cb(nil) end
    return true
  end
  local row = Lobby.players[Lobby.cursor]
  if not row then return false end
  -- pokefirered/src/union_room.c:1234
  if row.started or row.full then
    se(Lobby.SE_WALL_HIT)
    return false
  end
  Lobby.close()
  if cb then cb(row.slot or Lobby.cursor) end
  return true
end

function Lobby.cancel()
  local cb = Lobby._onCancel
  Lobby.close()
  if cb then cb() end
  return true
end

local function tickIndicator()
  local W = package.loaded["src.ui.game3.wireless_icon"]
  if not (W and W.update) then return end
  local Space = package.loaded["src.core.game3.scripting.space"]
  local Map = package.loaded["src.core.game3.map"]
  local mapId = Space and type(Space.mapId) == "string" and Space.mapId or (Map and Map.current)
  if W.onLinkMap and W.onLinkMap(mapId) then return end
  if W.frame then W.frame() end
  W.update(1 / 60)
end

function Lobby.update(_dt)
  if not Lobby.open then return end
  Lobby._frames = Lobby._frames + 1
  -- pokefirered/src/link_rfu_3.c:448
  tickIndicator()
  local tick = Lobby._onTick
  if tick then
    tick()
    if not Lobby.open then return end
  end
  local poll = Lobby._onPoll
  if not poll then return end
  local wait = (Lobby._pollWait or 0) - 1
  if wait > 0 then
    Lobby._pollWait = wait
    return
  end
  Lobby._pollWait = Lobby.POLL_FRAMES
  local list = poll()
  if type(list) == "table" then
    Lobby.players = list
    local n = #list
    if Lobby.cursor > n then Lobby.cursor = math.max(1, n) end
    if Lobby.top > Lobby.cursor then Lobby.top = Lobby.cursor end
  end
end

-- pokefirered/src/union_room.c:473
function Lobby.handleInput(input)
  if not (Lobby.open and input) then return end
  if Lobby.mode == "leader" then
    if input:wasPressed("b") then
      Lobby.cancel()
    elseif input:wasPressed("start") then
      Lobby.confirm()
    end
    return
  end
  if input:wasPressed("up") then Lobby.move(-1)
  elseif input:wasPressed("down") then Lobby.move(1)
  elseif input:wasPressed("a") then Lobby.confirm()
  elseif input:wasPressed("b") then Lobby.cancel()
  end
end

local T = 8

local function idText(trainerId)
  return RomText.plain("gText_UR_ID") .. string.format("%05d", (tonumber(trainerId) or 0) % 0x10000)
end

local function rowColors(row)
  if row.leaving then return FrlgFont.COLOR.RED end
  if row.pending then return FrlgFont.COLOR.GREEN end
  if row.started or row.full then return FrlgFont.COLOR.WHITE end
  return FrlgFont.COLOR.NORMAL
end

-- pokefirered/src/union_room.c:4079
local function drawCancelBar(textKey)
  local tpl = Lobby.CANCEL_TEMPLATE
  local c = Lobby.COLOR_CANCEL.bg
  love.graphics.setColor(c[1], c[2], c[3], 1)
  love.graphics.rectangle("fill", tpl.left * T, tpl.top * T, tpl.width * T, tpl.height * T)
  love.graphics.setColor(1, 1, 1, 1)
  FrlgFont.draw(RomText.plain(textKey), tpl.left * T + 8, tpl.top * T + 2,
    { small = true, colors = Lobby.COLOR_CANCEL })
end

-- pokefirered/src/union_room.c:4238
local function drawCandidate(row, px, py)
  local colors = rowColors(row)
  FrlgFont.draw(tostring(row.name or ""), px, py, { colors = colors })
  if row.trainerId ~= nil then
    FrlgFont.draw(idText(row.trainerId), px + 71, py, { small = true, colors = colors })
  end
end

-- pokefirered/src/union_room.c:4215
local function drawGroupRow(row, index, px, py)
  local colors = rowColors(row)
  FrlgFont.draw(string.format("%02d", index) .. RomText.plain("gText_UR_Colon"), px, py,
    { small = true, colors = FrlgFont.COLOR.NORMAL })
  local x = px + 18
  FrlgFont.draw(tostring(row.name or ""), x, py, { colors = colors })
  if row.trainerId ~= nil then
    FrlgFont.draw(idText(row.trainerId), x + 77, py, { small = true, colors = colors })
  end
end

local function drawTextbox(text)
  Window.dialogueFrame()
  FrlgFont.draw(tostring(text or ""), Chrome.DLG_LEFT * T, Chrome.DLG_TOP * T + 1,
    { maxWidth = Chrome.DLG_W * T, colors = FrlgFont.COLOR.NORMAL })
end

local function drawIndicator()
  pcall(function() require("src.ui.game3.wireless_icon").draw() end)
end

local function drawLeader()
  drawCancelBar("gText_UR_BButtonCancel")
  local list = Lobby.MEMBERS_TEMPLATE
  Window.stdFrame(list)
  local ox, oy = list.left * T, list.top * T
  local rows = { { name = Lobby.me.name, trainerId = Lobby.me.trainerId } }
  for _, p in ipairs(Lobby.players) do rows[#rows + 1] = p end
  for i = 1, math.min(#rows, Lobby.MAX_SHOWED) do
    drawCandidate(rows[i], ox, oy + (i - 1) * Lobby.ROW_H)
  end
  local box = Lobby.MODE_TEMPLATE
  Window.stdFrame(box)
  FrlgFont.draw(Lobby.modeText(), box.left * T, box.top * T + 2, { colors = FrlgFont.COLOR.NORMAL })
end

local function drawGroups()
  drawCancelBar("gText_UR_ChooseJoinCancel")
  local list = Lobby.GROUPS_TEMPLATE
  Window.stdFrame(list)
  local ox, oy = list.left * T, list.top * T
  for i = Lobby.top, math.min(#Lobby.players, Lobby.top + Lobby.MAX_SHOWED - 1) do
    local py = oy + (i - Lobby.top) * Lobby.ROW_H
    if i == Lobby.cursor then Window.cursorPx(ox, py) end
    drawGroupRow(Lobby.players[i], i, ox + 8, py)
  end
  -- pokefirered/src/union_room.c:346
  local box = Lobby.NAME_ID_TEMPLATE
  Window.stdFrame(box)
  FrlgFont.draw(Lobby.me.name, box.left * T, box.top * T + 2, { colors = FrlgFont.COLOR.NORMAL })
  FrlgFont.draw(idText(Lobby.me.trainerId), box.left * T, box.top * T + 16,
    { small = true, colors = FrlgFont.COLOR.NORMAL })
end

function Lobby.draw()
  if not Lobby.open then return end
  if not (love and love.graphics) then return end
  if Lobby.mode == "leader" then drawLeader() else drawGroups() end
  drawTextbox(Lobby.message())
  drawIndicator()
end

return Lobby
