#!/usr/bin/env luajit
-- ../pokefirered/src/pokedex_screen.c:2892-2921

package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function eq(a, b, msg)
  if a == b then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print(string.format("[FAIL] %s (%s ~= %s)", msg, tostring(a), tostring(b)))
  end
end

local function check(cond, msg)
  eq(cond and true or false, true, msg)
end

require("src.core.GameVersion").set("firered")

package.loaded["src.core.game3.audio"] = {
  playCry = function() end,
  playSe = function() end,
  playSong = function() end,
  stopAll = function() end,
}

local Cache = require("tests.game3_cache")
local root = Cache.mount("pokemon/pokedex/footprints/1.rgba")
if not root then
  print("[skip] " .. tostring(Cache.reason))
  os.exit(0)
end

local PokedexChrome = require("src.ui.game3.pokedex_chrome")
local Pokemon = require("src.core.game3.pokemon")
Pokemon.install(nil)

local DIR = root .. "/pokemon/pokedex/footprints"
local NUM_SPECIES = require("src.import.gba.versions").NUM_SPECIES or 412

local function file_bytes(rel)
  local f = io.open(DIR .. "/" .. rel, "rb")
  if not f then return nil end
  local d = f:read("*a")
  f:close()
  if type(d) == "string" and #d > 0 then return d end
  return nil
end

local function fake_love()
  return {
    image = {
      newImageData = function(w, h)
        local px = {}
        return {
          _w = w, _h = h, _px = px,
          setPixel = function(_, x, y, r, g, b, a)
            px[y * w + x] = { r, g, b, a }
          end,
        }
      end,
    },
    graphics = {
      setColor = function() end,
      newImage = function(data) return { _data = data, setFilter = function() end } end,
      draw = function() end,
    },
  }
end

local function image_to_rgba(img)
  local data = img._data
  local out = {}
  for y = 0, data._h - 1 do
    for x = 0, data._w - 1 do
      local p = data._px[y * data._w + x] or { 0, 0, 0, 0 }
      for i = 1, 4 do
        out[#out + 1] = string.char(math.floor(p[i] * 255 + 0.5))
      end
    end
  end
  return table.concat(out)
end

print("[test] 1. The dex entry draws gMonFootprintTable[species]")
do
  local realLove = love
  love = fake_love()
  local painted = nil
  love.graphics.draw = function(img) painted = img end

  local function drawnBytes(sp)
    painted = nil
    PokedexChrome.drawFootprint(sp, 104, 64)
    return painted and image_to_rgba(painted) or nil
  end

  -- ../pokefirered/include/constants/species.h:5
  for _, sp in ipairs({ 0, 1, 25, 29, 32, 151, 252, 277, 290, 411 }) do
    check(drawnBytes(sp) == file_bytes(sp .. ".rgba"),
      string.format("species %d draws footprints/%d.rgba", sp, sp))
  end

  local qm = file_bytes("question_mark.rgba")
  check(qm ~= nil, "the cache has a question_mark footprint")
  check(file_bytes("0.rgba") ~= qm, "species 0 has its own footprint, not the question mark")

  love = realLove
end

print("[test] 2. Every species resolves to its own species-id file")
do
  local wrong, missing = 0, 0
  local firstWrong = nil
  for sp = 0, NUM_SPECIES - 1 do
    local want = DIR .. "/" .. sp .. ".rgba"
    local bytes, rel = PokedexChrome.footprintSource(sp)
    if not bytes then
      missing = missing + 1
    elseif rel ~= want then
      wrong = wrong + 1
      firstWrong = firstWrong or string.format("species %d -> %s", sp, tostring(rel))
    end
  end
  eq(missing, 0, "every species has a footprint")
  eq(wrong, 0, "no species falls through to a name key" ..
    (firstWrong and (" (" .. firstWrong .. ")") or ""))
end

print("[test] 3. The two NIDORAN keep distinct footprints")
do
  local fBytes, fRel = PokedexChrome.footprintSource(29)
  local mBytes, mRel = PokedexChrome.footprintSource(32)
  eq(fRel, DIR .. "/29.rgba", "NIDORAN_F reads its species file")
  eq(mRel, DIR .. "/32.rgba", "NIDORAN_M reads its species file")
  eq(fBytes, file_bytes("29.rgba"), "NIDORAN_F bytes match the cache")
  eq(mBytes, file_bytes("32.rgba"), "NIDORAN_M bytes match the cache")
  check(fBytes ~= mBytes, "the two NIDORAN footprints differ")
end

if failed > 0 then
  print(string.format("\n[FAILED] %d check(s) failed", failed))
  os.exit(1)
end
print("\n[test] all passed")
