#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path
require("tests.game3_cache").mountOrSkip("game3_learn_move_test", "scripts/text.lua")

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local Message = { open = false, _stay = false, _done = nil, _waiting = false, shown = {} }
function Message.show(text, opts)
  opts = type(opts) == "table" and opts or {}
  Message.open = true
  Message._stay = opts.stay and true or false
  Message._done = opts.done
  Message._waiting = false
  Message.shown[#Message.shown + 1] = tostring(text)
  return Message
end
function Message.showStay(text, opts)
  opts = opts or {}
  opts.stay = true
  return Message.show(text, opts)
end
function Message.isOpen() return Message.open end
function Message.isWaiting() return Message.open and Message._waiting end
function Message.isTyping() return Message.open and not Message._waiting end
function Message.tick()
  if Message.open then Message._waiting = true end
end
function Message.skipReveal()
  if Message.open then Message._waiting = true end
end
function Message.close()
  local done = Message._done
  Message.open = false
  Message._stay = false
  Message._waiting = false
  Message._done = nil
  if done then done() end
end
package.loaded["src.ui.game3.message"] = Message

local Summary = { open = false, opens = 0, last = nil }
function Summary.openMenu(party, idx, opts)
  Summary.open = true
  Summary.opens = Summary.opens + 1
  Summary.last = { party = party, idx = idx, opts = opts or {} }
end
function Summary.isOpen() return Summary.open end
function Summary.pick(slotIdx)
  local o = Summary.last and Summary.last.opts or {}
  Summary.open = false
  if o.onSelectMove then o.onSelectMove(slotIdx) end
end
package.loaded["src.ui.game3.summary_menu"] = Summary

local Battle = require("src.core.game3.battle")
local Ui = require("src.core.game3.battle.ui")
local LearnMove = require("src.core.game3.battle.learn_move")
local Choice = require("src.ui.game3.choice")

local function idx_of(shown, needle, from)
  for i = from or 1, #shown do
    if shown[i]:find(needle, 1, true) then return i end
  end
  return nil
end

local function in_order(shown, needles)
  local at = 0
  for _, n in ipairs(needles) do
    local i = idx_of(shown, n, at + 1)
    if not i then return false, n end
    at = i
  end
  return true
end

local function run(moves, answers)
  Ui.reset({ headless = false })
  LearnMove.reset()
  Choice.active = false
  Message.open = false
  Message._done = nil
  Message.shown = {}
  Battle._headless = false
  Summary.open = false
  Summary.opens = 0
  Summary.last = nil
  local hooks = Battle._choiceHooksForTests and Battle._choiceHooksForTests() or {
    pushMsg = function(text, cb) Ui.push(text, cb) end,
    askYesNo = function(a, b) Ui.askYesNo(a, b) end,
    askForget = function(labels, cb, ctx) Ui.askForget(labels, cb, ctx) end,
    headless = false,
    battleText = true,
  }
  local yesNoLayouts = {}
  local mon = { species = 4, level = 19, moves = moves, pp = { 35, 40, 35, 30 }, maxPp = { 35, 40, 35, 30 } }
  local result
  local prompts = {}
  local openedWhileTyping = false
  local ok, err = pcall(function()
    LearnMove.begin({
      mon = mon,
      moveId = 52,
      displayName = "CHARMANDER",
      pushMsg = hooks.pushMsg,
      askYesNo = hooks.askYesNo,
      askForget = hooks.askForget,
      headless = hooks.headless,
      battleText = hooks.battleText,
      onDone = function(learned) result = learned end,
    })
    for _ = 1, 200 do
      if result ~= nil then break end
      if Summary.open then
        local ans = table.remove(answers, 1)
        if ans == "cancel" then Summary.pick(nil) else Summary.pick(ans) end
      elseif Choice.active then
        if Message.open and not Message._waiting then openedWhileTyping = true end
        prompts[#prompts + 1] = Message.open and Message.shown[#Message.shown] or ""
        yesNoLayouts[#yesNoLayouts + 1] = {
          kind = Choice.kind, style = Choice.style, left = Choice.left, top = Choice.top,
          labels = Choice.options and table.concat(Choice.options, "/"),
        }
        local ans = table.remove(answers, 1)
        if ans == "cancel" then Choice.cancel() else Choice.autoPick(ans) end
      elseif Message.open and Message._waiting and not Message._stay then
        Message.close()
      else
        Ui.pump()
        LearnMove.pump()
        Message.tick()
      end
    end
  end)
  local Pokemon = require("src.core.game3.pokemon")
  local names = { [52] = "EMBER", [10] = "SCRATCH", [45] = "GROWL", [15] = "CUT", [33] = "TACKLE", [39] = "TAIL WHIP" }
  local function canon(s)
    if type(s) ~= "string" then return s end
    for id, want in pairs(names) do
      local got = Pokemon.moveName(id) or ("MOVE " .. id)
      if got ~= want then
        local i = s:find(got, 1, true)
        while i do
          s = s:sub(1, i - 1) .. want .. s:sub(i + #got)
          i = s:find(got, i + #want, true)
        end
      end
    end
    return s
  end
  local shownCanon = {}
  for i, t in ipairs(Message.shown) do shownCanon[i] = canon(t) end
  for i, t in ipairs(prompts) do prompts[i] = canon(t) end
  return {
    ok = ok, err = err, result = result, mon = mon, shown = shownCanon,
    prompts = prompts, active = LearnMove.busy(), open = Message.open,
    openedWhileTyping = openedWhileTyping, layouts = yesNoLayouts,
    summaryOpens = Summary.opens, summaryLast = Summary.last,
  }
end

local function count_exact(shown, text)
  local n = 0
  for _, t in ipairs(shown) do
    if (t:gsub("\\p$", "")) == text then n = n + 1 end
  end
  return n
end

print("[test] 1. free slot: learned message dismissed finishes")
local r = run({ 10, 45 }, {})
check(r.ok, "no error " .. tostring(r.err))
check(r.result == true, "onDone(true)")
check(r.mon.moves[3] == 52, "EMBER in slot 3")
check(not r.active, "LearnMove idle")
check(idx_of(r.shown, "CHARMANDER learned\nEMBER!") ~= nil, "PKMNLEARNEDMOVE text")

print("[test] 2. four moves: NO delete, YES stop -> did not learn (ROM strings)")
r = run({ 10, 45, 33, 39 }, { false, true })
check(r.ok, "no error " .. tostring(r.err))
local ord, miss = in_order(r.shown, {
  "CHARMANDER is trying to\nlearn EMBER.",
  "But, CHARMANDER can't learn\nmore than four moves.",
  "Delete a move to make\nroom for EMBER?",
  "Stop learning\nEMBER?",
  "CHARMANDER did not learn\nEMBER.",
})
check(ord, "TRYTOLEARNMOVE1/2/3, STOPLEARNINGMOVE, DIDNOTLEARNMOVE order (missing " .. tostring(miss) .. ")")
check(idx_of(r.shown, "Should a move be deleted") == nil and idx_of(r.shown, "Stop trying") == nil,
  "field party-menu wording not used in battle")
check(r.result == false, "onDone(false)")
check(not r.active, "LearnMove idle")
check(r.prompts[1] == "Delete a move to make\nroom for EMBER?", "delete prompt text stays up under Yes/No")
check(r.prompts[2] == "Stop learning\nEMBER?", "stop prompt text stays up under Yes/No")
check(not r.openedWhileTyping, "YES/NO never opens while the prompt is still typing")
check(not r.open, "no message left open")
check(r.mon.moves[1] == 10 and r.mon.moves[4] == 39, "moves unchanged")
local lay = r.layouts[1] or {}
check(lay.kind == "yesno" and lay.style == "battle" and lay.left == 24 and lay.top == 9,
  "Yes/No content at tiles (24,9) 5x4, frame 23..29 x 8..13")
check(lay.labels == "Yes/No", "gText_BattleYesNoChoice labels")
check(r.summaryOpens == 0, "summary never opened on the stop path")

print("[test] 3. four moves: YES delete -> summary select move, forget slot 1 -> Poof chain")
r = run({ 10, 45, 33, 39 }, { true, 0 })
check(r.ok, "no error " .. tostring(r.err))
check(r.summaryOpens == 1, "summary move-select opened once")
local so = r.summaryLast and r.summaryLast.opts or {}
check(so.mode == "select_move" and so.moveToLearn == 52, "summary in select_move mode with EMBER as fifth move")
check(r.summaryLast and r.summaryLast.party and r.summaryLast.party[1] == r.mon, "summary shows the learning mon")
for _, l in ipairs(r.layouts) do
  check(l.kind ~= "multi", "no Choice.multi forget list")
end
ord, miss = in_order(r.shown, {
  "Delete a move to make\nroom for EMBER?",
  "1, 2, and… … … Poof!",
  "CHARMANDER forgot\nSCRATCH.",
  "And…",
  "CHARMANDER learned\nEMBER!",
})
check(ord, "123POOF, PKMNFORGOTMOVE, ANDELLIPSIS, PKMNLEARNEDMOVE order (missing " .. tostring(miss) .. ")")
check(r.result == true, "onDone(true)")
check(r.mon.moves[1] == 52, "EMBER replaced slot 1")
check(not r.active, "LearnMove idle")

print("[test] 4. HM picked: HM text then summary reopens, pick slot 2")
r = run({ 15, 45, 33, 39 }, { true, 0, 1 })
check(r.ok, "no error " .. tostring(r.err))
ord, miss = in_order(r.shown, { "Delete a move to make", "HM moves can't be\nforgotten now.", "CHARMANDER forgot\nGROWL.", "CHARMANDER learned\nEMBER!" })
check(ord, "message order (missing " .. tostring(miss) .. ")")
check(r.summaryOpens == 2, "summary reopened after HM refusal without re-asking")
check(count_exact(r.shown, "Delete a move to make\nroom for EMBER?") == 1, "no second delete prompt")
check(r.result == true, "onDone(true)")
check(r.mon.moves[1] == 15 and r.mon.moves[2] == 52, "CUT kept, EMBER in slot 2")

print("[test] 5. summary B-cancel returns to stop prompt")
r = run({ 10, 45, 33, 39 }, { true, "cancel", true })
check(r.ok, "no error " .. tostring(r.err))
check(r.result == false, "onDone(false)")
ord, miss = in_order(r.shown, { "Delete a move to make", "Stop learning\nEMBER?", "CHARMANDER did not learn\nEMBER." })
check(ord, "cancel -> stop -> did not learn (missing " .. tostring(miss) .. ")")

print("[test] 5b. NO to Stop learning re-asks from TRYTOLEARNMOVE1")
r = run({ 10, 45, 33, 39 }, { false, false, false, true })
check(r.ok, "no error " .. tostring(r.err))
check(count_exact(r.shown, "CHARMANDER is trying to\nlearn EMBER.") == 2, "TRYTOLEARNMOVE1 printed twice")
check(count_exact(r.shown, "But, CHARMANDER can't learn\nmore than four moves.") == 2, "TRYTOLEARNMOVE2 printed twice")
check(count_exact(r.shown, "Delete a move to make\nroom for EMBER?") == 2, "TRYTOLEARNMOVE3 printed twice")
check(r.result == false, "onDone(false)")

print("[test] 6. Ui.askYesNo(cb) single-arg form still works")
Ui.reset({ headless = false })
Message.open = false
Message.shown = {}
local got
Ui.askYesNo(function(yes) got = yes end)
check(Choice.active and not Message.open, "choice open without a prompt message")
Choice.autoPick(true)
check(got == true, "cb(true)")

print("[test] 6b. Ui.askYesNo(prompt, cb) waits for the prompt to finish printing")
Ui.reset({ headless = false })
Message.open = false
Message.shown = {}
Choice.active = false
got = nil
Ui.askYesNo("Should a move be deleted?", function(yes) got = yes end)
check(Message.open and Message._stay and not Message._waiting, "prompt shown as a typing stay message")
check(not Choice.active, "YES/NO not open while typing")
check(Ui.pump() == false and not Choice.active, "pump while typing keeps YES/NO closed")
Message.tick()
check(Ui.pump() == false and Choice.active and Choice.kind == "yesno", "YES/NO opens once the text is waiting")
Choice.autoPick(false)
check(got == false and not Message.open, "cb(false) and prompt closed")

print("[test] 7. Ui.push cb fires on dismiss and in headless pump")
Ui.reset({ headless = false })
local fired = 0
Ui.push("hello", function() fired = fired + 1 end)
Ui.push("plain")
check(Ui.log()[1] == "hello" and Ui.log()[2] == "plain", "log stays strings")
Ui.pump()
check(fired == 0 and Message.open, "cb waits for dismiss")
Message.close()
check(fired == 1, "cb fired on dismiss")
Ui.reset({ headless = true })
Ui.push("x", function() fired = fired + 1 end)
Ui.pump()
check(fired == 2, "headless pump fires cb")
Ui.push("", function() fired = fired + 1 end)
check(fired == 3, "empty text fires cb immediately")

print("[test] 8. real summary select_move: HM pick shows the HM notice and stays open")
package.loaded["src.ui.game3.summary_menu"] = nil
local okS, RealSummary = pcall(require, "src.ui.game3.summary_menu")
check(okS and RealSummary and RealSummary.openMenu, "summary_menu loads")
if okS and RealSummary then
  local function inputFor(key)
    return { wasPressed = function(_, k) return k == key end, isDown = function() return false end }
  end
  local picked = "unset"
  local hmMon = { species = 4, level = 19, moves = { 15, 45, 33, 39 }, pp = { 30, 40, 35, 30 } }
  local okOpen, errOpen = pcall(RealSummary.openMenu, { hmMon }, 1, {
    mode = "select_move", moveToLearn = 52,
    onSelectMove = function(slot) picked = slot end,
  })
  check(okOpen, "openMenu ok " .. tostring(errOpen))
  RealSummary.handleInput(inputFor("a"))
  check(RealSummary.isOpen() and picked == "unset", "HM slot not selectable")
  check(RealSummary._hmNotice == true, "HM moves can't be forgotten notice raised")
  RealSummary.handleInput(inputFor("down"))
  check(RealSummary._hmNotice == false, "cursor move clears the notice")
  RealSummary.handleInput(inputFor("a"))
  check(picked == 1 and not RealSummary.isOpen(), "non-HM slot 2 returns index 1")
end

if failed > 0 then
  print(string.format("[FAIL] %d check(s) failed", failed))
  os.exit(1)
end
print("[PASS] game3 learn move battle contract")
