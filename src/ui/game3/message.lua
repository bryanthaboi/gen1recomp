-- game3 dialog TextPrinter (FRLG field message semantics).
-- Variable-width latin_normal glyphs, typewriter pacing, explicit \\n only.

local TextIR = require("src.core.game3.scripting.text_ir")
local FrlgFont = require("src.ui.game3.frlg_font")
local Chrome = require("src.ui.game3.chrome")
local Display = require("src.core.game3.display")

local Message = {}

local RS_AUTO = "src.ui.game3.rs.field_auto_scroll_message"
local function rsPrinter()
  local p = package.loaded[RS_AUTO]
  return p and p.ownsFrame() and p or nil
end

Message.open = false
Message._pages = nil
Message._page = 1
Message._done = nil
Message._stay = false
Message._choice = nil
Message._frame = "dialogue"

-- Typewriter state for the current page.
Message._revealed = 0
Message._total = 0
Message._delay = 0
Message._waiting = false -- page fully revealed; waiting for A/B
Message._speedIdx = 1 -- 0 slow / 1 mid / 2 fast
Message._speedUp = false
Message._spedUp = false
Message._delayTick = false

-- pret sTextSpeedFrameDelays (options 0/1/2)
local SPEED_DELAYS = { 8, 4, 1 }

local function liveSession()
  local Runtime = package.loaded["src.core.game3.runtime"]
  local s = Runtime and Runtime.session
  return type(s) == "table" and s or nil
end

local placeholderCache = {}

-- pokeemerald/src/strings.c:6
local function cartPlaceholders(extracted, game)
  local Extract = require("src.import.gba.text_placeholders_extract")
  local RomText = require("src.core.game3.rom_text")
  local symbols = Extract.symbolsFor(game)
  local function value(name)
    local label = symbols[name]
    if label and RomText.has(label) then return RomText.plain(label) end
    return extracted[name]
  end
  local out, byGender = {}, {}
  for name, v in pairs(extracted) do out[name] = v end
  for name in pairs(symbols) do out[name] = value(name) end
  for name, pair in pairs(extracted.byGender or {}) do byGender[name] = pair end
  for name, pair in pairs(Extract.BY_GENDER) do
    byGender[name] = { male = out[pair.male], female = out[pair.female] }
  end
  out.byGender = byGender
  return out
end
Message.cartPlaceholders = cartPlaceholders

-- pokeemerald/src/string_util.c:456
TextIR.setContextProvider(function(kind, dialect, ctx)
  if kind == "gender" then
    local s = liveSession()
    return s and s.gender or nil
  end
  if kind == "playerName" then
    local s = liveSession()
    local name = s and (s.name or s.playerName)
    return (type(name) == "string" and name ~= "") and name or nil
  end
  if kind == "rivalName" or kind == "stringVars" then
    local Sp = package.loaded["src.core.game3.scripting.space"]
    local vm = Sp and Sp.vm
    if not vm then return nil end
    if kind == "stringVars" then return vm.ctx and vm.ctx.stringVars end
    local a = vm.adapters
    local r = a and a.rivalName
    if type(r) == "function" then r = r() end
    return r or (vm.ctx and vm.ctx.rivalName)
  end
  if kind ~= "placeholders" or not dialect.placeholders then return nil end
  local GameVersion = require("src.core.GameVersion")
  local s = liveSession()
  local id = (s and s.version) or GameVersion.get() or ""
  local Sp = package.loaded["src.core.game3.scripting.space"]
  local bundle = Sp and Sp.bundle
  local hit = placeholderCache[id]
  if hit and hit.bundle == bundle then return hit.values end
  local okC, CacheFs = pcall(require, "src.import.CacheFs")
  local t = okC and CacheFs.loadActive(dialect.placeholders) or nil
  if type(t) == "table" then
    placeholderCache[id] = { bundle = bundle, values = cartPlaceholders(t, id) }
    return placeholderCache[id].values
  end
  return nil
end)

local function split_pages(box)
  local pages = TextIR.splitPages(box)
  if #pages == 0 then pages[1] = box or "" end
  return pages
end

local function braille()
  local ok, Braille = pcall(require, "src.ui.game3.braille")
  if ok and type(Braille) == "table" then return Braille end
  return nil
end

local function beginPage()
  local page = Message.currentPage() or ""
  local B = Message._frame == "braille" and braille()
  Message._total = B and B.countGlyphs(page) or FrlgFont.countChars(page)
  Message._revealed = 0
  Message._delay = 0
  Message._arrowTicks = 0
  Message._waiting = (Message._total == 0)
  Message._speedUp = false
  Message._delayTick = false
  -- pokefirered/src/text_printer.c:91
  if Message._frame == "braille" then
    Message._revealed = Message._total
    Message._waiting = true
  end
end

function Message.setFrame(kind)
  if kind == "sign" then
    Message._frame = "sign"
  elseif kind == "braille" then
    -- pokefirered/src/scrcmd.c:1558
    Message._frame = "braille"
  elseif kind == "battle" then
    Message._frame = "battle"
  elseif kind == "voiceover" then
    -- pokefirered/src/battle_bg.c:359
    Message._frame = "voiceover"
  else
    Message._frame = "dialogue"
  end
end

function Message.frameKind()
  return Message._frame or "dialogue"
end

function Message.show(text, opts)
  local p = rsPrinter()
  if p then
    if p.isPrinting() then return Message end
    p.close()
  end
  if type(opts) == "function" then
    opts = { done = opts }
  elseif type(opts) ~= "table" then
    opts = {}
  end
  Message.open = true
  Message._stay = opts.stay and true or false
  Message._hold = opts.hold and true or false
  Message._autoScroll = false
  Message._held = false
  Message._done = opts.done
  Message._choice = nil
  if opts.frame == "sign" or opts.sign then
    Message._frame = "sign"
  elseif opts.frame == "braille" then
    -- pokefirered/src/scrcmd.c:1558
    Message._frame = "braille"
  elseif opts.frame == "voiceover" then
    -- pokefirered/src/battle_controller_oak_old_man.c:2238
    Message._frame = "voiceover"
  elseif opts.frame == "battle" or opts.battle then
    Message._frame = "battle"
  else
    -- Default field dialogue. Do not keep a sticky "battle" frame after fights
    -- (battle Ui draws its own textbox; field msgs need Chrome.dialogueFrame).
    Message._frame = "dialogue"
  end

  -- Resolve default ambient text colors
  if opts.colors then
    Message._colors = opts.colors
  elseif opts.gfxId then
    Message._colors = FrlgFont.colorForNpc(opts.gfxId)
  elseif opts.npcColor ~= nil then
    if opts.npcColor == FrlgFont.NPC_TEXT_COLOR.MALE then
      Message._colors = FrlgFont.COLOR.MALE_NPC
    elseif opts.npcColor == FrlgFont.NPC_TEXT_COLOR.FEMALE then
      Message._colors = FrlgFont.COLOR.FEMALE_NPC
    else
      Message._colors = FrlgFont.COLOR.NORMAL
    end
  elseif Message._frame == "battle" then
    Message._colors = FrlgFont.COLOR.WHITE
  else
    Message._colors = FrlgFont.COLOR.NORMAL
  end

  -- Prefer session options text speed when not overridden.
  local instant = tonumber(opts.speed) == 0
  local speed = opts.speed
  if speed == nil then
    local ok, Options = pcall(require, "src.core.game3.options")
    local okR, Runtime = pcall(require, "src.core.game3.runtime")
    if ok and okR and Runtime.getSession then
      speed = Options.textSpeed(Runtime.getSession())
    end
  end
  -- Also honor save-schema alias text_speed if Options path missed.
  if speed == nil and opts.session and opts.session.options then
    speed = opts.session.options.text_speed or opts.session.options.textSpeed
  end
  Message._speedIdx = tonumber(speed) or 1
  if Message._speedIdx < 0 then Message._speedIdx = 0 end
  if Message._speedIdx > 2 then Message._speedIdx = 2 end

  local _, _, dlgW = Chrome.dialogueWindow()
  local maxW = (opts.frame == "battle" or opts.battle) and 212 or dlgW * Display.TILE
  local ctx = opts.ctx or {}
  if not ctx.maxWidth then ctx.maxWidth = maxW end
  -- pokefirered/src/scrcmd.c:1566
  if Message._frame == "braille" then ctx.maxWidth = 4096 end

  local plain
  if Message._frame == "braille" then
    -- pokeruby/src/scrcmd.c:1433
    plain = type(text) == "table" and TextIR.toPlain(text, ctx) or tostring(text or "")
  elseif type(text) == "table" then
    plain = TextIR.toTextBox(text, ctx)
  else
    local ir = TextIR.fromAscii(tostring(text or ""))
    plain = TextIR.toTextBox(ir, ctx)
  end
  Message._pages = split_pages(plain)
  Message._page = 1
  -- pokeemerald/src/text.c:285
  Message._spedUp = false
  beginPage()
  if instant then
    Message.skipReveal()
  end
  return Message
end

function Message.showStay(text, opts)
  opts = opts or {}
  opts.stay = true
  return Message.show(text, opts)
end

function Message.currentPage()
  local p = rsPrinter()
  if p then return p.text() or "" end
  if not Message._pages then return "" end
  return Message._pages[Message._page] or ""
end

function Message.isOpen()
  return rsPrinter() ~= nil or Message.open
end

function Message.isWaiting()
  local p = rsPrinter()
  if p then return not p.isPrinting() end
  return Message.open and Message._waiting
end

function Message.isTyping()
  local p = rsPrinter()
  if p then return p.isPrinting() end
  return Message.open and not Message._waiting
end

function Message.isRsFieldAutoScroll()
  return rsPrinter() ~= nil
end

--- Instantly finish the current page reveal.
function Message.skipReveal()
  if rsPrinter() then return end
  if not Message.open then return end
  Message._revealed = Message._total
  Message._delay = 0
  Message._waiting = true
end

function Message.advance()
  if rsPrinter() then return end
  if not Message.open then return end
  if Message._choice then return end
  if Message._autoScroll and Message._waiting and Message._page < #Message._pages then return end

  if not Message._waiting then
    Message.skipReveal()
    return
  end

  if Message._page < #Message._pages then
    Message._page = Message._page + 1
    beginPage()
    return
  end
  if Message._stay then
    return
  end
  -- pokefirered/src/battle_controller_oak_old_man.c:780
  if Message._hold then
    if Message._held then return end
    Message._held = true
    local done = Message._done
    Message._done = nil
    if done then done() end
    return
  end
  Message.close()
end

function Message.isHeld()
  return Message.open and Message._held == true
end

function Message.close()
  local p = rsPrinter()
  if p then p.close() end
  local done = Message._done
  Message.open = false
  Message._pages = nil
  Message._page = 1
  Message._done = nil
  Message._stay = false
  Message._hold = false
  Message._held = false
  Message._autoScroll = false
  Message._choice = nil
  Message._revealed = 0
  Message._total = 0
  Message._waiting = false
  if done then done() end
end

function Message.closeStay()
  if not (Message.open and Message._stay) then return false end
  Message._done = nil
  Message.close()
  return true
end

-- pokefirered/src/main.c:480
function Message.reset()
  Message._done = nil
  Message.close()
  return true
end

function Message.tick()
  local p = rsPrinter()
  if p then
    p.tick()
    Message._waiting = not p.isPrinting()
    return
  end
  if Message.open and Message._waiting then
    Message._arrowTicks = (Message._arrowTicks or 0) + 1
    -- pokeemerald/src/text.c:854
    if Message._autoScroll and Message._page < #Message._pages and Message._arrowTicks >= 50 then
      Message._page = Message._page + 1
      beginPage()
    end
  end
  if not Message.open or Message._waiting then return end
  if Message._revealed >= Message._total then
    Message._waiting = true
    return
  end
  -- pokeemerald/src/text.c:944
  if Message._speedUp and Message._spedUp then
    Message._delay = 0
  end
  if Message._delay > 0 then
    Message._delay = Message._delay - 1
    Message._delayTick = true
    return
  end
  Message._delayTick = false
  Message._revealed = Message._revealed + 1
  if Message._revealed >= Message._total then
    Message._waiting = true
  else
    local d = SPEED_DELAYS[Message._speedIdx + 1] or 4
    -- pokeemerald/src/text.c:296
    if d > 0 then d = d - 1 end
    Message._delay = d
  end
end

-- pokeemerald/src/text.c:950
function Message.pressAB()
  if rsPrinter() or not Message.open or Message._waiting then return end
  if not Message._delayTick then return end
  Message._spedUp = true
  Message._delay = 0
end

-- pokeemerald/src/scrcmd.c:1292
function Message.setAutoScroll()
  if rsPrinter() or not Message.open then return false end
  Message._autoScroll = true
  -- pokeemerald/src/menu.c:476
  Message._speedIdx = 1
  return true
end

function Message.setSpeedUp(held)
  if rsPrinter() then return end
  Message._speedUp = held and true or false
end

--- Draw dialogue frame + text (and optional prompt).
function Message.draw()
  local p = rsPrinter()
  if p then return p.draw() end
  if not Message.open then return end
  if Message._frame == "sign" then
    Chrome.signFrame()
  elseif Message._frame == "voiceover" then
    -- pokefirered/src/battle_controller_oak_old_man.c:2238
    Chrome.dialogueFrame()
  elseif Message._frame == "battle" then
    -- Battle textbox chrome is drawn by battle Ui; text only here.
  elseif Message._frame == "braille" and braille() and braille().window() then
    local w = braille().window()
    -- pokeruby/src/text_window.c:158
    Chrome.stdFrame(w.left + 1, w.top + 1, w.right - w.left - 1, w.bottom - w.top - 1)
  else
    Chrome.dialogueFrame()
  end
  Message.drawText()
end

--- Draw dialogue text (and optional prompt) into the content window.
-- Caller draws frame first unless using Message.draw().
function Message.drawText()
  local p = rsPrinter()
  if p then return p.drawText() end
  if not Message.open then return end
  local page = Message.currentPage() or ""
  local baseX, baseY, maxW
  if Message._frame == "battle" then
    -- Window at tile (1,15)=px(8,120); printer x=2,y=2 → (10,122).
    -- Panel chrome now drawn from y=112.
    baseX, baseY, maxW = 10, 122, 224
  else
    local L, Top, W = Chrome.dialogueWindow()
    baseX = L * Display.TILE
    baseY = Top * Display.TILE + 1
    maxW = W * Display.TILE
  end
  if Message._frame == "braille" then
    -- pokefirered/src/scrcmd.c:1566
    local B = braille()
    local win = B and B.window()
    if win then
      -- pokeruby/src/scrcmd.c:1433
      baseX, baseY = win.textX * Display.TILE, win.textY * Display.TILE
    end
    if B then
      B.drawText(page, baseX, baseY, {
        maxWidth = maxW,
        limitChars = Message._revealed,
        colors = Message._colors or FrlgFont.COLOR.NORMAL,
      })
      B.drawCursor()
      return
    end
  end

  local drawn, endX, endY = FrlgFont.draw(page, baseX, baseY, {
    maxWidth = maxW,
    limitChars = Message._revealed,
    colors = (Message._frame == "battle") and FrlgFont.COLOR.WHITE or (Message._colors or FrlgFont.COLOR.NORMAL),
  })

  local rse = Chrome.arrowSpec()
  if rse then
    -- pokeemerald/src/text.c:792
    if Message._waiting and not Message._held and not Message._autoScroll
        and (rse.lastPage or Message._page < #Message._pages
          -- pokeemerald/src/text.c:1171
          or (Message._frame == "battle" and not Message._stay)) then
      local n = math.floor((Message._arrowTicks or 0) / (rse.period or ((rse.delay or 0) + 1)))
      Chrome.promptArrow(endX or baseX, endY or baseY, n)
    end
    return
  end
  if Message._waiting and not Message._stay and not Message._held then
    local t = love and love.timer and love.timer.getTime and love.timer.getTime() or 0
    -- Red arrow has 4 vertical bounce frames (0..3) in down_arrows.png
    local bounceSeq = { 0, 1, 2, 3, 2, 1 }
    local frame = bounceSeq[1 + (math.floor(t * 8) % #bounceSeq)] or 0

    local ax = (endX or (baseX + 16)) + 2
    local ay = (endY or baseY)
    -- Clamp arrow within the dialog panel
    if ax + 10 > baseX + maxW then
      ax = baseX + maxW - 10
    end
    Chrome.promptArrow(ax, ay, frame)
  end
end

-- pokeruby/src/field_message_box.c:144
function Message.rsFieldMessageBoxMode()
  local p = rsPrinter()
  if p then return p.mode() end
  if not Message.open then return 0 end
  if not Message._waiting then return 1 end
  if Message._pages and Message._page < #Message._pages then return 1 end
  return 0
end

function Message.showRsFieldAutoScroll(presentation, onPrinted)
  local profile = require("src.core.game3.profile").forSession()
  if profile.id ~= "ruby" and profile.id ~= "sapphire" then return false end
  if Message.rsFieldMessageBoxMode() ~= 0 then return false end
  local p = require(RS_AUTO)
  local prepared = p.prepare(presentation, onPrinted)
  Message._done = nil
  Message.close()
  p.open(prepared)
  Message.open, Message._stay, Message._frame = true, true, "dialogue"
  Message._pages, Message._page, Message._waiting = nil, 1, false
  return true
end

return Message
