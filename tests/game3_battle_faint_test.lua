#!/usr/bin/env luajit
-- Faint presentation: sink + hide mon/healthbox after "fainted!" dialog.

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

print("[test] 1. Anim.faintMon enemy sinks then hides")
local Anim = require("src.core.game3.battle.anim")
local Task = require("src.core.game3.task")
Anim.reset({ headless = false })
local p = Anim.present("enemy")
p.visible = true
p.oy = 0
local stage = Anim.stage()
stage.healthbox.enemy.visible = true
local done = false
Anim.faintMon("enemy", {
  playSe = false,
  onComplete = function() done = true end,
})
check(Anim.busy() == true, "faint tween busy")
for _ = 1, 40 do
  Task.update(1 / 60)
  Anim.update(1 / 60)
  if done then break end
end
check(done == true, "enemy faint completed")
check(p.visible == false, "enemy mon hidden")
check(stage.healthbox.enemy.visible == false, "enemy healthbox hidden")

print("[test] 2. AnimSeq builds faint step with side")
local AnimSeq = require("src.core.game3.battle.anim_seq")
Anim.reset({ headless = true })
AnimSeq.begin({
  msgs = { "PIDGEY used\nTACKLE!", "WILD RATTATA fainted!" },
  moveId = "TACKLE",
  user = { side = "player" },
  target = { side = "enemy" },
  hits = { { side = "enemy", from = 10, to = 0, maxHp = 10 } },
  faints = { { side = "enemy" } },
}, function() end)
local kinds = {}
for _, s in ipairs(AnimSeq._steps or {}) do
  kinds[#kinds + 1] = s.kind
  if s.kind == "faint" then
    check(s.data.side == "enemy", "faint side enemy")
  end
end
local function idx(k)
  for i, v in ipairs(kinds) do if v == k then return i end end
end
check(idx("msg") and idx("faint") and idx("msg") < idx("faint"), "faint after fainted msg")
check(not idx("faintse"), "uses faint not faintse-only")

print("[test] 3. Engine tags faints list")
local State = require("src.core.game3.battle.state")
local Engine = require("src.core.game3.battle.engine")
local Adapter = require("src.core.game3.battle.adapter")
local st = State.new({
  wild = true,
  playerParty = { { species = 1, level = 5, hp = 20, maxHp = 20, moves = { 33 }, pp = { 35 },
    attack = 50, defense = 10, spAtk = 50, spDef = 10, speed = 50 } },
  foeMon = { species = 16, level = 3, hp = 1, maxHp = 15, moves = { 33 }, pp = { 35 },
    attack = 10, defense = 5, spAtk = 10, spDef = 5, speed = 10 },
})
local ad = Adapter.new(st)
-- Force hit: high damage path via resolve with guaranteed accuracy
local out = {}
-- Make RNG always hit / max damage-ish
st.rng = function(a, b)
  if a == 1 and b == 100 then return 1 end -- accuracy
  if type(a) == "number" and type(b) == "number" then return b end
  return a or 0
end
ad.rng = function(_, lo, hi)
  if lo == 1 and hi == 100 then return 1 end
  if lo and hi then return hi end
  return lo or 0
end
Engine.resolveMove(st.player, st.enemy, 33, 1, ad, st, out)
local anim = out._anim
check(anim and anim.faints and #anim.faints >= 1, "anim.faints populated")
if anim and anim.faints and anim.faints[1] then
  check(anim.faints[1].side == "enemy", "faint side is enemy")
end
local joined = table.concat(out, " || ")
check(joined:find("fainted", 1, true) ~= nil, "fainted message present")

if failed > 0 then
  print("[test] FAILED " .. failed)
  os.exit(1)
end
print("[test] all passed")
