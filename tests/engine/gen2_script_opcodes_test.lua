-- Gen 2 script bytecode dialects: Gold/Silver vs Crystal.
--
-- Crystal inserts farjumptext at $52 and pushes every later opcode up by one
-- (pokecrystal/macros/scripts/events.asm:541).  Decoding a Crystal script with
-- the Gold table is silent: a Crystal $53 `jumptext` (2 operand bytes) reads as
-- Gold's `waitbutton` (0), the pointer walk desynchronises, and the extractor
-- emits plausible garbage rather than an error.  So the expected tables below
-- are transcribed from the two macro files by hand and pinned here.
--   luajit tests/engine/gen2_script_opcodes_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check = T.check
local eq = T.eq

local Opcodes = require("src.script.gen2.Opcodes")

-- pokegold/macros/scripts/events.asm:1-1015, in const order from $00.
-- Sizes are the macro body minus its own `db <name>_command`: db 1, dw 2,
-- dba 3, bigdt 3, map_id 2 (pokegold/macros/scripts/maps.asm:1-6).
-- `givepoke` is the one variable-length row: the macro emits 8 bytes when the
-- trainer argument is non-zero (events.asm:352-365) and the table declares the
-- 4-byte base, which src/import/RomExtractorGen2.lua re-measures per call site.
local GOLD_EXPECTED = {
  "scall 2", "farscall 3", "memcall 2", "sjump 2", "farsjump 3",
  "memjump 2", "ifequal 3", "ifnotequal 3", "iffalse 2", "iftrue 2",
  "ifgreater 3", "ifless 3", "jumpstd 2", "callstd 2", "callasm 3",
  "special 2", "memcallasm 2", "checkmapscene 2", "setmapscene 3",
  "checkscene 0", "setscene 1", "setval 1", "addval 1", "random 1",
  "checkver 0", "readmem 2", "writemem 2", "loadmem 3", "readvar 1",
  "writevar 1", "loadvar 2", "giveitem 2", "takeitem 2", "checkitem 1",
  "givemoney 4", "takemoney 4", "checkmoney 4", "givecoins 2",
  "takecoins 2", "checkcoins 2", "addcellnum 1", "delcellnum 1",
  "checkcellnum 1", "checktime 1", "checkpoke 1", "givepoke 4",
  "giveegg 2", "givepokemail 2", "checkpokemail 2", "checkevent 2",
  "clearevent 2", "setevent 2", "checkflag 2", "clearflag 2", "setflag 2",
  "wildon 0", "wildoff 0", "xycompare 2", "warpmod 3", "blackoutmod 2",
  "warp 4", "getmoney 2", "getcoins 1", "getnum 1", "getmonname 2",
  "getitemname 2", "getcurlandmarkname 1", "gettrainername 3",
  "getstring 3", "itemnotify 0", "pocketisfull 0", "opentext 0",
  "reanchormap 1", "closetext 0", "writeunusedbyte 1", "farwritetext 3",
  "writetext 2", "repeattext 2", "yesorno 0", "loadmenu 2",
  "closewindow 0", "jumptextfaceplayer 2", "jumptext 2", "waitbutton 0",
  "promptbutton 0", "pokepic 1", "closepokepic 0", "_2dmenu 0",
  "verticalmenu 0", "loadpikachudata 0", "randomwildmon 0",
  "loadtemptrainer 0", "loadwildmon 2", "loadtrainer 2", "startbattle 0",
  "reloadmapafterbattle 0", "catchtutorial 1", "trainertext 1",
  "trainerflagaction 1", "winlosstext 4", "scripttalkafter 0",
  "endifjustbattled 0", "checkjustbattled 0", "setlasttalked 1",
  "applymovement 3", "applymovementlasttalked 2", "faceplayer 0",
  "faceobject 2", "variablesprite 2", "disappear 1", "appear 1",
  "follow 2", "stopfollow 0", "moveobject 3", "writeobjectxy 1",
  "loademote 1", "showemote 3", "turnobject 2", "follownotexact 2",
  "earthquake 1", "changemapblocks 3", "changeblock 3", "reloadmap 0",
  "refreshmap 0", "writecmdqueue 2", "delcmdqueue 1", "playmusic 2",
  "encountermusic 0", "musicfadeout 3", "playmapmusic 0",
  "dontrestartmapmusic 0", "cry 2", "playsound 2", "waitsfx 0",
  "warpsound 0", "specialsound 0", "autoinput 3", "newloadmap 1",
  "pause 1", "deactivatefacing 1", "sdefer 2", "warpcheck 0",
  "stopandsjump 2", "endcallback 0", "end 0", "reloadend 1", "endall 0",
  "pokemart 3", "elevator 2", "trade 1", "askforphonenumber 1",
  "phonecall 2", "hangup 0", "describedecoration 1", "fruittree 1",
  "specialphonecall 2", "checkphonecall 0", "verbosegiveitem 2", "swarm 2",
  "halloffame 0", "credits 0", "warpfacing 5",
}

-- pokecrystal/macros/scripts/events.asm:1-1068, same transcription rules.
-- Cross-checked row for row against ScriptCommandTable
-- (pokecrystal/engine/overworld/scripting.asm:64-237), which is the table the
-- hardware actually indexes and therefore the authority over the macro file.
local CRYSTAL_EXPECTED = {
  "scall 2", "farscall 3", "memcall 2", "sjump 2", "farsjump 3",
  "memjump 2", "ifequal 3", "ifnotequal 3", "iffalse 2", "iftrue 2",
  "ifgreater 3", "ifless 3", "jumpstd 2", "callstd 2", "callasm 3",
  "special 2", "memcallasm 2", "checkmapscene 2", "setmapscene 3",
  "checkscene 0", "setscene 1", "setval 1", "addval 1", "random 1",
  "checkver 0", "readmem 2", "writemem 2", "loadmem 3", "readvar 1",
  "writevar 1", "loadvar 2", "giveitem 2", "takeitem 2", "checkitem 1",
  "givemoney 4", "takemoney 4", "checkmoney 4", "givecoins 2",
  "takecoins 2", "checkcoins 2", "addcellnum 1", "delcellnum 1",
  "checkcellnum 1", "checktime 1", "checkpoke 1", "givepoke 4",
  "giveegg 2", "givepokemail 2", "checkpokemail 2", "checkevent 2",
  "clearevent 2", "setevent 2", "checkflag 2", "clearflag 2", "setflag 2",
  "wildon 0", "wildoff 0", "xycompare 2", "warpmod 3", "blackoutmod 2",
  "warp 4", "getmoney 2", "getcoins 1", "getnum 1", "getmonname 2",
  "getitemname 2", "getcurlandmarkname 1", "gettrainername 3",
  "getstring 3", "itemnotify 0", "pocketisfull 0", "opentext 0",
  "reanchormap 1", "closetext 0", "writeunusedbyte 1", "farwritetext 3",
  "writetext 2", "repeattext 2", "yesorno 0", "loadmenu 2",
  "closewindow 0", "jumptextfaceplayer 2", "farjumptext 3", "jumptext 2",
  "waitbutton 0", "promptbutton 0", "pokepic 1", "closepokepic 0",
  "_2dmenu 0", "verticalmenu 0", "loadpikachudata 0", "randomwildmon 0",
  "loadtemptrainer 0", "loadwildmon 2", "loadtrainer 2", "startbattle 0",
  "reloadmapafterbattle 0", "catchtutorial 1", "trainertext 1",
  "trainerflagaction 1", "winlosstext 4", "scripttalkafter 0",
  "endifjustbattled 0", "checkjustbattled 0", "setlasttalked 1",
  "applymovement 3", "applymovementlasttalked 2", "faceplayer 0",
  "faceobject 2", "variablesprite 2", "disappear 1", "appear 1",
  "follow 2", "stopfollow 0", "moveobject 3", "writeobjectxy 1",
  "loademote 1", "showemote 3", "turnobject 2", "follownotexact 2",
  "earthquake 1", "changemapblocks 3", "changeblock 3", "reloadmap 0",
  "refreshmap 0", "writecmdqueue 2", "delcmdqueue 1", "playmusic 2",
  "encountermusic 0", "musicfadeout 3", "playmapmusic 0",
  "dontrestartmapmusic 0", "cry 2", "playsound 2", "waitsfx 0",
  "warpsound 0", "specialsound 0", "autoinput 3", "newloadmap 1",
  "pause 1", "deactivatefacing 1", "sdefer 2", "warpcheck 0",
  "stopandsjump 2", "endcallback 0", "end 0", "reloadend 1", "endall 0",
  "pokemart 3", "elevator 2", "trade 1", "askforphonenumber 1",
  "phonecall 2", "hangup 0", "describedecoration 1", "fruittree 1",
  "specialphonecall 2", "checkphonecall 0", "verbosegiveitem 2",
  "verbosegiveitemvar 2", "swarm 3", "halloffame 0", "credits 0",
  "warpfacing 5", "battletowertext 1", "getlandmarkname 2",
  "gettrainerclassname 2", "getname 3", "wait 1", "checksave 0",
}

local gold = Opcodes.forEdition("gold")
local crystal = Opcodes.forEdition("crystal")

-- CT-1: gold and silver share one dialect, and Opcodes[byte] keeps answering.
check(Opcodes.forEdition("silver") == gold, "silver resolves to the Gold table")
check(gold == Opcodes, "the Gold table is the module itself (Opcodes[byte])")
check(crystal ~= gold, "crystal resolves to a different table")
check(Opcodes.forEdition(nil) == gold, "an unknown edition falls back to Gold")
eq(Opcodes[0x52] and Opcodes[0x52].name, "jumptext",
  "Opcodes[0x52] is unchanged for existing callers")

local function auditTable(label, tbl, expected)
  local holes, wrong = {}, {}
  for i, want in ipairs(expected) do
    local byte = i - 1
    local name, size = want:match("^(%S+) (%d+)$")
    local row = tbl[byte]
    if not row then
      holes[#holes + 1] = ("$%02x"):format(byte)
    elseif row.name ~= name or row.size ~= tonumber(size) then
      wrong[#wrong + 1] = ("$%02x %s/%d wanted %s/%s")
        :format(byte, tostring(row.name), row.size or -1, name, size)
    end
  end
  eq(#holes, 0, label .. " has no missing opcode (" .. table.concat(holes, " ")
    .. ")")
  eq(#wrong, 0, label .. " matches events.asm (" .. table.concat(wrong, "; ")
    .. ")")
  local extra = {}
  for byte = 0x00, 0xff do
    if tbl[byte] and byte >= #expected then
      extra[#extra + 1] = ("$%02x %s"):format(byte, tbl[byte].name)
    end
  end
  eq(#extra, 0, label .. " declares nothing past the last command ("
    .. table.concat(extra, " ") .. ")")
end

auditTable("gold", gold, GOLD_EXPECTED)
auditTable("crystal", crystal, CRYSTAL_EXPECTED)

-- (a) $00-$51 is byte-identical between the dialects.
local drift = {}
for byte = 0x00, 0x51 do
  local g, c = gold[byte], crystal[byte]
  if not (g and c and g.name == c.name and g.size == c.size) then
    drift[#drift + 1] = ("$%02x"):format(byte)
  end
end
eq(#drift, 0, "$00-$51 is identical in both dialects ("
  .. table.concat(drift, " ") .. ")")

-- and the two dialects agree on NOTHING from $52 up, because the whole tail is
-- shifted by one.  farjumptext is the wedge.
eq(crystal[0x52].name, "farjumptext", "$52 is farjumptext on Crystal")
eq(crystal[0x52].size, 3, "farjumptext carries a dba, so 3 operand bytes")
eq(crystal[0x53].name, "jumptext", "Gold's $52 jumptext moved to $53")
eq(crystal[0xa0].size, 3,
  "Crystal swarm gained a leading flag byte (events.asm:1003-1008)")
eq(gold[0x9e].size, 2, "Gold swarm is still a bare map_id")

-- (c) NUM_EVENT_COMMANDS, both as the declared constant and as the row count.
local function rowCount(tbl)
  local n = 0
  for byte = 0x00, 0xff do if tbl[byte] then n = n + 1 end end
  return n
end
eq(Opcodes.NUM_EVENT_COMMANDS, 162,
  "pokegold events.asm:1015 NUM_EVENT_COMMANDS = $a2")
eq(crystal.NUM_EVENT_COMMANDS, 170,
  "pokecrystal events.asm:1068 NUM_EVENT_COMMANDS = $aa")
eq(rowCount(gold), Opcodes.NUM_EVENT_COMMANDS,
  "the Gold table is dense up to NUM_EVENT_COMMANDS")
eq(rowCount(crystal), crystal.NUM_EVENT_COMMANDS,
  "the Crystal table is dense up to NUM_EVENT_COMMANDS")

-- (d) farjumptext ends the walk the same way jumptext does.
check(Opcodes.TERMINATORS.farjumptext,
  "farjumptext is a TERMINATOR (jp ScriptJump, scripting.asm:318-327)")
check(Opcodes.TERMINATORS.jumptext, "jumptext still is")
check(crystal.TERMINATORS == Opcodes.TERMINATORS,
  "the Crystal table answers TERMINATORS too")
eq(crystal.key, Opcodes.key, "and key(), so a resolved table is self-sufficient")

-- (e) MOD_COMMAND is reachable only by name: no byte in EITHER dialect decodes
-- to it, so ROM data can never be mistaken for a mod verb.
local collide = {}
for byte = 0x00, 0xff do
  if gold[byte] and gold[byte].name == Opcodes.MOD_COMMAND then
    collide[#collide + 1] = ("gold $%02x"):format(byte)
  end
  if crystal[byte] and crystal[byte].name == Opcodes.MOD_COMMAND then
    collide[#collide + 1] = ("crystal $%02x"):format(byte)
  end
end
eq(#collide, 0, "MOD_COMMAND has no byte in either dialect ("
  .. table.concat(collide, " ") .. ")")
check(type(Opcodes.MOD_COMMAND) == "string" and Opcodes.MOD_COMMAND ~= "",
  "MOD_COMMAND is a name, not a byte")

-- The Vm side of the dialect: every Crystal-only verb has a branch, and the
-- shifted `swarm` reads its flag rather than its map group.
love = require("tests.love_stub")
local Vm = require("src.script.gen2.Vm")
local Events = require("src.world.gen2.Events")

do
  local seen, swarmArgs = {}, nil
  local events = Events.new()
  local vm = Vm.new({
    generation = 2,
    ["s:crystal"] = {
      -- pokecrystal/macros/scripts/events.asm:1003-1008: flag, then map_id.
      { op = "swarm", args = { 1, 24, 3 } },
      { op = "checksave" },
      { op = "wait", args = { 2 } },
      { op = "getlandmarkname", args = { 5, 3 } },
      { op = "gettrainerclassname", args = { 9, 3 } },
      { op = "getname", args = { 1, 152, 3 } },
      { op = "verbosegiveitemvar", args = { 20, 7 } },
      { op = "farjumptext", text = "t:far" },
      { op = "setevent", event = 1 },
    },
  }, { ["t:far"] = "Far text." }, events, {
    setSwarm = function(group, mapNum, kind)
      swarmArgs = { group, mapNum, kind }
    end,
    checkSave = function() return true end,
    getLandmarkName = function(id) seen.landmark = id return "RUINS" end,
    getTrainerClassName = function(id) seen.class = id return "SAGE" end,
    getMonName = function(id) seen.mon = id return "CHIKORITA" end,
    readVar = function(id) seen.var = id return 4 end,
    giveItem = function(item, qty) seen.give = { item, qty } return true end,
    getItemName = function() return "REPEL" end,
    showText = function(body, onDone) seen.text = body onDone() end,
  })

  check(vm:start("s:crystal"), "a Crystal-shaped script starts")
  for _ = 1, 40 do vm:update() end
  check(not vm:running(), "and runs to completion")

  eq(swarmArgs and swarmArgs[1], 24, "swarm reads the map group from args[2]")
  eq(swarmArgs and swarmArgs[2], 3, "and the map number from args[3]")
  eq(swarmArgs and swarmArgs[3], 1, "and passes SWARM_YANMA through as the kind")
  eq(seen.landmark, 5, "getlandmarkname passes its landmark id to the hook")
  eq(seen.class, 9, "gettrainerclassname passes the trainer group")
  eq(seen.mon, 152, "getname with MON_NAME routes to the mon-name hook")
  eq(seen.var, 7, "verbosegiveitemvar reads the quantity out of a var")
  eq(seen.give and seen.give[1], 20, "and gives the item the first byte names")
  eq(seen.give and seen.give[2], 4, "at the quantity the var held")
  eq(seen.text, "Far text.", "farjumptext prints its text")
  eq(next(vm.unknownOps or {}), nil,
    "no Crystal verb in the script fell through to the unknown ledger")
  -- Script_farjumptext ends on `jp ScriptJump`, so the setevent after it never
  -- runs -- the same reading Opcodes.TERMINATORS encodes for the extractor.
  check(not events:get(1),
    "farjumptext ended the script before the setevent below it")
  events:set(1, true)
  check(events:get(1), "and the event really is observable when it is set")
end

do
  -- Script_wait is SIX frames per unit (scripting.asm:2336-2347), not
  -- Script_pause's two.
  local vm = Vm.new({ generation = 2,
    ["s:wait"] = { { op = "wait", args = { 3 } }, { op = "end" } },
  }, {}, nil, {})
  check(vm:start("s:wait"), "a lone `wait` starts")
  local frames = 0
  while vm:running() and frames < 100 do
    vm:update()
    frames = frames + 1
  end
  eq(frames, 18, "`wait 3` holds the script for 3 * 6 frames")
end

T.finish()
