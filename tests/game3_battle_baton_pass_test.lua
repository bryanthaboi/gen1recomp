#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path
require("tests.game3_cache").requireData("game3_battle_baton_pass_test")

package.loaded["src.core.game3.audio"] = setmetatable({}, {
  __index = function() return function() end end,
})

local Moves = require("src.core.game3.battle.moves")
local ROM = {
  [16] = { effect = 149, power = 40, type = 2, accuracy = 100, pp = 35, secondaryChance = 0, target = 0, priority = 0, flags = 50 },
  [33] = { effect = 0, power = 35, type = 0, accuracy = 95, pp = 35, secondaryChance = 0, target = 0, priority = 0, flags = 51 },
  [93] = { effect = 76, power = 50, type = 14, accuracy = 100, pp = 25, secondaryChance = 10, target = 0, priority = 0, flags = 18 },
  [226] = { effect = 127, power = 0, type = 0, accuracy = 0, pp = 40, secondaryChance = 0, target = 16, priority = 0, flags = 0 },
}
Moves._romLoaded = true
Moves._rom = ROM
Moves.loadRomPack = function()
  Moves._romLoaded = true
  Moves._rom = ROM
  return true
end

local State = require("src.core.game3.battle.state")
local Engine = require("src.core.game3.battle.engine")
local Adapter = require("src.core.game3.battle.adapter")
local Types = require("src.core.game3.battle.types")

local failed, passed = 0, 0
local function check(cond, msg)
  if cond then
    passed = passed + 1
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function mon(o)
  return {
    species = o.species or 1, level = 50, hp = o.hp or 100, maxHp = 100,
    attack = 50, defense = 50, spAtk = 50, spDef = 50, speed = 50,
    ability = 0, nickname = o.nickname, moves = o.moves or { 33 }, pp = { 20, 20, 20, 20 },
  }
end

local function battle(party, foeParty)
  local st = State.new({ wild = false, playerParty = party, foeParty = foeParty })
  st.trainerClassName, st.trainerName = "YOUNGSTER", "BEN"
  st.rng = function(lo, hi) if lo == 1 and hi == 100 then return 1 end return hi end
  return st, Adapter.new(st)
end

local function kinds(out)
  local k = {}
  for _, ev in ipairs(out._anim.events or {}) do k[#k + 1] = ev.kind end
  return table.concat(k, ",")
end

print("=== player Baton Pass pauses for the party menu ===")
do
  local st, ad = battle({
    mon({ nickname = "ALPHA", moves = { 226 } }),
    mon({ nickname = "BETA" }),
    mon({ nickname = "GAMMA" }),
  }, { mon({ nickname = "FOE" }) })
  st.player.stages.attack = 2
  st.player.substituteHP = 25
  st.player.confusionTurns = 3
  st.interactiveChoices = true
  local out = {}
  Engine.resolveMove(st.player, st.enemy, 226, 1, ad, st, out)
  check(out.pendingChoice and out.pendingChoice.kind == "baton_pass", "resolve returns a baton_pass choice")
  check(#out.pendingChoice.candidates == 2, "two eligible bench mons")
  check(st.player.partyIndex == 1, "no switch before the choice")
  check(kinds(out):find("move", 1, true) ~= nil and kinds(out):find("switch", 1, true) == nil,
    "first half is attack string + anim only")
  check(st.player.mon.pp[1] == 19, "PP spent before the party screen")

  local out2 = Engine.resumeChoice(st, ad, 3)
  check(st.pendingChoice == nil and out2.pendingChoice == nil, "choice consumed")
  check(st.player.partyIndex == 3 and State.displayName(st.player) == "GAMMA", "picked slot 3 switched in")
  check(st.player.stages.attack == 2 and st.player.substituteHP == 25 and st.player.confusionTurns == 2,
    "stat stages, substitute and confusion passed")
  local goMsg
  for _, ev in ipairs(out2._anim.events) do
    if ev.kind == "msg" and ev.text == "Go! GAMMA!" then goMsg = ev end
  end
  check(goMsg and goMsg.wait == 0, "Go! text before switchinanim without waitmessage")
  local sw
  for _, ev in ipairs(out2._anim.events) do
    if ev.kind == "switch" and ev.reason == "baton_pass" then sw = ev end
  end
  check(sw and sw.from == 1 and sw.to == 3, "switch event 1 -> 3")
end

print("=== non-interactive keeps first eligible ===")
do
  local st, ad = battle({
    mon({ nickname = "ALPHA", moves = { 226 } }),
    mon({ nickname = "BETA" }),
    mon({ nickname = "GAMMA" }),
  }, { mon({ nickname = "FOE" }) })
  local out = {}
  Engine.resolveMove(st.player, st.enemy, 226, 1, ad, st, out)
  check(out.pendingChoice == nil and st.player.partyIndex == 2, "headless picks slot 2")
end

print("=== enemy Baton Pass uses GetMostSuitableMonToSwitchInto ===")
do
  local function run(rattataMoves)
    local st, ad = battle({ mon({ nickname = "ALPHA" }) }, {
      mon({ nickname = "PASSER", moves = { 226 } }),
      mon({ species = 16, nickname = "PIDGEY", moves = { 16 } }),
      mon({ species = 19, nickname = "RATTATA", moves = rattataMoves }),
    })
    st.player.type1, st.player.type2 = Types.ID.FIGHTING, nil
    return st, ad
  end
  local st, ad = run({ 33 })
  check(Engine.mostSuitableMon(st, ad, "enemy") == 2,
    "weakest-typed RATTATA has no SE move, falls to PIDGEY with GUST")
  local st2, ad2 = run({ 93 })
  check(Engine.mostSuitableMon(st2, ad2, "enemy") == 3, "RATTATA with CONFUSION wins on typing")
  local out = {}
  st2.interactiveChoices = true
  Engine.resolveMove(st2.enemy, st2.player, 226, 1, ad2, st2, out)
  check(out.pendingChoice == nil and st2.enemy.partyIndex == 3, "enemy never pauses; AI pick switched in")
end

print("=== Battle flow opens the party menu (can't cancel) ===")
do
  local shown
  package.loaded["src.ui.game3.party_menu"] = {
    show = function(party, overlay, opts) shown = opts end,
    isOpen = function() return false end,
  }
  local Battle = require("src.core.game3.battle.init")
  local Ui = require("src.core.game3.battle.ui")
  local Anim = require("src.core.game3.battle.anim")
  local st, ad = battle({
    mon({ nickname = "ALPHA", moves = { 226 } }),
    mon({ nickname = "BETA" }),
    mon({ nickname = "GAMMA" }),
  }, { mon({ nickname = "FOE" }) })
  Ui.reset({ headless = true })
  Anim.reset({ headless = true })
  Battle._active = true
  Battle._st, Battle._adapter = st, ad
  Battle._headless, Battle._auto = false, false
  Battle._actions = { { user = st.player, target = st.enemy, move = 226, slot = 1 } }
  Battle._actionI = 1
  Battle._metaAct = nil
  Battle._phase = "actions"
  Battle.update(0, nil)
  check(Battle._pendingChoice and Battle._pendingChoice.kind == "baton_pass", "step_action keeps the pending choice")
  Battle._openPendingChoiceForTests()
  check(shown and shown.mode == "battle_faint", "party menu in forced-send-out mode")
  check(shown.validate(1) ~= nil and shown.validate(2) == nil, "active mon rejected, bench accepted")
  shown.onSelect(3)
  check(st.player.partyIndex == 3 and Battle._phase == "animating", "selection resumes the move")
  Battle._active = false
  Battle._st = nil
end

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
