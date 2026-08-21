-- Gen 2 script VM over import-extracted command lists (data/generated/scripts.lua).
-- Yields on text / yesorno / movement / waitsfx so the overworld can drive UI.

local Movement = require("src.script.gen2.Movement")
local Opcodes = require("src.script.gen2.Opcodes")
local Specials = require("src.script.gen2.Specials")
local Strings = require("src.core.Strings")
local Logger = require("src.core.Logger")
-- The mod event/hook buses.  Null objects until a loader installs the live
-- ones, so every emit/call site below is a safe pass-through on a headless or
-- mod-free boot, and the Runtime.wants* guards keep even the payload
-- construction off that path.
local Runtime = require("src.mods.Runtime")

local unpack = table.unpack or unpack -- LuaJIT (LÖVE) compatibility

local Vm = {}
Vm.__index = Vm

-- The op name a mod's row carries; no cart byte decodes to it.  See
-- src/script/gen2/Opcodes.lua and Vm:runModCommand.
local MOD_COMMAND = Opcodes.MOD_COMMAND

local function arg1(cmd)
  if cmd == nil then return nil end
  if cmd.args then return cmd.args[1] end
  return nil
end

-- constants/script_constants.asm.  LAST_TALKED is -2, so the byte the
-- extractor writes is 254: `disappear LAST_TALKED` means hLastTalked, not
-- object 254.  Script_disappear / Script_turnobject / Script_writeobjectxy all
-- carry that substitution; Script_appear pointedly does not.
local LAST_TALKED = 0xfe
-- CompareMoneyAction writes one of these three to wScriptVar, and HAVE_MORE is
-- ZERO: an `iffalse` after a checkmoney / checkcoins means the player has MORE
-- than the amount asked for, not less.  Getting that round the wrong way is the
-- whole of the Goldenrod coin vendor.
local HAVE_MORE, HAVE_AMOUNT, HAVE_LESS = 0, 1, 2
-- CheckPokeMail's five answers; REFUSED is what SelectMonFromParty's carry
-- produces when the player backs out, and so also what a driver with no mail
-- handler at all gets.  The model is src/core/gen2/Mail.lua.
local POKEMAIL_REFUSED = 2
-- Script_askforphonenumber's three answers.  SUCCESS IS ZERO here.
local PHONE_CONTACT_GOT, PHONE_CONTACTS_FULL, PHONE_CONTACT_REFUSED = 0, 1, 2
-- constants/misc_constants.asm: the caps GiveMoney and GiveCoins write back.
local MAX_MONEY, MAX_COINS = 999999, 9999
-- constants/sfx_constants.asm
local SFX_ITEM, SFX_HANG_UP = 0x01, 0x6b
-- constants/script_constants.asm: EMOTE_FROM_MEM is -1, i.e. the byte $ff.
local EMOTE_FROM_MEM = 0xff
-- constants/misc_constants.asm GS_VERSION: 0 Gold, 1 Silver.
local GS_VERSION_GOLD = 0
-- engine/overworld/variables.asm .VarActionTable rows for wMapGroup and
-- wMapNumber.  `readvar` is the only route this VM has to either, and the pair
-- is how the CART names a map (constants/map_constants.asm map_const): see
-- Vm:scriptCtx, which reports them to mods.  Same ids World:readVar answers on.
local VAR_MAPGROUP, VAR_MAPNUMBER = 0x0c, 0x0d
-- wBattleResult (constants/battle_constants.asm), which is what `startbattle`
-- leaves in wScriptVar.  A win is ZERO: see the command for the scripts that
-- depend on it.  DRAW is the Sudowoodo / Gyarados "it fled" case; no battle
-- resumes with it yet, so it is here for the branch rather than for a caller.
local BATTLE_RESULTS = { win = 0, lose = 1, draw = 2 }
-- ItemPocketNames (data/items/pocket_names.asm), indexed by the item type
-- CheckItemPocket leaves in wItemAttributeValue: ITEM 1, KEY_ITEM 2, BALL 3,
-- TM_HM 4 (constants/item_data_constants.asm:15-19).  GetPocketName copies the
-- matching string into wStringBuffer3, which is the SECOND blank in both
-- _PutItemInPocketText and _PocketIsFullText (data/text/common_2.asm:1351,
-- :1361).  The cache's items.lua carries the same four names on `pocket`.
local POCKET_NAMES = {
  ITEM = "ITEM POCKET",
  KEY_ITEM = "KEY POCKET",
  BALL = "BALL POCKET",
  TM_HM = "TM POCKET",
}

-- CompareMoney (engine/events/money.asm) reports account minus amount as one
-- of the HAVE_* three rather than as a boolean.
local function compareFunds(account, amount)
  if account < amount then return HAVE_LESS end
  if account == amount then return HAVE_AMOUNT end
  return HAVE_MORE
end

-- givemoney / takemoney / checkmoney lay their operand down as `db account`
-- followed by `bigdt money` (macros/scripts/events.asm), and the extractor
-- leaves that untouched in `args`: args[1] is the account, args[2..4] are the
-- three money bytes BIG-endian.
local function moneyArgs(cmd)
  local a = cmd.args or {}
  return a[1] or 0,
    (a[2] or 0) * 0x10000 + (a[3] or 0) * 0x100 + (a[4] or 0)
end

-- The plain `dw` operands (coins, WRAM addresses, menu headers, mail and call
-- pointers) are little-endian in ROM whatever order the routine that reads them
-- stores them in: LoadCoinAmountToMem flips its two bytes into hMoneyTemp, but
-- the value in the script is still args[1] + args[2] * 256.
local function wordArg(cmd, first)
  local a = cmd.args or {}
  first = first or 1
  return (a[first] or 0) + (a[first + 1] or 0) * 0x100
end

-- The operand list of a MOD's row (Vm:runModCommand): `args` as the row wrote
-- it, or the tail of a Gen 1 shaped row -- { "mymod:shake", 4, 2 } -> { 4, 2 }.
-- Built fresh per dispatch rather than cached on the row, because the row
-- belongs to the mod and this VM does not write to other people's tables.
local function modArgs(cmd)
  if cmd.args then return cmd.args end
  local out = {}
  for i = 2, #cmd do out[i - 1] = cmd[i] end
  return out
end

-- Execute ONE command out of a list.  Split out of runList so the
-- `script.command` mod hook below has a single function to wrap, exactly the
-- way src/script/ScriptRunner.lua:163-170 wraps its own one-row dispatch.
--
-- Returns, in the same vocabulary the Gen 1 runner's control commands use:
--   "end"    this command ends the list it is in -- `end`, a tail-call
--            `sjump`, a taken `iftrue`, a `jumptext` that never comes back
--   number   a 1-based row to continue at; only a mod hook produces one, the
--            cart's own control flow is all whole-list tail calls
--   nil      fall through to the next row
local runList

local function runCmd(self, cmd, op)
  if op == "end" or op == "endall" or op == "endcallback" or op == "reloadend" then
    return "end"
  elseif op == "sjump" or op == "stopandsjump" then
    runList(self, cmd.script)
    return "end"
  elseif op == "scall" then
    runList(self, cmd.script)
  elseif op == "sdefer" then
    -- Script_sdefer only RECORDS the target: it writes
    -- wDeferredScriptBank/Addr and sets RUN_DEFERRED_SCRIPT, and it is
    -- RunSceneScript (engine/overworld/events.asm:388) that picks it up --
    -- after ScriptEvents has run the scene body to its `end`, as that pass's
    -- player event.  Running it inline instead put the League walk-ins, the
    -- Cerulean grunt and the Mt Moon rival cutscene inside the scene script,
    -- i.e. a beat early and under the map's fade-in.  Vm:runDeferred drains
    -- it where the cart does.
    self.deferred = cmd.script
  elseif op == "farscall" then
    -- Script_farscall is Script_scall with the bank taken from the command
    -- rather than from wScriptBank; both fall into the same ScriptCall, which
    -- pushes wScriptBank/wScriptPos and comes BACK here on `end`.  The
    -- extractor has already resolved bank:addr into a scripts.lua key and
    -- queued the target for disassembly, so at this level the two are one
    -- call.  An unresolved key is a no-op: runList returns on a nil list.
    runList(self, cmd.script)
  elseif op == "farsjump" then
    -- Script_farsjump is Script_sjump across banks: ScriptJump overwrites
    -- wScriptBank/wScriptPos and never pushes a return, so nothing after it
    -- in this list runs.  Opcodes.TERMINATORS already stops the extractor
    -- there; returning is what makes the interpreter agree with it.
    runList(self, cmd.script)
    return "end"
  elseif op == "memjump" then
    -- Script_memjump reads a three-byte far pointer OUT OF WRAM at the
    -- address in args = {lo, hi} and jumps to it.  The only real user is
    -- engine/overworld/events.asm's `memjump wQueuedScriptBank`, filled in at
    -- run time by LoadMemScript, so there is no static target for the
    -- extractor to follow and nothing here to run.
    --
    -- It is still a JUMP: the cart does not come back to this list.  So this
    -- returns rather than falling through, which is the difference between
    -- ending the script cleanly and running whatever bytes sit after it.
    -- Script_memjump never touches wScriptVar, so neither does this.
    return "end"
  elseif op == "memcall" then
    -- Script_memcall reads a three-byte far pointer out of WRAM at
    -- args = {lo, hi} and calls it.  The pointer is written at run time by
    -- the phone engine (engine/phone/phone.asm: `memcall wPhoneScriptBank`,
    -- `memcall wCallerContact + PHONE_CONTACT_SCRIPT2_BANK`), so nothing
    -- static exists for the extractor to follow and there is no target to
    -- interpret.  An explicit no-op rather than a silent skip; like the
    -- cart's own Script_memcall it leaves wScriptVar alone.
  elseif op == "memcallasm" then
    -- Script_memcallasm: the same WRAM far pointer as memcall, but `rst
    -- FarCall`ed as raw Game Boy code instead of as script bytecode.  Only
    -- engine/overworld/events.asm's `memcallasm wQueuedScriptBank` uses it.
    -- No interpreter can honour that, so it is an explicit no-op.  All 34
    -- rows the extractor found sit in data regions mis-read as code.
  elseif op == "callasm" then
    -- Script_callasm: `rst FarCall` into raw Game Boy code at bank:addr
    -- (args = {bank, lo, hi}).  Nothing in this port can run that, so this is
    -- a no-op, but a LOUD one: the routine a real callasm reaches is usually
    -- the one that writes wScriptVar for the iffalse right after it.
    -- FindItemInBallScript is `callasm .TryReceiveItem / iffalse .no_room`,
    -- FruitTreeScript is `callasm CheckFruitTree / iffalse .fruit`.
    --
    -- Script_callasm itself never touches wScriptVar, so neither does this:
    -- inventing a 0 or a 1 here would pick a branch at random for every
    -- caller at once.  The hook is the seam instead.  No `callasm` exists
    -- anywhere under pokegold/maps/, so nothing reachable today waits on it.
    if self.callAsmFn then
      -- cmd.label appears the day the importer resolves bank:addr through
      -- pokegold-symbols/pokegold.sym; until then the hook gets nil for it
      -- and can still match on the bank/address pair.  A number back is
      -- wScriptVar, nil means "not modelled, leave it alone".
      local value = self.callAsmFn(cmd.label, arg1(cmd) or 0, wordArg(cmd, 2))
      if value ~= nil then self.scriptVar = value % 256 end
    end
  elseif op == "jumptext" then
    self:emitFace(false)
    self:showText(cmd.text)
    return "end"
  elseif op == "jumptextfaceplayer" then
    self:emitFace(true)
    self:showText(cmd.text)
    return "end"
  elseif op == "faceplayer" then
    self:emitFace(true)
  elseif op == "opentext" or op == "closetext"
      or op == "promptbutton" or op == "closepokepic" then
    -- UI framing / pokepic teardown handled by hooks or TextBox.
    if op == "closepokepic" then
      -- Script_closepokepic is CloseWindow on the window Script_pokepic
      -- opened, so the pic-window flag `waitbutton` reads goes down with it.
      self.picOpen = false
      if self.hidePicFn then self.hidePicFn() end
    end
  elseif op == "reanchormap" then
    -- Script_reanchormap calls ReanchorMap (home/window.asm), which is
    -- ClearWindowData plus a re-blit of the BG map from the player's current
    -- position.  The re-blit half is free here -- src/render/Camera.lua
    -- follows the player every frame rather than anchoring a scrolled map --
    -- but the window teardown is not: WillsRoom's walk-in reanchors between
    -- the applymovement and the earthquake, and ElmsLab reanchors before
    -- every `pokepic`, so a window still standing here is one the cart has
    -- already taken down.
    self.picOpen = false
    if self.hidePicFn then self.hidePicFn() end
  elseif op == "writetext" or op == "farwritetext" then
    self:showText(cmd.text)
    if self.nextOp == "playsound" then
      -- pokegold home/joypad.asm PromptButton: the real press this box's
      -- own close absorbed plays SFX_READ_TEXT_2; drain it before the
      -- script's own playsound or Sound.lua's priority gate drops it.
      coroutine.yield({ kind = "waitsfx" })
    end
  elseif op == "rawtext" then
    -- NOT a cart opcode.  `writetext`'s operand is a KEY into text.lua, and
    -- text.lua only holds strings the extractor reached through a script
    -- pointer -- so a hand-ported script (src/world/gen2/CmdQueue.lua's two
    -- stone tables, whose text hangs off a callback nothing walks) has a
    -- literal and no key to name it by.  This is the one command that carries
    -- one, and the extractor never emits it.
    -- Declared through Strings.source at the table, looked up here, which is
    -- the split src/core/Strings.lua asks for: a module-level template must
    -- not resolve before Strings.load has a catalog.
    -- `stay` rides the row for the same reason the text does: a transcription
    -- that holds ONE MapTextbox over the next few commands has to say so, and
    -- Vm:textStays' one-command lookahead cannot work it out.
    -- `stay` / `hold` ride the row for the same reason the text does: a
    -- transcription that keeps ONE MapTextbox standing over the next few
    -- commands has to say so, and Vm:textStays' one-command lookahead cannot
    -- work it out.  `hold` is the cart `pause` those commands contain, in
    -- Script_pause's own doubled frames (Vm:pauseFrames).
    self:showRaw(Strings(cmd.text), cmd.stay,
      cmd.hold and Vm.pauseLength(cmd.hold) or nil)
  elseif op == "waitbutton" then
    -- Script_waitbutton (engine/overworld/scripting.asm) is WaitButton, i.e.
    -- WaitPressAorB_BlinkCursor: a REAL press of A or B, not a frame count.
    --
    -- After a `writetext` the port's TextBox has already taken that press on
    -- the last page, so the ordinary `writetext / waitbutton / closetext` run
    -- must not ask for a second one -- that was the whole of the old no-op.
    -- The case it got wrong is the one with no text box under it: a `pokepic`
    -- window.  ElmsLab's three starter balls are `reanchormap / pokepic /
    -- cry / waitbutton / closepokepic / opentext / writetext / yesorno`
    -- (maps/ElmsLab.asm ElmsLabPokeBallScript), and there the press is the
    -- ONLY thing holding the pic up: skipping it ran pokepic and closepokepic
    -- inside a single Vm:resume, so the starter's pic was built and thrown
    -- away without one frame ever drawing it (#911).
    if self.picOpen and self.waitButtonFn then
      coroutine.yield({ kind = "waitbutton" })
    end
  elseif op == "checkevent" then
    self.scriptVar = self.events:get(cmd.event) and 1 or 0
  elseif op == "setevent" then
    self.events:set(cmd.event, true)
    if self.onFlagsChanged then self.onFlagsChanged() end
  elseif op == "clearevent" then
    self.events:set(cmd.event, false)
    if self.onFlagsChanged then self.onFlagsChanged() end
  elseif op == "checkflag" then
    -- Script_checkflag: EngineFlagAction CHECK_FLAG over an ENGINE_* id,
    -- result in c, wScriptVar TRUE only when c is non-zero.  The read half of
    -- the setflag / clearflag pair below; see setflag for why the ENGINE_*
    -- namespace is kept apart from setevent's wEventFlags.
    local flag = cmd.flag or wordArg(cmd)
    local set
    if self.getEngineFlagFn then
      set = self.getEngineFlagFn(flag)
    else
      set = self.engineFlags[flag]
    end
    self.scriptVar = set and 1 or 0
  elseif op == "setflag" or op == "clearflag" then
    -- Script_setflag / Script_clearflag: EngineFlagAction SET_FLAG or
    -- RESET_FLAG over an ENGINE_* id (constants/engine_flags.asm).  This is a
    -- DIFFERENT namespace from setevent's wEventFlags and the two must not
    -- share a store: engine flags are the eight Johto and eight Kanto badges,
    -- the Pokegear cards, ENGINE_POKEDEX, ENGINE_BUG_CONTEST_TIMER and the
    -- fly points, and EngineFlags scatters each one into its own byte
    -- (wJohtoBadges, wPokegearFlags, wStatusFlags, wVisitedSpawns...).
    --
    -- They never gate object visibility, which is wEventFlags' job, so this
    -- deliberately does NOT call onFlagsChanged and cannot make an NPC pop in
    -- mid-script.  BugContestResultsWarpScript's `clearflag
    -- ENGINE_BUG_CONTEST_TIMER` is what stops the contest clock, so a missing
    -- clearflag leaves that timer running forever.  The local table is the
    -- fallback for a VM built without the hook (tests); with the hook, the
    -- badge lands in the save.
    local flag = cmd.flag or wordArg(cmd)
    local value = (op == "setflag")
    if self.setEngineFlagFn then
      self.setEngineFlagFn(flag, value)
    else
      self.engineFlags[flag] = value or nil
    end
  elseif op == "iftrue" then
    if self.scriptVar ~= 0 then
      runList(self, cmd.script)
      return "end"
    end
  elseif op == "iffalse" then
    if self.scriptVar == 0 then
      runList(self, cmd.script)
      return "end"
    end
  elseif op == "ifequal" then
    if self.scriptVar == (cmd.value or 0) then
      runList(self, cmd.script)
      return "end"
    end
  elseif op == "ifnotequal" then
    if self.scriptVar ~= (cmd.value or 0) then
      runList(self, cmd.script)
      return "end"
    end
  elseif op == "ifgreater" then
    -- Script_ifgreater: `ld a, [wScriptVar] / ld b, a / GetScriptByte / cp b`.
    -- The compare is OPERAND minus wScriptVar, so carry (and the jump) is set
    -- when the operand is BELOW wScriptVar: the branch is taken on
    -- scriptVar > value.  Spelled out because getting it round the wrong way
    -- silently swaps both arms.  Unsigned byte compare, which is why addval
    -- wraps at 256.  Like ifequal, the jump is a tail call.
    if (self.scriptVar or 0) > (cmd.value or 0) then
      runList(self, cmd.script)
      return "end"
    end
  elseif op == "ifless" then
    -- Script_ifless: the operand goes into b FIRST, then
    -- `ld a, [wScriptVar] / cp b`, i.e. scriptVar minus operand, so carry
    -- (and the jump) means scriptVar < value.  Note the operand order is the
    -- reverse of ifgreater's: the two are not mirror images in the source and
    -- copying one into the other is how the polarity gets lost.
    if (self.scriptVar or 0) < (cmd.value or 0) then
      runList(self, cmd.script)
      return "end"
    end
  elseif op == "pause" then
    self:pauseFrames(cmd.frames or cmd.length or 0)
  elseif op == "setscene" then
    local scene = cmd.scene or arg1(cmd) or 0
    if self.setSceneFn then self.setSceneFn(scene) end
  elseif op == "checkscene" then
    self.scriptVar = self.getSceneFn and self.getSceneFn() or 0
  elseif op == "setmapscene" then
    local group = cmd.group or (cmd.args and cmd.args[1])
    local map = cmd.map or (cmd.args and cmd.args[2])
    local scene = cmd.scene or (cmd.args and cmd.args[3]) or 0
    if self.setMapSceneFn then self.setMapSceneFn(group, map, scene) end
  elseif op == "checkmapscene" then
    -- Script_checkmapscene: GetMapSceneID for the `group, map` pair (first
    -- byte group, second byte map, the same order setmapscene takes), then
    -- wScriptVar = that map's scene byte.  A map with no scene_var row comes
    -- back with de = 0 and the command answers $ff, NOT 0: an `ifequal 0`
    -- after it must not match a map that has no scene at all, which is the
    -- whole reason the sentinel exists.  checkscene above has the same case
    -- for the current map; this is its cross-map twin.
    local args = cmd.args
    local group = cmd.group or (args and args[1])
    local mapNum = cmd.map or (args and args[2])
    local scene = self.getMapSceneFn and self.getMapSceneFn(group, mapNum)
    self.scriptVar = scene or 0xff
  elseif op == "turnobject" then
    -- engine/events/std_scripts.asm: turnobject LAST_TALKED resolves to the NPC last talked to
    local facing = Movement.dir(cmd.facing or 0)
    local object = cmd.object or 0
    if object == LAST_TALKED then object = self.lastTalked end
    if self.turnObjectFn then
      self.turnObjectFn(object, facing)
    end
  elseif op == "applymovement" or op == "applymovementlasttalked" then
    local object = cmd.object or 0
    if op == "applymovementlasttalked" then
      object = self.lastTalked or 1
    end
    local movKey = cmd.movement
    local bytes = movKey and self.movements and self.movements[movKey]
    if bytes and self.applyMovementFn then
      coroutine.yield({ kind = "move", object = object, bytes = bytes })
    end
  elseif op == "yesorno" then
    local yes = coroutine.yield({ kind = "yesorno" })
    self.scriptVar = yes and 1 or 0
  elseif op == "disappear" then
    -- Script_disappear has a `cp LAST_TALKED` the port was missing: the
    -- constant is -2, so the extracted byte is 254 and `disappear LAST_TALKED`
    -- was trying to hide object 253.  Script_appear has no such check, which
    -- is why the branch below has none either.
    local object = cmd.object or arg1(cmd)
    if object == LAST_TALKED then object = self.lastTalked end
    if self.disappearFn then self.disappearFn(object) end
  elseif op == "appear" then
    -- Script_appear: UnmaskCopyMapObjectStruct, then
    -- ApplyEventActionAppearDisappear with b = 0 (CLEAR_FLAG) over the
    -- object's MAPOBJECT_EVENT_FLAG.  The mirror of `disappear` above, and
    -- like it the object list changes NOW rather than at the next map load:
    -- the cart respawns the struct inside the same command, so this must not
    -- be routed through the deferred onFlagsChanged rebuild.
    --
    -- ApplyEventActionAppearDisappear returns without touching anything when
    -- the flag word is -1 ($ffff, which the extractor writes as 65535 and
    -- Events:objectVisible already reads as "always appear"), so an object
    -- with no flag is made visible by the struct copy alone.
    local object = cmd.object or arg1(cmd)
    if self.appearFn then self.appearFn(object) end
  elseif op == "moveobject" then
    -- Script_moveobject: `add 4` on x and on y, then CopyDECoordsToMapObject
    -- (engine/overworld/player_object.asm) writes them into
    -- MAPOBJECT_X_COORD / MAPOBJECT_Y_COORD.  That +4 is the same border
    -- offset PlayerSpawn_ConvertCoords applies to wXCoord/wYCoord, so the
    -- script's own bytes are plain map cells: the coordinate space the
    -- object_event macro and the extracted obj.x / obj.y already use.
    --
    -- It teleports an object that is normally still hidden; every use in
    -- pokegold is a `moveobject` immediately followed by an `appear`
    -- (VictoryRoad's rival, Clair in DragonsDenB1F, the Fast Ship crew).
    local args = cmd.args or {}
    local object = cmd.object or args[1] or 0
    local x = cmd.x or args[2] or 0
    local y = cmd.y or args[3] or 0
    if self.moveObjectFn then self.moveObjectFn(object, x, y) end
  elseif op == "variablesprite" then
    -- Script_variablesprite: wVariableSprites[byte] = sprite.  The macro
    -- emits `\1 - SPRITE_VARS`, so the first byte is already a 0-based slot
    -- into that table ($f0 SPRITE_CONSOLE .. $fc SPRITE_JANINE_IMPERSONATOR
    -- in constants/sprite_constants.asm) and the second is a plain
    -- OverworldSprites index, the numbering constants.spriteOrder uses.
    --
    -- An object whose sprite IS one of those ids is extracted with a NUMBER
    -- in `sprite` rather than a name (Route 36's Sudowoodo carries 244, i.e.
    -- $f4 SPRITE_WEIRD_TREE), so World:pooledNpc finds no sheet for it and
    -- the object never spawns.  Filling the slot is what puts the disguised
    -- tree, the Copycat, the Olivine rival and the four Fuchsia Gym Janines
    -- on the map at all.
    local args = cmd.args or {}
    local slot = cmd.slot or args[1] or 0
    local sprite = cmd.sprite or args[2] or 0
    self.variableSprites[slot] = sprite
    if self.variableSpriteFn then self.variableSpriteFn(slot, sprite) end
  elseif op == "loademote" then
    -- Script_loademote: EMOTE_FROM_MEM ($ff, -1 in
    -- constants/script_constants.asm) means "the emote already in
    -- wScriptVar", anything else is the literal id; LoadEmote then pushes
    -- that bubble's tiles into VRAM.  ShowEmoteScript is the only caller that
    -- uses the FROM_MEM form, and Script_showemote has written its own first
    -- byte to wScriptVar by the time it runs.
    --
    -- This port picks the sheet at draw time (World:showEmote indexes
    -- emoteOrder), so the command only has to remember WHICH bubble, for a
    -- later `show_emote` movement byte ($54) that carries no id of its own.
    local emote = cmd.emote or arg1(cmd) or 0
    if emote == EMOTE_FROM_MEM then emote = self.scriptVar or 0 end
    self.loadedEmote = emote
    if self.loadEmoteFn then self.loadEmoteFn(emote) end
  elseif op == "pokepic" then
    -- Script_pokepic opens a 7x7 window and leaves it standing: the pic is on
    -- screen until a `closepokepic` (or a `reanchormap`) takes the window
    -- down.  The flag is what tells the `waitbutton` above that there is no
    -- text box under it to have paid for the press already.
    local species = cmd.species or arg1(cmd)
    self.picOpen = true
    if self.showPicFn then
      self.showPicFn(species)
    end
  elseif op == "getmonname" then
    local species = cmd.species or arg1(cmd)
    if self.getMonNameFn then
      self:setStringBuffer(self.getMonNameFn(species))
    end
  elseif op == "getitemname" then
    local item = cmd.item or arg1(cmd) or 0
    if self.getItemNameFn then
      self:setStringBuffer(self.getItemNameFn(item))
    end
  elseif op == "getstring" then
    -- The extractor already read the `@`-terminated name the pointer aims
    -- at (Script_getstring CopyName1 -> wStringBuffer2), so the following
    -- writetext's TX_RAM has something to print.  Without this, Mom's
    -- "#GEAR" line renders its {STRBUF} as nothing.
    self:setStringBuffer(cmd.string)
  elseif op == "gettrainername" then
    if self.getTrainerNameFn then
      self:setStringBuffer(self.getTrainerNameFn(cmd.group, cmd.trainer))
    end
  elseif op == "getcurlandmarkname" then
    -- Script_getcurlandmarkname: GetWorldMapLocation on wMapGroup/wMapNumber,
    -- then GetLandmarkName into a string buffer.  The map is implicit, so the
    -- one operand byte is only the buffer id and this port has one buffer.
    -- landmarks.lua already carries the names, the line break included (the
    -- town map draws them two rows deep).
    local name = self.getLandmarkNameFn and self.getLandmarkNameFn()
    if name then self:setStringBuffer(name) end
  elseif op == "getnum" then
    -- Script_getnum: PrintNum of wScriptVar (PRINTNUM_LEFTALIGN | 1 byte,
    -- 3 chars) into wStringBuffer1, then GetStringBuffer copies that into
    -- whichever string buffer the operand names.  Left-aligned is why there
    -- are no padding spaces to reproduce: tostring() is the whole of it.
    -- Without this the Bug Contest judge's "You have N minutes left" prints
    -- an empty {STRBUF}.
    self:setStringBuffer(tostring(self.scriptVar or 0))
  elseif op == "repeattext" then
    -- Script_repeattext re-prints the text jumptext / jumptextfaceplayer
    -- stashed in wScriptTextBank / wScriptTextAddr, and ONLY when both
    -- operand bytes are -1.  Read the guard carefully: the HIGH byte lands in
    -- a and is compared first (`cp -1 / jr nz, .done`), then the low byte,
    -- and any other pointer falls out of the command without printing
    -- anything at all.  It never prints the pointer it was given.
    -- JumpTextScript's `repeattext -1, -1` is the only user in the ROM.
    local args = cmd.args
    if args and args[1] == 0xff and args[2] == 0xff and self.lastTextKey then
      self:showText(self.lastTextKey)
    end
  elseif op == "givepoke" then
    local species = cmd.species or arg1(cmd)
    local level = cmd.level or (cmd.args and cmd.args[2]) or 5
    local item = cmd.item or (cmd.args and cmd.args[3]) or 0
    local trainer = cmd.trainer or (cmd.args and cmd.args[4]) or 0
    if self.givePokeFn then
      -- engine/pokemon/move_mon.asm:1695-1736: the trainer arm copies the
      -- script's own nickname and OT name in instead of asking for one.
      local named = trainer ~= 0
        and { nickname = cmd.name, otName = cmd.otName } or nil
      local mon = self.givePokeFn(species, level, item, named)
      -- engine/pokemon/move_mon.asm:1753-1757
      if mon and trainer == 0 then
        Specials.askNickname(self, mon)
      end
    end
  elseif op == "checkpoke" then
    -- Script_checkpoke: IsInArray over wPartySpecies.  Party only, so a boxed
    -- mon does not count, which is the point of the checks that gate on
    -- carrying a particular species.
    local species = cmd.species or arg1(cmd) or 0
    local has = self.hasPokeFn and self.hasPokeFn(species)
    self.scriptVar = has and 1 or 0
  elseif op == "giveegg" then
    -- Script_giveegg's own comment: 0 when there is no room in the party,
    -- 2 when the egg went in.  Not 1, so an `iftrue` after it is testing "the
    -- party had room" and an `ifequal 2` is the same test spelled out.
    local args = cmd.args
    local species = cmd.species or (args and args[1]) or 0
    local level = cmd.level or (args and args[2]) or 5
    local given = self.giveEggFn and self.giveEggFn(species, level)
    self.scriptVar = given and 2 or 0
  elseif op == "givepokemail" then
    -- `givepokemail pointer` reads an item byte plus a MAIL_MSG_LENGTH
    -- message from behind a pointer in the script's own bank and hands both
    -- to GivePokeMail, which hangs the mail on the LAST party member.
    -- The extractor resolves that pointer into `cmd.mail = { item, message }`
    -- (RomExtractorGen2's givepokemail arm); the raw word is the fallback for
    -- a cache built before it, and an unresolved letter is one the model
    -- refuses rather than one it invents.  GivePokeMail writes no wScriptVar.
    if self.givePokeMailFn then
      self.givePokeMailFn(cmd.mail or wordArg(cmd))
    end
  elseif op == "checkpokemail" then
    -- CheckPokeMail (engine/pokemon/mail.asm) opens the party list and only
    -- then answers, so this BLOCKS: the coroutine parks on the yield and the
    -- world's own handler resumes it with one of POKEMAIL_WRONG_MAIL 0 /
    -- CORRECT 1 / REFUSED 2 / NO_MAIL 3 / LAST_MON 4.
    --
    -- With no handler at all, REFUSED is the honest answer: it is the value
    -- SelectMonFromParty's carry produces when the player backs out, so the
    -- script takes its own cancel path instead of being told a delivery
    -- happened.
    local expected = cmd.mail or wordArg(cmd)
    if self.checkPokeMailFn then
      local answer = coroutine.yield({ kind = "pokemail", mail = expected })
      self.scriptVar = tonumber(answer) or POKEMAIL_REFUSED
    else
      self.scriptVar = POKEMAIL_REFUSED
    end
  elseif op == "giveitem" or op == "verbosegiveitem" then
    local item = cmd.item or arg1(cmd) or 0
    local qty = cmd.quantity or (cmd.args and cmd.args[2]) or 1
    -- Script_giveitem's own `ld [wCurItem], a` (scripting.asm:1612).  It is
    -- what the standalone `specialsound` inside GiveItemScript reads back:
    -- CheckItemPocket runs on wCurItem, not on anything the opcode carries.
    self.curItem = item
    local ok = true
    if self.giveItemFn then
      ok = self.giveItemFn(item, qty) ~= false
    end
    self.scriptVar = ok and 1 or 0
    if op == "verbosegiveitem" then
      local name = self.getItemNameFn and self.getItemNameFn(item) or "?"
      self:setStringBuffer(name)
      -- GiveItemScript (engine/overworld/scripting.asm:441-449), command for
      -- command: `writetext .ReceivedItemText / iffalse .Full / waitsfx /
      -- specialsound / waitbutton / itemnotify`.  Both messages print into the
      -- ONE MapTextbox the caller's `opentext` opened; it comes down at the
      -- caller's `closetext` and at no point in between.
      --
      -- The `waitsfx` sits ABOVE `specialsound` -- it drains whatever sfx was
      -- already sounding so the item jingle starts clean -- and the port had
      -- it BELOW, parking the script on the jingle's full length.  The port's
      -- box waits for its own button and pops itself, so that park happened
      -- with NOTHING on the stack: the text box visibly tore down and rebuilt
      -- around a second of silence, and Game2's play clock (which only ticks
      -- while the overworld is the top state) came off pause for the gap.
      -- With the wait back on the cart's side of the sound, the second box is
      -- pushed inside the same frame the first one pops -- no frame ever
      -- renders the bare overworld, which is the closest this port's
      -- box-per-message shape gets to the cart's single MapTextbox.
      self:showRaw(Strings("{PLAYER} received\n%s.", name))
      if ok then
        -- GiveItemScript's `waitsfx` is NOT ported as a park, and that is the
        -- fix rather than an omission.  On the cart it drains whatever channel
        -- the script before it left sounding, and it runs while the received
        -- line is still on screen -- the box has not been touched yet, because
        -- the button press is one command further down at `waitbutton`.  This
        -- port's box takes that press itself and pops on it, so by the time
        -- the VM gets here the ONLY thing still sounding is the box's own
        -- Press_AB blip, and parking on it left the bare overworld drawing for
        -- the length of the blip -- exactly the seam the cart never opens.
        -- The received box's typing and its press are the drain point here.
        if self.specialSoundFn then
          self.specialSoundFn(item)
        elseif self.playSoundFn then
          self.playSoundFn(1) -- SFX_ITEM
        end
        -- _PutItemInPocketText's second blank is wStringBuffer3, which
        -- GetPocketName fills from ItemPocketNames: KEY ITEMs, BALLs and TMs
        -- name their own pocket, not the ITEM one (data/text/common_2.asm
        -- :1351, data/items/pocket_names.asm:10-13).
        self:showRaw(Strings("{PLAYER} put the\n%s in\nthe %s.",
          name, self:pocketName(item)))
      else
        self:showRaw(Strings("The %s\nis full…", self:pocketName(item)))
      end
    end
  elseif op == "itemnotify" then
    -- Script_itemnotify is GetPocketName + CurItemName, both of which read
    -- wCurItem (engine/overworld/scripting.asm:460).  It touches no string
    -- buffer, so the shared stand-in for wStringBuffer1..5 must not be read
    -- here: it is stale by design and a plain `giveitem` / `itemnotify` pair
    -- would print the last name any script happened to leave in it.  Nor is
    -- the buffer written back: CurItemName fills wStringBuffer1 while the
    -- port's single buffer mostly stands for wStringBuffer2, so mirroring
    -- the clobber would corrupt an unrelated {STRBUF} page.
    local name = self:curItemName()
    if name ~= "" then
      self:showRaw(Strings("{PLAYER} put the\n%s in\nthe %s.",
        name, self:pocketName(self.curItem)))
    end
  elseif op == "pocketisfull" then
    -- Script_pocketisfull reads wCurItem exactly as Script_itemnotify does
    -- (engine/overworld/scripting.asm:468).
    self:showRaw(Strings("The %s\nis full…", self:pocketName(self.curItem)))
  -- ---- bag, money and coins (engine/events/money.asm) --------------------
  elseif op == "checkitem" then
    -- Script_checkitem clears wScriptVar FIRST and only CheckItem's carry
    -- turns it TRUE, so a bag the world cannot answer for reads "no item"
    -- rather than leaving whatever the command before it left behind.
    local item = cmd.item or arg1(cmd) or 0
    local has = self.hasItemFn and self.hasItemFn(item)
    self.scriptVar = has and 1 or 0
  elseif op == "takeitem" then
    -- `takeitem item, quantity`; the one-argument macro form fills the
    -- quantity in as 1 at assembly time, so the ROM always carries both
    -- bytes.  Script_takeitem puts -1 in wCurItemQuantity so TossItem removes
    -- without asking, and wScriptVar is TRUE only when the pack really held
    -- that many.
    local args = cmd.args
    local item = cmd.item or (args and args[1]) or 0
    local qty = cmd.quantity or (args and args[2]) or 1
    local took = self.takeItemFn and self.takeItemFn(item, qty)
    self.scriptVar = took and 1 or 0
  elseif op == "checkmoney" then
    -- Script_checkmoney -> CompareMoney -> CompareMoneyAction: the answer is
    -- HAVE_MORE 0 / HAVE_AMOUNT 1 / HAVE_LESS 2, not a boolean.  The broke
    -- arm is `ifequal HAVE_LESS`, and an `iffalse` after a checkmoney means
    -- the player has MORE than the price, which is why guessing this one
    -- would have sent every shopkeeper down the wrong branch.
    local account, amount = moneyArgs(cmd)
    local have = self.getMoneyFn and self.getMoneyFn(account) or 0
    self.scriptVar = compareFunds(have, amount)
  elseif op == "givemoney" or op == "takemoney" then
    -- GiveMoney is AddMoney then a CompareMoney against MaxMoney that writes
    -- MAX_MONEY back over any overflow; TakeMoney's SubtractMoney leaves the
    -- account at 0 on a borrow rather than wrapping.  Neither touches
    -- wScriptVar, so nothing here may either.
    local account, amount = moneyArgs(cmd)
    if self.getMoneyFn and self.setMoneyFn then
      local have = self.getMoneyFn(account) or 0
      if op == "givemoney" then
        self.setMoneyFn(account, math.min(have + amount, MAX_MONEY))
      else
        self.setMoneyFn(account, math.max(have - amount, 0))
      end
    end
  elseif op == "getmoney" then
    -- `getmoney string_buffer, account` emits the ACCOUNT byte FIRST
    -- (macros/scripts/events.asm swaps the two arguments), which is the order
    -- Script_getmoney reads them in: GetMoneyAccount, then GetStringBuffer.
    -- PrintNum is PRINTNUM_LEFTALIGN, so no padding survives into the text,
    -- and this port has one shared string buffer so the buffer id is read and
    -- deliberately ignored.
    local account = arg1(cmd) or 0
    local have = self.getMoneyFn and self.getMoneyFn(account) or 0
    self:setStringBuffer(tostring(have))
  elseif op == "checkcoins" then
    -- Script_checkcoins -> CheckCoins -> the same CompareMoneyAction ladder,
    -- so the answers are the HAVE_* three again.  The Goldenrod coin vendor
    -- leads with `checkcoins MAX_COINS - 50` / `ifequal HAVE_MORE`, i.e. 0 is
    -- the "your case is nearly full" arm.
    local have = self.getCoinsFn and self.getCoinsFn() or 0
    self.scriptVar = compareFunds(have, wordArg(cmd))
  elseif op == "givecoins" or op == "takecoins" then
    -- GiveCoins caps at MAX_COINS the way GiveMoney caps at MAX_MONEY, and
    -- TakeCoins floors at 0 on a borrow.  Neither writes wScriptVar.
    local amount = wordArg(cmd)
    if self.getCoinsFn and self.setCoinsFn then
      local have = self.getCoinsFn() or 0
      if op == "givecoins" then
        self.setCoinsFn(math.min(have + amount, MAX_COINS))
      else
        self.setCoinsFn(math.max(have - amount, 0))
      end
    end
  elseif op == "getcoins" then
    -- Script_getcoins: wCoins through PrintNum into a string buffer.
    local have = self.getCoinsFn and self.getCoinsFn() or 0
    self:setStringBuffer(tostring(have))
  elseif op == "pokemart" then
    -- `pokemart dialog_id, mart_id` (macros/scripts/events.asm): one
    -- MARTTYPE_* byte then a WORD mart id, which the extractor leaves in
    -- `args` as dialog, lo, hi.  Script_pokemart farcalls OpenMartDialog,
    -- which does not return until the shop is closed, so this parks the VM
    -- on its resume the same way `startbattle` does.
    local args = cmd.args
    local martType = cmd.martType or cmd.dialog or (args and args[1]) or 0
    local martId = cmd.mart or cmd.martId
    if not martId and args then
      martId = (args[2] or 0) + (args[3] or 0) * 0x100
    end
    coroutine.yield({ kind = "mart", martType = martType,
      martId = martId or 0 })
  elseif op == "addcellnum" then
    local phone = cmd.phone or arg1(cmd) or 0
    if self.addCellFn then self.addCellFn(phone) end
  elseif op == "delcellnum" then
    local phone = cmd.phone or arg1(cmd) or 0
    if self.delCellFn then self.delCellFn(phone) end
  elseif op == "checkcellnum" then
    local phone = cmd.phone or arg1(cmd) or 0
    local has = self.hasCellFn and self.hasCellFn(phone)
    self.scriptVar = has and 1 or 0
  elseif op == "cry" then
    if self.cryFn then self.cryFn(cmd.id) end
  elseif op == "playsound" then
    if self.playSoundFn then self.playSoundFn(cmd.id) end
  elseif op == "playmusic" then
    if self.playMusicFn then self.playMusicFn(cmd.id) end
  elseif op == "playmapmusic" then
    -- Script_playmapmusic: PlayMapMusic (home/audio.asm), the song off the
    -- map's own header.  It compares against wMapMusic first and does nothing
    -- when that song is already playing, which Music.play's own dedupe
    -- reproduces.  Paired with `playmusic` at the end of a cutscene to hand
    -- the town its theme back.
    if self.playMapMusicFn then self.playMapMusicFn() end
  elseif op == "musicfadeout" then
    -- Script_musicfadeout: a WORD music id into wMusicFadeID, then a fade
    -- byte masked with ~(1 << MUSIC_FADE_IN_F).  Clearing bit 7 is what makes
    -- it a fade OUT; the low bits are the frames between volume steps
    -- (FadeToMapMusic uses 8, every script use in pokegold passes 16), and
    -- the queued song starts once the ramp bottoms out.  That is the same
    -- `control` byte Music.fadeOut already takes.
    local args = cmd.args or {}
    local music = cmd.id or wordArg(cmd)
    local fade = (cmd.fade or args[3] or 0) % 128 -- clear MUSIC_FADE_IN_F
    if self.fadeOutMusicFn then self.fadeOutMusicFn(music, fade) end
  elseif op == "dontrestartmapmusic" then
    -- Script_dontrestartmapmusic: wDontPlayMapMusicOnReload = TRUE.  It is a
    -- ONE SHOT, and it does not mean "keep playing": TryRestartMapMusic
    -- (home/audio.asm) sees the flag, plays MUSIC_NONE instead of the map
    -- theme, zeroes wMapMusic and clears the flag again.  So the next map
    -- reload comes back SILENT, which is how a scripted song or a deliberate
    -- silence survives the reload that follows it.
    self.dontRestartMapMusic = true
    if self.dontRestartMapMusicFn then self.dontRestartMapMusicFn() end
  elseif op == "warpsound" then
    -- Script_warpsound: GetWarpSFX (engine/overworld/tile_events.asm) then
    -- PlaySFX.  The choice comes off wPlayerTileCollision at play time:
    -- COLL_DOOR ($71) gives SFX_ENTER_DOOR, COLL_WARP_PANEL ($7c) gives
    -- SFX_WARP_TO, anything else gives SFX_EXIT_BUILDING.  The tile under the
    -- player decides, and the World owns that tile.
    if self.warpSoundFn then self.warpSoundFn() end
  elseif op == "waitsfx" then
    coroutine.yield({ kind = "waitsfx" })
  elseif op == "specialsound" then
    -- Script_specialsound (scripting.asm:476) is `farcall CheckItemPocket`
    -- over wCurItem, so the TM/HM jingle or SFX_ITEM is picked from the item
    -- the last giveitem parked there -- the opcode itself carries nothing.
    if self.specialSoundFn then
      self.specialSoundFn(self.curItem)
    elseif self.playSoundFn then
      self.playSoundFn(1) -- SFX_ITEM
    end
    coroutine.yield({ kind = "waitsfx" })
  elseif op == "readvar" then
    local id = cmd.var or arg1(cmd) or 0
    if self.readVarFn then
      self.scriptVar = self.readVarFn(id) or 0
    else
      self.scriptVar = 0
    end
  elseif op == "writevar" then
    -- Script_writevar: GetVarAction resolves the VAR_* id to an address, then
    -- [de] = wScriptVar.  The exact mirror of readvar, and the extractor
    -- gives both the same cmd.var field.  Only a handful of the rows in
    -- engine/overworld/variables.asm .VarActionTable are plain addresses
    -- (VAR_BATTLETYPE, wPlayerState); the RETVAR_EXECUTE rows resolve to code
    -- and writing them is meaningless, which is the World's call, not this
    -- file's.
    if self.writeVarFn then
      self.writeVarFn(cmd.var or arg1(cmd) or 0, (self.scriptVar or 0) % 256)
    end
  elseif op == "loadvar" then
    -- Script_loadvar: GetVarAction on the var id, then [de] = a LITERAL byte
    -- (args = {var, value}).  writevar takes wScriptVar, loadvar takes the
    -- next script byte, and that is the only difference between them.  Note
    -- the extractor's readvar/writevar branch matches only those two names,
    -- so loadvar falls through to the generic `args` arm and does NOT get a
    -- cmd.var of its own.
    --
    -- This is the command that arms the special battles:
    -- `loadvar VAR_BATTLETYPE, BATTLETYPE_FORCEITEM` in front of Lugia, Ho-Oh
    -- and the Red Gyarados, BATTLETYPE_FORCESHINY at the Lake of Rage,
    -- BATTLETYPE_TRAP in the Rocket base, BATTLETYPE_CANLOSE for the
    -- Cherrygrove rival.  Skipping it silently is why every one of those
    -- currently fights as a plain wild encounter you cannot lose to.
    local args = cmd.args
    local varId = cmd.var or (args and args[1]) or 0
    local value = (args and args[2]) or 0
    if self.writeVarFn then self.writeVarFn(varId, value % 256) end
  elseif op == "readmem" then
    -- Script_readmem: wScriptVar = the WRAM byte at args = {lo, hi}.  Real
    -- scripts use it as a counter the port has nowhere else to keep: the
    -- Goldenrod underground switch room reads $d6a8
    -- (wUndergroundSwitchPositions), addvals 1 or -1 and writes it straight
    -- back, and Route39Barn reads wMooMooBerries the same way.  So the VM
    -- carries its own sparse byte store and stays self-consistent.
    --
    -- The hook is the seam for the addresses the ENGINE really owns: it
    -- returns a number to answer for one, or nil to mean "not mine, use the
    -- script's own store".
    local addr = wordArg(cmd)
    local value = self.readMemFn and self.readMemFn(addr)
    if value == nil then value = self.mem[addr] end
    self.scriptVar = (value or 0) % 256
  elseif op == "writemem" or op == "loadmem" then
    -- Script_writemem takes its byte from wScriptVar; Script_loadmem reads
    -- the address FIRST and a literal value LAST (args = {lo, hi, value}).
    -- Both share readmem's sparse store: the hook returns truthy when the
    -- World has claimed that address, and anything it does not claim lands in
    -- the VM's own table so a read / addval / write triple still adds up.
    --
    -- Nothing in the extracted cache reaches loadmem yet: the two uses in
    -- pokegold are `loadmem hBGMapMode, $0` and trainer_scripts' `loadmem
    -- wRunningTrainerBattleScript, -1`, both in engine code the extractor
    -- never walks.  Implemented anyway so it is not a silent skip the day one
    -- becomes reachable.
    local addr = wordArg(cmd)
    local value
    if op == "loadmem" then
      value = ((cmd.args and cmd.args[3]) or 0) % 256
    else
      value = (self.scriptVar or 0) % 256
    end
    local handled = self.writeMemFn and self.writeMemFn(addr, value)
    if not handled then self.mem[addr] = value end
  elseif op == "jumpstd" then
    -- StdScripts entry: the extractor already resolved the id to the same
    -- scripts.lua key a map pointer would produce (see extractStdScripts),
    -- so a std script runs through this very interpreter.  jumpstd is a tail
    -- call: nothing after it runs.
    if cmd.script then runList(self, cmd.script) end
    return "end"
  elseif op == "callstd" then
    if cmd.script then runList(self, cmd.script) end
  elseif op == "special" then
    self:runSpecial(cmd.id, cmd)
  elseif op == "setval" then
    -- setval loads wScriptVar, which the ifequal family then tests.
    self.scriptVar = cmd.value or arg1(cmd) or 0
  elseif op == "addval" then
    -- Script_addval: `GetScriptByte / ld hl, wScriptVar / add [hl] /
    -- ld [hl], a`.  The operand is ADDED to wScriptVar and the result wraps
    -- at 8 bits, so `addval -1` (args = {255}) is how a script counts DOWN:
    -- the Goldenrod underground switch room does readmem / addval 1 /
    -- writemem to flick a switch on and readmem / addval -1 / writemem to
    -- flick it back off.
    self.scriptVar = ((self.scriptVar or 0) + (arg1(cmd) or 0)) % 256
  elseif op == "random" then
    -- Script_random: a uniform roll in 0 .. n-1, where n is the operand.  The
    -- cart gets there the long way (.Divide256byC finds 256 % n,
    -- rejection-samples Random() down to a multiple of n, then SimpleDivide
    -- takes the remainder) purely so the modulo is unbiased; math.random over
    -- the same span is the same distribution.  `random 0` returns early on
    -- `and a / ret z` with wScriptVar still holding the 0 it just stored, so
    -- a zero operand is a zero result and not an error.
    local n = arg1(cmd) or 0
    self.scriptVar = (n == 0) and 0 or math.random(0, n - 1)
  elseif op == "checkver" then
    -- Script_checkver: wScriptVar = GS_VERSION, a byte assembled into the
    -- command itself (constants/misc_constants.asm: 0 Gold, 1 Silver).  It is
    -- a plain value, not a flag, so the `iftrue` that follows is the SILVER
    -- arm and Gold falls through.  WhirlIslandLugiaChamber uses exactly that
    -- to give Gold a level 70 Lugia and Silver a level 40.  Defaults to Gold
    -- so a VM built without the hook plays the Gold branch.
    local version = GS_VERSION_GOLD
    if self.gsVersionFn then version = self.gsVersionFn() or version end
    self.scriptVar = version
  elseif op == "checktime" then
    -- Script_checktime: `xor a / ld [wScriptVar], a`, CheckTime hands back
    -- the bit for the current wTimeOfDay in c, the script byte is ANDed with
    -- it, and wScriptVar is TRUE only when the AND is non-zero.  The bits are
    -- shift_consts (constants/ram_constants.asm): MORN 1, DAY 2, NITE 4,
    -- DARKNESS 8, and ANYTIME is MORN|DAY|NITE = 7.
    --
    -- CheckTime.TimeOfDayTable lists MORN_F, DAY_F, NITE_F and then NITE_F
    -- again: DARKNESS_F (3) is not in it at all, so IsInArray fails, c comes
    -- back 0, and `checktime` is FALSE for every mask inside a pitch-black
    -- cave.  Transcribed rather than smoothed over, because that is the cart.
    local mask = arg1(cmd) or 0
    local time = self.getTimeOfDayFn and self.getTimeOfDayFn() or 0
    local bit = 0
    if time == 0 then bit = 1        -- MORN_F
    elseif time == 1 then bit = 2    -- DAY_F
    elseif time == 2 then bit = 4    -- NITE_F
    end                              -- DARKNESS_F falls through at 0
    -- Lua 5.1 has no band; the same shift-and-test shape Events:get uses.
    local hit = bit ~= 0 and math.floor(mask / bit) % 2 == 1
    self.scriptVar = hit and 1 or 0
  -- ---- trainer battles (engine/events/trainer_scripts.asm) ----------------
  elseif op == "loadtrainer" then
    -- `loadtrainer class, member` overrides whatever the object carried, so
    -- a rematch script can pick JOEY2 off the same object as JOEY1.
    self.trainer = self:lookupTrainer(cmd.class or arg1(cmd),
      cmd.member or (cmd.args and cmd.args[2]))
  elseif op == "loadtemptrainer" then
    -- wTempTrainer is the copy LoadTrainer_continue takes from the struct
    -- the object points at; here that is simply the object's own record.
    self.trainer = self:lookupTrainer(
      self.trainerObject and self.trainerObject.class,
      self.trainerObject and self.trainerObject.member)
  elseif op == "startbattle" then
    -- Resumes with "win" / "lose"; wRunningTrainerBattleScript is set for
    -- the endifjustbattled / checkjustbattled pair that follows.
    --
    -- Script_startbattle ends `ld a, [wBattleResult] / and
    -- ~BATTLERESULT_BITMASK / ld [wScriptVar], a`, and that byte counts up
    -- from a WIN: WIN 0, LOSE 1, DRAW 2 (constants/battle_constants.asm).
    -- So a win is the FALSE arm, which reads backwards until you look at the
    -- scripts: BurnedTower1F's `startbattle / iftrue .next / disappear
    -- FIREBREATHER_DICK` only makes the beaten trainer vanish because
    -- winning does not take the iftrue, and TrainerHouseB1F's
    -- `reloadmapafterbattle / iffalse .End` only stops the second battle
    -- because it does.  21 extracted scripts branch straight off this byte.
    local outcome = coroutine.yield({ kind = "battle", trainer = self.trainer,
      wild = self.wildMon })
    self.wildMon = nil
    self.trainer = nil
    self.justBattled = true
    self.battleOutcome = outcome
    self.scriptVar = BATTLE_RESULTS[outcome] or BATTLE_RESULTS.win
  elseif op == "loadwildmon" then
    -- Script_loadwildmon rewrites wBattleScriptFlags to the WILD shape
    -- ((1 << 7), no trainer bit), so the latest load command decides what
    -- `startbattle` fights.  This VM lives as long as the World, so a
    -- trainer left over from an earlier script (a sight trainer fought on
    -- the way to the lake) must not shadow the wild mon -- that stale
    -- record turned the Red Gyarados A-press into a rematch with the last
    -- trainer beaten.
    self.trainer = nil
    self.wildMon = { species = cmd.species or arg1(cmd),
      level = cmd.level or (cmd.args and cmd.args[2]) }
  elseif op == "randomwildmon" then
    -- Script_randomwildmon: `xor a / ld [wBattleScriptFlags], a`.  Clearing
    -- the flags IS the command: with neither the wild bit Script_loadwildmon
    -- sets ((1 << 7)) nor the trainer bit Script_loadtemptrainer sets
    -- ((1 << 7) | 1), the `startbattle` that follows rolls the map's own
    -- encounter table.  Sweet Scent, the Bug Contest and the rock-smash path
    -- all reach a battle this way.
    --
    -- The roll happens here rather than inside `startbattle` because this
    -- port carries the chosen mon in self.wildMon; nothing between the two
    -- commands can move the player or change the map, so the outcome is the
    -- same and the existing startbattle branch does not have to change.
    self.trainer = nil
    self.wildMon = nil
    if self.rollWildFn then self.wildMon = self.rollWildFn() end
  elseif op == "loadpikachudata" then
    -- Script_loadpikachudata: wTempWildMonSpecies = PIKACHU,
    -- wCurPartyLevel = 5.  It writes the pair `loadwildmon` would but leaves
    -- wBattleScriptFlags alone, so on the cart it only turns into a battle
    -- when something else has already asked for a wild one.  A Yellow
    -- leftover with 0 uses in pokegold; here so it stops falling through.
    -- 25 is PIKACHU in constants/pokemon_constants.asm, the same index
    -- constants.speciesOrder and World's speciesByIndex use.
    self.wildMon = { species = 25, level = 5 }
  elseif op == "wildon" or op == "wildoff" then
    -- Script_wildon / Script_wildoff: res / set
    -- STATUSFLAGS_NO_WILD_ENCOUNTERS_F, [wStatusFlags] (bit 5,
    -- constants/ram_constants.asm), the gate that keeps grass quiet during an
    -- escorted walk.  Unreferenced by pokegold's own bytecode (the ASM sets
    -- and clears the flag directly around the Bug Contest and the roaming-mon
    -- scenes), but the flag is real and World:tryWildEncounter needs the same
    -- switch either way.
    self.wildEncounters = (op == "wildon")
    if self.setWildEncountersFn then
      self.setWildEncountersFn(self.wildEncounters)
    end
  elseif op == "swarm" then
    -- Script_swarm: two bytes (a `map_id`: group, then map) handed to
    -- StoreSwarmMapIndices (engine/events/specials.asm), which writes
    -- wSwarmMapGroup / wSwarmMapNumber and then FALLS THROUGH into
    -- SetSwarmFlag -> DAILYFLAGS1_SWARM.  Both halves matter: CheckSwarmFlag
    -- is what makes the swarm expire, so a port that only stores the map
    -- leaves the Dunsparce call permanently live.
    local args = cmd.args or {}
    local group = cmd.group or args[1]
    local mapNum = cmd.map or args[2]
    if self.setSwarmFn then self.setSwarmFn(group, mapNum) end
  elseif op == "reloadmapafterbattle" or op == "reloadmap"
      or op == "refreshmap" then
    -- Losing ENDS the script.  Script_reloadmapafterbattle reads wBattleResult
    -- and, on LOSE, does `ScriptJump Script_BattleWhiteout` -- it never comes
    -- back to the command after it.
    --
    -- The port used to fall straight through, and every trainer script in the
    -- game is written `startbattle / reloadmapafterbattle / setevent
    -- EVENT_BEAT_<whoever>`, so a LOSS ran the win branch: Whitney handed out
    -- EVENT_BEAT_WHITNEY to a party that had just been wiped, the Elite Four
    -- could be cleared one room at a time by fainting in each, and the route
    -- bot reached the Hall of Fame with two Pokemon and four badges.  It also
    -- quietly desynced the flags from the badges, since the badge itself is
    -- given further down the same script after a scene the loser never runs.
    --
    -- World's own loss handling has already done the whiteout half (heal,
    -- halve the money, warp to the spawn point), which is what
    -- Script_BattleWhiteout does; all that was missing is that the script
    -- stops here.
    --
    -- The hook's argument is "this reload runs a map SETUP script".
    -- MapSetupScript_ReloadMap ends on `mapsetup ForceMapMusic`
    -- (data/maps/setup_scripts.asm:136), so `reloadmap` /
    -- `reloadmapafterbattle` are the ops that consume
    -- wDontPlayMapMusicOnReload; Script_refreshmap runs no setup script at
    -- all (engine/overworld/scripting.asm:2044), just
    -- LoadOverworldTilemapAndAttrmapPals / ApplyTilemap / UpdateSprites.
    if op == "reloadmapafterbattle" and self.battleOutcome == "lose" then
      self.aborted = true
      self.battleOutcome = nil
      if self.reloadMapFn then self.reloadMapFn(true) end
      return "end"
    end
    if self.reloadMapFn then self.reloadMapFn(op ~= "refreshmap") end
  elseif op == "catchtutorial" then
    -- `catchtutorial battle_type` runs the DUDE's catch demo
    -- (engine/events/catch_tutorial.asm): the player's name is parked in
    -- wMomsName and swapped for DUDE, the DUDE's own pack is loaded, an
    -- auto-input stream is armed, and only then is StartBattle farcall'd.
    -- The wild mon is the one the `loadwildmon RATTATA, 5` in front of the
    -- command left in wTempWildMonSpecies, so it rides along here the same
    -- way `startbattle` takes it.
    --
    -- The stream armed around StartBattle is `NO_INPUT, $ff`: it exists
    -- purely to take the controller away for the length of the demo, and the
    -- DUDE's actual presses come from the re-arms in PromptButton, the
    -- battle menu and TutorialPack (src/core/gen2/CatchTutorial.lua).
    --
    -- The order below is the ASM's exactly: StartAutoInput, the battle,
    -- StopAutoInput, and then the `jp Script_reloadmap` the command ends on.
    -- It is NOT a terminator: the script really does continue after the
    -- reload, and it leaves wScriptVar alone.
    local wild = self.wildMon
    self.wildMon = nil
    if self.autoInputStreamFn then
      self.autoInputStreamFn("CATCH_TUTORIAL")
    end
    if self.catchTutorialFn then
      coroutine.yield({ kind = "catchtutorial",
        battleType = cmd.battleType or arg1(cmd), wild = wild })
    end
    if self.stopAutoInputFn then self.stopAutoInputFn() end
    -- `jp Script_reloadmap`, so the setup script (and its ForceMapMusic row)
    -- really does run here.
    if self.reloadMapFn then self.reloadMapFn(true) end
  elseif op == "winlosstext" then
    -- Overrides the struct's win/loss text for this battle only; a 0
    -- argument zeroes that pointer (engine/overworld/scripting.asm:651)
    self.winLossArmed = true
    self.winTextOverride = cmd.winText
    self.lossTextOverride = cmd.lossText
  elseif op == "trainertext" then
    local which = cmd.index or arg1(cmd) or 0
    local obj = self.trainerObject or {}
    local key
    if which == 1 then
      key = self.winLossArmed and self.winTextOverride
        or (not self.winLossArmed and obj.winText or nil)
    elseif which == 2 then
      key = self.winLossArmed and self.lossTextOverride
        or (not self.winLossArmed and obj.lossText or nil)
    else
      key = obj.seenText
    end
    self:showText(key)
  elseif op == "trainerflagaction" then
    -- EventFlagAction over the struct's beat flag; CHECK writes wScriptVar.
    local action = cmd.action or arg1(cmd) or 0
    local flag = self.trainerObject and self.trainerObject.event
    if not flag then
      self.scriptVar = 0
    elseif action == 2 then -- CHECK_FLAG
      self.scriptVar = self.events:get(flag) and 1 or 0
    else
      self.events:set(flag, action == 1) -- SET_FLAG / RESET_FLAG
      if self.onFlagsChanged then self.onFlagsChanged() end
    end
  elseif op == "scripttalkafter" then
    -- Tail call into the struct's after-battle script.
    local after = self.trainerObject and self.trainerObject.scriptKey
    if after then runList(self, after) end
    return "end"
  elseif op == "endifjustbattled" then
    if self.justBattled then return "end" end
  elseif op == "checkjustbattled" then
    self.scriptVar = self.justBattled and 1 or 0
  elseif op == "setlasttalked" then
    self.lastTalked = cmd.object or arg1(cmd)
  elseif op == "encountermusic" then
    if self.encounterMusicFn then
      self.encounterMusicFn(self.trainerObject and self.trainerObject.class)
    end
  elseif op == "showemote" then
    -- `showemote emote, object, length` -- the ! bubble over a trainer.
    local emote = cmd.emote or arg1(cmd) or 0
    local object = cmd.object or (cmd.args and cmd.args[2]) or 0
    local frames = cmd.frames or (cmd.args and cmd.args[3]) or 0
    if self.showEmoteFn then
      self.showEmoteFn(emote, object, frames)
    end
    -- ShowEmoteScript holds on `pause 0`, which is Script_pause reading back
    -- the wScriptDelay Script_showemote wrote (scripting.asm:981, 986-991),
    -- so the bubble stays up for two frames per operand byte.
    self:pauseFrames(frames)
  elseif op == "trainerapproach" then
    -- SeenByTrainerScript's callasm TrainerWalkToPlayer + the applymovement
    -- that follows it, as one step: the World owns the path.
    if self.trainerApproachFn then
      coroutine.yield({ kind = "approach" })
    end
  elseif op == "faceobject" or op == "writeobjectxy" then
    -- faceobject PLAYER, LAST_TALKED squares the player up to the trainer.
    if op == "faceobject" and self.faceObjectFn then
      self.faceObjectFn(cmd.a or (cmd.args and cmd.args[1]),
        cmd.b or (cmd.args and cmd.args[2]))
    end
  elseif op == "follow" or op == "follownotexact" then
    -- `follow leader, follower` (macros/scripts/events.asm emits the LEADER
    -- first, and Script_follow hands that byte to SetLeaderIfVisible).  The
    -- follower's movement type becomes SPRITEMOVEDATA_FOLLOWING: it walks
    -- into whatever cell the leader has just left, one step behind, for as
    -- long as the pairing lasts.
    --
    -- Ignoring this used to be harmless-looking and was not: the New Bark
    -- Town teacher's `follow NEWBARKTOWN_TEACHER, PLAYER` is what drags the
    -- player back off the coord event's tile.  Without it she walked home
    -- alone, the player was still standing on (1,8), and the scene fired
    -- again the moment it ended -- so she was back at her spawn starting the
    -- same speech over, forever.
    if self.followFn then
      self.followFn(cmd.a or (cmd.args and cmd.args[1]),
        cmd.b or (cmd.args and cmd.args[2]))
    end
  elseif op == "stopfollow" then
    if self.stopFollowFn then self.stopFollowFn() end
  -- ---- map blocks (home/map.asm GetBlockLocation) -------------------------
  elseif op == "changeblock" then
    -- Script_changeblock: `add 4` on both bytes, then GetBlockLocation, whose
    -- `srl` halves each of them again, so the script's x and y are CELL
    -- coordinates and the block it rewrites is (x / 2, y / 2).  Checked
    -- against MahoganyMart1F, whose `changeblock 6, 2, $1e` is block (3, 1)
    -- and whose TEAM_ROCKET_BASE_B1F warp_event sits on cell (7, 3), inside
    -- exactly that block; and against BrunosRoom, whose `changeblock 4, 2,
    -- $16 ; open door` is block (2, 1) with its warp_events on cells (4, 2)
    -- and (5, 2).
    --
    -- This is Bruno's door slamming shut, the Ruins of Alph floor giving way,
    -- the Mahogany staircase and the Goldenrod underground doors.  The hook
    -- must drop whatever the renderer has baked for this map.
    local args = cmd.args or {}
    local x = cmd.x or args[1] or 0
    local y = cmd.y or args[2] or 0
    local block = cmd.block or args[3] or 0
    if self.changeBlockFn then
      self.changeBlockFn(math.floor(x / 2), math.floor(y / 2), block)
    end
  elseif op == "changemapblocks" then
    -- Script_changemapblocks: a `dba` (bank, then pointer) into
    -- wMapBlocksBank / wMapBlocksPointer, then ChangeMap + BufferScreen.  It
    -- repaints the WHOLE map from a second copy of its blockdata rather than
    -- poking one block the way changeblock does.
    --
    -- The three bytes are read in the order GetScriptByte reads them: bank
    -- first (`dba` is `dbw bank, address`), then the pointer low byte and
    -- high byte.  It stays a RAW ROM pointer here -- the importer only walks
    -- script pointers, so nothing under data/generated/ is keyed by one --
    -- and World:changeMapBlocks is what places it, against the blockdata
    -- bank/address every map's attributes already carry.  A pointer no map
    -- covers is a no-op there rather than a guess.
    --
    -- wScriptVar is untouched, as in the asm.
    local args = cmd.args or {}
    local bank = cmd.bank or args[1]
    local pointer = cmd.address
      or ((args[2] or 0) + (args[3] or 0) * 0x100)
    if self.changeMapBlocksFn then
      self.changeMapBlocksFn(bank, pointer)
    end
  elseif op == "earthquake" then
    -- Script_earthquake copies EarthquakeMovement (step_shake 16 /
    -- step_sleep 16 / step_end) into wEarthquakeMovementDataBuffer,
    -- overwrites buffer+1 (the step_shake parameter) with the script byte,
    -- overwrites buffer+3 (the step_sleep parameter) with `and %00111111` of
    -- the same byte, then ScriptCalls `applymovement PLAYER, buffer`.
    --
    -- So ONE byte carries two numbers.  The full byte is the displacement
    -- ShakeScreen hands the SPRITEMOVEDATA_SCREENSHAKE object; byte & $3f is
    -- how many frames the movement then sleeps for, and the sleep is what
    -- holds the script.  `earthquake 80` is a displacement of 80 held for 16
    -- frames, not 80 frames of anything.  StepFunction_Sleep decrements
    -- OBJECT_STEP_DURATION once per frame, so those are the 60 Hz frames
    -- waitFrames already counts.
    local param = cmd.param or arg1(cmd) or 0
    local frames = param % 64
    if self.earthquakeFn then self.earthquakeFn(param, frames) end
    self:waitFrames(frames)
  -- ---- warps (home/map.asm) ----------------------------------------------
  elseif op == "warp" or op == "warpfacing" then
    -- Script_warpfacing FALLS THROUGH into Script_warp: it is `warp` with a
    -- facing bolted on the front, not a separate jumptable case, so BOTH
    -- halves run.  Its byte is `maskbits NUM_DIRECTIONS` (& 3, the
    -- DOWN/UP/LEFT/RIGHT order Movement.dir already speaks) and goes into
    -- wPlayerSpriteSetupFlags with PLAYERSPRITESETUP_CUSTOM_FACING, so the
    -- player lands facing it rather than facing wherever arrival would have
    -- turned them.
    --
    -- Then a `map_id` (group, map) and x and y as plain map cells.  Distinct
    -- from the warp_events World:takeWarp already handles: those name a
    -- destination WARP and take their facing from where that warp sits on the
    -- destination map, this one names a raw cell.
    --
    -- It does NOT end the script.  Script_warp's StopScript only clears
    -- SCRIPT_RUNNING for the frame, exactly as Script_reloadmap's does, and
    -- the script resumes once the new map is up: std_scripts.asm's
    -- BugContestResultsWarpScript is `warp ROUTE_36_NATIONAL_PARK_GATE, 0, 4`
    -- followed by an `applymovement PLAYER` that walks the player in.  Every
    -- other use in pokegold is followed by `end` anyway.
    --
    -- Group 0 is the routine's own error arm: it eats the remaining three
    -- bytes and enters through MAPSETUP_BADWARP, which is EnterMapSpawnPoint
    -- on the map you are already standing on rather than a trip anywhere.
    local args = cmd.args or {}
    local base = (op == "warpfacing") and 1 or 0
    local facing
    if op == "warpfacing" then
      facing = Movement.dir(cmd.facing or args[1] or 0)
    end
    local group = cmd.group or args[base + 1] or 0
    local mapNum = cmd.map or args[base + 2]
    local x = cmd.x or args[base + 3]
    local y = cmd.y or args[base + 4]
    if group == 0 then
      -- MAPSETUP_BADWARP, which is a full load of the map already underfoot:
      -- HandleNewMap and LoadMapObjects are in its setup script and are NOT
      -- in MapSetupScript_ReloadMap, so this is a different hook from the
      -- `reloadmap` one above.  PlayersHousePCScript is the caller that
      -- cares -- the bedroom's decorations are rebuilt by those callbacks.
      local reload = self.badWarpFn or self.reloadMapFn
      if reload then reload() end
    elseif self.warpToFn then
      self.warpToFn(group, mapNum, x, y, facing)
    end
  elseif op == "warpcheck" then
    -- Script_warpcheck: WarpCheck (home/map.asm) -> GetDestinationWarpNumber
    -- + CopyWarpData, and on a hit `farcall EnableEvents`.  It does NOT warp
    -- by itself: it notices that the player is standing on a warp tile and
    -- lets the overworld loop take it once the script is done, which is why
    -- every use sits at the END of a scripted walk.
    --
    -- That is what drops the player through the hole a `changeblock` has just
    -- opened under them in RuinsOfAlphOmanyteChamber, and what puts them into
    -- the Pokecenter 2F link rooms after the receptionist has walked them up.
    -- The hook arms it; it must not warp mid-script.
    if self.warpCheckFn then self.warpCheckFn() end
  elseif op == "warpmod" then
    -- Script_warpmod: a warp id, then a `map_id`, into wBackupWarpNumber,
    -- wBackupMapGroup, wBackupMapNumber.  That triple is where the game
    -- believes you came IN from: Elevator's .FindCurrentFloor
    -- (engine/events/elevator.asm) reads the backup map to work out which
    -- floor you are standing on, and the escape-rope / dig return reads it to
    -- put you back outside.
    --
    -- Unreferenced by every script in pokegold; the rows the importer reports
    -- live in mis-walked regions of bank $45.  Ported anyway so the state
    -- exists the moment anything writes it.
    local args = cmd.args or {}
    local warpId = cmd.warp or args[1]
    local group = cmd.group or args[2]
    local mapNum = cmd.map or args[3]
    if self.setWarpModFn then self.setWarpModFn(warpId, group, mapNum) end
  elseif op == "blackoutmod" then
    -- Script_blackoutmod: a `map_id` into wLastSpawnMapGroup /
    -- wLastSpawnMapNumber, which is where a WHITEOUT puts the player rather
    -- than the last Pokecenter (engine/events/whiteout.asm reads the same
    -- pair; home/map.asm writes it on a normal Pokecenter entry).
    --
    -- The S.S. Aqua and Mr. Pokemon's house set it so that losing at sea or
    -- out past Cherrygrove does not respawn you somewhere you cannot leave.
    -- Distinct from the SPAWN_* id World:warpToSpawn uses today: this names a
    -- group/map pair directly, so the hook has to override that lookup.
    local args = cmd.args or {}
    local group = cmd.group or args[1]
    local mapNum = cmd.map or args[2]
    if self.setBlackoutMapFn then self.setBlackoutMapFn(group, mapNum) end
  elseif op == "newloadmap" then
    -- Script_newloadmap: hMapEntryMethod = the byte, then LoadMapStatus
    -- MAPSTATUS_ENTER and StopScript.  It RE-ENTERS THE CURRENT MAP through
    -- one of the MapSetupScripts (constants/map_setup_constants.asm,
    -- const_def $f1: $f1 WARP, $f3 RELOADMAP, $f4 TELEPORT, $f5 DOOR,
    -- $f6 FALL, $f8 LINKRETURN, $f9 TRAIN...), which is how the magnet train
    -- and a link return come back onto their own map with the right fade and
    -- sound.  Like `warp` it does not end the script; every real use is
    -- followed by `end` regardless.
    local method = cmd.method or arg1(cmd) or 0
    if self.newLoadMapFn then self.newLoadMapFn(method) end
  -- ---- windows and menus (home/menu.asm) ---------------------------------
  elseif op == "loadmenu" then
    -- `loadmenu menu_header` -> LoadMenuHeader.  The extractor follows the
    -- pointer now, so cmd.menu is the whole MenuHeader -- flags, the four
    -- border coords, the data flags and the item strings behind them.  A
    -- cache built before that leaves only the raw word, and the menu hook
    -- answers 0 for a header it cannot draw.  Stashed rather than acted on:
    -- LoadMenuHeader only copies it to wMenuHeader, and the verticalmenu /
    -- _2dmenu that follows is what opens it.
    self.menuHeader = cmd.menu or { address = wordArg(cmd) }
  elseif op == "verticalmenu" or op == "_2dmenu" then
    -- Script_verticalmenu answers with wMenuCursorY, Script__2dmenu with
    -- wMenuCursorPosition, and both `xor a` on the carry the menu returns for
    -- B.  Those cursors are 1-BASED, so the ifequal ladder after the command
    -- starts at 1 and 0 is the cancel arm: the Goldenrod coin vendor is
    -- loadmenu / verticalmenu / closewindow / ifequal 1 / ifequal 2 / sjump,
    -- and the Day-Care grid is loadmenu / _2dmenu / closewindow /
    -- ifequal 1..5.  Blocks the way yesorno does: yield the request, resume
    -- with the chosen index.
    local choice = coroutine.yield({ kind = "menu",
      style = (op == "_2dmenu") and "2d" or "vertical",
      header = self.menuHeader })
    self.scriptVar = tonumber(choice) or 0
  elseif op == "closewindow" then
    -- Script_closewindow: CloseWindow + UpdateSprites, the teardown for the
    -- window loadmenu / verticalmenu / _2dmenu put up.  The port's menu hook
    -- owns its own screen lifetime, so there is nothing left to tear down;
    -- kept as its own branch so it stops falling through the unknown-op path
    -- and so the teardown has an obvious home when a real window lands.
  -- ---- field events ------------------------------------------------------
  elseif op == "fruittree" then
    -- `fruittree tree_id` sets wCurFruitTree and JUMPS to FruitTreeScript, so
    -- nothing after it in the caller runs.  Opcodes.TERMINATORS does not list
    -- it, so the extractor kept disassembling the bytes that followed: every
    -- one of the 42 extracted fruittree scripts is this one command plus
    -- garbage, which is exactly why this branch has to return.
    --
    -- FruitTreeScript itself is transcribed here rather than looked up.  It
    -- is an engine script: nothing in the ROM's bytecode points at it, so
    -- neither it nor its text reaches data/generated, the same reason
    -- GiveItemScript is inlined in the verbosegiveitem branch above.  Text
    -- bodies from data/text/common_1.asm.
    local tree = cmd.tree or arg1(cmd) or 0
    -- callasm GetCurTreeFruit: FruitTreeItems[tree - 1], FRUITTREE_* being
    -- 1-based (constants/script_constants.asm `const FRUITTREE_ROUTE_29 ; 01`
    -- and GetCurTreeFruit's own `dec a`).  The hook undoes the offset.
    local item = self.fruitTreeItemFn and self.fruitTreeItemFn(tree) or 0
    local name = (item ~= 0 and self.getItemNameFn
      and self.getItemNameFn(item)) or "BERRY"
    -- readmem wCurFruit / getitemname STRING_BUFFER_3, USE_SCRIPT_VAR
    self.scriptVar = item
    self:setStringBuffer(name)
    self:showRaw(Strings("It's a fruit-\nbearing tree."))
    -- callasm TryResetFruitTrees / callasm CheckFruitTree / iffalse .fruit.
    -- The reset runs BEFORE the check and gated on ENGINE_ALL_FRUIT_TREES,
    -- so the first tree examined after the daily rollover refills the other
    -- twenty-nine as well as its own.
    if self.fruitTreeResetFn then self.fruitTreeResetFn() end
    -- CheckFruitTree is a CHECK_FLAG over wFruitTreeFlags, and the per-tree
    -- flag means "already picked" (ResetFruitTrees clears the lot once a
    -- day), so a CLEAR flag is the arm with fruit on it.
    local picked = self.fruitTreePickedFn and self.fruitTreePickedFn(tree)
    if picked then
      self:showRaw(Strings("There's nothing\nhere…"))
      return "end"
    end
    self:showRaw(Strings("Hey! It's\n%s!", name))
    -- readmem wCurFruit / giveitem ITEM_FROM_MEM / iffalse .packisfull
    local ok = true
    if self.giveItemFn then ok = self.giveItemFn(item, 1) ~= false end
    self.scriptVar = ok and 1 or 0
    if not ok then
      self:showRaw(Strings("But the PACK is\nfull…"))
      return "end"
    end
    self:showRaw(Strings("Obtained\n%s!", name))
    -- callasm PickedFruitTree: the flag is set AFTER the fruit is banked, so
    -- a full pack leaves the tree pickable.
    if self.fruitTreePickFn then self.fruitTreePickFn(tree) end
    if self.specialSoundFn then
      self.specialSoundFn(item)
    elseif self.playSoundFn then
      self.playSoundFn(SFX_ITEM)
    end
    -- FruitTreeScript's tail is `specialsound / itemnotify` with NOTHING
    -- between them (engine/events/fruit_trees.asm:23-24), and Script_specialsound
    -- is a bare PlaySFX -- it does not wait either (scripting.asm:476-483).
    -- The port used to park here on a `waitsfx`, which is the same seam
    -- GiveItemScript's did: this port's box takes its own button and pops on
    -- it, so the park ran with an EMPTY state stack and the bare overworld
    -- drew for the length of the jingle (163 frames measured) between the two
    -- pages of what the cart prints into ONE MapTextbox -- with Game2's play
    -- clock, which only pauses while a state is on the stack, running for
    -- every one of them.  The obtained box's own press is the drain point.
    -- itemnotify.  Berries are all ITEM pocket, so nothing here moves; the
    -- noun still comes from ItemPocketNames rather than from a third copy of
    -- the literal (data/items/pocket_names.asm:10-13).
    self:showRaw(Strings("{PLAYER} put the\n%s in\nthe %s.",
      name, self:pocketName(item)))
    return "end"
  elseif op == "describedecoration" then
    -- `describedecoration byte` picks one of five DECODESC_* arms
    -- (engine/overworld/decorations.asm) and JUMPS to the script each hands
    -- back, so like fruittree nothing after it runs and the bytes the
    -- extractor read past it are garbage.
    --
    -- Each arm is asm that chooses by what is INSTALLED in the player's
    -- room, and the extractor emits the scripts rather than the arms: the
    -- poster table plus the `end` it falls to when the wall is bare, the one
    -- script the two ornaments and the console share, and the giant
    -- ornament's.  Which one runs is decided by the wDeco* slot the arm
    -- reads, and `decorationSlot` is that read (src/core/gen2/Decorations.lua
    -- owns the slots themselves).
    --
    --   DecorationDesc_Poster       IsInArray over DecorationDesc_
    --                               PosterPointers on wDecoPoster, falling
    --                               to the bare `end` when the wall is bare
    --   ..._OrnamentOrConsole       one script for all three, with the
    --                               decoration's NAME in wStringBuffer3 --
    --                               "It's an adorable <name>!"
    --   ..._GiantOrnament           one script, no name
    local kind = cmd.decoration or arg1(cmd) or 0
    local descName = cmd.decorationName or ""
    if self.describeDecorationFn then self.describeDecorationFn(kind) end
    local arm = (self.eventTables.decorations or {})[descName]
    local placed, placedName
    if self.decorationSlotFn then
      placed, placedName = self.decorationSlotFn(descName)
    end
    if descName == "DECODESC_POSTER" and arm and arm.posters then
      for _, row in ipairs(arm.posters) do
        if row.decoration == placed then
          arm = row
          break
        end
      end
    elseif placedName then
      self:setStringBuffer(placedName)
    end
    if arm and arm.script and self.scripts[arm.script] then
      runList(self, arm.script)
      return "end"
    end
    return "end"
  elseif op == "trade" then
    -- `trade trade_id` -> NPCTrade (engine/events/npc_trade.asm): a whole
    -- blocking conversation (intro text, YesNoBox, a party pick, the gender
    -- and species checks, the trade animation) driven off
    -- data/events/npc_trades.asm, which is not extracted.  NPCTrade writes no
    -- wScriptVar, so with no hook the script simply carries on the way it
    -- does when the player backs out.
    if self.npcTradeFn then
      coroutine.yield({ kind = "trade", trade = cmd.trade or arg1(cmd) or 0 })
    end
  elseif op == "elevator" then
    -- Script_elevator: wScriptVar = 0 up front, farcall Elevator, and only a
    -- NON-carry return raises it to TRUE.  Elevator (engine/events/elevator.asm)
    -- carries on three paths (the current floor is not in the list, the
    -- player pressed B, or the player picked the floor they are already on)
    -- and it performs the ride itself, so wScriptVar means only "did we
    -- actually move".  GoldenrodDeptStoreElevatorScript's `iffalse .Done`
    -- right after is the branch that skips the SFX, the earthquake and the
    -- B1F crate reshuffle.
    --
    -- The extractor follows the operand into the map's own floor list now
    -- (db count, then `elevfloor floor, warp, map` rows), so the menu has
    -- something to offer.  With no list and no hook the answer stays 0, the
    -- player-backed-out case: answering 1 would play out a ride that never
    -- happened.
    self.scriptVar = 0
    if cmd.floors and #cmd.floors > 0 and self.elevatorFn then
      -- Elevator_GoToFloor writes wBackupWarpNumber / wBackupMapGroup /
      -- wBackupMapNumber and RIDES; the hook owns both halves, and answers
      -- the floor row it went to, or nil for a cancel and for "you picked
      -- the floor you are already on" (`cp [hl] / jr z, .quit`).
      local rode = coroutine.yield({ kind = "elevator", floors = cmd.floors })
      self.scriptVar = rode and 1 or 0
    end
  -- ---- phone (engine/phone/phone.asm) ------------------------------------
  elseif op == "askforphonenumber" then
    -- Script_askforphonenumber: YesNoBox FIRST, then AddPhoneNumber.  The
    -- answer is PHONE_CONTACT_GOT 0 / PHONE_CONTACTS_FULL 1 /
    -- PHONE_CONTACT_REFUSED 2, so SUCCESS IS ZERO here: an `iftrue` after
    -- this command means the number did NOT go in.
    local contact = cmd.phone or arg1(cmd) or 0
    local yes = coroutine.yield({ kind = "yesorno" })
    if not yes then
      self.scriptVar = PHONE_CONTACT_REFUSED
    else
      -- AddPhoneNumber returns carry, and so PHONE_CONTACTS_FULL, both when
      -- the list is full and when the number is already in it: _CheckCellNum
      -- runs before Phone_FindOpenSlot and answers with the same carry.
      local added = self.addPhoneNumberFn and self.addPhoneNumberFn(contact)
      self.scriptVar = added and PHONE_CONTACT_GOT or PHONE_CONTACTS_FULL
    end
  elseif op == "phonecall" then
    -- `phonecall caller_name` -> PhoneCall: two rings, then the caller's name
    -- in the telephone box.  docs/bugs_and_glitches.md calls this command out
    -- as one that may crash on retail (it reaches BrokenPlaceFarString, which
    -- is not in bank 0), and the only occurrence in the cache sits in a run of
    -- garbage past a fruittree, so nothing real depends on it.  Wired to the
    -- phone hook anyway, because the ring is what a script asking for it
    -- wants.
    if self.phoneCallFn then
      coroutine.yield({ kind = "phonecall",
        caller = cmd.caller or wordArg(cmd) })
    end
  elseif op == "hangup" then
    -- HangUp: PhoneClickText with SFX_HANG_UP under it, then the four <……>
    -- boops that close the call box (data/text/common_3.asm).  The sound is
    -- started BEFORE the line here because "Click!" ends in `done`: PrintText
    -- returns without waiting on the cart, while this port's text box holds
    -- until A, so playing it after would put the beep on an empty screen.
    if self.playSoundFn then self.playSoundFn(SFX_HANG_UP) end
    self:showRaw(Strings("Click!"))
    if self.hangUpFn then self.hangUpFn() end
  elseif op == "specialphonecall" then
    -- `specialphonecall call_id` only STORES the id; the call itself fires
    -- later, from CheckSpecialPhoneCall on an overworld step.  No wScriptVar.
    -- Script_specialphonecall writes two bytes but wSpecialPhoneCallID is a
    -- single `db` in wram, so the high byte lands in padding and only the low
    -- byte is ever read back.
    local id = cmd.call or wordArg(cmd)
    self.specialCall = id
    if self.setSpecialCallFn then self.setSpecialCallFn(id) end
  elseif op == "checkphonecall" then
    -- Script_checkphonecall reads only the LOW byte of wSpecialPhoneCallID
    -- (`ld a, [wSpecialPhoneCallID] / and a / jr z`), which is the whole byte
    -- the queue actually uses.  Transcribed as the low-byte test rather than
    -- tidied into a whole-word one.
    local id = self.getSpecialCallFn and self.getSpecialCallFn()
      or self.specialCall or 0
    self.scriptVar = ((id % 0x100) ~= 0) and 1 or 0
  -- ---- end of game -------------------------------------------------------
  elseif op == "halloffame" then
    -- Script_halloffame: the game timer stops, HallOfFame runs, and then
    -- ReturnFromCredits does Script_endall + MAPSTATUS_DONE.  The script
    -- stack is cleared and the overworld is torn down, so this returns
    -- whether or not a hook took the screen.
    if self.hallOfFameFn then
      coroutine.yield({ kind = "halloffame" })
    end
    return "end"
  elseif op == "credits" then
    -- Script_credits: RedCredits, then the same ReturnFromCredits teardown
    -- halloffame ends on.
    if self.creditsFn then
      coroutine.yield({ kind = "credits" })
    end
    return "end"
  -- ---- commands with no engine behind them yet ---------------------------
  elseif op == "deactivatefacing" then
    -- Script_deactivatefacing: wScriptDelay = the byte (left ALONE when the
    -- byte is 0, the same `and a / jr z` idiom Script_pause uses), then
    -- wScriptMode = SCRIPT_WAIT and StopScript.  WaitScript ticks that delay
    -- down one per frame and calls UnfreezeAllObjects before reading again,
    -- so what the command DOES is hold the script for N frames with the map's
    -- objects released.  This port never freezes them in the first place
    -- (World:step keeps updatePeople running while the VM is busy), so the
    -- wait is the whole of it and it goes through the same waitFrames `pause`
    -- uses.
    self:waitFrames(cmd.frames or arg1(cmd) or 0)
  elseif op == "writeunusedbyte" then
    -- Script_writeunusedbyte stores its operand in wUnusedScriptByte, and
    -- nothing in the ROM ever reads it back: the label is pokegold's own name
    -- for a dead write.  Kept as an explicit branch so the byte is consumed
    -- deliberately, and kept on the VM in case a romhack ever does read it.
    self.unusedScriptByte = arg1(cmd) or 0
  elseif op == "xycompare" then
    -- Script_xycompare does nothing but store a pointer in wXYComparePointer.
    -- The work happens much later, in SetXYCompareFlags (home/region.asm),
    -- which walks that table against the player's position on every map load
    -- and sets wXYCompareFlags, and which has its own famous bug (`ld a, $4`
    -- where `add $4` was meant, so the Y coordinate is never compared).
    --
    -- No map in Gold uses the command; every occurrence the extractor found
    -- is a data region mis-read as code.  So the pointer is recorded and
    -- nothing reads it, which is precisely what the cart does at this point.
    -- wScriptVar is untouched, as in the asm.
    self.xyComparePointer = wordArg(cmd)
  elseif op == "autoinput" then
    -- Script_autoinput hands a bank:pointer to StartAutoInput
    -- (home/joypad.asm), which replays a canned button stream through the
    -- joypad while the overworld keeps running: the player watches their
    -- character move on its own.  The operand is a `dba`, so the bytes are
    -- bank, then the low and high halves of the address, in that order.
    --
    -- The extractor emits those three bytes and nothing behind them, and no
    -- map in the ROM actually runs the command (every occurrence in
    -- scripts.lua is a data region mis-read as code), so the hook resolves
    -- the pointer against the four streams StartAutoInput really has call
    -- sites for -- src/core/gen2/AutoInput.lua POINTERS -- and arms nothing
    -- for anything else.  Script_autoinput does not write wScriptVar, so
    -- neither does this.
    if self.autoInputFn then
      self.autoInputFn(arg1(cmd) or 0, wordArg(cmd, 2))
    end
  elseif op == "writecmdqueue" then
    -- Script_writecmdqueue copies a five-byte entry (CMDQUEUE_ENTRY_SIZE) out
    -- of the script's own bank into the first free wCmdQueue slot;
    -- HandleQueuedCommand then polls that queue every frame.  Two maps use
    -- it, both for CMDQUEUE_STONETABLE: the Ice Path B1F boulder puzzle and
    -- the Blackthorn Gym 2F one, where the queue is what makes a pushed
    -- boulder fall into the water.
    --
    -- The five bytes sit behind a pointer in the script's own bank and the
    -- extractor emits only the pointer, so the World resolves the entry from
    -- the map instead (src/world/gen2/CmdQueue.lua STONE_TABLES).  Like the
    -- cart's own Script_writecmdqueue this leaves wScriptVar alone.
    if self.writeCmdQueueFn then
      self.writeCmdQueueFn(cmd.pointer or wordArg(cmd))
    end
  elseif op == "delcmdqueue" then
    -- Script_delcmdqueue: `xor a / ld [wScriptVar], a`, then DelCmdQueue over
    -- the queue entry whose type byte matches the operand.  Read the polarity
    -- off the `ret c`: DelCmdQueue's .done arm clears the slot and sets carry,
    -- so carry means it FOUND and deleted the entry, and that path returns
    -- with wScriptVar still 0.  The loop only falls through to
    -- `ld a, TRUE / ld [wScriptVar], a` when it ran off the end without a
    -- match.  So the command answers FALSE on a successful delete and TRUE
    -- when there was nothing to delete, which reads backwards until you check.
    --
    -- With a real queue behind it that polarity is now observable rather than
    -- academic: a map that deletes its own stone table answers FALSE.  With
    -- no hook (or an empty queue) TRUE is still the cart's answer.
    local kind = cmd.queue or arg1(cmd) or 0
    local deleted = false
    if self.delCmdQueueFn then deleted = self.delCmdQueueFn(kind) and true end
    self.scriptVar = deleted and 0 or 1
  elseif op == "unknown" or op == "truncated" then
    -- Not a command: the extractor emits these when the pointer walk ran into
    -- a byte that is not an opcode, or off the end of the bank, and both
    -- break its disassembly loop so they are always the last row in a list.
    -- Recorded separately from the unimplemented-opcode set below, because
    -- what they report is a mis-walked ROM region rather than a missing
    -- branch.  Ending the list is the only safe reading: the cart would be
    -- executing data here.
    self.badBytes[cmd.code or op] = (self.badBytes[cmd.code or op] or 0) + 1
    return "end"
  elseif op == MOD_COMMAND then
    -- A mod's verb, dispatched through the shared `commands` registry.  Last
    -- arm before the unknown-opcode ledger on purpose: no cart row can carry
    -- this op, so a stock script has already matched a branch above and never
    -- pays even this comparison.
    return self:runModCommand(cmd)
  else
    -- No branch for this opcode.  Falling through QUIETLY is the worst thing
    -- this interpreter can do: a script that runs `checkitem` and then
    -- `iftrue` reads a stale wScriptVar and takes the WRONG arm, which looks
    -- like a content bug rather than a missing command.  So keep running (a
    -- hard error would make the game unplayable over one unported command)
    -- but record it and say so once per opcode, and let the suite assert the
    -- set is empty for a script built only of implemented commands.
    self:noteUnknownOp(op)
  end
end

-- `key` is a scripts.lua key, or a command list itself: the two trainer
-- scripts (engine/events/trainer_scripts.asm) are reached through a player
-- event rather than a map pointer, so nothing extracts them and the World
-- hands them over inline.
-- Assigns the forward declaration above, not a new local: runCmd calls back
-- into this for every tail-call opcode.
function runList(self, key)
  local list = type(key) == "table" and key or self.scripts[key]
  if not list then return end
  local i = 1
  while list[i] do
    -- A whiteout replaces the running script rather than returning to it, so
    -- the abort has to unwind every nested scall as well as this list.  See
    -- `reloadmapafterbattle`.
    if self.aborted then return end
    local cmd = list[i]
    local op = cmd.op
    -- A row a MOD wrote in the Gen 1 shape, { "mymod:shake", 4, 2 }, normalised
    -- to the extension op so everything downstream -- the script.command hook's
    -- `name`, runCmd's dispatch -- sees one row kind.  The extractor stamps `op`
    -- on every row it emits (src/import/RomExtractorGen2.lua:3096, plus its
    -- "unknown" / "truncated" pair), so a row without one is never the cart's
    -- and the two shapes cannot be confused.  Vm:runModCommand has the contract.
    if op == nil and type(cmd[1]) == "string" then op = MOD_COMMAND end
    -- One-command lookahead, for `writetext`'s missing terminator.  A text that
    -- ends in `done` (home/text.asm:484) has no PromptButton, one that ends in
    -- `prompt` (:470) does, and the extractor throws the terminator away -- so
    -- the box cannot tell the two apart on its own.  What FOLLOWS the writetext
    -- can: a `yesorno` on the next row is InitYesNoTextBoxParameters going up
    -- over the box that is still holding the question, which the cart never
    -- closed.  Vm:showText reads this to keep that box standing.
    self.nextOp = list[i + 1] and list[i + 1].op or nil
    local jump
    if Runtime.wantsHook("script.command") then
      -- The SAME hook name and the same (ctx, name, args) argument list the
      -- Gen 1 runner passes (src/script/ScriptRunner.lua:164-169), so one mod
      -- can log or wrap every command in both generations.  What differs is
      -- what a "command" IS: Gen 1 dispatches a hand-ported row
      -- { "command", arg, ... } through the verb table, this VM dispatches one
      -- decoded row of the CART's own bytecode.  So `name` is the opcode name
      -- out of src/script/gen2/Opcodes.lua and `args` is its raw operand byte
      -- list -- which for most opcodes is empty, because the extractor decodes
      -- the interesting operands into NAMED fields (cmd.text, cmd.script,
      -- cmd.value, cmd.object).  The whole decoded row rides along as a fourth
      -- argument so a Gen 2 aware mod can read those without re-walking the
      -- bytes; a Gen 1 shaped wrapper that only takes three simply ignores it.
      --
      -- Hooks:call pcalls every link and the vanilla, and the command under it
      -- YIELDS (text, yesorno, movement, battle).  That only works because the
      -- engine runs on LuaJIT, whose pcall is resumable; stock Lua 5.1 would
      -- raise "attempt to yield across a C-call boundary" here.  Same contract
      -- the Gen 1 runner already relies on (src/script/ScriptRunner.lua:164).
      -- A mod's row reports the operands it actually dispatches with, which for
      -- a Gen 1 shaped row is the row's own tail rather than an `args` field.
      local args = (op == MOD_COMMAND and modArgs(cmd)) or cmd.args or {}
      jump = Runtime.call("script.command", function(_, hname, hargs, hcmd)
        -- Honour a link that rewrote the operand list on its way down, the way
        -- `nextFn(ctx, name, newargs)` does on Gen 1: run a copy of the row
        -- carrying the new operands rather than the row the cart wrote.
        local row = hcmd or cmd
        if hargs ~= nil and hargs ~= args and hargs ~= row.args then
          local copy = {}
          for k, v in pairs(row) do copy[k] = v end
          copy.args = hargs
          row = copy
        end
        -- `op` last, not row.op: a Gen 1 shaped mod row carries no `op` field
        -- and it is the normalisation above that made it a modcommand.
        return runCmd(self, row, hname or row.op or op)
      end, self:scriptCtx(), op, args, cmd)
    else
      jump = runCmd(self, cmd, op)
    end
    if jump == "end" then
      return
    elseif type(jump) == "number" then
      -- A hook-returned program counter, same as the Gen 1 runner's.
      i = jump
    else
      -- Gen 1 also lets a jump be a LABEL name; this VM's rows are the cart's
      -- own bytecode and carry no labels, so any other string is a mod asking
      -- for something that cannot exist here.  Say so once and fall through.
      if type(jump) == "string" then self:noteBadJump(jump) end
      i = i + 1
    end
  end
end

function Vm.new(scripts, text, events, hooks)
  hooks = hooks or {}
  local movements = (scripts and scripts.movements) or hooks.movements or {}
  return setmetatable({
    scripts = scripts or {},
    movements = movements,
    text = text or {},
    events = events,
    -- data/generated/events.lua: the side tables a command NAMES rather than
    -- carries (the trades, the floor labels, the decoration scripts).  Not the
    -- same thing as `events` above, which is wEventFlags.
    eventTables = hooks.eventTables or {},
    -- The `commands` registry as merged into data.commands: verb -> handler,
    -- for the mod verbs a mod-authored row can name (Vm:runModCommand).  Left
    -- ABSENT when the boot supplies none, so Vm.__index falls through to the
    -- module-level Vm.setCommands default and a mod-free boot has neither.
    commands = hooks.commands,
    scriptVar = 0,
    stringBuffer = "",
    busy = false,
    lastTalked = nil,
    showTextFn = hooks.showText,
    facePlayerFn = hooks.facePlayer,
    onFlagsChanged = hooks.onFlagsChanged,
    setSceneFn = hooks.setScene,
    getSceneFn = hooks.getScene,
    setMapSceneFn = hooks.setMapScene,
    turnObjectFn = hooks.turnObject,
    applyMovementFn = hooks.applyMovement,
    yesornoFn = hooks.yesorno,
    disappearFn = hooks.disappear,
    showPicFn = hooks.showPic,
    hidePicFn = hooks.hidePic,
    -- WaitButton for the one command that needs a real press of its own,
    -- `waitbutton` under an open `pokepic` window.  Absent on a headless
    -- build, and the opcode then keeps its old free pass rather than parking
    -- on a resume nobody will call.
    waitButtonFn = hooks.waitButton,
    getMonNameFn = hooks.getMonName,
    getItemNameFn = hooks.getItemName,
    -- CheckItemPocket on an item index -> "ITEM" | "KEY_ITEM" | "BALL" |
    -- "TM_HM", which is what GetPocketName indexes ItemPocketNames with.  The
    -- same lookup the world already makes for specialsound's TM/HM jingle.
    getItemPocketFn = hooks.getItemPocket,
    getTrainerNameFn = hooks.getTrainerName,
    setStringBufferFn = hooks.setStringBuffer,
    givePokeFn = hooks.givePoke,
    giveItemFn = hooks.giveItem,
    addCellFn = hooks.addCell,
    delCellFn = hooks.delCell,
    hasCellFn = hooks.hasCell,
    cryFn = hooks.cry,
    playSoundFn = hooks.playSound,
    playMusicFn = hooks.playMusic,
    specialSoundFn = hooks.specialSound,
    waitSfxFn = hooks.waitSfx,
    -- StartAutoInput, by script pointer (`autoinput`) and by stream name
    -- (CatchTutorial), plus StopAutoInput.  See src/core/gen2/AutoInput.lua.
    autoInputFn = hooks.autoInput,
    autoInputStreamFn = hooks.autoInputStream,
    stopAutoInputFn = hooks.stopAutoInput,
    readVarFn = hooks.readVar,
    -- Optional: the World's own label for the map a run belongs to.  Nothing
    -- inside the interpreter needs it -- only Vm:scriptCtx, which falls back to
    -- the cart's group:number pair when the World does not supply one.
    mapIdFn = hooks.mapId,
    -- `special` id -> SpecialsPointers label (constants.specialOrder).
    specialOrder = hooks.specialOrder,
    -- The world half of src/script/gen2/Specials.lua, as ONE sub-table: a
    -- special is an independent routine, so giving each its own `xFn` field
    -- here would have doubled this constructor for no gain.
    specials = hooks.specials,
    healPartyFn = hooks.healParty,
    healAnimFn = hooks.healAnim,
    nameRivalFn = hooks.nameRival,
    warpToSpawnFn = hooks.warpToSpawn,
    showMoneyFn = hooks.showMoney,
    showCoinsFn = hooks.showCoins,
    openPcFn = hooks.openPc,
    -- OpenMartDialog; nil means the shop is skipped rather than hanging.
    openMartFn = hooks.openMart,
    -- Trainer battles: the object's `trainer` struct is pushed in by the
    -- World before the script runs (LoadTrainer_continue's wTempTrainer).
    lookupTrainerFn = hooks.lookupTrainer,
    startBattleFn = hooks.startBattle,
    -- CatchTutorial's own StartBattle, which is a different entry point: no
    -- party mon is sent out and the DUDE plays it (engine/events/
    -- catch_tutorial.asm).
    catchTutorialFn = hooks.catchTutorial,
    reloadMapFn = hooks.reloadMap,
    badWarpFn = hooks.badWarp,
    encounterMusicFn = hooks.encounterMusic,
    showEmoteFn = hooks.showEmote,
    trainerApproachFn = hooks.trainerApproach,
    faceObjectFn = hooks.faceObject,
    followFn = hooks.follow,
    stopFollowFn = hooks.stopFollow,
    -- Scene / clock / cartridge identity.
    getMapSceneFn = hooks.getMapScene,
    getTimeOfDayFn = hooks.getTimeOfDay,
    gsVersionFn = hooks.gsVersion,
    -- ENGINE_* flags (badges, Pokegear cards, the contest timer): a different
    -- namespace from the wEventFlags the setevent / clearevent pair writes.
    getEngineFlagFn = hooks.getEngineFlag,
    setEngineFlagFn = hooks.setEngineFlag,
    -- Raw WRAM bytes and VAR_* slots.
    readMemFn = hooks.readMem,
    writeMemFn = hooks.writeMem,
    writeVarFn = hooks.writeVar,
    callAsmFn = hooks.callAsm,
    -- Map objects.
    appearFn = hooks.appear,
    moveObjectFn = hooks.moveObject,
    variableSpriteFn = hooks.variableSprite,
    loadEmoteFn = hooks.loadEmote,
    -- Map blocks and warps.
    changeBlockFn = hooks.changeBlock,
    changeMapBlocksFn = hooks.changeMapBlocks,
    earthquakeFn = hooks.earthquake,
    warpToFn = hooks.warpTo,
    warpCheckFn = hooks.warpCheck,
    warpSoundFn = hooks.warpSound,
    newLoadMapFn = hooks.newLoadMap,
    writeCmdQueueFn = hooks.writeCmdQueue,
    delCmdQueueFn = hooks.delCmdQueue,
    setWarpModFn = hooks.setWarpMod,
    setBlackoutMapFn = hooks.setBlackoutMap,
    -- Encounters.
    setSwarmFn = hooks.setSwarm,
    setWildEncountersFn = hooks.setWildEncounters,
    rollWildFn = hooks.rollWild,
    -- Music.
    playMapMusicFn = hooks.playMapMusic,
    fadeOutMusicFn = hooks.fadeOutMusic,
    dontRestartMapMusicFn = hooks.dontRestartMapMusic,
    -- Bag, money and coins.
    hasItemFn = hooks.hasItem,
    takeItemFn = hooks.takeItem,
    getMoneyFn = hooks.getMoney,
    setMoneyFn = hooks.setMoney,
    getCoinsFn = hooks.getCoins,
    setCoinsFn = hooks.setCoins,
    -- Party.
    hasPokeFn = hooks.hasPoke,
    giveEggFn = hooks.giveEgg,
    givePokeMailFn = hooks.givePokeMail,
    checkPokeMailFn = hooks.checkPokeMail,
    getLandmarkNameFn = hooks.getLandmarkName,
    -- loadmenu stashes a header for the verticalmenu / _2dmenu that follows;
    -- openMenu is the blocking half, modelled on yesorno.
    openMenuFn = hooks.openMenu,
    -- Field events.
    fruitTreeItemFn = hooks.fruitTreeItem,
    fruitTreeResetFn = hooks.fruitTreeReset,
    fruitTreePickedFn = hooks.fruitTreePicked,
    fruitTreePickFn = hooks.fruitTreePick,
    describeDecorationFn = hooks.describeDecoration,
    decorationSlotFn = hooks.decorationSlot,
    npcTradeFn = hooks.npcTrade,
    elevatorFn = hooks.elevator,
    -- Phone.
    addPhoneNumberFn = hooks.addPhoneNumber,
    phoneCallFn = hooks.phoneCall,
    hangUpFn = hooks.hangUp,
    setSpecialCallFn = hooks.setSpecialCall,
    getSpecialCallFn = hooks.getSpecialCall,
    -- End of game.
    hallOfFameFn = hooks.hallOfFame,
    creditsFn = hooks.credits,
    trainerObject = nil,
    trainer = nil,
    justBattled = false,
    lastSpecial = nil,
    -- Sparse WRAM store for readmem / writemem / loadmem: the Goldenrod switch
    -- room and the MooMoo berries are counters with nowhere else to live, and
    -- a read / addval / write triple has to add up even with no World hook.
    mem = {},
    -- ENGINE_* flags, when nothing supplies getEngineFlag / setEngineFlag.
    engineFlags = {},
    -- wVariableSprites: slot ($f0 SPRITE_CONSOLE .. $fc) -> sprite byte.
    variableSprites = {},
    -- Every opcode that reached the final else, and every extractor `unknown` /
    -- `truncated` row, so a test can assert both are empty for a real script.
    unknownOps = {},
    badBytes = {},
    -- Every map callback that tried to block, by script key.  Empty is the
    -- invariant: see Vm:runCallback.
    blockedCallbacks = {},
    menuHeader = nil,
    loadedEmote = nil,
    lastTextKey = nil,
    unusedScriptByte = nil,
    xyComparePointer = nil,
    specialCall = nil,
    dontRestartMapMusic = false,
    wildEncounters = true,
  }, Vm)
end

-- The sparse WRAM store as a plain table for the save file, and back.  Same
-- contract as Events:serialize / Events:restore: address -> byte, sparse, and
-- never a dense WRAM image (the cart has 8K of it and a script touches a
-- handful of bytes).  Zeroes are dropped on the way out because a missing
-- address already reads back as 0 in the readmem arm above.
--
-- The addresses the World claims through readMem / writeMem are NOT in here:
-- those belong to whatever engine state answered for them and are persisted by
-- their own owner.  This is only the bytes with nowhere else to live -- the
-- Goldenrod underground switches and wMooMooBerries.
function Vm:serializeMem()
  local out = {}
  for addr, value in pairs(self.mem) do
    if value ~= 0 then out[addr] = value end
  end
  return out
end

function Vm:restoreMem(bytes)
  if type(bytes) ~= "table" then return self end
  self.mem = {}
  for addr, value in pairs(bytes) do
    -- A serialized file can hand these back as strings; the readmem arm
    -- indexes by number, so a string key would silently read as 0.
    local index, byte = tonumber(addr), tonumber(value)
    if index and byte then self.mem[index] = byte % 256 end
  end
  return self
end

-- The unknown-opcode ledger.  Warn once per opcode name so a script in a loop
-- cannot flood the log, and keep the set so gen2_vm_test can assert it stays
-- empty across the whole extracted cache.
function Vm:noteUnknownOp(op)
  if op == nil then return end
  if self.unknownOps[op] then
    self.unknownOps[op] = self.unknownOps[op] + 1
    return
  end
  self.unknownOps[op] = 1
  Logger.warn("gen2 script: unimplemented opcode '%s' skipped", tostring(op))
end

-- Same ledger shape as noteUnknownOp: a `script.command` wrapper that returned
-- a Gen 1 LABEL name has asked for something the cart's bytecode has no notion
-- of, and a mod that does it once does it on every row, so warn once per name.
function Vm:noteBadJump(name)
  self.badJumps = self.badJumps or {}
  if self.badJumps[name] then return end
  self.badJumps[name] = true
  Logger.warn("gen2 script: script.command returned label '%s'; " ..
    "this VM has no labels, falling through", tostring(name))
end

-- ---- the mod verb table ----------------------------------------------------
--
-- THE CONTRACT.  Read this before adding a caller.
--
-- Gen 1 scripts are hand-written row lists ({ "command", args... }) and a mod
-- extends the language by registering a verb into the `commands` registry, which
-- src/script/ScriptRunner.lua:150 resolves by NAME on every row.  There is no
-- name to resolve here: this VM runs the CART's bytecode, where a command is an
-- opcode byte and every byte that means anything already means something
-- (src/script/gen2/Opcodes.lua).  Handing mods one of the free bytes would be
-- worse than useless -- ROM data that happens to start with it would decode as a
-- mod call instead of ending the pointer walk.
--
-- So the seam is a row the CART CANNOT WRITE.  Opcodes.MOD_COMMAND
-- ("modcommand") is an op name with no byte behind it, and the extractor only
-- ever stamps names out of the byte table plus its own "unknown" / "truncated"
-- pair.  A stock Gold boot therefore decodes byte for byte as it did before this
-- function existed and can never reach it; what reaches it is a row a mod wrote,
-- in either of two shapes:
--
--   { op = "modcommand", verb = "mymod:shake", args = { 4, 2 } }   -- native
--   { "mymod:shake", 4, 2 }                                        -- Gen 1 row
--
-- The second is the Gen 1 row shape verbatim (runList normalises it), so a mod
-- can ship ONE row list for both games as long as every row in it is its own
-- verb.  A list like that is runnable today: Vm:start and Vm:runCallback both
-- take a table of rows as well as a scripts.lua key, and `scall` / `sjump`
-- targets are keys into the same pool.
--
-- The verb resolves against the SAME registry Gen 1 uses -- same registry name
-- `commands`, same record shape, a bare function or the flagged table
-- { fn, foreground, blocking } that src/script/Commands.lua:1381-1390 unpacks --
-- reached through hooks.commands at Vm.new, or through Vm.setCommands for a boot
-- path with no way into that hooks literal.  `foreground` and `blocking` are
-- unpacked and ignored: they exist for Gen 1's parallel ambient runner, and this
-- VM has one script frame, so there is no second runner for them to mean
-- anything against.
--
-- The handler is called as fn(ctx, unpack(args)) with the same per-run ctx every
-- other mod-facing site in this file hands out (Vm:scriptCtx): ctx.vm where Gen 1
-- has ctx.runner, and no ctx.game / ctx.save / ctx.overworld, because this VM
-- owns none of them.  Its return value speaks runCmd's vocabulary, which is Gen
-- 1's control-command vocabulary: "end" ends the list, a number is a 1-based row
-- to continue at, nil falls through to the next row.  A verb may block exactly
-- the way a command does -- ctx.vm:showText, :showRaw and :waitFrames all yield
-- the VM's coroutine and Vm:resume drives them back.
function Vm.setCommands(source)
  -- Module-level default rather than per-instance: instances inherit it through
  -- Vm.__index, so hooks.commands still wins for a VM that was given one and
  -- everybody else sees whatever the boot installed.  The intended argument is
  -- the merged data.commands table, which is where the `commands` registry
  -- lands for both generations.  Whoever installs it owns replacing it: the
  -- merged table is rebuilt per boot and per mod hot reload, so the install has
  -- to happen on the same beat, and nil clears it back to a mod-free VM.
  Vm.commands = source
  return source
end

-- verb -> handler, unpacking the record shape Commands.resolve unpacks.  The
-- source is a table (data.commands) or a function(verb) for a boot that would
-- rather resolve lazily; nil for a mod-free boot, which is the only check the
-- dispatch path below pays for.
function Vm:resolveVerb(verb)
  local source = self.commands
  if source == nil or type(verb) ~= "string" then return nil end
  local record
  if type(source) == "function" then
    record = source(verb)
  else
    record = source[verb]
  end
  if type(record) == "table" then return record.fn, record end
  if type(record) == "function" then return record, nil end
  return nil
end

function Vm:runModCommand(cmd)
  local verb = cmd.verb or cmd[1]
  local fn = self:resolveVerb(verb)
  if type(fn) ~= "function" then
    self:noteUnknownVerb(verb)
    return nil
  end
  -- pcall, and then keep going: the same call the unimplemented-opcode arm in
  -- runCmd makes, for the same reason -- one bad row out of a third-party mod
  -- must not be able to make Gold unplayable.  Gen 1's runner lets the error
  -- reach the coroutine because a Gen 1 script IS the mod's contribution and
  -- dying with it is honest; here the mod's verb is one row inside the cart's
  -- own script, and taking the map's script down with it would blame the wrong
  -- author.  The pcall is resumable because the engine runs on LuaJIT, the same
  -- contract the script.command hook above already depends on.
  local ok, jump = pcall(fn, self:scriptCtx(), unpack(modArgs(cmd)))
  if ok then return jump end
  self:noteFailedVerb(verb, jump)
  return nil
end

-- Same one-warning-per-name ledger as noteUnknownOp, kept in its OWN table: a
-- verb nobody registered is a missing mod, not an unported opcode, and
-- gen2_vm_test asserts the opcode ledger stays empty across the whole cache.
function Vm:noteUnknownVerb(verb)
  local name = tostring(verb)
  self.unknownVerbs = self.unknownVerbs or {}
  if self.unknownVerbs[name] then
    self.unknownVerbs[name] = self.unknownVerbs[name] + 1
    return
  end
  self.unknownVerbs[name] = 1
  Logger.warn("gen2 script: no command '%s' in the commands registry; " ..
    "row skipped", name)
end

-- A verb that raised.  Reported to the mod manager's feed as well as the log
-- when the verb names its owner: the registries drop the owner at merge time, so
-- the "modid:verb" namespace mods write themselves (mods/examples/
-- example_lost_parcel: "example_lost_parcel:count_ask") is the only handle on it
-- this side of the loader.  A verb with no prefix is logged and blamed on nobody
-- rather than on a guess.
function Vm:noteFailedVerb(verb, err)
  local name = tostring(verb)
  self.failedVerbs = self.failedVerbs or {}
  local modId = name:match("^([^:]+):")
  if modId then Runtime.reportError(modId, name .. ": " .. tostring(err)) end
  if self.failedVerbs[name] then return end
  self.failedVerbs[name] = tostring(err)
  Logger.error("gen2 script: command '%s' failed: %s", name, tostring(err))
end

-- ---- the mod-facing script lifecycle ---------------------------------------
--
-- `script.started` / `script.ended` / `script.command` are the SAME three names
-- and the same payload keys the Gen 1 runner raises
-- (src/script/ScriptRunner.lua:119-190): both events carry { ctx = ... } and
-- `script.ended` additionally carries completed = true/false, so a mod that
-- brackets a run works unchanged on Gold.
--
-- What the names MEAN differs, and pretending otherwise would be the lie:
-- Gen 1's ctx is a bag of engine services (game, overworld, save, runner) plus
-- the row list's own extras, because a Gen 1 script is hand-ported rows this
-- engine wrote.  This VM runs the CART's bytecode; it owns no Game and no save,
-- and the facts that identify a run are the cart's own -- which map it belongs
-- to, which script pointer it started at, and which map object it hangs off.
-- Those are what go in, plus `vm` as the analogue of Gen 1's `runner` and
-- `generation` so a shared mod can tell the two apart without guessing.
--
-- The ctx is built once per run and memoised: a script that runs 200 commands
-- with a `script.command` wrapper installed must not build 200 tables, and the
-- Gen 1 runner likewise hands the same table to every command in a run.
function Vm:scriptCtx()
  local ctx = self.ctx
  if ctx then return ctx end
  local group, number
  if self.readVarFn then
    group, number = self.readVarFn(VAR_MAPGROUP), self.readVarFn(VAR_MAPNUMBER)
  end
  ctx = {
    vm = self,
    generation = 2,
    -- The scripts.lua key the run started from: "<bank>:<addr>" out of the ROM
    -- walk, or the command list itself for the two inline trainer scripts the
    -- World hands over (see runList).
    scriptKey = self.ctxKey,
    -- "script" for a CallMapScript-style run (Vm:start), "callback" for a
    -- MAPCALLBACK_* body (Vm:runCallback), which the cart runs on a nested
    -- frame rather than as the player's script.
    kind = self.ctxKind or "script",
    -- constants/map_constants.asm names a map by group + number, and that pair
    -- is all the VM can see; `mapId` is the World's own label when it supplies
    -- one (hooks.mapId) and the cart's "<group>:<number>" otherwise.  Do not
    -- parse it -- read mapGroup / mapNumber for the numbers.
    -- string.format, not Strings(): this is a machine id for a mod to key on,
    -- not player-facing text a translator should ever see.
    mapId = (self.mapIdFn and self.mapIdFn())
      or (group and string.format("%d:%d", group, number or 0)) or nil,
    mapGroup = group,
    mapNumber = number,
    -- hLastTalked: the 1-based map object this run hangs off, as the World
    -- stamped it before calling Vm:start.  nil for a run no object owns, and
    -- stale from the last conversation for a sign or a callback -- which is
    -- exactly what wLastTalked is on the cart, so it is reported as-is.
    object = self.lastTalked,
  }
  self.ctx = ctx
  return ctx
end

-- completed = false is an abandoned run, not a short one: a whiteout that
-- unwound the list (self.aborted), a coroutine that died on a Lua error, or a
-- map callback that yielded with nowhere to park.  Same distinction the Gen 1
-- runner draws when its resume fails.
function Vm:emitScriptEnded(completed)
  if Runtime.wants("script.ended") then
    Runtime.emit("script.ended",
      { ctx = self:scriptCtx(), completed = completed and true or false })
  end
  self.ctx = nil
end

-- The `trainer` struct only stores class + member; the roster comes from
-- trainers.lua through the World, so the VM never touches that table itself.
function Vm:lookupTrainer(class, member)
  if not (class and member) then return nil end
  if not self.lookupTrainerFn then return { class = class, member = member } end
  return self.lookupTrainerFn(class, member)
end

-- `special` handlers.  The script command carries an index into
-- SpecialsPointers (data/events/special_pointers.asm), which the extractor
-- turns into a name via constants.specialOrder; keying on the name rather than
-- the number means a repointed table cannot silently call the wrong routine.
--
-- The table itself lives in src/script/gen2/Specials.lua: 112 independent
-- routines are a different kind of code from one interpreter, and growing them
-- inside this file would have buried runList.  Everything there is either a
-- ported handler or a deliberate stub with its reason written down.
Vm.SPECIALS = Specials.ALL

function Vm:specialName(id)
  local order = self.specialOrder
  if not order or not id then return nil end
  return order[id + 1]
end

function Vm:runSpecial(id, _cmd)
  local name = self:specialName(id)
  local handler = name and Vm.SPECIALS[name]
  self.lastSpecial = name or id
  if handler then handler(self) end
end

-- wStringBuffer2 in one place: the VM substitutes {STRBUF} itself for the text
-- it yields, and the hook mirrors it onto the game so the shared {STRBUF} token
-- can cover any page the VM did not build (a stale buffer is the cart's own
-- behaviour -- CopyName1 never clears it).
function Vm:setStringBuffer(value)
  self.stringBuffer = value or ""
  if self.setStringBufferFn then self.setStringBufferFn(self.stringBuffer) end
end

-- CurItemName (engine/overworld/scripting.asm:507).  It reads wCurItem and
-- NOTHING else: the name in the "put the ... in" box comes from the item the
-- last giveitem banked, never from a string buffer.  Reading self.stringBuffer
-- there instead was what made Mr. Pokemon's MYSTERY EGG hand-over print
-- whatever name an earlier script had left behind (maps/MrPokemonsHouse.asm
-- :31-35 is a plain `giveitem` / `itemnotify` pair with a getstring before it).
function Vm:curItemName()
  if not (self.getItemNameFn and self.curItem) then return "" end
  return self.getItemNameFn(self.curItem) or ""
end

-- GetPocketName (engine/overworld/scripting.asm:488).  A VM built without the
-- hook (drivers, tests) keeps printing ITEM POCKET, which is the pocket the
-- overwhelming majority of the items these boxes name really live in.
function Vm:pocketName(item)
  local pocket = self.getItemPocketFn and item and self.getItemPocketFn(item)
  return POCKET_NAMES[pocket] or POCKET_NAMES.ITEM
end

function Vm:emitFace(doFace)
  if doFace and self.facePlayerFn then self.facePlayerFn() end
end

-- True when the command after the one being run is the cart's YES/NO prompt,
-- i.e. this box must not pop before the prompt goes up over it.  `promptbutton`
-- is deliberately NOT included: its own arm is a no-op here, so a box held open
-- for it would never be taken down, and the player presses A exactly once
-- either way.
function Vm:textStays()
  return self.nextOp == "yesorno"
end

-- `stay` is also settable per command, for the hand-ported scripts that hold
-- the box open over something that is not `yesorno`: HiddenItems'
-- FindItemInBallScript prints the found line, plays SFX_ITEM and then holds on
-- `pause 60` before the itemnotify line goes into the SAME MapTextbox
-- (engine/events/misc_scripts.asm:13-17).  A one-command lookahead cannot see
-- that -- the next op is `playsound`, not the hold -- so the transcription says
-- so itself.
--
-- `hold` is the cart `pause` those held-over commands contain, in frames.  It
-- travels with the text rather than being run as a `pause` of its own because
-- the port's world does not tick while a box is on the stack (Game2:update
-- stops at the top state), so the only clock that can count it is the box's;
-- World:showText is where it lands.
function Vm:showRaw(body, stay, hold)
  if not body or body == "" then body = "..." end
  if self.stringBuffer and self.stringBuffer ~= "" then
    body = body:gsub("{STRBUF}", self.stringBuffer)
  end
  if self.showTextFn then
    coroutine.yield({
      kind = "text",
      text = body,
      stay = (stay or self:textStays()) and true or false,
      hold = hold,
    })
  end
end

function Vm:showText(textKey)
  local body = textKey and self.text[textKey]
  -- wScriptTextAddr: jumptext / jumptextfaceplayer park their pointer there and
  -- JumpTextScript's `repeattext -1, -1` is what actually prints it.
  if textKey then self.lastTextKey = textKey end
  if not body or body == "" then body = "..." end
  if self.stringBuffer and self.stringBuffer ~= "" then
    -- Only the {STRBUF} marker reads the buffer.  The buffer is STALE by
    -- design (CopyName1 never clears it, so a berry picked an hour ago is
    -- still sitting in wStringBuffer2), which is why a text without the
    -- marker must never have the buffer spliced in on a guess: every
    -- extracted `received` text is complete, marker or literal.
    body = body:gsub("{STRBUF}", self.stringBuffer)
  end
  if self.showTextFn then
    coroutine.yield({ kind = "text", text = body, stay = self:textStays() })
  end
end

-- Script_pause's frame count, and the same hold `earthquake`, `showemote` and
-- `deactivatefacing` end on.  There is deliberately NO world hook here: a wait
-- has to SUSPEND the script, so it yields and Vm:resume parks the count in
-- waitLeft, which Vm:update spends.  A hook would have run the wait beside the
-- VM instead of inside it, and the script would have walked on through it.
function Vm:waitFrames(n)
  if n and n > 0 then
    coroutine.yield({ kind = "wait", frames = n })
  end
end

-- `pause` and `showemote`, the two commands that go through Script_pause
-- itself (engine/overworld/scripting.asm:2110-2124, and ShowEmoteScript's
-- `pause 0` reading the wScriptDelay Script_showemote just wrote).  Its inner
-- loop is `ld c, 2 / call DelayFrames` ONCE PER UNIT, so the hardware holds
-- two frames per operand byte: `pause 60` is 120 frames.
--
-- The factor lives here and not in waitFrames because the other two waiters do
-- not share the routine.  `deactivatefacing` hands the byte to WaitScript,
-- which does one `dec [wScriptDelay]` per frame (:30-42), and `earthquake`
-- spends it as a step_sleep, which StepFunction_Sleep also decrements once per
-- frame -- both are already 1:1 and doubling them would be a new bug.
function Vm:pauseFrames(n)
  self:waitFrames(Vm.pauseLength(n))
end

-- The same doubling, without the yield: a `pause` that a transcription folded
-- into the text row above it (rawtext's `hold`) is counted by the box, not by
-- the VM, but it is the same Script_pause operand and must not read differently.
function Vm.pauseLength(n)
  return (n or 0) * 2
end

function Vm:running()
  return self.busy
end

function Vm:start(scriptKey)
  if self.busy or not scriptKey then return false end
  if type(scriptKey) ~= "table" and not self.scripts[scriptKey] then
    return false
  end
  self.busy = true
  self.scriptVar = 0
  -- wRunningTrainerBattleScript and the win/loss overrides are per-run: the
  -- next script must not see the last one's battle.
  self.justBattled = false
  self.battleOutcome = nil
  self.winTextOverride = nil
  self.lossTextOverride = nil
  self.winLossArmed = nil
  -- The whiteout abort is per-run too: a script that ended because the player
  -- was wiped must not stop the next one before it starts.
  self.aborted = false
  -- The mod-facing run identity, rebuilt per run (Vm:scriptCtx).  Set BEFORE
  -- the emit so the event carries this run's key, not the last one's.
  self.ctx, self.ctxKey, self.ctxKind = nil, scriptKey, "script"
  if Runtime.wants("script.started") then
    Runtime.emit("script.started", { ctx = self:scriptCtx() })
  end
  self.co = coroutine.create(function()
    runList(self, scriptKey)
  end)
  self:resume()
  return true
end

-- ExecuteCallbackScript (home/map.asm), which is how a MAPCALLBACK_* body runs.
--
-- Not the same entry as Vm:start.  RunMapCallback does NOT check wScriptRunning
-- the way CallMapScript does, and it must not: every warp a SCRIPT takes is a
-- map load with that script still parked (Script_warp calls StopScript, which
-- clears SCRIPT_RUNNING for the frame and leaves wScriptPos where it was), and
-- the four callbacks inside the setup script run before it resumes.  So a
-- callback has to be runnable while this VM is busy.
--
-- What the cart saves around the nested run is wScriptMode and wScriptFlags,
-- and CallCallback pushes the parent's bank/position onto wScriptStack so
-- Script_endcallback's ExitScriptSubroutine pops straight back to it.  Here the
-- parked coroutine and the request it is parked on ARE that stack frame, so
-- they are what gets saved and put back.
--
-- wScriptVar is deliberately NOT saved: the cart does not save it either, so a
-- callback's own `checkevent` really does clobber the parent script's copy.
--
-- Nothing reachable from an extracted callback yields (no text, no battle, no
-- movement -- ScriptEvents runs inside the map load, with no frame to come back
-- on), and a callback that tried to would have nowhere to park.  One that does
-- is abandoned with the parent's frame put back untouched, and recorded, rather
-- than silently overwriting the request the parent is waiting on.
function Vm:runCallback(scriptKey)
  if not scriptKey then return false end
  if type(scriptKey) ~= "table" and not self.scripts[scriptKey] then
    return false
  end
  local parent = {
    busy = self.busy, co = self.co, pending = self.pending,
    waitLeft = self.waitLeft,
    waitSfx = self.waitSfx, waitSfxLeft = self.waitSfxLeft,
    -- The mod-facing ctx is part of the parent's frame: the callback runs as
    -- its own `script.started` / `script.ended` pair, and the parent's next
    -- command must go back to reporting the parent's run.
    ctx = self.ctx, ctxKey = self.ctxKey, ctxKind = self.ctxKind,
  }
  -- SCRIPT_RUNNING is set for the nested run (EnableScriptMode), so a hook that
  -- asks "is a script up?" -- the deferred object rebuild is the one that does
  -- -- answers the same yes it would inside any other script.
  self.busy = true
  self.co, self.pending = nil, nil
  self.waitLeft, self.waitSfx, self.waitSfxLeft = nil, nil, nil
  local abortedBefore = self.aborted
  self.aborted = false
  self.ctx, self.ctxKey, self.ctxKind = nil, scriptKey, "callback"
  if Runtime.wants("script.started") then
    Runtime.emit("script.started", { ctx = self:scriptCtx() })
  end
  local co = coroutine.create(function() runList(self, scriptKey) end)
  local ok, req = coroutine.resume(co)
  local finished = ok and coroutine.status(co) == "dead"
  -- Closed out while this run's ctx is still current: a callback that yielded
  -- with nowhere to park is abandoned, which is the completed = false case,
  -- and so is one that died on a Lua error (re-raised below).
  self:emitScriptEnded(finished)
  self.busy, self.co, self.pending = parent.busy, parent.co, parent.pending
  self.waitLeft = parent.waitLeft
  self.waitSfx, self.waitSfxLeft = parent.waitSfx, parent.waitSfxLeft
  self.aborted = abortedBefore
  self.ctx, self.ctxKey, self.ctxKind = parent.ctx, parent.ctxKey, parent.ctxKind
  if not ok then error(req) end
  if not finished then
    self:noteBlockedCallback(scriptKey, req)
    return false
  end
  return true
end

-- The blocked-callback ledger, the same shape as the unknown-opcode one: warn
-- once per script key so a callback that runs on every map load cannot flood
-- the log, and keep the set so a test can assert it stays empty.
function Vm:noteBlockedCallback(scriptKey, req)
  local key = tostring(scriptKey)
  self.blockedCallbacks = self.blockedCallbacks or {}
  if self.blockedCallbacks[key] then return end
  self.blockedCallbacks[key] = (req and req.kind) or true
  Logger.warn("gen2 map callback '%s' blocked on '%s'; abandoned",
    key, tostring(req and req.kind or "?"))
end

-- RunSceneScript's tail (engine/overworld/events.asm:414-429): the scene body
-- has just run to its `end`, and only NOW is the script `sdefer` recorded
-- CallScript'd -- as this pass's player event, so it runs after the whole scene
-- body rather than at the sdefer command's own position.  A whiteout unwound
-- the script instead of ending it, so nothing is left to defer to.
function Vm:runDeferred()
  local script = self.deferred
  self.deferred = nil
  if not script or self.aborted then return false end
  return self:start(script)
end

function Vm:resume(resumeValue)
  if not self.co then return end
  local ok, req = coroutine.resume(self.co, resumeValue)
  if not ok then
    self.busy = false
    self.co = nil
    self:emitScriptEnded(false)
    error(req)
  end
  if coroutine.status(self.co) == "dead" then
    self.busy = false
    self.co = nil
    self.pending = nil
    -- A whiteout unwound the list rather than running it out, so `aborted` is
    -- exactly the completed = false case.  Emitted BEFORE runDeferred, which
    -- starts a whole new run and would otherwise nest this run's `ended`
    -- inside the next run's `started`.
    self:emitScriptEnded(not self.aborted)
    self:runDeferred()
    return
  end
  self.pending = req
  if req and req.kind == "text" and self.showTextFn then
    self.showTextFn(req.text, function()
      self:resume()
    end, req.stay, req.hold)
  elseif req and req.kind == "wait" then
    self.waitLeft = req.frames or 0
  elseif req and req.kind == "waitbutton" then
    -- Only yielded when the hook exists (see the opcode), so no fallback arm:
    -- an arm that resumed immediately would put the bug straight back.
    self.waitButtonFn(function() self:resume() end)
  elseif req and req.kind == "yesorno" and self.yesornoFn then
    self.yesornoFn(function(yes)
      self:resume(yes and true or false)
    end)
  elseif req and req.kind == "move" and self.applyMovementFn then
    self.applyMovementFn(req.object, req.bytes, function()
      self:resume()
    end)
  elseif req and req.kind == "waitsfx" then
    self.waitSfx = true
    self.waitSfxLeft = 180 -- safety cap (~3s) if a source never ends
  elseif req and req.kind == "battle" then
    if self.startBattleFn then
      self.startBattleFn(req.trainer, req.wild, function(outcome)
        self:resume(outcome)
      end)
    else
      self:resume("win")
    end
  elseif req and req.kind == "catchtutorial" then
    -- farcall StartBattle: the script is parked here until the demo battle is
    -- over, because StopAutoInput and the map reload are on the other side of
    -- it.  Only reached when the hook exists, so there is no fallback arm.
    self.catchTutorialFn(req.wild, req.battleType, function()
      self:resume()
    end)
  elseif req and req.kind == "mart" then
    if self.openMartFn then
      self.openMartFn(req.martType, req.martId, function() self:resume() end)
    else
      self:resume()
    end
  elseif req and req.kind == "approach" then
    self.trainerApproachFn(function() self:resume() end)
  elseif req and req.kind == "menu" then
    -- Script_verticalmenu / Script__2dmenu.  Same shape as yesorno: the
    -- coroutine is parked on the yield and the menu's own callback resumes it
    -- with the 1-based index (0 or nil for B).  With no hook the script takes
    -- the cancel arm rather than hanging on a resume nobody will call.
    if self.openMenuFn then
      self.openMenuFn(req.header, req.style, function(choice)
        self:resume(choice)
      end)
    else
      self:resume(0)
    end
  elseif req and req.kind == "pokemail" then
    -- CheckPokeMail's SelectMonFromParty half.  Only reached when the hook
    -- exists (the opcode answers REFUSED outright otherwise), so there is no
    -- fallback arm here.
    self.checkPokeMailFn(req.mail, function(answer) self:resume(answer) end)
  elseif req and req.kind == "trade" then
    self.npcTradeFn(req.trade, function() self:resume() end)
  elseif req and req.kind == "elevator" then
    self.elevatorFn(req.floors, function(rode) self:resume(rode) end)
  elseif req and req.kind == "phonecall" then
    self.phoneCallFn(req.caller, function() self:resume() end)
  elseif req and req.kind == "halloffame" then
    self.hallOfFameFn(function() self:resume() end)
  elseif req and req.kind == "credits" then
    self.creditsFn(function() self:resume() end)
  end
end

function Vm:update()
  if not self.busy then return end
  if self.waitLeft and self.waitLeft > 0 then
    self.waitLeft = self.waitLeft - 1
    if self.waitLeft <= 0 then
      self.waitLeft = nil
      self:resume()
    end
    return
  end
  if self.waitSfx then
    local done = true
    if self.waitSfxFn then
      done = self.waitSfxFn()
    end
    if self.waitSfxLeft then
      self.waitSfxLeft = self.waitSfxLeft - 1
      if self.waitSfxLeft <= 0 then done = true end
    end
    if done then
      self.waitSfx = nil
      self.waitSfxLeft = nil
      self:resume()
    end
  end
end

return Vm
