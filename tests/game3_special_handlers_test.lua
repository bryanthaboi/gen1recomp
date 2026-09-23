#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;" .. package.path
require("tests.game3_cache").stubSpeciesNames()
local ROM_TEXT = { gText_PkmnsNickname = "'s nickname?" }
local function romTextKey(n, i, j) return j and (n .. "[" .. i .. "][" .. j .. "]") or (n .. "[" .. i .. "]") end
local function romTextPlain(key, ctx) return ((ROM_TEXT[key] or key):gsub("{PLAYER}", ctx and ctx.playerName or "")) end
package.loaded["src.core.game3.rom_text"] = {
  plain = romTextPlain, box = romTextPlain, ascii = romTextPlain, has = function() return true end,
  key = romTextKey, at = function(n, i, j, ctx) return romTextPlain(romTextKey(n, i, j), ctx) end,
  count = function() return 0 end, list = function() return {} end,
  lazy = function(map) return setmetatable({}, { __index = function(_, k) return map[k] end }) end,
}

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local Ctx = require("src.core.game3.scripting.ctx")
local Flags = require("src.core.game3.scripting.flags")
local Std = require("src.core.game3.scripting.stdscripts")
local Natives = require("src.core.game3.scripting.natives")
local Ops = require("src.core.game3.scripting.ops_a")

local function newCtx()
  local ctx = Ctx.new({})
  ctx.mode = "bytecode"
  ctx.status = "running"
  return ctx
end

local function session(tbl)
  package.loaded["src.core.game3.runtime"] = {
    getSession = function() return tbl end,
    isActive = function() return true end,
  }
  return tbl
end

print("[test] 1. ChoosePartyMon writes the slot into VAR_0x8004")
local s = session({
  trainerId = 4242,
  party = {
    { species = 1, nickname = "", otId = 4242 },
    { species = 4, nickname = "SPIKE", otId = 999 },
  },
})
local ctx = newCtx()
local picked, pending
local adapters = {
  log = function() end,
  chooseParty = function(opts, done)
    picked = opts.menuType
    pending = done
  end,
}
local yielded = Natives.special(ctx, Std.SPECIAL.ChoosePartyMon, adapters)
check(picked == "choose_single", "party chooser opened in choose_single mode")
check(yielded == true, "script yields while the picker is up")
check(ctx.nativePoll and ctx.nativePoll() == false, "native still waiting before a pick")
if pending then pending(1) end
check(Flags.getVar(nil, ctx, 0x8004) == 1, "VAR_0x8004 = 1 (got " ..
  tostring(Flags.getVar(nil, ctx, 0x8004)) .. ")")
check(ctx.nativePoll() == true, "native finished after the callback")

print("[test] 2. cancel writes SLOT_CANCEL (7), which scripts read as >= PARTY_SIZE")
local ctx2 = newCtx()
Natives.special(ctx2, Std.SPECIAL.ChoosePartyMon, {
  log = function() end,
  chooseParty = function(_, done) done(nil) end,
})
check(Flags.getVar(nil, ctx2, 0x8004) == 7, "VAR_0x8004 = 7 on cancel (got " ..
  tostring(Flags.getVar(nil, ctx2, 0x8004)) .. ")")

print("[test] 3. ChoosePartyMon is no longer the nickname keyboard")
local namedOpened = false
local ctx3 = newCtx()
Natives.special(ctx3, Std.SPECIAL.ChoosePartyMon, {
  log = function() end,
  openNaming = function(_, done) namedOpened = true; done("NOPE") end,
  chooseParty = function(_, done) done(0) end,
})
check(not namedOpened, "openNaming not reached by ChoosePartyMon")
check(s.party[1].nickname == "", "slot 1 nickname untouched")

print("[test] 4. specialvar writes the cart return value to its destination var")
local store = Flags.newStore()
local ctx4 = newCtx()
ctx4.lastBattleOutcome = Natives.B_OUTCOME.CAUGHT
local a = { log = function() end }
local function exec(c, row)
  return Ops.dispatch({ ctx = c, store = store, adapters = a, setPc = function() end }, row)
end
exec(ctx4, { op = "specialvar", [1] = 0x800D, [2] = Std.SPECIAL.GetBattleOutcome })
check(Flags.getVar(nil, ctx4, 0x800D) == Natives.B_OUTCOME.CAUGHT,
  "VAR_RESULT = B_OUTCOME_CAUGHT (got " .. tostring(Flags.getVar(nil, ctx4, 0x800D)) .. ")")
exec(ctx4, { op = "specialvar", [1] = 0x8008, [2] = Std.SPECIAL.GetBattleOutcome })
check(Flags.getVar(nil, ctx4, 0x8008) == Natives.B_OUTCOME.CAUGHT,
  "VAR_0x8008 = B_OUTCOME_CAUGHT (got " .. tostring(Flags.getVar(nil, ctx4, 0x8008)) .. ")")

print("[test] 5. GetDaycareState is not a battle outcome any more")
local ctx5 = newCtx()
ctx5.lastBattleOutcome = Natives.B_OUTCOME.CAUGHT
exec(ctx5, { op = "specialvar", [1] = 0x800D, [2] = Std.SPECIAL.GetDaycareState })
check(Flags.getVar(nil, ctx5, 0x800D) == 0, "empty daycare = DAYCARE_NO_MONS (got " ..
  tostring(Flags.getVar(nil, ctx5, 0x800D)) .. ")")
s.daycare = { { species = 16 } }
local ctx5b = newCtx()
exec(ctx5b, { op = "specialvar", [1] = 0x800D, [2] = Std.SPECIAL.GetDaycareState })
check(Flags.getVar(nil, ctx5b, 0x800D) == 2, "one mon = DAYCARE_ONE_MON (got " ..
  tostring(Flags.getVar(nil, ctx5b, 0x800D)) .. ")")
s.daycare = nil

print("[test] 6. IsMonOTIDNotPlayers answers the Name Rater")
local ctx6 = newCtx()
Flags.setVar(nil, ctx6, 0x8004, 0)
Natives.special(ctx6, Std.SPECIAL.IsMonOTIDNotPlayers, { log = function() end })
check(Flags.getVar(nil, ctx6, 0x800D) == 0, "own mon: VAR_RESULT = FALSE")
Flags.setVar(nil, ctx6, 0x8004, 1)
Natives.special(ctx6, Std.SPECIAL.IsMonOTIDNotPlayers, { log = function() end })
check(Flags.getVar(nil, ctx6, 0x800D) == 1, "traded mon: VAR_RESULT = TRUE")

print("[test] 7. the museum fossil id no longer touches FLAG_SYS_POKEDEX_GET")
local dexStore = Flags.newStore()
package.loaded["src.core.game3.scripting.space"] = { store = dexStore }
local ctx7 = newCtx()
Natives.special(ctx7, 0x18B, { log = function() end })
check(Flags.getFlag(dexStore, nil, 0x829) ~= true,
  "0x18B (OpenMuseumFossilPic) leaves FLAG_SYS_POKEDEX_GET clear")
Natives.special(ctx7, Std.SPECIAL.SetUnlockedPokedexFlags, { log = function() end })
check(Flags.getFlag(dexStore, nil, 0x829) ~= true,
  "SetUnlockedPokedexFlags does not set FLAG_SYS_POKEDEX_GET either")
check(s.gcnLinkFlags == 0x31, "SetUnlockedPokedexFlags sets gcnLinkFlags bits 0/4/5 (got " ..
  tostring(s.gcnLinkFlags) .. ")")

print("[test] 8. the Route 5 daycare id no longer unlocks the National Dex")
local ctx8 = newCtx()
Natives.special(ctx8, 0x179, { log = function() end })
check(Flags.getFlag(dexStore, nil, 0x840) ~= true, "0x179 leaves FLAG_SYS_NATIONAL_DEX clear")
Natives.special(ctx8, Std.SPECIAL.EnableNationalPokedex, { log = function() end })
check(Flags.getFlag(dexStore, nil, 0x840) == true, "0x16F EnableNationalPokedex sets it")

print("[test] 9. ChooseMonForMoveTutor opens the MOVE TUTOR party menu and answers FALSE on a cancel")
-- pokefirered/src/party_menu.c:5793 ChooseMonForMoveTutor
local PartyMenu9 = require("src.ui.game3.party_menu")
local ctx9 = newCtx()
local tutorPicker = false
Flags.setVar(nil, ctx9, 0x800D, 1)
Flags.setVar(nil, ctx9, 0x8005, 4)
local yield9 = Natives.special(ctx9, Std.SPECIAL.ChooseMonForMoveTutor, {
  log = function() end,
  chooseParty = function(_, done) tutorPicker = true; done(0) end,
})
check(yield9 == true, "the tutor special holds the script while the picker is up")
check(PartyMenu9.isOpen() and PartyMenu9.mode == "move_tutor",
  "the party menu is in the MOVE TUTOR action (got " .. tostring(PartyMenu9.mode) .. ")")
check(not tutorPicker, "the tutor drives the party menu itself, not the chooseParty seam")
PartyMenu9.close()
-- pokefirered/src/party_menu.c:4841
check(Flags.getVar(nil, ctx9, 0x800D) == 0, "VAR_RESULT = FALSE after a cancel (got "
  .. tostring(Flags.getVar(nil, ctx9, 0x800D)) .. ")")
check(ctx9.nativePoll and ctx9.nativePoll() == true, "the script resumes once the menu closes")

print("[test] 10. the nickname keyboard buffers the old nickname in STR_VAR_3")
local ctx10 = newCtx()
Flags.setVar(nil, ctx10, 0x8004, 1)
s.party[2].nickname = "SPIKE"
Natives.special(ctx10, Std.SPECIAL.ChangePokemonNickname, {
  log = function() end,
  openNaming = function(_, done) done("SPIKE") end,
})
check(ctx10.stringVars[3] == "SPIKE", "STR_VAR_3 holds the nickname the rater started from (got "
  .. tostring(ctx10.stringVars[3]) .. ")")
-- pokefirered/data/maps/LavenderTown_House2/scripts.inc:52
exec(ctx10, { op = "specialvar", [1] = 0x800D,
  [2] = Std.SPECIAL.NameRaterWasNicknameChanged })
check(Flags.getVar(nil, ctx10, 0x800D) == 0, "an unchanged nickname answers FALSE (got "
  .. tostring(Flags.getVar(nil, ctx10, 0x800D)) .. ")")
s.party[2].nickname = "SPARKY"
exec(ctx10, { op = "specialvar", [1] = 0x800D,
  [2] = Std.SPECIAL.NameRaterWasNicknameChanged })
check(Flags.getVar(nil, ctx10, 0x800D) == 1, "a new nickname answers TRUE (got "
  .. tostring(Flags.getVar(nil, ctx10, 0x800D)) .. ")")
check(ctx10.stringVars[1] == "SPARKY", "STR_VAR_1 holds the current nickname (got "
  .. tostring(ctx10.stringVars[1]) .. ")")

if failed > 0 then
  print("[test] FAILED " .. failed)
  os.exit(1)
end
print("[test] all passed")
