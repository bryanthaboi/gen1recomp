package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local home = os.getenv("HOME") or ""
local roots = {}
local identity = os.getenv("POKEPORT_IDENTITY")
if identity and identity ~= "" then
  roots[#roots + 1] = home .. "/Library/Application Support/LOVE/" .. identity .. "/emerald/"
  roots[#roots + 1] = home .. "/.local/share/love/" .. identity .. "/emerald/"
end
local ROOT
for _, r in ipairs(roots) do
  local f = io.open(r .. "data/generated/gba/pokemon/hoenn.lua", "rb")
  if f then
    f:close()
    ROOT = r
    break
  end
end
if not ROOT then
  local dir = require("tests.game3_cache").gameDir("emerald", "pokemon/hoenn.lua")
  ROOT = dir and dir .. "/"
end

local fs = {}
function fs:read(rel)
  if not ROOT then return nil end
  local f = io.open(ROOT .. rel, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end
function fs:exists(rel) return self:read(rel) ~= nil end
package.loaded["src.core.game3.dataset"] = {
  cache = function() return fs end,
  mountExtractRoots = function() end,
}

local GameVersion = require("src.core.GameVersion")
local before = GameVersion.get()
GameVersion.set("emerald")

local store = { flags = {}, vars = {} }
local session = { version = "emerald", gender = 0, party = {}, flags = {}, vars = {}, store = store,
  playtime = { hours = 12, minutes = 34, seconds = 56 }, dex = { seen = {}, caught = {}, owned = {} } }
package.loaded["src.core.game3.runtime"] = { getSession = function() return session end }
package.loaded["src.core.game3.scripting.space"] = { store = store }

local C = require("src.core.game3.constants").of("emerald")
local Rse = require("src.core.game3.rse.init")
local FieldRse = require("src.core.game3.scripting.natives_field_rse")
local H = FieldRse.BY_NAME

local specials = {}
local ctx = {
  getVar = function(_, id) return specials[id] or 0 end,
  setVar = function(_, id, v) specials[id] = v end,
}

print("[test] Lilycove fan club (pokeemerald/src/field_specials.c:3984)")
H.UpdateTrainerFanClubGameClear(ctx)
eq(Rse.var("VAR_FANCLUB_FAN_COUNTER"), 0x80 + 0x100 + 0x400 + 0x2000, "GameClear: got-first-fans bit + members 1/3/6")
eq(Rse.var("VAR_FANCLUB_LOSE_FAN_TIMER"), 12, "lose-fan timer starts at the play-time hours")
eq(Rse.var("VAR_LILYCOVE_FAN_CLUB_STATE"), 1, "VAR_LILYCOVE_FAN_CLUB_STATE = 1")
Rse.setFlag("FLAG_HIDE_FANCLUB_BOY", true)
H.UpdateTrainerFanClubGameClear(ctx)
check(Rse.flag("FLAG_HIDE_FANCLUB_BOY"), "a second GameClear does not reset the club")
eq(select(2, H.GetNumFansOfPlayerInTrainerFanClub(ctx)), 3, "three initial fans")

specials[0x8004] = 0
local _, counter = H.Script_TryGainNewFanFromCounter(ctx)
eq(counter, 0, "no counter while the club state is not 2")
Rse.setVar("VAR_LILYCOVE_FAN_CLUB_STATE", 2)
for _i = 1, 9 do _, counter = H.Script_TryGainNewFanFromCounter(ctx) end
eq(counter, 18, "defeating Drake adds 2 per call")
_, counter = H.Script_TryGainNewFanFromCounter(ctx)
eq(counter, 20, "counter pins at 20 once the player has 3 fans")
eq(FieldRse.numFans(), 3, "no fan gained at 3 fans")
Rse.setVar("VAR_FANCLUB_FAN_COUNTER", 0x80 + 0x100 + 19)
_, counter = H.Script_TryGainNewFanFromCounter(ctx)
eq(counter, 0, "gaining a fan clears the counter")
eq(FieldRse.numFans(), 2, "one fan gained under 3 fans")

print("[test] SetChampionSaveWarp (pokeemerald/src/save_location.c:136)")
session.specialSaveWarpFlags = 1
H.SetChampionSaveWarp(ctx)
eq(session.specialSaveWarpFlags, 0x81, "CHAMPION_SAVEWARP ors in bit 7")

print("[test] Birch dex rating text (pokeemerald/src/birch_pc.c:24)")
eq(FieldRse.pokedexRatingText(0), "gBirchDexRatingText_LessThan10", "0 -> LessThan10")
eq(FieldRse.pokedexRatingText(17), "gBirchDexRatingText_LessThan20", "17 -> LessThan20")
eq(FieldRse.pokedexRatingText(199), "gBirchDexRatingText_LessThan200", "199 -> LessThan200")

print("[test] PCTurnOnEffect_SetMetatile (pokeemerald/src/field_specials.c:1046)")
do
  local PcRse = require("src.core.game3.scripting.natives_pc_rse")
  local Field = require("src.core.game3.field")
  local realSet = Field.setMetatile
  local realMap = package.loaded["src.core.game3.map"]
  local realTs = package.loaded["src.core.game3.tileset_native"]
  package.loaded["src.core.game3.map"] = { currentDef = function() return { pair = "emerald_test" } end }
  package.loaded["src.core.game3.tileset_native"] = {
    ready = function() return true end,
    get = function() return { midToSlot = {} } end,
  }
  local wrote
  Field.setMetatile = function(_, _, mid, impassable) wrote = { mid = mid, impassable = impassable } end
  specials[0x8004] = 0
  PcRse.setPcMetatile(ctx, true)
  Field.setMetatile = realSet
  package.loaded["src.core.game3.map"] = realMap
  package.loaded["src.core.game3.tileset_native"] = realTs
  eq(wrote and wrote.mid, C:require("metatile_labels", "METATILE_Building_PC_On"),
    "PC on is written with no atlas check")
  eq(wrote and wrote.impassable, true, "PC on is written impassable")
end

if not ROOT then
  print("emerald_league_specials_test: cache checks skipped (set POKEPORT_IDENTITY to an identity with an Emerald cache)")
  GameVersion.set(before)
  T.finish()
  return
end

eq(FieldRse.pokedexRatingText(202), "gBirchDexRatingText_DexCompleted", "202 -> DexCompleted")
eq(FieldRse.pokedexRatingText(200), "gBirchDexRatingText_DexCompleted", "200 without Jirachi/Deoxys -> DexCompleted")

print("[test] ScriptGetPokedexInfo (pokeemerald/src/birch_pc.c:7)")
for _, n in ipairs({ "SPECIES_TREECKO", "SPECIES_ZIGZAGOON", "SPECIES_WINGULL" }) do
  local sp = C:require("species", n)
  session.dex.seen[sp] = true
  session.dex.caught[sp] = true
end
session.dex.seen[C:require("species", "SPECIES_BULBASAUR")] = true
specials[0x8004] = 0
H.ScriptGetPokedexInfo(ctx)
eq(specials[0x8005], 3, "Hoenn seen skips Bulbasaur")
eq(specials[0x8006], 3, "Hoenn caught")
specials[0x8004] = 1
H.ScriptGetPokedexInfo(ctx)
eq(specials[0x8005], 4, "National seen counts Bulbasaur")

print("[test] GameClear state (pokeemerald/src/post_battle_event_funcs.c:33)")
local PcRse = require("src.core.game3.scripting.natives_pc_rse")
session.specialSaveWarpFlags = 0
session.gameStats = {}
session.party = { { species = C:require("species", "SPECIES_BLAZIKEN"), level = 50 } }
PcRse.gameClearState(session)
eq(session.specialSaveWarpFlags, 1, "CONTINUE_GAME_WARP set")
eq(session.continueGameWarp and session.continueGameWarp.map, "EM_LITTLEROOT_TOWN_BRENDANS_HOUSE_2F",
  "continue warp goes to Brendan's bedroom")
eq(session.gameStats[1], 12 * 65536 + 34 * 256 + 56, "GAME_STAT_FIRST_HOF_PLAY_TIME packs h:m:s")
check(session.party[1].championRibbon == true, "party gets the CHAMPION RIBBON")
eq(session.gameStats[42], 1, "GAME_STAT_RECEIVED_RIBBONS incremented")
check(Rse.flag("FLAG_SYS_RIBBON_GET"), "FLAG_SYS_RIBBON_GET set")
session.gender = 1
session.gameStats[1] = 7
PcRse.gameClearState(session)
eq(session.continueGameWarp.map, "EM_LITTLEROOT_TOWN_MAYS_HOUSE_2F", "female continue warp goes to May's bedroom")
eq(session.gameStats[1], 7, "first HoF time is kept")
eq(session.gameStats[42], 1, "no ribbon stat when every mon already has it")

GameVersion.set(before)
T.finish()
