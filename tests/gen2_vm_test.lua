-- Gen 2 script VM + movement decode smoke (no LOVE window).
--   luajit tests/gen2_vm_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 vm")
local check, eq = S.check, S.eq

love = require("tests.love_stub")

local Movement = require("src.script.gen2.Movement")
local Vm = require("src.script.gen2.Vm")
local Events = require("src.world.gen2.Events")

-- Movement byte decode
eq(Movement.dir(0), "down", "facing 0 = down")
eq(Movement.dir(1), "up", "facing 1 = up")
local stepUp = Movement.decodeByte(0x0d) -- step | UP
eq(stepUp.kind, "step", "0x0d is step")
eq(stepUp.dir, "up", "0x0d steps up")
eq(Movement.decodeByte(0x03).kind, "turn", "0x03 turn_head RIGHT")
eq(Movement.decodeByte(0x47).kind, "end", "0x47 step_end")

-- Minimal givepoke / yesorno / setscene path
local events = Events.new()
local texts = { ["t:yes"] = "Take it?", ["t:got"] = "Got {STRBUF}!" }
local scripts = {
  generation = 2,
  movements = {
    ["m:up"] = { 0x0d, 0x47 },
  },
  ["s:ball"] = {
    { op = "writetext", text = "t:yes" },
    { op = "yesorno" },
    { op = "iffalse", script = "s:no" },
    { op = "getmonname", species = 152 },
    { op = "writetext", text = "t:got" },
    { op = "givepoke", species = 152, level = 5, item = 173, trainer = 0 },
    { op = "setscene", scene = 1 },
    { op = "applymovement", object = 0, movement = "m:up" },
    { op = "end" },
  },
  ["s:no"] = {
    { op = "end" },
  },
}

local log = {}
local scene = 0
local moved = false
local party = {}
local vm = Vm.new(scripts, texts, events, {
  showText = function(body, onDone)
    log[#log + 1] = { "text", body }
    onDone()
  end,
  yesorno = function(onChoose)
    log[#log + 1] = { "yesorno" }
    onChoose(true)
  end,
  getMonName = function(species)
    return species == 152 and "CHIKORITA" or "?"
  end,
  givePoke = function(species, level)
    log[#log + 1] = { "givepoke", species, level }
    party[#party + 1] = { species = species, level = level }
  end,
  setScene = function(s) scene = s end,
  getScene = function() return scene end,
  applyMovement = function(object, bytes, onDone)
    log[#log + 1] = { "move", object, #bytes }
    moved = true
    onDone()
  end,
})

check(vm:start("s:ball"), "starter script starts")
-- Drain any wait/move resumes (yesorno/text resume synchronously here).
for _ = 1, 10 do vm:update() end
check(not vm:running(), "script finished")
eq(scene, 1, "setscene → 1")
check(moved, "applymovement ran")
eq(#party, 1, "givepoke added to party")
eq(party[1].species, 152, "species is Chikorita index")
local gotText
for _, row in ipairs(log) do
  if row[1] == "text" and row[2]:find("CHIKORITA", 1, true) then
    gotText = true
  end
end
check(gotText, "getmonname filled STRBUF in received text")

-- givepoke's trainer arm (#1569): Script_givepoke (engine/overworld/
-- scripting.asm:1817-1824), GivePoke (engine/pokemon/move_mon.asm:1695-1736)
do
  local given, asked = nil, false
  local kenyaVm = Vm.new({ generation = 2,
    ["s:randy"] = {
      { op = "givepoke", species = 21, level = 10, item = 0, trainer = 1,
        name = "KENYA", otName = "RANDY" },
      { op = "end" },
    },
  }, {}, Events.new(), {
    givePoke = function(species, level, item, opts)
      given = { species = species, level = level, opts = opts }
      return { species = "SPEAROW" }
    end,
    askNickname = function() asked = true end,
  })
  check(kenyaVm:start("s:randy"), "Randy's script starts")
  for _ = 1, 10 do kenyaVm:update() end
  check(given ~= nil, "the gift reaches givePoke")
  check(given.opts ~= nil, "the trainer arm carries the two names")
  eq(given.opts.nickname, "KENYA", "the nickname is the script's own")
  eq(given.opts.otName, "RANDY", "and so is the OT name")
  check(not asked, "no nickname prompt on the trainer arm")
end

-- Every other givepoke in the game is the flag-FALSE form: no names, and the
-- nickname prompt still runs (engine/pokemon/move_mon.asm:1753-1757).
do
  local given, asked = nil, false
  local plainVm = Vm.new({ generation = 2,
    ["s:eevee"] = {
      { op = "givepoke", species = 133, level = 20, item = 0, trainer = 0 },
      { op = "end" },
    },
  }, {}, Events.new(), {
    givePoke = function(species, level, item, opts)
      given = { opts = opts }
      return { species = "EEVEE" }
    end,
    showText = function(_, onDone) onDone() end,
    -- GiveANickname_YesNo (move_mon.asm:1753-1757): the prompt's yes/no
    yesorno = function(onChoose)
      asked = true
      onChoose(false)
    end,
  })
  plainVm:start("s:eevee")
  for _ = 1, 10 do plainVm:update() end
  check(given ~= nil and given.opts == nil,
    "the flag-FALSE form hands givePoke no names")
  check(asked, "and the nickname prompt still runs on it")
end

-- Phone + verbosegiveitem (Elm directions / aide potion)
local phone = {}
local bag = {}
local itemLog = {}
local phoneVm = Vm.new({
  generation = 2,
  ["s:elm"] = {
    { op = "addcellnum", phone = 4 },
    { op = "checkcellnum", phone = 4 },
    { op = "iffalse", script = "s:fail" },
    { op = "verbosegiveitem", item = 18, quantity = 1 },
    { op = "setscene", scene = 2 },
    { op = "end" },
  },
  ["s:fail"] = { { op = "end" } },
}, {}, Events.new(), {
  showText = function(body, onDone)
    itemLog[#itemLog + 1] = body
    onDone()
  end,
  addCell = function(id) phone[id] = true end,
  hasCell = function(id) return phone[id] == true end,
  getItemName = function(index)
    return index == 18 and "POTION" or "?"
  end,
  giveItem = function(index, qty)
    bag[index] = (bag[index] or 0) + (qty or 1)
    return true
  end,
  specialSound = function()
    itemLog[#itemLog + 1] = "sfx"
  end,
  setScene = function(s) scene = s end,
})
check(phoneVm:start("s:elm"), "phone/item script starts")
for _ = 1, 20 do phoneVm:update() end
check(not phoneVm:running(), "phone/item script finished")
check(phone[4] == true, "addcellnum stored PHONE_ELM")
eq(bag[18], 1, "verbosegiveitem added POTION")
eq(scene, 2, "aide potion setscene → NOOP (2)")
local received, pocket
for _, body in ipairs(itemLog) do
  if type(body) == "string" and body:find("received", 1, true)
      and body:find("POTION", 1, true) then
    received = true
  end
  if type(body) == "string" and body:find("ITEM POCKET", 1, true) then
    pocket = true
  end
end
check(received, "verbosegiveitem shows received text")
check(pocket, "verbosegiveitem shows pocket notify")

-- pokemart.  Script_pokemart farcalls OpenMartDialog, which does not return
-- until the shop is closed, so the VM has to PARK on it the way it parks on a
-- battle; and its mart id is a WORD, not a byte.
local Opcodes = require("src.script.gen2.Opcodes")
eq(Opcodes[0x93].name, "pokemart", "$93 is pokemart")
eq(Opcodes[0x93].size, 3, "and carries dialog + a word mart id")

local martCalls, martLog = {}, {}
local martResume
local martVm = Vm.new({
  generation = 2,
  ["s:clerk"] = {
    { op = "opentext" },
    -- pokemart MARTTYPE_PHARMACY, MART_CIANWOOD -- the extractor leaves the
    -- three operand bytes in `args` as dialog, lo, hi.
    { op = "pokemart", args = { 3, 4, 0 } },
    { op = "writetext", text = "t:bye" },
    { op = "end" },
  },
}, { ["t:bye"] = "All right." }, Events.new(), {
  showText = function(body, onDone)
    martLog[#martLog + 1] = body
    onDone()
  end,
  openMart = function(martType, martId, onDone)
    martCalls[#martCalls + 1] = { martType, martId }
    martResume = onDone
  end,
})
check(martVm:start("s:clerk"), "clerk script starts")
eq(#martCalls, 1, "pokemart opened one mart")
eq(martCalls[1][1], 3, "dialog byte is MARTTYPE_PHARMACY")
eq(martCalls[1][2], 4, "mart id is MART_CIANWOOD")
eq(#martLog, 0, "nothing past the shop runs while it is open")
check(martVm:running(), "the script is parked on the shop")
martResume()
eq(#martLog, 1, "closing the shop resumes the script")
check(not martVm:running(), "and the clerk script finishes")

-- The high operand byte is a real byte: a mart id of $0121 must not read as
-- $21.  No mart is that far up the table, but a mis-shifted word would walk
-- the shelf and never say so.
local wordCalls = {}
local wordVm = Vm.new({
  generation = 2,
  ["s:word"] = {
    { op = "pokemart", args = { 0, 0x21, 0x01 } },
    { op = "end" },
  },
}, {}, Events.new(), {
  openMart = function(martType, martId, onDone)
    wordCalls[#wordCalls + 1] = { martType, martId }
    onDone()
  end,
})
check(wordVm:start("s:word"), "word-id script starts")
eq(wordCalls[1][2], 0x121, "mart id reads lo + hi * 256")
eq(wordCalls[1][1], 0, "and MARTTYPE_STANDARD is dialog 0")

-- A VM with no mart hook (the trainer-script harness, a headless driver) walks
-- straight past the shop rather than hanging on a resume nobody will call.
local skipLog = {}
local skipVm = Vm.new({
  generation = 2,
  ["s:skip"] = {
    { op = "pokemart", args = { 0, 1, 0 } },
    { op = "writetext", text = "t:bye" },
    { op = "end" },
  },
}, { ["t:bye"] = "Please come again!" }, Events.new(), {
  showText = function(body, onDone)
    skipLog[#skipLog + 1] = body
    onDone()
  end,
})
check(skipVm:start("s:skip"), "hookless mart script starts")
eq(#skipLog, 1, "the script runs on without a mart hook")
check(not skipVm:running(), "and finishes")

-- ---------------------------------------------------------------------------
-- Script command coverage (engine/overworld/scripting.asm).
--
-- Every block below drives a REAL Vm over a hand-built command list with stub
-- hooks and asserts the two things a wrong transcription gets wrong: the
-- wScriptVar the command leaves, and the hook it called with which arguments.
-- The arg SHAPES are the ones RomExtractorGen2 produces, so `args` here matches
-- what data/generated/scripts.lua actually carries.
-- ---------------------------------------------------------------------------

-- Text / yesorno / menu / battle hooks all resume synchronously, so a whole
-- script runs inside `drive` and the assertions stay flat.  The frame drain
-- covers `pause` / `earthquake` / `showemote` waits and the waitsfx park.
local function drive(scriptTable, hooks, texts, key)
  scriptTable.generation = 2
  local log = {}
  local base = {
    showText = function(body, onDone)
      log[#log + 1] = "text:" .. tostring(body)
      onDone()
    end,
    yesorno = function(onChoose)
      log[#log + 1] = "yesorno"
      onChoose(true)
    end,
    waitSfx = function() return true end,
  }
  for k, v in pairs(hooks or {}) do base[k] = v end
  local vm = Vm.new(scriptTable, texts or {}, Events.new(), base)
  vm:start(key or "s:t")
  for _ = 1, 4000 do
    if not vm:running() then break end
    vm:update()
  end
  return vm, log
end

-- setval / addval.  Script_addval is `add [hl]` into wScriptVar, so the result
-- wraps at 8 bits: `addval -1` (args = {255}) is how a script counts DOWN.
do
  local vm = drive({ ["s:t"] = {
    { op = "setval", value = 1 },
    { op = "addval", args = { 255 } },
  } })
  eq(vm.scriptVar, 0, "addval 255 wraps 1 back to 0, not 256")
  local down = drive({ ["s:t"] = {
    { op = "setval", value = 0 },
    { op = "addval", args = { 2 } },
    { op = "addval", args = { 255 } },
  } })
  eq(down.scriptVar, 1, "addval counts up then back down")
end

-- ifgreater / ifless.  The operand order is REVERSED between the two in the
-- asm, so this is the one polarity worth a table: ifgreater jumps when
-- wScriptVar > value, ifless when wScriptVar < value.
do
  local cases = {
    { var = 2, op = "ifgreater", value = 1, jump = true },
    { var = 2, op = "ifless", value = 1, jump = false },
    { var = 0, op = "ifless", value = 1, jump = true },
    { var = 0, op = "ifgreater", value = 1, jump = false },
    { var = 1, op = "ifgreater", value = 1, jump = false },
    { var = 1, op = "ifless", value = 1, jump = false },
  }
  for _, c in ipairs(cases) do
    -- The jump arm is detectable by what it leaves behind: only the target
    -- writes hLastTalked.
    local vm = drive({
      ["s:t"] = {
        { op = "setval", value = c.var },
        { op = c.op, value = c.value, script = "s:jump" },
      },
      ["s:jump"] = { { op = "setlasttalked", args = { 99 } } },
    })
    eq(vm.lastTalked == 99, c.jump, ("%s value=%d with scriptVar=%d"):format(
      c.op, c.value, c.var))
  end
end

-- checktime.  CheckTime.TimeOfDayTable has no DARKNESS_F row, so IsInArray
-- fails in a pitch-black cave and every mask reads FALSE, ANYTIME included.
do
  local function timeAnswer(timeOfDay, mask)
    local vm = drive({ ["s:t"] = { { op = "checktime", args = { mask } } } },
      { getTimeOfDay = function() return timeOfDay end })
    return vm.scriptVar
  end
  eq(timeAnswer(1, 2), 1, "checktime DAY is true at DAY_F")
  eq(timeAnswer(1, 4), 0, "checktime NITE is false at DAY_F")
  eq(timeAnswer(2, 4), 1, "checktime NITE is true at NITE_F")
  eq(timeAnswer(0, 7), 1, "checktime ANYTIME is true at MORN_F")
  eq(timeAnswer(3, 7), 0,
    "checktime ANYTIME is FALSE in darkness (no DARKNESS_F row)")
end

-- checkmapscene: a map with no scene_var row answers $ff, not 0, so an
-- `ifequal 0` after it must not match it.
do
  local seen = {}
  local vm = drive({ ["s:t"] = { { op = "checkmapscene", args = { 2, 3 } } } }, {
    getMapScene = function(g, m) seen = { g, m }; return nil end,
  })
  eq(vm.scriptVar, 0xff, "checkmapscene answers $ff for a sceneless map")
  eq(seen[1], 2, "checkmapscene passes the group byte first")
  eq(seen[2], 3, "checkmapscene passes the map byte second")
  local hit = drive({ ["s:t"] = { { op = "checkmapscene", args = { 2, 3 } } } }, {
    getMapScene = function() return 0 end,
  })
  eq(hit.scriptVar, 0, "a map WITH a scene of 0 answers 0")
end

-- readmem / addval / writemem, the Goldenrod underground switch triple.  With
-- no hook at all the VM's own sparse store has to stay self-consistent.
do
  local vm = drive({ ["s:t"] = {
    { op = "readmem", args = { 0xa8, 0xd6 } },
    { op = "addval", args = { 1 } },
    { op = "writemem", args = { 0xa8, 0xd6 } },
    { op = "readmem", args = { 0xa8, 0xd6 } },
    { op = "addval", args = { 1 } },
    { op = "writemem", args = { 0xa8, 0xd6 } },
    { op = "readmem", args = { 0xa8, 0xd6 } },
  } })
  eq(vm.scriptVar, 2, "readmem/addval/writemem round-trips through the VM store")
  eq(vm.mem[0xd6a8], 2, "and the byte lands at lo + hi * 256")
  -- loadmem writes a LITERAL third byte instead of wScriptVar.
  local lm = drive({ ["s:t"] = {
    { op = "setval", value = 99 },
    { op = "loadmem", args = { 0x00, 0xc0, 7 } },
    { op = "readmem", args = { 0x00, 0xc0 } },
  } })
  eq(lm.scriptVar, 7, "loadmem stores its own operand, not wScriptVar")
  -- The hook claims an address; anything it does not claim stays local.
  local claimed = {}
  local hooked = drive({ ["s:t"] = {
    { op = "setval", value = 5 },
    { op = "writemem", args = { 0x11, 0xd1 } },
  } }, {
    writeMem = function(addr, value) claimed[addr] = value; return true end,
  })
  eq(claimed[0xd111], 5, "writeMem hook takes the byte")
  eq(hooked.mem[0xd111], nil, "and a claimed address does not shadow into mem")

  -- The store rides the save (save.scriptMem, src/core/gen2/Save.lua), so it
  -- has to survive a serialize / restore pair the way the event bitfield does.
  vm.mem[0xd7f1] = 0
  local dumped = vm:serializeMem()
  eq(dumped[0xd6a8], 2, "serializeMem hands the switch byte to the save")
  eq(dumped[0xd7f1], nil, "and drops zeroes, which already read back as 0")
  -- A fresh VM handed that table back reads the same byte, which is the whole
  -- point: the switch room picks up where the last save left it.
  local readSwitch = { generation = 2, ["s:t"] = {
    { op = "readmem", args = { 0xa8, 0xd6 } },
  } }
  local reloaded = Vm.new(readSwitch, {}, Events.new(), {})
  reloaded:restoreMem(dumped)
  reloaded:start("s:t")
  eq(reloaded.scriptVar, 2, "a restored store answers the next readmem")
  -- A serialized file can hand the keys back as strings; indexing by number
  -- afterwards would silently read 0 without the tonumber in restoreMem.
  local strings = Vm.new(readSwitch, {}, Events.new(), {})
  strings:restoreMem({ ["54952"] = "4" })
  strings:start("s:t")
  eq(strings.scriptVar, 4, "restoreMem coerces string keys and values")
end

-- setflag / clearflag / checkflag.  ENGINE_* is a different namespace from
-- setevent's wEventFlags, and it must NOT fire onFlagsChanged: engine flags
-- never gate object visibility, so a badge cannot pop an NPC in mid-script.
do
  local rebuilds = 0
  local vm = drive({ ["s:t"] = {
    { op = "setflag", flag = 32 },
    { op = "checkflag", flag = 32 },
  } }, { onFlagsChanged = function() rebuilds = rebuilds + 1 end })
  eq(vm.scriptVar, 1, "checkflag reads back the flag setflag wrote")
  eq(rebuilds, 0, "engine flags do not trigger an object rebuild")
  local cleared = drive({ ["s:t"] = {
    { op = "setflag", flag = 16 },
    { op = "clearflag", flag = 16 },
    { op = "checkflag", flag = 16 },
  } })
  eq(cleared.scriptVar, 0, "clearflag ENGINE_BUG_CONTEST_TIMER clears it")
  -- checkevent must not see an engine flag and vice versa.
  local split = drive({ ["s:t"] = {
    { op = "setflag", flag = 26 },
    { op = "checkevent", event = 26 },
  } })
  eq(split.scriptVar, 0, "setflag does not write the wEventFlags namespace")
  -- With a hook, the store lives in the World / save instead.
  local store, reads = {}, 0
  local hooked = drive({ ["s:t"] = {
    { op = "setflag", flag = 41 },
    { op = "checkflag", flag = 41 },
  } }, {
    setEngineFlag = function(f, v) store[f] = v end,
    getEngineFlag = function(f) reads = reads + 1; return store[f] end,
  })
  eq(hooked.scriptVar, 1, "the engine-flag hooks round-trip")
  eq(reads, 1, "checkflag prefers the hook over the local table")
end

-- checkver defaults to Gold, so the `iftrue` fork after it is the SILVER arm.
do
  local gold = drive({ ["s:t"] = { { op = "checkver" } } })
  eq(gold.scriptVar, 0, "checkver with no hook plays the Gold branch")
  local silver = drive({ ["s:t"] = { { op = "checkver" } } },
    { gsVersion = function() return 1 end })
  eq(silver.scriptVar, 1, "checkver reports Silver when the hook says so")
end

-- delcmdqueue answers TRUE when there was nothing to delete: DelCmdQueue's
-- `ret c` path leaves wScriptVar at 0, and this port's queue is always empty.
do
  local vm = drive({ ["s:t"] = { { op = "delcmdqueue", args = { 0 } } } })
  eq(vm.scriptVar, 1, "delcmdqueue on an empty queue answers TRUE")
end

-- farscall returns, farsjump does not.
do
  local call = drive({
    ["s:t"] = {
      { op = "farscall", script = "s:far" },
      { op = "setlasttalked", args = { 7 } },
    },
    ["s:far"] = { { op = "setval", value = 3 } },
  })
  eq(call.scriptVar, 3, "farscall ran the target")
  eq(call.lastTalked, 7, "and came back to the command after it")
  local jump = drive({
    ["s:t"] = {
      { op = "farsjump", script = "s:far" },
      { op = "setlasttalked", args = { 7 } },
    },
    ["s:far"] = { { op = "setval", value = 3 } },
  })
  eq(jump.scriptVar, 3, "farsjump ran the target")
  eq(jump.lastTalked, nil, "and never came back")
end

-- memjump is a jump into WRAM: no target to run, but the list still ends.
do
  local vm = drive({ ["s:t"] = {
    { op = "memjump", args = { 2, 3 } },
    { op = "setlasttalked", args = { 5 } },
  } })
  eq(vm.lastTalked, nil, "memjump ends the list rather than falling through")
end

-- random.  `random 0` returns with wScriptVar still holding the 0 it stored.
do
  local zero = drive({ ["s:t"] = { { op = "random", args = { 0 } } } })
  eq(zero.scriptVar, 0, "random 0 is 0, not an error")
  local lo, hi = 99, -1
  for _ = 1, 200 do
    local vm = drive({ ["s:t"] = { { op = "random", args = { 6 } } } })
    if vm.scriptVar < lo then lo = vm.scriptVar end
    if vm.scriptVar > hi then hi = vm.scriptVar end
  end
  check(lo >= 0 and hi <= 5, "random 6 stays inside 0..5")
end

-- getnum prints wScriptVar into the string buffer (PRINTNUM_LEFTALIGN, so no
-- padding survives).
do
  local vm = drive({ ["s:t"] = {
    { op = "setval", value = 17 },
    { op = "addval", args = { 1 } },
    { op = "getnum", args = { 0 } },
  } })
  eq(vm.stringBuffer, "18", "getnum writes wScriptVar into the string buffer")
end

-- writevar / loadvar.  loadvar is what arms VAR_BATTLETYPE for Lugia, the Red
-- Gyarados and the Cherrygrove rival, and it does NOT get a cmd.var from the
-- extractor: the named branch matches readvar / writevar only.
do
  local wrote = {}
  drive({ ["s:t"] = { { op = "loadvar", args = { 3, 10 } } } },
    { writeVar = function(id, value) wrote[#wrote + 1] = { id, value } end })
  eq(wrote[1][1], 3, "loadvar takes VAR_BATTLETYPE from args[1]")
  eq(wrote[1][2], 10, "and BATTLETYPE_FORCEITEM from args[2]")
  local w2 = {}
  drive({ ["s:t"] = {
    { op = "setval", value = 9 },
    { op = "writevar", var = 3 },
  } }, { writeVar = function(id, value) w2 = { id, value } end })
  eq(w2[2], 9, "writevar takes its value from wScriptVar")
end

-- callasm cannot be run, and must NOT invent a wScriptVar: FindItemInBallScript
-- and FruitTreeScript both branch on whatever the routine left there.
do
  local vm = drive({ ["s:t"] = {
    { op = "setval", value = 4 },
    { op = "callasm", args = { 0x3e, 0x00, 0x40 } },
  } })
  eq(vm.scriptVar, 4, "callasm leaves wScriptVar alone with no hook")
  local seen
  local hooked = drive({ ["s:t"] = {
    { op = "setval", value = 4 },
    { op = "callasm", args = { 0x3e, 0x34, 0x12 } },
  } }, { callAsm = function(label, bank, addr)
    seen = { label, bank, addr }
    return 1
  end })
  eq(hooked.scriptVar, 1, "a hook that answers writes wScriptVar")
  eq(seen[2], 0x3e, "callasm passes the bank byte")
  eq(seen[3], 0x1234, "and the address as lo + hi * 256")
end

-- Map objects: appear, disappear LAST_TALKED, moveobject, variablesprite.
do
  local appeared, hidden, moved, sprites = {}, {}, {}, {}
  local vm = drive({ ["s:t"] = {
    { op = "setlasttalked", args = { 6 } },
    { op = "appear", args = { 3 } },
    { op = "disappear", args = { 0xfe }, object = 0xfe },
    { op = "moveobject", args = { 2, 18, 11 } },
    { op = "variablesprite", args = { 4, 40 } },
  } }, {
    appear = function(o) appeared[#appeared + 1] = o end,
    disappear = function(o) hidden[#hidden + 1] = o end,
    moveObject = function(o, x, y) moved = { o, x, y } end,
    variableSprite = function(s, i) sprites[#sprites + 1] = { s, i } end,
  })
  eq(appeared[1], 3, "appear takes its object id from args[1]")
  eq(hidden[1], 6, "disappear LAST_TALKED ($fe) resolves to hLastTalked")
  eq(moved[1], 2, "moveobject object id")
  eq(moved[2], 18, "moveobject x is a plain map cell")
  eq(moved[3], 11, "moveobject y is a plain map cell")
  eq(sprites[1][1], 4, "variablesprite slot is already SPRITE_VARS-relative")
  eq(sprites[1][2], 40, "variablesprite sprite index")
  eq(vm.variableSprites[4], 40, "and the VM keeps its own wVariableSprites")
end

-- loademote EMOTE_FROM_MEM ($ff) means "the emote already in wScriptVar".
do
  local vm = drive({ ["s:t"] = {
    { op = "setval", value = 2 },
    { op = "loademote", args = { 0xff } },
  } })
  eq(vm.loadedEmote, 2, "loademote EMOTE_FROM_MEM reads wScriptVar")
  local lit = drive({ ["s:t"] = { { op = "loademote", args = { 5 } } } })
  eq(lit.loadedEmote, 5, "and a literal id is taken as-is")
end

-- changeblock: the script's x/y are CELLS and the block written is (x/2, y/2).
-- BrunosRoom's `changeblock 4, 2, $16 ; open door` is block (2, 1), which is
-- the block its KARENS_ROOM warp_events on cells (4,2) and (5,2) sit in.
do
  local blocks = {}
  drive({ ["s:t"] = {
    { op = "changeblock", args = { 4, 2, 0x16 } },
    { op = "changeblock", args = { 6, 2, 0x1e } },
  } }, { changeBlock = function(x, y, b) blocks[#blocks + 1] = { x, y, b } end })
  eq(blocks[1][1], 2, "changeblock halves x into a block column")
  eq(blocks[1][2], 1, "changeblock halves y into a block row")
  eq(blocks[1][3], 0x16, "and passes the block id through")
  eq(blocks[2][1], 3, "MahoganyMart1F's stairs land on block (3, 1)")
end

-- changemapblocks: a `dba`, which is `dbw bank, address`, and GetScriptByte
-- reads it in that order -- bank, then the pointer low byte, then the high one.
-- The pointer stays raw here; World:changeMapBlocks is what places it against
-- the blockdata address every map carries.  wScriptVar is not part of the
-- command, so a script branching on it after one must still see its own value.
do
  local seen
  local vm = drive({ ["s:t"] = {
    { op = "setval", value = 9 },
    { op = "changemapblocks", args = { 0x60, 0x34, 0x62 } },
  } }, { changeMapBlocks = function(bank, address) seen = { bank, address } end })
  eq(seen[1], 0x60, "the first byte is the blockdata bank")
  eq(seen[2], 0x6234, "and the next two are a little-endian pointer")
  eq(vm.scriptVar, 9, "changemapblocks leaves wScriptVar alone")
  local none = drive({ ["s:t"] = {
    { op = "changemapblocks", args = { 0x60, 0x34, 0x62 } },
  } })
  local empty = true
  for _ in pairs(none.unknownOps) do empty = false end
  check(empty, "and an unhooked world does not reach the unknown-op path")
end

-- earthquake: ONE byte carries two numbers.  `earthquake 80` is a displacement
-- of 80 held for byte & $3f = 16 frames, and the hold is the script's wait.
do
  local quake
  local vm = Vm.new({ generation = 2, ["s:t"] = {
    { op = "earthquake", args = { 80 } },
    { op = "setlasttalked", args = { 4 } },
  } }, {}, Events.new(), {
    earthquake = function(displacement, frames) quake = { displacement, frames } end,
  })
  vm:start("s:t")
  eq(quake[1], 80, "earthquake displacement is the whole byte")
  eq(quake[2], 16, "earthquake sleeps byte & $3f frames")
  check(vm:running(), "and the script is parked on that wait")
  eq(vm.lastTalked, nil, "nothing after it runs while the ground shakes")
  for _ = 1, 20 do vm:update() end
  eq(vm.lastTalked, 4, "the script resumes when the shake ends")
end

-- warp / warpfacing.  Plain map cells, and NOT a terminator: std_scripts.asm's
-- BugContestResultsWarpScript walks the player in with an applymovement right
-- after its `warp`.
do
  local warps = {}
  local vm = drive({ ["s:t"] = {
    { op = "warp", args = { 15, 3, 25, 1 } },
    { op = "setlasttalked", args = { 8 } },
  } }, { warpTo = function(g, m, x, y, f) warps[#warps + 1] = { g, m, x, y, f } end })
  eq(warps[1][1], 15, "warp group")
  eq(warps[1][2], 3, "warp map")
  eq(warps[1][3], 25, "warp x cell")
  eq(warps[1][4], 1, "warp y cell")
  eq(warps[1][5], nil, "plain warp carries no facing")
  eq(vm.lastTalked, 8, "warp does not end the script")
  local faced = {}
  drive({ ["s:t"] = { { op = "warpfacing", args = { 2, 15, 3, 25, 1 } } } },
    { warpTo = function(g, m, x, y, f) faced = { g, m, x, y, f } end })
  eq(faced[1], 15, "warpfacing pushes the map_id past the facing byte")
  eq(faced[5], "left", "warpfacing masks its byte to a direction")
  -- Group 0 is the routine's own error arm: a re-entry, not a trip.
  local reloads = 0
  drive({ ["s:t"] = { { op = "warp", args = { 0, 0, 0, 0 } } } }, {
    warpTo = function() error("group 0 must not warp") end,
    reloadMap = function() reloads = reloads + 1 end,
  })
  eq(reloads, 1, "warp group 0 is MAPSETUP_BADWARP, a re-entry")
end

-- The warp side commands that only record state.
do
  local mods, blackout, method, checks, sounds = {}, {}, nil, 0, 0
  drive({ ["s:t"] = {
    { op = "warpmod", args = { 1, 15, 3 } },
    { op = "blackoutmod", args = { 26, 3 } },
    { op = "newloadmap", args = { 249 } },
    { op = "warpcheck" },
    { op = "warpsound" },
  } }, {
    setWarpMod = function(w, g, m) mods = { w, g, m } end,
    setBlackoutMap = function(g, m) blackout = { g, m } end,
    newLoadMap = function(x) method = x end,
    warpCheck = function() checks = checks + 1 end,
    warpSound = function() sounds = sounds + 1 end,
  })
  eq(mods[1], 1, "warpmod warp id comes first")
  eq(mods[2], 15, "then the map_id group")
  eq(blackout[1], 26, "blackoutmod group")
  eq(blackout[2], 3, "blackoutmod map (CHERRYGROVE_CITY)")
  eq(method, 249, "newloadmap passes MAPSETUP_TRAIN ($f9) through")
  eq(checks, 1, "warpcheck arms the pending warp")
  eq(sounds, 1, "warpsound asks the World for GetWarpSFX")
end

-- Music.  musicfadeout's operand is a WORD id then a fade byte whose bit 7
-- (MUSIC_FADE_IN_F) is masked off.
do
  local fade, mapMusic, dontRestart = {}, 0, 0
  local vm = drive({ ["s:t"] = {
    { op = "musicfadeout", args = { 56, 0, 16 } },
    { op = "playmapmusic" },
    { op = "dontrestartmapmusic" },
  } }, {
    fadeOutMusic = function(id, control) fade = { id, control } end,
    playMapMusic = function() mapMusic = mapMusic + 1 end,
    dontRestartMapMusic = function() dontRestart = dontRestart + 1 end,
  })
  eq(fade[1], 56, "musicfadeout reads its id as lo + hi * 256")
  eq(fade[2], 16, "and its fade control")
  eq(mapMusic, 1, "playmapmusic asks for the map's own song")
  eq(dontRestart, 1, "dontrestartmapmusic sets the one-shot")
  check(vm.dontRestartMapMusic, "and the VM remembers it")
  local high = drive({ ["s:t"] = { { op = "musicfadeout", args = { 1, 0, 0x90 } } } },
    { fadeOutMusic = function(_, control) fade = control end })
  eq(fade, 0x10, "MUSIC_FADE_IN_F (bit 7) is masked out of the fade byte")
end

-- Encounters.
do
  local switches = {}
  local vm = drive({ ["s:t"] = {
    { op = "wildoff" },
    { op = "wildon" },
  } }, { setWildEncounters = function(on) switches[#switches + 1] = on end })
  eq(switches[1], false, "wildoff sets STATUSFLAGS_NO_WILD_ENCOUNTERS_F")
  eq(switches[2], true, "wildon clears it")
  check(vm.wildEncounters, "and the VM tracks the switch itself")
  local rolled = 0
  local roll = drive({ ["s:t"] = {
    { op = "loadtrainer", class = 1, member = 1 },
    { op = "randomwildmon" },
  } }, { rollWild = function()
    rolled = rolled + 1
    return { species = 21, level = 4 }
  end })
  eq(rolled, 1, "randomwildmon rolls the map's own table")
  eq(roll.wildMon.species, 21, "and parks the pick for startbattle")
  eq(roll.trainer, nil, "clearing wBattleScriptFlags drops the trainer too")
  local pika = drive({ ["s:t"] = { { op = "loadpikachudata" } } })
  eq(pika.wildMon.species, 25, "loadpikachudata is PIKACHU")
  eq(pika.wildMon.level, 5, "at level 5")
  local swarm = {}
  drive({ ["s:t"] = { { op = "swarm", args = { 26, 5 } } } },
    { setSwarm = function(g, m) swarm = { g, m } end })
  eq(swarm[1], 26, "swarm group")
  eq(swarm[2], 5, "swarm map")
  eq(Opcodes[0x9e].size, 2,
    "swarm is a bare map_id: two operand bytes, not three")
end

-- Bag.  Script_checkitem clears wScriptVar FIRST, so a bag nobody can answer
-- for reads "no item" rather than leaving the last command's value behind.
do
  local bag = { [54] = 1 }
  local vm = drive({ ["s:t"] = {
    { op = "setval", value = 1 },
    { op = "checkitem", args = { 99 } },
  } }, { hasItem = function(i) return bag[i] ~= nil end })
  eq(vm.scriptVar, 0, "checkitem on a missing item is FALSE, not stale")
  local has = drive({ ["s:t"] = { { op = "checkitem", args = { 54 } } } },
    { hasItem = function(i) return bag[i] ~= nil end })
  eq(has.scriptVar, 1, "checkitem COIN_CASE is TRUE when it is in the pack")
  local took = {}
  local take = drive({ ["s:t"] = { { op = "takeitem", args = { 67, 1 } } } }, {
    takeItem = function(i, q) took = { i, q }; return true end,
  })
  eq(take.scriptVar, 1, "takeitem is TRUE when the pack held that many")
  eq(took[2], 1, "the one-argument macro form still carries a quantity byte")
  local fail = drive({ ["s:t"] = { { op = "takeitem", args = { 67, 2 } } } },
    { takeItem = function() return false end })
  eq(fail.scriptVar, 0, "and FALSE when it did not")
end

-- Money and coins.  CompareMoneyAction answers HAVE_MORE 0 / HAVE_AMOUNT 1 /
-- HAVE_LESS 2, so an `iffalse` after a checkmoney means the player has MORE.
do
  local money = { [0] = 1500, [1] = 0 }
  local function check1000(have)
    money[0] = have
    local vm = drive({ ["s:t"] = { { op = "checkmoney", args = { 0, 0, 3, 232 } } } },
      { getMoney = function(a) return money[a] end })
    return vm.scriptVar
  end
  eq(check1000(1500), 0, "checkmoney with more than the price is HAVE_MORE (0)")
  eq(check1000(1000), 1, "exactly the price is HAVE_AMOUNT (1)")
  eq(check1000(999), 2, "less than the price is HAVE_LESS (2)")
  -- bigdt is BIG-endian: {0, 39, 16} is 10000, not 1058304.
  money[0] = 10000
  local ten = drive({ ["s:t"] = { { op = "checkmoney", args = { 0, 0, 39, 16 } } } },
    { getMoney = function(a) return money[a] end })
  eq(ten.scriptVar, 1, "the three money bytes read big-endian")
  money[0] = 1500
  drive({ ["s:t"] = { { op = "takemoney", args = { 0, 0, 3, 232 } } } }, {
    getMoney = function(a) return money[a] end,
    setMoney = function(a, v) money[a] = v end,
  })
  eq(money[0], 500, "takemoney subtracts")
  drive({ ["s:t"] = { { op = "takemoney", args = { 0, 0, 3, 232 } } } }, {
    getMoney = function(a) return money[a] end,
    setMoney = function(a, v) money[a] = v end,
  })
  eq(money[0], 0, "and floors at 0 on a borrow rather than wrapping")
  money[0] = 999000
  drive({ ["s:t"] = { { op = "givemoney", args = { 0, 0x0f, 0x42, 0x40 } } } }, {
    getMoney = function(a) return money[a] end,
    setMoney = function(a, v) money[a] = v end,
  })
  eq(money[0], 999999, "givemoney caps at MAX_MONEY")
  money[1] = 200
  local moms = drive({ ["s:t"] = { { op = "getmoney", args = { 1, 0 } } } },
    { getMoney = function(a) return money[a] end })
  eq(moms.stringBuffer, "200",
    "getmoney emits the ACCOUNT byte first and prints that account")

  local coins = 9949
  local vend = drive({ ["s:t"] = { { op = "checkcoins", args = { 221, 38 } } } },
    { getCoins = function() return coins end })
  eq(vend.scriptVar, 1, "checkcoins reads its dw little-endian (9949)")
  drive({ ["s:t"] = { { op = "givecoins", args = { 50, 0 } } } }, {
    getCoins = function() return coins end,
    setCoins = function(v) coins = v end,
  })
  eq(coins, 9999, "givecoins caps at MAX_COINS")
  drive({ ["s:t"] = { { op = "takecoins", args = { 124, 21 } } } }, {
    getCoins = function() return coins end,
    setCoins = function(v) coins = v end,
  })
  eq(coins, 4499, "takecoins subtracts 5500")
  local gc = drive({ ["s:t"] = { { op = "getcoins", args = { 0 } } } },
    { getCoins = function() return coins end })
  eq(gc.stringBuffer, "4499", "getcoins prints wCoins")
end

-- Party.  Script_giveegg answers 2, not 1, when the egg went in.
do
  local egg = {}
  local vm = drive({ ["s:t"] = { { op = "giveegg", args = { 175, 5 } } } },
    { giveEgg = function(s, l) egg = { s, l }; return true end })
  eq(vm.scriptVar, 2, "giveegg answers 2 when the party had room")
  eq(egg[1], 175, "giveegg species (TOGEPI)")
  eq(egg[2], 5, "giveegg level")
  local full = drive({ ["s:t"] = { { op = "giveegg", args = { 175, 5 } } } },
    { giveEgg = function() return false end })
  eq(full.scriptVar, 0, "and 0 when it did not")
  local poke = drive({ ["s:t"] = { { op = "checkpoke", args = { 155 } } } },
    { hasPoke = function(s) return s == 155 end })
  eq(poke.scriptVar, 1, "checkpoke walks wPartySpecies")
  local mail = drive({ ["s:t"] = { { op = "checkpokemail", args = { 236, 90 } } } })
  eq(mail.scriptVar, 2, "checkpokemail with no mail model answers REFUSED (2)")
end

-- getcurlandmarkname takes its map implicitly; the one byte is only a buffer id.
do
  local vm = drive({ ["s:t"] = { { op = "getcurlandmarkname", args = { 0 } } } },
    { getLandmarkName = function() return "NEW BARK\nTOWN" end })
  eq(vm.stringBuffer, "NEW BARK\nTOWN", "getcurlandmarkname fills the buffer")
end

-- Menus BLOCK.  The Goldenrod coin vendor is loadmenu / verticalmenu /
-- closewindow / ifequal 1 / ifequal 2, so the cursor is 1-based and 0 is B.
do
  local resume, headers = nil, {}
  local vm = Vm.new({ generation = 2,
    ["s:t"] = {
      { op = "loadmenu", args = { 199, 69 } },
      { op = "verticalmenu" },
      { op = "closewindow" },
      { op = "ifequal", value = 1, script = "s:one" },
      { op = "setlasttalked", args = { 0 } },
    },
    ["s:one"] = { { op = "setlasttalked", args = { 1 } } },
  }, {}, Events.new(), {
    openMenu = function(header, style, onChoose)
      headers[#headers + 1] = { header, style }
      resume = onChoose
    end,
  })
  vm:start("s:t")
  check(vm:running(), "the script parks on the menu")
  eq(vm.lastTalked, nil, "nothing past the menu runs while it is open")
  eq(headers[1][2], "vertical", "verticalmenu asks for the vertical style")
  eq(headers[1][1].address, 0x45c7,
    "loadmenu stashes its MenuHeader pointer as lo + hi * 256")
  resume(1)
  eq(vm.lastTalked, 1, "picking row 1 takes the ifequal 1 arm")
  check(not vm:running(), "and the script finishes")

  local cancel = Vm.new({ generation = 2, ["s:t"] = {
    { op = "_2dmenu" },
    { op = "iffalse", script = "s:no" },
    { op = "setlasttalked", args = { 9 } },
  }, ["s:no"] = { { op = "setlasttalked", args = { 0 } } } },
    {}, Events.new(), {
      openMenu = function(_, style, onChoose)
        eq(style, "2d", "_2dmenu asks for the grid style")
        onChoose(nil)
      end,
    })
  cancel:start("s:t")
  eq(cancel.scriptVar, 0, "B out of a menu is 0")
  eq(cancel.lastTalked, 0, "which is the iffalse cancel arm")

  -- No hook at all must take the cancel arm rather than hang.
  local none = drive({ ["s:t"] = {
    { op = "verticalmenu" },
    { op = "setlasttalked", args = { 3 } },
  } })
  eq(none.scriptVar, 0, "a hookless menu answers 0")
  eq(none.lastTalked, 3, "and the script runs on")
end

-- elevator answers 0 (the player backed out), which is the arm
-- GoldenrodDeptStoreElevatorScript's `iffalse .Done` wants.
do
  local vm = drive({ ["s:t"] = {
    { op = "setval", value = 1 },
    { op = "elevator", args = { 218, 73 } },
    { op = "iffalse", script = "s:done" },
    { op = "setlasttalked", args = { 5 } },
  }, ["s:done"] = { { op = "setlasttalked", args = { 0 } } } })
  eq(vm.scriptVar, 0, "elevator answers FALSE with no floor list")
  eq(vm.lastTalked, 0, "so the script skips the ride")
end

-- Phone.  askforphonenumber's SUCCESS IS ZERO: an `iftrue` after it means the
-- number did NOT go in.
do
  local vm = drive({ ["s:t"] = { { op = "askforphonenumber", args = { 5 } } } },
    { addPhoneNumber = function() return true end })
  eq(vm.scriptVar, 0, "a registered number is PHONE_CONTACT_GOT (0)")
  local full = drive({ ["s:t"] = { { op = "askforphonenumber", args = { 5 } } } },
    { addPhoneNumber = function() return false end })
  eq(full.scriptVar, 1, "a full list is PHONE_CONTACTS_FULL (1)")
  local no = drive({ ["s:t"] = { { op = "askforphonenumber", args = { 5 } } } }, {
    yesorno = function(onChoose) onChoose(false) end,
    addPhoneNumber = function() error("refused must not register") end,
  })
  eq(no.scriptVar, 2, "saying no is PHONE_CONTACT_REFUSED (2)")

  local stored
  local call = drive({ ["s:t"] = {
    { op = "specialphonecall", args = { 4, 0 } },
    { op = "checkphonecall" },
  } }, { setSpecialCall = function(id) stored = id end })
  eq(stored, 4, "specialphonecall stores its dw id")
  eq(call.scriptVar, 1, "checkphonecall sees a queued call")
  local quiet = drive({ ["s:t"] = { { op = "checkphonecall" } } })
  eq(quiet.scriptVar, 0, "and answers 0 with nothing queued")
  -- Only the LOW byte is ever read back: wSpecialPhoneCallID is a single db.
  local highOnly = drive({ ["s:t"] = {
    { op = "specialphonecall", args = { 0, 2 } },
    { op = "checkphonecall" },
  } })
  eq(highOnly.scriptVar, 0, "a high-byte-only id reads as no call")

  local hung = 0
  local hangup = drive({ ["s:t"] = { { op = "hangup" } } },
    { hangUp = function() hung = hung + 1 end })
  eq(hung, 1, "hangup closes the call box")
  local sawClick
  for _, line in ipairs(select(2, drive({ ["s:t"] = { { op = "hangup" } } }))) do
    if line:find("Click!", 1, true) then sawClick = true end
  end
  check(sawClick, "and prints PhoneClickText")
end

-- Hall of Fame and the credits both tear the script stack down.
do
  local resume
  local vm = Vm.new({ generation = 2, ["s:t"] = {
    { op = "halloffame" },
    { op = "setlasttalked", args = { 4 } },
  } }, {}, Events.new(), {
    hallOfFame = function(onDone) resume = onDone end,
  })
  vm:start("s:t")
  check(vm:running(), "halloffame parks on its own screen")
  resume()
  eq(vm.lastTalked, nil, "and Script_endall means nothing after it runs")
  local credits = drive({ ["s:t"] = {
    { op = "credits" },
    { op = "setlasttalked", args = { 4 } },
  } }, { credits = function(onDone) onDone() end })
  eq(credits.lastTalked, nil, "credits ends the script stack too")
end

-- fruittree is a ScriptJump: nothing after it in the caller runs, and the
-- FruitTreeScript body is inlined here because no map pointer reaches it.
do
  local picked = {}
  local vm, log = drive({ ["s:t"] = {
    { op = "fruittree", args = { 1 } },
    { op = "setlasttalked", args = { 7 } },
  } }, {
    fruitTreeItem = function(tree) return tree == 1 and 158 or 0 end,
    getItemName = function(i) return i == 158 and "BERRY" or "?" end,
    giveItem = function() return true end,
    fruitTreePicked = function() return false end,
    fruitTreePick = function(t) picked[#picked + 1] = t end,
  })
  eq(vm.lastTalked, nil, "fruittree never returns to the caller")
  eq(picked[1], 1, "the tree flag is set after the fruit is banked")
  local joined = table.concat(log, "|")
  check(joined:find("fruit-", 1, true), "FruitBearingTreeText printed")
  check(joined:find("Hey! It's", 1, true), "HeyItsFruitText printed")
  check(joined:find("Obtained", 1, true), "ObtainedFruitText printed")

  local _, doneLog = drive({ ["s:t"] = { { op = "fruittree", args = { 2 } } } }, {
    fruitTreeItem = function() return 158 end,
    getItemName = function() return "BERRY" end,
    fruitTreePicked = function() return true end,
    fruitTreePick = function() error("a picked tree must not be picked again") end,
    giveItem = function() error("a picked tree has no fruit to give") end,
  })
  check(table.concat(doneLog, "|"):find("nothing", 1, true),
    "an already-picked tree prints NothingHereText and stops")

  local full = drive({ ["s:t"] = { { op = "fruittree", args = { 3 } } } }, {
    fruitTreeItem = function() return 158 end,
    getItemName = function() return "BERRY" end,
    fruitTreePicked = function() return false end,
    giveItem = function() return false end,
    fruitTreePick = function() error("a full pack must leave the tree pickable") end,
  })
  eq(full.scriptVar, 0, "a full pack answers FALSE the way giveitem does")
end

-- describedecoration is a ScriptJump too, so it must not fall into the garbage
-- the extractor read past it.
do
  local kinds = {}
  local vm = drive({ ["s:t"] = {
    { op = "describedecoration", args = { 0 } },
    { op = "setlasttalked", args = { 3 } },
  } }, { describeDecoration = function(k) kinds[#kinds + 1] = k end })
  eq(kinds[1], 0, "describedecoration passes its DECODESC_* byte")
  eq(vm.lastTalked, nil, "and ends the script")
end

-- repeattext prints the last jumptext, and ONLY for the -1, -1 operand.
do
  local vm, log = drive({ ["s:t"] = {
    { op = "jumptext", text = "t:hi" },
  }, ["s:after"] = {} }, {}, { ["t:hi"] = "Hello!" })
  eq(vm.lastTextKey, "t:hi", "jumptext parks its pointer in wScriptTextAddr")
  local _, again = drive({ ["s:t"] = {
    { op = "writetext", text = "t:hi" },
    { op = "repeattext", args = { 255, 255 } },
    { op = "repeattext", args = { 1, 2 } },
  } }, {}, { ["t:hi"] = "Hello!" })
  local n = 0
  for _, line in ipairs(again) do
    if line == "text:Hello!" then n = n + 1 end
  end
  eq(n, 2, "repeattext -1, -1 reprints once; any other pointer prints nothing")
  check(#log >= 1, "the jumptext harness printed its line")
end

-- The rest of the commands with no engine behind them yet: they must consume
-- their operand deliberately rather than fall through the unknown-op path.
do
  local vm = drive({ ["s:t"] = {
    { op = "setval", value = 6 },
    { op = "writeunusedbyte", args = { 3 } },
    { op = "xycompare", args = { 0x34, 0x34 } },
    { op = "autoinput", args = { 0x3e, 0x00, 0x40 } },
    { op = "writecmdqueue", args = { 0x10, 0x40 } },
    { op = "memcall", args = { 1, 15 } },
    { op = "memcallasm", args = { 7, 241 } },
    { op = "closewindow" },
    { op = "deactivatefacing", args = { 0 } },
  } })
  eq(vm.scriptVar, 6, "none of the inert commands touches wScriptVar")
  eq(vm.unusedScriptByte, 3, "writeunusedbyte still records its byte")
  eq(vm.xyComparePointer, 0x3434, "xycompare records its pointer")
  local empty = true
  for _ in pairs(vm.unknownOps) do empty = false end
  check(empty, "and none of them reaches the unknown-op path")
end

-- The unknown-op ledger itself.  A silent skip is what makes a missing opcode
-- corrupt a branch instead of announcing itself, so this has to be observable.
do
  local vm = drive({ ["s:t"] = {
    { op = "notacommand" },
    { op = "notacommand" },
    { op = "alsonot" },
  } })
  eq(vm.unknownOps.notacommand, 2, "an unimplemented opcode is counted")
  eq(vm.unknownOps.alsonot, 1, "per opcode name")
  local clean = drive({ ["s:t"] = {
    { op = "setval", value = 1 },
    { op = "checkver" },
    { op = "end" },
  } })
  local empty = true
  for _ in pairs(clean.unknownOps) do empty = false end
  check(empty, "a script of implemented commands leaves the ledger empty")
end

-- Cache-backed checks (skip when no gold cache / pre-slice extract).
local cache = os.getenv("GOLD_CACHE")
if not cache then
  local home = os.getenv("HOME") or ""
  cache = home .. "/Library/Application Support/LOVE/gold-dev/gold"
end
local scriptsPath = cache .. "/data/generated/scripts.lua"
local mapsPath = cache .. "/data/generated/maps.lua"
local sf, mf = io.open(scriptsPath, "r"), io.open(mapsPath, "r")
if not sf or not mf then
  if sf then sf:close() end
  if mf then mf:close() end
  check(true, "gold cache absent : VM unit checks only (SKIP cache facts)")
  S.finish()
  return
end
sf:close(); mf:close()

local goldScripts = assert(loadfile(scriptsPath))()
local maps = assert(loadfile(mapsPath))()
check(goldScripts.movements ~= nil
  or (goldScripts["60:40c6"] ~= nil),
  "scripts.lua present (movements after re-import)")
local lab = maps.ELMS_LAB
check(lab ~= nil, "ELMS_LAB in maps")
if lab and lab.sceneScripts then
  local s0 = lab.sceneScripts[0]
  check(s0 and s0.scriptKey, "ELMS_LAB scene 0 scriptKey extracted")
end
local ball = goldScripts["60:4144"]
if ball then
  local ops = {}
  for _, c in ipairs(ball) do ops[#ops + 1] = c.op end
  local joined = table.concat(ops, ",")
  check(joined:find("givepoke", 1, true), "Chikorita ball has givepoke")
  check(joined:find("yesorno", 1, true), "Chikorita ball has yesorno")
end
local directions = goldScripts["60:4186"]
if directions then
  local hasPhone, hasScene5
  for _, c in ipairs(directions) do
    if c.op == "addcellnum" and (c.phone == 4 or (c.args and c.args[1] == 4)) then
      hasPhone = true
    end
    if c.op == "setscene" and c.scene == 5 then hasScene5 = true end
  end
  check(hasPhone, "ElmDirections has addcellnum PHONE_ELM")
  check(hasScene5, "ElmDirections setscene → aide potion (5)")
end
local potion = goldScripts["60:42e9"]
if potion then
  local hasGive
  for _, c in ipairs(potion) do
    if c.op == "verbosegiveitem"
        and (c.item == 18 or (c.args and c.args[1] == 18)) then
      hasGive = true
    end
  end
  check(hasGive, "AideScript_GivePotion verbosegiveitem POTION")
end
-- Every clerk in Johto and Kanto is a `pokemart` in the extracted bytecode.
-- MartTypeDialogs has four entries and Marts has NUM_MARTS = 34, so a row that
-- decodes outside either range is a script the walker wandered into rather than
-- a real mart -- three such rows sit in bank $42 and GetMart hands them
-- DefaultMart, which is why this counts sane rows instead of demanding all of
-- them are.
local martTypesSeen, saneMarts = {}, 0
for key, list in pairs(goldScripts) do
  if type(key) == "string" and type(list) == "table" then
    for _, c in ipairs(list) do
      if type(c) == "table" and c.op == "pokemart" and c.args then
        local kind = c.args[1] or 0
        local id = (c.args[2] or 0) + (c.args[3] or 0) * 0x100
        if kind < 4 and id < 34 then
          saneMarts = saneMarts + 1
          martTypesSeen[kind] = true
        end
      end
    end
  end
end
check(saneMarts >= 30, "the cache carries a pokemart per mart clerk")
check(martTypesSeen[0], "MARTTYPE_STANDARD is scripted")
check(martTypesSeen[1], "MARTTYPE_BITTER is scripted (the herb shop)")
check(martTypesSeen[2], "MARTTYPE_BARGAIN is scripted (the underground)")
check(martTypesSeen[3], "MARTTYPE_PHARMACY is scripted (Cianwood)")

-- ---------------------------------------------------------------------------
-- Opcode coverage over the WHOLE extracted cache.
--
-- The point of this pair of checks is that a missing opcode used to be a silent
-- skip, and a silent skip is worse than an error: `checkitem` followed by
-- `iftrue` reads a stale wScriptVar and takes the wrong arm.  So: count what
-- Johto actually calls, and prove the interpreter has a branch for all of it.
-- ---------------------------------------------------------------------------
local vmSource
do
  local f = assert(io.open("src/script/gen2/Vm.lua", "r"))
  vmSource = f:read("*a")
  f:close()
end
local implemented = {}
for name in vmSource:gmatch('op == "([%w_]+)"') do implemented[name] = true end

local cacheOps, opUses, cacheRow = {}, {}, {}
local distinct, scriptCount = 0, 0
for key, list in pairs(goldScripts) do
  if type(key) == "string" and type(list) == "table" then
    scriptCount = scriptCount + 1
    for _, c in ipairs(list) do
      if type(c) == "table" and type(c.op) == "string" then
        if not cacheOps[c.op] then
          cacheOps[c.op] = true
          distinct = distinct + 1
          cacheRow[c.op] = c
        end
        opUses[c.op] = (opUses[c.op] or 0) + 1
      end
    end
  end
end

local missing, covered = {}, 0
for op in pairs(cacheOps) do
  if implemented[op] then
    covered = covered + 1
  else
    missing[#missing + 1] = ("%s (%d uses)"):format(op, opUses[op] or 0)
  end
end
table.sort(missing)
-- A floor, not a ratchet: the coverage assertion is the one below.  It used to
-- be 130, and it came down when the extractor stopped disassembling the 87
-- BGEVENT_ITEM `hiddenitem` structs as bytecode -- roughly twenty opcodes
-- (`memcall`, `autoinput`, `warpfacing`, a `callstd` with a four-digit std id)
-- were called ONLY out of that noise and never by a real Johto script.
check(distinct > 110,
  ("the cache calls %d distinct script commands across %d scripts")
    :format(distinct, scriptCount))
eq(#missing, 0,
  ("every command Johto calls has a branch (%d/%d covered; missing: %s)")
    :format(covered, distinct, table.concat(missing, ", ")))

-- Every opcode in the Opcodes table is either something the cache never calls
-- or something the VM handles; nothing is half-wired.
local tableMissing = {}
for code = 0x00, 0xa1 do
  local info = Opcodes[code]
  if info and not implemented[info.name] then
    tableMissing[#tableMissing + 1] = info.name
  end
end
table.sort(tableMissing)
eq(#tableMissing, 0,
  "every opcode in Opcodes.lua has a Vm branch (missing: "
    .. table.concat(tableMissing, ", ") .. ")")

-- Now drive a REAL command out of the cache for each distinct opcode through a
-- real Vm.  The script table is empty apart from the one row, so every jump
-- target resolves to nothing and each command is isolated; the hooks all resume
-- synchronously so a blocking command cannot hang the suite.  Nothing may reach
-- the unknown-op ledger.
local unhandled = {}
for op, row in pairs(cacheRow) do
  local resumed = false
  local vm = Vm.new({ generation = 2, ["s:one"] = { row } }, {}, Events.new(), {
    showText = function(_, onDone) onDone() end,
    yesorno = function(onChoose) onChoose(true) end,
    waitSfx = function() return true end,
    applyMovement = function(_, _, onDone) onDone() end,
    startBattle = function(_, _, onDone) onDone("win") end,
    openMart = function(_, _, onDone) onDone() end,
    trainerApproach = function(onDone) onDone() end,
    openMenu = function(_, _, onChoose) onChoose(0) end,
    npcTrade = function(_, onDone) onDone() end,
    phoneCall = function(_, onDone) onDone() end,
    hallOfFame = function(onDone) resumed = true; onDone() end,
    credits = function(onDone) resumed = true; onDone() end,
    getItemName = function() return "BERRY" end,
    fruitTreeItem = function() return 158 end,
    giveItem = function() return true end,
  })
  vm:start("s:one")
  for _ = 1, 600 do
    if not vm:running() then break end
    vm:update()
  end
  for name in pairs(vm.unknownOps) do
    unhandled[#unhandled + 1] = name
  end
  local _ = resumed
end
table.sort(unhandled)
eq(#unhandled, 0,
  "running one real row per opcode reaches no unknown-op path (hit: "
    .. table.concat(unhandled, ", ") .. ")")

-- The two commands whose operands are coordinates, checked against the cache
-- rather than against my arithmetic.  changeblock is CELLS halved into blocks,
-- so a row that lands outside its map's block grid would mean the halving is
-- wrong; warp names a group/map pair that has to exist in maps.lua.
local byGroupMap = {}
for id, def in pairs(maps) do
  if type(def) == "table" and def.group and def.map then
    byGroupMap[def.group * 256 + def.map] = id
  end
end
local warpRows, warpResolved = 0, 0
local blockRows, blockInGrid = 0, 0
for key, list in pairs(goldScripts) do
  if type(key) == "string" and type(list) == "table" then
    for _, c in ipairs(list) do
      if type(c) == "table" and c.op == "warp" and c.args then
        warpRows = warpRows + 1
        if byGroupMap[(c.args[1] or 0) * 256 + (c.args[2] or 0)] then
          warpResolved = warpResolved + 1
        end
      elseif type(c) == "table" and c.op == "changeblock" and c.args then
        blockRows = blockRows + 1
        -- No map id on the command, so this only checks the halving is sane
        -- against the largest map in the game rather than against the right
        -- one: a stride bug would push these into the hundreds.
        local bx = math.floor((c.args[1] or 0) / 2)
        local by = math.floor((c.args[2] or 0) / 2)
        if bx < 40 and by < 40 then blockInGrid = blockInGrid + 1 end
      end
    end
  end
end
check(warpRows >= 15, "the cache carries the scripted warps")
check(warpResolved >= warpRows - 1,
  ("every scripted warp names a real map (%d/%d)")
    :format(warpResolved, warpRows))
check(blockRows >= 50, "the cache carries the scripted changeblocks")
eq(blockInGrid, blockRows, "every changeblock halves into a plausible block")

local itemsPath = cache .. "/data/generated/items.lua"
local itemsChunk = loadfile(itemsPath)
if itemsChunk then
  local items = itemsChunk()
  if items and items.POTION then
    eq(items.POTION.index, 18, "POTION index is 0x12")
    check(items.POTION.name == "POTION", "POTION name extracted")
  else
    check(true, "items.lua stub : re-import for ItemNames (SKIP)")
  end
end

-- ================================================================= specials
--
-- data/events/special_pointers.asm.  Three things are under test here and they
-- fail differently, so they are asserted separately:
--
--   1. the MAPPING.  A special is dispatched by INDEX through the extracted
--      SpecialsPointers order, so an off-by-one silently runs the wrong
--      routine -- HealParty where PokemonCenterPC should be.  Every name this
--      module claims is driven through a real Vm at the index the CACHE says
--      it lives at, and the handler that runs has to be the one asked for.
--   2. COVERAGE.  How many of the 112 are ported, how many are deliberate
--      stubs, and that the two sets are disjoint and together cover the whole
--      table -- because a name with no entry at all falls through and leaves a
--      STALE wScriptVar behind, which is the failure this module exists to
--      stop.
--   3. the EFFECT of each ported routine, driven through a real Vm.
local Specials = require("src.script.gen2.Specials")

local handlerCount, stubCount = 0, 0
for _ in pairs(Specials.HANDLERS) do handlerCount = handlerCount + 1 end
for _ in pairs(Specials.STUBS) do stubCount = stubCount + 1 end
check(handlerCount >= 70,
  ("%d specials are ported"):format(handlerCount))
-- The stub floor only ever comes DOWN: every feature that lands moves a name
-- out of STUB_ROWS and into HANDLERS, and the pair of counts below plus the
-- disjointness and total-coverage checks that follow are what actually holds
-- the table together.  UnownPuzzle left this set when the Ruins of Alph
-- sliding-panel screen landed; PhotoStudio left it when the Cianwood photo
-- studio's conversation and portrait card landed (the print itself is still
-- out of scope, but that lives inside H.PhotoStudio now, not in STUB_ROWS).
-- MagnetTrain left it when the Goldenrod <-> Saffron ride cutscene landed.
-- UnownPrinter left it for the same reason PhotoStudio did: the ALPH RUINS
-- STAMP viewer is drawn on the cartridge and only the A press wanted the
-- printer, so the stub moved inside H.UnownPrinter.  MapRadio left it when
-- the wall radios got the gear's channel player (H.MapRadio).
-- RandomPhoneWildMon and RandomPhoneMon left it when the incoming-call ring
-- landed and GetCallerLocation finally had a caller to read: the id rides
-- vm.curPhoneCaller and both names now land in the string buffer.
check(stubCount >= 23,
  ("%d are deliberate stubs"):format(stubCount))

local overlap = {}
for name in pairs(Specials.HANDLERS) do
  if Specials.STUBS[name] then overlap[#overlap + 1] = name end
end
eq(table.concat(overlap, ","), "",
  "no special is both implemented and stubbed")
eq(handlerCount + stubCount, (function()
  local n = 0
  for _ in pairs(Specials.ALL) do n = n + 1 end
  return n
end)(), "and ALL is exactly the two sets merged")

-- Every stub says WHY, in its own words.  A stub with no reason is a hole
-- somebody meant to come back to and did not.
local unexplained = {}
for name in pairs(Specials.STUBS) do
  local reason = Specials.STUB_REASONS[name]
  if type(reason) ~= "string" or #reason < 10 then
    unexplained[#unexplained + 1] = name
  end
end
eq(table.concat(unexplained, ","), "", "every stub records its reason")

-- A Vm wired for one special at a time: `specials` is the World's hook table
-- (stubbed), and the script is one `special` row.
local function specialVm(id, opts)
  opts = opts or {}
  local vm = Vm.new({ ["s:x"] = { { op = "special", id = id } } }, {},
    Events.new(), {
      specialOrder = opts.order,
      specials = opts.hooks or {},
      showText = opts.showText,
      setStringBuffer = function(v) opts.buffer = v end,
      openPc = opts.openPc,
      healParty = opts.healParty,
      cry = opts.cry,
      showMoney = opts.showMoney,
      showCoins = opts.showCoins,
      warpToSpawn = opts.warpToSpawn,
      nameRival = opts.nameRival,
    })
  vm.scriptVar = opts.scriptVar or 0
  return vm
end

-- ---- 1. the mapping against the cache -------------------------------------
local specialOrder
do
  local chunk = cache and loadfile(cache .. "/data/generated/constants.lua")
  local consts = chunk and chunk()
  specialOrder = consts and consts.specialOrder
end

if specialOrder then
  eq(#specialOrder, 112,
    "the cache carries all 112 SpecialsPointers rows (the asm's 113 " ..
    "add_special matches include the MACRO line)")
  local uncovered = {}
  for _, name in ipairs(specialOrder) do
    if not Specials.ALL[name] then uncovered[#uncovered + 1] = name end
  end
  eq(table.concat(uncovered, ","), "",
    "every special in the cache resolves to a handler or a stub")

  -- The dispatch itself: put a marker handler at each index in turn and assert
  -- the VM runs THAT one.  This is the assertion that catches an off-by-one in
  -- Vm:specialName, which no amount of per-handler testing would.
  local misrouted = {}
  for index, name in ipairs(specialOrder) do
    local ran = nil
    local saved = Vm.SPECIALS[name]
    Vm.SPECIALS[name] = function() ran = name end
    local vm = specialVm(index - 1, { order = specialOrder })
    vm:start("s:x")
    for _ = 1, 4 do vm:update() end
    Vm.SPECIALS[name] = saved
    if ran ~= name then misrouted[#misrouted + 1] = name end
  end
  eq(table.concat(misrouted, ","), "",
    "and every one of the 112 indices dispatches to its own name")

  -- Nothing in the extracted cache asks for a special this table cannot
  -- answer.  The junk ids come from mis-walked ROM regions rather than from
  -- real scripts, so they are counted and reported, not asserted away.
  local goldScriptsForSpecials =
    cache and loadfile(cache .. "/data/generated/scripts.lua")
  if goldScriptsForSpecials then
    local rows = goldScriptsForSpecials()
    local real, junk, unhandled = 0, 0, {}
    local function walk(list)
      for _, cmd in ipairs(list) do
        if type(cmd) == "table" then
          if cmd.op == "special" then
            local id = cmd.id or (cmd.args and cmd.args[1])
            local name = id and specialOrder[id + 1]
            if name then
              real = real + 1
              if not Specials.ALL[name] then
                unhandled[#unhandled + 1] = name
              end
            else
              junk = junk + 1
            end
          end
          for _, v in pairs(cmd) do
            if type(v) == "table" then walk(v) end
          end
        end
      end
    end
    for _, list in pairs(rows) do
      if type(list) == "table" then walk(list) end
    end
    check(real > 300, ("the cache carries %d scripted specials"):format(real))
    eq(table.concat(unhandled, ","), "",
      "and every one of them resolves to a handler or a stub")
  end
end

-- ---- 2. the ported routines -----------------------------------------------

-- The four fixed hook forwards keep working through the new module.
do
  local healed = false
  local vm = specialVm(0, { order = { "HealParty" },
    healParty = function() healed = true end })
  vm.scriptVar = 0
  Specials.HANDLERS.HealParty(vm)
  check(healed, "HealParty still reaches its hook")
end

-- PlayersHousePC answers FALSE before it opens: `xor a / ld [wScriptVar], a`
-- runs before the farcall, so a script that reads the var after it does not
-- see whatever the last special left there.
do
  local opened = false
  local vm = specialVm(0, { order = { "PlayersHousePC" },
    openPc = function() opened = true end })
  vm.scriptVar = 7
  Specials.HANDLERS.PlayersHousePC(vm)
  eq(vm.scriptVar, 0, "PlayersHousePC zeroes wScriptVar first")
  check(opened, "and opens the storage system")
end

-- CheckFirstMonIsEgg / GetFirstPokemonHappiness: the happiness loop SKIPS
-- eggs, which is why a party led by an egg still gets an answer from the mon
-- behind it.
do
  local list = { { species = "TOGEPI", isEgg = true },
    { species = "CHIKORITA", happiness = 140 } }
  local vm = specialVm(0, { order = { "x" },
    hooks = { party = function() return list end,
      monName = function(s) return s end } })
  Specials.HANDLERS.CheckFirstMonIsEgg(vm)
  eq(vm.scriptVar, 1, "CheckFirstMonIsEgg is TRUE with an egg in slot 1")
  Specials.HANDLERS.GetFirstPokemonHappiness(vm)
  eq(vm.scriptVar, 140,
    "and GetFirstPokemonHappiness walks PAST the egg to the mon behind it")
  table.remove(list, 1)
  Specials.HANDLERS.CheckFirstMonIsEgg(vm)
  eq(vm.scriptVar, 0, "and is FALSE once the egg is gone")
end

-- The four party searches share FoundOne / FoundNone: wScriptVar goes IN as
-- the thing looked for and comes back TRUE or FALSE.
do
  local list = { { species = "CHIKORITA", level = 20, happiness = 200,
    otId = 1234 } }
  local hooks = { party = function() return list end,
    monIndex = function(s) return s == "CHIKORITA" and 152 or 0 end,
    save = function() return { player = { id = 1234 } } end }
  local vm = specialVm(0, { order = { "x" }, hooks = hooks })
  vm.scriptVar = 152
  Specials.HANDLERS.FindPartyMonThatSpecies(vm)
  eq(vm.scriptVar, 1, "FindPartyMonThatSpecies finds it")
  vm.scriptVar = 129
  Specials.HANDLERS.FindPartyMonThatSpecies(vm)
  eq(vm.scriptVar, 0, "and answers FALSE for a species that is not there")
  vm.scriptVar = 15
  Specials.HANDLERS.FindPartyMonAboveLevel(vm)
  eq(vm.scriptVar, 1, "FindPartyMonAboveLevel compares levels")
  vm.scriptVar = 152
  Specials.HANDLERS.FindPartyMonThatSpeciesYourTrainerID(vm)
  eq(vm.scriptVar, 1, "your own mon passes the trainer-ID check")
  list[1].otId = 9999
  vm.scriptVar = 152
  Specials.HANDLERS.FindPartyMonThatSpeciesYourTrainerID(vm)
  eq(vm.scriptVar, 0, "and a TRADED one of the same species does not")
end

-- CheckPokerus is ScriptReturnCarry over the party.
do
  local list = { { species = "CHIKORITA" } }
  local vm = specialVm(0, { order = { "x" },
    hooks = { party = function() return list end } })
  Specials.HANDLERS.CheckPokerus(vm)
  eq(vm.scriptVar, 0, "CheckPokerus is FALSE with a clean party")
  list[1].pokerus = 0x24
  Specials.HANDLERS.CheckPokerus(vm)
  eq(vm.scriptVar, 1, "and TRUE once one mon carries it")
end

-- The Bug Contest party mask.  ContestDropOffMons does not STORE the party,
-- it truncates the count to 1 and hides the rest behind a terminator; the
-- return walk is what puts a mon CAUGHT during the contest in front of them.
do
  local list = { { species = "CHIKORITA", hp = 20 }, { species = "MAGIKARP" },
    { species = "SHUCKLE" } }
  local vm = specialVm(0, { order = { "x" },
    hooks = { party = function() return list end } })
  Specials.HANDLERS.ContestDropOffMons(vm)
  eq(vm.scriptVar, 0, "a healthy lead mon is accepted")
  eq(#list, 1, "and the rest of the party is masked away")
  list[2] = { species = "CATERPIE" } -- the contest catch
  Specials.HANDLERS.ContestReturnMons(vm)
  eq(#list, 4, "the tail comes back")
  eq(list[2].species, "CATERPIE", "behind the mon caught during the contest")
  eq(list[3].species, "MAGIKARP", "in their old order")

  local fainted = { { species = "CHIKORITA", hp = 0 } }
  local vm2 = specialVm(0, { order = { "x" },
    hooks = { party = function() return fainted end } })
  Specials.HANDLERS.ContestDropOffMons(vm2)
  eq(vm2.scriptVar, 1, "a fainted lead mon is refused")
  eq(#fainted, 1, "and nothing is masked")
end

-- The Lucky Number Show: trailing digits of the trainer ID against the day's
-- five-digit number.  The BEST match wins across party and boxes.
eq(Specials.trailingDigitsShared(12345, 12345), 5, "an exact ID match is 5")
eq(Specials.trailingDigitsShared(99345, 12345), 3, "three trailing digits")
eq(Specials.trailingDigitsShared(99945, 12345), 2, "two trailing digits")
eq(Specials.trailingDigitsShared(99995, 12345), 1, "one is not enough")
eq(Specials.luckyPrizeFor(5), 1, "five digits is the first prize")
eq(Specials.luckyPrizeFor(4), 2, "four is the second")
eq(Specials.luckyPrizeFor(3), 2, "three is the second too")
eq(Specials.luckyPrizeFor(2), 3, "two is the third")
eq(Specials.luckyPrizeFor(1), 0, "one wins nothing")
do
  local record = { luckyNumber = 12345,
    party = { { species = "CHIKORITA", otId = 99345 } },
    boxes = { { { species = "MAGIKARP", otId = 12345 } } } }
  local vm = specialVm(0, { order = { "x" }, hooks = {
    save = function() return record end,
    party = function() return record.party end,
    monName = function(sp) return sp end } })
  Specials.HANDLERS.CheckForLuckyNumberWinners(vm)
  eq(vm.scriptVar, 1, "the BOX mon's exact match beats the party's partial one")
  check(vm.luckyNumberInBox, "and the routine remembers it was in a box")
  Specials.HANDLERS.PrintTodaysLuckyNumber(vm)
  eq(vm.stringBuffer, "12345", "and the number prints with leading zeros")
end

-- RestartLuckyNumberCountdown: days until the NEXT Friday, where Friday
-- itself is a week away rather than zero.  SUNDAY 0 .. SATURDAY 6.
eq(Specials.daysUntilFriday(0), 5, "Sunday is five days from Friday")
eq(Specials.daysUntilFriday(4), 1, "Thursday is one day out")
eq(Specials.daysUntilFriday(5), 7, "Friday itself waits a full week")
eq(Specials.daysUntilFriday(6), 6, "Saturday is six days out")

-- The Lucky Number Show's weekly gate.  wLuckyNumberDayTimer starts zeroed
-- (never armed), which is what makes the FIRST visit always reset; after that
-- it stays armed until the countdown actually reaches the next Friday, so a
-- second visit the same week keeps last week's number and last week's win.
do
  local record = {}
  local engineFlags = { ENGINE_LUCKY_NUMBER_SHOW = true }
  local vm = specialVm(0, { order = { "x" }, hooks = {
    save = function() return record end,
    setEngineFlag = function(flag, value) engineFlags[flag] = value end,
  } })

  Specials.HANDLERS.CheckLuckyNumberShowFlag(vm)
  eq(vm.scriptVar, 1, "a never-armed timer reads as already expired")

  Specials.HANDLERS.ResetLuckyNumberShowFlag(vm)
  check(record.luckyNumber ~= nil, "resetting rolls a number")
  check(record.luckyNumber >= 0 and record.luckyNumber <= 99999,
    "in the five-digit range")
  eq(engineFlags.ENGINE_LUCKY_NUMBER_SHOW, nil,
    "and clears the SAME storage checkflag ENGINE_LUCKY_NUMBER_SHOW reads")

  Specials.HANDLERS.CheckLuckyNumberShowFlag(vm)
  eq(vm.scriptVar, 0,
    "freshly armed, the timer is not expired again until next Friday")

  -- Fast-forward past the reset week: the stored day and the timer's
  -- remaining count both move, the same way CalcDaysSince advances the start
  -- day as a side effect of measuring it.
  local timer = record.luckyNumberReset
  local future = { day = (timer.day or 0) + timer.remaining }
  local BugContest = require("src.core.gen2.BugContest")
  local savedNow = BugContest.now
  BugContest.now = function() return future end
  Specials.HANDLERS.CheckLuckyNumberShowFlag(vm)
  BugContest.now = savedNow
  eq(vm.scriptVar, 1, "and IS expired once that many days have actually passed")
end

-- The haircut brothers.  wScriptVar is 2, 3 or 4 -- the barber's script
-- branches on those, so a 0-based table would have him say the wrong line --
-- and the happiness gained depends on the band the mon is already in.
do
  local mon = { species = "CHIKORITA", happiness = 250 }
  local vm = specialVm(0, { order = { "x" }, hooks = {
    party = function() return { mon } end,
    monName = function(sp) return sp end,
    selectPartyMon = function(_, done) done(1, mon) end } })
  local saved = Specials.random
  Specials.random = function() return 0 end -- the first row every time
  Specials.HANDLERS.OlderHaircutBrother(vm)
  eq(vm.scriptVar, 2, "the older brother's first row answers 2")
  eq(mon.happiness, 251, "and adds 1, the >= 200 band's OLDERCUT1")
  mon.happiness = 50
  Specials.HANDLERS.YoungerHaircutBrother(vm)
  eq(vm.scriptVar, 2, "the younger brother's first row answers 2 as well")
  eq(mon.happiness, 51, "with YOUNGCUT1's own low-band change")
  Specials.random = function() return 254 end -- fall through to the last row
  mon.happiness = 50
  Specials.HANDLERS.YoungerHaircutBrother(vm)
  eq(vm.scriptVar, 4, "the last row answers 4")
  eq(mon.happiness, 60, "and YOUNGCUT3 is +10 down there")
  Specials.random = saved
end
do
  -- An egg cannot be groomed: `.egg` leaves wScriptVar at 0.
  local egg = { species = "TOGEPI", isEgg = true }
  local vm = specialVm(0, { order = { "x" }, hooks = {
    party = function() return { egg } end,
    monName = function(sp) return sp end,
    selectPartyMon = function(_, done) done(1, egg) end } })
  vm.scriptVar = 3
  Specials.HANDLERS.DaisysGrooming(vm)
  eq(vm.scriptVar, 0, "Daisy refuses an egg")
end

-- Mania's Shuckie.  All three identity checks matter, because handing back a
-- Shuckle you caught yourself is the thing the routine refuses.
do
  local list = {}
  local vm = specialVm(0, { order = { "x" }, hooks = {
    party = function() return list end,
    data = function()
      return { pokemon = { SHUCKLE = { name = "SHUCKLE", index = 213,
        growthRate = "MEDIUM_FAST",
        baseStats = { hp = 20, attack = 10, defense = 230, speed = 5,
          specialAttack = 10, specialDefense = 230 },
        levelMoves = { { level = 1, move = "CONSTRICT" } } } },
        moves = { CONSTRICT = { name = "CONSTRICT", pp = 35 } } }
    end } })
  Specials.HANDLERS.GiveShuckle(vm)
  eq(vm.scriptVar, 1, "GiveShuckle hands one over")
  eq(#list, 1, "into the party")
  eq(list[1].nickname, "SHUCKIE", "nicknamed SHUCKIE")
  eq(list[1].otId, Specials.MANIA_OT_ID, "with MANIA's trainer ID")
  eq(list[1].item, "BERRY", "holding a BERRY")
  eq(list[1].level, 15, "at level 15")

  local hooks2 = { party = function() return list end,
    selectPartyMon = function(_, done) done(1, list[1]) end }
  local vm2 = specialVm(0, { order = { "x" }, hooks = hooks2 })
  local impostor = { species = "SHUCKLE", otId = 1, ot = "GOLD", hp = 5 }
  hooks2.selectPartyMon = function(_, done) done(1, impostor) end
  Specials.HANDLERS.ReturnShuckie(vm2)
  eq(vm2.scriptVar, Specials.SHUCKIE_WRONG_MON,
    "a Shuckle that is not MANIA's is refused")
  hooks2.selectPartyMon = function(_, done) done(1, list[1]) end
  list[1].hp = 0
  Specials.HANDLERS.ReturnShuckie(vm2)
  eq(vm2.scriptVar, Specials.SHUCKIE_FAINTED, "a fainted Shuckie is refused")
  list[1].hp = 20
  list[1].happiness = 150
  Specials.HANDLERS.ReturnShuckie(vm2)
  eq(vm2.scriptVar, Specials.SHUCKIE_HAPPY,
    "150+ happiness and Mania lets you keep it")
  eq(#list, 1, "so the party slot is untouched")
  list[1].happiness = 149
  Specials.HANDLERS.ReturnShuckie(vm2)
  eq(vm2.scriptVar, Specials.SHUCKIE_RETURNED, "and the real one goes back")
  eq(#list, 0, "leaving the party")
  hooks2.selectPartyMon = function(_, done) done(nil, nil) end
  Specials.HANDLERS.ReturnShuckie(vm2)
  eq(vm2.scriptVar, Specials.SHUCKIE_REFUSED, "B backs out")
end

-- CalcMagikarpLength, bug and all.  The two ends of the routine are what pin
-- it: bc < 10 is the +190 special case, and everything else lands through the
-- underflowing table walk.
do
  local feet, inches, mm = Specials.magikarpLength(0, 0)
  eq(mm, 190, "an all-zero ID and DV word is the 190 mm floor")
  eq(feet, 0, "which is 0 feet")
  eq(inches, 7, "and 7 inches")
  local _, _, mm2 = Specials.magikarpLength(0x1234, 0x5678)
  check(mm2 > 0 and mm2 < 65536, "a real pair produces a length in range")
  eq(Specials.magikarpLengthText(4, 2), [[4'2"]], "and it prints as feet'inches")
  eq(Specials.dvWord({ attack = 15, defense = 15, speed = 15, special = 15 }),
    0xffff, "the DV word packs attack/defense/speed/special into 16 bits")
end

-- CheckMagikarpLength's four answers, and the record it keeps.
do
  local record = { player = { name = "GOLD" } }
  local karp = { species = "MAGIKARP", otId = 1000,
    dvs = { attack = 15, defense = 15, speed = 15, special = 15 } }
  local chosen = karp
  local vm = specialVm(0, { order = { "x" }, hooks = {
    save = function() return record end,
    party = function() return { karp } end,
    monName = function(sp) return sp end,
    selectPartyMon = function(_, done) done(1, chosen) end } })
  Specials.HANDLERS.CheckMagikarpLength(vm)
  eq(vm.scriptVar, 3, "a first measurement always beats the record")
  check(record.magikarpRecord ~= nil, "and is written down")
  Specials.HANDLERS.CheckMagikarpLength(vm)
  eq(vm.scriptVar, 2, "measuring the same fish again does not beat it")
  chosen = { species = "CHIKORITA" }
  Specials.HANDLERS.CheckMagikarpLength(vm)
  eq(vm.scriptVar, 0, "a mon that is not a MAGIKARP answers 0")
  chosen = nil
  Specials.HANDLERS.CheckMagikarpLength(vm)
  eq(vm.scriptVar, 1, "and B answers 1")
  Specials.HANDLERS.MagikarpHouseSign(vm)
  check(vm.stringBuffer:find("'", 1, true) ~= nil,
    "the house sign prints the record on the wall")
end

-- SnorlaxAwake needs BOTH halves: the flute channel playing, and the player on
-- one of the five cells beside it.
do
  local song, cell = nil, { 0, 0 }
  local vm = specialVm(0, { order = { "x" }, hooks = {
    currentMusic = function() return song end,
    playerCell = function() return cell[1], cell[2] end } })
  Specials.HANDLERS.SnorlaxAwake(vm)
  eq(vm.scriptVar, 0, "no flute, no waking")
  song = Specials.POKE_FLUTE_SONG
  Specials.HANDLERS.SnorlaxAwake(vm)
  eq(vm.scriptVar, 0, "the flute alone is not enough from across the room")
  cell = { 34, 10 }
  Specials.HANDLERS.SnorlaxAwake(vm)
  eq(vm.scriptVar, 1, "the flute NEXT TO it wakes it")
end

-- InitRoamMons puts all three beasts out, with hp 0 meaning "roll stats when
-- it is first met".
do
  local record = {}
  local vm = specialVm(0, { order = { "x" },
    hooks = { save = function() return record end } })
  Specials.HANDLERS.InitRoamMons(vm)
  eq(#record.roamers, 3, "three roamers")
  eq(record.roamers[1].species, "RAIKOU", "RAIKOU first")
  eq(record.roamers[1].map, "ROUTE_42", "on ROUTE 42")
  eq(record.roamers[3].species, "SUICUNE", "SUICUNE third")
  eq(record.roamers[2].level, 40, "all at level 40")
  eq(record.roamers[1].hp, 0, "with no stats rolled yet")
end

-- The two Game Corner machines are CheckCoinsAndCoinCase and then the game:
-- both refusals are TEXT, and the machine must not open behind either.
do
  local shown, opened = {}, nil
  local coins, hasCase = 0, true
  local vm = specialVm(0, { order = { "SlotMachine" }, hooks = {
    coins = function() return coins end,
    hasItem = function() return hasCase end,
    gameCornerGame = function(kind, done) opened = kind done() end } })
  -- showRaw YIELDS its page, so the refusal is the request the coroutine
  -- parks on rather than a call: reading it off the yield is what proves the
  -- machine never opened behind the line.
  vm.showTextFn = function() end
  vm.co = coroutine.create(function()
    Specials.HANDLERS.SlotMachine(vm)
  end)
  local _, req = coroutine.resume(vm.co)
  shown[#shown + 1] = req and req.text
  eq(shown[1], "You have no coins.", "_NoCoinsText is the refusal")
  check(opened == nil, "no coins: the machine does not open")
  coins, hasCase = 100, false
  opened = nil
  vm.co = coroutine.create(function() Specials.HANDLERS.CardFlip(vm) end)
  local _, req2 = coroutine.resume(vm.co)
  eq(req2 and req2.text, "You don't have a\nCOIN CASE.",
    "_NoCoinCaseText is the other one")
  check(opened == nil, "no COIN CASE: the machine does not open either")
  coins, hasCase = 100, true
  vm.co = coroutine.create(function() Specials.HANDLERS.CardFlip(vm) end)
  coroutine.resume(vm.co)
  eq(opened, "cardflip", "with both, the machine opens")
end

-- Specials.block is the whole blocking contract, and both halves of it matter.
-- A hook that answers ON THE SPOT must not yield (resuming a coroutine that is
-- still running is an error); a hook that answers LATER must park the script
-- so nothing behind it runs until the screen closes.
do
  local vm = specialVm(0, { order = { "x" }, hooks = {} })
  local ran = false
  vm.co = coroutine.create(function()
    local value = Specials.block(vm, function(done) done(42) end)
    ran = (value == 42)
  end)
  coroutine.resume(vm.co)
  check(ran, "a synchronous hook returns without yielding")
  check(coroutine.status(vm.co) == "dead", "and the handler runs to the end")

  local finish
  local after = false
  local vm2 = specialVm(0, { order = { "x" }, hooks = {} })
  vm2.busy = true
  vm2.co = coroutine.create(function()
    local value = Specials.block(vm2, function(done) finish = done end)
    after = (value == 7)
  end)
  coroutine.resume(vm2.co)
  check(coroutine.status(vm2.co) == "suspended", "an async hook parks the script")
  check(not after, "and nothing behind it has run")
  finish(7)
  check(after, "the screen's own callback is what resumes it")
end

-- The Day Care doors all reach the same screen with a different side, and only
-- DayCareManOutside's answer is read back (TRUE = the party was full).
do
  local asked = {}
  local reply = 0
  local vm = specialVm(0, { order = { "x" }, hooks = {
    dayCare = function(side, done) asked[#asked + 1] = side done(reply) end } })
  vm.co = coroutine.create(function()
    Specials.HANDLERS.DayCareMan(vm)
  end)
  coroutine.resume(vm.co)
  eq(asked[1], "man", "DayCareMan opens the man's side")
  eq(vm.scriptVar, 0, "and answers 0")
  reply = 1
  vm.co = coroutine.create(function()
    Specials.HANDLERS.DayCareManOutside(vm)
  end)
  coroutine.resume(vm.co)
  eq(asked[2], "outside", "DayCareManOutside opens the egg hand-off")
  eq(vm.scriptVar, 1, "and carries its TRUE back into wScriptVar")
end

-- A stub is not a hole: each one leaves the value its routine's "nothing
-- happened" arm leaves, so the branch two commands later is right.
do
  local vm = specialVm(0, { order = { "x" }, hooks = {} })
  vm.scriptVar = 99
  Specials.STUBS.CheckMysteryGift(vm)
  eq(vm.scriptVar, 0, "CheckMysteryGift says there is no gift waiting")
end
check(Specials.STUBS.TrainerHouse == nil,
  "TrainerHouse is a HANDLER, not a stub: sMysteryGiftTrainerHouseFlag is " ..
  "honestly 0 without a link cable, so the routine is right rather than " ..
  "merely absent")
do
  local vm = specialVm(0, { order = { "x" }, hooks = {} })
  vm.scriptVar = 99
  Specials.STUBS.CloseLink(vm)
  eq(vm.scriptVar, 99,
    "CloseLink writes no wScriptVar, so the stub does not invent one")
end

-- ---- the Blackthorn move deleter -------------------------------------------
--
-- MoveDeletion is a HANDLER, not a stub: it drives its own conversation
-- through the yielding text/yesorno primitives rather than through a hook
-- that answers on the spot, so this drives it the way the SlotMachine and
-- Specials.block tests above do -- one coroutine.resume per yield, feeding
-- each `yesorno` its answer off a queue and letting every `text`/`waitsfx`
-- yield pass through with nothing to say back.
check(Specials.STUBS.MoveDeletion == nil,
  "MoveDeletion is a HANDLER: the screen it needed now exists")

local function driveMoveDeletion(vm, yesAnswers)
  local texts = {}
  local qi = 0
  local resumeArg = nil
  local ok, req = coroutine.resume(vm.co, resumeArg)
  while true do
    if not ok then error(req) end
    if req and req.kind == "text" then texts[#texts + 1] = req.text end
    if coroutine.status(vm.co) == "dead" then break end
    resumeArg = nil
    if req and req.kind == "yesorno" then
      qi = qi + 1
      resumeArg = yesAnswers[qi]
    end
    ok, req = coroutine.resume(vm.co, resumeArg)
  end
  return texts
end

-- Declining the very first "shall I make a #MON forget?" never reaches the
-- party list at all.
do
  local vm = specialVm(0, { order = { "x" }, hooks = {} })
  vm.showTextFn = function() end
  vm.co = coroutine.create(function() Specials.HANDLERS.MoveDeletion(vm) end)
  local texts = driveMoveDeletion(vm, { false })
  eq(#texts, 2, "the intro and the decline line, nothing more")
  check(texts[2]:find("No?", 1, true) ~= nil,
    "the decline line is _DeleterNoComeAgainText")
end

-- An egg has no moves to forget: `cp EGG` before the move count is even read.
do
  local egg = { isEgg = true, moves = {} }
  local vm = specialVm(0, { order = { "x" }, hooks = {
    selectPartyMon = function(_prompt, done) done(1, egg) end,
  } })
  vm.showTextFn = function() end
  vm.co = coroutine.create(function() Specials.HANDLERS.MoveDeletion(vm) end)
  local texts = driveMoveDeletion(vm, { true })
  check(texts[#texts]:find("EGG", 1, true) ~= nil,
    "the egg line is _DeleterEggText")
end

-- One move known: `.onlyonemove` fires before ChooseMoveToDelete ever opens.
do
  local mon = { moves = { { id = "TACKLE", pp = 35, maxPp = 35 } } }
  local opened = false
  local vm = specialVm(0, { order = { "x" }, hooks = {
    selectPartyMon = function(_prompt, done) done(1, mon) end,
    chooseMoveToDelete = function(_mon, done) opened = true done(nil) end,
  } })
  vm.showTextFn = function() end
  vm.co = coroutine.create(function() Specials.HANDLERS.MoveDeletion(vm) end)
  local texts = driveMoveDeletion(vm, { true })
  check(texts[#texts]:find("only one move", 1, true) ~= nil,
    "the one-move line is _MoveKnowsOneText")
  check(not opened, "ChooseMoveToDelete never opens for a one-move mon")
end

-- Backing out of the move list itself (B in ChooseMoveToDelete) declines the
-- same way backing out of the mon list does.
do
  local mon = { moves = {
    { id = "TACKLE", pp = 35, maxPp = 35 },
    { id = "GROWL", pp = 40, maxPp = 40 },
  } }
  local vm = specialVm(0, { order = { "x" }, hooks = {
    selectPartyMon = function(_prompt, done) done(1, mon) end,
    chooseMoveToDelete = function(_mon, done) done(nil) end,
  } })
  vm.showTextFn = function() end
  vm.co = coroutine.create(function() Specials.HANDLERS.MoveDeletion(vm) end)
  local texts = driveMoveDeletion(vm, { true })
  check(texts[#texts]:find("No?", 1, true) ~= nil,
    "backing out of the move list reads as a decline")
  eq(#mon.moves, 2, "and nothing was deleted")
end

-- The whole path: pick a mon, pick GROWL (slot 2 of 2), confirm, and it is
-- gone -- shifted out of the array the same way .DeleteMove shifts the PP
-- array beside it, since both live in the one `moves` entry here.
do
  local mon = { moves = {
    { id = "TACKLE", pp = 35, maxPp = 35 },
    { id = "GROWL", pp = 40, maxPp = 40 },
  } }
  local sfxPlayed, sfxFallback = nil, nil
  local vm = specialVm(0, { order = { "x" }, hooks = {
    selectPartyMon = function(_prompt, done) done(1, mon) end,
    chooseMoveToDelete = function(chosen, done)
      check(chosen == mon, "the move list opens on the mon SelectMonFromParty picked")
      done(2)
    end,
    playSfxNamed = function(name, fallback)
      sfxPlayed, sfxFallback = name, fallback
    end,
  } })
  vm.data = function() return { moves = { GROWL = { name = "GROWL" } } } end
  -- specialVm wires data() through nothing today, so H.MoveDeletion's own
  -- `data(vm)` (hooks(vm).data) needs the same hook the party/save readers
  -- use; specialVm has no `data` opt, so this reaches in directly.
  vm.specials.data = function() return { moves = { GROWL = { name = "GROWL" } } } end
  vm.showTextFn = function() end
  vm.co = coroutine.create(function() Specials.HANDLERS.MoveDeletion(vm) end)
  local texts = driveMoveDeletion(vm, { true, true })
  check(texts[#texts]:find("forgot the move", 1, true) ~= nil,
    "the last line is _DeleterForgotMoveText")
  eq(#mon.moves, 1, "GROWL is gone")
  eq(mon.moves[1].id, "TACKLE", "TACKLE, the move that was not picked, stays")
  eq(sfxPlayed, "Sfx_MoveDeleted", "the deletion jingle is asked for by label")
  eq(sfxFallback, 97, "and its SFX_MOVE_DELETED index is the fallback")
end

-- ---- the Goldenrod NAME RATER ----------------------------------------------
--
-- Same drive shape as driveMoveDeletion above: NameRater is a HANDLER, so it
-- yields through the same text/yesorno primitives rather than answering a
-- hook on the spot.
check(Specials.STUBS.NameRater == nil,
  "NameRater is a HANDLER: the keyboard it needed now exists")

local function driveNameRater(vm, yesAnswers)
  local texts = {}
  local qi = 0
  local resumeArg = nil
  local ok, req = coroutine.resume(vm.co, resumeArg)
  while true do
    if not ok then error(req) end
    if req and req.kind == "text" then texts[#texts + 1] = req.text end
    if coroutine.status(vm.co) == "dead" then break end
    resumeArg = nil
    if req and req.kind == "yesorno" then
      qi = qi + 1
      resumeArg = yesAnswers[qi]
    end
    ok, req = coroutine.resume(vm.co, resumeArg)
  end
  return texts
end

local PLAYER_HOOK = { save = function()
  return { player = { name = "CHRIS", id = 12345 } }
end }

-- Declining the very first "would you like me to rate names?" never reaches
-- the party list at all.
do
  local vm = specialVm(0, { order = { "x" }, hooks = PLAYER_HOOK })
  vm.showTextFn = function() end
  vm.co = coroutine.create(function() Specials.HANDLERS.NameRater(vm) end)
  local texts = driveNameRater(vm, { false })
  eq(#texts, 2, "the intro and the decline line, nothing more")
  check(texts[2]:find("Come", 1, true) ~= nil,
    "the decline line is _NameRaterComeAgainText")
end

-- Backing out of SelectMonFromParty (B) reads the same as declining.
do
  local hooks = {
    save = PLAYER_HOOK.save,
    selectPartyMon = function(_prompt, done) done(nil, nil) end,
  }
  local vm = specialVm(0, { order = { "x" }, hooks = hooks })
  vm.showTextFn = function() end
  vm.co = coroutine.create(function() Specials.HANDLERS.NameRater(vm) end)
  local texts = driveNameRater(vm, { true })
  check(texts[#texts]:find("Come", 1, true) ~= nil,
    "backing out of the party list reads as a decline")
end

-- `cp EGG`: an egg's nickname is never up for rating.
do
  local egg = { isEgg = true, nickname = "EGG" }
  local hooks = {
    save = PLAYER_HOOK.save,
    selectPartyMon = function(_prompt, done) done(1, egg) end,
  }
  local vm = specialVm(0, { order = { "x" }, hooks = hooks })
  vm.showTextFn = function() end
  vm.co = coroutine.create(function() Specials.HANDLERS.NameRater(vm) end)
  local texts = driveNameRater(vm, { true })
  check(texts[#texts]:find("EGG", 1, true) ~= nil,
    "the egg line is _NameRaterEggText")
end

-- CheckIfMonIsYourOT: a mon whose OT name or id differs from the player's
-- gets the refusal and never reaches the "how about a better name?" prompt.
do
  local traded = { name = "GOLDUCK", nickname = "PSY", ot = "RIVAL", otId = 999 }
  local hooks = {
    save = PLAYER_HOOK.save,
    selectPartyMon = function(_prompt, done) done(1, traded) end,
    renameMon = function() error("the traded arm must never open the keyboard") end,
  }
  local vm = specialVm(0, { order = { "x" }, hooks = hooks })
  vm.showTextFn = function() end
  vm.co = coroutine.create(function() Specials.HANDLERS.NameRater(vm) end)
  local texts = driveNameRater(vm, { true })
  check(texts[#texts]:find("perfect", 1, true) ~= nil,
    "the traded line is _NameRaterPerfectNameText")
  check(texts[#texts]:find("PSY", 1, true) ~= nil,
    "and it names the mon by its current nickname via {STRBUF}")
end

-- A mon with no `ot` / `otId` at all (Mon.new sets neither) reads as the
-- player's own, the same way H.FindPartyMonThatSpeciesYourTrainerID treats a
-- nil otId as a match.
do
  local mine = { name = "TOTODILE", nickname = "TOTO" }
  local hooks = {
    save = PLAYER_HOOK.save,
    selectPartyMon = function(_prompt, done) done(1, mine) end,
  }
  local vm = specialVm(0, { order = { "x" }, hooks = hooks })
  vm.showTextFn = function() end
  vm.co = coroutine.create(function() Specials.HANDLERS.NameRater(vm) end)
  local texts = driveNameRater(vm, { false })
  check(texts[#texts]:find("Come", 1, true) ~= nil,
    "declining the better-name offer for your own mon is a plain decline")
end

-- The whole rename path: a new, different name is copied onto the mon and
-- both NamedText and FinishedText print, in that order.
do
  local mine = { name = "CYNDAQUIL", nickname = "CINDY" }
  local hooks = {
    save = PLAYER_HOOK.save,
    selectPartyMon = function(_prompt, done) done(1, mine) end,
    renameMon = function(mon, done)
      check(mon == mine, "renameMon opens on the mon SelectMonFromParty picked")
      done("BLAZE")
    end,
  }
  local vm = specialVm(0, { order = { "x" }, hooks = hooks })
  vm.showTextFn = function() end
  vm.co = coroutine.create(function() Specials.HANDLERS.NameRater(vm) end)
  local texts = driveNameRater(vm, { true, true })
  eq(mine.nickname, "BLAZE", "the new name is copied onto the party mon")
  check(texts[#texts - 1]:find("BLAZE", 1, true) ~= nil,
    "NamedText prints the new name via {STRBUF}")
  check(texts[#texts]:find("better", 1, true) ~= nil,
    "and FinishedText follows it")
end

-- IsNewNameEmpty: a blank keyboard entry is treated as unchanged, not as a
-- second decline -- SameNameText prints, and the nickname is untouched.
do
  local mine = { name = "CYNDAQUIL", nickname = "CINDY" }
  local hooks = {
    save = PLAYER_HOOK.save,
    selectPartyMon = function(_prompt, done) done(1, mine) end,
    renameMon = function(_mon, done) done("   ") end,
  }
  local vm = specialVm(0, { order = { "x" }, hooks = hooks })
  vm.showTextFn = function() end
  vm.co = coroutine.create(function() Specials.HANDLERS.NameRater(vm) end)
  local texts = driveNameRater(vm, { true, true })
  eq(mine.nickname, "CINDY", "a blank entry leaves the old nickname in place")
  check(texts[#texts - 1]:find("CINDY", 1, true) ~= nil,
    "NamedText re-prints the OLD name, unchanged")
  check(texts[#texts]:find("same as before", 1, true) ~= nil,
    "and SameNameText follows it rather than FinishedText")
end

-- CompareNewToOld: retyping the identical name is the same "unchanged" arm
-- as a blank entry, not a second decline.
do
  local mine = { name = "CYNDAQUIL", nickname = "CINDY" }
  local hooks = {
    save = PLAYER_HOOK.save,
    selectPartyMon = function(_prompt, done) done(1, mine) end,
    renameMon = function(_mon, done) done("CINDY") end,
  }
  local vm = specialVm(0, { order = { "x" }, hooks = hooks })
  vm.showTextFn = function() end
  vm.co = coroutine.create(function() Specials.HANDLERS.NameRater(vm) end)
  local texts = driveNameRater(vm, { true, true })
  eq(mine.nickname, "CINDY", "retyping the same name is a no-op")
  check(texts[#texts]:find("same as before", 1, true) ~= nil,
    "and SameNameText prints, exactly as an empty entry does")
end

-- Backing out of the keyboard itself (B in NamingScreen) declines the same
-- way backing out of the mon list does.
do
  local mine = { name = "CYNDAQUIL", nickname = "CINDY" }
  local hooks = {
    save = PLAYER_HOOK.save,
    selectPartyMon = function(_prompt, done) done(1, mine) end,
    renameMon = function(_mon, done) done(nil) end,
  }
  local vm = specialVm(0, { order = { "x" }, hooks = hooks })
  vm.showTextFn = function() end
  vm.co = coroutine.create(function() Specials.HANDLERS.NameRater(vm) end)
  local texts = driveNameRater(vm, { true, true })
  eq(mine.nickname, "CINDY", "nothing was renamed")
  check(texts[#texts]:find("same as before", 1, true) ~= nil,
    "a nil name from the keyboard reads as blank, not as a decline")
end

-- ---- the #DEX-completion diploma -------------------------------------------
--
-- H.Diploma just parks on World:showDiploma and resumes once the screen
-- calls its onDone -- it never touches wScriptVar, matching _Diploma's own
-- asm (no `ld [wScriptVar], a` anywhere in the routine).
do
  local opened = false
  local hooks = {
    showDiploma = function(onDone)
      opened = true
      onDone()
    end,
  }
  local vm = specialVm(0, { order = { "x" }, hooks = hooks, scriptVar = 7 })
  vm.co = coroutine.create(function() Specials.HANDLERS.Diploma(vm) end)
  local ok, err = coroutine.resume(vm.co)
  check(ok, "H.Diploma runs to completion: " .. tostring(err))
  check(opened, "H.Diploma calls World:showDiploma via the specials hooks")
  eq(vm.scriptVar, 7, "the special never writes wScriptVar")
end

-- A missing hook (no screen) is a safe no-op, the same degrade every other
-- screen-opening special takes when its id is not registered.
do
  local vm = specialVm(0, { order = { "x" }, hooks = {}, scriptVar = 3 })
  vm.co = coroutine.create(function() Specials.HANDLERS.Diploma(vm) end)
  local ok, err = coroutine.resume(vm.co)
  check(ok, "H.Diploma tolerates a missing showDiploma hook: " .. tostring(err))
  eq(vm.scriptVar, 3, "and still leaves wScriptVar untouched")
end

-- ---- the Cianwood photo studio ---------------------------------------------
--
-- H.PhotoStudio never touches wScriptVar, matching PhotoStudio's own asm (no
-- `ld [wScriptVar], a` anywhere in the routine) -- so every case below checks
-- vm.scriptVar is left exactly where specialVm set it, the same way the
-- Diploma tests above do.
local function drivePhotoStudio(vm)
  local texts = {}
  local ok, req = coroutine.resume(vm.co, nil)
  while true do
    if not ok then error(req) end
    if req and req.kind == "text" then texts[#texts + 1] = req.text end
    if coroutine.status(vm.co) == "dead" then break end
    ok, req = coroutine.resume(vm.co, nil)
  end
  return texts
end

check(Specials.STUBS.PhotoStudio == nil,
  "PhotoStudio is a HANDLER now: the conversation and the portrait card exist")
check(Specials.HANDLERS.PhotoStudio ~= nil,
  "and it is the one that special dispatch resolves to")
check(Specials.STUBS.PrintDiploma ~= nil,
  "PrintDiploma stays stubbed -- it is nothing but the print, with no screen "
  .. "half of its own")
check(Specials.STUBS.UnownPrinter == nil
  and Specials.HANDLERS.UnownPrinter ~= nil,
  "UnownPrinter is a handler for the same reason this one is: the stamp "
  .. "viewer is drawn on the cartridge and only the A press wanted a printer")

-- Backing out of the party list (B in SelectMonFromParty) reads as a decline,
-- the same way MoveDeletion and NameRater treat it above.
do
  local opened = false
  local vm = specialVm(0, { order = { "x" }, hooks = {
    selectPartyMon = function(_prompt, done) done(nil, nil) end,
    showPhotoStudio = function(_mon, done) opened = true done() end,
  }, scriptVar = 5 })
  vm.showTextFn = function() end
  vm.co = coroutine.create(function() Specials.HANDLERS.PhotoStudio(vm) end)
  local texts = drivePhotoStudio(vm)
  eq(#texts, 2, "the which-mon prompt and the no-photo line, nothing more")
  check(texts[1]:find("photo", 1, true) ~= nil, "the first line is _WhichMonPhotoText")
  check(texts[2]:find("no picture", 1, true) ~= nil,
    "declining reads the same _NoPhotoText the printer-error arm would")
  check(not opened, "the portrait screen never opens for a declined pick")
  eq(vm.scriptVar, 5, "the special never writes wScriptVar")
end

-- An egg: `cp EGG` before the camera ever opens.
do
  local egg = { isEgg = true }
  local opened = false
  local vm = specialVm(0, { order = { "x" }, hooks = {
    selectPartyMon = function(_prompt, done) done(1, egg) end,
    showPhotoStudio = function(_mon, done) opened = true done() end,
  } })
  vm.showTextFn = function() end
  vm.co = coroutine.create(function() Specials.HANDLERS.PhotoStudio(vm) end)
  local texts = drivePhotoStudio(vm)
  check(texts[#texts]:find("EGG", 1, true) ~= nil, "the egg line is _EggPhotoText")
  check(not opened, "an egg never reaches the portrait screen either")
end

-- The full path: a real mon picked, the portrait screen opens for the "hold
-- still" beat, and the print always comes back as a no-photo -- there is no
-- Game Boy Printer to answer with a success, see the handler's header.
do
  local mon = { species = "CYNDAQUIL", nickname = "CINDY" }
  local opened, seenMon = false, nil
  local vm = specialVm(0, { order = { "x" }, hooks = {
    selectPartyMon = function(_prompt, done) done(1, mon) end,
    showPhotoStudio = function(picked, done)
      opened = true
      seenMon = picked
      done()
    end,
  } })
  vm.showTextFn = function() end
  vm.co = coroutine.create(function() Specials.HANDLERS.PhotoStudio(vm) end)
  local texts = drivePhotoStudio(vm)
  eq(#texts, 3, "which-mon, hold-still, and the printer-arm's no-photo line")
  check(texts[2]:find("Hold", 1, true) ~= nil, "the middle line is _HoldStillText")
  check(texts[3]:find("no picture", 1, true) ~= nil,
    "hPrinter is hardwired to the error arm: no peripheral, so no success text")
  check(opened, "the portrait screen opens for the picked mon")
  eq(seenMon, mon, "showPhotoStudio gets the exact mon SelectMonFromParty picked")
end

-- A missing hook (no screen) is a safe no-op, the same degrade every other
-- screen-opening special takes when its id is not registered.
do
  local mon = { species = "CYNDAQUIL" }
  local vm = specialVm(0, { order = { "x" }, hooks = {
    selectPartyMon = function(_prompt, done) done(1, mon) end,
  } })
  vm.showTextFn = function() end
  vm.co = coroutine.create(function() Specials.HANDLERS.PhotoStudio(vm) end)
  local ok, err = pcall(drivePhotoStudio, vm)
  check(ok, "H.PhotoStudio tolerates a missing showPhotoStudio hook: "
    .. tostring(err))
end

-- ---- PROF.OAK's PC #DEX rating ---------------------------------------------
--
-- ProfOaksPCBoot is a HANDLER, not a stub: it drives three text pages and a
-- fanfare through the same yielding primitives MoveDeletion/NameRater above
-- use, so this drives it the same way -- one resume per yield, with no
-- yesorno to answer (the yes/no gate lives in ProfOaksPC, which has no call
-- site here) and the `waitsfx` yield at the end passed straight through.
check(Specials.STUBS.ProfOaksPCBoot == nil,
  "ProfOaksPCBoot is a HANDLER: the seen/owned counts and rating table exist")

local function driveOaksPC(vm)
  local texts = {}
  local ok, req = coroutine.resume(vm.co, nil)
  while true do
    if not ok then error(req) end
    if req and req.kind == "text" then texts[#texts + 1] = req.text end
    if coroutine.status(vm.co) == "dead" then break end
    ok, req = coroutine.resume(vm.co, nil)
  end
  return texts
end

-- An empty dex: 0 seen, 0 caught, the lowest band (OakRating01, "Look for
-- #MON in grassy areas!").
do
  local hooks = { save = function()
    return { pokedex = { seen = {}, caught = {} } }
  end }
  local vm = specialVm(0, { order = { "x" }, hooks = hooks })
  vm.showTextFn = function() end
  vm.co = coroutine.create(function() Specials.HANDLERS.ProfOaksPCBoot(vm) end)
  local texts = driveOaksPC(vm)
  eq(#texts, 3, "the completion-level page, the seen/owned page, and the rating")
  check(texts[1]:find("completion level", 1, true) ~= nil,
    "page 1 is _OakPCText2")
  check(texts[2]:find("0 #MON seen", 1, true) ~= nil,
    "page 2 leads with the seen count, formatted in place of wStringBuffer3")
  check(texts[2]:find("0 #MON owned", 1, true) ~= nil,
    "and the owned count in place of wStringBuffer4")
  check(texts[3]:find("grassy areas", 1, true) ~= nil,
    "0 caught lands on OakRating01, the first row FindOakRating can match")
end

-- FindOakRating's ascending-cap walk: 9 caught lands on the SAME band as 0
-- (both <= 9, OakRating01), 10 caught crosses into the next one
-- (OakRating02, "understand how to use # BALLS").
do
  local function seenCaught(n)
    local caught = {}
    for i = 1, n do caught["MON" .. i] = true end
    return { pokedex = { seen = {}, caught = caught } }
  end
  local sfxPlayed = nil
  local hooks = {
    save = function() return seenCaught(9) end,
    playSfxNamed = function(name) sfxPlayed = name end,
  }
  local vm = specialVm(0, { order = { "x" }, hooks = hooks })
  vm.showTextFn = function() end
  vm.co = coroutine.create(function() Specials.HANDLERS.ProfOaksPCBoot(vm) end)
  local texts = driveOaksPC(vm)
  check(texts[3]:find("grassy areas", 1, true) ~= nil,
    "9 caught is still inside the first band's cap")
  eq(sfxPlayed, "Sfx_DexFanfareLessThan20",
    "and its fanfare is the Gold sfx label, not a pokered name")
end

do
  local caught = {}
  for i = 1, 10 do caught["MON" .. i] = true end
  local hooks = { save = function()
    return { pokedex = { seen = {}, caught = caught } }
  end }
  local vm = specialVm(0, { order = { "x" }, hooks = hooks })
  vm.showTextFn = function() end
  vm.co = coroutine.create(function() Specials.HANDLERS.ProfOaksPCBoot(vm) end)
  local texts = driveOaksPC(vm)
  check(texts[3]:find("# BALLS", 1, true) ~= nil,
    "10 caught crosses the first cap into OakRating02")
end

-- The top band: every count from 240 up through a full 251-species dex reads
-- the same "perfect #DEX" line and the same top fanfare -- the table's own
-- cap of 255 is never reached by a real save, so this is the row that never
-- changes again once the player is this close to done.
do
  local caught = {}
  for i = 1, 251 do caught["MON" .. i] = true end
  local seen = {}
  for i = 1, 251 do seen["MON" .. i] = true end
  local sfxPlayed = nil
  local hooks = {
    save = function() return { pokedex = { seen = seen, caught = caught } } end,
    playSfxNamed = function(name) sfxPlayed = name end,
  }
  local vm = specialVm(0, { order = { "x" }, hooks = hooks })
  vm.showTextFn = function() end
  vm.co = coroutine.create(function() Specials.HANDLERS.ProfOaksPCBoot(vm) end)
  local texts = driveOaksPC(vm)
  check(texts[2]:find("251 #MON seen", 1, true) ~= nil,
    "a full dex counts every `true` entry in save.pokedex.seen")
  check(texts[2]:find("251 #MON owned", 1, true) ~= nil, "and .caught")
  check(texts[3]:find("perfect", 1, true) ~= nil,
    "251 caught is OakRating19, the table's last row")
  eq(sfxPlayed, "Sfx_DexFanfare230Plus",
    "sharing the top fanfare with the last few bands below it")
  -- This special never touches Diploma or EVENT_ENABLE_DIPLOMA_PRINTING --
  -- that is Celadon Mansion 3F's GameFreakGameDesignerScript, reading
  -- VAR_DEXCAUGHT on its own -- so completing the dex here does not, on its
  -- own, open the diploma screen.  Diploma is now a real handler
  -- (src/ui/gen2/Diploma.lua), not a stub.
  check(Specials.STUBS.Diploma == nil,
    "Diploma is a real handler now, not a stub")
  check(Specials.HANDLERS.Diploma ~= nil,
    "and it is the one that special dispatch resolves to")
end

-- ---- itemnotify names the item and its own pocket --------------------------
--
-- Script_itemnotify is GetPocketName + CurItemName off wCurItem
-- (engine/overworld/scripting.asm:460), and _PutItemInPocketText's two blanks
-- are wStringBuffer1 (the item) and wStringBuffer3 (the pocket)
-- (data/text/common_2.asm:1351).  Neither reads the shared {STRBUF} stand-in,
-- which is exactly the trap maps/MrPokemonsHouse.asm:31-35 sets: a `getstring`
-- for MAP CARD sits a few rows above the `giveitem MYSTERY_EGG / itemnotify`
-- pair, so a port that printed the buffer would announce the MAP CARD.
do
  local function notifyBox(pocketFor)
    local log = {}
    local vm = Vm.new({
      generation = 2,
      ["s:gift"] = {
        { op = "getstring", string = "MAP CARD" },
        { op = "giveitem", item = 69, quantity = 1 },
        { op = "itemnotify" },
        { op = "end" },
      },
    }, {}, Events.new(), {
      showText = function(body, onDone)
        log[#log + 1] = body
        onDone()
      end,
      giveItem = function() return true end,
      getItemName = function(index)
        if index == 7 then return "MAP CARD" end
        if index == 69 then return "MYSTERY EGG" end
        return "?"
      end,
      getItemPocket = pocketFor,
    })
    check(vm:start("s:gift"), "the Mr. POKEMON gift script starts")
    for _ = 1, 20 do vm:update() end
    return log[1]
  end

  eq(notifyBox(function(index) return index == 69 and "KEY_ITEM" or nil end),
    "{PLAYER} put the\nMYSTERY EGG in\nthe KEY POCKET.",
    "itemnotify names wCurItem and its pocket, not the stale getstring")
  eq(notifyBox(function() return "TM_HM" end),
    "{PLAYER} put the\nMYSTERY EGG in\nthe TM POCKET.",
    "a TM_HM item names the TM POCKET")
  eq(notifyBox(function() return "BALL" end),
    "{PLAYER} put the\nMYSTERY EGG in\nthe BALL POCKET.",
    "and a BALL names the BALL POCKET")
end

S.finish()
