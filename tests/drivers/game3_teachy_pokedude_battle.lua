local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_teachy_pokedude_battle"

-- pokefirered/include/constants/items.h:438
local ITEM_TEACHY_TV = 366

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS teachy_pokedude_battle")
    love.event.quit(0)
  else
    print("FAIL teachy_pokedude_battle failures=" .. failures)
    love.event.quit(1)
  end
end

return function(game)
  print("PASS driver_started")
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Bag = require("src.core.game3.bag")
  local TeachyTv = require("src.core.game3.teachy_tv")
  local TvUi = require("src.ui.game3.teachy_tv")
  local Battle = require("src.core.game3.battle")
  local Audio = require("src.core.game3.audio")
  local Message = require("src.ui.game3.message")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end
  session.bag = session.bag or Bag.new()
  Bag.add(session.bag, ITEM_TEACHY_TV, 1)
  Bag.add(session.bag, 13, 2)
  local partyBefore = #(session.party or {})
  local fieldSong = Audio._mapSong

  local function songId()
    local c = Audio.currentSong and Audio.currentSong()
    return c and c.id
  end
  local function waitFor(fn, budget)
    for _ = 1, (budget or 900) do
      if fn() then return true end
      U.wait(1)
    end
    return fn() and true or false
  end
  local function tapThrough(fn, budget)
    for _ = 1, (budget or 3000) do
      if fn() then return true end
      if TvUi.waitingForKey() then U.tap(game, "a") end
      U.wait(1)
    end
    return fn() and true or false
  end

  local BattleTransition = require("src.core.game3.battle_transition")
  local BagMenu = require("src.ui.game3.bag_menu")
  local PartyMenu = require("src.ui.game3.party_menu")
  local BattleUi = require("src.core.game3.battle.ui")
  local Stack = require("src.ui.game3.stack")

  local function selectLesson(row)
    if not TvUi.isOpen() then
      TeachyTv.show(session, session.bag)
      U.wait(40)
    end
    local Fade = require("src.ui.game3.fade")
    waitFor(function() return TvUi.state == "list" and not Fade.isActive() end, 200)
    for _ = 1, 8 do
      if TvUi.cursor == row then break end
      U.tap(game, TvUi.cursor < row and "down" or "up")
      U.wait(10)
    end
    U.tap(game, "a")
    U.wait(10)
  end

  -- pokefirered/src/teachy_tv.c:1189 TeachyTvPreBattleAnimAndSetBattleCallback
  local function watchTransition(label, wantId, shotAt)
    if not result(tapThrough(function() return BattleTransition.isActive() or Battle.isActive() end, 4000),
        label .. ": the pre-battle transition started") then
      return false
    end
    result(BattleTransition._transitionId == wantId,
      label .. ": transition " .. wantId .. ", got " .. tostring(BattleTransition._transitionId))
    result(BattleTransition._opts and BattleTransition._opts.overUi == true, label .. ": it draws on the UI plane")
    local top = Stack.top()
    result(top and top.id == "teachy_tv", label .. ": over the TV screen, top=" .. tostring(top and top.id))
    local shot = false
    for _ = 1, 600 do
      if not BattleTransition.isActive() then break end
      local fx = BattleTransition._fx
      if not shot and shotAt and BattleTransition._phase == "main" and fx and shotAt(fx) then
        shot = true
        U.still(game, DIR .. "/pokedude_" .. label .. "_transition_mid.png")
      end
      U.wait(1)
    end
    if shotAt then result(shot, label .. ": caught the transition mid-way") end
    return true
  end

  local function runBattle(label, hooks)
    if not result(waitFor(function() return Battle.isActive() end, 900), label .. ": the POKé DUDE battle started") then
      return nil
    end
    local st = Battle.getState()
    result(st.pokedude == true, label .. ": BATTLE_TYPE_POKEDUDE")
    for _ = 1, 12000 do
      if not Battle.isActive() then break end
      if hooks and hooks.frame and hooks.frame(st) == "stop" then return st end
      if Message.isOpen() and Message.frameKind() == "voiceover" and Message.isWaiting() then
        if hooks and hooks.voiceover then hooks.voiceover(st) end
        U.tap(game, "a")
      elseif PartyMenu.isOpen() and PartyMenu.mode == "message" then
        if hooks and hooks.partyMessage then hooks.partyMessage(st) end
        U.tap(game, "a")
      end
      U.wait(1)
    end
    return st
  end

  local function afterWin(label, st, want, voCount)
    result(not Battle.isActive(), label .. ": the battle ended")
    result(st.result == want, label .. ": result " .. want .. ", got " .. tostring(st.result))
    print("[driver] " .. label .. " voiceovers: " .. table.concat(st.pd.log, ","))
    result(#st.pd.log == voCount, label .. ": " .. voCount .. " voiceovers, got " .. #st.pd.log)
    result(#(session.party or {}) == partyBefore, label .. ": the player's party is untouched")
    result(Bag.get(session.bag, 13) == 2 and Bag.get(session.bag, 14) == 0, label .. ": the player's bag is back")
    result(waitFor(function() return TvUi.phase == "outro" end, 400), label .. ": the lesson resumed at its outro")
    result(songId() == 272, label .. ": MUS_FOLLOW_ME after the battle, playing " .. tostring(songId()))
    result(tapThrough(function() return TvUi.state == "list" end, 3000), label .. ": the lesson ran back to the list")
  end

  -- pokefirered/src/teachy_tv.c:272 sBattleScript
  selectLesson(1)
  result(TeachyTv.whichScript(session) == TeachyTv.SCRIPT.BATTLE, "the battle lesson started")
  if not watchTransition("battle", BattleTransition.ID.WHITE_BARS_FADE,
      function(fx) return fx.state == 2 and (fx.barLevel1 and (fx.barLevel1[3] or 0) >= 6) end) then
    return finish()
  end
  local victorySong, shotVo, shotMenu = false, false, false
  local st = runBattle("battle", {
    frame = function(s)
      if not shotMenu and s.pd.step == "action" and s.pd.battlers[0].timer > 40 then
        shotMenu = true
        U.still(game, DIR .. "/pokedude_battle_action_menu.png")
      end
      -- pokefirered/src/battle_controller_pokedude.c:2573 PlayBGM(MUS_VICTORY_WILD)
      if songId() == 311 then victorySong = true end
    end,
    voiceover = function()
      if not shotVo then
        shotVo = true
        U.still(game, DIR .. "/pokedude_battle_voiceover.png")
      end
    end,
  })
  if not st then return finish() end
  result(victorySong, "battle: MUS_VICTORY_WILD played after the EXP voiceover")
  afterWin("battle", st, "win", 4)
  U.wait(30)
  U.shot(game, DIR .. "/pokedude_battle_back_on_list.png")
  result(TeachyTv.hasWatched(session, TeachyTv.SCRIPT.BATTLE), "the battle lesson is watched")

  -- pokefirered/src/item_menu.c:2316 Task_Bag_TeachyTvStatus
  selectLesson(2)
  result(TeachyTv.whichScript(session) == TeachyTv.SCRIPT.STATUS, "the status lesson started")
  if not watchTransition("status", BattleTransition.ID.SLICE,
      function(fx) return (fx.sl1 or 0) >= 60 end) then
    return finish()
  end
  local shotLit, shotBag, shotCured, curedText, sawBag = false, false, false, nil, false
  st = runBattle("status", {
    frame = function(s)
      if s.pd.menu == "bag" then sawBag = true end
      if not shotBag and s.pd.menu == "bag" and BagMenu.isOpen() and BagMenu.mode == "action" then
        shotBag = true
        local row = BagMenu.list()[BagMenu.cursor]
        result(row and tonumber(row.id) == 14 or row and row.id == "ANTIDOTE",
          "status: the POKé DUDE picked ANTIDOTE, row=" .. tostring(row and row.id))
        U.still(game, DIR .. "/pokedude_status_bag_antidote.png")
      end
    end,
    voiceover = function()
      if not shotLit and BattleUi.litHealthboxShown() then
        shotLit = true
        U.still(game, DIR .. "/pokedude_status_healthbox_lit.png")
      end
    end,
    partyMessage = function()
      if not shotCured then
        shotCured = true
        curedText = PartyMenu._messageText
        U.still(game, DIR .. "/pokedude_status_party_cured.png")
      end
    end,
  })
  if not st then return finish() end
  result(sawBag and shotBag, "status: the scripted bag opened on ANTIDOTE")
  result(shotLit, "status: voiceover 2 keeps the player healthbox lit")
  result(shotCured and tostring(curedText):find("poison") ~= nil,
    "status: the party menu printed the cure text: " .. tostring(curedText))
  local usedLine = false
  for _, t in ipairs(BattleUi.log() or {}) do
    if tostring(t):find("ANTIDOTE") then usedLine = true end
  end
  result(not usedLine, "status: the battle prints no 'used ANTIDOTE' line (battle_scripts_2.s:130)")
  afterWin("status", st, "win", 4)

  -- pokefirered/src/party_menu.c:2020 Task_PartyMenu_Pokedude
  selectLesson(3)
  result(TeachyTv.whichScript(session) == TeachyTv.SCRIPT.MATCHUPS, "the matchups lesson started")
  if not watchTransition("matchups", BattleTransition.ID.SLICE,
      function(fx) return (fx.sl1 or 0) >= 120 end) then
    return finish()
  end
  local shotShift = false
  st = runBattle("matchups", {
    frame = function(s)
      if not shotShift and s.pd.menu == "party" and PartyMenu.isOpen() and PartyMenu.mode == "action" then
        shotShift = true
        result(PartyMenu.ACTIONS[1] == "SHIFT" and PartyMenu.cursor == 2,
          "matchups: the selection window is up on BUTTERFREE")
        U.still(game, DIR .. "/pokedude_matchups_party_shift.png")
      end
    end,
  })
  if not st then return finish() end
  result(shotShift, "matchups: the scripted party menu shifted")
  result(st.player.mon.species == 12, "matchups: BUTTERFREE finished the battle")
  afterWin("matchups", st, "win", 7)

  -- pokefirered/src/item_menu.c:2262 Task_Bag_TeachyTvCatching
  selectLesson(4)
  result(TeachyTv.whichScript(session) == TeachyTv.SCRIPT.CATCHING, "the catching lesson started")
  if not watchTransition("catching", BattleTransition.ID.SLICE,
      function(fx) return (fx.sl1 or 0) >= 60 end) then
    return finish()
  end
  local shotBalls = false
  st = runBattle("catching", {
    frame = function(s)
      if not shotBalls and s.pd.menu == "bag" and BagMenu.isOpen() and BagMenu.mode == "action" then
        shotBalls = true
        result(BagMenu.currentPocket() == "POKE_BALLS" and BagMenu.cursor == 1,
          "catching: A on POKé BALL in the POKé BALLS pocket")
        U.still(game, DIR .. "/pokedude_catching_bag_pokeball.png")
      end
    end,
  })
  if not st then return finish() end
  result(shotBalls, "catching: the scripted bag reached the POKé BALL")
  afterWin("catching", st, "catch", 5)

  -- pokefirered/src/item_menu.c:2192 Task_BButtonInterruptTeachyTv
  selectLesson(2)
  if not watchTransition("status_b", BattleTransition.ID.SLICE, nil) then
    return finish()
  end
  st = runBattle("status_b", {
    frame = function(s)
      if s.pd.menu == "bag" and BagMenu.isOpen() and not BagMenu._open then
        U.tap(game, "b")
        return "stop"
      end
    end,
  })
  if not st then return finish() end
  result(waitFor(function() return not Battle.isActive() end, 400), "status_b: B in the scripted bag ended the battle")
  result(st.result == "draw", "status_b: as a draw, result=" .. tostring(st.result))
  result(waitFor(function() return TvUi.state == "list" end, 400), "status_b: the TV went back to its lesson list")
  result(Bag.get(session.bag, 13) == 2 and Bag.get(session.bag, 14) == 0, "status_b: the bag is the player's again")

  -- pokefirered/src/battle_main.c:1455
  selectLesson(2)
  if not watchTransition("status_hold", BattleTransition.ID.SLICE, nil) then
    return finish()
  end
  if not result(waitFor(function() return Battle.isActive() end, 900), "status_hold: the battle started") then
    return finish()
  end
  local st2 = Battle.getState()
  result(st2.player.mon.species == 19 and st2.enemy.mon.species == 43, "RATTATA vs ODDISH")
  waitFor(function() return st2.pd.step == "action" end, 1200)
  U.hold(game, "b", 4)
  game.input.state.b = false
  result(waitFor(function() return not Battle.isActive() end, 400), "holding B ended the battle")
  result(st2.result == "draw", "as a draw, result=" .. tostring(st2.result))
  result(waitFor(function() return TvUi.state == "list" end, 400), "the TV went back to its lesson list")
  result(TeachyTv.hasWatched(session, TeachyTv.SCRIPT.STATUS), "the status lesson stays watched from its full run")
  result(#(session.party or {}) == partyBefore, "the party is untouched after the B quit")
  result(Bag.get(session.bag, 13) == 2 and Bag.get(session.bag, 14) == 0, "the bag is the player's again")
  result(songId() == 346, "MUS_TEACHY_TV_MENU on the list, playing " .. tostring(songId()))
  U.wait(30)
  U.shot(game, DIR .. "/pokedude_b_quit_list.png")

  U.tap(game, "b")
  result(waitFor(function() return not TvUi.isOpen() end, 120), "B closed the TV")
  result(songId() == fieldSong, "the field song is back, playing " .. tostring(songId()))
  finish()
end
