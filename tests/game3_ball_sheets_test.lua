#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;" .. package.path
local GameCache = require("tests.game3_cache")
local root = GameCache.mountOrSkip("game3_ball_sheets_test")
require("tests.fixture_data.game3_items").install()

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function slurp(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local d = f:read("*a")
  f:close()
  return d
end

local NAMES = { [0] = "poke", "great", "safari", "ultra", "master", "net",
  "dive", "nest", "repeat", "timer", "luxury", "premier" }
local W, H = 16 * 12, 48

local rgba = slurp(root .. "/pokemon/battle/ball_open/balls.rgba")
print("[test] baked ball sheet strip")
check(rgba ~= nil and #rgba == W * H * 4, "balls.rgba is 192x48 RGBA")

local function alpha(ball, x, y)
  return rgba:byte(((y * W) + ball * 16 + x) * 4 + 4)
end

if rgba and #rgba == W * H * 4 then
  for ball = 0, 11 do
    local n = 0
    for y = 32, 47 do
      for x = 0, 15 do
        if alpha(ball, x, y) ~= 0 then n = n + 1 end
      end
    end
    check(n > 0, "ball " .. NAMES[ball] .. " open frame 2 is not blank")
  end

  local pret = "../pokefirered/graphics/interface/"
  local openGfx = slurp(pret .. "ball_open.4bpp")
  if not openGfx then
    print("[skip] pret pokefirered graphics not found; pixel parity not checked")
  else
    print("[test] pixel parity vs pret graphics/interface/ball/*.4bpp + ball_open.4bpp")
    local NO_SPLICE = { [6] = true, [10] = true, [11] = true }
    for ball = 0, 11 do
      local gfx = slurp(pret .. "ball/" .. NAMES[ball] .. ".4bpp")
      local pal = slurp(pret .. "ball/" .. NAMES[ball] .. ".gbapal")
      local bad = 0
      for ti = 0, 11 do
        local src, off = gfx, ti * 32
        if ti >= 8 and not NO_SPLICE[ball] then src, off = openGfx, (ti - 8) * 32 end
        local frame, sub = math.floor(ti / 4), ti % 4
        for py = 0, 7 do
          for px = 0, 7 do
            local byte = src:byte(off + py * 4 + math.floor(px / 2) + 1)
            local idx = (px % 2 == 0) and (byte % 16) or math.floor(byte / 16)
            local x = (sub % 2) * 8 + px
            local y = frame * 16 + math.floor(sub / 2) * 8 + py
            local o = ((y * W) + ball * 16 + x) * 4
            local r, g, b, a = rgba:byte(o + 1, o + 4)
            if idx == 0 then
              if a ~= 0 then bad = bad + 1 end
            else
              local c = pal:byte(idx * 2 + 1) + pal:byte(idx * 2 + 2) * 256
              local er, eg, eb = c % 32, math.floor(c / 32) % 32, math.floor(c / 1024) % 32
              local function to8(v) return math.floor(v * 255 / 31 + 0.5) end
              if a ~= 255 or r ~= to8(er) or g ~= to8(eg) or b ~= to8(eb) then bad = bad + 1 end
            end
          end
        end
      end
      check(bad == 0, NAMES[ball] .. " ball sheet matches pret (" .. bad .. " px differ)")
    end
  end
end

local BallOpen = require("src.core.game3.battle.ball_open")
local Anim = require("src.core.game3.battle.anim")
local CatchSeq = require("src.core.game3.battle.catch_seq")
local Catching = require("src.core.game3.battle.catching")
local Audio = require("src.core.game3.audio")
local Ui = require("src.core.game3.battle.ui")
local SummaryMenu = require("src.ui.game3.summary_menu")

print("[test] manifest names the ball strip")
local d = BallOpen.data()
check(d and d.ballSheet == "balls.rgba" and d.ballSheetW == W and d.ballSheetH == H, "manifest ballSheet/ballSheetW/ballSheetH")

print("[test] battle renderer picks the per-ball column")
local realLove = rawget(_G, "love")
love = {
  image = { newImageData = function(w, h) return { w = w, h = h } end },
  graphics = {
    newImage = function(id) return { getDimensions = function() return id.w, id.h end, setFilter = function() end } end,
    newQuad = function(x, y, w, h) return { x = x, y = y, w = w, h = h } end,
  },
}
local okQ = type(Ui.ballQuad) == "function"
check(okQ, "Ui.ballQuad exists")
if okQ then
  local img, q = Ui.ballQuad(11, 2)
  check(img ~= nil and q and q.x == 176 and q.y == 32, "premier open frame quad at (176,32)")
  local _, q3 = Ui.ballQuad(3, 0)
  check(q3 and q3.x == 48 and q3.y == 0, "ultra closed frame quad at (48,0)")
  local _, qn = Ui.ballQuad(nil, 1)
  check(qn and qn.x == 0 and qn.y == 16, "missing ball id draws the poke ball")
end
love = realLove

print("[test] thrown ball is tagged with the used item's ball")
Audio.playSe = function() return true end
Audio.stopAll = function() end
Audio.waitSe = function() end
Audio.playSong = function() return true end
Catching.storeCaught = function() return { firstTimeCaught = false } end
Ui.battlerSpriteCenter = function(_, _, base) return base.x, base.y end
for _, case in ipairs({ { 12, 11 }, { 2, 3 }, { 3, 1 }, { 1, 4 }, { 4, 0 }, { 11, 10 }, { 7, 6 } }) do
  Anim.reset({ headless = false })
  Anim.present("enemy").visible = true
  local st = { enemy = { species = 16, mon = { species = 16, name = "PIDGEY" } } }
  CatchSeq.begin(st, case[1], false, 1, {
    pushMsg = function() end, headless = false, session = { name = "RED" },
  })
  CatchSeq.update()
  CatchSeq._waitingMsg = false
  CatchSeq.update()
  local seen
  for _ = 1, 120 do
    Anim.update(1 / 60)
    local s = Anim.stage().ball
    if s.visible then seen = s.ballId break end
  end
  check(seen == case[2], ("item %d throws ball sheet %d (got %s)"):format(case[1], case[2], tostring(seen)))
end

print("[test] summary ball icon id")
check(type(SummaryMenu.ballIdOf) == "function", "SummaryMenu.ballIdOf exists")
if type(SummaryMenu.ballIdOf) == "function" then
  check(SummaryMenu.ballIdOf({ species = 25, pokeball = 12 }) == 11, "premier-caught mon shows premier icon")
  check(SummaryMenu.ballIdOf({ species = 25, pokeball = 1 }) == 4, "master-caught mon shows master icon")
  check(SummaryMenu.ballIdOf({ species = 25, pokeball = 12, isEgg = true }) == 0, "egg shows poke ball icon")
end

if failed > 0 then
  print(("[FAIL] %d check(s) failed"):format(failed))
  os.exit(1)
end
print("[ok] game3_ball_sheets_test")
