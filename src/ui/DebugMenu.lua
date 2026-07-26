-- Dev-mode debug menu: a menu-driven front end for the same cheats the
-- backtick console offers (src/dev/Console.lua) -- teleport, heal party,
-- give item, give Pokémon -- for anyone who'd rather not type Lua.
-- Opened with F3 (see the devMode gate in src/core/Game.lua); styled like
-- the START menu (src/ui/StartMenu.lua) but docked left instead of right,
-- so the two never visually collide if a future hotkey opens both.
-- Never required on a player boot.

local ListMenu = require("src.ui.ListMenu")
local Menu = require("src.ui.Menu")
local QuantityBox = require("src.ui.QuantityBox")
local TextBox = require("src.render.TextBox")

local DebugMenu = {}

local function report(game, text)
  game.stack:push(TextBox.new(game, text))
end

-- ------- teleport

local function sortedMapIds(data)
  local ids = {}
  for id in pairs(data.maps or {}) do table.insert(ids, id) end
  table.sort(ids)
  return ids
end

local function openTeleport(game)
  local items = {}
  for _, mapId in ipairs(sortedMapIds(game.data)) do
    table.insert(items, { value = mapId, label = mapId:gsub("_", " ") })
  end
  game.stack:push(ListMenu.new(game, "TELEPORT TO?", items, {
    onChoose = function(item)
      -- same rebuild the console's `warp` verb uses (src/dev/Console.lua):
      -- pop everything (this list and menu included) and enter fresh
      while game.stack:top() do game.stack:pop() end
      game.stack:push(require("src.world.OverworldController"),
                       item.value, 5, 5, "down")
    end,
  }))
end

-- ------- heal party

local function healParty(game)
  local Pokemon = require("src.pokemon.Pokemon")
  local party = game.save.party or {}
  for _, mon in ipairs(party) do
    Pokemon.heal(mon)
  end
  require("src.core.Sound").play(game.data, "Healing_Machine")
  report(game, (#party > 0) and "Party healed!" or "(no party)")
end

-- ------- give item

local function sortedItemIds(data)
  local ids = {}
  for id in pairs(data.items or {}) do table.insert(ids, id) end
  table.sort(ids, function(a, b)
    local da, db = data.items[a], data.items[b]
    return (da and da.name or a) < (db and db.name or b)
  end)
  return ids
end

local function openGiveItem(game)
  local items = {}
  for _, id in ipairs(sortedItemIds(game.data)) do
    local def = game.data.items[id]
    table.insert(items, { value = id, label = def and def.name or id })
  end
  game.stack:push(ListMenu.new(game, "GIVE ITEM", items, {
    onChoose = function(item, list)
      local id = item.value
      local def = game.data.items[id]
      local name = def and def.name or id
      list:close()
      game.stack:push(QuantityBox.new(game, {
        max = 99, start = 1,
        onDone = function(qty)
          if not qty then return end
          local Bag = require("src.inventory.Bag")
          if Bag.add(game.save, id, qty) then
            report(game, ("%s x%d added"):format(name, qty))
          else
            report(game, "Bag is full!")
          end
        end,
      }))
    end,
  }))
end

-- ------- give pokemon

local function dexOrderedSpecies(data)
  local byDex = {}
  for species, def in pairs(data.pokemon or {}) do
    if def.dex then byDex[def.dex] = species end
  end
  local ids = {}
  local size = (data.constants and data.constants.dexSize) or 151
  for n = 1, size do
    if byDex[n] then table.insert(ids, byDex[n]) end
  end
  return ids
end

local function openGivePokemon(game)
  local items = {}
  for _, id in ipairs(dexOrderedSpecies(game.data)) do
    local def = game.data.pokemon[id]
    table.insert(items, { value = id, label = def.name or id })
  end
  game.stack:push(ListMenu.new(game, "GIVE POKéMON", items, {
    onChoose = function(item, list)
      local id = item.value
      local def = game.data.pokemon[id]
      local name = def and def.name or id
      list:close()
      game.stack:push(QuantityBox.new(game, {
        max = 100, start = 5,
        onDone = function(level)
          if not level then return end
          local Pokemon = require("src.pokemon.Pokemon")
          local mon = Pokemon.new(game.data, id, level)
          if require("src.pokemon.Party").add(game.save.party, mon) then
            report(game, ("%s L%d joined the party"):format(name, level))
          elseif require("src.pokemon.Boxes").deposit(game.save, mon) then
            report(game, ("%s L%d sent to the PC"):format(name, level))
          else
            report(game, "Party and PC are full!")
          end
        end,
      }))
    end,
  }))
end

-- ------- no clip

-- Game.noclip (checked in src/world/Player.lua's tryMove) is a plain
-- field on the Game singleton, not save data -- it resets every process
-- launch and, unlike a flag on the Player instance (which TELEPORT above
-- recreates from scratch), survives a teleport.
local function noclipLabel(game)
  return "NO CLIP " .. (game.noclip and "ON" or "OFF")
end

-- ------- options (nested: lower-level toggles, tucked away so the
-- top-level menu stays short)

local function openOptions(game)
  local wildsItem = { keepOpen = true }
  local function wildsLabel() return "NO WILDS " .. (game.noWilds and "ON" or "OFF") end
  wildsItem.onSelect = function()
    -- consumed in OverworldController's onStepComplete
    game.noWilds = not game.noWilds
    wildsItem.label = wildsLabel()
  end
  wildsItem.label = wildsLabel()

  local fastItem = { keepOpen = true }
  local function fastLabel() return "FAST WALK " .. (game.fastWalk and "ON" or "OFF") end
  fastItem.onSelect = function()
    -- consumed in Player:tryMove
    game.fastWalk = not game.fastWalk
    fastItem.label = fastLabel()
  end
  fastItem.label = fastLabel()

  game.stack:push(Menu.new(game, { wildsItem, fastItem }, {
    tx = 0, ty = 0, tw = 16, -- fits "FAST WALK OFF" (13 chars)
    onCancel = function()
      -- B backs out to the parent menu, not the overworld -- this really
      -- is a nested menu, not a dead-end screen
      local menu = DebugMenu.new(game)
      menu.screenId = "DebugMenu"
      game.stack:push(menu)
    end,
  }))
end

-- ------- top-level menu

function DebugMenu.new(game)
  local noclipItem = { keepOpen = true }
  noclipItem.onSelect = function()
    game.noclip = not game.noclip
    noclipItem.label = noclipLabel(game)
  end
  noclipItem.label = noclipLabel(game)
  -- the rest are kept to 8 chars or fewer so they fit the same tw=11 box
  -- StartMenu uses (POKéMON here mirrors StartMenu's own entry of
  -- that name); NO CLIP needs the wider box below instead
  local items = {
    noclipItem,
    { label = "TELEPORT", onSelect = function() openTeleport(game) end },
    { label = "HEAL", onSelect = function() healParty(game) end },
    { label = "ITEM", onSelect = function() openGiveItem(game) end },
    { label = "POKéMON", onSelect = function() openGivePokemon(game) end },
    { label = "OPTIONS", onSelect = function() openOptions(game) end },
  }
  -- StartMenu docks tx=9..19 (right, tw=11); this mirrors it at
  -- tx=0..13 (left, widened to tw=14 so "NO CLIP OFF" fits) so the two
  -- boxes can never visually overlap.
  return Menu.new(game, items, { tx = 0, ty = 0, tw = 14 })
end

return DebugMenu
