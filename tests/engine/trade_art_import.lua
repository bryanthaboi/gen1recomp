-- The trade cinematic's Game Boy / cable / ball / bubble art must come out
-- of the ROM importer, not just the developer-only Python path (#750).
-- RomExtractor:extractTradeArt reads five symbols -- gfx/trade.asm
-- TradingAnimationGraphics(+2), engine/gfx/mon_icons.asm TradeBubbleIconGFX,
-- and the data/tilemaps.asm GameBoyTiles / LinkCableTiles id lists -- so
-- every shipped manifest has to carry them, the manifest generator has to
-- keep them on a regen, and RomImporter has to force pre-#750 caches to
-- re-import.  Addresses below were byte-verified against the canonical
-- Red/Blue/Yellow ROMs (each payload occurs exactly once) and match
-- pokered.sym / pokeblue.sym.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

local function readFile(path)
  local handle = io.open(path, "r")
  if not handle then return nil end
  local text = handle:read("*a")
  handle:close()
  return text
end

-- Red and Blue place the trade art identically; Yellow shifted it.
local RED_BLUE = {
  GameBoyTiles = { 30, 23584 },              -- 1e:5c20
  LinkCableTiles = { 30, 23632 },            -- 1e:5c50
  TradeBubbleIconGFX = { 28, 23129 },        -- 1c:5a59
  TradingAnimationGraphics = { 14, 27070 },  -- 0e:69be
  TradingAnimationGraphics2 = { 14, 27854 }, -- 0e:6cce
}
local YELLOW = {
  GameBoyTiles = { 30, 23932 },
  LinkCableTiles = { 30, 23980 },
  TradeBubbleIconGFX = { 28, 23302 },
  TradingAnimationGraphics = { 14, 27240 },
  TradingAnimationGraphics2 = { 14, 28024 },
}

local MANIFESTS = {
  { "tools/rom_manifest.json", RED_BLUE },
  { "tools/rom_manifest_blue.json", RED_BLUE },
  { "tools/rom_manifest_yellow.json", YELLOW },
}

for _, spec in ipairs(MANIFESTS) do
  local path, expected = spec[1], spec[2]
  local text = readFile(path)
  T.check(text ~= nil, path .. " is readable")
  if text then
    for name, location in pairs(expected) do
      local bank, addr = text:match(
        '"' .. name .. '"%s*:%s*%[%s*(%d+)%s*,%s*(%d+)%s*%]')
      T.eq(bank, tostring(location[1]),
        path .. ": " .. name .. " bank")
      T.eq(addr, tostring(location[2]),
        path .. ": " .. name .. " address")
    end
  end
end

-- the manifests are generated, so the generator has to keep asking for the
-- symbols or the next regen silently drops the trade art again
local gen = readFile("tools/make_rom_manifest.py")
T.check(gen ~= nil, "tools/make_rom_manifest.py is readable")
if gen then
  for name in pairs(RED_BLUE) do
    T.check(gen:find('"' .. name .. '"', 1, true) ~= nil,
      "a regenerated manifest keeps " .. name)
  end
end

-- extractTradeArt exists, extractField calls it, and the field table
-- publishes the paths the same way the Python path's field.py does, so
-- TradeAnim's `game.data.field.tradeArt` lookup lands on both build paths
local extractor = readFile("src/import/RomExtractor.lua")
T.check(extractor ~= nil, "src/import/RomExtractor.lua is readable")
if extractor then
  T.check(extractor:find("function RomExtractor:extractTradeArt", 1, true) ~= nil,
    "RomExtractor has extractTradeArt")
  T.check(extractor:find("self:extractTradeArt()", 1, true) ~= nil,
    "extractField runs it")
  T.check(extractor:find("data.tradeArt = tradeArt", 1, true) ~= nil,
    "field.lua publishes tradeArt")
end

-- a cache imported before #750 has none of the art; listing one of the
-- files in the engine-owned cache contract is what makes it re-import
local contract = readFile("src/import/CacheContract.lua")
T.check(contract ~= nil, "src/import/CacheContract.lua is readable")
if contract then
  local required = contract:match("CacheContract.REQUIRED_FILES = {(.-)\n}")
  T.check(required ~= nil, "CacheContract.REQUIRED_FILES parses")
  T.check(required ~= nil and required:find(
      '"assets/generated/trade/game_boy.png"', 1, true) ~= nil,
    "cache contract makes pre-#750 caches re-import the trade art")
end

T.finish("trade art import")
