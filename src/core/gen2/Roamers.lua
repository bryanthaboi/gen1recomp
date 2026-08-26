-- The two pieces of Gen 2 world state that override where a wild mon comes
-- from: the roaming legendaries, and swarms.
--
-- Both live in one module because they are the same KIND of thing -- a
-- persistent record that sits in front of a map's own encounter table -- and
-- because ChooseWildEncounter (engine/overworld/wildmons.asm) consults them in
-- one breath: _GrassWildmonLookup checks the swarm table before the Johto one,
-- and ChooseWildEncounter checks the roamers before it rolls a slot at all.
--
--   Roamers   engine/overworld/wildmons.asm  InitRoamMons, CheckEncounterRoamMon,
--             UpdateRoamMons, JumpRoamMons, _BackUpMapIndices
--             engine/battle/core.asm         BattleEnd_HandleRoamMons
--             data/wild/roammon_maps.asm     RoamMaps
--   Swarms    engine/events/specials.asm     StoreSwarmMapIndices, SetSwarmFlag,
--             CheckSwarmFlag, ActivateFishingSwarm
--             engine/overworld/wildmons.asm  _SwarmWildmonCheck
--             data/wild/swarm_grass.asm, swarm_water.asm
--
-- Everything here is save state.  A roamer that forgets where it is or how
-- hurt it is between two encounters is not a roamer, it is a random spawn.
--
-- MAP IDENTITY: the cart carries a roamer's position as a (group, number)
-- pair; the port carries map ids ("ROUTE_42"), which are the same fact with
-- the indirection removed, so every comparison below that reads as `cp d /
-- cp e` in the asm is one string compare here.  GROUP_N_A / MAP_N_A -- the
-- pair InitRoamMons never writes and BattleEnd_HandleRoamMons writes when a
-- beast is caught or beaten -- is nil.

local GameVersion = require("src.core.GameVersion")
local Mon = require("src.battle.gen2.Mon")
local Runtime = require("src.mods.Runtime")

local Roamers = {}

-- roamer.moved, a Gen 2 invention: Gen 1 has no roaming legendary, so there is
-- no name to share.  One event per beast that actually changed route, raised
-- from both routines that move them -- UpdateRoamMons (the one-route walk a
-- map connection or a door triggers) and JumpRoamMons (the scatter a fly or a
-- teleport triggers) -- so a tracker mod sees every hop.
--
--   index    the roamer slot, 1 Raikou / 2 Entei / 3 Suicune (Gold only)
--   slot     that roamer record, already carrying the new map
--   species  the beast's species id
--   from     the map id it left
--   to       the map id it is on now
--   reason   "connection" for UpdateRoamMons, "jump" for JumpRoamMons
--
-- A beast whose roll left it on the map it was already on raises nothing:
-- .Update's `jr z` re-rolls rather than standing still, so "moved" means moved.
local function emitMoved(index, slot, from, reason)
  if from == slot.map then return end
  if not Runtime.wants("roamer.moved") then return end
  Runtime.emit("roamer.moved", {
    index = index, slot = slot, species = slot.species,
    from = from, to = slot.map, reason = reason,
  })
end

--------------------------------------------------------------------------
-- The beasts
--------------------------------------------------------------------------

-- InitRoamMons, written out.  The species order IS the slot order -- Raikou 1,
-- Entei 2, Suicune 3 -- because CheckEncounterRoamMon indexes the structs by a
-- random 0..2 and GetRoamMonHP walks them by species, so renumbering them
-- would send Suicune's damage to Raikou's byte.
Roamers.SPECIES = {
  { species = "RAIKOU", level = 40, map = "ROUTE_42" },
  { species = "ENTEI", level = 40, map = "ROUTE_37" },
  { species = "SUICUNE", level = 40, map = "ROUTE_38" },
}
Roamers.LEVEL = 40

-- pokecrystal/engine/overworld/wildmons.asm:493 seeds Raikou and Entei only,
-- so the roster is read out of the cache when the cache carries one.
local function startMapFor(species)
  for _, row in ipairs(Roamers.SPECIES) do
    if row.species == species then return row.map end
  end
  return nil
end

function Roamers.roster(encounters)
  local extracted = encounters and encounters.roamMons
  if type(extracted) ~= "table" or #extracted == 0 then return Roamers.SPECIES end
  local rows = {}
  for _, row in ipairs(extracted) do
    rows[#rows + 1] = {
      species = row.species,
      level = row.level or Roamers.LEVEL,
      map = row.map or startMapFor(row.species),
    }
  end
  return rows
end

-- data/wild/roammon_maps.asm, entry for entry and in order.  The order matters
-- twice over: `.Update` picks a connection by a two-bit index into the list, so
-- shuffling one row changes which route a beast walks to, and JumpRoamMon picks
-- an ENTRY by a four-bit index, so shuffling the rows changes where a
-- teleport drops it.
--
-- Route 40 and Route 41 are deliberately absent (they are water routes, and
-- CheckEncounterRoamMon refuses to fire while the player is surfing anyway).
Roamers.NUM_MAPS = 16
Roamers.MAPS = {
  { map = "ROUTE_29", to = { "ROUTE_30", "ROUTE_46" } },
  { map = "ROUTE_30", to = { "ROUTE_29", "ROUTE_31" } },
  { map = "ROUTE_31", to = { "ROUTE_30", "ROUTE_32", "ROUTE_36" } },
  { map = "ROUTE_32", to = { "ROUTE_36", "ROUTE_31", "ROUTE_33" } },
  { map = "ROUTE_33", to = { "ROUTE_32", "ROUTE_34" } },
  { map = "ROUTE_34", to = { "ROUTE_33", "ROUTE_35" } },
  { map = "ROUTE_35", to = { "ROUTE_34", "ROUTE_36" } },
  { map = "ROUTE_36", to = { "ROUTE_35", "ROUTE_31", "ROUTE_32", "ROUTE_37" } },
  { map = "ROUTE_37", to = { "ROUTE_36", "ROUTE_38", "ROUTE_42" } },
  { map = "ROUTE_38", to = { "ROUTE_37", "ROUTE_39", "ROUTE_42" } },
  { map = "ROUTE_39", to = { "ROUTE_38" } },
  { map = "ROUTE_42", to = { "ROUTE_43", "ROUTE_44", "ROUTE_37", "ROUTE_38" } },
  { map = "ROUTE_43", to = { "ROUTE_42", "ROUTE_44" } },
  { map = "ROUTE_44", to = { "ROUTE_42", "ROUTE_43", "ROUTE_45" } },
  { map = "ROUTE_45", to = { "ROUTE_44", "ROUTE_46" } },
  { map = "ROUTE_46", to = { "ROUTE_45", "ROUTE_29" } },
}

-- RomExtractorGen2 emits `encounters.roamMaps` in exactly the shape above, so
-- the table above is the fallback for a cache built before it did (and for a
-- caller with no cache at all, which every unit test here is).
function Roamers.mapTable(encounters)
  local extracted = encounters and encounters.roamMaps
  if type(extracted) == "table" and #extracted > 0 then return extracted end
  return Roamers.MAPS
end

-- `.Update`'s search: walk RoamMaps for the entry whose START map is `mapId`.
-- The asm ends on `cp -1 / ret z`, which leaves b and c untouched -- a roamer
-- standing somewhere RoamMaps does not list simply does not move.
function Roamers.entryFor(mapId, encounters)
  if not mapId then return nil end
  for _, row in ipairs(Roamers.mapTable(encounters)) do
    if row.map == mapId then return row end
  end
  return nil
end

-- 0 .. n-1, the same convention src/battle/gen2/Encounter.lua and the battle
-- engine use for an injected random, so one seeded generator drives them all.
local function rand(random, n)
  if random then return random(n) end
  if love and love.math and love.math.random then
    return love.math.random(n) - 1
  end
  return math.random(n) - 1
end

-- JumpRoamMon: a completely random RoamMaps entry, re-rolled while it lands on
-- the map the PLAYER is standing on.  (The asm's `maskbits NUM_ROAMMON_MAPS /
-- cp NUM_ROAMMON_MAPS / jr nc` retry is dead code -- there are exactly 16
-- entries and the mask is four bits -- so it is not modelled.)
--
-- The retry is unbounded on the cart; `tries` caps it here so a caller that
-- hands in a degenerate random (a stub that always returns 0) cannot hang the
-- overworld.  Falling out of the loop leaves the beast where it was, which is
-- the same outcome `.Update`'s not-found path has.
function Roamers.jumpOne(playerMapId, random, encounters)
  local table_ = Roamers.mapTable(encounters)
  local count = #table_
  if count == 0 then return nil end
  for _ = 1, 32 do
    local row = table_[rand(random, count) + 1]
    if row and row.map ~= playerMapId then return row.map end
  end
  return nil
end

-- `.Update`: one roamer's move on a map change.
--
-- The single random byte does double duty, which is the part a paraphrase
-- always loses:
--
--   and %00011111   -> zero (1 in 32) means "jump to a completely random map"
--   and %11         -> otherwise the LOW TWO BITS of that same masked value are
--                      the connection index
--
-- so the choice of connection is not independent of the choice to jump.  An
-- index at or past the entry's connection count re-rolls, and so does a
-- connection that equals wRoamMons_LastMapGroup/Number -- the map the player
-- was on BEFORE the one they are on now, which is what keeps a beast from
-- following the player back and forth down one pair of routes.
function Roamers.moveOne(mapId, lastMapId, playerMapId, random, encounters)
  local entry = Roamers.entryFor(mapId, encounters)
  if not entry then return mapId end
  local list = entry.to or {}
  for _ = 1, 64 do
    local value = rand(random, 256) % 32
    if value == 0 then
      return Roamers.jumpOne(playerMapId, random, encounters) or mapId
    end
    local index = value % 4
    if index < #list then
      local candidate = list[index + 1]
      if candidate ~= lastMapId then return candidate end
    end
  end
  return mapId
end

--------------------------------------------------------------------------
-- The save record
--------------------------------------------------------------------------
--
-- save.roamers is a slot array in the roster order above, written first by the
-- InitRoamMons special (src/script/gen2/Specials.lua) when the Burned Tower
-- basement script fires.  Each slot:
--
--   species  nil once the beast has been caught or beaten (GetRoamMonSpecies
--            writes 0 there, which is what stops it ever appearing again)
--   level    40, and it never changes: the roam struct has no experience
--   map      the map id it occupies, nil for GROUP_N_A / MAP_N_A
--   hp       its remaining HP, 0 meaning "not yet rolled".  ONE byte on the
--            cart, because Raikou and Entei have under 256 HP at level 40 --
--            the port keeps the same ceiling rather than quietly widening it
--   dvs      rolled at the FIRST encounter and kept, so a beast you chase all
--            game is the same individual
--
-- There is deliberately no status field: the seven-byte roam_struct
-- (macros/ram.asm) has no room for one, and LoadEnemyMon zeroes
-- wEnemyMonStatus for every wild mon, so a beast you paralyse walks it off the
-- moment it flees.  Storing status would be a buff the cart does not grant.
Roamers.MAX_STORED_HP = 255

function Roamers.list(save)
  return (type(save) == "table" and save.roamers) or nil
end

function Roamers.slot(save, index)
  local list = Roamers.list(save)
  return list and list[index] or nil
end

-- InitRoamMons.  Safe to call twice: the Burned Tower script is behind a scene
-- flag, but a re-init would hand the player fresh beasts, so this only writes
-- when there is nothing there.
function Roamers.init(save, opts)
  if type(save) ~= "table" then return nil end
  if save.roamers and not (opts and opts.force) then return save.roamers end
  local encounters = opts and (opts.encounters
    or (opts.data and opts.data.gen2Encounters))
  local list = {}
  for _, row in ipairs(Roamers.roster(encounters)) do
    list[#list + 1] = {
      species = row.species,
      level = row.level,
      map = row.map,
      -- `xor a ; generate new stats` -- the asm comments its own zero.
      hp = 0,
    }
  end
  save.roamers = list
  return list
end

-- Is this beast still out there?  A caught or defeated one keeps its slot but
-- has neither a species nor a map, and every path below refuses it.
function Roamers.active(slot)
  return type(slot) == "table" and slot.species ~= nil and slot.map ~= nil
end

-- _BackUpMapIndices: Cur shifts into Last, then the player's current map
-- becomes Cur.  It runs at the END of both UpdateRoamMons and JumpRoamMons, so
-- the "last map" a move avoids is the one the player left BEFORE the one they
-- are standing on.
function Roamers.backUpMapIndices(save, playerMapId)
  if type(save) ~= "table" then return end
  local marks = save.roamerMaps or {}
  marks.last = marks.current
  marks.current = playerMapId
  save.roamerMaps = marks
end

function Roamers.lastMap(save)
  return (type(save) == "table" and save.roamerMaps and save.roamerMaps.last)
    or nil
end

-- UpdateRoamMons: each live beast moves along a connection, then the map
-- indices are backed up.  Runs on a map CONNECTION and on a door / fall warp
-- (data/maps/setup_scripts.asm MapSetupScript_Connection and
-- MapSetupScript_Door), not on a plain warp.
function Roamers.update(save, playerMapId, random, encounters)
  local list = Roamers.list(save)
  if not list then return false end
  local lastMapId = Roamers.lastMap(save)
  for index, slot in ipairs(list) do
    if Roamers.active(slot) then
      local from = slot.map
      slot.map = Roamers.moveOne(from, lastMapId, playerMapId, random,
        encounters)
      emitMoved(index, slot, from, "connection")
    end
  end
  Roamers.backUpMapIndices(save, playerMapId)
  return true
end

-- JumpRoamMons: every live beast teleports to a random roam map.  This is the
-- Teleport setup script (MapSetupScript_Teleport), which is why flying or
-- teleporting across Johto scatters them instead of nudging them one route.
function Roamers.jumpAll(save, playerMapId, random, encounters)
  local list = Roamers.list(save)
  if not list then return false end
  for index, slot in ipairs(list) do
    if Roamers.active(slot) then
      local from = slot.map
      slot.map = Roamers.jumpOne(playerMapId, random, encounters) or slot.map
      emitMoved(index, slot, from, "jump")
    end
  end
  Roamers.backUpMapIndices(save, playerMapId)
  return true
end

--------------------------------------------------------------------------
-- Meeting one
--------------------------------------------------------------------------

-- CheckEncounterRoamMon, which ChooseWildEncounter calls BEFORE it rolls a
-- slot -- so a roamer replaces the map's own encounter rather than adding to
-- it, and only on a map that has an encounter table at all.
--
-- One random byte, three gates:
--   cp 100 / jr nc   -> 100 of 256 get past
--   and %11 / jr z   -> three quarters of those get past
--   dec a            -> 1, 2 or 3 becomes slot 0, 1 or 2
-- which is 75/256, about 29%, split evenly between the three beasts.  A slot
-- whose map is not the player's map fails outright: there is NO re-roll onto
-- another beast, so two beasts sharing your route still only get one roll
-- each encounter.
--
-- Surfing refuses before anything else (`call CheckOnWater / jr z`), which is
-- what keeps Suicune out of the water on Route 42.
function Roamers.checkEncounter(save, mapId, onWater, random)
  if onWater then return nil end
  local list = Roamers.list(save)
  if not list then return nil end
  local value = rand(random, 256)
  if value >= 100 then return nil end
  local index = value % 4
  if index == 0 then return nil end
  local slot = list[index]
  if not Roamers.active(slot) then return nil end
  if slot.map ~= mapId then return nil end
  local hit = { index = index, slot = slot, species = slot.species,
    level = slot.level }
  -- roamer.encountered, a Gen 2 invention, raised on the roll that REPLACES
  -- the map's own encounter -- CheckEncounterRoamMon runs ahead of
  -- ChooseWildEncounter, so by the time the shared encounter.species hook sees
  -- anything the beast has already won the slot.  This is the only notice a
  -- mod gets that the wild mon about to appear is the roamer.
  --
  --   index / slot / species / level  the same four fields the caller takes
  --   mapId    the map the player is standing on, which is also the beast's
  --
  -- Observation only: the shared encounter.species hook still runs downstream
  -- and is where a mod changes what appears.
  if Runtime.wants("roamer.encountered") then
    Runtime.emit("roamer.encountered", {
      index = index, slot = slot, species = slot.species,
      level = slot.level, mapId = mapId,
    })
  end
  return hit
end

-- Build the enemy for a roaming battle, out of the ONE party-member builder
-- (src/battle/gen2/Mon.lua) so the beast arrives with a real Gen 2 moveset.
--
-- LoadEnemyMon's two roam branches, in the order it runs them:
--   * DVs: `and a` on the stored HP decides.  Zero means the struct has never
--     been used, so fresh DVs are rolled and kept; anything else reuses them.
--   * HP: zero takes .InitRoamHP, which writes the mon's FULL HP back into the
--     struct.  So the first encounter both rolls and banks it.
function Roamers.beginBattle(save, index, data)
  local slot = Roamers.slot(save, index)
  if not Roamers.active(slot) then return nil end
  local fresh = (slot.hp or 0) == 0
  local mon = Mon.new(data, slot.species, slot.level or Roamers.LEVEL, {
    dvs = (not fresh) and slot.dvs or nil,
  })
  if not mon then return nil end
  slot.dvs = mon.dvs
  if fresh then
    -- .InitRoamHP: the struct takes the mon's max HP now, not at the end of
    -- the battle.
    slot.hp = math.min(Roamers.MAX_STORED_HP, mon.maxHp or 0)
  else
    mon.hp = math.min(slot.hp, mon.maxHp or slot.hp)
  end
  return mon, slot
end

-- BattleEnd_HandleRoamMons.
--
-- `outcome` is the port's battle outcome; the cart reads the low nibble of
-- wBattleResult, where WIN is 0 and both a wild flee and a player run write
-- DRAW (WildFled_EnemyFled_LinkBattleCanceled, and TryToRunAwayFromBattle's
-- .can_escape).  So "caught" and "win" clear the beast for good, and
-- everything else banks its HP and moves it.
--
-- The `.not_roaming` tail is the other half of this routine and belongs to
-- ordinary wild battles: a 1-in-16 roll moves the beasts anyway, which is why
-- they drift while you grind and not only while you walk.
function Roamers.endBattle(save, index, outcome, hp, playerMapId, random,
    encounters)
  local slot = Roamers.slot(save, index)
  if not Roamers.active(slot) then return false end
  if outcome == "win" or outcome == "caught" then
    slot.species = nil
    slot.map = nil
    slot.hp = 0
    return true
  end
  slot.hp = math.max(0, math.min(Roamers.MAX_STORED_HP, hp or 0))
  Roamers.update(save, playerMapId, random, encounters)
  return true
end

-- BattleEnd_HandleRoamMons `.not_roaming`: after ANY other wild battle,
-- `call BattleRandom / and $f / ret nz` gives one chance in sixteen that the
-- beasts move.
function Roamers.afterWildBattle(save, playerMapId, random, encounters)
  if not Roamers.list(save) then return false end
  if rand(random, 256) % 16 ~= 0 then return false end
  return Roamers.update(save, playerMapId, random, encounters)
end

-- data/wild/flee_mons.asm.  TryEnemyFlee walks AlwaysFleeMons first and takes
-- the carry straight to `.Flee`, which is why a beast never gets a second turn
-- -- the roaming battle is one attack long unless it is trapped.  The other
-- two lists are the same routine's 50% and 10% gates and live here so the
-- battle engine has one place to read them from.
-- pokegold/data/wild/flee_mons.asm:34 lists Suicune; pokecrystal's:34 ends the
-- list at Entei, which is what makes maps/TinTower1F.asm:119 catchable.
Roamers.ALWAYS_FLEE_BY_ENGINE = {
  gs = { RAIKOU = true, ENTEI = true, SUICUNE = true },
  crystal = { RAIKOU = true, ENTEI = true },
}

function Roamers.alwaysFleeMons(versionId)
  return Roamers.ALWAYS_FLEE_BY_ENGINE[GameVersion.engine(versionId)]
    or Roamers.ALWAYS_FLEE_BY_ENGINE.gs
end

-- src/battle/gen2/Battle.lua:4070 reads AlwaysFleeMons by species name.
Roamers.ALWAYS_FLEE = setmetatable({}, {
  __index = function(_, species) return Roamers.alwaysFleeMons()[species] end,
})

Roamers.OFTEN_FLEE = {
  CUBONE = true, ARTICUNO = true, ZAPDOS = true, MOLTRES = true,
  QUAGSIRE = true, DELIBIRD = true, PHANPY = true, TEDDIURSA = true,
}
Roamers.SOMETIMES_FLEE = {
  MAGNEMITE = true, GRIMER = true, TANGELA = true, MR__MIME = true,
  EEVEE = true, PORYGON = true, DRATINI = true, DRAGONAIR = true,
  TOGETIC = true, UMBREON = true, UNOWN = true, SNUBBULL = true,
  HERACROSS = true,
}

--------------------------------------------------------------------------
-- Swarms
--------------------------------------------------------------------------

local Swarm = {}
Roamers.Swarm = Swarm

-- The state, on the save:
--   save.swarmMaps            the stored map pairs, keyed by swarm kind
--   save.swarmMap             the Gold single pair, kept as the legacy alias
--   save.dailyFlags.swarm     DAILYFLAGS1_SWARM_F
--   save.dailyFlags.fishingSwarm  wFishingSwarmFlag (FISHSWARM_* 0/1/2)
--   save.dailyResetDay        the day wDailyResetTimer was last restarted
--
-- src/world/gen2/World.lua:setSwarm and the ActivateFishingSwarm special
-- already write the flags and the alias; this module is where they are READ
-- and where they expire.

-- constants/script_constants.asm, ActivateFishingSwarm setval arguments.
Swarm.FISH_NONE = 0
Swarm.FISH_QWILFISH = 1
Swarm.FISH_REMORAID = 2

-- pokecrystal/constants/script_constants.asm:256-257 -- the kind byte Crystal
-- puts in front of a `swarm` map, choosing between its two stored pairs.
Swarm.KIND_ORDER = { "DUNSPARCE", "YANMA" }
Swarm.KINDS = { [0] = "DUNSPARCE", [1] = "YANMA" }
Swarm.DEFAULT_KIND = "DUNSPARCE"

local KIND_NAMES = { DUNSPARCE = true, YANMA = true }

local function kindName(kind)
  if type(kind) == "number" then return Swarm.KINDS[kind] or Swarm.DEFAULT_KIND end
  if KIND_NAMES[kind] then return kind end
  return Swarm.DEFAULT_KIND
end

-- pokegold/engine/events/specials.asm:288-293 has the one pair, so a Gold save
-- (and every save written before this record was keyed) folds onto that key.
local function goldShape(maps)
  return maps.YANMA == nil
end

function Swarm.maps(save)
  if type(save) ~= "table" then return nil end
  local maps = save.swarmMaps
  if type(maps) ~= "table" then
    maps = {}
    save.swarmMaps = maps
  end
  if save.swarmMap ~= nil and goldShape(maps) then
    maps[Swarm.DEFAULT_KIND] = save.swarmMap
  end
  return maps
end

local function anyMap(save)
  if type(save) ~= "table" then return false end
  if save.swarmMap ~= nil then return true end
  local maps = save.swarmMaps
  if type(maps) ~= "table" then return false end
  for _, name in ipairs(Swarm.KIND_ORDER) do
    if maps[name] ~= nil then return true end
  end
  return false
end

-- StoreSwarmMapIndices, which FALLS THROUGH into SetSwarmFlag: one command
-- writes the map pair AND the daily flag.  A port that stored only the map
-- would leave the Dunsparce call live for the rest of the game, because
-- CheckSwarmFlag answers off the flag and clears the pair itself.
--
-- pokecrystal/engine/events/specials.asm:290-306 picks the pair off c instead.
function Swarm.set(save, mapId, kind)
  if type(save) ~= "table" then return false end
  save.dailyFlags = save.dailyFlags or {}
  save.dailyFlags.swarm = true
  local name = kindName(kind)
  local maps = Swarm.maps(save)
  maps[name] = mapId
  if name == Swarm.DEFAULT_KIND then save.swarmMap = mapId end
  return true
end

-- ActivateFishingSwarm: wScriptVar into wFishingSwarmFlag, then the same
-- fallthrough into SetSwarmFlag -- note it does NOT touch the map pair, so a
-- fishing swarm rides whatever map a grass swarm left behind.
function Swarm.setFishing(save, kind)
  if type(save) ~= "table" then return false end
  save.dailyFlags = save.dailyFlags or {}
  save.dailyFlags.fishingSwarm = kind or Swarm.FISH_NONE
  save.dailyFlags.swarm = true
  return true
end

function Swarm.active(save)
  return type(save) == "table" and save.dailyFlags ~= nil
    and save.dailyFlags.swarm == true
end

function Swarm.mapId(save, kind)
  if not Swarm.active(save) then return nil end
  local maps = Swarm.maps(save)
  return maps and maps[kindName(kind)] or nil
end

-- pokecrystal/engine/overworld/wildmons.asm:414-451 tests Dunsparce first and
-- falls through to Yanma, so a map both are on answers Dunsparce.
function Swarm.onMap(save, mapId)
  if mapId == nil or not Swarm.active(save) then return nil end
  local maps = Swarm.maps(save)
  if not maps then return nil end
  for _, name in ipairs(Swarm.KIND_ORDER) do
    if maps[name] == mapId then return name end
  end
  return nil
end

function Swarm.fishing(save)
  if not Swarm.active(save) then return Swarm.FISH_NONE end
  return (save.dailyFlags and save.dailyFlags.fishingSwarm) or Swarm.FISH_NONE
end

-- CheckSwarmFlag.  Returns the value it leaves in wScriptVar: 0 while the flag
-- is up, 1 once it is not -- and on that 1 it clears the fishing flag and the
-- map pair, which is the ONLY thing that ever ends a swarm.  Note the polarity:
-- an `iffalse` after this special means "the swarm is still on".
function Swarm.check(save)
  if type(save) ~= "table" then return 1 end
  if Swarm.active(save) then return 0 end
  if save.dailyFlags then save.dailyFlags.fishingSwarm = nil end
  -- pokecrystal/engine/overworld/time.asm:103-112 zeroes wSwarmFlags whole,
  -- which strands both of Crystal's pairs on the one daily tick.
  local maps = save.swarmMaps
  if type(maps) == "table" then
    for _, name in ipairs(Swarm.KIND_ORDER) do maps[name] = nil end
  end
  save.swarmMap = nil
  return 1
end

-- CheckDailyResetTimer (engine/overworld/time.asm): a one-day countdown that,
-- when it runs out, zeroes wDailyFlags1 AND wDailyFlags2 and restarts itself.
-- `day` is a day number that only has to be monotonic and comparable -- the
-- port's save carries os.date("%j") in save.rtc.day.
function Swarm.checkDailyReset(save, day)
  if type(save) ~= "table" or not day then return false end
  if save.dailyResetDay == nil then
    save.dailyResetDay = day
    return false
  end
  if save.dailyResetDay == day then return false end
  save.dailyFlags = {}
  save.dailyResetDay = day
  return true
end

-- CheckTimeEvents' `.do_daily` block, in its order: the reset timer first, then
-- CheckSwarmFlag -- which is precisely why a swarm dies a day after it was set
-- rather than needing its own timer.  Returns true when the swarm ended on
-- this call.
function Swarm.timeEvents(save, day)
  local hadMap = anyMap(save)
  local reset = Swarm.checkDailyReset(save, day)
  Swarm.check(save)
  return reset and hadMap and not anyMap(save)
end

-- _SwarmWildmonCheck: the swarm table is searched BEFORE the Johto/Kanto one,
-- and only when the player is standing on the swarm's own map.  A swarm map
-- that is not in the swarm table falls through to the normal lookup
-- (`call LookUpWildmonsForMapDE / jr nc, .noSwarm`), which is what keeps a
-- fishing swarm from blanking the grass on Route 32.
--
-- The reader below looks for `encounters.swarmGrass` and
-- `encounters.swarmWater`, keyed by map id in exactly the shape
-- `encounters.grass` / `encounters.water` already use -- which is what
-- RomExtractorGen2 writes, since the cart's swarm tables ARE grass and water
-- records.  A cache built before it did simply has no swarm rows and every
-- lookup here falls through to the map's own list.
function Swarm.entry(save, encounters, mapId, kind)
  if not encounters then return nil end
  if not Swarm.onMap(save, mapId) then return nil end
  local table_ = (kind == "water") and encounters.swarmWater
    or encounters.swarmGrass
  return table_ and table_[mapId] or nil
end

-- An `encounters` view with the swarm's rows in front of the map's own, for a
-- caller that wants to keep using src/battle/gen2/Encounter.lua unchanged.
-- Returns the ORIGINAL table when no swarm applies, so the common step pays
-- nothing.
function Swarm.tables(save, encounters, mapId)
  if not encounters then return encounters end
  local grass = Swarm.entry(save, encounters, mapId, "grass")
  local water = Swarm.entry(save, encounters, mapId, "water")
  if not (grass or water) then return encounters end
  local view = {}
  for key, value in pairs(encounters) do view[key] = value end
  if grass then
    local rows = {}
    for key, value in pairs(encounters.grass or {}) do rows[key] = value end
    rows[mapId] = grass
    view.grass = rows
  end
  if water then
    local rows = {}
    for key, value in pairs(encounters.water or {}) do rows[key] = value end
    rows[mapId] = water
    view.water = rows
  end
  return view
end

return Roamers
