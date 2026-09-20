#!/usr/bin/env luajit
-- AnimSeq reads a few battle messages to pace the animation (a missed move
-- pauses, a fainted POKéMON drops).  The messages are translated by then, so
-- it has to recognise them through the catalog's wording, not the English.

package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local Strings = require("src.core.Strings")
local AnimSeq = require("src.core.game3.battle.anim_seq")

local function kinds(steps)
  local out = {}
  for _, step in ipairs(steps) do out[#out + 1] = step.kind end
  return table.concat(out, ",")
end

local function missPauses(text)
  local steps = AnimSeq.buildSteps({
    { kind = "msg", text = "PIKACHU utilise\nECLAIR!" },
    { kind = "msg", text = text },
  })
  return kinds(steps):find("pause", 1, true) ~= nil
end

check(missPauses("PIKACHU's\nattack missed!"), "an English miss pauses")

Strings.load({ strings = {
  ["%s's\nattack missed!"] = "%s\nrate son attaque!",
  ["It doesn't affect\n%s…"] = "Ça n'affecte pas\n%s…",
} })
check(missPauses("PIKACHU\nrate son attaque!"), "a translated miss pauses")
check(missPauses("Ça n'affecte pas\nRONFLEX…"), "a translated no-effect line pauses")
check(not missPauses("PIKACHU\nest KO!"), "another line does not pause")
Strings.load({})

print(("game3_battle_translated_text_test: %s (%d failed)"):format(failed == 0 and "PASS" or "FAIL", failed))
if failed > 0 then os.exit(1) end
