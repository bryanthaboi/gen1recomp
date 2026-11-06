return function()
  local U = dofile("tests/drivers/util.lua")
  local RomImporter = require("src.import.RomImporter")
  local Kit = require("src.ui.kit.Kit")
  local Transition = require("src.ui.kit.Transition")
  local SyncEngine = require("src.sync.SyncEngine")

  local dir = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/3107"
  os.execute('mkdir -p "' .. dir .. '" 2>/dev/null')
  love.window.getSafeArea = function()
    local w, h = love.graphics.getDimensions()
    return 0, 0, w, h
  end

  local status = SyncEngine.ERROR_TEXT.unauthorized
  local eng = {
    phase = "error", status = status,
    busy = function() return false end,
    linked = function() return false end,
  }
  local imp = RomImporter.new(function() end, { launcher = true })
  imp.ready.blue = true
  imp.tab = "blue"
  imp._ensureSlots = function() end
  imp._syncSupported = function() return true end
  imp._sync = eng
  imp._syncModal = { view = "home" }

  local drawn, pending, record = 0, nil, nil
  local texts = {}
  local kitText = Kit.text
  Kit.text = function(font, str, x, y, ...)
    if record and type(str) == "string" and #str > 8 then
      texts[#texts + 1] = { str = str, x = x, y = y, h = Kit.textHeight(font) }
    end
    return kitText(font, str, x, y, ...)
  end
  local auditRows
  love.draw = function()
    if record then texts = {}; Kit.audit = {} end
    imp:draw()
    if record then auditRows, Kit.audit = Kit.audit, nil; record = false end
    drawn = drawn + 1
    if pending then
      local path = pending
      pending = nil
      love.graphics.captureScreenshot(function(imagedata)
        local f = io.open(path, "wb")
        if f then f:write(imagedata:encode("png"):getString()) f:close() end
      end)
    end
  end

  local function frames(n)
    for _ = 1, n do
      local seen = drawn
      imp:update(1 / 60)
      for _ = 1, 4000 do
        coroutine.yield()
        if drawn > seen then break end
      end
    end
  end

  local failed = false
  local function verdict(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then failed = true end
  end

  love.window.setMode(411, 921, { resizable = true, highdpi = true })
  frames(1)
  Transition.reset()
  frames(3)
  record = true
  frames(1)

  local lines = {}
  for _, t in ipairs(texts) do
    if status:find(t.str, 1, true) and t.str ~= status then lines[#lines + 1] = t end
  end
  local joined = {}
  for i, t in ipairs(lines) do joined[i] = t.str end
  local whole = table.concat(joined):gsub("%s+", "")
  verdict(#lines >= 2 and #lines <= 4, "sync_error_wraps_to_at_most_4_lines (" .. #lines .. ")")
  verdict(whole == status:gsub("%s+", ""), "sync_error_text_shown_in_full")
  local bottom = 0
  for _, t in ipairs(lines) do bottom = math.max(bottom, t.y + t.h) end
  local top = lines[1] and lines[1].y or 0
  local clash = false
  for _, r in ipairs(auditRows or {}) do
    if r.class == "control" and r.y < bottom and r.y + r.h > top then clash = true end
  end
  verdict(not clash, "sync_error_lines_clear_of_buttons")
  local W, H = love.graphics.getDimensions()
  local off = false
  for _, r in ipairs(auditRows or {}) do
    if r.class == "control" then
      local c = r.clip
      local y2 = c and math.min(r.y + r.h, c.y + c.h) or (r.y + r.h)
      if r.y + r.h > H or (c and y2 < r.y + r.h - 0.5 and r.label:find("Create", 1, true)) then
        off = true
      end
    end
  end
  verdict(not off, "sync_buttons_not_clipped")

  local path = dir .. "/3107_01_sync_home_error_wrapped.png"
  os.remove(path)
  pending = path
  frames(2)
  local okShot = false
  for _ = 1, 4000 do
    local f = io.open(path, "rb")
    if f then f:close() okShot = true break end
    coroutine.yield()
  end
  U.log("shot", path)
  verdict(okShot, "shot_3107_01_sync_home_error_wrapped")
  love.event.quit(failed and 1 or 0)
end
