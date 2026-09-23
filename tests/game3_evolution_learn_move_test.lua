#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path
require("tests.game3_cache").mountOrSkip("game3_evolution_learn_move_test", "scripts/text.lua")

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local TYPE_TICKS = 3
local Message = { open = false, _stay = false, _done = nil, _waiting = false, _ticks = 0, shown = {} }
function Message.show(text, opts)
  opts = type(opts) == "table" and opts or {}
  Message.open = true
  Message._stay = opts.stay and true or false
  Message._done = opts.done
  Message._waiting = false
  Message._ticks = 0
  Message.shown[#Message.shown + 1] = tostring(text)
  return Message
end
function Message.showStay(text, opts)
  opts = opts or {}
  opts.stay = true
  return Message.show(text, opts)
end
function Message.setFrame() end
function Message.draw() end
function Message.isOpen() return Message.open end
function Message.isWaiting() return Message.open and Message._waiting end
function Message.isTyping() return Message.open and not Message._waiting end
function Message.currentPage() return Message.open and Message.shown[#Message.shown] or "" end
function Message.tick()
  if not Message.open or Message._waiting then return end
  Message._ticks = Message._ticks + 1
  if Message._ticks >= TYPE_TICKS then Message._waiting = true end
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
function Message.advance()
  if not Message.open then return end
  if not Message._waiting then return Message.skipReveal() end
  if Message._stay then return end
  Message.close()
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

local Pokemon = require("src.core.game3.pokemon")
local Choice = require("src.ui.game3.choice")
local LearnMove = require("src.core.game3.battle.learn_move")
local EvolutionScene = require("src.ui.game3.evolution_scene")

local function mv(id) return Pokemon.moveName(id) or ("MOVE " .. tostring(id)) end
local CONF, HARDEN, PSN = mv(93), mv(106), mv(77)
local NAME = "BUTTERFREE"

local function press(key)
  return { wasPressed = function(_, k) return k == key end, isDown = function() return false end }
end

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

local function count_exact(shown, text)
  local n = 0
  for _, t in ipairs(shown) do
    if (t:gsub("\\p$", "")) == text then n = n + 1 end
  end
  return n
end

local origLearnedAt = Pokemon.movesLearnedAt

local function run(moves, answers, learnset)
  LearnMove.reset()
  Choice.active = false
  Message.open = false
  Message._done = nil
  Message.shown = {}
  Summary.open = false
  Summary.opens = 0
  Summary.last = nil
  Pokemon.movesLearnedAt = function(_, lv)
    if tonumber(lv) == 10 then return learnset end
    return {}
  end
  local mon = { species = 12, speciesId = 12, level = 10, nickname = NAME, name = NAME,
    moves = moves, pp = { 35, 35, 40, 35 }, maxPp = { 35, 35, 40, 35 } }
  local result
  local prompts, layouts = {}, {}
  local openedWhileTyping = false
  local updates = 0
  local learnedClosedAt, learnedShownAt = {}, {}
  local ok, err = pcall(function()
    EvolutionScene.start(mon, 12, { canStop = false, onDone = function(r) result = r end })
    EvolutionScene._state = "congrats"
    Message.open = false
    EvolutionScene.handleInput(press("a"))
    for _ = 1, 3000 do
      if result ~= nil then break end
      if Summary.open then
        local ans = table.remove(answers, 1)
        if ans == "cancel" then Summary.pick(nil) else Summary.pick(ans) end
      elseif Choice.active then
        if Message.open and not Message._waiting then openedWhileTyping = true end
        prompts[#prompts + 1] = Message.open and Message.shown[#Message.shown] or ""
        layouts[#layouts + 1] = {
          kind = Choice.kind, style = Choice.style, left = Choice.left, top = Choice.top,
          labels = Choice.options and table.concat(Choice.options, "/"),
        }
        local ans = table.remove(answers, 1)
        if ans == "cancel" then Choice.cancel() else Choice.autoPick(ans) end
      elseif Message.open and Message._waiting and not Message._stay then
        local cur = Message.shown[#Message.shown]
        EvolutionScene.handleInput(press("a"))
        if cur:find(" learned\n", 1, true) then learnedClosedAt[#learnedClosedAt + 1] = updates end
      else
        local before = #Message.shown
        EvolutionScene.update(1 / 60)
        updates = updates + 1
        if #Message.shown > before and Message.shown[#Message.shown]:find(" learned\n", 1, true) then
          learnedShownAt[#learnedShownAt + 1] = updates
        end
      end
    end
  end)
  Pokemon.movesLearnedAt = origLearnedAt
  return {
    ok = ok, err = err, result = result, mon = mon, shown = Message.shown, prompts = prompts,
    layouts = layouts, openedWhileTyping = openedWhileTyping, updates = updates,
    learnedClosedAt = learnedClosedAt, learnedShownAt = learnedShownAt,
    summaryOpens = Summary.opens, summaryLast = Summary.last, open = EvolutionScene.isOpen(),
    active = LearnMove.busy(),
  }
end

local TRY1 = NAME .. " is trying to\nlearn " .. CONF .. "."
local TRY2 = "But, " .. NAME .. " can't learn\nmore than four moves."
local TRY3 = "Delete a move to make\nroom for " .. CONF .. "?"
local STOP = "Stop learning\n" .. CONF .. "?"
local DIDNOT = NAME .. " did not learn\n" .. CONF .. "."
local LEARNED = NAME .. " learned\n" .. CONF .. "!"

print("[test] 1. free slot: learned, then 0x40 frames before the scene ends")
local r = run({ 106, 33 }, {}, { 93 })
check(r.ok, "no error " .. tostring(r.err))
check(r.result == "evolved" and not r.open, "scene finished evolved")
check(r.mon.moves[3] == 93, "CONFUSION in slot 3")
check(idx_of(r.shown, LEARNED) ~= nil, "PKMNLEARNEDMOVE text")
local closedAt = r.learnedClosedAt[1]
check(closedAt ~= nil and r.updates - closedAt == 0x40,
  "scene ends 64 updates after the learned text is dismissed (got " .. tostring(closedAt and (r.updates - closedAt)) .. ")")

print("[test] 2. four moves: NO delete, YES stop -> did not learn (battle strings)")
r = run({ 106, 33, 81, 1 }, { false, true }, { 93 })
check(r.ok, "no error " .. tostring(r.err))
local ord, miss = in_order(r.shown, { TRY1, TRY2, TRY3, STOP, DIDNOT })
check(ord, "TRYTOLEARNMOVE1/2/3, STOPLEARNINGMOVE, DIDNOTLEARNMOVE order (missing " .. tostring(miss) .. ")")
check(idx_of(r.shown, "Should a move be deleted") == nil and idx_of(r.shown, "Stop trying") == nil
  and idx_of(r.shown, "wants to learn") == nil, "field party-menu wording not used")
check(r.prompts[1] == TRY3 and r.prompts[2] == STOP, "prompt text stays up under Yes/No")
check(not r.openedWhileTyping, "Yes/No never opens while the prompt is still printing")
local lay = r.layouts[1] or {}
check(lay.kind == "yesno" and lay.style == "battle" and lay.left == 24 and lay.top == 9, "battle Yes/No window")
check(r.summaryOpens == 0, "summary never opened on the stop path")
check(r.result == "evolved" and not r.active, "scene finished, LearnMove idle")
check(r.mon.moves[1] == 106 and r.mon.moves[4] == 1, "moves unchanged")

print("[test] 3. NO to Stop learning re-asks from TRYTOLEARNMOVE1")
r = run({ 106, 33, 81, 1 }, { false, false, false, true }, { 93 })
check(r.ok, "no error " .. tostring(r.err))
check(count_exact(r.shown, TRY1) == 2, "TRYTOLEARNMOVE1 printed twice")
check(count_exact(r.shown, TRY2) == 2, "TRYTOLEARNMOVE2 printed twice")
check(count_exact(r.shown, TRY3) == 2, "TRYTOLEARNMOVE3 printed twice")
check(r.result == "evolved", "scene finished")

print("[test] 4. YES -> summary move select, forget slot 1 -> Poof chain")
r = run({ 106, 33, 81, 1 }, { true, 0 }, { 93 })
check(r.ok, "no error " .. tostring(r.err))
check(r.summaryOpens == 1, "summary move-select opened once")
local so = r.summaryLast and r.summaryLast.opts or {}
check(so.mode == "select_move" and so.moveToLearn == 93, "summary select_move with CONFUSION as fifth move")
check(r.summaryLast and r.summaryLast.party and r.summaryLast.party[1] == r.mon, "summary shows the evolving mon")
ord, miss = in_order(r.shown, { TRY3, "1, 2, and… … … Poof!", NAME .. " forgot\n" .. HARDEN .. ".", "And…", LEARNED })
check(ord, "123POOF, PKMNFORGOTMOVE, ANDELLIPSIS, PKMNLEARNEDMOVE order (missing " .. tostring(miss) .. ")")
check(r.mon.moves[1] == 93, "CONFUSION replaced slot 1")
check(r.result == "evolved" and not r.active, "scene finished, LearnMove idle")

print("[test] 5. summary B-cancel goes to Stop learning")
r = run({ 106, 33, 81, 1 }, { true, "cancel", true }, { 93 })
check(r.ok, "no error " .. tostring(r.err))
ord, miss = in_order(r.shown, { TRY3, STOP, DIDNOT })
check(ord, "cancel -> stop -> did not learn (missing " .. tostring(miss) .. ")")
check(r.result == "evolved", "scene finished")

print("[test] 6. two moves at one level: 0x40 frames between them")
r = run({ 106 }, {}, { 93, 77 })
check(r.ok, "no error " .. tostring(r.err))
check(r.mon.moves[2] == 93 and r.mon.moves[3] == 77, "both moves learned in learnset order")
ord = in_order(r.shown, { LEARNED, NAME .. " learned\n" .. PSN .. "!" })
check(ord, "two learned messages in order")
local secondShown = r.learnedShownAt[#r.learnedShownAt]
check(r.learnedClosedAt[1] and secondShown and secondShown - r.learnedClosedAt[1] == 0x40,
  "second move starts 64 updates after the first learned text")
check(r.result == "evolved", "scene finished")

print("[test] 7. congratulations names the pre-evolution (nickname read before the rename)")
local Evolution = require("src.core.game3.evolution")
local function congrats(nickname)
  LearnMove.reset()
  Choice.active = false
  Message.open = false
  Message._done = nil
  Message.shown = {}
  local mon = { species = 11, speciesId = 11, level = 10, nickname = nickname, name = nickname,
    moves = { 33 }, pp = { 35 }, maxPp = { 35 } }
  EvolutionScene.start(mon, 12, { canStop = false, onDone = function() end })
  Evolution.renameMon(mon, 11, 12)
  EvolutionScene._state = "evo_cry"
  EvolutionScene._timer = 44
  EvolutionScene.update(1 / 60)
  local text = Message.shown[#Message.shown] or ""
  EvolutionScene._state = "idle"
  EvolutionScene.open = false
  EvolutionScene._mon = nil
  EvolutionScene._nick = nil
  return text, mon
end
local preName, postName = Pokemon.name(11), Pokemon.name(12)
local text, mon = congrats(preName)
check(EvolutionScene._state == "idle" and mon.nickname == postName, "un-nicknamed mon renamed to the post-evo species")
check(text == "Congratulations! Your " .. preName .. "\nevolved into " .. postName .. "!",
  "congrats names the pre-evo species, not the new one (got " .. text:gsub("\n", " ") .. ")")
text, mon = congrats("WORMY")
check(mon.nickname == "WORMY", "custom nickname kept through the rename")
check(text == "Congratulations! Your WORMY\nevolved into " .. postName .. "!",
  "congrats uses the custom nickname (got " .. text:gsub("\n", " ") .. ")")

if failed > 0 then
  print(string.format("[FAIL] %d check(s) failed", failed))
  os.exit(1)
end
print("[PASS] game3 evolution scene learn move")
