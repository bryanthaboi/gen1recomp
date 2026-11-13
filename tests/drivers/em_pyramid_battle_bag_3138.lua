local U = require("tests.drivers.util")
local S = require("tests.drivers.em_story_util")

return function(game)
  local d = S.new("em_pyramid_battle_bag_3138", "/tmp/em_pyramid_battle_bag_3138")
  local check, note = d.check, d.note
  local function shot(name) d.shot(game, name) end
  local function finish() return d.finish() end

  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not check(game.boot ~= nil, "boot reached") then return finish() end
  game:_handleBootAction({ action = "new_game", name = "BRENDAN", gender = 0 })
  U.wait(240)
  S.settle(game)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Natives = require("src.core.game3.scripting.natives")
  local Battle = require("src.core.game3.battle")
  local BattleUi = require("src.core.game3.battle.ui")
  local Encounters = require("src.core.game3.encounters")
  local PartyMenu = require("src.ui.game3.party_menu")
  local PBag = require("src.ui.game3.rse.pyramid_bag")
  local session = Runtime.getSession()
  if not check(session ~= nil, "field session exists") then return finish() end
  Natives.ensureBound(session)
  require("tests.drivers.em_f4_hooks").install()
  local Py = require("src.core.game3.rse.frontier.pyramid")
  local Util = require("src.core.game3.rse.frontier.util")
  local D = require("src.core.game3.rse.frontier.trainers")
  session.repelSteps = 0
  Encounters.onStep = function() return nil end

  local function tough(name, moves)
    local m = D.createMon(S.species(name), 50, 31, 0, tonumber(session.trainerId) or 0, { otName = session.name })
    local ms = {}
    for i, mv in ipairs(moves) do ms[i] = S.move(mv) end
    D.setMoves(m, ms)
    D.setEvs(m, { 252, 252, 6, 0, 0, 0 })
    m.otId, m.otName, m.ot = session.trainerId, session.name, session.name
    return m
  end
  session.party = {
    tough("SPECIES_METAGROSS", { "MOVE_METEOR_MASH", "MOVE_EARTHQUAKE", "MOVE_PSYCHIC", "MOVE_SHADOW_BALL" }),
    tough("SPECIES_SALAMENCE", { "MOVE_DRAGON_CLAW", "MOVE_EARTHQUAKE", "MOVE_FLAMETHROWER", "MOVE_AERIAL_ACE" }),
    tough("SPECIES_SWAMPERT", { "MOVE_SURF", "MOVE_EARTHQUAKE", "MOVE_ICE_BEAM", "MOVE_BRICK_BREAK" }),
  }
  session.party[1].hp = 10

  -- pokeemerald/data/maps/BattleFrontier_BattlePyramidLobby/scripts.inc:106
  S.setVar("VAR_FRONTIER_FACILITY", D.FACILITY.PYRAMID)
  S.setVar("VAR_FRONTIER_BATTLE_MODE", D.MODE.SINGLES)
  local f = Util.frontier(session)
  f.lvlMode = D.LVL.L50
  Py.init(session)
  f.challengeStatus, f.challengePaused = 0, 0
  Py.seedFloor(session)
  S.settle(game)
  local okLoad = pcall(function() Map.load(nil, game, Py.FLOOR_MAP, { x = 8, y = 8, facing = "down" }) end)
  session.x, session.y, session.facing = 8, 8, "down"
  U.wait(30)
  S.settle(game)
  if not check(okLoad and S.mapNow() == Py.FLOOR_MAP and Py.inPyramid(session), "standing on a Pyramid floor") then
    return finish()
  end

  local HYPER, FLUFFY = S.item("ITEM_HYPER_POTION"), S.item("ITEM_FLUFFY_TAIL")
  Py.initBag(session)
  Py.bagAdd(session, FLUFFY, 1)
  check(Py.bagCount(session, HYPER) == 1 and Py.bagCount(session, FLUFFY) == 1,
    "the pyramid bag holds one Hyper Potion and one Fluffy Tail")

  local function waitFor(cond, limit, tapA)
    for i = 1, limit do
      if cond() then return true end
      if tapA and i % 20 == 0 then U.tap(game, "a") else U.wait(1) end
    end
    return cond()
  end
  local function atCommand() return Battle._phase == "command" and BattleUi._mode == "menu" end
  local function bagIdle() return PBag.isOpen() and PBag._st.mode == "list" and PBag._st.fadeDir == 0 end

  local function pickItem(item)
    BattleUi._menuIndex = 2
    U.tap(game, "a")
    if not waitFor(bagIdle, 300) then return false end
    local ids = Py.bagLists(session)
    local idx
    for i, id in ipairs(ids) do if id == item then idx = i - 1 break end end
    if idx == nil then return false end
    Py.bagCursor = { cursor = 0, scroll = 0 }
    for _ = 1, idx do
      U.tap(game, "down")
      U.wait(4)
    end
    U.tap(game, "a")
    if not waitFor(function() return PBag._st.mode == "action" end, 60) then return false end
    return true
  end

  if not check(Py.sweetScentWildEncounter(session) ~= false, "a wild Pyramid battle starts") then return finish() end
  if not check(waitFor(atCommand, 3000, true), "the command menu is reached") then return finish() end
  local st = Battle._st
  check(st and st.pyramid == true, "the battle is a Pyramid battle")
  local lead = st.playerParty[st.player.partyIndex or 1]
  local hp0 = tonumber(lead.hp) or 0
  check(hp0 == 10, "the lead enters at 10 HP (" .. hp0 .. ")")

  if not check(pickItem(HYPER), "the Hyper Potion row opens its USE / CANCEL menu") then return finish() end
  shot("3138_01_pyramid_bag_use_menu")
  U.tap(game, "a")
  -- pokeemerald/src/item_use.c:1001
  if not check(waitFor(function() return PartyMenu.isOpen() end, 300), "USE opens the party menu to pick a target") then
    return finish()
  end
  U.wait(30)
  shot("3138_02_party_target")
  U.tap(game, "a")
  local healed = waitFor(function() return (tonumber(lead.hp) or 0) > hp0 end, 600)
  check(healed, "the Hyper Potion heals the chosen mon (" .. hp0 .. " -> " .. tostring(lead.hp) .. ")")
  U.wait(40)
  shot("3138_03_party_healed")
  local hpHealed = tonumber(lead.hp) or 0
  check(Py.bagCount(session, HYPER) == 0, "the Hyper Potion leaves the pyramid bag")
  local back = waitFor(function() return not PBag.isOpen() and not PartyMenu.isOpen() and atCommand() end, 3000, true)
  check(back, "the turn plays out and the command menu returns")
  check(hpHealed >= math.min(tonumber(lead.maxHp) or 0, hp0 + 200) or hpHealed == tonumber(lead.maxHp),
    "the heal is a full Hyper Potion (" .. hpHealed .. "/" .. tostring(lead.maxHp) .. ")")
  U.wait(20)
  shot("3138_04_back_in_battle")

  if Battle.isActive() and atCommand() then
    if check(pickItem(FLUFFY), "the Fluffy Tail row opens its USE / CANCEL menu") then
      U.tap(game, "a")
      -- pokeemerald/src/item_use.c:1035
      local over = waitFor(function() return not Battle.isActive() end, 3000, true)
      check(over, "the Fluffy Tail ends the wild battle")
      check(st.result == "run", "the battle result is a flee (" .. tostring(st.result) .. ")")
      check(Py.bagCount(session, FLUFFY) == 0, "the Fluffy Tail leaves the pyramid bag")
    end
  else
    check(false, "the battle is still at the command menu for the Fluffy Tail")
  end
  note("lead hp at end " .. tostring(lead.hp))
  U.wait(30)
  finish()
end
