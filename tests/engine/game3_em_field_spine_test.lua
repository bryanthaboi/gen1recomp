package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")
local before = GameVersion.get()
local MB = require("src.core.game3.mb")

local FR = { version = "firered" }
local EM = { version = "emerald" }

local FieldModules = require("src.core.game3.field_modules")
for name in pairs(FieldModules.NAMES) do
  check(FieldModules.enabled(name, FR), "FireRed keeps field module " .. name)
  if name == "mapNamePopup" then
    check(FieldModules.enabled(name, EM), "Emerald runs the themed map name popup")
  elseif name == "unionPlaza" then
    check(FieldModules.enabled(name, EM), "Emerald shares the 40-player union plaza")
  else
    check(not FieldModules.enabled(name, EM), "Emerald does not run FireRed field module " .. name)
  end
end
check(not pcall(FieldModules.enabled, "noSuchModule", FR), "an unknown field module name raises")

local Sem = require("src.core.game3.field_semantics")
eq(Sem.var(FR, "happinessSteps"), 0x4021, "FR happiness step var unchanged")
eq(Sem.var(FR, "massageSteps"), 0x4025, "FR massage var unchanged")
eq(Sem.var(FR, "poisonSteps"), 0x4022, "FR VAR_POISON_STEP_COUNTER")
eq(Sem.var(FR, "repelSteps"), 0x4020, "FR repel var unchanged")
eq(Sem.flag(FR, "flashActive"), 0x806, "FR flash flag unchanged")
eq(Sem.var(EM, "happinessSteps"), 0x402A, "EM VAR_FRIENDSHIP_STEP_COUNTER")
eq(Sem.var(EM, "poisonSteps"), 0x402B, "EM VAR_POISON_STEP_COUNTER")
eq(Sem.var(EM, "repelSteps"), 0x4021, "EM VAR_REPEL_STEP_COUNT")
eq(Sem.var(EM, "massageSteps"), nil, "EM has no massage counter")
eq(Sem.flag(EM, "flashActive"), 0x888, "EM FLAG_SYS_USE_FLASH")

local Dataset = require("src.core.game3.dataset")
local kind, env = Dataset.kindOfMapType(3)
eq(kind, "route", "MAP_TYPE_ROUTE is a route")
kind = Dataset.kindOfMapType(8)
eq(kind, "indoor", "MAP_TYPE_INDOOR is indoor")
kind = Dataset.kindOfMapType(1)
eq(kind, "town", "MAP_TYPE_TOWN is a town")
kind, env = Dataset.kindOfMapType(6)
eq(kind .. "/" .. env, "route/ROUTE", "MAP_TYPE_OCEAN_ROUTE is a route")

local def = {
  connections = {
    { dir = "south", map = "EM_ROUTE126", offset = 0 },
    { dir = "dive", map = "EM_UNDERWATER_ROUTE124", offset = 0 },
  },
}
Dataset.bindUnderwater(def)
eq(def.dive and def.dive.map, "EM_UNDERWATER_ROUTE124", "dive connection exposed as def.dive")
eq(def.emerge, nil, "no emerge row, no def.emerge")
local Connections = require("src.core.game3.connections")
local rows = Connections.each(def)
eq(#rows, 1, "dive rows stay out of the cardinal stitch")
eq(rows[1].dir, "south", "cardinal row kept")

local TilesetAnim = require("src.core.game3.tileset_anim")
local function frame(row, timer) return TilesetAnim.rseFrame(row, timer) end
eq(frame({ period = 16, frames = 4 }, 32), 2, "mod: (timer / period) % frames")
eq(frame({ period = 16, frames = 4 }, 80), 1, "mod wraps")
eq(frame({ period = 8, fn = "slot", slot = 3, frames = 8 }, 8), 6, "slot: (t - slot) & 0xFFFF % frames")
eq(frame({ period = 8, fn = "mauville", slot = 0, frames = 13, framesA = 5, framesB = 8 }, 16), 2,
  "mauville: first table while d < framesA")
eq(frame({ period = 8, fn = "mauville", slot = 0, frames = 13, framesA = 5, framesB = 8 }, 7 * 8), 5 + 7 % 8,
  "mauville: second table after framesA")
eq(frame({ period = 8, fn = "mauville", slot = 1, frames = 13, framesA = 5, framesB = 8 }, 0), 5 + 65535 % 8,
  "mauville: u16 underflow before the slot")

local manifest = [[return { family = "rse",
  counters = { primary = { init = "InitTilesetAnim_General", max = 256 },
    secondary = { init = "InitTilesetAnim_Mauville", max = 256, start = "primary" } },
  banks = {} }]]
local fake = { read = function(_, rel)
  if rel:find("general__mauville/anim_manifest.lua", 1, true) then return manifest end
  return nil
end }
TilesetAnim.install(fake)
check(TilesetAnim.enterMap("general__mauville", false), "rse manifest starts the RSE counters")
local st = TilesetAnim._rse
eq(st.primaryMax, 256, "primary max from InitTilesetAnim_General")
for _ = 1, 300 do TilesetAnim.stepRse() end
eq(st.primary, 300 % 256, "primary counter wraps at its max")
st.primary = 40
TilesetAnim.enterMap("general__mauville", true)
eq(st.primary, 40, "a connection crossing keeps the primary counter")
eq(st.secondary, 40, "Mauville secondary starts at the primary counter")
check(not TilesetAnim.enterMap("general__petalburg", false), "no manifest, no RSE counters")
TilesetAnim.invalidate()
eq(TilesetAnim._rse, nil, "invalidate drops the RSE counters")

local I = require("src.core.game3.scripting.interaction_scripts")
I.install(nil)
eq(I.scriptFor(0x83, "down"), "EventScript_PC", "FR PC row unchanged")
local bookshelf, tv = MB.require("BOOKSHELF"), MB.require("TELEVISION")
local secretPc = MB.require("SECRET_BASE_PC")
I.install({ behaviors = {}, interactions = {
  [bookshelf] = { script = "g3:1" },
  [tv] = { script = "g3:2", facing = "up" },
  [secretPc] = { script = "g3:3", sameElevation = true },
}, tileBits = { [MB.require("OCEAN_WATER")] = 2 } })
eq(I.scriptFor(bookshelf, "left"), "g3:1", "rse bookshelf row")
eq(I.scriptFor(tv, "left"), nil, "rse TV needs facing north")
eq(I.scriptFor(tv, "up"), "g3:2", "rse TV facing north")
eq(I.scriptFor(secretPc, "up", false), nil, "secret base PC needs the same elevation")
eq(I.scriptFor(secretPc, "up", true), "g3:3", "secret base PC at the same elevation")
eq(I.scriptFor(0x83, "down"), nil, "FR literal rows are not used on RSE")
local CollRse = require("src.core.game3.scripting.collision_rse")
check(CollRse._tileBits ~= nil, "install hands tile bits to collision_rse")
I.install(nil)
eq(CollRse._tileBits ~= nil, true, "a pack without tileBits leaves them alone")

local Collision = require("src.core.game3.collision")
local same = true
for beh = 0, 0xFF do
  local want = (beh >= 0x60 and beh <= 0x6F) or beh == 0x71
  if Collision.isWarpMetatileBehavior(beh) ~= want then same = false end
end
check(same, "FR warp behaviors 0x00-0xFF unchanged")
for _, name in ipairs({ "WATER_DOOR", "DEEP_SOUTH_WARP", "LAVARIDGE_GYM_B1F_WARP", "LAVARIDGE_GYM_1F_WARP",
    "AQUA_HIDEOUT_WARP", "MT_PYRE_HOLE", "MOSSDEEP_GYM_WARP", "BRIDGE_OVER_OCEAN" }) do
  check(Collision.isWarpMetatileBehavior(MB.require(name)), "RSE warp behavior " .. name)
  check(Collision.isStepWarpBehavior(MB.require(name)), "RSE step warp " .. name)
end
eq(Collision.arrowWarpDir(MB.require("SHOAL_CAVE_ENTRANCE")), "down", "shoal cave entrance is a south arrow")
eq(Collision.arrowWarpDir(MB.require("STAIRS_OUTSIDE_ABANDONED_SHIP")), "up", "abandoned ship stairs are a north arrow")
eq(Collision.arrivalFacing(MB.require("DEEP_SOUTH_WARP")), "up", "deep south warp arrival faces north")
check(Collision.isWarpPad(MB.require("AQUA_HIDEOUT_WARP")), "aqua hideout pads teleport")
check(not Collision.isWarpMetatileBehavior(MB.require("TALL_GRASS")), "grass is not a warp")

local Space = require("src.core.game3.scripting.space")
local bundle = { scripts = { ["g3:08000001"] = { { op = "end" } }, ["std:4"] = { { op = "end" } } } }
local labelsCache = { read = function(_, rel)
  if rel == "gba/scripts/labels.lua" then
    return 'return { Route101_EventScript_StartBirchRescue = "g3:08000001", Missing_Script = "g3:0badbad0" }'
  end
end }
Space.installLabels(bundle, labelsCache, "gba")
local prev = Space.bundle
Space.bundle = bundle
eq(Space.scriptKey("Route101_EventScript_StartBirchRescue"), "g3:08000001", "label resolves to its g3 key")
eq(Space.scriptKey("std:4"), "std:4", "a direct key stays itself")
eq(Space.scriptKey("Missing_Script"), nil, "a label with no script is nil")
check(bundle.scripts.Route101_EventScript_StartBirchRescue == bundle.scripts["g3:08000001"],
  "scripts[label] reads through labels.lua")
Space.bundle = prev
local noLabels = { scripts = {} }
eq(Space.installLabels(noLabels, { read = function() return nil end }, "gba"), nil, "no labels.lua, no metatable")
eq(getmetatable(noLabels.scripts), nil, "FR scripts table stays plain")

eq(table.concat(Space.tempFieldEventFlags(FR), ","), "2055,2114", "FR temp field flags unchanged")
eq(#Space.tempFieldEventFlags(EM), 5, "EM ClearTempFieldEventData clears five flags")

local Trainers = require("src.core.game3.scripting.trainers")
local pack = { trainers = {
  [1] = { name = "A", dialogs = {} },
  [2] = { name = "B", dialogs = { intro = "kept" }, scriptKey = "own" },
} }
local dcache = { read = function(_, rel)
  if rel == Trainers.DIALOGS_REL then
    return 'return { [1] = { scriptKey = "g3:1", introTextKey = "g3:2", dialogs = { intro = "hi" } },'
      .. ' [2] = { scriptKey = "g3:9", dialogs = { intro = "no" } } }'
  end
end }
eq(Trainers.mergeDialogs(pack, dcache), 1, "one trainer took dialogs from dialogs.lua")
eq(pack.trainers[1].dialogs.intro, "hi", "empty dialogs filled")
eq(pack.trainers[1].scriptKey, "g3:1", "script key filled")
eq(pack.trainers[2].dialogs.intro, "kept", "inline dialogs win")
eq(pack.trainers[2].scriptKey, "own", "inline script key wins")
eq(Trainers.mergeDialogs(pack, { read = function() return nil end }), 0, "no dialogs.lua, no change")

local HealLocations = require("src.core.game3.heal_locations")
GameVersion.set("emerald")
HealLocations.install({ model = "heal_row", whiteout = {
  [1] = { map = "EM_LITTLEROOT_TOWN_BRENDANS_HOUSE_2F", x = 4, y = 2 },
} })
eq(HealLocations.model(), "heal_row", "heal row model")
eq(HealLocations.get(1).healerLocalId, nil, "no healer on the RSE heal row")
eq(HealLocations.get(2), nil, "no FireRed source fallback on Emerald")
local s = { version = "emerald", healMap = "EM_INSIDE_OF_TRUCK" }
HealLocations.normalizeSession(s)
eq(s.healMap, "EM_INSIDE_OF_TRUCK", "normalizeSession leaves Emerald sessions alone")
GameVersion.set("firered")
HealLocations.install({ whiteout = { [2] = { map = "FR_X", x = 1, y = 2, healerLocalId = 1 } } })
eq(HealLocations.get(3).map, HealLocations.BY_ID[3].map, "FireRed keeps the source fallback")
local fs = { version = "firered", healMap = "FR_PLAYERS_HOUSE_2F" }
HealLocations.normalizeSession(fs)
eq(fs.healMap, "FR_PLAYERS_HOUSE_1F", "FireRed bedroom heal map still migrates to Mom")
HealLocations.invalidate()

local LayoutNative = require("src.core.game3.layout_native")
local bigCells = {}
for i = 1, 16 do bigCells[i] = { mid = 1, coll = 0, elev = 3 } end
local big = LayoutNative.fromDecoded({ width = 4, height = 4, cells = bigCells }, "EM_TEST", "p")
local small = LayoutNative.fromDecoded({ width = 2, height = 1,
  cells = { { mid = 7, coll = 0, elev = 3 }, { mid = 8, coll = 1, elev = 3 } } }, "EM_SUB", "p")
eq(big:stamp(small, 1, 2), 2, "stamp copies every sub-layout cell")
eq(big:midAt(1, 2) .. "," .. big:midAt(2, 2), "7,8", "stamped mids land at the offset")
eq(big:collAt(2, 2), 1, "stamped collision kept")
eq(big:setMetatiles({ { x = 0, y = 0, mid = 9 } }), 1, "bulk setMetatiles")
eq(big:midAt(0, 0), 9, "setMetatiles writes the mid")
eq(pcall(LayoutNative.fromDecoded, { width = 1, height = 1, cells = { { mid = 1 } } }, "EM_NOPAIR"), false,
  "a layout with no tileset pair raises")
local holey = LayoutNative.fromDecoded({ width = 2, height = 1, cells = { { mid = 1, coll = 0, elev = 3 } } }, "EM_HOLE", "p")
eq(pcall(holey.midAt, holey, 1, 0), false, "midAt raises on a missing in-bounds cell")
eq(pcall(holey.cellAt, holey, 1, 0), false, "cellAt raises on a missing in-bounds cell")
local borderless = LayoutNative.fromDecoded({ width = 1, height = 1, cells = { { mid = 1 } },
  borderWidth = 2, borderHeight = 2, borderMids = { 3 } }, "EM_BORDER", "p")
eq(pcall(borderless.midAt, borderless, -1, -1), false, "midAt raises on a missing border metatile")
eq(pcall(big.applyOverride, big, 0, 0, "abc", 0, 0), false, "applyOverride raises on a non-number metatile")
eq(pcall(big.setMetatiles, big, { { x = 1, y = 0, mid = "abc" } }), false, "setMetatiles raises on a non-number metatile")
eq(pcall(big.stamp, big, { width = 1, height = 1, cells = { { coll = 0 } } }, 0, 0), false,
  "stamp raises on a cell with no metatile")

GameVersion.set(before)
T.finish()
