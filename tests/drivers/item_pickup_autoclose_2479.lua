return function(game)
  local U=dofile("tests/drivers/util.lua")
  local TB=require("src.render.TextBox")
  local dir=assert(os.getenv("POKEPORT_SHOT_DIR"))
  local version=require("src.core.GameVersion").get()
  local failed=false
  local function check(label,ok)
    U.log(ok and "PASS" or "FAIL",label)
    failed=failed or not ok
    return ok
  end
  local function setup(hidden,full)
    local h=hidden and assert(game.data.field.hiddenItems.VIRIDIAN_FOREST[1])
    game.save.inventory={}
    game.save.bagOrder={}
    if full then
      local n=0
      for id in pairs(game.data.items) do
        if id~="IRON" and (not h or id~=h.item) and not id:find("BADGE") then
          game.save.inventory[id]=1 n=n+1
          if n==20 then break end
        end
      end
    end
    game.save.itemsTaken={}
    game.save.hiddenTaken={}
    if hidden then
      U.teleport(game,"VIRIDIAN_FOREST",h.x,h.y+1,"up")
    else
      U.teleport(game,"POKEMON_MANSION_3F",24,5,"right")
    end
    U.tap(game,"a")
    return game.overworld,game.stack:top()
  end
  for _,hidden in ipairs({false,true}) do
    local label=hidden and "hidden" or "ball"
    local ow,box=setup(hidden,false)
    if check(label.." opens",getmetatable(box)==TB) then
      local sawSound,noArrow=false,true
      for _=1,1200 do
        if game.stack:top()==ow then break end
        if box.autoSrc and box.autoSrc:isPlaying() then sawSound=true end
        if box.done and box:arrowVisible() then noArrow=false end
        U.wait(1)
      end
      check(label.." fanfare before autoclose",sawSound and noArrow and game.stack:top()==ow)
    end
  end
  local ow,box=setup(false,true)
  U.wait(300)
  check("full bag requires acknowledgement",getmetatable(box)==TB and game.stack:top()==box and box:arrowVisible())
  U.shot(game,dir.."/2479_"..version.."_full_bag_wait.png")
  ow,box=setup(true,true)
  U.wait(300)
  check("hidden full bag requires acknowledgement",getmetatable(box)==TB and game.stack:top()==box and box:arrowVisible() and not next(game.save.hiddenTaken))
  ow,box=setup(false,false)
  for _=1,1200 do
    if box.autoSrc and box.autoSrc:isPlaying() then break end
    U.wait(1)
  end
  if check("shot fanfare ready",box.autoSrc and box.autoSrc:isPlaying()) then
    U.shot(game,dir.."/2479_"..version.."_item_fanfare_no_arrow.png")
  end
  for _=1,1200 do if game.stack:top()==ow then break end U.wait(1) end
  if check("shot autoclosed ready",game.stack:top()==ow) then
    U.shot(game,dir.."/2479_"..version.."_item_autoclosed.png")
  end
  love.event.quit(failed and 1 or 0)
end
