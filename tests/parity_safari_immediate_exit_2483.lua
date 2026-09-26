package.path="./?.lua;./?/init.lua;"..package.path
love=require("tests.love_stub")
local T=require("tests.harness")
local Data=require("src.core.Data")
Data:load()
require("src.render.Font").load(Data)
local Game=require("src.core.Game")
local Input=require("src.core.Input")
local Renderer=require("src.render.Renderer")
local Stack=require("src.core.StateStack")
local OW=require("src.world.OverworldController")
local TB=require("src.render.TextBox")
local CB=require("src.ui.ChoiceBox")
local Version=require("src.core.GameVersion")
Game.data,Game.input,Game.renderer,Game.stack,Game.overworld=Data,Input,Renderer,Stack,OW
Input:init() Renderer:init() Stack:init()
local function tick(btn)
  Input.state=btn and {[btn]=true} or {}
  Input.pressed=btn and {[btn]=true} or {}
  Stack:update(1/60)
end
local function pump(predicate,btn)
  for i=1,4000 do
    if predicate() then return true end
    local top=Stack:top()
    local key=btn
    if not key and (getmetatable(top)==TB or getmetatable(top)==CB) then
      key=i%4==0 and "a" or nil
    end
    tick(key)
  end
  return false
end
local function inCenter()
  return OW.map.id=="SAFARI_ZONE_CENTER" and Stack:top()==OW and not OW.transitioning
end
local function leavingChoice()
  return OW.map.id=="SAFARI_ZONE_GATE" and getmetatable(Stack:top())==CB
end
for _,case in ipairs({{"red",3,3000},{"red",4,3000},{"yellow",3,3000},{"yellow",4,3000},{"yellow",4,200},{"yellow",4,0}}) do
  Version.set(case[1])
  Stack:clear() Input:reset()
  Game.save=require("src.core.SaveData").newGame()
  Game.save.options.textSpeed=1
  Game.save.money=case[3]
  if case[3]==0 then Game.save.safariNags=3 end
  Stack:push(OW,"SAFARI_ZONE_GATE",case[2],3,"up")
  local label=table.concat(case,"_")
  T.eq(OW.standingOnWarp,false,label.." admission starts off warp")
  T.check(pump(function() return getmetatable(Stack:top())==TB end,"up"),label.." admission triggered by walking")
  local arrived=pump(inCenter)
  T.check(arrived,label.." paid scripted admission reaches center")
  T.eq(OW.player.cellX,15,label.." arrival x")
  T.eq(OW.player.cellY,25,label.." arrival y")
  T.eq(OW.standingOnWarp,true,label.." source warp flag carried into center")
  T.eq(Game.save.safari and Game.save.safari.steps,500,label.." no extra step")
  T.check(pump(function() return OW.map.id=="SAFARI_ZONE_GATE" end,"down"),label.." first DOWN exits")
  T.check(pump(leavingChoice),label.." leaving early prompt")
  if getmetatable(Stack:top())==CB then
    tick("b")
    T.check(pump(inCenter),label.." NO returns to center")
    T.eq(OW.standingOnWarp,true,label.." NO retains immediate exit flag")
    T.check(pump(function() return OW.map.id=="SAFARI_ZONE_GATE" end,"down"),label.." DOWN exits again without step")
    T.check(pump(leavingChoice),label.." second leaving prompt")
    tick("a")
    T.check(pump(function() return Stack:top()==OW and not OW.runner:isRunning() and #OW.scriptMoves==0 and not OW.player.moving end),label.." YES exit completes")
    T.eq(Game.save.safari,nil,label.." YES clears safari")
    T.eq(OW.player.cellY,3,label.." YES walks below counter")
  end
end
T.finish("parity_safari_immediate_exit_2483")
