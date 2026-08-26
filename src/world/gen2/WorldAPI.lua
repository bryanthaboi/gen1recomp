-- mod.world for Gen 2 (Gold): the same facade src/world/WorldAPI.lua gives a
-- mod under Gen 1, resolved against src/world/gen2/World.lua instead of the
-- Gen 1 overworld state.  One name, one method set, two arms -- a mod that
-- declares gen2compat calls mod.world:current() and does not care which game
-- it is running on.
--
-- Two structural differences show through, and both are reported rather than
-- faked:
--
--   * Gold's World is not a stack state.  It hangs off the service owner as
--     game.world for the whole run, so there is no stack scan here; a menu or
--     a battle pushed over the world does not hide it.
--
--   * Gen 2 event flags are NUMBERS (wEventFlags is a bitfield, and the cart's
--     EVENT_* constants are indices into it), where Gen 1 flags are string
--     keys in save.flags.  setFlag/getFlag therefore take a numeric id here
--     and say so when handed a string, rather than silently writing a key the
--     bitfield cannot hold.
--
-- Anything Gen 2 has no equivalent for at all returns nil plus a reason, the
-- same shape the Gen 1 arm uses for "no overworld".  A dual-generation mod
-- checks the second return and degrades; it never crashes and never gets a
-- silent no-op.

local Logger = require("src.core.Logger")
local Movement = require("src.script.gen2.Movement")
local Runtime = require("src.mods.Runtime")
local HiddenItems = require("src.world.gen2.HiddenItems")
local MapOverview = require("src.world.MapOverview")
local Bike = require("src.world.gen2.Bike")
local FieldMoves = require("src.world.gen2.FieldMoves")
local Permissions = require("src.world.gen2.Permissions")
local Mail = require("src.core.gen2.Mail")

local WorldAPI = {}
WorldAPI.__index = WorldAPI

local NO_OVERWORLD = "no overworld"
local RODS = { "OLD_ROD", "GOOD_ROD", "SUPER_ROD" }
local FIELD_ACTIONS = {
  { id = "cut", move = "CUT" },
  { id = "surf", move = "SURF" },
  { id = "strength", move = "STRENGTH" },
  { id = "flash", move = "FLASH" },
  { id = "headbutt", move = "HEADBUTT" },
  { id = "whirlpool", move = "WHIRLPOOL" },
  { id = "waterfall", move = "WATERFALL" },
  { id = "sweet_scent", move = "SWEET_SCENT" },
  { id = "dig", move = "DIG" },
  { id = "teleport", move = "TELEPORT" },
}

local function validPartySlot(party, slot)
  return type(slot) == "number" and slot == math.floor(slot)
    and party[slot] ~= nil
end

function WorldAPI.new(game, modId)
  return setmetatable({ game = game, modId = modId }, WorldAPI)
end

-- the live World, or nil while the boot cinema is still up
function WorldAPI:overworld()
  local world = self.game and self.game.world
  if world and world.map then return world end
  return nil
end

function WorldAPI:current()
  local world = self:overworld()
  if not world or not world.map then return nil, NO_OVERWORLD end
  local p = world.player
  return { mapId = world.map.id, x = p and p.cellX, y = p and p.cellY,
           facing = p and p.facing }
end

-- Keep the public party-ordering contract identical across generations.
-- Gen 2 stores mail by party slot, so it must move with the Pokemon just as
-- the native PartyMenu's SwitchPartyMons path does.
function WorldAPI:canReorderParty()
  local world, game = self:overworld(), self.game
  local party = game and game.save and game.save.party or {}
  return #party > 1 and world ~= nil and world:acceptsMenuInput()
end

function WorldAPI:reorderParty(fromSlot, toSlot)
  local world, game = self:overworld(), self.game
  if not world then return nil, NO_OVERWORLD end
  if not world:acceptsMenuInput() then return nil, "world is busy" end
  local party = game.save and game.save.party or {}
  if not validPartySlot(party, fromSlot)
      or not validPartySlot(party, toSlot) then
    return nil, "invalid party slot"
  end
  if fromSlot ~= toSlot then
    party[fromSlot], party[toSlot] = party[toSlot], party[fromSlot]
    Mail.swapSlots(game.save, fromSlot, toSlot)
    require("src.core.Sound").play(game.data, "Sfx_SwitchPokemon")
  end
  return true
end

local function itemLabel(game, id)
  local def = game and game.data and game.data.items
    and game.data.items[id]
  return (def and def.name) or id
end

-- The same field-item contract as Gen 1, resolved through Gold's own bike,
-- collision and fishing rules.
function WorldAPI:availableFieldActions()
  local world, game, out = self:overworld(), self.game, {}
  if not (world and game and game.save and world.map and world.player) then
    return out, NO_OVERWORLD
  end
  if not world:acceptsMenuInput() then return out, "world is busy" end
  local inventory = game.save.inventory or {}

  if (inventory.BICYCLE or 0) > 0 then
    local bike = Bike.tryBike({
      state = world.playerState,
      environment = world.map.def and world.map.def.environment,
      collision = world:playerCollision(),
      alwaysOnBike = world:alwaysOnBike(),
    })
    if bike == "mount" or bike == "dismount" then
      out[#out + 1] = { id = "bicycle",
        label = bike == "dismount" and "BIKE OFF" or "BICYCLE" }
    end
  end

  local context = world:fieldContext()
  if not FieldMoves.isSurfing(world.playerState)
      and Permissions.isWater(context.facingColl) then
    local rods = {}
    for _, id in ipairs(RODS) do
      if (inventory[id] or 0) > 0 then
        rods[#rods + 1] = { id = id, label = itemLabel(game, id) }
      end
    end
    if #rods > 0 then
      out[#out + 1] = { id = "fish", label = "FISH", rods = rods }
    end
  end

  for _, row in ipairs(FIELD_ACTIONS) do
    if not (row.move == "STRENGTH" and world.strengthActive) then
      local mon = FieldMoves.partyMoveUser(context.party, row.move, context)
      if mon then
        context.mon = mon
        local result = FieldMoves.fromMenu(row.move, context)
        if result.ok then
          out[#out + 1] = { id = row.id,
            label = row.move:gsub("_", " ") }
        end
      end
    end
  end

  if (inventory.SQUIRTBOTTLE or 0) > 0
      and world:squirtbottleTreeScript() then
    out[#out + 1] = { id = "squirtbottle",
      label = itemLabel(game, "SQUIRTBOTTLE") }
  end
  return out
end

function WorldAPI:useFieldAction(id, opts)
  local world = self:overworld()
  if not world then return nil, NO_OVERWORLD end
  if not world:acceptsMenuInput() then return nil, "world is busy" end
  local found
  for _, action in ipairs(self:availableFieldActions()) do
    if action.id == id then found = action break end
  end
  if not found then return nil, "field action unavailable" end

  if id == "bicycle" then
    local outcome = world:useFieldItem("BICYCLE")
    if outcome and outcome ~= "nowhere" then return true end
  elseif id == "fish" then
    local rod = opts and opts.rod
    if not rod and #found.rods == 1 then rod = found.rods[1].id end
    for _, choice in ipairs(found.rods) do
      if choice.id == rod then
        local outcome = world:useFieldItem(rod)
        if outcome and outcome ~= "nowhere" then return true end
        break
      end
    end
    return nil, "fishing rod unavailable"
  elseif id == "squirtbottle" then
    local outcome = world:useFieldItem("SQUIRTBOTTLE")
    if outcome and outcome ~= "nowhere" then return true end
  end
  for _, row in ipairs(FIELD_ACTIONS) do
    if row.id == id then
      local context = world:fieldContext()
      local mon = FieldMoves.partyMoveUser(context.party, row.move, context)
      local result = mon and world:useFieldMove(row.move, mon)
      if result and result.ok then return true end
      return nil, "field action unavailable"
    end
  end
  return nil, "field action unavailable"
end

-- The same read-only minimap contract as Gen 1, with Gold's object/event
-- visibility rules supplying the semantic markers.
function WorldAPI:mapOverview()
  local world = self:overworld()
  if not world or not world.map then return nil, NO_OVERWORLD end
  local map, def, markers = world.map, world.map.def or {}, {}
  for _, warp in ipairs(def.warps or {}) do
    markers[#markers + 1] = { kind = "warp", x = warp.x, y = warp.y }
  end
  local visible = {}
  for _, npc in ipairs(world.npcs or {}) do
    if npc.def then visible[npc.def] = true end
  end
  for _, obj in ipairs(def.objects or {}) do
    local item = obj.itemball and obj.itemball.item
    if item and item ~= "0" and item ~= 0 and visible[obj] then
      markers[#markers + 1] = { kind = "item", x = obj.x, y = obj.y }
    end
  end
  for _, item in ipairs(HiddenItems.unfound(def, world.events)) do
    markers[#markers + 1] = { kind = "hidden", x = item.x, y = item.y }
  end
  return MapOverview.build(map, markers)
end

-- opts is accepted for signature parity with the Gen 1 arm; Gold's arrival FX
-- come from the map setup method, so opts.arrive has nothing to select yet.
function WorldAPI:warpTo(mapId, x, y, facing, opts)
  local world = self:overworld()
  if not world then return nil, NO_OVERWORLD end
  if not (world.maps and world.maps[mapId]) then
    return nil, "unknown map: " .. tostring(mapId)
  end
  if not (x and y) then return nil, "warpTo needs x and y" end
  local ok = world:warpToMapId(mapId, x, y,
    facing or (world.player and world.player.facing) or "down")
  if not ok then return nil, world.status or "warp failed" end
  return true
end

-- Gen 2 has no save.objectToggles: an object's visibility IS its
-- MAPOBJECT_EVENT_FLAG, which lives in the event bitfield and is therefore
-- already persistent and already re-read by the next LoadObjectMasks.  Setting
-- the flag is the whole operation; appear/disappear additionally take it off
-- the live map when the map is the active one.
--
-- objRef is the object's 1-based index in the map's object list, or its name
-- when the extracted map carries one.
function WorldAPI:toggleObject(mapId, objRef, visible)
  local world = self:overworld()
  if not world then return nil, NO_OVERWORLD end
  if not (world.map and world.map.id == mapId) then
    -- the flag is per object, and the object list only resolves for a loaded
    -- map, so an off-map toggle has nothing to name
    return nil, "map is not active: " .. tostring(mapId)
  end
  local def = world.map.def
  local objects = def and def.objects
  if not objects then return nil, "map has no objects" end
  local index
  for i, obj in ipairs(objects) do
    if i == objRef or obj.name == objRef then
      -- def.objects is keyed by the object's own index, and World:objectEntity
      -- reads it back as objectId - 1, so the id is that key plus one
      index = obj.index or i
      break
    end
  end
  if not index then
    return nil, "no such object: " .. tostring(objRef)
  end
  local objectId = index + 1
  if visible then world:appearObject(objectId) else world:disappearObject(objectId) end
  Runtime.emit("world.object_toggled",
    { mapId = mapId, objName = objRef, visible = visible and true or false })
  return true
end

-- id is a numeric EVENT_* index into wEventFlags.  A string is the Gen 1
-- habit and cannot work here, so it is refused with the reason rather than
-- stored somewhere the engine never looks.
local function flagId(id)
  if type(id) == "number" then return id end
  return nil, ("Gen 2 event flags are numeric ids, got %s (%s)")
    :format(type(id), tostring(id))
end

function WorldAPI:setFlag(id, value)
  local world = self:overworld()
  if not world or not world.events then return nil, NO_OVERWORLD end
  local numeric, err = flagId(id)
  if not numeric then return nil, err end
  world.events:set(numeric, value and true or false)
  return true
end

function WorldAPI:getFlag(id)
  local world = self:overworld()
  if not world or not world.events then return nil, NO_OVERWORLD end
  local numeric, err = flagId(id)
  if not numeric then return nil, err end
  return world.events:get(numeric)
end

-- active map only, same contract as the Gen 1 arm: this mutates the loaded
-- block data and rebuilds the view.  `block` is a block id.
function WorldAPI:replaceBlock(bx, by, block)
  local world = self:overworld()
  if not world or not world.map then return nil, NO_OVERWORLD end
  world:changeBlock(bx, by, block)
  return true
end

local UNSUPPORTED = "not supported in Gen 2 yet"

-- objDef uses the same shape as an extracted map's objects list (sprite, x, y,
-- movement, hours, ...), which is the Gen 1 arm's contract too.  Runtime
-- objects are not serialized; a mod respawns them on map.entered.
function WorldAPI:spawnNpc(mapId, objDef)
  local world = self:overworld()
  if not world then return nil, NO_OVERWORLD end
  if type(objDef) ~= "table" then return nil, "objDef must be a table" end
  local copy = {}
  for k, v in pairs(objDef) do copy[k] = v end
  return world:addRuntimeObject(mapId, copy, self.modId)
end

function WorldAPI:removeNpc(npcId)
  local world = self:overworld()
  if not world then return nil, NO_OVERWORLD end
  return world:removeRuntimeObject(npcId, self.modId)
end

-- a handle onto a live NPC.  Scripted movement does carry over: it compiles to
-- the cart's own movement stream and rides World:beginMovement, the same path
-- an `applymovement` in a map script takes -- so a mod's walk is frozen,
-- stepped and released exactly like a scripted one.  Only spawning does not.
local Handle = {}
Handle.__index = Handle

-- One movement stream at a time is the engine's own limit (World.moveState is
-- a single slot), so a second call while one is running is refused rather than
-- silently replacing the first and stranding its onDone.
function Handle:scriptMove(dir, tiles, onDone)
  local world = self.world
  if world.moveState then return nil, "a movement is already running" end
  local step = Movement.stepByte(dir)
  if not step then return nil, "unknown direction: " .. tostring(dir) end
  local bytes = {}
  for _ = 1, math.max(0, tiles or 1) do bytes[#bytes + 1] = step end
  bytes[#bytes + 1] = Movement.STEP_END
  world:beginMovement(self.objectId, bytes, onDone)
  return true
end

-- Gen 1's marchInPlace is step_sleep-with-animation; the Gen 2 stream has no
-- single byte for it, and faking one out of turn bytes would march the wrong
-- way.  Left explicit rather than approximated.
function Handle:marchInPlace()
  return nil, UNSUPPORTED
end

function Handle:face(dir)
  self.npc:scriptFace(dir)
  return true
end

function Handle:position()
  return self.npc.cellX, self.npc.cellY
end

function WorldAPI:npc(mapId, indexOrName)
  local world = self:overworld()
  if not world then return nil, NO_OVERWORLD end
  if world.map and world.map.id ~= mapId then return nil, "map is not active" end
  for _, npc in ipairs(world.npcs or {}) do
    local def = npc.def
    if def and (def.index == indexOrName or def.name == indexOrName) then
      return setmetatable(
        { world = world, npc = npc, objectId = (def.index or 0) + 1 }, Handle)
    end
  end
  return nil, "no such object: " .. tostring(indexOrName)
end

-- The Gen 2 VM runs the cart's own bytecode out of data/generated/scripts.lua,
-- not the Gen 1 runner's `{ "command", ... }` rows, so there is no row list to
-- hand it.  What a mod actually reaches for out of that vocabulary is a small
-- set of verbs that Gold has its own entry points for, so those are driven
-- directly here, one row at a time, and anything else is refused BY NAME
-- before the first row runs -- a half-run queue is the failure mode this
-- facade exists to avoid.  The full list is src/script/Commands.lua; these
-- five are the ones with a Gen 2 home.
local VERBS = {}

-- start_battle "wild" species level.  Gold's own grass step ends in
-- World:startBattle with a Mon (src/world/gen2/World.lua:4021), so this is
-- that call with the mon built from the mod's species and level.  The trainer
-- arm needs a party out of the extracted trainer table and an OPP_CLASS the
-- mod cannot name, so only the wild arm is served.
function VERBS.start_battle(api, row, resume)
  local world = api:overworld()
  local kind = row[2]
  if kind ~= "wild" then
    return nil, "only start_battle \"wild\" is supported in Gen 2"
  end
  local game = world.game
  local mon = require("src.battle.gen2.Mon").new(
    game and game.data, row[3], tonumber(row[4]) or 5)
  if not mon then return nil, "unknown species: " .. tostring(row[3]) end
  local save = game and game.save
  if save then
    save.pokedex = save.pokedex or { seen = {}, caught = {} }
    save.pokedex.seen[mon.species] = true
  end
  world:startBattle({ wild = mon }, function() resume() end)
  return true
end

function VERBS.warp(api, row, resume)
  local ok, err = api:warpTo(row[2], row[3], row[4], row[5])
  if not ok then return nil, err end
  resume()
  return true
end

function VERBS.text(api, row, resume)
  local world = api:overworld()
  world:showText(tostring(row[2] or ""), function() resume() end)
  return true
end

function VERBS.setflag(api, row, resume)
  local ok, err = api:setFlag(row[2], true)
  if not ok then return nil, err end
  resume()
  return true
end

function VERBS.clearflag(api, row, resume)
  local ok, err = api:setFlag(row[2], false)
  if not ok then return nil, err end
  resume()
  return true
end

-- Rows run in order, each one resuming the next from its own completion
-- callback, so a battle or a text box blocks the queue the way it blocks the
-- Gen 1 runner's coroutine.  One queue at a time, for the reason
-- Handle:scriptMove refuses a second movement.
function WorldAPI:queueScript(rows, extra)
  local world = self:overworld()
  if not world then return nil, NO_OVERWORLD end
  if type(rows) ~= "table" then return nil, "queueScript wants a row list" end
  if self.queue then return nil, "a script is already running" end
  for i, row in ipairs(rows) do
    local name = type(row) == "table" and row[1]
    if not VERBS[name] then
      return nil, ("unsupported script command in Gen 2: %s (row %d)")
        :format(tostring(name), i)
    end
  end
  self.queue = true
  local pc = 0
  local step
  local function finish(err)
    self.queue = nil
    if err then
      Logger.warn("[%s] queueScript stopped: %s", tostring(self.modId), err)
    end
    if extra and extra.onDone then extra.onDone(err == nil) end
  end
  step = function()
    pc = pc + 1
    local row = rows[pc]
    if not row then return finish(nil) end
    local ok, err = VERBS[row[1]](self, row, function() step() end)
    if not ok then finish(err or "row failed") end
  end
  step()
  return true
end

-- Gold's maps come from one table loaded at World:load, so there is no
-- per-map instance cache to drop.  Reloading the active map is the part that
-- carries meaning, and reloadMapBadWarp is exactly the cart's own
-- "load this map again where you stand" (MAPSETUP_BADWARP).
function WorldAPI:invalidateMap(mapId)
  local world = self:overworld()
  if not world then return nil, NO_OVERWORLD end
  if not (world.map and world.map.id == mapId) then return true end
  local ok, err = pcall(world.reloadMapBadWarp, world)
  if not ok then
    Logger.warn("[%s] invalidateMap %s failed: %s", tostring(self.modId),
                tostring(mapId), tostring(err))
    return nil, tostring(err)
  end
  Runtime.emit("map.reloaded", { mapId = mapId, reason = "invalidate" })
  return true
end

return WorldAPI
