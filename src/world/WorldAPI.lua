-- mod.world: the supported way for mod code to act on the running
-- overworld.  Every method resolves the live OverworldState by scanning
-- the state stack for the isOverworld marker and returns nil, "no
-- overworld" when none is up -- called from the title screen this is a
-- quiet no-op, never a crash.  Reaching into OverworldState internals
-- stays unsupported; anything a mod legitimately needs belongs here.

local Collision = require("src.world.Collision")
local Logger = require("src.core.Logger")
local FieldDefaults = require("src.world.FieldDefaults")
local Map = require("src.world.Map")
local MapLoader = require("src.world.MapLoader")
local MapOverview = require("src.world.MapOverview")
local Party = require("src.pokemon.Party")
local Runtime = require("src.mods.Runtime")

local WorldAPI = {}
WorldAPI.__index = WorldAPI

local NO_OVERWORLD = "no overworld"
local DIG_TILESETS = { FOREST = true, CEMETERY = true, CAVERN = true,
                       FACILITY = true, INTERIOR = true }
local RODS = { "OLD_ROD", "GOOD_ROD", "SUPER_ROD" }

local function acceptsMenuInput(game, ow)
  local stack = game and game.stack
  local runner = ow and ow.runner
  return ow and stack and stack.top and stack:top() == ow
    and not ow.transitioning and not ow.flyAnim and not ow.teleportOut
    and not ow.engaging and not ow.emote and not ow.pikaHop and not ow.healAnim
    and not (ow.player and (ow.player.moving or ow.player.inputLocked))
    and not (runner and runner.isRunning and runner:isRunning())
    and #(ow.scriptMoves or {}) == 0
end

local function validPartySlot(party, slot)
  return type(slot) == "number" and slot == math.floor(slot)
    and party[slot] ~= nil
end

local function outside(game, ow)
  return Map.isOutside(ow.map.def,
    FieldDefaults.field(game.data, "outsideTilesets"))
end

local function knows(mon, moveId)
  for _, move in ipairs(mon.moves or {}) do
    if move.id == moveId then return true end
  end
  return false
end

local function monInfo(game, mon, slot)
  local def = game.data.pokemon[mon.species] or {}
  return { slot = slot, species = mon.species,
    name = mon.nickname or def.name or mon.species, level = mon.level,
    hp = mon.hp, maxHp = mon.stats and mon.stats.hp or mon.hp }
end

local function softboiledSources(game)
  local party, sources = game.save.party or {}, {}
  for sourceSlot, source in ipairs(party) do
    local heal = source.stats and math.floor(source.stats.hp / 5) or 0
    if knows(source, "SOFTBOILED") and source.hp > heal then
      local info = monInfo(game, source, sourceSlot)
      info.targets = {}
      for targetSlot, target in ipairs(party) do
        if target ~= source and target.hp > 0 and target.stats
            and target.hp < target.stats.hp then
          info.targets[#info.targets + 1] = monInfo(game, target, targetSlot)
        end
      end
      if #info.targets > 0 then sources[#sources + 1] = info end
    end
  end
  return sources
end

local function flyDestinationAvailable(game, mapId)
  local field, save = game.data.field or {}, game.save
  for _, id in ipairs(field.flyOrder or {}) do
    if id == mapId then
      local def = game.data.maps and game.data.maps[id]
      return not not (save.visited and save.visited[id]
        and field.flyWarps and field.flyWarps[id]
        and def and Map.isFlyTown(def))
    end
  end
  return false
end

function WorldAPI.new(game, modId)
  return setmetatable({ game = game, modId = modId }, WorldAPI)
end

-- the live overworld, or nil.  Game.overworld is the fast path; the stack
-- scan is the authority, so a state pushed over the world (a battle, a
-- menu) still resolves to the world underneath it.
function WorldAPI:overworld()
  local game = self.game
  local stack = game and game.stack
  local states = stack and stack.states
  if states then
    for i = #states, 1, -1 do
      if states[i].isOverworld then return states[i] end
    end
  end
  local ow = game and game.overworld
  if ow and ow.isOverworld and ow.map then return ow end
  return nil
end

function WorldAPI:current()
  local ow = self:overworld()
  if not ow or not ow.map then return nil, NO_OVERWORLD end
  local p = ow.player
  return { mapId = ow.map.id, x = p and p.cellX, y = p and p.cellY,
           facing = p and p.facing }
end

local function validBlockCoordinate(value)
  return type(value) == "number" and value == value
    and value ~= math.huge and value ~= -math.huge
    and value == math.floor(value)
end

-- Read one block from the active Gen 1 map without exposing the mutable block
-- array.  Requiring the expected map id makes a stale signature fail closed
-- if a warp or reload moved the player before the caller completed its check.
-- Block coordinates are zero-based, matching replaceBlock.
function WorldAPI:activeBlockAt(mapId, bx, by)
  local ow = self:overworld()
  if not ow or not ow.map then return nil, NO_OVERWORLD end
  local map = ow.map
  if map.id ~= mapId then return nil, "map is not active" end
  if not validBlockCoordinate(bx) or not validBlockCoordinate(by) then
    return nil, "invalid block coordinates"
  end
  local def = map.def
  if not def or not validBlockCoordinate(def.width) or def.width <= 0
      or not validBlockCoordinate(def.height) or def.height <= 0 then
    return nil, "block unavailable"
  end
  if bx < 0 or by < 0 or bx >= def.width or by >= def.height then
    return nil, "block coordinates out of bounds"
  end
  if type(def.blocks) ~= "table" or type(map.blockAt) ~= "function" then
    return nil, "block unavailable"
  end
  local stored = def.blocks[by * def.width + bx + 1]
  if not validBlockCoordinate(stored) or stored < 0 then
    return nil, "block unavailable"
  end
  local ok, blockId = pcall(map.blockAt, map, bx, by)
  if not ok or not validBlockCoordinate(blockId) or blockId < 0
      or blockId ~= stored then
    return nil, "block unavailable"
  end
  return blockId
end

-- Companion UIs may offer party ordering while the player is in free roam.
-- The same guard that makes opening a menu safe keeps scripts, transitions,
-- movement and screens above the overworld from observing a mid-action swap.
function WorldAPI:canReorderParty()
  local game, ow = self.game, self:overworld()
  local party = game and game.save and game.save.party or {}
  return #party > 1 and not not acceptsMenuInput(game, ow)
end

function WorldAPI:reorderParty(fromSlot, toSlot)
  local game, ow = self.game, self:overworld()
  if not ow then return nil, NO_OVERWORLD end
  if not acceptsMenuInput(game, ow) then return nil, "world is busy" end
  local party = game.save and game.save.party or {}
  if not validPartySlot(party, fromSlot)
      or not validPartySlot(party, toSlot) then
    return nil, "invalid party slot"
  end
  if fromSlot ~= toSlot then
    party[fromSlot], party[toSlot] = party[toSlot], party[fromSlot]
    require("src.core.Sound").play(game.data, "Swap")
  end
  return true
end

-- Contextual field-item shortcuts. Only actions that can start immediately
-- are listed; callers receive copied labels and never inspect world internals.
function WorldAPI:availableFieldActions()
  local game, ow, out = self.game, self:overworld(), {}
  if not (game and game.save and ow and ow.map and ow.player) then
    return out, NO_OVERWORLD
  end
  if not acceptsMenuInput(game, ow) then return out, "world is busy" end
  local save, inventory = game.save, game.save.inventory or {}
  local items = game.data and game.data.items or {}

  if (inventory.BICYCLE or 0) > 0 and not ow.player.surfing
      and not (save.onBike and save.forcedBike)
      and (save.onBike or ow:bikeAllowed(ow.map.id)) then
    out[#out + 1] = { id = "bicycle",
      label = save.onBike and "BIKE OFF" or "BICYCLE" }
  end

  if not ow.player.surfing and ow:facingIsShoreOrWater() then
    local rods = {}
    for _, id in ipairs(RODS) do
      if (inventory[id] or 0) > 0 then
        local def = items[id]
        rods[#rods + 1] = { id = id, label = def and def.name or id }
      end
    end
    if #rods > 0 then
      out[#out + 1] = { id = "fish", label = "FISH", rods = rods }
    end
  end

  if ow:useCutFieldMove() == "ok" then
    out[#out + 1] = { id = "cut", label = "CUT" }
  end
  local surf = ow:useSurfFieldMove()
  if surf == "ok" or surf == "dismount" then
    out[#out + 1] = { id = "surf",
      label = surf == "dismount" and "LEAVE WATER" or "SURF" }
  end

  if not ow.strengthActive and ow:partyKnows("STRENGTH") then
    out[#out + 1] = { id = "strength", label = "STRENGTH" }
  end
  if ow.dark and ow:partyKnows("FLASH") then
    out[#out + 1] = { id = "flash", label = "FLASH" }
  end
  if DIG_TILESETS[ow.map.def.tileset] and ow.map.id ~= "AGATHAS_ROOM"
      and ow:partyKnows("DIG") then
    out[#out + 1] = { id = "dig", label = "DIG" }
  end
  if ow:partyKnows("TELEPORT") and outside(game, ow) then
    out[#out + 1] = { id = "teleport", label = "TELEPORT" }
  end
  local sources = softboiledSources(game)
  if #sources > 0 then
    out[#out + 1] = { id = "softboiled", label = "SOFTBOILED",
      sources = sources }
  end
  return out
end

function WorldAPI:useFieldAction(id, opts)
  local game, ow = self.game, self:overworld()
  if not ow then return nil, NO_OVERWORLD end
  if not acceptsMenuInput(game, ow) then return nil, "world is busy" end
  local found
  for _, action in ipairs(self:availableFieldActions()) do
    if action.id == id then found = action break end
  end
  if not found then return nil, "field action unavailable" end

  if id == "bicycle" then
    if ow:useBicycle() then return true end
  elseif id == "cut" then
    local x, y = ow.player:facingCell()
    if ow:tryCut(x, y) then return true end
  elseif id == "surf" then
    local mode = ow:useSurfFieldMove()
    if mode == "dismount" then
      ow:stopSurfing()
      return true
    elseif mode == "ok" then
      local x, y = ow.player:facingCell()
      ow:trySurf(x, y)
      return true
    end
  elseif id == "fish" then
    local rod = opts and opts.rod
    if not rod and #found.rods == 1 then rod = found.rods[1].id end
    for _, choice in ipairs(found.rods) do
      if choice.id == rod and ow:useFishingRod(rod) then return true end
    end
    return nil, "fishing rod unavailable"
  elseif id == "strength" then
    if ow:useStrengthFieldMove() then return true end
  elseif id == "flash" then
    if ow:useFlashFieldMove() then return true end
  elseif id == "dig" or id == "teleport" then
    ow:beginTeleportOut()
    return true
  elseif id == "softboiled" then
    local sourceSlot = opts and tonumber(opts.sourceSlot)
    local targetSlot = opts and tonumber(opts.targetSlot)
    local allowed
    for _, source in ipairs(found.sources or {}) do
      if source.slot == sourceSlot then
        for _, target in ipairs(source.targets or {}) do
          if target.slot == targetSlot then allowed = true break end
        end
      end
    end
    if not allowed then return nil, "softboiled target unavailable" end
    if ow:useSoftboiledFieldMove(game.save.party[sourceSlot],
        game.save.party[targetSlot]) then return true end
  end
  return nil, "field action unavailable"
end

-- FLY needs a destination choice, so it is exposed separately from the
-- immediate actions above. The request is still checked against the same
-- visited-town list as the native Town Map picker before the world may warp.
function WorldAPI:canFly()
  local game, ow = self.game, self:overworld()
  return not not (ow and ow.map and outside(game, ow) and ow:partyKnows("FLY"))
end

function WorldAPI:flyTo(mapId)
  local game, ow = self.game, self:overworld()
  if not ow then return nil, NO_OVERWORLD end
  if not self:canFly() then return nil, "fly unavailable" end
  if not acceptsMenuInput(game, ow) then return nil, "world is busy" end
  if not flyDestinationAvailable(game, mapId) then
    return nil, "destination unavailable"
  end
  ow:flyTo(mapId)
  return true
end

-- A compact, read-only view of the active map for minimaps and companion UIs.
-- `rows` describes collision terrain; optional `tileRows` reduces each real
-- 8x8 map tile to its average Game Boy shade ("0" lightest, "3" darkest).
-- `tileDetailRows` preserves one shade per 4x4 quadrant. Markers identify
-- exits and item spots that are still active without exposing world internals.
function WorldAPI:mapOverview()
  local ow = self:overworld()
  if not ow or not ow.map then return nil, NO_OVERWORLD end
  local map, markers = ow.map, {}
  local def = map.def or {}
  for _, warp in ipairs(def.warps or {}) do
    markers[#markers + 1] = { kind = "warp", x = warp.x, y = warp.y }
  end
  local game, save = self.game, self.game.save or {}
  for _, obj in ipairs(def.objects or {}) do
    if obj.item and obj.item ~= "0" and obj.item ~= 0
        and ow.objectVisible(save, map.id, obj) then
      markers[#markers + 1] = { kind = "item", x = obj.x, y = obj.y }
    end
  end
  local hidden = game.data and game.data.field and game.data.field.hiddenItems
  for _, item in ipairs(hidden and hidden[map.id] or {}) do
    local key = map.id .. "_" .. item.x .. "_" .. item.y
    if not (save.hiddenTaken and save.hiddenTaken[key]) then
      markers[#markers + 1] = { kind = "hidden", x = item.x, y = item.y }
    end
  end
  return MapOverview.build(map, markers)
end

-- opts.arrive = "fly" | "teleport" picks the arrival FX; anything else
-- lands the player without one, like a scripted warp.
function WorldAPI:warpTo(mapId, x, y, facing, opts)
  local ow = self:overworld()
  if not ow then return nil, NO_OVERWORLD end
  if not self.game.data.maps[mapId] then
    return nil, "unknown map: " .. tostring(mapId)
  end
  if opts and (opts.arrive == "fly" or opts.arrive == "teleport") then
    ow.arriveWarp = opts.arrive
  end
  ow:startWarpTo(mapId, x, y, facing or "down", opts and opts.onDone,
                 { via = "warp", keepMusic = opts and opts.keepMusic })
  return true
end

-- save.objectToggles is the same store the spawn filter reads, so a toggle
-- on an inactive map takes effect the next time it is entered.
function WorldAPI:toggleObject(mapId, objName, visible)
  local save = self.game and self.game.save
  if not save then return nil, "no save" end
  save.objectToggles = save.objectToggles or {}
  save.objectToggles[mapId] = save.objectToggles[mapId] or {}
  save.objectToggles[mapId][objName] = visible and true or false
  Runtime.emit("world.object_toggled",
    { mapId = mapId, objName = objName, visible = visible and true or false })
  local ow = self:overworld()
  if ow and ow.map and ow.map.id == mapId then
    ow:setMap(mapId, ow.player.cellX, ow.player.cellY, ow.player.facing,
              { seamless = true, via = "reload", keepMusic = true })
  end
  return true
end

function WorldAPI:setFlag(name, value)
  local save = self.game and self.game.save
  if not save or not save.flags then return nil, "no save" end
  save.flags[name] = value
  return true
end

function WorldAPI:getFlag(name)
  local save = self.game and self.game.save
  return save and save.flags and save.flags[name]
end

-- active map only: this mutates the runtime Map and rebuilds the renderer.
-- A layout change that must survive a reload belongs in a maps patch.
function WorldAPI:replaceBlock(bx, by, block)
  local ow = self:overworld()
  if not ow or not ow.map then return nil, NO_OVERWORLD end
  ow:replaceBlock(bx, by, block)
  return true
end

-- objDef uses the same shape as maps[].objects.  Runtime objects are not
-- serialized: a permanent NPC belongs in a maps patch, this is for
-- scripted and dynamic actors the mod re-spawns on map.entered.
function WorldAPI:spawnNpc(mapId, objDef)
  local ow = self:overworld()
  if not ow then return nil, NO_OVERWORLD end
  if type(objDef) ~= "table" then return nil, "objDef must be a table" end
  local copy = {}
  for k, v in pairs(objDef) do copy[k] = v end
  return ow:addRuntimeObject(mapId, copy, self.modId)
end

function WorldAPI:removeNpc(npcId)
  local ow = self:overworld()
  if not ow then return nil, NO_OVERWORLD end
  return ow:removeRuntimeObject(npcId, self.modId)
end

-- a handle onto a live NPC: scriptMove / marchInPlace / face, which is
-- everything the scripted-movement queue exposes
local Handle = {}
Handle.__index = Handle

function Handle:scriptMove(dir, tiles, onDone)
  self.ow:scriptMove(self.npc, dir, tiles or 1, onDone)
  return true
end

function Handle:marchInPlace(onDone)
  self.ow:marchInPlace(self.npc, onDone)
  return true
end

function Handle:face(dir)
  self.npc.facing = dir
  return true
end

function Handle:position()
  return self.npc.cellX, self.npc.cellY
end

-- Walk one tile starting NOW, outside the scripted-movement queue.
--
-- scriptMove queues onto OverworldState.scriptMoves, and a non-empty
-- scriptMoves is how the overworld knows a cutscene is running -- it gates
-- handleInput (OverworldController "local scripted = ... #self.scriptMoves >
-- 0"), so an actor animated that way freezes the player's controls for as
-- long as it walks.  That is right for Oak marching to his lab and wrong for
-- an actor that moves on its own schedule: a networked player's ghost, an
-- ambient walker.  This is the same per-tile state scriptMove sets, minus
-- the queue and therefore minus the lockout.
--
-- Collision is deliberately not checked.  The caller is replaying a move
-- that was already decided somewhere else (validated on the peer's machine,
-- or authored), and re-judging it here would let the two copies disagree
-- about where the actor is.  Use canStep first if you want the check.
function Handle:stepNow(dir)
  local npc = self.npc
  if not Collision.DELTA[dir] then return nil, "bad direction: " .. tostring(dir) end
  if npc.moving then return nil, "already moving" end
  npc.facing = dir
  npc.targetX, npc.targetY = Collision.target(npc.cellX, npc.cellY, dir)
  npc.moving = true
  npc.progress = 0
  return true
end

-- Would stepNow land somewhere legal?  Exposed separately so a caller that
-- does want the map's opinion can ask for it without giving up the "replay
-- verbatim" default above.
function Handle:canStep(dir)
  local ow = self.ow
  if not (ow and ow.map) then return false end
  return Collision.canMove(ow.map, ow.entities, self.npc, dir) and true or false
end

-- Snap to a cell with no animation: a warp arrival, or a resync that has
-- drifted too far to walk off.  Clears any step in flight so the entity
-- cannot land on its old target a frame later.
function Handle:placeAt(x, y, facing)
  local npc = self.npc
  npc.moving = false
  npc.marching = false
  npc.targetX, npc.targetY = nil, nil
  npc.progress = 0
  npc.cellX, npc.cellY = x, y
  npc.px, npc.py = x * 16, y * 16
  if facing then npc.facing = facing end
  return true
end

-- True while a step is still animating, so a driver can pace itself rather
-- than stomping a move in flight.
function Handle:isMoving()
  return self.npc.moving and true or false
end

-- Whether the player may walk through this object (Collision.occupied skips
-- passable entities -- Yellow's companion Pikachu is the engine's own user
-- of the flag).  It still draws and can still be talked to; it just stops
-- being an obstacle, which is what a dynamic actor wants when standing in a
-- doorway would otherwise wall someone in.
function Handle:setPassable(passable)
  self.npc.passable = passable and true or false
  return true
end

function WorldAPI:npc(mapId, indexOrName)
  local ow = self:overworld()
  if not ow then return nil, NO_OVERWORLD end
  if ow.map and ow.map.id ~= mapId then return nil, "map is not active" end
  for _, npc in ipairs(ow.npcs or {}) do
    if npc.def.index == indexOrName or npc.def.name == indexOrName
       or npc.id == indexOrName then
      return setmetatable({ ow = ow, npc = npc, id = npc.id }, Handle)
    end
  end
  return nil, "no such object: " .. tostring(indexOrName)
end

-- FIFO queueing is owned by the script runner; until it lands this runs
-- the rows when nothing else is running and refuses otherwise, so a mod
-- never silently loses a script.
function WorldAPI:queueScript(rows, extra)
  local ow = self:overworld()
  if not ow or not ow.runner then return nil, NO_OVERWORLD end
  if ow.runner:isRunning() then return nil, "a script is already running" end
  ow.runner:run(rows, extra)
  return true
end

-- The supported way to start a wild encounter.  Hand-rolling this -- build a
-- BattleState, push it -- silently costs evolutions and blackout-on-loss
-- (both hang off onFinish -> afterBattle) plus the entry wipe and battle
-- theme (both owned by pushBattle).  Nothing raises when they are missing.
function WorldAPI:startWildBattle(species, level)
  local ow = self:overworld()
  if not ow then return nil, NO_OVERWORLD end
  if not self.game.data.pokemon[species] then
    return nil, "unknown species: " .. tostring(species)
  end
  -- Pokemon.new writes the level through verbatim -- into level, the stat
  -- calc and the exp curve -- so a fraction has to be refused here rather
  -- than round somewhere downstream.  The % test also catches NaN, which
  -- passes both range comparisons.
  level = tonumber(level)
  if not level or level % 1 ~= 0 or level < 1 or level > 100 then
    return nil, "level must be a whole number 1..100"
  end
  -- overworld() resolves the world from UNDER whatever sits on top of it,
  -- so from a battle hook this would otherwise stack a second battle over
  -- the live one -- and on a loss its afterBattle blacks out and warps
  -- with the outer battle still on the stack.
  local BattleTransition = require("src.render.BattleTransition")
  for _, state in ipairs(self.game.stack and self.game.stack.states or {}) do
    if state.awardExp or getmetatable(state) == BattleTransition then
      return nil, "a battle is already running"
    end
  end
  if ow.transitioning then return nil, "the world is mid-warp" end
  -- BattleState.newWild marks the species SEEN before it reports an empty
  -- party, so the party check comes first: a refused call must not leave a
  -- Pokedex entry behind.
  local save = self.game.save
  if not (save and Party.firstHealthy(save.party or {})) then
    return nil, "no healthy party"
  end
  local battle = require("src.battle.BattleState")
    .newWild(self.game, species, level)
  battle.onFinish = function(result) ow:afterBattle(result, battle) end
  ow:pushBattle(battle)
  return true
end

-- refresh the warp index on a loaded Map so newly added warps are usable
-- without a full map reload; pass nil to target the active map
function WorldAPI:rebuildWarpIndex(mapId)
  local ow = self:overworld()
  if mapId then
    local cached = MapLoader.cached(mapId)
    if cached then cached:rebuildWarpIndex() end
    return cached ~= nil
  end
  if not ow or not ow.map then return nil, NO_OVERWORLD end
  ow.map:rebuildWarpIndex()
  return true
end

-- drop a map's cached instance so the next load re-reads its record; when
-- it is the active map the world reloads around the player in place
function WorldAPI:invalidateMap(mapId)
  local ow = self:overworld()
  if not ow then
    local had = MapLoader.invalidate(mapId)
    Runtime.emit("map.reloaded", { mapId = mapId, reason = "invalidate" })
    return had
  end
  local ok, err = pcall(ow.reloadMap, ow, mapId, "invalidate")
  if not ok then
    Logger.warn("[%s] invalidateMap %s failed: %s", tostring(self.modId),
                tostring(mapId), tostring(err))
    return nil, tostring(err)
  end
  return true
end

return WorldAPI
