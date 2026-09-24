#!/usr/bin/env luajit
-- src/data/party_menu.h:111

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

local function finish()
  if failed > 0 then
    print(string.format("[result] %d CHECK(S) FAILED", failed))
    os.exit(1)
  end
  print("[result] all checks passed")
  os.exit(0)
end

local function slurp(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local d = f:read("*a")
  f:close()
  return d
end

local GV = require("src.core.GameVersion")
local Versions = require("src.import.gba.versions")
local Chrome = require("src.import.gba.party_chrome_extract")

local TILEMAPS = {
  { "PARTY_MENU_CONFIRM_BUTTON_TILEMAP", 0x459FC4, 0x4599E4, "confirm_button.bin", 28 },
  { "PARTY_MENU_CANCEL_BUTTON_TILEMAP", 0x459FE0, 0x459A00, "cancel_button.bin", 28 },
  { "PARTY_MENU_SLOT_MAIN_TILEMAP", 0x45A180, 0x459BA0, "slot_main.bin", 70 },
  { "PARTY_MENU_SLOT_WIDE_TILEMAP", 0x45A20C, 0x459C2C, "slot_wide.bin", 54 },
  { "PARTY_MENU_SLOT_WIDE_EMPTY_TILEMAP", 0x45A278, 0x459C98, "slot_wide_empty.bin", 54 },
}

local OUTPUTS = {
  { "slot_main", 80 * 56 }, { "slot_main_selected", 80 * 56 },
  { "slot_main_multi", 80 * 56 }, { "slot_main_multi_selected", 80 * 56 },
  { "slot_wide", 144 * 24 }, { "slot_wide_selected", 144 * 24 },
  { "slot_wide_multi", 144 * 24 }, { "slot_wide_multi_selected", 144 * 24 },
  { "slot_wide_empty", 144 * 24 },
  { "cancel_button", 56 * 16 }, { "cancel_button_selected", 56 * 16 },
  { "confirm_button", 56 * 16 }, { "confirm_button_selected", 56 * 16 },
}

print("[test] 1. the slot and button tilemap offsets are pret's party_menu.o statics")
for _, row in ipairs(TILEMAPS) do
  check(Versions[row[1]] == row[2], "FireRed " .. row[1])
end
Versions.select("leafgreen")
for _, row in ipairs(TILEMAPS) do
  check(Versions[row[1]] == row[3], "LeafGreen " .. row[1])
end
Versions.select("firered")

print("[test] 2. the extractor carries no hand-written or repo-file tilemaps")
do
  local src = slurp("src/import/gba/party_chrome_extract.lua") or ""
  check(src ~= "", "party_chrome_extract.lua is readable")
  check(not src:find("DEFAULT_", 1, true), "no DEFAULT_* tilemap copies")
  check(not src:find("pokefirered/", 1, true), "no pret graphics paths")
  check(not src:find("chrome/menus/party", 1, true), "no repo chrome paths")
  check(not src:find("io.open(p", 1, true) and not src:find("love.filesystem.read, p", 1, true),
    "no file reads while baking")
end

local root = os.getenv("POKEFIRERED") or "../pokefirered"
local ROMS = {
  { "pokefirered.gba", "41cb23d8dccc8ebd7c649cd8fbb58eeace6e2fdc" },
  { "pokeleafgreen.gba", "574fa542ffebb14be69902d1d36f1ec0a4afd71e" },
  { "pokefirered_rev1.gba", "dd5945db9b930750cb39d00c84da8571feebf417" },
  { "pokeleafgreen_rev1.gba", "7862c67bdecbe21d1d69ce082ce34327e1c6ed5e" },
}

local baked = {}
local ran = 0
for n, case in ipairs(ROMS) do
  local data = slurp(root .. "/" .. case[1])
  if not data then
    print("[skip] " .. case[1] .. " not built in " .. root)
  else
    ran = ran + 1
    print("[test] 3." .. n .. " " .. case[1] .. " tilemaps read byte-exact to pret and bake")
    local rom = assert(require("src.import.gba.rom").open({
      info = function() return { size = #data, md5 = case[2] } end,
      read = function(_, _, off, len) return data:sub(off + 1, off + len) end,
    }, GV.forSha1(case[2])))
    for _, row in ipairs(TILEMAPS) do
      local want = slurp(root .. "/graphics/party_menu/" .. row[4])
      local got = {}
      for i = 1, row[5] do got[i] = string.char(rom:get(Versions[row[1]] + i - 1)) end
      check(want ~= nil and #want == row[5] and table.concat(got) == want, row[4] .. " matches pret")
    end
    local written = {}
    local cache = {
      write = function(_, rel, bytes) written[rel] = bytes; return true end,
      read = function(_, rel) return written[rel] end,
      exists = function(_, rel) return written[rel] ~= nil end,
    }
    local ok, err = pcall(Chrome.run, rom, cache, { cacheRoot = "x" })
    check(ok, "party_chrome_extract.run() completes (" .. tostring(err) .. ")")
    local bad = {}
    for _, o in ipairs(OUTPUTS) do
      local blob = written["x/pokemon/party/" .. o[1] .. ".rgba"]
      if not blob or #blob ~= o[2] * 4 then bad[#bad + 1] = o[1] end
    end
    check(#bad == 0, "every slot and button sheet is written at its size " .. table.concat(bad, " "))
    check(written["x/pokemon/party/status_icons.png"] == nil, "no repo status_icons.png is copied in")
    baked[case[1]] = written
  end
end
if ran == 0 then print("[skip] no pret build next to the checkout") end

local fr = baked["pokefirered.gba"]
if fr then
  for name, w in pairs(baked) do
    local same = true
    for _, o in ipairs(OUTPUTS) do
      local rel = "x/pokemon/party/" .. o[1] .. ".rgba"
      if w[rel] ~= fr[rel] then same = false end
    end
    check(same, name .. " bakes the same slot and button sheets as pokefirered.gba")
  end
end

local Cache = require("tests.game3_cache")
local croot = Cache.root("pokemon/party/slot_main.rgba")
if not croot then
  print("[skip] built cache: " .. tostring(Cache.reason))
  finish()
end
if fr then
  print("[test] 4. a built cache carries the same sheets")
  for _, o in ipairs(OUTPUTS) do
    local blob = slurp(croot .. "/pokemon/party/" .. o[1] .. ".rgba")
    check(blob == fr["x/pokemon/party/" .. o[1] .. ".rgba"], "cached " .. o[1] .. ".rgba equals the ROM bake")
  end
end
finish()
