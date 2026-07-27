-- Tournament play: host or join a bracket over the pokeserver relay.
-- Single-elimination, server-managed (pokeserver's `tournaments` map).
-- Matches run one at a time in bracket order; everyone not currently
-- playing -- still waiting their turn, or already eliminated -- watches
-- the live match play out via LinkBattle.newSpectator, reconstructed from
-- a copy of the real traffic the server fans out. Battle mode only (no
-- trade); vanilla only (Handshake.onlineAllowed already gated entry here
-- from LinkState). Elite Four music (Music_IndigoPlateau) loops the whole
-- time, uninterrupted by individual matches.

local CodeEntry = require("src.link.CodeEntry")
local DiscordPresence = require("src.core.DiscordPresence")
local Font = require("src.render.Font")
local Handshake = require("src.link.Handshake")
local LinkBattle = require("src.link.LinkBattle")
local Net = require("src.link.Net")
local Protocol = require("src.link.Protocol")
local Runtime = require("src.mods.Runtime")
local Sound = require("src.core.Sound")
local TextBox = require("src.render.TextBox")
local Strings = require("src.core.Strings")

local Tournament = {}
Tournament.__index = Tournament
Tournament.isOpaque = true

local CURSOR = 0xED
local MUSIC = "Music_IndigoPlateau"
local TURN_LIMITS = { 3, 6, 9 }
local PARTY_SIZES = { 1, 2, 3, 4, 5, 6 }
local ANY = "ANY" -- sentinel: a leading *nil* array entry breaks ipairs
                  -- (LuaJIT's # still reports the literal's full size, but
                  -- ipairs stops dead at the hole), so level bounds use
                  -- this string in self.settings instead of nil, converted
                  -- to nil only on the wire
local LEVEL_STEPS = { ANY, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60, 65,
                       70, 75, 80, 85, 90, 95, 100 }
local SETTINGS_ROWS = 6 -- POKEMON, MIN LV, MAX LV, TIMER, LEVELS, PLAYING
-- LEVELS cycles through this: ANY (real levels) or a fixed level every
-- match normalizes to, regardless of each side's real party
local FORCE_LEVEL_STEPS = { ANY, 50, 100 }
-- tournaments have no real participant cap (any number can join before
-- start); this is just generous headroom so Discord's party.size never
-- reads as "full" and blocks a real invite click
local TOURNAMENT_PARTY_MAX = 16

local function indexOf(list, value)
  for i, v in ipairs(list) do
    if v == value then return i end
  end
  return 1
end

-- accepts either the internal ANY sentinel or a raw wire value (nil means
-- "any" there too, since the server never round-trips the sentinel string)
local function levelLabel(v)
  return (v == ANY or v == nil) and "ANY" or tostring(v)
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

local function partyStats(party)
  local size, minLevel, maxLevel = 0, nil, nil
  for _, mon in ipairs(party or {}) do
    size = size + 1
    local lvl = mon.level or 1
    minLevel = minLevel and math.min(minLevel, lvl) or lvl
    maxLevel = maxLevel and math.max(maxLevel, lvl) or lvl
  end
  return size, minLevel or 0, maxLevel or 0
end

function Tournament.new(game)
  local self = setmetatable({}, Tournament)
  self.game = game
  self.stage = "menu"
  self.index = 1
  self.settings = { turnLimit = 6, requiredPartySize = 3, minLevel = ANY, maxLevel = ANY,
                    forceLevel = ANY, participating = true }
  self.settingsIndex = 1
  self.roster = {}
  self.spectatorRoster = {}
  Sound.startLoop(game.data, MUSIC)
  return self
end

-- entry point for a Discord "Ask to Join" click on a tournament invite
-- (see DiscordPresence.lua): skips the HOST/JOIN menu and code entry,
-- straight to "connecting with this code"
function Tournament.newJoinOnline(game, code)
  local self = Tournament.new(game)
  self:startJoining(code)
  return self
end

-- headcount for Discord's party.size: the roster only ever lists
-- competing players, so a non-participating (organizer-only) host isn't
-- in it even though they're right here running the thing
function Tournament:discordPartySize()
  return #self.roster + (self.participating == false and 1 or 0)
end

function Tournament:exitWith(message)
  DiscordPresence.setJoinCode(nil)
  Sound.stopLoop(MUSIC)
  Runtime.emit("link.ended", { reason = message and "error" or "bye" })
  if self.net then self.net:close() end
  self.game.stack:pop()
  if message then
    self.game.stack:push(TextBox.new(self.game, message))
  end
end

-- -------------------------------------------------------------------
-- host / join
-- -------------------------------------------------------------------

function Tournament:startHosting()
  self.net = Net.new()
  if not self.net:connectTCP(Net.defaultRelayAddress()) then
    self:exitWith(Strings("Link error:\n%s", self.net.error or "?"))
    return
  end
  local size, minL, maxL = partyStats(self.game.save.party)
  self.isCreator = true
  self.participating = self.settings.participating
  self.net:send({
    type = "host_tournament",
    turnLimit = self.settings.turnLimit,
    requiredPartySize = self.settings.requiredPartySize,
    minLevel = levelForWire(self.settings.minLevel),
    maxLevel = levelForWire(self.settings.maxLevel),
    forceLevel = levelForWire(self.settings.forceLevel),
    participating = self.settings.participating,
    name = self.game.save.player.name,
    partySize = size, partyMinLevel = minL, partyMaxLevel = maxL,
  })
  self.stage = "registering"
end

function Tournament:startJoining(code)
  self.net = Net.new()
  if not self.net:connectTCP(Net.defaultRelayAddress()) then
    self:exitWith(Strings("Link error:\n%s", self.net.error or "?"))
    return
  end
  local size, minL, maxL = partyStats(self.game.save.party)
  self.isCreator = false
  self.participating = true -- joining is always to compete; only hosting can opt out
  self.code = code
  self.net:send({
    type = "join_tournament", code = code, name = self.game.save.player.name,
    partySize = size, partyMinLevel = minL, partyMaxLevel = maxL,
  })
  self.stage = "registering"
end

-- -------------------------------------------------------------------
-- message handling (shared between "registering"/"bracket" and drained
-- again from a just-finished match's pendingTournamentMessages)
-- -------------------------------------------------------------------

local JOIN_ERROR_TEXT = {
  not_found = Strings.source("That code wasn't\nfound."),
  already_started = Strings.source("That tournament\nhas already begun."),
  expired = Strings.source("That code has\nexpired."),
}

function Tournament:handleMessage(msg)
  if msg.type == "tournament_hosted" then
    self.code = msg.code
    self.settings.turnLimit = msg.turnLimit
    self.settings.forceLevel = msg.forceLevel == nil and ANY or msg.forceLevel
    self.participating = msg.participating
    self.stage = "bracket"
    -- the server already seeded t.players/spectators with the creator at
    -- creation time; mirror that here so the Discord party size (and the
    -- "waiting for players" list) show the host from the very first frame,
    -- not just once someone else joins and a real roster broadcast arrives
    if self.participating then
      self.roster = { self.game.save.player.name }
    else
      self.spectatorRoster = { self.game.save.player.name }
    end
    if self.isCreator then
      DiscordPresence.setJoinCode(self.code, "tournament",
        self:discordPartySize(), TOURNAMENT_PARTY_MAX)
    end
  elseif msg.type == "tournament_host_error" then
    if msg.reason == "party_ineligible" then
      self:exitWith(Strings("Can't host:\nneed %d Pokemon\nLv %s-%s.", msg.requiredPartySize, levelLabel(msg.minLevel), levelLabel(msg.maxLevel)))
    else
      self:exitWith(Strings("Couldn't host\nthat tournament."))
    end
  elseif msg.type == "tournament_join_error" then
    if msg.reason == "party_ineligible" then
      self:exitWith(Strings("Your party needs\n%d Pokemon, Lv\n%s-%s.", msg.requiredPartySize, levelLabel(msg.minLevel), levelLabel(msg.maxLevel)))
    else
      self:exitWith(JOIN_ERROR_TEXT[msg.reason]
                    and Strings(JOIN_ERROR_TEXT[msg.reason])
                    or Strings("Couldn't join\nthat tournament."))
    end
  elseif msg.type == "tournament_roster" then
    self.roster = msg.players
    self.spectatorRoster = msg.spectators or {}
    self.settings.turnLimit = msg.turnLimit
    self.settings.requiredPartySize = msg.requiredPartySize
    self.settings.minLevel = msg.minLevel == nil and ANY or msg.minLevel
    self.settings.maxLevel = msg.maxLevel == nil and ANY or msg.maxLevel
    self.settings.forceLevel = msg.forceLevel == nil and ANY or msg.forceLevel
    self.stage = "bracket"
    if self.isCreator and self.code then
      DiscordPresence.setJoinCode(self.code, "tournament",
        self:discordPartySize(), TOURNAMENT_PARTY_MAX)
    end
  elseif msg.type == "bracket_update" then
    self.bracket = msg.tournament
    self.code = self.bracket.code
    if self.stage == "registering" then self.stage = "bracket" end
  elseif msg.type == "match_start" then
    self:enterMatch(msg)
  elseif msg.type == "match_start_spectate" then
    self:enterSpectate(msg)
  elseif msg.type == "tournament_bye" then
    self.byeRound = msg.round
  elseif msg.type == "tournament_over" then
    self.champion = msg.champion
    self.stage = "done"
  end
end

-- -------------------------------------------------------------------
-- entering a match: real participant
-- -------------------------------------------------------------------

function Tournament:sendHello(mode)
  self.myHello = Handshake.hello(self.game, mode)
  self.net:send(self.myHello)
end

function Tournament:pollHello()
  local msgs = self.net:poll()
  local keep, got = {}, false
  for _, msg in ipairs(msgs) do
    if msg.type == "hello" and not self.peerHello then
      self.peerHello = msg
      got = true
    else
      keep[#keep + 1] = msg
    end
  end
  for i = #keep, 1, -1 do
    table.insert(self.net.inbox, 1, keep[i])
  end
  return got
end

function Tournament:enterMatch(msg)
  self.isHost = (msg.role == "host")
  self.opponentName = msg.opponent
  self.matchRound = msg.round
  self.matchTurnLimit = msg.turnLimit
  self.peerHello = nil
  self:sendHello(self.isHost and "battle" or nil)
  self.stage = "matchHello"
end

function Tournament:beginMatchBattle()
  local verdict = Handshake.checkCompat(self.myHello, self.peerHello)
  if not (verdict == "full" or verdict == "vanilla_peer") then
    -- shouldn't happen (both sides already passed the online-play mods
    -- gate), but a mismatched engine/build is still possible -- bail out
    -- of just this match rather than crash the tournament
    self:exitWith(Strings("Link error:\nversion mismatch\nwith opponent."))
    return
  end
  self.linkSeed = self.isHost and love.math.random(1, 2 ^ 30) or nil
  local opts = {
    myParty = Protocol.packParty(self.game.save.party),
    theirName = self.opponentName or "FOE",
    seed = self.isHost and self.linkSeed or nil,
    verdict = verdict,
    strict = Handshake.strict(verdict),
    turnLimit = self.matchTurnLimit,
    forceLevel = levelForWire(self.settings.forceLevel),
    keepNetOpen = true, -- this is the tournament's own connection, not a
                        -- dedicated match socket -- don't let finish() close it
  }
  self.stage = "matchWaitParty"
  self.pendingBattleOpts = opts
  self.net:send({ type = "party",
                  mons = Protocol.packParty(self.game.save.party),
                  seed = self.linkSeed })
end

-- -------------------------------------------------------------------
-- entering a match: spectator
-- -------------------------------------------------------------------

function Tournament:enterSpectate(msg)
  self.matchRound = msg.round
  self.spectate = {
    hostName = msg.playerHost, guestName = msg.playerGuest,
    hostParty = nil, guestParty = nil, seed = nil,
  }
  self.stage = "spectateWait"
end

-- -------------------------------------------------------------------
-- update
-- -------------------------------------------------------------------

function Tournament:update(dt)
  local input = self.game.input

  if self.stage == "matchRunning" or self.stage == "spectateRunning" then
    if self.game.stack:top() == self then
      -- the battle popped; drain anything the network handed to it but it
      -- didn't itself understand (a bracket_update, the next match...)
      local battle = self.activeBattle
      self.activeBattle = nil
      if self.stage == "matchRunning" and battle and battle.result and self.net
         and not self.net.closed then
        -- a real participant reports its own outcome; the server resolves
        -- the match once both sides have (or one disconnects)
        self.net:send({ type = "tournament_result", result = battle.result })
      end
      if battle and battle.pendingTournamentMessages then
        for _, msg in ipairs(battle.pendingTournamentMessages) do
          self:handleMessage(msg)
        end
      end
      if self.stage == "matchRunning" or self.stage == "spectateRunning" then
        self.stage = "bracket"
      end
    end
    return
  end

  if self.net then
    self.net:update()
    if self.net.error and self.stage ~= "menu" and self.stage ~= "hostSettings"
       and self.stage ~= "codeEntry" then
      self:exitWith(Strings("Link error:\n%s", self.net.error:sub(1, 60)))
      return
    end
    if self.net.closed and self.stage ~= "done" then
      self:exitWith(Strings("The tournament\nconnection was\nlost."))
      return
    end
  end

  if self.stage == "matchHello" then
    if input:wasPressed("b") then self:exitWith(nil) return end
    self:pollHello()
    if self.peerHello then self:beginMatchBattle() end
    for _, msg in ipairs(self.net:poll()) do self:handleMessage(msg) end
    return
  elseif self.stage == "matchWaitParty" then
    if input:wasPressed("b") then self:exitWith(nil) return end
    local msgs = self.net:poll()
    for i, msg in ipairs(msgs) do
      if msg.type == "party" then
        self.pendingBattleOpts.theirParty = msg.mons
        if self.isHost then
          self.pendingBattleOpts.seed = self.pendingBattleOpts.seed or self.linkSeed
        else
          self.pendingBattleOpts.seed = msg.seed
        end
        local battle, why = self.isHost
          and LinkBattle.newHost(self.game, self.net, self.pendingBattleOpts)
          or LinkBattle.newGuest(self.game, self.net, self.pendingBattleOpts)
        if not battle then
          self:exitWith(why or Strings("Link battle\ncan't start."))
          return
        end
        -- anything after `party` in this same batch belongs to the
        -- battle now, not to Tournament -- put it back for its own poll()
        for j = #msgs, i + 1, -1 do
          table.insert(self.net.inbox, 1, msgs[j])
        end
        self.activeBattle = battle
        self.game.stack:push(battle)
        self.stage = "matchRunning"
        return
      else
        self:handleMessage(msg)
      end
    end
    return
  elseif self.stage == "spectateWait" then
    if input:wasPressed("b") then self:exitWith(nil) return end
    local msgs = self.net:poll()
    for i, msg in ipairs(msgs) do
      if msg.type == "spectate" and msg.msg.type == "party" then
        local inner = msg.msg
        if msg.side == "host" then
          self.spectate.hostParty = inner.mons
          self.spectate.seed = inner.seed
        else
          self.spectate.guestParty = inner.mons
        end
        if self.spectate.hostParty and self.spectate.guestParty then
          local battle, why = LinkBattle.newSpectator(self.game, self.net, {
            hostParty = self.spectate.hostParty, guestParty = self.spectate.guestParty,
            hostName = self.spectate.hostName, guestName = self.spectate.guestName,
            seed = self.spectate.seed,
            forceLevel = levelForWire(self.settings.forceLevel),
          })
          if not battle then
            self:exitWith(why or Strings("Can't watch this\nmatch."))
            return
          end
          for j = #msgs, i + 1, -1 do
            table.insert(self.net.inbox, 1, msgs[j])
          end
          self.activeBattle = battle
          self.game.stack:push(battle)
          self.stage = "spectateRunning"
          return
        end
      else
        self:handleMessage(msg)
      end
    end
    return
  end

  if self.net then
    for _, msg in ipairs(self.net:poll()) do self:handleMessage(msg) end
  end

  if self.stage == "menu" then
    if input:wasPressed("up") or input:wasPressed("down") then
      self.index = self.index == 1 and 2 or 1
    elseif input:wasPressed("b") then
      self:exitWith(nil)
    elseif input:wasPressed("a") then
      if self.index == 1 then
        self.stage = "hostSettings"
        self.settingsIndex = 1
      else
        self.stage = "codeEntry"
        self.codeEntry = CodeEntry.new()
      end
    end

  elseif self.stage == "hostSettings" then
    if input:wasPressed("b") then
      self.stage = "menu"
      self.index = 1
    elseif input:wasPressed("up") then
      self.settingsIndex = self.settingsIndex == 1 and SETTINGS_ROWS or self.settingsIndex - 1
    elseif input:wasPressed("down") then
      self.settingsIndex = self.settingsIndex % SETTINGS_ROWS + 1
    elseif input:wasPressed("left") or input:wasPressed("right") then
      local delta = input:wasPressed("right") and 1 or -1
      if self.settingsIndex == 1 then
        local i = indexOf(PARTY_SIZES, self.settings.requiredPartySize)
        i = ((i - 1 + delta) % #PARTY_SIZES) + 1
        self.settings.requiredPartySize = PARTY_SIZES[i]
      elseif self.settingsIndex == 2 then
        local i = indexOf(LEVEL_STEPS, self.settings.minLevel)
        i = ((i - 1 + delta) % #LEVEL_STEPS) + 1
        self.settings.minLevel = LEVEL_STEPS[i]
      elseif self.settingsIndex == 3 then
        local i = indexOf(LEVEL_STEPS, self.settings.maxLevel)
        i = ((i - 1 + delta) % #LEVEL_STEPS) + 1
        self.settings.maxLevel = LEVEL_STEPS[i]
      elseif self.settingsIndex == 4 then
        local i = indexOf(TURN_LIMITS, self.settings.turnLimit)
        i = ((i - 1 + delta) % #TURN_LIMITS) + 1
        self.settings.turnLimit = TURN_LIMITS[i]
      elseif self.settingsIndex == 5 then
        local i = indexOf(FORCE_LEVEL_STEPS, self.settings.forceLevel)
        i = ((i - 1 + delta) % #FORCE_LEVEL_STEPS) + 1
        self.settings.forceLevel = FORCE_LEVEL_STEPS[i]
      elseif self.settingsIndex == 6 then
        self.settings.participating = not self.settings.participating
      end
    elseif input:wasPressed("a") or input:wasPressed("start") then
      self:startHosting()
    end

  elseif self.stage == "codeEntry" then
    if input:wasPressed("b") then
      self.stage = "menu"
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
      self:startJoining(CodeEntry.text(self.codeEntry))
    end

  elseif self.stage == "registering" then
    if input:wasPressed("b") then self:exitWith(nil) end

  elseif self.stage == "bracket" then
    if input:wasPressed("b") then self:exitWith(nil) return end
    if input:wasPressed("a") and self.isCreator and #self.roster >= 2 then
      DiscordPresence.setJoinCode(nil) -- roster's locking in; stop advertising
      self.net:send({ type = "start_tournament" })
    end

  elseif self.stage == "done" then
    if input:wasPressed("a") or input:wasPressed("b") then
      self:exitWith(nil)
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

local SETTINGS_LABELS = { "POKEMON", "MIN LV", "MAX LV", "TIMER", "LEVELS", "PLAYING" }

function Tournament:draw()
  if self.stage == "menu" then
    drawTitle("TOURNAMENT")
    Font.draw(Strings("HOST"), 32, 48)
    Font.draw(Strings("JOIN"), 32, 68)
    Font.drawCode(CURSOR, 24, self.index == 1 and 48 or 68)

  elseif self.stage == "hostSettings" then
    drawTitle("TOURNAMENT RULES")
    local values = {
      tostring(self.settings.requiredPartySize),
      levelLabel(self.settings.minLevel),
      levelLabel(self.settings.maxLevel),
      self.settings.turnLimit .. "s",
      forceLevelLabel(self.settings.forceLevel),
      self.settings.participating and "YES" or "NO",
    }
    for i, label in ipairs(SETTINGS_LABELS) do
      local y = 32 + (i - 1) * 16
      Font.draw(label, 16, y)
      Font.draw(values[i], 96, y)
      if i == self.settingsIndex then Font.drawCode(CURSOR, 8, y) end
    end
    Font.draw(Strings("START: create"), 8, 128)

  elseif self.stage == "codeEntry" then
    drawTitle("ENTER CODE")
    for i = 1, CodeEntry.LENGTH do
      local x = 16 + (i - 1) * 16
      local ch = CodeEntry.CHARSET:sub(self.codeEntry.chars[i], self.codeEntry.chars[i])
      Font.draw(ch, x, 64)
      if i == self.codeEntry.pos then
        Font.drawCode(0xEE, x, 76)
      end
    end
    Font.draw(Strings("A: join  B: back"), 8, 128)

  elseif self.stage == "registering" then
    drawTitle("CONNECTING...")
    Font.draw(Strings("B: cancel"), 8, 128)

  elseif self.stage == "bracket" or self.stage == "matchHello"
      or self.stage == "matchWaitParty" or self.stage == "spectateWait" then
    drawTitle(Strings("TOURNAMENT %s", self.code or "??????"))
    if self.bracket then
      local y = 20
      for _, round in ipairs(self.bracket.rounds) do
        Font.draw(Strings("ROUND %d", round.round), 8, y)
        y = y + 10
        for _, m in ipairs(round.matches) do
          local line
          if m.bye then
            line = Strings("%s (bye)", m.a or m.b or "?")
          else
            local mark = m.state == "live" and "*" or (m.winner and "" or "")
            line = Strings("%s%s vs %s%s", m.winner == m.a and ">" or " ", m.a or "?",
              m.b or "?", m.winner == m.b and "<" or (mark == "*" and " *" or ""))
          end
          Font.draw(line, 12, y)
          y = y + 10
          if y > 120 then break end
        end
      end
    else
      if self.participating == false then
        Font.draw(Strings("(organizing --"), 16, 32)
        Font.draw(Strings("not playing)"), 16, 42)
      end
      Font.draw(Strings("Waiting for"), 16, 48)
      Font.draw(Strings("players to join:"), 16, 60)
      local y = 60
      for i, name in ipairs(self.roster) do
        y = 60 + i * 10
        Font.draw(name, 24, y)
      end
      for _, name in ipairs(self.spectatorRoster) do
        y = y + 10
        Font.draw(name .. " (watch)", 24, y)
      end
    end
    if self.isCreator and #self.roster >= 2 and not self.bracket then
      Font.draw(Strings("A: START  B: cancel"), 8, 132)
    else
      Font.draw(Strings("B: cancel"), 8, 132)
    end

  elseif self.stage == "done" then
    drawTitle("TOURNAMENT OVER")
    if self.champion then
      Font.draw(Strings("%s is the", self.champion), 16, 56)
      Font.draw(Strings("champion!"), 16, 68)
    end
    Font.draw(Strings("A: continue"), 8, 128)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return Tournament
