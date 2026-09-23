#!/usr/bin/env luajit
-- pokefirered/src/battle_controller_pokedude.c:2675 InitPokedudePartyAndOpponent

package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function eq(a, b, msg)
  check(a == b, string.format("%s (%s == %s)", msg, tostring(a), tostring(b)))
end

local Cache = require("tests.game3_cache")
local cacheRoot = Cache.mount("items/pack.lua")
if not cacheRoot then
  print("[skip] game3_teachy_pokedude: " .. tostring(Cache.reason))
  os.exit(0)
end

local Pokedude = require("src.core.game3.battle.pokedude")
local Battle = require("src.core.game3.battle.init")
local Ui = require("src.core.game3.battle.ui")
local Rules = require("src.core.game3.battle.rules")
local Pokemon = require("src.core.game3.pokemon")
local Bag = require("src.core.game3.bag")
local TeachyTv = require("src.core.game3.teachy_tv")
local Rng = require("src.core.game3.rng")
local Runtime = require("src.core.game3.runtime")

local S = TeachyTv.SCRIPT

print("[test] 1. pokefirered/src/battle_controller_pokedude.c:2326 the parties")
do
  local party, foes = Pokedude.build(S.BATTLE)
  eq(#party, 1, "one player mon for the battle lesson")
  eq(party[1].species, 19, "RATTATA")
  eq(party[1].level, 15, "at level 15")
  eq(Pokemon.natureId(party[1].personality), 1, "NATURE_LONELY")
  eq(party[1].gender, "M", "male")
  eq(party[1].moves[3], 158, "HYPER FANG in slot 3")
  eq(party[1].ivs.atk, 0, "CreateMon fixedIV 0")
  eq(foes[1].species, 16, "vs PIDGEY")
  eq(foes[1].level, 18, "at level 18")
  eq(Pokemon.natureId(foes[1].personality), 4, "NATURE_NAUGHTY")
  local mp = Pokedude.build(S.MATCHUPS)
  eq(#mp, 2, "POLIWAG and BUTTERFREE for the matchups lesson")
  eq(mp[2].species, 12, "BUTTERFREE second")
  local _, cf = Pokedude.build(S.CATCHING)
  eq(cf[1].species, 39, "the catching lesson faces JIGGLYPUFF")
  eq(#cf[1].moves, 3, "with three moves")
end

print("[test] 2. pokefirered/src/battle_script_commands.c:1201 no critical hits")
do
  local st = { pokedude = true }
  local crits = 0
  for i = 1, 400 do
    if Rules.crit.roll({ species = 19 }, 158, true, function() return 0 end, st) then crits = crits + 1 end
  end
  eq(crits, 0, "a forced crit roll never crits under BATTLE_TYPE_POKEDUDE")
  check(Rules.crit.roll({ species = 19 }, 158, true, function() return 0 end, {}), "the same roll crits outside it")
end

local function run_lesson(script, seed)
  Rng.SeedRng(seed)
  local session = { name = "RED", bag = Bag.new(), party = {}, modData = {}, dex = { seen = {}, owned = {}, caught = {} } }
  Bag.add(session.bag, 13, 3)
  local party, foes = Pokedude.build(script)
  if Battle.isActive() then Battle.abort("run") end
  Runtime.getSession = function() return session end
  TeachyTv.initPokedudeBag(session, script)
  local result
  Battle.start({
    wild = true,
    pokedude = true,
    pdScriptNum = script,
    headless = true,
    autoFight = false,
    playerParty = party,
    foe = foes[1],
    session = session,
    onDone = function(r) result = r end,
  })
  local st = Battle.getState()
  Battle.runToEnd()
  TeachyTv.restorePlayerBag(session)
  return st, result, session
end

print("[test] 3. pokefirered/src/battle_controller_pokedude.c:2146 the voiceover order per lesson")
do
  local named = {
    [S.BATTLE] = { "Pokedude_Text_SpeedierBattlerGoesFirst", "Pokedude_Text_MyRattataFasterThanPidgey",
      "Pokedude_Text_BattlersTakeTurnsAttacking", "Pokedude_Text_MyRattataWonGetsEXP" },
    [S.STATUS] = { "Pokedude_Text_UhOhRattataPoisoned", "Pokedude_Text_UhOhRattataPoisoned",
      "Pokedude_Text_HealStatusRightAway", "Pokedude_Text_UsingItemTakesTurn", "Pokedude_Text_YayWeManagedToWin" },
    [S.MATCHUPS] = { "Pokedude_Text_WaterNotVeryEffectiveAgainstGrass", "Pokedude_Text_GrassEffectiveAgainstWater",
      "Pokedude_Text_LetsTryShiftingMons", "Pokedude_Text_ShiftingUsesTurn",
      "Pokedude_Text_ButterfreeDoubleResistsGrass", "Pokedude_Text_ButterfreeGoodAgainstOddish",
      "Pokedude_Text_YeahWeWon" },
    [S.CATCHING] = { "Pokedude_Text_WeakenMonBeforeCatching", "Pokedude_Text_WeakenMonBeforeCatching",
      "Pokedude_Text_BestIfTargetStatused", "Pokedude_Text_CantDoubleUpOnStatus", "Pokedude_Text_LetMeThrowBall",
      "Pokedude_Text_PickBestKindOfBall" },
  }
  local BattleText = require("src.core.game3.battle.battle_text")
  for script, list in pairs(named) do
    for i, label in ipairs(list) do
      local key = Pokedude.textKey(script, i - 1)
      check(BattleText.get(key, { playerName = "RED" }) == BattleText.get(label, { playerName = "RED" }),
        key .. " reads " .. label .. " from the cache table")
    end
  end
  local spoken = {
    [S.BATTLE] = { 0, 1, 2, 3 },
    [S.STATUS] = { 1, 2, 3, 4 },
    [S.MATCHUPS] = { 0, 1, 2, 3, 4, 5, 6 },
    [S.CATCHING] = { 0, 2, 3, 4, 5 },
  }
  local want = {}
  for script, idx in pairs(spoken) do
    want[script] = {}
    for i, n in ipairs(idx) do want[script][i] = Pokedude.textKey(script, n) end
  end
  local names = { [S.BATTLE] = "battle", [S.STATUS] = "status", [S.MATCHUPS] = "matchups", [S.CATCHING] = "catching" }
  for script = S.BATTLE, S.CATCHING do
    for seed = 1, 6 do
      local st, result, session = run_lesson(script, seed * 7919)
      local got = table.concat(st.pd.log, ",")
      local exp = table.concat(want[script], ",")
      if got ~= exp then
        print("[info] " .. names[script] .. " seed " .. seed .. " log: " .. got)
        print("[info] battle log: " .. table.concat(Ui.log() or {}, " | "))
      end
      eq(got, exp, names[script] .. " lesson voiceovers in cart order, seed " .. seed)
      eq(result, script == S.CATCHING and "catch" or "win", names[script] .. " ends in " .. tostring(result))
      eq(#session.party, 0, "nothing joins the player's party")
      eq(Bag.get(session.bag, 13), 3, "the player's POTIONS are back")
      check(not session.dex.caught[39], "JIGGLYPUFF is not registered as caught")
      check(not session.dex.seen[16] and not session.dex.seen[43], "no foe is marked seen")
    end
  end
end

print("[test] 4. pokefirered/src/battle_script_commands.c:1015 no move misses")
do
  local misses = 0
  for seed = 1, 12 do
    run_lesson(S.BATTLE, seed * 104729)
    for _, t in ipairs(Ui.log() or {}) do
      if t:find("missed") then misses = misses + 1 end
    end
  end
  eq(misses, 0, "SAND ATTACK and friends never miss across 12 battles")
end

local NO = { wasPressed = function() return false end, isDown = function() return false end }
local function press(key)
  return { wasPressed = function(_, k) return k == key end, isDown = function() return false end }
end

print("[test] 5. pokefirered/src/item_menu.c:2262/2316 the timer-driven POKé DUDE bag")
do
  local BagMenu = require("src.ui.game3.bag_menu")
  local ItemsData = require("src.core.game3.items_data")
  local session = { name = "RED", bag = Bag.new(), party = {}, modData = {} }
  Bag.add(session.bag, 13, 3)
  Bag.add(session.bag, 17, 2)
  BagMenu.show(session.bag, { session = session })
  BagMenu.cursor = 2
  BagMenu.close()
  TeachyTv.initPokedudeBag(session, S.STATUS)

  local picked, cancelled, modeAtA, rowAtA
  BagMenu.showPokedude(session.bag, { session = session, plan = "status",
    onItem = function(id) picked = id end, onCancel = function() cancelled = true end })
  for f = 1, 400 do
    BagMenu.handleInput(NO)
    if f == 250 then
      modeAtA = BagMenu.mode
      local row = BagMenu.list()[BagMenu.cursor]
      rowAtA = row and ItemsData.toNumericId(row.id)
    end
    if picked or cancelled then break end
  end
  eq(modeAtA, "action", "A at 204 opened the USE/CANCEL context menu")
  eq(rowAtA, 14, "on the ANTIDOTE one row down")
  eq(picked, 14, "the STATUS bag closes with ANTIDOTE")
  check(not BagMenu.isOpen() and not BagMenu.isPokedude(), "and the bag is closed")

  picked = nil
  local pocketMid, cursorMid
  BagMenu.showPokedude(session.bag, { session = session, plan = "catching",
    onItem = function(id) picked = id end })
  for f = 1, 1000 do
    BagMenu.handleInput(NO)
    if f == 460 then pocketMid, cursorMid = BagMenu.currentPocket(), BagMenu.cursor end
    if picked then break end
  end
  eq(pocketMid, "POKE_BALLS", "two pocket switches right land on the POKé BALLS pocket")
  eq(cursorMid, 3, "two DPAD_DOWNs reach the NEST BALL")
  eq(picked, 4, "the CATCHING bag closes with POKé BALL")

  picked, cancelled = nil, nil
  BagMenu.showPokedude(session.bag, { session = session, plan = "catching",
    onItem = function(id) picked = id end, onCancel = function() cancelled = true end })
  for f = 1, 200 do
    BagMenu.handleInput(f == 60 and press("b") or NO)
    if picked or cancelled then break end
  end
  check(cancelled and not picked, "B interrupts the scripted bag (item_menu.c:2192)")
  check(not BagMenu.isOpen(), "and closes it")

  TeachyTv.restorePlayerBag(session)
  BagMenu.show(session.bag, { session = session, pocket = "ITEMS" })
  eq(BagMenu.cursor, 2, "the player's bag cursor is restored (item_menu.c:2089)")
  BagMenu.close()

  Bag.add(session.bag, 366, 1)
  BagMenu.show(session.bag, { session = session, pocket = "KEY_ITEMS" })
  BagMenu.open = false
  TeachyTv.initPokedudeBag(session, S.CATCHING)
  picked = nil
  BagMenu.showPokedude(session.bag, { session = session, plan = "catching",
    onItem = function(id) picked = id end })
  for _ = 1, 1000 do
    BagMenu.handleInput(NO)
    if picked then break end
  end
  TeachyTv.restorePlayerBag(session)
  eq(picked, 4, "the catching bag ran over a hidden player bag")
  eq(BagMenu.currentPocket(), "KEY_ITEMS",
    "the hidden player bag view is back on KEY ITEMS, not the POKé DUDE's pocket (item_menu.c:2089)")
  eq(BagMenu._bag, session.bag, "and it points at the player's bag again")
  local row = BagMenu.list()[BagMenu.cursor]
  eq(row and ItemsData.toNumericId(row.id), 366, "with the cursor on TEACHY TV")
end

print("[test] 6. pokefirered/src/party_menu.c:2020/2072 the timer-driven POKé DUDE party menu")
do
  local PartyMenu = require("src.ui.game3.party_menu")
  local session = { name = "RED", bag = Bag.new(), party = {}, modData = {} }
  local party = Pokedude.build(S.MATCHUPS)
  local chosen, cancelled, actionsAt
  PartyMenu.showPokedude(party, { plan = "switch", session = session, activeSlot = 1,
    onSelect = function(slot) chosen = slot end, onCancel = function() cancelled = true end })
  for f = 1, 300 do
    PartyMenu.handleInput(NO)
    if f == 200 then actionsAt = PartyMenu.mode == "action" and PartyMenu.ACTIONS[1] end
    if chosen or cancelled then break end
  end
  eq(actionsAt, "SHIFT", "A at 160 opened the selection window on SHIFT")
  eq(chosen, 2, "the switch plan shifts to BUTTERFREE at 240")
  check(not PartyMenu.isOpen(), "and closes the party menu")

  local used, selected
  local status = Pokedude.build(S.STATUS)
  PartyMenu.showPokedude(status, { plan = "item", session = session, item = 14, activeSlot = 1,
    onUse = function(slot) used = slot return "RATTATA was cured of its\npoisoning." end,
    onSelect = function(slot) selected = slot end })
  for _ = 1, 80 do PartyMenu.handleInput(NO) end
  check(used == nil, "nothing is used while data[0] counts to 80")
  PartyMenu.handleInput(NO)
  eq(used, 1, "ItemUseCB_MedicineStep runs on RATTATA at frame 80")
  eq(PartyMenu.mode, "message", "the cure text is in the party menu")
  for _ = 1, 30 do PartyMenu.handleInput(NO) end
  check(selected == nil and PartyMenu.isOpen(), "the text waits for a button (party_menu.c:453 autoScroll off)")
  PartyMenu.handleInput(press("a"))
  eq(selected, 1, "A closes the menu back to the battle")

  cancelled = nil
  PartyMenu.showPokedude(party, { plan = "switch", session = session, activeSlot = 1,
    onSelect = function() end, onCancel = function() cancelled = true end })
  for _ = 1, 10 do PartyMenu.handleInput(NO) end
  PartyMenu.handleInput(press("b"))
  check(cancelled and not PartyMenu.isOpen(), "B cancels the scripted party menu (party_menu.c:2052)")
end

print("[test] 7. pokefirered/src/pokeball.c:389 the POKé DUDE send-out ball starts at (32, 64)")
do
  local x, y = Pokedude.sendOutOrigin({ pokedude = true })
  eq(x * 1000 + y, 32064, "POKé DUDE throw origin")
  x, y = Pokedude.sendOutOrigin({})
  eq(x * 1000 + y, 48070, "the player's throw origin is unchanged")
end

if failed > 0 then
  print(string.format("FAILED %d check(s)", failed))
  os.exit(1)
end
print("All teachy pokedude checks passed.")
