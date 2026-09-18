local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp"

local function fail(label)
  print("FAIL " .. label)
  love.event.quit(1)
  while true do coroutine.yield() end
end

local function px8(img, x, y)
  local r, g, b, a = img:getPixel(x, y)
  return math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5), math.floor(a * 255 + 0.5)
end

local function render(fn)
  local canvas = love.graphics.newCanvas(240, 160)
  canvas:setFilter("nearest", "nearest")
  love.graphics.push("all")
  love.graphics.setCanvas(canvas)
  love.graphics.origin()
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.setColor(1, 1, 1, 1)
  fn()
  love.graphics.pop()
  return canvas:newImageData()
end

local function key(r, g, b) return r .. "," .. g .. "," .. b end

local function check_region(label, raw, full, tlX, tlY, x0, x1, y0, y1)
  local counts = {}
  for y = 0, 63 do
    for x = 0, 127 do
      local sx, sy = tlX + x, tlY + y
      if sx >= 0 and sx < 240 and sy >= 0 and sy < 160 then
        local r, g, b, a = px8(raw, sx, sy)
        if a == 255 then
          local k = key(r, g, b)
          counts[k] = (counts[k] or 0) + 1
        end
      end
    end
  end
  local cream, best = nil, -1
  for k, n in pairs(counts) do
    if n > best then cream, best = k, n end
  end
  print("U3 " .. label .. " baked cream", cream)
  local erased, bad = 0, 0
  for y = y0, y1 do
    for x = x0, x1 do
      local rr, rg, rb = px8(raw, tlX + x, tlY + y)
      if key(rr, rg, rb) ~= cream then
        local fr, fg, fb = px8(full, tlX + x, tlY + y)
        local k = key(fr, fg, fb)
        if k == cream then
          erased = erased + 1
        elseif k == key(rr, rg, rb) or k == "248,248,216" then
          bad = bad + 1
          print("U3 " .. label .. " ghost px", x, y, k)
        end
      end
    end
  end
  print("U3 " .. label .. " erased", erased, "ghost", bad)
  return erased > 0 and bad == 0
end

return function(game)
  for _ = 1, 600 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(180)
  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local session = Runtime.getSession()
  if not session then fail("u3 session") end
  session.party = {}
  Party.giveMon(session, 4, 5)
  local BattleBridge = require("src.core.game3.battle_bridge")
  local ok, err = BattleBridge.startWild(Runtime._mod, game, { species = 16, level = 3 }, { fade = false })
  if not ok then print("U3 start", err) fail("u3 battle start") end
  local Battle = require("src.core.game3.battle")
  local Ui = require("src.core.game3.battle.ui")
  for i = 1, 1500 do
    if Ui._mode == "menu" then break end
    if i % 20 == 0 then U.tap(game, "a") else U.wait(1) end
  end
  if Ui._mode ~= "menu" then fail("u3 reached action menu") end
  U.wait(30)
  local st = Battle._st
  local Anim = require("src.core.game3.battle.anim")
  local mon = st and st.player and st.player.mon
  if not mon then fail("u3 player mon") end
  mon.hp = 7
  Anim.syncDisplayFromState(st)
  U.wait(20)

  local BattleChrome = require("src.ui.game3.battle_chrome")
  local Healthbox = require("src.core.game3.battle.healthbox")
  local ptlX, ptlY = Healthbox.PLAYER_CENTER.x - 32, Healthbox.PLAYER_CENTER.y - 16
  local etlX, etlY = Healthbox.ENEMY_CENTER.x - 32, Healthbox.ENEMY_CENTER.y - 16
  local rawP = render(function() BattleChrome.drawPlayerBox(ptlX, ptlY) end)
  local fullP = render(function() Healthbox.draw("player", st.player) end)
  local rawE = render(function() BattleChrome.drawEnemyBox(etlX, etlY) end)
  local fullE = render(function() Healthbox.draw("enemy", st.enemy) end)

  local passP = check_region("player_slash", rawP, fullP, ptlX, ptlY, 64, 71, 24, 31)
  local passE = check_region("enemy_lv", rawE, fullE, etlX, etlY, 56, 63, 10, 15)

  if not U.shot(game, DIR .. "/u3_01_hp_7_no_ghost_slash_or_lv.png") then fail("u3 shot") end

  local all = true
  if passP then print("PASS u3 player healthbox no ghost slash at 1-digit hp") else print("FAIL u3 player healthbox no ghost slash at 1-digit hp") all = false end
  if passE then print("PASS u3 enemy healthbox no ghost Lv") else print("FAIL u3 enemy healthbox no ghost Lv") all = false end
  love.event.quit(all and 0 or 1)
  while true do coroutine.yield() end
end
