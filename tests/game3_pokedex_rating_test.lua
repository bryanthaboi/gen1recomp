#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;" .. package.path

local Game3Cache = require("tests.game3_cache")
if not Game3Cache.bundle() then print("[skip] pokedex_rating: " .. tostring(Game3Cache.reason)) return end
local PokedexRating = require("src.core.game3.pokedex_rating")
local RomText = require("src.core.game3.rom_text")
local Dex = require("src.core.game3.dex")
local Std = require("src.core.game3.scripting.stdscripts")
local Natives = require("src.core.game3.scripting.natives")
local Flags = require("src.core.game3.scripting.flags")

local passed = 0
local failed = 0

local function check(cond, msg)
  if cond then
    passed = passed + 1
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function eq(a, b, msg)
  check(a == b, (msg or "equal") .. " (got " .. tostring(a) .. ", expected " .. tostring(b) .. ")")
end

print("=== 1. Rating Message Evaluation Tiers ===")
do
  local dex = Dex.new()

  local t0, c0 = PokedexRating.getRatingMessage(5, dex)
  eq(t0, PokedexRating.TEXT.LESS_THAN_10, "5 caught -> LessThan10")
  eq(c0, false, "5 caught isComplete = false")

  local t15, c15 = PokedexRating.getRatingMessage(15, dex)
  eq(t15, PokedexRating.TEXT.LESS_THAN_20, "15 caught -> LessThan20")

  local t25, c25 = PokedexRating.getRatingMessage(25, dex)
  eq(t25, PokedexRating.TEXT.LESS_THAN_30, "25 caught -> LessThan30")

  local t35, c35 = PokedexRating.getRatingMessage(35, dex)
  eq(t35, PokedexRating.TEXT.LESS_THAN_40, "35 caught -> LessThan40")

  local t45, c45 = PokedexRating.getRatingMessage(45, dex)
  eq(t45, PokedexRating.TEXT.LESS_THAN_50, "45 caught -> LessThan50")

  local t55, c55 = PokedexRating.getRatingMessage(55, dex)
  eq(t55, PokedexRating.TEXT.LESS_THAN_60, "55 caught -> LessThan60")

  local t65, c65 = PokedexRating.getRatingMessage(65, dex)
  eq(t65, PokedexRating.TEXT.LESS_THAN_70, "65 caught -> LessThan70")

  local t75, c75 = PokedexRating.getRatingMessage(75, dex)
  eq(t75, PokedexRating.TEXT.LESS_THAN_80, "75 caught -> LessThan80")

  local t85, c85 = PokedexRating.getRatingMessage(85, dex)
  eq(t85, PokedexRating.TEXT.LESS_THAN_90, "85 caught -> LessThan90")

  local t95, c95 = PokedexRating.getRatingMessage(95, dex)
  eq(t95, PokedexRating.TEXT.LESS_THAN_100, "95 caught -> LessThan100")

  local t105, c105 = PokedexRating.getRatingMessage(105, dex)
  eq(t105, PokedexRating.TEXT.LESS_THAN_110, "105 caught -> LessThan110")

  local t115, c115 = PokedexRating.getRatingMessage(115, dex)
  eq(t115, PokedexRating.TEXT.LESS_THAN_120, "115 caught -> LessThan120")

  local t125, c125 = PokedexRating.getRatingMessage(125, dex)
  eq(t125, PokedexRating.TEXT.LESS_THAN_130, "125 caught -> LessThan130")

  local t135, c135 = PokedexRating.getRatingMessage(135, dex)
  eq(t135, PokedexRating.TEXT.LESS_THAN_140, "135 caught -> LessThan140")

  local t145, c145 = PokedexRating.getRatingMessage(145, dex)
  eq(t145, PokedexRating.TEXT.LESS_THAN_150, "145 caught -> LessThan150")
end

print("=== 2. Mew Exception at 150 Caught ===")
do
  -- 150 caught without Mew: COMPLETE
  local dexWithoutMew = Dex.new()
  for sp = 1, 150 do Dex.setCaught(dexWithoutMew, sp) end
  local t150NoMew, c150NoMew = PokedexRating.getRatingMessage(150, dexWithoutMew)
  eq(t150NoMew, PokedexRating.TEXT.COMPLETE, "150 caught without Mew -> COMPLETE")
  eq(c150NoMew, true, "150 caught without Mew -> isComplete = true")

  -- 150 caught with Mew (e.g. 1..149 + Mew 151): LESS_THAN_150
  local dexWithMew = Dex.new()
  for sp = 1, 149 do Dex.setCaught(dexWithMew, sp) end
  Dex.setCaught(dexWithMew, 151) -- Mew
  local t150Mew, c150Mew = PokedexRating.getRatingMessage(150, dexWithMew)
  eq(t150Mew, PokedexRating.TEXT.LESS_THAN_150, "150 caught including Mew -> LessThan150")
  eq(c150Mew, false, "150 caught including Mew -> isComplete = false")

  -- 151 caught (all including Mew): COMPLETE
  local dexFull = Dex.new()
  for sp = 1, 151 do Dex.setCaught(dexFull, sp) end
  local t151, c151 = PokedexRating.getRatingMessage(151, dexFull)
  eq(t151, PokedexRating.TEXT.COMPLETE, "151 caught -> COMPLETE")
  eq(c151, true, "151 caught -> isComplete = true")
end

print("=== 3. Special 0xD5 Execution via Natives ===")
do
  local session = {
    dex = Dex.new(),
    flags = {},
    vars = {},
    stringVars = {},
    specialVars = {},
  }
  local ctx = {
    session = session,
    stringVars = session.stringVars,
    specialVars = session.specialVars,
  }
  local Space = require("src.core.game3.scripting.space")
  Space.store = session

  local openedMsg = nil
  local adapters = {
    openMessageStay = function(msg) openedMsg = msg end,
  }

  -- Case A: Count = 42
  Flags.setVar(session, ctx, 0x8004, 42)
  Natives.special(ctx, Std.SPECIAL.GetProfOaksRatingMessage, adapters)
  eq(openedMsg, RomText.box(PokedexRating.TEXT.LESS_THAN_50), "opened message for 42 caught")
  eq(Flags.getVar(session, ctx, 0x800D), 0, "VAR_RESULT = 0 for incomplete")

  -- Case B: Count = 150 without Mew
  for sp = 1, 150 do Dex.setCaught(session.dex, sp) end
  Flags.setVar(session, ctx, 0x8004, 150)
  Natives.special(ctx, Std.SPECIAL.GetProfOaksRatingMessage, adapters)
  eq(openedMsg, RomText.box(PokedexRating.TEXT.COMPLETE), "opened complete message for 150 without Mew")
  eq(Flags.getVar(session, ctx, 0x800D), 1, "VAR_RESULT = 1 for complete")
end

print(string.format("\nTotal: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
