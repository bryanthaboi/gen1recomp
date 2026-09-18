local mod = ...
local build = assert(load(assert(mod:read("town.lua")), "@lttp/town.lua"))()
local player = assert(mod.packs:entry("lttp", "sprites", "player"))
local town = assert(mod.packs:entry("lttp", "tiles", "kakariko"))
local base = assert(mod.content.tilesets:get("OVERWORLD"))
local map = assert(mod.content.maps:get("PALLET_TOWN"))

-- Bank00.asm $9396/$95F4 DMA tables; player_oam.asm $85FB, $8000.
local function frame(head, body, flip, headY, headX)
  local out = {}
  local function part(tile, dx, dy)
    for y = 0, 1 do
      for x = 0, 1 do
        out[#out + 1] = { tile = tile + y * 16 + x,
          dx = dx + (flip and 1 - x or x) * 8, dy = dy + y * 8,
          flipX = flip or false }
      end
    end
  end
  part(body, 0, 8)
  part(head, headX or 0, headY or 0)
  return out
end

local tileset, mapBlocks, border = build(mod, base, map,
  "asset_packs/lttp/tiles/" .. town.file)
mod.content.tilesets:register("LTTP_PALLET", tileset)
mod.content.maps:patch("PALLET_TOWN", {
  tileset = "LTTP_PALLET", blocks = mapBlocks, borderBlock = border,
  outdoor = true,
})
local waterTilesets = mod.content.field:get("waterTilesets") or {}
waterTilesets[#waterTilesets + 1] = "LTTP_PALLET"
mod.content.field:patch("waterTilesets", waterTilesets)
mod.content.sprites:patch("SPRITE_RED", {
  image = "asset_packs/lttp/sprites/" .. player.file,
  frames = 6, walker = true, frameWidth = 16, frameHeight = 24,
  frameColumns = 1, frameOffset = 0,
  anchorX = 8, anchorY = 24,
  cellWidth = 8, cellHeight = 8, cellColumns = 16,
  cells = {
    frame(2, 38), frame(4, 66), frame(0, 32, true, 0, 1),
    frame(2, 42, false, -1), frame(4, 64, false, -1),
    frame(0, 34, true, -1, 1),
  },
  trueColor = true,
})
mod.exports.binding = { player = "player", town = "kakariko" }
mod.log:info("Link assembled from head/body cells; Pallet retains all three entrances")
