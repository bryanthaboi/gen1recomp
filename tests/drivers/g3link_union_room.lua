local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/g3link"

local CENTER_2F = "FR_VIRIDIAN_CITY_POKEMON_CENTER_2F"
local UNION_ROOM = "FR_UNION_ROOM"
-- pokefirered/include/constants/flags.h:1375
local FLAG_SYS_POKEDEX_GET = 0x829
-- pokefirered/include/constants/species.h:5
local BULBASAUR, CHARMANDER, PIDGEY = 1, 4, 16

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  local Link = package.loaded["src.core.game3.link"]
  if Link then pcall(Link.reset) end
  local Client = package.loaded["src.online.Client"]
  if Client then pcall(Client.disconnect) end
  if failures == 0 then
    print("PASS g3link_union_room")
    love.event.quit(0)
  else
    print("FAIL g3link_union_room failures=" .. failures)
    love.event.quit(1)
  end
end

local function now() return love.timer.getTime() end

return function(game)
  print("PASS driver_started")
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Player = require("src.core.game3.player")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")
  local SaveMenu = require("src.ui.game3.save_menu")
  local PartyMenu = require("src.ui.game3.party_menu")
  local Party = require("src.core.game3.party")
  local Link = require("src.core.game3.link")
  local Union = require("src.core.game3.link.union_room")
  local Chat = require("src.core.game3.link.chat")
  local UnionChat = require("src.ui.game3.union_chat")
  local Screen = require("src.ui.game3.union_room")
  local Lobby = require("src.ui.game3.minigames.common_lobby")
  local Natives = require("src.core.game3.scripting.natives")
  local NativesLink = require("src.core.game3.scripting.natives_link")
  local Client = require("src.online.Client")
  local Relay = require("tests.support.fake_relay")
  local RomText = require("src.core.game3.rom_text")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end
  Party.giveMon(session, BULBASAUR, 12)
  Party.giveMon(session, CHARMANDER, 10)
  Party.giveMon(session, PIDGEY, 9)

  local relay = Relay.new({ clock = function() return now() end })
  local plazaState = relay.plazaStateMsg
  relay.plazaStateMsg = function(self, s)
    local msg = plazaState(self, s)
    for _, m in ipairs(msg.members or {}) do
      local ss = self.sessions[m.id]
      if ss and ss.group then m.group = ss.group end
      if ss and ss.status then m.status = ss.status end
    end
    return msg
  end
  local me = relay:seat("a0000001", "RED")
  Client.configure({ relayAddress = "fake:1", connect = function() return me.transport end })

  local function ctx() return Space.vm and Space.vm.ctx end
  local function place(x, y, facing)
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing
    game.session.x, game.session.y, game.session.facing = x, y, facing
  end
  local pollExtra
  local function wait(n)
    for _ = 1, n do
      relay:pump()
      if pollExtra then pollExtra() end
      U.wait(1)
    end
  end
  local function waitFor(cond, seconds, frames)
    local t0, n = now(), 0
    while not cond() do
      relay:pump()
      if pollExtra then pollExtra() end
      U.wait(1)
      n = n + 1
      if now() - t0 > (seconds or 5) and n > (frames or 60) then return false end
    end
    return true
  end
  local function drive(cond, seconds)
    local t0 = now()
    while not cond() and now() - t0 < (seconds or 10) do
      if Choice.active or SaveMenu.isOpen() or Message.isOpen() then U.tap(game, "a") end
      wait(6)
    end
    return cond()
  end
  local function pageThrough(cond)
    return function()
      if Message.isOpen() and Message.isWaiting() and (Message._page or 1) < #(Message._pages or {}) then
        U.tap(game, "a")
      end
      return cond()
    end
  end
  local function pushPlaza()
    relay:to(me, relay:plazaStateMsg(me))
  end

  local live = Link.liveProfile()
  if not result(live ~= nil, "the live g3 profile computes (vanilla game)") then return finish() end
  local function peer(id, name, trainerId, gender, version)
    local s = relay:seat(id, name)
    relay:handle(s, { type = "lobby_hello", protocol = 3, name = name, profiles = { live },
      presence = { where = "launcher", status = "idle", version = version } })
    s.avatar = { name = name, trainerId = trainerId, gender = gender, version = version }
    return s
  end

  Link.connect()
  result(waitFor(function() return Client.state() == "online" end, 5, 120), "the Client is online on the relay")

  Map.load(nil, game, CENTER_2F, { x = 6, y = 4, facing = "up" })
  wait(60)
  Flags.setFlag(Space.store, ctx(), FLAG_SYS_POKEDEX_GET, true)
  place(6, 4, "up")
  wait(12)
  U.tap(game, "a")
  local entered = drive(function() return Space.mapId == UNION_ROOM and Union.state == "main" end, 25)
  if not result(entered, "the attendant walks the player into the Union Room") then
    U.shot(game, DIR .. "/g3link_union_enter_failed.png")
    return finish()
  end
  result(Union.relay, "the Union Room runs over the relay")
  result(waitFor(function() return Client.plaza() ~= nil end, 5, 60), "the player is in the union plaza")
  me.presence.where = "union"

  print("[driver] 1. avatars")
  local green = peer("b0000002", "GREEN", 3, 1, "leafgreen")
  local pink = peer("c0000003", "PINK", 5, 1, "firered")
  local yellow = peer("d0000004", "YELLOW", 6, 0, "firered")
  for _, s in ipairs({ green, pink, yellow }) do
    s.presence.where = "union"
    relay:handle(s, { type = "plaza_join", kind = "union", profile = live, avatar = s.avatar })
  end
  local group = { leader = pink.id, members = { pink.id, yellow.id }, activity = "chat" }
  pink.group, pink.status = group, "chatting"
  yellow.group, yellow.status = group, "chatting"
  pushPlaza()
  result(waitFor(function() return Union.playerCount() == 2 end, 10, 60),
    "GREEN takes a leader slot and PINK's chat group another")
  local slotG = Union.slotForId(green.id)
  local slotP = Union.slotForId(pink.id)
  result(slotG ~= nil and slotP ~= nil, "both have slots")
  result(waitFor(function() return slotG and Union.leaderObj(slotG).state == 1 end, 5, 60),
    "GREEN flew down onto her spot")
  result(slotP and Union.vobjVisible(slotP, 0) and Union.vobjVisible(slotP, 1),
    "PINK and YELLOW stand at the group offsets")
  result(slotP and Union.vobj(slotP, 0).dir == Union.DIR.SOUTH, "the chat leader faces south")
  place(7, 9, "up")
  wait(40)
  U.still(game, DIR .. "/g3link_union_room_avatars.png")

  print("[driver] 2. talking to a trainer opens the invite menu")
  local Objects = require("src.core.game3.objects")
  local opened = false
  for _ = 1, 20 do
    local eo = Objects.find(Union.LOCAL_IDS[slotG])
    if eo and not eo.moving then
      place(eo.cellX, eo.cellY + 1, "up")
      wait(2)
      U.tap(game, "a")
      if waitFor(function() return Screen.isOpen() and Screen.mode == "activity" end, 3, 180) then
        opened = true
        break
      end
      local Hud = require("src.ui.game3.hud")
      local Stack = require("src.ui.game3.stack")
      local Field = require("src.core.game3.field")
      local top = Stack.top()
      print("[driver] talk state=" .. tostring(Union.state) .. " eo=" .. tostring(eo.cellX) .. "," .. tostring(eo.cellY)
        .. " vm=" .. tostring(Space.vm and Space.vm:isRunning()) .. " msg=" .. tostring(Message.isOpen())
        .. " hud=" .. tostring(Hud.busy()) .. " top=" .. tostring(top and top.id) .. " ui=" .. tostring(Runtime.uiBusy and Runtime.uiBusy())
        .. " locked=" .. tostring(Field.locked) .. " running=" .. tostring(Field.running) .. " moving=" .. tostring(Player.moving)
        .. " p=" .. tostring(Player.cellX) .. "," .. tostring(Player.cellY) .. " " .. tostring(Player.facing))
      drive(function() return Union.state == "main" and not Message.isOpen() end, 5)
    end
    wait(10)
  end
  result(opened, "GREEN's GREETINGS / BATTLE / CHAT / EXIT menu")
  wait(6)
  U.still(game, DIR .. "/g3link_union_do_something.png")
  Screen.cursor = 4
  U.tap(game, "a")
  drive(function() return Union.state == "main" and not Message.isOpen() end, 8)

  print("[driver] 3. an incoming invite rings")
  place(7, 9, "up")
  wait(6)
  relay:handle(green, { type = "invite", to = me.id, activity = "chat", detail = {}, profile = live })
  result(waitFor(function() return Union.state == "player_contacted_you" or Union.state == "handle_activity_request" end,
    5, 120), "GREEN's chat invite reaches the player")
  result(waitFor(function()
    if Message.isOpen() and Message.isWaiting() and (Message._page or 1) < #(Message._pages or {}) then
      U.tap(game, "a")
    end
    return Choice.active
  end, 8, 600), "the cart's YES/NO")
  wait(4)
  U.still(game, DIR .. "/g3link_union_invite_dialogue.png")
  U.tap(game, "a")

  print("[driver] 4. the chat")
  result(waitFor(function() return Chat.isActive() and UnionChat.isOpen() end, 8, 400), "the chat screen opens")
  local room = Client.room()
  result(room ~= nil and room.intent == "chat", "a private chat room")
  local seq = 0
  local function greenSays(msg)
    seq = seq + 1
    relay:handle(green, { type = "room_msg", seq = seq, msg = msg })
  end
  greenSays({ type = "game3_union_hello", name = "GREEN", gender = 1, trainerId = 3, activity = 0x45 })
  greenSays({ type = "game3_chat_line", name = "GREEN", text = "HI RED!" })
  greenSays({ type = "game3_chat_line", name = "GREEN", text = Chat.encode({ "L", "E", "T", "'", "S", " ", "{EMOJI_HAPPY}" }) })
  wait(30)
  for _, key in ipairs({ "down", "right", "right", "a", "right", "a" }) do
    U.tap(game, key)
    wait(3)
  end
  result(table.concat(Chat.buffer) == "HI", "typing H and I on the keyboard")
  U.tap(game, "start")
  wait(10)
  result(#Chat.lines >= 4, "the log holds the join and three lines")
  local sent = relay:sent(me, "room_msg")
  local said
  for _, m in ipairs(sent) do
    if m.msg and m.msg.type == "game3_chat_line" then said = m.msg.text end
  end
  result(said == "HI", "RED's line went out on the room")
  wait(20)
  U.still(game, DIR .. "/g3link_union_chat_messages.png")
  U.tap(game, "select")
  wait(4)
  U.still(game, DIR .. "/g3link_union_chat_swap_menu.png")
  U.tap(game, "down")
  U.tap(game, "down")
  wait(2)
  U.tap(game, "a")
  wait(30)
  result(Chat.page == Chat.PAGE.EMOJI, "SELECT switched to the emoji page")
  U.still(game, DIR .. "/g3link_union_chat_emoji.png")
  U.tap(game, "b")
  wait(4)
  result(Chat.routine == "quit", "B on an empty line asks to quit")
  U.tap(game, "up")
  wait(2)
  U.tap(game, "a")
  result(waitFor(function() return not Chat.isActive() end, 10, 600), "leaving the chat")
  result(waitFor(function() return Union.state == "main" end, 5, 200), "back in the Union Room")
  result(Client.room() == nil, "the chat room was left")

  print("[driver] 4b. GREETINGS: the card as text, then the full card")
  local TrainerCard = require("src.ui.game3.trainer_card")
  relay:handle(green, { type = "room_leave" })
  wait(4)
  relay:handle(green, { type = "invite", to = me.id, activity = "card", detail = {}, profile = live })
  result(waitFor(pageThrough(function() return Choice.active end), 8, 600), "GREEN offers GREETINGS")
  U.tap(game, "a")
  result(waitFor(function() return Link.link ~= nil end, 8, 400), "a link for the card exchange")
  local lk = Link.link
  result(lk and lk._transport and lk._transport.target == (Client.room() or {}).room,
    "on the new card room, not the chat room a late room_state named")
  local hello = {}
  for k, v in pairs(lk.myHello) do hello[k] = v end
  hello.name = "GREEN"
  hello.game3 = { cacheVersion = lk.myHello.game3.cacheVersion, nativeVersion = lk.myHello.game3.nativeVersion,
    linkType = lk.linkType, trainerId = 3, gender = 1, seat = 0 }
  seq = 0
  greenSays(hello)
  greenSays({ type = "game3_link_card", card = { name = "GREEN", trainerId = 3, gender = 1, stars = 2,
    caughtMonsCount = 64, playTimeHours = 21, playTimeMinutes = 8, linkBattleWins = 12, linkBattleLosses = 3,
    pokemonTrades = 5, easyChatProfile = { 2601, 4128, 526, 2611 } } })
  result(waitFor(function() return Union.state == "card_info" and Message.isOpen() end, 8, 400),
    "the partner's card prints as text")
  waitFor(function() return Message.isWaiting() end, 4, 300)
  U.still(game, DIR .. "/g3link_union_card_text.png")
  local firstPage = Message.currentPage()
  U.tap(game, "a")
  result(waitFor(function()
    return Message.isOpen() and Message.isWaiting() and Message.currentPage() ~= firstPage
  end, 4, 300), "the card text goes on to the next page")
  print("[driver] card page 2=" .. tostring(Message.currentPage()))
  U.still(game, DIR .. "/g3link_union_card_text_page2.png")
  result(waitFor(function()
    if Message.isOpen() and Message.isWaiting() and not Choice.active
        and (not Message._stay or (Message._page or 1) < #(Message._pages or {})) then
      U.tap(game, "a")
    end
    return Choice.active
  end, 10, 900), "then asks to see the full card")
  U.tap(game, "a")
  result(waitFor(function() return TrainerCard.isOpen() end, 5, 200), "YES shows GREEN's TRAINER CARD")
  wait(40)
  U.still(game, DIR .. "/g3link_union_card_full.png")
  U.tap(game, "b")
  result(waitFor(function() return Union.state == "main" and not TrainerCard.isOpen() end, 8, 400),
    "closing the card returns to the Union Room")
  result(waitFor(function() return Client.room() == nil end, 5, 200), "and leaves the card room")

  print("[driver] 4c. declined requests")
  relay:handle(green, { type = "room_leave" })
  wait(4)
  local function msgHas(text)
    local page = Message.isOpen() and Message.currentPage() or ""
    return text ~= nil and page:find(text, 1, true) ~= nil
  end
  local asked = false
  for _ = 1, 20 do
    local eo = Objects.find(Union.LOCAL_IDS[slotG])
    if eo and not eo.moving then
      place(eo.cellX, eo.cellY + 1, "up")
      wait(2)
      U.tap(game, "a")
      if waitFor(function() return Screen.isOpen() and Screen.mode == "activity" end, 3, 180) then
        asked = true
        break
      end
      drive(function() return Union.state == "main" and not Message.isOpen() end, 5)
    end
    wait(10)
  end
  result(asked, "GREEN's menu again")
  Screen.cursor = 3
  U.tap(game, "a")
  local invId
  result(waitFor(function()
    for id, inv in pairs(relay.invites) do
      if inv.from == me.id and inv.to == green.id then invId = id end
    end
    return invId ~= nil
  end, 5, 300), "RED's chat request reaches GREEN")
  if invId then relay:handle(green, { type = "invite_reply", id = invId, accept = false }) end
  result(waitFor(function() return Union.lastResult == "declined" and Message.isOpen() end, 8, 600),
    "GREEN declines")
  waitFor(function() return not Message.isTyping() end, 4, 300)
  print("[driver] declined page=" .. tostring(Message.currentPage()))
  result(msgHas(Union.rejectText(Union.ACTIVITY.CHAT, 1):match("^[^\n\\]+")), "with the cart's chat-declined text")
  U.still(game, DIR .. "/g3link_union_request_declined.png")
  drive(function() return Union.state == "main" and not Message.isOpen() end, 8)

  place(7, 9, "up")
  wait(6)
  relay:handle(green, { type = "invite", to = me.id, activity = "chat", detail = {}, profile = live })
  result(waitFor(pageThrough(function() return Choice.active end), 8, 600), "GREEN asks to chat again")
  U.tap(game, "down")
  wait(2)
  U.tap(game, "a")
  result(waitFor(function() return Union.lastResult == "declined" and Message.isOpen() end, 8, 600), "NO declines")
  waitFor(function() return not Message.isTyping() end, 4, 300)
  print("[driver] you-declined page=" .. tostring(Message.currentPage()))
  result(msgHas(RomText.ascii("gText_UR_OfferDeclined2"):match("^[^\n\\]+")), "with the cart's you-declined text")
  U.still(game, DIR .. "/g3link_union_you_declined.png")
  drive(function() return Union.state == "main" and not Message.isOpen() end, 8)

  print("[driver] 5. the trading board")
  relay:handle(green, { type = "presence", board = { species = BULBASAUR, level = 14, wantType = 10 } })
  relay:handle(yellow, { type = "presence", board = { species = PIDGEY, level = 5, wantType = 12 } })
  pushPlaza()
  result(waitFor(function() return #Union.boardOffers() >= 1 end, 5, 120), "GREEN's offer is on the board")
  Union.trade().playerSpecies, Union.trade().playerLevel, Union.trade().type = CHARMANDER, 10, 11
  place(2, 2, "up")
  wait(8)
  U.tap(game, "a")
  result(waitFor(function() return Screen.isOpen() and Screen.mode == "board" end, 8, 600), "the trading board list")
  wait(8)
  U.still(game, DIR .. "/g3link_union_trading_board.png")
  U.tap(game, "a")
  result(waitFor(pageThrough(function() return Choice.active end), 8, 600), "asking GREEN to trade")
  U.tap(game, "b")
  drive(function() return Union.state == "main" and not Message.isOpen() end, 8)
  Union.resetTrade()
  place(3, 3, "up")
  wait(6)
  U.tap(game, "a")
  local reg = waitFor(pageThrough(function() return Screen.isOpen() and Screen.mode == "register" end), 8, 600)
  print("[driver] attendant state=" .. tostring(Union.state) .. " result=" .. tostring(
    Flags.getVar(Space.store, ctx(), 0x800D)) .. " msg=" .. tostring(Message.isOpen()))
  result(reg, "the attendant's REGISTER / INFO / EXIT")
  wait(4)
  U.still(game, DIR .. "/g3link_union_register_menu.png")
  U.tap(game, "b")
  drive(function() return Union.state == "main" and not Message.isOpen() end, 8)

  print("[driver] 6. a minigame group recruiting")
  place(7, 9, "up")
  wait(6)
  Flags.setVar(Space.store, ctx(), Link.VAR_0x8004, Union.LINK_GROUP.BERRY_CRUSH)
  local c = ctx()
  c.nativePoll = nil
  Natives.special(c, NativesLink.SPECIAL.TryBecomeLinkLeader, Space.vm.adapters)
  pollExtra = function()
    if c.nativePoll and not Lobby.isOpen() then c.nativePoll() end
  end
  result(waitFor(function() return Lobby.isOpen() and Lobby.mode == "leader" end, 5, 60), "the leader screen opens")
  result(waitFor(function() return relay.groups[me.id] ~= nil end, 5, 60), "the relay holds RED's open group")
  wait(10)
  U.still(game, DIR .. "/g3link_union_group_alone.png")
  relay:handle(yellow, { type = "group_join", leader = me.id, profile = live, avatar = yellow.avatar })
  result(waitFor(pageThrough(function() return Choice.active end), 8, 600), "YELLOW contacted the leader")
  wait(4)
  U.still(game, DIR .. "/g3link_union_group_request.png")
  U.tap(game, "a")
  result(waitFor(function() return Lobby.isOpen() and #Lobby.players == 1 end, 8, 600), "YELLOW is a member")
  wait(10)
  U.still(game, DIR .. "/g3link_union_group_recruiting.png")
  result(Lobby.canStart(), "two players can start Berry Crush")
  U.tap(game, "b")
  wait(10)
  pollExtra = nil
  result(not Lobby.isOpen(), "B leaves the group")

  finish()
end
