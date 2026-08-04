-- The Yellow Viridian catch tutorial has to FAIL its throw (#636).
-- pokeyellow scripts/ViridianCity.asm:168 (ViridianCityCheckWaitingOldMan)
-- starts the demo from (19,9); ItemUseBall's .oldManBattle branch reads
-- EVENT_INITIAL_CATCH_TRAINING and stores anim data $63, so the ball shakes
-- three times and breaks open, and only then does the losing-my-touch line
-- make sense.  No POKEPORT_SPEED here: the shakes and the ball sounds run on
-- the real-time audio clock and fast-forward pulls them apart.
--   POKEPORT_DRIVER=tests/drivers/oldman_yellow_bug636_test.lua \
--     POKEPORT_VERSION=yellow POKEPORT_IDENTITY=bug636 SHOT_DIR=/tmp/shots love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local mapScripts = require("data.scripts.init")
  local GameVersion = require("src.core.GameVersion")
  local BattleState = require("src.battle.BattleState")
  local TextBox = require("src.render.TextBox")
  local Pokemon = require("src.pokemon.Pokemon")

  local MAP = "VIRIDIAN_CITY"
  local OLD_MAN2 = "VIRIDIANCITY_OLD_MAN2"
  local TEXT = "TEXT_VIRIDIANCITY_OLD_MAN2"
  local SHOT_DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  -- ../pokeyellow/data/maps/objects/ViridianCity.asm:37 puts OLD_MAN2 on
  -- (18,9); the trigger cell is the gap east of him, (19,9).  Each candidate
  -- is {stand x, stand y, direction that walks into (19,9)}.
  local TRIGGER = { x = 19, y = 9 }
  local APPROACHES = {
    { 19, 10, "up" }, { 19, 8, "down" }, { 20, 9, "left" },
  }

  local fails = 0
  local function check(label, ok)
    if not ok then fails = fails + 1 end
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  local function flat(s) return (tostring(s):gsub("[\n\v\f]", " / ")) end

  -- ---- what the eye cannot see -------------------------------------------
  check("booted on Yellow (the fail branch is Yellow-only)",
        GameVersion.get() == "yellow")

  local hooks = mapScripts.get(MAP)
  check(MAP .. " has a map-script table", type(hooks) == "table")
  check("the (19,9) step hook survived the base-script merge",
        type(hooks) == "table" and type(hooks.onStep) == "function")
  check(TEXT .. " has a talk handler",
        type(hooks) == "table" and type(hooks.talk) == "table"
        and type(hooks.talk[TEXT]) == "function")

  -- a species constant that no longer resolves builds a nameless battler and
  -- looks exactly like the demo never starting
  local om = game.data.field.oldManBattle
  check("field.oldManBattle exists", type(om) == "table")
  check("it is Yellow's RATTATA, not Red's WEEDLE",
        type(om) == "table" and om.species == "RATTATA")
  check("that species resolves in the pokemon table",
        type(om) == "table" and game.data.pokemon[om.species] ~= nil)

  -- the flag itself, off a throwaway battle that is never pushed
  local probe = BattleState.newWild(game, (om and om.species) or "RATTATA",
                                    (om and om.level) or 5)
  probe:makeOldManDemo(nil, true)
  check("makeOldManDemo(name, true) sets demoFails", probe.demoFails == true)
  probe:makeOldManDemo(nil, false)
  check("and without it the demo still catches, for Red and the reruns",
        probe.demoFails == false)

  local miss = game.data.text._ItemUseBallText04
  check("_ItemUseBallText04 (three shakes, then free) resolves",
        type(miss) == "string" and miss ~= "")
  local touch = game.data.text._ViridianCityOldManLosingMyTouchText
  check("_ViridianCityOldManLosingMyTouchText resolves",
        type(touch) == "string" and touch ~= "")
  check("it really is the losing-my-touch line",
        type(touch) == "string" and touch:find("losing", 1, true) ~= nil)
  if type(miss) == "string" then U.log("breakout line reads:", flat(miss)) end
  if type(touch) == "string" then U.log("old man then says:", flat(touch)) end

  local sfx = (game.save.options or {}).sfxVol
  if sfx == 0 then
    U.log("FAIL sfx volume is 0, so the ball wobbles and the break will be silent")
  else
    U.log("sfx volume is", tostring(sfx), "-- the ball should be audible")
  end

  -- ---- put the tutorial back to its untouched state -----------------------
  game.save.party = {
    Pokemon.new(game.data, "PIKACHU", 6),
  }
  game.save.flags = game.save.flags or {}
  game.save.flags.EVENT_GOT_POKEDEX = true
  game.save.flags.EVENT_COMPLETED_CATCH_TRAINING = nil
  game.save.objectToggles = {}
  local ownedBefore = 0
  for _ in pairs((game.save.pokedex and game.save.pokedex.owned) or {}) do
    ownedBefore = ownedBefore + 1
  end
  local partyBefore = #game.save.party

  local function npcNamed(name)
    local ow = game.overworld
    for _, n in ipairs((ow and ow.npcs) or {}) do
      if n.def and n.def.name == name then return n end
    end
    return nil
  end

  -- walk into (19,9) from the first free neighbour, so a later map edit that
  -- walls off the south approach degrades instead of pressing into a fence
  local stand
  U.teleport(game, MAP, APPROACHES[1][1], APPROACHES[1][2], "up")
  U.wait(20)
  local ow = game.overworld
  check("the tutorial old man is on the map", npcNamed(OLD_MAN2) ~= nil)
  for _, a in ipairs(APPROACHES) do
    if ow and ow.map:isWalkableCell(a[1], a[2]) and not ow:npcAtCell(a[1], a[2]) then
      stand = a
      break
    end
  end
  check(("a free cell next to (%d,%d) to walk in from")
          :format(TRIGGER.x, TRIGGER.y), stand ~= nil)
  stand = stand or APPROACHES[1]
  if stand ~= APPROACHES[1] then
    U.log(("south approach blocked, walking in from (%d,%d)"):format(stand[1], stand[2]))
    U.teleport(game, MAP, stand[1], stand[2], stand[3])
    U.wait(15)
  end

  -- ---- step on the trigger and let the demo run ---------------------------
  local function topIsBattle()
    local top = game.stack:top()
    return (top and top.demo and top.demoName) and top or nil
  end

  local battle
  for _ = 1, 40 do
    U.hold(game, stand[3], 6)
    U.wait(4)
    battle = topIsBattle()
    if battle then break end
    -- the apology speech comes first; page through it to reach the battle
    if getmetatable(game.stack:top()) == TextBox then
      U.tap(game, "a")
      U.wait(6)
    end
  end
  if not battle then
    for _ = 1, 200 do
      battle = topIsBattle()
      if battle then break end
      if getmetatable(game.stack:top()) == TextBox then U.tap(game, "a") end
      U.wait(6)
    end
  end
  check("stepping onto (19,9) opened the catch demo", battle ~= nil)
  check("the demo is the failing one (#636)",
        battle ~= nil and battle.demoFails == true)
  if battle then
    U.log("demo opponent is", tostring(battle.enemy and battle.enemy.name))
  end

  -- Advance only pages that have finished typing (msgPrompt / msgWaiting are
  -- the same holds the player would clear by hand), so the toss animation and
  -- its sounds play at their own speed.
  local sawMiss, sawCaught, shot = false, false, false
  if battle then
    for _ = 1, 3000 do
      if game.stack:top() ~= battle then break end
      local cur = battle.current
      local line = cur and cur.text
      if type(line) == "string" then
        if miss and line == miss then sawMiss = true end
        if line:find("caught", 1, true) then sawCaught = true end
      end
      if battle.msgPrompt and sawMiss and not shot then
        shot = U.shot(game, SHOT_DIR .. "/bug636_ball_broke_open.png")
        if shot then U.log("captured", SHOT_DIR .. "/bug636_ball_broke_open.png") end
      end
      if battle.msgPrompt or battle.msgWaiting then
        U.tap(game, "a")
      end
      U.wait(2)
    end
  end
  check("the ball broke open and printed the three-shake line", sawMiss)
  check("nothing was caught", not sawCaught)

  -- ---- the line that only follows a failed throw --------------------------
  local box
  for _ = 1, 400 do
    local top = game.stack:top()
    if getmetatable(top) == TextBox then box = top break end
    U.wait(4)
  end
  check("the old man speaks again after the battle", box ~= nil)
  local shown = {}
  for _, page in ipairs((box and box.pages) or {}) do
    for _, l in ipairs(page) do shown[#shown + 1] = l end
  end
  local joined = table.concat(shown, " / ")
  if box then U.log("his box reads:", joined) end
  check("he says he must be losing his touch",
        joined:find("losing", 1, true) ~= nil)
  if box then
    if U.shot(game, SHOT_DIR .. "/bug636_losing_my_touch.png") then
      U.log("captured", SHOT_DIR .. "/bug636_losing_my_touch.png")
    end
  end

  local ownedAfter = 0
  for _ in pairs((game.save.pokedex and game.save.pokedex.owned) or {}) do
    ownedAfter = ownedAfter + 1
  end
  check("the demo added nothing to the party", #game.save.party == partyBefore)
  check("and nothing to the dex's owned list", ownedAfter == ownedBefore)

  -- ---- rewind so it can be watched again ----------------------------------
  game.save.flags.EVENT_COMPLETED_CATCH_TRAINING = nil
  game.save.objectToggles = {}
  U.teleport(game, MAP, stand[1], stand[2], stand[3])
  U.wait(15)

  if fails > 0 then
    U.log(fails, "check(s) above say FAIL; the screen is not worth watching yet.")
  end
  U.log(("ran the tutorial once and rewound it: you are on (%d,%d), so")
          :format(stand[1], stand[2]))
  U.log("holding " .. stand[3] .. " into (19,9) starts the demo again. The ball")
  U.log("should wobble three times and pop open, then he blames his touch. The")
  U.log("near miss to watch for is three wobbles, the caught jingle, and the")
  U.log("same line anyway.")

  while true do
    coroutine.yield()
  end
end
