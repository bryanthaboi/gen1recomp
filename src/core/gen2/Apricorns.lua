-- Kurt, the apricorns, the trees they grow on, and the day he takes to turn
-- one into a ball.
--
-- Gold has no engine/events/kurt.asm: the whole conversation is map script
-- bytecode in maps/KurtsHouse.asm, and the only compiled routines behind it are
-- Kurt_SelectApricorn (engine/menus/menu_2.asm), the ApricornBalls table
-- (data/items/apricorn_balls.asm) and the SelectApricornForKurt special
-- (engine/events/specials.asm), which is the one that actually takes the
-- apricorn out of the bag.  So this module is those three plus the clock the
-- script leans on, and nothing else: the dialogue belongs to the extracted
-- script and stays there.
--
-- The trees are the other half.  engine/events/fruit_trees.asm is a whole
-- FruitTreeScript in the ROM already; what it needs from the port is the
-- FruitTreeItems lookup, the per-tree picked flag and the daily reset that
-- refills every tree at once.  Seven of the thirty trees are apricorn trees,
-- which is why they live in this file rather than in a fruit module of their
-- own.
--
-- THE DAY-LONG WAIT is the piece most likely to be got wrong.  Kurt does not
-- run a timer of his own.  `setflag ENGINE_KURT_MAKING_BALLS` sets bit 0 of
-- wDailyFlags1, and the ONLY thing that ever clears it is CheckDailyResetTimer
-- wiping wDailyFlags1 and wDailyFlags2 whole once a day has passed
-- (engine/overworld/time.asm).  So "come back tomorrow" means "come back after
-- the next daily rollover", which can be twenty-three hours or one minute
-- depending on when you handed the apricorn over -- and a player who winds the
-- clock BACK gets the rollover immediately, because _CalcDaysSince wraps a
-- negative difference into a large positive one instead of clamping it.  The
-- cart does nothing to stop that, and neither does this.
--
-- The RTC helpers themselves are in src/core/gen2/BugContest.lua, which is the
-- port's only second-resolution consumer of the same engine/overworld/time.asm
-- block; both belong in a src/core/gen2/Time.lua once one exists.

local BugContest = require("src.core.gen2.BugContest")
local Buena = require("src.core.gen2.Buena")
local EngineFlags = require("src.core.gen2.EngineFlags")
local Runtime = require("src.mods.Runtime")
local CartTimers = require("src.save_convert.gen2_state.clock_phone")
local CartDayCareWild = require("src.save_convert.gen2_state.daycare_wild")

local Apricorns = EngineFlags.expose({}, {
  "ENGINE_KURT_MAKING_BALLS", "ENGINE_ALL_FRUIT_TREES",
})

-- ------------------------------------------------------- apricorns and balls
--
-- data/items/apricorn_balls.asm, in table order.  That order is load bearing
-- twice over: FindApricornsInBag walks it to build Kurt's menu, so the menu is
-- always red, blue, yellow, green, white, black, pink regardless of pack
-- order, and Kurt1's checkevent chain in maps/KurtsHouse.asm tests the seven
-- EVENT_GAVE_KURT_*_APRICORN flags in the same order, so a save that somehow
-- held two of them would hand back the earlier ball first.
--
-- The event ids are constants/event_flags.asm indices, which is what the
-- extracted script's `checkevent` / `setevent` / `clearevent` carry.  They are
-- NOT the count of `const` lines above them: `const_next 600` two lines before
-- EVENT_GAVE_KURT_RED_APRICORN jumps the counter, which is why the block sits
-- at 600 rather than at the 237 a reader who counted would arrive at.  The
-- extracted Kurt1 script agrees -- its red-apricorn arm is `setevent 600`.
Apricorns.BALLS = {
  { apricorn = "RED_APRICORN", ball = "LEVEL_BALL",  event = 600 },
  { apricorn = "BLU_APRICORN", ball = "LURE_BALL",   event = 601 },
  { apricorn = "YLW_APRICORN", ball = "MOON_BALL",   event = 602 },
  { apricorn = "GRN_APRICORN", ball = "FRIEND_BALL", event = 603 },
  { apricorn = "WHT_APRICORN", ball = "FAST_BALL",   event = 604 },
  { apricorn = "BLK_APRICORN", ball = "HEAVY_BALL",  event = 605 },
  { apricorn = "PNK_APRICORN", ball = "LOVE_BALL",   event = 606 },
}

-- constants/engine_flags.asm:97, ../pokecrystal/constants/engine_flags.asm:98
Apricorns.DAILY_ENGINE_FLAGS = {
  "ENGINE_KURT_MAKING_BALLS",
  "ENGINE_DAILY_BUG_CONTEST",
  "ENGINE_SWARM",
  "ENGINE_QWILFISH_SWARM",
  "ENGINE_TIME_CAPSULE",
  "ENGINE_ALL_FRUIT_TREES",
  "ENGINE_GOT_SHUCKIE_TODAY",
  "ENGINE_GOLDENROD_UNDERGROUND_MERCHANT_CLOSED",
  "ENGINE_FOUGHT_IN_TRAINER_HALL_TODAY",
  "ENGINE_MT_MOON_SQUARE_CLEFAIRY",
  "ENGINE_UNION_CAVE_LAPRAS",
  "ENGINE_GOLDENROD_UNDERGROUND_GOT_HAIRCUT",
  "ENGINE_GOLDENROD_DEPT_STORE_TM27_RETURN",
  "ENGINE_DAISYS_GROOMING",
  "ENGINE_INDIGO_PLATEAU_RIVAL_FIGHT",
  "ENGINE_DAILY_MOVE_TUTOR",
  "ENGINE_BUENAS_PASSWORD",
}

local CRYSTAL_PHONE_FLAGS = {
  "ENGINE_JACK_READY_FOR_REMATCH",
  "ENGINE_HUEY_READY_FOR_REMATCH",
  "ENGINE_GAVEN_READY_FOR_REMATCH",
  "ENGINE_BETH_READY_FOR_REMATCH",
  "ENGINE_JOSE_READY_FOR_REMATCH",
  "ENGINE_REENA_READY_FOR_REMATCH",
  "ENGINE_JOEY_READY_FOR_REMATCH",
  "ENGINE_WADE_READY_FOR_REMATCH",
  "ENGINE_RALPH_READY_FOR_REMATCH",
  "ENGINE_LIZ_READY_FOR_REMATCH",
  "ENGINE_ANTHONY_READY_FOR_REMATCH",
  "ENGINE_TODD_READY_FOR_REMATCH",
  "ENGINE_GINA_READY_FOR_REMATCH",
  "ENGINE_ARNIE_READY_FOR_REMATCH",
  "ENGINE_ALAN_READY_FOR_REMATCH",
  "ENGINE_DANA_READY_FOR_REMATCH",
  "ENGINE_CHAD_READY_FOR_REMATCH",
  "ENGINE_TULLY_READY_FOR_REMATCH",
  "ENGINE_BRENT_READY_FOR_REMATCH",
  "ENGINE_TIFFANY_READY_FOR_REMATCH",
  "ENGINE_VANCE_READY_FOR_REMATCH",
  "ENGINE_WILTON_READY_FOR_REMATCH",
  "ENGINE_PARRY_READY_FOR_REMATCH",
  "ENGINE_ERIN_READY_FOR_REMATCH",
  "ENGINE_BEVERLY_HAS_NUGGET",
  "ENGINE_JOSE_HAS_STAR_PIECE",
  "ENGINE_WADE_HAS_ITEM",
  "ENGINE_GINA_HAS_LEAF_STONE",
  "ENGINE_ALAN_HAS_FIRE_STONE",
  "ENGINE_DANA_HAS_THUNDERSTONE",
  "ENGINE_DEREK_HAS_NUGGET",
  "ENGINE_TULLY_HAS_WATER_STONE",
  "ENGINE_TIFFANY_HAS_PINK_BOW",
  "ENGINE_WILTON_HAS_ITEM",
  "ENGINE_JACK_MONDAY_MORNING",
  "ENGINE_HUEY_WEDNESDAY_NIGHT",
  "ENGINE_GAVEN_THURSDAY_MORNING",
  "ENGINE_BETH_FRIDAY_AFTERNOON",
  "ENGINE_JOSE_SATURDAY_NIGHT",
  "ENGINE_REENA_SUNDAY_MORNING",
  "ENGINE_JOEY_MONDAY_AFTERNOON",
  "ENGINE_WADE_TUESDAY_NIGHT",
  "ENGINE_RALPH_WEDNESDAY_MORNING",
  "ENGINE_LIZ_THURSDAY_AFTERNOON",
  "ENGINE_ANTHONY_FRIDAY_NIGHT",
  "ENGINE_TODD_SATURDAY_MORNING",
  "ENGINE_GINA_SUNDAY_AFTERNOON",
  "ENGINE_ARNIE_TUESDAY_MORNING",
  "ENGINE_ALAN_WEDNESDAY_AFTERNOON",
  "ENGINE_DANA_THURSDAY_NIGHT",
  "ENGINE_CHAD_FRIDAY_MORNING",
  "ENGINE_TULLY_SUNDAY_NIGHT",
  "ENGINE_BRENT_MONDAY_MORNING",
  "ENGINE_TIFFANY_TUESDAY_AFTERNOON",
  "ENGINE_VANCE_WEDNESDAY_NIGHT",
  "ENGINE_WILTON_THURSDAY_MORNING",
  "ENGINE_PARRY_FRIDAY_AFTERNOON",
  "ENGINE_ERIN_SATURDAY_NIGHT",
}

function Apricorns.sampleKenjiBreak(random)
  return (random or math.random)(4) + 2
end

local BY_APRICORN, BY_BALL = {}, {}
for index, row in ipairs(Apricorns.BALLS) do
  row.index = index
  BY_APRICORN[row.apricorn] = row
  BY_BALL[row.ball] = row
end

-- ------------------------------------------------------------- the registry
--
-- The `apricorns` registry (src/mods/Schemas.lua), one of the Gen 2-only six:
-- Red has no Kurt and no apricorn balls, so the name is gated under Gen 1 and
-- routed to data.gen2Apricorns under Gen 2.  src/mods/Builtins.lua seeds it
-- with the seven rows above, engine-owned, keyed by the apricorn item -- what
-- the player hands over and what FindApricornsInBag walks the bag for.
--
-- The three lookups below are rebuilt from the merged table when there is one,
-- so a registered row reaches Kurt's menu (Apricorns.inBag walks BALLS in
-- table order, which is why `index` is a field and the rebuild sorts by it),
-- the ball he hands back and the apricorn test the bag uses.  With no loader
-- the module's own rows stand, which is what every headless test gets.
local function rebuildLookups(rows)
  local ordered = {}
  for _, row in pairs(rows) do
    if type(row) == "table" and row.apricorn and row.ball then
      ordered[#ordered + 1] = row
    end
  end
  table.sort(ordered, function(a, b)
    if (a.index or 0) ~= (b.index or 0) then
      return (a.index or 0) < (b.index or 0)
    end
    return tostring(a.apricorn) < tostring(b.apricorn)
  end)
  Apricorns.BALLS, BY_APRICORN, BY_BALL = ordered, {}, {}
  for _, row in ipairs(ordered) do
    BY_APRICORN[row.apricorn] = row
    BY_BALL[row.ball] = row
  end
  return #ordered
end

-- vanilla registrations, engine-owned
function Apricorns.registerInto(registry, _, owner)
  for _, row in ipairs(Apricorns.BALLS) do
    registry:register(row.apricorn, row, owner)
  end
  return #Apricorns.BALLS
end

-- the merged table, folded into the three lookups; nil restores nothing (the
-- module's rows are already standing)
function Apricorns.useRegistry(data)
  local rows = data and data.gen2Apricorns
  if type(rows) ~= "table" then return 0 end
  return rebuildLookups(rows)
end

function Apricorns.row(apricorn) return BY_APRICORN[apricorn] end
function Apricorns.isApricorn(item) return BY_APRICORN[item] ~= nil end

function Apricorns.ballFor(apricorn)
  local row = BY_APRICORN[apricorn]
  return row and row.ball or nil
end

function Apricorns.apricornFor(ball)
  local row = BY_BALL[ball]
  return row and row.apricorn or nil
end

-- ------------------------------------------------------------- the save shape
--
-- Kurt keeps NO state of his own.  Everything he reads is already in the two
-- tables the extracted script writes:
--
--   save.events        wEventFlags, the EVENT_GAVE_KURT_*_APRICORN ids above
--                      and EVENT_KURT_GAVE_YOU_LURE_BALL (53) for the free one
--   save.engineFlags   ENGINE_KURT_MAKING_BALLS (79)
--
-- and the one thing that is genuinely new:
--
--   save.dailyReset    { remaining = 1, day = <wCurDay> }
--                      wDailyResetTimer and the start day beside it
--   save.fruitTrees    { [FRUITTREE_*] = true } for a tree already picked today
--
-- so nothing below invents a parallel copy of a flag the script can also see.
--
-- save.events is the SERIALIZED BITFIELD src/world/gen2/Events.lua writes --
-- byte index -> byte value, the shape wEventFlags has in SRAM -- and not a set
-- of ids, which is why the two helpers below do the byte and bit arithmetic
-- rather than indexing it.  While the game is running the live copy is
-- world.events and the save's is only refreshed on a write, so anything that
-- has to flip one of these flags MID PLAY goes through the script's own
-- `setevent` (Kurt's does): these two are for a save file at rest.
local FLAGS_PER_BYTE = 8

local function events(save)
  if type(save) ~= "table" then return nil end
  save.events = save.events or {}
  return save.events
end

local function engineFlags(save)
  if type(save) ~= "table" then return nil end
  save.engineFlags = save.engineFlags or {}
  return save.engineFlags
end

function Apricorns.event(save, id)
  local flags = events(save)
  if not (flags and id) then return false end
  local byte = flags[math.floor(id / FLAGS_PER_BYTE)] or 0
  return math.floor(byte / 2 ^ (id % FLAGS_PER_BYTE)) % 2 == 1
end

function Apricorns.setEvent(save, id, value)
  local flags = events(save)
  if not (flags and id) then return end
  local index = math.floor(id / FLAGS_PER_BYTE)
  local mask = 2 ^ (id % FLAGS_PER_BYTE)
  local byte = flags[index] or 0
  local set = math.floor(byte / mask) % 2 == 1
  if value and not set then
    flags[index] = byte + mask
  elseif not value and set then
    flags[index] = byte - mask
  end
end

-- ------------------------------------------------------ Kurt_SelectApricorn
--
-- FindApricornsInBag walks ApricornBalls and appends every apricorn the pack
-- holds, then appends a 0 for the CANCEL row -- so the list Kurt shows is
-- always in table order and always ends in CANCEL.  Its `scf` return is the
-- "you have none" case: a count of exactly 1 means nothing but CANCEL, and the
-- script's `ifequal FALSE` treats that the same as backing out.
--
-- `inventory` is the flat item -> count map the port's bag uses.
function Apricorns.bagList(inventory)
  inventory = inventory or {}
  local list = {}
  for _, row in ipairs(Apricorns.BALLS) do
    if (inventory[row.apricorn] or 0) > 0 then
      list[#list + 1] = row.apricorn
    end
  end
  -- The CANCEL row is part of the cart's list, not a decoration the menu adds:
  -- wKurtApricornCount counts it, and the menu's last entry is item 0.
  list.cancel = #list + 1
  list.empty = #list == 0
  return list
end

-- What the SelectApricornForKurt special leaves in wScriptVar: the chosen
-- apricorn, or FALSE.  `choice` is 1-based over the list bagList returned, and
-- the CANCEL row is `list.cancel`.
function Apricorns.select(inventory, choice)
  local list = Apricorns.bagList(inventory)
  if list.empty then return nil end
  if not choice or choice >= list.cancel then return nil end
  return list[choice]
end

-- The rest of SelectApricornForKurt, which the map script does NOT do and
-- which is easy to miss because it is in the special rather than in the
-- bytecode: the chosen apricorn is tossed out of the bag, one unit, before the
-- script ever sets its event.
--
--   ld [wCurItem], a / ld a, 1 / ld [wItemQuantityChange], a
--   ld hl, wNumItems / call TossItem
function Apricorns.takeApricorn(save, apricorn)
  if not (save and BY_APRICORN[apricorn]) then return false end
  local inventory = save.inventory or {}
  save.inventory = inventory
  local have = inventory[apricorn] or 0
  if have <= 0 then return false end
  have = have - 1
  inventory[apricorn] = have > 0 and have or nil
  return true
end

-- The whole handover, as one call: take the apricorn, set that colour's event,
-- and set ENGINE_KURT_MAKING_BALLS.  The two script lines this stands in for
-- are `setevent EVENT_GAVE_KURT_<colour>_APRICORN` and
-- `setflag ENGINE_KURT_MAKING_BALLS`, in .GaveKurtApricorns.
function Apricorns.give(save, apricorn)
  local row = BY_APRICORN[apricorn]
  if not row then return false end
  if not Apricorns.takeApricorn(save, apricorn) then return false end
  Apricorns.setEvent(save, row.event, true)
  local flags = engineFlags(save)
  if flags then flags[Apricorns.ENGINE_KURT_MAKING_BALLS] = true end
  return true, row.ball
end

-- Which apricorn Kurt currently has, in the order Kurt1 tests the events.  He
-- takes exactly ONE at a time: the .AskApricorn branch is only reachable when
-- every one of the seven events is clear.
function Apricorns.pending(save)
  for _, row in ipairs(Apricorns.BALLS) do
    if Apricorns.event(save, row.event) then
      return row.apricorn, row.ball
    end
  end
  return nil
end

function Apricorns.isWorking(save)
  local flags = engineFlags(save)
  return (flags and flags[Apricorns.ENGINE_KURT_MAKING_BALLS]) == true
end

-- .GiveLevelBall and its six siblings all open with
-- `checkflag ENGINE_KURT_MAKING_BALLS / iftrue .KurtMakingBallsScript`, so the
-- ball is ready exactly when he has an apricorn and the daily flag has rolled
-- over.
function Apricorns.readyBall(save)
  if Apricorns.isWorking(save) then return nil end
  local _, ball = Apricorns.pending(save)
  return ball
end

-- `verbosegiveitem <BALL> / iffalse .NoRoomForBall / clearevent
-- EVENT_GAVE_KURT_<colour>_APRICORN`.  The clear happens only after the ball
-- actually lands in the pack, which is why a full pack leaves Kurt holding it
-- and this returns the ball WITHOUT clearing on a refusal.
function Apricorns.collect(save)
  local ball = Apricorns.readyBall(save)
  if not ball then return nil end
  local apricorn = Apricorns.apricornFor(ball)
  local row = BY_APRICORN[apricorn]
  Apricorns.setEvent(save, row.event, false)
  -- apricorn.converted, a Gen 2 invention: Gen 1 has no Kurt and no apricorn,
  -- so there is no name to share.  Raised on the handover rather than on
  -- Apricorns.give, because the apricorn only becomes a ball once the daily
  -- rollover has run and the ball has actually landed in the pack -- a full
  -- pack leaves Kurt holding it and this function is not reached at all.
  --
  --   apricorn  the APRICORN_* item that went in
  --   ball      the BALL item that came out
  --   event     the EVENT_GAVE_KURT_*_APRICORN flag just cleared
  if Runtime.wants("apricorn.converted") then
    Runtime.emit("apricorn.converted",
      { apricorn = apricorn, ball = ball, event = row.event })
  end
  return ball, apricorn
end

-- --------------------------------------------------------- the daily rollover
--
-- RestartDailyResetTimer / InitOneDayCountdown: one day, counted from today.
function Apricorns.startDailyResetTimer(save, now)
  if type(save) ~= "table" then return nil end
  local stamp = now or BugContest.now()
  save.dailyReset = { remaining = 1, day = stamp.day }
  return save.dailyReset
end

-- UpdateTimeRemaining: subtract the elapsed units from the counter, clamp at
-- zero, and set carry when it reaches zero.  A delta of -1 (the "exceeds this
-- unit's range" sentinel GetTimeElapsed_ExceedsUnitLimit returns) zeroes it
-- outright.
local function updateTimeRemaining(remaining, elapsed)
  if elapsed == -1 then return 0, true end
  local left = remaining - elapsed
  if left < 0 then left = 0 end
  return left, left == 0
end

Apricorns.updateTimeRemaining = updateTimeRemaining

-- CheckDailyResetTimer.  CheckDayDependentEventHL walks past the counter to
-- the start day, takes the days since it -- ADVANCING the stored day to today
-- as it goes, which is what makes the counter decrement by "days since the
-- last poll" rather than by "days since the timer started" -- and then
-- UpdateTimeRemaining decides whether the day is up.
--
-- When it is, wDailyFlags1 and wDailyFlags2 are cleared whole and the timer
-- restarts.  Returns true on the frames the rollover actually happened.
function Apricorns.checkDailyResetTimer(save, now)
  if type(save) ~= "table" then return false end
  if not save.dailyReset then
    Apricorns.startDailyResetTimer(save, now)
    return false
  end
  local timer = save.dailyReset
  local stamp = { day = timer.day }
  local since = BugContest.elapsedSince(stamp, now, "day")
  timer.day = stamp.day
  local remaining, expired = updateTimeRemaining(timer.remaining or 1,
    since.days)
  timer.remaining = remaining
  if not expired then return false end
  Apricorns.dailyReset(save)
  Apricorns.startDailyResetTimer(save, now)
  return true
end

-- `xor a / ld hl, wDailyFlags1 / ld [hli], a / ld [hl], a`: both bytes, every
-- bit, in one go.  Kurt's ball being finished is a SIDE EFFECT of this and not
-- a thing anyone checks for -- which is also why finishing the Bug Contest
-- (ENGINE_DAILY_BUG_CONTEST) and refilling every fruit tree
-- (ENGINE_ALL_FRUIT_TREES) happen on the same tick.
-- ../pokecrystal/constants/engine_flags.asm:25,113-114
function Apricorns.dailyReset(save)
  local flags = engineFlags(save)
  if not flags then return end
  local crystal = save.version == "crystal"
  local function clear(name)
    flags[EngineFlags.id(name)] = nil
  end
  for _, name in ipairs(Apricorns.DAILY_ENGINE_FLAGS) do
    if EngineFlags.has(name) then clear(name) end
  end
  if crystal then
    CartTimers.dailyReset(save)
    CartDayCareWild.dailyReset(save)
    clear("ENGINE_GOLDENROD_DEPT_STORE_SALE_IS_ON")
    clear("ENGINE_DUNSPARCE_SWARM")
    clear("ENGINE_YANMA_SWARM")
    for _, name in ipairs(CRYSTAL_PHONE_FLAGS) do clear(name) end
    save.crystal = save.crystal or {}
    local days = (save.crystal.kenjiBreak or 0) - 1
    save.crystal.kenjiBreak = days > 0 and days or Apricorns.sampleKenjiBreak()
  end
  -- The port keeps a couple of these under names as well as ids
  -- (src/script/gen2/Specials.lua's ActivateFishingSwarm writes
  -- save.dailyFlags), so the same wipe has to reach that table.
  local fishing = crystal and save.dailyFlags and save.dailyFlags.fishingSwarm or nil
  save.dailyFlags = fishing ~= nil and { fishingSwarm = fishing } or {}
  Buena.dailyReset(save)
end

-- ---------------------------------------------------------------- the trees
--
-- data/items/fruit_trees.asm, indexed by FRUITTREE_*.  That enum opens
-- `const_def 1`, so it is ONE based and a 1-based Lua list lines up with it
-- exactly -- GetCurTreeFruit's `dec a` before GetFruitTreeItem is the cart
-- converting the same 1-based id into a 0-based offset, not evidence of a
-- 0-based table.
Apricorns.FRUIT_TREES = {
  "BERRY",        -- 01 FRUITTREE_ROUTE_29
  "BERRY",        -- 02 FRUITTREE_ROUTE_30_1
  "BERRY",        -- 03 FRUITTREE_ROUTE_38
  "BERRY",        -- 04 FRUITTREE_ROUTE_46_1
  "PSNCUREBERRY", -- 05 FRUITTREE_ROUTE_30_2
  "PSNCUREBERRY", -- 06 FRUITTREE_ROUTE_33
  "BITTER_BERRY", -- 07 FRUITTREE_ROUTE_31
  "BITTER_BERRY", -- 08 FRUITTREE_ROUTE_43
  "PRZCUREBERRY", -- 09 FRUITTREE_VIOLET_CITY
  "PRZCUREBERRY", -- 0a FRUITTREE_ROUTE_46_2
  "MYSTERYBERRY", -- 0b FRUITTREE_ROUTE_35
  "MYSTERYBERRY", -- 0c FRUITTREE_ROUTE_45
  "ICE_BERRY",    -- 0d FRUITTREE_ROUTE_36
  "ICE_BERRY",    -- 0e FRUITTREE_ROUTE_26
  "MINT_BERRY",   -- 0f FRUITTREE_ROUTE_39
  "BURNT_BERRY",  -- 10 FRUITTREE_ROUTE_44
  "RED_APRICORN", -- 11 FRUITTREE_ROUTE_37_1
  "BLU_APRICORN", -- 12 FRUITTREE_ROUTE_37_2
  "BLK_APRICORN", -- 13 FRUITTREE_ROUTE_37_3
  "WHT_APRICORN", -- 14 FRUITTREE_AZALEA_TOWN
  "PNK_APRICORN", -- 15 FRUITTREE_ROUTE_42_1
  "GRN_APRICORN", -- 16 FRUITTREE_ROUTE_42_2
  "YLW_APRICORN", -- 17 FRUITTREE_ROUTE_42_3
  "BERRY",        -- 18 FRUITTREE_ROUTE_11
  "PSNCUREBERRY", -- 19 FRUITTREE_ROUTE_2
  "BITTER_BERRY", -- 1a FRUITTREE_ROUTE_1
  "PRZCUREBERRY", -- 1b FRUITTREE_ROUTE_8
  "ICE_BERRY",    -- 1c FRUITTREE_PEWTER_CITY_1
  "MINT_BERRY",   -- 1d FRUITTREE_PEWTER_CITY_2
  "BURNT_BERRY",  -- 1e FRUITTREE_FUCHSIA_CITY
}

Apricorns.NUM_FRUIT_TREES = #Apricorns.FRUIT_TREES

-- GetCurTreeFruit.
function Apricorns.treeFruit(tree)
  return Apricorns.FRUIT_TREES[tree]
end

local function treeFlags(save)
  if type(save) ~= "table" then return nil end
  save.fruitTrees = save.fruitTrees or {}
  return save.fruitTrees
end

-- TryResetFruitTrees, run at the TOP of FruitTreeScript, before the tree is
-- checked: if ENGINE_ALL_FRUIT_TREES is clear then every tree in the game
-- refills at once and the flag is set so it only happens once a day.  It is
-- the daily reset above that clears the flag again.
function Apricorns.tryResetFruitTrees(save)
  local flags = engineFlags(save)
  if not flags then return false end
  if flags[Apricorns.ENGINE_ALL_FRUIT_TREES] then return false end
  save.fruitTrees = {}
  flags[Apricorns.ENGINE_ALL_FRUIT_TREES] = true
  return true
end

-- CheckFruitTree's `ld b, 2 / GetFruitTreeFlag` is a CHECK_FLAG, and the
-- wScriptVar it leaves is TRUE for a tree already picked -- so the script's
-- `iffalse .fruit` reads "not picked yet, there is fruit here".
function Apricorns.treePicked(save, tree)
  local flags = treeFlags(save)
  return (flags and flags[tree]) == true
end

-- PickedFruitTree's `ld b, 1` is a SET_FLAG.
function Apricorns.pickTree(save, tree)
  local flags = treeFlags(save)
  if not (flags and Apricorns.FRUIT_TREES[tree]) then return nil end
  if flags[tree] then return nil end
  flags[tree] = true
  return Apricorns.FRUIT_TREES[tree]
end

-- ------------------------------------------------------------- the module map
--
-- Where each half is called from, now that all four have a call site:
--
--   SelectApricornForKurt   src/script/gen2/Specials.lua's handler:
--                           Apricorns.bagList(save.inventory) builds
--                           FindApricornsInBag's list, Apricorns.select(...)
--                           reads the row the menu came back with, and
--                           Apricorns.takeApricorn is the special's own
--                           TossItem.  It stops there ON PURPOSE: the setevent
--                           and the setflag after it belong to
--                           maps/KurtsHouse.asm, which the extractor has, so
--                           doing them here as well would set them twice.
--                           Apricorns.give is the same pair as one call for a
--                           caller that has no script behind it.
--   Kurt1's .GiveXBall      the extracted script's own `checkflag
--                           ENGINE_KURT_MAKING_BALLS` / `verbosegiveitem` /
--                           `clearevent`; Apricorns.readyBall and
--                           Apricorns.collect are the same rule for a reader
--                           holding nothing but a save file.
--   FruitTreeScript         the VM's `fruittree` branch, through World's
--                           fruitTreeItem / fruitTreeReset / fruitTreePicked /
--                           fruitTreePick hooks: Apricorns.treeFruit,
--                           Apricorns.tryResetFruitTrees, Apricorns.treePicked
--                           and Apricorns.pickTree in that order.
--   CheckTimeEvents         World:checkTimeEvents, once a frame off the
--                           player-event chain: Apricorns.checkDailyResetTimer

return Apricorns
