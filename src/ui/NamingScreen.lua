-- Gen 1 letter-grid naming screen (engine/menus/naming_screen.asm).
-- Full gen-1 glyph grid (data/text/alphabets.asm): five 9-cell rows
-- ending in ED, plus a case-switch row.  A picks a letter, B deletes,
-- SELECT flips case, START or the ED cell confirms.  If opts.presets is
-- given, a "NEW NAME" + presets menu is shown first
-- (engine/menus/main_menu.asm name lists).
-- Pops itself from the stack, then calls opts.onDone(name).
--
-- ui.naming.grid may replace either page; keep an "ED" cell and a
-- single-cell case-switch row so confirm / case-flip keep working.

local Assets = require("src.render.Assets")
local Font = require("src.render.Font")
local HudTiles = require("src.render.HudTiles")
local Runtime = require("src.mods.Runtime")
local Sound = require("src.core.Sound")
local Theme = require("src.ui.Theme")
local Strings = require("src.core.Strings")
local RomText = require("src.core.RomText")

local NamingScreen = { isMenu = true }
NamingScreen.__index = NamingScreen
NamingScreen.isOpaque = true

-- engine/menus/naming_screen.asm:389
local UNDERSCORE, RAISED = 0x76, 0x77
-- engine/gfx/mon_icons.asm:88
local ICON_SPEED = 16

-- engine/menus/naming_screen.asm:326
local ED_IMAGE = "assets/generated/fonts/ed.png"
local edTile

local function drawEd(x, y)
  if edTile == nil then
    local ok, image = pcall(Assets.image, ED_IMAGE)
    edTile = ok and image or false
  end
  if not edTile then return false end
  love.graphics.draw(edTile, x, y)
  return true
end

function NamingScreen.invalidate() edTile = nil end
Assets.register(NamingScreen.invalidate)

-- SGB: generic whole-screen palette (SET_PAL_GENERIC)
function NamingScreen:sgbPalettes(game)
  return require("src.render.PaletteFX").wholeNamed(game.data, "MEWMON")
end

-- both letter pages (wAlphabetCase, data/text/alphabets.asm): row 6 is
-- the case-switch cell, labelled with the page it flips to
local GRID_UPPER = {
  { "A", "B", "C", "D", "E", "F", "G", "H", "I" },
  { "J", "K", "L", "M", "N", "O", "P", "Q", "R" },
  { "S", "T", "U", "V", "W", "X", "Y", "Z", " " },
  { "×", "(", ")", ":", ";", "[", "]", "<PK>", "<MN>" },
  { "-", "?", "!", "♂", "♀", "/", "<DOT>", ",", "ED" },
  { "lower case" },
}
local GRID_LOWER = {
  { "a", "b", "c", "d", "e", "f", "g", "h", "i" },
  { "j", "k", "l", "m", "n", "o", "p", "q", "r" },
  { "s", "t", "u", "v", "w", "x", "y", "z", " " },
  { "×", "(", ")", ":", ";", "[", "]", "<PK>", "<MN>" },
  { "-", "?", "!", "♂", "♀", "/", "<DOT>", ",", "ED" },
  { "UPPER CASE" },
}

-- locate the ED confirm cell and the case-switch row on a (possibly
-- modded) grid; falls back to vanilla coordinates
local function findMeta(grid)
  local caseRow, edRow, edCol = #grid, 5, 9
  for r, row in ipairs(grid) do
    if #row == 1 and (row[1] == "lower case" or row[1] == "UPPER CASE"
                      or row[1] == "lower" or row[1] == "UPPER") then
      caseRow = r
    end
    for c, cell in ipairs(row) do
      if cell == "ED" then edRow, edCol = r, c end
    end
  end
  return caseRow, edRow, edCol
end

local function sameGrid(grid) return grid end

function NamingScreen.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, NamingScreen)
  self.game = game
  -- engine/menus/naming_screen.asm:456, :481
  self.title = opts.title or (RomText(game.data, "YourTextString", nil)
    .. RomText(game.data, "NameTextString", nil))
  self.presets = opts.presets
  self.introBox = opts.introBox
  self.maxLen = opts.maxLen or 7
  self.default = opts.default
  self.onDone = opts.onDone
  self.glyphs = {} -- typed glyphs; multi-byte cells (<PK>, ♂, ×) count as 1
  self.row, self.col = 1, 1
  self.lower = false
  -- engine/menus/naming_screen.asm:460
  self.mon = opts.mon
  self.speciesName = opts.speciesName
  if self.mon and not self.speciesName then
    local def = game and game.data and game.data.pokemon
      and game.data.pokemon[self.mon.species]
    self.speciesName = (def and def.name) or self.mon.species
  end
  self.anim = 0
  return self
end

function NamingScreen:enter()
  if self.presets and #self.presets > 0 then
    local Menu = require("src.ui.Menu")
    -- engine/movie/oak_speech/oak_speech2.asm:1
    self.choosing = true
    self.isOpaque = false
    local items = { {
      label = Strings("NEW NAME"),
      onSelect = function()
        self.choosing = nil
        self.isOpaque = nil
      end,
    } }
    for _, preset in ipairs(self.presets) do
      table.insert(items, {
        label = preset,
        onSelect = function()
          -- the menu already popped itself; pop the naming screen too
          self.game.stack:pop()
          if self.onDone then self.onDone(preset, false) end
        end,
      })
    end
    if self.introBox then
      -- DisplayIntroNameTextBox (oak_speech2.asm:162): TextBoxBorder at
      -- hlcoord 0,0 with b=$a c=$9, "NAME" at hlcoord 3,0, list at hlcoord 2,2
      -- TextBoxBorder's b = $a is a fixed 12-row box, whatever the preset
      -- list's length (oak_speech2.asm:163-166)
      self.game.stack:push(Menu.new(self.game, items, {
        tx = 0, ty = 0, tw = 11, th = 12,
        itemY = 2, title = Strings("NAME"), cancelable = false,
      }))
    else
      self.game.stack:push(Menu.new(self.game, items, {
        tx = 4, ty = 0, tw = 12, th = #items * 2 + 2, cancelable = false,
      }))
    end
  end
end

-- engine/menus/naming_screen.asm:88
local REPROMPT_WHITE_FRAMES = 45

function NamingScreen:confirm()
  local name = table.concat(self.glyphs)
  if name == "" and self.presets and #self.presets > 0 then
    -- engine/movie/oak_speech/oak_speech2.asm:20
    self.row, self.col = 1, 1
    self.anim = 0
    self.whiteout = REPROMPT_WHITE_FRAMES
    return
  end
  if name == "" then
    -- An empty confirm (START, or the ED cell with nothing typed) must not
    -- invent a letter (#833).  DisplayNamingScreen seeds wStringBuffer with
    -- '@' (engine/menus/naming_screen.asm) and every caller checks that first
    -- byte: AskName falls through to .declinedNickname, copying the species
    -- name over the nick slot -- vanilla's "un-nicknamed", which this port
    -- models as mon.nickname == nil (src/save_convert/GenSave.lua), so
    -- evolution can still rename the mon.  DisplayNameRaterScreen takes
    -- .playerCancelled and keeps the old nick, which is why an explicit
    -- opts.default still wins here.  Player/rival naming
    -- (oak_speech2.asm ChoosePlayerName) re-opens on '@' and never accepts an
    -- empty result.
    -- Contract for callers: "" means NO name -- BattleState:askNicknameUI and
    -- Commands.give_pokemon both guard on #name > 0 before setting nickname.
    name = self.default or ""
  end
  Sound.play(self.game.data, "Press_AB")
  self.game.stack:pop()
  if self.onDone then self.onDone(name, true) end
end

function NamingScreen:grid()
  local base = self.lower and GRID_LOWER or GRID_UPPER
  if not Runtime.wantsHook("ui.naming.grid") then return base end
  local hooked = Runtime.call("ui.naming.grid", sameGrid, base, {
    lower = self.lower and true or false,
    title = self.title,
    maxLen = self.maxLen,
    game = self.game,
  })
  if type(hooked) ~= "table" or #hooked == 0 then return base end
  return hooked
end

-- Gen 1 jumps the cursor to ED once the name is full.
function NamingScreen:jumpToEnd()
  local _, edRow, edCol = findMeta(self:grid())
  self.row, self.col = edRow, edCol
end

function NamingScreen:update(dt)
  if (self.whiteout or 0) > 0 then
    self.whiteout = self.whiteout - 1
    return
  end
  -- engine/menus/naming_screen.asm:131
  self.anim = (self.anim or 0) + 1
  local GRID = self:grid()
  local caseRow, edRow, edCol = findMeta(GRID)
  local input = self.game.input
  if input:wasPressed("start") then
    self:confirm()
    return
  end
  if input:wasPressed("select") then -- SELECT also flips the case page
    self.lower = not self.lower
    return
  end
  if input:wasPressed("up") then
    -- wrapping up from the top row lands on the case-switch cell
    self.row = self.row > 1 and self.row - 1 or caseRow
    self.col = math.min(self.col, #GRID[self.row])
  elseif input:wasPressed("down") then
    self.row = self.row < #GRID and self.row + 1 or 1
    self.col = math.min(self.col, #GRID[self.row])
  elseif input:wasPressed("left") then
    -- no horizontal movement on the case-switch row
    if self.row ~= caseRow then
      self.col = self.col > 1 and self.col - 1 or #GRID[self.row]
    end
  elseif input:wasPressed("right") then
    if self.row ~= caseRow then
      self.col = self.col < #GRID[self.row] and self.col + 1 or 1
    end
  else
    -- Prefer A over B when both edges fire in one frame (love-nx dual
    -- gamepad+raw path historically set both; erase must not win).
    local pressedA = input:wasPressed("a")
    local pressedB = input:wasPressed("b")
    if pressedA and pressedB then pressedB = false end
    if pressedB then
      table.remove(self.glyphs)
    elseif pressedA then
      if self.row == edRow and self.col == edCol then
        self:confirm()
        return
      end
      if self.row == caseRow then
        self.lower = not self.lower
        return
      end
      if #self.glyphs < self.maxLen then
        Sound.play(self.game.data, "Press_AB")
        table.insert(self.glyphs, GRID[self.row][self.col])
        if #self.glyphs >= self.maxLen then self:jumpToEnd() end
      end
    end
  end
end

function NamingScreen:draw()
  if self.choosing then return end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)
  if (self.whiteout or 0) > 0 then return end
  love.graphics.setColor(0, 0, 0, 1)
  -- engine/menus/naming_screen.asm:453
  if self.mon then
    -- engine/gfx/mon_icons.asm:234
    local PartyMenu = require("src.ui.PartyMenu")
    love.graphics.setColor(1, 1, 1, 1)
    PartyMenu.drawIcon(self.game, self.mon, 8, 0, false, 0,
      math.floor((self.anim or 0) / ICON_SPEED) % 2 == 1)
    love.graphics.setColor(0, 0, 0, 1)
    Font.draw(self.speciesName or "", 32, 8)
    Font.draw(self.title, 8, 24)
  else
    Font.draw(self.title, 0, 8)
  end
  -- engine/menus/naming_screen.asm:369
  Font.draw(table.concat(self.glyphs), 80, 16)
  local raised = math.min(#self.glyphs, self.maxLen - 1)
  for i = 0, self.maxLen - 1 do
    HudTiles.namingTile(i == raised and RAISED or UNDERSCORE, 80 + i * 8, 24)
  end
  -- engine/menus/naming_screen.asm:99
  Font.drawBox(0, 4, 20, 11)
  love.graphics.setColor(0, 0, 0, 1)
  -- engine/menus/naming_screen.asm:346
  for r, row in ipairs(self:grid()) do
    for c, cell in ipairs(row) do
      local x, y = c * 16, 24 + r * 16
      if cell ~= "ED" or not drawEd(x, y) then
        Font.draw(Strings(cell), x, y)
      end
    end
  end
  Font.drawCode(Theme.cursor, self.col * 16 - 8, 24 + self.row * 16)
  love.graphics.setColor(1, 1, 1, 1)
end

return NamingScreen
