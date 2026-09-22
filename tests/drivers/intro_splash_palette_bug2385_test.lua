return function(game)
  local U = dofile("tests/drivers/util.lua")
  local P = require("src.render.PaletteFX")
  local GameVersion = require("src.core.GameVersion")
  local IntroMovie = require("src.ui.IntroMovie")
  local SHOT_DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "/tmp/shots"
  local version = GameVersion.get()
  local tag = "2385_" .. tostring(version)

  local STAR_START, FLASH_START, WAVES_START = 64, 104, 134

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

  local function waitFor(pred, limit)
    for _ = 1, limit or 3000 do
      if pred() then return true end
      U.wait(1)
    end
    return false
  end

  local function near(R, G, B, c, tol)
    tol = tol or 12
    return math.abs(R - c[1]) <= tol and math.abs(G - c[2]) <= tol
       and math.abs(B - c[3]) <= tol
  end

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

  local function load(path)
    local f = io.open(path, "rb")
    if not f then return false end
    local bytes = f:read("*a")
    f:close()
    local ok, img = pcall(function()
      return love.image.newImageData(love.filesystem.newFileData(bytes, "shot.png"))
    end)
    return ok and img or false
  end

  local function census(img, frame, bx1, by1, bx2, by2, colors)
    local W, H = img:getWidth(), img:getHeight()
    local ox, oy, scale = frame[1], frame[2], frame[3]
    local x1 = ox + math.floor(bx1 * scale + 0.5) + 1
    local y1 = oy + math.floor(by1 * scale + 0.5) + 1
    local x2 = ox + math.floor(bx2 * scale + 0.5) - 2
    local y2 = oy + math.floor(by2 * scale + 0.5) - 2
    local c = { black = 0 }
    for k in pairs(colors) do c[k] = 0 end
    for y = math.max(0, y1), math.min(H - 1, y2) do
      for x = math.max(0, x1), math.min(W - 1, x2) do
        local r, g, b = img:getPixel(x, y)
        local R = math.floor(r * 255 + 0.5)
        local G = math.floor(g * 255 + 0.5)
        local B = math.floor(b * 255 + 0.5)
        if R < 20 and G < 20 and B < 20 then c.black = c.black + 1 end
        for k, col in pairs(colors) do
          if near(R, G, B, col) then c[k] = c[k] + 1 end
        end
      end
    end
    local d = scale * scale
    for k, v in pairs(c) do c[k] = math.floor(v / d + 0.5) end
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
  local cols = {
    obj1 = obj[2], obj2 = obj[3], bg1 = bg[2], bg2 = bg[3],
    gray1 = { 170, 170, 170 }, gray2 = { 85, 85, 85 },
  }

  local function freeze() movie.update = function() end end
  local function thaw() movie.update = nil end

  local function shootAt(phase, timer, name)
    if not waitFor(function()
      return movie.phase > phase or (movie.phase == phase and movie.timer >= timer)
    end, 1200) or movie.phase ~= phase then
      check(tag .. " reached phase " .. phase .. " t" .. timer, false,
        movie.phase .. "/" .. movie.timer)
      return nil
    end
    freeze()
    local path = SHOT_DIR .. "/" .. tag .. "_" .. name .. ".png"
    local ok = U.shot(game, path)
    thaw()
    local img = ok and load(path)
    if not check(tag .. " shot " .. name, img and true or false) then return nil end
    return img, { letterbox(img) }
  end

  local LOGO = { 72, 56, 88, 80 }
  local TEXT = { 40, 80, 120, 88 }

  local img, fr = shootAt(1, 90, "01_copyright")
  if img then
    local c = census(img, fr, 16, 56, 144, 96, cols)
    U.log(string.format("copyright bg1=%d bg2=%d gray1=%d gray2=%d black=%d",
      c.bg1, c.bg2, c.gray1, c.gray2, c.black))
    check(tag .. " copyright shadows wear the boot-ROM BG ramp", c.bg1 + c.bg2 > 20,
      c.bg1 + c.bg2)
    check(tag .. " copyright card has no raw DMG grays", c.gray1 + c.gray2 == 0,
      c.gray1 + c.gray2)
  end

  img, fr = shootAt(2, STAR_START + 5, "02_logo_black")
  if img then
    local l = census(img, fr, LOGO[1], LOGO[2], LOGO[3], LOGO[4], cols)
    local t = census(img, fr, TEXT[1], TEXT[2], TEXT[3], TEXT[4], cols)
    U.log(string.format("logo black=%d obj=%d bg=%d | text black=%d obj=%d",
      l.black, l.obj1 + l.obj2, l.bg1 + l.bg2, t.black, t.obj1 + t.obj2))
    check(tag .. " logo starts black ($F9)", l.black > 60, l.black)
    check(tag .. " logo carries no BG ramp", l.bg1 + l.bg2 < 5, l.bg1 + l.bg2)
    check(tag .. " logo carries no OBJ ramp before the flash", l.obj1 + l.obj2 < 5,
      l.obj1 + l.obj2)
    check(tag .. " text starts black", t.black > 60, t.black)
  end

  img, fr = shootAt(2, FLASH_START + 5, "03_flash1_text_light")
  if img then
    local l = census(img, fr, LOGO[1], LOGO[2], LOGO[3], LOGO[4], cols)
    local t = census(img, fr, TEXT[1], TEXT[2], TEXT[3], TEXT[4], cols)
    check(tag .. " flash 1 ($7E): text goes OBJ0 light", t.obj1 > 60, t.obj1)
    check(tag .. " flash 1 ($7E): logo stays black", l.black > 60 and l.obj1 + l.obj2 < 5,
      l.black .. "/" .. (l.obj1 + l.obj2))
  end

  img, fr = shootAt(2, FLASH_START + 15, "04_flash2_logo_light")
  if img then
    local l = census(img, fr, LOGO[1], LOGO[2], LOGO[3], LOGO[4], cols)
    local t = census(img, fr, TEXT[1], TEXT[2], TEXT[3], TEXT[4], cols)
    check(tag .. " flash 2 ($9F): logo goes OBJ0 light", l.obj1 > 60, l.obj1)
    check(tag .. " flash 2 ($9F): text goes OBJ0 dark", t.obj2 > 60, t.obj2)
  end

  img, fr = shootAt(2, WAVES_START + 30, "05_settled_logo_dark")
  if img then
    local l = census(img, fr, LOGO[1], LOGO[2], LOGO[3], LOGO[4], cols)
    local t = census(img, fr, TEXT[1], TEXT[2], TEXT[3], TEXT[4], cols)
    local s = census(img, fr, 0, 90, 160, 112, cols)
    U.log(string.format("settled logo obj2=%d | text black=%d obj=%d | stars bg=%d obj=%d",
      l.obj2, t.black, t.obj1 + t.obj2, s.bg1 + s.bg2, s.obj1 + s.obj2))
    check(tag .. " settles on $E7: logo OBJ0 dark", l.obj2 > 60, l.obj2)
    check(tag .. " settles on $E7: text black", t.black > 60 and t.obj1 + t.obj2 < 5,
      t.black .. "/" .. (t.obj1 + t.obj2))
    check(tag .. " falling stars keep the BG ramp", s.bg1 + s.bg2 > 0 and s.obj1 + s.obj2 == 0,
      (s.bg1 + s.bg2) .. "/" .. (s.obj1 + s.obj2))
  end

  if movie.phase == 2 then
    freeze()
    game.save.options.colors = "gbc"
    P.applyOptions(game.save.options)
    movie.timer = STAR_START + 5
    local gf = P.pal(game.data, "GAMEFREAK")
    local path = SHOT_DIR .. "/" .. tag .. "_06_sgb_logo_black.png"
    local ok = U.shot(game, path)
    img = ok and load(path)
    if check(tag .. " shot 06_sgb_logo_black", img and gf and true or false) then
      fr = { letterbox(img) }
      local l = census(img, fr, LOGO[1], LOGO[2], LOGO[3], LOGO[4],
        { c3 = gf[3], c4 = gf[4] })
      check(tag .. " SGB logo starts on PAL_GAMEFREAK colour 4", l.c4 > 60 and l.c3 < 5,
        l.c4 .. "/" .. l.c3)
    end
    thaw()
  else
    check(tag .. " still on the splash for the SGB shot", false, movie.phase)
  end

  finish()
end
