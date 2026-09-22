package.path = "./?.lua;./?/init.lua;" .. package.path

love = love or require("tests.love_stub")

local S = require("tests.harness").suite("gen2 link fingerprint cross version")
local check, eq = S.check, S.eq

local Fingerprint = require("src.link.Fingerprint")
local ItemEffects = require("src.core.gen2.ItemEffects")

local home = os.getenv("HOME") or ""
local LOVE = home .. "/Library/Application Support/LOVE/"

local function cacheDir(env, fallback)
  return os.getenv(env) or (LOVE .. fallback)
end

local function readable(path)
  local f = io.open(path, "r")
  if not f then return false end
  f:close()
  return true
end

local function dataset(dir)
  local root = dir .. "/data/generated/"
  if not readable(root .. "pokemon.lua") then return nil end
  local function load(name)
    if not readable(root .. name .. ".lua") then return nil end
    return dofile(root .. name .. ".lua")
  end
  local data = {
    pokemon = load("pokemon") or {},
    items = load("items") or {},
    moves = load("moves") or {},
    type_chart = load("type_chart") or {},
    gen2Constants = load("constants"),
  }
  local chart = data.type_chart
  chart.matchups = chart.matchups or {}
  for _, row in ipairs(chart.foresightMatchups or {}) do
    chart.matchups[#chart.matchups + 1] = row
  end
  data.gen2HeldItems = ItemEffects.heldItemsFrom(data.items)
  return data
end

local gold = dataset(cacheDir("GOLD_CACHE", "gold-dev/gold"))
local silver = dataset(cacheDir("SILVER_CACHE", "rv2283-silver/silver"))
local crystal = dataset(cacheDir("CRYSTAL_CACHE", "crystal-dev/crystal"))

if not (gold and crystal) then
  check(true, "gold or crystal cache absent : SKIP")
else
  local g = Fingerprint.compute(gold, {}, 2)
  local c = Fingerprint.compute(crystal, {}, 2)
  eq(c, g, "a vanilla Crystal cache digests the same as a vanilla Gold cache")
  if silver then
    eq(Fingerprint.compute(silver, {}, 2), g, "and Silver matches both")
  else
    check(true, "silver cache absent : SKIP")
  end
  check(crystal.pokemon.tutorMoves ~= nil,
    "the crystal cache really carries the tutor list")
  eq(Fingerprint.records(crystal, "pokemon", 2).tutorMoves, nil,
    "and it is not treated as a species")
end

S.finish()
