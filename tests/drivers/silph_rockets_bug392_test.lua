-- Manual check that Team Rocket leaves Silph Co and the president keeps talking
-- (#392).  pokered scripts/SilphCo11F.asm: the Giovanni win runs
-- SilphCo11FTeamRocketLeavesScript (HideObject over TOGGLE_SILPH_CO_2F_2..11F_3),
-- and SilphCo11FSilphPresidentText prints .MasterBallDescriptionText on every
-- later talk.  No POKEPORT_SPEED: fast-forward desynchronizes the jingle.
--   SHOT_DIR=/tmp/shots POKEPORT_DRIVER=tests/drivers/silph_rockets_bug392_test.lua POKEPORT_IDENTITY=bug392 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local TextBox = require("src.render.TextBox")
  local BattleState = require("src.battle.BattleState")
  local ScriptRunner = require("src.script.ScriptRunner")
  local mapScripts = require("data.scripts.init")

  -- pokered data/maps/objects/SilphCo11F.asm: president (7,5) STAY DOWN, so
  -- he is read from (6,5) facing right; GIOVANNI (6,9), ROCKET1 (3,16),
  -- ROCKET2 (15,9).  SilphCo11FDefaultScript.PlayerCoordsArray is (6,13) and
  -- (7,12), each stepped onto from the cell below it (teleport ignores
  -- collision, so the stand cell only has to be south of the trigger).
  local PRESIDENT = { x = 7, y = 5 }
  local READ = { x = 6, y = 5, facing = "right" }
  local TRIGGERS = { { stand = { 7, 13 }, cell = { 7, 12 } },
                     { stand = { 6, 14 }, cell = { 6, 13 } } }
  local ELEVENTH = { "SILPHCO11F_GIOVANNI", "SILPHCO11F_ROCKET1",
                     "SILPHCO11F_ROCKET2" }
  -- one floor per shape: 3F is rocket + scientist + an item ball, 5F adds the
  -- rocket-aligned ROCKER, 7F keeps the rival out of the hide list
  local FLOORS = {
    { "SILPH_CO_3F", { 22, 7 },
      gone = { "SILPHCO3F_ROCKET", "SILPHCO3F_SCIENTIST" },
      stays = { "SILPHCO3F_HYPER_POTION", "SILPHCO3F_SILPH_WORKER_M" } },
    { "SILPH_CO_5F", { 13, 10 },
      gone = { "SILPHCO5F_ROCKET1", "SILPHCO5F_SCIENTIST",
               "SILPHCO5F_ROCKER", "SILPHCO5F_ROCKET2" },
      stays = { "SILPHCO5F_CARD_KEY", "SILPHCO5F_SILPH_WORKER_M" } },
    { "SILPH_CO_7F", { 10, 9 },
      gone = { "SILPHCO7F_ROCKET1", "SILPHCO7F_SCIENTIST",
               "SILPHCO7F_ROCKET2", "SILPHCO7F_ROCKET3" },
      stays = { "SILPHCO7F_TM_SWORDS_DANCE", "SILPHCO7F_SILPH_WORKER_M3" } },
  }

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  local function spawned(name)
    for _, n in ipairs(game.overworld and game.overworld.npcs or {}) do
      if n.def and n.def.name == name then return n end
    end
    return nil
  end

  local rows = mapScripts.get("SILPH_CO_11F").talk
                 .TEXT_SILPHCO11F_SILPH_PRESIDENT
  check("the president has a hand-ported talk script", type(rows) == "table")
  if type(rows) == "table" then
    local problems = ScriptRunner.validate(rows)
    check("his script validates: " .. (problems[1] or "no problems"),
          #problems == 0)
  end
  for _, key in ipairs({ "_SilphCo11FSilphPresidentText",
                         "_SilphCo11FSilphPresidentReceivedMasterBallText",
                         "_SilphCo11FSilphPresidentMasterBallDescriptionText" }) do
    local body = game.data.text[key]
    check(key .. " is extracted", type(body) == "string" and body ~= "")
  end

  local vol = game.save.options and game.save.options.sfxVol
  if (vol or 0) == 0 then
    U.log("sfxVol is 0: the key-item jingle will be silent, raise it in OPTION")
  else
    U.log("sfxVol", tostring(vol), "-- the ball arrives on the key-item jingle")
  end

  game.save.party = {
    Pokemon.new(game.data, "CHARIZARD", 70),
    Pokemon.new(game.data, "SNORLAX", 70),
    Pokemon.new(game.data, "LAPRAS", 70),
  }
  game.save.player.name = "bryan"
  game.save.flags.EVENT_BEAT_SILPH_CO_GIOVANNI = nil
  game.save.flags.EVENT_GOT_MASTER_BALL = nil
  game.save.objectToggles = {}

  U.teleport(game, "SILPH_CO_11F", READ.x, READ.y, READ.facing)
  U.wait(10)
  local ow = game.overworld
  for _, name in ipairs(ELEVENTH) do
    check(name .. " is on the floor before the fight", spawned(name) ~= nil)
  end
  U.shot(game, DIR .. "/silph392_0_before.png")

  local function facingThePresident()
    local o = game.overworld
    local fx, fy = o.player:facingCell()
    return o:npcAtCell(fx, fy) == spawned("SILPHCO11F_SILPH_PRESIDENT")
  end

  if not facingThePresident() then
    -- a map edit moved him: stand on any free walkable neighbour.
    -- {dx, dy, facing} is the offset from the president plus the way back.
    local sides = {
      { 0, 1, "up" }, { 0, -1, "down" }, { 1, 0, "left" }, { -1, 0, "right" },
    }
    for _, s in ipairs(sides) do
      local cx, cy = PRESIDENT.x + s[1], PRESIDENT.y + s[2]
      if ow.map:isWalkableCell(cx, cy) and not ow:npcAtCell(cx, cy) then
        U.log("president moved; standing on", cx, cy, "facing", s[3])
        U.teleport(game, "SILPH_CO_11F", cx, cy, s[3])
        U.wait(10)
        ow = game.overworld
        break
      end
    end
  end
  check("the player is facing the president", facingThePresident())

  local function boxText(top)
    local lines = {}
    for _, page in ipairs(top.pages or {}) do
      for _, line in ipairs(page) do lines[#lines + 1] = line end
    end
    return table.concat(lines, " ")
  end

  -- one whole talk: A to open, then A through every box until the world is back
  local function talk()
    local seen = {}
    U.tap(game, "a")
    U.wait(20)
    for _ = 1, 120 do
      local top = game.stack:top()
      if getmetatable(top) == TextBox then
        local txt = boxText(top)
        if txt ~= "" and seen[#seen] ~= txt then seen[#seen + 1] = txt end
      elseif top == game.overworld then
        break
      end
      U.tap(game, "a")
      U.wait(10)
    end
    return table.concat(seen, " / ")
  end

  local first = talk()
  U.log("first talk reads:", first)
  check("the first talk prints his thank-you", first ~= "")
  check("and hands over the MASTER BALL",
        (game.save.inventory.MASTER_BALL or 0) > 0)
  check("EVENT_GOT_MASTER_BALL is set", game.save.flags.EVENT_GOT_MASTER_BALL == true)

  U.wait(20)
  local second = talk()
  U.log("second talk reads:", second)
  check("the second talk is not silence", second ~= "")
  check("it is the MASTER BALL description",
        second:find("prototype", 1, true) ~= nil)
  check("and no second ball is handed out",
        (game.save.inventory.MASTER_BALL or 0) == 1)
  U.shot(game, DIR .. "/silph392_1_president.png")

  -- the hide pass, floor by floor: this is what a save that beat Giovanni sees
  -- on its next visit, and what the win itself does in one go
  game.save.flags.EVENT_BEAT_SILPH_CO_GIOVANNI = true
  for i, floor in ipairs(FLOORS) do
    local mapId, at = floor[1], floor[2]
    U.teleport(game, mapId, at[1], at[2], "down")
    U.wait(10)
    for _, name in ipairs(floor.gone) do
      check(name .. " left " .. mapId, spawned(name) == nil)
    end
    for _, name in ipairs(floor.stays) do
      check(name .. " is still there", spawned(name) ~= nil)
    end
    local toggles = game.save.objectToggles[mapId] or {}
    check(mapId .. " toggles were written to the save",
          toggles[floor.gone[1]] == false)
    U.shot(game, ("%s/silph392_2_%s.png"):format(DIR, mapId:lower()))
    if i == #FLOORS then
      check("the 7F rival keeps his toggle",
            toggles.SILPHCO7F_RIVAL ~= false)
    end
  end

  -- put the fight back on the table: clear the event, the toggles and the
  -- battle records so the coordinate trigger re-arms
  game.save.flags.EVENT_BEAT_SILPH_CO_GIOVANNI = nil
  game.save.objectToggles = {}
  game.save.defeatedTrainers = {}
  game.save.flags.EVENT_BEAT_SILPH_CO_11F_TRAINER_0 = nil
  game.save.flags.EVENT_BEAT_SILPH_CO_11F_TRAINER_1 = nil

  local fired, cell
  for i, t in ipairs(TRIGGERS) do
    U.teleport(game, "SILPH_CO_11F", t.stand[1], t.stand[2], "up")
    U.wait(10)
    ow = game.overworld
    if i == 1 then
      for _, name in ipairs(ELEVENTH) do
        check(name .. " is back on the floor", spawned(name) ~= nil)
      end
      U.shot(game, DIR .. "/silph392_3_rearmed.png")
    end
    U.hold(game, "up", 24)
    for _ = 1, 300 do
      U.wait(1)
      if getmetatable(game.stack:top()) == BattleState then break end
    end
    if getmetatable(game.stack:top()) == BattleState
       or (ow.player.cellX == t.cell[1] and ow.player.cellY == t.cell[2]) then
      fired, cell = true, t.cell
      break
    end
    U.log(("the step up from (%d,%d) missed the trigger; trying the other pad")
            :format(t.stand[1], t.stand[2]))
  end
  cell = cell or TRIGGERS[1].cell
  check(("stepping onto (%d,%d) started GIOVANNI"):format(cell[1], cell[2]),
        fired == true)
  U.shot(game, DIR .. "/silph392_4_giovanni.png")

  U.log("Win the fight: after the fade GIOVANNI and both ROCKETs, (3,16) and")
  U.log("(15,9), should be gone, and every grunt and lab-coat trainer on")
  U.log("3F/5F/7F with them.  The president at (7,5) has the ball already, so")
  U.log("A on him should describe it again, never an empty beat.")

  while true do
    coroutine.yield()
  end
end
