-- engine/movie/title.asm:76, engine/movie/title_yellow.asm:61
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local P = require("src.render.PaletteFX")
  local SHOT_DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "/tmp/shots"

  local fails = 0
  local function check(label, ok, detail)
    U.log(ok and "PASS" or "FAIL", label, detail or "")
    if not ok then fails = fails + 1 end
    return ok
  end

  local function waitFor(pred, limit)
    for _ = 1, limit or 1800 do
      if pred() then return true end
      U.wait(1)
    end
    return false
  end

  local function loadShot(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local bytes = f:read("*a")
    f:close()
    local ok, img = pcall(function()
      return love.image.newImageData(
        love.filesystem.newFileData(bytes, "shot.png"))
    end)
    return ok and img or nil
  end

  local function letterbox(img)
    local W, H = img:getWidth(), img:getHeight()
    local s = math.max(1, math.floor(math.min(W / 160, H / 144)))
    return math.floor((W - 160 * s) / 2), math.floor((H - 144 * s) / 2), s
  end

  local function count(img, bx1, by1, bx2, by2, pred)
    local ox, oy, s = letterbox(img)
    local n = 0
    for y = by1, by2 do
      for x = bx1, bx2 do
        local px = math.min(img:getWidth() - 1, ox + math.floor((x + 0.5) * s))
        local py = math.min(img:getHeight() - 1, oy + math.floor((y + 0.5) * s))
        local r, g, b = img:getPixel(px, py)
        if pred(r * 255, g * 255, b * 255) then n = n + 1 end
      end
    end
    return n
  end

  local function isRed(r, g, b) return r > 180 and r - g > 60 and r - b > 60 end
  local function isDarkGrey(r, g, b)
    return math.abs(r - g) < 8 and math.abs(g - b) < 8 and r > 40 and r < 140
  end

  local title
  local function onTitle()
    local top = game.stack:top()
    if top and top.screenId == "TitleState" then title = top return true end
    return false
  end
  for _ = 1, 40 do
    if onTitle() then break end
    U.tap(game, "start")
    U.wait(20)
  end
  if not check("reached the title screen", onTitle()) then
    love.event.quit(1)
    return
  end
  check("title reached the loop phase",
        waitFor(function() return title.phase == "loop" end))

  local EYES = { { 56, 80, 71, 95 }, { 88, 80, 103, 95 } }
  for _, mode in ipairs({ "gbc", "og" }) do
    P.applyOptions({ colors = mode })
    check(mode .. " eyes open", waitFor(function()
      local t = title.blinkTimer or 0
      return title:blinkOverlay() == nil and t > 0x20 and t < 0x70
    end, 1200))
    local shot = SHOT_DIR .. "/2804_title_eyes_" .. mode .. ".png"
    if check(mode .. " shot written", U.still(game, shot)) then
      local img = loadShot(shot)
      if check(mode .. " shot decoded", img ~= nil) then
        local pred = mode == "gbc" and isRed or isDarkGrey
        for i, e in ipairs(EYES) do
          local n = count(img, e[1], e[2], e[3], e[4], pred)
          check(string.format("%s eye %d has OBJ color 2 pixels under the iris",
            mode, i), n >= 3, tostring(n))
        end
      end
    end
  end
  P.applyOptions({ colors = "gbc" })

  U.log(fails == 0 and "PASS 2804" or ("FAIL 2804 " .. fails))
  love.event.quit(fails == 0 and 0 or 1)
end
