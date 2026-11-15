-- Gen 2 adapter for the route bot.
--
-- Everything the bot core knows about "the running game" goes through this
-- table, so the core (tests/drivers/gold/bot.lua) is pathfinding and policy
-- with no idea which generation it is driving.  The Gen 1 bot
-- (tests/drivers/route.lua) reaches into `G.overworld`, src/world/Warp and
-- src/world/Collision directly and is 8k lines because of it; keeping the seam
-- here is what lets a Gen 1 adapter drop in later without a second rewrite of
-- the BFS, the wall memory and the watchdog.
--
-- The contract, in one sentence per method, is at the bottom of this file.

local BattleState = require("src.ui.gen2.BattleState")
local ElevatorMenu = require("src.ui.gen2.ElevatorMenu")
local EvolutionAnim = require("src.ui.gen2.EvolutionAnim")
local PartyMenu = require("src.ui.gen2.PartyMenu")
local FieldMoves = require("src.world.gen2.FieldMoves")
local Permissions = require("src.world.gen2.Permissions")

local FlagIds = require("src.core.gen2.FlagIds")

local A = {}

A.name = "gen2"

-- ---------------------------------------------------------------------------
-- state
-- ---------------------------------------------------------------------------

function A.world(g) return g.world end

function A.ready(g)
  return g.world ~= nil and g.world.map ~= nil and g.phase == "play"
end

function A.mapId(g)
  local w = g.world
  return w and w.map and w.map.id or nil
end

function A.map(g)
  local w = g.world
  return w and w.map or nil
end

function A.pos(g)
  local p = g.world and g.world.player
  if not p then return nil, nil end
  return p.cellX, p.cellY
end

function A.facing(g)
  local p = g.world and g.world.player
  return p and p.facing or "down"
end

function A.moving(g)
  local p = g.world and g.world.player
  return p and p.moving or false
end

-- "Anything that makes the overworld ignore normal player input."  Two
-- separate sources and both matter: World:busy() covers scripts, cutscene
-- movement and the map-setup chain, while a non-nil stack top covers every
-- screen the world pushed (text boxes, choice boxes, menus, the battle).
-- Game2's fixed step returns early on a stack top BEFORE it ever reaches
-- world:step, so a bot that only asked World:busy() would hold a direction
-- into a text box and wonder why it never moved.
function A.busy(g)
  if g.stack and g.stack:top() ~= nil then return true end
  local w = g.world
  return w and w:busy() or false
end

function A.top(g)
  return g.stack and g.stack:top() or nil
end

function A.topIs(g, class)
  local t = A.top(g)
  return t ~= nil and getmetatable(t) == class
end

function A.inBattle(g)
  return A.topIs(g, BattleState)
end

A.BattleState = BattleState

-- "intro" | "menu" | "moves" | "resolving" | "forced-switch" | "submenu" |
-- "evolving" | "done" (src/ui/gen2/BattleState.lua:94).  The bot needs it to
-- tell a battle that is waiting for a decision from one that is waiting for a
-- button.
function A.battlePhase(g)
  local st = A.top(g)
  return (st and A.inBattle(g)) and st.phase or nil
end

-- The battle menu is a 2x2 grid filled row-major -- FIGHT / PkMn over PACK /
-- RUN -- so RUN is index 4 (BattleState's MENU table).  Set the index rather
-- than steer the cursor with d-pad presses: the same technique
-- tests/drivers/gold_boot_smoke.lua uses on the intro menu, and it cannot
-- desync from a cursor that wrapped somewhere unexpected.
A.BATTLE_MENU_FIGHT = 1
A.BATTLE_MENU_POKEMON = 2
A.BATTLE_MENU_PACK = 3
A.BATTLE_MENU_RUN = 4

-- The catch tutorial is a battle with NO player mon at all
-- (src/ui/gen2/BattleState.lua:1067), so its move list is empty and FIGHT is a
-- dead end by design: the menu enters the "moves" phase, finds nothing to
-- submit, and sits there.  Its intended path is PACK, whose tutorial arm
-- throws the DUDE's ball and ends the demo.
function A.battleIsTutorial(g)
  local st = A.top(g)
  return (st and A.inBattle(g) and st.tutorial) and true or false
end

-- The line currently in the battle message box (BattleState.message).  The bot
-- logs it whenever it changes, because "the battle never ended" on its own says
-- nothing about WHY -- whereas the actual text ("CATERPIE has no moves left!")
-- names the engine event that is failing to advance.
function A.battleMessage(g)
  local st = A.top(g)
  return (st and A.inBattle(g)) and st.message or nil
end

function A.playerMoveCount(g)
  local st = A.top(g)
  if not (st and A.inBattle(g)) then return 0 end
  local battle = st.battle
  return #((battle and battle.player and battle.player.moves) or {})
end

-- Choose this turn's move and park the cursor on it.
--
-- Always taking slot 1 is what wedged the long runs.  Two ways it fails, and
-- both are unrecoverable because the port implements no STRUGGLE: a slot-1
-- move at 0 PP just emits "No PP left for this move!" and returns
-- (src/battle/gen2/Battle.lua:739), so the turn never resolves and the menu
-- comes straight back; and a slot-1 move the target is immune to (TACKLE into
-- a GASTLY) means neither side can ever land damage.
--
-- So: only ever select a move that HAS PP, and among those prefer the one that
-- hits hardest, which also gets us off a status move when a damaging one is
-- available.  Returns the chosen index, or nil when every move is dry -- the
-- caller's cue to escape rather than press A at a turn that cannot happen.
function A.pickBattleMove(g)
  local st = A.top(g)
  if not (st and A.inBattle(g) and st.phase == "moves") then return nil end
  local battle = st.battle
  local moves = (battle and battle.player and battle.player.moves) or {}
  local defs = g.data and g.data.moves
  -- Score by EXPECTED damage, not raw power.
  --
  -- Raw power alone is what walked a Fire starter into Morty's Gastly line and
  -- a level-58 lead into Bruno: the hardest-hitting move in the list is
  -- routinely the one the target resists or is immune to, and the bot has no
  -- switching to recover with.  Damage.typeMultiplier is the same table the
  -- battle engine itself uses (matchups are in tenths, so 10 is neutral), so
  -- this cannot disagree with the damage that actually lands.
  local ok, Damage = pcall(require, "src.battle.gen2.Damage")
  local matchups = g.data and g.data.type_chart and g.data.type_chart.matchups
  local st2 = A.top(g)
  local enemy = st2 and st2.battle and st2.battle.enemy
  local enemyTypes = (enemy and enemy.types) or {}
  if enemy and #enemyTypes == 0 then
    local pdef = g.data and g.data.pokemon and g.data.pokemon[enemy.species]
    enemyTypes = (pdef and pdef.types) or {}
  end

  -- STAB, the other half of the damage formula.  Without it a 40-power EMBER
  -- on a Fire starter scores below an 80-power STRENGTH even though the two
  -- land within a few points of each other, which is how the lead ended up
  -- swinging an HM at the Elite Four all game.
  local self_ = st2 and st2.battle and st2.battle.player
  local selfTypes = (self_ and self_.types) or {}
  if self_ and #selfTypes == 0 then
    local sdef = g.data and g.data.pokemon and g.data.pokemon[self_.species]
    selfTypes = (sdef and sdef.types) or {}
  end
  local function stab(moveType)
    for _, t in ipairs(selfTypes) do
      if t == moveType then return 1.5 end
    end
    return 1
  end

  -- `.move_disabled` re-enters the list (engine/battle/core.asm:5236-5246), so
  -- picking a disabled row never resolves.
  local disabled = battle and battle.player and battle.player.volatile
    and battle.player.volatile.disabled

  local bestIndex, bestScore
  for i, move in ipairs(moves) do
    if (move.pp or 0) > 0 and move.id ~= disabled then
      local def = defs and defs[move.id]
      local power = (def and def.power) or 0
      local score = power
      if ok and Damage and Damage.typeMultiplier and def and def.type
          and matchups and #enemyTypes > 0 and power > 0 then
        local mult = Damage.typeMultiplier(def.type, enemyTypes, matchups)
        score = power * (mult or 10) / 10
      end
      if def and def.type and power > 0 then score = score * stab(def.type) end
      if not bestIndex or score > bestScore then
        bestIndex, bestScore = i, score
      end
    end
  end
  if bestIndex then st.moveIndex = bestIndex end
  return bestIndex
end

function A.setBattleMenu(g, index)
  local st = A.top(g)
  if st and A.inBattle(g) and st.phase == "menu" then
    st.menuIndex = index
    return true
  end
  return false
end

-- Why is the world refusing input?  `busy` is a boolean over half a dozen
-- independent sources, so when a run wedges "still busy" says nothing useful.
-- This names the source, which is the difference between a bug report and a
-- shrug: the stack's top state (and its phase, if it has one) plus whichever of
-- World:busy()'s own fields is set.
function A.busyReason(g)
  local parts = {}
  local top = A.top(g)
  if top then
    local kind = "other"
    local mt = getmetatable(top)
    if mt == BattleState then kind = "BattleState"
    elseif mt == EvolutionAnim then kind = "EvolutionAnim" end
    parts[#parts + 1] = "stack=" .. kind
    if top.phase then parts[#parts + 1] = "phase=" .. tostring(top.phase) end
    if top.step then parts[#parts + 1] = "step=" .. tostring(top.step) end
    if top.timer then parts[#parts + 1] = "timer=" .. tostring(top.timer) end
  else
    parts[#parts + 1] = "stack=empty"
  end
  local w = g.world
  if w then
    if w.vm and w.vm:running() then parts[#parts + 1] = "vm:running" end
    for _, field in ipairs({ "mapSetup", "textbox", "moveState", "choicebox",
                             "fishing", "headbutt", "fieldMove" }) do
      if w[field] ~= nil then parts[#parts + 1] = field end
    end
  end
  return table.concat(parts, " ")
end

-- The species on the far side of a wild battle, so the bot can decide whether
-- this is the one worth a ball.
function A.enemySpecies(g)
  local st = A.top(g)
  if not (st and A.inBattle(g)) then return nil end
  local battle = st.battle
  return battle and battle.enemy and battle.enemy.species or nil
end

function A.enemyHpFraction(g)
  local st = A.top(g)
  if not (st and A.inBattle(g)) then return 1 end
  local enemy = st.battle and st.battle.enemy
  if not (enemy and enemy.maxHp and enemy.maxHp > 0) then return 1 end
  return (enemy.hp or 0) / enemy.maxHp
end

function A.isWildBattle(g)
  local st = A.top(g)
  return (st and A.inBattle(g) and st.battle and st.battle.wild) and true or false
end

-- Throw a ball.  BattleState:useItem takes an item id and does the whole
-- PokeBallEffect itself, so this skips the PACK menu the player would walk --
-- the same shortcut ops.teach takes, and for the same reason: the route is what
-- is under test, not menu navigation.
-- The strongest healing item in the bag, or nil.
--
-- The bot fought every gym from Whitney on with no items at all, which is why
-- each one had to be answered with tens of thousands of frames of grinding: a
-- level advantage was the only lever it had.  Ordered worst-first so the
-- cheapest thing that will do the job is spent.
A.HEAL_ITEMS = { "POTION", "SUPER_POTION", "HYPER_POTION", "MAX_POTION",
                 "FULL_RESTORE" }

-- Roughly what each one restores, for rationing.  `full` means the whole bar.
A.HEAL_AMOUNT = {
  POTION = 20, SUPER_POTION = 50, HYPER_POTION = 200,
  MAX_POTION = "full", FULL_RESTORE = "full",
}

-- The lead's status condition ("paralyze" / "sleep" / "freeze" / "burn" /
-- "poison" / "toxic"), or nil.  The battle mon aliases the party slot, so this
-- is the same table the turn loop reads.
function A.leadStatus(g)
  local st = A.top(g)
  local lead = st and st.battle and st.battle.player
  return lead and lead.status or nil
end

-- Cure a movement-blocking status with a FULL_RESTORE, or nil.
--
-- The port implements FULL_RESTORE (status + full HP) but not the standalone
-- FULL_HEAL / PARLYZ_HEAL, so the one cure the bot has is the FULL_RESTORE it
-- otherwise saves for the Champion.  Paralysis is worth one: THUNDER WAVE off
-- Clair's DRAGONAIR halves the lead's speed AND skips a quarter of its turns,
-- so a paralyzed Fire lead loses the KINGDRA attrition war to a super-
-- effective SURF and Clair's HYPER POTION every time.  Only the three statuses
-- that actually cost turns, and only in a trainer fight (a wild one is over
-- before it matters), and only once the FULL_RESTORE would also do real HP
-- work OR the fight is a leader/Elite Four -- so it does not burn on a route
-- grunt's STUN SPORE.
local TURN_COSTING_STATUS = { paralyze = true, sleep = true, freeze = true }

function A.statusCure(g)
  local st = A.top(g)
  if not (st and A.inBattle(g)) or A.battleIsTutorial(g) then return nil end
  if not (st.battle and st.battle.trainer) then return nil end   -- trainers only
  local status = A.leadStatus(g)
  if not TURN_COSTING_STATUS[status] then return nil end
  local save = g.save
  if not (save and save.inventory and (save.inventory.FULL_RESTORE or 0) > 0) then
    return nil
  end
  return "FULL_RESTORE"
end

-- Which heal to spend, given how much trouble the lead is in.
--
-- This used to answer "the strongest one owned", which is the wrong end of the
-- shelf.  The Elite Four is five fights with no Pokecenter between them, so the
-- bag has to last all five -- and a bot that drinks a FULL RESTORE to top up
-- 43% of a health bar in WILL's room meets LANCE with an empty bag.  Run 21
-- swept all four rooms and then lost the Champion that way, twice.
--
-- So: the weakest item that would actually accomplish something, and the
-- strongest only when the next hit is going to kill.  "Actually accomplish
-- something" is a quarter of the bar -- a 20-point POTION on a level-88
-- TYPHLOSION is a wasted turn, which at these levels is worse than not healing.
function A.bestHeal(g, fraction)
  local save = g.save
  if not (save and save.inventory) then return nil end
  local have = function(id) return (save.inventory[id] or 0) > 0 end

  -- The emergency: reach for the best thing in the bag.
  if (fraction or 1) < 0.35 then
    for i = #A.HEAL_ITEMS, 1, -1 do
      if have(A.HEAL_ITEMS[i]) then return A.HEAL_ITEMS[i] end
    end
    return nil
  end

  local lead = A.party(g)[1]
  local maxHp = (lead and (lead.maxHp or (lead.stats and lead.stats.hp))) or 100
  local worthwhile = maxHp * 0.25
  for _, id in ipairs(A.HEAL_ITEMS) do          -- weakest first
    local amount = A.HEAL_AMOUNT[id]
    if have(id) and (amount == "full" or amount >= worthwhile) then
      return id
    end
  end
  -- Nothing meaningful short of the good stuff; leave it for the emergency.
  return nil
end

-- BattleState:useItem is the same entry point A.throwBall uses: it takes an
-- item id and runs the effect, skipping the PACK menu the player would walk.
function A.useItem(g, itemId)
  local st = A.top(g)
  if not (st and A.inBattle(g) and st.phase == "menu") then return false end
  st:useItem(itemId)
  return true
end

function A.throwBall(g, itemId)
  local st = A.top(g)
  if not (st and A.inBattle(g)) then return false end
  if st.phase ~= "menu" then return false end
  st:useItem(itemId)
  return true
end

-- A lead that faints leaves the battle in its "forced-switch" phase, which
-- opens the party list and waits for a choice (src/ui/gen2/BattleState.lua:703).
-- The list is its own screen, so the battle's own menu handling cannot answer
-- it -- and mashing A only re-selects whatever the cursor starts on, which is
-- the mon that just fainted.  Point the cursor at something that can still
-- fight and confirm.
function A.partyMenuUp(g)
  return A.topIs(g, PartyMenu)
end

-- AskLearnMove's forget picker (BattleState phase "choose-forget").  The mon
-- levelled into a fifth move and the battle is paused on which of the four to
-- drop.  Leaving it unanswered froze the exp queue; picking wrong throws away
-- the attack the endgame needs -- so keep HMs and drop the weakest real move.
function A.forgetMenuUp(g)
  local st = A.top(g)
  return st ~= nil and A.inBattle(g) and st.phase == "choose-forget"
    and (st.messageTimer or 0) <= 0 and st.pendingLearn ~= nil
end

-- Answer the forget picker.  Points forgetIndex at the weakest non-HM move and
-- presses A to drop it, unless the newcomer is no upgrade or every slot is an
-- HM, in which case it presses B and keeps the four.  Same set-index-then-tap
-- shape as A.chooseHealthyPartyMon.  Returns "learn", "keep" or false.
local HM_MOVE = { CUT = true, FLY = true, SURF = true, STRENGTH = true,
                  FLASH = true, WHIRLPOOL = true, WATERFALL = true }

function A.resolveForgetMenu(g)
  local st = A.top(g)
  if not A.forgetMenuUp(g) then return false end
  local learn = st.pendingLearn
  local mon = learn and st.battle and st.battle.party[learn.index]
  local moves = (mon and mon.moves) or {}
  local defs = (st.game and st.game.data and st.game.data.moves) or {}
  -- The pending move's own power: never drop a stronger move for a weaker one,
  -- or the bot keeps sawing away with the level-1 attack it already has.
  local newPower = (learn.move and defs[learn.move.id]
    and defs[learn.move.id].power) or 0
  local worst, worstPower
  for i, mv in ipairs(moves) do
    if not HM_MOVE[mv.id] then
      local p = (defs[mv.id] and defs[mv.id].power) or 0
      if not worst or p < worstPower then worst, worstPower = i, p end
    end
  end
  if not worst or worstPower >= newPower then
    return "b"                -- keep the four it has
  end
  st.forgetIndex = worst      -- cursor on the drop; caller taps A to confirm
  return "a"
end

-- The naming keyboard, and how to get off it without typing anything.
--
-- The bot's dialogue loop answers an unknown prompt by pressing A, which on a
-- keyboard screen means "add the letter under the cursor".  The cursor starts
-- on A and the field holds ten characters, so every unqueued nickname prompt
-- produced a Pokemon called AAAAAAAAAA -- which is how the hatched TOGEPI ended
-- up with that name for a whole playthrough.  There is no cancel on this screen
-- (only END), and accepting an EMPTY name is the "no thanks" answer: HatchEggs
-- copies the species name into the slot, and the port stores that as no
-- nickname (src/core/gen2/Breeding.lua:1010).
function A.namingScreenUp(g)
  local t = A.top(g)
  return t ~= nil and type(t.accept) == "function"
    and type(t.addCharacter) == "function"
end

function A.dismissNaming(g)
  local t = A.top(g)
  if not A.namingScreenUp(g) then return false end
  t.text = ""
  t:accept()
  return true
end

-- Switch training, which is the only way a level-5 mon gets anywhere.
--
-- Battle:awardExperience credits every PARTICIPANT that is still alive, not
-- just whoever landed the kill -- so sending the weakling out and immediately
-- switching to the fighter earns it a full share while it never takes a hit
-- (the incoming mon eats the turn's attack, as on the cart). Without this a
-- party-minimum grind is unreachable by construction: the TOGEPI hatches at
-- level 5, gets rotated to the front, faints to Route 34's teens before it can
-- act, and a FAINTED participant is awarded nothing. Run 24 sat at
-- "grind: level 5/20" for 166k frames proving it.
function A.openBattleParty(g)
  local st = A.top(g)
  if not (st and A.inBattle(g) and st.phase == "menu") then return false end
  if type(st.openParty) ~= "function" then return false end
  st:openParty()
  return true
end

-- The highest-level healthy non-egg mon: the one that can actually win the
-- fight the weakling just got credit for starting.
function A.chooseStrongestPartyMon(g)
  local menu = A.top(g)
  if not (menu and A.topIs(g, PartyMenu)) then return false end
  local best
  for i, mon in ipairs(menu.party or {}) do
    if not mon.isEgg and (mon.hp or 0) > 0
        and (not best or (mon.level or 0) > (menu.party[best].level or 0)) then
      best = i
    end
  end
  if not best then return false end
  menu.index = best
  return true
end

-- Is the mon currently out the weakest thing we could have sent?  Used to
-- decide whether a switch is worth the turn.
function A.leadIsWeakest(g)
  local party = A.party(g)
  local lead = party[1]
  if not lead then return false end
  local leadLevel = lead.level or 0
  for i = 2, #party do
    local mon = party[i]
    if mon and not mon.isEgg and (mon.hp or 0) > 0
        and (mon.level or 0) > leadLevel then
      return true
    end
  end
  return false
end

function A.chooseHealthyPartyMon(g)
  local menu = A.top(g)
  if not (menu and A.topIs(g, PartyMenu)) then return false end
  for index, mon in ipairs(menu.party or {}) do
    -- Never an EGG.  It has HP, so "the first mon with HP left" picked it, and
    -- the log filled with "AAAAAAAAAA fainted!" -- the Togepi egg being sent
    -- into Morty's Gengar and dying on the spot, twice, before the only mon
    -- that could fight got its turn.  The cart cannot do this: an egg has no
    -- moves and CheckCurPartyMon refuses it.
    if not mon.isEgg and (mon.hp or 0) > 0 then
      menu.index = index
      return true
    end
  end
  return false
end

-- ---------------------------------------------------------------------------
-- flags, items, party
-- ---------------------------------------------------------------------------

function A.event(g, name)
  local id = FlagIds.events(g.data.gen2Constants)[name]
  if not id then return nil end            -- nil, not false: an unknown NAME is
                                           -- a route bug, not an unset flag
  local w = g.world
  if not (w and w.events) then return nil end
  return w.events:get(id)
end

function A.engine(g, name)
  local id = FlagIds.engine(g.data.gen2Constants)[name]
  if not id then return nil end
  local w = g.world
  if not w then return nil end
  return w:engineFlag(id) and true or false
end

function A.knownFlag(g, name)
  local constants = g.data.gen2Constants
  return FlagIds.events(constants)[name] ~= nil or FlagIds.engine(constants)[name] ~= nil
end

function A.badges(g)
  local n = 0
  for _, badge in ipairs({
    "ENGINE_ZEPHYRBADGE", "ENGINE_HIVEBADGE", "ENGINE_PLAINBADGE",
    "ENGINE_FOGBADGE", "ENGINE_MINERALBADGE", "ENGINE_STORMBADGE",
    "ENGINE_GLACIERBADGE", "ENGINE_RISINGBADGE",
  }) do
    if A.engine(g, badge) then n = n + 1 end
  end
  return n
end

function A.party(g)
  local save = g.save
  return (save and save.party) or {}
end

function A.partySize(g)
  return #A.party(g)
end

-- Lowest surviving level in the party, which is what "grind to level N" has to
-- mean: the highest would let one overlevelled starter mask five faint-bait
-- team-mates, and the average would hide both.
function A.minLevel(g)
  local lowest
  for _, mon in ipairs(A.party(g)) do
    -- An EGG occupies a party slot, has a level, and can never fight or gain
    -- one -- so counting it makes "grind the party to N" a target that can
    -- never be reached, and the route carries the Togepi egg from Violet all
    -- the way to Elm.  Breeding.isEgg is the same predicate the party menu and
    -- the battle switch-in use.
    local lv = (not mon.isEgg) and mon.level or nil
    if lv and (not lowest or lv < lowest) then lowest = lv end
  end
  return lowest or 0
end

-- The lead's level.  Pre-gym grinding targets this rather than the party
-- minimum: the SLOWPOKE is caught around L6 purely to carry SURF, and dragging
-- the whole party up to the lead's level would multiply the grind for no
-- fighting benefit.
function A.leadLevel(g)
  local mon = A.party(g)[1]
  return (mon and mon.level) or 0
end

function A.partyHealthy(g)
  local party = A.party(g)
  if #party == 0 then return false end
  for _, mon in ipairs(party) do
    if (mon.hp or 0) > 0 then return true end
  end
  return false
end

-- Fraction of the lead mon's HP, for the "should we go heal" policy.
function A.leadHpFraction(g)
  local mon = A.party(g)[1]
  if not mon or not mon.maxHp or mon.maxHp == 0 then return 1 end
  return (mon.hp or 0) / mon.maxHp
end

-- Fraction of the party's total PP still available.
--
-- This is not a nicety, it is the difference between a run that finishes and
-- one that wedges forever.  The Gen 2 port has no STRUGGLE: at 0 PP the
-- player's move emits "No PP left for this move!" and returns
-- (src/battle/gen2/Battle.lua:739), and an enemy with no usable move emits
-- "<name> has no moves left!" and returns (:1880).  Neither side falls back to
-- Struggle the way the cart does, so a battle where both sides are dry can
-- never end and cannot be run from if it is a trainer.  The bot's only defence
-- is to never arrive at 0 PP, which means treating PP as a resource worth
-- walking to a Pokecenter for.
function A.partyPpFraction(g)
  local have, max = 0, 0
  for _, mon in ipairs(A.party(g)) do
    for _, move in ipairs(mon.moves or {}) do
      have = have + (move.pp or 0)
      max = max + (move.maxPp or move.pp or 0)
    end
  end
  if max == 0 then return 1 end
  return have / max
end

-- The same measure over ATTACKING moves only.
--
-- Total PP is the wrong trigger for "go and heal" and it let a run wedge:
-- LEER and SMOKESCREEN carry 30 and 20 PP and are never spent, so a starter
-- whose EMBER and TACKLE are both dry still reports most of its PP intact.
-- What actually decides whether the next battle can be won is how many
-- POWERED moves are left, so that is what the policy watches.
function A.damagingPpFraction(g)
  local defs = g.data and g.data.moves
  local have, max = 0, 0
  for _, mon in ipairs(A.party(g)) do
    for _, move in ipairs(mon.moves or {}) do
      local def = defs and defs[move.id]
      if def and (def.power or 0) > 0 then
        have = have + (move.pp or 0)
        max = max + (move.maxPp or move.pp or 0)
      end
    end
  end
  if max == 0 then return 1 end   -- nothing damaging to run out of
  return have / max
end

-- Bag membership by item id ("POTION", "HM_CUT").  `save.inventory` is the
-- flat id -> count map; the four Gen 2 pockets are a PackMenu presentation of
-- it, not a second store (src/core/gen2/Save.lua:158).
function A.hasItem(g, id)
  local save = g.save
  if not (save and save.inventory) then return false end
  return (save.inventory[id] or 0) > 0
end

-- ---------------------------------------------------------------------------
-- geometry
-- ---------------------------------------------------------------------------

function A.inBounds(map, x, y)
  return map:inBounds(x, y)
end

-- Can the player stand on this cell right now?  On foot that is the cart's
-- .CheckWalkable (permission == LAND); surfing it is the WATER half of
-- .CheckSurfable, plus the LAND cells that end the surf.
function A.walkable(g, map, x, y)
  if not map:inBounds(x, y) then return false end
  local coll = map:cellCollision(x, y)
  if A.surfing(g) then
    return Permissions.surfable(coll) ~= nil
  end
  return Permissions.isWalkable(coll)
end

function A.surfing(g)
  local w = g.world
  return w and FieldMoves.isSurfing(w.playerState) or false
end

-- Is this cell water?  Separate from A.walkable because the bot needs to plan
-- a route that STARTS on land and continues over water: "can I stand here" and
-- "could I get here at all" are different questions the moment SURF exists.
function A.isWater(map, x, y)
  if not map:inBounds(x, y) then return false end
  return Permissions.isWater(map:cellCollision(x, y))
end

-- COLL_ICE / COLL_ICE_2B.  A step that lands here keeps going until a non-ice
-- cell or a bump (World:turningDirection + CheckStandingOnIce), so the bot's
-- planner has to treat ice as a slide to a REST position, not as ordinary floor.
function A.isIce(map, x, y)
  if not map:inBounds(x, y) then return false end
  return Permissions.isIce(map:cellCollision(x, y))
end

-- The elevator's floor list when it is the top state, or nil.  The three
-- elevators (both dept stores and the Radio Tower) are the one interior link
-- the map graph cannot express -- Elevator_GoToFloor rewrites the door warp's
-- destination instead of warping -- so ops.elevator drives this screen's
-- cursor with real presses and then walks out the door.
function A.elevatorMenu(g)
  local top = A.top(g)
  if top and getmetatable(top) == ElevatorMenu then return top end
  return nil
end

-- The display name of the menu's i-th row ("B1F", "1F", ...).
function A.elevatorFloorName(menu, i)
  local row = menu.floors and menu.floors[i]
  if not row then return nil end
  return ElevatorMenu.floorName(menu.floorNames, row.floorId)
end

-- GetMovementPermissions' verdict on leaving (x, y) toward dir: the standing
-- tile's side-wall kind and Gold's neighbour arms (an UP_WALL below forbids
-- the DOWN step).  The same Permissions.stepPermitted the engine runs, so the
-- planner and the world cannot disagree about a one-way tile.
function A.stepPermitted(map, x, y, dir)
  return Permissions.stepPermitted(
    function(cx, cy) return map:cellCollision(cx, cy) end, x, y, dir)
end

-- The facings that hop the ledge at (x, y), or nil (.TryJump's .ledge_table).
function A.ledgeFacings(map, x, y)
  if not map:inBounds(x, y) then return nil end
  return Permissions.ledgeFacings(map:cellCollision(x, y))
end

-- Who in the party can carry us, or nil.  World:partyMoveUser is the same check
-- the field-move menu runs, so this honours the badge gate (FOGBADGE) rather
-- than just the move being known.
function A.surfUser(g)
  local w = g.world
  if not (w and w.partyMoveUser) then return nil end
  -- The badge, not just the move.  partyMoveUser answers "who knows SURF",
  -- which is the question the field-move MENU asks; the gate that actually
  -- decides whether the water opens is FOGBADGE, checked inside useFieldMove.
  -- Planning on the move alone made the whole coast look passable to a bot
  -- that had lost Morty, so every step along the shore tried to launch and was
  -- refused -- twenty thousand frames of walking up and down a beach.
  if not FieldMoves.hasBadge(g.save, FieldMoves.BADGE.SURF) then return nil end
  local ok, user = pcall(w.partyMoveUser, w, "SURF")
  return ok and user or nil
end

function A.startSurf(g)
  local w = g.world
  local user = A.surfUser(g)
  if not (w and user) then return false end
  local ok, result = pcall(w.useFieldMove, w, "SURF", user)
  return ok and result and result.ok or false
end

-- The other two badge-gated water moves, same shape as A.surfUser /
-- A.startSurf.  WHIRLPOOL swaps the facing block for plain water
-- (Script_UsedWhirlpool); WATERFALL climbs the whole falls in forced UP steps
-- (Script_UsedWaterfall).  Route 27 needs both at once, which is why the
-- route carries a mule that knows them alongside SURF.
local function badgedWaterUser(g, move)
  local w = g.world
  if not (w and w.partyMoveUser) then return nil end
  if not FieldMoves.hasBadge(g.save, FieldMoves.BADGE[move]) then return nil end
  local ok, user = pcall(w.partyMoveUser, w, move)
  return ok and user or nil
end

function A.whirlpoolUser(g) return badgedWaterUser(g, "WHIRLPOOL") end
function A.waterfallUser(g) return badgedWaterUser(g, "WATERFALL") end

local function useWaterMove(g, move, user)
  local w = g.world
  if not (w and user) then return false end
  local ok, result = pcall(w.useFieldMove, w, move, user)
  return ok and result and result.ok or false
end

function A.useWhirlpool(g)
  return useWaterMove(g, "WHIRLPOOL", A.whirlpoolUser(g))
end

function A.useWaterfall(g)
  return useWaterMove(g, "WATERFALL", A.waterfallUser(g))
end

function A.isWhirlpool(map, x, y)
  if not map:inBounds(x, y) then return false end
  return Permissions.isWhirlpool(map:cellCollision(x, y))
end

function A.isWaterfall(map, x, y)
  if not map:inBounds(x, y) then return false end
  return Permissions.isWaterfall(map:cellCollision(x, y))
end

function A.warpAt(map, x, y)
  return map:warpAt(x, y)
end

-- Does stepping here actually leave the map?
--
-- A `warp_event` coordinate is NOT enough.  CheckWarpTile reads the TILE's
-- collision, so a warp_event sitting on plain floor never fires -- and Ecruteak
-- Gym is full of them: thirty of its thirty-three warps are the floor holes,
-- but several of those coordinates are ordinary floor and are the safe path
-- between the pits.  Refusing every warp COORDINATE cut the gym in half and
-- left Morty, and therefore FOGBADGE and SURF, unreachable on foot.
--
-- Carpets count too: they need a press in their own direction, but a bot that
-- walks over one while holding that direction still leaves.
function A.isWarpTile(map, x, y)
  if not map:warpAt(x, y) then return false end
  local coll = map:cellCollision(x, y)
  return Permissions.isWarpCollision(coll)
      or Permissions.carpetDirection(coll) ~= nil
end

-- Which direction this tile's warp wants held, or nil if it takes on arrival.
--
-- Gen 2 has two kinds of warp tile and they are driven completely differently
-- (src/world/gen2/Permissions.lua).  A door / staircase / cave / panel fires
-- the moment you step on it.  A CARPET fires only from
-- World:checkCarpetWhileStanding, which wants the player STOPPED on the tile
-- with the carpet's own direction held -- so a bot that just walks on and
-- waits will stand in a doorway forever, which is exactly what the front door
-- of the player's house did on the first run.
-- A COLL_COUNTER tile: not walkable, but an A press reaches over it (see
-- World:interact).  The bot needs this to know a nurse two cells away is
-- talkable from where it can actually stand.
-- Does a step onto this cell roll for a wild encounter?  Wandering at random
-- mostly walks corridor, which is why a hunt could burn 150k frames without
-- meeting the species it wanted.
function A.isEncounterCell(map, x, y)
  return Permissions.isEncounterCollision(map:cellCollision(x, y))
end

function A.isCounter(map, x, y)
  return Permissions.isCounter(map:cellCollision(x, y))
end

function A.carpetDir(map, x, y)
  return Permissions.carpetDirection(map:cellCollision(x, y))
end

function A.warps(map)
  return map.warps or {}
end

function A.connections(map)
  return map.connections or {}
end

-- Objects and bg events live on the extracted DEF, not on the live Map:
-- Map.new copies blocks, warps and connections and leaves the rest behind
-- (src/world/gen2/Map.lua:13).  Reading map.objects therefore silently gives
-- an empty list, which is how "heal" once concluded a Pokecenter had no nurse
-- while she was standing at (3,1).
function A.objects(map)
  if not map then return {} end
  return map.objects or (map.def and map.def.objects) or {}
end

function A.bgEvents(map)
  if not map then return {} end
  return map.bgEvents or (map.def and map.def.bgEvents) or {}
end

-- Is an NPC standing here?  Blocks a step the same way a wall does, but is
-- transient, which is why the bot's wall memory must never learn from it.
function A.npcAt(g, x, y)
  local w = g.world
  if not (w and w.npcAt) then return nil end
  local ok, npc = pcall(w.npcAt, w, x, y)
  return ok and npc or nil
end

-- The npc whose OBJECT ROW homes at (x, y), wherever it stands right now.
--
-- A sighted trainer WALKS to the player and stays where the fight happened,
-- so the cell a route row names -- the object's home coordinates out of the
-- map data -- can be empty while the trainer parks two cells away.  The
-- RaticateTail grunt is the one that costs a run: his sight line pulls him
-- off (5,15), the re-talk row then presses A at nothing, and without
-- EVENT_LEARNED_RATICATE_TAIL the door to Giovanni never opens.
function A.npcHome(g, x, y)
  local w = g.world
  for _, npc in ipairs((w and w.npcs) or {}) do
    if (npc.homeX == x and npc.homeY == y)
        or (npc.def and npc.def.x == x and npc.def.y == y) then
      return npc
    end
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- input
-- ---------------------------------------------------------------------------
-- Two shapes, and mixing them up is the classic driver bug.  A press is an
-- EDGE: pressQueue is what Input:step promotes into wasPressed, which is what
-- every menu, text box and `interact` reads.  A direction is a HELD state:
-- World:pollInput asks input:isDown, so a tapped direction is usually gone
-- before the world looks.

function A.press(g, button)
  local input = g.input
  input.pressQueue[#input.pressQueue + 1] = button
  input.state[button] = true
end

function A.release(g, button)
  g.input.state[button] = false
end

A.DIRS = { "up", "down", "left", "right" }

function A.releaseDirs(g)
  for _, d in ipairs(A.DIRS) do g.input.state[d] = false end
end

function A.hold(g, dir)
  A.releaseDirs(g)
  g.input.pressQueue[#g.input.pressQueue + 1] = dir
  g.input.state[dir] = true
end

-- ---------------------------------------------------------------------------
-- save / checkpoint
-- ---------------------------------------------------------------------------

-- Drop the player onto a map directly.  A TEST-HARNESS SHORTCUT, not
-- navigation: tests/drivers/gold_walk_smoke.lua uses the same world:setMap call
-- to skip a fragile indoor route.  The bot uses it only as a last resort, after
-- real pathfinding has failed, and says so in the log every time -- a run that
-- needed it has NOT proved the map graph works, only that everything downstream
-- of the gap does.
function A.teleport(g, mapId, x, y)
  local w = g.world
  if not (w and w.setMap) then return false end
  local ok = pcall(w.setMap, w, mapId, x, y, "down")
  return ok and A.mapId(g) == mapId
end

function A.save(g)
  local ok, res, err = pcall(require("src.core.gen2.Save").save, g.save)
  if not ok then return false, tostring(res) end
  return res and true or false, err
end

-- ---------------------------------------------------------------------------
-- checkpoints
-- ---------------------------------------------------------------------------
-- A run is ~700k frames of accumulated luck, so reproducing a section-13 bug
-- used to mean replaying sections 00-12 first and hoping the variance landed
-- the same way.  A checkpoint is the ordinary save file under a second name:
-- Game2:snapshotSave folds the live world (position, events, map scenes,
-- player state, script memory) back into the save table, which is exactly
-- the state a resume has to restore.  Nothing here is a shortcut the player
-- could not take -- it is SAVE and CONTINUE, driven from the harness.

local function ckptPath(name)
  return ("gold-ckpt-%s.lua"):format(tostring(name))
end

A.checkpointPath = ckptPath

function A.writeCheckpoint(g, name)
  if not (g.snapshotSave and love and love.filesystem) then
    return false, "no snapshot"
  end
  local ok, snap = pcall(g.snapshotSave, g)
  if not (ok and snap) then return false, tostring(snap) end
  local encoded
  ok, encoded = pcall(require("src.core.SaveSerializer").encode, snap)
  if not ok then return false, tostring(encoded) end
  local wrote, err = love.filesystem.write(ckptPath(name), encoded)
  return wrote and true or false, err
end

function A.hasCheckpoint(name)
  return love and love.filesystem
    and love.filesystem.getInfo(ckptPath(name)) ~= nil
end

-- Restore one.  continueGame is the CONTINUE path itself: it adopts the save,
-- clears the stack, drops the world and rebuilds it at save.position -- so a
-- resumed run is in the same state a player who saved and reloaded would be.
function A.loadCheckpoint(g, name)
  if not (love and love.filesystem) then return false, "no filesystem" end
  local raw = love.filesystem.read(ckptPath(name))
  if not raw then return false, "no checkpoint " .. tostring(name) end
  local Save = require("src.core.gen2.Save")
  local ok, save = pcall(require("src.core.SaveSerializer").decode, raw)
  if not (ok and type(save) == "table") then return false, tostring(save) end
  Save.migrate(save)
  Save.normalize(save)
  local started, err = pcall(g.continueGame, g, save)
  if not started then return false, tostring(err) end
  return true
end

return A
