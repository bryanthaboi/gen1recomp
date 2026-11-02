package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Loader = require("src.mods.Loader")
local Unified = require("src.mods.UnifiedContent")
local FieldMoves = require("src.world.gen2.FieldMoves")
local Fixture = require("tests.fixtures.gen2_flypoints")

local BODY = [[local mod = ...
local c = mod.content
c.landmarks:register("LANDMARK_MOD_TOWN", { name = "MOD\nTOWN", index = 96, x = 60, y = 60 })
c.landmarks:register("LANDMARK_MOD_PEAK", { name = "MOD\nPEAK", index = 97, x = 70, y = 70 })
c.spawns:register("SPAWN_MOD_TOWN", { map = "MOD_TOWN", x = 5, y = 6 })
c.spawns:register("SPAWN_MOD_PEAK", { map = "MOD_PEAK", x = 2, y = 3 })
c.fly_points:register("SPAWN_MOD_TOWN", { landmark = "LANDMARK_MOD_TOWN", region = "johto", order = 3 })
c.fly_points:register("SPAWN_MOD_PEAK", { landmark = "LANDMARK_MOD_PEAK", region = "kanto", flag = 300 })
c.spawns:patch("SPAWN_VIOLET", { x = 30 })
assert(not pcall(function()
  c.fly_points:register("SPAWN_MOD_X", { landmark = "LANDMARK_MOD_TOWN", region = "hoenn" })
end))
assert(not pcall(function()
  c.fly_points:register("SPAWN_MOD_Y", { landmark = "LANDMARK_MOD_TOWN", region = "johto", flag = 10 })
end))
assert(not pcall(function()
  c.spawns:register("SPAWN_MOD_Z", { map = "MOD_TOWN", x = 300, y = 1 })
end))
]]

local KEEP = { SPAWN_NEW_BARK = true, SPAWN_VIOLET = true, SPAWN_INDIGO = true }

for _, version in ipairs({ "gold", "silver", "crystal" }) do
  for _, api in ipairs({ 2, 3 }) do
    T.sdk.captureRuntime()
    local files = {}
    local function add(id, body)
      files["mods/" .. id .. "/manifest.json"] = ('{"id":"%s","name":"%s",'
        .. '"version":"1.0.0","api":%d,"games":["all"],"entry":"main.lua"}')
        :format(id, id, api)
      files["mods/" .. id .. "/main.lua"] = body
    end
    add("a_good", BODY)
    add("b_failed", 'local mod = ...; mod.content.fly_points:register("SPAWN_VIOLET_X", '
      .. '{ landmark = "LANDMARK_VIOLET_CITY", region = "johto" }); error("rollback fixture")')
    local flypoints = {}
    for spawn, row in pairs(Fixture.rows(version)) do
      if KEEP[spawn] then flypoints[spawn] = row end
    end
    local violetFlag = flypoints.SPAWN_VIOLET.flag
    add("c_native_flags", ([[local mod = ...
local c = mod.content
c.fly_points:patch("SPAWN_VIOLET", { flag = %d })
assert(not pcall(function()
  c.fly_points:register("SPAWN_MOD_SHARE", { landmark = "LANDMARK_MOD_TOWN", region = "johto", flag = %d })
end), "a new row took Violet's flag")
assert(not pcall(function()
  c.fly_points:patch("SPAWN_NEW_BARK", { flag = %d })
end), "New Bark took Violet's flag")
]]):format(violetFlag, violetFlag, violetFlag))
    add("d_clash", 'local mod = ...; mod.content.fly_points:register("SPAWN_MOD_CLASH", '
      .. '{ landmark = "LANDMARK_MOD_PEAK", region = "kanto", flag = 300 })')
    local landmarks = {
      landmarks = {
        LANDMARK_NEW_BARK_TOWN = { id = "LANDMARK_NEW_BARK_TOWN", index = 1, name = "NEW BARK", x = 8, y = 8 },
        LANDMARK_VIOLET_CITY = { id = "LANDMARK_VIOLET_CITY", index = 5, name = "VIOLET", x = 9, y = 9 },
        LANDMARK_INDIGO_PLATEAU = { id = "LANDMARK_INDIGO_PLATEAU", index = 63, name = "INDIGO", x = 10, y = 10 },
      },
      spawns = {
        SPAWN_NEW_BARK = { id = "SPAWN_NEW_BARK", index = 14, map = "NEW_BARK_TOWN", x = 13, y = 6 },
        SPAWN_VIOLET = { id = "SPAWN_VIOLET", index = 16, map = "VIOLET_CITY", x = 31, y = 26 },
        SPAWN_INDIGO = { id = "SPAWN_INDIGO", index = 13, map = "ROUTE_23", x = 9, y = 6 },
      },
      flypoints = flypoints,
    }
    local maps = {}
    for _, id in ipairs({ "NEW_BARK_TOWN", "VIOLET_CITY", "ROUTE_23", "MOD_TOWN", "MOD_PEAK" }) do
      maps[id] = { id = id, width = 1, height = 1, blocks = { 1 } }
    end
    local data = { gen2Landmarks = landmarks, gen2Maps = maps }
    local loader = Loader.new({ fs = T.sdk.memfs(files), generation = 2, version = version, dev = true })
    loader:load(data)
    local label = version .. " API " .. api .. " "
    T.eq(loader.mods.a_good.failed, nil, label .. "fly point writes load")
    T.eq(loader.mods.b_failed.failed, true, label .. "rollback owner fails")
    T.eq(loader.mods.c_native_flags.failed, nil,
      label .. "a cart row keeps its own flag; no other row may take it")
    T.eq(loader.mods.d_clash.failed, true, label .. "a second mod claiming flag 300 fails to load")
    local clash = false
    for _, message in ipairs(loader.errors) do
      if tostring(message):find("flag collision: 300", 1, true) then clash = true end
    end
    T.eq(clash, true, label .. "the clash is reported as a flag collision")
    T.eq(flypoints.SPAWN_MOD_CLASH, nil, label .. "the clashing row is rolled back")
    T.eq(flypoints.SPAWN_MOD_SHARE, nil, label .. "the shared-flag row never lands")
    T.eq(flypoints.SPAWN_NEW_BARK.flag ~= violetFlag, true, label .. "New Bark keeps its flag")
    T.eq(data.gen2Landmarks, landmarks, label .. "retains mounted landmarks")
    T.eq(landmarks.flypoints, flypoints, label .. "merges onto the cache flypoints")
    T.eq(flypoints.SPAWN_VIOLET_X, nil, label .. "failed mod row rolled back")
    T.eq(landmarks.spawns.SPAWN_VIOLET.x, 30, label .. "spawns patch moves the landing")
    T.eq(landmarks.spawns.SPAWN_VIOLET.y, 26, label .. "spawns patch keeps the rest")
    T.eq(landmarks.spawns.SPAWN_MOD_TOWN and landmarks.spawns.SPAWN_MOD_TOWN.map, "MOD_TOWN",
      label .. "spawns register adds a row")
    T.eq(flypoints.SPAWN_MOD_TOWN and flypoints.SPAWN_MOD_TOWN.landmark, "LANDMARK_MOD_TOWN",
      label .. "fly_points register adds a row")

    FieldMoves.bindFlypoints(landmarks.flypoints, landmarks.spawns)
    local order = {}
    for _, row in ipairs(FieldMoves.FLYPOINTS) do order[#order + 1] = row.spawn end
    T.same(order, { "SPAWN_NEW_BARK", "SPAWN_VIOLET", "SPAWN_MOD_TOWN", "SPAWN_INDIGO", "SPAWN_MOD_PEAK" },
      label .. "mod rows sort into their region by order")
    T.eq(FieldMoves.KANTO_FLYPOINT, 4, label .. "Kanto split follows the regions")

    local new, violet, indigo = flypoints.SPAWN_NEW_BARK.flag, flypoints.SPAWN_VIOLET.flag,
      flypoints.SPAWN_INDIGO.flag
    local save = { engineFlags = { [new] = true, [violet] = true } }
    T.eq(#FieldMoves.flyPoints(save, landmarks, "johto"), 2, label .. "mod point hidden before a visit")
    FieldMoves.noteVisit(save, "VIOLET_CITY", landmarks.spawns)
    T.eq(save.visitedSpawns, nil, label .. "a cart flypoint is left to its own flag")
    FieldMoves.noteVisit(save, "MOD_TOWN", landmarks.spawns)
    local johto = FieldMoves.flyPoints(save, landmarks, "johto")
    T.eq(#johto, 3, label .. "entering the spawn map marks a flag-less point visited")
    T.eq(johto[3] and johto[3].spawn, "SPAWN_MOD_TOWN", label .. "listed after Violet")
    T.eq(johto[3] and johto[3].index, 96, label .. "with its registered landmark")

    save.engineFlags[300] = true
    local _, shown = FieldMoves.flyPoints(save, landmarks, "kanto")
    T.eq(shown, "johto", label .. "a Kanto mod point waits for SPAWN_INDIGO")
    save.engineFlags[indigo] = true
    local kanto
    kanto, shown = FieldMoves.flyPoints(save, landmarks, "kanto")
    T.eq(shown, "kanto", label .. "Kanto opens once Indigo is visited")
    T.eq(#kanto, 2, label .. "and lists the flagged mod point")
    FieldMoves.noteVisit(save, "MOD_PEAK", landmarks.spawns)
    T.eq(save.visitedSpawns.SPAWN_MOD_PEAK, nil, label .. "a flagged point is never marked on entry")

    landmarks.spawns.SPAWN_MOD_TOWN = nil
    FieldMoves.bindFlypoints(landmarks.flypoints, landmarks.spawns)
    T.eq(#FieldMoves.FLYPOINTS, 4, label .. "a point whose spawn is gone is dropped")
    FieldMoves.bindFlypoints(nil)
    T.sdk.restoreRuntime()
  end
end
for _, version in ipairs({ "red", "firered" }) do
  local gen = version == "red" and 1 or 3
  T.eq(Unified.supports("fly_points", gen, version), false, version .. " has no fly_points surface")
  T.eq(Unified.supports("spawns", gen, version), false, version .. " has no spawns surface")
end
T.finish("Gen 2 fly points registry")
