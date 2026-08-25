-- Link play UI: one player hosts (the screen shows their LAN address),
-- the other joins by typing that address in.  Direct peer-to-peer over
-- lua-enet (bundled with LÖVE),  no relay server.

local CodeEntry = require("src.link.CodeEntry")
local DiscordPresence = require("src.core.DiscordPresence")
local Font = require("src.render.Font")
local Handshake = require("src.link.Handshake")
local Net = require("src.link.Net")
local Protocol = require("src.link.Protocol")
local Runtime = require("src.mods.Runtime")
local Screens = require("src.ui.Screens")
local Session = require("src.link.Session")
local TextBox = require("src.render.TextBox")
local Strings = require("src.core.Strings")

local LinkState = {}
LinkState.__index = LinkState
LinkState.isOpaque = true

local CURSOR = 0xED
local CURSOR_HOLLOW = 0xEC
local ANY = "ANY" -- sentinel: a leading nil array entry breaks ipairs under
                  -- LuaJIT even though # still reports the full size, so
                  -- the level picker cycles this string instead of nil,
                  -- converted to nil only on the wire (see levelForWire)
local FORCE_LEVEL_STEPS = { ANY, 50, 100 }

local function indexOf(list, value)
  for i, v in ipairs(list) do
    if v == value then return i end
  end
  return 1
end

local function levelForWire(v)
  -- ANY ("use each mon's real level") goes on the wire as nil (no forced
  -- level).  An explicit guard, not `v == ANY and nil or v`: that idiom's
  -- true branch is nil, so it falls through to `or v` and returned the
  -- literal "ANY" string, which then crashed math.floor in unpackMon (#204).
  if v == ANY then return nil end
  return v
end

local function forceLevelLabel(v)
  return (v == ANY or v == nil) and "ANY" or ("AUTO " .. tostring(v))
end

-- stages before a successful transport has become this link's Session;
-- terminal checks skip them rather than keying off self.net's presence
local PRE_CONNECT_STAGES = { menu = true, lanMenu = true, onlineMenu = true }

-- how long the host waits for a v2 hello before deciding the peer predates
-- the handshake (a pre-mod guest sends nothing until it hears the mode)
local HELLO_GRACE = 2

-- the joiner edits an IPv4 address as 12 digits (three per octet),
-- prefilled with our own LAN IP so usually only the tail needs changing
local function ipDigits(ip)
  local digits = {}
  local a, b, c, d = (ip or ""):match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
  local octets = { tonumber(a) or 192, tonumber(b) or 168,
                   tonumber(c) or 0, tonumber(d) or 1 }
  for _, o in ipairs(octets) do
    o = math.min(255, o)
    table.insert(digits, math.floor(o / 100))
    table.insert(digits, math.floor(o / 10) % 10)
    table.insert(digits, o % 10)
  end
  return digits
end

local function openSession(role, connect)
  local transport = Net.new()
  if connect(transport) then
    return Session.new(transport, { role = role, kind = "link" })
  end
  local detail = transport.error or "?"
  transport:close()
  return nil, detail
end

function LinkState.new(game)
  local self = setmetatable({}, LinkState)
  self.game = game
  -- a link session runs at 1X on both machines whatever either player set
  -- GAME SPEED to (see Game:logicSpeed); cleared in exitWith
  game.linkSession = true
  self.stage = "menu"
  self.index = 1
  self.addr = ipDigits(Net.lanIP())
  self.addrPos = 12 -- the last octet is what usually differs
  self.status = ""
  return self
end

-- entry point for a Discord "Ask to Join" click (see DiscordPresence.lua):
-- skips the whole LAN/ONLINE/TOURNAMENT menu and jumps straight to
-- "connecting with this code", same as if the player had typed it in
function LinkState.newJoinOnline(game, code)
  local self = LinkState.new(game)
  local session, detail = openSession("guest", function(transport)
    return transport:joinOnline(nil, code)
  end)
  if session then
    self.net = session
    self.stage = "onlineJoining"
  else
    self.stage = "menu" -- exitWith below needs a real stage to unwind from
    self:exitWith(Strings("Link error:\n%s", detail))
  end
  return self
end

-- Adopt a transport that is ALREADY paired and skip the connect UI: an
-- overworld multiplayer session handing one pair of players off to a battle
-- or a trade.  The caller has settled which mode and which side hosts, so
-- all that is left is the hello exchange every link session runs before it
-- commits -- the fingerprint/mod compatibility check still gets its say,
-- exactly as it would have on the LAN or ONLINE path.
--
-- `transport` is anything Session accepts (update/poll/send/close plus the
-- .paired/.closed/.error fields), which is what lets a mod route a battle
-- over a channel of its own.  Ownership transfers with it: exitWith closes
-- the session, so the caller's transport is done once this state unwinds.
--
-- opts.forceLevel  the level rule, normally chosen on the battleOptions
--                  screen; an adopted session has no menu to pick it on
function LinkState.newFromSession(game, transport, mode, isHost, opts)
  local self = LinkState.new(game)
  self.net = Session.new(transport, { role = isHost and "host" or "guest",
                                      kind = "link" })
  self.adopted = true
  self.adoptedMode, self.adoptedHost = mode, isHost and true or false
  self.forceLevel = opts and opts.forceLevel or nil
  self.stage = "adopted"
  self:sendHello(isHost and mode or nil)
  return self
end

function LinkState:exitWith(message, reason)
  DiscordPresence.setJoinCode(nil)
  self.game.linkSession = nil -- back to the player's own GAME SPEED
  if self.game.linkNet == self.net then self.game.linkNet = nil end
  Runtime.emit("link.ended", { reason = reason or (message and "error" or "bye") })
  if self.net then self.net:close() end
  self.game.stack:pop()
  if message then
    self.game.stack:push(TextBox.new(self.game, message))
  end
end

-- Online play meets strangers, so it requires a vanilla simulation on both
-- ends (Handshake.onlineAllowed).  Mods merge into the shared Data
-- registries at boot and there is no unmerge, so switching them off has to
-- go through a relaunch -- but the player should not have to go find the
-- mod manager and work out which mods count.  This turns the blocking mods
-- off, records them so the mod manager can put them back, and relaunches.
-- Verified translations are not blockers (#501), so a player keeps their
-- language across the restart and only the gameplay mods go.  The restart
-- is confirmed rather than silent: it drops unsaved progress.
function LinkState:offerVanillaRestart()
  local game = self.game
  local loader = game.mods
  local mods = Handshake.onlineBlockers(game)
  local names = {}
  for i, mod in ipairs(mods) do
    if i > 2 then break end
    names[#names + 1] = tostring(mod.id):upper():sub(1, 12)
  end
  local list = table.concat(names, ", ")
  if #mods > #names then list = list .. (" +%d"):format(#mods - #names) end
  local text = Strings(
    "Online play runs\nvanilla for both\nplayers.\fTurn off %s\nand restart?", list)
  self.game.linkSession = nil
  Runtime.emit("link.ended", { reason = "error" })
  if self.net then self.net:close() end
  game.stack:pop()
  game.stack:push(TextBox.new(game, text, nil, { choice = function(yes)
    if not yes then return end
    -- setEnabled persists the toggle itself (Loader:_saveState), so the
    -- relaunch comes up vanilla and the mod manager lists them as disabled
    -- for the player to switch back on afterwards
    for _, mod in ipairs(mods) do
      if loader and loader.setEnabled then loader:setEnabled(mod.id, false) end
    end
    if game.restartWithMods then
      game:restartWithMods()
    elseif love.event and love.event.quit then
      love.event.quit("restart")
    end
  end }))
end

-- -------------------------------------------------------------------
-- handshake v2 (D8): both peers announce engine version, api version and
-- a fingerprint of their link surface, and the verdict comes from the two
-- hellos rather than from whoever picked the mode.  The guest announces
-- itself the moment it pairs; the host's hello still carries the mode, so
-- a pre-mod build reads it exactly as it always did.
-- -------------------------------------------------------------------

-- take the peer's hello out of the inbox without eating anything that
-- shares the batch with it
function LinkState:pollHello()
  local message
  if not self.peerHello then message = self.net:take("hello") end
  if message then
    self.peerHello = message
    self.peerName = message.name
  end
  return message ~= nil, self.net:hasPending()
end

function LinkState:sendHello(mode)
  self.myHello = Handshake.hello(self.game, mode)
  self.net:send(self.myHello)
end

function LinkState:decideCompat(mode, isHost)
  self.isHost = isHost
  self.pendingMode = mode
  self.myHello = self.myHello or Handshake.hello(self.game, isHost and mode or nil)
  local peer = self.peerHello
  self.verdict = Handshake.checkCompat(self.myHello, peer)
  Runtime.emit("link.connected", {
    role = isHost and "host" or "guest",
    remote = { name = peer and peer.name or self.peerName, mode = mode,
               mods = peer and peer.mods, fingerprint = peer and peer.fingerprint },
  })
  if self.verdict == "full" or self.verdict == "vanilla_peer" then
    if isHost and mode == "battle" and not self.adopted then
      -- host picks the level rule now, before the parties are exchanged
      -- (an adopted session had it passed in; see newFromSession)
      self.stage = "battleOptions"
    else
      self:startMode(mode, isHost)
    end
    return
  end
  -- naming the difference up front is the whole point: the old behaviour
  -- was a silent draw three turns into a battle that could never work
  self.noticeLines = Handshake.describe(self.myHello, peer, self.verdict, mode)
  self.noticeExits = self.verdict == "refused" or mode ~= "trade"
  self.stage = "notice"
end

-- -------------------------------------------------------------------
-- update
-- -------------------------------------------------------------------

function LinkState:update(dt)
  local input = self.game.input
  if self.net then
    self.net:update()
    local status = self.net:getStatus()
    if status == "failed" and not PRE_CONNECT_STAGES[self.stage] then
      self:exitWith(Strings("Link error:\n%s",
        (self.net.error or "?"):sub(1, 60)))
      return
    end
    -- the peer vanished without a bye (only once the session FIFO drains,
    -- so a final message travelling with the disconnect still counts)
    if status == "closed"
       and not PRE_CONNECT_STAGES[self.stage] and self.stage ~= "addrEntry"
       and self.stage ~= "codeEntry" and self.stage ~= "notice"
       and self.stage ~= "battleRunning" then
      self:exitWith(Strings("The link was\nbroken."))
      return
    end
  end

  -- handed over from an already-paired session (LinkState.newFromSession):
  -- both hellos are in flight, and the first one to land settles compat and
  -- drops us straight into the agreed mode
  if self.stage == "adopted" then
    if self:pollHello() then
      self:decideCompat(self.adoptedMode, self.adoptedHost)
    end
    return
  end

  if self.stage == "menu" then
    if input:wasPressed("down") then
      self.index = self.index % 3 + 1
    elseif input:wasPressed("up") then
      self.index = (self.index - 2) % 3 + 1
    elseif input:wasPressed("b") then
      self:exitWith(nil)
    elseif input:wasPressed("a") then
      if self.index == 1 then
        self.stage = "lanMenu"
        self.index = 1
      elseif self.index == 2 or self.index == 3 then
        if not Handshake.onlineAllowed(self.game) then
          self:offerVanillaRestart()
          return
        end
        if self.index == 2 then
          self.stage = "onlineMenu"
        else
          local Tournament = require("src.link.Tournament")
          self.game.stack:pop()
          self.game.stack:push(Tournament.new(self.game))
        end
        self.index = 1
      end
    end

  elseif self.stage == "lanMenu" then
    if input:wasPressed("up") or input:wasPressed("down") then
      self.index = self.index == 1 and 2 or 1
    elseif input:wasPressed("b") then
      self.stage = "menu"
      self.index = 1
    elseif input:wasPressed("a") then
      if self.index == 1 then
        local session, detail = openSession("host", function(transport)
          return transport:host()
        end)
        if session then
          self.net = session
          self.stage = "hosting"
        else
          self:exitWith(Strings("Link error:\n%s", detail))
        end
      else
        self.stage = "addrEntry"
      end
    end

  elseif self.stage == "onlineMenu" then
    if input:wasPressed("up") or input:wasPressed("down") then
      self.index = self.index == 1 and 2 or 1
    elseif input:wasPressed("b") then
      self.stage = "menu"
      self.index = 2
    elseif input:wasPressed("a") then
      if self.index == 1 then
        local session, detail = openSession("host", function(transport)
          return transport:hostOnline()
        end)
        if session then
          self.net = session
          self.stage = "onlineHosting"
        else
          self:exitWith(Strings("Link error:\n%s", detail))
        end
      else
        self.stage = "codeEntry"
        self.codeEntry = CodeEntry.new()
      end
    end

  elseif self.stage == "onlineHosting" then
    if not self.discordCodeSet and self.net.code then
      DiscordPresence.setJoinCode(self.net.code)
      self.discordCodeSet = true
    end
    if input:wasPressed("b") then self:exitWith(nil) return end
    if self.net.paired then
      DiscordPresence.setJoinCode(nil) -- someone's here now; stop advertising
      self.stage = "modeSelect"
      self.index = 1
    end

  elseif self.stage == "codeEntry" then
    if input:wasPressed("b") then
      self.stage = "onlineMenu"
      self.index = 2
    elseif input:wasPressed("up") then
      CodeEntry.up(self.codeEntry)
    elseif input:wasPressed("down") then
      CodeEntry.down(self.codeEntry)
    elseif input:wasPressed("left") then
      CodeEntry.left(self.codeEntry)
    elseif input:wasPressed("right") then
      CodeEntry.right(self.codeEntry)
    elseif input:wasPressed("a") then
      local code = CodeEntry.text(self.codeEntry)
      local session, detail = openSession("guest", function(transport)
        return transport:joinOnline(nil, code)
      end)
      if session then
        self.net = session
        self.stage = "onlineJoining"
      else
        self:exitWith(Strings("Link error:\n%s", detail))
      end
    end

  elseif self.stage == "onlineJoining" then
    if input:wasPressed("b") then self:exitWith(nil) return end
    if self.net.paired then
      self.stage = "waitMode"
      self:sendHello(nil) -- the host owns the mode; this is just who we are
    end

  elseif self.stage == "hosting" then
    if input:wasPressed("b") then self:exitWith(nil) return end
    if self.net.paired then
      self.stage = "modeSelect"
      self.index = 1
    end

  elseif self.stage == "addrEntry" then
    if input:wasPressed("b") then self:exitWith(nil) return end
    if input:wasPressed("up") then
      self.addr[self.addrPos] = (self.addr[self.addrPos] + 1) % 10
    elseif input:wasPressed("down") then
      self.addr[self.addrPos] = (self.addr[self.addrPos] - 1) % 10
    elseif input:wasPressed("left") then
      self.addrPos = math.max(1, self.addrPos - 1)
    elseif input:wasPressed("right") then
      self.addrPos = math.min(12, self.addrPos + 1)
    elseif input:wasPressed("a") then
      local octets = {}
      for i = 1, 4 do
        local base = (i - 1) * 3
        octets[i] = math.min(255, self.addr[base + 1] * 100
                                  + self.addr[base + 2] * 10
                                  + self.addr[base + 3])
      end
      local address = table.concat(octets, ".")
      local session, detail = openSession("guest", function(transport)
        return transport:join(address)
      end)
      if session then
        self.net = session
        self.stage = "joining"
      else
        self:exitWith(Strings("Link error:\n%s", detail))
      end
    end

  elseif self.stage == "joining" then
    if input:wasPressed("b") then self:exitWith(nil) return end
    if self.net.paired then
      self.stage = "waitMode"
      self:sendHello(nil) -- the host owns the mode; this is just who we are
    end

  elseif self.stage == "modeSelect" then -- host picks
    self:pollHello()
    if input:wasPressed("up") or input:wasPressed("down") then
      self.index = self.index == 1 and 2 or 1
    elseif input:wasPressed("a") then
      local mode = self.index == 1 and "trade" or "battle"
      self:sendHello(mode)
      if self.peerHello then
        self:decideCompat(mode, true)
      else
        self.pendingMode = mode
        self.helloWait = 0
        self.stage = "waitHello"
      end
    elseif input:wasPressed("b") then
      self:exitWith(nil)
    end

  elseif self.stage == "battleOptions" then -- host picks the level rule,
                                             -- once compat is confirmed and
                                             -- before parties are exchanged
    self.levelChoice = self.levelChoice or ANY
    if input:wasPressed("b") then
      self:exitWith(nil)
    elseif input:wasPressed("up") or input:wasPressed("down")
        or input:wasPressed("left") or input:wasPressed("right") then
      local delta = (input:wasPressed("down") or input:wasPressed("left")) and -1 or 1
      local i = indexOf(FORCE_LEVEL_STEPS, self.levelChoice)
      i = ((i - 1 + delta) % #FORCE_LEVEL_STEPS) + 1
      self.levelChoice = FORCE_LEVEL_STEPS[i]
    elseif input:wasPressed("a") then
      self.forceLevel = levelForWire(self.levelChoice)
      self:startMode(self.pendingMode, true)
    end

  elseif self.stage == "waitHello" then -- host waits for the peer's hello
    if input:wasPressed("b") then self:exitWith(nil) return end
    local got, other = self:pollHello()
    self.helloWait = self.helloWait + (dt or 0)
    -- a pre-mod peer never sends one: it just gets on with the mode, so
    -- its first message -- or the grace period -- is the answer
    if got or other or self.helloWait > HELLO_GRACE then
      self:decideCompat(self.pendingMode, true)
    end

  elseif self.stage == "waitMode" then -- guest waits for host's pick
    if input:wasPressed("b") then self:exitWith(nil) return end
    local message = self.net:take("hello")
    if message then
      self.peerHello = message
      self.peerName = message.name
      self:decideCompat(message.mode, false)
    end

  elseif self.stage == "notice" then
    if input:wasPressed("b") or (self.noticeExits and input:wasPressed("a")) then
      self.net:send({ type = "bye" })
      self:exitWith(nil, "error")
    elseif input:wasPressed("a") then
      self:startMode(self.pendingMode, self.isHost)
    end

  elseif self.stage == "trade" then
    self:updateTrade(input)

  elseif self.stage == "battleWait" then
    if input:wasPressed("b") then self:exitWith(nil) return end
    local message = self.net:take("party")
    if message then
      -- the host owns this rule (same as mode); the guest only learns
      -- it here, off the host's own party message
      if not self.isHost then self.forceLevel = message.forceLevel end
      local LinkBattle = require("src.link.LinkBattle")
      local opts = {
        myParty = Protocol.packParty(self.game.save.party),
        theirParty = message.mons,
        theirName = self.peerName or "FOE",
        seed = self.isHost and self.linkSeed or message.seed,
        verdict = self.verdict,
        strict = Handshake.strict(self.verdict),
        forceLevel = self.forceLevel,
      }
      local battle, why
      if self.isHost then
        battle, why = LinkBattle.newHost(self.game, self.net, opts)
      else
        battle, why = LinkBattle.newGuest(self.game, self.net, opts)
      end
      if not battle then
        self.net:send({ type = "bye" })
        self:exitWith(why or Strings("Link battle\ncan't start."), "error")
        return
      end
      self.game.stack:push(battle)
      self.battle = battle
      self.stage = "battleRunning"
    end

  elseif self.stage == "battleRunning" then
    if self.game.stack:top() == self then
      -- the lockstep copies carry the damage the real party never takes
      -- (cable rules), so a mode that wants it -- a tournament ladder, a
      -- battle royale -- reads it from here before the state unwinds
      local battle = self.battle
      if battle and Runtime.wants("link.battle_ended") then
        Runtime.emit("link.battle_ended", {
          result = battle.result or "ended",
          myParty = battle.playerParty,
          theirParty = battle.enemyParty,
          peerName = self.peerName,
          role = self.isHost and "host" or "guest",
        })
      end
      self.battle = nil
      self:exitWith(nil) -- battle finished
    end
  end
end

function LinkState:startMode(mode, isHost)
  self.isHost = isHost
  if mode == "trade" then
    self.stage = "trade"
    -- a subset session settles which mons both games rebuild identically
    -- before either party goes out, so a pick can't land on a mon the
    -- other side would reconstruct differently
    self.trade = Protocol.TradeSession.new(self.game.data, self.game.save.party, {
      subset = self.verdict == "subset",
      strict = Handshake.strict(self.verdict),
      peerName = self.peerName,
    })
    self.net:send(self.trade:opening())
    self.index = 1
    self.theirIndex = 1
    self.side = "mine"
    self.pickChoice = nil
  else
    self.stage = "battleWait"
    -- the host deals the shared RNG seed for the lockstep simulation
    if isHost then
      self.linkSeed = love.math.random(1, 2 ^ 30)
    end
    self.net:send({ type = "party",
                    mons = Protocol.packParty(self.game.save.party),
                    seed = self.linkSeed,
                    forceLevel = isHost and self.forceLevel or nil })
  end
end

-- -------------------------------------------------------------------
-- trade flow
-- -------------------------------------------------------------------

function LinkState:openStats(mon)
  if not mon then return end
  self.game.linkNet = self.net
  Screens.push(self.game, "SummaryMenu", mon)
end

function LinkState:updateTrade(input)
  if self.game.linkNet == self.net then self.game.linkNet = nil end
  for _, msg in ipairs(self.net:poll()) do
    local reply = self.trade:handle(msg)
    if reply then self.net:send(reply) end
  end
  local t = self.trade

  if t.stage == "cancelled" then
    self:exitWith(t.error and Strings("The trade stopped:\n%s.", t.error)
                  or Strings("The trade was\ncancelled."))
    return
  end
  if t.stage == "done" then
    local sent = t.party[t.myPick]
    local received, evoTo = t:apply(self.game)
    -- Autosave the instant the swap commits into game.save.party, matching the
    -- Cable Club: pokered engine/link/cable_club.asm calls SaveSAVtoSRAM
    -- (engine/menus/save.asm) right after every trade so the trade is on the
    -- cartridge before the animation runs.  Without this the received mon
    -- lives only in memory until a manual START-menu save, so a force-quit
    -- would lose it and a reset would clone the sent mon (#222).  Guarded so
    -- headless LinkBattle-style fake games with no writeSave are unaffected.
    if self.game.writeSave then self.game:writeSave() end
    local name = received.nickname or self.game.data.pokemon[received.species].name
    Runtime.emit("link.ended", { reason = "done" })
    self.game.linkSession = nil -- this path pops without exitWith
    self.net:close()
    self.game.stack:pop()
    local game = self.game
    require("src.core.Sound").play(game.data, "Trade_Machine")
    Screens.push(game, "TradeAnim", {
      sent = sent, received = received,
      enemyName = (self.peerName or "TRAINER"),
      playerOt = game.save.player.name,
      playerOtId = sent.otId or game.save.player.id,
      enemyOtId = received.otId,
      onDone = function()
        game.stack:push(TextBox.new(game,
          Strings("Trade completed!\f%s received\n%s!", game.save.player.name, name),
          function()
            if evoTo then
              -- via="TRADE": a trade evolution cannot be B-cancelled
              -- (pokered LINK_STATE_TRADING skips the flash B-poll) (#213).
              -- Re-save once the evolution movie finishes so the evolved
              -- species (not the pre-evo landed by t:apply) is what persists,
              -- keeping disk in step with the autosave above (#222).
              require("src.pokemon.Evolution").evolve(game, received, evoTo,
                function() if game.writeSave then game:writeSave() end end, "TRADE")
            end
          end))
      end,
    })
    return
  end

  -- pokered engine/link/cable_club.asm TradeCenter_SelectMon: A on one of
  -- your own mons opens the "STATS     TRADE" row (.displayStatsTradeMenu)
  -- and only TRADE commits the pick, while the enemy list carries its own
  -- cursor whose A shows that mon's status pages (.displayEnemyMonStats).
  -- The cart's enemy path sets hl but never wMonDataLocation, the way the
  -- battle menu's STATS (engine/battle/core.asm) does, so LoadMonData_ reads
  -- the player's party and it draws YOUR mon at that slot -- an omission,
  -- not behaviour, so we show the peer's mon.
  if t.stage == "picking" and self.pickChoice then
    if input:wasPressed("left") then
      self.pickChoice = 1
    elseif input:wasPressed("right") then
      self.pickChoice = 2
    elseif input:wasPressed("b") then
      self.pickChoice = nil -- .cancelPlayerMonChoice: back to the list, not
                            -- out of the trade
    elseif input:wasPressed("a") then
      if self.pickChoice == 1 then
        self.pickChoice = nil
        self:openStats(self.game.save.party[self.index])
      elseif t:canPick(self.index) then
        self.pickChoice = nil
        self.side = "mine"
        self.net:send(t:pick(self.index))
      end
    end
  elseif t.stage == "picking" and input:wasPressed("up") then
    if self.side == "theirs" then
      self.theirIndex = math.max(1, self.theirIndex - 1)
    else
      self.index = math.max(1, self.index - 1)
    end
  elseif t.stage == "picking" and input:wasPressed("down") then
    if self.side == "theirs" then
      self.theirIndex = math.min(#(t.theirParty or {}), self.theirIndex + 1)
    else
      self.index = math.min(#self.game.save.party, self.index + 1)
    end
  elseif t.stage == "picking" and input:wasPressed("right") then
    if t.theirParty and #t.theirParty > 0 then
      self.side = "theirs"
      self.theirIndex = math.min(self.theirIndex, #t.theirParty)
    end
  elseif t.stage == "picking" and input:wasPressed("left") then
    self.side = "mine"
  elseif self.confirmed == nil and input:wasPressed("b") then
    -- once confirm=true has been sent to the peer, backing out here
    -- would desync the two sides (the peer may already be committing
    -- the trade) -- B is dead after that, matching the A branch's own
    -- self.confirmed == nil guard
    self.net:send({ type = "bye" })
    self:exitWith(Strings("The trade was\ncancelled."))
  elseif t.stage == "picking" and input:wasPressed("a") then
    if self.side == "theirs" then
      self:openStats((t.theirParty or {})[self.theirIndex])
    else
      self.pickChoice = 1
    end
  elseif t.stage == "confirming" and self.confirmed == nil then
    if input:wasPressed("a") then
      self.confirmed = true
      self.net:send(t:confirm(true))
    end
  end
end

-- -------------------------------------------------------------------
-- draw
-- -------------------------------------------------------------------

local function drawTitle(text)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(text, 8, 6)
end

function LinkState:draw()
  if self.stage == "menu" then
    drawTitle("BOIS CLUB LIVE")
    Font.draw(Strings("LINK CABLE (LAN)"), 32, 44)
    Font.draw(Strings("ONLINE MATCH"), 32, 60)
    Font.draw(Strings("TOURNAMENT"), 32, 76)
    Font.drawCode(CURSOR, 24, 44 + (self.index - 1) * 16)

  elseif self.stage == "lanMenu" then
    drawTitle("LINK CABLE (LAN)")
    Font.draw(Strings("HOST A GAME"), 32, 48)
    Font.draw(Strings("JOIN A GAME"), 32, 68)
    Font.drawCode(CURSOR, 24, self.index == 1 and 48 or 68)
    Font.draw(Strings("UDP port %s", Net.defaultPort()), 8, 128)

  elseif self.stage == "onlineMenu" then
    drawTitle("ONLINE MATCH")
    Font.draw(Strings("HOST ONLINE"), 32, 48)
    Font.draw(Strings("JOIN ONLINE"), 32, 68)
    Font.drawCode(CURSOR, 24, self.index == 1 and 48 or 68)

  elseif self.stage == "onlineHosting" then
    drawTitle("HOSTING ONLINE")
    Font.draw(Strings("Tell your friend"), 16, 40)
    Font.draw(Strings("the code:"), 16, 52)
    Font.draw(self.net.code or "??????", 32, 68)
    Font.draw(Strings("Waiting for join..."), 8, 96)

  elseif self.stage == "codeEntry" then
    drawTitle("ENTER CODE")
    for i = 1, CodeEntry.LENGTH do
      local x = 16 + (i - 1) * 16
      local ch = CodeEntry.CHARSET:sub(self.codeEntry.chars[i], self.codeEntry.chars[i])
      Font.draw(ch, x, 64)
      if i == self.codeEntry.pos then
        Font.drawCode(0xEE, x, 76) -- ▼ under the active slot
      end
    end
    Font.draw(Strings("A: connect  B: back"), 8, 128)

  elseif self.stage == "onlineJoining" then
    drawTitle("CONNECTING...")
    Font.draw(Strings("Calling..."), 8, 56)
    Font.draw(self.net.target or "", 8, 72)

  elseif self.stage == "hosting" then
    drawTitle("HOSTING")
    Font.draw(Strings("Friend joins at:"), 16, 48)
    Font.draw(self.net.address or "?", 16, 64)
    Font.draw(Strings("Waiting for join..."), 8, 96)

  elseif self.stage == "addrEntry" then
    drawTitle("ENTER HOST ADDRESS")
    for i = 1, 12 do
      local octet = math.floor((i - 1) / 3) -- 0..3
      local x = 16 + (i - 1) * 8 + octet * 8 -- gap for the dots
      Font.draw(tostring(self.addr[i]), x, 64)
      if i == self.addrPos then
        Font.drawCode(0xEE, x, 76) -- ▼ under the active digit
      end
    end
    for octet = 1, 3 do
      Font.draw(".", 16 + octet * 32 - 8, 64)
    end
    Font.draw(Strings("Port: %s", Net.defaultPort()), 16, 96)
    Font.draw(Strings("A: connect  B: back"), 8, 128)

  elseif self.stage == "joining" then
    drawTitle("JOINING...")
    Font.draw(Strings("Calling..."), 8, 56)
    Font.draw(self.net.target or "", 8, 72)

  elseif self.stage == "modeSelect" then
    drawTitle("CONNECTED!")
    Font.draw(Strings("TRADE"), 32, 48)
    Font.draw(Strings("BATTLE"), 32, 68)
    Font.drawCode(CURSOR, 24, self.index == 1 and 48 or 68)

  elseif self.stage == "battleOptions" then
    drawTitle("BATTLE OPTIONS")
    Font.draw(Strings("LEVELS:"), 16, 56)
    Font.draw(forceLevelLabel(self.levelChoice or ANY), 88, 56)
    Font.draw(Strings("A: continue  B: back"), 8, 128)

  elseif self.stage == "waitMode" or self.stage == "waitHello" then
    drawTitle("CONNECTED!")
    if self.stage == "waitHello" then
      Font.draw(Strings("Checking the"), 16, 56)
      Font.draw(Strings("other game..."), 16, 72)
    else
      Font.draw(Strings("Waiting for the"), 16, 56)
      Font.draw(Strings("host to choose..."), 16, 72)
    end

  elseif self.stage == "notice" then
    -- a version-skew notice has nothing to do with mods (#758)
    drawTitle(self.verdict == "engine_skew" and "UPDATE YOUR GAME"
                                             or "CHECK YOUR MODS")
    for i, line in ipairs(self.noticeLines or {}) do
      if i > 8 then break end -- what fits above the prompt row
      Font.draw(line, 8, 24 + (i - 1) * 12)
    end
    Font.draw(self.noticeExits and "A: back" or Strings("A: trade anyway"), 8, 128)

  elseif self.stage == "trade" then
    drawTitle("TRADE")
    local t = self.trade
    Font.draw(Strings("YOURS"), 8, 20)
    for i, mon in ipairs(self.game.save.party) do
      local def = self.game.data.pokemon[mon.species]
      local label = (mon.nickname or def.name):sub(1, 8)
      if not t:canPick(i) then label = label .. "X" end
      Font.draw(label, 16, 20 + i * 12)
      if i == self.index and self.side ~= "theirs" then
        Font.drawCode(CURSOR, 8, 20 + i * 12)
      end
    end
    Font.draw(Strings("THEIRS"), 84, 20)
    for i, mon in ipairs(t.theirParty or {}) do
      local def = self.game.data.pokemon[mon.species]
      Font.draw((mon.nickname or def.name):sub(1, 8), 92, 20 + i * 12)
      if self.side == "theirs" and i == self.theirIndex then
        Font.drawCode(CURSOR, 84, 20 + i * 12)
      elseif t.theirPick == i then
        Font.drawCode(CURSOR_HOLLOW, 84, 20 + i * 12)
      end
    end
    if self.pickChoice then
      Font.draw(Strings("STATS"), 16, 128)
      Font.draw(Strings("TRADE"), 96, 128)
      Font.drawCode(CURSOR, self.pickChoice == 1 and 8 or 88, 128)
    else
      local hint
      if t.stage == "waitRecords" then hint = "Comparing games..."
      elseif t.stage == "waitParty" then hint = "Exchanging data..."
      elseif t.stage == "picking" then
        if self.side == "theirs" then hint = Strings("A: stats")
        else
          hint = t:canPick(self.index) and "Pick one to trade"
                 or Strings("X: not on theirs")
        end
      elseif t.stage == "waitPick" then hint = "Waiting for them..."
      elseif t.stage == "confirming" then
        hint = self.confirmed and "Waiting..." or Strings("A: trade  B: cancel")
      end
      Font.draw(hint or "", 8, 132)
    end

  elseif self.stage == "battleWait" or self.stage == "battleRunning" then
    drawTitle("LINK BATTLE")
    Font.draw(Strings("Exchanging data..."), 16, 64)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return LinkState
