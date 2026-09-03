-- home/text_script.asm:8
-- engine/battle/battle_transitions.asm:14
--   POKEPORT_DRIVER=tests/drivers/oak_pikachu_wipe_bug2119_test.lua \
--     POKEPORT_VERSION=yellow POKEPORT_IDENTITY=yellow-sep02 POKEPORT_TOUCH=0 \
--     SHOT_DIR=/tmp/shots love .
--   POKEPORT_DRIVER=tests/drivers/oak_pikachu_wipe_bug2119_test.lua \
--     POKEPORT_VERSION=red POKEPORT_IDENTITY=bug2119 POKEPORT_TOUCH=0 \
--     SHOT_DIR=/tmp/shots love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local GameVersion = require("src.core.GameVersion")
  local TextBox = require("src.render.TextBox")
  local ChoiceBox = require("src.ui.ChoiceBox")
  local Pokemon = require("src.pokemon.Pokemon")

  local SHOT_DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local fails = 0
  local function check(label, ok)
    if not ok then fails = fails + 1 end
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  local function shot(name)
    local path = SHOT_DIR .. "/" .. name .. ".png"
    if U.shot(game, path) then U.log("captured", path .. " @f" .. U.frame()) end
  end

  local function npcNamed(name)
    local ow = game.overworld
    for _, n in ipairs((ow and ow.npcs) or {}) do
      if n.def and n.def.name == name then return n end
    end
    return nil
  end

  local function page()
    local top = game.stack:top()
    if getmetatable(top) == ChoiceBox then
      U.tap(game, "b")
    elseif getmetatable(top) == TextBox then
      U.tap(game, "a")
    end
  end

  local function waitForWipe(label, wantName, shotName, maxFrames, step)
    for _ = 1, maxFrames do
      local ow = game.overworld
      local keep = ow and ow.battleOamKeep
      if keep ~= nil then
        check(label .. ": the wipe keeps a second OAM block", keep ~= false)
        check(label .. ": that block is " .. wantName,
              keep and keep.def and keep.def.name == wantName)
        check(label .. ": the kept NPC is drawable", keep and keep.draw ~= nil)
        for _ = 1, 400 do
          local top = game.stack:top()
          if top and top.phase == "wipe" and top.wipeLen
             and top.t >= math.floor(top.wipeLen / 2) then
            break
          end
          if not ow.battleOamKeep then break end
          U.wait(1)
        end
        shot(shotName)
        return keep
      end
      step()
      U.wait(2)
    end
    check(label .. ": reached the battle wipe", false)
    return nil
  end

  game.save.flags = game.save.flags or {}
  game.save.player.name = "bryan"
  game.save.party = { Pokemon.new(game.data, "PIKACHU", 6) }
  game.save.objectToggles = {}
  game.save.flags.EVENT_GOT_POKEDEX = true
  game.save.flags.EVENT_COMPLETED_CATCH_TRAINING = nil

  if GameVersion.isYellow() then
    -- scripts/ViridianCity.asm:177
    U.teleport(game, "VIRIDIAN_CITY", 19, 10, "up")
    U.wait(20)
    check("OLD_MAN2 is on the map", npcNamed("VIRIDIANCITY_OLD_MAN2") ~= nil)
    local stepped = false
    waitForWipe("Yellow old man", "VIRIDIANCITY_OLD_MAN2",
                "bug2119_oldman2_wipe", 900, function()
      if not stepped then
        U.hold(game, "up", 6)
        U.wait(4)
        local p = game.overworld and game.overworld.player
        stepped = p ~= nil and p.cellY == 9
      end
      page()
    end)

    -- scripts/PalletTown.asm:117
    game.save.flags.EVENT_GOT_STARTER = nil
    game.save.flags.EVENT_FOLLOWED_OAK_INTO_LAB = nil
    U.teleport(game, "PALLET_TOWN", 10, 4, "up")
    U.wait(20)
    local steps = 0
    waitForWipe("Oak's Pikachu demo", "PALLETTOWN_OAK",
                "bug2119_oak_wipe", 2400, function()
      local ow = game.overworld
      if ow and ow.player.cellY > 0 and game.stack:top() == ow and steps < 12 then
        U.hold(game, "up", 8)
        steps = steps + 1
      end
      page()
    end)
  else
    -- pokered scripts/ViridianCity.asm:62
    U.teleport(game, "VIRIDIAN_CITY", 17, 6, "up")
    U.wait(20)
    check("the walking old man is on the map", npcNamed("VIRIDIANCITY_OLD_MAN") ~= nil)
    local talked = false
    waitForWipe("Red old man", "VIRIDIANCITY_OLD_MAN",
                "bug2119_oldman_wipe", 900, function()
      local ow = game.overworld
      local man = npcNamed("VIRIDIANCITY_OLD_MAN")
      if not talked and ow and man and game.stack:top() == ow then
        local fx, fy = ow.player:facingCell()
        if ow:npcAtCell(fx, fy) == man then
          U.tap(game, "a")
          talked = true
        end
      else
        page()
      end
    end)
  end

  U.log(fails == 0 and "ALL PASS" or (fails .. " check(s) FAILED"))
  U.log("The NPC who started the demo should stay on screen next to you for")
  U.log("the whole flash + wipe; before #2119 only the player survived it.")

  while true do coroutine.yield() end
end
