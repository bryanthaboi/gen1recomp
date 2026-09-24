#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;" .. package.path
require("tests.fixture_data.game3_items").install()

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

local FakeRelay = require("tests.g3link_fake_relay")

local CENTER_MAP = "FR_TEST_POKEMON_CENTER_2F"
local MAPS = {
  [CENTER_MAP] = { warps = { { x = 9, y = 1, destMap = "FR_TRADE_CENTER", destWarp = 1 } } },
  FR_TRADE_CENTER = { warps = { { x = 5, y = 8, mapGroup = 0x7F, mapNum = 0x7F, destWarp = 128 } } },
}

local store = { flags = {}, vars = {} }
local session = {
  store = store, map = CENTER_MAP, x = 9, y = 2, name = "RED", gender = 0, trainerId = 0x1234,
  party = { { species = 1, level = 12 }, { species = 4, level = 9 } },
  bag = { pockets = { items = {} } },
}
local input = { pressed = {} }
function input:wasPressed(k) return self.pressed[k] == true end
function input:isDown(k) return self.pressed[k] == true end
local game = { data = { maps = MAPS }, session = session, input = input,
  save = { player = { name = "RED" }, options = {} } }

package.loaded["src.core.game3.runtime"] = {
  getSession = function() return session end,
  isActive = function() return true end,
  _game = game,
}
local Player = { cellX = 9, cellY = 1, facing = "up" }
package.loaded["src.core.game3.player"] = Player
package.loaded["src.core.game3.map"] = { load = function() end }

local romBundle = require("tests.game3_cache").bundle()
if not romBundle then
  package.loaded["src.core.game3.rom_text"] = {
    plain = function(key) return key end, box = function(key) return key end,
    ascii = function(key) return key end, has = function() return true end,
    ir = function(key) return { { t = "text", s = key } } end,
    key = function(n, i, j) return j and (n .. "[" .. i .. "][" .. j .. "]") or (n .. "[" .. i .. "]") end,
    at = function(n, i, j) return j and (n .. "[" .. i .. "][" .. j .. "]") or (n .. "[" .. i .. "]") end,
    count = function() return 0 end, list = function() return {} end,
    lazy = function(map) return setmetatable({}, { __index = function(_, k) return map[k] end }) end,
  }
end
local RomText = require("src.core.game3.rom_text")

local ctx = { specialVars = {}, stringVars = {} }
local adapters = { log = function() end, playSe = function() end }
package.loaded["src.core.game3.scripting.space"] = {
  store = store, mapId = CENTER_MAP, vm = { ctx = ctx, adapters = adapters },
  ensureBundle = function() return romBundle end,
}

local LIVE = { engine = 3, engineVersion = "1.0.0", fingerprint = "f00dcafe", kind = "vanilla",
  version = "firered" }
package.loaded["src.online.ArenaData"] = {
  liveProfile3 = function(_, rulesetId)
    local p = {}
    for k, v in pairs(LIVE) do p[k] = v end
    p.rulesetId = rulesetId
    return p
  end,
}
local Client = FakeRelay.client({ state = "online", id = "0000beef" })
Client._profiles = { LIVE }
package.loaded["src.online.Client"] = Client

local Natives = require("src.core.game3.scripting.natives")
local NativesLink = require("src.core.game3.scripting.natives_link")
local Multi = require("src.core.game3.scripting.multichoice")
local Link = require("src.core.game3.link")
local Union = require("src.core.game3.link.union_room")
local Flags = require("src.core.game3.scripting.flags")
local Message = require("src.ui.game3.message")
local Choice = require("src.ui.game3.choice")
local Stack = require("src.ui.game3.stack")
local Window = require("src.ui.game3.window")
local ListMenu = require("src.ui.game3.list_menu")
local PinEntry = require("src.ui.game3.pin_entry")
local LinkMenu = require("src.ui.game3.link_menu")
local Game3Link = require("src.link.Game3Link")
local Strings = require("src.core.Strings")
local Direct = LinkMenu.Direct

local function getVar(id) return tonumber(Flags.getVar(store, ctx, id)) or 0 end
local function page() return Message.isOpen() and Message.currentPage() or nil end
local function flat(s) return (tostring(s or ""):gsub("%s+", " ")) end
local function shows(text)
  local p = page()
  return p ~= nil and p ~= "" and flat(text):find(flat(p), 1, true) == 1
end
local function press(target, key)
  input.pressed = { [key] = true }
  local r = target(input)
  input.pressed = {}
  return r
end
local function tick(n)
  for _ = 1, n or 1 do
    local top = Stack.top()
    if top and top.mod and top.mod.update then top.mod.update(1 / 60) end
  end
end
local function tickMsg() for _ = 1, 400 do Message.tick() end end
local function items(n)
  local out = {}
  for i = 1, n do out[i] = { label = "ROW" .. i, id = i } end
  return out
end

print("[test] 1. ListMenu moves, scrolls and pages like list_menu.c")
local picked, cancelled, moved = nil, 0, 0
local lm = ListMenu.new({
  template = Window.template(1, 3, 17, 10), items = items(16), maxShowed = 5, rowHeight = 16,
  upTextY = 0, scrollMultiple = "dpad", sound = false,
  onSelect = function(item) picked = item.id end,
  onCancel = function() cancelled = cancelled + 1 end,
  onMove = function() moved = moved + 1 end,
})
eq(select(2, lm:selected()), 1, "starts on the first row")
eq(press(function(i) return lm:handleInput(i) end, "up"), nil, "up at the top does nothing")
for _ = 1, 3 do lm:handleInput({ wasPressed = function(_, k) return k == "down" end }) end
eq(lm.row, 3, "the cursor walks down to the middle row")
eq(lm.scroll, 0, "without scrolling")
press(function(i) return lm:handleInput(i) end, "down")
eq(lm.row, 3, "then the rows scroll under a fixed cursor")
eq(lm.scroll, 1, "one row scrolled")
eq(select(2, lm:selected()), 5, "fifth item selected")
for _ = 1, 10 do press(function(i) return lm:handleInput(i) end, "down") end
eq(lm.scroll, 11, "scroll stops at total - maxShowed")
press(function(i) return lm:handleInput(i) end, "down")
eq(lm.row, 4, "then the cursor walks to the last row")
eq(press(function(i) return lm:handleInput(i) end, "down"), nil, "and stops at the end")
eq(select(2, lm:selected()), 16, "last item")
press(function(i) return lm:handleInput(i) end, "left")
eq(select(2, lm:selected()), 11, "LEFT pages up by maxShowed (LIST_MULTIPLE_SCROLL_DPAD)")
eq(press(function(i) return lm:handleInput(i) end, "a"), "select", "A selects")
eq(picked, 11, "onSelect gets the item")
lm.items[11].disabled = true
picked = nil
eq(press(function(i) return lm:handleInput(i) end, "a"), nil, "A on a disabled row is refused")
eq(picked, nil, "no select on a disabled row")
eq(press(function(i) return lm:handleInput(i) end, "b"), "cancel", "B cancels")
eq(cancelled, 1, "onCancel ran")
check(moved > 0, "onMove fires on every change")
lm:setItems(items(3), true)
eq(lm.scroll, 0, "shrinking the list clamps the scroll")
check(lm.row <= 2, "and the cursor")
local held = { wasPressed = function() return false end, isDown = function(_, k) return k == "down" end }
lm:setItems(items(16), false)
lm:handleInput({ wasPressed = function(_, k) return k == "down" end, isDown = function(_, k) return k == "down" end })
local before = select(2, lm:selected())
for _ = 1, ListMenu.REPEAT_START - 1 do lm:handleInput(held) end
eq(select(2, lm:selected()), before, "holding does not repeat before 40 frames")
lm:handleInput(held)
eq(select(2, lm:selected()), before + 1, "then repeats (main.c keyRepeatStartDelay)")
local dx, dy = ListMenu.bounce({ bounceDir = 1, multiplier = 2, frequency = 8 }, 8)
eq(dx, 0, "vertical arrows bounce on y only")
eq(dy, 2, "by gSineTable * 2 / 256")

print("[test] 2. PinEntry scrubs, masks and confirms")
local got = "unset"
PinEntry.show({ mode = "set", onDone = function(pin) got = pin end })
check(PinEntry.isOpen() and Stack.top().id == "pin_entry", "pin_entry is the top layer")
eq(PinEntry.title, Strings("Set a 4-digit PIN."), "set title")
for _ = 1, 3 do press(PinEntry.handleInput, "up") end
eq(PinEntry.digits[1], 3, "up scrubs the digit")
press(PinEntry.handleInput, "right")
eq(PinEntry.cursor, 2, "right moves the cursor")
check(PinEntry.visited[1], "the digit left behind is masked")
press(PinEntry.handleInput, "down")
eq(PinEntry.digits[2], 9, "down wraps 0 -> 9")
press(PinEntry.handleInput, "a")
eq(PinEntry.cursor, 3, "A advances like the naming screen")
press(PinEntry.handleInput, "start")
eq(PinEntry.cursor, 4, "START jumps to the last cell")
press(PinEntry.handleInput, "up")
press(PinEntry.handleInput, "up")
press(PinEntry.handleInput, "left")
press(PinEntry.handleInput, "right")
eq(PinEntry.cursor, 4, "left/right walk the cells")
press(PinEntry.handleInput, "a")
eq(got, "3902", "A on the last cell confirms the PIN")
check(not PinEntry.isOpen(), "and closes")
PinEntry.show({ mode = "enter", onDone = function(pin) got = pin end })
eq(PinEntry.title, Strings("Enter the 4-digit PIN."), "enter title")
press(PinEntry.handleInput, "up")
PinEntry.setError(Strings("The PIN didn't match."))
eq(PinEntry.digits[1], 0, "an error resets the digits")
eq(PinEntry.error, Strings("The PIN didn't match."), "and shows the line")
press(PinEntry.handleInput, "b")
eq(got, nil, "B cancels with nil")

print("[test] 3. the JOIN/LEAD override is registered and gated")
eq(Multi.OVERRIDES and Multi.OVERRIDES[63], Union.directModes, "OVERRIDES[MULTICHOICE_JOIN_OR_LEAD]")
local sel
local function done(v) sel = v end
Flags.setVar(store, ctx, Link.VAR_0x8004, Union.LINK_GROUP.BERRY_CRUSH)
eq(Union.directModes(ctx, {}, done), false, "groups 4..6 keep the cart's JOIN / LEAD")
Client._state = "offline"
Flags.setVar(store, ctx, Link.VAR_0x8004, Union.LINK_GROUP.TRADE)
eq(Union.directModes(ctx, {}, done), false, "no adapter keeps the cart's JOIN / LEAD")
Client._state = "online"

print("[test] 4. AUTO / CHOOSE / SET PIN / EXIT")
Message.show("CHOOSE A LEADER", { stay = true, speed = 0 })
eq(Union.directModes(ctx, {}, done), true, "the override takes the multichoice")
check(Direct.isOpen() and Direct.view == "modes", "AUTO / CHOOSE / SET PIN / EXIT is up")
local MODES_PROMPT = Strings("AUTO or CHOOSE finds a partner.\nSET PIN hosts a private room.")
check(shows(MODES_PROMPT), "the prompt names the new choices, not JOIN GROUP")
eq(#Direct.modes.items, 4, "four rows")
eq(Direct.modes.items[1].label, Strings("AUTO"), "AUTO")
eq(Direct.modes.items[3].label, Strings("SET PIN"), "SET PIN")
eq(Direct.modes.template.left, 20, "at sWindowTemplate_InviteToActivity left 20")
eq(Direct.modes.template.top, 6, "top 6")
press(Direct.handleInput, "a")
eq(sel, 0, "AUTO answers JOIN (0)")
eq(Union.direct.mode, "auto", "mode auto")
check(not Direct.isOpen(), "the box closes")

sel = nil
Union.directModes(ctx, {}, done)
press(Direct.handleInput, "down")
press(Direct.handleInput, "a")
eq(sel, 0, "CHOOSE answers JOIN (0)")
eq(Union.direct.mode, "choose", "mode choose")

sel = nil
Union.directModes(ctx, {}, done)
for _ = 1, 3 do press(Direct.handleInput, "down") end
press(Direct.handleInput, "a")
eq(sel, 2, "EXIT answers 2")
sel = nil
Union.directModes(ctx, {}, done)
press(Direct.handleInput, "b")
eq(sel, 127, "B answers SCR_MENU_CANCEL")

sel = nil
Message.show("CHOOSE A LEADER", { stay = true, speed = 0 })
Union.directModes(ctx, {}, done)
press(Direct.handleInput, "down")
press(Direct.handleInput, "down")
press(Direct.handleInput, "a")
check(PinEntry.isOpen() and PinEntry.mode == "set", "SET PIN opens the PIN entry in set mode")
check(not Message.isOpen(), "the leader text steps aside for the PIN title")
press(PinEntry.handleInput, "b")
check(Direct.view == "modes" and not PinEntry.isOpen(), "B goes back to the mode box")
eq(select(2, Direct.modes:selected()), 3, "on SET PIN")
check(shows(MODES_PROMPT), "with the mode prompt back")
press(Direct.handleInput, "a")
PinEntry.digits = { 0, 4, 2, 0 }
PinEntry.cursor = 4
press(PinEntry.handleInput, "a")
check(shows(Strings("Use this PIN?")), "Use this PIN?")
tickMsg()
tick()
check(Choice.isOpen(), "YES/NO")
press(Direct.handleInput, "a")
check(shows(Strings("Let AUTO players join?")), "Let AUTO players join?")
tickMsg()
tick()
press(Direct.handleInput, "down")
press(Direct.handleInput, "a")
eq(sel, 1, "SET PIN answers LEAD (1)")
eq(Union.direct.mode, "pin", "mode pin")
eq(Union.direct.pin, "0420", "with the PIN")
eq(Union.direct.auto, false, "AUTO players kept out")
check(not Direct.isOpen() and not Choice.isOpen(), "everything closed")

print("[test] 5. SET PIN queues a locked room and shows the link count")
ctx.nativePoll, ctx.stateWait = nil, nil
Natives.special(ctx, NativesLink.SPECIAL.TryBecomeLinkLeader, adapters)
local q = Client.last("queueDirect")[1]
eq(q and q.pin, "0420", "queueDirect carries the PIN")
eq(q and q.auto, false, "and auto false")
check(Direct.isOpen() and Direct.view == "wait", "the wait layer is up")
local hostRoom = FakeRelay.room({ seats = 2, intent = "trade", stage = "waiting", match = false })
hostRoom.match = nil
Client.bindRoom(hostRoom, 0)
tick()
eq(Direct.count, 2, "UpdateLinkPlayerCountDisplay sees the room's players")
input.pressed = { b = true }
Direct.handleInput(input)
input.pressed = {}
eq(ctx.nativePoll(), true, "B gives up hosting")
eq(getVar(Link.VAR_RESULT), Link.LINKUP.FAILED, "LINKUP_FAILED")
Client.bindRoom(nil, nil)
Message.reset()

print("[test] 6. CHOOSE lists trainers and rooms, locked rooms take a PIN")
local ROOM_ID = "r00000000000000a1"
Client._directEntries.trade = {
  { kind = "player", id = "aaaa0001", name = "BLUE", since = 1,
    avatar = { name = "BLUE", trainerId = 0x2222, gender = 0, version = "leafgreen" } },
  { kind = "room", room = ROOM_ID, host = "aaaa0002", name = "GREEN", locked = true, auto = false,
    seats = 2, players = 1, since = 2, avatar = { name = "GREEN", trainerId = 3, gender = 1 } },
}
Union.direct = { mode = "choose" }
ctx.nativePoll, ctx.stateWait = nil, nil
local y = Natives.special(ctx, NativesLink.SPECIAL.TryJoinLinkGroup, adapters)
eq(y, true, "the script waits")
local dl = Client.last("directList")
eq(dl and dl[1], "trade", "directList trade")
eq(dl and dl[2] and dl[2].rulesetId, "g3_link", "with the g3_link profile")
check(Direct.isOpen() and Direct.view == "choose", "the group list is up")
check(shows(RomText.ascii(RomText.key("gTexts_UR_ChooseTrainer", 3))), "Please choose the TRAINER to trade with.")
eq(#Direct.list.items, 16, "sixteen numbered slots like the cart")
eq(Direct.list.template.left, 1, "sWindowTemplate_GroupList left 1")
eq(Direct.list.template.w, 17, "17 wide")
eq(Direct.list.maxShowed, 5, "5 rows")
local r1, r2 = Direct.list.items[1].row, Direct.list.items[2].row
eq(r1 and r1.name, "BLUE", "slot 1 is the AUTO trainer")
eq(r1 and r1.trainerId, 0x2222, "with the trainer id")
eq(r2 and r2.locked, true, "slot 2 is the locked room")
check(Direct.list.items[3].disabled, "empty slots are refused")
eq(Direct.me and Direct.me.name, "RED", "own name in PlayerNameAndId")
local nameC = Direct.rowColors(r1)
eq(nameC, require("src.ui.game3.frlg_font").COLOR.GREEN, "a new row prints green (newPlayerCountdown)")
tick(Direct.NEW_FRAMES + 1)
nameC = Direct.rowColors(r1)
eq(nameC, require("src.ui.game3.frlg_font").COLOR.MALE_NPC, "then in its gender colour")
eq(Direct.rowColors(r2), ListMenu.COLOR_WHITE, "the locked room prints white")

table.insert(Client._directEntries.trade, 1, { kind = "player", id = "aaaa0009", name = "GOLD", since = 0,
  avatar = { name = "GOLD", trainerId = 9, gender = 0 } })
tick(Direct.REFRESH_FRAMES)
eq(Direct.list.items[1].row.name, "BLUE", "rows are sticky")
eq(Direct.list.items[3].row and Direct.list.items[3].row.name, "GOLD", "a newcomer takes the lowest free slot")
table.remove(Client._directEntries.trade, 1)
tick(Direct.REFRESH_FRAMES)
eq(Direct.list.items[3].row, nil, "a leaver frees its slot")

press(Direct.handleInput, "down")
press(Direct.handleInput, "a")
check(PinEntry.isOpen() and PinEntry.mode == "enter", "a locked room asks for the PIN")
PinEntry.digits = { 1, 2, 3, 4 }
PinEntry.confirm()
local jr = Client.last("joinRoom")
eq(jr and jr[1], ROOM_ID, "room_join on the room id")
eq(jr and jr[2], "player", "as a player")
eq(jr and jr[4], "1234", "with the PIN")
check(Direct.frozen, "the list is frozen while joining")
Client.pendings[#Client.pendings].done = true
Client.pendings[#Client.pendings].reason = "bad_pin"
tick()
check(not PinEntry.isOpen(), "a wrong PIN closes the entry")
check(Direct.notice and shows(Strings("The PIN didn't match.")), "with The PIN didn't match.")
tickMsg()
press(Direct.handleInput, "a")
check(not Direct.frozen and not Direct.notice, "then fades back to the list")
check(shows(RomText.ascii(RomText.key("gTexts_UR_ChooseTrainer", 3))), "with the choose text")
press(Direct.handleInput, "a")
check(PinEntry.isOpen() and PinEntry.mode == "enter", "the locked room asks again")
PinEntry.digits = { 4, 3, 2, 1 }
PinEntry.confirm()
Client.pendings[#Client.pendings].done = true
Client.pendings[#Client.pendings].reason = "pin_locked"
tick()
check(shows(Strings("Too many tries. Please try again later.")), "five wrong tries lock the room")
tickMsg()
press(Direct.handleInput, "a")
check(not Direct.frozen and not Direct.notice, "back on the list")
check(shows(RomText.ascii(RomText.key("gTexts_UR_ChooseTrainer", 3))), "with the choose text")

print("[test] 7. CHOOSE on a trainer invites; the match walks into the Trade Center")
press(Direct.handleInput, "up")
press(Direct.handleInput, "a")
local inv = Client.last("invite")
eq(inv and inv[1], "aaaa0001", "invite the AUTO trainer")
eq(inv and inv[2], "trade", "for a trade")
eq(inv and inv[3] and inv[3].ruleset, "g3_link", "with the ruleset")
check(shows(RomText.ascii("gText_UR_AwaitingPlayersResponse", { stringVars = { "BLUE" } })),
  "Awaiting BLUE's response...")
local h = Client.handles[#Client.handles]
h.state, h.why = "closed", "busy"
tick()
check(Direct.notice, "a refused invite prints a notice")
check(shows(RomText.ascii("gText_UR_TrainerAppearsBusy")), "The TRAINER appears to be busy")
tickMsg()
press(Direct.handleInput, "a")
press(Direct.handleInput, "a")
h = Client.handles[#Client.handles]
h.state, h.why = "accepted", "accepted"
local room = FakeRelay.room({ seats = 2, intent = "trade" })
Client.bindRoom(room, 1)
tick()
check(not Direct.isOpen(), "the list closes on match_start")
eq(ctx.nativePoll(), true, "the script resumes")
eq(getVar(Link.VAR_RESULT), Link.LINKUP.SUCCESS, "LINKUP_SUCCESS")
check(Link.link ~= nil and Link.link.seat == 1, "the link attaches at seat 1")
eq(Link.link and Link.link.linkType, Game3Link.LINKTYPE.TRADE_SETUP, "as a trade link")
eq(Client.last("directList")[1], nil, "the list subscription stops")
check(type(ctx.stateWait) == "function", "the Trade Center warp is armed")
Link.reset()
Client.bindRoom(nil, nil)

print("[test] 8. B leaves CHOOSE; multi lists rooms only")
Client._directEntries.battle_multi = {
  { kind = "player", id = "aaaa0001", name = "BLUE", avatar = { name = "BLUE" } },
  { kind = "room", room = ROOM_ID, host = "aaaa0002", name = "GREEN", avatar = { name = "GREEN" } },
}
local rows = Union.directRows("battle_multi")
eq(#rows, 1, "multi CHOOSE lists rooms only")
eq(rows[1].kind, "room", "the room")
Union.direct = { mode = "choose" }
Flags.setVar(store, ctx, Link.VAR_0x8004, Union.LINK_GROUP.MULTI_BATTLE)
ctx.nativePoll, ctx.stateWait = nil, nil
Natives.special(ctx, NativesLink.SPECIAL.TryJoinLinkGroup, adapters)
check(shows(RomText.ascii(RomText.key("gTexts_UR_ChooseTrainer", 2))), "Please choose the LEADER for a MULTI BATTLE.")
press(Direct.handleInput, "b")
eq(ctx.nativePoll(), true, "B resumes the script")
eq(getVar(Link.VAR_RESULT), Link.LINKUP.FAILED, "LINKUP_FAILED back to the menu")
eq(Client.status, "busy", "presence back to busy")
check(not Direct.isOpen() and not Message.isOpen(), "all closed")

print("[test] 9. a CHOOSE joiner seated in a half-full MULTI room can leave with B")
local MULTI_ROOM = "r00000000000000b2"
local function joinMulti()
  Client._directEntries.battle_multi = {
    { kind = "room", room = MULTI_ROOM, host = "aaaa0002", name = "GREEN", locked = false, auto = false,
      seats = 4, players = 1, since = 1, avatar = { name = "GREEN", trainerId = 3, gender = 1 } },
  }
  Union.direct = { mode = "choose" }
  Flags.setVar(store, ctx, Link.VAR_0x8004, Union.LINK_GROUP.MULTI_BATTLE)
  Flags.setVar(store, ctx, Link.VAR_RESULT, 0)
  ctx.nativePoll, ctx.stateWait = nil, nil
  Natives.special(ctx, NativesLink.SPECIAL.TryJoinLinkGroup, adapters)
  tick(Direct.NEW_FRAMES + 1)
  press(Direct.handleInput, "a")
  eq(Client.last("joinRoom") and Client.last("joinRoom")[1], MULTI_ROOM, "A on GREEN's room sends room_join")
end
joinMulti()
local leaves = Client.count("leaveRoom")
press(Direct.handleInput, "b")
tick(2)
eq(ctx.nativePoll(), false, "B while the join is pending does nothing")
eq(Client.count("leaveRoom"), leaves, "and does not leave")
Client.pendings[#Client.pendings].done = true
local waitingMulti = FakeRelay.room({ id = MULTI_ROOM, seats = 4, intent = "battle_multi", stage = "waiting" })
waitingMulti.match = nil
Client.bindRoom(waitingMulti, 1)
tick(10)
eq(ctx.nativePoll(), false, "seated in GREEN's room, waiting for two more players")
press(Direct.handleInput, "b")
tick(2)
eq(ctx.nativePoll(), true, "B gets the player out of the half-full room")
eq(getVar(Link.VAR_RESULT), Link.LINKUP.FAILED, "LINKUP_FAILED back to the attendant")
eq(Client.count("leaveRoom"), leaves + 1, "the relay room is left")
eq(Client.status, "busy", "presence back to busy")
check(not Direct.isOpen() and not Message.isOpen(), "all closed")
Client.bindRoom(nil, nil)

joinMulti()
Client.pendings[#Client.pendings].done = true
Client.bindRoom(waitingMulti, 1)
tick(10)
Client.bindRoom(nil, nil)
tick(2)
check(Direct.notice and shows(RomText.ascii(RomText.key("gTexts_UR_PlayerDisconnected", 2))),
  "the room closing under a seated joiner: The other TRAINER appears unavailable")
tickMsg()
press(Direct.handleInput, "a")
tick(2)
check(Direct.view == "choose" and not Direct.frozen and Direct.onLeave == nil, "and puts the list back")
press(Direct.handleInput, "b")
eq(ctx.nativePoll(), true, "B then leaves CHOOSE")

if failed > 0 then
  print("[FAIL] direct corner: " .. failed .. " failed")
  os.exit(1)
end
print("[pass] direct corner")
