local Chat = {}

-- pokefirered/src/union_room_chat.c:70 registeredTexts[UNION_ROOM_KB_ROW_COUNT][21]
Chat.MAX_LENGTH = 20
-- pokefirered/src/union_room_chat.c:70 registeredTexts
Chat.MAX_LINES = 10

Chat.MSG = {
  LINE = "game3_chat_line",
  BYE = "game3_chat_bye",
}

Chat.state = "off"
Chat.lines = {}
Chat.lastResult = nil

local function link()
  return require("src.core.game3.link")
end

local function screen()
  local ok, mod = pcall(require, "src.ui.game3.union_room")
  return ok and mod or nil
end

local function live()
  local lk = link().link
  if lk and lk.isOpen and lk:isOpen() then return lk end
  return nil
end

function Chat.isActive()
  return Chat.state ~= "off"
end

local function push(name, text)
  Chat.lines[#Chat.lines + 1] = { name = name, text = text }
  while #Chat.lines > Chat.MAX_LINES do table.remove(Chat.lines, 1) end
end

Chat.push = push

function Chat.localName()
  local s = link().session()
  return (s and (s.name or s.playerName)) or "PLAYER"
end

-- pokefirered/src/union_room_chat.c:318 EnterUnionRoomChat
function Chat.start(opts)
  opts = opts or {}
  if not live() then return false, "no_link" end
  Chat.state = "on"
  Chat.lines = {}
  Chat.lastResult = nil
  Chat._onDone = opts.onDone
  local s = screen()
  if s and s.showChat then
    s.showChat({
      lines = Chat.lines,
      onSay = function(text) Chat.say(text) end,
      onLeave = function() Chat.stop("left") end,
    })
  end
  link().startPump()
  return true
end

-- pokefirered/src/union_room_chat.c:805 ChatEntryRoutine_SendMessage
function Chat.say(text)
  if Chat.state ~= "on" then return false end
  if type(text) ~= "string" then return false end
  text = text:sub(1, Chat.MAX_LENGTH)
  if text == "" then return false end
  local lk = live()
  if not lk then
    Chat.stop("peer_dropped")
    return false
  end
  lk:send({ type = Chat.MSG.LINE, name = Chat.localName(), text = text })
  push(Chat.localName(), text)
  return true
end

function Chat.update(dt)
  if Chat.state == "off" then return false end
  local lk = live()
  if not lk then
    Chat.stop("peer_dropped")
    return false
  end
  local line = lk:take(Chat.MSG.LINE)
  while line do
    push(line.name, tostring(line.text or ""))
    line = lk:take(Chat.MSG.LINE)
  end
  -- pokefirered/src/union_room.c:3144 gText_UR_ChatEnded
  if lk:take(Chat.MSG.BYE) then
    Chat.stop("peer_left")
    return false
  end
  return true
end

-- pokefirered/src/union_room.c:3144 gText_UR_ChatEnded
function Chat.stop(reason)
  if Chat.state == "off" then return false end
  Chat.state = "off"
  Chat.lastResult = reason or "left"
  local lk = live()
  if lk and reason ~= "peer_left" and reason ~= "peer_dropped" then
    lk:send({ type = Chat.MSG.BYE })
  end
  local s = screen()
  if s and s.isOpen and s.isOpen() and s.mode == "chat" then s.close() end
  local cb = Chat._onDone
  Chat._onDone = nil
  if cb then cb(Chat.lastResult) end
  return true
end

function Chat.reset()
  Chat.state = "off"
  Chat.lines = {}
  Chat.lastResult = nil
  Chat._onDone = nil
end

return Chat
