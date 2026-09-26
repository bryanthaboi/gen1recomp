package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Data = T.fixtures.fresh()
local OW = require("src.world.OverworldController")
local TB = require("src.render.TextBox")
local Sound = require("src.core.Sound")
local Version = require("src.core.GameVersion")
local function set(fn, name, value)
  for i = 1, 100 do
    local key = debug.getupvalue(fn, i)
    if key == name then debug.setupvalue(fn, i, value) return end
    if not key then error(name) end
  end
end
local source = {playing = true, isPlaying = function(s) return s.playing end}
local played
set(OW.talkTo,"mapScripts",{talkScript=function() return nil end})
Sound.play = function(_, name) played = name return source end
Sound.waitFrames = function() return 600 end
Data.field.hiddenItems.FIX_TOWN = {{x=3,y=3,item="FIX_BALL"}}
for _, version in ipairs({"red", "yellow"}) do
  Version.set(version)
  for _, hidden in ipairs({false, true}) do
    for _, full in ipairs({false, true}) do
      local save = require("src.core.SaveData").newGame()
      save.inventory = {}
      if full then for i=1,20 do save.inventory["FILL"..i]=1 end end
      local pressed = false
      local game = {data=Data, save=save, input={wasPressed=function() return pressed end, isDown=function() return false end}}
      game.stack = {push=function(s,b) s.box=b end, pop=function(s) s.box=nil end}
      set(OW.tryHiddenObject,"Game",game)
      set(OW.tryHiddenObject,"TextBox",TB)
      local npc={id="pickup",def={item="FIX_BALL",text=99}}
      local ow=setmetatable({map={id="FIX_TOWN"},npcs={npc},entities={npc}}, {__index=OW})
      if hidden then ow:tryHiddenObject(3,3) else ow:talkTo(npc) end
      local box=game.stack.box
      T.check(box ~= nil,"pickup opens textbox")
      box.done=true
      source.playing=true
      for _=1,10 do box:update() end
      local label=version.."_"..(hidden and "hidden" or "ball")..(full and "_full" or "_success")
      T.eq(game.stack.box,box,label.." held")
      if full then
        T.eq(save.inventory.FIX_BALL,nil,label.." no award")
        T.check(box:arrowVisible(),label.." arrow")
        T.check(hidden and not (save.hiddenTaken or {}).FIX_TOWN_3_3 or not hidden and #ow.npcs==1,label.." retained")
      else
        T.eq(save.inventory.FIX_BALL,1,label.." one award")
        T.eq(played,hidden and "Get_Item2" or "Get_Item1",label.." sound")
        T.check(not box:arrowVisible(),label.." no arrow")
        source.playing=false
        box:update()
        T.eq(game.stack.box,nil,label.." autoclose")
        T.check(hidden and save.hiddenTaken.FIX_TOWN_3_3 or not hidden and #ow.npcs==0,label.." consumed")
      end
    end
  end
end
local opts=TB.soundOpts({data=Data},"Get_Item1")
T.eq(opts.auto.wait,true,"ordinary soundOpts preserves button wait")
T.finish("item_pickup_autoclose_bug2479")
