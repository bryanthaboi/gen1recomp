package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
love = love or require("tests.love_stub")

local OnlinePanel = require("src.import.OnlinePanel")
local Connect = require("src.online.Connect")
local Client = require("src.online.Client")
local Kit = require("src.ui.kit.Kit")
local Layout = require("src.ui.kit.Layout")
local Transition = require("src.ui.kit.Transition")
local Icons = require("src.ui.kit.Icons")
local VirtualKeyboard = require("src.ui.kit.VirtualKeyboard")
local DiscordPresence = require("src.core.DiscordPresence")

local function patch(tbl, fields)
  local keys, saved = {}, {}
  for k, v in pairs(fields) do
    keys[#keys + 1] = k
    saved[k] = tbl[k]
    tbl[k] = v
  end
  return function()
    for _, k in ipairs(keys) do tbl[k] = saved[k] end
  end
end

local function newImp(ready)
  return { ready = ready or { red = true }, activeSlot = {}, slots = {},
    pulse = 0, _pages = {}, _uiActions = {}, _actAt = {} }
end

local RED_PROFILE = { engine = 1, version = "red", kind = "vanilla",
  fingerprint = "abc", rule = { partySize = 1 } }

local function setUp(imp)
  local st = OnlinePanel.state(imp)
  st.version, st.slotId, st.setupDone = "red", "slot1", true
  st.team = { { where = "party", index = 1 } }
  st.profiles["red|vanilla|-"] = { profile = RED_PROFILE }
  local SAVE = { party = { { species = "PIKACHU", level = 20, moves = {} } } }
  st.slotRead = { key = "red|slot1|-",
    data = { generation = 1, party = SAVE.party, save = SAVE } }
  return st
end

local function drawWith(fn, width, height)
  Kit.layout(width or 1280, height or 800)
  Kit.beginFrame(-1, -1, false, 0)
  local m = Layout.metrics(1200)
  local ok, res = pcall(fn, m)
  Kit.endFrame()
  if not ok then print(res) end
  return ok, res, m
end

do
  local want = { lock = true, ["lock-open"] = true, mail = true }
  for _, name in ipairs(Icons.NAMES) do want[name] = nil end
  T.eq(next(want), nil, "the atlas names lock, lock-open and mail")
  local f = io.open("assets/launcher/lucide/icons.png", "rb")
  local head = f and f:read(24) or ""
  if f then f:close() end
  local b1, b2, b3, b4 = head:byte(17, 20)
  local width = ((b1 or 0) * 16777216) + ((b2 or 0) * 65536)
    + ((b3 or 0) * 256) + (b4 or 0)
  T.eq(width, #Icons.NAMES * 96, "and the atlas has one 96px cell per name")
end

T.eq(OnlinePanel.sanitizePin("12a3 4567"), "1234", "a PIN keeps four digits")
T.eq(OnlinePanel.sanitizePin("x"), "", "and nothing else")
T.check(OnlinePanel.pinValid("0000"), "0000 is a valid PIN")
T.check(not OnlinePanel.pinValid("123"), "three digits is not")
T.check(not OnlinePanel.pinValid("12a4"), "letters are not")

do
  Connect.reset()
  local sentProfiles, sentPresence, connected = nil, nil, nil
  local restore = patch(Client, {
    state = function() return "online" end,
    setProfiles = function(list) sentProfiles = list return list end,
    setPresence = function(p) sentPresence = p return true end,
    connect = function(opts) connected = opts return true end,
  })
  local ok = Connect.start({ source = "game", version = "firered",
    profiles = { { version = "firered" } },
    presence = { where = "game", status = "busy", version = "firered" } })
  T.check(ok, "Connect.start while online answers true")
  T.eq(connected, nil, "without a second hello")
  T.eq(sentProfiles and sentProfiles[1].version, "firered",
    "it only swaps the profiles")
  T.eq(sentPresence and sentPresence.where, "game", "and the presence")
  restore()
end

do
  Connect.reset()
  local connected, configured = nil, nil
  local restoreLinked = patch(Connect, { linked = function() return false end,
    storedName = function() return "RED#417" end,
    persistName = function() return true end })
  local restore = patch(Client, {
    state = function() return "offline" end,
    configure = function(opts)
      if opts and opts.relayAddress then configured = opts.relayAddress end
      return configured
    end,
    connect = function(opts) connected = opts return true end,
  })
  T.check(Connect.start({ source = "launcher", version = "red",
    profiles = { RED_PROFILE },
    presence = { where = "launcher", status = "idle", version = "red" },
    relayAddress = "127.0.0.1:17999" }), "an offline start connects")
  T.eq(configured, "127.0.0.1:17999", "on the relay address it was given")
  T.eq(connected and connected.name, "RED#417", "with the stored name")
  T.eq(connected and connected.presence and connected.presence.where,
    "launcher", "announcing where the player is")
  T.eq(connected and connected.profiles and connected.profiles[1], RED_PROFILE,
    "and the profiles")
  T.eq(Connect.name(), "RED#417", "Connect.name reports it")
  restore()
  restoreLinked()
end

do
  Connect.reset()
  local connected = nil
  local polls = 0
  local sync = {
    lobbyTicket = function(_, name) return { name = name } end,
    poll = function()
      polls = polls + 1
      if polls < 2 then return { status = "pending" } end
      return { status = "ok", data = { ticket = "tk1", expiresAt = 9e12 } }
    end,
    release = function() end,
  }
  local restoreLinked = patch(Connect, { linked = function() return true end,
    storedName = function() return "BLUE#222" end,
    persistName = function() return true end })
  local restore = patch(Client, {
    state = function() return "offline" end,
    configure = function() return "127.0.0.1:1" end,
    connect = function(opts) connected = opts return true end,
  })
  T.check(Connect.start({ source = "launcher", syncClient = sync }),
    "a linked player asks for a ticket first")
  T.eq(Connect.state(), "ticket", "and Connect says so")
  T.check(Connect.busy(), "which counts as busy")
  T.eq(connected, nil, "nothing is dialled yet")
  Connect.update(0)
  T.eq(connected, nil, "while the ticket is pending")
  Connect.update(0)
  T.eq(connected and connected.ticket, "tk1", "then the hello carries the ticket")
  T.eq(Connect.ticketState(), "ok", "and the ticket is kept")
  restore()
  restoreLinked()
end

do
  local restore = patch(Client, {
    upgradeRequired = function() return { text = "Please update." } end,
    state = function() return "error" end,
  })
  T.eq(Connect.error(), "Please update.", "upgrade_required text is the error")
  Client.upgradeRequired = function() return {} end
  T.eq(Connect.error(), "This build is too old for online play. Please update.",
    "with a clear line when the relay sends none")
  restore()
  local ok, why = Connect.setName("ab")
  T.check(not ok, "a two-letter name is refused")
  T.eq(why, "Names are 3 to 16 characters.", "saying why")
end

do
  local imp = newImp({ red = true, firered = true })
  T.eq(OnlinePanel.gameName("firered"), "FireRed", "rows say FireRed")
  T.eq(OnlinePanel.gameName("leafgreen"), "LeafGreen", "and LeafGreen")
  T.eq(OnlinePanel.whereText({ where = "union" }), "Union Room",
    "a Union Room trainer is shown there")
  T.eq(OnlinePanel.whereText({ where = "direct" }), "Direct Corner",
    "and a Direct Corner one")
  local row = OnlinePanel.playerRow(imp, { id = "a1", name = "LEAF", engine = 3,
    version = "leafgreen", where = "union", status = "idle", online = true }, "me")
  T.eq(row.reason, nil, "an idle FireRed-engine trainer can be invited")
  T.eq(row.engine, 3, "on engine 3")
  local busy = OnlinePanel.playerRow(imp, { id = "a2", name = "X", engine = 1,
    version = "red", where = "game", status = "busy" }, "me")
  T.check(busy.reason ~= nil, "a trainer inside a game cannot be")
  local gold = OnlinePanel.playerRow(imp, { id = "a3", name = "G", engine = 2,
    version = "gold", where = "launcher", status = "idle" }, "me")
  T.check(gold.reason ~= nil, "nor one whose game this machine lacks")
  T.check(OnlinePanel.entryPasses("gen3", { engine = 3 }), "the Gen 3 chip")
  T.check(not OnlinePanel.entryPasses("gen1", { engine = 3 }),
    "Gen 1 no longer swallows Gen 3")
  local found = false
  for _, f in ipairs(OnlinePanel.FILTERS) do
    if f.id == "gen3" then found = true end
  end
  T.check(found, "FILTERS gains a Gen 3 chip")
end

do
  local imp = newImp()
  local st = setUp(imp)
  local ROOM = "r00000000000000aa"
  local joins = {}
  local pending
  local now = 1000
  local restore = patch(Client, {
    joinRoom = function(room, as, profile, pin)
      joins[#joins + 1] = { room = room, as = as, pin = pin }
      pending = { id = room, done = false }
      return pending
    end,
    serverTime = function() return now end,
    setProfiles = function(list) return list end,
    room = function() return nil end,
    tournament = function() return nil end,
    lobby = function() return {} end,
  })
  OnlinePanel.go(imp, "play")
  T.check(OnlinePanel.startJoin(imp, { room = ROOM, locked = true,
    name = "BLUE" }), "joining a locked row")
  T.check(OnlinePanel.pinModal(imp) ~= nil, "opens the PIN modal")
  T.eq(imp._onlineFocus, OnlinePanel.PIN_FIELD, "with the field focused")
  T.eq(#joins, 0, "and sends nothing yet")
  OnlinePanel.fieldType(imp, OnlinePanel.PIN_FIELD, "12a")
  T.eq(OnlinePanel.pinModal(imp).pin, "12", "the field takes digits only")
  T.check(not OnlinePanel.pinSubmit(imp), "two digits do not submit")
  T.eq(OnlinePanel.pinModal(imp).error, "A PIN is 4 digits.", "saying why")
  OnlinePanel.fieldType(imp, OnlinePanel.PIN_FIELD, "3456")
  T.eq(OnlinePanel.pinModal(imp).pin, "1234", "and stops at four")
  OnlinePanel.fieldBack(imp, OnlinePanel.PIN_FIELD)
  OnlinePanel.fieldType(imp, OnlinePanel.PIN_FIELD, "9")
  T.check(OnlinePanel.pinSubmit(imp), "ENTER sends the join")
  T.eq(joins[1] and joins[1].pin, "1239", "carrying the PIN")
  T.eq(joins[1] and joins[1].room, ROOM, "for the listed room")
  T.eq(OnlinePanel.pinModal(imp), nil, "the modal closes")
  T.eq(OnlinePanel.screen(imp), "room", "and the Room screen waits")

  pending.error, pending.reason, pending.triesLeft, pending.done =
    "Wrong PIN.", "bad_pin", 3, true
  OnlinePanel.update(imp, 1 / 60)
  local mo = OnlinePanel.pinModal(imp)
  T.check(mo ~= nil, "a wrong PIN brings the modal back")
  T.eq(mo and mo.error, "That PIN didn't match. 3 tries left.",
    "with a one-line error")
  T.eq(OnlinePanel.screen(imp), "play", "over the list")
  T.eq(mo and mo.pin, "1239", "the field keeps the PIN that missed")
  T.check(OnlinePanel.pinFailed(imp, { reason = "bad_pin", triesLeft = 1 }),
    "a last miss reopens the modal")
  T.eq(OnlinePanel.pinModal(imp).error, "That PIN didn't match. 1 try left.",
    "saying try, not tries")
  OnlinePanel.fieldBack(imp, OnlinePanel.PIN_FIELD)
  OnlinePanel.fieldBack(imp, OnlinePanel.PIN_FIELD)
  OnlinePanel.fieldBack(imp, OnlinePanel.PIN_FIELD)
  OnlinePanel.fieldBack(imp, OnlinePanel.PIN_FIELD)
  OnlinePanel.fieldType(imp, OnlinePanel.PIN_FIELD, "0000")
  OnlinePanel.pinSubmit(imp)
  T.eq(#joins, 2, "a second try goes out")
  T.eq(joins[2] and joins[2].pin, "0000", "with the retyped PIN")
  pending.error, pending.reason, pending.retryAt, pending.done =
    "Locked.", "pin_locked", now + 600000, true
  OnlinePanel.update(imp, 1 / 60)
  T.check(OnlinePanel.pinLocked(imp), "five misses lock the room")
  T.eq(OnlinePanel.pinModal(imp).error, "Too many tries. Try again in 10 min.",
    "and the modal says for how long")
  OnlinePanel.fieldType(imp, OnlinePanel.PIN_FIELD, "1111")
  T.check(not OnlinePanel.pinSubmit(imp), "ENTER stays off while locked")
  T.eq(#joins, 2, "nothing more is sent")
  now = now + 600001
  T.check(not OnlinePanel.pinLocked(imp), "the lockout ends on the relay clock")

  local ok = drawWith(function(m)
    return require("src.import.online.PinModal").draw(imp, m)
  end)
  T.check(ok, "the PIN modal draws")
  T.check(OnlinePanel.back(imp), "Back closes the modal")
  T.eq(OnlinePanel.pinModal(imp), nil, "and it is gone")
  restore()
  OnlinePanel.home(imp)
end

do
  local imp = newImp({ red = true, firered = true })
  local st = setUp(imp)
  local invites, replies = {}, {}
  local restore = patch(Client, {
    invite = function(to, activity, detail, profile)
      local h = { to = to, activity = activity, state = "sending" }
      invites[#invites + 1] = { to = to, activity = activity, detail = detail,
        profile = profile, handle = h }
      return h
    end,
    replyInvite = function(id, accept)
      replies[#replies + 1] = { id = id, accept = accept }
      return true
    end,
    serverTime = function() return 5000 end,
    setProfiles = function(list) return list end,
    room = function() return nil end,
    tournament = function() return nil end,
  })
  local gen1 = OnlinePanel.activitiesFor(imp, { engine = 1 })
  T.eq(table.concat(gen1, ","), "battle_single,trade",
    "a Gen 1 trainer can be asked to battle or trade")
  local gen3 = OnlinePanel.activitiesFor(imp, { engine = 3 })
  T.eq(table.concat(gen3, ","), "battle_single,battle_double,trade",
    "a Gen 3 trainer also gets a double battle")
  T.eq(#OnlinePanel.activitiesFor(imp, { engine = 2 }), 0,
    "a game this machine lacks offers nothing")

  local player = { id = "0badf00d", name = "BLUE#123", engine = 1,
    version = "red" }
  T.check(OnlinePanel.invitePickerOpen(imp, player), "INVITE opens the picker")
  T.check(imp._invitePicker ~= nil, "as a modal")
  local ok = drawWith(function(m)
    return require("src.import.online.InvitePicker").draw(imp, m)
  end)
  T.check(ok, "which draws")
  T.check(OnlinePanel.startInvite(imp, player, "battle_single"),
    "picking Battle sends the invite")
  T.eq(imp._invitePicker, nil, "and closes the picker")
  T.eq(invites[1] and invites[1].to, "0badf00d", "to that trainer")
  T.eq(invites[1] and invites[1].activity, "battle_single", "for a battle")
  T.eq(invites[1] and invites[1].profile and invites[1].profile.version, "red",
    "with the picked game's profile")
  T.eq(st.status, "Invite sent to BLUE#123.", "and a line saying so")
  invites[1].handle.id = "i00000000000000a1"
  OnlinePanel.inviteClosed(imp, { id = "i00000000000000a1", why = "declined" })
  T.check(st.status ~= nil and st.status ~= "Invite sent to BLUE#123.",
    "a decline replaces it with one line")
  T.eq(st.outgoing, nil, "and clears the outgoing invite")

  local fresh = newImp({ red = true })
  local fst = OnlinePanel.state(fresh)
  fst.version = "red"
  T.check(OnlinePanel.startInvite(fresh, player, "battle_single"),
    "inviting before any setup")
  T.eq(OnlinePanel.screen(fresh), "wizard", "walks the setup wizard first")
  T.eq(OnlinePanel.wizard(fresh).kind, "invite", "an invite wizard")

  local INV = { id = "i00000000000000b2", activity = "battle_single",
    from = { id = "0badf00d", name = "BLUE#123" }, detail = {},
    expiresAt = 5000 + 20000 }
  OnlinePanel.inviteIn(imp, INV)
  OnlinePanel.inviteIn(imp, INV)
  T.eq(#st.invites, 1, "a repeated invite_in is one toast")
  local toast = OnlinePanel.toast(imp)
  T.check(toast ~= nil, "an invite shows a toast")
  T.eq(OnlinePanel.inviteLine(toast), "BLUE#123 invites you to a battle.",
    "reading who and what")
  T.eq(OnlinePanel.inviteLeft(toast), 1, "with a full countdown bar")
  local tok, drew = drawWith(function(m)
    return require("src.import.online.Toast").draw(imp, m, 80, false)
  end)
  T.check(tok and drew, "the toast draws on any tab")
  T.check(imp._toastRect ~= nil, "and records its rect for occlusion")
  T.check(OnlinePanel.toastAction(imp, "accept"), "ACCEPT")
  T.eq(replies[1] and replies[1].accept, true, "replies yes")
  T.eq(replies[1] and replies[1].id, INV.id, "to that invite")
  OnlinePanel.pruneInvites(imp)
  T.eq(OnlinePanel.toast(imp), nil, "and the toast goes")

  local INV2 = { id = "i00000000000000c3", activity = "trade",
    from = { id = "0badf00d", name = "BLUE#123" }, detail = {},
    expiresAt = 5000 + 20000 }
  OnlinePanel.inviteIn(imp, INV2)
  T.check(OnlinePanel.toastAction(imp, "decline"), "DECLINE")
  T.eq(replies[2] and replies[2].accept, false, "replies no")
  OnlinePanel.pruneInvites(imp)
  T.eq(OnlinePanel.toast(imp), nil, "and the toast goes")

  local INV3 = { id = "i00000000000000d4", activity = "battle_single",
    from = { id = "0badf00d", name = "BLUE#123" }, detail = {},
    expiresAt = 4000 }
  OnlinePanel.inviteIn(imp, INV3)
  OnlinePanel.pruneInvites(imp)
  T.eq(OnlinePanel.toast(imp), nil, "an expired invite never shows")

  local INV4 = { id = "i00000000000000e5", activity = "battle_single",
    from = { id = "0badf00d", name = "BLUE#123" }, detail = {},
    expiresAt = 5000 + 20000 }
  local unset = newImp({ red = true })
  local ust = OnlinePanel.state(unset)
  ust.version = "red"
  OnlinePanel.inviteIn(unset, INV4)
  T.check(OnlinePanel.toastAction(unset, "accept"),
    "accepting before any setup")
  T.eq(OnlinePanel.wizard(unset) and OnlinePanel.wizard(unset).kind, "accept",
    "opens the accept wizard")
  T.eq(#replies, 2, "without answering yet")
  setUp(unset)
  OnlinePanel.wizardTo(unset, "summary")
  OnlinePanel.wizardNext(unset)
  T.eq(replies[3] and replies[3].id, INV4.id, "the wizard's confirm accepts it")
  T.eq(replies[3] and replies[3].accept, true, "with a yes")
  restore()
end

do
  Kit.layout(1280, 800)
  local x, y, w, h = Kit.toastRect(1280, "BLUE invites you to a battle.", 60, 1)
  T.check(x + w <= 1280, "the toast sits inside the window")
  T.check(x > 640, "top-right")
  local sx = Kit.toastRect(1280, "BLUE invites you to a battle.", 60, 0)
  T.check(sx >= 1280, "fully slid out starts past the right edge")
  local bx = x + w - 20
  local by = y + h - 30
  Kit.beginFrame(bx, by, true, 0)
  Kit.occlude(x, y, w, h)
  T.check(not Kit.hit(bx, by, 4, 4), "controls under the toast lose the tap")
  local action = Kit.toast({ id = "t", text = "BLUE invites you to a battle.",
    W = 1280, top = 60, slide = 1, progress = 0.5 })
  T.eq(action, "accept", "while the toast's own ACCEPT takes it")
  Kit.occlude(nil)
  Kit.endFrame()
  Kit.beginFrame(x + 20, by, true, 0)
  action = Kit.toast({ id = "t", text = "x", W = 1280, top = 60, slide = 1 })
  T.eq(action, "decline", "DECLINE sits on the left")
  Kit.endFrame()
  Kit.beginFrame(x + 20, by, true, 0)
  action = Kit.toast({ id = "t", text = "x", W = 1280, top = 60, slide = 1,
    blocked = true })
  T.eq(action, nil, "a toast under the loader takes nothing")
  Kit.endFrame()
end

do
  local armed, reduce = Transition.armed, Transition.reduceMotion
  Transition.armed, Transition.reduceMotion = true, false
  Transition.start("toast", "in", { duration = 0.2 })
  T.check(Transition.get("toast") ~= nil, "the toast slides in")
  T.check(not Transition.active(), "without blocking the rest of the launcher")
  Transition.reduceMotion = true
  Transition.start("toast", "in", { duration = 0.2 })
  T.eq(Transition.progress("toast"), 1, "reduce motion snaps it in")
  Transition.armed, Transition.reduceMotion = armed, reduce
  Transition.reset()
end

do
  VirtualKeyboard.active, VirtualKeyboard.mode = true, 4
  VirtualKeyboard.maxLen, VirtualKeyboard.text = 4, ""
  T.eq(VirtualKeyboard.currentRows()[1][1], "1", "the PIN pad is a number pad")
  VirtualKeyboard.textinput("12a3456")
  T.eq(VirtualKeyboard.text, "1234", "typing into it keeps four digits")
  VirtualKeyboard.active, VirtualKeyboard.mode = false, 1
  VirtualKeyboard.maxLen, VirtualKeyboard.text = nil, ""
end

do
  local TOKEN = ("0123456789abcdef"):rep(2)
  local st = DiscordPresence._state
  DiscordPresence.setJoinSecret(TOKEN:upper(), 1, 2)
  T.eq(st.joinSecret, TOKEN, "the join secret is the invite token")
  DiscordPresence.setJoinSecret("ABC123", 1, 2)
  T.eq(st.joinSecret, nil, "a room code is never advertised")
  DiscordPresence.setJoinSecret(TOKEN, 1, 2)
  DiscordPresence.setJoinCode(nil)
  T.eq(st.joinSecret, nil, "the old clear call still clears it")

  local returned = nil
  local game = { returnToLauncher = function(o) returned = o end,
    stack = { top = function() return nil end } }
  st.game, st.activity = game, "exploring"
  DiscordPresence.handleJoinRequest("i:" .. TOKEN)
  T.eq(returned and returned.tab, "online", "a join returns to the ONLINE tab")
  T.eq(returned and returned.invite, TOKEN, "carrying the invite token")
  returned = nil
  DiscordPresence.handleJoinRequest("m:ABC123")
  T.eq(returned, nil, "an old code secret joins nothing")

  local g3 = { generation = 3, returnToLauncher = function(o) returned = o end }
  st.game = g3
  package.loaded["src.core.game3.link"] = { link = {} }
  DiscordPresence.handleJoinRequest("i:" .. TOKEN)
  T.eq(returned, nil, "a Gen 3 game mid-link is left alone")
  package.loaded["src.core.game3.link"] = nil
  DiscordPresence.handleJoinRequest("i:" .. TOKEN)
  T.eq(returned and returned.invite, TOKEN, "and joins once it is free")

  st.game, st.activity = nil, "menu"
  local handed = nil
  DiscordPresence.joinHandler = function(token) handed = token end
  DiscordPresence.handleJoinRequest(TOKEN)
  T.eq(handed, TOKEN, "the launcher's own handler takes a bare token")
  DiscordPresence.joinHandler = nil

  local imp = newImp()
  OnlinePanel.state(imp)
  local restore = patch(Client, {
    state = function() return "online" end,
    joinRoomByInvite = function(token, as)
      handed = { token = token, as = as }
      return { done = false }
    end,
    setProfiles = function(list) return list end,
    room = function() return nil end,
    tournament = function() return nil end,
    lobby = function() return {} end,
  })
  OnlinePanel._discordInvite = TOKEN
  OnlinePanel.update(imp, 1 / 60)
  T.eq(type(handed) == "table" and handed.token, TOKEN,
    "the panel joins by the token on its next update")
  restore()

  local minted = {}
  local restoreMint = patch(Client, {
    inviteToken = function(room) minted[#minted + 1] = room return true end,
    serverTime = function() return 1000 end,
  })
  local ROOM = { room = "r00000000000000ab", stage = "waiting", seats = 2,
    players = { { id = "me" } } }
  st.enabled = false
  OnlinePanel.clearPresence()
  OnlinePanel.pushPresence(ROOM)
  T.eq(#minted, 0, "no token is minted while Discord is not running")
  st.enabled = true
  OnlinePanel.pushPresence(ROOM)
  T.eq(minted[1], ROOM.room, "a waiting room asks the relay for a token")
  OnlinePanel.pushPresence(ROOM)
  T.eq(#minted, 1, "once")
  OnlinePanel._tokenFor.token = TOKEN
  OnlinePanel._tokenFor.expiresAt = 1000 + 1800000
  OnlinePanel.pushPresence(ROOM)
  T.eq(st.joinSecret, TOKEN, "the token becomes the Discord join secret")
  T.eq(st.partyMax, 2, "with the room's seat count")
  ROOM.players[2] = { id = "them" }
  OnlinePanel.pushPresence(ROOM)
  T.eq(st.joinSecret, nil, "a full room stops advertising")
  st.enabled = false
  restoreMint()
end

do
  local imp = newImp()
  local st = setUp(imp)
  local joined, created = nil, nil
  local restore = patch(Client, {
    joinTournament = function(opts) joined = opts return { done = false } end,
    createTournament = function(opts) created = opts return { done = false } end,
    setProfiles = function(list) return list end,
  })
  T.check(OnlinePanel.joinTournament(imp, { code = "tq2ra3" }, "spectator"),
    "a private tournament code joins")
  T.eq(joined and joined.code, "TQ2RA3", "upper-cased")
  T.eq(joined and joined.tour, nil, "with no id")
  T.check(OnlinePanel.joinTournament(imp, { tour = "t00000000000000aa" },
    "spectator"), "a listed tournament joins by id")
  T.eq(joined and joined.tour, "t00000000000000aa", "by its id")
  T.eq(joined and joined.code, nil, "and no code")
  st.tourPublic, st.tourPlaying = false, false
  OnlinePanel.hostTournament(imp)
  T.eq(created and created.public, false, "a private tournament is created")
  st.tourPublic, st.tourPlaying = true, true
  restore()
end

do
  local imp = newImp({ red = true, firered = true })
  local st = setUp(imp)
  local TOUR = { tour = "t00000000000000aa", code = "TQ2RA3", creator = "me",
    stage = "registering", players = { { id = "me", name = "RED" } },
    spectators = {}, bracket = {} }
  local ROOM = { room = "r00000000000000aa", host = "me", stage = "waiting",
    intent = "battle", locked = true, seats = 2,
    profile = RED_PROFILE, players = { { id = "me", name = "RED" } },
    spectators = {} }
  local LOBBY = {}
  for i = 1, 20 do
    LOBBY[i] = { id = ("%08x"):format(i), name = "T" .. i, online = true,
      where = (i % 3 == 0) and "union" or "launcher", status = "idle",
      engine = (i % 2 == 0) and 3 or 1,
      version = (i % 2 == 0) and "firered" or "red",
      room = ("r%016x"):format(i), locked = i % 4 == 0, open = true,
      intent = "battle", stage = "waiting", spectators = 0,
      profile = RED_PROFILE }
  end
  local currentTour, currentRoom = nil, ROOM
  local restore = patch(Client, {
    state = function() return "online" end,
    you = function() return { id = "me", name = "RED" } end,
    lobby = function() return LOBBY end,
    openRooms = function() return LOBBY end,
    watchable = function() return LOBBY end,
    counts = function() return { players = 21, openRooms = 20 } end,
    room = function() return currentRoom end,
    tournament = function() return currentTour end,
    serverTime = function() return 0 end,
  })
  local function screenDraw(id)
    return drawWith(function(m)
      return OnlinePanel.buildOnlinePanel(imp, m.contentX, m.top + 100,
        m.contentW, math.max(200, m.h - 200), m)
    end)
  end
  OnlinePanel.go(imp, "play")
  st.list = "players"
  OnlinePanel.invalidate(imp, "lobby")
  OnlinePanel.refresh(imp)
  T.check(#OnlinePanel.cache(imp).players > 0, "the Trainers list fills")
  Kit.audit = {}
  T.check(screenDraw("play"), "Play draws the Trainers list")
  local sawInvite = false
  for _, row in ipairs(Kit.audit) do
    if row.label == "Invite" then sawInvite = true end
  end
  Kit.audit = nil
  T.check(sawInvite, "with an Invite action per trainer")
  st.list = "rooms"
  T.check(screenDraw("play"), "and the lobby list with locks")

  st.routeKey = "R" .. ROOM.room
  OnlinePanel.go(imp, "room")
  Kit.audit = {}
  T.check(screenDraw("room"), "Room draws the players card")
  local sawCopy = false
  for _, row in ipairs(Kit.audit) do
    if row.label == "Copy" then sawCopy = true end
  end
  Kit.audit = nil
  T.check(not sawCopy, "with no code to copy")

  currentRoom, currentTour = nil, TOUR
  st.routeKey = "T" .. TOUR.tour
  OnlinePanel.go(imp, "tournament")
  Kit.audit = {}
  T.check(screenDraw("tournament"), "the creator's tournament screen draws")
  sawCopy = false
  for _, row in ipairs(Kit.audit) do
    if row.label == "Copy" then sawCopy = true end
  end
  Kit.audit = nil
  T.check(sawCopy, "with the private code and Copy")
  TOUR.creator = "someone"
  Kit.audit = {}
  screenDraw("tournament")
  sawCopy = false
  for _, row in ipairs(Kit.audit) do
    if row.label == "Copy" then sawCopy = true end
  end
  Kit.audit = nil
  T.check(not sawCopy, "a player who did not create it sees no code")
  TOUR.creator = "me"

  st.private, st.pin = true, "12"
  OnlinePanel.startWizard(imp, "hostBattle")
  OnlinePanel.wizardTo(imp, "visibility")
  T.check(screenDraw("wizard"), "the Private (PIN) step draws")
  st.private, st.pin = false, ""

  local INV = { id = "i00000000000000f6", activity = "trade",
    from = { id = "0badf00d", name = "BLUE#123" }, detail = {},
    expiresAt = 20000 }
  OnlinePanel.inviteIn(imp, INV)
  local Toast = require("src.import.online.Toast")
  local PinModal = require("src.import.online.PinModal")
  OnlinePanel.pinOpen(imp, { room = ROOM.room, locked = true, name = "BLUE" })
  OnlinePanel.home(imp)
  OnlinePanel.go(imp, "play")
  local clock = os.clock
  drawWith(function(m)
    OnlinePanel.buildOnlinePanel(imp, m.contentX, m.top + 100, m.contentW, 500, m)
    PinModal.draw(imp, m)
    Toast.draw(imp, m, 80, false)
  end)
  local started = clock()
  for _ = 1, 25 do
    drawWith(function(m)
      OnlinePanel.buildOnlinePanel(imp, m.contentX, m.top + 100, m.contentW, 500, m)
      PinModal.draw(imp, m)
      Toast.draw(imp, m, 80, false)
    end)
  end
  local cost = (clock() - started) / 25
  T.check(cost < 0.008, ("Play + PIN modal + toast draw in %.3f ms")
    :format(cost * 1000))
  OnlinePanel.pinClose(imp)
  restore()
end

do
  local imp = newImp()
  local st = setUp(imp)
  local created
  local restore = patch(Client, {
    createRoom = function(opts) created = opts return { done = false } end,
    setProfiles = function(list) return list end,
  })
  OnlinePanel.startWizard(imp, "hostBattle")
  st.private, st.pin = true, "1234"
  OnlinePanel.home(imp)
  st.tradeRole = "host"
  OnlinePanel.startWizard(imp, "tradeRemote")
  local has = {}
  for _, id in ipairs(OnlinePanel.wizardSteps(imp)) do has[id] = true end
  T.check(has.visibility, "hosting a trade asks Public / Private (PIN)")
  T.eq(st.private, false, "starting from Public, not the last battle's choice")
  st.tradeRole = "join"
  has = {}
  for _, id in ipairs(OnlinePanel.wizardSteps(imp)) do has[id] = true end
  T.check(not has.visibility, "joining a listed trade skips it")
  local shown = false
  for _, row in ipairs(OnlinePanel.wizardAnswers(imp)) do
    if row.step == "visibility" then shown = true end
  end
  T.check(not shown, "and the summary leaves it out")
  st.tradeRole = "host"
  OnlinePanel.home(imp)
  T.check(OnlinePanel.hostTrade(imp), "a trade is hosted")
  T.eq(created and created.private, false, "public")
  T.eq(created and created.pin, nil, "with no stale PIN")
  st.private, st.pin = true, "4321"
  created = nil
  OnlinePanel.home(imp)
  T.check(OnlinePanel.hostTrade(imp), "a private trade is hosted")
  T.eq(created and created.pin, "4321", "with the PIN picked for it")
  st.private, st.pin = false, ""
  restore()
  OnlinePanel.home(imp)
end

do
  local imp = newImp()
  setUp(imp)
  local armed = 0
  local was = { enabled = DiscordPresence._state.enabled,
    armed = DiscordPresence.launcherArmed }
  local restoreClient = patch(Client, {
    state = function() return "online" end,
    room = function() return nil end,
    tournament = function() return nil end,
    lobby = function() return {} end,
    setProfiles = function(list) return list end,
  })
  local restorePresence = patch(DiscordPresence, {
    ensureLauncher = function()
      armed = armed + 1
      DiscordPresence.launcherArmed = true
      return true
    end,
    update = function() end,
  })
  DiscordPresence.launcherArmed = false
  for _ = 1, 3 do OnlinePanel.update(imp, 1 / 60) end
  T.eq(armed, 1, "back in the launcher while online, presence is re-armed once")
  DiscordPresence.launcherArmed = false
  for _ = 1, 3 do OnlinePanel.update(imp, 1 / 60) end
  T.eq(armed, 1, "and not retried every frame")
  restorePresence()
  restoreClient()
  DiscordPresence._state.enabled = was.enabled
  DiscordPresence.launcherArmed = was.armed
end

do
  local clock = 100
  local restoreTimer = patch(love.timer, { getTime = function() return clock end })
  local restore = patch(Client, { serverTime = function() return 1000 end })
  local imp = newImp()
  OnlinePanel.state(imp)
  Transition.reset()
  local armed, reduce = Transition.armed, Transition.reduceMotion
  Transition.armed, Transition.reduceMotion = true, false
  local A = { id = "i000000000000000a", activity = "battle_single",
    from = { id = "0000000a", name = "BLUE#102" }, detail = {}, expiresAt = 21000 }
  local B = { id = "i000000000000000b", activity = "trade",
    from = { id = "0000000b", name = "LEAF#104" }, detail = {}, expiresAt = 21000 }
  OnlinePanel.inviteIn(imp, A)
  clock = clock + 1
  Transition.update(clock)
  OnlinePanel.inviteIn(imp, B)
  Transition.update(clock)
  T.eq(Transition.progress("toast"), 1,
    "a queued invite does not re-slide the toast on screen")
  T.eq(OnlinePanel.toast(imp).line, OnlinePanel.inviteLine(A),
    "the toast line is built once on arrival")
  OnlinePanel.declineInvite(imp, OnlinePanel.toast(imp))
  OnlinePanel.pruneInvites(imp)
  Transition.update(clock)
  T.eq(OnlinePanel.toast(imp).id, B.id, "the queued invite shows next")
  T.check(Transition.progress("toast") < 1, "and slides in")
  Transition.armed, Transition.reduceMotion = armed, reduce
  Transition.reset()
  restore()
  restoreTimer()
end

do
  local imp = newImp()
  local st = OnlinePanel.state(imp)
  st.outgoing = { to = "0badf00d", activity = "battle_single", id = nil }
  st.outgoingName = "BLUE#123"
  OnlinePanel.inviteClosed(imp, { id = "i0000000000000077", why = "timeout",
    to = "0c0ffee0", activity = "trade" })
  T.check(st.outgoing ~= nil,
    "an unrelated invite closing leaves the one still being sent alone")
  OnlinePanel.inviteClosed(imp, { why = "busy", to = "0badf00d",
    activity = "battle_single" })
  T.eq(st.outgoing, nil, "a refusal for that trainer closes it")
  T.eq(st.status, OnlinePanel.inviteClosedText({ why = "busy" }), "with one line")
end

do
  local imp = newImp()
  setUp(imp)
  local now = 1000
  local restore = patch(Client, {
    serverTime = function() return now end,
    joinRoom = function(room) return { id = room, done = false } end,
    setProfiles = function(list) return list end,
    room = function() return nil end,
    tournament = function() return nil end,
    lobby = function() return {} end,
  })
  local ROOM = "r00000000000000bb"
  OnlinePanel.pinOpen(imp, { room = ROOM, locked = true, name = "BLUE" })
  OnlinePanel.pinFailed(imp, { reason = "pin_locked", retryAt = now + 600000,
    pinTarget = { room = ROOM, locked = true, name = "BLUE" } })
  OnlinePanel.pinClose(imp)
  OnlinePanel.pinOpen(imp, { room = ROOM, locked = true, name = "BLUE" })
  T.check(OnlinePanel.pinLocked(imp),
    "Cancel then Join on the same locked row keeps the lockout")
  OnlinePanel.pinClose(imp)
  OnlinePanel.pinOpen(imp, { room = "r00000000000000cc", locked = true })
  T.check(not OnlinePanel.pinLocked(imp), "another room is not locked")
  OnlinePanel.pinClose(imp)
  now = now + 600001
  OnlinePanel.pinOpen(imp, { room = ROOM, locked = true })
  T.check(not OnlinePanel.pinLocked(imp), "the lockout ends on the relay clock")
  T.eq(OnlinePanel._pinLockout[ROOM], nil, "and is forgotten")
  OnlinePanel.pinClose(imp)
  restore()
end

do
  local imp = newImp({ firered = true })
  local restore = patch(Client, {
    room = function() return { room = "r00000000000000dd", intent = "battle" } end,
    tournament = function() return { tour = "t00000000000000dd",
      stage = "registering" } end,
  })
  local function has(list, id)
    for _, v in ipairs(list) do if v == id then return true end end
    return false
  end
  local row = OnlinePanel.playerRow(imp, { id = "0badf00d", name = "LEAF",
    engine = 3, version = "firered", where = "union" }, "me")
  local acts = OnlinePanel.activitiesFor(imp, row)
  T.check(not has(acts, "watch") and not has(acts, "tournament"),
    "a Union Room trainer is not offered Watch or Join my tournament")
  acts = OnlinePanel.activitiesFor(imp, { engine = 3, place = "launcher" })
  T.check(has(acts, "watch") and has(acts, "tournament"),
    "a launcher trainer still is")
  restore()
end

do
  local Room = require("src.import.online.Room")
  local seen = {}
  local restoreKit = patch(Kit, {
    tag = function(_, _, _, _, label) seen[#seen + 1] = label end,
    text = function(_, text) seen[#seen + 1] = text end,
  })
  local imp = newImp({ firered = true })
  drawWith(function(m)
    return Room.playersCard(imp, 0, 0, 600, m, { seats = 4, stage = "battling",
      players = { { id = "a", name = "P0", seat = 0 }, { id = "c", name = "P2", seat = 2 },
        { id = "d", name = "P3", seat = 3 } } }, false)
  end)
  restoreKit()
  local at = {}
  for i, v in ipairs(seen) do at[v] = at[v] or i end
  T.eq(seen[(at.P2 or 1) - 1], "TEAM A", "seat 2 stays on TEAM A after seat 1 leaves")
  T.eq(seen[(at.P3 or 1) - 1], "TEAM B", "seat 3 stays on TEAM B")
  T.eq(seen[(at["Open seat"] or 1) - 1], "TEAM B", "the empty seat is seat 1")
end

do
  local Room = require("src.import.online.Room")
  local two = { { id = "a" }, { id = "b" } }
  T.eq(Room.stageText({ stage = "waiting", seats = 2, players = { two[1] } }),
    "Waiting for a challenger", "one of two seats waits for a challenger")
  T.eq(Room.stageText({ stage = "waiting", seats = 2, players = two }),
    "Both trainers are picking a team", "a full room no longer waits")
  T.eq(Room.stageText({ stage = "ready", seats = 4, engine = 3, players = two }),
    "Waiting for trainers", "a readied multi host still waits for seats")
  T.eq(Room.stageText({ stage = "waiting", seats = 4, engine = 3,
      players = { two[1], two[2], { id = "c" }, { id = "d" } } }),
    "Everyone is here", "a full Gen 3 room says so")
  T.eq(Room.stageText({ stage = "waiting", seats = 2, intent = "trade",
      players = two }), "Both trainers are here", "a full trade room too")
  T.eq(Room.stageText({ stage = "battling", seats = 2, players = two }),
    "Battle in progress", "later stages pass through")

  local Home = require("src.import.online.Home")
  T.eq(Home.countsText(1, 1), "1 player online, 1 open lobby", "one reads singular")
  T.eq(Home.countsText(2, 0), "2 players online, 0 open lobbies", "others plural")
end

T.finish("online panel c1")
