local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_battle_medicine_party_text"

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
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local Anim = require("src.core.game3.battle.anim")
  local AnimSeq = require("src.core.game3.battle.anim_seq")
  local IntroSeq = require("src.core.game3.battle.intro_seq")
  local Ui = require("src.core.game3.battle.ui")
  local BagMenu = require("src.ui.game3.bag_menu")
  local PartyMenu = require("src.ui.game3.party_menu")
  local RomText = require("src.core.game3.rom_text")
  local Pokemon = require("src.core.game3.pokemon")
  local session = Runtime.getSession()

  session.party = {}
  Party.giveMon(session, 4, 20)
  Party.giveMon(session, 25, 20)
  local lead = session.party[1]
  lead.hp = math.max(1, lead.hp - 15)
  session.party[2].status = "PSN"
  session.bag = Bag.new()
  Bag.add(session.bag, 13, 2)

  local f, lastTap = 0, 0
  local function at_command()
    return Battle.isActive() and Battle._phase == "command" and Ui._mode == "menu"
  end
  local function busy()
    local s = AnimSeq._steps and AnimSeq._steps[AnimSeq._i]
    return (Anim.vm() and Anim.vm():busy()) or (s and s.kind ~= "msg") or IntroSeq._waitingGen
  end
  local function run_until(pred, limit)
    for _ = 1, limit or 3000 do
      f = f + 1
      if pred() then return true end
      if not busy() and Ui.dialogPending and Ui.dialogPending() and f - lastTap >= 14 then
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
  local function log_has(from, needle)
    local log = Ui.log() or {}
    for i = from + 1, #log do
      if tostring(log[i]):find(needle, 1, true) then return true end
    end
    return false
  end

  local ok = BattleBridge.startWild(Runtime._mod, game, { species = 19, level = 2 }, { fade = false })
  result(ok == true, "wild battle started")
  result(run_until(at_command, 4000), "reached the command menu")

  local st = Battle.getState()
  local hpBefore = tonumber(st.player.mon.hp) or 0
  local logFrom = #(Ui.log() or {})

  Ui._menuIndex = 2
  U.tap(game, "a")
  result(wait_for(function() return BagMenu.open and not BagMenu._open and BagMenu.mode == "list" end), "battle bag open")
  U.wait(10)
  U.tap(game, "a")
  result(wait_for(function() return BagMenu.mode == "action" end, 120), "POTION context menu")
  U.wait(10)
  U.tap(game, "a")
  result(wait_for(function() return PartyMenu.isOpen() and PartyMenu.mode == "use" end, 240), "party menu opened for the POTION")
  U.wait(20)
  U.shot(game, DIR .. "/medicine_party_before_use.png")
  U.tap(game, "a")

  local want = RomText.plain("gText_PkmnHPRestoredByVar2",
    { stringVars = { Pokemon.displayMonName(lead), tostring(15) } })
  local shown = wait_for(function()
    return PartyMenu.isOpen() and PartyMenu.mode == "message" and PartyMenu._messageText ~= nil
  end, 300)
  local text = tostring(PartyMenu._messageText or ""):gsub("\n", " ")
  print("[driver] party message: " .. text)
  result(shown and text:find("HP was restored", 1, true) ~= nil,
    "the party menu prints the HP restored text (party_menu.c:4528)")
  result(shown and text:gsub("%s+", " ") == tostring(want):gsub("%s+", " "),
    "it names the mon and the 15 points it got back")
  result(shown and Bag.get(session.bag, 13) == 1, "the POTION is spent in the party menu (party_menu.c:4502)")
  if shown then U.shot(game, DIR .. "/medicine_party_hp_restored.png") end
  U.wait(20)
  U.tap(game, "a")

  result(wait_for(function() return not PartyMenu.isOpen() and not BagMenu.open end, 300), "menus closed back to the battle")
  run_until(function() return f > 10 and at_command() end, 4000)
  result(not log_has(logFrom, "POTION"),
    "the battle prints no 'RED used the POTION.' (battle_scripts_2.s:130)")
  result((tonumber(st.player.mon.hp) or 0) >= math.min(hpBefore + 15, st.player.mon.maxHp) - 20,
    "the lead kept the healed HP")
  for i, line in ipairs(Ui.log() or {}) do
    if i > logFrom then print("  log: " .. tostring(line):gsub("\n", " ")) end
  end

  local ItemsData = require("src.core.game3.items_data")
  local BerryPouch = require("src.ui.game3.berry_pouch")
  local ITEM_YELLOW_FLUTE, ITEM_X_ATTACK, ITEM_PERSIM_BERRY, ITEM_BERRY_POUCH = 40, 75, 140, 365
  Bag.add(session.bag, ITEM_X_ATTACK, 1)
  Bag.add(session.bag, ITEM_YELLOW_FLUTE, 1)
  Bag.add(session.bag, ITEM_PERSIM_BERRY, 1)
  Bag.add(session.bag, ITEM_BERRY_POUCH, 1)

  local function open_bag_on(pocket, itemId)
    Ui._menuIndex = 2
    U.tap(game, "a")
    if not wait_for(function() return BagMenu.open and not BagMenu._open and BagMenu.mode == "list" end) then
      return false
    end
    for i, p in ipairs(ItemsData.BAG_POCKET_ORDER) do
      if p == pocket then BagMenu.pocketIdx = i end
    end
    BagMenu.scroll = 0
    for i, row in ipairs(BagMenu.list()) do
      if (ItemsData.toNumericId(row.id) or tonumber(row.id)) == itemId then BagMenu.cursor = i end
    end
    U.wait(10)
    U.tap(game, "a")
    if not wait_for(function() return BagMenu.mode == "action" end, 120) then return false end
    BagMenu.actionCursor = 1
    U.wait(10)
    U.tap(game, "a")
    return true
  end
  local function back_to_command()
    local closed = wait_for(function() return not PartyMenu.isOpen() and not BagMenu.open and not BerryPouch.isOpen() end, 300)
    return closed and run_until(function() return at_command() end, 4000)
  end

  -- pokefirered/src/item_use.c:766 Task_BattleUse_StatBooster_DelayAndPrint
  logFrom = #(Ui.log() or {})
  result(open_bag_on("ITEMS", ITEM_X_ATTACK), "X ATTACK picked from the battle bag")
  local xShown = wait_for(function()
    return BagMenu.open and BagMenu.mode == "message" and tostring(BagMenu.messageText or ""):find("rose", 1, true) ~= nil
  end, 300)
  local xText = tostring(BagMenu.messageText or ""):gsub("\n", " ")
  print("[driver] bag message: " .. xText)
  result(xShown and xText:find("ATTACK", 1, true) ~= nil, "the bag prints the ATTACK rose text (item_use.c:775)")
  result((st.player.stages.attack or 0) == 1 and Bag.get(session.bag, ITEM_X_ATTACK) == 0,
    "X ATTACK raised the stage and was spent in the bag")
  if xShown then U.shot(game, DIR .. "/xitem_bag_stat_rose.png") end
  U.wait(10)
  U.tap(game, "a")
  result(back_to_command(), "back at the command menu after the X ATTACK")
  result(not log_has(logFrom, "rose"), "the battle prints no stat line for the X ATTACK (battle_scripts_2.s:130)")

  -- pokefirered/src/party_menu.c:4505
  st.player.confusionTurns = 3
  logFrom = #(Ui.log() or {})
  result(open_bag_on("ITEMS", ITEM_YELLOW_FLUTE), "YELLOW FLUTE picked from the battle bag")
  result(wait_for(function() return PartyMenu.isOpen() and PartyMenu.mode == "use" end, 240), "party menu opened for the YELLOW FLUTE")
  U.wait(20)
  U.tap(game, "a")
  local fShown = wait_for(function()
    return PartyMenu.isOpen() and PartyMenu.mode == "message" and PartyMenu._messageText ~= nil
  end, 300)
  local fText = tostring(PartyMenu._messageText or ""):gsub("\n", " ")
  print("[driver] flute message: " .. fText)
  result(fShown and fText:find("confusion", 1, true) ~= nil, "the party menu prints the snapped-out text (party_menu.c:4360)")
  result(st.player.confusionTurns == nil, "the lead is no longer confused")
  result(Bag.get(session.bag, ITEM_YELLOW_FLUTE) == 1, "the YELLOW FLUTE is not used up (party_menu.c:4498)")
  if fShown then U.shot(game, DIR .. "/flute_party_snapped_out.png") end
  U.wait(10)
  U.tap(game, "a")
  result(back_to_command(), "back at the command menu after the YELLOW FLUTE")
  result(not log_has(logFrom, "FLUTE"), "the battle prints no line for the flute")

  st.player.confusionTurns = 3
  logFrom = #(Ui.log() or {})
  result(open_bag_on("KEY_ITEMS", ITEM_BERRY_POUCH), "BERRY POUCH opened from the battle bag")
  result(wait_for(function() return BerryPouch.isOpen() and BerryPouch.mode == "list" end, 240), "the Berry Pouch is up")
  for i, row in ipairs(BerryPouch.list()) do
    if (ItemsData.toNumericId(row.id) or tonumber(row.id)) == ITEM_PERSIM_BERRY then BerryPouch.cursor = i end
  end
  U.wait(10)
  U.tap(game, "a")
  wait_for(function() return BerryPouch.mode == "action" end, 120)
  BerryPouch.actionCursor = 1
  U.wait(10)
  U.tap(game, "a")
  result(wait_for(function() return PartyMenu.isOpen() and PartyMenu.mode == "use" end, 240), "party menu opened for the PERSIM BERRY")
  U.wait(20)
  U.tap(game, "a")
  local bShown = wait_for(function()
    return PartyMenu.isOpen() and PartyMenu.mode == "message" and PartyMenu._messageText ~= nil
  end, 300)
  local bText = tostring(PartyMenu._messageText or ""):gsub("\n", " ")
  print("[driver] berry message: " .. bText)
  result(bShown and bText:find("confusion", 1, true) ~= nil, "the PERSIM BERRY prints the snapped-out text")
  result(st.player.confusionTurns == nil and Bag.get(session.bag, ITEM_PERSIM_BERRY) == 0,
    "the PERSIM BERRY cured the confusion and was eaten")
  if bShown then U.shot(game, DIR .. "/berry_party_snapped_out.png") end
  U.wait(10)
  U.tap(game, "a")
  result(back_to_command(), "back at the command menu after the PERSIM BERRY")
  result(not log_has(logFrom, "PERSIM"), "the battle prints no line for the berry")

  Battle.abort("run")
  wait_for(function() return not Battle.isActive() end, 120)

  if fails == 0 then print("PASS game3_battle_medicine_party_text") end
  love.event.quit(fails == 0 and 0 or 1)
end
