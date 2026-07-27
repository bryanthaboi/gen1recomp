-- The lower dialogue box: bordered 20x6-tile window, typewriter effect,
-- two visible text lines, A to advance.
--
-- Text markers (from the extractor): \n = second line, \v = scroll one
-- line up, \f = page break (wait for A, clear).  {PLAYER}/{RIVAL} etc. are
-- substituted before display.  Pushed on the state stack; pops itself when
-- the text is exhausted and A is pressed, then calls onDone.

local Font = require("src.render.Font")
local Theme = require("src.ui.Theme")

local TextBox = {}
TextBox.__index = TextBox

-- theme-free fallbacks; geometry resolves against Theme.textBox at
-- construction time, so an unthemed boot stays byte-identical
local BOX_TX, BOX_TY, BOX_TW, BOX_TH = 0, 12, 20, 6
local MAX_COLS = 18

-- opts.choice: when the last page has typed out, a YES/NO ChoiceBox pops
-- up over the still-visible text (YesNoChoicePokeCenter and friends);
-- the box then closes and choice(yes) runs instead of onDone.
-- opts.defaultNo starts the cursor on NO.
-- opts.auto: texts with no `prompt` (a text_asm/text_end tail, like
-- _UsedStrengthText) never wait for a button: once the last page has
-- typed out, auto.sound() runs (returning an audio source blocks like
-- WaitForSoundToFinish; nil headless), then auto.delay frames pass
-- (default 3, Delay3) and the box pops itself + calls onDone.  No
-- blinking cursor, no Press_AB beep.
function TextBox.new(game, text, onDone, opts)
  local self = setmetatable({}, TextBox)
  self.game = game
  self.onDone = onDone
  self.choice = opts and opts.choice
  self.defaultNo = opts and opts.defaultNo
  self.auto = opts and opts.auto
  local box = Theme.textBox or {}
  self.boxTx = box.tx or BOX_TX
  self.boxTy = box.ty or BOX_TY
  self.boxTw = box.tw or BOX_TW
  self.boxTh = box.th or BOX_TH
  self.maxCols = box.maxCols or MAX_COLS
  self.textX = (self.boxTx + 1) * 8
  self.line1Y = (self.boxTy + 2) * 8
  self.line2Y = (self.boxTy + 4) * 8
  text = TextBox.substitute(game, text)
  self.pages = TextBox.paginate(text, self.maxCols)
  self.pageIndex = 1
  self.lineIndex = 1
  self.charIndex = 0
  self.shown = {} -- visible lines (max 2), each a list of glyph codes
  self.waiting = false
  self.contAdvance = false
  self.done = false
  self.blink = 0
  self:beginLine()
  return self
end

-- The runtime tokens substitute() knows, as handlers the tokens registry
-- serves.  Each is fn(game, arg) -> replacement, or nil to drop the token.
-- RAM keeps pokered's stale-buffer semantics: give_item copies the item
-- name into stringBuffer, like GiveItem -> CopyToStringBuffer
-- (home/give.asm), and it stays set afterwards.
TextBox.TOKENS = {
  PLAYER = function(game) return game.save.player.name or "RED" end,
  RIVAL = function(game) return game.save.player.rival or "BLUE" end,
  RAM = function(game, arg)
    if arg == "wStringBuffer" then return game.stringBuffer end
    if arg == "wBoxNumString" then return game.boxNumString end
    -- SendNewMonToBox / _SentToBoxText reads the deposited nick here
    if arg == "wBoxMonNicks" then return game.boxMonNicks end
    return nil
  end,
}

function TextBox.registerInto(registry, _, owner)
  for id, handler in pairs(TextBox.TOKENS) do
    registry:register(id, handler, owner)
  end
end

function TextBox.substitute(game, text)
  local Tokens = require("src.script.Tokens")
  local handlers = game.data and game.data.tokens or TextBox.TOKENS
  return Tokens.expand(game, text, handlers)
end

-- Split marked-up text into pages of lines.  \v-scrolled lines become
-- additional lines on the same page (the box scrolls them).
-- pages.contBefore[p][i] is true when line i was preceded by \v (cont):
-- pokered ContText waits for A/B + ▼ before scrolling that line in.
function TextBox.paginate(text, maxCols)
  maxCols = maxCols or (Theme.textBox and Theme.textBox.maxCols) or MAX_COLS
  -- maxCols is a column count, so the budget is that many vanilla 8px
  -- cells.  Measuring in pixels rather than columns is what lets a mod's
  -- variable-advance page wrap correctly (#186).
  local budget = maxCols * 8
  local pages = {}
  local contBefore = {}
  -- Soft-wrap on glyph boundaries, never byte boundaries: a line is over
  -- budget by what it *draws*, and the cut falls between glyphs so a
  -- multi-byte char is never torn in half.
  local function pushLine(lines, conts, line, wait)
    while true do
      local spans = Font.split(line)
      local fit = Font.spansFitting(spans, budget)
      if fit >= #spans then break end
      -- a glyph wider than the whole box still has to advance by one
      fit = math.max(fit, 1)
      local cut = spans[fit].to
      for i = fit, 1, -1 do
        if line:sub(spans[i].from, spans[i].to) == " " then
          cut = spans[i].to
          break
        end
      end
      table.insert(lines, line:sub(1, cut))
      table.insert(conts, wait)
      wait = false
      line = line:sub(cut + 1)
    end
    table.insert(lines, line)
    table.insert(conts, wait)
  end
  for pageText in (text .. "\f"):gmatch("(.-)\f") do
    if pageText ~= "" then
      local lines, conts = {}, {}
      local pos, waitNext = 1, false
      while true do
        local npos = pageText:find("[\n\v]", pos)
        if not npos then
          pushLine(lines, conts, pageText:sub(pos), waitNext)
          break
        end
        pushLine(lines, conts, pageText:sub(pos, npos - 1), waitNext)
        waitNext = pageText:sub(npos, npos) == "\v"
        pos = npos + 1
      end
      if lines[#lines] == "" then
        table.remove(lines)
        table.remove(conts)
      end
      if #lines > 0 then
        table.insert(pages, lines)
        table.insert(contBefore, conts)
      end
    end
  end
  if #pages == 0 then
    pages = { { "" } }
    contBefore = { { false } }
  end
  pages.contBefore = contBefore
  return pages
end

function TextBox:currentLine()
  return self.pages[self.pageIndex][self.lineIndex]
end

function TextBox:beginLine()
  self.charIndex = 0
  self.codes = Font.encode(self:currentLine())
  if #self.shown >= 2 then
    table.remove(self.shown, 1)
    self.scrollPx = 8 -- pixel scroll-up (ScrollTextUpOneLine)
  end
  table.insert(self.shown, {})
end

function TextBox:update(dt)
  local input = self.game.input
  self.blink = (self.blink + 1) % 60
  if self.done then
    if self.auto then
      if not self.autoStarted then
        self.autoStarted = true
        self.autoSrc = self.auto.sound and self.auto.sound() or nil
        self.autoTimer = 0
      end
      if self.autoSrc and self.autoSrc.isPlaying and self.autoSrc:isPlaying() then
        return -- the cry is still sounding (WaitForSoundToFinish)
      end
      -- auto.wait: the pet-NPC cries (PewterNidoranHouseNidoranText,
      -- ViridianNicknameHouseSpearowText) have nothing queued behind the
      -- cry, so DisplayTextID's trailing WaitForTextScrollButtonPress still
      -- runs once it is over -- their maps enable auto text box drawing,
      -- which zeroes wDoNotWaitForButtonPressAfterDisplayingText
      -- (home/window.asm AutoTextBoxDrawingCommon).  Drop the auto gate and
      -- hand the box to the plain A/B path, which also starts the blinking
      -- arrow, instead of popping it (#247, #251).
      if self.auto.wait then
        self.auto = nil
        return
      end
      self.autoTimer = self.autoTimer + 1
      local delay = self.auto.delay or 3
      -- auto.onOverlap: fired once when the delay elapses but before the
      -- box closes, so an overlay (the Pallet "!" bubble) can appear
      -- while the box is still on screen; the box then lingers
      -- auto.overlap more frames before popping (scripts/PalletTown.asm
      -- PalletTownOakText: DelayFrames 10 then EmotionBubble over the
      -- still-shown "Hey! Wait!" box).
      if self.auto.onOverlap and not self.overlapFired
         and self.autoTimer >= delay then
        self.overlapFired = true
        self.auto.onOverlap()
      end
      if self.autoTimer >= delay + (self.auto.overlap or 0) then
        self.game.stack:pop()
        if self.onDone then self.onDone() end
      end
      return
    end
    if self.choice then
      if not self.choicePushed then
        self.choicePushed = true
        local ChoiceBox = require("src.ui.ChoiceBox")
        self.game.stack:push(ChoiceBox.new(self.game, function(yes)
          self.game.stack:pop() -- this text box, under the choice
          self.choice(yes)
        end, { defaultNo = self.defaultNo }))
      end
      return
    end
    if input:wasPressed("a") or input:wasPressed("b") then
      require("src.core.Sound").play(self.game.data, "Press_AB")
      self.game.stack:pop()
      if self.onDone then self.onDone() end
    end
    return
  end
  if self.waiting then
    if input:wasPressed("a") or input:wasPressed("b") then
      require("src.core.Sound").play(self.game.data, "Press_AB")
      self.waiting = false
      if self.contAdvance then
        -- ContText / ManualTextScroll: keep the box, scroll one line
        self.contAdvance = false
        self.lineIndex = self.lineIndex + 1
        self:beginLine()
      else
        self.shown = {}
        self.pageIndex = self.pageIndex + 1
        self.lineIndex = 1
        self:beginLine()
      end
    end
    return
  end
  -- typewriter cadence: one character every N frames, N = the OPTION
  -- text speed (TextSpeedOptionData frame delays 1/3/5); holding A/B
  -- prints every frame like the original's held-button fast path
  local delay = (self.game.save.options and self.game.save.options.textSpeed) or 3
  if delay ~= 1 and delay ~= 3 and delay ~= 5 then delay = 3 end
  if input:isDown("a") or input:isDown("b") then delay = 1 end
  self.charTimer = (self.charTimer or 0) + 1
  while self.charTimer >= delay do
    self.charTimer = self.charTimer - delay
    if self.charIndex < #self.codes then
      self.charIndex = self.charIndex + 1
      local line = self.shown[#self.shown]
      line[#line + 1] = self.codes[self.charIndex]
    else
      -- line finished
      local page = self.pages[self.pageIndex]
      if self.lineIndex < #page then
        local nextIdx = self.lineIndex + 1
        local conts = self.pages.contBefore and self.pages.contBefore[self.pageIndex]
        if conts and conts[nextIdx] then
          -- pokered <CONT>: ▼ + WaitForTextScrollButtonPress before scroll
          self.waiting = true
          self.contAdvance = true
        else
          self.lineIndex = nextIdx
          self:beginLine()
        end
      elseif self.pageIndex < #self.pages then
        self.waiting = true
        self.contAdvance = false
      else
        self.done = true
      end
      break
    end
  end
end

function TextBox:draw()
  Font.drawBox(self.boxTx, self.boxTy, self.boxTw, self.boxTh)
  love.graphics.setColor(0, 0, 0, 1)
  if self.scrollPx and self.scrollPx > 0 then
    self.scrollPx = self.scrollPx - 2
    if self.scrollPx <= 0 then self.scrollPx = nil end
  end
  local off = self.scrollPx or 0
  local ys = { self.line1Y, self.line2Y }
  for i, line in ipairs(self.shown) do
    local y = (ys[i] or self.line2Y) + off
    for j, code in ipairs(line) do
      Font.drawCode(code, self.textX + (j - 1) * 8, y)
    end
  end
  if (self.waiting or (self.done and not self.choice and not self.auto))
     and self.blink < 30 then
    -- page-advance cursor: glyph $EE by default, the blinking down arrow
    -- the original prints via `ld a, "▼"` (home/text.asm)
    Font.drawCode(Theme.moreArrow or 0xEE,
                  (self.boxTx + self.boxTw - 2) * 8,
                  (self.boxTy + self.boxTh - 1) * 8 - 4)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return TextBox
