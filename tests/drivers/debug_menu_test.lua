-- Driver: the F3 debug menu (src/ui/DebugMenu.lua) -- opens via the real
-- devMode hotkey (Game:keypressed), then exercises NO CLIP, OPTIONS
-- (NO WILDS / FAST WALK), HEAL, ITEM, GIVE POKEMON and TELEPORT end to
-- end. Run with POKEPORT_DEV=1 set alongside POKEPORT_DRIVER (devMode
-- gates the hotkey, same as the console).
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local ListMenu = require("src.ui.ListMenu")
  local Menu = require("src.ui.Menu")

  U.teleport(game, "PALLET_TOWN", 5, 5, "down")

  local mon = Pokemon.new(game.data, "CHARMANDER", 12)
  mon.hp = 1
  table.insert(game.save.party, mon)

  local function topIs(cls) return getmetatable(game.stack:top()) == cls end

  local function openMenu()
    game:keypressed("f3")
    U.wait(2)
  end

  -- jump a ListMenu's cursor straight to a known value instead of mashing
  -- "down" through a 100+ row list (fossil_menu_test.lua sets NPC state
  -- directly the same way -- these drivers own the live objects, not just
  -- simulated input)
  local function selectValue(list, value)
    for i, item in ipairs(list.items) do
      if item.value == value then
        list.index = i
        return true
      end
    end
    return false
  end

  -- item order: NO CLIP, TELEPORT, HEAL, ITEM, POKEMON, OPTIONS
  U.log("f3 opens the menu:", (function()
    openMenu()
    return topIs(Menu)
  end)())
  U.shot(game, DIR .. "/debug_00_menu.png")

  U.log("f3 closes it again:", (function()
    game:keypressed("f3")
    U.wait(2)
    return game.stack:top() == game.overworld
  end)())

  -- -------- NO CLIP --------
  openMenu()
  U.log("noclip starts off:", not game.noclip)
  U.tap(game, "a") -- toggle on; keepOpen leaves the menu up
  U.wait(2)
  U.log("noclip on, menu still open:", game.noclip == true, topIs(Menu))
  U.shot(game, DIR .. "/debug_01_noclip_on.png")
  U.tap(game, "a") -- toggle back off
  U.wait(2)
  U.log("noclip off again:", game.noclip == false)
  U.shot(game, DIR .. "/debug_02_noclip_off.png")
  U.tap(game, "b") -- keepOpen never auto-closes; B backs out like any menu
  U.wait(3)
  U.log("back to overworld after b:", game.stack:top() == game.overworld)

  -- -------- OPTIONS (nested submenu) --------
  openMenu()
  for _ = 1, 5 do U.tap(game, "down") end -- NO CLIP -> ... -> OPTIONS
  U.tap(game, "a")
  U.wait(3)
  U.log("options submenu opened:", topIs(Menu))
  U.log("noWilds/fastWalk start off:", not game.noWilds, not game.fastWalk)
  U.shot(game, DIR .. "/debug_03_options.png")
  U.tap(game, "a") -- toggle NO WILDS on
  U.wait(2)
  U.log("noWilds on:", game.noWilds == true)
  U.shot(game, DIR .. "/debug_04_options_wilds_on.png")
  U.tap(game, "down")
  U.tap(game, "a") -- toggle FAST WALK on
  U.wait(2)
  U.log("fastWalk on:", game.fastWalk == true)
  U.shot(game, DIR .. "/debug_05_options_fastwalk_on.png")
  U.tap(game, "b") -- nested: backs out to the parent debug menu, not the overworld
  U.wait(3)
  U.log("back to the parent debug menu (not overworld):",
        topIs(Menu) and game.stack:top() ~= game.overworld)
  U.shot(game, DIR .. "/debug_06_options_back.png")
  U.tap(game, "b") -- close the debug menu entirely
  U.wait(3)
  U.log("closed to overworld:", game.stack:top() == game.overworld)
  -- leave the toggles as found so they don't affect the rest of this run
  game.noWilds = false
  game.fastWalk = false

  -- -------- HEAL --------
  openMenu()
  U.tap(game, "down")
  U.tap(game, "down") -- NO CLIP -> TELEPORT -> HEAL
  U.tap(game, "a")
  U.wait(3)
  U.log("mon hp before heal was 1, after:", mon.hp, "max:", mon.stats.hp)
  U.shot(game, DIR .. "/debug_07_healed.png")
  U.tap(game, "a") -- dismiss "Party healed!" TextBox
  U.wait(3)

  -- -------- ITEM --------
  openMenu()
  U.tap(game, "down")
  U.tap(game, "down")
  U.tap(game, "down") -- NO CLIP -> TELEPORT -> HEAL -> ITEM
  U.tap(game, "a")
  U.wait(3)
  local itemList = game.stack:top()
  local itemId = itemList.items[1] and itemList.items[1].value
  U.log("give-item list opened:", topIs(ListMenu), "first item:", tostring(itemId))
  U.shot(game, DIR .. "/debug_08_item_list.png")
  U.tap(game, "a") -- choose it
  U.wait(3)
  U.shot(game, DIR .. "/debug_09_item_qty.png")
  U.tap(game, "a") -- confirm default quantity (1)
  U.wait(3)
  U.log("inventory after give:", itemId, "=", tostring(game.save.inventory[itemId]))
  U.shot(game, DIR .. "/debug_10_item_given.png")
  U.tap(game, "a") -- dismiss confirmation

  -- -------- GIVE POKEMON --------
  U.wait(3)
  local beforeCount = #game.save.party
  openMenu()
  U.tap(game, "down")
  U.tap(game, "down")
  U.tap(game, "down")
  U.tap(game, "down") -- NO CLIP -> TELEPORT -> HEAL -> ITEM -> POKEMON
  U.tap(game, "a")
  U.wait(3)
  local monList = game.stack:top()
  local speciesId = monList.items[1] and monList.items[1].value
  U.log("give-pokemon list opened:", topIs(ListMenu), "first species:", tostring(speciesId))
  U.shot(game, DIR .. "/debug_11_pokemon_list.png")
  U.tap(game, "a") -- choose it
  U.wait(3)
  U.shot(game, DIR .. "/debug_12_pokemon_level.png")
  U.tap(game, "a") -- confirm default level (5)
  U.wait(3)
  U.log("party count before/after give:", beforeCount, #game.save.party,
        "last species:", tostring(game.save.party[#game.save.party]
          and game.save.party[#game.save.party].species))
  U.shot(game, DIR .. "/debug_13_pokemon_given.png")
  U.tap(game, "a") -- dismiss confirmation
  U.wait(3)

  -- -------- TELEPORT --------
  openMenu()
  U.tap(game, "down") -- NO CLIP -> TELEPORT
  U.tap(game, "a")
  U.wait(3)
  local mapList = game.stack:top()
  U.log("teleport list opened:", topIs(ListMenu))
  local found = selectValue(mapList, "VIRIDIAN_CITY")
  U.log("VIRIDIAN_CITY in map list:", found)
  U.shot(game, DIR .. "/debug_14_map_list.png")
  U.tap(game, "a") -- warp
  U.wait(10)
  U.log("landed on:", game.overworld.map.id, "stack top is overworld:",
        game.stack:top() == game.overworld)
  U.shot(game, DIR .. "/debug_15_teleported.png")

  U.log("DONE")
  love.event.quit()
end
