-- Minimal second-window process for src/render/DesktopScreen.lua.

local DesktopCompanion = {}

function DesktopCompanion.install(config)
  local enet = require("enet")
  local host = assert(enet.host_create())
  local peer = assert(host:connect(("127.0.0.1:%d"):format(config.port), 2))
  local image, sourceW, sourceH, preference
  local background = { 0, 0, 0, 1 }
  local connected, commandedQuit = false, false
  local pointerDown = false
  local started = love.timer.getTime()
  local lastContact = started

  local function send(kind, payload)
    if not connected then return end
    pcall(peer.send, peer, kind .. config.token .. (payload or ""), 1, "reliable")
  end

  local function receiveFrame(data)
    local prefix = "F" .. config.token .. "\n"
    if data:sub(1, #prefix) ~= prefix then return end
    local split = data:find("\n", #prefix + 1, true)
    if not split then return end
    local w, h, rgb, mode = data:sub(#prefix + 1, split - 1)
      :match("^(%d+),(%d+),(%d+),([%w_:.-]+)$")
    w, h, rgb = tonumber(w), tonumber(h), tonumber(rgb)
    if not w or not h or w < 1 or h < 1 or w > 4096 or h > 4096 then return end
    local ok, raw = pcall(love.data.decompress, "string", "lz4",
      data:sub(split + 1))
    if not ok or type(raw) ~= "string" or #raw ~= w * h * 4 then return end
    local made, pixels = pcall(love.image.newImageData, w, h, "rgba8", raw)
    if not made then return end
    if not image or sourceW ~= w or sourceH ~= h then
      if image and image.release then image:release() end
      image = love.graphics.newImage(pixels)
    else
      image:replacePixels(pixels)
    end
    sourceW, sourceH, preference = w, h, mode
    image:setFilter(mode:find("cover", 1, true) and "linear" or "nearest",
      mode:find("cover", 1, true) and "linear" or "nearest")
    background = {
      math.floor(rgb / 0x10000) % 0x100 / 255,
      math.floor(rgb / 0x100) % 0x100 / 255,
      rgb % 0x100 / 255, 1,
    }
  end

  local function service()
    while true do
      local event = host:service(0)
      if not event then break end
      if event.type == "connect" then
        connected, lastContact = true, love.timer.getTime()
        send("H")
      elseif event.type == "receive" then
        lastContact = love.timer.getTime()
        if event.data == "Q" .. config.token then
          commandedQuit = true
          love.event.quit()
        elseif event.data ~= "P" .. config.token then
          receiveFrame(event.data)
        end
      elseif event.type == "disconnect" then
        love.event.quit()
      end
    end
  end

  local function placement()
    if not image then return 0, 0, 1 end
    local ww, wh = love.graphics.getDimensions()
    local cover = preference and preference:find("cover", 1, true)
    local dpi = love.graphics.getDPIScale and love.graphics.getDPIScale() or 1
    local dpiY = dpi
    if love.graphics.getPixelDimensions then
      local pw, ph = love.graphics.getPixelDimensions()
      if ww > 0 and wh > 0 and pw > 0 and ph > 0 then dpi, dpiY = pw / ww, ph / wh end
    end
    local width, height = math.floor(ww*dpi + 1e-7), math.floor(wh*dpiY + 1e-7)
    local scale = (cover and math.max or math.min)(width / sourceW, height / sourceH)
    if preference and preference:match(":integer$") and scale >= 1 then
      scale = math.floor(scale + 1e-7)
    end
    return math.floor((width - sourceW * scale) / 2 + 1e-7) / dpi,
      math.floor((height - sourceH * scale) / 2 + 1e-7) / dpiY, scale / dpi, scale / dpiY
  end

  local function input(action, x, y)
    if not image then return false end
    local dx, dy, scaleX, scaleY = placement()
    local sx, sy = math.floor((x - dx) / scaleX), math.floor((y - dy) / scaleY)
    if sx < 0 or sy < 0 or sx >= sourceW or sy >= sourceH then return false end
    send("I", ("\n%s,%d,%d"):format(action, sx, sy))
    return true
  end

  function love.update()
    service()
    local t = love.timer.getTime()
    if (not connected and t - started > 5) or t - lastContact > 5 then
      love.event.quit()
    end
  end

  function love.draw()
    love.graphics.clear(background[1], background[2], background[3], background[4])
    if not image then return end
    local x, y, scaleX, scaleY = placement()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(image, x, y, 0, scaleX, scaleY)
  end

  function love.mousepressed(x, y, button)
    if button == 1 then pointerDown = input("down", x, y) end
  end
  function love.mousereleased(x, y, button)
    if button == 1 and pointerDown then
      if not input("up", x, y) then send("I", "\ncancel,0,0") end
      pointerDown = false
    end
  end
  function love.touchpressed(_, x, y) input("down", x, y) end
  function love.touchreleased(_, x, y) input("up", x, y) end
  function love.keypressed(key)
    if key == "escape" then love.event.quit() end
  end
  function love.quit()
    if not commandedQuit then send("C") end
    pcall(peer.disconnect_now, peer)
  end
end

return DesktopCompanion
