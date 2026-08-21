-- Dataset-only half of scripts/test_local_rom_matrix.sh. The shell runner
-- points POKEPORT_DATA_DIR at one freshly imported private cache.

package.path = "./?.lua;./?/init.lua;" .. package.path

local version = assert(os.getenv("POKEPORT_MATRIX_VERSION"),
  "POKEPORT_MATRIX_VERSION is required")
local supported = {
  red = true, blue = true, yellow = true, gold = true, silver = true,
}
assert(supported[version], "unsupported matrix version " .. tostring(version))

local GameVersion = require("src.core.GameVersion")
assert(GameVersion.set(version) == version, "version normalization changed")

local Data = require("src.core.Data")
Data:load()

local function countRecords(rows, field)
  local count = 0
  for _, row in pairs(rows or {}) do
    if type(row) == "table" and row[field] ~= nil then count = count + 1 end
  end
  return count
end

local species = countRecords(Data.pokemon, "dex")
local maps = countRecords(Data.maps, "width")
local moves = countRecords(Data.moves, "id")
local cries = Data.audio and Data.audio.cries
local cryCount = 0
for _ in pairs(cries or {}) do cryCount = cryCount + 1 end

if GameVersion.generation() == 1 then
  assert(species == 151, ("%s species count is %d, expected 151")
    :format(version, species))
  assert(maps >= 220, ("%s map count is only %d"):format(version, maps))
  assert(moves >= 165, ("%s move count is only %d"):format(version, moves))
  assert(cryCount == 154, ("%s cry count is %d, expected 154")
    :format(version, cryCount))
  if version == "yellow" then
    assert(Data.field.oldManBattle.species == "RATTATA",
      "Yellow old-man tutorial did not use RATTATA")
    assert(Data.field.oakSpeech.demoSpecies == "PIKACHU",
      "Yellow Oak speech did not use PIKACHU")
  else
    assert(Data.field.oldManBattle.species == "WEEDLE",
      version .. " old-man tutorial did not use WEEDLE")
  end
else
  assert(species == 251, ("%s species count is %d, expected 251")
    :format(version, species))
  assert(maps >= 360, ("%s map count is only %d"):format(version, maps))
  assert(moves >= 251, ("%s move count is only %d"):format(version, moves))
  assert(cryCount == 250, ("%s cry count is %d, expected 250")
    :format(version, cryCount))
  assert(Data.constants.generation == 2,
    version .. " constants are not marked generation 2")
end

print(("[rom-matrix] DATA %s maps=%d species=%d moves=%d cries=%d")
  :format(version, maps, species, moves, cryCount))
