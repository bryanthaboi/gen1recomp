local U=require('tests.drivers.util')
local Mon=require('src.battle.gen2.Mon')
local ItemEffects=require('src.core.gen2.ItemEffects')

return function(game)
  local deadline=love.timer.getTime()+25
  local oldWrite,oldOptions,oldPersist=rawget(game,'writeSave'),rawget(game,'writeOptions'),rawget(game,'persistOptions')
  local oldSpeed=game.speedOverride
  local oldVolume=love.audio.getVolume()
  local battle,oldUse
  local ok,err=xpcall(function()
    local identity=os.getenv('POKEPORT_IDENTITY') or ''
    assert(identity~='' and identity~='pokemon-love2d','isolated READY identity required')
    local version=game.save.version
    assert(version=='gold' or version=='silver' or version=='crystal','Gen2 edition required')
    local root=assert(os.getenv('POKEPORT_GEN2_'..version:upper()..'_DATA'),'explicit actual edition dataset required')
    local sourceItems=assert(loadfile(root..'/items.lua'))()
    for _,id in ipairs({'GUARD_SPEC','DIRE_HIT','X_ATTACK'}) do
      assert(sourceItems[id] and game.data.items[id] and sourceItems[id].name==game.data.items[id].name,'actual edition item metadata mismatch '..id)
    end
    local out=assert(os.getenv('POKEPORT_SHOT_DIR'))
    game.writeSave=function() error('H04 unexpected save write') end
    game.writeOptions=game.writeSave;game.persistOptions=game.writeSave
    love.audio.setVolume(0)
    game.speedOverride=200
    assert(game:logicSpeed()==200,'actual clock did not accelerate')
    local function wait(n)
      for _=1,n do assert(love.timer.getTime()<deadline,'H04 deadline');U.wait(1) end
    end
    local function shot(name)
      assert(U.still(game,out..'/h04-'..version..'-'..name..'.png'),'capture failed')
      assert(love.timer.getTime()<deadline,'H04 capture deadline')
    end
    for _=1,1200 do if game.world and game.world.map and not game.stack:top() then break end;wait(1) end
    local world=assert(game.world);assert(world.map and not game.stack:top(),'READY Gen2 world did not settle')
    local function new(id)
      return assert(Mon.new(game.data,id,20,{dvs={attack=15,defense=15,speed=15,special=15}}))
    end
    local player,enemy=new('SNORLAX'),new('RATTATA')
    player.moves={{id='TACKLE',pp=35,maxPp=35}};enemy.moves={{id='SPLASH',pp=40,maxPp=40}}
    game.save.party={player}
    game.save.inventory.GUARD_SPEC=2;game.save.inventory.DIRE_HIT=2;game.save.inventory.X_ATTACK=2
    assert(world:startBattle({wild=enemy}),'actual wild battle failed')
    local screen
    local function menu()
      for _=1,5000 do
        screen=game.stack:top()
        if screen and screen.battle and screen.phase=='menu' and #screen.queue==0 and not screen.anim then return end
        if screen and screen.battle then U.tap(game,'a') end;wait(1)
      end
      error('actual battle menu did not settle')
    end
    menu()
    battle=screen.battle;oldUse=battle.useBattleItem
    local captured
    battle.useBattleItem=function(self,id)
      local used,why=oldUse(self,id)
      captured={}
      for i,event in ipairs(self.events) do captured[i]=event end
      return used,why
    end
    local function pick(id)
      screen:openPack()
      local pack=game.stack:top()
      assert(pack and pack.screenId=='Gen2PackMenu' and pack:inBattle(),'actual battle PACK missing')
      for _=1,4 do if pack:pocket().id==game.data.items[id].pocket then break end;pack:switchPocket(1) end
      local index
      for i,row in ipairs(pack.rows) do if row.id==id then index=i;break end end
      assert(index,'actual PACK item missing '..id)
      pack.index=index;pack:useSelected()
      assert(game.stack:top()==screen,'actual PACK callback did not return to battle')
    end
    local function typed(text)
      assert(screen.message==text,'actual queued dialog mismatch')
      for _=1,2500 do
        if not screen:syncTyper() and screen:messageArrowVisible() then return end
        wait(1)
      end
      error('actual dialog did not finish typing')
    end
    for _,row in ipairs({{'GUARD_SPEC','mist'},{'DIRE_HIT','focusEnergy'}}) do
      local id,field=unpack(row)
      local turn=battle.turn
      pick(id)
      assert(captured[1] and captured[1].kind=='message','source Used-item line missing')
      typed(captured[1].text);shot(id:lower()..'-used')
      assert(#captured==1,'item emitted extra source-inaccurate success message')
      assert(game.save.inventory[id]==1 and battle.turn==turn+1,'successful item did not spend exactly one item/turn')
      assert(battle:volatile(battle.player)[field],'successful item substatus missing')
      menu();turn=battle.turn
      pick(id)
      typed(screen:rom(ItemEffects.TEXT_NO_EFFECT));shot(id:lower()..'-refused')
      assert(#captured==0 and game.save.inventory[id]==1 and battle.turn==turn,'refusal spent item/turn or emitted success')
      assert(battle:volatile(battle.player)[field],'refusal lost substatus')
      menu()
    end
    local turn=battle.turn
    pick('X_ATTACK')
    assert(captured[1] and captured[1].kind=='message','X ATTACK Used line missing')
    typed(captured[1].text);shot('x-attack-used')
    local stage
    for _,event in ipairs(captured) do if event.kind=='stage' and event.stat=='attack' then stage=event end end
    assert(stage and type(stage.text)=='string','X ATTACK stat text missing')
    assert(game.save.inventory.X_ATTACK==1 and battle.turn==turn+1 and battle.stages.player.attack==1,'X ATTACK state/consumption changed')
    for _=1,5000 do
      if screen.message==stage.text then break end
      U.tap(game,'a');wait(1)
    end
    typed(stage.text);shot('x-attack-stat-rise');menu()
    print('PASS H04 actual typed item dialogs, Pack callback, refusal, substatus, bag and turns '..version)
  end,debug.traceback)
  if battle and oldUse then battle.useBattleItem=oldUse end
  game.writeSave,game.writeOptions,game.persistOptions=oldWrite,oldOptions,oldPersist
  game.speedOverride=oldSpeed
  love.audio.setVolume(oldVolume)
  if not ok then print('FAIL H04 '..tostring(err)) end
  love.event.quit(ok and 0 or 1)
end
