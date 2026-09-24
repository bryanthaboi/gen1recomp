local Stack = require("src.ui.game3.stack")
local Window = require("src.ui.game3.window")
local FrlgFont = require("src.ui.game3.frlg_font")
local Chat = require("src.core.game3.link.chat")

local UnionChat = {}

UnionChat.DIR = "data/generated/gba/union_room/"
UnionChat.LAYER = "union_chat"

-- pokefirered/src/union_room_chat_display.c:162
UnionChat.WIN_LOG = { x = 64, y = 8, w = 168, h = 152 }
UnionChat.WIN_ENTRY = { x = 72, y = 144 }
UnionChat.WIN_KEYBOARD = { x = 0, y = 16 }
UnionChat.SWAP_TEMPLATE = Window.template(1, 2, 7, 9)
-- pokefirered/src/union_room_chat_display.c:1220
UnionChat.WIN0 = { x = 64, y = 0, w = 176, h = 144 }
-- pokefirered/src/union_room_chat.c:387
UnionChat.ICON_X = 232
UnionChat.ICON_Y = 150
-- pokefirered/src/union_room_chat_display.c:1096
UnionChat.KEY_PITCH = 12
UnionChat.REGISTER_MAX_W = 40
UnionChat.REGISTER_CUT_W = 35

UnionChat.MIN_SPACING = "\252\20\8"

-- pokefirered/src/union_room_chat_display.c:1209
local SH = FrlgFont.STDPAL[3]
UnionChat.SEAT_COLORS = {
  [0] = { fg = FrlgFont.STDPAL[2], shadow = SH, bg = FrlgFont.STDPAL[0] },
  [1] = { fg = FrlgFont.STDPAL[6], shadow = SH, bg = FrlgFont.STDPAL[0] },
  [2] = { fg = FrlgFont.STDPAL[8], shadow = SH, bg = FrlgFont.STDPAL[0] },
  [3] = { fg = FrlgFont.STDPAL[4], shadow = SH, bg = FrlgFont.STDPAL[0] },
  [4] = { fg = FrlgFont.STDPAL[5], shadow = SH, bg = FrlgFont.STDPAL[0] },
}
-- pokefirered/src/union_room_chat_display.c:619
UnionChat.REGISTER_COLORS = { fg = FrlgFont.STDPAL[1], shadow = FrlgFont.STDPAL[2], bg = FrlgFont.STDPAL[0] }

UnionChat.open = false
UnionChat._art = nil

function UnionChat.isOpen()
  return UnionChat.open
end

local function readCache(rel)
  return require("src.core.game3.dataset").cache():read(UnionChat.DIR .. rel)
end

local function imageFrom(name, w, h, edit)
  local bytes = readCache(name .. ".rgba")
  assert(type(bytes) == "string" and #bytes == w * h * 4, "union_room/" .. name .. ".rgba missing from the cache")
  local data = love.image.newImageData(w, h, "rgba8", bytes)
  if edit then edit(data) end
  local img = love.graphics.newImage(data)
  img:setFilter("nearest", "nearest")
  return img
end

-- pokefirered/src/union_room_chat_display.c:1269
local function punchLogWindow(data)
  local w = UnionChat.WIN_LOG
  local r0, g0, b0 = data:getPixel(w.x + math.floor(w.w / 2), w.y + math.floor(w.h / 2))
  data:mapPixel(function(_, _, r, g, b, a)
    if r == r0 and g == g0 and b == b0 then return r, g, b, 0 end
    return r, g, b, a
  end, w.x, w.y, w.w, w.h)
end

function UnionChat.loadArt()
  if UnionChat._art then return UnionChat._art end
  local src = readCache("manifest.lua")
  assert(type(src) == "string", "union_room/manifest.lua missing from the cache")
  local m = assert(load(src, "@union_room/manifest.lua", "t", {}))()
  local function frames(key)
    local e = assert(m[key], "union_room manifest has no " .. key)
    local img = imageFrom(key, e.width, e.height)
    local n = tonumber(e.frames) or 1
    local fh = tonumber(e.frame_h) or e.height
    local quads = {}
    for i = 0, n - 1 do quads[i] = love.graphics.newQuad(0, i * fh, e.width, fh, e.width, e.height) end
    return { image = img, quads = quads, w = e.width, h = fh }
  end
  local bg = m.chat_bg
  local panel = m.chat_panel
  UnionChat._art = {
    bg = imageFrom("chat_bg", bg.width, bg.height, punchLogWindow),
    panel = imageFrom("chat_panel", panel.width, panel.height),
    panelW = panel.width,
    panelH = panel.height,
    icons = frames("chat_icons"),
    selector = frames("chat_selector_cursor"),
    entryCursor = frames("chat_text_entry_cursor"),
    charCursor = frames("chat_char_select_cursor"),
    rButton = frames("chat_r_button"),
  }
  return UnionChat._art
end

local function fade()
  local ok, Fade = pcall(require, "src.ui.game3.fade")
  return ok and Fade and Fade.begin and Fade.MODE and Fade or nil
end

-- pokefirered/src/union_room_chat.c:357
function UnionChat.show()
  if not (type(love) == "table" and love.graphics) then return false end
  UnionChat.loadArt()
  UnionChat.open = true
  Stack.push(UnionChat.LAYER, UnionChat, { hideBelow = true, fullscreen = true })
  local Fade = fade()
  if Fade then
    Fade.clear()
    Fade.begin(Fade.MODE.FROM_BLACK, 1, function() end)
  end
  return true
end

-- pokefirered/src/union_room_chat.c:905
function UnionChat.fadeOut(done)
  local Fade = fade()
  if not Fade then
    done()
    return
  end
  Fade.begin(Fade.MODE.TO_BLACK, 1, function()
    done()
    Fade.clear()
    Fade.begin(Fade.MODE.FROM_BLACK, 1, function() end)
  end)
end

function UnionChat.close()
  if not UnionChat.open then return false end
  UnionChat.open = false
  Stack.pop(UnionChat.LAYER)
  return true
end

function UnionChat.reset()
  UnionChat.open = false
  Stack.pop(UnionChat.LAYER)
end

function UnionChat.update(dt)
  local ok, Icon = pcall(require, "src.ui.game3.wireless_icon")
  if ok and Icon.update then Icon.update(dt) end
end

function UnionChat.handleInput(input)
  local ok, Fade = pcall(require, "src.ui.game3.fade")
  if ok and Fade.isActive and Fade.isActive() then return end
  Chat.handleInput(input)
end

local function drawFrame(frames, index, x, y)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(frames.image, frames.quads[index] or frames.quads[0], x, y)
end

local function clipBg1(fn)
  local w0 = UnionChat.WIN0
  love.graphics.setScissor(0, 0, w0.x, 160)
  fn()
  love.graphics.setScissor(0, w0.y + w0.h, 240, 160 - (w0.y + w0.h))
  fn()
  love.graphics.setScissor()
end

-- pokefirered/src/union_room_chat_display.c:1209
function UnionChat.drawLog()
  local w = UnionChat.WIN_LOG
  local white = FrlgFont.STDPAL[1]
  love.graphics.setColor(white[1], white[2], white[3], 1)
  love.graphics.rectangle("fill", w.x, w.y, w.w, w.h)
  love.graphics.setScissor(w.x, w.y, w.w, w.h)
  local shift = Chat.scroll and Chat.scroll.offset or 0
  for i, line in ipairs(Chat.lines or {}) do
    local y = w.y + (i - 1) * Chat.LINE_HEIGHT + shift
    FrlgFont.draw(line.text, w.x, y, {
      colors = UnionChat.SEAT_COLORS[line.seat] or UnionChat.SEAT_COLORS[0],
      maxWidth = w.w,
    })
  end
  love.graphics.setScissor()
end

function UnionChat.registeredLabel(text)
  local width = FrlgFont.measure(text, { small = true })
  if width <= UnionChat.REGISTER_MAX_W then return text, nil end
  local tokens = Chat.tokens(text)
  local cut = #tokens
  repeat
    cut = cut - 1
    local part = table.concat(tokens, "", 1, math.max(0, cut))
    width = FrlgFont.measure(part, { small = true })
  until cut <= 0 or width <= UnionChat.REGISTER_CUT_W
  return table.concat(tokens, "", 1, math.max(0, cut)), "…"
end

-- pokefirered/src/union_room_chat_display.c:1096
function UnionChat.drawKeyboard(ox)
  local k = UnionChat.WIN_KEYBOARD
  if Chat.page ~= Chat.PAGE.REGISTER then
    local left = Chat.page == Chat.PAGE.EMOJI and 6 or 8
    for row = 0, Chat.KB_ROWS - 1 do
      local key = Chat.KEYBOARD[Chat.page][row + 1]
      if key then
        FrlgFont.draw(UnionChat.MIN_SPACING .. require("src.core.game3.rom_text").plain(key),
          k.x + left + ox, k.y + row * UnionChat.KEY_PITCH, { small = true, colors = FrlgFont.COLOR.NORMAL })
      end
    end
    return
  end
  for row = 0, Chat.KB_ROWS - 1 do
    local label, tail = UnionChat.registeredLabel(Chat.registered[row + 1] or "")
    local y = k.y + row * UnionChat.KEY_PITCH
    FrlgFont.draw(label, k.x + 4 + ox, y, { small = true, colors = FrlgFont.COLOR.NORMAL })
    if tail then
      FrlgFont.draw(tail, k.x + 4 + UnionChat.REGISTER_CUT_W + ox, y, { small = true, colors = FrlgFont.COLOR.NORMAL })
    end
  end
end

-- pokefirered/src/union_room_chat_display.c:592
function UnionChat.drawEntry()
  local e = UnionChat.WIN_ENTRY
  local highlight = Chat.routine == "register" and Chat.phase == 1
  local from = highlight and Chat.registerStart() or #Chat.buffer
  for i, t in ipairs(Chat.buffer or {}) do
    local x = e.x + (i - 1) * 8
    local colors = FrlgFont.COLOR.NORMAL
    if i > from then
      local bg = FrlgFont.STDPAL[5]
      love.graphics.setColor(bg[1], bg[2], bg[3], 1)
      love.graphics.rectangle("fill", x, e.y + 1, 8, 14)
      colors = UnionChat.REGISTER_COLORS
    end
    FrlgFont.draw(t, x, e.y + 1, { colors = colors })
  end
end

function UnionChat.selectorFrame()
  local closed = (Chat.blink or 0) > 0
  if Chat.page ~= Chat.PAGE.REGISTER then return closed and 1 or 0 end
  return closed and 3 or 2
end

-- pokefirered/src/union_room_chat_objects.c:222
function UnionChat.selectorPos()
  if Chat.page ~= Chat.PAGE.REGISTER then
    return Chat.col * 8 + 10 - 32, Chat.row * 12 + 24 - 16
  end
  return 24 - 32, Chat.row * 12 + 24 - 16
end

-- pokefirered/src/union_room_chat_objects.c:317
function UnionChat.iconFrame()
  if Chat.page == Chat.PAGE.REGISTER then
    return #Chat.buffer > 0 and 3 or nil
  end
  return Chat.canToggleCase() and 0 or nil
end

local function drawMessage()
  local msg = Chat.msg
  if not msg then return end
  local y0 = 16 * 8 - (msg.vofs or 0)
  local left, width = 8, 21
  if msg.wide then left, width = 1, 28 end
  if msg.box == 1 then
    love.graphics.push()
    love.graphics.translate(0, -(msg.vofs or 0))
    Window.fixedStdFrame(Window.template(left + 1, 17, width - 2, 2))
    love.graphics.pop()
    FrlgFont.draw(msg.text, left * 8 + 8 + 1, y0 + 8, { colors = FrlgFont.COLOR.NORMAL, linePitch = 16,
      letterSpacing = 1, maxWidth = (width - 2) * 8 })
  else
    Window.fixedStdFrame(Window.template(left, 16, width, 4))
    FrlgFont.draw(msg.text, left * 8, y0, { colors = FrlgFont.COLOR.NORMAL, linePitch = 16,
      letterSpacing = 1, maxWidth = width * 8 })
  end
end

-- pokefirered/src/union_room_chat_display.c:940
local function drawYesNo()
  local yn = Chat.yesNo
  if not yn then return end
  local RomText = require("src.core.game3.rom_text")
  Window.stdFrame(Window.template(yn.left, yn.top, 6, 4))
  local px, py = yn.left * 8, yn.top * 8
  FrlgFont.draw(RomText.plain("gText_Yes"), px + 8, py + 2, { colors = FrlgFont.COLOR.NORMAL })
  FrlgFont.draw(RomText.plain("gText_No"), px + 8, py + 16, { colors = FrlgFont.COLOR.NORMAL })
  Window.cursorPx(px, py + 2 + 14 * yn.cursor)
end

-- pokefirered/src/union_room_chat_display.c:1194
local function drawSwap()
  local sw = Chat.swap
  if not sw then return end
  local RomText = require("src.core.game3.rom_text")
  local tpl = UnionChat.SWAP_TEMPLATE
  Window.stdFrame(tpl)
  local px, py = tpl.left * 8, tpl.top * 8
  for i = 0, Chat.SWAP_EXIT do
    FrlgFont.draw(RomText.plain(RomText.key("sKeyboardSwapTexts", i)), px + 8, py + i * 14,
      { colors = FrlgFont.COLOR.NORMAL })
  end
  Window.cursorPx(px, py + sw.cursor * 14)
end

function UnionChat.draw()
  if not UnionChat.open or not (love and love.graphics) then return end
  local art = UnionChat.loadArt()
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("fill", 0, 0, 240, 160)
  UnionChat.drawLog()
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(art.bg, 0, 0)

  local e = UnionChat.WIN_ENTRY
  local pos = #(Chat.buffer or {})
  if pos < Chat.MAX_LENGTH then drawFrame(art.entryCursor, 0, e.x + pos * 8, e.y) end
  drawFrame(art.charCursor, 0, 60 + (Chat.charX2 or 0), 144)
  drawFrame(art.rButton, 0, 0, 144)
  local icon = UnionChat.iconFrame()
  if icon then drawFrame(art.icons, icon, 16, 144) end

  local hofs = Chat.hofs or 0
  local w0 = UnionChat.WIN0
  art.panelTop = art.panelTop or love.graphics.newQuad(0, 0, art.panelW, w0.h, art.panelW, art.panelH)
  art.panelBottom = art.panelBottom
    or love.graphics.newQuad(0, w0.h, art.panelW, art.panelH - w0.h, art.panelW, art.panelH)
  clipBg1(function()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(art.panel, art.panelTop, -hofs, 0)
    love.graphics.draw(art.panel, art.panelBottom, 0, w0.h)
  end)
  love.graphics.setScissor(0, 0, w0.x, w0.h)
  UnionChat.drawKeyboard(-hofs)
  love.graphics.setScissor()
  UnionChat.drawEntry()

  if not Chat.slide then
    local sx, sy = UnionChat.selectorPos()
    drawFrame(art.selector, UnionChat.selectorFrame(), sx, sy)
  end

  drawSwap()
  drawMessage()
  drawYesNo()
  local ok, Icon = pcall(require, "src.ui.game3.wireless_icon")
  if ok and Icon.draw then Icon.draw(UnionChat.ICON_X, UnionChat.ICON_Y) end
end

return UnionChat
