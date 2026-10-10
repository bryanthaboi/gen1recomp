-- engine/items/town_map.asm:325
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local GameVersion = require("src.core.GameVersion")
local PaletteFX = require("src.render.PaletteFX")
local SpriteRenderer = require("src.render.SpriteRenderer")
local TownMap = require("src.ui.TownMap")

local prevVersion, prevMode = GameVersion.get(), PaletteFX.mode
local realObp = SpriteRenderer.obpImage

local baked = {}
SpriteRenderer.obpImage = function(path, colors, group)
  baked[#baked + 1] = { path = path, colors = colors, group = group }
  return nil
end

local function game()
  return {
    data = {
      field = {
        townMap = { PALLET_TOWN = { x = 1, y = 2, name = "PALLET TOWN" } },
        playerSprites = { walk = "SPRITE_RED" },
      },
      sprites = { SPRITE_RED = { image = "assets/generated/sprites/red_walk.png" } },
      maps = {},
    },
    save = {},
    overworld = { map = { id = "PALLET_TOWN" } },
  }
end

for _, version in ipairs({ "red", "blue" }) do
  GameVersion.set(version)
  PaletteFX.setMode("ogred")
  baked = {}
  TownMap.new(game(), {})
  local bake
  for _, b in ipairs(baked) do
    if b.path == "assets/generated/sprites/red_walk.png" then bake = b end
  end
  check(bake ~= nil, version .. ": player marker baked")
  if bake then
    local want, group = PaletteFX.ogObjNormal()
    local base = PaletteFX.ogObjBase()
    eq(bake.group, group, version .. ": marker uses the rOBP0 $D0 bake")
    for i = 2, 4 do
      eq(table.concat(bake.colors[i], ","), table.concat(want[i], ","),
        version .. ": OBJ color " .. (i - 1))
    end
    eq(table.concat(bake.colors[2], ","), table.concat(base[1], ","),
      version .. ": OBJ color 1 is the white shade")
  end
end

SpriteRenderer.obpImage = realObp
GameVersion.set(prevVersion)
PaletteFX.setMode(prevMode)

T.finish("town map OG rOBP0 bug 2841")
