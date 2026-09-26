package.path="./?.lua;./?/init.lua;"..package.path
love=require("tests.love_stub")
local T=require("tests.harness")
local Oak=require("src.ui.OakSpeech")
local TB=require("src.render.TextBox")
local Sound=require("src.core.Sound")
local Version=require("src.core.GameVersion")
local originalCry=Sound.playCry
local source={playing=true,isPlaying=function(s) return s.playing end}
Sound.waitFrames=function() return 600 end
Sound.playPress=function() end
Sound.play=function() end
for _,case in ipairs({{"red","NIDORINO","NIDORINA"},{"blue","NIDORINO","NIDORINA"},{"yellow","PIKACHU","PIKACHU"},{"red","RAICHU","RAICHU",true},{"yellow","RAICHU","RAICHU",true},{"red","NIDORINO","NIDORINO",true}}) do
  Version.set(case[1])
  local calls,advanced=0,0
  local pressed=false
  local game={data={text={_OakSpeechText2A="TRANSLATED FIRST\fTRANSLATED LAST"}},save={player={},options={textSpeed=1}},input={wasPressed=function() return pressed end,isDown=function() return false end}}
  game.stack={push=function(s,b) s.box=b end,pop=function(s) s.box=nil end}
  local pic={}
  local speech=setmetatable({game=game,demoSpecies=case[2],demoPic=pic,cfg={demoSpecies=case[4] and case[2] or nil},advance=function() advanced=advanced+1 end},Oak)
  local label=case[1].."_"..case[2]..(case[4] and "_custom" or "")
  Sound.playCry=function(_,species,clip)
    calls=calls+1
    T.eq(species,case[3],label.." cry species")
    T.eq(clip,false,label.." chip request")
    T.check(game.stack.box and game.stack.box.done,label.." cry at final text")
    source.playing=true
    return source
  end
  speech:runStep({kind="demo"})
  T.eq(calls,0,label.." no reveal cry")
  for _=1,32 do speech:update(0) end
  local box=game.stack.box
  T.eq(getmetatable(box),TB,label.." real textbox")
  T.eq(box.pages[1][1],"TRANSLATED FIRST",label.." translated text")
  for _=1,200 do box:update() end
  T.eq(calls,0,label.." no intermediate page cry")
  T.check(box.waiting,label.." first page waits")
  pressed=true box:update() pressed=false
  for _=1,200 do box:update() end
  T.eq(calls,1,label.." final page cry once")
  T.check(not box:arrowVisible(),label.." no arrow during cry")
  pressed=true
  for _=1,10 do box:update() end
  T.eq(advanced,0,label.." cannot dismiss playing cry")
  pressed=false source.playing=false box:update()
  T.eq(advanced,0,label.." completed cry awaits acknowledgement")
  T.check(box:arrowVisible(),label.." arrow after cry")
  pressed=true box:update()
  T.eq(advanced,1,label.." acknowledgement advances")
  T.eq(calls,1,label.." single cry")
  T.eq(speech.pic,pic,label.." sprite retained")
  T.eq(speech.picFlip,true,label.." sprite flipped")
end
Sound.playCry=originalCry
love.audio={}
local pcmCalls={}
local pcm={}
Sound.playPikaCry=function(_,clip) pcmCalls[#pcmCalls+1]=clip return pcm end
local chip={stop=function() end,setPitch=function() end,setVolume=function() end,play=function(s) s.played=true end}
package.loaded["src.core.ChipAudio"]={isSuspended=function() return false end,newCry=function() return chip end}
local data={audio={cries={PIKACHU={chip={}}},pikaCries=42}}
T.eq(Sound.playCry(data,"PIKACHU",false),chip,"false selects synthesized Pikachu with PCM available")
T.eq(#pcmCalls,0,"chip request bypasses PCM")
T.check(chip.played,"chip source played")
T.eq(Sound.playCry(data,"PIKACHU"),pcm,"default retains PCM")
T.eq(pcmCalls[1],1,"default retains clip 1")
T.eq(Sound.playCry(data,"PIKACHU",37),pcm,"numeric retains PCM")
T.eq(pcmCalls[2],37,"numeric retains clip 37")
T.finish("oak_intro_cry_bug2481")
