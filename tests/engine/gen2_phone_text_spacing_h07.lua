package.path="./?.lua;./?/init.lua;"..package.path
love=require("tests.love_stub")
require("src.core.Logger").warn=function()end
local T=require("tests.harness").suite("Gen2 phone text spacing H07")
local Gear=require("src.ui.gen2.Pokegear")
local Chrome=require("src.ui.gen2.Chrome")
local Arena=require("src.ui.gen2.ArenaState")
local Save=require("src.core.gen2.Save")
local rows={}
local original=Chrome.print
Chrome.print=function(text,x,y,...)rows[#rows+1]={text=text,x=x,y=y};return original(text,x,y,...)end
local function speech()
 local out={};for _,r in ipairs(rows)do if r.x==1 and r.y>=13 then out[#out+1]=r end end
 return out
end
for _,edition in ipairs({"gold","silver","crystal"})do
 require("src.core.GameVersion").set(edition)
 local root=os.getenv("POKEPORT_GEN2_"..edition:upper().."_DATA")
 if not root then print("SKIP H07 actual "..edition.." data")else
  local text=assert(loadfile(root.."/rom_text.lua"))()
  local save=Save.newGame({trainerId=1234});save.engineFlags={};for i=0,500 do save.engineFlags[i]=true end
  local game={save=save,data={},input={wasPressed=function()return false end}}
  local gear=Gear.new(game,{save=save,text=text,clock={hour=12},mapDef={phoneService=false}})
  for i,c in ipairs(gear.cards)do if c.id=="phone" then gear.cardIndex=i end end
  gear.mode="card"
  for _,kind in ipairs({"idle","nosignal"})do
   if kind=="nosignal" then gear:callContact(1);T.eq(gear.call.kind,"nosignal",edition.." real no-service producer")end
   for _,style in ipairs({"drawPhone"})do
    rows={};gear[style](gear)
    local out=speech()
    T.eq(#out,2,edition.." "..kind.." "..style.." two source lines")
    T.eq(out[1] and out[1].y,14,edition.." first source line")
    T.eq(out[2] and out[2].y,16,edition.." second source line")
    local expected=Chrome.wrap(gear.call and gear.call.text or gear:phoneText("AskWhoCall"),18)
    T.eq(out[1] and out[1].text,expected[1],edition.." original first text preserved")
    T.eq(out[2] and out[2].text,expected[2],edition.." original second text preserved")
   end
  end
  gear:hangUp();T.eq(gear.call,nil,edition.." normal hangup restores prompt")
  rows={};gear:drawPhone()
  local names={};for _,r in ipairs(rows)do if r.x==2 then names[r.y]=true end end
  for _,y in ipairs({4,6,8,10})do T.check(names[y],edition.." contact list row"..y.." unchanged")end
 end
end
local arena=Arena.new({},{})
arena:fail("one\ntwo\nthree\nfour")
rows={};arena:drawPanel()
local out=speech()
T.eq(#out,4,"engine-owned Arena retains four interior lines")
for i=1,4 do T.eq(out[i].y,12+i,"Arena four-row footprint remains inside border")end
Chrome.print=original
T.finish()
