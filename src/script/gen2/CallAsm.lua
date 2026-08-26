-- `callasm` / `memcall` / `memcallasm` / `memjump`: the four script commands
-- whose operand is not bytecode.
--
-- Script_callasm (engine/overworld/scripting.asm) reads a three-byte far
-- pointer out of the script and `rst FarCall`s it as raw Game Boy code.
-- Script_memcallasm does the same with a pointer read out of WRAM instead;
-- Script_memcall calls the WRAM pointer as bytecode, and Script_memjump jumps
-- to it and never comes back.  No interpreter can run any of them, so each
-- target routine needs its own hand port, and this file is where they live.
--
-- Dispatch is BY ADDRESS, the way src/script/gen2/Specials.lua dispatches by
-- name.  SITES maps the `bank:addr` pair the command carries -- resolved
-- against pokegold-symbols/pokegold.sym -- onto a routine name, and HANDLERS
-- maps that name onto the port.  Keying on the pair rather than on a counted
-- index means a routine that moved between revisions cannot silently call the
-- wrong port; keying the port on the NAME means the table can be asserted
-- against the symbol file by a test.
--
-- WHAT wScriptVar DOES AND DOES NOT GET WRITTEN.  Script_callasm itself never
-- touches wScriptVar: it is the TARGET routine that does, and only eleven of
-- them do.  A handler therefore returns a byte only when its asm ends in
-- `ld [wScriptVar], a`, and nil otherwise -- nil meaning "leave it alone".
-- Inventing a 0 or a 1 for the rest would pick a branch at random for the
-- `callasm` / `iffalse` pairs (FindItemInBallScript and FruitTreeScript are
-- both one), which is exactly the bug this contract exists to prevent.
--
-- WHAT IS ACTUALLY IN THE CACHE: nothing.  Thirty-eight rows in
-- data/generated/scripts.lua used to carry one of these four opcodes and not
-- one of them was real -- every one sat inside a key the extractor had made
-- out of a three-byte `hiddenitem` bg_event operand (45:697a is
-- IlexForestHiddenEther, 47:40a5 is WhirlIslandB1FHiddenRareCandy) and then
-- disassembled as if it were code.  A cache built since the extractor stopped
-- walking those operands has none at all, and a stale one still misses SITES
-- because its bank/address pairs are noise; tests/gen2_callasm_test.lua
-- asserts that neither resolves.
--
-- The real sites are the fifty-seven in engine/*.asm listed below.  None of
-- those engine scripts is reachable from a map script pointer, so none of them
-- is extracted either, and the port reaches their routines through the
-- hand-ported flows in src/world/gen2/ -- which is why CallAsm.run is a public
-- entry point beside CallAsm.dispatch.  Both roads end at the same table,
-- which is the point of having one.
--
-- love-free: a handler takes the World (or anything shaped like it) and calls
-- back into the module that already owns the behaviour.  Nothing here
-- re-transcribes a table that has a home elsewhere.

local Phone = require("src.core.gen2.Phone")

local CallAsm = {}

-- ---- the site table --------------------------------------------------------
--
-- Every `callasm` / `memcall` / `memcallasm` / `memjump` operand in the cart,
-- resolved against pokegold-symbols/pokegold.sym.  The comment on each group
-- is the file the site is IN; the name is the routine the pointer reaches.
CallAsm.SITES = {
  -- engine/overworld/scripting.asm: GiveItemScript's opening no-op.
  ["25:6e71"] = "GiveItemScript_DummyFunction",
  -- engine/overworld/events.asm: the START and SELECT presses, the queued
  -- script the overworld hands itself, the egg hatch and the facing change.
  ["04:6994"] = "StartMenu",
  ["04:76e9"] = "SelectMenu",
  ["05:7312"] = "OverworldHatchEgg",
  ["25:664f"] = "EnableWildEncounters",
  -- engine/phone/phone.asm and engine/events/mom_phone.asm.
  ["24:4277"] = "RingTwice_StartCall",
  ["24:42df"] = "HangUp",
  ["04:5800"] = "InitCallReceiveDelay",
  ["24:4264"] = "LoadBillScript",
  ["24:4272"] = "LoadElmScript",
  ["3f:4db2"] = "MomTriesToBuySomething_ASMFunction",
  -- engine/items/itemfinder.asm.
  ["04:6960"] = "ItemfinderSound",
  -- engine/events/fruit_trees.asm.
  ["11:4041"] = "GetCurTreeFruit",
  ["11:404c"] = "TryResetFruitTrees",
  ["11:4055"] = "CheckFruitTree",
  ["11:405f"] = "PickedFruitTree",
  -- engine/events/sweet_scent.asm.
  ["14:4725"] = "SweetScentEncounter",
  -- engine/events/trainer_scripts.asm.
  ["02:490e"] = "TrainerWalkToPlayer",
  -- engine/events/squirtbottle.asm.
  ["14:4786"] = "CheckCanUseSquirtbottle",
  -- engine/events/hidden_item.asm.
  ["04:7a11"] = "SetMemEvent",
  -- engine/events/poisonstep.asm.
  ["14:468e"] = "PlayPoisonSFX",
  ["14:46b1"] = "CheckWhitedOut",
  -- engine/events/whiteout.asm.
  ["04:68c7"] = "OverworldBGMap",
  ["04:68d7"] = "BattleBGMap",
  ["04:68e0"] = "HalveMoney",
  ["04:68ee"] = "GetWhiteoutSpawn",
  -- engine/events/overworld.asm: the field moves.
  ["03:474b"] = "GetPartyNickname",
  ["03:4855"] = "CutDownTreeOrGrass",
  ["23:4a6b"] = "BlindingFlash",
  ["00:310a"] = "HideSprites",
  ["23:4d65"] = "FlyFromAnim",
  ["05:560c"] = "SkipUpdateMapSprites",
  ["23:4dab"] = "FlyToAnim",
  ["05:415c"] = "LoadWalkingSpritesGFX",
  ["03:4b49"] = "CheckContinueWaterfall",
  ["03:4d15"] = "SetStrengthFlag",
  ["03:4d7b"] = "TryStrengthOW",
  ["03:4e20"] = "DisappearWhirlpool",
  ["23:4a8e"] = "ShakeHeadbuttTree",
  ["03:4f7f"] = "HasRockSmash",
  ["03:5096"] = "PutTheRodAway",
  ["03:506d"] = "Fishing_CheckFacingUp",
  ["14:454f"] = "LoadFishingGFX",
  ["03:51c7"] = "AskCutScript_CheckMap",
  -- engine/events/treemons.asm, reached from the HEADBUTT and ROCK SMASH arms
  -- of engine/events/overworld.asm.
  ["2e:6378"] = "TreeMonEncounter",
  ["2e:63a1"] = "RockMonEncounter",
  -- engine/events/misc_scripts.asm.
  ["04:66d1"] = "TryReceiveItem",
}

-- pokegold-symbols/pokesilver.sym: bank $03 sits two bytes earlier in Silver.
CallAsm.SITES_SILVER = {
  ["03:4749"] = "GetPartyNickname",
  ["03:4853"] = "CutDownTreeOrGrass",
  ["03:4b47"] = "CheckContinueWaterfall",
  ["03:4d13"] = "SetStrengthFlag",
  ["03:4d79"] = "TryStrengthOW",
  ["03:4e1e"] = "DisappearWhirlpool",
  ["03:4f7d"] = "HasRockSmash",
  ["03:5094"] = "PutTheRodAway",
  ["03:506b"] = "Fishing_CheckFacingUp",
  ["03:51c5"] = "AskCutScript_CheckMap",
}

-- pokecrystal-symbols/pokecrystal.sym: Crystal's own addresses for the same sites.
CallAsm.SITES_CRYSTAL = {
  ["25:6f76"] = "GiveItemScript_DummyFunction",
  ["04:65cd"] = "StartMenu",
  ["04:7327"] = "SelectMenu",
  ["05:6f5e"] = "OverworldHatchEgg",
  ["25:6706"] = "EnableWildEncounters",
  ["24:426f"] = "RingTwice_StartCall",
  ["24:42eb"] = "HangUp",
  ["04:53e5"] = "InitCallReceiveDelay",
  ["24:425c"] = "LoadBillScript",
  ["24:426a"] = "LoadElmScript",
  ["3f:5017"] = "MomTriesToBuySomething_ASMFunction",
  ["04:6599"] = "ItemfinderSound",
  ["14:46ef"] = "SweetScentEncounter",
  ["02:431e"] = "TrainerWalkToPlayer",
  ["14:4753"] = "CheckCanUseSquirtbottle",
  ["04:764f"] = "SetMemEvent",
  ["14:4658"] = "PlayPoisonSFX",
  ["14:467b"] = "CheckWhitedOut",
  ["04:64fa"] = "OverworldBGMap",
  ["04:650a"] = "BattleBGMap",
  ["04:6513"] = "HalveMoney",
  ["04:6527"] = "GetWhiteoutSpawn",
  ["03:4706"] = "GetPartyNickname",
  ["03:4810"] = "CutDownTreeOrGrass",
  ["23:47e1"] = "BlindingFlash",
  ["00:3016"] = "HideSprites",
  ["23:4aed"] = "FlyFromAnim",
  ["05:54f1"] = "SkipUpdateMapSprites",
  ["23:4b33"] = "FlyToAnim",
  ["05:4157"] = "LoadWalkingSpritesGFX",
  ["03:4b38"] = "CheckContinueWaterfall",
  ["03:4d12"] = "SetStrengthFlag",
  ["03:4d78"] = "TryStrengthOW",
  ["03:4e1d"] = "DisappearWhirlpool",
  ["23:480a"] = "ShakeHeadbuttTree",
  ["03:4f7c"] = "HasRockSmash",
  ["03:5095"] = "PutTheRodAway",
  ["03:506c"] = "Fishing_CheckFacingUp",
  ["2e:44b3"] = "LoadFishingGFX",
  ["03:51ba"] = "AskCutScript_CheckMap",
  ["2e:41ea"] = "TreeMonEncounter",
  ["2e:4219"] = "RockMonEncounter",
  ["04:62f8"] = "TryReceiveItem",
}

-- The three WRAM addresses `memcall` / `memcallasm` / `memjump` take instead of
-- a routine.  Not sites: the pointer AT the address is written at run time
-- (LoadMemScript for the queued script, the phone engine for the other two),
-- so there is nothing static to resolve and nothing to port.  Kept so a test
-- can tell "a WRAM operand" apart from "a routine nobody has named yet".
CallAsm.MEM_OPERANDS = {
  ["00:cfd8"] = "wQueuedScriptBank",
  ["00:ceed"] = "wPhoneScriptBank",
  ["00:cf2a"] = "wCallerContact",
}

-- ---- constants -------------------------------------------------------------

-- constants/map_object_constants.asm.  The port already keeps
-- SPRITEMOVEDATA_STRENGTH_BOULDER ($19) in World; this is its neighbour.
local SPRITEMOVEDATA_SUDOWOODO = 0x17

-- constants/sfx_constants.asm, resolved by LABEL at call time the way
-- src/world/gen2/HiddenItems.lua does it; the numbers are only the fallback
-- for a cache whose sfx table sits somewhere else.
local SFX_POISON = { "Sfx_Poison", 11 }
local SFX_SECOND_PART_OF_ITEMFINDER = { "Sfx_SecondPartOfItemfinder", 18 }
local SFX_TRANSACTION = { "Sfx_Transaction", 34 }
local SFX_CALL = { "Sfx_Call", 106 }

-- ItemFinder.ItemfinderSound's `ld c, 4`.
local ITEMFINDER_SFX_LOOPS = 4

-- data/maps/spawn_points.asm.  SPAWN_HOME is the first row, and it is what
-- GetWhiteoutSpawn falls back to when IsSpawnPoint says no.
local SPAWN_HOME = "SPAWN_HOME"

-- ---- ctx plumbing ----------------------------------------------------------

-- A handler talks to the World through its own methods, and every one of them
-- is optional: a headless test hands in a table with two of them and the rest
-- of the file still runs.  That is the same bargain Specials strikes with its
-- hook table, and it is what makes this dispatch testable without a map.
local function call(ctx, name, ...)
  local fn = ctx and ctx[name]
  if type(fn) ~= "function" then return nil end
  return fn(ctx, ...)
end

local function saveOf(ctx)
  return ctx and ctx.game and ctx.game.save or nil
end

-- ---- the phone's caller-ID box ---------------------------------------------
--
-- Phone_TextboxWithName is the one routine in this file that DRAWS, so it is
-- the one place a handler reaches past the World's method table: the box is a
-- state on src/core/StateStack.lua, pushed under the call's text pages the way
-- the cart's box sits under the speech box.  The require is lazy and the whole
-- pair is a no-op without a stack, so the "love-free" bargain at the top of
-- this file still holds for every headless caller.
--
-- The state is tagged rather than tracked in a local: a handler is dispatched
-- from wherever the script happens to be running, and a module-level handle
-- would outlive a save reload or a second world.
local CALLER_BOX = "gen2CallerBox"

local function stackOf(ctx)
  return ctx and ctx.game and ctx.game.stack or nil
end

-- GetCallerClassAndName reads wCurCaller (engine/phone/phone.asm:471-475), and
-- vm.curPhoneCaller is this port's wCurCaller: World:receivePhoneCall and
-- World:momTriesToBuy both park the PHONE_* contact there before the rows run.
-- Contact 0 is the wrong-number script, which NonTrainerCallerNames answers
-- for -- Phone.contactName already makes that distinction.
local function showCallerBox(ctx)
  local stack = stackOf(ctx)
  if not stack then return end
  for _, state in ipairs(stack.states or {}) do
    if state[CALLER_BOX] then return end
  end
  local contact = (ctx.vm and ctx.vm.curPhoneCaller) or 0
  local data = ctx.game and ctx.game.data
  local name, className = Phone.contactName(contact, data and data.trainers)
  local box = require("src.ui.gen2.CallerBox").new(name, className)
  box[CALLER_BOX] = true
  stack:push(box)
end

-- The box is the top of the stack when this runs, and StateStack:pop is what
-- takes it off -- so `exit` and screen.popped fire the way they do for every
-- other Gold screen.  It CAN only be the top: src/core/Game2.lua's fixed step
-- hands the tick to the top state and returns whenever that state has an
-- `update`, so the VM this handler is running inside is not advancing at all
-- while a text page is over the box.  The by-identity search below is the
-- guard for the day that stops being true (a mod screen pushed from a hook,
-- say): the box comes off either way, because a caller box left on the stack
-- would sit over the overworld forever with nothing to take it down.
local function hideCallerBox(ctx)
  local stack = stackOf(ctx)
  local states = stack and stack.states
  if not states then return end
  for index = #states, 1, -1 do
    if states[index][CALLER_BOX] then
      if index == #states then
        stack:pop()
      else
        table.remove(states, index)
      end
      return
    end
  end
end

local H = {}

-- ---- engine/overworld/scripting.asm ---------------------------------------

-- GiveItemScript_DummyFunction is one `ret`.  It exists so GiveItemScript
-- opens on a command rather than on `writetext`, and the port keeps it named
-- so the site is accounted for instead of falling through as unknown.
function H.GiveItemScript_DummyFunction()
  return nil
end

-- ---- engine/overworld/events.asm ------------------------------------------

-- SelectMenuScript's `callasm SelectMenu` reaches UseRegisteredItem
-- (engine/overworld/select_menu.asm), which is exactly World:useSelectItem:
-- the four ITEMMENU_* arms plus CantUseItem's two "nothing registered" and
-- "no field handler" cases.  StartMenu, its neighbour in the same table, is a
-- stub instead -- the START menu is a pushed screen, not a blocking call.
function H.SelectMenu(ctx)
  call(ctx, "useSelectItem")
  return nil
end

-- HatchEggScript is `callasm OverworldHatchEgg / end`: the whole player event
-- is this one routine.  World:hatchEggs is HatchEggs
-- (engine/pokemon/breeding.asm) with its four text beats.
function H.OverworldHatchEgg(ctx)
  call(ctx, "hatchEggs")
  return nil
end

-- ---- engine/phone/phone.asm and engine/overworld/time.asm -----------------

-- RingTwice_StartCall: Phone_StartRinging's SFX_CALL and the flashing
-- caller-ID box, twice over on a twenty-frame cadence.
--
-- Both halves are here.  The SOUND is the ring the player hears.  The BOX is
-- .CallerTextboxWithName -> Phone_TextboxWithName (engine/phone/phone.asm:466,
-- :474, :582), the four-row strip across the top of the screen naming who is
-- calling; src/ui/gen2/CallerBox.lua is its port and carries the layout.  This
-- port's textbox holds for A where the cart's PrintText returns, so the six
-- twenty-frame flashes have nowhere to live -- the box simply goes up with the
-- first ring and stays, which is the state the cart leaves it in anyway: it is
-- written straight into wTilemap, CloseText restores it with everything else
-- under the speech box, and only the overworld's own tilemap redraw at the end
-- of the call takes it down (which is what InitCallReceiveDelay does below).
--
-- Idempotent, because Script_ReceivePhoneCall rings TWICE and a second box
-- would bury the first.  ctx.game is absent in the pure-module tests and in
-- any headless harness, and then the ring is all there is to do.
function H.RingTwice_StartCall(ctx)
  call(ctx, "playSfxNamed", SFX_CALL[1], SFX_CALL[2])
  showCallerBox(ctx)
  return nil
end

-- InitCallReceiveDelay (engine/overworld/time.asm): zero
-- wTimeCyclesSinceLastCall and restart the receive countdown at its twenty
-- in-game minutes.  StartMap runs it on every map load (World:setMap ->
-- Phone.onMapLoad) and Script_ReceivePhoneCall's tail runs it here, so a
-- hung-up call arms the same timer a warp does.
function H.InitCallReceiveDelay(ctx)
  -- The caller-ID box comes down here, and only here.  Script_ReceivePhoneCall
  -- runs this as its LAST row (engine/phone/phone.asm:431-438), which is the
  -- moment the cart's overworld redraws its tilemap over the strip -- there is
  -- no routine that erases the box, so there is no row to hang the teardown on
  -- but this one.  Ahead of the countdown, so a save-less harness still tidies
  -- the screen.
  hideCallerBox(ctx)
  local save = saveOf(ctx)
  if not save then return nil end
  local step = call(ctx, "stepContext")
  Phone.initReceiveDelay(save, step and step.phone)
  return nil
end

-- ---- engine/items/itemfinder.asm ------------------------------------------

-- .ItemfinderSound: four times round SFX_SECOND_PART_OF_ITEMFINDER then
-- SFX_TRANSACTION, each through WaitPlaySFX so the pair does not overlap.
-- The port plays them back to back; there is no channel to wait on.
function H.ItemfinderSound(ctx)
  for _ = 1, ITEMFINDER_SFX_LOOPS do
    call(ctx, "playSfxNamed", SFX_SECOND_PART_OF_ITEMFINDER[1],
      SFX_SECOND_PART_OF_ITEMFINDER[2])
    call(ctx, "playSfxNamed", SFX_TRANSACTION[1], SFX_TRANSACTION[2])
  end
  return nil
end

-- ---- engine/events/fruit_trees.asm ----------------------------------------
--
-- All four read wCurFruitTree, which `fruittree tree_id` sets before it jumps
-- to FruitTreeScript; `ctx.curFruitTree` is that byte.  The item table itself
-- lives in src/core/gen2/Apricorns.lua and is reached through World.

-- GetCurTreeFruit: FruitTreeItems[wCurFruitTree - 1] -> wCurFruit.  The `dec a`
-- is the cart turning a 1-based FRUITTREE_* into a 0-based offset, which
-- World:fruitTreeItem already undoes, so nothing is shifted here.
function H.GetCurTreeFruit(ctx)
  local tree = (ctx and ctx.curFruitTree) or 0
  ctx.curFruit = call(ctx, "fruitTreeItem", tree) or 0
  return nil
end

-- TryResetFruitTrees: gated on DAILYFLAGS1_ALL_FRUIT_TREES, so the FIRST tree
-- examined after the daily rollover refills every tree in the game.
function H.TryResetFruitTrees(ctx)
  call(ctx, "fruitTreeReset")
  return nil
end

-- CheckFruitTree is `ld b, 2 / GetFruitTreeFlag`, a CHECK_FLAG over
-- wFruitTreeFlags, and it puts the flag itself in wScriptVar.  The flag means
-- "already picked", so a CLEAR flag is the arm with fruit on it -- which is
-- why FruitTreeScript reads it with `iffalse .fruit`.
function H.CheckFruitTree(ctx)
  local tree = (ctx and ctx.curFruitTree) or 0
  return call(ctx, "fruitTreePicked", tree) and 1 or 0
end

-- PickedFruitTree is `ld b, 1 / GetFruitTreeFlag`: SET_FLAG, no wScriptVar.
function H.PickedFruitTree(ctx)
  local tree = (ctx and ctx.curFruitTree) or 0
  call(ctx, "fruitTreePick", tree)
  return nil
end

-- ---- engine/events/overworld.asm ------------------------------------------

-- GetPartyNickname copies wCurPartyMon's nickname into wStringBuffer1-3, which
-- is what {STRBUF} reads back for "<nickname> used CUT!".  wCurPartyMon is
-- whatever CheckPartyMove last left there, and `ctx.curPartyMon` is the port's
-- name for the same slot.  Five separate `callasm` sites reach it.
function H.GetPartyNickname(ctx)
  local mon = ctx and ctx.curPartyMon
  if not mon then
    local save = saveOf(ctx)
    mon = save and save.party and save.party[1] or nil
  end
  call(ctx, "setNickname", mon)
  return nil
end

-- CutDownTreeOrGrass writes wCutWhirlpoolReplacementBlock over the block at
-- wCutWhirlpoolOverworldBlockAddr, redraws, then plays OWCutAnimation.  The
-- port owns the pair as World:replaceBlock, which is also what drops the map's
-- baked canvases -- a bake is keyed by map and daytime and knows nothing about
-- the blocks it came from, so a changed block that skips it stays on screen.
-- `ctx.cutWhirlpoolBlockIndex` / `ctx.cutWhirlpoolReplacement` are the port's
-- wCutWhirlpoolOverworldBlockAddr and wCutWhirlpoolReplacementBlock: an index
-- into the loaded map's block buffer rather than a pointer into it.
function H.CutDownTreeOrGrass(ctx)
  local index = ctx and ctx.cutWhirlpoolBlockIndex
  local blockId = ctx and ctx.cutWhirlpoolReplacement
  if index and blockId then call(ctx, "replaceBlock", index, blockId) end
  return nil
end

-- DisappearWhirlpool is CutDownTreeOrGrass with PlayWhirlpoolSound in place of
-- OWCutAnimation: the same block write, the same redraw, then the surf wash the
-- port owns as World:playWhirlpoolSound.  #1717
function H.DisappearWhirlpool(ctx)
  local ret = H.CutDownTreeOrGrass(ctx)
  call(ctx, "playWhirlpoolSound")
  return ret
end

-- BlindingFlash sets STATUSFLAGS_FLASH_F and reloads the palettes.  Setting
-- the flag is all there is to it here: Palettes.daytimeFor already turns a
-- flashed PALETTE_DARK map into a NITE one, which is the cart's .UsedFlash
-- arm, and the reload is the port's own baked-canvas drop.
function H.BlindingFlash(ctx)
  if not ctx then return nil end
  ctx.flashUsed = true
  if call(ctx, "applyPalettes") then call(ctx, "refreshMapImages") end
  return nil
end

-- .CheckContinueWaterfall, the bottom of Script_UsedWaterfall's loop: TRUE
-- when the tile the player has just climbed onto is ANOTHER waterfall tile,
-- and the `iffalse .loop` reads it inverted -- 0 keeps climbing.
function H.CheckContinueWaterfall(ctx)
  local coll = call(ctx, "playerCollision")
  local FieldMoves = require("src.world.gen2.FieldMoves")
  return FieldMoves.waterfallContinues(coll) and 1 or 0
end

-- SetStrengthFlag: BIKEFLAGS_STRENGTH_ACTIVE, wStrengthSpecies from the mon
-- CheckPartyMove picked, and then a tail call into GetPartyNickname.  It runs
-- FIRST, before the text, which is why the line that follows can name the mon.
function H.SetStrengthFlag(ctx)
  ctx.strengthActive = true
  local mon = ctx and ctx.curPartyMon
  if mon then ctx.strengthSpecies = mon.species end
  return H.GetPartyNickname(ctx)
end

-- TryStrengthOW's three answers, and note the inversion in the cart: `bit
-- BIKEFLAGS_STRENGTH_ACTIVE_F` jumps to .already_using when the bit is CLEAR,
-- so 2 is the not-yet case and 0 the already-on one.
--   0  STRENGTH is already active
--   1  no mon knows it, or no PLAINBADGE
--   2  it may be switched on right now
function H.TryStrengthOW(ctx)
  local FieldMoves = require("src.world.gen2.FieldMoves")
  local fieldCtx = call(ctx, "fieldContext")
  if not fieldCtx then return 1 end
  local result = FieldMoves.tryStrengthOW(fieldCtx)
  if result.ok then return 2 end
  if fieldCtx.strengthActive then return 0 end
  return 1
end

-- .CheckMap, inside AskCutScript and reached only after the YES: it is
-- CheckMapForSomethingToCut with the answer inverted into wScriptVar, so the
-- `iftrue Script_Cut` that follows fires on 1.
function H.AskCutScript_CheckMap(ctx)
  local FieldMoves = require("src.world.gen2.FieldMoves")
  local fieldCtx = call(ctx, "fieldContext")
  if not fieldCtx then return 0 end
  return FieldMoves.somethingToCut(fieldCtx) and 1 or 0
end

-- HasRockSmash is INVERTED: `call CheckPartyMove / jr nc, .yes` puts 1 in
-- wScriptVar when the party does NOT know ROCK SMASH, which is why
-- AskRockSmashScript reads it with `ifequal 1, .no`.  Transcribing it the
-- obvious way round refuses the move for every party that has it.
function H.HasRockSmash(ctx)
  local mon = call(ctx, "partyMoveUser", "ROCK_SMASH")
  if mon then
    -- engine/events/overworld.asm:1339
    ctx.curPartyMon = mon
    return 0
  end
  return 1
end

-- PutTheRodAway: ClearBox over the text window, then wPlayerAction back to
-- PLAYER_NORMAL so the fishing sprite drops.  Two of the fishing scripts end
-- on it and one has it in the middle, and in this port the whole rod pose is
-- World's `fishing` state -- dropping it IS wPlayerAction going back to
-- normal.  It has to be gone before a battle is pushed, or World:busy would
-- still be holding the world when the battle returns.
function H.PutTheRodAway(ctx)
  if ctx then ctx.fishing = nil end
  return nil
end

-- Fishing_CheckFacingUp: `and $c / cp OW_UP`.  The rod is only cast upward
-- from a shore tile, and a 1 here is what lets the bite script run.
function H.Fishing_CheckFacingUp(ctx)
  local player = ctx and ctx.player
  return (player and player.facing == "up") and 1 or 0
end

-- ---- engine/events/treemons.asm -------------------------------------------

-- TreeMonEncounter: GetTreeMonSet / GetTreeMons / GetTreeMon, and
-- BATTLETYPE_TREE plus wScriptVar = 1 only if all three came back with carry.
-- The roll needs the tree's own cell, which HeadbuttScript left in the object
-- coordinates; `ctx.curHeadbuttCell` is the port's name for the same pair.
--
-- World:tryHeadbutt fuses the roll with the `startbattle` that follows it in
-- the script, so a "battle" answer here is the 1 and everything else the 0.
-- That fusing is why the port's own headbutt path calls tryHeadbutt directly
-- rather than coming through this routine.
function H.TreeMonEncounter(ctx)
  local cell = ctx and ctx.curHeadbuttCell
  if not cell then return 0 end
  return call(ctx, "tryHeadbutt", cell[1], cell[2]) == "battle" and 1 or 0
end

-- RockMonEncounter is that same twin over RockMonMaps with a flat 40 percent
-- (`ld a, 10 / RandomRange / cp 4`) where the tree has its coordinate score.
-- It writes NO wScriptVar: RockSmashScript reads the answer back one row later
-- with `readmem wTempWildMonSpecies / iffalse`, so returning a number here
-- would decide a branch the cart decides some other way.  World's own routine
-- leaves the pair where that readmem can see it, and where the `randomwildmon`
-- two rows further down takes it into the battle.
function H.RockMonEncounter(ctx)
  call(ctx, "rockMonEncounter")
  return nil
end

-- ---- engine/events/sweet_scent.asm ----------------------------------------

-- SweetScentEncounter: the same CanEncounterWildMon gate a step takes, but
-- every percentage roll downstream is skipped -- GetMapEncounterRate only has
-- to come back nonzero.  World:sweetScentEncounter is that whole routine.
function H.SweetScentEncounter(ctx)
  return call(ctx, "sweetScentEncounter") and 1 or 0
end

-- ---- engine/events/trainer_scripts.asm ------------------------------------

-- TrainerWalkToPlayer builds the movement that closes the gap and hands it to
-- the applymovement that follows.  The World owns the path, so this is the
-- same seam the VM's `trainerapproach` branch uses.  No wScriptVar.
function H.TrainerWalkToPlayer(ctx)
  call(ctx, "trainerApproach")
  return nil
end

-- ---- engine/events/squirtbottle.asm ---------------------------------------

-- .CheckCanUseSquirtbottle: Route 36, and the object the player is facing has
-- to carry SPRITEMOVEDATA_SUDOWOODO.  Anything else is a 0 and the item says
-- nothing happened.  GetFacingObject's own carry (nobody there) is the same 0.
function H.CheckCanUseSquirtbottle(ctx)
  local map = ctx and ctx.map
  if not (map and map.id == "ROUTE_36") then return 0 end
  local player = ctx.player
  if not player then return 0 end
  local Map = require("src.world.gen2.Map")
  local delta = Map.DELTA[player.facing or "down"] or Map.DELTA.down
  local npc = call(ctx, "npcAt", player.cellX + delta[1], player.cellY + delta[2])
  local def = npc and npc.def
  if def and def.movement == SPRITEMOVEDATA_SUDOWOODO then return 1 end
  return 0
end

-- ---- engine/events/hidden_item.asm ----------------------------------------

-- SetMemEvent sets the flag whose number is sitting in wHiddenItemEvent, the
-- word the `hiddenitem` bg_event operand carries beside the item.  It runs
-- AFTER the giveitem, so a full bag leaves the item on the map.
--
-- wEventFlags is keyed by NUMBER: the operand is already one, and passing a
-- name here would throw.
function H.SetMemEvent(ctx)
  local flag = ctx and ctx.hiddenItemEvent
  if flag and ctx.events then ctx.events:set(flag, true) end
  return nil
end

-- ---- engine/events/poisonstep.asm -----------------------------------------

-- .PlayPoisonSFX: SFX_POISON, then LoadPoisonBGPals for four frames.
-- engine/events/poisonstep.asm:101
function H.PlayPoisonSFX(ctx)
  call(ctx, "playSfxNamed", SFX_POISON[1], SFX_POISON[2])
  call(ctx, "poisonBGFlash")
  return nil
end

-- .CheckWhitedOut walks wPoisonStepPartyFlags, applies HAPPINESS_POISONFAINT
-- and prints one line per mon that actually dropped, and ends on
-- CheckPlayerPartyForFitMon -- whose `d` is 1 when something can still fight.
-- The `iffalse .whiteout` that follows is therefore reading "no fit mon".
--
-- The happiness hit and the naming are World:poisonFaintScript's, because they
-- have to be spread over as many text boxes as there were faints; what is left
-- for this routine is the answer.
function H.CheckWhitedOut(ctx)
  local StepEvents = require("src.world.gen2.StepEvents")
  local save = saveOf(ctx)
  local party = (save and save.party) or {}
  return StepEvents.whitedOut(party) and 0 or 1
end

-- ---- engine/events/whiteout.asm -------------------------------------------

-- HalveMoney shifts wMoney right one bit as a 24-bit big-endian value:
-- `srl a` on the high byte then `rra` twice, so the carry walks down and the
-- whole three bytes end up halved with the remainder dropped.  That is floor
-- division for every value wMoney can hold, and the wallet ALONE -- Mom's
-- savings are a separate three bytes the routine never reaches.
function H.HalveMoney(ctx)
  local save = saveOf(ctx)
  local player = save and save.player
  if not player then return nil end
  player.money = math.floor((player.money or 0) / 2)
  return nil
end

-- GetWhiteoutSpawn validates wLastSpawnMapGroup / wLastSpawnMapNumber (the
-- pair `blackoutmod` writes) against the SpawnPoints table and falls back to
-- SPAWN_HOME when it is not one of them, which is what stops a whiteout at sea
-- from respawning the player somewhere they cannot leave.
--
-- Registered and ported, but NOT yet consumed: World:warpToSpawn prefers the
-- blackout map itself over the SPAWN_* row it matches, which is a deliberate
-- divergence tests/gen2_world_test.lua pins.  The spawn id is left on the ctx
-- for the day that changes.
function H.GetWhiteoutSpawn(ctx)
  local save = saveOf(ctx)
  local override = save and save.blackoutMap
  local spawns = ctx and ctx.landmarks and ctx.landmarks.spawns
  local answer = SPAWN_HOME
  if override and type(spawns) == "table" then
    for id, row in pairs(spawns) do
      if type(row) == "table" and row.map == override then
        answer = id
        break
      end
    end
  end
  ctx.defaultSpawnpoint = answer
  return nil
end

-- ---- stubs -----------------------------------------------------------------
--
-- { name, wScriptVar or nil, reason }.  A nil second field is the whole point
-- for most of these: the asm writes no wScriptVar, so neither does the stub.
local STUB_ROWS = {
  -- Graphics and VRAM.  Every one of these is a tilemap, palette or sprite
  -- reload around an animation the port's renderer draws its own way; there is
  -- no VRAM here to load anything into.
  { "OverworldBGMap", nil, "ClearPalettes / ClearScreen / RotateThreePalettesLeft: the fade to white is the renderer's" },
  { "BattleBGMap", nil, "SCGB_BATTLE_GRAYSCALE through GetSGBLayout: no SGB layout in this port" },
  { "HideSprites", nil, "clears OAM for the FLY animation; the port hides the party sprite itself" },
  { "FlyFromAnim", nil, "the bird's own frames; World:flyTo lifts the player under the setup script's fade instead" },
  { "FlyToAnim", nil, "the landing frames; the same lift read backwards under the fade in" },
  { "SkipUpdateMapSprites", nil, "suppresses one UpdateMapSprites while FLY is mid-air" },
  { "LoadWalkingSpritesGFX", nil, "reloads the walking sprite bank after FLY lands" },
  { "LoadFishingGFX", nil, "the rod and bobber tiles, which the extractor does not carry; World:updateFishing bobs the player instead" },
  { "ShakeHeadbuttTree", nil, "the tree wobble frames; World:runHeadbutt owns the shake and the outcome" },
  -- The START menu is a pushed screen with its own lifetime, not something a
  -- script coroutine can block on the way the cart's StartMenu does.
  { "StartMenu", nil, "the START menu is a Screens.push state, not a blocking call" },
  -- The phone.  These four write into wCallerContact / wPhoneScriptBank so
  -- that the `memcall` two lines later has somewhere to jump.  The port's
  -- call descriptors carry their scripts.lua key instead (bank $41 is
  -- extracted through PhoneContacts now), so the pointer plumbing has nothing
  -- to store: src/core/gen2/PhoneRing.lua hands the VM the caller script
  -- directly, and RingTwice_StartCall / InitCallReceiveDelay above are the
  -- two halves of Script_ReceivePhoneCall that still had asm to port.
  { "HangUp", nil, "the VM's own `hangup` op carries the Click! and SFX_HANG_UP; PhoneRing.script uses it in this row's place" },
  { "LoadBillScript", nil, "writes wCallerContact for Script_SpecialBillCall; the call descriptor names the script key instead" },
  { "LoadElmScript", nil, "writes wCallerContact for Script_SpecialElmCall; the call descriptor names the script key instead" },
  { "MomTriesToBuySomething_ASMFunction", nil, "queues Mom's pages into wCallerContact; World:momTriesToBuy hands the same rows to PhoneRing.script" },
  -- wEnabledPlayerEvents has no home in this port: nothing ever CLEARS
  -- PLAYEREVENTS_WILD_ENCOUNTERS here, so re-enabling it is already the
  -- standing state and a write would be a write nobody reads.  Not the same
  -- byte as STATUSFLAGS_NO_WILD_ENCOUNTERS_F, which `wildoff` owns.
  { "EnableWildEncounters", nil, "the port has no wEnabledPlayerEvents; the bit is never cleared" },
  -- FindItemInBallScript's opener.  The port reaches Poke Ball items through
  -- the object's own itemball row rather than through this script, so the
  -- ReceiveItem here has no bag to write to and no wItemBallItemID to read.
  -- A 0 or a 1 would pick the "no room" arm at random, so it stays nil.
  { "TryReceiveItem", nil, "wItemBallItemID / wItemBallQuantity are set by a script path this port does not run" },
}

CallAsm.HANDLERS = H
CallAsm.STUBS = {}
CallAsm.STUB_REASONS = {}

for _, row in ipairs(STUB_ROWS) do
  local name, value, reason = row[1], row[2], row[3]
  CallAsm.STUB_REASONS[name] = reason
  CallAsm.STUBS[name] = function()
    return value
  end
end

-- The merged table, built rather than written out so the two sets cannot
-- drift and so a name in both is a hard error here instead of a silent shadow.
CallAsm.ALL = {}
for name, fn in pairs(CallAsm.HANDLERS) do
  CallAsm.ALL[name] = fn
end
for name, fn in pairs(CallAsm.STUBS) do
  if CallAsm.ALL[name] then
    error("gen2 callasm routine '" .. name .. "' is both implemented and stubbed", 0)
  end
  CallAsm.ALL[name] = fn
end

-- ---- dispatch --------------------------------------------------------------

-- The `bank:addr` key, lower case hex, two digits and four -- the same shape
-- data/generated/scripts.lua uses for its own script keys, so the two can be
-- compared by eye.
function CallAsm.key(bank, addr)
  return string.format("%02x:%04x", (bank or 0) % 0x100, (addr or 0) % 0x10000)
end

-- The routine name for a site, or nil.  `label` wins when the extractor has
-- one (it does not today: nothing resolves bank:addr against the symbol file
-- at import time), and the address pair is the fallback that always works.
function CallAsm.nameFor(label, bank, addr)
  if label and CallAsm.ALL[label] then return label end
  local key = CallAsm.key(bank, addr)
  return CallAsm.SITES[key] or CallAsm.SITES_SILVER[key] or CallAsm.SITES_CRYSTAL[key]
end

-- Run a routine by name.  Returns the byte the asm leaves in wScriptVar, or
-- nil when it writes none -- and an unknown name is nil too, because a routine
-- nobody has ported must not decide a branch.
function CallAsm.run(ctx, name)
  local fn = CallAsm.ALL[name]
  if not fn then return nil end
  local ok, value = pcall(fn, ctx)
  -- A handler that throws is a bug, but it must not take the script down with
  -- it: the cart's own callasm cannot fail, so the branch after it still has
  -- to see the "left alone" answer rather than an aborted coroutine.
  if not ok then return nil end
  if type(value) ~= "number" then return nil end
  return value % 0x100
end

-- The VM seam: src/script/gen2/Vm.lua's `callasm` / `memcallasm` branch, via
-- World:callAsm.  Nil for anything not in the table, which is every row in
-- this cache -- all thirty-eight of them are mis-decoded `hiddenitem` data.
function CallAsm.dispatch(ctx, label, bank, addr)
  local name = CallAsm.nameFor(label, bank, addr)
  if not name then return nil end
  return CallAsm.run(ctx, name)
end

return CallAsm
