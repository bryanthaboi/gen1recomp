-- engine/menus/naming_screen.asm:84

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

package.loaded["src.core.Sound"] = { play = function() end }

local icons = {}
package.loaded["src.ui.PartyMenu"] = {
  drawIcon = function(_, mon, x, y, selected, counter, alt)
    local r, g, b, a = love.graphics.getColor()
    icons[#icons + 1] = {
      species = mon.species, x = x, y = y, alt = alt,
      color = { r, g, b, a },
    }
    return true
  end,
}

local Font = require("src.render.Font")
local HudTiles = require("src.render.HudTiles")
local NamingScreen = require("src.ui.NamingScreen")

local text, tiles, boxes, cursors = {}, {}, {}, {}
Font.draw = function(s, x, y)
  local r, g, b = love.graphics.getColor()
  text[#text + 1] = { s = s, x = x, y = y, color = { r, g, b } }
end
Font.drawCode = function(code, x, y)
  cursors[#cursors + 1] = { code = code, x = x, y = y }
end
Font.drawBox = function(tx, ty, tw, th)
  boxes[#boxes + 1] = { tx = tx, ty = ty, tw = tw, th = th }
end
HudTiles.namingTile = function(code, x, y)
  tiles[#tiles + 1] = { code = code, x = x, y = y }
end

local function newGame()
  return {
    data = { pokemon = { CHARMANDER = { name = "CHARMANDER", dex = 4 } } },
    stack = { pop = function() end },
    input = { wasPressed = function() return false end },
  }
end

local function render(opts)
  text, tiles, boxes, cursors, icons = {}, {}, {}, {}, {}
  local ns = NamingScreen.new(newGame(), opts)
  return ns
end

local function drawn(s)
  for _, entry in ipairs(text) do
    if entry.s == s then return entry end
  end
end

local ns = render({ title = "YOUR NAME?", maxLen = 7 })
ns:draw()

local title = drawn("YOUR NAME?")
check(title ~= nil, "the player title is drawn")
eq(title and title.x, 0, "title at hlcoord 0,1 -> x 0")
eq(title and title.y, 8, "title at hlcoord 0,1 -> y 8")

eq(#boxes, 1, "the letter grid sits in one TextBoxBorder")
eq(boxes[1].tx, 0, "box at hlcoord 0,4 -> tx 0")
eq(boxes[1].ty, 4, "box at hlcoord 0,4 -> ty 4")
eq(boxes[1].tw, 20, "c=18 -> 20 tiles wide")
eq(boxes[1].th, 11, "b=9 -> 11 tiles tall")

eq(#tiles, 7, "PLAYER_NAME_LENGTH - 1 underscores")
eq(tiles[1].x, 80, "underscore row starts at hlcoord 10")
eq(tiles[1].y, 24, "underscore row is hlcoord 10,3")
eq(tiles[7].x, 128, "and runs one tile per slot")
eq(tiles[1].code, 0x77, "the empty name raises the first slot")
eq(tiles[2].code, 0x76, "every other slot is the flat underscore")

local a = drawn("A")
check(a ~= nil, "the grid's A cell is drawn")
eq(a and a.x, 16, "grid column 1 at hlcoord 2 -> x 16")
eq(a and a.y, 40, "grid row 1 at hlcoord 5 -> y 40")
local lower = drawn("lower case")
eq(lower and lower.y, 120, "the case-switch label lands below the box")

eq(#cursors, 1, "one menu cursor")
eq(cursors[1].x, 8, "cursor at wTopMenuItemX 1 -> x 8")
eq(cursors[1].y, 40, "cursor at wTopMenuItemY 3 -> y 40")

check(#icons == 0, "a player screen draws no party icon")

ns = render({ title = "YOUR NAME?", maxLen = 7 })
ns.glyphs = { "R", "E", "D" }
ns:draw()
local typed = drawn("RED")
check(typed ~= nil, "the typed name is drawn")
eq(typed and typed.x, 80, "typed name at hlcoord 10,2 -> x 80")
eq(typed and typed.y, 16, "typed name at hlcoord 10,2 -> y 16")
eq(tiles[4].code, 0x77, "the raised underscore tracks the next free slot")
eq(tiles[4].x, 104, "which is three tiles along")
eq(tiles[3].code, 0x76, "slots behind it stay flat")

ns = render({ title = "YOUR NAME?", maxLen = 7 })
ns.glyphs = { "A", "B", "C", "D", "E", "F", "G" }
ns:draw()
eq(tiles[7].code, 0x77, "a full buffer keeps the LAST underscore raised")
eq(tiles[6].code, 0x76, "and nothing past it")

ns = render({
  title = "NICKNAME?", maxLen = 10, mon = { species = "CHARMANDER" },
})
eq(ns.speciesName, "CHARMANDER", "the species row comes from the mon")
ns:draw()

eq(#icons, 1, "NAME_MON_SCREEN draws the party icon")
eq(icons[1].x, 8, "icon OAM b/c $10 -> x 8")
eq(icons[1].y, 0, "icon OAM b/c $10 -> y 0")

local ic = icons[1].color
check(ic[1] == 1 and ic[2] == 1 and ic[3] == 1 and (ic[4] or 1) == 1,
  "the icon is drawn untinted, not as a black silhouette")

local species = drawn("CHARMANDER")
check(species ~= nil, "the species name is drawn")
eq(species and species.x, 32, "species at hlcoord 4,1 -> x 32")
eq(species and species.y, 8, "species at hlcoord 4,1 -> y 8")
local sc = species and species.color
check(sc and sc[1] == 0 and sc[2] == 0 and sc[3] == 0,
  "and the text after the icon is back to black")

local nick = drawn("NICKNAME?")
check(nick ~= nil, "NICKNAME? is drawn")
eq(nick and nick.x, 8, "NICKNAME? at hlcoord 1,3 -> x 8")
eq(nick and nick.y, 24, "on the underscore row, not the title row")

eq(#tiles, 10, "NAME_LENGTH - 1 underscores for a mon")
eq(tiles[10].x, 152, "the last one ends the screen row")

ns.anim, icons = 0, {}
ns:draw()
check(icons[1] and icons[1].alt == false, "frame 1 for the first 16 steps")
ns.anim, icons = 16, {}
ns:draw()
check(icons[1] and icons[1].alt == true, "frame 2 for the next 16")

-- naming_screen.asm:326
local Assets = require("src.render.Assets")
local realImage, realDraw = Assets.image, love.graphics.draw
local edDraws = {}
love.graphics.draw = function(image, x, y)
  local r, g, b, a = love.graphics.getColor()
  edDraws[#edDraws + 1] = {
    image = image, x = x, y = y, color = { r, g, b, a },
  }
end

local edImage = { getDimensions = function() return 8, 8 end }
Assets.image = function(path)
  if path == "assets/generated/fonts/ed.png" then return edImage end
  error("no such asset: " .. tostring(path))
end
NamingScreen.invalidate()
ns = render({ title = "YOUR NAME?", maxLen = 7 })
edDraws = {}
ns:draw()

eq(#edDraws, 1, "the confirm cell draws one ED tile")
check(edDraws[1] and edDraws[1].image == edImage, "the tile is fonts/ed.png")
eq(edDraws[1] and edDraws[1].x, 144, "ED at hlcoord 18 -> x 144")
eq(edDraws[1] and edDraws[1].y, 104, "ED on the last letter row -> y 104")
local ec = edDraws[1] and edDraws[1].color
check(ec and ec[1] == 0 and ec[2] == 0 and ec[3] == 0,
  "drawn in the grid's black, like every other cell")
check(drawn("ED") == nil, "and never as the two ASCII glyphs E and D")

Assets.image = function(path) error("no such asset: " .. tostring(path)) end
NamingScreen.invalidate()
ns = render({ title = "YOUR NAME?", maxLen = 7 })
edDraws = {}
ns:draw()

eq(#edDraws, 0, "a cache without fonts/ed.png draws no tile")
local edText = drawn("ED")
check(edText ~= nil, "and falls back to the text cell instead of a blank")
eq(edText and edText.x, 144, "at the same column")
eq(edText and edText.y, 104, "and the same row")

love.graphics.draw, Assets.image = realDraw, realImage
NamingScreen.invalidate()

-- naming_screen.asm:487
local OakSpeech = require("src.ui.OakSpeech")
local rival
for _, step in ipairs(OakSpeech.defaultSteps({})) do
  if step.id == "name_rival" then rival = step end
end
check(rival ~= nil, "the speech still has a name_rival step")
eq(rival and rival.title, nil, "the rival step carries no hand-typed title")
local fixtureText = dofile("tests/fixture_data/text.lua")
eq(fixtureText.RivalsTextString .. fixtureText.NameTextString, "RIVAL's NAME?",
  "the rival prompt is RivalsTextString + NameTextString")

T.finish("naming_screen_layout_1947")
