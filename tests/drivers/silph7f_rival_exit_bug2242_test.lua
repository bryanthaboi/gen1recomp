-- scripts/SilphCo7F.asm:206-252
--   POKEPORT_DRIVER=tests/drivers/silph7f_rival_exit_bug2242_test.lua \
--     POKEPORT_IDENTITY=bug2242 POKEPORT_TOUCH=0 POKEPORT_VERSION=red \
--     POKEPORT_SHOT_DIR=/tmp/shots love .   (BUG2242_TILE=2 runs the upper tile)
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local Flags = require("src.script.Flags")
  local TextBox = require("src.render.TextBox")
  local mapScripts = require("data.scripts.init")

  local MAP = "SILPH_CO_7F"
  local TILE_Y = tonumber(os.getenv("BUG2242_TILE") or "3")
  if TILE_Y ~= 2 and TILE_Y ~= 3 then TILE_Y = 3 end
  local TRIG_X = 3
  local WANT = (TILE_Y == 2)
    and { rx = 3, ry = 3,
          dirs = { "right", "right" },
          cells = { "(4,3)", "(5,3)" },
          shotCell = "(4,3)" }
     or { rx = 3, ry = 4,
          dirs = { "left", "up", "up", "right", "right", "right", "down" },
          cells = { "(2,4)", "(2,3)", "(2,2)", "(3,2)", "(4,2)", "(5,2)", "(5,3)" },
          shotCell = "(4,2)" }

  local failures = 0
  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    if not ok then failures = failures + 1 end
    return ok
  end
  local function finish()
    U.log(("%s: %d failure(s)"):format(failures == 0 and "DONE" or "DONE WITH FAILURES",
                                       failures))
    love.event.quit(failures == 0 and 0 or 1)
    while true do coroutine.yield() end
  end

  local tank = Pokemon.new(game.data, "MEWTWO", 100)
  tank.moves = {
    { id = "PSYCHIC_M", pp = 99 },
    { id = "THUNDERBOLT", pp = 99 },
    { id = "ICE_BEAM", pp = 99 },
    { id = "RECOVER", pp = 99 },
  }
  game.save.party = { tank }
  game.save.player = game.save.player or {}
  game.save.player.name = game.save.player.name or "RED"
  game.save.player.rival = game.save.player.rival or "BLUE"
  game.save.defeatedTrainers = {}
  game.save.objectToggles = game.save.objectToggles or {}
  game.save.objectToggles[MAP] = nil
  Flags.set(game.save, "EVENT_CHOSE_SQUIRTLE")
  Flags.clear(game.save, "EVENT_BEAT_SILPH_CO_RIVAL")

  U.teleport(game, MAP, TRIG_X + 1, TILE_Y, "left")
  U.wait(10)
  local ow = game.overworld

  local t = game.data.text
  for _, key in ipairs({ "_SilphCo7FRivalText", "_SilphCo7FRivalWaitedHereText",
                         "_SilphCo7FRivalDefeatedText",
                         "_SilphCo7FRivalGoodLuckToYouText" }) do
    check(key .. " resolves to a string",
          type(t[key]) == "string" and t[key] ~= "")
  end
  local defeated = t._SilphCo7FRivalDefeatedText or ""
  local needle = defeated:match("Oh ho") and "Oh ho" or "BOSS"

  local spawn
  for _, o in ipairs(game.data.maps[MAP].objects or {}) do
    if o.name == "SILPHCO7F_RIVAL" then spawn = o end
  end
  check("SILPHCO7F_RIVAL has an object_event", spawn ~= nil)
  check("it spawns on (3,7) as in data/maps/objects/SilphCo7F.asm",
        spawn ~= nil and spawn.x == 3 and spawn.y == 7)
  check("SILPH_CO_7F (5,4) is the desk, not floor", not ow.map:isWalkableCell(5, 4))

  local Music = require("src.core.Music")
  local realPlay = Music.play
  Music.play = function() end
  local rows, probeFacing
  do
    local probe = {
      runner = { isRunning = function() return false end,
                 run = function(_, r) rows = r end },
      player = { facing = "left" },
      npcByIndex = function() return { def = { name = "X" } } end,
    }
    local script = mapScripts.get(MAP)
    check("SILPH_CO_7F has an onStep hook", script ~= nil and script.onStep ~= nil)
    if script and script.onStep then
      check(("onStep fires on the ambush tile (%d,%d)"):format(TRIG_X, TILE_Y),
            script.onStep(game, probe, TRIG_X, TILE_Y) == true)
    end
    probeFacing = probe.player.facing
  end
  Music.play = realPlay

  local moveTo, walk, arm, battle, mapDefeat
  for i, r in ipairs(rows or {}) do
    if r[1] == "move_npc_to" then moveTo = r end
    if r[1] == "walk_npc" then walk = r end
    if r[1] == "save_end_battle_text" then arm = i end
    if r[1] == "rival_battle" then battle = i end
    if r[1] == "show_text" and r[2] == "_SilphCo7FRivalDefeatedText" then mapDefeat = i end
  end
  check("the scene carries move/walk rows", moveTo ~= nil and walk ~= nil)
  check("player is turned down at the rival", probeFacing == "down")
  check("_SilphCo7FRivalDefeatedText is armed right before rival_battle",
        arm ~= nil and battle ~= nil and arm == battle - 1
        and rows[arm][2] == "_SilphCo7FRivalDefeatedText")
  check("the loss line is not printed on the map afterwards", mapDefeat == nil)
  if moveTo and walk then
    U.log(("plan: rival to (%d,%d), exit %s"):format(
            moveTo[3], moveTo[4], table.concat(walk[3], ", ")))
    check(("rival parks on (%d,%d)"):format(WANT.rx, WANT.ry),
          moveTo[3] == WANT.rx and moveTo[4] == WANT.ry)
    local same = #walk[3] == #WANT.dirs
    for i = 1, #WANT.dirs do
      if walk[3][i] ~= WANT.dirs[i] then same = false end
    end
    check("exit list is " .. table.concat(WANT.dirs, ", "), same)
    local D = { up = { 0, -1 }, down = { 0, 1 },
                left = { -1, 0 }, right = { 1, 0 } }
    local x, y, clean = moveTo[3], moveTo[4], true
    for i, d in ipairs(walk[3]) do
      x, y = x + D[d][1], y + D[d][2]
      if not ow.map:isWalkableCell(x, y) then
        clean = false
        U.log(("  exit step %d (%s) walks into solid ground at (%d,%d)")
                :format(i, d, x, y))
      end
      if x == TRIG_X and y == TILE_Y then
        clean = false
        U.log(("  exit step %d (%s) walks through the player on (%d,%d)")
                :format(i, d, x, y))
      end
    end
    check("every exit cell is walkable and none is the player's", clean)
    check("the exit ends on the (5,3) teleporter", x == 5 and y == 3)
  end

  U.hold(game, "left", 24)

  local function boxText()
    local top = game.stack:top()
    if getmetatable(top) ~= TextBox then return "" end
    local parts = {}
    for _, page in ipairs(top.pages or {}) do
      if type(page) == "table" then
        for _, line in ipairs(page) do parts[#parts + 1] = tostring(line) end
      end
    end
    return table.concat(parts, " ")
  end

  local function rivalNpc()
    for _, n in ipairs(game.overworld and game.overworld.npcs or {}) do
      if n.def and n.def.name == "SILPHCO7F_RIVAL" then return n end
    end
  end

  local waited = t._SilphCo7FRivalWaitedHereText or ""
  local waitedNeedle = waited:match("waited") and "waited" or "here"
  local parked
  for _ = 1, 600 do
    local r = rivalNpc()
    local s = boxText()
    if r and #ow.scriptMoves == 0 and not r.moving
       and s:find(waitedNeedle, 1, true) then
      parked = r
      break
    end
    if s ~= "" then U.tap(game, "a") end
    U.wait(2)
  end
  check("the rival showed up and stopped walking", parked ~= nil)
  if parked then
    U.log(("rival parked on (%d,%d) facing %s; player on (%d,%d) facing %s")
            :format(parked.cellX, parked.cellY, tostring(parked.facing),
                    ow.player.cellX, ow.player.cellY, tostring(ow.player.facing)))
    check(("he is on (%d,%d) live"):format(WANT.rx, WANT.ry),
          parked.cellX == WANT.rx and parked.cellY == WANT.ry)
  end

  local sawBattle, defeatInBattle, moneyAfter, shotDefeat = false, false, false, false
  for f = 1, 4000 do
    local top = game.stack:top()
    if top and top.phase then
      if not sawBattle then U.log("battle started at loop " .. f) end
      sawBattle = true
      local cur = top.current
      local text = cur and type(cur.text) == "string" and cur.text or ""
      if text:find(needle, 1, true) then
        defeatInBattle = true
        if not shotDefeat then
          shotDefeat = true
          U.log("in-battle loss line: " .. text:gsub("\n", " / "))
          check("the loss line opens with the rival's tag",
                text:sub(1, #game.save.player.rival + 2) == game.save.player.rival .. ": ")
          U.wait(45)
          if U.shot(game, DIR .. "/2241_01_defeat_text_in_battle.png") then
            U.log("captured", DIR .. "/2241_01_defeat_text_in_battle.png")
          end
        end
      elseif defeatInBattle and text:find("for winning", 1, true) then
        moneyAfter = true
      end
      if top.phase == "menu" then top.menuIndex = 1
      elseif top.phase == "moveSelect" then top.moveIndex = 1 end
      U.tap(game, "a")
      if f > 2400 and top.onFinish then
        U.log("force-finishing a stalled battle")
        top.onFinish("win")
        if game.stack:top() == top then game.stack:pop() end
      end
    elseif sawBattle then
      break
    elseif top ~= ow then
      U.tap(game, "a")
    end
    U.wait(2)
  end
  check("the battle ran and ended", sawBattle)
  check("the loss line printed inside the battle state", defeatInBattle)
  check("the money line followed it", moneyAfter)

  local mapBoxes = {}
  local sawLuck = false
  local luck = t._SilphCo7FRivalGoodLuckToYouText or ""
  local luckNeedle = luck:match("moving on up") and "moving on up" or "luck"
  for _ = 1, 600 do
    local s = boxText()
    if s ~= "" and mapBoxes[#mapBoxes] ~= s then mapBoxes[#mapBoxes + 1] = s end
    if s:find(luckNeedle, 1, true) then sawLuck = true break end
    if game.stack:top() ~= ow then U.tap(game, "a") end
    U.wait(3)
  end
  check("GoodLuckToYou is on screen after the battle", sawLuck)
  check("EVENT_BEAT_SILPH_CO_RIVAL is set",
        game.save.flags.EVENT_BEAT_SILPH_CO_RIVAL == true)
  local leaked = false
  for _, s in ipairs(mapBoxes) do
    if s:find(needle, 1, true) then leaked = true end
  end
  check("no map box carried the loss line", not leaked)

  local visited, last = {}, nil
  local function sample()
    local r = rivalNpc()
    if not r then return false end
    local function note(x, y)
      local key = ("(%d,%d)"):format(x, y)
      if key ~= last then
        visited[#visited + 1] = key
        last = key
      end
    end
    if r.moving and r.targetX then
      note(r.targetX, r.targetY)
    else
      note(r.cellX, r.cellY)
    end
    return true
  end
  sample()
  local shotWalk = false
  local gone = false
  U.tap(game, "a")
  for _ = 1, 1200 do
    if game.stack:top() ~= ow and getmetatable(game.stack:top()) == TextBox then
      U.tap(game, "a")
    end
    if not sample() then gone = true break end
    if not shotWalk and last == WANT.shotCell then
      shotWalk = true
      U.wait(4)
      if U.shot(game, DIR .. "/2242_02_walk_around_player.png") then
        U.log("captured", DIR .. "/2242_02_walk_around_player.png")
      end
      sample()
    end
    U.wait(1)
  end
  U.log("rival visited: " .. table.concat(visited, " "))
  check("the rival was hidden at the end of the walk", gone)
  local start = ("(%d,%d)"):format(WANT.rx, WANT.ry)
  check("the walk starts from his parked cell", visited[1] == start)
  local path = {}
  for i = 2, #visited do path[#path + 1] = visited[i] end
  check("visited cells are " .. table.concat(WANT.cells, " "),
        table.concat(path, " ") == table.concat(WANT.cells, " "))
  check("he ends on (5,3)", visited[#visited] == "(5,3)")
  if TILE_Y == 3 then
    check("he arrives on (5,3) from (5,2)", visited[#visited - 1] == "(5,2)")
    local bad = false
    for _, c in ipairs(visited) do
      if c == "(4,3)" or c == "(5,4)" then bad = true end
    end
    check("he never steps on (4,3) or the (5,4) desk", not bad)
  end
  check("the rival is gone from the map", rivalNpc() == nil)

  finish()
end
