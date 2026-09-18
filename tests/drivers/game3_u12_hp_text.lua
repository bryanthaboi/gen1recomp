local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp"

return function(game)
  local fails = 0
  local function check(cond, label)
    if cond then
      print("PASS " .. label)
    else
      fails = fails + 1
      print("FAIL " .. label)
    end
  end

  U.wait(30)
  game:_handleBootAction({ action = "new_game", name = "RED", rivalName = "BLUE", gender = 0 })
  U.wait(120)
  local Runtime = require("src.core.game3.runtime")
  local session = Runtime.getSession()
  local Party = require("src.core.game3.party")
  session.party = {}
  Party.giveMon(session, 52, 50)
  local lead = session.party[1]
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Ui = require("src.core.game3.battle.ui")
  local Healthbox = require("src.core.game3.battle.healthbox")

  local function find(needle)
    for i, t in ipairs(Ui.log() or {}) do
      if t:find(needle, 1, true) then return i end
    end
    return nil
  end

  local function shotData(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local bytes = f:read("*a")
    f:close()
    local ok, img = pcall(love.image.newImageData, love.filesystem.newFileData(bytes, "shot.png"))
    return ok and img or nil
  end

  local function sampler(img)
    local W, H = img:getDimensions()
    local s = math.max(1, math.min(math.floor(W / 240), math.floor(H / 160)))
    local ox, oy = math.floor((W - 240 * s) / 2), math.floor((H - 160 * s) / 2)
    local tlx, tly = Healthbox.PLAYER_CENTER.x - 32, Healthbox.PLAYER_CENTER.y - 16
    return function(bx, by)
      local r, g, b = img:getPixel(ox + (tlx + bx) * s + math.floor(s / 2), oy + (tly + by) * s + math.floor(s / 2))
      return math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5)
    end
  end

  local function isInk(px, bx, by)
    local r, g, b = px(bx, by)
    return r == 66 and g == 66 and b == 66
  end

  local function checkShot(path, tag)
    local img = shotData(path)
    check(img ~= nil, tag .. " shot readable")
    if not img then return end
    local px = sampler(img)
    local stray
    for by = 16, 23 do
      for bx = 56, 95 do
        if isInk(px, bx, by) then stray = stray or string.format("(%d,%d)", bx, by) end
      end
    end
    check(stray == nil, tag .. " no text ink on the HP bar rows 16-23" .. (stray and (" first at " .. stray) or ""))
    local minY, maxY, minX, maxX = 99, -1, 999, -1
    for by = 24, 31 do
      for bx = 56, 95 do
        if isInk(px, bx, by) then
          minY, maxY = math.min(minY, by), math.max(maxY, by)
          minX, maxX = math.min(minX, bx), math.max(maxX, bx)
        end
      end
    end
    print(string.format("U12 %s ink bbox x%d-%d y%d-%d", tag, minX, maxX, minY, maxY))
    check(maxY == 31, tag .. " digits bottom row at box y31")
    check(isInk(px, 78, 24) and isInk(px, 75, 31), tag .. " slash cell at box x75")
    check(minX >= 60, tag .. " current HP starts at box x60 or right of it")
  end

  local ok = BattleBridge.startWild(Runtime._mod, game, { species = 16, level = 2 }, {})
  check(ok, "u12 wild battle started")
  local sentOut = false
  for f = 1, 4000 do
    U.wait(1)
    if find("Go!") and Ui.waitingForCommand() then sentOut = true break end
    if f % 20 == 0 and not Ui.waitingForCommand() then U.tap(game, "a") end
  end
  check(sentOut, "u12 MEOWTH sent out and command menu up")
  U.wait(120)
  local hp, maxHp = tonumber(lead.hp), tonumber(lead.maxHp)
  print("U12 MEOWTH HP", hp, maxHp)
  check(hp == maxHp and maxHp >= 100 and maxHp <= 999, "u12 L50 MEOWTH has a real 3-digit HP")
  local p1 = DIR .. "/u12_01_full_hp_3digit_healthbox.png"
  U.shot(game, p1)
  checkShot(p1, "u12 full hp")

  local Battle = require("src.core.game3.battle")
  local st = Battle.getState and Battle.getState()
  local battler = st and st.player
  local Anim = require("src.core.game3.battle.anim")
  local pres = Anim.present and Anim.present("player")
  if battler and battler.mon then
    battler.mon.hp = 7
    if pres and pres.displayHp ~= nil then pres.displayHp = 7 end
    U.wait(30)
    local p2 = DIR .. "/u12_02_one_digit_hp_right_aligned.png"
    U.shot(game, p2)
    checkShot(p2, "u12 one digit hp")
    battler.mon.hp = maxHp
    if pres and pres.displayHp ~= nil then pres.displayHp = maxHp end
  else
    print("U12 no battler handle for the 1-digit shot")
  end

  if fails == 0 then
    print("PASS u12 hp text")
    love.event.quit(0)
  else
    print("FAIL u12 hp text")
    love.event.quit(1)
  end
end
