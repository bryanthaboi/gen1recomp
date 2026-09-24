local TextIR = require("src.core.game3.scripting.text_ir")

local Chat = {}

-- pokefirered/src/union_room_chat.c:21
Chat.MAX_LENGTH = 15
-- pokefirered/src/union_room_chat_display.c:744
Chat.MAX_LINES = 10
Chat.MAX_SEATS = 5
Chat.KB_ROWS = 10
Chat.KB_COLS = 5
-- pokefirered/include/union_room_chat.h:4
Chat.PAGE = { UPPER = 0, LOWER = 1, EMOJI = 2, REGISTER = 3 }
Chat.SWAP_EXIT = 4
-- pokefirered/src/union_room_chat.c:322
Chat.REPEAT_START = 20
Chat.REPEAT_CONTINUE = 5
-- pokefirered/src/union_room_chat.c:1226
Chat.REGISTER_CHARS = 10
-- pokefirered/src/union_room_chat.c:709
Chat.EXIT_DELAY = 150
-- pokefirered/src/union_room_chat.c:1002
Chat.SAVED_FRAMES = 120
-- pokefirered/src/union_room_chat_display.c:757
Chat.SCROLL_PIXELS = 5
Chat.SCROLL_STEPS = 3
Chat.LINE_HEIGHT = 15
-- pokefirered/src/union_room_chat_display.c:1160
Chat.SLIDE_STEP = 12
Chat.SLIDE_MAX = 56
-- pokefirered/src/union_room_chat_objects.c:260
Chat.BLINK_FRAMES = 3

Chat.MSG = {
  LINE = "game3_chat_line",
  BYE = "game3_chat_bye",
  JOIN = "game3_union_hello",
}

-- pokefirered/src/union_room_chat.c:279
Chat.KEYBOARD = {
  [0] = {
    "gText_UnionRoomChatKeyboard_ABCDE", "gText_UnionRoomChatKeyboard_FGHIJ",
    "gText_UnionRoomChatKeyboard_KLMNO", "gText_UnionRoomChatKeyboard_PQRST",
    "gText_UnionRoomChatKeyboard_UVWXY", "gText_UnionRoomChatKeyboard_Z",
    "gText_UnionRoomChatKeyboard_01234Upper", "gText_UnionRoomChatKeyboard_56789Upper",
    "gText_UnionRoomChatKeyboard_PunctuationUpper", "gText_UnionRoomChatKeyboard_SymbolsUpper",
  },
  [1] = {
    "gText_UnionRoomChatKeyboard_abcde", "gText_UnionRoomChatKeyboard_fghij",
    "gText_UnionRoomChatKeyboard_klmno", "gText_UnionRoomChatKeyboard_pqrst",
    "gText_UnionRoomChatKeyboard_uvwxy", "gText_UnionRoomChatKeyboard_z",
    "gText_UnionRoomChatKeyboard_01234Lower", "gText_UnionRoomChatKeyboard_56789Lower",
    "gText_UnionRoomChatKeyboard_PunctuationLower", "gText_UnionRoomChatKeyboard_SymbolsLower",
  },
  [2] = {
    "gText_UnionRoomChatKeyboard_Emoji1", "gText_UnionRoomChatKeyboard_Emoji2",
    "gText_UnionRoomChatKeyboard_Emoji3", "gText_UnionRoomChatKeyboard_Emoji4",
    "gText_UnionRoomChatKeyboard_Emoji5", "gText_UnionRoomChatKeyboard_Emoji6",
    "gText_UnionRoomChatKeyboard_Emoji7", "gText_UnionRoomChatKeyboard_Emoji8",
    "gText_UnionRoomChatKeyboard_Emoji9", "gText_UnionRoomChatKeyboard_Emoji10",
  },
}

-- pokefirered/src/union_room_chat.c:1430
Chat.REGISTERED_DEFAULTS = {
  "gText_Hello", "gText_Pokemon2", "gText_Trade", "gText_Battle", "gText_Lets",
  "gText_Ok", "gText_Sorry", "gText_YaySmileEmoji", "gText_ThankYou", "gText_ByeBye",
}

-- pokefirered/src/union_room_chat_display.c:222
Chat.MESSAGES = {
  QUIT = { key = "gText_QuitChatting", box = 1 },
  REGISTER_WHERE = { key = "gText_RegisterTextWhere", box = 1, vofs = 16 },
  REGISTER_HERE = { key = "gText_RegisterTextHere", box = 1 },
  INPUT_TEXT = { key = "gText_InputText", box = 1, vofs = 16 },
  EXITING = { key = "gText_ExitingTheChat", box = 2 },
  LEADER_LEFT = { key = "gText_LeaderHasLeftEndingChat", box = 2, dynamic = true },
  ASK_SAVE = { key = "gText_RegisteredTextChanged_OKtoSave", box = 2, wide = true },
  ASK_OVERWRITE = { key = "gText_RegisteredTextChanged_AlreadySavedFile", box = 2, wide = true },
  SAVING = { key = "gText_RegisteredTextChanged_SavingDontTurnOff", box = 2, wide = true },
  SAVED = { key = "gText_RegisteredTextChanged_SavedTheGame", box = 2, wide = true, player = true },
  WARN_LEADER = { key = "gText_IfLeaderLeavesChatWillEnd", box = 2, wide = true },
}

-- pokefirered/src/union_room_chat.c:132
local CASE_PAIRS = {
  "Àà", "Áá", "Ââ", "Ää", "Çç", "Èè", "Éé", "Êê", "Ëë", "Ìì", "Íí", "Îî", "Ïï",
  "Òò", "Óó", "Ôô", "Öö", "Œœ", "Ùù", "Úú", "Ûû", "Üü", "Ññ",
}
local CASE = {}
for c = 65, 90 do
  CASE[string.char(c)] = string.char(c + 32)
  CASE[string.char(c + 32)] = string.char(c)
end
for _, pair in ipairs(CASE_PAIRS) do
  local upper, lower = pair:match("^([\192-\255][\128-\191]*)(.+)$")
  CASE[upper], CASE[lower] = lower, upper
end

local EMOJI_ID, EMOJI_TAG = {}, {}
for id, sym in pairs(TextIR.EXTRA_SYMBOL) do
  if sym:match("^{EMOJI_") then
    EMOJI_ID[sym] = id
    EMOJI_TAG[id] = sym
  end
end
Chat.PUA_BASE = 0xE000

Chat.state = "off"
Chat.lines = {}
Chat.lastResult = nil

local function link()
  return require("src.core.game3.link")
end

local function romText()
  return require("src.core.game3.rom_text")
end

local function playSe(name)
  local okA, Audio = pcall(require, "src.core.game3.audio")
  local okS, SE = pcall(require, "src.core.game3.se_ids")
  if okA and okS and Audio.playSe and SE[name] then pcall(Audio.playSe, SE[name]) end
end

Chat.playSe = playSe

local function utf8Tokens(s)
  local out = {}
  local i, n = 1, #s
  while i <= n do
    local b = s:byte(i)
    if b == 0x7B then
      local close = s:find("}", i + 1, true)
      if close then
        out[#out + 1] = s:sub(i, close)
        i = close + 1
      else
        out[#out + 1] = "{"
        i = i + 1
      end
    else
      local len = 1
      if b >= 0xF0 then len = 4 elseif b >= 0xE0 then len = 3 elseif b >= 0xC0 then len = 2 end
      if b >= 0x80 and b < 0xC0 then
        i = i + 1
      else
        local ch = s:sub(i, i + len - 1)
        if #ch == len and not (len > 1 and not ch:sub(2):match("^[\128-\191]+$")) then
          out[#out + 1] = ch
        end
        i = i + len
      end
    end
  end
  return out
end

Chat.tokens = utf8Tokens

local function codepoint(ch)
  local b1, b2, b3 = ch:byte(1, 3)
  if #ch == 3 then return (b1 % 16) * 4096 + (b2 % 64) * 64 + (b3 % 64) end
  return nil
end

local function utf8Char(cp)
  return string.char(0xE0 + math.floor(cp / 4096), 0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
end

function Chat.encode(tokens)
  local out = {}
  for _, t in ipairs(tokens) do
    local id = EMOJI_ID[t]
    if id then out[#out + 1] = utf8Char(Chat.PUA_BASE + id) else out[#out + 1] = t end
  end
  return table.concat(out)
end

function Chat.decode(text)
  local out = {}
  for _, t in ipairs(utf8Tokens(tostring(text or ""))) do
    local cp = t:sub(1, 1) ~= "{" and codepoint(t) or nil
    if cp and cp >= Chat.PUA_BASE and cp < Chat.PUA_BASE + 0x100 then
      local tag = EMOJI_TAG[cp - Chat.PUA_BASE]
      if tag then out[#out + 1] = tag end
    elseif t:sub(1, 1) == "{" then
      if EMOJI_ID[t] then out[#out + 1] = t end
    else
      out[#out + 1] = t
    end
  end
  while #out > Chat.MAX_LENGTH do table.remove(out) end
  return out
end

function Chat.cleanName(name)
  local out = {}
  for _, t in ipairs(utf8Tokens(tostring(name or ""))) do
    if t:sub(1, 1) ~= "{" and t:byte(1) >= 0x20 and #out < 7 then out[#out + 1] = t end
  end
  return table.concat(out)
end

function Chat.caseOf(token)
  return CASE[token]
end

function Chat.keyboardRow(page, row)
  local key = Chat.KEYBOARD[page] and Chat.KEYBOARD[page][row + 1]
  if not key then return {} end
  local memo = Chat._rows or {}
  Chat._rows = memo
  if not memo[key] then memo[key] = utf8Tokens(romText().plain(key)) end
  return memo[key]
end

function Chat.defaultRegistered()
  local out = {}
  for i, key in ipairs(Chat.REGISTERED_DEFAULTS) do out[i] = romText().plain(key) end
  return out
end

local function sessionRef()
  local ok, s = pcall(function() return link().session() end)
  return ok and s or nil
end

function Chat.localName()
  local s = sessionRef()
  return tostring((s and (s.name or s.playerName)) or "PLAYER"):sub(1, 7)
end

local function localHello()
  local s = sessionRef() or {}
  return {
    type = Chat.MSG.JOIN,
    name = Chat.localName(),
    gender = (s.gender == 1 or s.gender == "female") and 1 or 0,
    trainerId = (tonumber(s.trainerId or s.id) or 0) % 65536,
    activity = 5 + 0x40,
  }
end

local function relayChannel(rs, client)
  local roomId = rs.target
  local C = client
  return {
    relay = true,
    send = function(_, msg) rs:send(msg) end,
    take = function(_, t) return rs:take(t) end,
    seat = function() return tonumber(rs:seat()) end,
    players = function() return rs:players() or {} end,
    closed = function()
      if rs.closed or rs.left then return true end
      local room = C and C.room and C.room()
      if type(room) ~= "table" then return true end
      if roomId ~= nil and room.room ~= roomId then return true end
      local state = C.state and C.state()
      return state == "error" or state == "offline"
    end,
    leave = function() if not rs.left then rs:close() end end,
  }
end

local function linkChannel(lk)
  return {
    relay = false,
    send = function(_, msg) if lk:isOpen() then lk:send(msg) end end,
    take = function(_, t) return lk:take(t) end,
    seat = function()
      if lk.seat ~= nil then return tonumber(lk.seat) end
      return lk.role == "guest" and 1 or 0
    end,
    players = function()
      local out = {}
      for _, p in ipairs(lk.players and lk:players() or {}) do
        out[#out + 1] = { seat = tonumber(p.seat) or (p.role == "guest" and 1 or 0), name = p.name }
      end
      return out
    end,
    closed = function() return not lk:isOpen() end,
    leave = function() end,
  }
end

Chat.relayChannel = relayChannel
Chat.linkChannel = linkChannel

function Chat.isActive()
  return Chat.state ~= "off"
end

function Chat.isLeader()
  return Chat.seat == 0
end

local function seatName(seat)
  local name = Chat.members[seat]
  if name then return name end
  for _, p in ipairs(Chat.channel and Chat.channel:players() or {}) do
    if tonumber(p.seat) == seat then return p.name end
  end
  return ""
end

-- pokefirered/src/union_room_chat_display.c:1209
local function pushLine(text, seat)
  Chat.lines[#Chat.lines + 1] = { text = text, seat = tonumber(seat) or 0 }
  if #Chat.lines >= Chat.MAX_LINES then
    table.remove(Chat.lines, 1)
    Chat.scroll = { step = 0, offset = Chat.SCROLL_PIXELS * Chat.SCROLL_STEPS }
  end
end

Chat.pushLine = pushLine

-- pokefirered/src/union_room_chat.c:1283
function Chat.chatLine(name, tokens)
  return tostring(name or "") .. "\252\19\42:" .. table.concat(tokens)
end

function Chat.joinedLine(name)
  return romText().plain("gText_F700JoinedChat", { dynamic = { [0] = name } })
end

function Chat.leftLine(name)
  return romText().plain("gText_F700LeftChat", { dynamic = { [0] = name } })
end

function Chat.push(name, text)
  pushLine(Chat.chatLine(name, Chat.decode(text)), Chat.seat)
end

local function resetWork()
  Chat.lines = {}
  Chat.buffer = {}
  Chat.lastPos = 0
  Chat.page = Chat.PAGE.UPPER
  Chat.col, Chat.row = 0, 0
  Chat.routine = "input"
  Chat.phase = 0
  Chat.timer = 0
  Chat.msg = nil
  Chat.yesNo = nil
  Chat.swap = nil
  Chat.blink = 0
  Chat.slide = nil
  Chat.hofs = 0
  Chat.scroll = nil
  Chat.charX2, Chat.charTimer = 0, 0
  Chat.exitType = nil
  Chat.hostName = ""
  Chat.members = {}
  Chat.present = {}
  Chat.changed = false
  Chat._held, Chat._heldFrames = nil, 0
  Chat._exitSeen = nil
  Chat.sent = 0
end

-- pokefirered/src/union_room_chat.c:318 EnterUnionRoomChat
function Chat.start(opts)
  opts = opts or {}
  local channel = opts.channel
  if not channel and opts.session then channel = relayChannel(opts.session, opts.client or link().client()) end
  if not channel then
    local lk = link().link
    if not (lk and lk.isOpen and lk:isOpen()) then return false, "no_link" end
    channel = linkChannel(lk)
  end
  resetWork()
  Chat.channel = channel
  Chat.seat = channel:seat() or 0
  Chat.state = "on"
  Chat.lastResult = nil
  Chat._onDone = opts.onDone
  local s = sessionRef()
  local reg = s and type(s.registeredTexts) == "table" and s.registeredTexts or nil
  if not reg then reg = Chat.defaultRegistered() end
  Chat.registered = {}
  for i = 1, Chat.KB_ROWS do Chat.registered[i] = tostring(reg[i] or "") end
  Chat.members[Chat.seat] = Chat.localName()
  for _, p in ipairs(channel:players()) do
    local seat = tonumber(p.seat)
    if seat then Chat.present[seat] = true end
  end
  -- pokefirered/src/union_room_chat.c:431
  channel:send(localHello())
  if opts.screen ~= false then
    local ok, Screen = pcall(require, "src.ui.game3.union_chat")
    if ok and Screen.show and type(love) == "table" and love.graphics then Screen.show() end
  end
  link().startPump()
  return true
end

local function others()
  local n = 0
  for seat in pairs(Chat.present) do
    if seat ~= Chat.seat then n = n + 1 end
  end
  return n
end

Chat.others = others

-- pokefirered/src/union_room_chat.c:1451
function Chat.receive()
  local ch = Chat.channel
  if not ch then return end
  local join = ch:take(Chat.MSG.JOIN)
  while join do
    local seat = tonumber(join.seat)
    if seat and seat ~= Chat.seat then
      Chat.members[seat] = Chat.cleanName(join.name)
      Chat.present[seat] = true
      pushLine(Chat.joinedLine(Chat.members[seat]), seat)
    end
    join = ch:take(Chat.MSG.JOIN)
  end
  local line = ch:take(Chat.MSG.LINE)
  while line do
    local seat = tonumber(line.seat)
    if seat and seat ~= Chat.seat then
      if type(line.name) == "string" and line.name ~= "" then Chat.members[seat] = Chat.cleanName(line.name) end
      Chat.present[seat] = true
      pushLine(Chat.chatLine(Chat.members[seat] or seatName(seat), Chat.decode(line.text)), seat)
    end
    line = ch:take(Chat.MSG.LINE)
  end
  local bye = ch:take(Chat.MSG.BYE)
  while bye do
    local seat = tonumber(bye.seat)
    if seat and seat ~= Chat.seat and Chat.present[seat] then
      Chat.leave(seat)
    end
    bye = ch:take(Chat.MSG.BYE)
  end
  if ch.relay then
    local now = {}
    for _, p in ipairs(ch:players()) do
      local seat = tonumber(p.seat)
      if seat then now[seat] = true end
    end
    for seat in pairs(Chat.present) do
      if seat ~= Chat.seat and not now[seat] then Chat.leave(seat) end
    end
    for seat in pairs(now) do Chat.present[seat] = true end
  end
end

function Chat.leave(seat)
  if not Chat.present[seat] then return end
  Chat.present[seat] = nil
  local name = seatName(seat)
  pushLine(Chat.leftLine(name), seat)
  if Chat.exitType or Chat.routine == "fade" then return end
  if seat == 0 and Chat.seat ~= 0 then
    Chat.hostName = name
    Chat.exitType = "disbanded"
  elseif Chat.seat == 0 and others() == 0 then
    Chat.exitType = "leader_last"
  end
end

local function goRoutine(name)
  Chat.routine = name
  Chat.phase = 0
  Chat.timer = 0
end

Chat.goRoutine = goRoutine

function Chat.showMessage(id)
  local def = Chat.MESSAGES[id]
  local ctx = {}
  if def.dynamic then ctx.dynamic = { [0] = Chat.hostName } end
  if def.player then
    ctx.dynamic = { [0] = Chat.localName() }
    ctx.playerName = Chat.localName()
  end
  Chat.msg = { id = id, text = romText().plain(def.key, ctx), box = def.box, wide = def.wide == true,
    vofs = def.vofs or 0 }
end

function Chat.hideMessage()
  Chat.msg = nil
  Chat.yesNo = nil
end

-- pokefirered/src/union_room_chat_display.c:940
function Chat.showYesNo(left, top)
  Chat.yesNo = { left = left, top = top, cursor = 1 }
end

function Chat.lastToken()
  return Chat.buffer[#Chat.buffer]
end

-- pokefirered/src/union_room_chat.c:1415
function Chat.canToggleCase()
  local t = Chat.lastToken()
  return t ~= nil and CASE[t] ~= nil
end

-- pokefirered/src/union_room_chat.c:1078
function Chat.append()
  local add
  if Chat.page ~= Chat.PAGE.REGISTER then
    local row = Chat.keyboardRow(Chat.page, Chat.row)
    local t = row[Chat.col + 1]
    add = t and { t } or {}
  else
    add = utf8Tokens(Chat.registered[Chat.row + 1] or "")
    add[#add + 1] = " "
  end
  Chat.lastPos = #Chat.buffer
  for _, t in ipairs(add) do
    if #Chat.buffer >= Chat.MAX_LENGTH then break end
    Chat.buffer[#Chat.buffer + 1] = t
  end
end

-- pokefirered/src/union_room_chat.c:1131
function Chat.deleteLast()
  Chat.lastPos = #Chat.buffer
  if #Chat.buffer > 0 then table.remove(Chat.buffer) end
end

-- pokefirered/src/union_room_chat.c:1142
function Chat.toggleCase()
  local t = Chat.lastToken()
  if t and CASE[t] then Chat.buffer[#Chat.buffer] = CASE[t] end
end

-- pokefirered/src/union_room_chat.c:1218
function Chat.registerStart()
  return math.max(0, #Chat.buffer - Chat.REGISTER_CHARS)
end

-- pokefirered/src/union_room_chat.c:1165
function Chat.registerAt(row)
  local parts = {}
  for i = Chat.registerStart() + 1, #Chat.buffer do parts[#parts + 1] = Chat.buffer[i] end
  Chat.registered[(row or Chat.row) + 1] = table.concat(parts)
  Chat.changed = true
end

-- pokefirered/src/union_room_chat.c:1027
function Chat.moveCursor(dir)
  local maxRow = Chat.KB_ROWS - 1
  if dir == "up" then
    Chat.row = Chat.row > 0 and Chat.row - 1 or maxRow
  elseif dir == "down" then
    Chat.row = Chat.row < maxRow and Chat.row + 1 or 0
  elseif Chat.page ~= Chat.PAGE.REGISTER and dir == "left" then
    Chat.col = Chat.col > 0 and Chat.col - 1 or Chat.KB_COLS - 1
  elseif Chat.page ~= Chat.PAGE.REGISTER and dir == "right" then
    Chat.col = Chat.col < Chat.KB_COLS - 1 and Chat.col + 1 or 0
  else
    return false
  end
  return true
end

-- pokefirered/src/union_room_chat.c:805 ChatEntryRoutine_SendMessage
function Chat.send()
  if #Chat.buffer == 0 then return false end
  local ch = Chat.channel
  if not ch or ch:closed() then return false end
  local text = Chat.encode(Chat.buffer)
  ch:send({ type = Chat.MSG.LINE, name = Chat.localName(), text = text })
  pushLine(Chat.chatLine(Chat.localName(), Chat.buffer), Chat.seat)
  Chat.sent = Chat.sent + 1
  Chat.buffer = {}
  Chat.lastPos = Chat.MAX_LENGTH
  return true
end

function Chat.say(text)
  if Chat.state ~= "on" then return false end
  Chat.buffer = Chat.decode(Chat.encode(utf8Tokens(tostring(text or ""))))
  return Chat.send()
end

local function pressed(input, key)
  return input and input.wasPressed and input:wasPressed(key) and true or false
end

local REPEAT_KEYS = { "up", "down", "left", "right", "b" }

local function trackHeld(input)
  local key
  if input and input.isDown then
    for _, k in ipairs(REPEAT_KEYS) do
      local ok, down = pcall(input.isDown, input, k)
      if ok and down then
        key = k
        break
      end
    end
  end
  if key ~= Chat._held or (key and pressed(input, key)) then
    Chat._held, Chat._heldFrames = key, 0
  elseif key then
    Chat._heldFrames = Chat._heldFrames + 1
  end
end

local function repeated(input, key)
  if pressed(input, key) then return true end
  local n = Chat._heldFrames - Chat.REPEAT_START
  return Chat._held == key and n >= 0 and n % Chat.REPEAT_CONTINUE == 0
end

local function dpad(input)
  for _, dir in ipairs({ "up", "down", "left", "right" }) do
    if repeated(input, dir) and Chat.moveCursor(dir) then return true end
  end
  return false
end

-- pokefirered/src/menu.c:342
local function yesNoInput(input)
  local yn = Chat.yesNo
  if not yn then return nil end
  if pressed(input, "up") or pressed(input, "down") then
    yn.cursor = yn.cursor == 0 and 1 or 0
    playSe("SE_SELECT")
    return nil
  end
  if pressed(input, "a") then
    playSe("SE_SELECT")
    return yn.cursor
  end
  if pressed(input, "b") then
    playSe("SE_SELECT")
    return -1
  end
  return nil
end

-- pokefirered/src/union_room_chat.c:453
local function handleKeyboard(input)
  if pressed(input, "start") then
    if #Chat.buffer > 0 then goRoutine("send") end
  elseif pressed(input, "select") then
    goRoutine("switch")
  elseif repeated(input, "b") then
    if #Chat.buffer > 0 then
      Chat.deleteLast()
    else
      goRoutine("quit")
    end
  elseif pressed(input, "a") then
    Chat.append()
    Chat.blink = Chat.BLINK_FRAMES + 1
  elseif pressed(input, "r") then
    if Chat.page ~= Chat.PAGE.REGISTER then
      Chat.toggleCase()
    else
      goRoutine("register")
    end
  else
    dpad(input)
  end
end

function Chat.handleInput(input)
  if Chat.state ~= "on" or not input then return end
  trackHeld(input)
  if Chat.slide then return end
  local r = Chat.routine
  if r == "input" then
    handleKeyboard(input)
  elseif r == "switch" and Chat.phase == 1 then
    local sw = Chat.swap
    if pressed(input, "up") then
      sw.cursor = (sw.cursor - 1) % (Chat.SWAP_EXIT + 1)
      playSe("SE_SELECT")
    elseif pressed(input, "down") or pressed(input, "select") then
      sw.cursor = (sw.cursor + 1) % (Chat.SWAP_EXIT + 1)
      playSe("SE_SELECT")
    elseif pressed(input, "a") then
      playSe("SE_SELECT")
      Chat.swap = nil
      local pick = sw.cursor
      if pick == Chat.page or pick > Chat.PAGE.REGISTER then
        goRoutine("input")
      else
        Chat.col, Chat.row = 0, 0
        Chat.slide = { dir = 1, target = pick }
        goRoutine("input")
      end
    elseif pressed(input, "b") then
      playSe("SE_SELECT")
      Chat.swap = nil
      goRoutine("input")
    end
  elseif r == "quit" and Chat.phase == 1 then
    local pick = yesNoInput(input)
    if pick == 0 then
      Chat.hideMessage()
      if Chat.isLeader() then
        goRoutine("quit_leader")
      else
        Chat.channel:send({ type = Chat.MSG.BYE })
        Chat.exitType = "left"
        goRoutine("save_and_exit")
      end
    elseif pick ~= nil then
      Chat.hideMessage()
      goRoutine("input")
    end
  elseif r == "quit_leader" and Chat.phase == 1 then
    local pick = yesNoInput(input)
    if pick == 0 then
      Chat.hideMessage()
      Chat.channel:send({ type = Chat.MSG.BYE })
      Chat.exitType = "left"
      goRoutine("save_and_exit")
    elseif pick ~= nil then
      Chat.hideMessage()
      goRoutine("input")
    end
  elseif r == "register" and Chat.phase == 1 then
    if pressed(input, "a") then
      Chat.registerAt(Chat.row)
      Chat.hideMessage()
      goRoutine("input")
    elseif pressed(input, "b") then
      Chat.hideMessage()
      goRoutine("input")
    else
      dpad(input)
    end
  elseif r == "input_text" and Chat.phase == 1 then
    if pressed(input, "a") or pressed(input, "b") then
      Chat.hideMessage()
      goRoutine("input")
    end
  elseif (r == "ask_save" or r == "ask_overwrite") and Chat.phase == 1 then
    local pick = yesNoInput(input)
    if pick == 0 then
      Chat.hideMessage()
      goRoutine(r == "ask_save" and "ask_overwrite" or "saving")
    elseif pick ~= nil then
      Chat.hideMessage()
      goRoutine("fade")
    end
  end
end

-- pokefirered/src/union_room_chat.c:905
local function saveGame()
  local s = sessionRef()
  if s then
    s.registeredTexts = {}
    for i = 1, Chat.KB_ROWS do s.registeredTexts[i] = Chat.registered[i] end
  end
  local game = link().game()
  if game and type(game.saveGame) == "function" then pcall(game.saveGame, game) end
end

local function stepRoutine()
  local r = Chat.routine
  if r == "input" or r == "switch" and Chat.phase == 1 then return end
  if r == "send" then
    Chat.send()
    goRoutine("input")
  elseif r == "switch" then
    Chat.swap = { cursor = Chat.page }
    Chat.phase = 1
  elseif r == "quit" and Chat.phase == 0 then
    Chat.showMessage("QUIT")
    Chat.showYesNo(23, 11)
    Chat.phase = 1
  elseif r == "quit_leader" and Chat.phase == 0 then
    Chat.showMessage("WARN_LEADER")
    Chat.showYesNo(23, 10)
    Chat.phase = 1
  elseif r == "register" and Chat.phase == 0 then
    if #Chat.buffer > 0 then
      Chat.showMessage("REGISTER_WHERE")
      Chat.phase = 1
    else
      Chat.showMessage("INPUT_TEXT")
      goRoutine("input_text")
      Chat.phase = 1
    end
  elseif r == "exit_chat" then
    if Chat.phase == 0 then
      Chat.showMessage("EXITING")
      Chat.phase = 1
    end
    Chat.timer = Chat.timer + 1
    if Chat.timer >= Chat.EXIT_DELAY then goRoutine("save_and_exit") end
  elseif r == "disbanded" then
    if Chat.phase == 0 then
      Chat.hideMessage()
      Chat.showMessage("LEADER_LEFT")
      Chat.phase = 1
    end
    Chat.timer = Chat.timer + 1
    if Chat.timer >= Chat.EXIT_DELAY then goRoutine("save_and_exit") end
  elseif r == "drop" then
    Chat.hideMessage()
    Chat.timer = Chat.timer + 1
    if Chat.timer >= Chat.EXIT_DELAY then goRoutine("save_and_exit") end
  elseif r == "save_and_exit" then
    Chat.hideMessage()
    goRoutine(Chat.changed and "ask_save" or "fade")
  elseif r == "ask_save" and Chat.phase == 0 then
    Chat.showMessage("ASK_SAVE")
    Chat.showYesNo(23, 10)
    Chat.phase = 1
  elseif r == "ask_overwrite" and Chat.phase == 0 then
    Chat.showMessage("ASK_OVERWRITE")
    Chat.showYesNo(23, 10)
    Chat.phase = 1
  elseif r == "saving" then
    if Chat.phase == 0 then
      Chat.showMessage("SAVING")
      Chat.phase = 1
    elseif Chat.phase == 1 then
      saveGame()
      Chat.showMessage("SAVED")
      playSe("SE_SAVE")
      Chat.phase = 2
    else
      Chat.timer = Chat.timer + 1
      if Chat.timer > Chat.SAVED_FRAMES then goRoutine("fade") end
    end
  elseif r == "fade" and Chat.phase == 0 then
    Chat.phase = 1
    local ok, Screen = pcall(require, "src.ui.game3.union_chat")
    if ok and Screen.isOpen and Screen.isOpen() and Screen.fadeOut then
      Screen.fadeOut(function() Chat.stop(Chat.exitType or "left") end)
    else
      Chat.stop(Chat.exitType or "left")
    end
  end
end

-- pokefirered/src/union_room_chat_display.c:1156
local function stepSlide()
  local sl = Chat.slide
  if not sl then return end
  if sl.dir == 1 then
    Chat.hofs = math.min(Chat.SLIDE_MAX, Chat.hofs + Chat.SLIDE_STEP)
    if Chat.hofs >= Chat.SLIDE_MAX then
      Chat.page = sl.target
      sl.dir = -1
    end
  else
    Chat.hofs = math.max(0, Chat.hofs - Chat.SLIDE_STEP)
    if Chat.hofs <= 0 then Chat.slide = nil end
  end
end

function Chat.update(_dt)
  if Chat.state == "off" then return false end
  local ch = Chat.channel
  if ch and Chat.routine ~= "fade" then
    Chat.receive()
    if not Chat.exitType and ch:closed() then
      if Chat.seat ~= 0 and Chat.present[0] then
        Chat.hostName = seatName(0)
        Chat.exitType = "disbanded"
      else
        Chat.exitType = "dropped"
      end
    end
  end
  -- pokefirered/src/union_room_chat.c:410
  local exit = Chat.exitType
  if exit and Chat._exitSeen ~= exit and Chat.routine ~= "save_and_exit" and Chat.routine ~= "fade"
      and Chat.routine ~= "ask_save" and Chat.routine ~= "ask_overwrite" and Chat.routine ~= "saving" then
    Chat._exitSeen = exit
    Chat.swap = nil
    if exit == "leader_last" then
      Chat.hideMessage()
      goRoutine("exit_chat")
    elseif exit == "disbanded" then
      goRoutine("disbanded")
    elseif exit == "dropped" then
      goRoutine("drop")
    end
  end
  stepRoutine()
  stepSlide()
  if Chat.blink > 0 then Chat.blink = Chat.blink - 1 end
  local sc = Chat.scroll
  if sc then
    sc.offset = sc.offset - Chat.SCROLL_PIXELS
    if sc.offset <= 0 then Chat.scroll = nil end
  end
  -- pokefirered/src/union_room_chat_objects.c:298
  Chat.charTimer = Chat.charTimer + 1
  if Chat.charTimer > 4 then
    Chat.charTimer = 0
    Chat.charX2 = Chat.charX2 + 1
    if Chat.charX2 > 4 then Chat.charX2 = 0 end
  end
  return Chat.state ~= "off"
end

function Chat.stop(reason)
  if Chat.state == "off" then return false end
  Chat.state = "off"
  Chat.lastResult = reason or "left"
  local ch = Chat.channel
  if ch and reason ~= "peer_left" and reason ~= "dropped" and reason ~= "disbanded"
      and not ch:closed() and Chat.exitType == nil then
    ch:send({ type = Chat.MSG.BYE })
  end
  local okS, Screen = pcall(require, "src.ui.game3.union_chat")
  if okS and Screen.isOpen and Screen.isOpen() then Screen.close() end
  local cb = Chat._onDone
  Chat._onDone = nil
  Chat.channel = nil
  if cb then cb(Chat.lastResult) end
  return true
end

function Chat.reset()
  Chat.state = "off"
  Chat.lines = {}
  Chat.lastResult = nil
  Chat._onDone = nil
  Chat.channel = nil
  Chat._exitSeen = nil
  Chat.exitType = nil
  local Screen = package.loaded["src.ui.game3.union_chat"]
  if Screen and Screen.reset then Screen.reset() end
end

return Chat
