-- engine/battle/animations.asm:248-260, :2582-2628
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local AnimPlayer = require("src.battle.AnimPlayer")
local BattleState = require("src.battle.BattleState")
local PaletteFX = require("src.render.PaletteFX")
local GameVersion = require("src.core.GameVersion")

local data = {
  moveAnims = {
    SHAKE_ANIM = { seq = { { subanim = "SHAKE", tileset = 0, delay = 4 } } },
    TOSS_ANIM = { seq = { { subanim = "TOSS", tileset = 0, delay = 2 } } },
  },
  subanims = {
    SHAKE = { type = "NORMAL", blocks = {
      { block = "BALL", coord = "REST", mode = 4 },
      { block = "BALL", coord = "REST", mode = 4 },
    } },
    TOSS = { type = "NORMAL", blocks = {
      { block = "BALL", coord = "REST", mode = 4 },
      { block = "BALL", coord = "REST", mode = 4 },
      { block = "BALL", coord = "REST", mode = 4 },
    } },
  },
  frameBlocks = {
    BALL = { { x = 0, y = 0, tile = 2 }, { x = 8, y = 0, tile = 3 },
             { x = 0, y = 8, tile = 4, pal1 = true } },
  },
  baseCoords = { REST = { x = 120, y = 56 } },
}

local function obps(sprites)
  local out = {}
  for i, s in ipairs(sprites or {}) do out[i] = s.obp end
  return table.concat(out, ",")
end

local p = AnimPlayer.new(data)
p:start("SHAKE_ANIM", true, { shakes = 3 })
local last = p.steps[#p.steps]
T.eq(obps(last.sprites), "f0,f0,obp1",
  "the shake frames play under wAnimPalette")
local rest = p:finalSprites()
T.eq(obps(rest), "e4,e4,obp1",
  "the resting ball wears the popped rOBP0, rOBP1 tiles untouched")
T.eq(obps(last.sprites), "f0,f0,obp1",
  "finalSprites copies; the compiled step keeps its tags")
T.eq(rest[1].x, 120, "resting ball keeps its OAM x")
T.eq(rest[1].y, 56, "resting ball keeps its OAM y")
T.eq(rest[2].tile, 3, "resting ball keeps its tiles")

p:start("TOSS_ANIM", true, { ball = "MASTER_BALL" })
local flick = p.steps[#p.steps].sprites
T.check(flick[1].obp == "f0" or flick[1].obp == "f0x",
  "a Master Ball toss frame carries the $f0/$cc flicker tag")
T.eq(obps(p:finalSprites()), "e4,e4,obp1",
  "the flicker tag also restores to $e4 once the row ends")

local prevVersion, prevMode = GameVersion.get(), PaletteFX.mode
local zone = { { 255, 255, 240 }, { 208, 184, 144 }, { 144, 112, 80 }, { 48, 48, 48 } }
local fake = { zoneColorsAt = function() return zone end }
local function shades(obp)
  local out = BattleState.animSpriteColors(fake, { obp = obp, x = 120, y = 56 }, 112, 40)
  local idx = {}
  for i = 1, 3 do
    local c = out[i]
    for j = 1, 4 do
      if math.floor(c[1] * 255 + 0.5) == zone[j][1] then idx[i] = j - 1 end
    end
  end
  return table.concat(idx, ",")
end
for _, v in ipairs({ { "yellow", "ogred" }, { "red", "gbc" }, { "blue", "gbc" } }) do
  GameVersion.set(v[1])
  PaletteFX.setMode(v[2])
  T.eq(shades("f0"), "0,3,3", v[1] .. "/" .. v[2] .. " $f0 maps to shades 0,3,3")
  T.eq(shades("e4"), "1,2,3", v[1] .. "/" .. v[2] .. " $e4 maps to the zone's shades 1,2,3")
end
GameVersion.set(prevVersion)
PaletteFX.setMode(prevMode)

T.finish("caught ball rOBP0 restore")
