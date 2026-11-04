package.path = "./?.lua;./?/init.lua;" .. package.path

local clock, quit = 1, false
local sent, queue, draws = {}, {}, 0
local ww,wh,dpi,lastDraw=100,100,1
local pixelWidth
local peer = {
  send = function(_, data) sent[#sent + 1] = data end,
  disconnect_now = function() end,
}
local host = {
  connect = function() return peer end,
  service = function()
    if #queue == 0 then return nil end
    return table.remove(queue, 1)
  end,
}
local rendered = {
  setFilter = function() end, replacePixels = function() end,
  release = function() end,
}
love = {
  timer = { getTime = function() return clock end },
  data = { decompress = function(_, _, value) return value end },
  image = { newImageData = function(w, h, format, raw)
    assert(format == "rgba8" and #raw==w*h*4)
    return {}
  end },
  graphics = {
    newImage = function() return rendered end,
    getDimensions = function() return ww, wh end,
    getDPIScale = function() return dpi end,
    getPixelDimensions = function() return pixelWidth or ww*dpi, wh*dpi end,
    clear = function() end, setColor = function() end,
    draw = function(_,x,y,_,sx,sy) draws = draws + 1;lastDraw={x,y,sx,sy} end,
  },
  event = { quit = function() quit = true end },
}
package.preload.enet = function()
  return { host_create = function() return host end }
end

require("src.render.DesktopCompanion").install({ port = 50000, token = "token" })
queue[#queue + 1] = { type = "connect" }
love.update()
assert(sent[#sent] == "Htoken", "companion authenticates after connecting")
queue[#queue + 1] = {
  type = "receive", data = "Ftoken\n1,1,0,auto\nrgba",
}
love.update()
love.draw()
assert(draws == 1, "companion draws a received frame")
love.mousepressed(50, 50, 1)
love.mousereleased(50, 50, 1)
assert(sent[#sent - 1] == "Itoken\ndown,0,0"
  and sent[#sent] == "Itoken\nup,0,0", "mouse input maps back to source pixels")
local function near(a,b) assert(math.abs(a-b)<1e-6,tostring(a).." != "..tostring(b)) end
for _,case in ipairs({
  {640,480,1,"fit",53,0,20/9}, {640,480,1,"integer",80,24,2},
  {480,320,1,"integer",120,52,1}, {320,240,2,"integer",40,12,1},
  {320,240,2,"integer",60,12,5/6,1,768},
}) do
  ww,wh,dpi=case[1],case[2],case[3]
  pixelWidth=case[9]
  queue[#queue+1]={type="receive",data="Ftoken\n240,216,0,secondary:"..case[4].."\n"..string.rep("rgba",240*216)}
  love.update();love.draw()
  near(lastDraw[1],case[5]);near(lastDraw[2],case[6]);near(lastDraw[3],case[7]);near(lastDraw[4],case[8] or case[7])
  love.mousepressed(lastDraw[1]+120.25*lastDraw[3],lastDraw[2]+108.25*lastDraw[4],1)
  assert(sent[#sent]=="Itoken\ndown,120,108","fit and integer share exact pointer placement")
end
local activeFilter, activeShader, drawnFilter, drawnShader
rendered.getWidth=function() return 240 end
rendered.getHeight=function() return 216 end
rendered.getFilter=function() return "nearest","nearest" end
rendered.setFilter=function(_,value) activeFilter=value end
love.graphics.newShader=function() return {send=function() end} end
love.graphics.getShader=function() return activeShader end
love.graphics.setShader=function(value) activeShader=value end
local originalDraw=love.graphics.draw
love.graphics.draw=function(...)
  drawnFilter,drawnShader=activeFilter,activeShader;return originalDraw(...)
end
for _,case in ipairs({
  {1240,1080,"auto",5,"nearest",false},
  {1080,1240,"auto",4.5,"linear",true},
  {1240,1080,"bilinear",5,"linear",false},
  {1080,1240,"nearest",4.5,"nearest",false},
}) do
  ww,wh,dpi,pixelWidth=case[1],case[2],1,nil
  queue[#queue+1]={type="receive",data="Ftoken\n240,216,0,secondary:fit:"..case[3].."\n"..string.rep("rgba",240*216)}
  love.update();love.draw();near(lastDraw[3],case[4]);near(lastDraw[4],case[4])
  assert(drawnFilter==case[5] and (drawnShader~=nil)==case[6],"desktop resolves actual output scale and manual filter")
  assert(activeShader==nil and activeFilter=="nearest","desktop restores caller graphics state")
end
queue[#queue + 1] = { type = "receive", data = "Qtoken" }
love.update()
assert(quit, "parent can close the companion")
print("desktop companion: ok")
