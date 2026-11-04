-- Replay one companion frame without a window or native graphics calls.
return function(Companion, spec)
  local events, queue, result = {}, {}, {}
  local min, mag
  local image = {
    setFilter = function(_,a,b) min,mag=a,b end,
    replacePixels = function() end, release = function() end,
    getWidth = function() return spec.sw end, getHeight = function() return spec.sh end,
  }
  local peer = {send=function(_,text)
    if text:sub(1,2)=="It" then events[#events+1]=text:sub(4) end
  end,disconnect_now=function() end}
  local host = {connect=function() return peer end,
    service=function() return table.remove(queue,1) end}
  package.loaded.enet=nil
  package.preload.enet=function() return {host_create=function() return host end} end
  love={timer={getTime=function() return 1 end},data={decompress=function(_,_,b) return b end},
    image={newImageData=function() return {} end},
    graphics={newImage=function() return image end,
      getDimensions=function() return spec.ww,spec.wh end,
      getDPIScale=function() return spec.dpi end,
      getPixelDimensions=function() return spec.ww*spec.dpi,spec.wh*spec.dpi end,
      clear=function() end,setColor=function() end,
      draw=function(_,x,y,rotation,sx,sy)
        result.x,result.y,result.sx,result.sy=x,y,sx,sy
        result.min,result.mag=min,mag
      end},event={quit=function() end}}
  Companion.install({port=50000,token="t"})
  queue[#queue+1]={type="connect"}
  queue[#queue+1]={type="receive",data="Ft\n"..spec.sw..","..spec.sh..",1122867,"..spec.mode.."\n"..string.rep("a",spec.sw*spec.sh*4)}
  love.update();love.draw()
  love.mousepressed(spec.ww*.25,spec.wh*.6,1)
  love.mousereleased(spec.ww*.25,spec.wh*.6,1)
  result.events=table.concat(events,"|")
  return result
end
