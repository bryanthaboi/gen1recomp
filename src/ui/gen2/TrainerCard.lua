-- Gold's trainer card (engine/menus/trainer_card.asm), transcribed from the
-- routines that draw it rather than laid out by eye.
--
-- The card is not a text box.  TrainerCard_InitBorder writes the frame out of
-- the sheet's own tiles: a row of $23, then a row of $23 + 17 spaces + $04 +
-- $23, then d rows of $23 + 18 spaces + $23, then $23 + $24 + 17 spaces +
-- $23, then a closing row of $23 -- d + 4 rows in all.  It is called twice,
-- at (0,0) with d = 5 (rows 0-8) and at (0,8) with d = 6 (rows 8-17), so the
-- two halves share row 8.
--
-- Page 1 (TrainerCard_PrintTopHalfOfCard + _Page1_PrintDexCaught_GameTime):
--   (2,2) "NAME/", <NEXT> twice to (2,6) "MONEY"; the blank middle line is
--         then overwritten by the $27/$28 "ID No" tiles at (2,4)
--   (7,2) player name, (5,4) ID as 5 digits with leading zeros,
--         (7,6) money as PRINTNUM_MONEY 6 digits
--   (1,3) the $25 x12 + $26 divider
--   (14,1) the player's portrait: a 5x7 block of running tile ids from $00
--   (2,8) the $29..$2d status caption
--   (2,10) "#DEX" and (2,12) "PLAY TIME"; (15,10) caught count,
--         (11,12) hours as 4 digits then (16,12) minutes, with the colon at
--         (15,12) blinking every 32 frames
--   (12,15) "BADGES▶"
--
-- Pages 2 and 3 (TrainerCard_Page2_3_InitObjectsAndStrings): the $79..$7d
-- "BADGES" caption at (2,8), then eight gym leader faces from LeaderGFX --
-- four at row 10 and four at row 13, each ten tiles laid 4 across then two
-- rows of 3 offset one column in -- with the badges themselves as OBJs out of
-- BadgeGFX at TrainerCard_JohtoBadgesOAM's coordinates.  Page 3's LoadGFX
-- requests LeaderGFX2/BadgeGFX2, but those INCBIN the identical .2bpp files,
-- and TrainerCard_Page3_Joypad still hands TrainerCard_Page2_3_AnimateBadges
-- the Johto table -- whose header word is `dw wJohtoBadges` -- so the "Kanto"
-- page is really the Johto page redrawn: same faces, same badges, gated on
-- the same flags.  We match that rather than wire it to wKantoBadges.
--
-- Colour comes from _CGB_TrainerCard: the whole attrmap is palette 1
-- (Falkner's trainer colours, which is what tints the frame), the portrait
-- box is palette 0 (the player's), and each leader's lower two rows get that
-- leader's own palette.

local Chrome = require("src.ui.gen2.Chrome")
local GbcPalette = require("src.render.GbcPalette")
local Gen2Save = require("src.core.gen2.Save")
local TileSheet = require("src.ui.gen2.TileSheet")

local TrainerCard = {}
TrainerCard.__index = TrainerCard
TrainerCard.isOpaque = true

local SCREEN_W, SCREEN_H = 20, 18

-- Frame tiles, which live at $23 because ChrisPicAndTrainerCardGFX is the
-- 35-tile portrait followed by the 6-tile frame.
local TILE_FRAME = 0x23
local TILE_NOTCH_LOW = 0x24 -- the (1, bottom-1) notch
local TILE_NOTCH_HIGH = 0x04 -- the (18, top+1) one, from the portrait sheet
local TILE_DIVIDER = 0x25
local TILE_DIVIDER_END = 0x26
local TILE_ID_NO = { 0x27, 0x28 }
local TILE_STATUS = { 0x29, 0x2a, 0x2b, 0x2c, 0x2d }
local TILE_BADGES_CAPTION = { 0x79, 0x7a, 0x7b, 0x7c, 0x7d }
local TILE_COLON = 0x2e

-- Johto then Kanto, in badge order.
local JOHTO_BADGES = {
  "ZEPHYR", "HIVE", "PLAIN", "FOG", "STORM", "MINERAL", "GLACIER", "RISING",
}
local KANTO_BADGES = {
  "BOULDER", "CASCADE", "THUNDER", "RAINBOW", "SOUL", "MARSH", "VOLCANO",
  "EARTH",
}

-- The two slots _CGB_TrainerCard swaps by gender: CHRIS and FALKNER/KrisPalette.
-- ../pokecrystal/engine/gfx/cgb_layouts.asm:619-624, data/trainers/palettes.asm:9-12
local PLAYER_PALETTE, BORDER_PALETTE = 1, 2

-- Kris's attrmap: the border takes CHRIS's palette, the portrait takes hers,
-- the top-right corner follows the border, and Clair's face borrows hers
-- (../pokecrystal/engine/gfx/cgb_layouts.asm:649-666, :698-712).
local FEMALE_ZONES = {
  { 14, 1, 5, 7, BORDER_PALETTE },
  { 18, 1, 1, 1, PLAYER_PALETTE },
  { 14, 14, 4, 2, BORDER_PALETTE },
}

-- TrainerCard_JohtoBadgesOAM lists the badges in wJohtoBadges bit order,
-- which is not the order they are drawn in: Mineral comes before Storm.
local BADGE_OAM_ORDER = {
  "ZEPHYR", "HIVE", "PLAIN", "FOG", "MINERAL", "STORM", "GLACIER", "RISING",
}

function TrainerCard:wantsFillScale() return true end
function TrainerCard:drawsWidescreen() return true end

-- opts: save, onClose(), sprites (sprites.lua), palettes, menuGfx
function TrainerCard.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, TrainerCard)
  self.game = game
  self.save = opts.save or (game and game.save)
  local data = game and game.data or {}
  self.palettes = opts.palettes or data.gen2Palettes
  self.sprites = opts.sprites or data.gen2Sprites
  self.onClose = opts.onClose
  self.page = 1 -- 1 card, 2 Johto badges, 3 Kanto badges
  self.frames = 0

  local gfx = (opts.menuGfx or data.gen2MenuGfx or {}).trainerCard
  self.gfx = gfx
  self.female = Gen2Save.isFemale(self.save) and gfx ~= nil
    and gfx.cardFemale ~= nil
  if gfx then
    -- One palette lookup per cell, flattened from the FillBoxCGB zones the
    -- way PackGfx does it.  Anything outside a zone is palette 1.
    self.zone = {}
    self.zoneDefault = BORDER_PALETTE
    for _, z in ipairs(gfx.paletteZones or {}) do
      for y = z[2], z[2] + z[4] - 1 do
        for x = z[1], z[1] + z[3] - 1 do
          self.zone[y * SCREEN_W + x] = z[5]
        end
      end
    end
    if self.female then
      self.zoneDefault = PLAYER_PALETTE
      for _, z in ipairs(FEMALE_ZONES) do
        for y = z[2], z[2] + z[4] - 1 do
          for x = z[1], z[1] + z[3] - 1 do
            self.zone[y * SCREEN_W + x] = z[5]
          end
        end
      end
    end
    local function paletteFor(_, tx, ty)
      return self:colorsAt(tx, ty)
    end
    self.card = TileSheet.new({
      path = (self.female and gfx.cardFemale) or gfx.card,
      wide = gfx.cardTilesWide or 16, firstTile = 0,
      paletteFor = paletteFor,
    })
    self.status = TileSheet.new({
      path = gfx.status, wide = gfx.statusWide or 6,
      firstTile = gfx.statusFirstTile or 0x29, paletteFor = paletteFor,
    })
    self.leaders = TileSheet.new({
      path = gfx.leaders, wide = gfx.leadersWide or 10,
      firstTile = gfx.leadersFirstTile or 0x29, paletteFor = paletteFor,
    })
    self.badges = TileSheet.new({
      path = gfx.badges, wide = gfx.badgesWide or 2, firstTile = 0,
      palette = gfx.badgePalette,
    })
  end
  return self
end

function TrainerCard:styled()
  return self.card ~= nil and self.card:available()
end

-- The eight BG palettes _CGB_TrainerCard loads: the player's, then the seven
-- leaders whose classes have a pic palette of their own.
function TrainerCard:palette(index)
  local pals = self.palettes
  if not pals then return nil end
  if index == 1 then
    return self:pair(pals.trainers and pals.trainers.PLAYER)
  end
  local classes = self.gfx and self.gfx.leaderClasses or {}
  return self:pair(pals.trainers and pals.trainers[classes[index - 1]])
end

-- LoadPalette_White_Col1_Col2_Black: the two stored colours sit between white
-- and black, which is how every trainer palette in the game is used.
function TrainerCard:pair(colors)
  if not (colors and colors[1] and colors[2]) then return nil end
  return {
    { 255, 255, 255 }, colors[1], colors[2], { 0, 0, 0 },
  }
end

function TrainerCard:colorsAt(tx, ty)
  local index = (self.zone and self.zone[ty * SCREEN_W + tx])
    or self.zoneDefault or BORDER_PALETTE
  return self:palette(index)
end

function TrainerCard:pages()
  -- Kanto's page only exists once the player has been there; the cart gates it
  -- on the Kanto badges having started.
  local kanto = self.save and self.save.player
    and next(self.save.player.kantoBadges or {}) ~= nil
  return kanto and 3 or 2
end

function TrainerCard:update(_dt)
  self.frames = self.frames + 1
  local input = self.game and self.game.input
  if not input then return end
  if input:wasPressed("b") or input:wasPressed("start") then
    if self.onClose then self.onClose() end
    return
  end
  local pages = self:pages()
  if input:wasPressed("right") then
    self.page = self.page < pages and self.page + 1 or 1
  elseif input:wasPressed("left") then
    self.page = self.page > 1 and self.page - 1 or pages
  elseif input:wasPressed("a") then
    -- Page 1's A is "turn the page"; page 2's A quits (TrainerCard_Page2_Joypad).
    if self.page == 1 then
      self.page = 2
    elseif self.onClose then
      self.onClose()
    end
  end
end

function TrainerCard:caughtCount()
  local caught = 0
  for _, has in pairs((self.save and self.save.pokedex
    and self.save.pokedex.caught) or {}) do
    if has then caught = caught + 1 end
  end
  return caught
end

-- PRINTNUM_MONEY prints a ¥ in front of the first significant digit rather
-- than at a fixed column, and the field is six digits wide.
local function moneyText(amount)
  local digits = ("%06d"):format(math.max(0, math.floor(amount or 0)))
  local first = digits:find("[1-9]") or #digits
  return (" "):rep(first - 1) .. "\xc2\xa5" .. digits:sub(first)
end

function TrainerCard:tile(sheet, id, tx, ty)
  if sheet then sheet:draw(id, tx, ty) end
end

-- TrainerCard_InitBorder, literally.
function TrainerCard:frame(ty, interiorRows)
  local sheet = self.card
  for x = 0, SCREEN_W - 1 do self:tile(sheet, TILE_FRAME, x, ty) end
  self:tile(sheet, TILE_FRAME, 0, ty + 1)
  self:tile(sheet, TILE_NOTCH_HIGH, 18, ty + 1)
  self:tile(sheet, TILE_FRAME, 19, ty + 1)
  for row = 2, interiorRows + 1 do
    self:tile(sheet, TILE_FRAME, 0, ty + row)
    self:tile(sheet, TILE_FRAME, 19, ty + row)
  end
  local notch = ty + interiorRows + 2
  self:tile(sheet, TILE_FRAME, 0, notch)
  self:tile(sheet, TILE_NOTCH_LOW, 1, notch)
  self:tile(sheet, TILE_FRAME, 19, notch)
  for x = 0, SCREEN_W - 1 do
    self:tile(sheet, TILE_FRAME, x, ty + interiorRows + 3)
  end
end

-- The 5x7 portrait: running tile ids from $00, row-major, at (14,1).
function TrainerCard:drawPortrait()
  local wide = self.gfx and self.gfx.portraitWide or 5
  local high = math.floor((self.gfx and self.gfx.portraitTiles or 35) / wide)
  for row = 0, high - 1 do
    for col = 0, wide - 1 do
      self:tile(self.card, row * wide + col, 14 + col, 1 + row)
    end
  end
end

-- TrainerCard_PrintTopHalfOfCard runs once, in .InitRAM, and no page redraws
-- it -- so the name, ID, money and portrait stay on screen behind the badge
-- pages too.
function TrainerCard:drawTopHalf()
  local player = (self.save or {}).player or {}
  self:frame(0, 5)
  Chrome.print("NAME/", 2, 2)
  Chrome.print(player.name or "GOLD", 7, 2)
  self:tile(self.card, TILE_ID_NO[1], 2, 4)
  self:tile(self.card, TILE_ID_NO[2], 3, 4)
  Chrome.print(Chrome.number(player.id or 0, 5, true), 5, 4)
  Chrome.print("MONEY", 2, 6)
  Chrome.print(moneyText(player.money), 7, 6)
  for x = 1, 12 do self:tile(self.card, TILE_DIVIDER, x, 3) end
  self:tile(self.card, TILE_DIVIDER_END, 13, 3)
  self:drawPortrait()
end

function TrainerCard:drawCard()
  local save = self.save or {}
  self:drawTopHalf()
  self:frame(8, 6)

  -- The $29..$2d caption plaque, which sits on the row the two halves share.
  for i, id in ipairs(TILE_STATUS) do
    self:tile(self.status, id, 1 + i, 8)
  end

  -- `#` is the compression byte for POKé, four tiles, so spelling it out is
  -- what the cart actually draws.
  Chrome.print("POKéDEX", 2, 10)
  Chrome.print("PLAY TIME", 2, 12)
  Chrome.print(Chrome.number(self:caughtCount(), 3), 15, 10)

  local time = save.playTime or {}
  Chrome.print(Chrome.number(time.hours or 0, 4), 11, 12)
  -- The colon is $2e, which belongs to CardStatusGFX rather than the card
  -- sheet, and TrainerCard_Page1_PrintGameTime xors it with ' ' every 32
  -- frames -- which is what makes the clock look like it is running.
  if math.floor(self.frames / 32) % 2 == 0 then
    self:tile(self.status, TILE_COLON, 15, 12)
  end
  Chrome.print(Chrome.number(time.minutes or 0, 2, true), 16, 12)

  Chrome.print("BADGES", 12, 15)
  Chrome.cursor(18, 15)
end

-- TrainerCard_Page2_3_PlaceLeadersFaces: four tiles across the top row, then
-- two rows of three offset one column in, ten tiles per face with the id
-- running on across all eight.
function TrainerCard:drawLeaderFace(first, tx, ty)
  local id = first
  for col = 0, 3 do
    self:tile(self.leaders, id, tx + col, ty)
    id = id + 1
  end
  for row = 1, 2 do
    for col = 1, 3 do
      self:tile(self.leaders, id, tx + col, ty + row)
      id = id + 1
    end
  end
  return id
end

function TrainerCard:drawBadgeSprites(owned, names)
  local list = self.gfx and self.gfx.badgeOam
  if not (list and self.badges and self.badges:available()) then return end
  local G = love.graphics
  -- Eight frames on a 3-bit counter, stepped every 8 VBlanks.
  local frame = math.floor(self.frames / 8) % 8
  for i, obj in ipairs(list) do
    -- The OAM table is in wJohtoBadges bit order, which is not the drawing
    -- order (Mineral is listed before Storm), so the earned flag is looked up
    -- by name -- or by that name's position, since a save may key the array
    -- either way.
    local name = BADGE_OAM_ORDER[i]
    local slot
    for index, badge in ipairs(names) do
      if badge == name then slot = index end
    end
    if owned[name] or (slot and owned[slot]) then
      local tile = obj.frames[frame + 1] or 0
      -- Bit 7 of the tile id is an x-flip, which is how Risingbadge turns.
      local flip = tile >= 0x80
      local base = flip and (tile - 0x80) or tile
      local sx = flip and -1 or 1
      local function body()
        for _, cell in ipairs({ { 0, 0, 0 }, { 1, 0, 1 }, { 0, 1, 2 },
            { 1, 1, 3 } }) do
          local quad = self.badges:quad(base + cell[3])
          if quad then
            local px = obj.x + (flip and (1 - cell[1]) or cell[1]) * 8
            G.draw(self.badges:image(), quad,
              px + (flip and 8 or 0), obj.y + cell[2] * 8, 0, sx, 1)
          end
        end
      end
      G.setColor(1, 1, 1, 1)
      if self.gfx.badgePalette and GbcPalette.available() then
        GbcPalette.with(self.gfx.badgePalette, body)
      else
        body()
      end
    end
  end
end

function TrainerCard:drawBadges(names, owned)
  self:drawTopHalf()
  self:frame(8, 6)
  for i, id in ipairs(TILE_BADGES_CAPTION) do
    self:tile(self.leaders, id, 1 + i, 8)
  end
  local id = self.gfx and self.gfx.leadersFirstTile or 0x29
  for face = 0, 3 do id = self:drawLeaderFace(id, 2 + face * 4, 10) end
  for face = 0, 3 do id = self:drawLeaderFace(id, 2 + face * 4, 13) end
  self:drawBadgeSprites(owned, names)
end

-- ------------------------------------------------------------------ fallback

function TrainerCard:drawPlain()
  local save = self.save or {}
  local player = save.player or {}
  Chrome.clear()
  if self.page == 1 then
    Chrome.box(0, 0, 20, 9)
    Chrome.print("NAME/", 2, 2)
    Chrome.print(player.name or "GOLD", 7, 2)
    Chrome.print("ID No", 2, 4)
    Chrome.print(Chrome.number(player.id or 0, 5, true), 5, 4)
    Chrome.print("MONEY", 2, 6)
    Chrome.print(moneyText(player.money), 7, 6)
    Chrome.box(0, 8, 20, 10)
    Chrome.print("POKéDEX", 2, 10)
    Chrome.print(Chrome.number(self:caughtCount(), 3), 15, 10)
    Chrome.print("PLAY TIME", 2, 12)
    local time = save.playTime or {}
    Chrome.print(Chrome.number(time.hours or 0, 4), 11, 12)
    Chrome.print(":", 15, 12)
    Chrome.print(Chrome.number(time.minutes or 0, 2, true), 16, 12)
    Chrome.print("BADGES", 12, 15)
    Chrome.cursor(18, 15)
    return
  end
  local names = self.page == 2 and JOHTO_BADGES or KANTO_BADGES
  -- TrainerCard_Page3_Joypad hands TrainerCard_Page2_3_AnimateBadges the
  -- exact same TrainerCard_JohtoBadgesOAM pointer page 2 uses, and that
  -- table's own header word is `dw wJohtoBadges` -- so page 3 never once
  -- reads wKantoBadges, it just relabels the Johto flags.  held stays
  -- player.badges on both pages to match.
  local held = player.badges or {}
  Chrome.box(0, 0, 20, 9)
  Chrome.print(self.page == 2 and "JOHTO BADGES" or "KANTO BADGES", 2, 2)
  Chrome.box(0, 8, 20, 10)
  for i, name in ipairs(names) do
    local tx = 2 + ((i - 1) % 4) * 4
    local ty = 10 + math.floor((i - 1) / 4) * 3
    Chrome.print((held[i] or held[name]) and name:sub(1, 4) or "----", tx, ty)
  end
end

function TrainerCard:drawPanel()
  if not self:styled() then
    self:drawPlain()
    love.graphics.setColor(1, 1, 1, 1)
    return
  end
  local G = love.graphics
  G.setColor(1, 1, 1, 1)
  G.rectangle("fill", 0, 0, SCREEN_W * 8, SCREEN_H * 8)
  local player = (self.save and self.save.player) or {}
  if self.page == 1 then
    self:drawCard()
  elseif self.page == 2 then
    self:drawBadges(JOHTO_BADGES, player.badges or {})
  else
    -- Page 3 reuses TrainerCard_JohtoBadgesOAM wholesale, header word and
    -- all, so it is really the Johto page again: JOHTO_BADGES here keeps
    -- drawBadgeSprites' name/position fallback matched to player.badges,
    -- the same table page 2 reads.
    self:drawBadges(JOHTO_BADGES, player.badges or {})
  end
  G.setColor(1, 1, 1, 1)
end

function TrainerCard:draw()
  self:drawPanel()
end

function TrainerCard:drawWidescreen(winW, winH)
  local G = love.graphics
  G.setColor(1, 1, 1, 1)
  G.rectangle("fill", 0, 0, winW, winH)
  local scale = Chrome.fitScale(winW, winH)
  G.push()
  G.translate(Chrome.fitOrigin(winW, winH, scale))
  G.scale(scale, scale)
  self:drawPanel()
  G.pop()
end

TrainerCard.JOHTO_BADGES = JOHTO_BADGES
TrainerCard.KANTO_BADGES = KANTO_BADGES
TrainerCard.BADGE_OAM_ORDER = BADGE_OAM_ORDER
TrainerCard.moneyText = moneyText

return TrainerCard
