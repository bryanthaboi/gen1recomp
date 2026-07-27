-- Discord Rich Presence via the local Discord IPC pipe.  Shows the player's
-- current map (and battle status) on their Discord profile.  Desktop only;
-- no-ops on mobile, headless runs, or when Discord is not running.
--
-- Application ID is the only credential needed for presence.  The Discord
-- Interactions public key is unused here (that is for verifying bot HTTP
-- payloads, not Rich Presence).

local Json = require("src.link.Json")
local Logger = require("src.core.Logger")
local Runtime = require("src.mods.Runtime")
local Strings = require("src.core.Strings")

local DiscordPresence = {
  APP_ID = "1529183141267374262",
}

local OP_HANDSHAKE, OP_FRAME, OP_CLOSE = 0, 1, 2

local MIN_UPDATE_INTERVAL = 2.0
local RECONNECT_INTERVAL = 30.0

local state = {
  enabled = false,
  connected = false,
  socket = nil,       -- Windows: file handle; Unix: ffi sockfd
  isWindows = false,
  ffi = nil,
  ffiReady = false,
  startedAt = 0,
  dirty = false,
  lastSentKey = nil,
  lastSendAt = -1e9,
  nextReconnectAt = 0,
  location = nil,     -- display name
  mapId = nil,
  activity = "menu",  -- menu | exploring | battle
  battleLabel = nil,
  unsubs = {},
  pid = nil,
  loggedAbsent = false, -- one quiet note when Discord isn't running
  game = nil,          -- kept for the "friend clicked join" -> push a screen path
  joinCode = nil,       -- the online-match/tournament code to advertise as a join secret, if any
  joinKind = "match",   -- "match" (LinkState online) or "tournament"
  partySize = 1,        -- current headcount for the party.size Discord shows
  partyMax = 2,
  subscribedJoin = false, -- SUBSCRIBE ACTIVITY_JOIN sent on this connection?
}

-- MSG_DONTWAIT differs by OS (Darwin 0x80, Linux 0x40); only used for the
-- ongoing per-frame inbound poll, never for the one-time connect/handshake
local MSG_DONTWAIT_BY_OS = { ["OS X"] = 0x80, Linux = 0x40 }

local function disabledByEnv()
  return os.getenv("POKEPORT_NO_DISCORD") == "1"
      or os.getenv("POKEPORT_AUTOPILOT") ~= nil
      or os.getenv("POKEPORT_DRIVER") ~= nil
end

local function isDesktop()
  if not love or not love.system or not love.system.getOS then return false end
  local osName = love.system.getOS()
  return osName == "OS X" or osName == "Windows" or osName == "Linux"
end

local function packU32(n)
  n = math.floor(n) % 0x100000000
  local b1 = n % 256; n = math.floor(n / 256)
  local b2 = n % 256; n = math.floor(n / 256)
  local b3 = n % 256; n = math.floor(n / 256)
  local b4 = n % 256
  return string.char(b1, b2, b3, b4)
end

local function unpackU32(s)
  local b1, b2, b3, b4 = s:byte(1, 4)
  return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
end

local function nonce()
  return string.format("%08x-%04x-4%03x-%04x-%04x%08x",
    math.random(0, 0xffffffff),
    math.random(0, 0xffff),
    math.random(0, 0xfff),
    math.random(0, 0x3fff) + 0x8000,
    math.random(0, 0xffff),
    math.random(0, 0xffffffff))
end

local function resolvePid()
  if state.pid then return state.pid end
  local ffi = state.ffi
  if ffi then
    if state.isWindows then
      pcall(ffi.cdef, "unsigned long GetCurrentProcessId(void);")
      local ok, p = pcall(function() return ffi.C.GetCurrentProcessId() end)
      if ok and p and tonumber(p) and tonumber(p) > 0 then
        state.pid = tonumber(p)
        return state.pid
      end
    else
      pcall(ffi.cdef, "int getpid(void);")
      local ok, p = pcall(function() return ffi.C.getpid() end)
      if ok and p and tonumber(p) and tonumber(p) > 0 then
        state.pid = tonumber(p)
        return state.pid
      end
    end
  end
  state.pid = 1000 + math.random(1, 8999)
  return state.pid
end

local function ensureFfi()
  if state.ffiReady then return state.ffi end
  if state.ffi == false then return nil end
  local ok, ffi = pcall(require, "ffi")
  if not ok or not ffi then
    state.ffi = false
    return nil
  end
  state.ffi = ffi
  if state.isWindows then
    state.ffiReady = true
    return ffi
  end
  -- Darwin sockaddr_un has sun_len + uint8_t family; Linux uses u16 family.
  local osName = love.system.getOS()
  local cdef
  if osName == "OS X" then
    cdef = [[
      typedef unsigned int socklen_t;
      typedef int ssize_t;
      struct sockaddr_un {
        uint8_t sun_len;
        uint8_t sun_family;
        char sun_path[104];
      };
      struct timeval { long tv_sec; int tv_usec; };
      int socket(int domain, int type, int protocol);
      int connect(int sockfd, const void *addr, socklen_t addrlen);
      int setsockopt(int sockfd, int level, int optname, const void *optval, socklen_t optlen);
      ssize_t send(int sockfd, const void *buf, size_t len, int flags);
      ssize_t recv(int sockfd, void *buf, size_t len, int flags);
      int close(int fd);
    ]]
  else
    cdef = [[
      typedef unsigned int socklen_t;
      typedef int ssize_t;
      struct sockaddr_un {
        unsigned short sun_family;
        char sun_path[108];
      };
      struct timeval { long tv_sec; long tv_usec; };
      int socket(int domain, int type, int protocol);
      int connect(int sockfd, const void *addr, socklen_t addrlen);
      int setsockopt(int sockfd, int level, int optname, const void *optval, socklen_t optlen);
      ssize_t send(int sockfd, const void *buf, size_t len, int flags);
      ssize_t recv(int sockfd, void *buf, size_t len, int flags);
      int close(int fd);
    ]]
  end
  -- cdef may already be registered from a prior boot; either way we need
  -- sockaddr_un usable before claiming readiness
  pcall(ffi.cdef, cdef)
  local ready = pcall(function() return ffi.new("struct sockaddr_un") end)
  if not ready then
    state.ffi = false
    state.ffiReady = false
    return nil
  end
  state.ffiReady = true
  return ffi
end

local function closeSocket()
  local sock = state.socket
  state.socket = nil
  state.connected = false
  if not sock then return end
  if state.isWindows then
    pcall(function() sock:close() end)
  elseif state.ffi then
    pcall(state.ffi.C.close, sock)
  end
end

local function writeRaw(bytes)
  if not state.socket then return false end
  if state.isWindows then
    local ok = pcall(function()
      state.socket:seek("end")
      local _, writeErr = state.socket:write(bytes)
      state.socket:flush()
      if writeErr then error(writeErr) end
    end)
    return ok
  end
  local ffi = state.ffi
  if not ffi then return false end
  local ok, sent = pcall(ffi.C.send, state.socket, bytes, #bytes, 0)
  return ok and sent == #bytes
end

local function sendFrame(opcode, payload)
  local body = payload or ""
  local ok, frame = pcall(function()
    return packU32(opcode) .. packU32(#body) .. body
  end)
  if not ok or not frame then return false end
  return writeRaw(frame)
end

local function readExact(n)
  if not state.socket or n <= 0 then return nil end
  if state.isWindows then
    local ok, data = pcall(function() return state.socket:read(n) end)
    if not ok or not data or #data < n then return nil end
    return data
  end
  local ffi = state.ffi
  if not ffi then return nil end
  local ok, data = pcall(function()
    local buf = ffi.new("char[?]", n)
    local got = 0
    while got < n do
      local nread = ffi.C.recv(state.socket, buf + got, n - got, 0)
      if not nread or nread <= 0 then return nil end
      got = got + tonumber(nread)
    end
    return ffi.string(buf, n)
  end)
  if not ok then return nil end
  return data
end

local function receiveFrame()
  local header = readExact(8)
  if not header then return nil end
  local ok, opcode, length = pcall(function()
    return unpackU32(header:sub(1, 4)), unpackU32(header:sub(5, 8))
  end)
  if not ok or not opcode or not length or length < 0 or length > 65536 then
    return nil
  end
  local data = length > 0 and readExact(length) or ""
  if data == nil then return nil end
  return opcode, data
end

local function unixSocketPaths()
  local paths = {}
  local envs = { "XDG_RUNTIME_DIR", "TMPDIR", "TMP", "TEMP" }
  local bases = {}
  for _, key in ipairs(envs) do
    local v = os.getenv(key)
    if v and v ~= "" then
      if v:sub(-1) == "/" then v = v:sub(1, -2) end
      bases[#bases + 1] = v
    end
  end
  bases[#bases + 1] = "/tmp"
  local suffixes = {
    "",
    "/app/com.discordapp.Discord",
    "/app/com.discordapp.DiscordCanary",
    "/app/com.discordapp.DiscordPTB",
    "/snap.discord",
    "/snap.discord-canary",
  }
  local seen = {}
  for i = 0, 9 do
    local name = "discord-ipc-" .. i
    for _, base in ipairs(bases) do
      for _, suffix in ipairs(suffixes) do
        local path = base .. suffix .. "/" .. name
        if not seen[path] then
          seen[path] = true
          paths[#paths + 1] = path
        end
      end
    end
  end
  return paths
end

local function setSocketTimeout(fd, seconds)
  local ffi = state.ffi
  if not ffi or not fd then return end
  pcall(function()
    local tv = ffi.new("struct timeval")
    tv.tv_sec = seconds
    tv.tv_usec = 0
    -- SOL_SOCKET / SO_RCVTIMEO / SO_SNDTIMEO differ by OS
    local sol, rcv, snd
    if love.system.getOS() == "OS X" then
      sol, rcv, snd = 0xffff, 0x1006, 0x1005
    else
      sol, rcv, snd = 1, 20, 21
    end
    ffi.C.setsockopt(fd, sol, rcv, tv, ffi.sizeof(tv))
    ffi.C.setsockopt(fd, sol, snd, tv, ffi.sizeof(tv))
  end)
end

local function connectUnix()
  local ffi = ensureFfi()
  if not ffi then return false end
  local darwin = love.system.getOS() == "OS X"
  local maxPath = darwin and 103 or 107
  -- AF_UNIX=1, SOCK_STREAM=1 on Linux/macOS
  local pathsOk, paths = pcall(unixSocketPaths)
  if not pathsOk or not paths then return false end
  for _, path in ipairs(paths) do
    if #path <= maxPath then
      local ok, connected = pcall(function()
        local fd = ffi.C.socket(1, 1, 0)
        if not fd or fd < 0 then return false end
        local addr = ffi.new("struct sockaddr_un")
        addr.sun_family = 1
        if darwin then
          -- SUN_LEN: sizeof(sun_len+sun_family) + path + NUL
          addr.sun_len = 2 + #path + 1
        end
        ffi.copy(addr.sun_path, path)
        local rc = ffi.C.connect(fd, ffi.cast("void*", addr), ffi.sizeof(addr))
        if rc == 0 then
          setSocketTimeout(fd, 1) -- handshake must not freeze the game
          state.socket = fd
          return true
        end
        ffi.C.close(fd)
        return false
      end)
      if ok and connected then return true end
    end
  end
  return false
end

local function connectWindows()
  for i = 0, 9 do
    local path = "\\\\.\\pipe\\discord-ipc-" .. i
    local ok, file = pcall(io.open, path, "r+")
    if ok and file then
      state.socket = file
      return true
    end
  end
  return false
end

local function handshake()
  local ok, payload = pcall(Json.encode, { v = 1, client_id = DiscordPresence.APP_ID })
  if not ok or not payload then return false end
  if not sendFrame(OP_HANDSHAKE, payload) then return false end
  -- Discord echoes READY as a FRAME.  A timeout/missing client is a soft miss.
  local opcode = receiveFrame()
  if opcode == OP_FRAME then return true end
  -- Windows named pipes have no easy read timeout: if the write succeeded
  -- and Discord is present, proceed optimistically so boot never blocks.
  if state.isWindows then return true end
  return false
end

local function noteAbsent()
  if state.loggedAbsent then return end
  state.loggedAbsent = true
  -- info, not warn: missing Discord is normal for many players
  Logger.info("discord: rich presence unavailable (Discord not running)")
end

local function connect()
  local ok, result = pcall(function()
    closeSocket()
    local linked
    if state.isWindows then
      linked = connectWindows()
    else
      linked = connectUnix()
    end
    if not linked then return false end
    if not handshake() then
      closeSocket()
      return false
    end
    state.connected = true
    state.dirty = true
    state.lastSentKey = nil
    state.loggedAbsent = false
    state.subscribedJoin = false
    -- ask for "friend clicked join" dispatches; a plain outbound write, so
    -- it's harmless to send even on Windows, where the inbound poll below
    -- isn't implemented yet (see pollJoinRequest)
    if sendFrame(OP_FRAME, Json.encode({
      cmd = "SUBSCRIBE", evt = "ACTIVITY_JOIN", nonce = nonce(),
    })) then
      state.subscribedJoin = true
    end
    Logger.info("discord: rich presence connected")
    return true
  end)
  if not ok then
    closeSocket()
    return false
  end
  return result and true or false
end

local function locationName(game, mapId)
  if not mapId then return nil end
  local field = game and game.data and game.data.field
  local townMap = field and field.townMap
  local locations = townMap and (townMap.locations or townMap)
  local entry = type(locations) == "table" and locations[mapId]
  if type(entry) == "table" then
    local name = entry.name or entry.label
    if type(name) == "string" and name ~= "" then return name end
  end
  local def = game and game.data and game.data.maps and game.data.maps[mapId]
  if def and type(def.label) == "string" and def.label ~= "" then
    -- PalletTown -> Pallet Town
    return def.label:gsub("(%l)(%u)", "%1 %2")
  end
  return tostring(mapId):gsub("_", " ")
end

local function speciesName(game, species)
  if not species or not game or not game.data or not game.data.pokemon then
    return nil
  end
  local def = game.data.pokemon[species]
  return def and def.name or tostring(species):gsub("_", " ")
end

local function buildActivity()
  local details, activityState
  if state.activity == "battle" then
    details = state.battleLabel or Strings("In battle")
    activityState = state.location and (state.location) or "Kanto"
  elseif state.activity == "exploring" and state.location then
    details = state.location
    activityState = "Exploring the overworld"
  else
    details = state.location or "Kanto"
    activityState = "At the title screen"
  end

  local activity = {
    details = details,
    state = activityState,
    timestamps = { start = state.startedAt },
    assets = {
      large_image = "logo",
      large_text = "Pokemon Gen1Recomp",
    },
  }
  -- a party/join-secret pair is what makes Discord show "Ask to Join" on
  -- the profile card; the secret carries our own room/tournament code plus
  -- a one-letter kind tag ("m"/"t") so the click handler on the other end
  -- knows which screen to jump into -- Discord only echoes the string
  -- back, so the kind has to ride inside it
  if state.joinCode then
    local kindTag = state.joinKind == "tournament" and "t" or "m"
    activity.party = { id = "pokeport-" .. state.joinCode,
                       size = { state.partySize, state.partyMax } }
    activity.secrets = { join = "join:" .. kindTag .. ":" .. state.joinCode }
  end
  return activity
end

local function activityKey(activity)
  local partyKey = activity.party
    and (activity.party.size[1] .. "/" .. activity.party.size[2]) or ""
  return (activity.details or "") .. "|" .. (activity.state or "") .. "|"
    .. (activity.secrets and activity.secrets.join or "") .. "|" .. partyKey
end

local function flush(force)
  if not state.enabled or not state.connected then return end
  local ok = pcall(function()
    local now = love.timer.getTime()
    if not force and (now - state.lastSendAt) < MIN_UPDATE_INTERVAL then
      state.dirty = true
      return
    end
    local activity = buildActivity()
    local key = activityKey(activity)
    if not force and key == state.lastSentKey then
      state.dirty = false
      return
    end
    local payload = Json.encode({
      cmd = "SET_ACTIVITY",
      args = {
        pid = resolvePid(),
        activity = activity,
      },
      nonce = nonce(),
    })
    if not sendFrame(OP_FRAME, payload) then
      closeSocket()
      state.nextReconnectAt = now + RECONNECT_INTERVAL
      return
    end
    state.lastSentKey = key
    state.lastSendAt = now
    state.dirty = false
  end)
  if not ok then
    closeSocket()
    local now = love and love.timer and love.timer.getTime and love.timer.getTime() or 0
    state.nextReconnectAt = now + RECONNECT_INTERVAL
  end
end

local function setPresence(fields)
  -- event listeners must never throw into the overworld/battle path
  pcall(function()
    if fields.location ~= nil then state.location = fields.location end
    if fields.mapId ~= nil then state.mapId = fields.mapId end
    if fields.activity ~= nil then state.activity = fields.activity end
    if fields.clearBattle then
      state.battleLabel = nil
    elseif fields.battleLabel ~= nil then
      state.battleLabel = fields.battleLabel
    end
    state.dirty = true
    flush(false)
  end)
end

local function subscribe(game)
  local events = Runtime.events
  if not events or not events.on then return end

  local function track(name, fn)
    state.unsubs[#state.unsubs + 1] = events:on(name, fn, 0, "discord")
  end

  track("map.entered", function(ev)
    local mapId = ev and ev.mapId
    setPresence({
      mapId = mapId,
      location = locationName(game, mapId),
      activity = "exploring",
      clearBattle = true,
    })
  end)

  track("battle.started", function(ev)
    local battle = ev and ev.battle
    local label = Strings("In battle")
    if ev and ev.kind == "wild" then
      local name = speciesName(game, ev.species)
      if name then
        label = "Battling wild " .. name
        if ev.level then label = label .. " Lv" .. tostring(ev.level) end
      else
        label = Strings("Wild battle")
      end
    elseif ev and ev.kind == "trainer" then
      local tname = battle and battle.trainer and battle.trainer.name
      label = tname and ("Battling " .. tname) or Strings("Trainer battle")
    elseif ev and ev.kind == "link" then
      label = Strings("Link battle")
    end
    local mapId = state.mapId
      or (game.save and game.save.player and game.save.player.map)
    setPresence({
      activity = "battle",
      battleLabel = label,
      location = locationName(game, mapId) or state.location,
      mapId = mapId,
    })
  end)

  track("battle.ended", function()
    local mapId = state.mapId
      or (game.save and game.save.player and game.save.player.map)
    setPresence({
      activity = mapId and "exploring" or "menu",
      clearBattle = true,
      location = locationName(game, mapId) or state.location,
      mapId = mapId,
    })
  end)

  track("screen.pushed", function(ev)
    local s = ev and ev.state
    local id = s and s.screenId
    if not id and s and s.onNewGame then id = "TitleState" end
    if id == "TitleState" or id == "IntroMovie" then
      state.mapId = nil
      setPresence({
        activity = "menu",
        location = id == "IntroMovie" and "Watching the intro" or Strings("Title screen"),
        clearBattle = true,
      })
    end
  end)
end

-- Advertise (or clear, with code=nil) an online-match/tournament code as a
-- Discord join secret. LinkState/Tournament call this once they have a
-- real code from the relay, and clear it again once paired/started or the
-- hosting screen exits (an invite that's already full or gone is worse
-- than no invite). kind is "match" (default) or "tournament"; size/max are
-- the party.size Discord shows (default 1/2, a plain 1v1 room) -- a
-- tournament passes its live roster count and a generous cap instead, and
-- should call this again whenever the roster changes, not just once.
function DiscordPresence.setJoinCode(code, kind, size, max)
  pcall(function()
    state.joinCode = code
    state.joinKind = kind or "match"
    state.partySize = size or 1
    state.partyMax = max or 2
    state.dirty = true
    flush(false)
  end)
end

-- A friend clicked "Ask to Join" on our profile and Discord delivered the
-- secret back over this same connection. Only act from a safe spot (never
-- yank the player out of a battle or an already-running link session) --
-- "exploring"/"menu" are the coarse buckets subscribe() above already
-- tracks; anything more specific (a shop, a dialogue box) is a rarer miss
-- worth accepting rather than adding a second, finer-grained state tracker
-- just for this.
local function handleJoinRequest(secret)
  if not secret or secret == "" then return end
  if state.activity == "battle" then return end
  local game = state.game
  if not game or not game.stack then return end
  local top = game.stack:top()
  if top and top.stage and top.net then return end -- already in a link session
  local kindTag, code = secret:match("^(%a):(.+)$")
  if not kindTag then kindTag, code = "m", secret end -- older/plain secret: assume match
  Runtime.emit("discord.join_requested", { code = code, kind = kindTag })
  if kindTag == "t" then
    local ok, Tournament = pcall(require, "src.link.Tournament")
    if ok and Tournament.newJoinOnline then
      game.stack:push(Tournament.newJoinOnline(game, code))
    end
  else
    local ok, LinkState = pcall(require, "src.link.LinkState")
    if ok and LinkState.newJoinOnline then
      game.stack:push(LinkState.newJoinOnline(game, code))
    end
  end
end

-- non-blocking peek for an incoming ACTIVITY_JOIN dispatch. Unix (FFI)
-- only for now: reading a Windows named pipe without risking a stall needs
-- a HANDLE-level PeekNamedPipe that the plain io.open() connection below
-- doesn't give us, so a Windows player's presence/party/join-secret still
-- all work (they can still be seen and clicked), the click just isn't
-- delivered back to their own game session yet.
local function pollJoinRequest()
  if state.isWindows or not state.ffi or not state.socket or not state.subscribedJoin then
    return
  end
  pcall(function()
    local ffi = state.ffi
    local dontwait = MSG_DONTWAIT_BY_OS[love.system.getOS()] or 0
    local hbuf = ffi.new("char[8]")
    local n = ffi.C.recv(state.socket, hbuf, 8, dontwait)
    if not n or tonumber(n) <= 0 then return end -- nothing waiting right now
    local header = ffi.string(hbuf, 8)
    local opcode = unpackU32(header:sub(1, 4))
    local length = unpackU32(header:sub(5, 8))
    if not opcode or not length or length < 0 or length > 65536 then return end
    -- the body may lag the header by a packet; the connection's normal
    -- (short-timeout) blocking read is fine here since it has already
    -- announced its exact length
    local body = length > 0 and readExact(length) or ""
    if body == nil then return end
    if opcode == 3 then -- PING -> PONG, keeps Discord from closing on us
      sendFrame(4, body)
      return
    end
    if opcode ~= 1 then return end
    local decoded = Json.decode(body)
    if decoded and decoded.evt == "ACTIVITY_JOIN" then
      local secret = decoded.data and decoded.data.secret
      if type(secret) == "string" and secret ~= "" then
        if secret:sub(1, 5) == "join:" then secret = secret:sub(6) end
        handleJoinRequest(secret)
      end
    end
  end)
end

function DiscordPresence.init(game)
  local ok, err = pcall(function()
    DiscordPresence.shutdown()
    if disabledByEnv() or not isDesktop() then return end

    state.enabled = true
    state.isWindows = love.system.getOS() == "Windows"
    state.startedAt = os.time()
    state.activity = "menu"
    state.location = "Title screen"
    state.mapId = nil
    state.battleLabel = nil
    state.joinCode = nil
    state.game = game
    state.dirty = true
    state.nextReconnectAt = 0
    state.loggedAbsent = false

    if not state.isWindows and not ensureFfi() then
      -- no FFI / broken cdef: stay disabled, never throw
      state.enabled = false
      return
    end

    subscribe(game)
    if connect() then
      flush(true)
    else
      noteAbsent()
      local now = (love.timer and love.timer.getTime and love.timer.getTime()) or 0
      state.nextReconnectAt = now + RECONNECT_INTERVAL
    end
  end)
  if not ok then
    closeSocket()
    state.enabled = false
    -- still soft: a broken presence stack must not abort boot
    Logger.info("discord: rich presence disabled (%s)", tostring(err))
  end
end

function DiscordPresence.update(_dt)
  if not state.enabled then return end
  pcall(function()
    local now = love.timer.getTime()
    if not state.connected then
      if now >= state.nextReconnectAt then
        state.nextReconnectAt = now + RECONNECT_INTERVAL
        if connect() then
          flush(true)
        else
          noteAbsent()
        end
      end
      return
    end
    pollJoinRequest()
    if state.dirty then flush(false) end
  end)
end

function DiscordPresence.shutdown()
  pcall(function()
    for _, unsub in ipairs(state.unsubs) do
      pcall(unsub)
    end
    state.unsubs = {}
    if state.connected then
      pcall(function()
        -- omit activity to clear the presence
        sendFrame(OP_FRAME, Json.encode({
          cmd = "SET_ACTIVITY",
          args = { pid = resolvePid() },
          nonce = nonce(),
        }))
        sendFrame(OP_CLOSE, "{}")
      end)
    end
    closeSocket()
  end)
  state.enabled = false
  state.dirty = false
  state.lastSentKey = nil
  state.connected = false
  state.socket = nil
  state.subscribedJoin = false
  state.joinCode = nil
end

-- test / debug helpers
DiscordPresence._state = state
DiscordPresence.locationName = locationName
DiscordPresence.handleJoinRequest = handleJoinRequest

return DiscordPresence
