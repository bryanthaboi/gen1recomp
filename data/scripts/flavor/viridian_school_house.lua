-- Viridian School House's two readables (data/events/hidden_events.asm,
-- hidden_events_for VIRIDIAN_SCHOOL_HOUSE):
--   hidden_text_predef 3, 0  PrintBlackboardLinkCableText, ViridianSchoolBlackboard
--   hidden_text_predef 3, 4  PrintNotebookText, ViridianSchoolNotebook
-- tools/extract/field.py only parses `hidden_event` rows, so neither
-- hidden_text_predef row reaches data/generated/field.lua and both tiles
-- were dead A presses (#503).  Same hook shape, and the same sibling asm
-- file, as the Celadon roof house in data/scripts/celadon_eevee.lua (#391);
-- hidden_text_predef spends the facing byte on the tx_pre id, so neither
-- tile gates on facing.

local Font = require("src.render.Font")
local Theme = require("src.ui.Theme")
local TextBox = require("src.render.TextBox")

-- ViridianSchoolBlackboard (engine/events/hidden_events/school_blackboard.asm):
-- StatusAilmentText1/2 are the two columns of the 12x8 box at the top left
-- (hlcoord 0, 0 + `lb bc, 6, 10`); picking a status prints its
-- ViridianBlackboardStatusPointers entry and jumps back to .blackboardLoop,
-- QUIT or B falls through to .exitBlackboard.
local STATUS_LABELS = {
  { " SLP", "_ViridianBlackboardSleepText" },
  { " PSN", "_ViridianBlackboardPoisonText" },
  { " PAR", "_ViridianBlackboardPrlzText" },
  { " BRN", "_ViridianBlackboardBurnText" },
  { " FRZ", "_ViridianBlackboardFrozenText" },
}

-- The headings list is a two-column menu, which src/ui/Menu.lua does not do
-- (it stacks one column), so the layout lives here (#591).  .blackboardLoop:
-- TextBoxBorder at hlcoord 0, 0 with `lb bc, 6, 10` is the 12x8 box,
-- StatusAilmentText1 (" SLP"/" PSN"/" PAR") is placed at hlcoord 1, 2 and
-- StatusAilmentText2 (" BRN"/" FRZ"/" QUIT") at hlcoord 6, 2.  LEFT/RIGHT
-- move wTopMenuItemX between those two columns and swap wMenuItemOffset
-- between 0 and 3 while leaving wCurrentMenuItem (the row) alone; UP/DOWN
-- are not in wMenuWatchedKeys, so they only slide the cursor and loop.
local BOARD_LABELS = {}
for i, row in ipairs(STATUS_LABELS) do BOARD_LABELS[i] = row[1] end
BOARD_LABELS[#BOARD_LABELS + 1] = " QUIT"
local BOARD_COL_X = { 1, 6 }
local BOARD_ROW_Y = 2
local BOARD_ROWS = 3

local StatusBoard = {}
StatusBoard.__index = StatusBoard

function StatusBoard.new(game, onPick, onQuit)
  return setmetatable({ game = game, col = 1, row = 1, labels = BOARD_LABELS,
                        onPick = onPick, onQuit = onQuit }, StatusBoard)
end

-- flat index = pokered's wMenuItemOffset (0 or 3) + wCurrentMenuItem (0..2),
-- so 1..5 are the statuses in ViridianBlackboardStatusPointers order and 6
-- is QUIT
function StatusBoard:selection()
  return (self.col - 1) * BOARD_ROWS + self.row
end

function StatusBoard:update()
  local input = self.game.input
  if input:wasPressed("up") then
    -- wMenuWrappingEnabled is never set here, so both ends are hard stops
    if self.row > 1 then self.row = self.row - 1 end
  elseif input:wasPressed("down") then
    if self.row < BOARD_ROWS then self.row = self.row + 1 end
  elseif input:wasPressed("left") then
    self.col = 1
  elseif input:wasPressed("right") then
    self.col = 2
  elseif input:wasPressed("a") or input:wasPressed("b") then
    -- HandleMenuInput_ (home/window.asm) beeps for the PAD_A | PAD_B branch,
    -- and B and QUIT share .exitBlackboard
    require("src.core.Sound").play(self.game.data, "Press_AB")
    local sel = self:selection()
    if input:wasPressed("b") or sel > #STATUS_LABELS then
      self.onQuit()
    else
      self.onPick(sel)
    end
  end
end

function StatusBoard:draw()
  Font.drawBox(0, 0, 12, 8)
  love.graphics.setColor(0, 0, 0, 1)
  for i, label in ipairs(BOARD_LABELS) do
    local col = i <= BOARD_ROWS and 1 or 2
    local row = i - (col - 1) * BOARD_ROWS
    Font.draw(label, BOARD_COL_X[col] * 8, (BOARD_ROW_Y + row - 1) * 8)
  end
  -- wTopMenuItemX equals the column PlaceString started at, so the cursor
  -- covers the blank each label leads with
  Font.drawCode(Theme.cursor, BOARD_COL_X[self.col] * 8,
                (BOARD_ROW_Y + self.row - 1) * 8)
  love.graphics.setColor(1, 1, 1, 1)
end

local function blackboard(game)
  local text = game.data.text or {}
  local openBoard
  -- wCurrentMenuItem / wMenuItemOffset are zeroed once, above .blackboardLoop,
  -- and nothing inside the loop clears them again: after a status blurb
  -- `jp .blackboardLoop` comes back with the cursor still on the row and
  -- column the player just picked.  One StatusBoard lives for the whole
  -- reading and is re-pushed each pass, so only entering the blackboard
  -- resets to the left column / top row (#591).
  local board
  -- .blackboardLoop reprints ViridianSchoolBlackboardText2 and only then
  -- calls HandleMenuInput, so the prompt is on screen for exactly as long as
  -- the headings list is.  That text ends in `done`, not `prompt`
  -- (data/text/text_2.asm:646), so PrintText returns with the box still up
  -- and never waits for a button: TextBox opts.stay holds it open under the
  -- list and these callbacks pop the pair together (#591).
  local function closeBoard()
    game.stack:pop() -- the headings list
    game.stack:pop() -- the held "Which heading" box under it
  end
  local function pick(i)
    closeBoard()
    game.stack:push(TextBox.new(game,
      text[STATUS_LABELS[i][2]] or STATUS_LABELS[i][1], openBoard))
  end
  function openBoard()
    game.stack:push(TextBox.new(game,
      text._ViridianSchoolBlackboardText2 or "Which heading do\nyou want to read?",
      nil, { stay = { onShown = function()
        board = board or StatusBoard.new(game, pick, closeBoard)
        game.stack:push(board)
      end } }))
  end
  game.stack:push(TextBox.new(game,
    text._ViridianSchoolBlackboardText1
      or "The blackboard\ndescribes POKéMON\vSTATUS changes\vduring battles.",
    openBoard))
end

-- ViridianSchoolNotebook (engine/events/hidden_events/school_notebooks.asm):
-- pages 1-3 each end in TurnPageSchoolNotebook (TurnPageText + YesNoChoice)
-- and NO stops the read; page 4 turns without asking and runs straight into
-- page 5, the girl catching you at it.
local function notebook(game)
  local text = game.data.text or {}
  local function page(n, after)
    return TextBox.new(game, text["_ViridianSchoolNotebookText" .. n] or "", after)
  end
  local function turnPage(nextPage)
    return function()
      game.stack:push(TextBox.new(game, text._TurnPageText or "Turn the page?",
        nil, { choice = function(yes)
          if yes then game.stack:push(nextPage()) end
        end }))
    end
  end
  local function page5() return page(5) end
  local function page4() return page(4, function() game.stack:push(page5()) end) end
  local function page3() return page(3, turnPage(page4)) end
  local function page2() return page(2, turnPage(page3)) end
  game.stack:push(page(1, turnPage(page2)))
end

return {
  VIRIDIAN_SCHOOL_HOUSE = {
    onInteract = function(game, ow, fx, fy)
      if fx == 3 and fy == 0 then
        blackboard(game)
        return true
      end
      if fx == 3 and fy == 4 then
        notebook(game)
        return true
      end
      return false
    end,
  },
}
