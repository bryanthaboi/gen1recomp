-- Script verbs that had no handler (E10 significant subset).
--
-- Implements the conditional std calls, the door-state verbs, the PC-item
-- verbs, comparestat, bufferitemnameplural, the four mon verbs and the (same
-- map) *at verbs.  The v* RAM-script family and the compare_* locals family
-- remain unimplemented and are recorded in the review's remaining-scope list.
--   luajit tests/engine/game3_script_verbs_subset_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Vm = require("src.core.game3.scripting.vm")
local Ops = require("src.core.game3.scripting.ops_a")
local Std = require("src.core.game3.scripting.stdscripts")
local Flags = require("src.core.game3.scripting.flags")
local Ctx = require("src.core.game3.scripting.ctx")
local Storage = require("src.core.game3.storage")
local Bag = require("src.core.game3.bag")
local Schema = require("src.core.game3.save_schema_firered")
local Runtime = require("src.core.game3.runtime")

local VAR_RESULT = (Ctx and Ctx.VAR_RESULT) or 0x800D

local session = Schema.newGame({ name = "RED" })
session.bag = Bag.new()
Storage.ensure(session)
session.storage.items = {}
Runtime.session = session
Runtime._game = { data = { maps = {} } }

local END = { { op = "end" } }
local function new_vm()
  local vm = Vm.new({
    store = Flags.newStore(),
    scripts = { t_main = END, ["std:1"] = END, ["std:2"] = END },
    text = Std.TEXT, stdscripts = Std.SCRIPTS,
  })
  vm.ctx.stack = vm.ctx.stack or {}
  return vm
end

-- 1. callstd_if with a true condition calls the std script.
local vm = new_vm()
vm.ctx.comparisonResult = 1 -- EQ
vm:setPc("t_main", 1)
Ops.dispatch(vm, { op = "callstd_if", [1] = 1, [2] = 1 })
eq(#vm.ctx.stack, 1, "callstd_if (condition true) pushes a return address")
eq(vm.ctx.pc.listKey, "std:1", "...and enters the std script")

-- 2. callstd_if with a false condition falls through.
vm = new_vm()
vm.ctx.comparisonResult = 0 -- LT
vm:setPc("t_main", 1)
Ops.dispatch(vm, { op = "callstd_if", [1] = 1, [2] = 1 })
eq(#vm.ctx.stack, 0, "callstd_if (condition false) does not push")
eq(vm.ctx.pc.listKey, "t_main", "...and stays on the current list")

-- 3. gotostd_if jumps without a return address, and only when the condition holds.
vm = new_vm()
vm.ctx.comparisonResult = 1
vm:setPc("t_main", 1)
Ops.dispatch(vm, { op = "gotostd_if", [1] = 1, [2] = 2 })
eq(vm.ctx.pc.listKey, "std:2", "gotostd_if (condition true) enters the std script")
eq(#vm.ctx.stack, 0, "...without pushing a return address")
vm = new_vm()
vm.ctx.comparisonResult = 0
vm:setPc("t_main", 1)
Ops.dispatch(vm, { op = "gotostd_if", [1] = 1, [2] = 2 })
eq(vm.ctx.pc.listKey, "t_main", "gotostd_if (condition false) falls through")

-- 4. The door-state verbs reach the host door seam.
local seen = {}
vm = new_vm()
-- tolerate (op,x,y) and (adapter,op,x,y)
vm.adapters.doorAnim = function(a1, a2, a3, a4)
  local op, x, y = a1, a2, a3
  if a3 == nil and type(a1) == "table" then op, x, y = a2, a3, a4 end
  seen[#seen + 1] = { op, x, y }
end
Ops.dispatch(vm, { op = "setdooropen", [1] = 3, [2] = 7 })
Ops.dispatch(vm, { op = "setdoorclosed", [1] = 4, [2] = 8 })
eq(#seen, 2, "both door-state verbs reach the door seam")
local first, second = seen[1] or {}, seen[2] or {}
eq(first[1], "opendoor", "setdooropen maps to the open animation")
eq(first[2], 3, "...carrying its x")
eq(second[1], "closedoor", "setdoorclosed maps to the close animation")

-- 5. checkpcitem reports whether the PC holds enough.
vm = new_vm()
session.storage.items = { { id = 13, qty = 5 } }
Ops.dispatch(vm, { op = "checkpcitem", [1] = 13, [2] = 3 })
eq(Flags.getVar(vm.store, vm.ctx, VAR_RESULT), 1, "checkpcitem reports enough stored")
Ops.dispatch(vm, { op = "checkpcitem", [1] = 13, [2] = 9 })
eq(Flags.getVar(vm.store, vm.ctx, VAR_RESULT), 0, "checkpcitem reports too few stored")

-- 6. addpcitem stores into the PC and reports success.
vm = new_vm()
session.storage.items = {}
Ops.dispatch(vm, { op = "addpcitem", [1] = 13, [2] = 4 })
eq(session.storage.items[1] and session.storage.items[1].qty, 4, "addpcitem stores the quantity")
eq(Flags.getVar(vm.store, vm.ctx, VAR_RESULT), 1, "addpcitem reports success")
Ops.dispatch(vm, { op = "addpcitem", [1] = 13, [2] = 2 })
eq((session.storage.items[1] or {}).qty, 6, "...and stacks onto an existing entry")

-- 7. addpcitem respects the PC stack cap instead of destroying overflow.
vm = new_vm()
session.storage.items = { { id = 13, qty = Storage.MAX_ITEM_QTY } }
Ops.dispatch(vm, { op = "addpcitem", [1] = 13, [2] = 5 })
eq((session.storage.items[1] or {}).qty, Storage.MAX_ITEM_QTY, "a full stack is not overfilled")
eq(Flags.getVar(vm.store, vm.ctx, VAR_RESULT), 0, "...and the verb reports failure")

-- 8. comparestat (src/scrcmd.c:582) reads {statId byte, value word} and sets
--    ctx.comparisonResult to LT/EQ/GT from the serialized game stat table.
local Opcodes = require("src.core.game3.scripting.opcodes")
local cs = Opcodes.get(0xcc)
eq(cs.size, 7, "comparestat is a 7-byte instruction (0xcc + B + W)")
eq(cs.args[1].kind, "byte", "...statId is a byte")
eq(cs.args[2].kind, "word", "...value is a word")
session.gameStats = { [5] = 10 }
vm = new_vm()
Ops.dispatch(vm, { op = "comparestat", [1] = 5, [2] = 11 })
eq(vm.ctx.comparisonResult, 0, "comparestat reports LT below the stat")
Ops.dispatch(vm, { op = "comparestat", [1] = 5, [2] = 10 })
eq(vm.ctx.comparisonResult, 1, "comparestat reports EQ at the stat")
Ops.dispatch(vm, { op = "comparestat", [1] = 5, [2] = 9 })
eq(vm.ctx.comparisonResult, 2, "comparestat reports GT above the stat")

-- 9. bufferitemnameplural (src/scrcmd.c:1637) pluralises like the ROM: "S" after
--    a Poké Ball stack, and the final letter replaced by "IES" for a berry
--    stack.  The names themselves come from the item pack, which does not exist
--    in a ROM-free checkout, so assert the rule against each item's own singular
--    name rather than a hard-coded one.
local ItemsData = require("src.core.game3.items_data")
local function plural(item, qty)
  local vm = new_vm()
  Ops.dispatch(vm, { op = "bufferitemnameplural", [1] = 0, [2] = item, [3] = qty })
  return vm.ctx.stringVars[1]
end
local ballName = ItemsData.displayName(4)
eq(plural(4, 2), ballName .. "S", "a Poké Ball stack pluralises with S")
eq(plural(4, 1), ballName, "...and stays singular at one")
local berryName = ItemsData.displayName(133)
eq(ItemsData.isBerry(133), true, "the berry item is classified as a berry")
eq(plural(133, 2), berryName:sub(1, -2) .. "IES",
  "a berry stack replaces the final letter with IES")
eq(plural(133, 1), berryName, "...and stays singular at one")

-- 10-12. The party-mon verbs (src/scrcmd.c:1767, :2239, :2248, :2256) use
--    0-based party indices and move slots.
vm = new_vm()
session.party = { { species = 1, moves = {}, pp = {}, maxPp = {} } }
Ops.dispatch(vm, { op = "setmonmove", [1] = 0, [2] = 0, [3] = 33 })
eq(session.party[1].moves[1], 33, "setmonmove writes the 0-based slot")
eq(type(session.party[1].pp[1]), "number", "...and resets its PP")
Ops.dispatch(vm, { op = "setmonmetlocation", [1] = 0, [2] = 88 })
eq(session.party[1].metLocation, 88, "setmonmetlocation writes metLocation")
Ops.dispatch(vm, { op = "setmonmodernfatefulencounter", [1] = 0 })
eq(session.party[1].modernFatefulEncounter, true, "setmonmodernfatefulencounter flags the mon")
Ops.dispatch(vm, { op = "checkmonmodernfatefulencounter", [1] = 0 })
eq(Flags.getVar(vm.store, vm.ctx, VAR_RESULT), 1, "checkmonmodernfatefulencounter reports it")
Ops.dispatch(vm, { op = "checkmonmodernfatefulencounter", [1] = 1 })
eq(Flags.getVar(vm.store, vm.ctx, VAR_RESULT), 0, "...and 0 for a party slot with no mon")

-- 13. The door-state verbs read x/y through VarGet (src/scrcmd.c:2156).
vm = new_vm()
seen = {}
vm.adapters.doorAnim = function(a1, a2, a3, a4)
  local op, x, y = a1, a2, a3
  if a3 == nil and type(a1) == "table" then op, x, y = a2, a3, a4 end
  seen[#seen + 1] = { op, x, y }
end
local V0x4001 = 0x4001
Flags.setVar(vm.store, vm.ctx, V0x4001, 6)
Ops.dispatch(vm, { op = "setdooropen", [1] = V0x4001, [2] = 9 })
eq((seen[1] or {})[2], 6, "setdooropen resolves variable coordinates")
eq((seen[1] or {})[3], 9, "...and passes literal ones through")

-- 14. The *at verbs (src/scrcmd.c:993-1080) address a specific map.  On the
--    current map they behave as the plain command; elsewhere they skip.
local Map = require("src.core.game3.map")
vm = new_vm()
Map.current = "FR_PALLET_TOWN"
local added = {}
vm.adapters.addObject = function(lid) added[#added + 1] = lid end
Ops.dispatch(vm, { op = "addobjectat", [1] = 2, [2] = 3, [3] = 0 })
eq(#added, 1, "addobjectat on the current map adds the object")
eq(added[1], 2, "...with the resolved local id")
Ops.dispatch(vm, { op = "addobjectat", [1] = 2, [2] = 3, [3] = 1 })
eq(#added, 1, "addobjectat on another map is skipped")
Ops.dispatch(vm, { op = "applymovementat", [1] = 2, [2] = { 0xFE }, [3] = 3, [4] = 1 })
eq(vm.ctx.activeMoves[2], nil, "applymovementat on another map is skipped")
Ops.dispatch(vm, { op = "applymovementat", [1] = 2, [2] = { 0xFE }, [3] = 3, [4] = 0 })
eq(vm.ctx.activeMoves[2] ~= nil, true, "applymovementat on the current map starts the movement")

-- 15. The pointer family layouts (asm/macros/event.inc) each carry a leading
--     byte plus a word; the table used to declare them a byte short, which
--     desynced every following instruction.
for _, byte in ipairs({ 0x11, 0x12, 0x13 }) do
  local d = Opcodes.get(byte)
  eq(d.size, 6, string.format("0x%02x is a 6-byte instruction", byte))
  eq(d.args[1].kind, "byte", string.format("0x%02x starts with a byte", byte))
  eq(d.args[2].kind, "word", string.format("0x%02x ends with a word", byte))
end

-- 16. Script locals and the synthetic pointer store (src/scrcmd.c:293-375).
vm = new_vm()
Ops.dispatch(vm, { op = "loadbyte", 0, 10 })
Ops.dispatch(vm, { op = "loadbyte", 1, 20 })
Ops.dispatch(vm, { op = "copylocal", [1] = 0, [2] = 1 })
eq(vm.ctx.data[0], 20, "copylocal copies a local")
Ops.dispatch(vm, { op = "loadbyte", 0, 5 })
Ops.dispatch(vm, { op = "loadbyte", 1, 9 })
Ops.dispatch(vm, { op = "compare_local_to_local", [1] = 0, [2] = 1 })
eq(vm.ctx.comparisonResult, 0, "compare_local_to_local reports LT")
Ops.dispatch(vm, { op = "loadbyte", 0, 7 })
Ops.dispatch(vm, { op = "compare_local_to_value", [1] = 0, [2] = 7 })
eq(vm.ctx.comparisonResult, 1, "compare_local_to_value reports EQ")
Ops.dispatch(vm, { op = "setptr", [1] = 42, [2] = 0x1234 })
eq(vm.ctx.scriptMem[0x1234], 42, "setptr writes the synthetic byte store")
Ops.dispatch(vm, { op = "loadbytefromptr", [1] = 1, [2] = 0x1234 })
eq(vm.ctx.data[1], 42, "loadbytefromptr reads it back into a local")
Ops.dispatch(vm, { op = "loadbyte", 2, 9 })
Ops.dispatch(vm, { op = "setptrbyte", [1] = 2, [2] = 0x1235 })
eq(vm.ctx.scriptMem[0x1235], 9, "setptrbyte stores a local")
Ops.dispatch(vm, { op = "copybyte", [1] = 0x1236, [2] = 0x1235 })
eq(vm.ctx.scriptMem[0x1236], 9, "copybyte copies between pointers")
Ops.dispatch(vm, { op = "compare_local_to_ptr", [1] = 2, [2] = 0x1234 })
eq(vm.ctx.comparisonResult, 0, "compare_local_to_ptr compares local vs store")
Ops.dispatch(vm, { op = "compare_ptr_to_ptr", [1] = 0x1234, [2] = 0x1236 })
eq(vm.ctx.comparisonResult, 2, "compare_ptr_to_ptr compares two stored bytes")

Ops.dispatch(vm, { op = "loadword", 0, 0x12AB })
Ops.dispatch(vm, { op = "copylocal", 3, 0 })
eq(vm.ctx.data[3], 0x12AB, "copylocal preserves the full loadword register")
Ops.dispatch(vm, { op = "compare_local_to_value", 3, 0xAB })
eq(vm.ctx.comparisonResult, 1, "local comparisons read the low byte")
Ops.dispatch(vm, { op = "setptrbyte", 3, 0x1237 })
Ops.dispatch(vm, { op = "loadbytefromptr", 0, 0x1237 })
eq(vm.ctx.data[0], 0xAB, "pointer writes truncate a word register to a byte")
Ops.dispatch(vm, { op = "loadword", 0, "std:1" })
Ops.dispatch(vm, { op = "copylocal", 1, 0 })
eq(vm.ctx.data[1], "std:1", "copylocal preserves the host's symbolic text pointers")

-- 17. The RAM-script (v*) control flow (src/scrcmd.c:171-209, :1580).
vm = new_vm()
vm:setPc("t_main", 4)
Ops.dispatch(vm, { op = "setvaddress", [1] = 0x800000 })
eq(vm.ctx.vaddress, 0x800000, "setvaddress is recorded")
Ops.dispatch(vm, { op = "vgoto", [1] = "std:1" })
eq(vm.ctx.pc.listKey, "std:1", "vgoto jumps to the script")
vm:setPc("t_main", 4)
Ops.dispatch(vm, { op = "vgoto_if", [1] = 2, [2] = "std:1" })
eq(vm.ctx.pc.listKey, "t_main", "vgoto_if with a false condition falls through")
vm.ctx.comparisonResult = 2
Ops.dispatch(vm, { op = "vgoto_if", [1] = 2, [2] = "std:1" })
eq(vm.ctx.pc.listKey, "std:1", "...and jumps when it holds")
vm = new_vm()
vm:setPc("t_main", 4)
Ops.dispatch(vm, { op = "vcall", [1] = "std:1" })
eq(vm.ctx.pc.listKey, "std:1", "vcall enters the script")
eq(#vm.ctx.stack, 1, "...pushing a return address")
Ops.dispatch(vm, { op = "returnram" })
eq(vm.ctx.pc.listKey, "t_main", "returnram resumes the caller")
eq(vm.ctx.pc.index, 4, "...at the return site")
vm = new_vm()
Ops.dispatch(vm, { op = "vmessage", [1] = "std:1" })
eq(vm.ctx.messageOpen, true, "vmessage opens the message box")
vm = new_vm()
Ops.dispatch(vm, { op = "vbuffermessage", [1] = "std:1" })
eq(type(vm.ctx.stringVars[4]), "string", "vbuffermessage fills the gStringVar4 buffer")
vm = new_vm()
Ops.dispatch(vm, { op = "vbufferstring", [1] = 1, [2] = "std:1" })
eq(type(vm.ctx.stringVars[2]), "string", "vbufferstring fills the requested string var")
vm = new_vm()
Ops.dispatch(vm, { op = "endram" })
eq(vm.ctx.status, "shutdown", "endram stops the script")

T.finish("game3_script_verbs_subset_test")
