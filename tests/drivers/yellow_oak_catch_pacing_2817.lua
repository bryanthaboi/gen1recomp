-- pokeyellow engine/battle/core.asm:2122-2131
-- pokeyellow home/list_menu.asm:65-80
-- pokeyellow engine/battle/init_battle.asm:106-107
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local GameVersion = require("src.core.GameVersion")
  local BattleState = require("src.battle.BattleState")

  local SHOT_DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "/tmp/shots"
  local failed = false
  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    if not ok then failed = true end
    return ok
  end
  local function done()
    love.event.quit(failed and 1 or 0)
    while true do coroutine.yield() end
  end

  if not check("running Yellow", GameVersion.isYellow()) then done() end

  U.teleport(game, "PALLET_TOWN", 10, 8, "up")
  U.wait(10)

  local battle = BattleState.newWild(game, "PIKACHU", 5)
  battle:makeOldManDemo("oak")

  local menuFrames, cursorItemAt = 0, nil
  local clearedDuringWait = nil
  local realUpdate = battle.update
  battle.update = function(self, dt)
    if self.phase == "menu" and self.demo then
      menuFrames = menuFrames + 1
    end
    local r = realUpdate(self, dt)
    if self.phase == "menu" and self.demo and not cursorItemAt
       and (self.demoTimer or 0) > (self.demoDelays and self:demoDelays() or 80) then
      cursorItemAt = menuFrames
    end
    return r
  end

  game.stack:push(battle)
  U.wait(10)

  local shotWait, shotFight, shotItem = false, false, false
  for _ = 1, 3000 do
    if game.stack:top() ~= battle then break end
    if battle.phase == "messages" and battle.introBalls == nil
       and battle.shown == nil and (battle.waitFrames or 0) > 10 then
      clearedDuringWait = true
      if not shotWait then
        shotWait = U.still(game, SHOT_DIR .. "/2817_01_box_cleared_after_appeared.png")
      end
    end
    if battle.phase == "menu" then
      if menuFrames == 10 and not shotFight then
        shotFight = U.still(game, SHOT_DIR .. "/2817_02_cursor_on_fight.png")
      elseif menuFrames == 30 and not shotItem then
        shotItem = U.still(game, SHOT_DIR .. "/2817_03_cursor_on_item.png")
      end
      U.wait(1)
    elseif battle.phase == "messages" and battle.current and battle.msgPrompt then
      U.tap(game, "a")
    else
      U.wait(1)
    end
  end

  check("the box is blank during the 40-frame StartBattle wait", clearedDuringWait == true)
  check("cursor leaves FIGHT after 20 frames (got " .. tostring(cursorItemAt) .. ")",
        cursorItemAt == 21)
  check("the bag opens after 20 + 20 frames (got " .. tostring(menuFrames) .. ")",
        menuFrames == 41)

  local bag = game.stack:top()
  local isBag = bag ~= battle and bag.items ~= nil
  check("the scripted bag is on top", isBag)
  if not isBag then done() end
  check("the bag lists POKé BALL x1", bag.items[1] and bag.items[1].count == 1)
  check("the bag lists CANCEL under it", bag.items[2] and bag.items[2].cancel == true)

  local hollowAt = nil
  local shotBag = false
  for _ = 1, 200 do
    if game.stack:top() ~= bag then break end
    if bag.hollowIndex and not hollowAt then hollowAt = bag.scriptTimer end
    if (bag.scriptTimer or 0) == 10 and not shotBag then
      shotBag = U.still(game, SHOT_DIR .. "/2817_04_bag_pokeball_cancel.png")
    end
    U.wait(1)
  end
  check("the auto-A lands 20 frames into the bag (got " .. tostring(hollowAt) .. ")",
        hollowAt == 21)
  check("the bag closes into the throw", game.stack:top() ~= bag)

  local said = false
  for _ = 1, 600 do
    if battle.current and tostring(battle.current.text or ""):find("PROF.OAK", 1, true) then
      said = true
      break
    end
    U.wait(1)
  end
  check("PROF.OAK used POKé BALL! follows", said)
  done()
end
