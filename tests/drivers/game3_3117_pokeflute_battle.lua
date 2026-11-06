local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_3117_pokeflute_battle"

return function(game)
  local fails = 0
  local function result(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then fails = fails + 1 end
  end

  for _ = 1, 600 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(180)

  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local Bag = require("src.core.game3.bag")
  local ItemsData = require("src.core.game3.items_data")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local Anim = require("src.core.game3.battle.anim")
  local AnimSeq = require("src.core.game3.battle.anim_seq")
  local IntroSeq = require("src.core.game3.battle.intro_seq")
  local Ui = require("src.core.game3.battle.ui")
  local BagMenu = require("src.ui.game3.bag_menu")
  local Message = require("src.ui.game3.message")
  local Audio = require("src.core.game3.audio")
  local session = Runtime.getSession()

  local POKE_FLUTE = 350
  session.party = {}
  Party.giveMon(session, 9, 59)
  Party.giveMon(session, 25, 20)
  session.party[2].status = "SLP"
  session.party[2].sleep = 3
  session.bag = Bag.new()
  Bag.add(session.bag, POKE_FLUTE, 1)

  local f, lastTap = 0, 0
  local function at_command()
    return Battle.isActive() and Battle._phase == "command" and Ui._mode == "menu"
  end
  local function busy()
    local s = AnimSeq._steps and AnimSeq._steps[AnimSeq._i]
    return (Anim.vm() and Anim.vm():busy()) or (s and s.kind ~= "msg") or IntroSeq._waitingGen
  end
  local function page()
    return Message.isOpen and Message.isOpen() and tostring(Message.currentPage() or "") or ""
  end
  local function run_until(pred, limit, noTapIn)
    for _ = 1, limit or 3000 do
      f = f + 1
      if pred() then return true end
      local p = page()
      if not busy() and Ui.dialogPending and Ui.dialogPending() and f - lastTap >= 14
          and not (noTapIn and p:find(noTapIn, 1, true)) then
        lastTap = f
        U.tap(game, "a")
      else
        U.wait(1)
      end
    end
    return false
  end
  local function wait_for(pred, limit)
    for _ = 1, limit or 600 do
      if pred() then return true end
      U.wait(1)
    end
    return false
  end

  local ok = BattleBridge.startWild(Runtime._mod, game, { species = 19, level = 5 }, { fade = false })
  result(ok == true, "wild battle started")
  result(run_until(at_command, 4000), "reached the command menu")

  local st = Battle.getState()
  st.enemy.status = "SLP"
  st.enemy.sleepTurns = 6
  st.enemy.mon.status = "SLP"
  st.enemy.mon.sleep = 6
  Anim.syncDisplayFromState(st)
  local pf = Anim.present(1)
  result(pf and pf.displayStatus == "SLP", "foe healthbox shows SLP before the flute")

  Ui._menuIndex = 2
  U.tap(game, "a")
  result(wait_for(function() return BagMenu.open and not BagMenu._open and BagMenu.mode == "list" end), "battle bag open")
  for i, p in ipairs(ItemsData.BAG_POCKET_ORDER) do
    if p == "KEY_ITEMS" then BagMenu.pocketIdx = i end
  end
  BagMenu.scroll = 0
  for i, row in ipairs(BagMenu.list()) do
    if (ItemsData.toNumericId(row.id) or tonumber(row.id)) == POKE_FLUTE then BagMenu.cursor = i end
  end
  U.wait(10)
  U.tap(game, "a")
  result(wait_for(function() return BagMenu.mode == "action" end, 120), "POKE FLUTE context menu")
  BagMenu.actionCursor = 1
  U.wait(10)
  U.tap(game, "a")
  result(wait_for(function() return not BagMenu.open end, 300), "bag closed back to the battle")

  local played = wait_for(function() return page():find("played the", 1, true) ~= nil end, 600)
  result(played, "the battle prints the played the POKe FLUTE line (battle_scripts_2.s:200)")
  if played then U.shot(game, DIR .. "/3117_01_played_flute.png") end
  local fanfare = wait_for(function() return Audio._fanfareActive == true end, 300)
  result(fanfare, "the POKe FLUTE fanfare plays (battle_scripts_2.s:202)")
  local cantUse = false
  for _, line in ipairs(Ui.log() or {}) do
    if tostring(line):find("can't be used", 1, true) then cantUse = true end
  end
  result(not cantUse, "no 'This can't be used right now.' line")

  local awoke = wait_for(function() return page():find("awoke", 1, true) ~= nil end, 3000)
  result(awoke, "the battle prints the hearing the FLUTE awoke line (battle_scripts_2.s:204)")
  result(awoke and Audio._fanfareActive ~= true, "the awoke line waits for the fanfare (battle_scripts_2.s:203)")
  if awoke and wait_for(function() return Message.isWaiting and Message.isWaiting() end, 300) then
    U.shot(game, DIR .. "/3117_02_flute_awoke.png")
  end

  result(st.enemy.status == nil and st.enemy.mon.status == nil, "the sleeping wild RATTATA woke")
  result(session.party[2].status == nil or st.playerParty[2].status == nil, "the sleeping bench PIKACHU woke")
  result(Bag.get(session.bag, POKE_FLUTE) == 1, "the POKe FLUTE stays in the bag")

  result(run_until(function() return f > 10 and at_command() end, 4000), "turn played out back to the command menu")
  pf = Anim.present(1)
  result(pf and not pf.displayStatus, "foe healthbox SLP icon cleared (battle_scripts_2.s:206)")
  local foeMoved, afterFlute = false, false
  for _, line in ipairs(Ui.log() or {}) do
    local s = tostring(line)
    if s:find("awoke", 1, true) then afterFlute = true
    elseif afterFlute and s:find("RATTATA used", 1, true) then foeMoved = true end
  end
  result(foeMoved, "the flute used the turn and the woken foe moved")
  if at_command() then U.shot(game, DIR .. "/3117_03_icon_cleared.png") end
  for _, line in ipairs(Ui.log() or {}) do print("  log: " .. tostring(line):gsub("\n", " ")) end

  Battle.abort("run")
  wait_for(function() return not Battle.isActive() end, 120)

  if fails == 0 then print("PASS game3_3117_pokeflute_battle") end
  love.event.quit(fails == 0 and 0 or 1)
end
