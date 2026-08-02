-- Driver: the lobby cast, the records board, and buying a prize.
--
--   POKEPORT_DRIVER=mods/celadon_battle_facility/tests/lobby_driver.lua \
--   POKEPORT_IDENTITY=cbf_driver love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "shots"
  local TextBox = require("src.render.TextBox")
  local Menu = require("src.ui.Menu")
  local Bag = require("src.inventory.Bag")

  local FACILITY = "CELADON_BATTLE_FACILITY"
  local failures = 0
  local function check(cond, msg)
    U.log(cond and "ok  " or "FAIL", msg)
    if not cond then failures = failures + 1 end
  end

  if not game.data.maps[FACILITY] then
    U.log("driver aborted: the mod is not loaded")
    return
  end
  game.save.flags = game.save.flags or {}
  game.save.flags.EVENT_GOT_STARTER = true

  -- ------- the lobby, with everyone in it

  U.teleport(game, FACILITY, 6, 8, "up")
  U.wait(10)
  U.shot(game, DIR .. "/cbf_8_lobby_cast.png")
  local ow = game.overworld
  U.log("npcs on the map:", #(ow.npcs or {}))
  check(#(ow.npcs or {}) == 4, "all four lobby NPCs spawned")

  -- ------- the records board

  U.teleport(game, FACILITY, 10, 5, "up")
  U.tap(game, "a")
  local sawRecords = false
  for _ = 1, 200 do
    local top = game.stack:top()
    if top ~= game.overworld and getmetatable(top) ~= TextBox
       and getmetatable(top) ~= Menu then
      sawRecords = true
      break
    end
    U.tap(game, "a")
    U.wait(2)
  end
  check(sawRecords, "the archivist opens the records board")
  U.wait(6)
  U.shot(game, DIR .. "/cbf_9_records.png")
  -- close it and drain back to the overworld
  for _ = 1, 60 do
    if game.stack:top() == game.overworld then break end
    U.tap(game, "b")
    U.wait(2)
  end

  -- ------- buying a prize

  Bag.add(game.save, "CBF_TOKEN", 5, game.data)
  local before = game.save.inventory.CBF_TOKEN or 0
  check(before == 5, "the player is holding 5 BATTLE PT")

  U.teleport(game, FACILITY, 2, 5, "up")
  U.tap(game, "a")
  local sawMenu = false
  for _ = 1, 250 do
    local top = game.stack:top()
    if top == game.overworld then break end
    if getmetatable(top) == Menu then
      if not sawMenu then
        sawMenu = true
        U.shot(game, DIR .. "/cbf_10_prizes.png")
      end
      U.tap(game, "a")           -- take the first row: FULL RESTORE, 1 PT
    else
      U.tap(game, "a")
    end
    U.wait(2)
  end
  check(sawMenu, "the counter offers a prize menu")

  local after = game.save.inventory.CBF_TOKEN or 0
  local got = game.save.inventory.FULL_RESTORE or 0
  U.log("tokens:", before, "->", after, " full restores:", got)
  check(got >= 1, "the prize reached the bag")
  check(after == before - 1, "exactly one token was spent")

  U.log(failures == 0 and "DRIVER PASS" or ("DRIVER FAIL (" .. failures .. ")"))
end
