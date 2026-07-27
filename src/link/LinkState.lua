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
local TextBox = require("src.render.TextBox")
local Strings = require("src.core.Strings")

local LinkState = {}
LinkState.__index = LinkState
LinkState.isOpaque = true

local CURSOR = 0xED
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

-- stages before any Net object is meaningfully "this session's link" --
-- .net can still be a leftover failed attempt sitting on self, so error/
-- closed checks below skip these rather than keying off self.net's
-- presence alone
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

function LinkState.new(game)
  local self = setmetatable({}, LinkState)
  self.game = game
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
  self.net = Net.new()
  if self.net:joinOnline(nil, code) then
    self.stage = "onlineJoining"
  else
    self.stage = "menu" -- exitWith below needs a real stage to unwind from
    self:exitWith(Strings("Link error:\n%s", self.net.error or "?"))
  end
  return self
end

function LinkState:exitWith(message, reason)
  DiscordPresence.setJoinCode(nil)
  Runtime.emit("link.ended", { reason = reason or (message and "error" or "bye") })
  if self.net then self.net:close() end
  self.game.stack:pop()
  if message then
    self.game.stack:push(TextBox.new(self.game, message))
  end
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
  local msgs = self.net:poll()
  local keep, got = {}, false
  for _, msg in ipairs(msgs) do
    if msg.type == "hello" and not self.peerHello then
      self.peerHello = msg
      self.peerName = msg.name
      got = true
    else
      keep[#keep + 1] = msg
    end
  end
  for i = #keep, 1, -1 do
    table.insert(self.net.inbox, 1, keep[i])
  end
  return got, #keep > 0
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
    if isHost and mode == "battle" then
      -- host picks the level rule now, before the parties are exchanged
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
    if self.net.error and not PRE_CONNECT_STAGES[self.stage] then
      self:exitWith(Strings("Link error:\n%s", self.net.error:sub(1, 60)))
      return
    end
    -- the peer vanished without a bye (only once the inbox is drained,
    -- so a final message travelling with the disconnect still counts)
    if self.net.closed and #self.net.inbox == 0
       and not PRE_CONNECT_STAGES[self.stage] and self.stage ~= "addrEntry"
       and self.stage ~= "codeEntry" and self.stage ~= "notice"
       and self.stage ~= "battleRunning" then
      self:exitWith(Strings("The link was\nbroken."))
      return
    end
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
          self:exitWith(Strings("Online play needs\nno mods enabled.\fDisable them in\nSTART > MODS."))
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
      self.net = Net.new()
      if self.index == 1 then
        if self.net:host() then
          self.stage = "hosting"
        else
          self:exitWith(Strings("Link error:\n%s", self.net.error or "?"))
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
        self.net = Net.new()
        if self.net:hostOnline() then
          self.stage = "onlineHosting"
        else
          self:exitWith(Strings("Link error:\n%s", self.net.error or "?"))
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
      self.net = Net.new()
      if self.net:joinOnline(nil, code) then
        self.stage = "onlineJoining"
      else
        self:exitWith(Strings("Link error:\n%s", self.net.error or "?"))
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
      if self.net:join(table.concat(octets, ".")) then
        self.stage = "joining"
      else
        self:exitWith(Strings("Link error:\n%s", self.net.error or "?"))
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
    local msgs = self.net:poll()
    for i, msg in ipairs(msgs) do
      if msg.type == "hello" then
        self.peerHello = msg
        self.peerName = msg.name
        -- the host's next messages (party, ...) can share this batch;
        -- put them back so the new stage's poll sees them
        for j = #msgs, i + 1, -1 do
          table.insert(self.net.inbox, 1, msgs[j])
        end
        self:decideCompat(msg.mode, false)
        break
      end
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
    local msgs = self.net:poll()
    for i, msg in ipairs(msgs) do
      if msg.type == "party" then
        -- the host owns this rule (same as mode); the guest only learns
        -- it here, off the host's own party message
        if not self.isHost then self.forceLevel = msg.forceLevel end
        local LinkBattle = require("src.link.LinkBattle")
        local opts = {
          myParty = Protocol.packParty(self.game.save.party),
          theirParty = msg.mons,
          theirName = self.peerName or "FOE",
          seed = self.isHost and self.linkSeed or msg.seed,
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
        self.stage = "battleRunning"
        for j = #msgs, i + 1, -1 do
          table.insert(self.net.inbox, 1, msgs[j])
        end
        break
      end
    end

  elseif self.stage == "battleRunning" then
    if self.game.stack:top() == self then
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

function LinkState:updateTrade(input)
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

  if t.stage == "picking" and input:wasPressed("up") then
    self.index = math.max(1, self.index - 1)
  elseif t.stage == "picking" and input:wasPressed("down") then
    self.index = math.min(#self.game.save.party, self.index + 1)
  elseif self.confirmed == nil and input:wasPressed("b") then
    -- once confirm=true has been sent to the peer, backing out here
    -- would desync the two sides (the peer may already be committing
    -- the trade) -- B is dead after that, matching the A branch's own
    -- self.confirmed == nil guard
    self.net:send({ type = "bye" })
    self:exitWith(Strings("The trade was\ncancelled."))
  elseif t.stage == "picking" and input:wasPressed("a") then
    if t:canPick(self.index) then
      self.net:send(t:pick(self.index))
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
    drawTitle("CHECK YOUR MODS")
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
      if i == self.index then Font.drawCode(CURSOR, 8, 20 + i * 12) end
    end
    Font.draw(Strings("THEIRS"), 84, 20)
    for i, mon in ipairs(t.theirParty or {}) do
      local def = self.game.data.pokemon[mon.species]
      Font.draw((mon.nickname or def.name):sub(1, 8), 92, 20 + i * 12)
      if t.theirPick == i then Font.drawCode(CURSOR, 84, 20 + i * 12) end
    end
    local hint
    if t.stage == "waitRecords" then hint = "Comparing games..."
    elseif t.stage == "waitParty" then hint = "Exchanging data..."
    elseif t.stage == "picking" then
      hint = t:canPick(self.index) and "Pick one to trade"
             or Strings("X: not on theirs")
    elseif t.stage == "waitPick" then hint = "Waiting for them..."
    elseif t.stage == "confirming" then
      hint = self.confirmed and "Waiting..." or Strings("A: trade  B: cancel")
    end
    Font.draw(hint or "", 8, 132)

  elseif self.stage == "battleWait" or self.stage == "battleRunning" then
    drawTitle("LINK BATTLE")
    Font.draw(Strings("Exchanging data..."), 16, 64)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return LinkState
