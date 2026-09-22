-- audio/poke_flute.asm:1
-- audio/sfx/pokeflute_ch7.asm:1
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local S = require("tests.harness").suite("parity in-battle poke flute #2305")
local check, eq = S.check, S.eq

local ChipSynth = require("src.core.ChipSynth")
local Sound = require("src.core.Sound")
local GameVersion = require("src.core.GameVersion")

local function readAll(path, mode)
  local f = io.open(path, mode or "r")
  if not f then return nil end
  local body = f:read("*a")
  f:close()
  return body
end

local function framesOf(data, def)
  local rate = ChipSynth.SAMPLE_RATE
  local engine = ChipSynth.newEngine(data, def,
    { sfx = true, allowLoops = false, frameTicks = 0x100 })
  local ran, cap = 0, rate * 20
  while ran < cap and not engine:finished() do
    ran = ran + 1
    engine:sample()
  end
  return engine:finished() and ran * 60 / rate or nil
end

local function runCache(label, version, root)
  local audioPath = root .. "/data/generated/audio.lua"
  local progPath = root .. "/assets/generated/audio/programs.bin"
  local chunk = loadfile(audioPath)
  local bytes = readAll(progPath, "rb")
  if not (chunk and bytes) then return false end
  local audio = chunk()
  local data = { audio = audio }
  local realRead = love.filesystem.read
  local savedVersion = GameVersion.current
  love.filesystem.read = function(name, ...)
    if name == audio.programFile then return bytes end
    return realRead(name, ...)
  end
  ChipSynth.invalidateBanks()
  GameVersion.current = version
  local ok, err = pcall(function()
    local def = Sound._pokefluteInBattleDef(data)
    check(def ~= nil, label .. ": the in-battle flute derives from Caught_Mon")
    if not def then return end
    local battle = framesOf(data, def)
    local field = framesOf(data, audio.sfx.Pokeflute)
    check(battle and math.abs(battle - 256) <= 1,
      ("%s: in-battle flute runs 256 frames (got %s)"):format(label,
        tostring(battle)))
    check(field and math.abs(field - 576) <= 1,
      ("%s: field flute runs 576 frames (got %s)"):format(label,
        tostring(field)))
    eq(ChipSynth.effectChannels(data, def) ~= nil, true,
      label .. ": the derived def reads as a header")
  end)
  GameVersion.current = savedVersion
  love.filesystem.read = realRead
  ChipSynth.invalidateBanks()
  check(ok, label .. ": renders" .. (ok and "" or (": " .. tostring(err))))
  return true
end

local savedRate = ChipSynth.SAMPLE_RATE
ChipSynth.setSampleRate(8000)
local okTree = pcall(runCache, "tree", os.getenv("POKEPORT_VERSION") or "red", ".")
ChipSynth.setSampleRate(savedRate)
check(okTree, "tree cache ran")

local yellow = os.getenv("POKEPORT_YELLOW_CACHE")
if yellow and yellow ~= "" then
  ChipSynth.setSampleRate(8000)
  local okY = pcall(runCache, "yellow", "yellow", yellow)
  ChipSynth.setSampleRate(savedRate)
  check(okY, "yellow cache ran")
end

S.finish()
