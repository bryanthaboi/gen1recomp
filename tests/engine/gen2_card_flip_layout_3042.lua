package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
love = require("tests.love_stub")
local CardFlip = require("src.ui.gen2.CardFlip")
local Chrome = require("src.ui.gen2.Chrome")

-- pokecrystal/engine/games/card_flip.asm:1349
for x = 2, 5 do
  local flip = setmetatable({ cursorX = x, cursorY = 1 }, CardFlip)
  flip.cursorX, flip.cursorY = CardFlip.moveCursor(x, 1, "up")
  local px, py, w, h = flip:cursorBounds()
  T.eq(px, x < 4 and 96 or 128, "paired wager anchor from column " .. x)
  T.eq(py, 0, "paired wager top")
  T.eq(w, 32, "paired wager width")
  T.eq(h, 8, "paired wager height")
  T.eq(flip.cursorX, x, "moving up retains the logical column")
end

local originalFill, originalGlyphs = Chrome.paletteFill, Chrome.paletteGlyphs
local printed
local filled
Chrome.paletteFill = function(x, y, w, h, palette)
  filled[#filled + 1] = { x = x, y = y, w = w, h = h, palette = palette }
end
Chrome.paletteGlyphs = function(palette)
  return palette, function(code, x, y)
    printed[#printed + 1] = { code = code, x = x / 8, y = y / 8, palette = palette }
  end, function() end
end

local PAL = { { 255, 255, 255 }, { 140, 58, 255 }, { 49, 156, 66 }, { 0, 0, 0 } }
local PALETTES = { bg = {}, obj = { [0] = PAL } }
for slot = 0, 7 do PALETTES.bg[slot] = PAL end
local gfx = { faceDown = {}, faceUp = {}, deck = {}, palettes = PALETTES }
for i = 1, 30 do gfx.faceDown[i], gfx.faceUp[i] = i % 32, (i + 1) % 32 end
gfx.faceUp[8], gfx.faceUp[9] = 0x7f, 0x7f
for card = 0, 23 do
  gfx.deck[card * 2 + 1] = 200 + math.floor(card / 4)
  gfx.deck[card * 2 + 2] = 0x4e + card % 4 * 3
end
local game = { data = { gen2MenuGfx = { cardFlip = gfx } } }

-- pokecrystal/engine/games/card_flip.asm:458
for mon = 0, 3 do
  printed, filled = {}, {}
  local face, back, picture = {}, {}, {}
  local s1, s2 = { available = function() return true end }, { available = function() return true end }
  function s1:draw(tile, x, y)
    local target = y >= 6 and face or back
    target[#target + 1] = { tile = tile, x = x, y = y, palette = self.palette }
  end
  function s2:draw(tile, x, y)
    picture[#picture + 1] = { tile = tile, x = x, y = y, palette = self.palette }
  end
  local flip = setmetatable({ game = game, faceUp = CardFlip.card(1, mon), which = 1, phase = "result",
    sheets = function() return s1, s2 end }, CardFlip)
  flip:drawCards()
  T.eq(#back, 30, "face-down card has thirty cached tiles")
  for i, tile in ipairs(back) do T.eq(tile.tile, gfx.faceDown[i], "face-down tile comes from cache") end
  T.eq(#picture, 9, "face-up Pokemon has nine tiles")
  for i, tile in ipairs(picture) do
    T.eq(tile.tile, 24 + mon * 3 + i - 1, "cached picture tile " .. mon .. ":" .. i)
    T.eq(tile.x, 3 + (i - 1) % 3, "picture column")
    T.eq(tile.y, 8 + math.floor((i - 1) / 3), "picture row")
  end
  local spaces, level = 0, false
  for _, glyph in ipairs(printed) do
    if glyph.y == 7 then
      if glyph.code == 0x7f and (glyph.x == 4 or glyph.x == 5) then spaces = spaces + 1 end
      if glyph.code == 201 and glyph.x == 5 then level = true end
      T.eq(glyph.palette, s2.palette, "level row uses the card palette")
    end
  end
  T.eq(spaces, 2, "face-up level row clears both font-space cells")
  T.check(level, "cached level glyph stays in its original tile")
  T.eq(#filled, 3, "both font spaces and the level glyph get an opaque cell")
  for _, fill in ipairs(filled) do
    T.eq(fill.palette, s2.palette, "font background uses the card palette")
    T.eq(fill.w, 8, "font tile width")
    T.eq(fill.h, 8, "font tile height")
  end
  for _, tile in ipairs(face) do
    T.eq(tile.tile, gfx.faceUp[(tile.y - 6) * 5 + tile.x - 2 + 1], "face-up tile comes from cache")
    T.eq(tile.palette, s2.palette, "whole face uses the Pokemon palette")
    T.check(not (tile.y == 7 and (tile.x == 4 or tile.x == 5)),
      "card-body tiles do not cover the font-space cells")
  end
end
Chrome.paletteFill, Chrome.paletteGlyphs = originalFill, originalGlyphs

local missing = setmetatable({}, CardFlip)
T.check(not pcall(missing.drawCards, missing), "drawing requires cached Card Flip data")
local short = setmetatable({ game = { data = { gen2MenuGfx = { cardFlip = {
  faceDown = gfx.faceDown, faceUp = gfx.faceUp, deck = {}, palettes = PALETTES,
} } } } }, CardFlip)
T.check(not pcall(short.drawCards, short), "drawing rejects a short cached deck")
short.game.data.gen2MenuGfx.cardFlip.deck = gfx.deck
short.game.data.gen2MenuGfx.cardFlip.faceUp = {}
T.check(not pcall(short.drawCards, short), "drawing rejects a short cached face map")

-- pokecrystal/engine/games/card_flip.asm:229
local flip = setmetatable({
  game = { input = { wasPressed = function(_, key) return key == "a" end } },
  deck = { 0, 1 }, played = 0, which = 0, discarded = { [2] = true },
  cursorX = 4, cursorY = 2, phase = "bet",
}, CardFlip)
flip:tick()
T.eq(flip.phase, "flipping", "discarded exact-card wager is still accepted")
T.eq(flip.payoutLeft, 0, "a discarded exact-card wager loses against another card")

-- pokegold/engine/games/card_flip.asm:301
do
  local boxes, originalTextbox, originalPrint = {}, Chrome.textbox, Chrome.print
  Chrome.textbox = function(x, y) boxes[#boxes + 1] = x .. "," .. y end
  Chrome.print = function() end
  local data = { text = {
    _CardFlipShuffledText = "The cards have\nbeen shuffled.",
    _CardFlipPlayAgainText = "Want to play\nagain?",
    ["CardFlip_PrintCoinBalance.CoinStr"] = "COIN",
  } }
  local panel = setmetatable({ game = { data = data }, save = { player = { coins = 9 } },
    phase = "message" }, CardFlip)
  panel.drawBoard, panel.drawCards = function() end, function() end
  panel.lines = panel:text("shuffled")
  panel:drawPanel()
  T.eq(table.concat(boxes, " "), "0,12", "the shuffled text has no coin box")
  boxes = {}
  panel.lines = panel:text("playAgain")
  panel:drawPanel()
  T.eq(boxes[2], "9,15", "other Card Flip text keeps the coin box")
  Chrome.textbox, Chrome.print = originalTextbox, originalPrint
end

T.finish("gen2_card_flip_layout_3042")
