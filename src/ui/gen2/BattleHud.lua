-- The battle HUD, drawn from the cart's own tiles.
--
-- The HUD is not lines and boxes an engine invents: it is tiles the cart loads
-- into fixed VRAM slots (engine/gfx/load_font.asm LoadBattleFontsHPBar /
-- LoadHPBar), placed at fixed tile coordinates.  Drawing it from those tiles is
-- what makes it align on the 8px grid by construction rather than by eye, and
-- it is why "HP:" looks like the cart's bold glyph instead of three font
-- letters.
--
--   FontBattleExtra      -> $60  "HP:" is $60/$61; the bar's cells are $62
--                                (empty) through $6a (8 pixels of fill), and
--                                $6b is the bar's right end cap
--   EnemyHPBarBorderGFX  -> $6c  4 tiles: $6d left side, $6f bottom left
--   HPExpBarBorderGFX    -> $73  6 tiles: $73 right side, $74 bottom left,
--                                $76 bottom side, $77 / $78 bottom right
--   ExpBarGFX            -> $55  9 exp-bar fill cells
--
-- The HP-bar cells are 2bpp: the bar's rule is shade 3 and its fill shades 1-2,
-- so they are coloured through palettes.hpBar (gfx/battle/hp_bar.pal) the same
-- way the cart colours PAL_BATTLE_BG_PLAYER_HP.  The two border sheets are
-- 1bpp and draw black.

local Assets = require("src.render.Assets")
local GbcPalette = require("src.render.GbcPalette")
local HpBar = require("src.battle.gen2.HpBar")

local BattleHud = {}
BattleHud.__index = BattleHud

-- Tile ids, so the arithmetic below reads as the ASM does.
local TILE_HP_LABEL = 0x60      -- and $61
local TILE_BAR_EMPTY = 0x62     -- $62..$6a is 0..8 pixels of fill
local TILE_BAR_END = 0x6b
local FIRST_BATTLE_EXTRA = 0x60

-- Enemy border sheet ($6c..$6f) and player border sheet ($73..$78).
local ENEMY_BORDER_FIRST = 0x6c
local PLAYER_BORDER_FIRST = 0x73
local TILE_ENEMY_LEFT = 0x6d
local TILE_ENEMY_BOTTOM_LEFT = 0x74   -- from the player sheet, per the ASM
local TILE_ENEMY_BOTTOM_RIGHT = 0x78
local TILE_BOTTOM_SIDE = 0x76
local TILE_PLAYER_RIGHT = 0x73
local TILE_PLAYER_BOTTOM_RIGHT = 0x77
local TILE_PLAYER_BOTTOM_LEFT = 0x6f

-- DrawEnemyHUDBorder's tail: ExpBarGFX's 9th tile, the caught mark
-- (engine/battle/trainer_huds.asm:143-152).
local TILE_CAUGHT = 0x5d

-- The ball icons StageBallTilesData stages, one per party slot
-- (engine/battle/trainer_huds.asm:47-99).
local TILE_BALL_NORMAL = 0x31
local TILE_BALL_STATUSED = 0x32
local TILE_BALL_FAINTED = 0x33
local TILE_BALL_EMPTY = 0x34
-- DrawPlayerPartyIconHUDBorder's corner (trainer_huds.asm:118-132), which is
-- DrawPlayerHUDBorder's with $77 swapped for $5c.
local TILE_PARTY_ICON_BOTTOM_RIGHT = 0x5c

BattleHud.PARTY_LENGTH = 6

function BattleHud.new(menuGfx, palettes)
  local self = setmetatable({}, BattleHud)
  self.gfx = menuGfx and menuGfx.battleHud or nil
  self.palettes = palettes
  self.images = {}
  self.quads = {}
  return self
end

function BattleHud:image(key)
  local path = self.gfx and self.gfx[key]
  if not path then return nil end
  local cached = self.images[path]
  if cached == nil then
    local ok, image = pcall(Assets.image, path)
    cached = ok and image or false
    self.images[path] = cached
  end
  return cached or nil
end

-- One 8x8 tile out of a horizontal strip, cached per (sheet, index).
function BattleHud:quad(image, index)
  local key = tostring(image) .. ":" .. index
  local quad = self.quads[key]
  if not quad then
    local w, h = image:getDimensions()
    quad = love.graphics.newQuad(index * 8, 0, 8, 8, w, h)
    self.quads[key] = quad
  end
  return quad
end

function BattleHud:available()
  return self:image("hpBar") ~= nil
end

-- The 4-colour palette the HP-bar cells draw with: white, the bar's own light
-- colour, the state's fill colour, black -- which is HPBarPals' two colours
-- bracketed the way every Gen 2 palette is.
function BattleHud:barColors(key, zero)
  local pal = self.palettes and self.palettes.hpBar and self.palettes.hpBar[key]
  if not pal then return nil end
  return {
    zero or { 255, 255, 255 },
    { pal[1][1], pal[1][2], pal[1][3] },
    { pal[2][1], pal[2][2], pal[2][3] },
    { 0, 0, 0 },
  }
end

-- Draw a run of tiles from a sheet whose first tile is `firstTile`, colouring
-- with `colors` when one is given.
function BattleHud:drawTile(key, firstTile, tile, tx, ty, colors, mirror)
  local image = self:image(key)
  if not image then return false end
  local index = tile - firstTile
  if index < 0 then return false end
  local G = love.graphics
  G.setColor(1, 1, 1, 1)
  local function body()
    if mirror then
      -- Flip in place: the origin moves a tile right and x scales by -1.
      G.draw(image, self:quad(image, index), tx * 8 + 8, ty * 8, 0, -1, 1)
    else
      G.draw(image, self:quad(image, index), tx * 8, ty * 8)
    end
  end
  -- home/fade.asm:35 (RotateThreePalettesRight)
  if GbcPalette.available() then
    GbcPalette.with(colors or GbcPalette.DMG_SHADES, body)
  else
    G.setColor(0, 0, 0, 1)
    body()
    G.setColor(1, 1, 1, 1)
  end
  return true
end

-- Six bar cells at (tx, ty), no label and no end cap.
--
-- This is DrawBattleHPBar itself: the party menu calls it with `ld d, $6` and
-- `ld b, $0` (PlacePartyHPBar), so a party row's bar is literally the battle
-- HUD's bar minus the "HP:" prefix -- same tiles, same HPBarPals colour, same
-- one-pixel-at-a-time fill.  Sharing this method is what keeps the two screens
-- from ever disagreeing about how full a bar looks.
function BattleHud:drawBar(hp, maxHp, tx, ty, zero, pixels)
  pixels = pixels or HpBar.pixels(hp, maxHp)
  local colors = self:barColors(HpBar.palette(pixels), zero)
  for cell = 0, HpBar.LENGTH_TILES - 1 do
    local remaining = pixels - cell * 8
    local filled = math.max(0, math.min(8, remaining))
    self:drawTile("hpBar", FIRST_BATTLE_EXTRA, TILE_BAR_EMPTY + filled,
      tx + cell, ty, colors)
  end
  return tx + HpBar.LENGTH_TILES
end

-- "HP:" plus the six bar cells plus the end cap, starting at tile (tx, ty).
-- Returns the column just past the assembly (tx + 9), so the caller can put the
-- frame's vertical stub there.
-- `zero` overrides colour 0: the stats screen puts the page tint there
-- (engine/gfx/color.asm:386-390).  #1693
function BattleHud:drawHpBar(hp, maxHp, tx, ty, zero, pixels)
  pixels = pixels or HpBar.pixels(hp, maxHp)
  local colors = self:barColors(HpBar.palette(pixels), zero)
  -- The "HP:" badge sits inside the bar's own attrmap region, so it wears the
  -- HP palette too: its background is HPBarPals' light colour (the cream the
  -- cart shows) and its letters are black.  Drawing it white-on-black was the
  -- one place this HUD invented a colour instead of reading one.
  self:drawTile("hpBar", FIRST_BATTLE_EXTRA, TILE_HP_LABEL, tx, ty, colors)
  self:drawTile("hpBar", FIRST_BATTLE_EXTRA, TILE_HP_LABEL + 1, tx + 1, ty,
    colors)
  self:drawBar(hp, maxHp, tx + 2, ty, zero, pixels)
  self:drawTile("hpBar", FIRST_BATTLE_EXTRA, TILE_BAR_END,
    tx + 2 + HpBar.LENGTH_TILES, ty, colors)
  return tx + 3 + HpBar.LENGTH_TILES
end

-- The exp bar, transcribed from FillInExpBar / PlaceExpBar rather than guessed
-- from the tile art:
--
--   FillInExpBar starts at (10,11), adds 7 to reach the RIGHTMOST tile, then
--   PlaceExpBar writes 8 tiles walking LEFT (ld [hld]):
--     * while at least 8 pixels remain: tile $6a, the HP bar's full cell
--     * the leftover 1..7 pixels: tile $54 + remainder, i.e. $55..$5b from
--       ExpBarGFX -- which is why those cells anchor their fill to the right,
--       against the full cells beside them
--     * every remaining cell: tile $62, the HP bar's empty cell
--
-- So the bar is eight tiles wide (64 pixels), it grows from the RIGHT, and two
-- of its three tiles come from FontBattleExtra rather than ExpBarGFX.  Getting
-- any of those three facts wrong is what makes it look like dashes.
BattleHud.EXP_CELLS = 8
BattleHud.EXP_LENGTH_PX = BattleHud.EXP_CELLS * 8
local TILE_EXP_FULL = 0x6a    -- FontBattleExtra
local TILE_EXP_EMPTY = 0x62   -- FontBattleExtra
local EXP_PARTIAL_BASE = 0x54 -- $54 + remainder lands in ExpBarGFX

-- PAL_BATTLE_BG_EXP, which the attrmap lays over (10,11)..(18,11)
-- (engine/gfx/cgb_layouts.asm:142-145).
function BattleHud:expColors(zero)
  local pal = self.palettes and self.palettes.expBar
  if not pal then return nil end
  return {
    zero or { 255, 255, 255 },
    { pal[1][1], pal[1][2], pal[1][3] },
    { pal[2][1], pal[2][2], pal[2][3] },
    { 0, 0, 0 },
  }
end

function BattleHud:drawExpBar(fraction, tx, ty, zero)
  if not self:image("hpBar") then return false end
  fraction = math.max(0, math.min(1, fraction or 0))
  local pixels = math.floor(fraction * BattleHud.EXP_LENGTH_PX)
  -- The whole row wears the exp bar's palette, full and empty cells included.
  local colors = self:expColors(zero)

  local remaining = pixels
  for cell = BattleHud.EXP_CELLS - 1, 0, -1 do
    local column = tx + cell
    if remaining >= 8 then
      remaining = remaining - 8
      self:drawTile("hpBar", FIRST_BATTLE_EXTRA, TILE_EXP_FULL, column, ty,
        colors)
    elseif remaining > 0 then
      self:drawTile("expBar", self.gfx.expBarFirstTile,
        EXP_PARTIAL_BASE + remaining, column, ty, colors)
      remaining = 0
    else
      self:drawTile("hpBar", FIRST_BATTLE_EXTRA, TILE_EXP_EMPTY, column, ty,
        colors)
    end
  end
  return true
end

-- than on the tile grid (../pokecrystal/engine/sprite_anims/core.asm:547-608).
function BattleHud:drawExpBarEnd(x, y, colors)
  local image = self:image("expBarEnd")
  if not image then return false end
  local G = love.graphics
  G.setColor(1, 1, 1, 1)
  local function body() G.draw(image, x, y) end
  if colors and GbcPalette.available() then
    GbcPalette.with(colors, body)
  else
    G.setColor(0, 0, 0, 1)
    body()
    G.setColor(1, 1, 1, 1)
  end
  return true
end

-- The mark sits inside the enemy HP block, which the battle attrmap fills with
-- PAL_BATTLE_BG_ENEMY_HP (engine/gfx/cgb_layouts.asm:123-128).
function BattleHud:drawCaughtIcon(tx, ty, hp, maxHp)
  local first = self.gfx and self.gfx.expBarFirstTile
  if not first or (self.gfx.expBarCells or 0) < 9 then return false end
  local colors = self:barColors(HpBar.palette(HpBar.pixels(hp, maxHp)))
  if not colors then return false end
  return self:drawTile("expBar", first, TILE_CAUGHT, tx, ty, colors)
end

-- Both frames come out of PlaceHUDBorderTiles, which lays four tiles in a
-- fixed pattern from one starting coordinate:
--
--   tiles[0] (side)        at the start
--   tiles[1] (near corner) one row BELOW it, same column
--   tiles[3] (bottom side) x8, stepping by de (+1 right, -1 left)
--   tiles[2] (far corner)  one step past that run
--
-- Getting the corner's row wrong is what leaves the vertical stub floating
-- clear of the bottom rule instead of joined to it.
function BattleHud:placeBorder(tiles, tx, ty, step)
  -- side
  self:drawTile(tiles.sideSheet, tiles.sideFirst, tiles.side, tx, ty)
  -- near corner, one row down
  self:drawTile(tiles.cornerSheet, tiles.cornerFirst, tiles.nearCorner,
    tx, ty + 1)
  -- eight bottom-side tiles, then the far corner
  local x = tx
  for _ = 1, 8 do
    x = x + step
    self:drawTile(tiles.cornerSheet, tiles.cornerFirst, tiles.bottom,
      x, ty + 1)
  end
  x = x + step
  self:drawTile(tiles.farSheet or tiles.cornerSheet,
    tiles.farFirst or tiles.cornerFirst, tiles.farCorner, x, ty + 1)
end

-- DrawEnemyHUDBorder: hlcoord 1, 2 stepping right, tiles $6d / $74 / $78 / $76.
function BattleHud:drawEnemyFrame()
  self:placeBorder({
    sideSheet = "enemyBorder", sideFirst = ENEMY_BORDER_FIRST,
    cornerSheet = "playerBorder", cornerFirst = PLAYER_BORDER_FIRST,
    side = TILE_ENEMY_LEFT,
    nearCorner = TILE_ENEMY_BOTTOM_LEFT,
    farCorner = TILE_ENEMY_BOTTOM_RIGHT,
    bottom = TILE_BOTTOM_SIDE,
  }, 1, 2, 1)
end

-- DrawPlayerHUDBorder: hlcoord 18, 10 stepping LEFT, tiles $73 / $77 / $6f /
-- $76, plus the extra vertical bar DrawPlayerHUD writes at (18,9) so the stub
-- is two rows tall.
local PLAYER_FRAME_TILES = {
  sideSheet = "playerBorder", sideFirst = PLAYER_BORDER_FIRST,
  cornerSheet = "playerBorder", cornerFirst = PLAYER_BORDER_FIRST,
  -- $6f is the LAST tile of EnemyHPBarBorderGFX, not the player sheet
  -- (engine/gfx/load_font.asm:57-65).
  farSheet = "enemyBorder", farFirst = ENEMY_BORDER_FIRST,
  side = TILE_PLAYER_RIGHT,
  nearCorner = TILE_PLAYER_BOTTOM_RIGHT,
  farCorner = TILE_PLAYER_BOTTOM_LEFT,
  bottom = TILE_BOTTOM_SIDE,
}

function BattleHud:drawPlayerFrame()
  self:drawTile("playerBorder", PLAYER_BORDER_FIRST, TILE_PLAYER_RIGHT, 18, 9)
  self:placeBorder(PLAYER_FRAME_TILES, 18, 10, -1)
end

-- DrawPlayerPartyIconHUDBorder (engine/battle/trainer_huds.asm:118-132): the
-- player border with $5c for the bottom right, and no bar at (18,9).
function BattleHud:drawPartyIconFrame()
  self:placeBorder(PLAYER_FRAME_TILES, 18, 10, -1)
  return self:drawTile("expBar", self.gfx and self.gfx.expBarFirstTile,
    TILE_PARTY_ICON_BOTTOM_RIGHT, 18, 11, self:expColors())
end

-- StageBallTilesData's .GetHUDTile, and the $34 it stages past the party
-- count (engine/battle/trainer_huds.asm:47-100).
local function ballTile(mon)
  if not mon then return TILE_BALL_EMPTY end
  if (mon.hp or 0) <= 0 then return TILE_BALL_FAINTED end
  return mon.status and TILE_BALL_STATUSED or TILE_BALL_NORMAL
end

-- PAL_BATTLE_OB_YELLOW (engine/battle/trainer_huds.asm:213-214).
function BattleHud:ballColors()
  local pals = self.palettes and self.palettes.battleObjects
  return pals and pals.PAL_BATTLE_OB_YELLOW or nil
end

-- LoadTrainerHudOAM (engine/battle/trainer_huds.asm:203-223): six sprites
-- from (tx, ty), each one tile further along `step`.
function BattleHud:drawBallRow(party, tx, ty, step)
  if not self:image("balls") then return false end
  local first = self.gfx.ballsFirstTile or TILE_BALL_NORMAL
  local colors = self:ballColors()
  for slot = 1, BattleHud.PARTY_LENGTH do
    self:drawTile("balls", first, ballTile(party and party[slot]),
      tx + (slot - 1) * step, ty, colors)
  end
  return true
end

BattleHud.TILE_HP_LABEL = TILE_HP_LABEL
BattleHud.TILE_BAR_EMPTY = TILE_BAR_EMPTY
BattleHud.TILE_BAR_END = TILE_BAR_END

return BattleHud
