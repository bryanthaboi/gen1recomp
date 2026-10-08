local U=require('tests.drivers.util')
local failures=0
local function check(ok,label)
  print((ok and 'PASS ' or 'FAIL ')..label)
  if not ok then failures=failures+1 end
  return ok
end
local function finish()
  print((failures==0 and 'PASS ' or 'FAIL ')..'2767 native Surf timing failures='..failures)
  love.event.quit(failures==0 and 0 or 1)
end
return function(game)
  for _=1,600 do
    if game.phase=='boot' and game.boot then break end
    U.wait(1)
  end
  if not check(game.phase=='boot' and game.boot~=nil,'2767 boot ready') then return finish() end
  game:_handleBootAction({action='new_game',name='SURFER'})
  U.wait(180)
  local Runtime=require('src.core.game3.runtime')
  local Map=require('src.core.game3.map')
  local Player=require('src.core.game3.player')
  local Collision=require('src.core.game3.collision')
  local Space=require('src.core.game3.scripting.space')
  local Flags=require('src.core.game3.scripting.flags')
  local Field=require('src.core.game3.field')
  require('src.core.game3.encounters').onStep=function() return nil end
  require('src.core.game3.trainer_sight').check=function() return false end
  local session=Runtime.getSession()
  if not check(session~=nil,'2767 field session ready') then return finish() end
  local loader=game.mods
  print('MODS 2767 safeMode='..tostring(loader and loader.safeMode))
  for _,id in ipairs(loader and loader.order or {}) do
    print('MODS 2767 ordered='..tostring(type(id)=='table' and id.manifest and id.manifest.id or id))
  end
  local mapId='EM_ROUTE131'
  Map.load(Runtime._mod,game,mapId,{x=17,y=2,facing='right'})
  U.wait(90)
  local shoeId=Flags.forVersion('emerald').IDS.FLAG_SYS_B_DASH
  if not check(Collision.isWater(17,2) and Collision.isWater(18,2),'2767 real Route131 water fixture') then return finish() end
  local function measure(label,b,shoes)
    if Space.vm and Space.vm:isRunning() then Space.vm:halt(false) end
    Field.locked=false
    Player.reset(17,2,'right')
    Player.surfing,Player.currentElevation,Player.elevation=true,1,1
    Flags.setFlag(Space.store,nil,shoeId,shoes)
    local input={isDown=function(_,key) return key=='right' or key=='b' and b end}
    Player.update(game,input)
    if not check(Player.moving,label..' step starts') then return end
    local selected=Player.stepFrames
    Player._onStepDone=function() end
    local count=0
    while Player.moving and count<24 do
      U.wait(1)
      count=count+1
    end
    print('MEASURE 2767 '..label..' selected='..selected..' duration='..count..' surf='..tostring(Player.surfing))
    check(count==8 and selected==8 and Player.cellX==18 and Player.surfing,label..' completes in 8 frames')
  end
  measure('no_B_no_shoes',false,false)
  measure('B_no_shoes',true,false)
  measure('no_B_shoes',false,true)
  measure('B_shoes',true,true)
  local shots=os.getenv('POKEPORT_SHOT_DIR')
  if shots then check(U.still(game,shots..'/2767_01_surfing.png'),'2767 Surf frame captured') end
  Map.load(Runtime._mod,game,mapId,{x=59,y=2,facing='right'})
  U.wait(90)
  Player.surfing,Player.currentElevation,Player.elevation=true,1,1
  Player._onStepDone=function() end
  local status=Player.tryMove('right',game,false)
  local selected=Player.stepFrames
  local count=0
  while Player.moving and count<24 do U.wait(1);count=count+1 end
  print('MEASURE 2767 water_seam result='..tostring(status)..' duration='..count..' selected='..selected..' map='..tostring(Map.current))
  check(status=='connection' and Map.current=='EM_ROUTE130' and count==8 and selected==8 and Player.surfing,'2767 water seam completes in 8 frames')
  if shots then check(U.still(game,shots..'/2767_02_water_seam.png'),'2767 seam frame captured') end
  finish()
end
