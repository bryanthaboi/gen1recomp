-- POKEPORT_IDENTITY=red-sep04 POKEPORT_DRIVER=tests/drivers/intro_og_obj_palette_bug2264_test.lua POKEPORT_SHOT_DIR=/tmp/shots love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local P = require("src.render.PaletteFX")
  local GameVersion = require("src.core.GameVersion")
  local IntroMovie = require("src.ui.IntroMovie")
  local SHOT_DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "/tmp/shots"
  local version = GameVersion.get()
  local tag = "2264_" .. tostring(version)

  local fails = 0
  local function check(label, ok, detail)
    U.log(ok and "PASS" or "FAIL", label, detail or "")
    if not ok then fails = fails + 1 end
    return ok
  end

  local function finish()
    P.applyOptions({ colors = "ogred" })
    if fails > 0 then
      U.log("FAIL " .. tag .. ": " .. fails .. " check(s), shots in " .. SHOT_DIR)
      love.event.quit(1)
    else
      U.log("PASS " .. tag .. ": all checks, shots in " .. SHOT_DIR)
      love.event.quit(0)
    end
    while true do coroutine.yield() end
  end

  local rendered = 0
  local hostDraw = love.draw
  love.draw = function(...)
    local r = hostDraw(...)
    rendered = rendered + 1
    return r
  end

  local function waitRenderedFrames(frames)
    local target = rendered + (frames or 2)
    for _ = 1, 2400 do
      if rendered >= target then return true end
      U.wait(1)
    end
    return false
  end

  local function waitFor(pred, limit)
    for _ = 1, limit or 3000 do
      if pred() then return true end
      U.wait(1)
    end
    return false
  end

  local function near(R, G, B, c)
    return math.abs(R - c[1]) <= 12 and math.abs(G - c[2]) <= 12
       and math.abs(B - c[3]) <= 12
  end

  local objRamp, bgRamp

  local function letterbox(img)
    local W, H = img:getWidth(), img:getHeight()
    local x1, y1, x2, y2 = W, H, -1, -1
    for y = 0, H - 1 do
      for x = 0, W - 1 do
        local r, g, b = img:getPixel(x, y)
        if r > 0.02 or g > 0.02 or b > 0.02 then
          if x < x1 then x1 = x end
          if x > x2 then x2 = x end
          if y < y1 then y1 = y end
          if y > y2 then y2 = y end
        end
      end
    end
    local bw, bh = x2 - x1 + 1, y2 - y1 + 1
    if x2 >= x1 and math.abs(bw / 160 - bh / 144) < 0.05 then
      return x1, y1, bh / 144
    end
    local s = math.min(W / 160, H / 144)
    return math.floor((W - 160 * s) / 2), math.floor((H - 144 * s) / 2), s
  end

  local shotImg = {}
  local function load(path)
    if shotImg[path] ~= nil then return shotImg[path] end
    local f = io.open(path, "rb")
    if not f then shotImg[path] = false return false end
    local bytes = f:read("*a")
    f:close()
    local ok, img = pcall(function()
      return love.image.newImageData(love.filesystem.newFileData(bytes, "shot.png"))
    end)
    shotImg[path] = ok and img or false
    return shotImg[path]
  end

  local function census(path, bx1, by1, bx2, by2)
    local img = load(path)
    if not img then return nil end
    local W, H = img:getWidth(), img:getHeight()
    local ox, oy, scale = letterbox(img)
    local x1 = ox + math.floor(bx1 * scale + 0.5) + 1
    local y1 = oy + math.floor(by1 * scale + 0.5) + 1
    local x2 = ox + math.floor(bx2 * scale + 0.5) - 2
    local y2 = oy + math.floor(by2 * scale + 0.5) - 2
    local c = { obj = 0, bg = 0, black = 0, total = 0 }
    for y = math.max(0, y1), math.min(H - 1, y2) do
      for x = math.max(0, x1), math.min(W - 1, x2) do
        local r, g, b = img:getPixel(x, y)
        local R = math.floor(r * 255 + 0.5)
        local G = math.floor(g * 255 + 0.5)
        local B = math.floor(b * 255 + 0.5)
        c.total = c.total + 1
        if R < 20 and G < 20 and B < 20 then c.black = c.black + 1 end
        if near(R, G, B, objRamp[1]) or near(R, G, B, objRamp[2]) then c.obj = c.obj + 1 end
        if near(R, G, B, bgRamp[1]) or near(R, G, B, bgRamp[2]) then c.bg = c.bg + 1 end
      end
    end
    local d = scale * scale
    c.obj = math.floor(c.obj / d + 0.5)
    c.bg = math.floor(c.bg / d + 0.5)
    return c
  end

  local movie
  check(tag .. " intro is on the stack", waitFor(function()
    movie = game.stack:top()
    return getmetatable(movie) == IntroMovie
  end, 600))
  if getmetatable(movie) ~= IntroMovie then finish() end

  game.save.options.colors = "ogred"
  P.applyOptions(game.save.options)
  check(tag .. " COLORS is ogred", P.mode == "ogred", P.mode)
  local blue = GameVersion.isBlue()
  local obj = blue and P.GBC_OBJ_BLUE or P.GBC_OBJ
  local bg = P.ogBg()
  objRamp = { obj[2], obj[3] }
  bgRamp = { bg[2], bg[3] }

  check(tag .. " scrollIn finished", waitFor(function()
    return movie.phase == 3 and movie.opIndex > 1 and movie.nidoX == 72
  end, 3000), tostring(movie.nidoX))
  waitRenderedFrames(3)
  local nidoX, nidoY, gengarX = movie.nidoX, movie.nidoY, movie.gengarX
  local shot1 = SHOT_DIR .. "/" .. tag .. "_01_fight_after_scroll_in.png"
  check(tag .. " replay recorded", #P.uiSpriteRedraws() >= 2, "#" .. #P.uiSpriteRedraws())
  if check(tag .. " shot 01", U.shot(game, shot1) and load(shot1)) then
    local nido = census(shot1, math.max(nidoX, gengarX + 56), nidoY, nidoX + 48, 112)
    local gengar = census(shot1, gengarX, 56, math.min(gengarX + 56, nidoX), 112)
    local topBar = census(shot1, 0, 0, 160, 32)
    local botBar = census(shot1, 0, 112, 160, 144)
    U.log(string.format("nido band obj=%d bg=%d | gengar band obj=%d bg=%d",
      nido.obj, nido.bg, gengar.obj, gengar.bg))
    check(tag .. " front mon wears the boot-ROM OBJ ramp", nido.obj > 150, nido.obj)
    check(tag .. " front mon carries no BG ramp", nido.bg < 20, nido.bg)
    check(tag .. " Gengar keeps the BG ramp", gengar.bg > 150, gengar.bg)
    check(tag .. " Gengar carries no OBJ ramp", gengar.obj < 20, gengar.obj)
    check(tag .. " top bar stays solid black", topBar.black == topBar.total,
      topBar.black .. "/" .. topBar.total)
    check(tag .. " bottom bar covers the OAM_PRIO sprite", botBar.black == botBar.total,
      botBar.black .. "/" .. botBar.total)
  end

  local function near1(path, c, bx1, by1, bx2, by2)
    local img = load(path)
    if not img then return 0, 1 end
    local ox, oy, scale = letterbox(img)
    local hit, total = 0, 0
    for y = oy + math.floor(by1 * scale) + 1, oy + math.floor(by2 * scale) - 2 do
      for x = ox + math.floor(bx1 * scale) + 1, ox + math.floor(bx2 * scale) - 2 do
        local r, g, b = img:getPixel(x, y)
        total = total + 1
        if near(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
                math.floor(b * 255 + 0.5), c) then hit = hit + 1 end
      end
    end
    return hit, total
  end

  for step, want in ipairs({ { name = "fadepal6_bars_bg_shade2", c = bg[3] },
                             { name = "fadepal7_bars_bg_shade1", c = bg[2] } }) do
    check(tag .. " reached fade step " .. step, waitFor(function()
      return movie.fadeStep == step or movie.phase == 4
    end, 3000), tostring(movie.fadeStep))
    if movie.phase ~= 3 then break end
    local upd = movie.update
    movie.update = function() end
    waitRenderedFrames(2)
    local shot = SHOT_DIR .. "/" .. tag .. "_0" .. (step + 1) .. "_" .. want.name .. ".png"
    if check(tag .. " shot fade step " .. step, U.shot(game, shot) and load(shot)) then
      local hit, total = near1(shot, want.c, 0, 112, 160, 144)
      check(tag .. " fade step " .. step .. " bottom bar is BG shade " .. (3 - step),
        hit == total, hit .. "/" .. total)
      hit, total = near1(shot, want.c, 0, 0, 160, 32)
      check(tag .. " fade step " .. step .. " top bar is BG shade " .. (3 - step),
        hit == total, hit .. "/" .. total)
    end
    movie.update = upd
  end

  finish()
end
