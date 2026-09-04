-- Driver: #154 Route 22 rival exit direction + #168 Cerulean Bill text
-- and southbound walk-off.
--
--   SHOT_DIR=/tmp/rival_walkoff POKEPORT_SPEED=8 \
--     POKEPORT_DRIVER=tests/drivers/rival_walkoff_test.lua love .

return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/rival_walkoff"
  os.execute("mkdir -p " .. DIR)

  local Pokemon = require("src.pokemon.Pokemon")
  local Flags = require("src.script.Flags")
  local Zoom = require("src.render.Zoom")
  if game.save.options then game.save.options.zoom = 0 end
  Zoom.reset()

  local function tank()
    local mon = Pokemon.new(game.data, "MEWTWO", 100)
    mon.moves = {
      { id = "PSYCHIC_M", pp = 99 },
      { id = "THUNDERBOLT", pp = 99 },
      { id = "ICE_BEAM", pp = 99 },
      { id = "RECOVER", pp = 99 },
    }
    return mon
  end

  game.save.party = { tank() }
  game.save.player = game.save.player or {}
  game.save.player.name = "RED"
  game.save.player.rival = "BLUE"
  Flags.set(game.save, "EVENT_CHOSE_SQUIRTLE")

  local function idle(ow)
    return game.stack:top() == ow and not ow.runner:isRunning()
           and #ow.scriptMoves == 0 and not ow.transitioning
  end

  local function mashUntil(cond, label, cap)
    for _ = 1, cap or 800 do
      if cond() then return true end
      if game.stack:top() ~= game.overworld then U.tap(game, "a") end
      U.wait(2)
    end
    U.log("TIMEOUT waiting for " .. label)
    return false
  end

  local function rivalNpc()
    local ow = game.overworld
    for _, npc in ipairs(ow.npcs or {}) do
      if npc.def and npc.def.name and npc.def.name:find("RIVAL") then
        return npc
      end
    end
  end

  -- Fight until the battle state leaves the stack.  Do NOT mash the
  -- post-battle script text -- the caller screenshots that.
  local function winBattle(label)
    local ow = game.overworld
    local sawBattle = false
    for frames = 1, 5000 do
      local top = game.stack:top()
      if top and top.phase then
        sawBattle = true
        if top.phase == "menu" then
          top.menuIndex = 1
        elseif top.phase == "moveSelect" then
          top.moveIndex = 1
        end
        U.tap(game, "a")
        if frames > 2400 and top.onFinish then
          U.log("force-finishing stalled", label)
          top.onFinish("win")
          if game.stack:top() == top then game.stack:pop() end
        end
      elseif sawBattle then
        -- battle popped: either a TextBox or the overworld runner
        return true
      elseif top ~= ow then
        U.tap(game, "a") -- pre-battle dialogue
      end
      U.wait(2)
    end
    U.log("TIMEOUT winBattle", label)
    return false
  end

  -- ---------------------------------------------------------- #154
  -- Route 22 optional post-lab rival: after the fight he must walk
  -- toward Viridian (right / down), not back toward the League.
  Flags.set(game.save, "EVENT_GOT_POKEDEX")
  Flags.clear(game.save, "EVENT_BEAT_BROCK")
  Flags.clear(game.save, "EVENT_BEAT_ROUTE22_RIVAL_1ST_BATTLE")
  Flags.clear(game.save, "EVENT_BEAT_GIOVANNI")
  Flags.clear(game.save, "EVENT_BEAT_ROUTE22_RIVAL_2ND_BATTLE")

  U.teleport(game, "ROUTE_22", 30, 5, "left")
  local ow = game.overworld
  U.shot(game, DIR .. "/r22_0_before.png")
  U.hold(game, "left", 20)

  mashUntil(function()
    return ow.runner:isRunning() or game.stack:top() ~= ow
  end, "route22 ambush", 200)
  U.shot(game, DIR .. "/r22_1_ambush.png")
  mashUntil(function() return game.stack:top() ~= ow end, "route22 battle", 800)
  winBattle("route22")

  local sawExit, exitFacing, exitX, exitY = false, nil, nil, nil
  for _ = 1, 600 do
    if game.stack:top() ~= ow then U.tap(game, "a") end
    local r = rivalNpc()
    if r and game.save.flags.EVENT_BEAT_ROUTE22_RIVAL_1ST_BATTLE then
      if (r.facing == "right" or r.facing == "down" or r.cellX > 28)
         and not sawExit then
        sawExit = true
        exitFacing, exitX, exitY = r.facing, r.cellX, r.cellY
        U.shot(game, DIR .. "/r22_2_exit.png")
        U.log("r22 exit:", exitFacing, exitX, exitY)
      elseif sawExit and (r.facing == "down" or r.cellY > 5) then
        U.shot(game, DIR .. "/r22_3_exit_mid.png")
        U.log("r22 exit mid:", r.facing, r.cellX, r.cellY)
        break
      end
    end
    if idle(ow) and game.save.flags.EVENT_BEAT_ROUTE22_RIVAL_1ST_BATTLE then
      break
    end
    U.wait(2)
  end
  mashUntil(function() return idle(ow) end, "route22 done", 800)
  U.shot(game, DIR .. "/r22_4_done.png")
  U.log("r22 beat:", tostring(game.save.flags.EVENT_BEAT_ROUTE22_RIVAL_1ST_BATTLE),
        "exitFacing:", tostring(exitFacing))

  -- ---------------------------------------------------------- #168
  -- Nugget Bridge: Bill dialogue, then walk into Cerulean (south).
  Flags.clear(game.save, "EVENT_BEAT_CERULEAN_RIVAL")
  game.save.party = { tank() }

  U.teleport(game, "CERULEAN_CITY", 20, 7, "up")
  ow = game.overworld
  U.shot(game, DIR .. "/cer_0_before.png")
  U.hold(game, "up", 20)

  mashUntil(function()
    return ow.runner:isRunning() or game.stack:top() ~= ow
  end, "cerulean ambush", 200)
  U.shot(game, DIR .. "/cer_1_ambush.png")
  mashUntil(function() return game.stack:top() ~= ow end, "cerulean battle", 800)
  winBattle("cerulean")

  local function boxText(top)
    if not top or type(top.pages) ~= "table" then return "" end
    local parts = {}
    for _, page in ipairs(top.pages) do
      if type(page) == "table" then
        for _, line in ipairs(page) do parts[#parts + 1] = tostring(line) end
      end
    end
    return table.concat(parts, " ")
  end

  local billShot, exitShot, lastBox, postBoxes = false, false, nil, 0
  for _ = 1, 2000 do
    local top = game.stack:top()
    if top ~= ow then
      local t = boxText(top)
      if game.save.flags.EVENT_BEAT_CERULEAN_RIVAL and t ~= "" and top ~= lastBox then
        lastBox = top
        postBoxes = postBoxes + 1
        U.log("post-battle box", postBoxes, t:sub(1, 80))
        -- Bill line is the second post-flag text (after DefeatedText)
        if not billShot and (t:find("BILL") or t:find("Storage")
            or t:find("invented") or t:find("MANIAC") or t:find("pages")
            or t:find("guess what") or postBoxes >= 2) then
          billShot = true
          for _ = 1, 30 do U.wait(2); U.tap(game, "a") end -- advance into Bill body
          U.wait(20)
          U.shot(game, DIR .. "/cer_2_bill.png")
          U.log("bill text:", boxText(game.stack:top()):sub(1, 160))
        end
      end
      U.tap(game, "a")
    elseif game.save.flags.EVENT_BEAT_CERULEAN_RIVAL then
      local r = rivalNpc()
      if r and r.cellY and r.cellY >= 6 and r.facing == "down" and not exitShot then
        exitShot = true
        U.shot(game, DIR .. "/cer_3_exit.png")
        U.log("cer exit:", r.facing, r.cellX, r.cellY)
      end
      if idle(ow) then break end
    end
    U.wait(2)
  end
  mashUntil(function() return idle(ow) end, "cerulean done", 800)
  U.shot(game, DIR .. "/cer_4_done.png")
  U.log("cer beat:", tostring(game.save.flags.EVENT_BEAT_CERULEAN_RIVAL),
        "billShot:", tostring(billShot), "exitShot:", tostring(exitShot))

  Flags.clear(game.save, "EVENT_BEAT_CERULEAN_RIVAL")
  game.save.party = { tank() }

  U.teleport(game, "CERULEAN_CITY", 21, 7, "up")
  ow = game.overworld
  U.shot(game, DIR .. "/cer21_0_before.png")
  U.hold(game, "up", 20)

  local firstX, firstY, spawnShot = nil, nil, false
  local path, lastCell = {}, nil
  local keptSprite, wipeShot = nil, false
  for _ = 1, 1200 do
    local r = rivalNpc()
    if r and r.cellX then
      if not firstX then
        firstX, firstY = r.cellX, r.cellY
        U.log("cer21 rival first visible at", firstX, firstY)
      end
      local cell = r.cellX .. "," .. r.cellY
      if cell ~= lastCell then
        lastCell = cell
        path[#path + 1] = cell
      end
      if not spawnShot then
        spawnShot = true
        U.shot(game, DIR .. "/cer21_1_spawn.png")
      end
    end
    if ow.battleOamKeep ~= nil and not keptSprite then
      keptSprite = ow.battleOamKeep
      U.log("cer21 battleOamKeep:",
            tostring(keptSprite and keptSprite.def and keptSprite.def.name))
    end
    local wipe = game.renderer and game.renderer.battleWipe
    if wipe and wipe.prog and wipe.prog > 0.2 and wipe.prog < 0.8
       and not wipeShot then
      wipeShot = true
      U.shot(game, DIR .. "/cer21_2_wipe.png")
    end
    local top = game.stack:top()
    if top ~= ow then
      if top.phase then break end
      U.tap(game, "a") -- advance the pre-battle box
    end
    U.wait(1)
  end
  U.log("cer21 approach path:", table.concat(path, " -> "))
  U.log(firstX == 21 and "PASS #2149 rival spawns in the player's column"
        or ("FAIL #2149 rival first seen at x=" .. tostring(firstX)))
  U.log(#path <= 4 and "PASS #2149 approach is three straight steps"
        or ("FAIL #2149 approach took " .. (#path - 1) .. " steps"))
  U.log(keptSprite and keptSprite ~= false
        and "PASS #2150 the rival's OAM block survives the wipe"
        or "FAIL #2150 battleOamKeep was false, the rival is culled")
  U.log(wipeShot and "wipe frame captured" or "no wipe frame captured")

  winBattle("cerulean21")
  mashUntil(function() return idle(ow) end, "cerulean21 done", 2000)
  U.shot(game, DIR .. "/cer21_3_done.png")
end
