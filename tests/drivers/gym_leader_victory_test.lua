-- Driver: gym-leader post-battle dialogue chain (#164).
-- Invokes checkVictoryRewards for Brock then Misty (same path as a win)
-- and screenshots pages that must include badge-effect + TM explanation
-- text -- not just a synthetic "received badge/TM" stub.
--
--   SHOT_DIR=/tmp/gym164 POKEPORT_DRIVER=tests/drivers/gym_leader_victory_test.lua love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local TextBox = require("src.render.TextBox")
  local OW = require("src.world.OverworldController")

  local function currentPageText()
    local top = game.stack:top()
    if getmetatable(top) ~= TextBox then return "" end
    local page = top.pages and top.pages[top.pageIndex]
    if not page then return "" end
    return table.concat(page, "\n")
  end

  local function mashUntil(cond)
    for _ = 1, 1200 do
      if cond() then return true end
      U.tap(game, "a")
      U.wait(2)
    end
    return false
  end

  local function advancePages(want, shotName)
    U.log(shotName, "waiting for:", want)
    local ok = mashUntil(function()
      local top = game.stack:top()
      if getmetatable(top) ~= TextBox then return false end
      -- only match once the current page has finished typing
      if not (top.waiting or top.done) then return false end
      return currentPageText():find(want, 1, true) ~= nil
    end)
    U.log(shotName, "found:", ok, "page:", currentPageText():gsub("\n", "\\n"))
    U.shot(game, DIR .. "/" .. shotName .. ".png")
    assert(ok, shotName .. " missing dialogue containing: " .. want)
  end

  local function runLeader(mapId, x, y, class, party, shots)
    while game.stack:top() do game.stack:pop() end
    game.save.flags = game.save.flags or {}
    game.save.inventory = game.save.inventory or {}
    game.save.defeatedTrainers = game.save.defeatedTrainers or {}
    game.stack:push(OW, mapId, x, y, "up")
    U.wait(5)
    local ow = game.stack:top()
    U.shot(game, DIR .. "/" .. shots.prefix .. "_0_gym.png")
    -- true: the badge line rode the battle screen on the real path (#1606)
    ow:checkVictoryRewards(class, party, true)
    U.wait(10)
    for _, s in ipairs(shots.pages) do
      advancePages(s.want, shots.prefix .. "_" .. s.name)
    end
    U.log(shots.prefix, "closing box:", mashUntil(function()
      return game.stack:top() == ow
    end))
    U.shot(game, DIR .. "/" .. shots.prefix .. "_done.png")
  end

  game.save.player.name = game.save.player.name or "RED"

  -- The REAL gym path (#1606): the badge line and jingle must ride the
  -- battle it pushes (scripts/PewterGym.asm:117-119).
  while game.stack:top() do game.stack:pop() end
  local Pokemon = require("src.pokemon.Pokemon")
  game.save.party = { Pokemon.new(game.data, "CHARIZARD", 50) }
  game.save.flags = game.save.flags or {}
  game.save.inventory = game.save.inventory or {}
  game.save.defeatedTrainers = game.save.defeatedTrainers or {}
  game.stack:push(OW, "PEWTER_GYM", 4, 3, "up")
  U.wait(5)
  local realOw = game.stack:top()
  local brock
  for _, npc in ipairs(realOw.npcs or {}) do
    if npc.def and npc.def.trainerClass == "OPP_BROCK" then brock = npc end
  end
  assert(brock, "Brock stands in PEWTER_GYM")
  require("data.scripts.gyms").PEWTER_GYM.talk.TEXT_PEWTERGYM_BROCK(
    game, realOw, brock, function() end)
  local battle
  for _ = 1, 600 do
    local top = game.stack:top()
    if top and top.oppClass == "OPP_BROCK" and top.onFinish then
      battle = top
      break
    end
    U.tap(game, "a")
    U.wait(2)
  end
  assert(battle, "the real gym path reaches Brock's BattleState")
  assert(type(battle.endBattleText) == "string" and #battle.endBattleText > 0,
         "the battle carries the armed badge line (#1606)")
  assert(battle.endBattleSound == "Get_Item1",
         "and the badge jingle beside it (sound_level_up, PewterGym.asm)")
  U.shot(game, DIR .. "/brock_real_battle.png")
  U.log("force-finishing Brock's battle to run the reward chain")
  battle.onFinish("win")
  if game.stack:top() == battle then game.stack:pop() end
  U.wait(10)
  -- rewardDialogueShown: the badge line rode the battle screen, so the map
  -- chain opens on the TM prelude, not on a reprint of the badge line
  for _, s in ipairs({
    { want = "Wait!", name = "1_wait" },
    { want = "TM34", name = "2_tm34" },
    { want = "BIDE", name = "3_bide" },
  }) do
    advancePages(s.want, "brock_" .. s.name)
  end
  assert(game.save.flags.EVENT_BEAT_BROCK, "EVENT_BEAT_BROCK")
  assert(game.save.inventory.BOULDERBADGE, "BOULDERBADGE")
  assert((game.save.inventory.TM_BIDE or 0) >= 1, "TM_BIDE")

  -- checkVictoryRewards direct drive, as after a battle whose badge line
  -- rode the battle screen (shownOnBattleScreen = true)
  runLeader("CERULEAN_GYM", 5, 5, "OPP_MISTY", 1, {
    prefix = "misty",
    pages = {
      { want = "CUT", name = "1_cut" },
      { want = "TM11", name = "2_tm11" },
    },
  })
  assert(game.save.flags.EVENT_BEAT_MISTY, "EVENT_BEAT_MISTY")
  assert(game.save.inventory.CASCADEBADGE, "CASCADEBADGE")
  assert((game.save.inventory.TM_BUBBLEBEAM or 0) >= 1, "TM_BUBBLEBEAM")

  U.log("gym_leader_victory_test: ok")
end
