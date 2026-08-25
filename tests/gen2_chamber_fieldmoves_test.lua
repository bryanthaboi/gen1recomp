-- The two Ruins of Alph walls the FIELD MOVES open, at their production seams:
-- ../pokecrystal/engine/events/overworld.asm:280-291 FlashFunction.CheckUseFlash
-- (ZEPHYRBADGE first, SpecialAerodactylChamber second, the darkness test last)
-- and :808-813 EscapeRopeOrDig's `.escaperope` arm.
--   luajit tests/gen2_chamber_fieldmoves_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 chamber field moves")
local check, eq = S.check, S.eq

love = require("tests.love_stub")

local Events = require("src.world.gen2.Events")
local FieldMoves = require("src.world.gen2.FieldMoves")
local UnownWords = require("src.world.gen2.UnownWords")

local function ctxFor(mapId, badges, dark)
  local events = Events.new()
  return {
    events = events,
    save = { player = { badges = badges } },
    dark = dark or false,
    openAerodactylWall = function()
      return UnownWords.aerodactylChamber(events, mapId)
    end,
  }, events
end

local AERO = UnownWords.CHAMBER_MAPS.AERODACTYL

-- :281-283, the badge gate ahead of the special.
local ctx, events = ctxFor(AERO, {}, false)
local refused = FieldMoves.fromMenu("FLASH", ctx)
eq(refused.ok, false, "no ZEPHYRBADGE: FLASH is refused in the chamber")
eq(refused.badge, "ZEPHYR", "and it is the badge that refused it")
check(not UnownWords.wallOpened(events, "AERODACTYL"),
  "a badgeless press must not reach SpecialAerodactylChamber")

-- :284-287, the special's carry is a second way into `.useflash`.
ctx, events = ctxFor(AERO, { ZEPHYR = true }, false)
local used = FieldMoves.fromMenu("FLASH", ctx)
eq(used.ok, true, "with the badge FLASH runs in a chamber that is not dark")
eq(used.action, "flash", "and it queues the flash")
check(UnownWords.wallOpened(events, "AERODACTYL"),
  "and the wall-opened flag is set")

-- :288-290, any other lit map still refuses.
ctx, events = ctxFor("RUINS_OF_ALPH_OUTSIDE", { ZEPHYR = true }, false)
eq(FieldMoves.fromMenu("FLASH", ctx).ok, false, "a lit route still refuses")
check(not UnownWords.wallOpened(events, "AERODACTYL"),
  "and opens nothing")

-- A dark cave is the ordinary arm, with no chamber anywhere near it.
ctx = ctxFor("SLOWPOKE_WELL_B1F", { ZEPHYR = true }, true)
eq(FieldMoves.fromMenu("FLASH", ctx).ok, true, "a dark cave is still lit")

-- A cache with no chamber hook at all (Gold) must behave exactly as before.
eq(FieldMoves.fromMenu("FLASH", {
  save = { player = { badges = { ZEPHYR = true } } }, dark = false }).ok, false,
  "with no openAerodactylWall on the ctx, a lit map refuses")

-- ../pokecrystal/engine/events/unown_walls.asm:81, the escape rope's own arm.
local ropeEvents = Events.new()
eq(UnownWords.kabutoChamber(ropeEvents, "RUINS_OF_ALPH_OUTSIDE"), false,
  "the rope opens nothing outside a chamber")
check(not UnownWords.wallOpened(ropeEvents, "KABUTO"), "flag still clear")
eq(UnownWords.kabutoChamber(ropeEvents, UnownWords.CHAMBER_MAPS.KABUTO), true,
  "and opens the Kabuto wall inside it")
check(UnownWords.wallOpened(ropeEvents, "KABUTO"), "flag set")

S.finish()
