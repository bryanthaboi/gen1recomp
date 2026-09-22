#!/usr/bin/env luajit
-- data/specials.inc:170, src/party_menu_specials.c:14-22, src/start_menu.c:215-216, data/scripts/questionnaire.inc:4

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
    print("[test] FAILED " .. failed)
    os.exit(1)
  end
  print("[test] all passed")
  os.exit(0)
end

local session = {
  trainerId = 4242,
  party = { { species = 1, nickname = "", otId = 4242 },
            { species = 4, nickname = "", otId = 4242 } },
}
package.loaded["src.core.game3.runtime"] = {
  getSession = function() return session end,
  isActive = function() return true end,
}

local Flags = require("src.core.game3.scripting.flags")
local Std = require("src.core.game3.scripting.stdscripts")
local Vm = require("src.core.game3.scripting.vm")

print("[test] 1. a new game opens with the world in its hiding state")
local store = Flags.newStore()
Flags.applyNewGameHideFlags(store)
check(Flags.getFlag(store, nil, 0x02B) == true, "lab Oak starts hidden (FLAG_HIDE_OAK_IN_HIS_LAB 0x2B)")
check(Flags.getFlag(store, nil, 0x02C) == true, "Pallet Town Oak starts hidden (0x2C)")
check(Flags.getFlag(store, nil, 0x092) == true, "Pewter running-shoes guide starts hidden (0x92)")
check(Flags.getFlag(store, nil, 0x033) == true, "Bill's sea-cottage form starts hidden (0x33)")
check(Flags.getFlag(store, nil, 0x035) == true, "Fuji starts hidden in the Lavender house (0x35)")
check(Flags.getFlag(store, nil, 0x0AE) == true, "Sabrina's journals start hidden (0xAE)")
check(Flags.getFlag(store, nil, 0x829) == false,
  "FLAG_SYS_POKEDEX_GET stays clear until a dex event grants it")
check(Flags.getVar(store, nil, Flags.VAR_IDS.VAR_MASSAGE_COOLDOWN_STEP_COUNTER) == 500,
  "the massage step counter opens at 500")

print("[test] 2. the dex-grant event yields to the party picker and resumes")
local pickedMenu, pending
local vm = Vm.new({
  store = store,
  scripts = {
    ["scenario:oak_grants_dex"] = {
      { op = "special", [1] = Std.SPECIAL.ChoosePartyMon }, -- data/specials.inc:170
      { op = "setvar", [1] = 0x4031, [2] = 1 },
      { op = "setflag", [1] = 0x829 },
      -- start_menu.c:217-218
      { op = "setflag", [1] = 0x828 },
      { op = "end" },
    },
  },
  adapters = {
    log = function() end,
    chooseParty = function(opts, done)
      pickedMenu = opts.menuType
      pending = done
    end,
  },
})
check(vm:start("scenario:oak_grants_dex") == true, "the event script starts")
check(pickedMenu == "choose_single",
  "the party picker opens in choose_single mode (party_menu_specials.c:20)")
check(vm:isRunning() == true, "the script holds while the picker is up")
check(vm.ctx.nativePoll ~= nil and vm.ctx.nativePoll() == false,
  "the native still reports waiting before the pick")
if pending then pending(1) end
check(Flags.getVar(nil, vm.ctx, 0x8004) == 1,
  "the picked 0-based slot lands in VAR_0x8004 (got "
    .. tostring(Flags.getVar(nil, vm.ctx, 0x8004)) .. ")")
check(vm.ctx.nativePoll() == true, "the native reports finished after the callback")
vm:tick()
check(vm:isRunning() == false, "the script resumes and runs to the end")
check(Flags.getVar(store, nil, 0x4031) == 1, "VAR_STARTER_MON recorded the starter")
check(Flags.getFlag(store, nil, 0x829) == true,
  "the event granted FLAG_SYS_POKEDEX_GET to the store")

print("[test] 3. the granted flag flips the start-menu Pokédex branch both ways")
package.loaded["src.core.game3.scripting.space"] = { store = store, active = false }
local StartMenu = require("src.ui.game3.start_menu")

local function hasRow(id)
  for _, e in ipairs(StartMenu.ENTRIES) do
    if e.id == id then return true end
  end
  return false
end
local function openMenu()
  StartMenu.show({ session = { name = "TESTER" } })
end

openMenu()
check(hasRow("pokedex"),
  "with FLAG_SYS_POKEDEX_GET set the POKéDEX row appears (start_menu.c:215)")
check(StartMenu.ENTRIES[1] and StartMenu.ENTRIES[1].id == "pokedex",
  "POKéDEX leads the menu in retail order")
StartMenu.close(true)

Flags.setFlag(store, nil, 0x829, false)
openMenu()
check(not hasRow("pokedex"), "clearing the flag with the real Flags API drops the row")
check(StartMenu.ENTRIES[1] and StartMenu.ENTRIES[1].id == "pokemon",
  "POKéMON leads the menu instead")
StartMenu.close(true)

Flags.setFlag(store, nil, 0x829, true)
openMenu()
check(hasRow("pokedex"), "setting the flag again flips the branch back on")
check(StartMenu.ENTRIES[1] and StartMenu.ENTRIES[1].id == "pokedex",
  "and POKéDEX returns to the top slot")
StartMenu.close(true)

print("[test] 4. a cache-backed object-interaction event runs end to end")
local Cache = require("tests.game3_cache")
local bundle = Cache.bundle("objects/pack.lua")
if not bundle then
  print("[skip] game3_scenario_event_test object event: " .. tostring(Cache.reason))
  finish()
end

check(bundle.scripts["EventScript_Questionnaire"] ~= nil,
  "EventScript_Questionnaire is seeded into the objects pack")
local messages, asked = {}, false
local objVm = Vm.new({
  scripts = bundle.scripts, text = bundle.text, movements = bundle.movements,
  onMessage = function(text) messages[#messages + 1] = text end,
  askYesNo = function(cb) asked = true; cb(false) end, -- questionnaire.inc:35
})
if not objVm:start("EventScript_Questionnaire") then
  check(false, "EventScript_Questionnaire starts from the bundle")
else
  for _ = 1, 200 do objVm:tick() end
  check(#messages == 1, "the event shows one prompt (got " .. #messages .. ")")
  check((table.concat(messages, " "):lower()):find("questionnaire", 1, true) ~= nil,
    "the prompt asks about the questionnaire (questionnaire.inc:4)")
  check(asked, "the yes/no box reached the player")
  check(objVm:isRunning() == false, "declining releases control (questionnaire.inc:35)")
end

finish()
