local Stack = require("src.ui.game3.stack")

local Pouch = {}

Pouch.ID = "berry_pouch"
Pouch.VISIBLE = 7
-- pokefirered/include/constants/songs.h:9
Pouch.SE_SELECT = 5
Pouch._state = nil

local function clock()
  if love and love.timer and love.timer.getTime then return love.timer.getTime() end
  return os.clock()
end

local function BerryPouch()
  return require("src.ui.game3.berry_pouch")
end

local function MG()
  return require("src.core.game3.minigames.common")
end

local function rows()
  local st = Pouch._state
  if not st then return {} end
  return require("src.core.game3.bag").listPocket(st.bag, "BERRY_POUCH")
end

function Pouch.isOpen()
  return Pouch._state ~= nil
end

-- pokefirered/src/berry_crush.c:1033
function Pouch.open(session, done)
  local bag = type(session) == "table" and session.bag or nil
  local list = bag and require("src.core.game3.bag").listPocket(bag, "BERRY_POUCH") or {}
  if #list == 0 then
    done(nil)
    return false
  end
  local BP = BerryPouch()
  BP.show(session, bag, { fromBerryCrush = true, cursor = 1, scroll = 0 })
  Pouch._state = { done = done, bag = bag, fade = 16, target = 0, t0 = clock(), picked = nil }
  Stack.push(Pouch.ID, Pouch, { hideBelow = true, fullscreen = true })
  return true
end

function Pouch.close(itemId)
  local st = Pouch._state
  if not st then return end
  Pouch._state = nil
  local BP = BerryPouch()
  BP.open = false
  BP._onClose = nil
  Stack.pop(Pouch.ID)
  if st.done then st.done(itemId) end
end

local function stepFade(st)
  local frames = math.floor((clock() - st.t0) * 60)
  if st.target == 0 then
    st.fade = math.max(0, 16 - 2 * frames)
  else
    st.fade = math.min(16, 2 * frames)
  end
end

function Pouch.update(dt)
  local st = Pouch._state
  if not st then return end
  local BP = BerryPouch()
  if BP.update then BP.update(dt) end
  local mg = MG()
  mg.update(dt)
  local m = mg.match()
  if not mg.isActive() or (m and (m.phase == "error" or m.phase == "done")) then
    Pouch.close(nil)
    return
  end
  stepFade(st)
  -- pokefirered/src/berry_pouch.c:966
  if st.picked and st.fade >= 16 then Pouch.close(st.picked) end
end

local function move(delta)
  local BP = BerryPouch()
  local list = rows()
  local total = #list
  if total == 0 then return end
  local cur = math.max(1, math.min(total, (BP.cursor or 1) + delta))
  if cur == BP.cursor then return end
  BP.cursor = cur
  if BP.cursor <= BP.scroll then BP.scroll = BP.cursor - 1 end
  if BP.cursor > BP.scroll + Pouch.VISIBLE then BP.scroll = BP.cursor - Pouch.VISIBLE end
  if BP.scroll < 0 then BP.scroll = 0 end
  BP.wobbleTimer = 0.25
  pcall(function() require("src.core.game3.audio").playSe(Pouch.SE_SELECT) end)
end

-- pokefirered/src/berry_pouch.c:934
function Pouch.handleInput(input)
  local st = Pouch._state
  if not st or st.picked or st.fade > 0 or not input then return end
  if input:wasPressed("up") then
    move(-1)
  elseif input:wasPressed("down") then
    move(1)
  elseif input:wasPressed("left") or input:wasPressed("l") then
    move(-Pouch.VISIBLE)
  elseif input:wasPressed("right") or input:wasPressed("r") then
    move(Pouch.VISIBLE)
  elseif input:wasPressed("a") then
    local row = rows()[BerryPouch().cursor or 1]
    if row then
      pcall(function() require("src.core.game3.audio").playSe(Pouch.SE_SELECT) end)
      st.picked = require("src.core.game3.items_data").toNumericId(row.id) or tonumber(row.id)
      st.target = 16
      st.t0 = clock()
    end
  end
end

function Pouch.draw()
  local BP = BerryPouch()
  if BP.draw then BP.draw() end
  local st = Pouch._state
  if st and st.fade > 0 then
    love.graphics.setColor(0, 0, 0, st.fade / 16)
    love.graphics.rectangle("fill", 0, 0, 240, 160)
    love.graphics.setColor(1, 1, 1, 1)
  end
end

function Pouch.reset()
  if Pouch._state then
    Pouch._state = nil
    Stack.pop(Pouch.ID)
  end
end

return Pouch
