-- Driver: mart buy flow,  greeting, BUY list, purchase, unwind, then
-- confirm the player can still walk (softlock check).  Runs both the
-- generic mart (Pewter) and the script-run mart (Viridian post-parcel,
-- open_mart with a yielded runner,  the old softlock).
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "/tmp/shots"
  local Flags = require("src.script.Flags")
  local Menu = require("src.ui.Menu")
  local ListMenu = require("src.ui.ListMenu")
  local QuantityBox = require("src.ui.QuantityBox")
  local ChoiceBox = require("src.ui.ChoiceBox")
  game.save.money = 3000
  Flags.set(game.save, "EVENT_GOT_STARTER")
  Flags.set(game.save, "EVENT_GOT_OAKS_PARCEL")
  Flags.set(game.save, "EVENT_OAK_GOT_PARCEL")

  local failures = 0
  local function check(label, ok)
    if not ok then failures = failures + 1 end
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end
  local function topIs(cls)
    return getmetatable(game.stack:top()) == cls
  end
  local function mash(btn, cond)
    for _ = 1, 120 do
      if cond() then return true end
      U.tap(game, btn)
      U.wait(4)
    end
    return false
  end

  local function buyRun(tag)
    local ow = game.overworld
    U.tap(game, "a") -- talk to the clerk
    U.wait(20)
    check(tag .. " menu", mash("a", function() return topIs(Menu) end))
    U.tap(game, "a") -- BUY
    U.wait(8)
    check(tag .. " list", topIs(ListMenu))
    U.shot(game, ("%s/%s_0_list.png"):format(DIR, tag))
    U.tap(game, "a") -- first item
    U.wait(8)
    check(tag .. " qty", topIs(QuantityBox))
    U.tap(game, "down") -- engine/events/pokemart.asm:152-153
    U.wait(6)
    check(tag .. " qty max 99", game.stack:top().qty == 99)
    U.shot(game, ("%s/%s_0b_qty99.png"):format(DIR, tag))
    U.tap(game, "up")
    U.wait(6)
    U.tap(game, "a") -- x01
    for _ = 1, 300 do
      if topIs(ChoiceBox) then break end
      local t = game.stack:top()
      if t and t.isTextBox and t.waiting and (t.preWait or 0) == 0 then
        U.tap(game, "a")
      end
      U.wait(1)
    end
    check(tag .. " confirm", topIs(ChoiceBox))
    U.shot(game, ("%s/%s_1_confirm.png"):format(DIR, tag))
    local money0 = game.save.money
    U.tap(game, "a") -- YES
    for _ = 1, 40 do
      if game.save.money < money0 then break end
      U.wait(1)
    end
    U.wait(8)
    check(tag .. " bought", game.save.money < money0)
    U.shot(game, ("%s/%s_2_bought.png"):format(DIR, tag))
    check(tag .. " unwound", mash("b", function() return game.stack:top() == ow end))
    check(tag .. " runner idle", not (ow.runner and ow.runner:isRunning()))
    local x0, y0 = ow.player.cellX, ow.player.cellY
    U.hold(game, "right", 30)
    U.wait(20)
    check(tag .. " player moved", ow.player.cellX ~= x0 or ow.player.cellY ~= y0)
    U.shot(game, ("%s/%s_3_walk.png"):format(DIR, tag))
  end

  local ok, err = pcall(function()
    U.teleport(game, "PEWTER_MART", 2, 5, "left")
    buyRun("pewter")
    U.teleport(game, "VIRIDIAN_MART", 2, 5, "left")
    buyRun("viridian")
  end)
  if not ok then check("shop_test error: " .. tostring(err), false) end
  U.log(failures == 0 and "PASS shop_test" or ("FAIL shop_test (" .. failures .. " failures)"))
  love.event.quit(failures == 0 and 0 or 1)
  U.wait(600)
end
