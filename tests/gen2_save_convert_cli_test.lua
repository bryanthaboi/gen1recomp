-- The standalone .sav converter refuses a Gen 2 save, ROM-free.
--   luajit tests/gen2_save_convert_cli_test.lua
-- Also dofile'd by tests/run_tests.lua.
--
-- src/save_convert/GenSave.lua models Gen 1 SRAM only, and SaveConvert answers
-- a plain refusal for a Gen 2 game rather than pushing a Gen 2 save table
-- through Gen 1 offsets.  That refusal keys on the game the caller names, so
-- the CLI has to name one: tools/save_convert/convert.lua runs the real
-- binary here (a subprocess, not the library) because the hole this covers was
-- exactly the two call sites in it that passed no game at all.
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 save convert cli")
local check = S.check

local SaveSerializer = require("src.core.SaveSerializer")

local function run(cmd)
  local pipe = io.popen(cmd .. " 2>&1")
  if not pipe then return nil end
  local out = pipe:read("*a")
  pipe:close()
  return out or ""
end

local probe = run("luajit -v")
if not probe or not probe:find("LuaJIT") then
  check(true, "luajit not on PATH : SKIP")
  S.finish()
  return
end

local function tmp(name)
  local dir = os.getenv("TMPDIR") or "/tmp/"
  if dir:sub(-1) ~= "/" then dir = dir .. "/" end
  return dir .. "gen2-cli-" .. name
end

local function write(path, text)
  local f = assert(io.open(path, "w"))
  f:write(text)
  f:close()
end

local function exists(path)
  local f = io.open(path, "rb")
  if f then f:close() return true end
  return false
end

-- A Gold slot as src/core/gen2/Save.lua writes it: `generation`/`version` at
-- the top level, and party rows carrying fields Gen 1 never had.
local goldPath = tmp("gold.lua")
local outPath = tmp("gold.sav")
os.remove(outPath)
write(goldPath, SaveSerializer.encode({
  format = 7, generation = 2, version = "gold",
  player = { name = "GOLD", money = 3000 },
  party = { { species = "TOTODILE", level = 5, happiness = 70, pokerus = 0,
              dvs = { atk = 15, def = 15, spd = 15, spc = 15 } } },
}))

local out = run(("luajit tools/save_convert/convert.lua export %q %q")
  :format(goldPath, outPath))
-- Gen 2 no longer needs the cartridge image the save came from (#2283): one
-- is synthesized. What it does need is the map the save stands on, which this
check(out:find("does not name one", 1, true) ~= nil,
  "exporting a Gold slot that names no map is refused, and says why: "
    .. (out:gsub("%s+$", "")))
check(out:find("no cartridge image to write", 1, true) == nil,
  "and not with the old lineage refusal: " .. (out:gsub("%s+$", "")))
check(not exists(outPath),
  "and no 32768-byte file that looks like a Red battery is written")


-- The way IN is no longer a gate: Gen 2 imports through
-- src/save_convert/Gen2Save.lua now.  What this pins is that the bytes reach
-- that codec and are judged by ITS rules -- an all-zero image has neither of
-- Gen 2's check values, so it is refused for being blank rather than for
-- being Gold.
local savPath = tmp("in.sav")
local outPath2 = tmp("in.lua")
os.remove(outPath2)
write(savPath, string.rep("\0", 32768))
out = run(("luajit tools/save_convert/convert.lua import %q %q gold")
  :format(savPath, outPath2))
check(out:find("not supported yet", 1, true) == nil,
  "importing for a Gen 2 game is no longer refused by version: " .. (out:gsub("%s+$", "")))
check(out:find("checksum", 1, true) ~= nil,
  "a blank image is refused on Gen 2's own check values: " .. (out:gsub("%s+$", "")))
check(not exists(outPath2), "and writes nothing")

-- Gen 1 keeps working: a Red-shaped save is never caught by the Gen 2 gate.
-- (Whether the export then succeeds depends on data/generated/ being built,
-- which this suite deliberately does not require.)
local redPath = tmp("red.lua")
local outPath3 = tmp("red.sav")
os.remove(outPath3)
write(redPath, SaveSerializer.encode({
  meta = { format = "gen1_import", version = "red" },
  player = { name = "RED", money = 3000 },
  party = {},
}))
out = run(("luajit tools/save_convert/convert.lua export %q %q")
  :format(redPath, outPath3))
check(not out:find("Gen 2 cart save", 1, true),
  "a Gen 1 save is not refused: " .. (out:gsub("%s+$", "")))

for _, path in ipairs({ goldPath, outPath, savPath, outPath2, redPath,
                        outPath3 }) do
  os.remove(path)
end

S.finish()
