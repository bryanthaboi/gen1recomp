-- Manual check for #1453: the SGB zone scissors must stay contiguous in
-- framebuffer pixels on a fractional-DPI surface (Android), where LOVE 11
-- truncates the scissor to whole units before scaling it.  Zones are pokered
-- data/sgb/sgb_packets.asm BlkPacket_Titlescreen (rows 0-7 / 8-9 / 10-17).
--   POKEPORT_DRIVER=tests/drivers/title_seam_bug1453_test.lua POKEPORT_TOUCH=0 SHOT_DIR=/tmp/shots love .
-- PROBE_DPI picks the density to emulate (default 2.625, the reporter's).
-- Do not set POKEPORT_SPEED: fast-forward desynchronizes the title music.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local PaletteFX = require("src.render.PaletteFX")
  local Renderer = require("src.render.Renderer")
  local SHOT_DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local DPI = tonumber(os.getenv("PROBE_DPI") or "") or 2.625

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- past the copyright splash / attract movie (engine/movie/splash.asm)
  local title
  for _ = 1, 120 do
    local top = game.stack:top()
    if top and top.screenId == "TitleState" and top.sgbPalettes then
      title = top
      break
    end
    U.tap(game, "start")
    U.wait(9)
  end
  check("the title screen is on top", title ~= nil)
  if not (title and title.sgbPalettes) then
    U.log("No title state to look at; nothing below can run.")
    while true do coroutine.yield() end
  end

  local opts = game.save.options
  local mode = opts and opts.colors or PaletteFX.mode
  if PaletteFX.mode ~= "gbc" then
    U.log("COLORS is", tostring(mode) .. "; switching the view to SGB for the check")
    PaletteFX.setMode("gbc")
    U.wait(20)
  end
  local zones = PaletteFX.ensureZones(title:sgbPalettes(game))
  check("the title builds three SGB zones", zones ~= nil and #zones == 3)

  -- A canvas carries its own dpiscale, so the emulated Android surface goes
  -- through the same LOVE scissor path the phone does, on this desktop.
  local probe = love.graphics.newCanvas(math.floor(1920 / DPI),
                                        math.floor(1080 / DPI),
                                        { dpiscale = DPI })
  local PW, PH = probe:getPixelWidth(), probe:getPixelHeight()
  local Sp = math.max(1, math.floor(math.min(PW / 160, PH / 144)))
  local Ux, Uy = Sp / DPI, Sp / DPI
  local uox = math.floor((PW - 160 * Sp) / 2) / DPI
  local uoy = math.floor((PH - 144 * Sp) / 2) / DPI
  local uvpw, uvph = 160 * Ux, 144 * Uy
  U.log(("emulating %dx%d px at dpi %.4f, fit scale %d"):format(PW, PH, DPI, Sp))

  -- what the pre-fix Renderer handed LOVE: fractional units with a half
  -- framebuffer pixel of bias, which LOVE 11 truncates away
  local function scissorOld(x, y, w, h)
    local x2, y2 = math.min(x + w, uox + uvpw), math.min(y + h, uoy + uvph)
    x, y = math.max(x, uox), math.max(y, uoy)
    if x2 <= x or y2 <= y then return false end
    local px1, py1 = math.floor(x * DPI), math.floor(y * DPI)
    local px2, py2 = math.ceil(x2 * DPI), math.ceil(y2 * DPI)
    love.graphics.setScissor((px1 + 0.5) / DPI, (py1 + 0.5) / DPI,
                             (px2 - px1 + 0.5) / DPI, (py2 - py1 + 0.5) / DPI)
    return true
  end

  local function renderProbe(old)
    love.graphics.setCanvas(probe)
    love.graphics.clear(0, 0, 0, 1)
    love.graphics.setColor(1, 1, 1, 1)
    if old then
      local shader = PaletteFX.shader()
      love.graphics.setShader(shader)
      for _, z in ipairs(zones) do
        PaletteFX.sendColors(shader, z.colors)
        if scissorOld(uox + z.x * Ux, uoy + z.y * Uy, z.w * Ux, z.h * Uy) then
          love.graphics.draw(Renderer.canvas, uox, uoy, 0, Ux, Uy)
        end
      end
      love.graphics.setScissor()
      love.graphics.setShader()
    else
      Renderer:blitCanvas(Renderer.canvas, Ux, Uy, zones, Ux, Uy,
                          uox, uoy, uox, uoy, uvpw, uvph, DPI, DPI)
    end
    love.graphics.setCanvas()
    return probe:newImageData()
  end

  local top = math.floor(uoy * DPI)
  local bottom = math.floor((uoy + uvph) * DPI)
  local col = math.floor(uox * DPI) + 2
  local function blackRows(data)
    local rows = {}
    for py = top, math.min(bottom - 1, data:getHeight() - 1) do
      local r, g, b = data:getPixel(col, py)
      if r < 0.02 and g < 0.02 and b < 0.02 then rows[#rows + 1] = py end
    end
    return rows
  end

  local dataNew = renderProbe(false)
  local dataOld = renderProbe(true)
  local rowsNew, rowsOld = blackRows(dataNew), blackRows(dataOld)
  U.log(("picture rows %d-%d, sampling the background column at x=%d")
    :format(top, bottom - 1, col))
  U.log("pre-fix math left", #rowsOld, "black rows:",
        #rowsOld > 0 and table.concat(rowsOld, ",") or "none")
  check("no letterbox row shows through the zone boundaries", #rowsNew == 0)
  check("the emulated surface reproduces the seam without the fix", #rowsOld > 0)

  local ZOOM, CW, CH = 4, 220, 28
  local cy = math.max(top, math.floor((uoy + 64 * Uy) * DPI) - math.floor(CH / 2))
  local cx = math.floor(uox * DPI)
  local function zoomOf(data)
    local out = love.image.newImageData(CW * ZOOM, CH * ZOOM)
    out:mapPixel(function(x, y)
      return data:getPixel(cx + math.floor(x / ZOOM), cy + math.floor(y / ZOOM))
    end)
    return out
  end
  local function writePng(imageData, path)
    local dir = path:match("^(.*)[/\\][^/\\]+$")
    if dir and dir ~= "" then os.execute('mkdir -p "' .. dir .. '" 2>/dev/null') end
    local f = io.open(path, "wb")
    if not f then return false end
    f:write(imageData:encode("png"):getString())
    f:close()
    return true
  end

  local zoomOld, zoomNew = zoomOf(dataOld), zoomOf(dataNew)
  check("wrote " .. SHOT_DIR .. "/bug1453_before.png",
        writePng(zoomOld, SHOT_DIR .. "/bug1453_before.png"))
  check("wrote " .. SHOT_DIR .. "/bug1453_after.png",
        writePng(zoomNew, SHOT_DIR .. "/bug1453_after.png"))

  local imgOld = love.graphics.newImage(zoomOld)
  local imgNew = love.graphics.newImage(zoomNew)
  local baseDraw = love.draw
  love.draw = function()
    baseDraw()
    local w, h = love.graphics.getDimensions()
    local s = math.min((w - 24) / imgOld:getWidth(),
                       (h * 0.5 - 48) / (imgOld:getHeight() * 2))
    local bw = imgOld:getWidth() * s + 16
    local bh = imgOld:getHeight() * 2 * s + 56
    local bx, by = (w - bw) / 2, h - bh - 8
    love.graphics.setColor(0, 0, 0, 0.75)
    love.graphics.rectangle("fill", bx, by, bw, bh)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("BEFORE (dpi " .. DPI .. ")", bx + 8, by + 4)
    love.graphics.draw(imgOld, bx + 8, by + 20, 0, s, s)
    love.graphics.print("AFTER", bx + 8, by + 24 + imgOld:getHeight() * s)
    love.graphics.draw(imgNew, bx + 8, by + 40 + imgOld:getHeight() * s, 0, s, s)
  end

  PaletteFX.setMode(mode)
  U.wait(10)
  U.shot(game, SHOT_DIR .. "/bug1453_title.png")
  U.log("captured", SHOT_DIR .. "/bug1453_title.png")
  U.log("The title is live and the pad is yours; the strip along the bottom is")
  U.log("the row-64 zone boundary of an emulated " .. DPI .. "x Android surface,")
  U.log("magnified " .. ZOOM .. "x: BEFORE carries the black hairline across the")
  U.log("picture, AFTER is unbroken off-white. PROBE_DPI=2.75 tries another one.")

  while true do
    coroutine.yield()
  end
end
