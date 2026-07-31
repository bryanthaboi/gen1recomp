-- Standalone: luajit mods/pokemon_recolor/tests/pokemon_recolor_test.lua
--
-- Asserts the mod's stated effect and, just as importantly, its stated
-- NON-effects: this is a battle-pic mod, so tilesets, icons, sprites and
-- every stat must come out of a load untouched.
--
-- The shipped fixture carries almost no content, so anything meaningful
-- has to be seeded first; otherwise every lookup takes its defensive warn
-- branch and a green run would prove nothing.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

local MOD_DIR = "pokemon_recolor"
local MOD = "mods/" .. MOD_DIR

local chunk = assert(loadfile(MOD .. "/ramps.lua"), "ramps.lua must load")
local ALL = chunk()
T.check(type(ALL) == "table" and #ALL > 0, "ramps.lua yields a list")

-- Every species is listed so its choice survives regeneration; only those
-- carrying a ramp are repainted.  Splitting them here is what lets the
-- suite assert both halves of the contract.
local RAMPS, VANILLA = {}, {}
for _, e in ipairs(ALL) do
  T.check(type(e.variant) == "number" and e.variant >= 1 and e.variant <= 4,
    tostring(e.id) .. " records a variant in 1..4")
  if e.ramp then RAMPS[#RAMPS + 1] = e else VANILLA[#VANILLA + 1] = e end
end
T.check(#VANILLA > 0, "some species are recorded as vanilla")
for _, e in ipairs(VANILLA) do
  T.eq(e.variant, 1, e.id .. " carries no ramp, so its variant must be 1")
end
for _, e in ipairs(RAMPS) do
  T.neq(e.variant, 1, e.id .. " carries a ramp, so its variant must not be 1")
end

-- ------- seed a vanilla-shaped view

local GREY = { 248, 168, 88, 0 }
local Data = T.fixtures.fresh()

for _, entry in ipairs(RAMPS) do
  Data.pokemon[entry.id] = {
    id = entry.id,
    spriteFront = "assets/generated/" .. entry.front,
    spriteBack = "assets/generated/" .. entry.back,
    baseStats = { speed = 50, attack = 60 },
    learnset = { { level = 1, move = "FIX_TACKLE" } },
    types = { "NORMAL" },
  }
end
-- a species the mod must NOT touch: absent from ramps.lua by review
Data.pokemon.LEFT_ALONE = {
  id = "LEFT_ALONE", spriteFront = "assets/generated/battle/front/x.png",
  spriteBack = "assets/generated/battle/back/xb.png",
  baseStats = { speed = 50 },
}
Data.tilesets.OVERWORLD = {
  id = "OVERWORLD", image = "assets/generated/tilesets/overworld.png",
  blocks = { { 1, 2, 3, 4 } }, walkable = { [1] = true }, grassTile = 82,
}
Data.icons = { bySpecies = {}, byDex = {}, icons = {} }

-- The transform's pixel path needs a real LOVE run: love.image is absent
-- from the headless stub. Hiding the imported cache puts this load on the
-- no-cache branch, which is the one a mod owes the player anyway -- write
-- nothing, load regardless -- and keeps the suite from depending on
-- whether the machine running it happens to have a ROM imported.
local function noCacheFs()
  local inner = T.fs.new(".")
  local hidden = "assets/generated/"
  local overlay = {}

  local function isHidden(path)
    return type(path) == "string" and path:sub(1, #hidden) == hidden
  end

  local fs = { root = inner.root }
  function fs.read(path)
    if isHidden(path) then return nil end
    return overlay[path] or inner.read(path)
  end
  function fs.write(path, body) overlay[path] = body return true end
  function fs.createDirectory() return true end
  function fs.load(path) return inner.load(path) end
  function fs.getInfo(path)
    if isHidden(path) then return nil end
    if overlay[path] then return { type = "file" } end
    return inner.getInfo(path)
  end
  function fs.getDirectoryItems(path)
    if isHidden(path) then return {} end
    -- Supplying an fs bypasses the SDK's own alias, which normally mounts
    -- the mod under test alone. Without narrowing discovery here every mod
    -- in mods/ would load too, and one of them overriding a species this
    -- suite asserts on would fail it for reasons that are not this mod's.
    if path == "mods" then return { MOD_DIR } end
    return inner.getDirectoryItems(path)
  end
  return fs
end

local run = T.sdk.loadMod(MOD, { data = Data, fs = noCacheFs() })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
T.eq(run.mod and run.mod.manifest.assets_transforms, "transforms.lua",
  "the manifest declares its transform")
T.eq(run.mod and run.mod.manifest.category, "GRAPHICS", "declared GRAPHICS")

-- ------- the stated effect

local painted = 0
for _, entry in ipairs(RAMPS) do
  local record = Data.pokemon[entry.id]
  T.eq(record.trueColor, true, entry.id .. " opted into trueColor")
  -- patch, not override: the pic paths must NOT be rewritten. The transform
  -- writes under the same relative name, so the resolver swaps the file in
  -- underneath a record that still points at the cache.
  T.eq(record.spriteFront, "assets/generated/" .. entry.front,
    entry.id .. " kept its vanilla front path")
  T.eq(record.spriteBack, "assets/generated/" .. entry.back,
    entry.id .. " kept its vanilla back path")
  painted = painted + 1
end
T.check(painted >= 100, "a substantial share of the dex is repainted")

-- every ramp is four in-range colours, lightest first
for _, entry in ipairs(RAMPS) do
  T.eq(#entry.ramp, 4, entry.id .. " has exactly four shades")
  local prev
  for _, c in ipairs(entry.ramp) do
    T.eq(#c, 3, entry.id .. " shade is an rgb triple")
    for _, v in ipairs(c) do
      T.check(v >= 0 and v <= 255, entry.id .. " channel in range")
    end
    local l = 0.299 * c[1] + 0.587 * c[2] + 0.114 * c[3]
    if prev then
      T.check(l <= prev + 1, entry.id .. " shades run lightest first")
    end
    prev = l
  end
end

-- ------- the stated NON-effects

T.neq(Data.pokemon.LEFT_ALONE.trueColor, true,
  "a species absent from ramps.lua is never flagged")
T.neq(Data.tilesets.OVERWORLD.trueColor, true, "tilesets are untouched")
T.eq(Data.tilesets.OVERWORLD.grassTile, 82, "tileset records intact")
local iconCount = 0
for _ in pairs(Data.icons.bySpecies) do iconCount = iconCount + 1 end
T.eq(iconCount, 0, "no party icons are registered")

for _, entry in ipairs(VANILLA) do
  local record = Data.pokemon[entry.id]
  if record then
    T.neq(record.trueColor, true,
      entry.id .. " is recorded vanilla and must not be flagged")
  end
end

for _, entry in ipairs(RAMPS) do
  local record = Data.pokemon[entry.id]
  T.eq(record.baseStats.speed, 50, entry.id .. " base stats untouched")
  T.eq(record.baseStats.attack, 60, entry.id .. " all stats untouched")
  T.check(record.learnset ~= nil, entry.id .. " learnset survived the patch")
  T.check(record.types ~= nil, entry.id .. " types survived the patch")
end

-- ------- the recipe

local transform = assert(loadfile(MOD .. "/transforms.lua"))()
T.check(type(transform) == "function", "transforms.lua returns function(ctx)")

-- no imported cache: write nothing, raise nothing
local wrote = 0
local ok, err = pcall(transform, {
  exists = function() return false end,
  readImage = function() error("must not read without exists()", 0) end,
  writeImage = function() wrote = wrote + 1 end,
  recolor = function(img) return img end,
})
T.check(ok, "the recipe survives an empty cache (" .. tostring(err) .. ")")
T.eq(wrote, 0, "and writes nothing rather than failing the mod")

-- populated cache: two pics per species, all under battle/, four-colour ramps
wrote = 0
local read, ramps = {}, {}
T.check(pcall(transform, {
  exists = function() return true end,
  readImage = function(rel) read[#read + 1] = rel return { rel } end,
  writeImage = function() wrote = wrote + 1 end,
  recolor = function(img, ramp) ramps[#ramps + 1] = ramp return img end,
}), "the recipe runs over a populated cache")
T.eq(wrote, #read, "every pic it read, it wrote back")
T.eq(wrote, #RAMPS * 2, "one front and one back per listed species")
for _, rel in ipairs(read) do
  T.check(rel:sub(1, 7) == "battle/",
    "only battle pics are derived, got " .. rel)
end
for _, ramp in ipairs(ramps) do
  T.eq(#ramp, 4, "every ramp handed to recolor is four colours")
end

run.release()
T.finish("pokemon_recolor")
