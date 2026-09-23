#!/usr/bin/env luajit
-- pokefirered/src/hall_of_fame.c:1011

package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function eq(a, b, msg)
  check(a == b, string.format("%s (%s == %s)", msg, tostring(a), tostring(b)))
end

require("src.core.GameVersion").set("firered")

package.loaded["src.core.game3.audio"] = {
  playSe = function() end,
  playCry = function() end,
  playSong = function() end,
  stopAll = function() end,
}

local gfx = setmetatable({}, { __index = function() return function() end end })
gfx.newQuad = function() return {} end
gfx.newImage = function()
  return { setFilter = function() end, getDimensions = function() return 64, 64 end }
end
_G.love = { graphics = gfx }

local Cache = require("tests.game3_cache")
if not Cache.mount("meta.json") then
  print("[skip] " .. tostring(Cache.reason))
  os.exit(0)
end

local Pokemon = require("src.core.game3.pokemon")
local FrlgFont = require("src.ui.game3.frlg_font")
local HallOfFame = require("src.ui.game3.hall_of_fame")

check(Pokemon.nationalDex == nil, "there is no Pokemon.nationalDex export to call")
check(type(Pokemon.national) == "function", "the export is Pokemon.national")

local species, national = nil, nil
for sp = 1, 411 do
  local nat = Pokemon.national(sp)
  local name = Pokemon.name(sp)
  if nat and nat ~= sp and type(name) == "string" and name:match("^%a") then
    species, national = sp, nat
    break
  end
end
if not species then
  print("[skip] this cache has no species whose internal id differs from its dex number")
  os.exit(0)
end
print(string.format("[info] internal species %d is National Dex %d (%s)",
  species, national, tostring(Pokemon.name(species))))

local drawn = {}
local realDraw = FrlgFont.draw
FrlgFont.draw = function(text, x, y, opts)
  drawn[#drawn + 1] = tostring(text)
  return realDraw(text, x, y, opts)
end

HallOfFame.start({
  session = { name = "RED", trainerId = 12345, national_dex_unlocked = true, party = {
    { species = species, name = Pokemon.name(species), level = 50, otId = 12345 },
  } },
  onDone = function() end,
  warp = false,
})
check(HallOfFame.isOpen(), "the Hall of Fame opened for the induction")
for _ = 1, 400 do
  if HallOfFame.phase() == "hold" then break end
  HallOfFame.update(1 / 60)
end
check(HallOfFame.phase() == "hold", "the first mon slid in and its info printed")
HallOfFame.draw()
FrlgFont.draw = realDraw

local row = nil
for _, text in ipairs(drawn) do
  if text:match("^No%. %d") then row = text end
end
check(row ~= nil, "the induction card printed a dex number row (" .. table.concat(drawn, " | ") .. ")")
eq(row, string.format("No. %03d", national),
  "the row is the National Dex number, not the internal species id")
check(row ~= string.format("No. %03d", species),
  "and it is not the internal id " .. tostring(species))

HallOfFame.close()

if failed > 0 then
  print("[test] FAILED " .. failed)
  os.exit(1)
end
print("[test] all passed")
os.exit(0)
