#!/usr/bin/env luajit
-- pokefirered/src/pokemon.c:5741, pokefirered/src/learn_move.c:476

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

local function finish()
  if failed > 0 then
    print(string.format("[FAIL] %d check(s) failed", failed))
    os.exit(1)
  end
  print("[PASS] game3_moveteach_relearner")
  os.exit(0)
end

local function listEq(got, want)
  if type(got) ~= "table" or #got ~= #want then return false end
  for i = 1, #want do
    if got[i] ~= want[i] then return false end
  end
  return true
end

local function show(list)
  local parts = {}
  for i = 1, #list do parts[i] = tostring(list[i]) end
  return "{" .. table.concat(parts, ",") .. "}"
end

local Cache = require("tests.game3_cache")
local cacheRoot = Cache.mount("pokemon/learnsets.lua")
if not cacheRoot then
  print("[skip] game3_moveteach_relearner: " .. tostring(Cache.reason))
  os.exit(0)
end
print("[info] FireRed cache at " .. cacheRoot)

local Pokemon = require("src.core.game3.pokemon")
Pokemon.install(nil)

local MoveLearn = require("src.core.game3.move_learn")
local LearnMove = require("src.core.game3.battle.learn_move")
local MoveRelearner = require("src.ui.game3.move_relearner")
local Natives = require("src.core.game3.scripting.natives")

local TACKLE, VINE_WHIP, GROWL = 33, 22, 45
local LEECH_SEED, GROWTH, RAZOR_LEAF = 73, 74, 75
local SOLAR_BEAM, POISON_POWDER, SLEEP_POWDER = 76, 77, 79
local SWEET_SCENT, SYNTHESIS = 230, 235

local BULBASAUR, IVYSAUR, CHARMANDER = 1, 2, 4

local function monAt(species, level)
  local moves, pp, maxPp = Pokemon.movesAtLevel(species, level)
  return { species = species, level = level, moves = moves, pp = pp, maxPp = maxPp }
end

print("[test] 1. GetMoveRelearnerMoves keeps pret's learnset order")
do
  local bulba = monAt(BULBASAUR, 50)
  check(listEq(bulba.moves, { SWEET_SCENT, GROWTH, SYNTHESIS, SOLAR_BEAM }),
    "a level 50 BULBASAUR starts with its four newest moves " .. show(bulba.moves))
  local relearn = MoveLearn.relearnableMoves(bulba)
  check(listEq(relearn, { TACKLE, GROWL, LEECH_SEED, VINE_WHIP,
    POISON_POWDER, SLEEP_POWDER, RAZOR_LEAF }),
    "it can relearn the seven older moves in learnset order " .. show(relearn))
end

print("[test] 2. duplicate learnset rows collapse to one entry")
do
  local ivy = monAt(IVYSAUR, 50)
  local relearn = MoveLearn.relearnableMoves(ivy)
  check(listEq(relearn, { TACKLE, GROWL, LEECH_SEED, VINE_WHIP,
    POISON_POWDER, SLEEP_POWDER }),
    "IVYSAUR's repeated GROWL / LEECH SEED rows appear once " .. show(relearn))
end

print("[test] 3. the level gate and the egg gate")
do
  local fresh = monAt(CHARMANDER, 5)
  check(#MoveLearn.relearnableMoves(fresh) == 0,
    "a level 5 CHARMANDER with its starting moveset has nothing to relearn")

  local mid = monAt(BULBASAUR, 20)
  local relearn = MoveLearn.relearnableMoves(mid)
  local aboveLevel = false
  for _, id in ipairs(relearn) do
    for _, e in ipairs(Pokemon.learnset(BULBASAUR)) do
      if (tonumber(e[2] or e.move) or 0) == id and (tonumber(e[1] or e.level) or 0) > 20 then
        aboveLevel = true
      end
    end
  end
  check(not aboveLevel, "no move learned above the mon's level is offered at level 20")

  local egg = monAt(BULBASAUR, 50)
  egg.isEgg = true
  check(MoveLearn.countRelearnableMoves(egg) == 0,
    "GetNumberOfRelearnableMoves returns 0 for an egg")
  check(MoveLearn.countRelearnableMoves(monAt(BULBASAUR, 50)) == 7,
    "and 7 for the level 50 BULBASAUR")
end

print("[test] 4. special ChooseMonForMoveRelearner sets VAR_0x8005")
do
  local Ctx = require("src.core.game3.scripting.ctx")
  local Flags = require("src.core.game3.scripting.flags")
  local prevRuntime = package.loaded["src.core.game3.runtime"]
  package.loaded["src.core.game3.runtime"] = {
    getSession = function()
      return { party = { monAt(BULBASAUR, 50), monAt(CHARMANDER, 5) } }
    end,
    isActive = function() return true end,
  }

  local function newCtx()
    local ctx = Ctx.new({})
    ctx.mode = "bytecode"
    ctx.status = "running"
    return ctx
  end

  local ctx = newCtx()
  local handled = select(3, Natives.special(ctx, 0xDB, {
    log = function() end,
    chooseParty = function(_, done) done(0) end,
  }))
  check(handled == true, "special 0xDB is bound (pokefirered/data/specials.inc:230)")
  check(Flags.getVar(nil, ctx, 0x8004) == 0,
    "VAR_0x8004 carries the chosen slot, got " .. tostring(Flags.getVar(nil, ctx, 0x8004)))
  check(Flags.getVar(nil, ctx, 0x8005) == 7,
    "VAR_0x8005 carries GetNumberOfRelearnableMoves, got "
      .. tostring(Flags.getVar(nil, ctx, 0x8005)))

  local ctx2 = newCtx()
  local pending
  Natives.special(ctx2, 0xDB, {
    log = function() end,
    chooseParty = function(_, done) pending = done end,
  })
  check(ctx2.nativePoll and ctx2.nativePoll() == false,
    "the script yields while the party picker is up")
  pending(1)
  check(ctx2.nativePoll() == true, "the native finishes after the pick")
  check(Flags.getVar(nil, ctx2, 0x8005) == 0,
    "a fresh level 5 slot reports 0 relearnable moves, got "
      .. tostring(Flags.getVar(nil, ctx2, 0x8005)))

  package.loaded["src.core.game3.runtime"] = prevRuntime
end

print("[test] 5. the replace-a-move branch")
do
  local mon = monAt(BULBASAUR, 50)
  local said = {}
  local asked = {}
  local done = nil
  LearnMove.reset()
  LearnMove.begin({
    mon = mon,
    moveId = RAZOR_LEAF,
    relearner = true,
    pushMsg = function(text, cb) said[#said + 1] = text; if cb then cb() end end,
    askYesNo = function(text, cb) asked[#asked + 1] = text; cb(true) end,
    askForget = function(_, cb) cb(1) end,
    onDone = function(learned) done = learned end,
  })
  check(done == true, "the relearner reports the move as learned")
  check(mon.moves[2] == RAZOR_LEAF,
    "the chosen slot now holds RAZOR LEAF, got " .. tostring(mon.moves[2]))
  check(mon.pp[2] == Pokemon.movePp(RAZOR_LEAF),
    "and its PP was reset to full, got " .. tostring(mon.pp[2]))
  check(asked[1] and asked[1]:find("Delete an older move", 1, true) ~= nil,
    "pret's relearner wording is used for the delete prompt: " .. tostring(asked[1]))
  local joined = table.concat(said, "|")
  check(joined:find("is trying to learn", 1, true) ~= nil,
    "the trying-to-learn page is printed")
  check(joined:find("Which move should be forgotten?", 1, true) ~= nil,
    "the which-move page is printed before the summary screen")
  check(joined:find("forgot GROWTH.", 1, true) ~= nil,
    "the forgot page names the replaced move: " .. joined)
end

print("[test] 6. the give-up branch prints no did-not-learn page")
do
  local mon = monAt(BULBASAUR, 50)
  local before = mon.moves[1]
  local said = {}
  local answers = { false, true }
  local nAsked = 0
  local done = nil
  LearnMove.reset()
  LearnMove.begin({
    mon = mon,
    moveId = RAZOR_LEAF,
    relearner = true,
    pushMsg = function(text, cb) said[#said + 1] = text; if cb then cb() end end,
    askYesNo = function(text, cb)
      nAsked = nAsked + 1
      said[#said + 1] = text
      cb(answers[nAsked])
    end,
    askForget = function(_, cb) cb(nil) end,
    onDone = function(learned) done = learned end,
  })
  check(done == false, "declining the delete and confirming the stop teaches nothing")
  check(mon.moves[1] == before, "the moveset is untouched")
  local joined = table.concat(said, "|")
  check(joined:find("Stop learning RAZOR LEAF?", 1, true) ~= nil,
    "pret's stop wording is used: " .. joined)
  check(joined:find("did not learn", 1, true) == nil,
    "and no did-not-learn page is printed (pokefirered/src/learn_move.c:583)")
end

print("[test] 7. the screen's move list and its CANCEL row")
do
  local mon = monAt(BULBASAUR, 50)
  local done = nil
  MoveRelearner.show(mon, { onDone = function(learned) done = learned end })
  check(MoveRelearner.isOpen(), "the relearner screen opened")
  check(#MoveRelearner.moves() == 7, "it lists the seven relearnable moves")
  check(MoveRelearner.prompt:find("Teach which move to", 1, true) ~= nil,
    "the prompt window asks which move to teach")

  local pressed = nil
  local input = { wasPressed = function(_, key) return key == pressed end }
  local function press(key)
    pressed = key
    MoveRelearner.handleInput(input)
    pressed = nil
  end

  for _ = 1, 7 do press("down") end
  check(MoveRelearner.cursor == 8, "the cursor reaches the CANCEL row")
  press("down")
  check(MoveRelearner.cursor == 8, "and does not wrap past it")
  press("a")
  check(MoveRelearner.prompt:find("Give up trying to teach", 1, true) ~= nil,
    "CANCEL asks the give-up question")
  press("a")
  check(done == false, "answering YES closes the screen with nothing learned")
  check(not MoveRelearner.isOpen(), "and the screen is closed")
  check(#mon.moves == 4, "the moveset is unchanged")
end

print("[test] 8. teaching a move into a free slot from the screen")
do
  local mon = monAt(BULBASAUR, 50)
  mon.moves[4] = nil
  mon.pp[4] = nil
  mon.maxPp[4] = nil
  local done = nil
  MoveRelearner.show(mon, { onDone = function(learned) done = learned end })
  local wanted = MoveRelearner.moves()[1]
  check(wanted == TACKLE, "the first offer is TACKLE, got " .. tostring(wanted))

  local pressed = nil
  local input = { wasPressed = function(_, key) return key == pressed end }
  local function press(key)
    pressed = key
    MoveRelearner.handleInput(input)
    pressed = nil
  end

  press("a")
  check(MoveRelearner.prompt:find("Teach TACKLE?", 1, true) ~= nil,
    "the confirm asks Teach TACKLE?, got " .. tostring(MoveRelearner.prompt))
  press("a")
  check(MoveRelearner.prompt:find("learned", 1, true) ~= nil,
    "the learned page is shown, got " .. tostring(MoveRelearner.prompt))
  press("a")
  check(done == true, "the screen reports the teach back to the script")
  check(Pokemon.knowsMove(mon, TACKLE), "and the mon knows TACKLE")
  check(not MoveRelearner.isOpen(), "the screen closed after the teach")
end

finish()
