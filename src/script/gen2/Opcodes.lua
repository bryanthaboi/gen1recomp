-- Gen 2 script opcodes from pokegold/macros/scripts/events.asm.
-- `size` is operand bytes after the opcode (for import-time disassembly).

local Opcodes = {
  [0x00] = { name = "scall", size = 2 },
  [0x01] = { name = "farscall", size = 3 },
  [0x02] = { name = "memcall", size = 2 },
  [0x03] = { name = "sjump", size = 2 },
  [0x04] = { name = "farsjump", size = 3 },
  [0x05] = { name = "memjump", size = 2 },
  [0x06] = { name = "ifequal", size = 3 },
  [0x07] = { name = "ifnotequal", size = 3 },
  [0x08] = { name = "iffalse", size = 2 },
  [0x09] = { name = "iftrue", size = 2 },
  [0x0a] = { name = "ifgreater", size = 3 },
  [0x0b] = { name = "ifless", size = 3 },
  [0x0c] = { name = "jumpstd", size = 2 },
  [0x0d] = { name = "callstd", size = 2 },
  [0x0e] = { name = "callasm", size = 3 },
  [0x0f] = { name = "special", size = 2 },
  [0x10] = { name = "memcallasm", size = 2 },
  [0x11] = { name = "checkmapscene", size = 2 },
  [0x12] = { name = "setmapscene", size = 3 },
  [0x13] = { name = "checkscene", size = 0 },
  [0x14] = { name = "setscene", size = 1 },
  [0x15] = { name = "setval", size = 1 },
  [0x16] = { name = "addval", size = 1 },
  [0x17] = { name = "random", size = 1 },
  [0x18] = { name = "checkver", size = 0 },
  [0x19] = { name = "readmem", size = 2 },
  [0x1a] = { name = "writemem", size = 2 },
  [0x1b] = { name = "loadmem", size = 3 },
  [0x1c] = { name = "readvar", size = 1 },
  [0x1d] = { name = "writevar", size = 1 },
  [0x1e] = { name = "loadvar", size = 2 },
  [0x1f] = { name = "giveitem", size = 2 },
  [0x20] = { name = "takeitem", size = 2 },
  [0x21] = { name = "checkitem", size = 1 },
  [0x22] = { name = "givemoney", size = 4 }, -- account + 3-byte money (macro)
  [0x23] = { name = "takemoney", size = 4 },
  [0x24] = { name = "checkmoney", size = 4 },
  [0x25] = { name = "givecoins", size = 2 },
  [0x26] = { name = "takecoins", size = 2 },
  [0x27] = { name = "checkcoins", size = 2 },
  [0x28] = { name = "addcellnum", size = 1 },
  [0x29] = { name = "delcellnum", size = 1 },
  [0x2a] = { name = "checkcellnum", size = 1 },
  [0x2b] = { name = "checktime", size = 1 },
  [0x2c] = { name = "checkpoke", size = 1 },
  -- Variable length in ROM (4, or 8 when trainer≠0); extractor special-cases it.
  [0x2d] = { name = "givepoke", size = 4 },
  [0x2e] = { name = "giveegg", size = 2 },
  [0x2f] = { name = "givepokemail", size = 2 },
  [0x30] = { name = "checkpokemail", size = 2 },
  [0x31] = { name = "checkevent", size = 2 },
  [0x32] = { name = "clearevent", size = 2 },
  [0x33] = { name = "setevent", size = 2 },
  [0x34] = { name = "checkflag", size = 2 },
  [0x35] = { name = "clearflag", size = 2 },
  [0x36] = { name = "setflag", size = 2 },
  [0x37] = { name = "wildon", size = 0 },
  [0x38] = { name = "wildoff", size = 0 },
  [0x39] = { name = "xycompare", size = 2 },
  [0x3a] = { name = "warpmod", size = 3 },
  [0x3b] = { name = "blackoutmod", size = 2 },
  [0x3c] = { name = "warp", size = 4 },
  [0x3d] = { name = "getmoney", size = 2 },
  [0x3e] = { name = "getcoins", size = 1 },
  [0x3f] = { name = "getnum", size = 1 },
  [0x40] = { name = "getmonname", size = 2 },
  [0x41] = { name = "getitemname", size = 2 },
  [0x42] = { name = "getcurlandmarkname", size = 1 },
  [0x43] = { name = "gettrainername", size = 3 },
  [0x44] = { name = "getstring", size = 3 },
  [0x45] = { name = "itemnotify", size = 0 },
  [0x46] = { name = "pocketisfull", size = 0 },
  [0x47] = { name = "opentext", size = 0 },
  [0x48] = { name = "reanchormap", size = 1 },
  [0x49] = { name = "closetext", size = 0 },
  [0x4a] = { name = "writeunusedbyte", size = 1 },
  [0x4b] = { name = "farwritetext", size = 3 },
  [0x4c] = { name = "writetext", size = 2 },
  [0x4d] = { name = "repeattext", size = 2 },
  [0x4e] = { name = "yesorno", size = 0 },
  [0x4f] = { name = "loadmenu", size = 2 },
  [0x50] = { name = "closewindow", size = 0 },
  [0x51] = { name = "jumptextfaceplayer", size = 2 },
  [0x52] = { name = "jumptext", size = 2 },
  [0x53] = { name = "waitbutton", size = 0 },
  [0x54] = { name = "promptbutton", size = 0 },
  [0x55] = { name = "pokepic", size = 1 },
  [0x56] = { name = "closepokepic", size = 0 },
  [0x57] = { name = "_2dmenu", size = 0 },
  [0x58] = { name = "verticalmenu", size = 0 },
  [0x59] = { name = "loadpikachudata", size = 0 },
  [0x5a] = { name = "randomwildmon", size = 0 },
  [0x5b] = { name = "loadtemptrainer", size = 0 },
  [0x5c] = { name = "loadwildmon", size = 2 },
  [0x5d] = { name = "loadtrainer", size = 2 },
  [0x5e] = { name = "startbattle", size = 0 },
  [0x5f] = { name = "reloadmapafterbattle", size = 0 },
  [0x60] = { name = "catchtutorial", size = 1 },
  [0x61] = { name = "trainertext", size = 1 },
  [0x62] = { name = "trainerflagaction", size = 1 },
  [0x63] = { name = "winlosstext", size = 4 },
  [0x64] = { name = "scripttalkafter", size = 0 },
  [0x65] = { name = "endifjustbattled", size = 0 },
  [0x66] = { name = "checkjustbattled", size = 0 },
  [0x67] = { name = "setlasttalked", size = 1 },
  [0x68] = { name = "applymovement", size = 3 },
  [0x69] = { name = "applymovementlasttalked", size = 2 },
  [0x6a] = { name = "faceplayer", size = 0 },
  [0x6b] = { name = "faceobject", size = 2 },
  [0x6c] = { name = "variablesprite", size = 2 },
  [0x6d] = { name = "disappear", size = 1 },
  [0x6e] = { name = "appear", size = 1 },
  [0x6f] = { name = "follow", size = 2 },
  [0x70] = { name = "stopfollow", size = 0 },
  [0x71] = { name = "moveobject", size = 3 },
  [0x72] = { name = "writeobjectxy", size = 1 },
  [0x73] = { name = "loademote", size = 1 },
  [0x74] = { name = "showemote", size = 3 },
  [0x75] = { name = "turnobject", size = 2 },
  [0x76] = { name = "follownotexact", size = 2 },
  [0x77] = { name = "earthquake", size = 1 },
  [0x78] = { name = "changemapblocks", size = 3 },
  [0x79] = { name = "changeblock", size = 3 },
  [0x7a] = { name = "reloadmap", size = 0 },
  [0x7b] = { name = "refreshmap", size = 0 },
  [0x7c] = { name = "writecmdqueue", size = 2 },
  [0x7d] = { name = "delcmdqueue", size = 1 },
  [0x7e] = { name = "playmusic", size = 2 },
  [0x7f] = { name = "encountermusic", size = 0 },
  [0x80] = { name = "musicfadeout", size = 3 },
  [0x81] = { name = "playmapmusic", size = 0 },
  [0x82] = { name = "dontrestartmapmusic", size = 0 },
  [0x83] = { name = "cry", size = 2 },
  [0x84] = { name = "playsound", size = 2 },
  [0x85] = { name = "waitsfx", size = 0 },
  [0x86] = { name = "warpsound", size = 0 },
  [0x87] = { name = "specialsound", size = 0 },
  [0x88] = { name = "autoinput", size = 3 },
  [0x89] = { name = "newloadmap", size = 1 },
  [0x8a] = { name = "pause", size = 1 },
  [0x8b] = { name = "deactivatefacing", size = 1 },
  [0x8c] = { name = "sdefer", size = 2 },
  [0x8d] = { name = "warpcheck", size = 0 },
  [0x8e] = { name = "stopandsjump", size = 2 },
  [0x8f] = { name = "endcallback", size = 0 },
  [0x90] = { name = "end", size = 0 },
  [0x91] = { name = "reloadend", size = 1 },
  [0x92] = { name = "endall", size = 0 },
  [0x93] = { name = "pokemart", size = 3 },
  [0x94] = { name = "elevator", size = 2 },
  [0x95] = { name = "trade", size = 1 },
  [0x96] = { name = "askforphonenumber", size = 1 },
  [0x97] = { name = "phonecall", size = 2 },
  [0x98] = { name = "hangup", size = 0 },
  [0x99] = { name = "describedecoration", size = 1 },
  [0x9a] = { name = "fruittree", size = 1 },
  [0x9b] = { name = "specialphonecall", size = 2 },
  [0x9c] = { name = "checkphonecall", size = 0 },
  [0x9d] = { name = "verbosegiveitem", size = 2 },
  -- `swarm` is a bare `map_id` (macros/scripts/events.asm: `db swarm_command /
  -- map_id \1`), and map_id is two bytes; Script_swarm makes exactly two
  -- GetScriptByte calls.  This row said 3, which ate the opcode byte after
  -- every swarm and shifted the rest of that script by one.  The four users all
  -- live in engine/phone/scripts/trainers.asm, which the pointer walk does not
  -- reach yet, so nothing in today's cache is mis-decoded by it.
  [0x9e] = { name = "swarm", size = 2 },
  [0x9f] = { name = "halloffame", size = 0 },
  [0xa0] = { name = "credits", size = 0 },
  [0xa1] = { name = "warpfacing", size = 5 },
}

-- pokegold/macros/scripts/events.asm:1015 DEF NUM_EVENT_COMMANDS EQU $a2
Opcodes.NUM_EVENT_COMMANDS = 0xa2

-- pokecrystal/macros/scripts/events.asm:1-539 is identical to pokegold's, so
-- $00..$51 is copied; :541 inserts farjumptext and shifts everything after it.
local CRYSTAL = {}
for byte = 0x00, 0x51 do
  local row = Opcodes[byte]
  CRYSTAL[byte] = { name = row.name, size = row.size }
end

-- pokecrystal/macros/scripts/events.asm:541-1066, cross-checked against
-- ScriptCommandTable at pokecrystal/engine/overworld/scripting.asm:64-237.
CRYSTAL[0x52] = { name = "farjumptext", size = 3 }
CRYSTAL[0x53] = { name = "jumptext", size = 2 }
CRYSTAL[0x54] = { name = "waitbutton", size = 0 }
CRYSTAL[0x55] = { name = "promptbutton", size = 0 }
CRYSTAL[0x56] = { name = "pokepic", size = 1 }
CRYSTAL[0x57] = { name = "closepokepic", size = 0 }
CRYSTAL[0x58] = { name = "_2dmenu", size = 0 }
CRYSTAL[0x59] = { name = "verticalmenu", size = 0 }
CRYSTAL[0x5a] = { name = "loadpikachudata", size = 0 }
CRYSTAL[0x5b] = { name = "randomwildmon", size = 0 }
CRYSTAL[0x5c] = { name = "loadtemptrainer", size = 0 }
CRYSTAL[0x5d] = { name = "loadwildmon", size = 2 }
CRYSTAL[0x5e] = { name = "loadtrainer", size = 2 }
CRYSTAL[0x5f] = { name = "startbattle", size = 0 }
CRYSTAL[0x60] = { name = "reloadmapafterbattle", size = 0 }
CRYSTAL[0x61] = { name = "catchtutorial", size = 1 }
CRYSTAL[0x62] = { name = "trainertext", size = 1 }
CRYSTAL[0x63] = { name = "trainerflagaction", size = 1 }
CRYSTAL[0x64] = { name = "winlosstext", size = 4 }
CRYSTAL[0x65] = { name = "scripttalkafter", size = 0 }
CRYSTAL[0x66] = { name = "endifjustbattled", size = 0 }
CRYSTAL[0x67] = { name = "checkjustbattled", size = 0 }
CRYSTAL[0x68] = { name = "setlasttalked", size = 1 }
CRYSTAL[0x69] = { name = "applymovement", size = 3 }
CRYSTAL[0x6a] = { name = "applymovementlasttalked", size = 2 }
CRYSTAL[0x6b] = { name = "faceplayer", size = 0 }
CRYSTAL[0x6c] = { name = "faceobject", size = 2 }
CRYSTAL[0x6d] = { name = "variablesprite", size = 2 }
CRYSTAL[0x6e] = { name = "disappear", size = 1 }
CRYSTAL[0x6f] = { name = "appear", size = 1 }
CRYSTAL[0x70] = { name = "follow", size = 2 }
CRYSTAL[0x71] = { name = "stopfollow", size = 0 }
CRYSTAL[0x72] = { name = "moveobject", size = 3 }
CRYSTAL[0x73] = { name = "writeobjectxy", size = 1 }
CRYSTAL[0x74] = { name = "loademote", size = 1 }
CRYSTAL[0x75] = { name = "showemote", size = 3 }
CRYSTAL[0x76] = { name = "turnobject", size = 2 }
CRYSTAL[0x77] = { name = "follownotexact", size = 2 }
CRYSTAL[0x78] = { name = "earthquake", size = 1 }
CRYSTAL[0x79] = { name = "changemapblocks", size = 3 }
CRYSTAL[0x7a] = { name = "changeblock", size = 3 }
CRYSTAL[0x7b] = { name = "reloadmap", size = 0 }
CRYSTAL[0x7c] = { name = "refreshmap", size = 0 }
CRYSTAL[0x7d] = { name = "writecmdqueue", size = 2 }
CRYSTAL[0x7e] = { name = "delcmdqueue", size = 1 }
CRYSTAL[0x7f] = { name = "playmusic", size = 2 }
CRYSTAL[0x80] = { name = "encountermusic", size = 0 }
CRYSTAL[0x81] = { name = "musicfadeout", size = 3 }
CRYSTAL[0x82] = { name = "playmapmusic", size = 0 }
CRYSTAL[0x83] = { name = "dontrestartmapmusic", size = 0 }
CRYSTAL[0x84] = { name = "cry", size = 2 }
CRYSTAL[0x85] = { name = "playsound", size = 2 }
CRYSTAL[0x86] = { name = "waitsfx", size = 0 }
CRYSTAL[0x87] = { name = "warpsound", size = 0 }
CRYSTAL[0x88] = { name = "specialsound", size = 0 }
CRYSTAL[0x89] = { name = "autoinput", size = 3 }
CRYSTAL[0x8a] = { name = "newloadmap", size = 1 }
CRYSTAL[0x8b] = { name = "pause", size = 1 }
CRYSTAL[0x8c] = { name = "deactivatefacing", size = 1 }
CRYSTAL[0x8d] = { name = "sdefer", size = 2 }
CRYSTAL[0x8e] = { name = "warpcheck", size = 0 }
CRYSTAL[0x8f] = { name = "stopandsjump", size = 2 }
CRYSTAL[0x90] = { name = "endcallback", size = 0 }
CRYSTAL[0x91] = { name = "end", size = 0 }
CRYSTAL[0x92] = { name = "reloadend", size = 1 }
CRYSTAL[0x93] = { name = "endall", size = 0 }
CRYSTAL[0x94] = { name = "pokemart", size = 3 }
CRYSTAL[0x95] = { name = "elevator", size = 2 }
CRYSTAL[0x96] = { name = "trade", size = 1 }
CRYSTAL[0x97] = { name = "askforphonenumber", size = 1 }
CRYSTAL[0x98] = { name = "phonecall", size = 2 }
CRYSTAL[0x99] = { name = "hangup", size = 0 }
CRYSTAL[0x9a] = { name = "describedecoration", size = 1 }
CRYSTAL[0x9b] = { name = "fruittree", size = 1 }
CRYSTAL[0x9c] = { name = "specialphonecall", size = 2 }
CRYSTAL[0x9d] = { name = "checkphonecall", size = 0 }
CRYSTAL[0x9e] = { name = "verbosegiveitem", size = 2 }
CRYSTAL[0x9f] = { name = "verbosegiveitemvar", size = 2 }
-- events.asm:1003-1008: Crystal's swarm is `db flag` then `map_id`, not a bare
-- map_id; Script_swarm makes three GetScriptByte calls (scripting.asm:654-662).
CRYSTAL[0xa0] = { name = "swarm", size = 3 }
CRYSTAL[0xa1] = { name = "halloffame", size = 0 }
CRYSTAL[0xa2] = { name = "credits", size = 0 }
CRYSTAL[0xa3] = { name = "warpfacing", size = 5 }
CRYSTAL[0xa4] = { name = "battletowertext", size = 1 }
CRYSTAL[0xa5] = { name = "getlandmarkname", size = 2 }
CRYSTAL[0xa6] = { name = "gettrainerclassname", size = 2 }
CRYSTAL[0xa7] = { name = "getname", size = 3 }
CRYSTAL[0xa8] = { name = "wait", size = 1 }
CRYSTAL[0xa9] = { name = "checksave", size = 0 }

-- pokecrystal/macros/scripts/events.asm:1068 DEF NUM_EVENT_COMMANDS EQU $aa
CRYSTAL.NUM_EVENT_COMMANDS = 0xaa

-- Commands that end the current linear path (jumps transfer control).
--
-- `fruittree` and `describedecoration` are ScriptJumps (Script_fruittree does
-- `jp ScriptJump` into FruitTreeScript, Script_describedecoration jumps to
-- whatever DescribeDecoration hands back), and `halloffame` / `credits` both
-- fall into ReturnFromCredits, which is Script_endall plus MAPSTATUS_DONE.
-- Without them the disassembler kept walking the data that follows: all 42
-- extracted fruittree scripts and all 13 describedecoration ones currently
-- carry a tail of garbage commands, which is why Vm.lua returns on each of
-- these four regardless.  `catchtutorial` is deliberately NOT here: it ends on
-- `jp Script_reloadmap` and the script really does continue afterwards, the
-- same way `reloadmap` itself does.
--
-- `farjumptext` is Crystal-only and joins them for the same reason `jumptext`
-- is here: pokecrystal/engine/overworld/scripting.asm:318-327 ends on
-- `jp ScriptJump` into JumpTextScript.
Opcodes.TERMINATORS = {
  sjump = true, farsjump = true, memjump = true, jumpstd = true,
  jumptext = true, farjumptext = true, jumptextfaceplayer = true,
  stopandsjump = true, ["end"] = true, endall = true, endcallback = true,
  reloadend = true,
  fruittree = true, describedecoration = true,
  halloffame = true, credits = true,
}

-- The one op name this engine adds, and the reason it deliberately has NO byte
-- behind it.  Every row above is keyed by the opcode byte the cart carries, and
-- src/import/RomExtractorGen2.lua resolves a command as Opcodes[byte]: a byte
-- that is not in that table breaks the pointer walk into an `unknown` row.  Give
-- a mod verb one of the free bytes and ROM data that happens to start with it
-- would decode as a mod call instead of ending the walk, so the free space stays
-- free and the extension op is reachable only by NAME -- which is to say, only
-- from a row a mod wrote, never from one the extractor did.  The free space is
-- per dialect and the intersection is what matters: Gold leaves $a2..$ff
-- (events.asm:1015), Crystal only $aa..$ff (events.asm:1068).
--
-- src/script/gen2/Vm.lua:runModCommand is the only reader; the contract for the
-- row shapes and the verb table is documented there.
Opcodes.MOD_COMMAND = "modcommand"

function Opcodes.key(bank, address)
  return string.format("%02x:%04x", bank, address)
end

CRYSTAL.TERMINATORS = Opcodes.TERMINATORS
CRYSTAL.MOD_COMMAND = Opcodes.MOD_COMMAND
CRYSTAL.key = Opcodes.key

-- Gold and Silver share one dialect (pokegold/macros/scripts/events.asm:540);
-- Crystal renumbers from $52 (pokecrystal/macros/scripts/events.asm:541).
function Opcodes.forEdition(edition)
  if edition == "crystal" then return CRYSTAL end
  return Opcodes
end

return Opcodes
