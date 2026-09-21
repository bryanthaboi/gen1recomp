#!/usr/bin/env luajit
-- pokefirered/src/party_menu.c:1892 GetTutorMove, :1907 CanLearnTutorMove,
-- pokefirered/src/field_specials.c:2219 CapeBrinkGetMoveToTeachLeadPokemon

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
  print("[PASS] game3_moveteach_tutor")
  os.exit(0)
end

local Cache = require("tests.game3_cache")
local cacheRoot = Cache.mount("pokemon/learnsets.lua")
if not cacheRoot then
  print("[skip] game3_moveteach_tutor: " .. tostring(Cache.reason))
  os.exit(0)
end
print("[info] FireRed cache at " .. cacheRoot)

local Pokemon = require("src.core.game3.pokemon")
Pokemon.install(nil)

local MoveLearn = require("src.core.game3.move_learn")
local PartyMenu = require("src.ui.game3.party_menu")
local Natives = require("src.core.game3.scripting.natives")
local Flags = require("src.core.game3.scripting.flags")
local Ctx = require("src.core.game3.scripting.ctx")

local MEGA_PUNCH, SWORDS_DANCE, MEGA_KICK = 5, 14, 25
local BODY_SLAM, DOUBLE_EDGE, COUNTER = 34, 38, 68
local SEISMIC_TOSS, MIMIC, METRONOME = 69, 102, 118
local SOFT_BOILED, DREAM_EATER, THUNDER_WAVE = 135, 138, 86
local EXPLOSION, ROCK_SLIDE, SUBSTITUTE = 153, 157, 164
local FRENZY_PLANT, BLAST_BURN, HYDRO_CANNON = 338, 307, 308
local TACKLE = 33

local BULBASAUR, VENUSAUR, CHARIZARD, BLASTOISE = 1, 3, 6, 9
local GEODUDE, CHANSEY = 74, 113

-- pokefirered/include/constants/flags.h:761
local FLAG_TUTOR_FRENZY_PLANT = 0x2DE
local FLAG_TUTOR_BLAST_BURN = 0x2DF
local FLAG_TUTOR_HYDRO_CANNON = 0x2E0

local function monAt(species, level)
  local moves, pp, maxPp = Pokemon.movesAtLevel(species, level)
  return {
    species = species, speciesId = species, level = level,
    moves = moves, pp = pp, maxPp = maxPp,
    hp = 20, maxHp = 20, friendship = 70, happiness = 70,
  }
end

local pressed = nil
local input = {
  wasPressed = function(_, key) return key == pressed end,
  isDown = function(_, key) return key == pressed end,
}
local function press(key)
  pressed = key
  PartyMenu.handleInput(input)
  pressed = nil
end

print("[test] 1. sTutorMoves")
do
  local want = {
    [0] = MEGA_PUNCH, SWORDS_DANCE, MEGA_KICK, BODY_SLAM, DOUBLE_EDGE, COUNTER,
    SEISMIC_TOSS, MIMIC, METRONOME, SOFT_BOILED, DREAM_EATER, THUNDER_WAVE,
    EXPLOSION, ROCK_SLIDE, SUBSTITUTE,
  }
  check(MoveLearn.TUTOR_MOVE_COUNT == 15, "TUTOR_MOVE_COUNT is 15")
  local allOk = true
  for tutor = 0, 14 do
    if MoveLearn.tutorMove(tutor) ~= want[tutor] then
      allOk = false
      print("       tutor " .. tutor .. " gave " .. tostring(MoveLearn.tutorMove(tutor))
        .. " want " .. tostring(want[tutor]))
    end
  end
  check(allOk, "all fifteen regular tutor moves match pret's table")
  check(MoveLearn.tutorMove(MoveLearn.TUTOR_MOVE_FRENZY_PLANT) == FRENZY_PLANT,
    "GetTutorMove(TUTOR_MOVE_FRENZY_PLANT) is FRENZY PLANT")
  check(MoveLearn.tutorMove(MoveLearn.TUTOR_MOVE_BLAST_BURN) == BLAST_BURN,
    "GetTutorMove(TUTOR_MOVE_BLAST_BURN) is BLAST BURN")
  check(MoveLearn.tutorMove(MoveLearn.TUTOR_MOVE_HYDRO_CANNON) == HYDRO_CANNON,
    "GetTutorMove(TUTOR_MOVE_HYDRO_CANNON) is HYDRO CANNON")
end

print("[test] 2. CanLearnTutorMove, the three hardcoded starter branches")
do
  check(MoveLearn.canLearnTutorMove(VENUSAUR, MoveLearn.TUTOR_MOVE_FRENZY_PLANT),
    "VENUSAUR can learn FRENZY PLANT")
  check(not MoveLearn.canLearnTutorMove(CHARIZARD, MoveLearn.TUTOR_MOVE_FRENZY_PLANT),
    "CHARIZARD cannot")
  check(MoveLearn.canLearnTutorMove(CHARIZARD, MoveLearn.TUTOR_MOVE_BLAST_BURN),
    "CHARIZARD can learn BLAST BURN")
  check(not MoveLearn.canLearnTutorMove(BLASTOISE, MoveLearn.TUTOR_MOVE_BLAST_BURN),
    "BLASTOISE cannot")
  check(MoveLearn.canLearnTutorMove(BLASTOISE, MoveLearn.TUTOR_MOVE_HYDRO_CANNON),
    "BLASTOISE can learn HYDRO CANNON")
  check(not MoveLearn.canLearnTutorMove(BULBASAUR, MoveLearn.TUTOR_MOVE_HYDRO_CANNON),
    "BULBASAUR cannot")
end

print("[test] 3. CanLearnTutorMove, the per-species bitfield")
do
  local sets = MoveLearn.tutorLearnsets()
  if not sets then
    print("[skip] no pokemon/tutor.lua in this cache; sTutorLearnsets is not imported yet")
    check(not MoveLearn.canLearnTutorMove(GEODUDE, 13),
      "with no imported table every regular tutor refuses")
  else
    -- pokefirered/src/data/pokemon/tutor_learnsets.h:22
    check(MoveLearn.canLearnTutorMove(GEODUDE, 13), "GEODUDE can learn ROCK SLIDE")
    check(not MoveLearn.canLearnTutorMove(GEODUDE, 9), "GEODUDE cannot learn SOFT-BOILED")
    check(MoveLearn.canLearnTutorMove(CHANSEY, 9), "CHANSEY can learn SOFT-BOILED")
    check(MoveLearn.canLearnTutorMove(BULBASAUR, 1), "BULBASAUR can learn SWORDS DANCE")
    check(not MoveLearn.canLearnTutorMove(BULBASAUR, 0), "BULBASAUR cannot learn MEGA PUNCH")
    check(not MoveLearn.canLearnTutorMove(0, 0), "SPECIES_NONE can learn nothing")
  end
end

print("[test] 4. CanMonLearnTMTutor with item 0")
do
  local venu = monAt(VENUSAUR, 40)
  check(MoveLearn.canMonLearnTutorMove(venu, MoveLearn.TUTOR_MOVE_FRENZY_PLANT)
      == MoveLearn.CAN_LEARN_MOVE,
    "a VENUSAUR that does not know FRENZY PLANT reports CAN_LEARN_MOVE")
  check(MoveLearn.canMonLearnTutorMove(venu, MoveLearn.TUTOR_MOVE_BLAST_BURN)
      == MoveLearn.CANNOT_LEARN_MOVE,
    "and CANNOT_LEARN_MOVE for the wrong starter move")

  local known = monAt(VENUSAUR, 40)
  known.moves[1] = FRENZY_PLANT
  check(MoveLearn.canMonLearnTutorMove(known, MoveLearn.TUTOR_MOVE_FRENZY_PLANT)
      == MoveLearn.ALREADY_KNOWS_MOVE,
    "one that already knows it reports ALREADY_KNOWS_MOVE")

  local egg = monAt(VENUSAUR, 40)
  egg.isEgg = true
  check(MoveLearn.canMonLearnTutorMove(egg, MoveLearn.TUTOR_MOVE_FRENZY_PLANT)
      == MoveLearn.CANNOT_LEARN_MOVE_IS_EGG,
    "an EGG reports CANNOT_LEARN_MOVE_IS_EGG")
end

print("[test] 5. GetLeadMonIndex skips eggs")
do
  local egg = monAt(BULBASAUR, 5)
  egg.isEgg = true
  check(MoveLearn.leadMonIndex({ egg, monAt(VENUSAUR, 40) }) == 1,
    "the lead is the first non-egg slot, got "
      .. tostring(MoveLearn.leadMonIndex({ egg, monAt(VENUSAUR, 40) })))
  check(MoveLearn.leadMonIndex({ monAt(VENUSAUR, 40) }) == 0, "slot 1 otherwise")
  check(MoveLearn.leadMonIndex({}) == 0, "and 0 with no party")
end

local prevRuntime = package.loaded["src.core.game3.runtime"]
local store = { flags = {}, vars = {} }
local session = { store = store, party = {} }
package.loaded["src.core.game3.runtime"] = {
  getSession = function() return session end,
  isActive = function() return true end,
}

print("[test] 6. CapeBrinkGetMoveToTeachLeadPokemon")
do
  local party = { monAt(VENUSAUR, 40) }
  session.party = party

  local function newCtx()
    local ctx = Ctx.new({})
    ctx.mode = "bytecode"
    ctx.status = "running"
    return ctx
  end

  local strings = {}
  local adapters = { log = function() end,
    setStringVar = function(i, t) strings[i] = t end }

  local ctx = newCtx()
  local handled = select(3, Natives.special(ctx, 0x1A3, adapters))
  check(handled == true, "special 0x1A3 is bound (pokefirered/data/specials.inc:430)")
  check(Flags.getVar(store, ctx, 0x800D) == 0,
    "a VENUSAUR below max friendship is refused, got "
      .. tostring(Flags.getVar(store, ctx, 0x800D)))

  party[1].friendship = 255
  party[1].happiness = 255
  ctx = newCtx()
  Natives.special(ctx, 0x1A3, adapters)
  check(Flags.getVar(store, ctx, 0x800D) == 1, "at friendship 255 it returns TRUE")
  check(Flags.getVar(store, ctx, 0x8005) == MoveLearn.TUTOR_MOVE_FRENZY_PLANT,
    "VAR_0x8005 carries MOVETUTOR_FRENZY_PLANT, got "
      .. tostring(Flags.getVar(store, ctx, 0x8005)))
  check(Flags.getVar(store, ctx, 0x8006) == 4,
    "VAR_0x8006 carries the number of known moves, got "
      .. tostring(Flags.getVar(store, ctx, 0x8006)))
  check(Flags.getVar(store, ctx, 0x8007) == 0, "VAR_0x8007 carries the lead slot")
  check(strings[2] == Pokemon.moveName(FRENZY_PLANT),
    "STR_VAR_2 holds the move name, got " .. tostring(strings[2]))

  ctx = newCtx()
  Flags.setFlag(store, ctx, FLAG_TUTOR_FRENZY_PLANT, true)
  Natives.special(ctx, 0x1A3, adapters)
  check(Flags.getVar(store, ctx, 0x800D) == 0,
    "with FLAG_TUTOR_FRENZY_PLANT set it refuses a second time")
  Flags.setFlag(store, ctx, FLAG_TUTOR_FRENZY_PLANT, false)

  party[1] = monAt(BULBASAUR, 40)
  party[1].friendship = 255
  ctx = newCtx()
  Natives.special(ctx, 0x1A3, adapters)
  check(Flags.getVar(store, ctx, 0x800D) == 0, "a non-starter-final lead is refused")
end

print("[test] 7. HasLearnedAllMovesFromCapeBrinkTutor")
do
  local ctx = Ctx.new({})
  ctx.mode = "bytecode"
  ctx.status = "running"
  Flags.setVar(store, ctx, 0x8005, MoveLearn.TUTOR_MOVE_FRENZY_PLANT)
  local handled = select(3, Natives.special(ctx, 0x1A4, { log = function() end }))
  check(handled == true, "special 0x1A4 is bound (pokefirered/data/specials.inc:431)")
  check(Flags.getFlag(store, ctx, FLAG_TUTOR_FRENZY_PLANT) == true,
    "it burns FLAG_TUTOR_FRENZY_PLANT")
  check(Flags.getVar(store, ctx, 0x800D) == 0, "one of three is not all of them")

  Flags.setVar(store, ctx, 0x8005, MoveLearn.TUTOR_MOVE_BLAST_BURN)
  Natives.special(ctx, 0x1A4, { log = function() end })
  check(Flags.getFlag(store, ctx, FLAG_TUTOR_BLAST_BURN) == true,
    "then FLAG_TUTOR_BLAST_BURN")
  check(Flags.getVar(store, ctx, 0x800D) == 0, "two of three is still not all")

  Flags.setVar(store, ctx, 0x8005, MoveLearn.TUTOR_MOVE_HYDRO_CANNON)
  Natives.special(ctx, 0x1A4, { log = function() end })
  check(Flags.getFlag(store, ctx, FLAG_TUTOR_HYDRO_CANNON) == true,
    "then FLAG_TUTOR_HYDRO_CANNON")
  check(Flags.getVar(store, ctx, 0x800D) == 1, "all three returns TRUE")
end

print("[test] 8. the party menu MOVE_TUTOR action")
do
  local party = { monAt(VENUSAUR, 40), monAt(BULBASAUR, 10) }
  party[1].moves[4] = nil
  party[1].pp[4] = nil
  party[1].maxPp[4] = nil
  PartyMenu.show(party, nil, {
    mode = "move_tutor",
    tutor = MoveLearn.TUTOR_MOVE_FRENZY_PLANT,
  })
  check(PartyMenu.mode == "move_tutor", "the menu opens in the tutor action")
  check(PartyMenu.slotDescription(1) == "ABLE!",
    "the VENUSAUR slot reads ABLE!, got " .. tostring(PartyMenu.slotDescription(1)))
  check(PartyMenu.slotDescription(2) == "NOT ABLE!",
    "the BULBASAUR slot reads NOT ABLE!, got " .. tostring(PartyMenu.slotDescription(2)))

  press("a")
  check(PartyMenu.mode == "message", "picking the VENUSAUR prints a page")
  check(tostring(PartyMenu._messageText):find("learned", 1, true) ~= nil,
    "which is the learned page, got " .. tostring(PartyMenu._messageText))
  check(Pokemon.knowsMove(party[1], FRENZY_PLANT), "the VENUSAUR knows FRENZY PLANT")
  PartyMenu.dismissMessage()
  check(PartyMenu._tutorResult == true, "and the menu reports a real teach")
  check(not PartyMenu.isOpen(), "the menu closed")
end

print("[test] 9. the refusals")
do
  local party = { monAt(BULBASAUR, 10) }
  PartyMenu.show(party, nil, {
    mode = "move_tutor",
    tutor = MoveLearn.TUTOR_MOVE_FRENZY_PLANT,
  })
  press("a")
  check(tostring(PartyMenu._messageText):find("are not compatible", 1, true) ~= nil,
    "an incompatible mon gets pret's first page, got " .. tostring(PartyMenu._messageText))
  PartyMenu.dismissMessage()
  check(tostring(PartyMenu._messageText):find("can't be\nlearned", 1, true) ~= nil,
    "then its second page, got " .. tostring(PartyMenu._messageText))
  PartyMenu.dismissMessage()
  check(PartyMenu._tutorResult == false, "and nothing was taught")

  local known = { monAt(VENUSAUR, 40) }
  known[1].moves[1] = FRENZY_PLANT
  PartyMenu.show(known, nil, {
    mode = "move_tutor",
    tutor = MoveLearn.TUTOR_MOVE_FRENZY_PLANT,
  })
  press("a")
  check(tostring(PartyMenu._messageText):find("already knows", 1, true) ~= nil,
    "one that already knows the move is told so, got " .. tostring(PartyMenu._messageText))
  PartyMenu.dismissMessage()
  check(PartyMenu._tutorResult == false, "and VAR_RESULT stays FALSE")
end

print("[test] 10. a full moveset takes the replace flow")
do
  local party = { monAt(VENUSAUR, 40) }
  local mon = party[1]
  check(Pokemon.moveSlotCount(mon) == 4, "the VENUSAUR starts with four moves")
  PartyMenu.show(party, nil, {
    mode = "move_tutor",
    tutor = MoveLearn.TUTOR_MOVE_FRENZY_PLANT,
  })
  press("a")
  check(PartyMenu.mode == "message", "the wants-to-learn page opens")
  PartyMenu.dismissMessage()
  PartyMenu.dismissMessage()
  check(PartyMenu.mode == "yesno", "then the delete prompt, got " .. tostring(PartyMenu.mode))
  check(tostring(PartyMenu._yesNoPrompt):find("Should a move be deleted", 1, true) ~= nil,
    "with pret's field wording, got " .. tostring(PartyMenu._yesNoPrompt))
  local cb = PartyMenu._yesNoCallback
  cb(false)
  check(tostring(PartyMenu._yesNoPrompt):find("Stop trying to teach", 1, true) ~= nil,
    "declining asks the stop question, got " .. tostring(PartyMenu._yesNoPrompt))
  PartyMenu._yesNoCallback(true)
  check(tostring(PartyMenu._messageText):find("did not learn", 1, true) ~= nil,
    "confirming prints the did-not-learn page, got " .. tostring(PartyMenu._messageText))
  PartyMenu.dismissMessage()
  check(PartyMenu._tutorResult == false, "and VAR_RESULT stays FALSE")
  check(not Pokemon.knowsMove(mon, FRENZY_PLANT), "the moveset is untouched")
end

print("[test] 11. ChooseMonForMoveTutor sets VAR_RESULT only on a real teach")
do
  local party = { monAt(VENUSAUR, 40) }
  party[1].moves[4] = nil
  party[1].pp[4] = nil
  party[1].maxPp[4] = nil
  session.party = party

  local function newCtx()
    local ctx = Ctx.new({})
    ctx.mode = "bytecode"
    ctx.status = "running"
    return ctx
  end

  local ctx = newCtx()
  Flags.setVar(store, ctx, 0x8005, MoveLearn.TUTOR_MOVE_FRENZY_PLANT)
  Flags.setVar(store, ctx, 0x8007, 0)
  local yielded, _, handled = Natives.special(ctx, 0x18D, { log = function() end })
  check(handled == true, "special 0x18D is bound (pokefirered/data/specials.inc:408)")
  check(yielded == true, "the script yields while the tutor party menu is up")
  check(PartyMenu.isOpen() and PartyMenu.mode == "move_tutor",
    "and the menu opened in the tutor action")
  press("a")
  PartyMenu.dismissMessage()
  check(ctx.nativePoll and ctx.nativePoll() == true, "the native finishes when it closes")
  check(Flags.getVar(store, ctx, 0x800D) == 1,
    "VAR_RESULT is TRUE after a real teach, got " .. tostring(Flags.getVar(store, ctx, 0x800D)))
  check(Pokemon.knowsMove(party[1], FRENZY_PLANT), "the mon learned FRENZY PLANT")

  party[1] = monAt(VENUSAUR, 40)
  ctx = newCtx()
  Flags.setVar(store, ctx, 0x8005, MoveLearn.TUTOR_MOVE_FRENZY_PLANT)
  Natives.special(ctx, 0x18D, { log = function() end })
  press("b")
  check(Flags.getVar(store, ctx, 0x800D) == 0,
    "cancelling leaves VAR_RESULT FALSE, got " .. tostring(Flags.getVar(store, ctx, 0x800D)))
  check(not Pokemon.knowsMove(party[1], FRENZY_PLANT), "and teaches nothing")
end

print("[test] 12. the Cape Brink tutor picks the lead mon with no player choice")
do
  local party = { monAt(BLASTOISE, 40), monAt(BULBASAUR, 10) }
  party[1].moves[3] = nil
  party[1].moves[4] = nil
  party[1].pp[3], party[1].pp[4] = nil, nil
  party[1].maxPp[3], party[1].maxPp[4] = nil, nil
  session.party = party

  local ctx = Ctx.new({})
  ctx.mode = "bytecode"
  ctx.status = "running"
  Flags.setVar(store, ctx, 0x8005, MoveLearn.TUTOR_MOVE_HYDRO_CANNON)
  Flags.setVar(store, ctx, 0x8007, 0)
  Natives.special(ctx, 0x18D, { log = function() end })
  check(PartyMenu.mode == "move_tutor", "the party menu opened")
  PartyMenu.update(1 / 60)
  check(tostring(PartyMenu._messageText):find("learned", 1, true) ~= nil,
    "the lead mon is taught with no A press, got " .. tostring(PartyMenu._messageText))
  PartyMenu.dismissMessage()
  check(Pokemon.knowsMove(party[1], HYDRO_CANNON), "the BLASTOISE knows HYDRO CANNON")
  check(Flags.getVar(store, ctx, 0x800D) == 1, "VAR_RESULT is TRUE")
end

package.loaded["src.core.game3.runtime"] = prevRuntime

print("[test] 13. the tutor action never disturbs the plain chooser")
do
  local party = { monAt(BULBASAUR, 10) }
  PartyMenu.show(party, nil, { mode = "choose" })
  check(PartyMenu._tutor == nil, "a plain choose carries no tutor")
  check(PartyMenu.slotDescription(1) == nil,
    "and prints no ABLE line, got " .. tostring(PartyMenu.slotDescription(1)))
  PartyMenu.close()
  local free = monAt(BULBASAUR, 10)
  check(MoveLearn.tutorMove(99) == nil, "an out-of-range tutor has no move")
  check(MoveLearn.canMonLearnTutorMove(free, 99) == MoveLearn.CANNOT_LEARN_MOVE,
    "and refuses")
  check(Pokemon.knowsMove(free, TACKLE),
    "a level 10 BULBASAUR still knows TACKLE from its own learnset")
end

finish()
