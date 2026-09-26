return function(game)
  local U=dofile("tests/drivers/util.lua")
  local Oak=require("src.ui.OakSpeech")
  local TB=require("src.render.TextBox")
  local Sound=require("src.core.Sound")
  local version=require("src.core.GameVersion").get()
  local dir=assert(os.getenv("POKEPORT_SHOT_DIR"))
  local failed=false
  local function check(label,ok)
    U.log(ok and "PASS" or "FAIL",label)
    failed=failed or not ok
    return ok
  end
  local cry=Sound.playCry
  local calls,source,atDone,atStep,chosen,clip
  local speech
  Sound.playCry=function(data,species,pikaClip)
    calls=calls+1
    local top=game.stack:top()
    atDone=getmetatable(top)==TB and top.done
    atStep=speech.step
    chosen,clip=species,pikaClip
    source=cry(data,species,pikaClip)
    return source
  end
  local function start()
    while game.stack:top() do game.stack:pop() end
    game.save.options.textSpeed=1
    calls,source,atDone,chosen=0,nil,false,nil
    speech=Oak.new(game,function() end)
    game.stack:push(speech)
    local demo
    for i,step in ipairs(speech.steps) do if step.kind=="demo" then demo=i end end
    for _=1,1800 do
      if speech.step==demo then break end
      U.tap(game,"a") U.wait(3)
    end
    return demo
  end
  local function reachCry()
    for _=1,1800 do
      if calls>0 then return true end
      local top=game.stack:top()
      if getmetatable(top)==TB and top.waiting then U.tap(game,"a") else U.wait(1) end
    end
    return false
  end
  local demo=start()
  check("no cry during demo reveal",calls==0)
  if check("demo cry reached",reachCry()) then
    check("cry starts after final Text2A",atDone and atStep==demo)
    check("cart intro chip species",clip==false and chosen==(version=="yellow" and "PIKACHU" or "NIDORINA"))
    check("actual cry source playing",source and source:isPlaying())
    local held=true
    for _=1,1200 do
      if not source or not source:isPlaying() then break end
      if speech.step~=demo then held=false end
      U.tap(game,"a")
    end
    check("cry holds Text2A through playback",held)
    U.wait(2)
    check("cry complete waits for acknowledgement",speech.step==demo and calls==1)
    U.tap(game,"a") U.wait(2)
    check("acknowledgement advances with flipped sprite",speech.step==demo+1 and speech.pic==speech.demoPic and speech.picFlip)
  end
  start()
  if check("screenshot cry reached",reachCry()) and atDone then
    U.shot(game,dir.."/2481_"..version.."_text_complete_cry.png")
  end
  Sound.playCry=cry
  love.event.quit(failed and 1 or 0)
end
