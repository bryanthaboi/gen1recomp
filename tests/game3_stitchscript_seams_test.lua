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

local GameVersion = require("src.core.GameVersion")
GameVersion.set("firered")

local Flags = require("src.core.game3.scripting.flags")
local Vm = require("src.core.game3.scripting.vm")
local Adapters = require("src.core.game3.scripting.adapters")
local Runtime = require("src.core.game3.runtime")
local Storage = require("src.core.game3.storage")
local Natives = require("src.core.game3.scripting.natives")
local FieldView = require("src.core.game3.field_view")
local FieldEffects = require("src.core.game3.field_effects")
local Braille = require("src.ui.game3.braille")
local PartyMenu = require("src.ui.game3.party_menu")

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function eq(a, b, msg)
  check(a == b, string.format("%s (%s == %s)", msg, tostring(a), tostring(b)))
end

local VAR_TEMP_1 = 0x4001
local VAR_0x8004 = 0x8004
local VAR_0x8005 = 0x8005
local VAR_0x8006 = 0x8006
local SPECIAL_CHANGE_BOX_POKEMON_NICKNAME = 0x166
local SPECIAL_BRAILLE_CURSOR_TOGGLE = 0x1B2
local SPECIES_MAGIKARP = 129
local SLOT_CANCEL = 7

local prevSession = Runtime.session

local function newSession()
  local session = {
    party = {},
    store = Flags.newStore(),
    dex = { seen = {}, owned = {} },
    name = "RED",
    trainerId = 1,
  }
  Storage.ensure(session)
  Runtime.session = session
  return session
end

local function run(rows, adapters)
  local store = Flags.newStore()
  local vm = Vm.new({
    store = store,
    scripts = { t = rows },
    adapters = adapters or Adapters.host(nil, nil, nil),
  })
  vm:start("t")
  return vm, store
end

print("[test] 1. setflashlevel writes the level pret keeps in SaveBlock1")
FieldView.setFlashLevel(0)
run({
  { op = "setflashlevel", [1] = 3 },
  { op = "end" },
})
eq(FieldView.getFlashLevel(), 3, "a literal argument lands in the flash level")

run({
  { op = "setvar", [1] = VAR_TEMP_1, [2] = 1 },
  { op = "setflashlevel", [1] = VAR_TEMP_1 },
  { op = "end" },
})
eq(FieldView.getFlashLevel(), 1, "the halfword argument goes through VarGet")

run({
  { op = "setflashlevel", [1] = 9 },
  { op = "end" },
})
eq(FieldView.getFlashLevel(), 0, "out of range clamps to 0")

print("[test] 2. animateflash blocks the script until the radius animation ends")
FieldEffects._anims = {}
FieldView.setFlashLevel(4)
local vm2 = run({
  { op = "animateflash", [1] = 0 },
  { op = "setflashlevel", [1] = 0 },
  { op = "end" },
})
local function poll2()
  return type(vm2.ctx.nativePoll) == "function" and vm2.ctx.nativePoll() or false
end
check(vm2.ctx.mode == "native" and type(vm2.ctx.nativePoll) == "function",
  "the script is parked in a native wait")
eq(poll2(), false, "and does not finish on the first poll")
eq(#FieldEffects._anims, 1, "one flash_level animation is running")
eq(FieldEffects._anims[1] and FieldEffects._anims[1].kind, "flash_level",
  "it is the flash_level animation")
check(FieldView.flashRadius() ~= nil, "the radius is being driven while it runs")

local ticks = 0
while ticks < 4000 and #FieldEffects._anims > 0 and not poll2() do
  FieldEffects.step()
  ticks = ticks + 1
end
check(poll2(), "the native wait ends with the animation, ticks " .. tostring(ticks))
check(ticks > 1, "it really animated instead of finishing instantly")
eq(FieldView.getFlashLevel(), 0, "and the cave is fully lit at the end")
eq(#FieldEffects._anims, 0, "no animation is left over")

FieldEffects._anims = {}
FieldView.setFlashLevel(2)
local vm2b = run({
  { op = "animateflash", [1] = 2 },
  { op = "end" },
})
check(vm2b.ctx.mode ~= "native", "animating to the level already shown does not park the script")
eq(FieldView.getFlashLevel(), 2, "the level is unchanged")
FieldView.setFlashLevel(0)

print("[test] 3. BrailleCursorToggle creates and destroys the blinking cursor")
Braille.clearCursor()
run({
  { op = "setvar", [1] = VAR_0x8006, [2] = 0 },
  { op = "setvar", [1] = VAR_0x8004, [2] = 52 },
  { op = "setvar", [1] = VAR_0x8005, [2] = 130 },
  { op = "special", [1] = SPECIAL_BRAILLE_CURSOR_TOGGLE, id = SPECIAL_BRAILLE_CURSOR_TOGGLE },
  { op = "end" },
})
local cur = Braille.cursor()
check(type(cur) == "table", "VAR_0x8006 = 0 created the cursor")
eq(cur and cur.x, 52 + 27, "x is the braille string width plus 27")
eq(cur and cur.y, 130, "y is VAR_0x8005 straight from the map script")

run({
  { op = "setvar", [1] = VAR_0x8006, [2] = 1 },
  { op = "special", [1] = SPECIAL_BRAILLE_CURSOR_TOGGLE, id = SPECIAL_BRAILLE_CURSOR_TOGGLE },
  { op = "end" },
})
eq(Braille.cursor(), nil, "VAR_0x8006 = 1 destroys it again")

print("[test] 4. ChangeBoxPokemonNickname renames the mon at monBoxId / monBoxPos")
local s4 = newSession()
local giveMagikarp = { { op = "givemon", [1] = SPECIES_MAGIKARP, [2] = 5 }, { op = "end" } }
for _ = 1, 7 do run(giveMagikarp) end
eq(#s4.party, 6, "the party filled up")
local boxed = s4.storage.boxes[1].mons[1]
check(boxed ~= nil, "the seventh gift is in box 1 slot 1")
eq(s4.monBoxId, 0, "session.monBoxId points at box 1")
eq(s4.monBoxPos, 0, "session.monBoxPos points at slot 1")

local opened, titleSeen, beforeVar3 = false, nil, nil
local naming = {
  log = function() end,
  setStringVar = function(idx, text)
    if idx == 3 then beforeVar3 = text end
  end,
  openNaming = function(opts, done)
    opened = true
    titleSeen = opts.title
    eq(opts.template, "NICKNAME", "the keyboard opens on the NICKNAME template")
    eq(opts.maxLen, 10, "with POKEMON_NAME_LENGTH")
    eq(opts.species, SPECIES_MAGIKARP, "for the boxed MAGIKARP")
    done("SPLASHY")
  end,
}
local vm4 = run({
  { op = "special", [1] = SPECIAL_CHANGE_BOX_POKEMON_NICKNAME,
    id = SPECIAL_CHANGE_BOX_POKEMON_NICKNAME },
  { op = "waitstate" },
  { op = "end" },
}, naming)
check(opened, "the special reached the naming keyboard")
check(type(titleSeen) == "string" and titleSeen ~= "", "it carried a title")
check(type(beforeVar3) == "string", "STR_VAR_3 got the old name, " .. tostring(beforeVar3))
local renamed = s4.storage.boxes[1].mons[1]
eq(renamed and renamed.nickname, "SPLASHY", "the box mon was renamed")
eq(#s4.party, 6, "no party mon was touched")
check(s4.party[1] and (s4.party[1].nickname == nil or s4.party[1].nickname == ""),
  "slot 1 of the party kept its name")
check(not vm4:isRunning(), "the script ran past waitstate once naming was done")

print("[test] 5. it is a no-op when the box slot is empty")
local s5 = newSession()
s5.monBoxId, s5.monBoxPos = 0, 0
local reopened = false
run({
  { op = "special", [1] = SPECIAL_CHANGE_BOX_POKEMON_NICKNAME,
    id = SPECIAL_CHANGE_BOX_POKEMON_NICKNAME },
  { op = "end" },
}, { log = function() end, openNaming = function() reopened = true end })
check(not reopened, "no keyboard for an empty slot")

print("[test] 6. the party picker fallback writes VAR_0x8004 exactly once")
local s6 = newSession()
s6.party = {
  { species = 1, level = 5, hp = 10, maxHp = 10 },
  { species = 4, level = 5, hp = 10, maxHp = 10 },
}
local function pickerCtx()
  local ctx = { specialVars = {}, writes = {} }
  function ctx:setVar(id, value)
    if id == VAR_0x8004 then self.writes[#self.writes + 1] = value end
  end
  return ctx
end

local function pollOf(ctx)
  return type(ctx.nativePoll) == "function" and ctx.nativePoll() or false
end

local ctx6 = pickerCtx()
local yielded = Natives.choosePartyMon(ctx6, { log = function() end }, "choose_single")
check(yielded == true, "the script yields while the picker is up")
check(PartyMenu.open == true, "the real party menu opened")
eq(#ctx6.writes, 0, "nothing is written before the player picks")
eq(pollOf(ctx6), false, "the native wait is still pending")
PartyMenu.close()
if PartyMenu._onSelect then PartyMenu._onSelect(2) end
check(pollOf(ctx6), "the wait ends once the menu is gone")
eq(#ctx6.writes, 1, "one write, not a cancel followed by the slot")
eq(Flags.getVar(nil, ctx6, VAR_0x8004), 1, "slot 2 reports as the 0-based 1")

local ctx6b = pickerCtx()
Natives.choosePartyMon(ctx6b, { log = function() end }, "choose_single")
PartyMenu.close()
check(pollOf(ctx6b), "closing with no pick also ends the wait")
eq(#ctx6b.writes, 1, "cancel writes once too")
eq(Flags.getVar(nil, ctx6b, VAR_0x8004), SLOT_CANCEL, "and it is SLOT_CANCEL")

print("[test] 7. waitbuttonpress arms on a later tick, as SetupNativeScript does")
local arms, release = 0, nil
local vm7 = run({
  { op = "waitbuttonpress" },
  { op = "end" },
}, {
  log = function() end,
  armWaitButton = function(cb)
    arms = arms + 1
    release = cb
  end,
})
eq(arms, 0, "the tick that dispatched the op arms nothing")
check(vm7:isRunning(), "and the script is waiting")
vm7:tick()
eq(arms, 1, "the next tick arms it")
vm7:tick()
eq(arms, 1, "later ticks do not re-arm")
release()
vm7:tick()
check(not vm7:isRunning(), "the press ends the wait")

Runtime.session = prevSession

if failed > 0 then
  print(string.format("FAILED %d check(s)", failed))
  os.exit(1)
end
print("PASS game3_stitchscript_seams")
os.exit(0)
