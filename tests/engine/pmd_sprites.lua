package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Ax = require("src.import.pmd.AxSprites")
local Pmd = require("src.import.pmd.PmdImport")
local Sprite = require("src.import.pmd.Sprite")
local Importers = require("src.import.Importers")
local AssetPacks = require("src.mods.AssetPacks")
local Writer = require("src.import.LuaWriter")

T.eq(Pmd.COUNT, 423, "every monster and form is catalogued")
T.check(Importers.validateDescriptor(Importers.get("pmd_red")), "launcher descriptor validates")
T.eq(Pmd.identify("bad"), nil, "wrong ROM size rejected")
local _, _, _, _, ptr = Ax.reader(string.rep("\0", 16))
T.check(not pcall(ptr, 0), "non-ROM pointer rejected")
T.check(not pcall(Ax.read, "SIRO", 0, 1, 0, 0), "truncated SIRO rejected")

local function draw(parts, tiles)
  local pixels = {}
  Ax.drawPose({ parts = parts, tiles = tiles }, function(x, y, c) pixels[y * 1000 + x] = c end)
  return pixels
end
local part = { x = 0, y = 0, w = 8, h = 8, tile = 0 }
local tiles = string.char(0x21) .. string.rep("\0", 30) .. string.char(0x43)
local p = draw({ part }, tiles)
T.eq(p[0], 1, "low nibble is left pixel")
T.eq(p[1], 2, "high nibble is right pixel")
T.eq(p[2], nil, "color zero stays transparent")
part.flipX, part.flipY = true, true
p = draw({ part }, tiles)
T.eq(p[0], 4, "both OAM flips applied")
T.eq(p[7007], 1, "flipped opposite corner")
part.flipX, part.flipY = false, false
p = draw({ part, { x = 0, y = 0, w = 8, h = 8, tile = 1 } },
  tiles .. string.rep(string.char(0x55), 32))
T.eq(p[0], 1, "earlier OAM piece wins overlap")
T.eq(p[2], 5, "transparent pixels reveal later OAM piece")

do
  local bytes = {}
  for i = 1, 2048 do bytes[i] = 0 end
  local function u16(at, value)
    value = value % 65536
    bytes[at + 1], bytes[at + 2] = value % 256, math.floor(value / 256)
  end
  local function u32(at, value) u16(at, value % 65536); u16(at + 2, math.floor(value / 65536)) end
  local function ptr(at, value) u32(at, value + 0x8000000) end
  for i = 1, 4 do bytes[i] = ("SIRO"):byte(i) end
  ptr(4,16); ptr(16,64); ptr(20,68); u32(24,1); ptr(28,112)
  ptr(64,160); ptr(68,80); ptr(112,128)
  for i = 0, 7 do ptr(80 + i * 4,208) end
  ptr(128,256); u32(132,64)
  u16(160,0); bytes[164] = 251; u16(164,512); u16(166,256); u16(168,0x3C00)
  u16(170,65535); bytes[174] = 5; u16(174,512); u16(176,1280); u16(178,0x6C01)
  u16(180,65535); u16(182,65535)
  bytes[209] = 8; u16(210,0); u16(212,-2); u16(214,3)
  for i = 257, 288 do bytes[i] = 0x11 end
  for i = 289, 320 do bytes[i] = 0x22 end
  bytes[512 + 6 * 64 + 2 * 4 + 1] = 123
  local raw = {}
  for i, value in ipairs(bytes) do raw[i] = string.char(value) end
  local sprite = Ax.read(table.concat(raw), 0, 1, 512, 3)
  local color, palette
  Ax.drawPose(sprite.poses[1], function(_, _, c, pal) color, palette = c, pal end)
  T.eq(color, 2, "per-piece depth controls overlap")
  T.eq(palette, 6, "fixed-palette flag overrides species palette")
  T.eq(sprite.palettes[6][2][1], 123, "PMD palette is RGB888")
  T.eq(sprite.sequences[1][1][3], -2, "signed animation x offset decoded")
  T.eq(sprite.sequences[1][1][4], 3, "animation y offset decoded")
end

local meta = { animations = { {1,1,2,2,1,1,2,2} },
  sequences = { {{1,2,0,0},{2,3,4,-1}}, {{3,1,0,0}} } }
T.eq(Sprite.frame(meta, 0, "down", 2)[1], 2, "durations select next pose")
T.eq(Sprite.frame(meta, 0, "down", 5)[1], 1, "animation loops at total duration")
T.eq(Sprite.frame(meta, 0, "right", 0)[1], 3, "east has its own direction")
T.eq(Sprite.frame(meta, 0, "down", 2)[3], 4, "animation offset preserved")

do
  local bytes = Writer.encode(meta)
  local entry = { file = "pikachu.png", size = 4, sprite = { frameWidth = 32 },
    metadata = { file = "pikachu.lua", size = #bytes } }
  local pack = { format = 1, importer = "pmd_red", pack = "sprites", kind = "sprite",
    version = "1.0.0", source = { md5 = "test" }, entries = { pikachu = entry } }
  local files = { ["asset_packs/pmd_red/sprites/pack.lua"] = Writer.encode(pack),
    ["asset_packs/pmd_red/sprites/pikachu.lua"] = bytes }
  local fs = T.sdk.memfs(files)
  local api = AssetPacks.new({ required_assets = {{ importer = "pmd_red", pack = "sprites" }} }, fs)
  T.eq(api:metadata("pmd_red", "sprites", "pikachu").sequences[1][2][1], 2,
    "declared mod can read animation metadata")
  T.eq(api:metadata("lttp", "sprites", "pikachu"), nil, "undeclared metadata refused")
  T.eq(api:metadata("pmd_red", "sprites", "absent"), nil, "unknown metadata entry refused")
  local copied = api:entry("pmd_red", "sprites", "pikachu")
  copied.sprite.frameWidth = 999
  T.eq(api:entry("pmd_red", "sprites", "pikachu").sprite.frameWidth, 32, "layout metadata is copied")
  files["asset_packs/pmd_red/sprites/pikachu.lua"] = "bad"
  T.eq(api:metadata("pmd_red", "sprites", "pikachu"), nil, "truncated metadata refused")
  entry.metadata.file = "../escape.lua"
  T.check(not Importers.validatePack(pack), "metadata traversal refused")
  entry.metadata = { file = "evil.exe", size = 3 }
  T.check(not Importers.validatePack(pack), "metadata extension checked")
  entry.metadata = { file = "pikachu.lua", size = Importers.MAX_ENTRY_BYTES + 1 }
  T.check(not Importers.validatePack(pack), "oversized metadata refused")
end

local romPath = os.getenv("PMD_ROM")
if romPath then
  local f = assert(io.open(romPath, "rb")); local rom = f:read("*a"); f:close()
  T.check(Pmd.identify(rom) ~= nil, "real supported ROM identified")
  local count, poseCount = 0, 0
  for i = 1, Pmd.COUNT do
    local s = Pmd.readPokemon(rom, i)
    for _, pose in ipairs(s.poses) do Ax.drawPose(pose, function() end) end
    count, poseCount = count + 1, poseCount + #s.poses
  end
  T.eq(count, 423, "all real ROM sprites decode and composite")
  print("Verified " .. poseCount .. " real ROM poses")
end
T.finish("pmd_sprites")
