-- Controller-driven on-screen keyboard (OSK) for handhelds and gamepads.
-- Allows typing URLs (mod index, repositories), mod search queries, and custom names
-- without needing a physical keyboard.

local Theme = require("src.ui.kit.Theme")
local PAL = Theme.PAL
local Kit = nil
local function getKit()
  if not Kit then Kit = require("src.ui.kit.Kit") end
  return Kit
end

local VirtualKeyboard = {
  active = false,
  text = "",
  title = "Enter Text",
  targetId = nil,
  onDone = nil,
  row = 1,
  col = 1,
  mode = 1, -- 1: lower, 2: upper, 3: symbols
}

local ROWS_LOWER = {
  { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "=" },
  { "q", "w", "e", "r", "t", "y", "u", "i", "o", "p", "/", ":" },
  { "a", "s", "d", "f", "g", "h", "j", "k", "l", ".", "_", "@" },
  { "z", "x", "c", "v", "b", "n", "m", "?", "!", "&", "%", "#" },
  { { id = "shift", label = "Shift", w = 2 }, { id = "sym", label = "Sym", w = 2 }, { id = "space", label = "Space", w = 4 }, { id = "back", label = "Bksp", w = 2 }, { id = "done", label = "Done", w = 2 } },
  { { id = "url_https", label = "https://", w = 3 }, { id = "url_http", label = "http://", w = 2 }, { id = "url_json", label = ".json", w = 2 }, { id = "url_zip", label = ".zip", w = 2 }, { id = "clear", label = "Clear", w = 3 } },
}

local ROWS_UPPER = {
  { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "=" },
  { "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "/", ":" },
  { "A", "S", "D", "F", "G", "H", "J", "K", "L", ".", "_", "@" },
  { "Z", "X", "C", "V", "B", "N", "M", "?", "!", "&", "%", "#" },
  { { id = "shift", label = "shift", w = 2 }, { id = "sym", label = "Sym", w = 2 }, { id = "space", label = "Space", w = 4 }, { id = "back", label = "Bksp", w = 2 }, { id = "done", label = "Done", w = 2 } },
  { { id = "url_https", label = "https://", w = 3 }, { id = "url_http", label = "http://", w = 2 }, { id = "url_json", label = ".json", w = 2 }, { id = "url_zip", label = ".zip", w = 2 }, { id = "clear", label = "Clear", w = 3 } },
}

local ROWS_SYM = {
  { "!", "@", "#", "$", "%", "^", "&", "*", "(", ")", "_", "+" },
  { "~", "`", "{", "}", "[", "]", "|", "\\", ";", ":", "'", "\"" },
  { "<", ">", ",", ".", "/", "?", "=", "-", "*", "/", "\\", "~" },
  { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", ".", "=" },
  { { id = "shift", label = "ABC", w = 2 }, { id = "sym", label = "123", w = 2 }, { id = "space", label = "Space", w = 4 }, { id = "back", label = "Bksp", w = 2 }, { id = "done", label = "Done", w = 2 } },
  { { id = "url_https", label = "https://", w = 3 }, { id = "url_http", label = "http://", w = 2 }, { id = "url_json", label = ".json", w = 2 }, { id = "url_zip", label = ".zip", w = 2 }, { id = "clear", label = "Clear", w = 3 } },
}

local ROWS_DIGITS = {
  { "1", "2", "3" },
  { "4", "5", "6" },
  { "7", "8", "9" },
  { { id = "back", label = "Bksp" }, "0", { id = "done", label = "Done" } },
}

VirtualKeyboard.ROWS_DIGITS = ROWS_DIGITS

local function isLinuxHandheld()
  return os.getenv("HANDHELD") == "1"
      or os.getenv("PORTMASTER") == "1"
      or os.getenv("POKEPORT_HANDHELD") == "1"
      or os.getenv("TRIMUI") == "1"
      or os.getenv("MUOS") == "1"
      or os.getenv("KNULLI") == "1"
      or os.getenv("POKEPORT_SBC") == "1"
      or os.getenv("ANBERNIC") == "1"
end

function VirtualKeyboard.isSupported()
  return isLinuxHandheld()
end

function VirtualKeyboard.open(opts)
  if not isLinuxHandheld() then return false end
  opts = opts or {}
  VirtualKeyboard.active = true
  VirtualKeyboard.text = tostring(opts.text or "")
  VirtualKeyboard.title = opts.title or "Enter Text"
  VirtualKeyboard.targetId = opts.targetId
  VirtualKeyboard.onDone = opts.onDone
  VirtualKeyboard.row = 1
  VirtualKeyboard.col = 1
  VirtualKeyboard.mode = opts.digits and 4 or 1
  VirtualKeyboard.maxLen = tonumber(opts.maxLen)
  return true
end

function VirtualKeyboard.close(confirmed)
  if not VirtualKeyboard.active then return end
  local txt = VirtualKeyboard.text
  local cb = VirtualKeyboard.onDone
  VirtualKeyboard.active = false
  VirtualKeyboard.targetId = nil
  VirtualKeyboard.onDone = nil
  if cb then
    cb(txt, confirmed == true)
  end
end

local function currentRows()
  if VirtualKeyboard.mode == 4 then return ROWS_DIGITS end
  if VirtualKeyboard.mode == 2 then return ROWS_UPPER end
  if VirtualKeyboard.mode == 3 then return ROWS_SYM end
  return ROWS_LOWER
end

VirtualKeyboard.currentRows = currentRows

local function triggerKey(key)
  if type(key) == "string" then
    local cap = VirtualKeyboard.maxLen
    if cap and #VirtualKeyboard.text >= cap then return end
    VirtualKeyboard.text = VirtualKeyboard.text .. key
  elseif type(key) == "table" then
    if key.id == "shift" then
      VirtualKeyboard.mode = (VirtualKeyboard.mode == 2) and 1 or 2
    elseif key.id == "sym" then
      VirtualKeyboard.mode = (VirtualKeyboard.mode == 3) and 1 or 3
    elseif key.id == "space" then
      VirtualKeyboard.text = VirtualKeyboard.text .. " "
    elseif key.id == "back" then
      VirtualKeyboard.text = VirtualKeyboard.text:sub(1, -2)
    elseif key.id == "clear" then
      VirtualKeyboard.text = ""
    elseif key.id == "done" then
      VirtualKeyboard.close(true)
    elseif key.id == "url_https" then
      VirtualKeyboard.text = VirtualKeyboard.text .. "https://"
    elseif key.id == "url_http" then
      VirtualKeyboard.text = VirtualKeyboard.text .. "http://"
    elseif key.id == "url_json" then
      VirtualKeyboard.text = VirtualKeyboard.text .. ".json"
    elseif key.id == "url_zip" then
      VirtualKeyboard.text = VirtualKeyboard.text .. ".zip"
    end
  end
end

function VirtualKeyboard.gamepadpressed(button)
  if not VirtualKeyboard.active then return false end

  local rows = currentRows()
  local r = VirtualKeyboard.row
  local c = VirtualKeyboard.col

  if button == "dpup" then
    VirtualKeyboard.row = math.max(1, r - 1)
    local maxC = #rows[VirtualKeyboard.row]
    if VirtualKeyboard.col > maxC then VirtualKeyboard.col = maxC end
    return true
  elseif button == "dpdown" then
    VirtualKeyboard.row = math.min(#rows, r + 1)
    local maxC = #rows[VirtualKeyboard.row]
    if VirtualKeyboard.col > maxC then VirtualKeyboard.col = maxC end
    return true
  elseif button == "dpleft" then
    VirtualKeyboard.col = math.max(1, c - 1)
    return true
  elseif button == "dpright" then
    VirtualKeyboard.col = math.min(#rows[r], c + 1)
    return true
  elseif button == "a" then
    local key = rows[r] and rows[r][c]
    if key then triggerKey(key) end
    return true
  elseif button == "b" then
    VirtualKeyboard.close(false)
    return true
  elseif button == "x" then
    VirtualKeyboard.text = VirtualKeyboard.text:sub(1, -2)
    return true
  elseif button == "y" then
    if VirtualKeyboard.mode == 4 then return true end
    VirtualKeyboard.text = VirtualKeyboard.text .. " "
    return true
  elseif button == "leftshoulder" or button == "rightshoulder" then
    if VirtualKeyboard.mode == 4 then return true end
    VirtualKeyboard.mode = (VirtualKeyboard.mode % 3) + 1
    local maxC = #currentRows()[VirtualKeyboard.row]
    if VirtualKeyboard.col > maxC then VirtualKeyboard.col = maxC end
    return true
  elseif button == "start" then
    VirtualKeyboard.close(true)
    return true
  end

  return true -- consume all input while keyboard modal is up
end

function VirtualKeyboard.keypressed(key)
  if not VirtualKeyboard.active then return false end
  if key == "escape" then
    VirtualKeyboard.close(false)
    return true
  elseif key == "return" then
    VirtualKeyboard.close(true)
    return true
  elseif key == "backspace" then
    VirtualKeyboard.text = VirtualKeyboard.text:sub(1, -2)
    return true
  end
  return false
end

function VirtualKeyboard.textinput(text)
  if not VirtualKeyboard.active then return false end
  if VirtualKeyboard.mode == 4 then text = tostring(text or ""):gsub("%D", "") end
  local cap = VirtualKeyboard.maxLen
  VirtualKeyboard.text = VirtualKeyboard.text .. text
  if cap and #VirtualKeyboard.text > cap then
    VirtualKeyboard.text = VirtualKeyboard.text:sub(1, cap)
  end
  return true
end

function VirtualKeyboard.draw(m)
  if not VirtualKeyboard.active then return end

  local Kit = getKit()
  local s = m and m.s or Kit.scale or 1
  local W = (m and m.W) or (love.graphics and love.graphics.getWidth()) or 640
  local H = (m and m.H) or (love.graphics and love.graphics.getHeight()) or 480

  -- Scrim background
  Theme.fill(0, 0, W, H, PAL.bg, 0.92)
  local shielded = Kit.blockClicks
  Kit.blockClicks = true

  local pad = math.floor(12 * s)
  local modalW = math.floor(math.min(540 * s, W - 20 * s))
  local modalH = math.floor(math.min(360 * s, H - 20 * s))
  local px = math.floor((W - modalW) / 2)
  local py = math.floor((H - modalH) / 2)

  Kit.card(px, py, modalW, modalH, true)
  Kit.blockClicks = shielded

  local cy = py + pad
  -- Title & hint
  Kit.text("button", VirtualKeyboard.title, px + pad, cy, PAL.heading)
  Kit.textRight("micro", VirtualKeyboard.mode == 4
    and "X: Bksp  Start: Done  B: Cancel"
    or "L1/R1: Mode  X: Bksp  Y: Space  Start: Done  B: Cancel",
    px + modalW - pad, cy + 2 * s, PAL.muted)

  cy = cy + Kit.textHeight("button") + math.floor(8 * s)

  -- Preview textfield box
  local fieldH = math.floor(32 * s)
  Theme.fillRounded(px + pad, cy, modalW - 2 * pad, fieldH, PAL.bg, 1)
  Theme.strokeRounded(px + pad, cy, modalW - 2 * pad, fieldH, PAL.lineStrong, 1, 2)

  local shown = Kit.ellipsizeLeft("mono", VirtualKeyboard.text .. "_", modalW - 4 * pad)
  Kit.text("mono", shown, px + pad + math.floor(8 * s), cy + math.floor(7 * s), PAL.heading)

  cy = cy + fieldH + math.floor(10 * s)

  -- Keyboard Rows
  local rows = currentRows()
  local rowH = math.floor(30 * s)
  local gap = math.floor(4 * s)
  local availableW = modalW - 2 * pad

  for rIdx, rData in ipairs(rows) do
    local totalUnits = 0
    for _, key in ipairs(rData) do
      totalUnits = totalUnits + (type(key) == "table" and (key.w or 1) or 1)
    end

    local unitW = (availableW - (gap * (#rData - 1))) / totalUnits
    local kx = px + pad

    for cIdx, key in ipairs(rData) do
      local units = type(key) == "table" and (key.w or 1) or 1
      local kw = math.floor(unitW * units)
      local isSelected = (VirtualKeyboard.row == rIdx and VirtualKeyboard.col == cIdx)

      local label = type(key) == "table" and key.label or key
      local isSpecial = type(key) == "table"

      -- Click / touch detection
      if Kit.press(kx, cy, kw, rowH) then
        VirtualKeyboard.row = rIdx
        VirtualKeyboard.col = cIdx
        triggerKey(key)
      end

      if isSelected then
        Theme.fillRounded(kx, cy, kw, rowH, PAL.ink, 1)
        Kit.textCenterBold("small", label, kx, cy + math.floor(6 * s), kw, PAL.inverse)
      else
        Theme.fillRounded(kx, cy, kw, rowH, isSpecial and PAL.raised or PAL.surface, 1)
        Theme.strokeRounded(kx, cy, kw, rowH, PAL.line, Theme.A.hairline, 1)
        Kit.textCenter("small", label, kx, cy + math.floor(6 * s), kw, isSpecial and PAL.heading or PAL.text)
      end

      kx = kx + kw + gap
    end

    cy = cy + rowH + gap
  end

  Kit.blockClicks = shielded
end

return VirtualKeyboard
