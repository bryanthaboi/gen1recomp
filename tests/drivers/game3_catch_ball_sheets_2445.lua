local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or ".bazinga/BSA/09-24-26-00-unassigned/shots/game3_catch_ball_sheets_2445"

local NAMES = { [0] = "poke", "great", "safari", "ultra", "master", "net",
  "dive", "nest", "repeat", "timer", "luxury", "premier" }

return function(game)
  local fails = 0
  local function pass(label, ok, detail)
    if ok then
      print("PASS " .. label)
    else
      fails = fails + 1
      print("FAIL " .. label .. (detail and (" " .. detail) or ""))
    end
  end
  local function quit()
    print(fails == 0 and "PASS 2445 all" or ("FAIL 2445 " .. fails .. " check(s)"))
    love.event.quit(fails == 0 and 0 or 1)
  end

  for _ = 1, 600 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(180)

  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local Bag = require("src.core.game3.bag")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local Ui = require("src.core.game3.battle.ui")
  local Anim = require("src.core.game3.battle.anim")
  local BallOpen = require("src.core.game3.battle.ball_open")
  local CatchSeq = require("src.core.game3.battle.catch_seq")
  local Catching = require("src.core.game3.battle.catching")
  local SummaryMenu = require("src.ui.game3.summary_menu")
  local session = Runtime.getSession()
  session.party = {}
  Party.giveMon(session, 4, 50)
  session.party[1].pokeball = 12
  local ITEMS = { 12, 2, 3, 4, 1, 11, 7, 6, 8, 9, 10 }
  for _, item in ipairs(ITEMS) do Bag.add(session.bag, item, 3) end

  local draws = {}
  local realDraw = love.graphics.draw
  love.graphics.draw = function(img, q, ...)
    if img and img == Ui._ballSheet and type(q) == "userdata" and q.getViewport then
      local x, y = q:getViewport()
      draws[#draws + 1] = { col = math.floor(x / 16), frame = math.floor(y / 16) }
    end
    return realDraw(img, q, ...)
  end
  local function drawnCols()
    local seen, out = {}, {}
    for _, d in ipairs(draws) do
      if not seen[d.col] then seen[d.col] = true out[#out + 1] = d.col end
    end
    table.sort(out)
    return table.concat(out, ",")
  end

  SummaryMenu.openMenu(session.party, 1, { session = session })
  U.wait(30)
  draws = {}
  U.wait(2)
  U.still(game, DIR .. "/2445_summary_premier_icon.png")
  pass("2445 summary ball icon premier", drawnCols() == "11", "cols=" .. drawnCols())
  SummaryMenu.close()
  U.wait(10)

  Catching.tryCatch = function() return false, 1 end

  local ok = BattleBridge.startWild(Runtime._mod, game, { species = 16, level = 3 }, { fade = false })
  if not ok then pass("2445 battle start", false) quit() return end

  local shotSend = false
  local held = 0
  for _ = 1, 1500 do
    local s = Anim.stage() and Anim.stage().ball
    if Ui.dialogPending() and not (s and s.visible) then
      held = held + 1
      if held % 20 == 0 then U.tap(game, "a") end
    end
    if s and s.visible and s.side == "player" then
      U.wait(8)
      draws = {}
      U.wait(1)
      U.still(game, DIR .. "/2445_sendout_premier_midarc.png")
      pass("2445 sendout premier ballId", s.ballId == 11, "ballId=" .. tostring(s.ballId))
      pass("2445 sendout premier sheet", drawnCols() == "11", "cols=" .. drawnCols())
      shotSend = true
      break
    end
    U.wait(1)
  end
  if not shotSend then pass("2445 sendout seen", false) end

  local function toCommand(maxFrames)
    for _ = 1, maxFrames do
      if Battle._phase == "command" and not Ui.dialogPending() then return true end
      if Ui.dialogPending() then U.tap(game, "a") U.wait(3) else U.wait(1) end
    end
    return false
  end

  local Healthbox = require("src.core.game3.battle.healthbox")
  local BattleChrome = require("src.ui.game3.battle_chrome")
  local function enemyBoxRect()
    local hb = Anim.stage().healthbox and Anim.stage().healthbox.enemy
    local w, h = BattleChrome._enemyBox:getDimensions()
    return Healthbox.ENEMY_CENTER.x - 32 + ((hb and hb.ox) or 0), Healthbox.ENEMY_CENTER.y - 16, w, h
  end

  local function throw(item)
    local prev = CatchSeq._ball
    Ui._pendingCommand = { kind = "bag", user = "player", itemId = item }
    Ui._mode = "none"
    for _ = 1, 400 do
      if CatchSeq._ball and CatchSeq._ball ~= prev then return CatchSeq._ball end
      if Ui.dialogPending() then U.tap(game, "a") U.wait(2) else U.wait(1) end
    end
    return nil
  end

  for _, item in ipairs(ITEMS) do
    local want = BallOpen.ballIdForItem(item)
    local name = NAMES[want]
    local ready = toCommand(2000)
    if not ready and Battle._phase == nil then
      print("[driver] battle ended before " .. name .. "; starting another")
      U.wait(60)
      if BattleBridge.startWild(Runtime._mod, game, { species = 16, level = 3 }, { fade = false }) then
        ready = toCommand(3000)
      end
    end
    if not ready then
      pass("2445 command before " .. name, false,
        "phase=" .. tostring(Battle._phase) .. " dialog=" .. tostring(Ui.dialogPending()) .. " mode=" .. tostring(Ui._mode))
      break
    end
    local b = throw(item)
    if not b then pass("2445 throw " .. name, false) break end
    draws = {}
    local clear = false
    local startX
    for _ = 1, 120 do
      U.wait(1)
      local s = Anim.stage().ball
      if s.visible and s.frame == 0 then
        local bx = (s.x or 0) + (s.ox or 0) - 8
        local by = (s.y or 0) + (s.oy or 0) - 8
        startX = startX or bx
        local hbx, hby, hbw, hbh = enemyBoxRect()
        local apart = bx + 16 <= hbx or bx >= hbx + hbw or by + 16 <= hby or by >= hby + hbh
        if apart and bx >= 0 and by >= 0 and bx - startX >= 24 then
          U.still(game, DIR .. "/2445_" .. name .. "_midthrow.png")
          print(string.format("[driver] %s midthrow ball (%d,%d) healthbox (%d,%d %dx%d)",
            name, bx, by, hbx, hby, hbw, hbh))
          clear = true
          break
        end
      end
    end
    pass("2445 throw " .. name .. " clear of healthbox", clear)
    local midCols = drawnCols()
    local opened = false
    for _ = 1, 200 do
      local s = Anim.stage().ball
      if s.visible and s.frame == 2 then
        draws = {}
        U.wait(1)
        if s.visible and s.frame == 2 then
          U.still(game, DIR .. "/2445_" .. name .. "_open.png")
          opened = true
          break
        end
      end
      U.wait(1)
    end
    local openFrame2 = false
    for _, d in ipairs(draws) do
      if d.frame == 2 and d.col == want then openFrame2 = true end
    end
    pass("2445 throw " .. name .. " sheet", midCols == tostring(want), "cols=" .. midCols)
    pass("2445 open " .. name .. " frame2", opened and openFrame2, "cols=" .. drawnCols())
    U.wait(150)
  end

  love.graphics.draw = realDraw
  quit()
end
