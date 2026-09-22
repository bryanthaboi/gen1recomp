package.path = "./?.lua;./?/init.lua;" .. package.path

local Std = require("src.core.game3.scripting.stdscripts")
local Natives = require("src.core.game3.scripting.natives")
local Flags = require("src.core.game3.scripting.flags")
local Schema = require("src.core.game3.save_schema_firered")
local TrainerCard = require("src.ui.game3.trainer_card")

local passed, failed = 0, 0
local function check(cond, msg)
  if cond then
    passed = passed + 1
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function checkEq(got, expected, msg)
  if got == expected then
    passed = passed + 1
    print(string.format("[ok] %s (got %s)", msg, tostring(got)))
  else
    failed = failed + 1
    print(string.format("[FAIL] %s: expected %s, got %s", msg, tostring(expected), tostring(got)))
  end
end

local SPACE_KEY = "src.core.game3.scripting.space"
local RT_KEY = "src.core.game3.runtime"

local realLoadedSpace = package.loaded[SPACE_KEY]
local realLoadedRt = package.loaded[RT_KEY]

local function teardown()
  package.loaded[SPACE_KEY] = realLoadedSpace
  package.loaded[RT_KEY] = realLoadedRt
end

print("=== 1. Photo script path writes tint + species into THE store the card reads ===")
local session, store, ctx
do
  session = Schema.newGame({ name = "RED" })
  session.party = { { speciesId = 4, species = 4 } }

  store = Flags.newStore()
  package.loaded[SPACE_KEY] = { store = store, getStore = function() return store end }
  package.loaded[RT_KEY] = { getSession = function() return session end }

  ctx = {
    flags = session.flags,
    vars = session.vars,
    specialVars = {},
  }

  Flags.setVar(store, ctx, 0x8004, 2)
  local yielded = Natives.special(ctx, Std.SPECIAL.UpdateTrainerCardPhotoIcons)
  check(yielded == false, "UpdateTrainerCardPhotoIcons completes without yielding")

  checkEq(Flags.getVar(store, ctx, 0x4042), 2, "store 0x4042 tint idx is 2 (PINK)")
  checkEq(Flags.getVar(store, ctx, 0x4043), 4, "store 0x4043 icon 1 is species 4")
  for id = 0x4044, 0x4048 do
    checkEq(Flags.getVar(store, ctx, id), 0, string.format("store 0x%04X empty slot", id))
  end
  checkEq(session.vars[0x4042], nil, "special vars do NOT leak into session.vars")

  local c = TrainerCard.cardData(session)
  checkEq(c.monIconTint, 2, "gather reads monIconTint=2 from the live store")
  checkEq(c.monSpecies[1], 4, "gather reads monSpecies[1]=4 from the live store")
end

print("=== 2. Persist round trip: serialize (game.save) -> loadInto (next boot) ===")
do
  local snap = Flags.serialize(store)
  checkEq(snap.vars["16450"], 2, "serialize writes string key [\"16450\"]=2 (save format)")
  checkEq(snap.vars["16451"], 4, "serialize writes string key [\"16451\"]=4")

  local bootStore = Flags.newStore()
  Flags.loadInto(bootStore, snap)
  checkEq(bootStore.vars[0x4042], 2, "loadInto restores numeric 0x4042=2")
  checkEq(bootStore.vars[0x4043], 4, "loadInto restores numeric 0x4043=4")

  package.loaded[SPACE_KEY] = { store = bootStore, getStore = function() return bootStore end }
  local c = TrainerCard.cardData(session)
  checkEq(c.monIconTint, 2, "card gather after reload reads monIconTint=2")
  checkEq(c.monSpecies[1], 4, "card gather after reload reads monSpecies[1]=4")
end

print("=== 3. Store unavailable: session.vars fallback must read string keys ===")
do
  local snap = Flags.serialize(store)
  session.vars = snap.vars
  package.loaded[SPACE_KEY] = nil

  local c = TrainerCard.cardData(session)
  checkEq(c.monIconTint, 2, "fallback reads [\"16450\"] -> monIconTint=2")
  checkEq(c.monSpecies[1], 4, "fallback reads [\"16451\"] -> monSpecies[1]=4")
end

print("=== 4. Multi-mon party: all six species keys match snapshot order ===")
do
  local session4 = Schema.newGame({ name = "RED" })
  session4.party = {
    { speciesId = 1, species = 1 },
    { speciesId = 4, species = 4 },
    { speciesId = 7, species = 7 },
    { speciesId = 25, species = 25 },
    { speciesId = 133, species = 133 },
    { speciesId = 152, species = 152 },
  }
  local store4 = Flags.newStore()
  package.loaded[SPACE_KEY] = { store = store4, getStore = function() return store4 end }
  package.loaded[RT_KEY] = { getSession = function() return session4 end }

  local ctx4 = { flags = session4.flags, vars = session4.vars, specialVars = {} }
  Flags.setVar(store4, ctx4, 0x8004, 2)
  Natives.special(ctx4, Std.SPECIAL.UpdateTrainerCardPhotoIcons)

  checkEq(Flags.getVar(store4, ctx4, 0x4042), 2, "multi-mon: store 0x4042 tint idx is 2")
  local want = { 1, 4, 7, 25, 133, 152 }
  for i = 1, 6 do
    checkEq(Flags.getVar(store4, ctx4, 0x4042 + i), want[i],
      string.format("multi-mon: store 0x%04X icon %d snapshot order", 0x4042 + i, i))
  end
  local c4 = TrainerCard.cardData(session4)
  checkEq(c4.monIconTint, 2, "multi-mon: gather monIconTint=2")
  for i = 1, 6 do
    checkEq(c4.monSpecies[i], want[i], string.format("multi-mon: gather monSpecies[%d]", i))
  end
end

teardown()

print(string.format("Total: %d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
