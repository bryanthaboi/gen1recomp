local T = require("tests.harness")
local RomExtractorGen2 = require("src.import.RomExtractorGen2")

local function read(path)
  local f = assert(io.open(path, "rb"))
  local s = f:read("*a")
  f:close()
  return s
end

local source = read("src/import/RomExtractorGen2.lua")
local manifests = {}
for _, version in ipairs({ "gold", "silver", "crystal" }) do
  manifests[version] = read("tools/rom_manifest_" .. version .. ".json")
end

local guarded, lineNo = {}, 0
for line in (source .. "\n"):gmatch("(.-)\n") do
  lineNo = lineNo + 1
  local name = line:match("if%s+self%.symbols%[\"([^\"]+)\"%]")
    or line:match("=%s*self%.symbols%[\"([^\"]+)\"%]")
    or line:match("if%s+not%s+self%.symbols%[\"([^\"]+)\"%]")
  if name then guarded[#guarded + 1] = { name = name, line = lineNo } end
end

local everywhere = {}
for _, hit in ipairs(guarded) do
  local pattern = "\"" .. hit.name:gsub("%p", "%%%0") .. "\""
  local count = 0
  for _, text in pairs(manifests) do
    if text:find(pattern) then count = count + 1 end
  end
  if count == 3 then everywhere[#everywhere + 1] = hit.name .. ":" .. hit.line end
end
T.eq(#everywhere, 0, "no optional read of a symbol every Gen 2 manifest carries: "
  .. table.concat(everywhere, " "))

local direct, at = {}, 0
for line in (source .. "\n"):gmatch("(.-)\n") do
  at = at + 1
  if line:find("self.symbols", 1, true) and not line:find("^%s*%-%-")
      and not line:find("local location = self.symbols[name]", 1, true) then
    direct[#direct + 1] = tostring(at)
  end
end
T.eq(#direct, 0, "every symbol read goes through RomExtractorGen2:symbol: "
  .. table.concat(direct, " "))

local function stub(edition)
  return setmetatable({
    symbols = {},
    edition = edition,
    rom = { bytes = function() return {} end, byte = function() return 0 end },
    write2bpp = function() end,
    colors = function() return {} end,
    predefPal = function() return {} end,
    beginStage = function() end,
    tick = function() end,
    write = function() end,
    manifest = { constants = {} },
  }, { __index = RomExtractorGen2 })
end

local function errorsWith(fn, name)
  local ok, err = pcall(fn)
  return not ok and tostring(err):find(name, 1, true) ~= nil
end

T.check(errorsWith(function() stub("gold"):billsPcGfx() end, "PCMailGFX"),
  "billsPcGfx errors without PCMailGFX")
T.check(errorsWith(function() stub("gold"):extractMarts() end, "Marts"),
  "extractMarts errors without Marts")
T.check(errorsWith(function() stub("crystal"):monAnimTables(false) end,
  "required symbol is missing"), "crystal monAnimTables errors without its pointer tables")
T.eq(stub("gold"):monAnimTables(false), nil, "gold has no mon animation tables")

local function missing(edition, method, name)
  local ex = stub(edition)
  T.check(errorsWith(function() return ex[method](ex) end, name),
    edition .. " " .. method .. " errors without " .. name)
end
missing("gold", "readMagnetTrain", "MagnetTrainBGTiles")
missing("gold", "readRoamMons", "InitRoamMons")
missing("gold", "readRoamMaps", "RoamMaps")
missing("gold", "readTreeMons", "TreeMons")
missing("gold", "extractInitialEvents", "InitializeEventsScript")
missing("gold", "splashGfx", "GameFreakLogoGFX")
missing("crystal", "specialTilesetPalettes", "required symbol is missing")
missing("crystal", "readAsleepTreeMons", "AsleepTreeMons")
missing("crystal", "readBattleTowerText", "BattleTowerText")
do
  local ex = stub("gold")
  ex.symbols = { Marts = { 5, 0x4000 }, BargainShopData = { 5, 0x4100 } }
  ex.rom.word = function() return 0x4200 end
  T.check(errorsWith(function() ex:extractMarts() end, "DefaultMart"),
    "extractMarts errors without DefaultMart")
end

T.finish("Gen 2 extractor required symbols")
