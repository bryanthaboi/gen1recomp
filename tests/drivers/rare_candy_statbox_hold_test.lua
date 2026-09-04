-- ../pokered/engine/items/item_effects.asm:1403-1411
-- ../pokered/engine/pokemon/evos_moves.asm:120-128
--   POKEPORT_DRIVER=tests/drivers/rare_candy_statbox_hold_test.lua \
--     POKEPORT_IDENTITY=red-aug28 POKEPORT_VERSION=red POKEPORT_TOUCH=0 \
--     SHOT_DIR=/tmp/shots love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local Screens = require("src.ui.Screens")
  local Bag = require("src.inventory.Bag")
  local StatBox = require("src.battle.BattleState").StatBox
  local SHOT_DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  local function findStat()
    for _, s in ipairs(game.stack.states) do
      if getmetatable(s) == StatBox then return s end
    end
  end
  local function findEvo()
    local Evo = require("src.ui.EvolutionState")
    for _, s in ipairs(game.stack.states) do
      if getmetatable(s) == Evo then return s end
    end
  end
  local function topText()
    local t = game.stack:top()
    if not (t and t.pages) then return nil end
    local out = {}
    for _, page in ipairs(t.pages) do
      for _, line in ipairs(page) do out[#out + 1] = line end
    end
    return table.concat(out, " ")
  end
  local function waitFor(fn, frames)
    for _ = 1, frames or 600 do
      if fn() then return true end
      U.wait(1)
    end
    return false
  end

  local mon = Pokemon.new(game.data, "CATERPIE", 6)
  game.save.party = { mon }
  game.save.inventory = {}
  Bag.add(game.save, "RARE_CANDY", 3, game.data)
  U.teleport(game, "PALLET_TOWN", 10, 8, "down")
  U.wait(10)

  Screens.push(game, "BagMenu", {})
  U.wait(12)
  U.tap(game, "a")
  U.wait(12)
  U.tap(game, "a")
  U.wait(12)
  U.tap(game, "a")
  U.wait(40)
  check("the candy raised the level", mon.level == 7)

  for _ = 1, 60 do
    if findStat() then break end
    U.tap(game, "a")
    U.wait(8)
  end
  local stat = findStat()
  if not check("the level-up stat window opened", stat ~= nil) then
    while true do coroutine.yield() end
  end
  U.shot(game, SHOT_DIR .. "/candy_statbox_1_stats.png")

  -- pokered engine/items/item_effects.asm:1392-1394
  local PartyMenu = require("src.ui.PartyMenu")
  local picker
  for _, s in ipairs(game.stack.states) do
    if getmetatable(s) == PartyMenu then picker = s end
  end
  if check("the party menu is still under the stat window", picker ~= nil) then
    local msg = picker:bottomMessage() or ""
    check("its bottom box still holds the level line, not the item prompt "
          .. "(#2161): " .. msg:gsub("\n", " "),
          msg:find("Use item") == nil)
  end

  U.tap(game, "a")
  check("the stat window is still on the stack after its A press",
        findStat() ~= nil)
  check("'is evolving!' typed under it",
        waitFor(function()
          local t = topText()
          return t and t:find("evolving") ~= nil
        end, 300))
  U.wait(30)
  U.shot(game, SHOT_DIR .. "/candy_statbox_2_is_evolving.png")
  check("and the stats are STILL up through the 50-frame hold",
        findStat() ~= nil)

  check("the evolution movie starts", waitFor(findEvo, 400))
  U.wait(10)
  U.shot(game, SHOT_DIR .. "/candy_statbox_3_cleared.png")
  check("ClearScreenArea is what finally covers it", findStat() ~= nil)

  U.log("Shots: " .. SHOT_DIR .. "/candy_statbox_*.png")
  U.log("Shot 1 is the ATTACK/DEFENSE/SPEED/SPECIAL window. Shot 2 must")
  U.log("STILL show that window with 'What? CATERPIE is evolving!' in the")
  U.log("box below it -- the cart clears rows 0-11 only inside")
  U.log("TryEvolvingMon, 50 frames later. Broken looked like an empty")
  U.log("overworld above the text. Shot 3 is the white evolution field,")
  U.log("which is that ClearScreenArea.")

  while true do coroutine.yield() end
end
