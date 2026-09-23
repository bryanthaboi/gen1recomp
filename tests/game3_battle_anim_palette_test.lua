package.path = "./?.lua;./?/init.lua;" .. package.path
local CACHE_ROOT = require("tests.game3_cache").rootOrSkip("game3_battle_anim_palette_test", "pokemon/battle_anims/pack.lua")

local passed, failed = 0, 0
local function check(cond, name)
  if cond then
    passed = passed + 1
  else
    failed = failed + 1
    print("[FAIL] " .. tostring(name))
  end
end

local HOME = os.getenv("HOME") or ""
local PRET = os.getenv("POKEFIRERED") or (HOME .. "/Documents/development/pokefirered")
local ROM = os.getenv("FIRERED_ROM") or (HOME .. "/Documents/development/decprep/Pokemon - Fire Red Version.gba")
local PACK = CACHE_ROOT .. "/pokemon/battle_anims/pack.lua"

local function read_file(p)
  local f = io.open(p, "rb")
  if not f then return nil end
  local d = f:read("*a")
  f:close()
  return d
end

local function be32(s, i)
  local a, b, c, d = s:byte(i, i + 3)
  return ((a * 256 + b) * 256 + c) * 256 + d
end

local function png_palette(path)
  local s = read_file(path)
  if not s then return nil end
  local i = 9
  while i < #s do
    local len = be32(s, i)
    local typ = s:sub(i + 4, i + 7)
    if typ == "PLTE" then
      local out = {}
      for k = 0, math.floor(len / 3) - 1 do
        local o = i + 8 + k * 3
        local r, g, b = s:byte(o, o + 2)
        out[k + 1] = math.floor(r / 8) + math.floor(g / 8) * 32 + math.floor(b / 8) * 1024
      end
      return out
    end
    i = i + 12 + len
  end
  return nil
end

local function jasc_palette(path)
  local s = read_file(path)
  if not s then return nil end
  local out, n = {}, 0
  for line in s:gmatch("[^\r\n]+") do
    n = n + 1
    local r, g, b = line:match("^(%d+) (%d+) (%d+)$")
    if n > 3 and r then
      out[#out + 1] = math.floor(r / 8) + math.floor(g / 8) * 32 + math.floor(b / 8) * 1024
    end
  end
  return out
end

local function same16(a, b)
  if not (a and b) then return false end
  for i = 1, 16 do
    if (a[i] or 0) ~= (b[i] or 0) then return false end
  end
  return true
end

print("=== battle anim palette / extraction ===")

local pack = dofile(PACK)
check(type(pack) == "table", "pack loads")

print("[test] 1. indexed tag sheets + palettes")
local Versions = require("src.import.gba.versions")
local nIdx, nPal = 0, 0
for i = 0, 288 do
  local name = Versions.ANIM_TAG_NAMES[i]
  local t = pack.tags[name]
  if t and t.idxFile and type(t.pal) == "table" and #t.pal == 16 then nIdx = nIdx + 1 end
  if pack.tagPals[name] then nPal = nPal + 1 end
end
check(nIdx >= 280, "every anim tag has an indexed sheet + 16-colour palette (" .. nIdx .. ")")
check(nPal == 289, "gBattleAnimPaletteTable exported for every tag (" .. nPal .. ")")
check(#pack.tagPals.MUSIC_NOTES_2 >= 48, "MUSIC_NOTES_2 keeps its extra palettes")
check(pack.tags.TAG_SMOKESCREEN and pack.tags.TAG_SMOKESCREEN.idxFile ~= nil, "Smokescreen impact sheet extracted")

-- pokefirered/graphics/battle_anims/sprites
for tag, file in pairs({ PROTECT = "protect.png", LOCK_ON = "lock_on.png", GUST = "gust.png",
    RAINBOW_RINGS = "rainbow_rings.png", MUSIC_NOTES = "music_notes.png" }) do
  local want = png_palette(PRET .. "/graphics/battle_anims/sprites/" .. file)
  if want then check(same16(pack.tags[tag].pal, want), tag .. " palette matches pret " .. file) end
end
local ice = jasc_palette(PRET .. "/graphics/battle_anims/sprites/ice_cube.pal")
if ice then check(same16(pack.tags.ICE_CUBE.pal, ice), "ICE_CUBE palette matches pret ice_cube.pal") end
local notes2 = jasc_palette(PRET .. "/graphics/battle_anims/sprites/music_notes_2.pal")
if notes2 then
  local ok = true
  for i = 1, 48 do if (pack.tagPals.MUSIC_NOTES_2[i] or 0) ~= (notes2[i] or 0) then ok = false end end
  check(ok, "MUSIC_NOTES_2 48-colour palette matches pret music_notes_2.pal")
end

print("[test] 2. named anim backgrounds")
local BG_PNG = {
  ATTRACT = "backgrounds/attract.png", SCARY_FACE_PLAYER = "backgrounds/scary_face.png",
  MORNING_SUN = "masks/light_beam.png", METAL_SHINE = "masks/metal_shine.png",
  CURE_BUBBLES = "masks/cure_bubbles.png", SURF_PLAYER = "backgrounds/water.png",
}
for _, key in ipairs({ "ATTRACT", "SCARY_FACE_PLAYER", "SCARY_FACE_OPPONENT", "MORNING_SUN", "METAL_SHINE",
    "CURE_BUBBLES", "CURSE", "FOG", "SANDSTORM", "SURF_PLAYER", "SURF_OPPONENT" }) do
  local e = pack.animBgs[key]
  check(e and e.file and e.idxFile and #e.pal == 16 and e.w >= 256 and e.h == 256, "anim BG extracted: " .. key)
  local png = BG_PNG[key]
  local want = png and png_palette(PRET .. "/graphics/battle_anims/" .. png)
  if want and e then check(same16(e.pal, want), key .. " palette matches pret " .. png) end
end
check(pack.animBgs.SURF_PLAYER.w == 512, "Surf wave is a 64x32 tilemap")
check(pack.animBgs.CURSE.pal[2] == 0x7FFF, "Curse mask index 1 is sRgbWhite")
check(same16(pack.animBgs.SANDSTORM.pal, pack.tagPals.FLYING_DIRT), "Sandstorm uses gBattleAnimSpritePal_FlyingDirt")
local muddy = jasc_palette(PRET .. "/graphics/battle_anims/backgrounds/water_muddy.pal")
if muddy then check(same16(pack.bgPals.MUDDY_WATER, muddy), "Muddy Water palette matches pret water_muddy.pal") end
local fogPal = jasc_palette(PRET .. "/graphics/weather/default.pal")
if fogPal then check(same16(pack.animBgs.FOG.pal, fogPal), "Fog uses gDefaultWeatherSpritePalette") end
for id = 0, 26 do
  local e = pack.animBgs[id]
  check(e and e.idxFile and #e.pal == 16, "table BG " .. id .. " indexed")
end

print("[test] 3. ROM addresses decode to pret tilemaps")
local romf = io.open(ROM, "rb")
if romf then
  romf:close()
  local FileIO = require("src.import.gba.file_io")
  local Rom = require("src.import.gba.rom")
  local Lz77 = require("src.import.gba.lz77")
  local rom = Rom.open(FileIO.makeImports(ROM, "41cb23d8dccc8ebd7c649cd8fbb58eeace6e2fdc", "firered"), "firered")
  local function lz(off)
    local ok, b = pcall(Lz77.decompress, function(j) return rom:get(j) end, off)
    return ok and b or nil
  end
  local BIN = {
    ATTRACT = "backgrounds/attract.bin", SCARY_FACE_PLAYER = "backgrounds/scary_face_player.bin",
    SCARY_FACE_OPPONENT = "backgrounds/scary_face_opponent.bin", MORNING_SUN = "masks/light_beam.bin",
    METAL_SHINE = "masks/metal_shine.bin", CURE_BUBBLES = "masks/cure_bubbles.bin", CURSE = "masks/curse.bin",
    FOG = "backgrounds/fog.bin", SANDSTORM = "backgrounds/sandstorm_brew.bin",
    SURF_PLAYER = "backgrounds/water_player.bin", SURF_OPPONENT = "backgrounds/water_opponent.bin",
  }
  for key, bin in pairs(BIN) do
    local want = read_file(PRET .. "/graphics/battle_anims/" .. bin)
    local got = lz(Versions.BATTLE_ANIMS.named_bgs[key].map)
    local ok = want and got and #want == Lz77.len(got)
    if ok then
      for i = 1, #want do
        if want:byte(i) ~= got[i] then ok = false break end
      end
    end
    if want then check(ok, key .. " tilemap at ROM matches pret " .. bin) end
  end
  rom:clearCache()
else
  print("[skip] no ROM; address checks skipped")
end

print("[test] 4. palette runtime")
local AnimPal = require("src.core.game3.battle.anim_pal")
AnimPal.reset(pack)
AnimPal.setPack(pack)
-- pokefirered/src/palette.c:779
check(AnimPal.blendColor(0x0000, 8, 0x7FFF) == AnimPal.pack(15, 15, 15), "BlendPalette halfway to white")
check(AnimPal.blendColor(AnimPal.pack(31, 10, 0), 3, 0) == AnimPal.pack(25, 8, 0), "BlendPalette uses arithmetic >> 4")
local fin = AnimPal.resolve({ [0] = 0, AnimPal.pack(31, 31, 31) }, { affine = { m = -1, r = 1, g = 1, b = 1 } })
check(fin[1] == 0, "invert via affine state")
fin = AnimPal.resolve({ [0] = 0, AnimPal.pack(30, 0, 0) }, { gray = true })
check(fin[1] == AnimPal.pack(10, 10, 10), "greyscale is (r+g+b)/3")

local Anim = require("src.core.game3.battle.anim")
local AnimTasks = require("src.core.game3.battle.anim_tasks")
local AnimSprites = require("src.core.game3.battle.anim_sprites")
local AnimCallbacks = require("src.core.game3.battle.anim_callbacks")
Anim.reset({ headless = false })
Anim.loadPack(pack)
local vm = Anim.vm()
vm:setBattlers("player", "enemy")
AnimPal.markLoaded("PROTECT", true)
local base = AnimPal.unfadedOf("PROTECT")
local before = {}
for i = 0, 15 do before[i] = base[i] end

-- pokefirered/src/battle_anim_effects_1.c:4006
local s = AnimSprites.acquire({ x = 0, y = 0, tag = "PROTECT", callback = AnimCallbacks.get("Protect") })
s._args, s._vm, s._op = { 0, 0, 90 }, vm, { animBattler = "attacker", subpriority = 2 }
for i = 0, 7 do vm.args[i] = ({ 0, 0, 90 })[i + 1] or 0 end
pcall(s.callback, s)
for _ = 1, 4 do AnimSprites.update() end
local f = AnimPal.fadedOf("PROTECT")
check(f[1] == before[3] and f[7] == before[2], "Protect rotates faded indices 1..7 (two steps)")
check(AnimPal.unfadedOf("PROTECT")[1] == before[1], "Protect leaves unfaded palette intact")
AnimSprites.reset()

-- pokefirered/src/battle_anim_effects_1.c:5289
AnimPal.markLoaded("MUSIC_NOTES", true)
local t = AnimTasks.spawn("MusicNotesRainbowBlend", 2, {}, vm)
AnimTasks.update(vm)
check(AnimPal.isLoaded("BENT_SPOON") and AnimPal.fadedOf("BENT_SPOON")[1] == 0x7FFF, "rainbow allocates BENT_SPOON palette")
check(AnimPal.fadedOf("LARGE_FRESH_EGG")[5] == AnimPal.pack(12, 22, 31), "rainbow writes LARGE_FRESH_EGG index 5")
AnimTasks.spawn("MusicNotesClearRainbowBlend", 2, {}, vm)
AnimTasks.update(vm)
check(not AnimPal.isLoaded("SPHERE_TO_CUBE"), "clear frees the rainbow palettes")

-- pokefirered/src/battle_anim_water.c:626
AnimPal.markLoaded("RAINBOW_RINGS", true)
local rr = AnimPal.unfadedOf("RAINBOW_RINGS")
local r1, r2 = rr[1], rr[2]
for i = 0, 7 do vm.args[i] = 0 end
vm.args[0] = 6
AnimTasks.spawn("RotateAuroraRingColors", 2, { 6 }, vm)
for _ = 1, 4 do AnimTasks.update(vm) end
check(AnimPal.fadedOf("RAINBOW_RINGS")[1] == r2 and AnimPal.fadedOf("RAINBOW_RINGS")[8] == r1, "Aurora ring colours rotate 1..8")

-- pokefirered/src/battle_anim_effects_3.c:1362
AnimPal.bgLoad("bg", 3)
local bg = {}
for i = 0, 15 do bg[i] = AnimPal.bgColors("bg")[i] end
vm.args[7] = 0
local ps = AnimTasks.spawn("SetPsychicBackground", 2, {}, vm)
for _ = 1, 5 do AnimTasks.update(vm) end
check(AnimPal.bgColors("bg")[1] == bg[11] and AnimPal.bgColors("bg")[2] == bg[1], "Psychic BG rotates BG palette 1..11")
vm.args[7] = -1
AnimTasks.update(vm)
check(not ps.active, "SetPsychicBackground ends on arg7 0xFFFF")

-- pokefirered/src/battle_anim_status_effects.c:376
AnimPal.markLoaded("ICE_CUBE", true)
local ic = AnimPal.unfadedOf("ICE_CUBE")
local c13, c14 = ic[13], ic[14]
local cube = AnimTasks.spawn("FrozenIceCube", 2, {}, vm)
for _ = 1, 1 + 10 + 18 do AnimTasks.update(vm) end
check(cube._cube and cube._cube.eva == 9, "ice cube fades in to eva 9")
check(AnimPal.fadedOf("ICE_CUBE")[13] == c14, "ice cube rotates palette 13..15")
local n = 0
while cube.active and n < 200 do AnimTasks.update(vm) n = n + 1 end
check(not cube.active, "FrozenIceCube completes")

print("[test] 5. g5 BG tasks run every pack script")
local G5 = require("src.core.game3.battle.anim_port.g5_tasks")
local want = {}
for k in pairs(G5) do want[k] = true end
local errs = {}
local rawPrint = print
print = function(...)
  local line = table.concat({ ... }, " ")
  if line:find("%[battle%.anim%]") then errs[#errs + 1] = line end
end
local ran = 0
for _, kind in ipairs({ "moves", "general" }) do
  for id, ops in pairs(pack[kind]) do
    local hit = false
    local function scan(list, seen)
      for _, op in ipairs(list or {}) do
        local nm = tostring(op.task or ""):gsub("^AnimTask_", "")
        if op.op == "createvisualtask" and want[nm] then hit = true end
        for _, k in ipairs({ "label", "label1", "label2" }) do
          local l = op[k]
          if l and pack.labels[l] and not seen[l] then seen[l] = true scan(pack.labels[l], seen) end
        end
      end
    end
    scan(ops, {})
    if hit then
      for _, atk in ipairs({ "player", "enemy" }) do
        vm.headless = false
        vm:launch(ops, { attackerSide = atk, targetSide = atk == "player" and "enemy" or "player",
          attackerSpecies = 6, targetSpecies = 9 })
        local fr = 0
        while vm.active and fr < 3000 do vm:update(1 / 60) fr = fr + 1 end
        check(not vm.active, "terminates: " .. kind .. ":" .. id .. " " .. atk)
        ran = ran + 1
      end
    end
  end
end
print = rawPrint
check(ran >= 20, "ran g5 task scripts (" .. ran .. ")")
check(#errs == 0, "no runtime errors: " .. tostring(errs[1]))

print(string.format("game3_battle_anim_palette: %d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
