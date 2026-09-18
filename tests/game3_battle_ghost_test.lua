#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path

package.loaded["src.core.game3.audio"] = setmetatable({}, {
  __index = function() return function() end end,
})

local Moves = require("src.core.game3.battle.moves")
local ROM = {
  [33] = { effect = 0, power = 35, type = 0, accuracy = 95, pp = 35, secondaryChance = 0, target = 0, priority = 0, flags = 51 },
  [45] = { effect = 18, power = 0, type = 0, accuracy = 100, pp = 40, secondaryChance = 0, target = 8, priority = 0, flags = 22 },
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
local Abilities = require("src.core.game3.battle.abilities")
local Residuals = require("src.core.game3.battle.residual_handlers")
local CatchSeq = require("src.core.game3.battle.catch_seq")
local Ui = require("src.core.game3.battle.ui")

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
    attack = 50, defense = 50, spAtk = 50, spDef = 50, speed = o.speed or 50,
    ability = o.ability or 0, nickname = o.nickname, moves = o.moves or { 33 }, pp = { 20, 20, 20, 20 },
  }
end

local function battle(opts)
  opts = opts or {}
  local st = State.new({
    wild = true,
    playerParty = { mon({ nickname = "ALPHA", ability = opts.playerAbility }) },
    foeParty = { mon({ species = opts.foeSpecies or 92, nickname = "GHOST" }) },
  })
  st.ghostBattle = true
  st.ghostUnveiled = opts.unveiled
  st.rng = function(lo, hi) if lo == 1 and hi == 100 then return 1 end return hi end
  return st, Adapter.new(st)
end

local function use(st, ad, user, move)
  local target = (user == st.player) and st.enemy or st.player
  local out = {}
  Engine.resolveMove(user, target, move, 1, ad, st, out)
  return table.concat(out, " || "), out
end

local function find_event(out, pred)
  for _, ev in ipairs(out._anim.events or {}) do
    if pred(ev) then return ev end
  end
end

print("=== player too scared to move ===")
do
  local st, ad = battle()
  local txt, out = use(st, ad, st.player, 33)
  check(txt:find("ALPHA is too scared to move!", 1, true) ~= nil, "too scared text")
  check(txt:find("used", 1, true) == nil, "no attack string")
  check(st.enemy.mon.hp == 100, "ghost takes no damage")
  check(st.player.mon.pp[1] == 20, "no PP spent")
  check(find_event(out, function(e) return e.kind == "anim" and e.name == "MON_SCARED" end) ~= nil,
    "MON_SCARED general anim launched")
end

print("=== ghost Get out ===")
do
  local st, ad = battle()
  local txt, out = use(st, ad, st.enemy, 33)
  check(txt:find("GHOST: Get out…… Get out……", 1, true) ~= nil, "Get out text")
  check(st.player.mon.hp == 100, "player takes no damage")
  local msg = find_event(out, function(e) return e.kind == "msg" and e.text:find("Get out", 1, true) end)
  check(msg and msg.wait == 0, "Get out text has no waitmessage (anim plays under it)")
  local gi = find_event(out, function(e) return e.kind == "anim" and e.name == "GHOST_GET_OUT" end)
  check(gi ~= nil and gi.attacker == "enemy", "GHOST_GET_OUT general anim on the ghost")
end

print("=== silph scope unveiled battles fight normally ===")
do
  local st, ad = battle({ unveiled = true, foeSpecies = 105 })
  local txt = use(st, ad, st.player, 33)
  check(txt:find("used", 1, true) ~= nil and st.enemy.mon.hp < 100, "unveiled ghost can be hit")
end

print("=== run / intimidate / weather ===")
do
  local st, ad = battle()
  st.player.mon.speed = 1
  st.enemy.mon.speed = 255
  check(Engine.tryFlee(st, ad, st.player) == true, "player always escapes a ghost")
  local st2, ad2 = battle({ playerAbility = "INTIMIDATE" })
  st2.player.ability = "INTIMIDATE"
  check(Abilities.switchIn(ad2, st2.player) == false and not st2.player.expIntimidatePending,
    "INTIMIDATE does not activate in a ghost battle")
  check(Abilities.runIntimidate(ad2) == false and st2.enemy.stages.attack == 0, "ghost attack not cut")
  local st3, ad3 = battle()
  st3.weather, st3.weatherTurns = "SAND", 3
  local mark = ad3:eventMark()
  ad3._say = function() end
  Residuals.tickWeather(ad3)
  local buffetedGhost, buffetedPlayer = false, false
  for _, e in ipairs(ad3:eventsSince(mark)) do
    if e.kind == "msg" and e.text:find("buffeted", 1, true) then
      if e.text:find("GHOST", 1, true) then buffetedGhost = true else buffetedPlayer = true end
    end
  end
  check(not buffetedGhost and buffetedPlayer, "sandstorm skips the ghost only")
end

print("=== ball dodge ===")
do
  local st = battle()
  local msgs = {}
  CatchSeq.begin(st, 4, false, 0, {
    headless = true, ghostDodge = true, pushMsg = function(t) msgs[#msgs + 1] = t end,
    session = { name = "RED" },
  })
  check(msgs[#msgs] == "It dodged the thrown BALL!\nThis POKéMON can't be caught!", "dodge text")
  check(CatchSeq.result() == "fail_catch", "no catch")
end

print("=== headless battle flow ===")
do
  local Battle = require("src.core.game3.battle.init")
  local Damage = require("src.core.game3.battle.damage")
  local pMon = Damage.ensureStats({ species = 1, level = 30, hp = 90, maxHp = 90, moves = { 33 }, pp = { 35 } })
  local foe = { species = 92, level = 20, hp = 50, maxHp = 50, moves = { 33 }, pp = { 35 }, ghost = true }
  Battle.start({ headless = true, autoFight = false, playerParty = { pMon }, foe = foe, wild = true })
  local st = Battle.getState()
  check(st.ghostBattle == true and st.enemy.mon.nickname == "GHOST", "foe.ghost starts a GHOST battle")
  local log = Ui.log()
  check(log[1] == "The GHOST appeared!\\pDarn!\nThe GHOST can't be ID'd!", "can't be ID'd intro")
  check(log[2] == "Go! BULBASAUR!", "then Go!")
  Battle._phase = "command"
  Ui._pendingCommand = { kind = "bag", itemId = 4, user = "player" }
  Battle.update(0, nil)
  for _ = 1, 6 do Battle.update(0, nil) end
  log = Ui.log()
  local dodged, getOut = false, false
  for _, t in ipairs(log) do
    if t:find("dodged the thrown BALL", 1, true) then dodged = true end
    if t:find("Get out", 1, true) then getOut = true end
  end
  check(dodged and getOut and Battle.isActive(), "ball dodged, ghost acts, battle continues")
  Battle.abort()

  local foe2 = { species = 105, level = 30, hp = 60, maxHp = 60, moves = { 33 }, pp = { 35 }, ghost = true, ghostUnveiled = true }
  Battle.start({ headless = true, autoFight = false, playerParty = { pMon }, foe = foe2, wild = true })
  st = Battle.getState()
  log = Ui.log()
  check(log[1] == "The GHOST appeared!" and log[2] == "SILPH SCOPE unveiled the GHOST's\nidentity!"
    and log[3] == "The GHOST was MAROWAK!", "silph scope reveal text")
  check(st.enemy.mon.nickname == nil and State.displayName(st.enemy) ~= "GHOST", "unveiled name restored")
  Battle.abort()
end

print("=== pic placement ===")
do
  local base = { x = 176, y = 40 }
  local _, gy = Ui.battlerSpriteCenter("enemy", 92, base, 0, true)
  check(gy == 40, "GHOST pic sits at BATTLER_COORD_Y")
  local _, ny = Ui.battlerSpriteCenter("enemy", 92, base, 0, false)
  check(ny ~= 40, "real mon uses pic offset")
end

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
