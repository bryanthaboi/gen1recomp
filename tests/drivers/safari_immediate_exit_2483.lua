return function(game)
  local U=dofile("tests/drivers/util.lua")
  local TB=require("src.render.TextBox")
  local CB=require("src.ui.ChoiceBox")
  local version=require("src.core.GameVersion").get()
  local dir=assert(os.getenv("POKEPORT_SHOT_DIR"))
  local failed=false
  local function check(label,ok)
    U.log(ok and "PASS" or "FAIL",label)
    failed=failed or not ok
    return ok
  end
  local function pump(predicate,button)
    for i=1,2400 do
      if predicate() then return true end
      local top=game.stack:top()
      if button then U.hold(game,button,1)
      elseif getmetatable(top)==TB or getmetatable(top)==CB then U.tap(game,"a") U.wait(3)
      else U.wait(1) end
    end
    return false
  end
  local function inCenter()
    local ow=game.overworld
    return ow.map.id=="SAFARI_ZONE_CENTER" and game.stack:top()==ow and not ow.transitioning
  end
  local function leavingChoice()
    return game.overworld.map.id=="SAFARI_ZONE_GATE" and getmetatable(game.stack:top())==CB
  end
  for _,x in ipairs({3,4}) do
    game.save.safari=nil
    game.save.safariGameOver=nil
    game.save.money=3000
    game.save.options.textSpeed=1
    U.teleport(game,"SAFARI_ZONE_GATE",x,3,"up")
    check("admission starts off warp "..x,game.overworld.standingOnWarp==false)
    check("admission walking trigger "..x,pump(function() return getmetatable(game.stack:top())==TB end,"up"))
    if check("paid admission reaches center "..x,pump(inCenter)) then
      local ow=game.overworld
      check("arrival retains warp flag "..x,ow.standingOnWarp and ow.player.cellX==15 and ow.player.cellY==25)
      check("arrival without extra step "..x,game.save.safari and game.save.safari.steps==500)
      check("first DOWN exits "..x,pump(function() return game.overworld.map.id=="SAFARI_ZONE_GATE" end,"down"))
      if check("leaving early prompt "..x,pump(leavingChoice)) then
        U.shot(game,dir.."/2483_"..version.."_"..x.."_immediate_leaving_early.png")
        U.tap(game,"b")
        check("NO returns to center "..x,pump(inCenter))
        check("NO retains immediate exit "..x,game.overworld.standingOnWarp)
        check("second DOWN exits "..x,pump(function() return game.overworld.map.id=="SAFARI_ZONE_GATE" end,"down"))
        if check("second leaving prompt "..x,pump(leavingChoice)) then
          U.tap(game,"a")
          check("YES exit completes "..x,pump(function()
            local cur=game.overworld
            return game.stack:top()==cur and not cur.runner:isRunning() and #cur.scriptMoves==0 and not cur.player.moving
          end))
          check("YES clears safari "..x,game.save.safari==nil and game.overworld.player.cellY==3)
          U.shot(game,dir.."/2483_"..version.."_"..x.."_returned_balls_exit.png")
        end
      end
    end
  end
  love.event.quit(failed and 1 or 0)
end
