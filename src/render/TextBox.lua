-- The lower dialogue box: bordered 20x6-tile window, typewriter effect,
-- two visible text lines, A to advance.
--
-- Text markers (from the extractor): \n = second line, \v = scroll one
-- line up, \f = page break (wait for A, clear).  {PLAYER}/{RIVAL} etc. are
-- substituted before display.  Pushed on the state stack; pops itself when
-- the text is exhausted and A is pressed, then calls onDone.

local Font = require("src.render.Font")
local UIVisibility = require("src.battle.UIVisibility")
local Theme = require("src.ui.Theme")
local Timing = require("src.core.Timing")

local TextBox = {}
TextBox.__index = TextBox
TextBox.isTextBox = true

-- theme-free fallbacks; geometry resolves against Theme.textBox at
-- construction time, so an unthemed boot stays byte-identical
local BOX_TX, BOX_TY, BOX_TW, BOX_TH = 0, 12, 20, 6
local MAX_COLS = 18
-- pokegold constants/ram_constants.asm: TEXT_DELAY_FAST/MED/SLOW = 1/3/5
local NAME_DELAYS = { FAST = 1, MID = 3, SLOW = 5 }

-- opts.choice: when the last page has typed out, a YES/NO ChoiceBox pops
-- up over the still-visible text (YesNoChoicePokeCenter and friends);
-- the box then closes and choice(yes) runs instead of onDone.
-- opts.defaultNo starts the cursor on NO.
-- opts.choiceLabels / opts.choiceBox: data/yes_no_menu_strings.asm:16
-- opts.auto: texts with no `prompt` (a text_asm/text_end tail, like
-- _UsedStrengthText) never wait for a button: once the last page has
-- typed out, auto.sound() runs (returning an audio source blocks like
-- WaitForSoundToFinish; nil headless), then auto.delay frames pass
-- (default 3, Delay3) and the box pops itself + calls onDone.  No
-- blinking cursor, no Press_AB beep.
-- opts.auto.tick, when given, runs once per frame for as long as the box
-- is held open.  It is the only per-frame hook a script has while a box is
-- up: StateStack updates the top state only, so the overworld and its
-- ScriptRunner are frozen underneath (the Pewter JIGGLYPUFF dance drives
-- its spin off it, data/scripts/story5.lua, #249).
-- opts.stay: text that ends in `done` rather than `prompt` returns from
-- PrintText with the box still on screen while the caller keeps running
-- (_ViridianSchoolBlackboardText2, data/text/text_2.asm:646).  Such a box
-- waits for nothing, shows no blinking arrow, and never pops itself --
-- whoever pushed it owns the pop.  stay.onShown fires once, on the frame
-- the last page finishes typing, which is where the caller pushes whatever
-- goes on top of it (#591).  stay.prompt waits out one arrowed A/B press
-- first (TextCommand_PROMPT_BUTTON, home/text.asm:434-444) (#1511).
function TextBox.new(game, text, onDone, opts)
  local self = setmetatable({}, TextBox)
  self.game = game
  self.onDone = onDone
  self.choice = opts and opts.choice
  self.defaultNo = opts and opts.defaultNo
  self.choiceNoSound = opts and opts.noSound
  self.choiceLabels = opts and opts.choiceLabels
  self.choiceBox = opts and opts.choiceBox
  self.money = opts and opts.money
  self.auto = opts and opts.auto
  self.stay = opts and opts.stay
  -- engine/events/hidden_events/cinnabar_gym_quiz.asm:119
  self.preSound = opts and opts.preSound
  -- opts.instant: put the LAST page up already typed, with no typewriter and
  -- no page waits.  A `yesorno` follows a `writetext` that has already been
  -- read, so re-typing the line under the YES/NO box would be wrong -- the
  -- cart never closed the box in the first place.
  self.instant = opts and opts.instant
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
  if self.instant then
    self.pageIndex = #self.pages
    -- Both lines of the page at once, which is what the box looks like the
    -- moment before the prompt appears.
    local page = self.pages[self.pageIndex] or {}
    -- The page's LAST two lines, which is what the box is holding.  A `cont`
    -- inside the page ran _ContTextNoPause (home/text.asm:442): TextScroll
    -- twice, then the next line is written at TEXTBOX_INNERY + 2, i.e. the
    -- bottom row.  Taking the first two would walk the text backwards the
    -- instant the prompt appears.
    for index = math.max(1, #page - 1), #page do
      local visible = {}
      for _, code in ipairs(Font.encode(page[index])) do
        if code ~= Font.TEXT_PAUSE_CODE and code ~= Font.TEXT_DOT_WAIT_CODE then
          visible[#visible + 1] = code
        end
      end
      self.shown[#self.shown + 1] = visible
    end
    self.lineIndex = #page
    self.codes = self.shown[#self.shown] or {}
    self.charIndex = #self.codes
    self.done = true
    return self
  end
  self:beginLine()
  return self
end

-- soundOpts: a jingle carried at the end of the string as a trailing text
-- command (sound_get_item_1 and friends -> home/text.asm TextCommand_SOUND),
-- which runs PlaySound then WaitForSoundToFinish once the last page has
-- typed, so the box holds until the fanfare is over.  Merges into a caller's
-- opts table; auto.wait keeps the trailing button press the plain A/B path
-- gives every other box.
function TextBox.soundOpts(game, sound, opts)
  opts = opts or {}
  local auto = opts.auto
  -- auto = true is the no-button-wait arming (text_opts); keep that choice
  if auto == true then auto = { wait = false } end
  auto = auto or {}
  if auto.wait == nil then auto.wait = true end
  auto.delay = auto.delay or 0
  auto.sound = type(sound) == "function" and sound
    or function() return require("src.core.Sound").play(game.data, sound) end
  opts.auto = auto
  return opts
end

-- The runtime tokens substitute() knows, as handlers the tokens registry
-- serves.  Each is fn(game, arg) -> replacement, or nil to drop the token.
-- RAM keeps pokered's stale-buffer semantics: give_item copies the item
-- name into stringBuffer, like GiveItem -> CopyToStringBuffer
-- (home/give.asm), and it stays set afterwards.
TextBox.TOKENS = {
  PLAYER = function(game) return game.save.player.name or "RED" end,
  -- A Gen 1 save keeps the rival on player.rival; a Gold save keeps him at
  -- save.rival.name, seeded "???" by InitializeNPCNames and written by the
  -- NameRival special, whose own InitName fallback (not the seed) is where
  -- "SILVER" comes from (pokegold engine/events/specials.asm
  -- NameRival .DefaultName).  The Gen 1
  -- default must not leak into a Gold textbox: the cart's officer never says
  -- BLUE.  The tail therefore splits by generation rather than ending on the
  -- Gen 1 literal.  A Gold save with no rival record at all is one that never
  -- reached the naming screen, and wRivalName is then still what
  -- InitializeNPCNames seeded it with, "???"
  -- (pokegold engine/menus/intro_menu.asm .Rival).
  RIVAL = function(game)
    local gold = game.save.generation == 2 or game.save.version == "gold"
    return game.save.player.rival
      or (game.save.rival and game.save.rival.name)
      or (gold and "???" or "BLUE")
  end,
  -- Gen 2's TX_RAM points at wStringBuffer2, which getstring / getmonname /
  -- getitemname fill.  An unset buffer prints nothing, the same as the cart's
  -- freshly `@`-filled buffer.
  STRBUF = function(game) return game.stringBuffer end,
  -- Extracted TX_PAUSE / TX_DOTS commands are kept in strings as tokens so
  -- they survive Lua serialization and mod overlays.  Substitution turns
  -- them into zero-width Font sentinels; update() consumes those sentinels at
  -- the exact point in the typewriter stream where the cartridge command ran.
  PAUSE = function() return "\30" end,
  DOTS = function(_, count)
    local n = math.max(0, math.min(255, tonumber(count) or 0))
    return string.rep("…\31", n)
  end,
  RAM = function(game, arg)
    if arg == "wStringBuffer" then return game.stringBuffer end
    if arg == "wNameBuffer" then return game.stringBuffer end
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

function TextBox:visibleText()
  local page = self.pages[self.pageIndex]
  if not page then return nil end
  local out, count = {}, #(self.shown or {})
  for i = math.max(1, self.lineIndex - count + 1), self.lineIndex do
    if page[i] ~= nil then
      out[#out + 1] = page[i]:gsub("[\30\31]", "")
    end
  end
  return #out > 0 and out or nil
end

function TextBox:update(dt)
  local input = self.game.input
  self.blink = (self.blink + 1) % 60
  -- home/text.asm:506
  if self.preSound then
    if not self.preStarted then
      self.preStarted = true
      self.preSrc = self.preSound()
    end
    if self.preSrc and self.preSrc.isPlaying and self.preSrc:isPlaying() then
      return
    end
    self.preSound, self.preSrc = nil, nil
  end
  -- A page or CONT advance blocks the whole box while the original's scroll
  -- and clear run (src/core/Timing.lua TEXT_SCROLL_PAIR / TEXT_PAGE_CLEAR).
  -- Nothing types and no input is read until it drains.
  if (self.holdFrames or 0) > 0 then
    self.holdFrames = self.holdFrames - 1
    return
  end
  if self.done then
    -- opts.stay: the box is finished but stays up under whatever the caller
    -- pushed over it; StateStack updates the top state only, so this runs
    -- exactly once (#591)
    if self.stay then
      if not self.stayShown then
        -- stay.prompt: arrowed A/B wait, then the box stays up
        -- (TextCommand_PROMPT_BUTTON, home/text.asm:434-444)
        if self.stay.prompt
           and not (input:wasPressed("a") or input:wasPressed("b")) then
          return
        end
        if self.stay.prompt then
          require("src.core.Sound").play(self.game.data, "Press_AB")
        end
        self.stayShown = true
        if self.stay.onShown then self.stay.onShown() end
      end
      return
    end
    if self.auto then
      if not self.autoStarted then
        self.autoStarted = true
        self.autoSrc = self.auto.sound and self.auto.sound() or nil
        self.autoTimer = 0
      end
      -- auto.tick: one call per frame for as long as the box is held open,
      -- run before the autoSrc gate so a tick-driven gate can clear itself
      -- on the same frame.  It is the only per-frame hook a script gets
      -- while a box is up, since StateStack updates the top state only and
      -- the overworld underneath is frozen (the Pewter JIGGLYPUFF spin,
      -- #249).
      if self.auto.tick then self.auto.tick() end
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
        end, { defaultNo = self.defaultNo, noSound = self.choiceNoSound,
               labels = self.choiceLabels, box = self.choiceBox,
               -- this box is anchored below it; the pair moves together
               anchor = "bottom" }))
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
    -- _ContText and Paragraph both print the â–¼ and run ProtectedDelay3
    -- before ManualTextScroll starts watching the joypad (home/text.asm:265,
    -- :234), so the arrow is up for three frames that swallow the button.
    if (self.preWait or 0) > 0 then
      self.preWait = self.preWait - 1
      return
    end
    if input:wasPressed("a") or input:wasPressed("b") then
      require("src.core.Sound").play(self.game.data, "Press_AB")
      self.waiting = false
      if self.contAdvance then
        -- ContText / ManualTextScroll: keep the box, scroll one line
        self.contAdvance = false
        self.lineIndex = self.lineIndex + 1
        self:beginLine()
        -- ScrollTextUpOneLine is 5 blocking frames and, as its own comment
        -- says, is "always called twice in a row" (home/text.asm:280-305)
        self.holdFrames = Timing.TEXT_SCROLL_PAIR
      else
        self.shown = {}
        self.pageIndex = self.pageIndex + 1
        self.lineIndex = 1
        self:beginLine()
        -- ClearScreenArea then DelayFrames 20: the box sits empty before the
        -- next page starts typing (home/text.asm:236-240)
        self.holdFrames = Timing.TEXT_PAGE_CLEAR
      end
    end
    return
  end
  -- typewriter cadence: one character every N frames, N = the OPTION
  -- text speed (TextSpeedOptionData frame delays 1/3/5); holding A/B
  -- prints every frame like the original's held-button fast path
  local rawSpeed = self.game.save.options and self.game.save.options.textSpeed
  local delay = NAME_DELAYS[rawSpeed] or rawSpeed or 3
  if delay ~= 1 and delay ~= 3 and delay ~= 5 then delay = 3 end
  if input:isDown("a") or input:isDown("b") then delay = 1 end
  self.charTimer = (self.charTimer or 0) + 1
  while self.charTimer >= delay do
    self.charTimer = self.charTimer - delay
    if self.charIndex < #self.codes then
      self.charIndex = self.charIndex + 1
      local code = self.codes[self.charIndex]
      if code == Font.TEXT_PAUSE_CODE then
        -- TextCommand_PAUSE polls the held buttons before DelayFrames 30.
        if not (input:isDown("a") or input:isDown("b")) then
          self.holdFrames = Timing.TEXT_PAUSE
        end
        break
      elseif code == Font.TEXT_DOT_WAIT_CODE then
        -- TextCommand_DOTS writes one ellipsis, then polls the held buttons
        -- before each ten-frame delay.  The token expands to `… sentinel` for
        -- every requested dot, so the visible glyph was appended immediately
        -- before this event.
        if not (input:isDown("a") or input:isDown("b")) then
          self.holdFrames = Timing.TEXT_DOT
        end
        break
      else
        local line = self.shown[#self.shown]
        line[#line + 1] = code
      end
    else
      -- line finished
      local page = self.pages[self.pageIndex]
      if self.lineIndex < #page then
        local nextIdx = self.lineIndex + 1
        local conts = self.pages.contBefore and self.pages.contBefore[self.pageIndex]
        if conts and conts[nextIdx] then
          -- pokered <CONT>: ▼ + WaitForTextScrollButtonPress before scroll
          self.waiting = true
          self.preWait = Timing.TEXT_PRE_ADVANCE
          self.contAdvance = true
        else
          self.lineIndex = nextIdx
          self:beginLine()
        end
      elseif self.pageIndex < #self.pages then
        self.waiting = true
        self.preWait = Timing.TEXT_PRE_ADVANCE
        self.contAdvance = false
      else
        self.done = true
      end
      break
    end
  end
end

function TextBox:draw()
  if not UIVisibility.bottomVisible(self, true) then return end
  -- The dialogue box belongs against the bottom of the screen, not floating
  -- in the middle of a zoomed-out letterbox.  Declared per frame; the
  -- renderer blits this region to the screen edge and the rest of the UI
  -- where it always was (Renderer:setUIAnchor).
  local r = self.game and self.game.renderer
  if r and r.setUIAnchor then
    r:setUIAnchor(self.boxTx * 8, self.boxTy * 8,
                  self.boxTw * 8, self.boxTh * 8, "bottom")
  end
  -- The box's own tiles are all font-page ($79-$7e frame, ' ' $7f interior),
  -- so they take whatever BG palette 0 colour 0 the screen UNDER the box is
  -- using.  On every Gen 1 screen and nearly every Gold one that is white and
  -- this is nil; the Pokegear's is a pale cream, and a call's pushed textbox
  -- has to sit on the gear's paper rather than paint a white band across it
  -- (pokegold engine/pokegear/pokegear.asm TownMapPals sends every tile
  -- >= $60 to palette 0).  Gen 1's Game has no textboxPaper, so it stays nil.
  local paper = self.game and self.game.textboxPaper and self.game:textboxPaper()
  Font.drawBox(self.boxTx, self.boxTy, self.boxTw, self.boxTh, paper)
  love.graphics.setColor(0, 0, 0, 1)
  if self.scrollPx and self.scrollPx > 0 then
    self.scrollPx = self.scrollPx - 2
    if self.scrollPx <= 0 then self.scrollPx = nil end
  end
  -- Only the retained line carries the offset: it slides up from where it
  -- already sat (line2Y) to line1Y.  The incoming line is drawn at its home
  -- row instead, because offsetting it too put fresh glyphs 8px low -- on the
  -- box's bottom border -- whenever the typewriter beat the 4-frame slide
  -- (#314).  The sub-tile slide is ours to begin with: ScrollTextUpOneLine
  -- (home/text.asm:283) copies the rows up whole and waits 5 frames, so
  -- nothing in the original is ever drawn between two rows.
  local off = self.scrollPx or 0
  local ys = { self.line1Y, self.line2Y }
  for i, line in ipairs(self.shown) do
    local y = (ys[i] or self.line2Y) + (i == 1 and off or 0)
    -- the pen advances per glyph, matching the pixel budget paginate
    -- measured with; every fixed-width page still lands on the 8px grid
    local pen = self.textX
    for _, code in ipairs(line) do
      Font.drawCode(code, pen, y)
      pen = pen + Font.advanceOf(code)
    end
  end
  if self.money then
    -- money box (engine/menus/text_box.asm:130): DisplayMoneyBox at
    -- hlcoord 11,0, the amount right-aligned on its middle row
    Font.drawBox(11, 0, 9, 3)
    love.graphics.setColor(0, 0, 0, 1)
    local money = ("¥%d"):format(self.money() or 0)
    Font.draw(money, 152 - Font.width(money), 8)
  end
  if (self.waiting or (self.done and not self.choice and not self.auto
                       and (not self.stay
                            or (self.stay.prompt and not self.stayShown))))
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
