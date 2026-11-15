package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.modkit")
local Schemas = require("src.mods.Schemas")
local BattleState = require("src.ui.gen2.BattleState")

local function rows(n)
  local out = {}
  for i = 1, n do out[i] = { { 255, 255, 255 }, { 120, 120, 120 }, { 60, 60, 60 }, { 0, 0, 0 } } end
  return out
end

local function freshData()
  local data = require("tests.modkit.fixtures").fresh()
  data.gen2Palettes = {
    generation = 2, source = "fixture",
    expBar = { { 247, 214, 123 }, { 33, 140, 255 } },
    battleText = { { 255, 255, 255 }, { 140, 156, 255 }, { 115, 132, 255 }, { 0, 0, 0 } },
    specialTilesets = { TILESET_ICE_PATH = rows(8) },
  }
  return data
end

local FIXTURE = {
  ["mods/good/manifest.json"] = [[{"id":"good","name":"Good","version":"1.0.0",
    "api":2,"games":["all"],"entry":"main.lua"}]],
  ["mods/good/main.lua"] = [[
    local mod = ...
    mod.content.palettes:patch("battleText", { [2] = { 255, 0, 0 } })
    mod.content.palettes:patch("specialTilesets",
      { TILESET_ICE_PATH = { [1] = { {255,255,255}, {1,2,3}, {4,5,6}, {0,0,0} } } })
  ]],
  ["mods/badtext/manifest.json"] = [[{"id":"badtext","name":"Bad Text","version":"1.0.0",
    "api":2,"games":["all"],"entry":"main.lua"}]],
  ["mods/badtext/main.lua"] = [[
    local mod = ...
    mod.content.palettes:override("battleText", "red")
  ]],
  ["mods/badtile/manifest.json"] = [[{"id":"badtile","name":"Bad Tile","version":"1.0.0",
    "api":2,"games":["all"],"entry":"main.lua"}]],
  ["mods/badtile/main.lua"] = [[
    local mod = ...
    mod.content.palettes:override("specialTilesets", { TILESET_ICE_PATH = "blue" })
  ]],
}

local function only(id)
  local fs = {}
  local prefix = "mods/" .. id .. "/"
  for k, v in pairs(FIXTURE) do
    if k:sub(1, #prefix) == prefix then fs[k] = v end
  end
  return T.sdk.memfs(fs)
end

local function check(id, value)
  return Schemas.check(Schemas.REGISTRIES.palettes, "palettes", id, value, "override", 2)
end
T.eq(check("battleText", "red"), nil, "schema refuses a battleText that is not a palette row")
T.eq(check("battleText", { { 999, 0, 0 }, { 0, 0, 0 } }), nil,
  "schema refuses a battleText channel past 255")
T.eq(check("specialTilesets", { TILESET_ICE_PATH = "blue" }), nil,
  "schema refuses a specialTilesets set that is not a row list")
T.eq(check("battleText", { { 255, 255, 255 }, { 1, 2, 3 }, { 4, 5, 6 }, { 0, 0, 0 } }), true,
  "schema accepts a four-colour battleText row")

do
  local data = freshData()
  local run = T.sdk.loadMods({ "mods/good" }, { fs = only("good"), generation = 2, data = data })
  T.eq(#run.errors, 0, "valid battleText and specialTilesets patches load (" .. tostring(run.errors[1]) .. ")")
  T.same(data.gen2Palettes.battleText[2], { 255, 0, 0 }, "the battleText patch lands")
  local screen = setmetatable({ palettes = data.gen2Palettes }, { __index = BattleState })
  T.same(screen:textboxPalette()[2], { 255, 0, 0 }, "and the battle text box reads it")
  T.same(data.gen2Palettes.specialTilesets.TILESET_ICE_PATH[1][2], { 1, 2, 3 },
    "the specialTilesets patch lands")
  run.release()
end

for _, case in ipairs({ { "badtext", "palettes.battleText" }, { "badtile", "palettes.specialTilesets" } }) do
  local data = freshData()
  local run = T.sdk.loadMods({ "mods/" .. case[1] }, { fs = only(case[1]), generation = 2, data = data })
  local named = false
  for _, err in ipairs(run.errors) do
    if tostring(err):find(case[2], 1, true) then named = true end
  end
  T.check(named, case[1] .. ": a malformed value is a load error naming " .. case[2])
  run.release()
end

T.finish("palettes_gen2_battle_text")
