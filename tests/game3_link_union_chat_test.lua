#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function eq(a, b, msg)
  check(a == b, string.format("%s (%s == %s)", msg, tostring(a), tostring(b)))
end

local romBundle = require("tests.game3_cache").bundle()
package.loaded["src.core.game3.scripting.space"] = { ensureBundle = function() return romBundle end }
if not romBundle then
  package.loaded["src.core.game3.rom_text"] = {
    plain = function(key, ctx)
      local d = ctx and ctx.dynamic
      if d and d[0] then return key .. ":" .. d[0] end
      return key
    end,
    ascii = function(key) return key end, has = function() return true end,
    ir = function(key) return { { t = "text", s = key } } end,
    key = function(n, i, j) return j and (n .. "[" .. i .. "][" .. j .. "]") or (n .. "[" .. i .. "]") end,
    lazy = function(t) return t end,
  }
end
local RomText = require("src.core.game3.rom_text")

local session = { name = "RED", gender = 0, trainerId = 0x1234 }
local saves = 0
local game = { session = session, saveGame = function() saves = saves + 1 return true end }
package.loaded["src.core.game3.runtime"] = {
  getSession = function() return session end,
  isActive = function() return true end,
  _game = game,
}

local Chat = require("src.core.game3.link.chat")
if not romBundle then
  Chat._rows = {}
  local ascii = { "ABCDE", "FGHIJ", "KLMNO", "PQRST", "UVWXY", "Z    ", "01234", "56789", ".,!? ", "-/&  " }
  for i, key in ipairs(Chat.KEYBOARD[0]) do Chat._rows[key] = Chat.tokens(ascii[i]) end
  for i, key in ipairs(Chat.KEYBOARD[1]) do Chat._rows[key] = Chat.tokens(ascii[i]:lower()) end
  for _, key in ipairs(Chat.KEYBOARD[2]) do Chat._rows[key] = Chat.tokens("{EMOJI_HAPPY}{EMOJI_ANGRY}:;.") end
end

local function channel(seat, players)
  local ch = { relay = true, sent = {}, inbox = {}, isClosed = false, left = false }
  ch.playerList = players or { { seat = 0, name = "RED" }, { seat = 1, name = "BLUE" } }
  function ch:send(msg) self.sent[#self.sent + 1] = msg end
  function ch:take(t)
    for i, m in ipairs(self.inbox) do
      if m.type == t then return table.remove(self.inbox, i) end
    end
    return nil
  end
  function ch:seat() return seat end
  function ch:players() return self.playerList end
  function ch:closed() return self.isClosed end
  function ch:leave() self.left = true end
  function ch:push(fromSeat, msg)
    msg.seat = fromSeat
    self.inbox[#self.inbox + 1] = msg
  end
  function ch:last(t)
    for i = #self.sent, 1, -1 do
      if self.sent[i].type == t then return self.sent[i] end
    end
    return nil
  end
  return ch
end

local input = { pressed = {}, down = {} }
function input:wasPressed(k) return self.pressed[k] == true end
function input:isDown(k) return self.down[k] == true end
local function press(k)
  input.pressed = { [k] = true }
  input.down = { [k] = true }
  Chat.handleInput(input)
  input.pressed, input.down = {}, {}
  Chat.update(1 / 60)
end
local function frames(n)
  for _ = 1, n do Chat.update(1 / 60) end
end

print("[test] 1. the wire form keeps emoji as one character each")
local toks = { "H", "I", "{EMOJI_HAPPY}", "é", "…" }
local wire = Chat.encode(toks)
eq(#Chat.tokens(wire), 5, "five code points on the wire")
local back = Chat.decode(wire)
eq(table.concat(back, ","), table.concat(toks, ","), "and back")
local hostile = Chat.decode("{COLOR RED}HI\252\19\42" .. string.rep("X", 20))
eq(hostile[1], "H", "tags other than emoji are dropped")
check(#hostile <= Chat.MAX_LENGTH, "and a line never exceeds 15 characters")
eq(Chat.cleanName("{PLAYER}BLUE12345"), "BLUE123", "names are 7 plain characters")
eq(Chat.caseOf("a"), "A", "a <-> A")
eq(Chat.caseOf("é"), "É", "é <-> É")
eq(Chat.caseOf("1"), nil, "digits do not toggle")

print("[test] 2. starting announces the player and loads the registered phrases")
local ch = channel(1)
local done
check(Chat.start({ channel = ch, screen = false, onDone = function(r) done = r end }), "chat starts")
eq(Chat.seat, 1, "seat 1")
local hello = ch:last("game3_union_hello")
eq(hello and hello.name, "RED", "CHAT_MESSAGE_JOIN carries the name")
eq(#Chat.registered, 10, "ten registered phrases")
if romBundle then
  eq(Chat.registered[1], RomText.plain("gText_Hello"), "the cart's defaults (UnionRoomChat_InitializeRegisteredTexts)")
end

print("[test] 3. typing from the keyboard, deleting, toggling case, sending")
press("a")
eq(table.concat(Chat.buffer), "A", "A types the key under the cursor")
press("right")
press("a")
eq(table.concat(Chat.buffer), "AB", "right moves one column")
press("r")
eq(table.concat(Chat.buffer), "Ab", "R toggles the last letter's case")
check(Chat.canToggleCase(), "the A<->a icon shows")
press("b")
eq(table.concat(Chat.buffer), "A", "B deletes")
for _ = 1, 20 do press("a") end
eq(#Chat.buffer, Chat.MAX_LENGTH, "the buffer stops at 15 characters")
press("start")
local line = ch:last("game3_chat_line")
eq(line and Chat.decode(line.text)[1], "A", "START sends the line")
eq(line and #Chat.tokens(line.text), 15, "all 15 characters")
eq(#Chat.buffer, 0, "and clears the buffer")
eq(#Chat.lines, 1, "the player's own line is in the log")
eq(Chat.lines[1].seat, 1, "in its seat colour")

print("[test] 4. joins, lines and leaves from other seats")
ch:push(0, { type = "game3_union_hello", name = "BLUE", gender = 0, trainerId = 2, activity = 0x45 })
ch:push(0, { type = "game3_chat_line", name = "BLUE", text = "HELLO" })
Chat.update(1 / 60)
eq(#Chat.lines, 3, "a join line and a chat line")
eq(Chat.lines[2].text, Chat.joinedLine("BLUE"), "gText_F700JoinedChat")
check(Chat.lines[3].text:sub(-6) == ":HELLO", "BLUE: HELLO")
eq(Chat.lines[3].seat, 0, "leader colour")
ch.playerList[3] = { seat = 2, name = "GOLD" }
ch:push(2, { type = "game3_union_hello", name = "GOLD", gender = 0, trainerId = 3, activity = 0x45 })
Chat.update(1 / 60)
eq(Chat.members[2], "GOLD", "a third trainer joins the running chat")
table.remove(ch.playerList, 3)
Chat.update(1 / 60)
eq(Chat.lines[#Chat.lines].text, Chat.leftLine("GOLD"), "a seat gone from the room left the chat")
check(Chat.exitType == nil, "the chat keeps going")
for i = 1, 12 do ch:push(0, { type = "game3_chat_line", name = "BLUE", text = "L" .. i }) end
Chat.update(1 / 60)
check(#Chat.lines < Chat.MAX_LINES, "the log keeps the last rows")
check(Chat.scroll ~= nil, "and scrolls")
frames(3)
eq(Chat.scroll, nil, "three 5 px steps")

print("[test] 5. SELECT swaps pages; the REGISTER page registers the last 10 characters")
press("select")
eq(Chat.routine, "switch", "the swap menu")
eq(Chat.swap and Chat.swap.cursor, Chat.PAGE.UPPER, "on the current page")
press("select")
eq(Chat.swap and Chat.swap.cursor, Chat.PAGE.LOWER, "SELECT moves the cursor")
press("a")
check(Chat.slide ~= nil, "the keyboard slides out")
frames(12)
eq(Chat.page, Chat.PAGE.LOWER, "and in on LOWER")
eq(Chat.slide, nil, "slide finished")
press("a")
eq(Chat.buffer[1], "a", "lower-case keys")
Chat.buffer = Chat.tokens("0123456789ABCDE")
press("select")
press("down")
press("a")
frames(12)
eq(Chat.page, Chat.PAGE.EMOJI, "EMOJI page")
press("select")
press("down")
press("a")
frames(12)
eq(Chat.page, Chat.PAGE.REGISTER, "the registered phrases page")
press("r")
eq(Chat.routine, "register", "R on the phrase page registers")
eq(Chat.msg and Chat.msg.id, "REGISTER_WHERE", "gText_RegisterTextWhere")
eq(Chat.registerStart(), 5, "only the last 10 characters register")
press("down")
press("down")
press("a")
eq(Chat.registered[3], "56789ABCDE", "row 3 now holds the text")
check(Chat.changed, "registered texts changed")
Chat.buffer = {}
press("r")
eq(Chat.routine, "input_text", "nothing to register: gText_InputText")
press("a")
eq(Chat.routine, "input", "back to typing")
Chat.row = 0
press("a")
eq(table.concat(Chat.buffer), Chat.registered[1] .. " ", "A on a phrase types it and a space")

print("[test] 6. leaving asks to save the changed phrases, then saves")
Chat.buffer = {}
press("b")
eq(Chat.routine, "quit", "B on an empty line asks to quit")
eq(Chat.msg and Chat.msg.id, "QUIT", "gText_QuitChatting")
eq(Chat.yesNo and Chat.yesNo.cursor, 1, "NO is the default")
press("up")
press("a")
eq(ch:last("game3_chat_bye") ~= nil, true, "a member leaving says CHAT_MESSAGE_LEAVE")
frames(2)
eq(Chat.routine, "ask_save", "registered texts changed: OK to save?")
press("up")
press("a")
frames(1)
eq(Chat.routine, "ask_overwrite", "already a saved file")
press("up")
press("a")
frames(3)
eq(saves, 1, "the game was saved")
eq(session.registeredTexts and session.registeredTexts[3], "56789ABCDE", "with the new phrase")
eq(Chat.msg and Chat.msg.id, "SAVED", "gText_RegisteredTextChanged_SavedTheGame")
frames(Chat.SAVED_FRAMES + 3)
eq(Chat.state, "off", "the chat closed")
eq(done, "left", "onDone reports the player left")

print("[test] 7. the leader leaving disbands the chat for everyone")
ch = channel(1)
done = nil
Chat.start({ channel = ch, screen = false, onDone = function(r) done = r end })
Chat.present[0] = true
Chat.members[0] = "BLUE"
ch:push(0, { type = "game3_chat_bye" })
Chat.update(1 / 60)
eq(Chat.exitType, "disbanded", "CHAT_MESSAGE_DISBAND")
frames(2)
eq(Chat.routine, "disbanded", "ChatEntryRoutine_Disbanded")
eq(Chat.msg and Chat.msg.id, "LEADER_LEFT", "gText_LeaderHasLeftEndingChat")
eq(Chat.hostName, "BLUE", "naming the leader")
frames(Chat.EXIT_DELAY + 3)
eq(done, "disbanded", "and the chat ends")
eq(ch:last("game3_chat_bye"), nil, "without a bye of our own")

print("[test] 8. the leader alone again exits (CHATEXIT_LEADER_LAST)")
ch = channel(0)
done = nil
Chat.start({ channel = ch, screen = false, onDone = function(r) done = r end })
Chat.update(1 / 60)
ch:push(1, { type = "game3_chat_bye" })
Chat.update(1 / 60)
eq(Chat.exitType, "leader_last", "the only member left")
frames(2)
eq(Chat.msg and Chat.msg.id, "EXITING", "gText_ExitingTheChat")
frames(Chat.EXIT_DELAY + 3)
eq(done, "leader_last", "the leader leaves too")

print("[test] 9. the leader quitting warns, then disbands")
ch = channel(0)
done = nil
Chat.start({ channel = ch, screen = false, onDone = function(r) done = r end })
Chat.update(1 / 60)
press("b")
press("up")
press("a")
frames(1)
eq(Chat.routine, "quit_leader", "If the LEADER leaves, the chat will end")
press("up")
press("a")
check(ch:last("game3_chat_bye") ~= nil, "the leader's bye disbands the room")
frames(3)
eq(done, "left", "and the leader leaves")

print("[test] 10. a dropped link ends the chat")
ch = channel(1)
done = nil
Chat.start({ channel = ch, screen = false, onDone = function(r) done = r end })
ch.isClosed = true
Chat.update(1 / 60)
check(Chat.exitType == "disbanded" or Chat.exitType == "dropped", "the room vanished")
frames(Chat.EXIT_DELAY + 3)
check(done ~= nil, "the chat closed")

print("[test] 11. a hand-edited save is cut to the cart's registered text and record limits")
local Schema = require("src.core.game3.save_schema_firered")
local longRecords = {}
for i = 1, 25 do longRecords[i] = { name = "TRAINERNAME" .. i, trainerId = 70000 + i } end
local restored = Schema.fromSaveTable({
  registeredTexts = { "ABCDEFGHIJKLMNOP", "HI{HAPPY}" },
  trainerNameRecords = longRecords,
})
eq(restored.registeredTexts[1], "ABCDEFGHIJ", "registered texts keep REGISTER_CHARS tokens")
eq(restored.registeredTexts[2], "HI{HAPPY}", "an emoji tag counts as one token")
eq(restored.registeredTexts[10], "", "all ten rows present")
eq(#restored.trainerNameRecords, 20, "trainerNameRecords[20]")
eq(restored.trainerNameRecords[1].name, "TRAINER", "names cut to PLAYER_NAME_LENGTH")
eq(restored.trainerNameRecords[1].trainerId, (70001) % 65536, "ids are u16")

Chat.reset()
if failed == 0 then
  print("[pass] union room chat")
  os.exit(0)
end
print("[fail] union room chat: " .. failed)
os.exit(1)
