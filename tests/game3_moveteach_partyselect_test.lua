#!/usr/bin/env luajit
-- pokefirered/src/party_menu.c:5651, pokefirered/src/evolution_scene.c:637

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

local function finish()
  if failed > 0 then
    print(string.format("[FAIL] %d check(s) failed", failed))
    os.exit(1)
  end
  print("[PASS] game3_moveteach_partyselect")
  os.exit(0)
end

local function show(list)
  local parts = {}
  for i = 1, #(list or {}) do parts[i] = tostring(list[i]) end
  return "{" .. table.concat(parts, ",") .. "}"
end

local Cache = require("tests.game3_cache")
local cacheRoot = Cache.mount("pokemon/learnsets.lua")
if not cacheRoot then
  print("[skip] game3_moveteach_partyselect: " .. tostring(Cache.reason))
  os.exit(0)
end
print("[info] FireRed cache at " .. cacheRoot)

local Pokemon = require("src.core.game3.pokemon")
Pokemon.install(nil)

local PartyMenu = require("src.ui.game3.party_menu")
local Evolution = require("src.core.game3.evolution")

local BULBASAUR, IVYSAUR, CHARMANDER, SQUIRTLE = 1, 2, 4, 7
local PIDGEY, RATTATA, GOLBAT = 16, 19, 42
local CROBAT = 169

local function monAt(species, level)
  local moves, pp, maxPp = Pokemon.movesAtLevel(species, level)
  return {
    species = species, speciesId = species, level = level,
    moves = moves, pp = pp, maxPp = maxPp,
    hp = 20, maxHp = 20,
  }
end

local function sixParty()
  return {
    monAt(BULBASAUR, 20), monAt(CHARMANDER, 20), monAt(SQUIRTLE, 20),
    monAt(PIDGEY, 20), monAt(RATTATA, 20), monAt(GOLBAT, 20),
  }
end

local pressed = nil
local input = { wasPressed = function(_, key) return key == pressed end,
  isDown = function(_, key) return key == pressed end }
local function press(key)
  pressed = key
  PartyMenu.handleInput(input)
  pressed = nil
end

local function openMulti(party, opts)
  opts = opts or {}
  opts.mode = opts.mode or "choose"
  opts.count = opts.count or 3
  PartyMenu.show(party, nil, opts)
end

local function chooseAction(label)
  local guard = 0
  while PartyMenu.ACTIONS[PartyMenu.actionCursor] ~= label and guard < 8 do
    press("down")
    guard = guard + 1
  end
  press("a")
end

print("[test] 1. { mode = choose, count = 3 } opens pret's multi picker")
do
  local party = sixParty()
  local got, calls = nil, 0
  openMulti(party, { onSelect = function(order) got = order; calls = calls + 1 end })
  check(PartyMenu.mode == "choose_multi",
    "the published option shape lands in choose_multi, got " .. tostring(PartyMenu.mode))
  check(#PartyMenu.chosenOrder() == 0, "nothing is entered yet")

  press("a")
  check(PartyMenu.mode == "action" and PartyMenu.ACTIONS[1] == "ENTER",
    "an eligible mon offers ENTER / SUMMARY / CANCEL, got " .. show(PartyMenu.ACTIONS))
  press("a")
  check(PartyMenu.mode == "choose_multi", "ENTER returns to the list")
  local order = PartyMenu.chosenOrder()
  check(#order == 1 and order[1] == 1, "slot 1 is FIRST, got " .. show(order))

  press("down")
  press("down")
  press("a")
  chooseAction("ENTER")
  press("down")
  press("a")
  chooseAction("ENTER")
  order = PartyMenu.chosenOrder()
  check(#order == 3 and order[1] == 1 and order[2] == 3 and order[3] == 4,
    "the entry order is remembered, got " .. show(order))
  check(PartyMenu.cursor == 7,
    "the third entry moves the cursor onto CONFIRM, got " .. tostring(PartyMenu.cursor))

  press("a")
  check(calls == 1 and got ~= nil, "CONFIRM closed the picker once")
  check(not PartyMenu.isOpen(), "the party menu is closed")
  check(#got == 3 and got[1] == 1 and got[2] == 3 and got[3] == 4,
    "the caller receives the ordered slots, got " .. show(got))
end

print("[test] 2. a fourth entry is refused with pret's message")
do
  local party = sixParty()
  openMulti(party, { onSelect = function() end })
  for _, slot in ipairs({ 1, 2, 3 }) do
    PartyMenu.cursor = slot
    press("a")
    chooseAction("ENTER")
  end
  PartyMenu.cursor = 4
  press("a")
  chooseAction("ENTER")
  check(PartyMenu.mode == "message", "the fourth ENTER shows a message")
  check(tostring(PartyMenu._messageText):find("No more than three", 1, true) ~= nil,
    "pret's wording is used, got " .. tostring(PartyMenu._messageText))
  press("a")
  check(PartyMenu.mode == "choose_multi", "and the list comes back")
  check(#PartyMenu.chosenOrder() == 3, "still three entries")
  PartyMenu.close()
end

print("[test] 3. NO ENTRY removes a mon and closes the gap")
do
  local party = sixParty()
  openMulti(party, { onSelect = function() end })
  for _, slot in ipairs({ 1, 2, 3 }) do
    PartyMenu.cursor = slot
    press("a")
    chooseAction("ENTER")
  end
  PartyMenu.cursor = 1
  press("a")
  check(PartyMenu.ACTIONS[1] == "NO ENTRY",
    "an entered mon offers NO ENTRY, got " .. show(PartyMenu.ACTIONS))
  press("a")
  local order = PartyMenu.chosenOrder()
  check(#order == 2 and order[1] == 2 and order[2] == 3,
    "the remaining two shift up, got " .. show(order))
  PartyMenu.cursor = 5
  press("a")
  chooseAction("ENTER")
  order = PartyMenu.chosenOrder()
  check(order[3] == 5, "the new pick lands third, got " .. show(order))
  PartyMenu.close()
end

print("[test] 4. a fainted mon and an EGG are NOT ABLE")
do
  local party = sixParty()
  party[2].hp = 0
  party[3].isEgg = true
  openMulti(party, { onSelect = function() end })
  PartyMenu.cursor = 2
  press("a")
  check(PartyMenu.ACTIONS[1] == "SUMMARY" and #PartyMenu.ACTIONS == 2,
    "a fainted mon only offers SUMMARY / CANCEL, got " .. show(PartyMenu.ACTIONS))
  press("b")
  PartyMenu.cursor = 3
  press("a")
  check(PartyMenu.ACTIONS[1] == "SUMMARY" and #PartyMenu.ACTIONS == 2,
    "and so does an EGG, got " .. show(PartyMenu.ACTIONS))
  press("b")
  check(PartyMenu.mode == "choose_multi", "B backs out of the action menu")
  PartyMenu.close()
end

print("[test] 5. CONFIRM with nothing entered refuses")
do
  local party = sixParty()
  local calls = 0
  openMulti(party, { onSelect = function() calls = calls + 1 end })
  PartyMenu.cursor = 7
  press("a")
  check(PartyMenu.mode == "message"
    and tostring(PartyMenu._messageText):find("No battling this way", 1, true) ~= nil,
    "pret's no-mon message is shown, got " .. tostring(PartyMenu._messageText))
  check(calls == 0, "the caller is not told anything yet")
  press("a")
  check(PartyMenu.mode == "choose_multi" and PartyMenu.isOpen(), "the picker stays up")
  PartyMenu.close()
end

print("[test] 6. START jumps to CONFIRM and the buttons wrap pret's way")
do
  local party = sixParty()
  openMulti(party, { onSelect = function() end })
  press("start")
  check(PartyMenu.cursor == 7, "START moves to CONFIRM, got " .. tostring(PartyMenu.cursor))
  press("down")
  check(PartyMenu.cursor == 8, "down from CONFIRM is CANCEL, got " .. tostring(PartyMenu.cursor))
  press("down")
  check(PartyMenu.cursor == 1, "down from CANCEL wraps to the first slot")
  press("up")
  check(PartyMenu.cursor == 8, "up from the first slot is CANCEL")
  press("up")
  check(PartyMenu.cursor == 7, "up from CANCEL is CONFIRM")
  press("up")
  check(PartyMenu.cursor == 6, "up from CONFIRM is the last party slot")
  PartyMenu.close()
end

print("[test] 7. cancel asks first and returns nil")
do
  local party = sixParty()
  local got, calls = "unset", 0
  openMulti(party, { onSelect = function(order) got = order; calls = calls + 1 end })
  PartyMenu.cursor = 1
  press("a")
  chooseAction("ENTER")
  press("b")
  check(PartyMenu.mode == "yesno"
    and tostring(PartyMenu._yesNoPrompt):find("Cancel the battle?", 1, true) ~= nil,
    "pret asks Cancel the battle?, got " .. tostring(PartyMenu._yesNoPrompt))
  press("down")
  press("a")
  check(PartyMenu.mode == "choose_multi" and calls == 0,
    "answering NO keeps the picker up")
  check(#PartyMenu.chosenOrder() == 1, "and keeps the entry")

  press("b")
  press("a")
  check(calls == 1 and got == nil, "answering YES returns nil to the caller")
  check(not PartyMenu.isOpen(), "and closes the picker")
  check(#PartyMenu.chosenOrder() == 0, "the order was cleared")
end

print("[test] 8. a National Dex blocked level-up still plays the cancel scene")
do
  local session = {}
  local golbat = monAt(GOLBAT, 40)
  golbat.friendship = 255
  local target, blocked = Evolution.levelTarget(golbat, session)
  check(target == nil, "levelTarget refuses CROBAT before the National Dex")
  local raw = Evolution.targetSpecies(golbat, Evolution.EVO_MODE_NORMAL)
  check(raw == CROBAT, "pret's own scan still returns CROBAT, got " .. tostring(raw))
  check(Evolution.nationalAllows(raw, session) == false, "and the Dex gate blocks it")

  local Bag = require("src.core.game3.bag")
  local bag = Bag.new()
  Bag.add(bag, 68, 1) -- ITEM_RARE_CANDY, pokefirered/include/constants/items.h:72
  local started = nil
  local prevScene = package.loaded["src.ui.game3.evolution_scene"]
  package.loaded["src.ui.game3.evolution_scene"] = {
    start = function(mon, postSpecies, opts) started = { mon = mon, to = postSpecies, opts = opts } end,
  }

  PartyMenu.show({ golbat }, nil, {
    mode = "use", item = 68, bag = bag, session = session,
  })
  press("a")
  local guard = 0
  while PartyMenu.isOpen() and not started and guard < 40 do
    press("a")
    guard = guard + 1
  end
  package.loaded["src.ui.game3.evolution_scene"] = prevScene

  check(started ~= nil, "the rare candy path started the evolution scene")
  if started then
    check(started.to == CROBAT, "on the raw pret target, got " .. tostring(started.to))
    check(started.opts.autoCancel == true,
      "with autoCancel so the scene stops itself at the sprite cycle")
  end
  check(golbat.level == 41, "the mon still levelled up, got " .. tostring(golbat.level))
  check(Pokemon.speciesOf(golbat) == GOLBAT, "and did not evolve")
  if PartyMenu.isOpen() then PartyMenu.close() end
end

print("[test] 9. an allowed level-up evolution is untouched")
do
  local session = {}
  local bulba = monAt(BULBASAUR, 15)
  local Bag = require("src.core.game3.bag")
  local bag = Bag.new()
  Bag.add(bag, 68, 1)
  local started = nil
  local prevScene = package.loaded["src.ui.game3.evolution_scene"]
  package.loaded["src.ui.game3.evolution_scene"] = {
    start = function(mon, postSpecies, opts) started = { to = postSpecies, opts = opts } end,
  }

  PartyMenu.show({ bulba }, nil, { mode = "use", item = 68, bag = bag, session = session })
  press("a")
  local guard = 0
  while PartyMenu.isOpen() and not started and guard < 40 do
    press("a")
    guard = guard + 1
  end
  package.loaded["src.ui.game3.evolution_scene"] = prevScene

  check(started ~= nil and started.to == IVYSAUR,
    "BULBASAUR reaching level 16 starts the IVYSAUR scene, got "
      .. tostring(started and started.to))
  check(started and started.opts.autoCancel == false,
    "and the scene is not auto cancelled")
  if PartyMenu.isOpen() then PartyMenu.close() end
end

print("[test] 10. the evolution scene itself honours autoCancel")
do
  local Scene = require("src.ui.game3.evolution_scene")
  local session = {}
  local golbat = monAt(GOLBAT, 40)
  golbat.friendship = 255
  local ended = nil
  Scene.start(golbat, CROBAT, {
    session = session, canStop = true, autoCancel = true, headless = true,
    onDone = function(r) ended = r end,
  })
  local guard = 0
  while Scene._state ~= "cancel" and guard < 4000 do
    Scene.update(1 / 60)
    guard = guard + 1
  end
  -- pokefirered/src/evolution_scene.c:641
  check(Scene._state == "cancel",
    "the blocked scene cancels itself with no B press, state=" .. tostring(Scene._state))
  check(Pokemon.speciesOf(golbat) == GOLBAT,
    "and the GOLBAT is still a GOLBAT, got " .. tostring(Pokemon.speciesOf(golbat)))
  for _ = 1, 20 do
    if not Scene.isOpen() then break end
    pressed = "a"
    Scene.handleInput(input)
    pressed = nil
    Scene.update(1 / 60)
  end
  check(not Scene.isOpen() and ended == "stopped",
    "and the scene ends on the stopped path, got " .. tostring(ended))

  local allowed = monAt(GOLBAT, 40)
  allowed.friendship = 255
  Scene.start(allowed, CROBAT, {
    session = session, canStop = true, autoCancel = false, headless = true,
  })
  guard = 0
  while Pokemon.speciesOf(allowed) == GOLBAT and guard < 4000 do
    Scene.update(1 / 60)
    guard = guard + 1
  end
  check(Pokemon.speciesOf(allowed) == CROBAT,
    "without the flag the same scene still evolves, got " .. tostring(Pokemon.speciesOf(allowed)))
end

-- pokefirered/src/party_menu.c:5674 GetBattleEntryEligibility
print("[test] 11. eligible takes a 0-based slot array as well as a rule function")
do
  local party = sixParty()
  openMulti(party, { onSelect = function() end, eligible = { 0, 2 } })
  check(PartyMenu.slotDescription(1) == "ABLE",
    "slot 1 is in the array and reads ABLE, got " .. tostring(PartyMenu.slotDescription(1)))
  check(PartyMenu.slotDescription(2) == "NOT ABLE",
    "slot 2 is not and reads NOT ABLE, got " .. tostring(PartyMenu.slotDescription(2)))
  check(PartyMenu.slotDescription(3) == "ABLE",
    "slot 3 is in the array and reads ABLE, got " .. tostring(PartyMenu.slotDescription(3)))
  press("a")
  check(PartyMenu.ACTIONS[1] == "ENTER",
    "an array-eligible mon still offers ENTER, got " .. show(PartyMenu.ACTIONS))
  if PartyMenu.isOpen() then PartyMenu.close() end
end

finish()
