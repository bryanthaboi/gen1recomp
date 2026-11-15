-- engine/gfx/cgb_layouts.asm:488-499 _CGB_Diploma, gfx/sgb/predef.pal:28
--   GOLD_CACHE=<dir> CRYSTAL_CACHE=<dir> luajit tests/engine/gen2_diploma_bg_palette_s4.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check, eq = T.check, T.eq

local CacheContract = require("src.import.CacheContract")
local NamingScreen = require("src.ui.gen2.NamingScreen")
local Diploma = require("src.ui.gen2.Diploma")

local SET0 = { { 222, 255, 222 }, { 173, 173, 173 }, { 107, 107, 107 }, { 0, 0, 0 } }
local PREDEF = { { 255, 255, 255 }, { 247, 181, 140 }, { 132, 115, 156 }, { 0, 0, 0 } }
local gfx = { palettes = { SET0 }, bgPalette = PREDEF }

local S7C_TEXT = require("tests.fixture_data.gen2_rom_text_s7_c").text()
local naming = NamingScreen.new({ data = require("tests.fixtures.gen2_naming").fill({ gen2Diploma = gfx,
  text = S7C_TEXT }) },
  { type = "player" })
eq(naming.palette, PREDEF, "naming screen BG uses PREDEFPAL_DIPLOMA, not DiplomaPalettes set 0")
local box = NamingScreen.new({ data = require("tests.fixtures.gen2_naming").fill({ gen2Diploma = gfx,
  text = S7C_TEXT }) },
  { type = "box" })
eq(box.palette, PREDEF, "box naming path uses the same layout")
local diploma = Diploma.new({ data = { text = S7C_TEXT } }, { playerName = "GOLD", gfx = gfx })
eq(diploma:palette(), PREDEF, "diploma page uses PREDEFPAL_DIPLOMA")

for _, version in ipairs({ "gold", "silver", "crystal" }) do
  local found = false
  for _, path in ipairs(CacheContract.requiredFiles(version)) do
    if path == "data/generated/diploma.lua" then found = true end
  end
  check(found, version .. " requires data/generated/diploma.lua")
end

local function scale5(v) return math.floor(v * 255 / 31 + 0.5) end

local function decompPredef(repo)
  local f = io.open(repo .. "/gfx/sgb/predef.pal", "r")
  if not f then return nil end
  for line in f:lines() do
    if line:find("PREDEFPAL_DIPLOMA", 1, true) then
      f:close()
      local n = {}
      for v in line:gmatch("%d+") do n[#n + 1] = tonumber(v) end
      local out = {}
      for i = 0, 3 do
        out[i + 1] = { scale5(n[i * 3 + 1]), scale5(n[i * 3 + 2]), scale5(n[i * 3 + 3]) }
      end
      return out
    end
  end
  f:close()
  return nil
end

local appSupport = (os.getenv("HOME") or "") .. "/Library/Application Support/LOVE/"
local caches = {
  { "gold", os.getenv("GOLD_CACHE") or (appSupport .. "gold-dev/gold"), "../pokegold" },
  { "crystal", os.getenv("CRYSTAL_CACHE") or (appSupport .. "crystal-dev/crystal"), "../pokecrystal" },
}

for _, entry in ipairs(caches) do
  local version, dir, repo = entry[1], entry[2], entry[3]
  local mf = io.open(dir .. "/" .. CacheContract.MARKER_PATH, "r")
  local marker = mf and mf:read("*a")
  if mf then mf:close() end
  local chunk = marker and CacheContract.markerMatches(version, marker)
    and loadfile(dir .. "/data/generated/diploma.lua")
  if not chunk then
    print("[skip] no current " .. version .. " cache at " .. dir)
  else
    local data = chunk()
    local want = decompPredef(repo)
    check(type(data.bgPalette) == "table", version .. " cache carries bgPalette")
    if not want then
      print("[skip] no " .. repo .. "/gfx/sgb/predef.pal")
    else
      for i = 1, 4 do
        T.same(data.bgPalette[i], want[i], version .. " bgPalette colour " .. (i - 1) .. " matches predef.pal")
      end
    end
  end
end

T.finish("gen2 diploma bg palette S4")
