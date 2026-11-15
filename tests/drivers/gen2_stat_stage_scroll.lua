local U = require("tests.drivers.util")
local Mon = require("src.battle.gen2.Mon")

-- pokecrystal data/text/common_2.asm:678-681 _BattleStatWentWayUpText
-- pokecrystal home/text.asm:520 _ContTextNoPause

return function(game)
  local failed = 0
  local function check(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then failed = failed + 1 end
    return ok
  end
  local ok, err = xpcall(function()
    local identity = os.getenv("POKEPORT_IDENTITY") or ""
    assert(identity ~= "" and identity ~= "pokemon-love2d", "isolated identity required")
    local version = game.save.version
    local out = os.getenv("POKEPORT_SHOT_DIR") or "."
    game.writeSave = function() end
    for _ = 1, 1200 do
      if game.world and game.world.map and not game.stack:top() then break end
      U.wait(1)
    end
    local function new(species, ids)
      local moves = {}
      for _, id in ipairs(ids) do
        local d = assert(game.data.moves[id], id)
        moves[#moves + 1] = { id = id, pp = d.pp, maxPp = d.pp, ppUps = 0 }
      end
      return assert(Mon.new(game.data, species, 50, { moves = moves,
        dvs = { attack = 15, defense = 15, speed = 15, special = 15 } }))
    end
    local player, enemy = new("MEW", { "SWORDS_DANCE" }), new("SNORLAX", { "SPLASH" })
    player.nickname = "MEW"
    game.save.party = { player }
    assert(game.world:startBattle({ wild = enemy }), "wild battle failed")
    local screen
    for _ = 1, 1200 do
      screen = game.stack:top()
      if screen and screen.screenId == "Gen2BattleState" and screen.battle then break end
      U.wait(1)
    end
    assert(screen and screen.battle, "BattleState required")
    for _ = 1, 5000 do
      if screen.phase == "menu" and #screen.queue == 0 and not screen.anim then break end
      U.tap(game, "a"); U.wait(1)
    end
    assert(screen.phase == "menu", "menu did not settle")
    screen.battle.random = function() return 0 end
    assert(screen:chooseMenu("fight")); assert(screen:chooseMove(1))

    local seenHead, presses = false, 0
    for _ = 1, 6000 do
      if screen.message and screen.message:find("way up", 1, true) then break end
      U.wait(1)
    end
    check(screen.message and screen.message:find("way up", 1, true), version .. " Swords Dance prints the way-up line")
    check(screen.messagePages == nil, version .. " the way-up line is one held page")
    for _ = 1, 2000 do
      local lines = screen:messageLines()
      if not seenHead and lines[1] == "MEW's" and lines[2] == "ATTACK" then
        seenHead = U.still(game, out .. "/rf1b_01_" .. version .. "_head_before_scroll.png")
      end
      if not screen:syncTyper() then break end
      U.wait(1)
    end
    local lines = screen:messageLines()
    check(seenHead, version .. " MEW's / ATTACK shows before the scroll")
    check(lines[1] == "ATTACK" and lines[2] == "went way up!",
      version .. " the box scrolled to ATTACK / went way up! with no press (" .. table.concat(lines, " / ") .. ")")
    check(screen.messageTimer > 0, version .. " the scrolled line waits for one press")
    U.still(game, out .. "/rf1b_02_" .. version .. "_scrolled_prompt.png")
    U.tap(game, "a")
    presses = presses + 1
    for _ = 1, 30 do U.wait(1) end
    check(not (screen.message and screen.message:find("way up", 1, true)) or screen.messageTimer == 0,
      version .. " one press clears the stat line (presses=" .. presses .. ")")
  end, debug.traceback)
  if not ok then
    print("FAIL " .. tostring(err))
    failed = failed + 1
  end
  love.event.quit(failed == 0 and 0 or 1)
end
