local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp"

return function(game)
  local ok = true
  local function expect(cond, label)
    if cond then
      print("PASS " .. label)
    else
      print("FAIL " .. label)
      ok = false
    end
  end

  local function loadShot(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local bytes = f:read("*a")
    f:close()
    local okData, fd = pcall(love.filesystem.newFileData, bytes, "shot.png")
    if not okData then return nil end
    local okImg, img = pcall(love.image.newImageData, fd)
    if not okImg then return nil end
    return img
  end

  local function blockStats(img, ox, oy, k)
    local iw, ih = img:getDimensions()
    local bad, total = 0, 0
    for by = 0, 159 do
      for bx = 0, 239 do
        local x0, y0 = ox + bx * k, oy + by * k
        if x0 + k <= iw and y0 + k <= ih then
          total = total + 1
          local r0, g0, b0 = img:getPixel(x0, y0)
          local uniform = true
          for yy = y0, y0 + k - 1 do
            for xx = x0, x0 + k - 1 do
              local r, g, b = img:getPixel(xx, yy)
              if r ~= r0 or g ~= g0 or b ~= b0 then uniform = false break end
            end
            if not uniform then break end
          end
          if not uniform then bad = bad + 1 end
        end
      end
    end
    return bad, total
  end

  U.wait(30)
  local start = { map = "FR_PALLET_TOWN", x = 8, y = 10, facing = "down" }
  game:_handleBootAction({ action = "new_game", name = "RED", rivalName = "BLUE", gender = 0, start = start })
  U.wait(120)

  local Display = require("src.core.game3.display")
  local sizes = {
    { 1360, 860, 5, "u6_01_landscape_1360x860_5x" },
    { 1024, 768, 4, "u6_02_landscape_1024x768_4x" },
    { 900, 1100, 3, "u6_03_portrait_900x1100_3x" },
    { 700, 1000, 2, "u6_04_portrait_700x1000_2x" },
  }
  for _, sz in ipairs(sizes) do
    love.window.updateMode(sz[1], sz[2], { resizable = true })
    U.wait(20)
    local w, h = love.graphics.getDimensions()
    local scale, ox, oy, _, _, scaleY = Display.fit(w, h)
    print("U6 size", w, h, "scale", scale, scaleY, "ox", ox, "oy", oy)
    expect(scale == sz[3] and scaleY == sz[3], sz[4] .. " whole scale " .. sz[3])
    expect(ox == math.floor(ox) and oy == math.floor(oy), sz[4] .. " whole-pixel offsets")
    local path = DIR .. "/" .. sz[4] .. ".png"
    U.shot(game, path)
    local img = loadShot(path)
    expect(img ~= nil, sz[4] .. " shot readable")
    if img then
      local bad, total = blockStats(img, ox, oy, sz[3])
      print("U6 blocks", sz[4], "nonuniform", bad, "of", total)
      expect(total == 240 * 160 and bad == 0, sz[4] .. " every texel is a uniform " .. sz[3] .. "x" .. sz[3] .. " block")
    end
  end

  love.event.quit(ok and 0 or 1)
end
