#!/usr/bin/env luajit
-- pokefirered/src/battle_script_commands.c:9617 Cmd_givecaughtmon
-- pokefirered/data/battle_scripts_2.s:87 trygivecaughtmonnick

package.path = "./?.lua;./?/init.lua;" .. package.path
require("tests.game3_cache").mountOrSkip("game3_stitchbattle_pc_transfer_test", "scripts/text.lua")
require("tests.fixture_data.game3_items").install()

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function has(s, sub)
  return type(s) == "string" and s:find(sub, 1, true) ~= nil
end

local function flat(s)
  return tostring(s):gsub("\n", " "):gsub("\f", " | ")
end

package.loaded["src.ui.game3.stack"] = {
  push = function() end,
  pop = function() end,
  busy = function() return false end,
  drawOrder = function() return {} end,
}

local Flags = require("src.core.game3.scripting.flags")
local Storage = require("src.core.game3.storage")
local Dex = require("src.core.game3.dex")
local Runtime = require("src.core.game3.runtime")
local Catching = require("src.core.game3.battle.catching")
local CatchSeq = require("src.core.game3.battle.catch_seq")
local BattleItems = require("src.core.game3.battle.items")
local Bag = require("src.core.game3.bag")

local FLAG_SYS_NOT_SOMEONES_PC = 0x834
local FLAG_SHOWN_BOX_WAS_FULL_MESSAGE = 0x843
local VAR_PC_BOX_TO_SEND_MON = 0x4037

local function filler(sp)
  return { species = sp, speciesId = sp, name = "RATTATA", level = 5, hp = 20, maxHp = 20, nickname = "" }
end

local function caterpie()
  return { species = 10, speciesId = 10, name = "CATERPIE", level = 3, hp = 6, maxHp = 6, nickname = "" }
end

local function new_session(fillBox1)
  local s = { name = "RED", store = Flags.newStore(), dex = Dex.new(), party = {} }
  for i = 1, 6 do s.party[i] = filler(19) end
  Storage.ensure(s)
  s.storage.currentBox = 1
  if fillBox1 then
    for slot = 1, Storage.IN_BOX_COUNT do s.storage.boxes[1].mons[slot] = filler(19) end
  end
  Dex.registerCapture(s.dex, 10)
  Runtime.session = s
  Flags.setFlag(s.store, nil, FLAG_SHOWN_BOX_WAS_FULL_MESSAGE, false)
  Flags.setFlag(s.store, nil, FLAG_SYS_NOT_SOMEONES_PC, false)
  Flags.setVar(s.store, nil, VAR_PC_BOX_TO_SEND_MON, 0)
  return s
end

local function foe_state(session)
  local mon = caterpie()
  local enemy = { species = 10, level = 3, hp = 6, maxHp = 6, mon = mon }
  return { wild = true, enemy = enemy, player = { mon = session.party[1] }, playerName = "RED" }, enemy
end

local prevSession = Runtime.getSession and Runtime.getSession() or nil

print("[test] 1. the headless ball path prints pret's Someone's PC line, not the hand-written one")
local s1 = new_session(false)
local st1 = foe_state(s1)
local msgs1 = {}
CatchSeq.begin(st1, 4, true, 4, {
  headless = true,
  session = s1,
  pushMsg = function(t) msgs1[#msgs1 + 1] = t end,
})
local line1
for _, m in ipairs(msgs1) do if has(m, "transferred") then line1 = m end end
check(line1 ~= nil, "a transfer line was printed")
check(not has(line1 or "", "to the PC."), "the hand-written 'was transferred to the PC.' string is gone")
check(has(line1 or "", "CATERPIE was transferred to\nSomeone's PC."),
  "pret STRINGID_PKMNTRANSFERREDSOMEONESPC: " .. flat(line1))
check(has(line1 or "", "It was placed in \nBOX “BOX 1.”"), "and it names the box it was placed in")

print("[test] 2. FLAG_SYS_NOT_SOMEONES_PC swaps in BILL'S PC")
local s2 = new_session(false)
Flags.setFlag(s2.store, nil, FLAG_SYS_NOT_SOMEONES_PC, true)
local st2 = foe_state(s2)
local msgs2 = {}
CatchSeq.begin(st2, 4, true, 4, {
  headless = true,
  session = s2,
  pushMsg = function(t) msgs2[#msgs2 + 1] = t end,
})
local line2
for _, m in ipairs(msgs2) do if has(m, "transferred") then line2 = m end end
check(has(line2 or "", "CATERPIE was transferred to\nBILL'S PC."),
  "pret STRINGID_PKMNTRANSFERREDBILLSPC: " .. flat(line2))
Flags.setFlag(s2.store, nil, FLAG_SYS_NOT_SOMEONES_PC, false)

print("[test] 3. a spillover names the box that was full first")
local s3 = new_session(true)
local st3 = foe_state(s3)
local msgs3 = {}
CatchSeq.begin(st3, 4, true, 4, {
  headless = true,
  session = s3,
  pushMsg = function(t) msgs3[#msgs3 + 1] = t end,
})
local line3
for _, m in ipairs(msgs3) do if has(m, "transferred") then line3 = m end end
check(has(line3 or "", "BOX “BOX 1” on\nSomeone's PC was full."),
  "pret STRINGID_PKMNBOXSOMEONESPCFULL: " .. flat(line3))
check(has(line3 or "", "CATERPIE was transferred to\nBOX “BOX 2.”"),
  "and the mon went to BOX 2")
check(s3.storage.boxes[2].mons[1] ~= nil, "the caught mon really is in box 2")

print("[test] 4. the bag-item ball path uses the same four strings")
local s4 = new_session(false)
local st4 = foe_state(s4)
s4.bag = Bag.new()
Bag.add(s4.bag, 1, 1)
local _, msgs4 = BattleItems.use(st4, nil, s4.bag, s4, 1, nil, nil)
local line4
for _, m in ipairs(msgs4 or {}) do if has(m, "transferred") then line4 = m end end
check(line4 ~= nil, "a transfer line was printed for the bag path")
check(not has(line4 or "", "to the PC."), "the hand-written string is gone from items.lua too")
check(has(line4 or "", "CATERPIE was transferred to\nSomeone's PC."),
  "pret line from the bag path: " .. flat(line4))

print("[test] 5. an empty nickname never leaks into the caught line")
local s5 = new_session(false)
local st5 = foe_state(s5)
local msgs5 = {}
CatchSeq.begin(st5, 4, true, 4, {
  headless = true,
  session = s5,
  pushMsg = function(t) msgs5[#msgs5 + 1] = t end,
})
local gotcha
for _, m in ipairs(msgs5) do if has(m, "Gotcha!") then gotcha = m end end
check(has(gotcha or "", "CATERPIE was caught!"), "Gotcha line names the species: " .. flat(gotcha))

local Battle = require("src.core.game3.battle")
local BattleUi = require("src.core.game3.battle.ui")
local Choice = require("src.ui.game3.choice")
local Message = require("src.ui.game3.message")
local Naming = require("src.ui.game3.naming")

local mockInput = {
  _pressed = {},
  press = function(self, key) self._pressed[key] = true end,
  clear = function(self) self._pressed = {} end,
  isDown = function(self, key) return self._pressed[key] == true end,
  wasPressed = function(self, key)
    if self._pressed[key] then
      self._pressed[key] = false
      return true
    end
    return false
  end,
}
function mockInput:consume(key)
  return self:wasPressed(key)
end

local function run_to_choice()
  local guard = 0
  while Message.isOpen() and not Choice.active and guard < 4000 do
    Message.tick()
    BattleUi.pump()
    guard = guard + 1
  end
end

local function log_after(mark)
  local out = {}
  for i = mark + 1, #(BattleUi._log or {}) do out[#out + 1] = BattleUi._log[i] end
  return out
end

print("[test] 6. declining the nickname prints the pret line with the species name")
local s6 = new_session(true)
local st6, enemy6 = foe_state(s6)
Battle.start({
  wild = true,
  playerParty = s6.party,
  foe = st6.enemy,
  headless = false,
  session = s6,
})
local catchRes6 = Catching.storeCaught(s6, enemy6, 4)
check(catchRes6 and catchRes6.location == "pc", "the catch really overflowed into the PC")
local mark6 = #(BattleUi._log or {})
Battle.startPostCatchFlow(catchRes6)
run_to_choice()
check(Choice.active == true, "the nickname Yes/No is up")
mockInput:clear()
mockInput:press("b")
Battle.update(1 / 60, { input = mockInput })
check(not Naming.isOpen(), "declining does not open the keyboard")
check(Battle._phase == "catch_pc_msg", "phase is catch_pc_msg (got " .. tostring(Battle._phase) .. ")")
local line6
for _, m in ipairs(log_after(mark6)) do if has(m, "transferred") then line6 = m end end
check(line6 ~= nil, "a transfer line reached the battle log")
check(not has(line6 or "", "to the PC."), "init.lua no longer hand-writes the line")
check(has(line6 or "", "BOX “BOX 1” on\nSomeone's PC was full."),
  "the box-was-full page is pret's: " .. flat(line6))
check(has(line6 or "", "CATERPIE was transferred to\nBOX “BOX 2.”"), "and the species name is used")

print("[test] 7. naming the caught mon skips the line, as trygivecaughtmonnick does")
local s7 = new_session(true)
local st7, enemy7 = foe_state(s7)
Battle.start({
  wild = true,
  playerParty = s7.party,
  foe = st7.enemy,
  headless = false,
  session = s7,
})
local catchRes7 = Catching.storeCaught(s7, enemy7, 4)
check(catchRes7 and catchRes7.location == "pc", "the second catch also overflowed into the PC")
local mark7 = #(BattleUi._log or {})
Battle.startPostCatchFlow(catchRes7)
run_to_choice()
mockInput:clear()
mockInput:press("a")
Battle.update(1 / 60, { input = mockInput })
check(Naming.isOpen(), "accepting opens the keyboard")
Naming.close("AAAAAAAAAA")
check(catchRes7.mon.nickname == "AAAAAAAAAA", "the typed nickname was applied to the boxed mon")
local leaked = nil
for _, m in ipairs(log_after(mark7)) do
  if has(m, "transferred") then leaked = m end
end
check(leaked == nil, "no transfer line is printed on the nickname branch (got " .. flat(leaked) .. ")")
check(Battle._phase == "ending", "battle goes straight to ending (got " .. tostring(Battle._phase) .. ")")

print("[test] 8. the nickname branch still runs givecaughtmon's ShouldShowBoxWasFullMessage")
check(Flags.getFlag(s7.store, nil, FLAG_SHOWN_BOX_WAS_FULL_MESSAGE) and true or false,
  "FLAG_SHOWN_BOX_WAS_FULL_MESSAGE is set after the nicknamed catch")
local st8, enemy8 = foe_state(s7)
Battle.start({
  wild = true,
  playerParty = s7.party,
  foe = st8.enemy,
  headless = false,
  session = s7,
})
local catchRes8 = Catching.storeCaught(s7, enemy8, 4)
check(catchRes8 and catchRes8.location == "pc", "the next catch overflows into the PC too")
local mark8 = #(BattleUi._log or {})
Battle.startPostCatchFlow(catchRes8)
run_to_choice()
mockInput:clear()
mockInput:press("b")
Battle.update(1 / 60, { input = mockInput })
local line8
for _, m in ipairs(log_after(mark8)) do if has(m, "transferred") then line8 = m end end
check(has(line8 or "", "CATERPIE was transferred to\nSomeone's PC."),
  "the declined catch after it gets the plain line: " .. flat(line8))
check(not has(line8 or "", "was full"), "and not a second box-was-full page")

Runtime.session = prevSession

if failed > 0 then
  print(string.format("\n%d PC-transfer test(s) failed.", failed))
  os.exit(1)
end
print("\nAll PC-transfer tests passed.")
