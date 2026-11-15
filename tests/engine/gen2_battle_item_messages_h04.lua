package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local Mon=require('src.battle.gen2.Mon')
local Battle=require('src.battle.gen2.Battle')
local BattleState=require('src.ui.gen2.BattleState')
local Stack=require('src.core.StateStack')
local Save=require('src.core.gen2.Save')
local ItemEffects=require('src.core.gen2.ItemEffects')
local GameVersion=require('src.core.GameVersion')
local checks,failures=0,0
local function eq(got,want,name)
  checks=checks+1
  if got~=want then failures=failures+1;if failures<=20 then print('FAIL '..name..' got='..tostring(got)..' want='..tostring(want)) end end
end
local function settle(screen)
  for _=1,2500 do if screen.phase=='menu' and #screen.queue==0 and not screen.anim then return end;screen:update(1/60) end
  error('actual BattleState did not settle')
end
local oldVersion=GameVersion.get()
for _,version in ipairs({'gold','silver','crystal'}) do
  local root=os.getenv('POKEPORT_GEN2_'..version:upper()..'_DATA')
  if not root then print('SKIP H04 actual '..version..' item consumers; set POKEPORT_GEN2_'..version:upper()..'_DATA')
  else
    GameVersion.set(version)
    local data={}
    for _,name in ipairs({'pokemon','moves','items','type_chart'}) do data[name]=assert(loadfile(root..'/'..name..'.lua'))() end
    data.text=assert(loadfile(root..'/rom_text.lua'))()
    local function make()
      local function new(id)
        return assert(Mon.new(data,id,20,{dvs={attack=15,defense=15,speed=15,special=15}}))
      end
      local player,enemy=new('SNORLAX'),new('RATTATA')
      player.moves={{id='TACKLE',pp=35,maxPp=35}}
      enemy.moves={{id='SPLASH',pp=40,maxPp=40}}
      local save=Save.newGame({playerName='ITEMS'});save.party={player};save.inventory={}
      local game={data=data,save=save,options=save.options,input={wasPressed=function() return true end,isDown=function() return false end}}
      game.stack=setmetatable({}, {__index=Stack});game.stack:init()
      local battle=Battle.new({data=data,party={player},wild=enemy,save=save,random=function() return 0 end})
      local screen=BattleState.new(game,{battle=battle});game.stack:push(screen)
      settle(screen)
      return game,battle,screen
    end
    local function pick(game,screen,id)
      screen:openPack()
      local pack=game.stack:top()
      assert(pack.screenId=='Gen2PackMenu' and pack:inBattle(),'actual battle PACK missing')
      for _=1,4 do if pack:pocket().id==data.items[id].pocket then break end;pack:switchPocket(1) end
      local index
      for i,row in ipairs(pack.rows) do if row.id==id then index=i;break end end
      assert(index,'actual imported item not in PACK '..id)
      pack.index=index;pack:useSelected()
      eq(game.stack:top(),screen,version..' PACK returns to actual battle consumer')
    end
    for _,row in ipairs({{'GUARD_SPEC','mist'},{'DIRE_HIT','focusEnergy'},{'X_ACCURACY','xAccuracy'}}) do
      local id,field=unpack(row)
      local game,battle,screen=make();game.save.inventory[id]=2
      local original,captured=battle.useBattleItem
      battle.useBattleItem=function(self,item)
        local ok,why=original(self,item)
        captured={}
        for i,event in ipairs(self.events) do captured[i]=event end
        return ok,why
      end
      local turn=battle.turn;pick(game,screen,id)
      local messages=0
      for _,event in ipairs(captured) do if event.kind=='message' then messages=messages+1 end end
      eq(messages,1,version..' '..id..' source UseItemText only')
      eq(captured[1].text,battle:romLine('ItemUsedText',{PLAYER=battle:playerName(),STRBUF=game.data.items[id].name}),version..' '..id..' item-used line is ItemUsedText')
      eq(screen.message,captured[1].text,version..' '..id..' actual queued first dialog')
      eq(game.save.inventory[id],1,version..' '..id..' actual bag decremented once')
      eq(battle.turn,turn+1,version..' '..id..' actual turn spent once')
      eq(battle:volatile(battle.player)[field],true,version..' '..id..' volatile effect set')
      settle(screen)
      turn=battle.turn;pick(game,screen,id)
      eq(game.save.inventory[id],1,version..' '..id..' refusal does not consume')
      eq(battle.turn,turn,version..' '..id..' refusal does not spend turn')
      eq(battle:volatile(battle.player)[field],true,version..' '..id..' refusal retains effect')
      eq(#captured,0,version..' '..id..' refusal emits no success events')
      eq(screen.message,screen:rom(ItemEffects.TEXT_NO_EFFECT),version..' '..id..' actual refusal dialog')
    end
    for id,stat in pairs(Battle.X_ITEM_STATS) do
      local game,battle,screen=make();game.save.inventory[id]=2
      local events,original={},battle.emit
      battle.emit=function(self,event) events[#events+1]=event;return original(self,event) end
      local turn=battle.turn;pick(game,screen,id)
      eq(battle.stages.player[stat],1,version..' '..id..' stage effect retained')
      eq(game.save.inventory[id],1,version..' '..id..' bag consumption retained')
      eq(battle.turn,turn+1,version..' '..id..' turn retained')
      local stage
      for _,event in ipairs(events) do if event.kind=='stage' and event.side=='player' then stage=event end end
      eq(stage and stage.stat,stat,version..' '..id..' distinct stat event retained')
      eq(stage and type(stage.text),'string',version..' '..id..' stat text retained')
    end
    local _,battle=make()
    for _,move in ipairs({'MIST','FOCUS_ENERGY'}) do
      battle:clearVolatile(battle.player);battle:takeEvents()
      battle:useMove(battle.player,battle.enemy,move)
      local events=battle:takeEvents();local used=false
      for _,event in ipairs(events) do if event.kind=='move' and event.move==move then used=true end end
      eq(used,true,version..' '..move..' distinct move dispatch retained')
      local itemLine=false
      for _,event in ipairs(events) do if event.kind=='message' and event.text:find(' used the',1,true) then itemLine=true end end
      eq(itemLine,false,version..' '..move..' does not dispatch item text')
    end
  end
end
GameVersion.set(oldVersion)
print('H04 battle item messages '..(checks-failures)..'/'..checks)
assert(failures==0,tostring(failures)..' H04 failures')
