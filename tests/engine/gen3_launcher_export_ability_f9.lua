package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness")
local SaveConvert = require("src.save_convert.SaveConvert")
local Gen3Save = require("src.save_convert.Gen3Save")
local Pokemon = require("src.core.game3.pokemon")

local ABILITIES = "return { [1] = { 65, 0 }, [7] = { 67, 0 }, [25] = { 9, 0 }, [63] = { 28, 39 } }"
local NATIONAL = "return { toNational = { [1] = 1, [7] = 7, [25] = 25, [63] = 63 }, toSpecies = { [1] = 1, [7] = 7, [25] = 25, [63] = 63 } }"

local FAKE = "/nonexistent-export-ability-f9/"
local serveAbilities = true
local realOpen = io.open
io.open = function(path, mode)
  if type(path) == "string" and path:sub(1, #FAKE) == FAKE then
    local body
    if serveAbilities and path:match("pokemon/abilities%.lua$") then body = ABILITIES end
    if path:match("pokemon/national%.lua$") then body = NATIONAL end
    if path:match("map_tree/maps/%d+_%d+/header%.json$") then body = '{"layoutId": 1}' end
    if not body then return nil, "missing" end
    return { read = function() return body end, close = function() end, lines = function() return body:gmatch("[^\n]+") end }
  end
  return realOpen(path, mode)
end

local installs, packLogs = 0, 0
local realInstall = Pokemon.install
Pokemon.install = function(...)
  installs = installs + 1
  return realInstall(...)
end
local realPrint = print
print = function(...)
  local line = table.concat({ tostring((...)) }, " ")
  if line:find("species pack", 1, true) then packLogs = packLogs + 1 end
  return realPrint(...)
end

local HOME = { emerald = "EM_LITTLEROOT_TOWN", ruby = "RU_LITTLEROOT_TOWN", firered = "FR_PALLET_TOWN", leafgreen = "FR_PALLET_TOWN" }
-- pokeemerald/src/pokemon.c:2296
local EXPECT = { { 1, 3, 0 }, { 7, 5, 0 }, { 25, 9, 0 }, { 63, 11, 1 }, { 63, 12, 0 } }

local function exportParty(v, abilityNum)
  Pokemon.invalidate()
  Pokemon._cache = nil
  installs, packLogs = 0, 0
  SaveConvert.setGen3CacheDir(v, FAKE .. v)
  local party = {}
  for i, e in ipairs(EXPECT) do
    party[i] = { species = e[1], speciesNumbering = "internal", personality = e[2], level = 5, exp = 135,
      otId = 1, hp = 20, maxHp = 20, moves = { 33 }, abilityNum = abilityNum and e[3] or nil }
  end
  local map = HOME[v]
  local save = { version = v, engine = "game3", generation = 3, name = "RV", gender = 0, trainerId = 1, secretId = 2,
    map = map, x = 5, y = 9, facing = "down", healMap = map, healX = 5, healY = 9, party = party, flags = {}, vars = {},
    money = 3000, modData = { cartImport = { lastHealLocation = { map = map, warpId = -1, x = 5, y = 9 } } } }
  return SaveConvert.exportSav(save, v)
end

for _, v in ipairs({ "emerald", "ruby", "firered", "leafgreen" }) do
  serveAbilities = true
  local bytes, err = exportParty(v, false)
  T.check(bytes ~= nil, v .. " launcher export encodes (" .. tostring(err) .. ")")
  T.eq(installs, 0, v .. " launcher export never installs the runtime species pack")
  T.eq(packLogs, 0, v .. " launcher export logs no species pack lookup")
  local c = bytes and Gen3Save.forVersion(v).decode(bytes)
  for i, e in ipairs(EXPECT) do
    local m = c and c.party[i]
    T.eq(m and m.abilityNum, e[3], ("%s species %d personality %d abilityNum from the version cache"):format(v, e[1], e[2]))
  end

  serveAbilities = false
  bytes, err = exportParty(v, false)
  T.check(bytes == nil, v .. " export without pokemon/abilities.lua writes no guessed ability bit")
  T.eq(err, Gen3Save.MSG.noData, v .. " export without pokemon/abilities.lua is refused with the re-import notice")
  T.eq(installs, 0, v .. " export without pokemon/abilities.lua never installs the runtime species pack")
  bytes, err = exportParty(v, true)
  T.check(bytes ~= nil, v .. " mons carrying abilityNum export without pokemon/abilities.lua (" .. tostring(err) .. ")")
  c = bytes and Gen3Save.forVersion(v).decode(bytes)
  for i, e in ipairs(EXPECT) do
    local m = c and c.party[i]
    T.eq(m and m.abilityNum, e[3], ("%s species %d personality %d keeps its own abilityNum"):format(v, e[1], e[2]))
  end
end

Pokemon.install = realInstall
print = realPrint
io.open = realOpen
T.finish("gen3_launcher_export_ability_f9")
