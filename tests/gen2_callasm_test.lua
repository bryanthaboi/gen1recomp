-- The `callasm` / `memcall` / `memcallasm` / `memjump` registry:
-- src/script/gen2/CallAsm.lua, which resolves the bank:addr operand against
-- pokegold-symbols/pokegold.sym and runs the hand-ported routine.
--
-- Two things are worth asserting here and nothing else is.  The first is the
-- wScriptVar contract: only the eleven routines whose asm ends in
-- `ld [wScriptVar], a` may answer with a number, because every other site is
-- followed by an `iffalse` the cart decides some other way.  The second is
-- WHICH rows in this cache resolve, pinned name by name: a row that starts
-- answering is either a real site the extractor has finally reached or an
-- address collision, and the two are told apart by hand against
-- pokegold.sym, not by whatever the cache happens to hold.
--
-- ROM-free: `luajit tests/gen2_callasm_test.lua`.  The cache section at the
-- bottom SKIPs when no Gold cache is present.
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 callasm")
local check, eq = S.check, S.eq

local CallAsm = require("src.script.gen2.CallAsm")

-- ---- the site table -------------------------------------------------------
do
  local sites, routines = 0, {}
  for _, name in pairs(CallAsm.SITES) do
    sites = sites + 1
    routines[name] = true
  end
  local routineCount = 0
  for _ in pairs(routines) do routineCount = routineCount + 1 end
  eq(sites, 51, "every Gold/Silver callasm target address is registered")
  eq(routineCount, 47, "the revision aliases still name exactly 47 routines")

  local unmapped = {}
  for key, name in pairs(CallAsm.SITES) do
    if not CallAsm.ALL[name] then unmapped[#unmapped + 1] = key .. " " .. name end
  end
  eq(#unmapped, 0, "every site has a port or a stub: " .. table.concat(unmapped, ", "))

  -- Disjoint by construction: CallAsm.lua raises if a name lands in both, so
  -- this is the assertion that the raise has not been defeated by a rename.
  for name in pairs(CallAsm.HANDLERS) do
    check(CallAsm.STUBS[name] == nil, name .. " is ported, not stubbed")
  end
  for name in pairs(CallAsm.STUBS) do
    check(CallAsm.STUB_REASONS[name] ~= nil, name .. " says why it is a stub")
  end

  -- pokegold-symbols/pokegold.sym, spot-checked across banks so a table that
  -- was rebuilt against the wrong ROM revision fails here rather than silently
  -- calling the neighbouring routine.
  eq(CallAsm.SITES["11:4055"], "CheckFruitTree", "11:4055 is CheckFruitTree")
  eq(CallAsm.SITES["04:68e0"], "HalveMoney", "04:68e0 is HalveMoney")
  eq(CallAsm.SITES["03:4d7b"], "TryStrengthOW", "03:4d7b is TryStrengthOW")
  eq(CallAsm.SITES["03:4d79"], "TryStrengthOW",
    "Silver's relocated 03:4d79 is also TryStrengthOW")
  eq(CallAsm.SITES["2e:6378"], "TreeMonEncounter", "2e:6378 is TreeMonEncounter")
  eq(CallAsm.SITES["14:4786"], "CheckCanUseSquirtbottle",
    "14:4786 is _Squirtbottle.CheckCanUseSquirtbottle")

  -- The three WRAM operands are NOT sites: the pointer at the address is
  -- written at run time, so there is nothing static to resolve.
  eq(CallAsm.SITES["00:cfd8"], nil, "wQueuedScriptBank is not a routine")
  eq(CallAsm.MEM_OPERANDS["00:cfd8"], "wQueuedScriptBank",
    "it is a memjump / memcallasm operand instead")
end

-- ---- the key format -------------------------------------------------------
do
  eq(CallAsm.key(0x11, 0x4055), "11:4055", "two hex digits and four, lower case")
  eq(CallAsm.key(0x04, 0x0800), "04:0800", "both halves are zero padded")
  eq(CallAsm.key(0, 0), "00:0000", "bank 0 at 0")
end

-- ---- the wScriptVar contract ----------------------------------------------
--
-- The eleven routines whose asm writes wScriptVar, taken one at a time out of
-- the decomp.  Everything else must answer nil however it is called, because
-- Script_callasm itself never touches wScriptVar and inventing a byte picks a
-- branch at random.
local WRITES_SCRIPT_VAR = {
  CheckFruitTree = true,            -- engine/events/fruit_trees.asm
  SweetScentEncounter = true,       -- engine/events/sweet_scent.asm
  CheckCanUseSquirtbottle = true,   -- engine/events/squirtbottle.asm
  CheckWhitedOut = true,            -- engine/events/poisonstep.asm
  TryStrengthOW = true,             -- engine/events/overworld.asm
  CheckContinueWaterfall = true,    -- engine/events/overworld.asm
  AskCutScript_CheckMap = true,     -- engine/events/overworld.asm
  HasRockSmash = true,              -- engine/events/overworld.asm
  Fishing_CheckFacingUp = true,     -- engine/events/overworld.asm
  TreeMonEncounter = true,          -- engine/events/treemons.asm
  TryReceiveItem = true,            -- engine/events/misc_scripts.asm
}

do
  local writers = 0
  for _ in pairs(WRITES_SCRIPT_VAR) do writers = writers + 1 end
  eq(writers, 11, "eleven of the fifty-seven sites write wScriptVar")

  -- An empty ctx: no map, no party, no save.  Every routine still has to come
  -- back with the right SHAPE of answer, which is the whole contract.  A
  -- STUBBED writer is the one case that answers nil anyway: a routine that
  -- never ran must not pick the branch that follows it.
  for name in pairs(CallAsm.ALL) do
    local value = CallAsm.run({}, name)
    if WRITES_SCRIPT_VAR[name] and CallAsm.HANDLERS[name] then
      eq(type(value), "number", name .. " answers a wScriptVar byte")
      check(type(value) == "number" and value >= 0 and value < 256,
        name .. " answers one byte")
    else
      eq(value, nil, name .. " leaves wScriptVar alone")
    end
  end

  -- TryReceiveItem is the one wScriptVar writer that is a STUB, and it is the
  -- reason the stub table carries a nil value rather than a 0: the "no room"
  -- arm must not be picked by a routine that never ran.
  eq(CallAsm.run({}, "TryReceiveItem"), nil,
    "the stubbed writer still answers nil, not a guessed branch")
end

-- ---- dispatch --------------------------------------------------------------
do
  local halved = { game = { save = { player = { money = 5001 } } } }
  -- 04:68e0 is HalveMoney, reached with no label at all -- which is how every
  -- callasm in this cache arrives, because nothing resolves symbols at import.
  eq(CallAsm.dispatch(halved, nil, 0x04, 0x68e0), nil, "HalveMoney writes no wScriptVar")
  eq(halved.game.save.player.money, 2500,
    "the 24-bit srl/rra/rra is floor division")

  -- An address nobody has named answers nil rather than falling through to a
  -- neighbour, and a label the table does not know is ignored in favour of the
  -- address.
  eq(CallAsm.dispatch({}, nil, 0x45, 0x9752), nil, "an unknown site is nil")
  eq(CallAsm.nameFor("NotARoutine", 0x11, 0x4055), "CheckFruitTree",
    "an unknown label falls back to the address")
  eq(CallAsm.nameFor("HalveMoney", 0x11, 0x4055), "HalveMoney",
    "a known label wins over the address")

  -- A handler that throws must not take the script down with it: the cart's
  -- own callasm cannot fail, and the branch after it still needs the
  -- "left alone" answer rather than an aborted coroutine.
  local exploding = setmetatable({}, { __index = function()
    return function() error("boom") end
  end })
  eq(CallAsm.run(exploding, "SelectMenu"), nil, "a throwing handler answers nil")
end

-- ---- the routines, one at a time ------------------------------------------

-- engine/events/fruit_trees.asm.  The flag means "already picked" and
-- FruitTreeScript reads it with `iffalse .fruit`, so a picked tree is the 1.
do
  local picked = {}
  local ctx = {
    curFruitTree = 7,
    fruitTreeItem = function(_self, tree) return 100 + tree end,
    fruitTreeReset = function() picked.reset = true end,
    fruitTreePicked = function(_self, tree) return tree == 7 end,
    fruitTreePick = function(_self, tree) picked.tree = tree end,
  }
  CallAsm.run(ctx, "GetCurTreeFruit")
  eq(ctx.curFruit, 107, "GetCurTreeFruit leaves the item in wCurFruit")
  CallAsm.run(ctx, "TryResetFruitTrees")
  check(picked.reset, "TryResetFruitTrees runs the daily refill")
  eq(CallAsm.run(ctx, "CheckFruitTree"), 1, "a picked tree answers 1")
  ctx.curFruitTree = 8
  eq(CallAsm.run(ctx, "CheckFruitTree"), 0, "an unpicked one answers 0")
  CallAsm.run(ctx, "PickedFruitTree")
  eq(picked.tree, 8, "PickedFruitTree sets the flag and writes no wScriptVar")
end

-- engine/events/overworld.asm GetPartyNickname: wCurPartyMon's nickname into
-- the string buffers, which is what {STRBUF} reads back.
do
  local named
  local ctx = {
    curPartyMon = { nickname = "SPARKY" },
    setNickname = function(_self, mon) named = mon end,
  }
  CallAsm.run(ctx, "GetPartyNickname")
  eq(named.nickname, "SPARKY", "the mon CheckPartyMove picked is named")

  -- With nothing in wCurPartyMon the cart still reads slot 0.
  local first = { game = { save = { party = { { nickname = "TOTO" } } } },
    setNickname = function(_self, mon) named = mon end }
  CallAsm.run(first, "GetPartyNickname")
  eq(named.nickname, "TOTO", "an unset wCurPartyMon is slot 0")
end

-- engine/events/overworld.asm HasRockSmash is INVERTED: 1 means the party does
-- NOT know it, which is why AskRockSmashScript reads it with `ifequal 1, .no`.
do
  local without = { partyMoveUser = function() return nil end }
  local with = { partyMoveUser = function() return { nickname = "ONIX" } end }
  eq(CallAsm.run(without, "HasRockSmash"), 1, "no ROCK SMASH in the party is 1")
  eq(CallAsm.run(with, "HasRockSmash"), 0, "a mon that knows it is 0")
end

-- engine/events/overworld.asm Fishing_CheckFacingUp: `and $c / cp OW_UP`.
do
  eq(CallAsm.run({ player = { facing = "up" } }, "Fishing_CheckFacingUp"), 1,
    "facing up is the only 1")
  eq(CallAsm.run({ player = { facing = "left" } }, "Fishing_CheckFacingUp"), 0,
    "any other facing is 0")
end

-- engine/events/overworld.asm PutTheRodAway: wPlayerAction back to normal,
-- which in this port is the fishing state going away.
do
  local ctx = { fishing = { phase = "done" } }
  CallAsm.run(ctx, "PutTheRodAway")
  eq(ctx.fishing, nil, "the rod pose is dropped")
end

-- engine/events/overworld.asm SetStrengthFlag: BIKEFLAGS_STRENGTH_ACTIVE, the
-- species, and a tail call into GetPartyNickname.
do
  local named
  local ctx = {
    curPartyMon = { nickname = "GEODUDE", species = "GEODUDE" },
    setNickname = function(_self, mon) named = mon end,
  }
  eq(CallAsm.run(ctx, "SetStrengthFlag"), nil, "SetStrengthFlag writes no wScriptVar")
  check(ctx.strengthActive, "STRENGTH is switched on")
  eq(ctx.strengthSpecies, "GEODUDE", "and wStrengthSpecies is the mon's")
  eq(named.nickname, "GEODUDE", "the nickname is copied in the same routine")
end

-- engine/events/squirtbottle.asm .CheckCanUseSquirtbottle: Route 36, and the
-- object faced has to carry SPRITEMOVEDATA_SUDOWOODO ($17).
do
  local function ctxWith(mapId, movement)
    return {
      map = { id = mapId },
      player = { cellX = 5, cellY = 5, facing = "up" },
      npcAt = function(_self, x, y)
        if x == 5 and y == 4 and movement then
          return { def = { movement = movement } }
        end
        return nil
      end,
    }
  end
  eq(CallAsm.run(ctxWith("ROUTE_36", 0x17), "CheckCanUseSquirtbottle"), 1,
    "Route 36 plus a Sudowoodo is the 1")
  eq(CallAsm.run(ctxWith("ROUTE_36", 0x19), "CheckCanUseSquirtbottle"), 0,
    "a STRENGTH boulder on the same tile is not")
  eq(CallAsm.run(ctxWith("ROUTE_36", nil), "CheckCanUseSquirtbottle"), 0,
    "GetFacingObject's own carry is the same 0")
  eq(CallAsm.run(ctxWith("ROUTE_35", 0x17), "CheckCanUseSquirtbottle"), 0,
    "and the map check comes first")
end

-- engine/events/hidden_item.asm SetMemEvent: the flag whose NUMBER is in
-- wHiddenItemEvent.  wEventFlags is keyed by number, not by name.
do
  local set = {}
  local ctx = {
    hiddenItemEvent = 173,
    events = { set = function(_self, flag, value) set[flag] = value end },
  }
  eq(CallAsm.run(ctx, "SetMemEvent"), nil, "SetMemEvent writes no wScriptVar")
  eq(set[173], true, "the hidden item's flag is set by number")
end

-- engine/events/poisonstep.asm .PlayPoisonSFX: SFX_POISON then
-- LoadPoisonBGPals, four frames (#1362)
do
  local World = require("src.world.gen2.World")
  local ctx = { poisonBGFlash = World.poisonBGFlash,
    playSfxNamed = function() end }
  eq(CallAsm.run(ctx, "PlayPoisonSFX"), nil, "PlayPoisonSFX writes no wScriptVar")
  eq(ctx.poisonFlash, 4, "and sets the flash to exactly four frames")

  local hurt = { game = { save = { party = { { hp = 5, status = "psn" } },
      poisonStepCount = 3 } },
    poisonBGFlash = World.poisonBGFlash, playSfxNamed = function() end,
    stepContext = function() return { linkMode = false } end }
  World.countStep(hurt)
  eq(hurt.poisonFlash, 4, "the hurt arm reaches it too")

  local faint = { poisonBGFlash = World.poisonBGFlash, playSfxNamed = function() end }
  World.poisonFaintScript(faint, { fainted = {}, whiteout = false })
  eq(faint.poisonFlash, 4, "and so does the faint arm")

  local ok = pcall(CallAsm.run, {}, "PlayPoisonSFX")
  check(ok, "a ctx with no poisonBGFlash does not error")
end

-- engine/events/poisonstep.asm .CheckWhitedOut ends on
-- CheckPlayerPartyForFitMon, whose answer is 1 when something can still fight;
-- the `iffalse .whiteout` after it is reading "no fit mon".
do
  local fit = { game = { save = { party = { { hp = 4, maxHp = 20 } } } } }
  local out = { game = { save = { party = { { hp = 0, maxHp = 20 } } } } }
  eq(CallAsm.run(fit, "CheckWhitedOut"), 1, "a mon that can still fight is 1")
  eq(CallAsm.run(out, "CheckWhitedOut"), 0, "a whited-out party is 0")
end

-- engine/events/whiteout.asm HalveMoney: the wallet ALONE.  Mom's savings are
-- a separate three bytes the routine never reaches.
do
  local ctx = { game = { save = {
    player = { money = 9999 },
    mom = { savedMoney = 4000 },
  } } }
  CallAsm.run(ctx, "HalveMoney")
  eq(ctx.game.save.player.money, 4999, "9999 halves to 4999, remainder dropped")
  eq(ctx.game.save.mom.savedMoney, 4000, "Mom's savings are untouched")
end

-- engine/events/whiteout.asm GetWhiteoutSpawn: IsSpawnPoint over the
-- `blackoutmod` pair, SPAWN_HOME when it is not one.
do
  local spawns = {
    SPAWN_HOME = { map = "PLAYERS_HOUSE_1F" },
    SPAWN_OLIVINE = { map = "OLIVINE_POKECENTER_1F" },
  }
  local known = { landmarks = { spawns = spawns },
    game = { save = { blackoutMap = "OLIVINE_POKECENTER_1F" } } }
  CallAsm.run(known, "GetWhiteoutSpawn")
  eq(known.defaultSpawnpoint, "SPAWN_OLIVINE", "a real spawn point is kept")

  local adrift = { landmarks = { spawns = spawns },
    game = { save = { blackoutMap = "FAST_SHIP_1F" } } }
  CallAsm.run(adrift, "GetWhiteoutSpawn")
  eq(adrift.defaultSpawnpoint, "SPAWN_HOME",
    "somewhere that is not a spawn point falls back to SPAWN_HOME")
end

-- engine/items/itemfinder.asm .ItemfinderSound: `ld c, 4` around a pair of
-- WaitPlaySFX calls, so eight sounds, alternating.
do
  local played = {}
  local ctx = { playSfxNamed = function(_self, name) played[#played + 1] = name end }
  CallAsm.run(ctx, "ItemfinderSound")
  eq(#played, 8, "four loops of two sounds")
  eq(played[1], "Sfx_SecondPartOfItemfinder", "the ping comes first")
  eq(played[2], "Sfx_Transaction", "then the transaction blip")
  eq(played[8], "Sfx_Transaction", "and the pair repeats to the end")
end

-- engine/overworld/events.asm HatchEggScript is one command: `callasm
-- OverworldHatchEgg / end`.  World:countStep runs it through the registry.
do
  local hatched = false
  local ctx = { hatchEggs = function() hatched = true end }
  eq(CallAsm.run(ctx, "OverworldHatchEgg"), nil, "the hatch writes no wScriptVar")
  check(hatched, "and it runs HatchEggs")
end

-- ---- the World seam --------------------------------------------------------
do
  local World = require("src.world.gen2.World")
  local ctx = { game = { save = { player = { money = 100 } } } }
  -- World:callAsm is what src/script/gen2/Vm.lua's callasm branch calls, and
  -- it dispatches on the address because `label` is always nil today.
  eq(World.callAsm(ctx, nil, 0x04, 0x68e0), nil, "the seam answers nil for HalveMoney")
  eq(ctx.game.save.player.money, 50, "and the routine ran")
  eq(World.callAsm(ctx, nil, 0x45, 0x9752), nil, "a garbage address is a no-op")
  eq(ctx.game.save.player.money, 50, "and changes nothing")
end

-- ---- the cache -------------------------------------------------------------
--
-- WHICH rows carry one of the four opcodes and resolve, pinned exactly.
--
-- The row count is deliberately not pinned.  It was thirty-eight before the
-- extractor stopped walking three-byte `hiddenitem` bg_event operands as
-- bytecode, and every one of those thirty-eight sat inside a key made out of
-- one (45:697a is IlexForestHiddenEther, 47:40a5 is
-- WhirlIslandB1FHiddenRareCandy), so their bank/address pairs were noise; a
-- cache built after that fix has none at all.
--
-- The RESOLUTIONS are pinned, because a row that starts resolving is either a
-- real site the extractor has finally reached or an address collision, and
-- both want reading before the registry answers them.  These five appeared
-- when `farscall` / `farsjump` / `farwritetext` stopped reading their `dba`
-- operand backwards: the swap sent 40:4154 and 40:4158 at 4d:4e03 / 4f:6003
-- instead of AskStrengthScript / AskRockSmashScript, so the STRENGTH and ROCK
-- SMASH arms of engine/events/overworld.asm were unreachable and their
-- `callasm` rows were never walked.  All five are exact pokegold.sym matches,
-- not collisions:
--
--   03:4d30 Script_UsedStrength    -> 03:4d15 SetStrengthFlag
--   03:4d4e AskStrengthScript      -> 03:4d7b TryStrengthOW
--   03:4f35 RockSmashScript        -> 03:474b GetPartyNickname
--   03:4f35 RockSmashScript        -> 2e:63a1 RockMonEncounter
--   03:4f60 AskRockSmashScript     -> 03:4f7f HasRockSmash
local EXPECTED_RESOLVED = {
  "GetPartyNickname", "HasRockSmash", "RockMonEncounter",
  "SetStrengthFlag", "TryStrengthOW",
}
local ASM_OPS = {
  callasm = true, memcall = true, memcallasm = true, memjump = true,
}

local cacheDir = os.getenv("GOLD_CACHE")
if not cacheDir then
  cacheDir = (os.getenv("HOME") or "") ..
    "/Library/Application Support/LOVE/gold-dev/gold"
end
local scriptsFile = loadfile(cacheDir .. "/data/generated/scripts.lua")
if not scriptsFile then
  check(true, "no Gold cache (SKIP)")
  S.finish()
  return
end
local scripts = scriptsFile()

local rows, resolved = 0, {}
for key, list in pairs(scripts) do
  if type(list) == "table" then
    for _, cmd in ipairs(list) do
      if type(cmd) == "table" and ASM_OPS[cmd.op] then
        rows = rows + 1
        local args = cmd.args or {}
        -- callasm is bank, lo, hi; the other three are lo, hi out of WRAM.
        local bank, addr
        if cmd.op == "callasm" then
          bank = args[1] or 0
          addr = (args[2] or 0) + (args[3] or 0) * 0x100
        else
          bank = 0
          addr = (args[1] or 0) + (args[2] or 0) * 0x100
        end
        local name = CallAsm.nameFor(cmd.label, bank, addr)
        if name then
          resolved[#resolved + 1] = name
        end
      end
    end
  end
end

check(rows >= 0,
  ("%d rows in this cache carry callasm / memcall / memcallasm / memjump")
    :format(rows))
-- `pairs` over the script table has no order, so sort before comparing.
table.sort(resolved)
eq(table.concat(resolved, ", "), table.concat(EXPECTED_RESOLVED, ", "),
  "and exactly the five edition-specific field-move sites resolve")
for _, name in ipairs(resolved) do
  check(CallAsm.HANDLERS[name] ~= nil or CallAsm.STUBS[name] ~= nil,
    name .. " is ported or stubbed, so the site answers something deliberate")
end

S.finish()
