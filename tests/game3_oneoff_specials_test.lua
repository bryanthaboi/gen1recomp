-- Tests for Gen 3 one-off script specials:
-- 1. Field_AskSaveTheGame (0x5D)
-- 2. SetWalkingIntoSignVars (0x170)
-- 3. LoadPlayerBag (0x14B)
-- 4. StickerManGetBragFlags (0x168)
-- 5. UpdateTrainerCardPhotoIcons (0x167)
-- 6. SeafoamIslandsB4F_CurrentDumpsPlayerOnLand (0x15C)

local Std = require("src.core.game3.scripting.stdscripts")
local Natives = require("src.core.game3.scripting.natives")
local Flags = require("src.core.game3.scripting.flags")
local Schema = require("src.core.game3.save_schema_firered")
local Link = require("src.core.game3.link.init")

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

print("=== 1. Field_AskSaveTheGame (0x5D) ===")
do
  local session = Schema.newGame({ name = "RED" })
  local rt = { getSession = function() return session end, game = function() return {} end }
  package.loaded["src.core.game3.runtime"] = rt

  local ctx = {
    flags = session.flags,
    vars = session.vars,
    stringVars = session.stringVars,
    specialVars = session.specialVars,
  }

  local mockAdapters = {}
  -- Mock SaveMenu
  local SaveMenu = require("src.ui.game3.save_menu")
  SaveMenu.show = function(opts)
    SaveMenu._phase = "saved"
    opts.onClose()
  end

  local yielded = Natives.special(ctx, Std.SPECIAL.Field_AskSaveTheGame, mockAdapters)
  checkEq(yielded, false, "Field_AskSaveTheGame completes")
  checkEq(Flags.getVar(session, ctx, 0x800D), 1, "Field_AskSaveTheGame sets VAR_RESULT = 1 on save")

  -- Cancel save test
  SaveMenu.show = function(opts)
    SaveMenu._phase = "cancelled"
    opts.onClose()
  end
  Natives.special(ctx, Std.SPECIAL.Field_AskSaveTheGame, mockAdapters)
  checkEq(Flags.getVar(session, ctx, 0x800D), 0, "Field_AskSaveTheGame sets VAR_RESULT = 0 on cancel")
end

print("=== 2. SetWalkingIntoSignVars (0x170) ===")
do
  local session = Schema.newGame({ name = "RED" })
  package.loaded["src.core.game3.runtime"] = { getSession = function() return session end }
  local ctx = {
    session = session,
    flags = session.flags,
    vars = session.vars,
    stringVars = session.stringVars,
    specialVars = session.specialVars,
  }

  Natives.special(ctx, Std.SPECIAL.SetWalkingIntoSignVars)
  checkEq(ctx.walkAwayFromSignInhibitTimer, 6, "ctx.walkAwayFromSignInhibitTimer set to 6")
  checkEq(ctx.msgBoxIsCancelable, true, "ctx.msgBoxIsCancelable is true")
  checkEq(ctx.canWalkAway, true, "ctx.canWalkAway is true")
  checkEq(session.walkAwayFromSignInhibitTimer, 6, "session.walkAwayFromSignInhibitTimer set to 6")
  checkEq(session.msgBoxIsCancelable, true, "session.msgBoxIsCancelable is true")
end

print("=== 3. LoadPlayerBag (0x14B) ===")
do
  local session = Schema.newGame({ name = "RED" })
  session.bag = { pockets = { items = { { item = 13, qty = 5 } } } }
  local rt = { getSession = function() return session end }
  package.loaded["src.core.game3.runtime"] = rt

  local ctx = {
    flags = session.flags,
    vars = session.vars,
    stringVars = session.stringVars,
    specialVars = session.specialVars,
  }

  local yielded = Natives.special(ctx, Std.SPECIAL.LoadPlayerBag)
  checkEq(yielded, false, "LoadPlayerBag completes without yielding")
  check(Link._bagBackup ~= nil, "Link._bagBackup created")
  checkEq(Link._bagBackup.pockets.items[1].qty, 5, "Link._bagBackup has correct quantity")
end

print("=== 4. StickerManGetBragFlags (0x168) ===")
do
  local session = Schema.newGame({ name = "RED" })
  session.hofClears = 12
  session.eggsHatched = 70000 -- Exceeds 0xFFFF to test clamping
  session.linkBattleWins = 5

  local rt = { getSession = function() return session end }
  package.loaded["src.core.game3.runtime"] = rt

  local ctx = {
    flags = session.flags,
    vars = session.vars,
    stringVars = session.stringVars,
    specialVars = session.specialVars,
  }

  local yielded, result = Natives.special(ctx, Std.SPECIAL.StickerManGetBragFlags)
  checkEq(yielded, false, "StickerManGetBragFlags does not yield")
  checkEq(Flags.getVar(session, ctx, 0x8004), 12, "VAR_0x8004 has HOF clears (12)")
  checkEq(Flags.getVar(session, ctx, 0x8005), 65535, "VAR_0x8005 clamped to 0xFFFF (65535)")
  checkEq(Flags.getVar(session, ctx, 0x8006), 5, "VAR_0x8006 has link wins (5)")
  -- Bitmask: bit 0 (HOF>0) = 1, bit 1 (eggs>0) = 2, bit 2 (linkWins>0) = 4 -> 1+2+4 = 7
  checkEq(Flags.getVar(session, ctx, 0x8008), 7, "VAR_0x8008 has brag bitmask 7")
  checkEq(Flags.getVar(session, ctx, 0x800D), 7, "VAR_RESULT has brag bitmask 7")

  -- Test zero stats
  session.hofClears = 0
  session.eggsHatched = 0
  session.linkBattleWins = 0
  Natives.special(ctx, Std.SPECIAL.StickerManGetBragFlags)
  checkEq(Flags.getVar(session, ctx, 0x8008), 0, "VAR_0x8008 is 0 when all stats are 0")
end

print("=== 5. UpdateTrainerCardPhotoIcons (0x167) ===")
do
  local session = Schema.newGame({ name = "RED" })
  -- Party with 3 mons
  session.party = {
    { speciesId = 1 }, -- Bulbasaur
    { speciesId = 4 }, -- Charmander
    { speciesId = 7 }, -- Squirtle
  }

  local rt = { getSession = function() return session end }
  package.loaded["src.core.game3.runtime"] = rt

  local ctx = {
    flags = session.flags,
    vars = session.vars,
    stringVars = session.stringVars,
    specialVars = session.specialVars,
  }

  Flags.setVar(session, ctx, 0x8004, 2) -- Tint index 2

  Natives.special(ctx, Std.SPECIAL.UpdateTrainerCardPhotoIcons)

  -- Check slots 1..3
  checkEq(Flags.getVar(session, ctx, 0x4043), 1, "VAR_TRAINER_CARD_MON_ICON_1 is Bulbasaur (1)")
  checkEq(Flags.getVar(session, ctx, 0x4044), 4, "VAR_TRAINER_CARD_MON_ICON_2 is Charmander (4)")
  checkEq(Flags.getVar(session, ctx, 0x4045), 7, "VAR_TRAINER_CARD_MON_ICON_3 is Squirtle (7)")

  -- Check empty slots 4..6 are padded with 0
  checkEq(Flags.getVar(session, ctx, 0x4046), 0, "VAR_TRAINER_CARD_MON_ICON_4 is empty (0)")
  checkEq(Flags.getVar(session, ctx, 0x4047), 0, "VAR_TRAINER_CARD_MON_ICON_5 is empty (0)")
  checkEq(Flags.getVar(session, ctx, 0x4048), 0, "VAR_TRAINER_CARD_MON_ICON_6 is empty (0)")

  -- Check tint index
  checkEq(Flags.getVar(session, ctx, 0x4042), 2, "VAR_TRAINER_CARD_MON_ICON_TINT_IDX is 2")
end

print("=== 6. SeafoamIslandsB4F_CurrentDumpsPlayerOnLand (0x15C) ===")
do
  local session = Schema.newGame({ name = "RED" })
  session.surfing = true
  session.player = { surfing = true, state = "surf", facing = "left" }
  session.facing = "left"

  local rt = {
    getSession = function() return session end,
    player = { surfing = true, state = "surf", facing = "left" },
  }
  package.loaded["src.core.game3.runtime"] = rt

  local ctx = {
    flags = session.flags,
    vars = session.vars,
    stringVars = session.stringVars,
    specialVars = session.specialVars,
  }

  Natives.special(ctx, Std.SPECIAL.SeafoamIslandsB4F_CurrentDumpsPlayerOnLand)

  checkEq(session.surfing, false, "session.surfing is false")
  checkEq(session.player.surfing, false, "session.player.surfing is false")
  checkEq(session.player.state, "walk", "session.player.state is 'walk'")
  checkEq(session.player.facing, "up", "session.player.facing is 'up' (North)")
  checkEq(rt.player.surfing, false, "rt.player.surfing is false")
  checkEq(rt.player.state, "walk", "rt.player.state is 'walk'")
  checkEq(rt.player.facing, "up", "rt.player.facing is 'up' (North)")
end

print(string.format("\nTotal: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
