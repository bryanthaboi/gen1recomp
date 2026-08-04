-- Minimal Pokédex: dex-ordered list with seen/owned markers.

local ListMenu = require("src.ui.ListMenu")
local Strings = require("src.core.Strings")

local PokedexMenu = {}

-- SGB: PalPacket_Pokedex, whole screen
function PokedexMenu:sgbPalettes(game)
  return require("src.render.PaletteFX").wholeNamed(game.data, "BROWNMON")
end

function PokedexMenu.new(game, opts)
  opts = opts or {}
  local dex = game.save.pokedex or { seen = {}, owned = {} }
  local byDex = {}
  for species, def in pairs(game.data.pokemon) do
    if def.dex then byDex[def.dex] = def end
  end
  local items = {}
  local seen, owned = 0, 0
  -- dex bound and number width come from constants; the fallbacks keep a
  -- cache imported before those keys existed on the Kanto numbering
  local constants = game.data.constants or {}
  local numFmt = ("%%0%dd"):format(constants.dexDigits or 3)
  for n = 1, constants.dexSize or 151 do
    local def = byDex[n]
    if def then
      local label
      if dex.owned[def.id] then
        label = (numFmt .. " %s"):format(n, def.name)
        owned = owned + 1
        seen = seen + 1
      elseif dex.seen[def.id] then
        label = (numFmt .. " %s"):format(n, def.name)
        seen = seen + 1
      else
        label = (numFmt .. " -----"):format(n)
      end
      table.insert(items, {
        label = label,
        -- owned entries carry the pokéball marker like the original
        -- list; seen-only entries are just the name
        ball = dex.owned[def.id] or nil,
        value = (dex.owned[def.id] or dex.seen[def.id]) and def.id or nil,
      })
    end
  end
  local list = ListMenu.new(game, "POKéDEX", items, {
    -- SEEN / OWN in the original's fixed three-digit field: engine/menus/
    -- pokedex.asm HandlePokedexListMenu prints both counts with
    -- `lb bc, 1, 3` (hlcoord 16,3 and 16,6), labelled by PokedexSeenText
    -- and PokedexOwnText ("OWN", not "OWNED").  The width is load bearing
    -- here: a bare ListMenu footer goes through the 18-column text wrap,
    -- so the old 19-glyph "SEEN 100  OWNED 100" split in two and its first
    -- half landed on the list's last row at y=120 (#639).
    footer = Strings("SEEN %3d  OWN %3d", seen, owned),
    pageJump = true, -- Left/Right page jumps like the original
    onCancel = opts.onCancel, -- B returns to the start menu when opened from it
    onChoose = function(item, dexList)
      if not item.value then return end
      -- the DATA / CRY / AREA / QUIT choice (engine/menus/pokedex.asm
      -- PokedexMenuItemsText); CRY keeps the side menu open like the
      -- original.  B is what returns to the list: HandlePokedexSideMenu
      -- hands back b=2 for B and b=1 for QUIT, and ShowPokedexMenu sends
      -- b=1 to .exitPokedex, so QUIT closes the whole Pokédex (#571)
      local Menu = require("src.ui.Menu")
      local Screens = require("src.ui.Screens")
      local entries = {
        { label = Strings("DATA"), onSelect = function()
            Screens.push(game, "DexEntryMenu", item.value)
          end },
        { label = Strings("CRY"), keepOpen = true, onSelect = function()
            require("src.core.Sound").playCry(game.data, item.value)
          end },
        { label = Strings("AREA"), onSelect = function()
            Screens.push(game, "TownMap", { nestSpecies = item.value })
          end },
      }
      -- Yellow's PRNT item (engine/menus/pokedex.asm PokedexMenuItemsText
      -- _YELLOW branch -> PrintPokedexEntry): the Game Boy Printer job is
      -- stood in for by a PNG of the entry page saved under prints/.
      if require("src.core.GameVersion").isYellow() then
        entries[#entries + 1] = { label = Strings("PRNT"), onSelect = function()
          local DexEntryMenu = require("src.ui.DexEntryMenu")
          local Printer = require("src.core.Printer")
          local TextBox = require("src.render.TextBox")
          local def = game.data.pokemon[item.value]
          local path = require("src.pokemon.Sprites").path(
            game.data, item.value, "front", { kind = "dex" })
          local ok, sprite = false, nil
          if path then ok, sprite = pcall(love.graphics.newImage, path) end
          local saved, err = Printer.save("dex_" .. item.value, 160, 144,
            function()
              DexEntryMenu.render(game, def, ok and sprite or nil, false)
            end)
          game.stack:push(TextBox.new(game, saved
            and Strings("Printed %s's\ndata!\fSaved as\n%s\vin the save\nfolder.",
                        def.name, saved)
            or Strings("Printer error!\n%s", tostring(err))))
        end }
      end
      entries[#entries + 1] = { label = Strings("QUIT"), onSelect = function()
        -- .exitPokedex: drop the dex list too and hand back to whoever
        -- opened it (the start menu, whose saved cursor is still on
        -- POKéDEX -- wBattleAndStartSavedMenuItem)
        dexList:close()
        if opts.onCancel then opts.onCancel() end
      end }
      game.stack:push(Menu.new(game, entries,
        { tx = 12, ty = 8, tw = 8,
          th = #entries * 2 + 2 }))
    end,
  })
  list.sgbPalettes = PokedexMenu.sgbPalettes
  return list
end

return PokedexMenu
