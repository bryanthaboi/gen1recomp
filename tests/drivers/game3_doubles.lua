local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_doubles"

local TRAINER_TWINS_ELI_ANNE = 484
local MAGIKARP, IVYSAUR, WARTORTLE = 129, 2, 8
local TURN_CAP = 30

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS game3_doubles")
    love.event.quit(0)
  else
    print("FAIL game3_doubles failures=" .. failures)
    love.event.quit(1)
  end
end

local function log_has(Ui, needle)
  for _, t in ipairs(Ui.log and Ui.log() or {}) do
    if type(t) == "string" and t:find(needle, 1, true) then return true end
  end
  return false
end

local function find_trainer_object(TrainerSight, Objects, tid)
  local found = {}
  for _, lid in ipairs(Objects.listActive()) do
    local eo = Objects.find(lid)
    if eo and TrainerSight.getTrainerId(eo) == tid then found[#found + 1] = eo end
  end
  table.sort(found, function(a, b) return (a.cellX or 0) < (b.cellX or 0) end)
  return found[1], found[2]
end

return function(game)
  for _ = 1, 600 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end

  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(180)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Party = require("src.core.game3.party")
  local Objects = require("src.core.game3.objects")
  local TrainerSight = require("src.core.game3.trainer_sight")
  local Trainers = require("src.core.game3.scripting.trainers")
  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the field") then return finish() end

  local info = Trainers.info(TRAINER_TWINS_ELI_ANNE)
  result(info and info.doubleBattle == true, "trainer 484 ELI & ANNE is flagged doubleBattle")

  session.party = {}
  Party.giveMon(session, MAGIKARP, 5)
  result(Party.monsStateToDoubles(session.party) == Party.PLAYER_HAS_ONE_MON, "one mon: PLAYER_HAS_ONE_MON")

  local okC, MapCatalog = pcall(require, "src.import.gba.map_catalog")
  local mapId = (okC and MapCatalog.pretToEngine and MapCatalog.pretToEngine("Route8")) or "FR_ROUTE_8"
  Map.load(nil, game, mapId, { x = 40, y = 6, facing = "up" })
  game.session.x, game.session.y, game.session.facing = 40, 6, "up"
  U.wait(90)
  session = Runtime.getSession()

  local eli, anne = find_trainer_object(TrainerSight, Objects, TRAINER_TWINS_ELI_ANNE)
  if not result(eli ~= nil, "found a TRAINER_TWINS_ELI_ANNE object on " .. tostring(mapId)) then return finish() end
  result(anne ~= nil, "found the second twin object sharing the trainer id")
  result(TrainerSight.battleType(eli) == 4, "twin script is trainerbattle type 4 (got " .. tostring(TrainerSight.battleType(eli)) .. ")")
  result(TrainerSight.blockedByDoubles(eli) == true, "trainer sight blocks a one-mon player (trainer_see.c:114)")

  local tx, ty = eli.cellX, eli.cellY + 1
  Map.load(nil, game, mapId, { x = tx, y = ty, facing = "up" })
  game.session.x, game.session.y, game.session.facing = tx, ty, "up"
  U.wait(60)
  local Battle = require("src.core.game3.battle")
  local Message = package.loaded["src.ui.game3.message"] or require("src.ui.game3.message")
  U.tap(game, "a")
  local sawMsg = false
  for _ = 1, 240 do
    if Message.isOpen and Message.isOpen() then sawMsg = true break end
    U.wait(1)
  end
  result(sawMsg, "talking with one mon shows the not-enough-mons line")
  U.wait(30)
  U.shot(game, DIR .. "/00_not_enough.png")
  for _ = 1, 200 do
    if not (Message.isOpen and Message.isOpen()) and not (Space.vm and Space.vm:isRunning()) then break end
    U.tap(game, "a")
    U.wait(4)
  end
  local fid = Flags.trainerFlagId(TRAINER_TWINS_ELI_ANNE)
  result(not Battle.isActive(), "no battle with one mon")
  result(not Flags.getFlag(Space.store, Space.vm and Space.vm.ctx, fid), "trainer flag still clear after the refusal")

  Party.giveMon(session, IVYSAUR, 30)
  Party.giveMon(session, WARTORTLE, 30)
  result(Party.monsStateToDoubles(session.party) == Party.PLAYER_HAS_TWO_USABLE_MONS, "three mons: PLAYER_HAS_TWO_USABLE_MONS")
  result(TrainerSight.blockedByDoubles(eli) == false, "trainer sight allows the pair once two mons are usable")
  local moneyBefore = tonumber(session.money) or 0

  local Ui = require("src.core.game3.battle.ui")
  local Anim = require("src.core.game3.battle.anim")
  local PartyMenu = require("src.ui.game3.party_menu")
  for _ = 1, 600 do
    if Battle.isActive() then break end
    U.tap(game, "a")
    U.wait(3)
  end
  if not result(Battle.isActive(), "trainerbattle script started the battle") then return finish() end

  local st = Battle._st
  result(st and st.double == true, "battle state is double")
  result(st and st.battlersCount == 4, "battlersCount is 4")
  result(st and st.battlers[2] ~= nil and not st.absent[2], "player right flank present")
  result(st and st.battlers[3] ~= nil and not st.absent[3], "opponent right flank present")

  local shots = {}
  local function shot_once(key, name)
    if shots[key] then return end
    shots[key] = true
    U.wait(2)
    result(U.shot(game, DIR .. "/" .. name .. ".png"), "screenshot " .. name)
  end

  for _ = 1, 400 do
    if Battle._phase ~= "intro" then break end
    if log_has(Ui, " and ") and Ui.dialogPending and Ui.dialogPending() then
      U.wait(20)
      shot_once("intro", "01_intro_sent_out")
    end
    if Ui.dialogPending and Ui.dialogPending() then U.tap(game, "a") else U.wait(1) end
  end
  result(log_has(Ui, "sent\nout ") and log_has(Ui, " and "), "intro used the two-mon send-out line")
  result(log_has(Ui, "Go! ") and log_has(Ui, " and\n"), "intro used Go! X and Y!")

  local sawFaint, sawReplacement = false, false
  local guard = 0
  while Battle.isActive() and guard < 20000 do
    guard = guard + 1
    st = Battle._st
    if st and (st.turn or 0) > TURN_CAP then break end
    local phase = Battle._phase
    if st then
      for id = 0, 3 do
        local b = st.battlers[id]
        if b and b.mon and (tonumber(b.mon.hp) or 0) <= 0 and not sawFaint then
          sawFaint = true
          U.wait(10)
          shot_once("faint", "05_faint")
        end
      end
    end
    if PartyMenu.isOpen and PartyMenu.isOpen() then
      sawReplacement = sawReplacement or phase == "switching"
      shot_once("replace", "06_replacement_party")
      local pick
      for i = 1, #(PartyMenu._party or {}) do
        local ok = PartyMenu._validate == nil or PartyMenu._validate(i) == nil
        local mon = PartyMenu._party[i]
        if ok and mon and (tonumber(mon.hp) or 0) > 0 then pick = i break end
      end
      result(pick ~= nil, "a valid replacement is listed")
      if not pick then return finish() end
      PartyMenu.cursor = pick
      U.wait(30)
      U.tap(game, "a")
      U.wait(20)
      result(PartyMenu.mode == "action" and PartyMenu.ACTIONS[1] == "SEND OUT",
        "replacement action menu offers SEND OUT")
      shot_once("replace_action", "06b_send_out_menu")
      PartyMenu.actionCursor = 1
      U.tap(game, "a")
      U.wait(20)
      result(not PartyMenu.isOpen(), "SEND OUT closed the party menu")
    elseif phase == "command" and Ui._mode == "menu" and not Anim.busy() then
      local who = Ui.activeBattler and Ui.activeBattler() or 0
      shot_once("cmd" .. tostring(who), who == 0 and "02_command_left" or "02_command_right")
      U.tap(game, "a")
      U.wait(8)
    elseif phase == "command" and Ui._mode == "moves" then
      U.tap(game, "a")
      U.wait(8)
    elseif phase == "command" and Ui._mode == "target" then
      shot_once("target", "03_target_select")
      U.tap(game, "a")
      U.wait(8)
    elseif phase == "animating" or phase == "residuals" then
      if not shots.mid then
        U.wait(12)
        shot_once("mid", "04_mid_turn")
      end
      if Ui.dialogPending and Ui.dialogPending() then U.tap(game, "a") else U.wait(1) end
    else
      if Ui.dialogPending and Ui.dialogPending() then U.tap(game, "a") else U.wait(1) end
      if Ui.choiceActive and Ui.choiceActive() then U.tap(game, "b") U.wait(4) end
    end
  end

  local res = Battle.getResult() or (st and st.result)
  result(not Battle.isActive(), "battle ended within " .. TURN_CAP .. " turns (turn=" .. tostring(st and st.turn) .. ")")
  result(res == "win", "player won the double battle (result=" .. tostring(res) .. ")")
  result(sawFaint, "a battler fainted during the fight")
  if sawReplacement then
    result(true, "player picked a replacement for a fainted slot")
  else
    print("NOTE no player replacement was needed this run")
  end
  for _ = 1, 600 do
    if not (Space.vm and Space.vm:isRunning()) and not (Message.isOpen and Message.isOpen()) then break end
    U.tap(game, "a")
    U.wait(3)
  end
  result(Flags.getFlag(Space.store, Space.vm and Space.vm.ctx, fid), "trainer flag set after the win")
  local gained = (tonumber(session.money) or 0) - moneyBefore
  local Prize = require("src.core.game3.battle.prize")
  local expected = Prize.calc(TRAINER_TWINS_ELI_ANNE, { double = true })
  result(res ~= "win" or gained == expected, "prize money doubled (gained=" .. tostring(gained) .. " expected=" .. tostring(expected) .. ")")
  U.shot(game, DIR .. "/07_after.png")
  finish()
end
