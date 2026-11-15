package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Schemas = require("src.mods.Schemas")

local f = assert(io.open("src/import/RomExtractorGen2.lua", "rb"))
local src = f:read("*a")
f:close()

local body = src:match("function RomExtractorGen2:extractPalettes%(%)(.-)\nend\n")
T.check(body ~= nil, "found RomExtractorGen2:extractPalettes")
local block = body and body:match("\n  local data = {\n(.-)\n  }\n  self:write%(\"palettes\", data%)")
T.check(block ~= nil, "found the table extractPalettes writes as palettes")

local keys = {}
for line in ((block or "") .. "\n"):gmatch("([^\n]*)\n") do
  local key = line:match("^    ([%a_][%w_]*)%s*=")
  if key then keys[#keys + 1] = key end
end
T.check(#keys >= 10, ("read %d palettes cache keys"):format(#keys))

local spec = Schemas.shapeFor("palettes", Schemas.REGISTRIES.palettes, 2)
local typed = spec and spec.keys or {}
for _, key in ipairs(keys) do
  T.check(typed[key] ~= nil,
    ("palettes cache key %s has a type in Schemas palettes gen2Keys"):format(key))
end

T.finish("gate_gen2_palette_keys")
