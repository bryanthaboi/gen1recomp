package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("yellow jessie/james advanced obp #3071")
local check, eq = S.check, S.eq

local GameVersion = require("src.core.GameVersion")
local PaletteFX = require("src.render.PaletteFX")

local prevVer = GameVersion.get()
local prevMode = PaletteFX.mode

GameVersion.set("yellow")
PaletteFX.setMode("redpp")

local function obp(idx, seed)
  return PaletteFX.spriteObp({ source = "ROM:SpriteSheetPointerTable[" .. idx .. "]" }, seed)
end

local seeds = {
  "MT_MOON_B2F_obj_2", "MT_MOON_B2F_obj_6", "ROCKET_HIDEOUT_B4F_obj_2",
  "ROCKET_HIDEOUT_B4F_obj_3", "POKEMON_TOWER_7F_obj_1", "POKEMON_TOWER_7F_obj_2",
  "SILPH_CO_11F_obj_6", "SILPH_CO_11F_obj_7", "x", "",
}

for _, seed in ipairs(seeds) do
  local c, g = obp(68, seed)
  eq(g, 0, "Jessie SPR_PAL_ORANGE for seed " .. seed)
  eq(c and c[3][1], 255, "Jessie dark shade is red for seed " .. seed)
  local c2, g2 = obp(69, seed)
  eq(g2, 1, "James SPR_PAL_BLUE for seed " .. seed)
  eq(c2 and c2[3][3], 255, "James dark shade is blue for seed " .. seed)
  for idx = 65, 67 do
    local cm, gm = obp(idx, seed)
    eq(gm, 8, "sprite " .. idx .. " pink group for seed " .. seed)
    eq(cm and table.concat(cm[2], ","), "255,123,148", "sprite " .. idx .. " light shade is PINKMON for seed " .. seed)
    eq(cm and table.concat(cm[3], ","), "255,0,49", "sprite " .. idx .. " dark shade is PINKMON for seed " .. seed)
  end
end

local pink = PaletteFX.worldPack().spritePalettes[8]
eq(pink, require("data.palettes_gbc").palettes.PINKMON, "Yellow pink OBJ group is the pack's PINKMON ramp")
for g = 0, 7 do
  local other = PaletteFX.worldPack().spritePalettes[g]
  check(pink and other and table.concat(other[3], ",") ~= table.concat(pink[3], ","),
    "pink dark shade differs from OBJ group " .. g)
end

local _, rocket = obp(23, "MT_MOON_B2F_obj_1")
check(rocket ~= 0 and rocket ~= 1, "Jessie/James differ from SPRITE_ROCKET")

for idx = 60, 69 do
  check(type(PaletteFX.worldPack().spriteAssignment[idx]) == "number",
    "Yellow character sprite " .. idx .. " has a fixed group")
end

GameVersion.set("red")
local _, redFairy = obp(55, "PokemonFanClub_obj_3")
eq(redFairy, 0, "Red Clefairy keeps SPR_PAL_ORANGE")
check(PaletteFX.worldPack().spritePalettes[8] == nil, "Red has no pink OBJ group")

local Game = require("src.core.Game")
local GbcPalette = require("src.render.GbcPalette")
local OW = os.getenv("F8_OVERWORLD_SOURCE")
  and assert(loadfile(os.getenv("F8_OVERWORLD_SOURCE")))()
  or require("src.world.OverworldController")
local prevData = Game.data
Game.data = { maps = {} }
OW._setGameForTest(Game)

local function fadeState()
  return setmetatable({
    map = { id = "PEWTER_POKECENTER", def = { tileset = "POKECENTER" } },
    neighbors = {}, player = { cellY = 4 },
  }, { __index = OW })
end

local function rgbKey(c, scale)
  scale = scale or 1
  return string.format("%d,%d,%d", math.floor(c[1] * scale + 0.5),
    math.floor(c[2] * scale + 0.5), math.floor(c[3] * scale + 0.5))
end

local function dstFor(u, color)
  local want = rgbKey(color)
  for i = 1, u.count do
    if rgbKey(u.src[i], 255) == want then return u.dst[i] end
  end
end

local BYTES = { 0xE4, 0xF9, 0xFE, 0xFF, 0x90, 0x40 }

GameVersion.set("yellow")
local pinkObj = PaletteFX.worldPack().spritePalettes[8]
for _, byte in ipairs(BYTES) do
  local u = fadeState():warpFadeUniforms(byte)
  check(u and u.count > 0, string.format("Yellow warp fade table exists for byte %02X", byte))
  for shade = 2, 3 do
    local dst = u and pinkObj and dstFor(u, pinkObj[shade])
    local index = math.floor(byte / 4 ^ (shade - 1)) % 4 + 1
    eq(dst and rgbKey(dst, 255), pinkObj and rgbKey(pinkObj[index]),
      string.format("Yellow warp fade remaps PINKMON shade %d for byte %02X", shade, byte))
  end
end

for _, version in ipairs({ "red", "blue" }) do
  GameVersion.set(version)
  local w = PaletteFX.worldPack()
  for _, byte in ipairs(BYTES) do
    local u = fadeState():warpFadeUniforms(byte)
    local bg = {}
    for _, colors in ipairs(PaletteFX.worldGroupColors(Game.data, "POKECENTER", "PEWTER_POKECENTER", 4) or {}) do
      bg[#bg + 1] = colors
    end
    for group = 0, 7 do
      if w.spritePalettes[group] then bg[#bg + 1] = w.spritePalettes[group] end
    end
    local ref = GbcPalette.remapUniforms(bg, byte)
    local same = u and ref and u.count == ref.count
    for i = 1, same and u.count or 0 do
      same = same and rgbKey(u.src[i], 255) == rgbKey(ref.src[i], 255)
        and rgbKey(u.dst[i], 255) == rgbKey(ref.dst[i], 255)
    end
    check(same, string.format("%s warp fade table is BG plus OBJ groups 0-7 for byte %02X", version, byte))
    check(u and pinkObj and dstFor(u, pinkObj[3]) == nil,
      string.format("%s warp fade table has no PINKMON for byte %02X", version, byte))
  end
end

Game.data = prevData
PaletteFX.setMode(prevMode)
GameVersion.set(prevVer)

S.finish()
