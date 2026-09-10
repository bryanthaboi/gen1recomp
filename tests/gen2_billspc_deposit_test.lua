--   luajit tests/gen2_billspc_deposit_test.lua
-- engine/pokemon/bills_pc.asm:117, home/pokemon.asm:124-127, pokegold home/pokemon.asm:101-107

package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 bills pc deposit")
local check, eq = S.check, S.eq

love = require("tests.love_stub")

local BoxMenu = require("src.ui.gen2.BoxMenu")
local Boxes = require("src.core.gen2.Boxes")
local Chrome = require("src.ui.gen2.Chrome")
local Font = require("src.render.Font")
local GameVersion = require("src.core.GameVersion")
local Sound = require("src.core.Sound")

local function mon(species)
  return { species = species, nickname = species, name = species,
    level = 5, hp = 20, maxHp = 20 }
end

local function newInput()
  local input = { pressed = {} }
  function input:press(...)
    for _, button in ipairs({ ... }) do self.pressed[button] = true end
  end
  function input:wasPressed(button)
    if self.pressed[button] then
      self.pressed[button] = nil
      return true
    end
    return false
  end
  function input:isDown() return false end
  return input
end

local function newGame(save)
  local input = newInput()
  return {
    input = input,
    save = save,
    data = { audio = { cries = { TYRANITAR = {}, CYNDAQUIL = {}, GEODUDE = {} } },
      pokemon = {} },
    stack = { _items = {},
      push = function(self, s) self._items[#self._items + 1] = s end,
      pop = function(self) return table.remove(self._items) end,
      top = function(self) return self._items[#self._items] end,
    },
  }, input
end

local function newSave()
  local save = { party = { mon("TYRANITAR"), mon("CYNDAQUIL"), mon("TOTODILE") },
    boxes = {}, boxNames = {}, currentBox = 1 }
  Boxes.box(save, 1)[1] = mon("GEODUDE")
  return save
end

local function press(screen, input, ...)
  for _, button in ipairs({ ... }) do
    input:press(button)
    screen:update(0)
  end
end

local function open(mode)
  local save = newSave()
  local game, input = newGame(save)
  local menu = BoxMenu.new(game, { save = save, mode = mode,
    onClose = function() end })
  return menu, input, save
end

local rec
local realDrawCode, realBox, realPrint = Font.drawCode, Chrome.box, Chrome.print
local realRect, realFill = love.graphics.rectangle, nil
Font.drawCode = function(code, x, y)
  rec.codes[#rec.codes + 1] = { code = code, x = x, y = y }
end
Chrome.box = function(tx, ty, tw, th)
  rec.boxes[#rec.boxes + 1] = { tx, ty, tw, th }
  realBox(tx, ty, tw, th)
end
Chrome.print = function(text, tx, ty)
  rec.prints[#rec.prints + 1] = { text = text, tx = tx, ty = ty }
end
love.graphics.rectangle = function(mode, x, y, w, h)
  rec.rects[#rec.rects + 1] = { mode = mode, x = x, y = y, w = w, h = h }
end

local function draw(menu)
  rec = { codes = {}, boxes = {}, prints = {}, rects = {} }
  menu:draw()
  return rec
end

local cryPlaying = false
local realPlayCry = Sound.playCry
Sound.playCry = function() return { isPlaying = function() return cryPlaying end } end

do
  GameVersion.set("gold")
  local menu = open("deposit")
  local r = draw(menu)
  local atCorner = {}
  for _, g in ipairs(r.codes) do
    if g.x == 8 * 8 and g.y == 2 * 8 then atCorner[#atCorner + 1] = g.code end
  end
  eq(#atCorner, 2, "row 2's left corner is painted exactly twice (list tl, header bl)")
  eq(atCorner[#atCorner], Font.BORDER.bl, "and the header's '└' lands last")
  local order = {}
  for _, b in ipairs(r.boxes) do
    if b[1] == 8 and (b[2] == 0 or b[2] == 2) then order[#order + 1] = b[2] end
  end
  eq(order[1], 2, "the list box is drawn first")
  eq(order[2], 0, "and the header box over it")
end

do
  GameVersion.set("gold")
  local menu = open("deposit")
  local f = menu:selectionFrameRect(1)
  eq(f.x .. "," .. f.y .. "," .. f.w .. "," .. f.h, "71,25,80,16", "Gold's frame is 80x16 at (71,25)")
  check(not f.rounded, "with square corners")
  f = menu:selectionFrameRect(2)
  eq(f.y, 41, "row 2 sits 16px lower")
  local r = draw(menu)
  local line
  for _, q in ipairs(r.rects) do if q.mode == "line" then line = q end end
  check(line and line.x == 71.5 and line.y == 25.5 and line.w == 79 and line.h == 15,
    "Gold draws one outline rectangle at those pixels")

  GameVersion.set("crystal")
  menu = open("deposit")
  f = menu:selectionFrameRect(1)
  eq(f.x .. "," .. f.y .. "," .. f.w .. "," .. f.h, "70,29,83,13", "Crystal's frame is 83x13 at (70,29)")
  check(f.rounded, "with rounded corners")
  r = draw(menu)
  local fills = {}
  for _, q in ipairs(r.rects) do
    if q.mode == "fill" and q.h == 1 and q.w == 79 then fills[#fills + 1] = q end
  end
  eq(#fills, 2, "two 79px horizontal runs")
  eq(fills[1].x .. "," .. fills[1].y, "72,29", "top line y=29 x=72..150")
  eq(fills[2].x .. "," .. fills[2].y, "72,41", "bottom line y=41")
  local sides, corners = {}, {}
  for _, q in ipairs(r.rects) do
    if q.mode == "fill" and q.w == 1 and q.h == 9 then sides[#sides + 1] = q.x end
    if q.mode == "fill" and q.w == 1 and q.h == 1 then corners[#corners + 1] = q.x .. "," .. q.y end
  end
  table.sort(sides)
  eq(sides[1] .. "," .. sides[2], "70,152", "sides at x=70 and x=152")
  table.sort(corners)
  eq(table.concat(corners, " "), "151,30 151,40 71,30 71,40", "corner pixels inset by one")
  local anyLine = false
  for _, q in ipairs(r.rects) do if q.mode == "line" then anyLine = true end end
  check(not anyLine, "and no square outline on Crystal")
end

do
  GameVersion.set("gold")
  local menu, input = open("deposit")
  check(menu:selectionFrameVisible(), "the frame is up while browsing the list")
  press(menu, input, "a")
  eq(menu.phase, "submenu", "A opens DEPOSIT/STATS/RELEASE/CANCEL")
  check(not menu:selectionFrameVisible(), "ClearSprites: no frame under the submenu")
  local r = draw(menu)
  local frameRects = 0
  for _, q in ipairs(r.rects) do
    if q.mode == "line" or (q.mode == "fill" and q.w <= 83 and q.h <= 16
        and q.y >= 24 and q.y <= 41 and q.x >= 70) then
      frameRects = frameRects + 1
    end
  end
  eq(frameRects, 0, "and drawPanel paints none of it")
  press(menu, input, "b")
  check(menu:selectionFrameVisible(), "B brings the list and its frame back")
end

do
  GameVersion.set("crystal")
  local menu, input, save = open("deposit")
  cryPlaying = true
  press(menu, input, "a", "a")
  eq(#save.party, 2, "DEPOSIT moved the mon")
  eq(Boxes.box(save, 1)[2].nickname, "TYRANITAR", "into the current box")
  check(menu.cryWait ~= nil, "Crystal enters the cry wait")
  eq(menu.message, nil, "with no message yet")
  eq(menu.panelCleared, nil, "and the left panel intact")
  eq(menu:panelMon().nickname, "TYRANITAR", "still showing the deposited mon")
  eq(menu.phase, "submenu", "under the submenu")
  check(not menu:selectionFrameVisible(), "and no frame")
  local r = draw(menu)
  local storedPrinted = false
  for _, p in ipairs(r.prints) do
    if type(p.text) == "string" and p.text:find("Stored") then storedPrinted = true end
  end
  check(not storedPrinted, "nothing says Stored yet")

  press(menu, input, "a")
  press(menu, input, "a")
  check(menu.cryWait ~= nil and menu.message == nil, "two frames in, still waiting")
  cryPlaying = false
  menu:update(0)
  eq(menu.cryWait, nil, "the wait ends when the cry does")
  eq(menu.message, "Stored TYRANITAR!", "and Stored prints")
  eq(menu.messageFrames, 50, "for the 50-frame hold")
  eq(menu.panelCleared, true, "with the panel cleared")
  eq(menu:panelMon().nickname, "CYNDAQUIL", "panelMon falls back to the selection")

  menu, input = open("deposit")
  cryPlaying = true
  press(menu, input, "a", "a")
  for _ = 1, 180 do menu:update(0) end
  check(menu.cryWait ~= nil, "180 frames of a stuck cry are tolerated")
  menu:update(0)
  eq(menu.cryWait, nil, "frame 181 lets go")
  eq(menu.message, "Stored TYRANITAR!", "and holds the message")

  menu, input = open("withdraw")
  cryPlaying = true
  press(menu, input, "a", "a")
  check(menu.cryWait ~= nil, "WITHDRAW waits on the cry too")
  eq(menu:panelMon().nickname, "GEODUDE", "showing the withdrawn mon")
  cryPlaying = false
  for _ = 1, 3 do menu:update(0) end
  eq(menu.message, "Got GEODUDE!", "then Got prints")
end

do
  GameVersion.set("gold")
  local menu, input = open("deposit")
  cryPlaying = true
  press(menu, input, "a", "a")
  eq(menu.cryWait, nil, "Gold has no cry wait")
  eq(menu.message, "Stored TYRANITAR!", "Stored prints at once")
  eq(menu.messageFrames, 50, "with the 50-frame hold")
  eq(menu.panelCleared, true, "and the panel cleared")
end

do
  GameVersion.set("crystal")
  local menu, input = open("deposit")
  eq(table.concat(menu:messageBox({ "Stored X!" }), ","), "0,15,20,3", "one line: Textbox (0,15) 1x18")
  eq(table.concat(menu:messageBox({ "a", "b" }), ","), "0,12,20,6", "two lines keep the tall box")
  cryPlaying = false
  press(menu, input, "a", "a")
  for _ = 1, 3 do menu:update(0) end
  eq(menu.message, "Stored TYRANITAR!", "Stored is up")
  local r = draw(menu)
  local box = r.boxes[#r.boxes]
  for _, b in ipairs(r.boxes) do if b[1] == 0 then box = b end end
  eq(table.concat(box, ","), "0,15,20,3", "drawPanel draws the one-row box")
  local at
  for _, p in ipairs(r.prints) do if p.text == "Stored TYRANITAR!" then at = p end end
  check(at and at.tx == 1 and at.ty == 16, "with the string at (1,16)")
  local tall = false
  for _, b in ipairs(r.boxes) do if b[1] == 0 and b[2] == 12 then tall = true end end
  check(not tall, "and no 6-row box")
end

Font.drawCode, Chrome.box, Chrome.print = realDrawCode, realBox, realPrint
love.graphics.rectangle = realRect
Sound.playCry = realPlayCry
GameVersion.set("red")

S.finish()
