#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local AnimSeq = require("src.core.game3.battle.anim_seq")

local function kinds(steps)
  local out = {}
  for _, step in ipairs(steps) do out[#out + 1] = step.kind end
  return table.concat(out, ",")
end

local function missPauses(text, id)
  local steps = AnimSeq.buildSteps({
    { kind = "msg", text = "PIKACHU utilise\nECLAIR!", id = "sText_AttackerUsedX" },
    { kind = "msg", text = text, id = id },
  })
  return kinds(steps):find("pause", 1, true) ~= nil
end

check(missPauses("PIKACHU's\nattack missed!", "STRINGID_ATTACKMISSED"), "a miss pauses")
check(missPauses("PIKACHU\nrate son attaque!", "STRINGID_ATTACKMISSED"), "a translated miss pauses")
check(missPauses("Ça n'affecte pas\nRONFLEX…", "sText_ItDoesntAffect"), "a translated no-effect line pauses")
check(not missPauses("PIKACHU's\nattack missed!", nil), "an English line without an id does not pause")
check(not missPauses("PIKACHU\nest KO!", "STRINGID_TARGETFAINTED"), "another line does not pause")
check(AnimSeq.isMoveUsedId("sText_AttackerUsedX"), "the used-move line is recognised by id")
check(not AnimSeq.isMoveUsedId(nil), "no id is not the used-move line")

print(("game3_battle_translated_text_test: %s (%d failed)"):format(failed == 0 and "PASS" or "FAIL", failed))
if failed > 0 then os.exit(1) end
