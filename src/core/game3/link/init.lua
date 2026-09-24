local Game3Link = require("src.link.Game3Link")

local Link = {}

-- pokefirered/include/constants/cable_club.h:5
Link.USING = {
  SINGLE_BATTLE = 1,
  DOUBLE_BATTLE = 2,
  TRADE_CENTER = 3,
  RECORD_CORNER = 4,
  MULTI_BATTLE = 5,
  UNION_ROOM = 6,
  BERRY_CRUSH = 7,
  MINIGAME = 8,
  BATTLE_TOWER = 9,
}

-- pokefirered/include/constants/cable_club.h:16
Link.LINKUP = {
  ONGOING = 0,
  SUCCESS = 1,
  SOMEONE_NOT_READY = 2,
  DIFF_SELECTIONS = 3,
  WRONG_NUM_PLAYERS = 4,
  FAILED = 5,
  CONNECTION_ERROR = 6,
  PLAYER_NOT_READY = 7,
  RETRY_ROLE_ASSIGN = 8,
  PARTNER_NOT_READY = 9,
}

-- pokefirered/include/constants/vars.h:163
Link.VAR_CABLE_CLUB_STATE = 0x406F
Link.VAR_RESULT = 0x800D
Link.VAR_0x8004 = 0x8004
Link.VAR_0x8006 = 0x8006

-- pokefirered/src/union_room.c:1863 CreateTrainerCardInBuffer
Link.MSG = { CARD = "game3_link_card" }
Link.peerCard = nil
Link.peerCards = {}

local MAP_DYNAMIC_NUM = 0x7F
local WARP_ID_NONE = 0xFF
-- pokefirered/include/constants/songs.h:13
local SE_EXIT = 9

Link.link = nil
Link.exitQueued = false
Link._warpMap = nil
Link._bagBackup = nil
Link._localClose = false
Link._pump = nil

local function runtime()
  return package.loaded["src.core.game3.runtime"]
end

function Link.session()
  local rt = runtime()
  local s = rt and rt.getSession and rt.getSession()
  if s then return s end
  local game = rt and rt._game
  return game and game.session or nil
end

function Link.game()
  local rt = runtime()
  return rt and rt._game or nil
end

local function space()
  return package.loaded["src.core.game3.scripting.space"]
end

function Link.store()
  local Space = space()
  if Space and Space.store then return Space.store end
  local s = Link.session()
  return s and s.store or nil
end

local function flags()
  return require("src.core.game3.scripting.flags")
end

function Link.getVar(ctx, id)
  return tonumber(flags().getVar(Link.store(), ctx, id)) or 0
end

function Link.setVar(ctx, id, value)
  flags().setVar(Link.store(), ctx, id, value)
end

function Link.setResult(ctx, value)
  flags().setVar(nil, ctx, Link.VAR_RESULT, value)
end

function Link.currentMap()
  local Space = space()
  if Space and type(Space.mapId) == "string" then return Space.mapId end
  local Map = package.loaded["src.core.game3.map"]
  if Map and type(Map.current) == "string" then return Map.current end
  local s = Link.session()
  return s and s.map or nil
end

function Link.mapDef(mapId)
  if type(mapId) ~= "string" then return nil end
  local game = Link.game()
  local def = game and game.data and game.data.maps and game.data.maps[mapId]
  if def then return def end
  local Collision = package.loaded["src.core.game3.collision"]
  if Collision and Collision._mapId == mapId then return Collision._mapDef end
  return nil
end

function Link.playerCell()
  local Player = package.loaded["src.core.game3.player"]
  local x, y = Player and tonumber(Player.cellX), Player and tonumber(Player.cellY)
  if x and y then return x, y end
  local s = Link.session()
  return s and tonumber(s.x) or 0, s and tonumber(s.y) or 0
end

-- pokefirered/src/field_control_avatar.c:1173 SetCableClubWarp
function Link.setCableClubWarp(ctx)
  local s = Link.session()
  local mapId = Link.currentMap()
  Link._warpMap = mapId
  local def = Link.mapDef(mapId)
  if not (s and def) then return nil end
  local px, py = Link.playerCell()
  for i, w in ipairs(def.warps or {}) do
    if tonumber(w.x) == px and tonumber(w.y) == py then
      local destWarp = tonumber(w.destWarp) or 1
      -- pokefirered/src/overworld.c:556 SetWarpDestinationToMapWarp
      s.warpDestination = {
        map = w.destMap or w.map,
        mapGroup = tonumber(w.mapGroup),
        mapNum = tonumber(w.mapNum),
        warpId = destWarp - 1,
        x = -1,
        y = -1,
      }
      local destDef = Link.mapDef(w.destMap or w.map)
      local landing = destDef and destDef.warps and destDef.warps[destWarp]
      if landing and tonumber(landing.mapNum) == MAP_DYNAMIC_NUM then
        -- pokefirered/src/overworld.c:600 SetDynamicWarp
        s.dynamicWarp = { map = mapId, warpId = i - 1, x = px, y = py }
      end
      return s.warpDestination
    end
  end
  return nil
end

local function resolveDest(dest)
  local mapId = dest.map or dest.mapId
  if type(mapId) ~= "string" then return nil end
  local def = Link.mapDef(mapId)
  local wid = tonumber(dest.warpId)
  -- pokefirered/src/overworld.c:564 SetPlayerCoordsFromWarp
  local landing = wid and wid >= 0 and wid < WARP_ID_NONE
    and def and def.warps and def.warps[wid + 1]
  if landing then
    return mapId, tonumber(landing.x) or 0, tonumber(landing.y) or 0
  end
  local x, y = tonumber(dest.x), tonumber(dest.y)
  if x and y and x >= 0 and y >= 0 then return mapId, x, y end
  return mapId, 0, 0
end

Link.resolveDest = resolveDest

function Link.warpToDest(ctx, adapters, dest, kind)
  if type(dest) ~= "table" then return false end
  local group, num = tonumber(dest.mapGroup), tonumber(dest.mapNum)
  if adapters and adapters.warp and group and num and num ~= MAP_DYNAMIC_NUM then
    if ctx then ctx.warpPending = true end
    adapters.warp(group, num, dest.warpId, dest.x, dest.y, function()
      if ctx then ctx.warpPending = false end
    end, kind)
    return true
  end
  local mapId, x, y = resolveDest(dest)
  if not mapId then return false end
  local Map = package.loaded["src.core.game3.map"]
  if not Map then
    local okM, loaded = pcall(require, "src.core.game3.map")
    Map = okM and loaded or nil
  end
  if not (Map and Map.load) then return false end
  local rt = runtime()
  local Player = package.loaded["src.core.game3.player"]
  -- src/overworld.c:2144
  if Player and Player.setVisible then Player.setVisible(true) end
  Map.load(rt and rt._mod, Link.game(), mapId, {
    x = x,
    y = y,
    facing = (Player and Player.facing) or "down",
    depth1Connections = true,
  })
  return true
end

-- pokefirered/src/field_fadetransition.c:646 DoCableClubWarp
function Link.doCableClubWarp(ctx, adapters)
  local Warp = package.loaded["src.core.game3.warp"]
  if ctx and ctx.warpPending and Warp and Warp.isBusy() then
    Link._warpMap = nil
    return false
  end
  if adapters and adapters.playSe then adapters.playSe(SE_EXIT) end
  local armedOn = Link._warpMap
  Link._warpMap = nil
  local mapId = Link.currentMap()
  local s = Link.session()
  local warped = not (armedOn and mapId ~= armedOn)
    and Link.warpToDest(ctx, adapters, s and s.warpDestination, "warpsilent")
  if not warped then
    local Player = package.loaded["src.core.game3.player"]
    if Player and Player.setVisible then Player.setVisible(true) end
  end
  return false
end

local function copyTable(value, depth)
  if type(value) ~= "table" or (depth or 0) > 8 then return value end
  local out = {}
  for k, v in pairs(value) do out[k] = copyTable(v, (depth or 0) + 1) end
  return out
end

-- pokefirered/src/load_save.c:208 LoadPlayerBag
function Link.loadPlayerBag()
  local s = Link.session()
  if not (s and s.bag) then return false end
  Link._bagBackup = copyTable(s.bag)
  return true
end

-- pokefirered/src/load_save.c:239 SavePlayerBag
function Link.savePlayerBag()
  local s = Link.session()
  local backup = Link._bagBackup
  Link._bagBackup = nil
  if not (s and backup) then return false end
  s.bag = backup
  return true
end

function Link.callSpecial(ctx, adapters, id)
  local Natives = package.loaded["src.core.game3.scripting.natives"]
  local handler = Natives and Natives.ALLOW and Natives.ALLOW["special:" .. id]
  if not handler then return false end
  handler(ctx, adapters)
  return true
end

function Link.cableClubState(ctx)
  return Link.getVar(ctx, Link.VAR_CABLE_CLUB_STATE)
end

function Link.inLinkRoom(ctx)
  return Link.cableClubState(ctx) ~= 0
end

-- pokefirered/src/cable_club.c:809 CleanupLinkRoomState
function Link.cleanupLinkRoomState(ctx, adapters)
  local mode = Link.getVar(ctx, Link.VAR_0x8004)
  if mode == Link.USING.SINGLE_BATTLE or mode == Link.USING.DOUBLE_BATTLE
      or mode == Link.USING.MULTI_BATTLE then
    Link.callSpecial(ctx, adapters, 0x28)
    Link.savePlayerBag()
  end
  local s = Link.session()
  -- pokefirered/src/overworld.c:610 SetWarpDestinationToDynamicWarp
  if s and type(s.dynamicWarp) == "table" then
    s.warpDestination = copyTable(s.dynamicWarp)
    return s.warpDestination
  end
  return nil
end

-- pokefirered/src/field_fadetransition.c:685 ReturnFromLinkRoom
function Link.returnFromLinkRoom(ctx, adapters)
  Link.closeLink("return_from_link_room")
  if adapters and adapters.playSe then adapters.playSe(SE_EXIT) end
  local s = Link.session()
  local dest = s and (s.warpDestination or s.dynamicWarp)
  return Link.warpToDest(ctx, adapters, dest, "warpsilent")
end

function Link.vmCtx()
  local Space = space()
  local vm = Space and Space.vm
  return vm and vm.ctx or nil, vm and vm.adapters or nil
end

function Link.doLinkRoomExit(ctx, adapters)
  if ctx == nil and adapters == nil then
    ctx, adapters = Link.vmCtx()
  end
  Link.cleanupLinkRoomState(ctx, adapters)
  return Link.returnFromLinkRoom(ctx, adapters)
end

-- pokefirered/src/cable_club.c:821 ExitLinkRoom
function Link.exitLinkRoom(ctx, adapters)
  Link.exitQueued = true
  local link = Link.link
  if link and link:isOpen() then
    link:send({ type = "game3_exit_link_room" })
    return true
  end
  Link.exitQueued = false
  Link.doLinkRoomExit(ctx, adapters)
  return false
end

local function leaveLink(link)
  if type(link) == "table" and type(link.leave) == "function" then
    pcall(link.leave, link)
  end
end

function Link.attach(link)
  Link.link = link
  Link._cardSent = false
  Link.peerCard = nil
  Link.peerCards = {}
  link.onClosed = function(reason)
    Link.link = nil
    Link._pump = nil
    Link._cardSent = false
    Link.lastCloseReason = reason
    if Link._localClose then return end
    leaveLink(link)
    local Union = package.loaded["src.core.game3.link.union_room"]
    if Union and Union.isActive() and Union.onUnionRoomMap() then return end
    if Link.inLinkRoom() then Link.doLinkRoomExit() end
  end
  Link.startPump()
  return link
end

-- pokefirered/src/link.c:386 OpenLink
function Link.open(opts)
  opts = opts or {}
  local transport = opts.transport
  if not (opts.link or transport) then return nil, "no_transport" end
  Link.closeLink("reopen")
  local link = opts.link or Game3Link.attach(transport, {
    role = opts.role,
    seat = opts.seat,
    seats = opts.seats,
    hello = opts.hello,
    linkType = opts.linkType,
    game = opts.game or Link.game(),
    timeout = opts.timeout,
    onReady = opts.onReady,
  })
  return Link.attach(link)
end

function Link.client()
  local loaded = package.loaded["src.online.Client"]
  if loaded then return loaded end
  local ok, Client = pcall(require, "src.online.Client")
  return ok and Client or nil
end

function Link.clientCall(name, ...)
  local C = Link.client()
  local fn = C and C[name]
  if type(fn) ~= "function" then return nil end
  local ok, a, b = pcall(fn, ...)
  if not ok then return nil end
  return a, b
end

-- pokefirered/src/link.c:386
function Link.openRelay(opts)
  opts = opts or {}
  local rs = opts.session or Link.clientCall("roomSession")
  if not rs then return nil, "no_room" end
  local RelayTransport = require("src.core.game3.link.relay_transport")
  local transport = RelayTransport.new(rs, { client = opts.client })
  local seat = transport:seat()
  if seat == nil then return nil, "spectator" end
  return Link.open({
    transport = transport,
    seat = seat,
    seats = transport:seats(),
    hello = opts.hello,
    linkType = opts.linkType,
    game = opts.game,
    timeout = opts.timeout,
    onReady = opts.onReady,
  })
end

-- pokefirered/src/cable_club.c:222 CreateLinkupTask waits for the other machine
function Link.beginConnect(_opts)
  return Link.link ~= nil
end

-- pokefirered/src/link.c:419 CloseLink
function Link.closeLink(reason)
  local link = Link.link
  Link.link = nil
  Link._pump = nil
  Link._cardSent = false
  if not link then return false end
  Link._localClose = true
  local ok = pcall(function() link:close(reason or "close_link") end)
  leaveLink(link)
  Link._localClose = false
  return ok
end

function Link.union()
  return require("src.core.game3.link.union_room")
end

function Link.battle()
  return require("src.core.game3.link.battle")
end

function Link.trade()
  return require("src.core.game3.link.trade")
end

function Link.status()
  return require("src.core.game3.link.status")
end

function Link.update(dt)
  local link = Link.link
  if link then
    link:update(dt)
    -- pokefirered/src/union_room.c:1863 CreateTrainerCardInBuffer
    if link.isReady and link:isReady() then
      if not Link._cardSent then Link._cardSent = Link.sendTrainerCard() end
      local card = link:take(Link.MSG.CARD)
      while card do
        Link.peerCard = card.card
        local seat = tonumber(card.seat)
        if seat and seat >= 0 then Link.peerCards[seat] = card.card end
        card = link:take(Link.MSG.CARD)
      end
    end
  end
  if Link.exitQueued then
    local live = Link.link
    if not (live and live:isOpen()) then
      Link.exitQueued = false
      Link._exits = nil
      Link.doLinkRoomExit()
    else
      local ex = Link._exits or { seats = {}, n = 0 }
      Link._exits = ex
      local exit = live:take("game3_exit_link_room")
      while exit do
        local seat = tonumber(exit.seat)
        if seat == nil then
          ex.n = ex.n + 1
        elseif not ex.seats[seat] then
          ex.seats[seat] = true
          ex.n = ex.n + 1
        end
        exit = live:take("game3_exit_link_room")
      end
      local need = math.max(1, (tonumber(live.nseats) or 2) - 1)
      if ex.n >= need then
        Link.exitQueued = false
        Link._exits = nil
        Link.closeLink("exit_link_room")
        Link.doLinkRoomExit()
      end
    end
  end
  local Union = package.loaded["src.core.game3.link.union_room"]
  local union = Union and Union.update(dt) or false
  local Battle = package.loaded["src.core.game3.link.battle"]
  local battle = Battle and Battle.update(dt) or false
  local Trade = package.loaded["src.core.game3.link.trade"]
  local trade = Trade and Trade.update(dt) or false
  local Chat = package.loaded["src.core.game3.link.chat"]
  local chat = Chat and Chat.update(dt) or false
  return Link.link ~= nil or Link.exitQueued or union or battle or trade or chat
end

function Link.startPump()
  if Link._pump then return Link._pump end
  local okT, Task = pcall(require, "src.core.game3.task")
  if not (okT and Task and Task.spawn) then return nil end
  Link._pump = Task.spawn(function(_, dt)
    if not Link.update(dt or 0) then
      Link._pump = nil
      return true
    end
    return false
  end)
  return Link._pump
end

-- pokefirered/src/start_menu.c:620 Field_AskSaveTheGame
function Link.askSaveTheGame(ctx, adapters)
  local okS, SaveMenu = pcall(require, "src.ui.game3.save_menu")
  if not (okS and type(SaveMenu) == "table" and SaveMenu.show) then
    Link.setResult(ctx, 0)
    return false
  end
  local Natives = require("src.core.game3.scripting.natives")
  return Natives.yieldHost(ctx, adapters, function(done)
    SaveMenu.show({
      session = Link.session(),
      game = Link.game(),
      onClose = function()
        -- pokefirered/src/start_menu.c:637 task50_save_game
        Link.setResult(ctx, SaveMenu._phase == "saved" and 1 or 0)
        done()
      end,
    })
  end)
end

Link.ADAPTER_RULESET = "g3_link"
Link._live = nil

function Link.version()
  local ok, GameVersion = pcall(require, "src.core.GameVersion")
  local v = ok and GameVersion.get and GameVersion.get() or nil
  if v == "leafgreen" then return "leafgreen" end
  return "firered"
end

function Link.liveProfile(rulesetId)
  rulesetId = rulesetId or Link.ADAPTER_RULESET
  local game = Link.game()
  local memo = Link._live
  if memo and memo.game == game and memo.rulesetId == rulesetId then
    return memo.profile, memo.why
  end
  local ok, ArenaData = pcall(require, "src.online.ArenaData")
  if not (ok and type(ArenaData) == "table" and type(ArenaData.liveProfile3) == "function") then
    return nil, "unavailable"
  end
  local okP, profile, why = pcall(ArenaData.liveProfile3, game, rulesetId)
  if not okP then return nil, tostring(profile) end
  if profile == nil and why == nil then why = "profile" end
  Link._live = { game = game, rulesetId = rulesetId, profile = profile, why = why }
  return profile, why
end

local function sameSurface(a, b)
  return type(a) == "table" and type(b) == "table" and tonumber(a.engine) == 3
    and a.fingerprint ~= nil and a.fingerprint == b.fingerprint
    and a.engineVersion == b.engineVersion
end

function Link.online()
  local C = Link.client()
  return C ~= nil and type(C.state) == "function" and C.state() == "online"
end

function Link.adapterConnected()
  if not Link.online() then return false end
  local live = Link.liveProfile()
  if not live then return false end
  for _, p in ipairs(Link.clientCall("profiles") or {}) do
    if sameSurface(p, live) then return true end
  end
  return false
end

function Link.avatar()
  local s = Link.session() or {}
  return {
    name = tostring(s.name or s.playerName or ""):sub(1, 7),
    trainerId = (tonumber(s.trainerId or s.id) or 0) % 65536,
    gender = (s.gender == 1 or s.gender == "female") and 1 or 0,
    version = Link.version(),
  }
end

function Link.connectOptions(live)
  local s = Link.session() or {}
  local version = Link.version()
  return {
    source = "game",
    version = version,
    trainerName = s.name or s.playerName,
    profiles = { live },
    presence = { where = "game", status = "busy", version = version },
  }
end

local function connectModule()
  local loaded = package.loaded["src.online.Connect"]
  if loaded then return loaded end
  local ok, Connect = pcall(require, "src.online.Connect")
  return ok and type(Connect) == "table" and Connect or nil
end

function Link.connect()
  local live, why = Link.liveProfile()
  if not live then return false, why end
  local Connect = connectModule()
  if not (Connect and Connect.start) then return false, "unavailable" end
  local okS, ok, err = pcall(Connect.start, Link.connectOptions(live))
  if not okS then return false, tostring(ok) end
  return ok and true or false, err
end

function Link.connectState()
  local Connect = connectModule()
  if Connect and Connect.state then
    local ok, s = pcall(Connect.state)
    if ok and s then return s end
  end
  local C = Link.client()
  return C and C.state and C.state() or "offline"
end

function Link.connectError()
  local Connect = connectModule()
  local err = Connect and Connect.error and Connect.error()
  if err == nil then err = Link.clientCall("error") end
  return err
end

function Link.reasonText(why)
  local Strings = require("src.core.Strings")
  if why == "mods" then
    return Strings("Mods that change link play are on, so this game can't go online.")
  end
  if why == "unavailable" then
    return Strings("Online play isn't available in this build.")
  end
  local Connect = connectModule()
  local upgrade = Connect and Connect.upgradeText and Connect.upgradeText()
  if type(upgrade) == "string" and upgrade ~= "" then return upgrade end
  if type(why) == "string" and why ~= "" then
    return Strings("The connection failed: %s.", (why:gsub("%.$", "")))
  end
  return Strings("The connection failed.")
end

function Link.setStatus(status)
  if not Link.online() then return false end
  Link.clientCall("setStatus", status)
  return true
end

local function inputPressed(key)
  local game = Link.game()
  local input = game and game.input
  return input and input.wasPressed and input:wasPressed(key) and true or false
end

Link.inputPressed = inputPressed

-- pokefirered/src/link.c:243 IsWirelessAdapterConnected
function Link.isWirelessAdapterConnected(ctx, adapters)
  if Link.adapterConnected() then
    Link.setResult(ctx, 1)
    return false, 1
  end
  if Link.online() and Link.liveProfile() then
    Link.connect()
    if Link.adapterConnected() then
      Link.setResult(ctx, 1)
      return false, 1
    end
  end
  Link.setResult(ctx, 0)
  if not (type(love) == "table" and love.graphics) then return false, 0 end
  local okM, Message = pcall(require, "src.ui.game3.message")
  local okC, Choice = pcall(require, "src.ui.game3.choice")
  if not (okM and okC and Message.show and Choice.yesNo) then return false, 0 end
  local Strings = require("src.core.Strings")
  local Natives = require("src.core.game3.scripting.natives")
  local stage = "ask"
  local finished = false
  local function finish(value)
    Link.setResult(ctx, value)
    finished = true
  end
  local function fail(why)
    stage = "reason"
    Message.show(Link.reasonText(why), function() finish(0) end)
  end
  Natives.yieldHost(ctx, adapters, function() end)
  Message.show(Strings("Connect to the Wireless Club?"), { stay = true })
  Link.connectPrompt = { stage = function() return stage end }
  ctx.nativePoll = function()
    if finished then
      Link.connectPrompt = nil
      return true
    end
    if stage == "ask" then
      if Message.isWaiting() then
        stage = "choice"
        Choice.yesNo(function(yes)
          if not yes then
            Message.close()
            finish(0)
            return
          end
          local ok, err = Link.connect()
          if not ok then
            fail(err)
            return
          end
          stage = "connecting"
          Message.show(Strings("Connecting..."), { stay = true })
        end, { left = 20, top = 8 })
      end
    elseif stage == "connecting" then
      if Link.adapterConnected() then
        Message.close()
        finish(1)
      else
        local state = Link.connectState()
        if state == "error" or state == "offline" then
          fail(Link.connectError() or state)
        elseif inputPressed("b") then
          local Connect = connectModule()
          if Connect and Connect.disconnect then pcall(Connect.disconnect) end
          Message.close()
          finish(0)
        end
      end
    end
    if finished then
      Link.connectPrompt = nil
      return true
    end
    return false
  end
  return true
end

local function dexCaught(dex, sp)
  local okD, Dex = pcall(require, "src.core.game3.dex")
  if okD and Dex and Dex.isCaught then
    local ok, v = pcall(Dex.isCaught, dex, sp)
    if ok then return v == true end
  end
  return type(dex.caught) == "table" and dex.caught[sp] == true
end

-- pokefirered/src/trainer_card.c:858
function Link.cardStars(s)
  local stars = 0
  if (tonumber(s.hofDebutHours) or 0) ~= 0 or (tonumber(s.hofDebutMinutes) or 0) ~= 0
      or (tonumber(s.hofDebutSeconds) or 0) ~= 0 then
    stars = 1
  end
  local dex = type(s.dex) == "table" and s.dex or nil
  if dex then
    local kanto = true
    for sp = 1, 150 do
      if not dexCaught(dex, sp) then
        kanto = false
        break
      end
    end
    if kanto then
      stars = stars + 1
      local all = true
      for sp = 152, 384 do
        if (sp <= 248 or sp >= 252) and not dexCaught(dex, sp) then
          all = false
          break
        end
      end
      if all then stars = stars + 1 end
    end
  end
  if (tonumber(s.berriesPicked) or 0) >= 200 and (tonumber(s.jumpsInRow) or 0) >= 200 then stars = stars + 1 end
  return math.min(4, stars)
end

-- pokefirered/src/trainer_card.c:818
function Link.cardCaught(s)
  local dex = type(s.dex) == "table" and s.dex or nil
  if not dex then return 0 end
  local okD, Dex = pcall(require, "src.core.game3.dex")
  if okD and Dex and Dex.countCaught then
    -- pokefirered/include/constants/flags.h:1398
    local okF, national = pcall(flags().getFlag, Link.store(), nil, 0x840)
    local ok, n = pcall(Dex.countCaught, dex, okF and national and "national" or "kanto")
    if ok and n then return n end
  end
  return 0
end

-- pokefirered/src/trainer_card.c:858 TrainerCard_GenerateCardForLinkPlayer
function Link.localTrainerCard()
  local s = Link.session()
  if type(s) ~= "table" then return nil end
  local stats = type(s.gameStats) == "table" and s.gameStats or {}
  local card = type(s.trainerCard) == "table" and s.trainerCard or {}
  return {
    stars = Link.cardStars(s),
    caughtMonsCount = Link.cardCaught(s),
    easyChatProfile = type(s.easyChatProfile) == "table" and s.easyChatProfile or nil,
    name = s.name or s.playerName,
    gender = s.gender,
    trainerId = s.trainerId or s.id,
    money = s.money,
    playTimeHours = s.playTimeHours,
    playTimeMinutes = s.playTimeMinutes,
    hofDebutHours = s.hofDebutHours,
    hofDebutMinutes = s.hofDebutMinutes,
    hofDebutSeconds = s.hofDebutSeconds,
    linkBattleWins = card.linkBattleWins or stats.linkBattleWins,
    linkBattleLosses = card.linkBattleLosses or stats.linkBattleLosses,
    -- pokefirered/src/trainer_card.c:824
    pokemonTrades = math.min(0xFFFF, tonumber(stats[21]) or 0),
    -- pokefirered/src/trainer_card.c:876
    berryCrushPoints = math.min(0xFFFF, tonumber(stats[51]) or 0),
    unionRoomNum = math.min(0xFFFF, tonumber(stats[50]) or 0),
    badges = card.badges,
    dex = s.dex,
    store = s.store,
  }
end

function Link.sendTrainerCard()
  local link = Link.link
  if not (link and link.isOpen and link:isOpen()) then return false end
  local card = Link.localTrainerCard()
  if not card then return false end
  link:send({ type = Link.MSG.CARD, card = card })
  return true
end

-- pokefirered/src/cable_club.c:980 Script_ShowLinkTrainerCard
function Link.showLinkTrainerCard(ctx, adapters)
  local index = Link.getVar(ctx, Link.VAR_0x8006)
  local card = Link.peerCards[index]
  local link = Link.link
  if card == nil and (tonumber(link and link.nseats) or 2) <= 2 then card = Link.peerCard end
  local mySeat = link and (tonumber(link.seat) or (link.role == "guest" and 1 or 0)) or nil
  if mySeat ~= nil and index == mySeat then card = Link.localTrainerCard() end
  card = card or Link.localTrainerCard()
  local okC, TrainerCard = pcall(require, "src.ui.game3.trainer_card")
  if not (okC and type(TrainerCard) == "table" and TrainerCard.show
      and type(love) == "table" and love.graphics) then
    return false, 0
  end
  local Natives = require("src.core.game3.scripting.natives")
  return Natives.yieldHost(ctx, adapters, function(done)
    -- pokefirered/src/trainer_card.c:1865 ShowTrainerCardInLink
    TrainerCard.show({ session = card, onClose = function() done() end })
  end)
end

-- pokefirered/src/wireless_communication_status_screen.c:302 BeginNormalPaletteFade
local function takeScreen()
  local okF, Fade = pcall(require, "src.ui.game3.fade")
  if not (okF and Fade and Fade.begin and Fade.MODE) then return function() end end
  local covered = not (Fade.isActive and Fade.isActive()) and (tonumber(Fade.t) or 0) >= 16
  if not (covered and Fade.mode == Fade.MODE.TO_BLACK) then return function() end end
  Fade.clear()
  return function()
    Fade.begin(Fade.MODE.FROM_BLACK, 1, function() end)
  end
end

-- pokefirered/src/wireless_communication_status_screen.c:195 ShowWirelessCommunicationScreen
function Link.showWirelessCommunicationScreen(ctx, adapters)
  local okS, LinkMenu = pcall(require, "src.ui.game3.link_menu")
  if not (okS and type(LinkMenu) == "table" and LinkMenu.show) then
    return false
  end
  local restore = takeScreen()
  local Natives = require("src.core.game3.scripting.natives")
  return Natives.yieldHost(ctx, adapters, function(done)
    LinkMenu.show({
      onClose = function()
        restore()
        done()
      end,
    })
  end)
end

function Link.reset()
  local Union = package.loaded["src.core.game3.link.union_room"]
  if Union then Union.reset() end
  local Battle = package.loaded["src.core.game3.link.battle"]
  if Battle then Battle.reset() end
  local Trade = package.loaded["src.core.game3.link.trade"]
  if Trade then Trade.reset() end
  local Chat = package.loaded["src.core.game3.link.chat"]
  if Chat then Chat.reset() end
  Link.closeLink("reset")
  Link.exitQueued = false
  Link._warpMap = nil
  Link._bagBackup = nil
  Link._localClose = false
  Link._pump = nil
  Link._cardSent = false
  Link.peerCard = nil
  Link.peerCards = {}
  Link._exits = nil
  Link._live = nil
  Link.connectPrompt = nil
end

package.loaded["src.core.game3.link"] = Link
package.loaded["src.core.game3.link.init"] = Link

return Link
