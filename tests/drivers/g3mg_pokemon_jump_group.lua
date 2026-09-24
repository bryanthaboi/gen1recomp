local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or ".bazinga/BSA/09-23-26-03-gen3online/shots/minigames"

local CORNER = "FR_TWO_ISLAND_JOYFUL_GAME_CORNER"
-- pokefirered/include/constants/flags.h:790
local FLAG_GOT_MOON_STONE_FROM_JOYFUL_GAME_CORNER = 0x2FB
-- pokefirered/include/constants/flags.h:1375
local FLAG_SYS_POKEDEX_GET = 0x829
-- pokefirered/include/constants/vars.h:173
local VAR_MAP_SCENE_TWO_ISLAND_JOYFUL_GAME_CORNER = 0x4079
-- pokefirered/include/constants/vars.h:163
local VAR_CABLE_CLUB_STATE = 0x406F
local CHARMANDER, PIKACHU, SQUIRTLE = 4, 25, 7

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
    print("PASS g3mg_pokemon_jump_group")
    love.event.quit(0)
  else
    print("FAIL g3mg_pokemon_jump_group failures=" .. failures)
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
  local Bag = require("src.core.game3.bag")
  local Link = require("src.core.game3.link")
  local Screen = require("src.ui.game3.union_room")
  local Client = require("src.online.Client")
  local Relay = require("tests.support.fake_relay")
  local Wire = require("src.link.Wire")
  local MG = require("src.core.game3.minigames.common")
  local Lobby = require("src.ui.game3.minigames.common_lobby")
  local Countdown = require("src.ui.game3.minigames.common_countdown")
  local G = require(MG.GAMES.jump)
  local Game = G.Game
  local FUNC = Game.FUNC

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end
  session.trainerId = 0x1234
  Party.giveMon(session, CHARMANDER, 12)

  local relay = Relay.new({ clock = function() return now() end })
  local me = relay:seat("a0000001", "RED")
  Client.configure({ relayAddress = "fake:1", connect = function() return me.transport end })

  local function ctx() return Space.vm and Space.vm.ctx end
  local function getVar(id) return tonumber(Flags.getVar(Space.store, ctx(), id)) or 0 end
  local function setVar(id, v) Flags.setVar(Space.store, ctx(), id, v) end

  local peerHooks = {}
  local function fakeHooks()
    local h = { bag = {}, log = {} }
    h.hooks = {
      canAdd = function() return true end,
      addItem = function(item, qty) h.bag[item] = (h.bag[item] or 0) + qty return true end,
      updateRecords = function(score, row, exc) h.records = { score, row, exc } return true end,
      fanfareDone = function() return true end,
    }
    return h
  end
  G.hooksFor = function(c)
    local h = peerHooks[tonumber(c.seat)]
    if h then return h.hooks end
    return G.defaultHooks()
  end

  local peers = {}
  local function peerSession(s)
    local rs = { paired = true, closed = false, left = false, seq = 0, target = s.room }
    function rs:send(msg)
      self.seq = self.seq + 1
      relay:handle(s, { type = "room_msg", seq = self.seq, msg = msg })
    end
    function rs:poll()
      local out = {}
      for _, m in ipairs(s.transport.inbox) do
        if m.type == "room_msg" and type(m.msg) == "table" then
          local inner = Wire.sanitize(m.msg)
          if inner then
            if m.relay then
              inner.relay = true
              if type(inner.seat) ~= "number" then inner.seat = -1 end
            else
              inner.seat = m.seat
            end
            out[#out + 1] = inner
          end
        end
      end
      s.transport.inbox = {}
      return out
    end
    function rs:players()
      local room = relay.rooms[s.room or ""]
      return room and room.players or {}
    end
    function rs:close()
      self.left = true
      self.closed = true
      relay:handle(s, { type = "room_leave" })
    end
    return rs
  end

  local art = assert(G.loadArt())
  local function planPeer(p)
    local input = p.input
    input.want = nil
    local sim = p.m.sim
    if not sim then return end
    local g = sim.game
    local gfx = g.gfx
    if gfx.yesno then
      input.want = gfx.yesno.cursor == 0 and "a" or "up"
      return
    end
    if gfx.msgWindow and gfx.msgWindow.itemId and gfx.msgWindow.shown then
      input.want = "a"
      return
    end
    if p.jump and g.comm.funcId == FUNC.GAME_ROUND and g.vineState == 4
        and g.player.monState == Game.MONSTATE.NORMAL then
      input.want = "a"
    end
  end

  local function startPeer(s, species)
    local room = relay.rooms[s.room or ""]
    local seat = relay:seatOf(room, s.id)
    peerHooks[seat] = fakeHooks()
    local players = {}
    for _, p in ipairs(room.players) do
      players[#players + 1] = { id = p.id, name = p.name, seat = p.seat, trainerId = 0x2000 + p.seat, gender = p.seat % 2 }
    end
    local input = { want = nil }
    function input:wasPressed(b) return self.want == b end
    function input:isDown() return false end
    local m = MG.Match.new({ game = "jump", session = peerSession(s), seat = seat, seats = #players,
      players = players, seed = room.seed, partySlot = 0 },
      { module = G, art = art, partyMon = { species = species, personality = 0x5a5a0000 + seat, otId = 77 },
        me = { name = s.name, trainerId = 0x2000 + seat, gender = seat % 2 }, leader = room.leader,
        countdown = function() return Countdown.new(120, 80, { playSe = function() end }) end })
    local peer = { s = s, m = m, input = input, acc = 0, last = now(), jump = true, seat = seat }
    peers[#peers + 1] = peer
    return peer
  end

  local function stepPeers()
    for _, p in ipairs(peers) do
      if not p.gone and not p.m:finished() then
        local t = now()
        p.acc = p.acc + (t - p.last)
        p.last = t
        local n = 0
        while p.acc >= MG.DT and n < 8 do
          p.acc = p.acc - MG.DT
          n = n + 1
          planPeer(p)
          p.m:step(p.input)
        end
      end
    end
  end

  local redJump = false
  local lastTap = -1
  local function mySim()
    local m = MG.match()
    return m and m.sim or nil
  end
  local function redTick()
    local sim = mySim()
    if not (sim and redJump) then return false end
    local g = sim.game
    if g.comm.funcId == FUNC.GAME_ROUND and (g.vineState == 3 or g.vineState == 4)
        and g.player.monState == Game.MONSTATE.NORMAL and lastTap ~= g.comm.jumpsInRow then
      lastTap = g.comm.jumpsInRow
      U.tap(game, "a")
      return true
    end
    return false
  end

  local function wait(n)
    for _ = 1, n do
      relay:pump()
      stepPeers()
      if not redTick() then U.wait(1) end
    end
  end
  local function waitFor(cond, seconds)
    local t0 = now()
    while not cond() do
      relay:pump()
      stepPeers()
      if not redTick() then U.wait(1) end
      if now() - t0 > (seconds or 5) then return false end
    end
    return true
  end

  local live = Link.liveProfile()
  if not result(live ~= nil, "the live g3 profile computes (vanilla game)") then return finish() end
  Link.connect()
  result(waitFor(function() return Client.state() == "online" end, 5), "the Client is online on the relay")
  wait(20)

  print("[driver] lobby screens")
  Lobby.showPlayers({ { name = "BLUE", trainerId = 0x2222 }, { name = "LEAF", trainerId = 0x3333 } },
    { mode = "leader", group = { min = 2, max = 5 }, activity = 9 })
  wait(12)
  U.shot(game, DIR .. "/g3mg_pokemon_jump_lobby_leader.png")
  result(Lobby.canStart(), "POKEMON JUMP leader screen: two members, START allowed")
  Lobby.reset()
  wait(2)

  local blue = relay:seat("b0000002", "BLUE")
  relay:handle(blue, { type = "lobby_hello", protocol = 3, name = "BLUE", profiles = { live } })
  local leaf = relay:seat("c0000003", "LEAF")
  relay:handle(leaf, { type = "lobby_hello", protocol = 3, name = "LEAF", profiles = { live } })
  relay:handle(blue, { type = "group_open", activity = "minigame_jump", profile = live,
    avatar = { name = "BLUE", trainerId = 0x2222, gender = 0, version = "leafgreen" } })

  Flags.setFlag(Space.store, ctx(), FLAG_SYS_POKEDEX_GET, true)
  Flags.setFlag(Space.store, ctx(), FLAG_GOT_MOON_STONE_FROM_JOYFUL_GAME_CORNER, true)
  Map.load(nil, game, CORNER, { x = 6, y = 3, facing = "up" })
  wait(60)
  setVar(VAR_MAP_SCENE_TWO_ISLAND_JOYFUL_GAME_CORNER, 4)
  Player.cellX, Player.cellY = 6, 3
  Player.px, Player.py = 6 * 16, 3 * 16
  Player.targetX, Player.targetY = 6, 3
  Player.facing = "up"
  session.x, session.y, session.facing = 6, 3, "up"
  wait(10)
  U.tap(game, "a")

  local picked, joined = false, false
  local t0 = now()
  while now() - t0 < 40 do
    relay:pump()
    stepPeers()
    if PartyMenu.isOpen() and not picked then
      picked = true
      wait(10)
      U.tap(game, "a")
    elseif not joined and ((Screen.isOpen() and Screen.mode == "group" and #Screen.players > 0)
        or (Lobby.isOpen() and Lobby.mode == "group" and #Lobby.players > 0)) then
      wait(6)
      U.shot(game, DIR .. "/g3mg_pokemon_jump_lobby_join.png")
      joined = true
      U.tap(game, "a")
    elseif Choice.active or SaveMenu.isOpen() or (Message.isOpen() and Message.isWaiting and Message.isWaiting()) then
      U.tap(game, "a")
    end
    local g = relay.groups[blue.id]
    if g and #g.pending > 0 then
      for _, p in ipairs(g.pending) do
        relay:handle(blue, { type = "group_accept", from = p.id, ok = true })
      end
      if #g.members == 2 then
        relay:handle(leaf, { type = "group_join", leader = blue.id, profile = live,
          avatar = { name = "LEAF", trainerId = 0x3333, gender = 1, version = "firered" } })
      end
    end
    if g and #g.members == 3 then
      relay:handle(blue, { type = "group_start" })
    end
    if MG.isActive() then break end
    U.wait(2)
  end
  result(picked, "ChooseMonForWirelessMinigame opened the party menu")
  result(MG.partySlot == 0, "Charmander (slot 0) entered")
  result(joined, "the group list showed BLUE's POKEMON JUMP group")
  if not result(MG.isActive(), "MG.arm launched Pokemon Jump on the script's waitstate") then
    U.shot(game, DIR .. "/g3mg_pokemon_jump_no_launch.png")
    return finish()
  end
  local mine = MG.match()
  startPeer(blue, PIKACHU)
  startPeer(leaf, SQUIRTLE)
  result(mine and mine.seat == 1, "RED sits at seat 1")
  result(mine and mine.leader == 0, "BLUE leads")
  result(waitFor(function() return mine.sim ~= nil end, 10), "every seat readied and BLUE started Pokemon Jump")
  result(mine.sim and mine.sim.game.numPlayers == 3, "three jumpers")

  local namesShot, countdownShot = false, false
  local reached = waitFor(function()
    local sim = mine.sim
    local g = sim.game
    local gfx = g.gfx
    if not countdownShot then
      local c = (mine.phase == "countdown" and mine.countdown) or gfx.countdown
      if c and c:running() and c:digitShown() == 3 then
        U.still(game, DIR .. "/g3mg_pokemon_jump_countdown.png")
        countdownShot = true
      end
    end
    if not namesShot and gfx.names.visible and gfx.names.highlight and gfx:isMonIntroBounceActive() then
      if gfx.monSprites[g.multiplayerId].y2 <= -20 then
        U.still(game, DIR .. "/g3mg_pokemon_jump_intro_names.png")
        namesShot = true
      end
    end
    return g.comm.funcId == FUNC.GAME_ROUND
  end, 30)
  result(countdownShot, "the 3-2-1-START countdown played")
  result(namesShot, "intro: names over the mons, RED's highlighted, RED's mon hops")
  if not result(reached, "the vine starts swinging") then
    U.shot(game, DIR .. "/g3mg_pokemon_jump_stuck.png")
    return finish()
  end
  redJump = true

  local midShot, bonusShot = false, false
  waitFor(function()
    local g = mine.sim.game
    local gfx = g.gfx
    if not midShot and g.comm.jumpsInRow >= 2 and gfx.monSprites[g.multiplayerId].y2 <= -20
        and gfx.vine.priority == 2 then
      U.still(game, DIR .. "/g3mg_pokemon_jump_midgame.png")
      midShot = true
    end
    if not bonusShot and gfx.bonus.visible and gfx:bonusScrollY() > -36 then
      U.still(game, DIR .. "/g3mg_pokemon_jump_bonus.png")
      bonusShot = true
    end
    return g.comm.jumpsInRow >= 4 and midShot
  end, 60)
  local g = mine.sim.game
  result(g.comm.jumpsInRow >= 4, "four jumps in a row with RED tapping A (" .. g.comm.jumpsInRow .. ")")
  result(midShot, "mid-game shot: mons in the air over the vine")
  result(g.comm.jumpScore > g.comm.jumpsInRow * 10, "same-time bonus scored (" .. g.comm.jumpScore .. ")")
  result(bonusShot, "bonus plate shown")
  local Audio = require("src.core.game3.audio")
  local playing = Audio._currentSong and Audio._currentSong.id
  result(playing == Game.MUS_POKE_JUMP, "MUS_POKE_JUMP plays during the game (" .. tostring(playing) .. ")")

  local roomId = Client.room() and Client.room().room
  peers[1].gone = true
  relay:handle(blue, { type = "room_leave" })
  relay:migrateLeader(roomId)
  result(waitFor(function() return mine:isLeader() end, 3), "BLUE dropped: RED leads Pokemon Jump")
  result(waitFor(function() return peers[2].m.leader == 1 end, 3), "LEAF follows RED")
  local row = g.comm.jumpsInRow
  result(waitFor(function() return mine.sim.game.comm.jumpsInRow >= row + 2 end, 30),
    "the vine keeps swinging under RED")
  U.still(game, DIR .. "/g3mg_pokemon_jump_after_migration.png")
  g = mine.sim.game
  g.comm.jumpScore = math.max(g.comm.jumpScore, 4990)
  result(waitFor(function() return mine.sim.game.comm.jumpScore >= 5000 end, 20), "score reaches 5000")
  peers[2].jump = false

  local overShot, prizeShot, savingShot, againShot, droppedShot = false, false, false, false, false
  local prizeItem
  local done = waitFor(function()
    local sim = mine.sim
    if not sim then return true end
    local gm = sim.game
    local gfx = gm.gfx
    if not overShot and gm.comm.funcId == FUNC.GAME_OVER and gfx.names.visible and not gfx.names.highlight then
      U.still(game, DIR .. "/g3mg_pokemon_jump_game_over.png")
      overShot = true
    end
    local w = gfx.msgWindow
    if w and w.shown then
      if w.key == "gText_AwesomeWonF701F700" and not prizeShot then
        wait(20)
        U.still(game, DIR .. "/g3mg_pokemon_jump_prize.png")
        prizeShot = true
        prizeItem = w.itemId
        U.tap(game, "a")
      elseif w.key == "gText_SavingDontTurnOffPower" and not savingShot then
        U.still(game, DIR .. "/g3mg_pokemon_jump_saving.png")
        savingShot = true
      elseif w.key == "gText_SomeoneDroppedOut2" and not droppedShot then
        wait(10)
        U.still(game, DIR .. "/g3mg_pokemon_jump_dropped_out.png")
        droppedShot = true
      end
    end
    if gfx.yesno and not againShot then
      wait(10)
      U.still(game, DIR .. "/g3mg_pokemon_jump_play_again.png")
      againShot = true
      U.tap(game, "down")
      wait(4)
      U.tap(game, "a")
    end
    return not MG.isActive()
  end, 60)
  result(overShot, "game over: LEAF's mon flashes, names shown")
  result(prizeShot, "prize: Awesome score! You've won a berry!")
  result(savingShot, "SAVING... DON'T TURN OFF THE POWER.")
  result(againShot, "Want to play again? YES/NO")
  result(droppedShot, "RED said NO: Somebody dropped out. The link will be canceled.")
  result(done, "the minigame exits")
  result(prizeItem ~= nil and Bag.get(session.bag, prizeItem) >= 1,
    "prize berry " .. tostring(prizeItem) .. " in RED's bag")
  local rec = session.pokemonJumpRecords or {}
  result((rec.bestJumpScore or 0) >= 5000, "best score record " .. tostring(rec.bestJumpScore))
  result((rec.jumpsInRow or 0) >= 6, "jumps in a row record " .. tostring(rec.jumpsInRow))
  local leafRes = peers[2].m.result
  result(leafRes ~= nil and leafRes.results and leafRes.results[1] and leafRes.results[1].score == rec.bestJumpScore,
    "LEAF got RED's game3_mg_result")
  result(peerHooks[2] and peerHooks[2].bag[prizeItem] == 1, "LEAF got the same berry")

  result(waitFor(function() return Space.mapId == CORNER and getVar(VAR_CABLE_CLUB_STATE) == 0 end, 10),
    "warped back and ExitMinigameRoom cleared VAR_CABLE_CLUB_STATE")
  local Fade = require("src.ui.game3.fade")
  waitFor(function() return not Fade.isActive() and (tonumber(Fade.t) or 0) == 0 and not Space.vm:isRunning() end, 10)
  wait(30)
  U.shot(game, DIR .. "/g3mg_pokemon_jump_returned.png")
  local after = Audio._currentSong and Audio._currentSong.id
  result(after ~= Game.MUS_POKE_JUMP, "the corner's map music is back after the warp (" .. tostring(after) .. ")")
  result(Client.room() == nil, "RED left the relay room")
  finish()
end
