-- Link battles over the peer-to-peer link (src/link/Net.lua),
-- lockstep-simulated like the real link cable: BOTH sides run the
-- full battle engine (BattleState) locally
-- from mirrored perspectives, on a shared RNG seed the host deals out.
-- Each turn the two chosen actions are exchanged and both machines
-- resolve the turn independently -- identical clamped party copies +
-- identical RNG stream = identical outcomes.  A per-turn state hash is
-- exchanged; a mismatch (desync) ends the match as a draw, like a
-- cable pull.
--
-- Cable rules: no experience, no money, no items; either side may RUN
-- (a draw); a fainted mon is auto-replaced by the next healthy party
-- member (the original prompts; documented divergence).  Badge stat
-- boosts don't apply on either side (divergence: Gen 1 famously kept
-- them in link battles).

local Fingerprint = require("src.link.Fingerprint")
local Font = require("src.render.Font")
local Handshake = require("src.link.Handshake")
local Logger = require("src.core.Logger")
local Protocol = require("src.link.Protocol")
local Runtime = require("src.mods.Runtime")
local TurnOrder = require("src.battle.TurnOrder")
local Strings = require("src.core.Strings")

local LinkBattle = {}

-- Deterministic Park-Miller PRNG: both sides must roll identical
-- streams, so love.math.random can't be used.
local function makeRng(seed)
  local s = seed % 2147483647
  if s <= 0 then s = s + 2147483646 end
  return function(a, b)
    s = (s * 16807) % 2147483647
    if a == nil then return s / 2147483647 end
    if b == nil then a, b = 1, a end
    return a + (s % (b - a + 1))
  end
end

-- Battlers go through BattleState.makeBattler so pics get the same
-- Assets.resolve + SGB/GBC palette + padBottom path as wild/trainer
-- battles.  save=nil skips badge boosts so both machines keep identical
-- stats (Gen 1 cable battles famously kept badges; we still diverge).
local function mkBattler(data, mon, isPlayer)
  local BattleState = require("src.battle.BattleState")
  return BattleState.makeBattler(data, mon, isPlayer, nil)
end

-- shared by LinkBattle.new (myParty/theirParty) and LinkBattle.newSpectator
-- (hostParty/guestParty): pack->unpack clamp so every perspective watching
-- a given match holds identical mon copies. errFmt(packedMon, why) builds
-- the message shown when strict mode refuses an unrebuildable mon.
local function unpackParty(game, packed, unpackOpts, errFmt)
  local out = {}
  for _, p in ipairs(packed or {}) do
    local mon, why = Protocol.unpackMon(game.data, p, unpackOpts)
    if mon then
      table.insert(out, mon)
    elseif unpackOpts.strict then
      return nil, errFmt(p, why)
    end
  end
  return out
end

-- decode a wire action message against whichever battler it belongs to
-- (the opponent's, from a real participant's perspective; either side's,
-- from a spectator's)
local function decodeWireAction(s, msg, battler)
  if msg.kind == "move" then
    local slot = math.max(1, math.min(#battler.curMoves, math.floor(msg.slot or 1)))
    return battler.curMoves[slot]
  elseif msg.kind == "struggle" then
    return { id = "STRUGGLE", pp = 1, struggle = true }
  elseif msg.kind == "locked" then
    return s:lockedAction(battler)
  end
  return nil
end

-- canonical (host-side-first) state hash, unchanged since v1: it stays on
-- the wire as `value` so a pre-mod peer still compares something it agrees
-- with, while the components below carry the real coverage
local function stateHash(self, role)
  local function sig(b)
    return ("%s:%d:%s"):format(b.mon.species, b.mon.hp, tostring(b.mon.status))
  end
  local hostSide = role == "host" and self.player or self.enemy
  local guestSide = role == "host" and self.enemy or self.player
  return sig(hostSide) .. "|" .. sig(guestSide)
end

-- The signature is split into components so a mismatch can name what
-- diverged: species:hp:status alone missed stat stages, PP, toxic counters
-- and bench damage until they happened to move an active's HP, and the
-- match then ended in a draw that explained nothing.
local STAGES = { "attack", "defense", "special", "speed", "accuracy", "evasion" }
local VOLATILE = {
  "bideDamage", "bideTurns", "boundTurns", "chargeReady", "charging",
  "confusedTurns", "disabledSlot", "disabledTurns", "flinched", "focusEnergy",
  "invulnerable", "leechSeeded", "lightScreen", "mist", "mustRecharge",
  "rageMove", "reflect", "skipMove", "sleepTurns", "substituteHP",
  "thrashMove", "thrashTurns", "toxicCounter", "trapDamage", "trapMove",
  "trappingTurns",
}

-- move instances ride some volatile slots; only their id is comparable
local function scalar(v)
  if type(v) == "table" then return tostring(v.id or "?") end
  if type(v) == "boolean" then return v and "T" or "F" end
  return tostring(v)
end

local function stageStr(b)
  local out = {}
  for i, stat in ipairs(STAGES) do
    out[i] = tostring((b.stages or {})[stat] or 0)
  end
  return table.concat(out, ",")
end

local function ppStr(mon)
  local out = {}
  for i, mv in ipairs(mon.moves or {}) do
    out[i] = ("%s=%s"):format(tostring(mv.id), tostring(mv.pp or 0))
  end
  return table.concat(out, ",")
end

local function volStr(b)
  local out = {}
  for _, key in ipairs(VOLATILE) do
    if b[key] ~= nil then
      out[#out + 1] = key .. "=" .. scalar(b[key])
    end
  end
  return table.concat(out, ",")
end

local function activeStr(b)
  return ("%s:%d:%s:%s:%s"):format(b.mon.species, b.mon.hp,
                                   tostring(b.mon.status), stageStr(b),
                                   ppStr(b.mon))
end

local function benchStr(party)
  local out = {}
  for i, mon in ipairs(party or {}) do
    out[i] = ("%s:%d:%s"):format(tostring(mon.species), mon.hp or 0,
                                 tostring(mon.status))
  end
  return table.concat(out, "|")
end

-- canonical (host-side-first) per-component signature for desync detection
local function stateSig(self, role, myParty, theirParty)
  local host = role == "host" and self.player or self.enemy
  local guest = role == "host" and self.enemy or self.player
  local hostParty = role == "host" and myParty or theirParty
  local guestParty = role == "host" and theirParty or myParty
  return {
    actives = Fingerprint.digest(activeStr(host) .. "|" .. activeStr(guest)),
    volatile = Fingerprint.digest(volStr(host) .. "|" .. volStr(guest)),
    bench = Fingerprint.digest(benchStr(hostParty) .. "|" .. benchStr(guestParty)),
  }
end

local PARTS = { "actives", "volatile", "bench" }

-- opts: { myParty = packed, theirParty = packed, theirName, role =
-- "host"/"guest", seed, verdict, strict }.  Returns nil plus a reason when
-- the handshake says the two link surfaces don't match: a lockstep
-- simulation of two different rulebooks can only end in a bogus draw.
function LinkBattle.new(game, net, opts)
  local BattleState = require("src.battle.BattleState")
  local role = opts.role
  local theirName = opts.theirName or "FOE"

  if not Handshake.battleAllowed(opts.verdict) then
    return nil, Strings("Link battle needs\nthe same mods on\nboth games.")
  end

  -- both parties pass through the same pack->unpack clamp on both
  -- machines, so the copies are identical everywhere
  local unpackOpts = { strict = opts.strict or false, forceLevel = opts.forceLevel }
  local myParty, myErr = unpackParty(game, opts.myParty, unpackOpts, function(p)
    return Strings("Your %s can't\nbattle on the\nother game.", tostring(p.species))
  end)
  if not myParty then return nil, myErr end
  local theirParty, theirErr = unpackParty(game, opts.theirParty, unpackOpts, function(p, why)
    return Strings("Their %s isn't\nin this game.\n(%s)", tostring(p.species), tostring(why))
  end)
  if not theirParty then return nil, theirErr end
  if #myParty == 0 or #theirParty == 0 then
    Logger.warn("link: empty party on one side")
  end

  -- a mod validates its own extra namespace here, the same site the trade
  -- path gets in TradeSession:apply, before anything simulates with it.
  -- Both parties go through it on both machines and in the canonical
  -- host-first order: a validator that strips a field from one side only,
  -- or in a different order, leaves the two simulations holding different
  -- mons and desyncs on the first turn the difference matters.
  local function announceReceived(party)
    for _, mon in ipairs(party) do
      Runtime.emit("pokemon.received",
                   { mon = mon, from = "link", peerName = theirName })
    end
  end
  announceReceived(role == "host" and myParty or theirParty)
  announceReceived(role == "host" and theirParty or myParty)

  -- build on a wild battle and reshape it into the lockstep link battle.
  -- The RATTATA scaffold is unreachable on the negotiated path: an empty or
  -- unrebuildable party is refused above, so it only ever covers a caller
  -- that skipped the handshake.
  local self = BattleState.newWild(game, theirParty[1] and theirParty[1].species
                                         or "RATTATA", 5)
  self.kind = "link"
  self.linkRole = role
  self.net = net
  -- BattleState:update only runs while it's the top of the state
  -- stack, but the player can push PartyMenu/ChoiceBox/NamingScreen on
  -- top of it (forced switch on faint, evolution naming...); the ENet
  -- transport must stay serviced regardless, or the peer's actions
  -- back up and the link can stall or time out. Game:step services
  -- game.linkNet unconditionally every frame.
  game.linkNet = net
  self.rng = makeRng(opts.seed or 1)
  self.player = mkBattler(game.data, myParty[1], true)
  self.enemy = mkBattler(game.data, theirParty[1], false)
  self.enemyParty = theirParty
  self.playerParty = myParty -- intro ball row uses the clamped copies
  self.opponentName = theirName
  self.introText = Strings("%s wants\nto battle!", theirName)
  self.remoteHashes = {}
  self.localHashes = {}
  self.remoteParts = {}
  self.localParts = {}
  self.checkedTurns = {}

  local send = function(msg) net:send(msg) end

  local function endAsDraw(s, text)
    if s.linkEnded then return end
    s.result = "draw"
    s.afterQueue = "finish"
    s.phase = "messages"
    if text then s:say(text) end
  end

  -- a tournament shot clock (opts.turnLimit) costs the slow player
  -- specifically, unlike RUN or a desync -- both of which stay a draw --
  -- so it needs its own result rather than reusing endAsDraw
  local function endWithResult(s, result, text)
    if s.linkEnded then return end
    s.result = result
    s.afterQueue = "finish"
    s.phase = "messages"
    if text then s:say(text) end
  end

  local function orderMove(action)
    if action and action.id then return game.data.moves[action.id] end
    return nil
  end

  -- player-side SendOutMon (poof + grow-in + cry); mirrors BattleState
  local function sendOutPlayer(s, mon)
    local previous = s.player
    s.player = mkBattler(game.data, mon, true)
    s:syncSides()
    Runtime.emit("battle.battler_switched", {
      battle = s, side = s.sides[1], battler = s.player, previous = previous,
    })
    s.sendingOut = true
    s:sayNext(s:sendOutText(s.player.name))
    s:animNext("POOF_ANIM", false)
    s:actNext(function()
      s.sendingOut = false
      s:startGrowIn(s.player)
      require("src.core.Sound").playCry(s.data, s.player.mon.species)
    end)
  end

  -- enemy-side EnemySendOut (grow-in + cry; no poof)
  local function sendOutEnemy(s, mon)
    local previous = s.enemy
    s.enemy = mkBattler(game.data, mon, false)
    s:syncSides()
    Runtime.emit("battle.battler_switched", {
      battle = s, side = s.sides[2], battler = s.enemy, previous = previous,
    })
    s.enemySendingOut = true
    s:sayNext(Strings("%s sent\nout %s!", theirName, s.enemy.name))
    s:actNext(function()
      s.enemySendingOut = false
      s:startGrowIn(s.enemy)
      s:actNext(function()
        require("src.core.Sound").playCry(s.data, s.enemy.mon.species)
      end)
    end)
  end

  -- decode a remote action message against the enemy battler
  local function decodeTheirAction(s, msg)
    return decodeWireAction(s, msg, s.enemy)
  end

  -- with the handshake guaranteeing both games share a link surface, a
  -- mismatch here is RNG non-determinism -- almost always a mod rolling
  -- love.math.random inside battle logic instead of the injected s.rng
  local function reportDesync(s, turn, component, localH, remoteH)
    Logger.warn("link: desync turn %s component=%s (%s vs %s)",
                tostring(turn), component, tostring(localH), tostring(remoteH))
    Runtime.emit("link.desync", { turn = turn, component = component,
                                  localHash = localH, remoteHash = remoteH })
    endAsDraw(s, Strings(
      "Link desync!\n%s differs.\fAre both games\nrunning the same\nmods?",
      component))
  end

  -- a verified turn stays recorded: consuming it here left a finished
  -- battle holding 0-1 entries, so the whole-battle sweep the link suite
  -- runs over localHashes had nothing left to compare
  local function checkHashes(s)
    for turn, localH in pairs(s.localHashes) do
      local remoteH = s.remoteHashes[turn]
      if remoteH and not s.checkedTurns[turn] then
        s.checkedTurns[turn] = true
        local mine, theirs = s.localParts[turn], s.remoteParts[turn]
        if mine and theirs then
          for _, component in ipairs(PARTS) do
            if mine[component] ~= theirs[component] then
              reportDesync(s, turn, component, mine[component], theirs[component])
              return
            end
          end
        end
        -- a v1 peer sends the combined value only
        if remoteH ~= localH then
          reportDesync(s, turn, "state", localH, remoteH)
          return
        end
      end
    end
  end

  -- both actions in hand: resolve the turn identically on both machines
  local function resolveLockstep(s, myMsg, theirMsg)
    if myMsg.kind == "run" or theirMsg.kind == "run" then
      local who = myMsg.kind == "run" and game.save.player.name or theirName
      endAsDraw(s, Strings("%s ran from\nthe battle!", who))
      return
    end
    s.phase = "messages"
    s.afterQueue = "linkNext"
    s.turnCount = (s.turnCount or 0) + 1

    local myAction = myMsg.action
    local theirSwitch = theirMsg.kind == "switch"
                        and math.max(1, math.min(#theirParty,
                                                 math.floor(theirMsg.index or 1)))
                        or nil

    -- switches happen before attacks (both may switch)
    if myMsg.kind == "switch" then
      local idx = myMsg.index
      s:act(function() sendOutPlayer(s, myParty[idx]) end)
      myAction = nil
    end
    if theirSwitch then
      s:act(function() sendOutEnemy(s, theirParty[theirSwitch]) end)
    end

    s:act(function()
      local theirAction = decodeTheirAction(s, theirMsg)
      Runtime.emit("battle.turn_started", {
        battle = s, turn = s.turnCount,
        playerAction = myAction, enemyAction = theirAction,
      })
      if myAction and theirAction then
        -- the tie-break roll is shared: the guest inverts it so both
        -- machines agree on who goes first.  A modded ordering rule has
        -- to run here too, or the two peers order the turn differently.
        local first
        local myMove, theirMove = orderMove(myAction), orderMove(theirAction)
        if Runtime.wantsHook("battle.turn_order") then
          first = Runtime.call("battle.turn_order", function(a, aMove, b, bMove, c)
            return TurnOrder.firstMover(a, aMove, b, bMove, c.rng, c.invertTie)
          end, s.player, myMove, s.enemy, theirMove,
             { rng = s.rng, invertTie = role == "guest" })
        else
          first = TurnOrder.firstMover(s.player, myMove, s.enemy, theirMove,
                                       s.rng, role == "guest")
        end
        local order
        if first then
          order = { { s.player, s.enemy, myAction },
                    { s.enemy, s.player, theirAction } }
        else
          order = { { s.enemy, s.player, theirAction },
                    { s.player, s.enemy, myAction } }
        end
        for _, entry in ipairs(order) do
          s:act(function() s:executeAction(entry[1], entry[2], entry[3]) end)
        end
      elseif myAction then
        s:act(function() s:executeAction(s.player, s.enemy, myAction) end)
      elseif theirAction then
        s:act(function() s:executeAction(s.enemy, s.player, theirAction) end)
      end
      s:act(function() s:endOfTurn() end)
      s:act(function()
        if s.linkEnded then return end
        local parts = stateSig(s, role, myParty, theirParty)
        local h = stateHash(s, role)
        s.localHashes[s.turnCount] = h
        s.localParts[s.turnCount] = parts
        send({ type = "hash", turn = s.turnCount, value = h, parts = parts })
        checkHashes(s)
      end)
    end)
  end

  self.pendingMyAction = nil
  self.remoteAction = nil
  local function tryResolve(s)
    if not s.pendingMyAction or not s.remoteAction then return end
    local mine, theirs = s.pendingMyAction, s.remoteAction
    s.pendingMyAction, s.remoteAction = nil, nil
    resolveLockstep(s, mine, theirs)
  end

  -- my chosen action: send it and wait for theirs
  local function submit(s, msg, localAction)
    msg.action = nil
    send(msg)
    msg.action = localAction
    s.pendingMyAction = msg
    s.phase = "waitRemote"
    tryResolve(s)
  end

  self.resolveTurn = function(s, action)
    local kind
    if action.struggle then
      kind = "struggle"
    elseif action.special then
      kind = "locked"
    else
      kind = "move"
    end
    local slot
    if kind == "move" then
      for i, mv in ipairs(s.player.curMoves) do
        if mv == action then slot = i end
      end
      if not slot then kind = "locked" end -- thrash/rage move instances
    end
    submit(s, { type = "action", kind = kind, slot = slot }, action)
  end

  self.resolveSwitch = function(s, newMon)
    for i, mon in ipairs(myParty) do
      if mon == newMon then
        submit(s, { type = "action", kind = "switch", index = i }, nil)
        return
      end
    end
  end

  -- the party menu must offer the clamped link copies
  self.openParty = function(s)
    s.phase = "messages"
    s.afterQueue = "menu"
    s:ui(function()
      return s:buildScreen("PartyMenu", {
        battle = s,
        party = myParty,
        onSwitch = function(mon)
          if mon == s.player.mon then
            s:say(Strings("%s is\nalready out!", s.player.name))
          elseif mon.hp <= 0 then
            s:say(Strings("There's no will\nto fight!"))
          else
            s:resolveSwitch(mon)
          end
        end,
      })
    end)
  end

  self.openItems = function(s)
    s:say(Strings("Items can't be\nused in a link\nbattle!"))
    s.phase = "messages"
    s.afterQueue = "menu"
  end

  self.tryRun = function(s)
    submit(s, { type = "action", kind = "run" }, nil)
  end

  -- fainted mons auto-replace with the next healthy teammate, in party
  -- order, identically on both machines
  self.playerMonFainted = function(s)
    for _, mon in ipairs(myParty) do
      if mon.hp > 0 then
        s:act(function() sendOutPlayer(s, mon) end)
        return
      end
    end
    s:sayNext(Strings("%s is out of\nPOKéMON!\f%s wins!", game.save.player.name,
                                                          theirName))
    s.result = "lose"
    s.afterQueue = "finish"
  end

  self.enemyMonFainted = function(s)
    for _, mon in ipairs(theirParty) do
      if mon.hp > 0 then
        s:act(function() sendOutEnemy(s, mon) end)
        return
      end
    end
    s:sayNext(Strings("%s is out of\nPOKéMON!\f%s wins!", theirName,
                                                          game.save.player.name))
    s.result = "win"
    s.afterQueue = "finish"
  end

  local baseUpdate = self.update
  self.update = function(s, dt)
    net:update()
    for _, msg in ipairs(net:poll()) do
      if msg.type == "action" then
        s.remoteAction = msg
        tryResolve(s)
      elseif msg.type == "hash" then
        s.remoteHashes[msg.turn or 0] = msg.value
        s.remoteParts[msg.turn or 0] = msg.parts
        checkHashes(s)
      elseif msg.type == "bye" then
        -- only a draw if our own simulation hasn't already decided
        -- (the winner's bye can arrive while we're still animating)
        if not s.result then
          endAsDraw(s, Strings("%s left the\nbattle.", theirName))
        end
      elseif msg.type == "forfeit" then
        -- the peer's own shot clock ran out; unlike a mutual RUN/desync
        -- draw, this has a definite winner (us)
        if not s.result then
          endWithResult(s, "win", Strings("%s ran out of\ntime!", theirName))
        end
      else
        -- a tournament control message (bracket_update, the next
        -- match_start, ...) can arrive while this match is still
        -- finishing up; Tournament.lua drains this once it regains the
        -- stack top rather than losing it to this poll loop
        s.pendingTournamentMessages = s.pendingTournamentMessages or {}
        table.insert(s.pendingTournamentMessages, msg)
      end
    end
    if net.closed and not s.linkEnded and not s.result then
      endAsDraw(s)
    end
    if s.phase == "waitRemote" then
      return -- the other side is still choosing
    end
    if s.phase == "messages" and s.afterQueue == "linkNext" then
      if not s:updateQueue() then
        s.afterQueue = "menu"
        s.phase = "menu"
      end
      return
    end
    if opts.turnLimit and s.phase == "menu" then
      if not s.turnClockActive then
        s.turnClockActive = true
        s.turnClock = opts.turnLimit
      end
      s.turnClock = s.turnClock - dt
      if s.turnClock <= 0 then
        s.turnClockActive = false
        send({ type = "forfeit" })
        endWithResult(s, "lose", Strings("Time's up! You\nforfeit the match."))
      end
    elseif opts.turnLimit then
      s.turnClockActive = false
    end
    baseUpdate(s, dt)
  end

  if opts.turnLimit then
    local baseDraw = self.draw
    self.draw = function(s, ...)
      baseDraw(s, ...)
      if s.phase == "menu" and s.turnClockActive then
        love.graphics.setColor(1, 1, 1, 1)
        Font.draw(tostring(math.max(0, math.ceil(s.turnClock))), 144, 4)
      end
    end
  end

  local baseFinish = self.finish
  self.finish = function(s)
    if not s.linkEnded then
      s.linkEnded = true
      send({ type = "bye" })
    end
    -- opts.keepNetOpen: a tournament match's `net` is the caller's
    -- long-lived tournament connection (still needed for the next round,
    -- spectating, bracket updates, ...), not a dedicated match socket --
    -- closing it here the way a plain 1v1 link battle does would sever
    -- the whole tournament, not just this match.
    if not opts.keepNetOpen then
      net:close()
    end
    if game.linkNet == net then game.linkNet = nil end
    baseFinish(s)
  end

  return self
end

-- A tournament spectator: reconstructs the exact same lockstep battle a
-- live match's two real participants are playing, from a copy of the
-- traffic the relay fans out to onlookers (see pokeserver's `spectate`
-- envelope). No local input drives anything here -- both sides' actions
-- arrive over the wire, tagged by which real player sent them -- so it's
-- a read-only replay, not a third participant: no hash/desync checking
-- (a spectator has nothing to verify against), no shot clock (nothing to
-- act on), and `finish` must NOT close `net`, since that's the caller's
-- long-lived tournament connection, not a dedicated match socket.
--
-- opts: { hostParty = packed, guestParty = packed, hostName, guestName,
-- seed, verdict, strict }. `self.player` is always the host's battler and
-- `self.enemy` the guest's, which is what makes TurnOrder.firstMover's
-- tie-break (below) land on the same result the host's own instance
-- already computed with invertTie=false.
function LinkBattle.newSpectator(game, net, opts)
  local BattleState = require("src.battle.BattleState")
  local hostName = opts.hostName or "HOST"
  local guestName = opts.guestName or "GUEST"

  if not Handshake.battleAllowed(opts.verdict) then
    return nil, Strings("Link battle needs\nthe same mods on\nboth games.")
  end

  local unpackOpts = { strict = opts.strict or false, forceLevel = opts.forceLevel }
  local hostParty, hostErr = unpackParty(game, opts.hostParty, unpackOpts, function(p)
    return Strings("%s's %s can't\nbattle on this\ngame.", hostName, tostring(p.species))
  end)
  if not hostParty then return nil, hostErr end
  local guestParty, guestErr = unpackParty(game, opts.guestParty, unpackOpts, function(p, why)
    return Strings("%s's %s can't\nbattle on this\ngame.\n(%s)", guestName, tostring(p.species), tostring(why))
  end)
  if not guestParty then return nil, guestErr end
  if #hostParty == 0 or #guestParty == 0 then
    Logger.warn("link: empty party on one side (spectator)")
  end

  local self = BattleState.newWild(game, guestParty[1] and guestParty[1].species
                                         or "RATTATA", 5)
  self.kind = "link" -- exact same visual treatment as a real link battle
  self.spectating = true -- Tournament.lua's marker: don't report a result for this one
  self.net = net
  game.linkNet = net
  self.rng = makeRng(opts.seed or 1)
  self.player = mkBattler(game.data, hostParty[1], true)
  self.enemy = mkBattler(game.data, guestParty[1], false)
  self.enemyParty = guestParty
  self.playerParty = hostParty
  self.opponentName = guestName
  self.introText = Strings("%s vs %s!", hostName, guestName)

  local function orderMove(action)
    if action and action.id then return game.data.moves[action.id] end
    return nil
  end

  local function endSpectate(s, text)
    if s.linkEnded then return end
    s.result = s.result or "ended"
    s.afterQueue = "finish"
    s.phase = "messages"
    if text then s:say(text) end
  end

  local function sendOutHost(s, mon)
    local previous = s.player
    s.player = mkBattler(game.data, mon, true)
    s:syncSides()
    Runtime.emit("battle.battler_switched", {
      battle = s, side = s.sides[1], battler = s.player, previous = previous,
    })
    s.sendingOut = true
    s:sayNext(s:sendOutText(s.player.name))
    s:animNext("POOF_ANIM", false)
    s:actNext(function()
      s.sendingOut = false
      s:startGrowIn(s.player)
      require("src.core.Sound").playCry(s.data, s.player.mon.species)
    end)
  end

  local function sendOutGuest(s, mon)
    local previous = s.enemy
    s.enemy = mkBattler(game.data, mon, false)
    s:syncSides()
    Runtime.emit("battle.battler_switched", {
      battle = s, side = s.sides[2], battler = s.enemy, previous = previous,
    })
    s.enemySendingOut = true
    s:sayNext(Strings("%s sent\nout %s!", guestName, s.enemy.name))
    s:actNext(function()
      s.enemySendingOut = false
      s:startGrowIn(s.enemy)
      s:actNext(function()
        require("src.core.Sound").playCry(s.data, s.enemy.mon.species)
      end)
    end)
  end

  local function resolveSpecTurn(s, hostMsg, guestMsg)
    if hostMsg.kind == "run" or guestMsg.kind == "run" then
      endSpectate(s, "The match ended.")
      return
    end
    s.phase = "messages"
    s.afterQueue = "linkNext"
    s.turnCount = (s.turnCount or 0) + 1

    if hostMsg.kind == "switch" then
      local idx = hostMsg.index
      s:act(function() sendOutHost(s, hostParty[idx]) end)
    end
    if guestMsg.kind == "switch" then
      local idx = guestMsg.index
      s:act(function() sendOutGuest(s, guestParty[idx]) end)
    end

    s:act(function()
      local hostAction = hostMsg.kind ~= "switch" and hostMsg.kind ~= "run"
                          and decodeWireAction(s, hostMsg, s.player) or nil
      local guestAction = guestMsg.kind ~= "switch" and guestMsg.kind ~= "run"
                          and decodeWireAction(s, guestMsg, s.enemy) or nil
      Runtime.emit("battle.turn_started", {
        battle = s, turn = s.turnCount,
        playerAction = hostAction, enemyAction = guestAction,
      })
      if hostAction and guestAction then
        local hostMove, guestMove = orderMove(hostAction), orderMove(guestAction)
        local first
        if Runtime.wantsHook("battle.turn_order") then
          first = Runtime.call("battle.turn_order", function(a, aMove, b, bMove, c)
            return TurnOrder.firstMover(a, aMove, b, bMove, c.rng, c.invertTie)
          end, s.player, hostMove, s.enemy, guestMove, { rng = s.rng, invertTie = false })
        else
          first = TurnOrder.firstMover(s.player, hostMove, s.enemy, guestMove, s.rng, false)
        end
        local order
        if first then
          order = { { s.player, s.enemy, hostAction }, { s.enemy, s.player, guestAction } }
        else
          order = { { s.enemy, s.player, guestAction }, { s.player, s.enemy, hostAction } }
        end
        for _, entry in ipairs(order) do
          s:act(function() s:executeAction(entry[1], entry[2], entry[3]) end)
        end
      elseif hostAction then
        s:act(function() s:executeAction(s.player, s.enemy, hostAction) end)
      elseif guestAction then
        s:act(function() s:executeAction(s.enemy, s.player, guestAction) end)
      end
      s:act(function() s:endOfTurn() end)
    end)
  end

  self.resolveTurn = function() end -- a spectator's own input never drives anything
  self.resolveSwitch = function() end
  self.tryRun = function() end
  self.openParty = function(s) s.phase = "waitBoth" end

  self.playerMonFainted = function(s)
    for _, mon in ipairs(hostParty) do
      if mon.hp > 0 then
        s:act(function() sendOutHost(s, mon) end)
        return
      end
    end
    s:sayNext(Strings("%s is out of\nPOKéMON!\f%s wins!", hostName, guestName))
    s.result = "guestWin"
    s.afterQueue = "finish"
  end

  self.enemyMonFainted = function(s)
    for _, mon in ipairs(guestParty) do
      if mon.hp > 0 then
        s:act(function() sendOutGuest(s, mon) end)
        return
      end
    end
    s:sayNext(Strings("%s is out of\nPOKéMON!\f%s wins!", guestName, hostName))
    s.result = "hostWin"
    s.afterQueue = "finish"
  end

  self.hostMsg, self.guestMsg = nil, nil
  local baseUpdate = self.update
  self.update = function(s, dt)
    net:update()
    for _, msg in ipairs(net:poll()) do
      if msg.type == "spectate" then
        local inner = msg.msg
        if inner.type == "action" then
          if msg.side == "host" then s.hostMsg = inner else s.guestMsg = inner end
          if s.hostMsg and s.guestMsg then
            local h, g = s.hostMsg, s.guestMsg
            s.hostMsg, s.guestMsg = nil, nil
            resolveSpecTurn(s, h, g)
          end
        elseif inner.type == "bye" or inner.type == "forfeit" then
          if not s.result then endSpectate(s, "The match ended.") end
        end
        -- "hello"/"party"/"hash" ride along too (Tournament.lua already
        -- consumed hello/party before building this battle); none of them
        -- need any action here
      else
        -- same reasoning as the real-participant loop above: don't lose a
        -- bracket_update/match_start_spectate that arrives mid-match
        s.pendingTournamentMessages = s.pendingTournamentMessages or {}
        table.insert(s.pendingTournamentMessages, msg)
      end
    end
    if net.closed and not s.linkEnded and not s.result then
      endSpectate(s)
    end
    if s.phase == "messages" and s.afterQueue == "linkNext" then
      if not s:updateQueue() then
        s.afterQueue = "waitBoth"
        s.phase = "waitBoth"
      end
      return
    end
    if s.phase == "menu" or s.phase == "waitBoth" then
      return -- frozen between resolved turns; never a real decision here
    end
    baseUpdate(s, dt)
  end

  local baseFinish = self.finish
  self.finish = function(s)
    s.linkEnded = true
    if game.linkNet == net then game.linkNet = nil end
    baseFinish(s) -- deliberately doesn't touch net: it's the caller's
                  -- tournament connection, still needed after this match
  end

  return self
end

-- backwards-compatible entry points (LinkState passes role explicitly)
function LinkBattle.newHost(game, net, opts)
  opts.role = "host"
  return LinkBattle.new(game, net, opts)
end

function LinkBattle.newGuest(game, net, opts)
  opts.role = "guest"
  return LinkBattle.new(game, net, opts)
end

return LinkBattle
