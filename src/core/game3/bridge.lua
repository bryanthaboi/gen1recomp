-- Host ↔ game3 data bridge (enterFromHost / returnToHost).
-- Contracts: H1 clock continuity, H2 bag quarantine+99 overflow, H6 opaque party,
-- H9 National Dex, move_overlay persistence.

local Party = require("src.core.game3.party")
local Bag = require("src.core.game3.bag")
local Dex = require("src.core.game3.dex")
local Items = require("src.core.game3.items")

local Bridge = {}

Bridge.SAVE_KEY = "firered_game3"

local function sidecar(save)
  save.modData = save.modData or {}
  save.modData[Bridge.SAVE_KEY] = save.modData[Bridge.SAVE_KEY] or {}
  return save.modData[Bridge.SAVE_KEY]
end

function Bridge.storageToSidecar(sc, session)
  if not (sc and session and session.storage) then return end
  sc.storage = require("src.core.game3.storage").serialize(session.storage)
  sc.pc = nil
end

local function snapshot_money(save)
  return tonumber(save.money) or 0
end

--- Enter Sevii: snapshot opaque party + bag/dex into session; pause host field later via runtime.
function Bridge.enterFromHost(mod, game, opts)
  opts = opts or {}
  local Runtime = require("src.core.game3.runtime")
  local save = game and game.save
  if not save then
    return nil, "no save"
  end

  if Runtime.isActive() and opts.alreadyOnMap then
    Runtime.log("enterFromHost skipped — already active (adopt)")
    return Runtime.getSession()
  end

  local sc = sidecar(save)

  local session = {
    party = Party.takeOpaque(save.party),
    bag = Bag.new(),
    dex = Dex.new(),
    money = snapshot_money(save),
    coins = tonumber(save.coins) or 0,
    name = save.name or save.playerName,
    rivalName = save.rivalName,
    gender = save.gender,
    map = opts.map or "FR_PLAYERS_HOUSE_2F",
    x = opts.x or 6,
    y = opts.y or 6,
    facing = opts.facing or "down",
    healMap = sc.healMap or "FR_PLAYERS_HOUSE_1F",
    healX = sc.healX or 8,
    healY = sc.healY or 5,
    move_overlay = sc.move_overlay or {},
    options = sc.options or {},
    storage = require("src.core.game3.storage").restore(sc.storage, sc.pc, sc.pcItems or save.pcItems or save.pc_items),
    enteredAt = os.time(),
  }

  local Options = require("src.core.game3.options")
  Options.ensure(session)

  sc.move_overlay = session.move_overlay

  Bag.mergeFromHost(session.bag, save.inventory)
  Bag.restoreSidecar(session.bag, sc)
  Dex.mergeFromHost(session.dex, save)
  Dex.restoreNational(session.dex, sc)

  session._partyProof = Party.takeOpaque(session.party)

  do
    local HealLocations = require("src.core.game3.heal_locations")
    HealLocations.normalizeSession(session)
  end

  Runtime.log(string.format(
    "enterFromHost map=%s alreadyOnMap=%s reason=%s",
    tostring(session.map),
    tostring(opts.alreadyOnMap == true),
    tostring(opts.reason or "ferry")))

  Runtime.start(mod, game, session, opts)
  return session
end

--- Persist session sidecar without leaving Sevii / warping host.
function Bridge.persistSessionOnly(mod, game)
  local Runtime = require("src.core.game3.runtime")
  local save = game and game.save
  if not save then return end
  local session = Runtime.getSession()
  local sc = sidecar(save)
  if not session then return end
  if session.party then
    Party.writeBack(save.party, session.party)
  end
  if session.bag then
    local hostWrites, quarantine, overflow = Bag.splitForHost(session.bag, save.inventory)
    -- On internal persist we keep host bag as-is for host-safe stacks still
    -- living in game3 bag; only update quarantine/overflow mirrors.
    sc.quarantine = quarantine
    sc.overflow = overflow
    sc._hostWriteSnapshot = hostWrites
  end
  if session.dex then
    local _, national = Dex.splitForHost(session.dex)
    sc.national_dex = national
  end
  sc.move_overlay = session.move_overlay or sc.move_overlay
  sc.healMap = session.healMap
  sc.healX = session.healX
  sc.healY = session.healY
  sc.options = session.options or sc.options
  Bridge.storageToSidecar(sc, session)
  if session.money ~= nil then save.money = session.money end
end

--- Leave Sevii: write opaque party, split bag/dex, persist sidecar, resume host.
function Bridge.returnToHost(mod, game, opts)
  opts = opts or {}
  local Runtime = require("src.core.game3.runtime")
  local save = game and game.save
  if not save then
    return nil, "no save"
  end
  local session = Runtime.getSession()
  local sc = sidecar(save)

  if session and session.party then
    Party.writeBack(save.party, session.party)
  end

  if session and session.bag then
    local hostWrites, quarantine, overflow = Bag.splitForHost(session.bag, save.inventory)
    -- Replace host-safe stacks we manage: write capped qty.
    for id, qty in pairs(hostWrites) do
      local have = save.inventory[id] or 0
      if have > 0 then
        save.inventory[id] = nil
        -- keep bagOrder clean
        if save.bagOrder then
          for i = #save.bagOrder, 1, -1 do
            if save.bagOrder[i] == id then table.remove(save.bagOrder, i) end
          end
        end
      end
      if qty > 0 then
        save.inventory[id] = math.min(Items.HOST_MAX_QTY, qty)
        if save.bagOrder then
          table.insert(save.bagOrder, id)
        end
      end
    end
    sc.quarantine = quarantine
    sc.overflow = overflow
    -- Clear live bag mirror; quarantine holds non-host + overflow holds 99+ rem.
  end

  if session and session.dex then
    local hostUpdates, national = Dex.splitForHost(session.dex)
    Dex.applyHostUpdates(save, hostUpdates)
    sc.national_dex = national
  end

  if session then
    sc.move_overlay = session.move_overlay or sc.move_overlay
    sc.healMap = session.healMap
    sc.healX = session.healX
    sc.healY = session.healY
    sc.options = session.options or sc.options
    Bridge.storageToSidecar(sc, session)
    if session.money ~= nil then
      save.money = session.money
    end
  end

  Runtime.stop(mod, game)

  -- Warp host to Vermilion (or opts).
  local world = (game and (game.overworld or game.world)) or nil
  local mapId = opts.map
  local x = opts.x
  local y = opts.y
  if not mapId then
    local Host = require("src.core.game3.host_stub")
    if Host.isGen2() then
      mapId, x, y = "VERMILION_PORT", 7, 12
    else
      mapId, x, y = "VERMILION_CITY", 18, 29
    end
  end
  x = x or 7
  y = y or 12
  if mod and mod.world and mod.world.warpTo then
    mod.world:warpTo(mapId, x, y)
  elseif world and world.warpToMapId then
    world:warpToMapId(mapId, x, y, opts.facing or "down")
  elseif world and world.setMap then
    world:setMap(mapId, x, y, opts.facing or "down")
  end

  return true
end

--- Persist sidecar flags from Space store without leaving Sevii.
function Bridge.persistFlags(mod, game, storeSerialize)
  local save = game and game.save
  if not save then return end
  local sc = sidecar(save)
  if type(storeSerialize) == "table" then
    for k, v in pairs(storeSerialize) do
      if k ~= "quarantine" and k ~= "overflow" and k ~= "national_dex"
          and k ~= "move_overlay" then
        sc[k] = v
      end
    end
  end
end

function Bridge.getSidecar(save)
  if not save then return {} end
  return sidecar(save)
end

return Bridge
