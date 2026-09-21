#!/usr/bin/env luajit

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

local Disasm = require("src.core.game3.scripting.disasm")
local Ops = require("src.core.game3.scripting.ops_a")
local Oak = require("src.core.game3.battle.oak_advice")
local Rules = require("src.core.game3.battle.rules")
local Battle = require("src.core.game3.battle")
local Ui = require("src.core.game3.battle.ui")

print("[test] 1. trainerbattle_earlyrival operand decode")
do
  local function bytes(s)
    local t = {}
    for i = 1, #s do t[i] = s:byte(i) end
    return t
  end

  local oaksLab = bytes("\x5c\x09\x46\x01\x03\x00\x00\x00\x00\x08\x00\x00\x00\x08")
  local row = Disasm.decodeOne(oaksLab, 1)
  check(row.op == "trainerbattle", "opcode 0x5c decodes as trainerbattle")
  check(row.type == 9, "Oak's Lab type == TRAINER_BATTLE_EARLY_RIVAL (9)")
  check(row.trainer == 326, "Oak's Lab trainer == 326")
  check(row.flags == 3, "Oak's Lab flags == RIVAL_BATTLE_TUTORIAL (3)")

  local route22 = bytes("\x5c\x09\x49\x01\x00\x00\x00\x00\x00\x08\x00\x00\x00\x08")
  local row22 = Disasm.decodeOne(route22, 1)
  check(row22.type == 9, "Route 22 type == TRAINER_BATTLE_EARLY_RIVAL (9)")
  check(row22.trainer == 329, "Route 22 trainer == 329")
  check(row22.flags == 0, "Route 22 flags == 0 (not a tutorial)")
end

print("[test] 2. ops_a forwards firstBattle only for flags & RIVAL_BATTLE_TUTORIAL")
do
  local function dispatch(flags)
    local seen = nil
    local vm = {
      ctx = { pc = { listKey = "oak_test", index = 1 }, mode = "bytecode", status = "running" },
      store = { flags = {}, vars = {} },
      adapters = {
        openMessageAsync = function(_t, done) done() end,
        startTrainerBattle = function(_foe, done, opts)
          seen = opts
          done("win")
        end,
      },
      getText = function() return nil end,
      setPc = function() end,
    }
    Ops.dispatch(vm, {
      op = "trainerbattle",
      type = 9,
      trainer = 326,
      flags = flags,
      victoryText = nil,
    })
    return seen
  end

  local tut = dispatch(3)
  check(tut ~= nil, "flags=3 started a battle")
  check(tut and tut.earlyRival == true, "flags=3 earlyRival true")
  check(tut and tut.firstBattle == true, "flags=3 firstBattle true")
  check(tut and tut.rivalFlags == 3, "flags=3 rivalFlags forwarded")

  local heal = dispatch(1)
  check(heal and heal.firstBattle == true, "flags=1 firstBattle true (flags & 3 is two bits)")

  local r22 = dispatch(0)
  check(r22 ~= nil, "flags=0 started a battle")
  check(not (r22 and r22.firstBattle), "flags=0 (Route 22) firstBattle falsy")
end

print("[test] 3. Oak advice flag word + player-name expansion")
do
  local st = { firstBattle = true, playerName = "BLUE" }
  local out = {}
  local function sink(t) out[#out + 1] = t end

  check(Oak.active(st) == true, "Oak.active true on a first battle")
  check(Oak.active({ firstBattle = false }) == false, "Oak.active false otherwise")

  check(Oak.sayOnce(st, Oak.FLAG_INFLICT_DMG, "inflictingDamage", sink) == true, "first inflictingDamage says")
  check(#out == 1, "one page pushed")
  check(out[1]:find("Inflicting damage on the foe", 1, true) ~= nil, "pret gText_InflictingDamageIsKey text")
  check(Oak.sayOnce(st, Oak.FLAG_INFLICT_DMG, "inflictingDamage", sink) == false, "second inflictingDamage is a no-op")
  check(#out == 1, "still one page")

  check(Oak.sayOnce(st, Oak.FLAG_STAT_CHG, "loweringStats", sink) == true, "stat-chg mask is independent")
  check(Oak.sayOnce(st, Oak.FLAG_HP_RESTORE, "keepAnEyeOnHp", sink) == true, "hp-restore mask is independent")
  check(st.oakMsgFlags == 7, "all three once-only flags set (0x7)")

  local off = { firstBattle = false, playerName = "BLUE" }
  local none = {}
  check(Oak.say(off, "noRunning", function(t) none[#none + 1] = t end) == false, "inactive state says nothing")
  check(#none == 0, "no pages pushed when inactive")

  local pages = Oak.pages(st, "howDisappointing")
  check(pages and pages[1]:find("How disappointing", 1, true) ~= nil, "howDisappointing text present")
  check(pages and pages[1]:find("{B_PLAYER_NAME}", 1, true) == nil, "B_PLAYER_NAME placeholder expanded")
  check(pages and pages[1]:find("but if you lose, BLUE", 1, true) ~= nil
    or (pages and pages[1]:find("lose, BLUE,", 1, true) ~= nil), "player name substituted")

  local intro = Oak.pages(st, "forPetesSake")
  check(intro and #intro == 3, "opening Oak speech is three prints")
  check(intro and intro[2]:find("The TRAINER that makes the other", 1, true) ~= nil, "gText_TheTrainerThat present")
  check(intro and intro[3]:find("Try battling and see for yourself", 1, true) ~= nil, "gText_TryBattling present")
end

local function party(level, hp)
  return { { species = 1, level = level, hp = hp, maxHp = hp, moves = { 33 }, pp = { 35 }, maxPp = { 35 } } }
end

local function run(opts)
  if Battle.isActive() then Battle.abort("win") end
  local ok = Battle.start(opts)
  local res = Battle.runToEnd()
  local log = {}
  for i, t in ipairs(Ui.log() or {}) do log[i] = t end
  return ok, res, log, Battle._st
end

local function find(log, needle)
  for i, t in ipairs(log) do
    if t:find(needle, 1, true) then return i end
  end
  return nil
end

local function count(log, needle)
  local n = 0
  for _, t in ipairs(log) do
    if t:find(needle, 1, true) then n = n + 1 end
  end
  return n
end

print("[test] 4. firstBattle no longer hijacks the trainer's aiFlags")
do
  local ok, _res, _log, st = run({
    wild = false, headless = true, trainerId = 326,
    firstBattle = true, earlyRival = true, rivalFlags = 3,
    playerParty = party(60, 200),
    foe = { species = 7, level = 5, trainerId = 326, aiFlags = 7 },
  })
  check(ok, "tutorial battle started")
  check(st and st.aiFlags == 7, "st.aiFlags == 7 (CHECK_BAD_MOVE|TRY_TO_FAINT|CHECK_VIABILITY), not 0x80000000")
  check(st and st.firstBattle == true, "st.firstBattle set from opts")
end

print("[test] 5. Oak's advice fires in a tutorial win")
do
  local _ok, res, log = run({
    wild = false, headless = true, trainerId = 326,
    firstBattle = true, earlyRival = true, rivalFlags = 3,
    playerName = "RED",
    playerParty = party(60, 200),
    foe = { species = 7, level = 5, trainerId = 326 },
  })
  check(res == "win", "tutorial battle won")
  check(find(log, "Oh, for Pete's sake") ~= nil, "opening Oak speech logged")
  check(find(log, "The TRAINER that makes the other") ~= nil, "second opening page logged")
  check(find(log, "Try battling and see for yourself") ~= nil, "third opening page logged")
  check(count(log, "Inflicting damage on the foe") == 1, "first-damage advice fires exactly once")
  local iGo = find(log, "Go! ")
  local iOak = find(log, "Oh, for Pete's sake")
  check(iGo and iOak and iGo < iOak, "Oak speaks after the player sends out")
end

print("[test] 6. non-tutorial trainer battle stays silent")
do
  local _ok, res, log = run({
    wild = false, headless = true, trainerId = 326,
    playerParty = party(60, 200),
    foe = { species = 7, level = 5, trainerId = 326 },
  })
  check(res == "win", "plain trainer battle won")
  check(find(log, "Oh, for Pete's sake") == nil, "no Oak opening speech")
  check(find(log, "Inflicting damage on the foe") == nil, "no first-damage advice")
end

print("[test] 7. tutorial loss: rival victory speech + Oak, no white-out pair")
do
  local _ok, res, log = run({
    wild = false, headless = true, trainerId = 326,
    firstBattle = true, earlyRival = true, rivalFlags = 3,
    playerName = "RED",
    victoryText = "RIVAL: Yeah!\nAm I great or what?",
    playerParty = party(2, 1),
    foe = { species = 6, level = 80, trainerId = 326 },
  })
  check(res == "lose", "tutorial battle lost")
  local iWin = find(log, "Am I great or what?")
  local iOak = find(log, "How disappointing")
  check(iWin ~= nil, "rival victory speech displayed")
  check(iOak ~= nil, "Oak's 'How disappointing' displayed")
  check(iWin and iOak and iWin < iOak, "victory speech precedes Oak")
  check(find(log, "blacked out") == nil, "no 'blacked out!' on the tutorial loss")
  check(find(log, "You have no more") == nil, "no 'no more POKéMON left!' on the tutorial loss")
end

print("[test] 8. ordinary trainer loss still whites out")
do
  local _ok, res, log = run({
    wild = false, headless = true, trainerId = 326,
    playerName = "RED",
    victoryText = "RIVAL: Yeah!\nAm I great or what?",
    playerParty = party(2, 1),
    foe = { species = 6, level = 80, trainerId = 326 },
  })
  check(res == "lose", "plain trainer battle lost")
  check(find(log, "You have no more") ~= nil, "'no more POKéMON left!' still printed")
  check(find(log, "blacked out") ~= nil, "'blacked out!' still printed")
  check(find(log, "Am I great or what?") == nil, "no victory speech outside the early-rival path")
  check(find(log, "How disappointing") == nil, "no Oak text outside the tutorial")
end

print("[test] 9. Oak's prize-money advice after the money line")
do
  local Runtime = package.loaded["src.core.game3.runtime"]
  package.loaded["src.core.game3.runtime"] = {
    getSession = function()
      return { name = "RED", money = 0, party = {} }
    end,
  }
  local _ok, res, log = run({
    wild = false, headless = true, trainerId = 326,
    firstBattle = true, earlyRival = true, rivalFlags = 3,
    playerName = "RED",
    playerParty = party(60, 200),
    foe = { species = 7, level = 5, trainerId = 326 },
  })
  package.loaded["src.core.game3.runtime"] = Runtime
  check(res == "win", "tutorial battle won with a session")
  local iMoney = find(log, "for winning!")
  local iOak = find(log, "Hm! Excellent!")
  check(iMoney ~= nil, "prize money line printed")
  check(iOak ~= nil, "Oak's prize-money advice printed")
  check(iMoney and iOak and iMoney < iOak, "Oak speaks after the prize money line")
end

print("[test] 10. Oak's advice is queued for B_WIN_OAK_OLD_MAN, not the battle textbox")
do
  check(type(Ui.markVoiceover) == "function", "Ui.markVoiceover exists")
  check(type(Ui.voiceoverDim) == "function", "Ui.voiceoverDim exists")
  Ui.reset({ headless = false })
  Ui.bindState({ firstBattle = true, playerName = "RED" })
  check(Ui.voiceoverDim and Ui.voiceoverDim() == 0, "no dim before any voiceover text")
  if Ui.markVoiceover then Ui.markVoiceover("page one") end
  Ui.push("ordinary battle line")
  Ui.push("page one")
  local q = Ui._queue
  check(type(q[1]) ~= "table" or q[1].oak ~= true, "an unmarked push is an ordinary battle line")
  check(type(q[2]) == "table" and q[2].oak == true, "a marked push is a voiceover item")
  Ui._queue = {}
  Ui.push("page one")
  check(type(Ui._queue[1]) == "table" and Ui._queue[1].oak == true,
    "the tag survives a deferred replay of the same line")
  Ui._queue = {}
  Ui.pushTimed("page one", 64)
  check(type(Ui._queue[1]) == "table" and Ui._queue[1].oak == true
    and Ui._queue[1].timed ~= true,
    "an animation-queue replay of Oak's line waits for the player, not a timer")
  Ui.pushTimed("ordinary battle line", 64)
  check(type(Ui._queue[2]) == "table" and Ui._queue[2].timed == true,
    "ordinary animation lines stay timed")

  -- pokefirered/data/battle_scripts_1.s:2953
  Ui._queue = {}
  local ir = { { t = "text", s = "RIVAL: Yeah!" }, { t = "nl" },
    { t = "text", s = "Am I great or what?" }, { t = "eos" } }
  Ui.push(ir)
  local item = Ui._queue[1]
  check(type(item) == "table" and item.text == ir,
    "a script TextIR list survives the queue instead of reading as a queue item")
  Ui.reset({ headless = true })

  local st = { firstBattle = true, playerName = "RED" }
  Ui.reset({ headless = false })
  Ui.bindState(st)
  check(Oak.say(st, "noRunning") == true, "Oak.say pushes through Ui by default")
  check(type(Ui._queue[1]) == "table" and Ui._queue[1].oak == true,
    "Oak.say's own pages are tagged for the voiceover window")

  local Message = require("src.ui.game3.message")
  Message.setFrame("voiceover")
  check(Message.frameKind() == "voiceover", "message.lua knows the voiceover frame")
  check(Message.frameKind() ~= "dialogue", "voiceover is not the field dialogue frame")
  Message.setFrame("battle")
  check(Message.frameKind() == "battle", "battle frame still selectable")
  Ui.reset({ headless = true })
end

print("[test] 11. no crits until the first damaging hit has landed")
do
  local always = function() return 0 end
  local st = { firstBattle = true, oakMsgFlags = 0 }
  local move = { power = 40, effect = 0 }
  check(Rules.crit.roll({}, move, nil, always) == true, "crit rolls normally with no battle state")
  check(Rules.crit.roll({}, move, nil, always, st) == false, "no crit while FLAG_INFLICT_DMG is unset")
  Oak.setFlag(st, Oak.FLAG_INFLICT_DMG)
  check(Rules.crit.roll({}, move, nil, always, st) == true, "crits return once the first hit has landed")
  check(Rules.crit.roll({}, move, nil, always, { firstBattle = false }) == true,
    "ordinary battles are untouched")
end

print("[test] 12. the tutorial's first move cannot miss")
do
  local function missRng(lo, hi)
    if lo == 1 and hi == 100 then return 100 end
    return lo
  end

  local _ok, _res, tutLog = run({
    wild = false, headless = true, trainerId = 326, rng = missRng,
    firstBattle = true, earlyRival = true, rivalFlags = 3,
    playerName = "RED",
    playerParty = party(60, 200),
    foe = { species = 7, level = 5, trainerId = 326 },
  })
  check(find(tutLog, "attack missed") == nil, "the tutorial's first move auto-hits")
  check(find(tutLog, "Inflicting damage on the foe") ~= nil, "it landed damage on the foe")
  check(find(tutLog, "critical hit") == nil, "and it could not crit")

  local _ok2, _res2, plainLog = run({
    wild = false, headless = true, trainerId = 326, rng = missRng,
    playerName = "RED",
    playerParty = party(60, 200),
    foe = { species = 7, level = 5, trainerId = 326 },
  })
  check(find(plainLog, "attack missed") ~= nil, "the same roll misses outside the tutorial")
end

print("[test] 13. party-menu advice pages")
do
  check(Oak.FLAG_PARTY_MENU == 8, "FIRST_BATTLE_MSG_FLAG_PARTY_MENU is 0x8")
  check(type(Oak.take) == "function", "Oak.take hands the pages to the party menu")
  local st = { firstBattle = true, playerName = "RED" }
  local pages = Oak.take and Oak.take(st, Oak.FLAG_PARTY_MENU, "partyMenu")
  check(pages ~= nil and #pages == 4, "the two strings.c pages split into four screens")
  check(pages and pages[1]:find("important to get to know", 1, true) ~= nil,
    "gText_OakImportantToGetToKnowPokemonThroughly present")
  check(pages and pages[2]:find("This is a list of your POKéMON,\nRED.", 1, true) ~= nil,
    "gText_OakThisIsListOfPokemon expands the player name")
  check(pages and pages[4]:find("use an item on one", 1, true) ~= nil, "last screen present")
  check(st.oakMsgFlags == Oak.FLAG_PARTY_MENU, "the party-menu flag is set once taken")
  check(Oak.take and Oak.take(st, Oak.FLAG_PARTY_MENU, "partyMenu") == nil, "a second open says nothing")
  check(Oak.take and Oak.take({ firstBattle = false }, Oak.FLAG_PARTY_MENU, "partyMenu") == nil,
    "no advice outside the tutorial battle")
end

print("[test] 14. the voiceover frame stays up through the undim")
do
  local Message = require("src.ui.game3.message")
  local st = { firstBattle = true, playerName = "RED" }
  Ui.reset({ headless = false })
  Ui.bindState(st)
  local fired = 0
  Oak.say(st, "noRunning", function(t) Ui.push(t, function() fired = fired + 1 end) end)
  local shownAt, heldDim, closedDim = nil, nil, nil
  local openBelowFull = false
  for _ = 1, 300 do
    Ui.pump()
    if Message.isOpen() then
      if not shownAt then shownAt = Ui.voiceoverDim() end
      if Message.isHeld and Message.isHeld() then
        if Ui.voiceoverDim() < 0.5 then openBelowFull = true end
      else
        Message.skipReveal()
        Message.advance()
        heldDim = Ui.voiceoverDim()
      end
    elseif shownAt and not closedDim then
      closedDim = Ui.voiceoverDim()
    end
  end
  check(shownAt == 0.5, "the page appears only at y = 8")
  check(fired == 1, "the page callback fires once when the player dismisses it")
  check(heldDim == 0.5, "dismissal happens at full dim")
  check(openBelowFull, "the frame is still drawn while y walks 8 -> 0")
  check(closedDim == 0, "the frame is removed once the fade is done")
  check(Ui.busy() == false, "the battle resumes afterwards")

  Message.show("x", { frame = "dialogue", done = function() fired = fired + 1 end })
  Message.skipReveal()
  Message.advance()
  check(not Message.isOpen() and fired == 2, "a message without hold still closes on the last A")
  Ui.reset({ headless = true })
end

print("[test] 15. Cmd_attackcanceler's protect check still runs before the accuracy bypass")
do
  local function protectRun(first)
    local _ok, _res, log = run({
      wild = false, headless = true, trainerId = 326,
      firstBattle = first or nil, earlyRival = first or nil, rivalFlags = first and 3 or nil,
      playerName = "RED",
      playerParty = { { species = 1, level = 5, hp = 200, maxHp = 200, moves = { 33 }, pp = { 35 }, maxPp = { 35 } } },
      foe = { species = 7, level = 5, trainerId = 326, moves = { 182 }, hp = 200, maxHp = 200 },
    })
    return log
  end
  local tut = protectRun(true)
  local used = find(tut, "BULBASAUR used")
  local guarded = find(tut, "protected")
  check(used ~= nil and guarded ~= nil and guarded < used, "the foe protects on turn one of the tutorial")
  local after = used and tut[used + 1] or ""
  check(after:find("protected", 1, true) ~= nil, "the first tutorial move is still stopped by PROTECT")
  check(after:find("Inflicting damage", 1, true) == nil, "so Oak's damage advice waits for a hit that lands")
end

print("[test] 16. party-menu advice wraps once per page and ramps the dim")
do
  local okPm, PartyMenu = pcall(require, "src.ui.game3.party_menu")
  local FrlgFont = require("src.ui.game3.frlg_font")
  local st = { firstBattle = true, playerName = "RED" }
  Ui.reset({ headless = true })
  Ui.bindState(st)
  local wraps = 0
  local realWrap = FrlgFont.wrap
  FrlgFont.wrap = function(...)
    wraps = wraps + 1
    return realWrap(...)
  end
  local mons = { { species = 1, level = 5, hp = 20, maxHp = 20, moves = { 33 } } }
  local opened = okPm and pcall(PartyMenu.show, mons, { battle = true })
  if opened and PartyMenu.mode == "oak" then
    local fx = PartyMenu._oakFx
    check(type(fx) == "table" and fx.phase == "darken" and fx.y == 0, "the dim starts at 0")
    check(wraps == 1 and PartyMenu._oakWrapped ~= nil, "the first page is wrapped when the advice begins")
    local press = false
    local input = { wasPressed = function(_, b) return press and b == "a" end, isDown = function() return false end }
    PartyMenu.handleInput({ wasPressed = function() return true end, isDown = function() return false end })
    check(PartyMenu._oakPage == 1 and fx.phase == "darken", "A is ignored until the screen has darkened")
    local frames = 0
    while fx.phase == "darken" and frames < 200 do
      PartyMenu.update(1 / 60)
      frames = frames + 1
    end
    check(fx.y == 6 and frames == 30, "0 -> 6 at delay 4 takes 30 frames")
    for _ = 1, 20 do PartyMenu.update(1 / 60) end
    check(wraps == 1, "idle frames never wrap again")
    press = true
    PartyMenu.handleInput(input)
    press = false
    check(fx.phase == "lighten" and PartyMenu._oakPage == 1, "after msg 1 the first slot lightens")
    frames = 0
    while fx.phase == "lighten" and frames < 200 do
      PartyMenu.update(1 / 60)
      frames = frames + 1
    end
    check(fx.slot == 0 and fx.y == 6 and PartyMenu._oakPage == 2, "slot 1 is lit, the rest stays dim, msg 2 starts")
    check(wraps == 2, "the page change wrapped exactly once")
    for _ = 1, 3 do
      press = true
      PartyMenu.handleInput(input)
      press = false
      PartyMenu.update(1 / 60)
    end
    check(fx.phase == "normal" and PartyMenu.mode == "oak", "the last A starts the fade back")
    check(wraps == 4, "four screens, four wraps")
    frames = 0
    while PartyMenu.mode == "oak" and frames < 200 do
      PartyMenu.update(1 / 60)
      frames = frames + 1
    end
    check(PartyMenu.mode ~= "oak" and PartyMenu._oakFx == nil, "the menu takes over once the dim is gone")
  else
    print("[skip] party menu needs extracted data")
  end
  FrlgFont.wrap = realWrap
  if okPm and PartyMenu.hide then pcall(PartyMenu.hide) end
  Ui.reset({ headless = true })
end

if failed > 0 then
  print(string.format("[FAIL] %d check(s) failed", failed))
  os.exit(1)
end
print("[PASS] game3 oak first battle")
