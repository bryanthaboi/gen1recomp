-- Items on the link cable (RFC 0021): a mode that opts in gets the bag,
-- the item rides the wire as the turn's action, and the peer -- and a
-- spectator -- apply the same effect to their copies before the moves,
-- so the per-turn hash still agrees.  Cable rules stay the default.
--   luajit tests/run_engine.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
local Link = require("tests.modkit.link")
local Net = require("src.link.Net")
local Protocol = require("src.link.Protocol")
local LinkBattle = require("src.link.LinkBattle")
local ItemEffects = require("src.inventory.ItemEffects")

math.randomseed(4242)
local Input = Link.prepare(Data)

-- the host's lead starts hurt on BOTH machines (packed HP rides the
-- wire), so a POTION has something to restore
local function pair(opts)
  local gameA = Link.fakeGame(Data, { "FIXMON_A", "FIXMON_B" }, { name = "RED" })
  local gameB = Link.fakeGame(Data, { "FIXMON_A", "FIXMON_B" }, { name = "BLUE" })
  local lead = gameA.save.party[1]
  lead.hp = math.max(1, math.floor(lead.stats.hp / 3))
  local netA, netB = Net.loopbackPair()
  local packedA = Protocol.packParty(gameA.save.party)
  local packedB = Protocol.packParty(gameB.save.party)
  local base = { seed = 987654321 }
  for k, v in pairs(opts or {}) do base[k] = v end
  local function with(extra)
    local o = {}
    for k, v in pairs(base) do o[k] = v end
    for k, v in pairs(extra) do o[k] = v end
    return o
  end
  local battleA = LinkBattle.newHost(gameA, netA,
    with({ myParty = packedA, theirParty = packedB, theirName = "BLUE" }))
  local battleB = LinkBattle.newGuest(gameB, netB,
    with({ myParty = packedB, theirParty = packedA, theirName = "RED" }))
  return gameA, gameB, battleA, battleB, packedA, packedB
end

local function watch(battle)
  local seen = {}
  local sayNext, say = battle.sayNext, battle.say
  battle.sayNext = function(s, text) seen[#seen + 1] = text; return sayNext(s, text) end
  battle.say = function(s, text, ...) seen[#seen + 1] = text; return say(s, text, ...) end
  return seen
end

local function has(list, needle)
  for _, text in ipairs(list) do
    if type(text) == "string" and text:find(needle, 1, true) then return true end
  end
  return false
end

-- ------- cable rules by default: the bag is refused, nothing new on the wire

do
  local gameA, gameB, battleA, battleB = pair()
  local seenA = watch(battleA)
  gameA.stack:push(battleA)
  gameB.stack:push(battleB)
  for _ = 1, 3000 do
    if battleA.phase == "menu" then break end
    Input.pressed = { a = true }
    gameA.stack:update(1 / 60)
    gameB.stack:update(1 / 60)
  end
  T.eq(battleA.phase, "menu", "default: the host reaches its menu")
  battleA:openItems()
  T.check(has(seenA, "Items can't be"), "default: the bag is refused with the cable line")
  T.check(battleA.itemUsed == require("src.battle.BattleState").itemUsed,
    "default: itemUsed is the inherited one, nothing rides the wire")
end

-- ------- opted in: the host's POTION heals on both machines before the moves

do
  local gameA, gameB, battleA, battleB = pair({ items = true })
  local seenA, seenB = watch(battleA), watch(battleB)
  local resA, resB
  battleA.onFinish = function(r) resA = r end
  battleB.onFinish = function(r) resB = r end
  gameA.stack:push(battleA)
  gameB.stack:push(battleB)

  local used, guestMoved = false, false
  local hpBeforeOnB
  -- A advances text on a side that is not at its menu; a side AT its menu
  -- is left there, so the battle stops after the one turn under test
  local function pressFor(battle)
    Input.pressed = (battle.phase ~= "menu") and { a = true } or {}
  end
  for _ = 1, 20000 do
    if resA or resB then break end
    if not used and battleA.phase == "menu" and gameA.stack:top() == battleA then
      -- what the bag does, in order: the effect on the lockstep copy, then
      -- the turn spent with the item's context (BagMenu's `spent`)
      hpBeforeOnB = battleB.enemy.mon.hp
      local target = battleA.player.mon
      local result, payload = ItemEffects.use(Data, gameA.save, "POTION", target, battleA)
      T.eq(result, "consumed", "the host's POTION lands on its copy")
      battleA:itemUsed({}, { item = "POTION", target = target })
      used = true
    end
    if not guestMoved and battleB.phase == "menu" and gameB.stack:top() == battleB then
      battleB:resolveTurn(battleB.player.curMoves[1])
      guestMoved = true
    end
    pressFor(battleA)
    gameA.stack:update(1 / 60)
    pressFor(battleB)
    gameB.stack:update(1 / 60)
    if used and guestMoved and battleA.phase == "menu" and battleB.phase == "menu" then
      break
    end
  end
  T.check(used, "items: the host got a menu to use the POTION from")
  T.eq(battleA.phase, "menu", "items: the turn resolved on the host")
  T.eq(battleB.phase, "menu", "items: ...and on the guest")
  T.eq(battleA.turnCount, 1, "items: one turn on the host")
  T.eq(battleB.turnCount, 1, "items: one turn on the guest")
  T.check(resA == nil and resB == nil, "items: nobody desynced or ran")
  T.check(hpBeforeOnB ~= nil and battleB.enemy.mon.hp ~= hpBeforeOnB or
          battleB.enemy.mon.hp == battleA.player.mon.hp,
    "items: the guest's copy of the host's lead moved")
  T.eq(battleB.enemy.mon.hp, battleA.player.mon.hp,
    "items: after the turn both machines hold the same HP for the host's lead")
  T.check(has(seenB, "RED used"), "items: the guest prints the host's used line")
  T.check(has(seenB, "restored"), "items: ...and the restore line")
  local mismatch
  for turn, hash in pairs(battleA.localHashes) do
    local other = battleB.localHashes[turn]
    if other and other ~= hash then mismatch = mismatch or turn end
  end
  T.check(mismatch == nil, "items: the per-turn state hash still agrees")
  T.check(battleA.remoteHashes[1] ~= nil and battleB.remoteHashes[1] ~= nil,
    "items: both sides exchanged the turn's hash")
end

-- ------- a spectator applies both players' items to its own copies

do
  local gameA, gameB, _, _, packedA, packedB = pair({ items = true })
  local gameS = Link.fakeGame(Data, { "FIXMON_A" }, { name = "WATCHER" })
  local inbox = {}
  local net = { closed = false }
  function net:update() end
  function net:poll() local m = inbox; inbox = {}; return m end
  function net:send() end
  function net:close() end
  local spec = LinkBattle.newSpectator(gameS, net, {
    hostParty = packedA, guestParty = packedB,
    hostName = "RED", guestName = "BLUE", seed = 987654321,
  })
  T.check(spec ~= nil, "spectator: opens off the packed parties")
  local seenS = watch(spec)
  gameS.stack:push(spec)
  local function frozen() return spec.phase == "waitBoth" or spec.phase == "menu" end
  for _ = 1, 3000 do
    if frozen() then break end
    Input.pressed = { a = true }
    gameS.stack:update(1 / 60)
  end
  T.check(frozen(), "spectator: waits for the first turn (" .. spec.phase .. ")")
  local before = spec.player.mon.hp
  inbox[#inbox + 1] = { type = "spectate", side = "host",
                        msg = { type = "action", kind = "item", item = "POTION", index = 1 } }
  inbox[#inbox + 1] = { type = "spectate", side = "guest",
                        msg = { type = "action", kind = "move", slot = 1 } }
  for _ = 1, 6000 do
    if frozen() and spec.turnCount == 1 then break end
    Input.pressed = { a = true }
    gameS.stack:update(1 / 60)
  end
  T.eq(spec.turnCount, 1, "spectator: the turn played")
  T.check(spec.player.mon.hp > before or spec.player.mon.hp == spec.player.mon.stats.hp,
    "spectator: the host's lead was healed on the replica (" .. before .. " -> " .. spec.player.mon.hp .. ")")
  T.check(has(seenS, "RED used"), "spectator: prints the host's used line")
end

T.finish("items ride the link cable when a mode asks (RFC 0021)")
