local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_battle_safari"

local SAFARI_MAP = "FR_SAFARI_ZONE_CENTER"
-- pokefirered/include/constants/flags.h:1327
local FLAG_SYS_SAFARI_MODE = 0x800

return function(game)
  local fails = 0
  local function result(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then fails = fails + 1 end
    return ok
  end
  local function finish()
    if fails == 0 then
      print("PASS battle_safari")
      love.event.quit(0)
    else
      print("FAIL battle_safari failures=" .. fails)
      love.event.quit(1)
    end
  end

  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Collision = require("src.core.game3.collision")
  local Encounters = require("src.core.game3.encounters")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Battle = require("src.core.game3.battle")
  local Ui = require("src.core.game3.battle.ui")
  local Rules = require("src.core.game3.battle.rules")
  local Rng = require("src.core.game3.rng")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end
  session.party = {}
  Party.giveMon(session, 6, 40)

  -- pokefirered/src/safari_zone.c:27
  Flags.setFlag(Space.store, Space.vm and Space.vm.ctx, FLAG_SYS_SAFARI_MODE, true)
  session.safari = { active = true, balls = Rules.safari.BALLS, steps = Rules.safari.STEPS }

  local function placeAt(mapId, x, y, facing)
    Map.load(nil, game, mapId, { x = x, y = y, facing = facing or "down" })
    if game.session then
      game.session.x, game.session.y, game.session.facing = x, y, facing or "down"
    end
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing or "down"
    U.wait(60)
  end

  -- pokefirered/src/wild_encounter.c:712 TILE_ENCOUNTER_LAND
  local function grassy(cx, cy)
    if Encounters.encounterTypeAt(cx, cy) ~= 1 then return false end
    return Collision.isWalkable(cx, cy) and Collision.canEnter(game, cx, cy, {}) ~= false
  end

  local function openCell()
    local layout = Map._def and Map._def.midLayout
    if not layout then return nil end
    local best, bestScore = nil, -1
    for cy = 3, layout.height - 4 do
      for cx = 3, layout.width - 4 do
        if grassy(cx, cy) then
          local score = 0
          for dy = -2, 2 do
            for dx = -2, 2 do
              if grassy(cx + dx, cy + dy) then score = score + 1 end
            end
          end
          if score > bestScore then best, bestScore = { cx, cy }, score end
        end
      end
    end
    if best and bestScore >= 9 then return best[1], best[2], bestScore end
    return nil
  end

  local OPPOSITE = { right = "left", left = "right", up = "down", down = "up" }

  local function patrol(maxSteps, dir)
    local steps, stuck = 0, 0
    local d = dir
    while steps < maxSteps and stuck < 8 do
      if Battle.isActive and Battle.isActive() then return true, steps end
      local bx, by = Player.cellX, Player.cellY
      U.hold(game, d, 20)
      U.wait(4)
      if Battle.isActive and Battle.isActive() then return true, steps end
      if Map.current ~= SAFARI_MAP then
        U.log("patrol left the map to " .. tostring(Map.current))
        return false, steps
      end
      if Player.cellX ~= bx or Player.cellY ~= by then
        steps = steps + 1
        stuck = 0
      else
        stuck = stuck + 1
      end
      d = OPPOSITE[d]
    end
    return (Battle.isActive and Battle.isActive()) or false, steps
  end

  local function atMenu()
    return Battle.isActive and Battle.isActive()
      and Battle._phase == "command" and Ui._mode == "menu"
  end

  local function waitForMenu(n)
    for _ = 1, n or 600 do
      if atMenu() then return true end
      if not (Battle.isActive and Battle.isActive()) then return false end
      U.tap(game, "a")
      U.wait(6)
    end
    return atMenu()
  end

  local function pick(slot)
    -- pokefirered/src/battle_controller_safari.c:162
    if slot == 2 or slot == 4 then U.tap(game, "right") U.wait(6) end
    if slot == 3 or slot == 4 then U.tap(game, "down") U.wait(6) end
    U.tap(game, "a")
    U.wait(20)
  end

  local function logHas(text)
    for _, t in ipairs(Ui.log() or {}) do
      if tostring(t):find(text, 1, true) then return true end
    end
    return false
  end

  -- pokefirered/src/battle_message.c:376
  local function reaction()
    if logHas("is eating!") then return "eating" end
    if logHas("is angry!") then return "angry" end
    if logHas("is watching") then return "watching" end
    return nil
  end

  local function waitForReaction(maxFrames)
    local i = 0
    while i < (maxFrames or 600) do
      local r = reaction()
      if r then
        U.wait(90)
        return r
      end
      if not (Battle.isActive and Battle.isActive()) then return nil end
      if i % 30 == 0 then U.tap(game, "a") end
      U.wait(1)
      i = i + 1
    end
    return reaction()
  end

  placeAt(SAFARI_MAP, 10, 10, "down")
  local gx, gy, score = openCell()
  if not result(gx ~= nil, SAFARI_MAP .. " has open grass") then return finish() end
  U.log(string.format("grass start (%d,%d) open=%d", gx, gy, score))
  local walkDir = grassy(gx + 1, gy) and "right" or "down"
  placeAt(SAFARI_MAP, gx, gy, walkDir)
  Rng.SeedRng(0x2468)
  Rng.SeedWildEncounterRng(0x2468)
  Encounters.resetRateModifiers()

  local hit, steps = patrol(300, walkDir)
  U.log(string.format("patrol ended map=%s pos=(%d,%d) steps=%d",
    tostring(Map.current), Player.cellX, Player.cellY, steps))
  if not result(hit, "walking the Safari Zone grass started a battle (steps=" .. steps .. ")") then
    return finish()
  end
  U.wait(120)

  local st = Battle.getState()
  result(st and st.safari == true, "the battle is a Safari battle")
  result(st and st.safariState ~= nil, "safari state seeded")
  if st and st.safariState then
    U.log(string.format("safari: balls=%s catchFactor=%s escapeFactor=%s",
      tostring(st.safariState.balls), tostring(st.safariState.catchFactor),
      tostring(st.safariState.escapeFactor)))
  end

  result(waitForMenu(900), "reached the safari command menu")
  result(U.shot(game, DIR .. "/safari_01_menu.png"), "shot the BALL/BAIT/ROCK/RUN menu and ball counter")

  local beforeBait = st.safariState and st.safariState.catchFactor
  Ui._log = {}
  pick(2)
  U.wait(90)
  result(logHas("threw some BAIT"), "BAIT thrown")
  result(st.safariState and st.safariState.catchFactor <= math.floor((beforeBait or 0) / 2) + 3,
    "BAIT lowered the catch factor (" .. tostring(beforeBait) .. " -> "
    .. tostring(st.safariState and st.safariState.catchFactor) .. ")")
  local baitReaction = waitForReaction(900)
  U.log("bait reaction = " .. tostring(baitReaction))
  result(baitReaction ~= nil, "foe reacted after the bait")
  result(U.shot(game, DIR .. "/safari_02_bait.png"), "shot the reaction after the bait")

  if not (Battle.isActive and Battle.isActive()) then
    U.log("battle ended early after the bait")
    return finish()
  end
  result(waitForMenu(900), "menu came back after the bait turn")

  local beforeRock = st.safariState and st.safariState.catchFactor
  Ui._log = {}
  pick(3)
  U.wait(90)
  result(logHas("threw a ROCK"), "ROCK thrown")
  result(st.safariState and st.safariState.catchFactor >= (beforeRock or 0),
    "ROCK raised the catch factor (" .. tostring(beforeRock) .. " -> "
    .. tostring(st.safariState and st.safariState.catchFactor) .. ")")
  local rockReaction = waitForReaction(900)
  U.log("rock reaction = " .. tostring(rockReaction))
  result(rockReaction ~= nil, "foe reacted after the rock")
  result(U.shot(game, DIR .. "/safari_03_angry.png"), "shot the reaction after the rock")

  if not (Battle.isActive and Battle.isActive()) then
    U.log("battle ended early after the rock")
    return finish()
  end
  result(waitForMenu(900), "menu came back after the rock turn")

  local ballsBefore = st.safariState and st.safariState.balls
  Ui._log = {}
  pick(1)
  U.wait(150)
  result(st.safariState and st.safariState.balls == (ballsBefore or 0) - 1,
    "one SAFARI BALL spent (" .. tostring(ballsBefore) .. " -> "
    .. tostring(st.safariState and st.safariState.balls) .. ")")
  result(session.safari.balls == (st.safariState and st.safariState.balls),
    "session ball count follows the battle")
  result(U.shot(game, DIR .. "/safari_04_ball.png"), "shot the SAFARI BALL throw")

  for _ = 1, 400 do
    if not (Battle.isActive and Battle.isActive()) then break end
    if atMenu() then
      pick(4)
    else
      U.tap(game, "a")
      U.wait(8)
    end
  end
  result(not (Battle.isActive and Battle.isActive()), "left the safari battle")

  return finish()
end
