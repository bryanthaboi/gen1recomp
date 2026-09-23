#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path
require("tests.game3_cache").mountOrSkip("game3_battle_forms_intro_test")

package.loaded["src.core.game3.audio"] = setmetatable({}, {
  __index = function() return function() end end,
})

local State = require("src.core.game3.battle.state")
local Adapter = require("src.core.game3.battle.adapter")
local Abilities = require("src.core.game3.battle.abilities")
local Anim = require("src.core.game3.battle.anim")
local AnimSeq = require("src.core.game3.battle.anim_seq")
local IntroSeq = require("src.core.game3.battle.intro_seq")
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
    species = o.species or 1, level = 50, hp = 100, maxHp = 100, attack = 50, defense = 50,
    spAtk = 50, spDef = 50, speed = 50, ability = o.ability, nickname = o.nickname,
    moves = { 33 }, pp = { 20 },
  }
end

print("=== Go! stays on screen through battle-start INTIMIDATE ===")
do
  Anim.reset({ headless = false })
  local st = State.new({
    wild = true,
    playerParty = { mon({ nickname = "ALPHA" }) },
    foeMon = mon({ species = 16, nickname = "PIDGEY" }),
  })
  IntroSeq.begin(st, { pushMsg = function() end, headless = false })
  local goStep
  for _, step in ipairs(IntroSeq._steps or {}) do
    if step.kind == "msg" and tostring(step.data.text):find("^Go! ") then goStep = step end
  end
  check(goStep and goStep.data.linger == true, "wild intro Go! is a lingering (no-wait) print")
  IntroSeq.reset()

  Ui.reset({ headless = false })
  local Message = require("src.ui.game3.message")
  Ui.pushTimed("Go! ALPHA!", 0)
  local guard = 0
  while Ui.dialogPending() and guard < 500 do
    guard = guard + 1
    Message.tick()
    Ui.pump()
  end
  check(not Ui.dialogPending(), "Go! print completes without a button press")
  check(Message.isOpen() and Message.currentPage():find("Go! ALPHA!", 1, true) ~= nil,
    "Go! text still in the textbox when the stat-drop anim starts")
  Ui.pushTimed("PIDGEY's INTIMIDATE\ncuts ALPHA's ATTACK!", 64)
  Ui.pump()
  check(Message.currentPage():find("INTIMIDATE", 1, true) ~= nil, "cut message replaces it")
  Ui.reset({ headless = true })
end

print("=== intimidate at battle start is anim then text ===")
do
  local st = State.new({
    wild = true,
    playerParty = { mon({ nickname = "ALPHA" }) },
    foeMon = mon({ species = 58, nickname = "GROWL", ability = "INTIMIDATE" }),
  })
  st.enemy.ability = "INTIMIDATE"
  local ad = Adapter.new(st)
  local Engine = require("src.core.game3.battle.engine")
  local mark = ad:eventMark()
  ad._say = function() end
  Engine.battleStartEffects(st, ad)
  local evs = ad:eventsSince(mark)
  check(evs[1] and evs[1].kind == "anim" and evs[1].name == "STATS_CHANGE"
    and evs[2] and evs[2].kind == "msg", "STATS_CHANGE anim precedes the cut text")
end

print("=== Castform forms ===")
do
  local st = State.new({
    wild = true,
    playerParty = { mon({ species = 385, nickname = "CAST", ability = "FORECAST" }) },
    foeMon = mon({ species = 385, nickname = "FOECAST", ability = "FORECAST" }),
  })
  st.player.ability, st.enemy.ability = "FORECAST", "FORECAST"
  local ad = Adapter.new(st)
  st.weather = "SUN"
  st.enemy.substituteHP = 10
  local mark = ad:eventMark()
  ad._say = function() end
  Abilities.forecast(ad)
  Abilities.forecast(ad)
  local args = {}
  for _, e in ipairs(ad:eventsSince(mark)) do
    if e.kind == "anim" and e.name == "CASTFORM_CHANGE" then args[e.attacker] = e.arg end
  end
  check(args.player == 1, "sun -> CASTFORM_FIRE arg 1")
  check(args.enemy == 1 + 128, "behind a substitute the arg carries 0x80")

  Anim.reset({ headless = true })
  local Battle = require("src.core.game3.battle.init")
  package.loaded["src.core.game3.battle"] = Battle
  Battle._st = st
  AnimSeq.beginEvents(ad:eventsSince(mark), function() end)
  for _ = 1, 20 do AnimSeq.update() end
  local pe, pp = Anim.present("enemy"), Anim.present("player")
  check(pe.castformForm == 1 and pe.castformMon == st.enemy.mon, "0x80 path sets the form without the anim")
  check(pp.castformForm == 1, "anim path lands the new form")
  check(Ui.castformForm("enemy", st.enemy) == 1, "Ui reads the enemy form")
  local base = { x = 176, y = 40 }
  local _, y1 = Ui.battlerSpriteCenter("enemy", 385, base, 1, false)
  local _, y0 = Ui.battlerSpriteCenter("enemy", 385, base, 0, false)
  check(y1 == 40 + 9 - 14 and y0 == 40 + 17 - 13, "per-form y_offset and elevation")
  local _, yb = Ui.battlerSpriteCenter("player", 385, { x = 72, y = 80 }, 2, false)
  check(yb == 80 + 0 + 4, "castform back sprite y offset 0")
  local fresh = State.makeBattler(mon({ species = 385 }), "enemy", {})
  check(Ui.castformForm("enemy", fresh) == 0, "a different mon switched in reads NORMAL")
  st.weather = nil
  st.enemy.substituteHP = 0
  local m2 = ad:eventMark()
  Abilities.forecast(ad)
  local back
  for _, e in ipairs(ad:eventsSince(m2)) do
    if e.kind == "anim" and e.name == "CASTFORM_CHANGE" then back = e.arg end
  end
  check(back == 0, "weather ends -> CASTFORM_NORMAL anim")
  Battle._st = nil
end

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
