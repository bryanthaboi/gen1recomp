-- Adapted from AnimaEngine v1.0.0, Copyright (c) 2026 KillDaWill, MIT.
-- See ANIMAENGINE_LICENSE and PROVENANCE.md. Uses CPU composition, no GPU/native dependency.
local Animation = require("src.import.gen5.Animation")
local Composer = {}
local function flag(value) return value==true or value==1 end
local function scale(value) return (not value or value==0) and 1 or value/4096 end
local function transform(frame,x,y)
  local angle=(frame.rotation or 0)*math.pi*2/65536
  local sx,sy=x*scale(frame.scale_x),y*scale(frame.scale_y)
  return (frame.translate_x or 0)+sx*math.cos(angle)-sy*math.sin(angle),
    (frame.translate_y or 0)+sx*math.sin(angle)+sy*math.cos(angle)
end
local function matrix(record,frame,parent)
  local function point(x,y)
    x,y=transform(frame,x,y)
    x,y=x+(record.x or 0),y+(record.y or 0)
    if parent then x,y=transform(parent,x,y) end
    return x,y
  end
  local tx,ty=point(0,0)
  local ax,ay=point(1,0)
  local bx,by=point(0,1)
  return ax-tx,ay-ty,bx-tx,by-ty,tx,ty
end
local function objects(cells,nanr,nmcr,mapIndex,tick,parent)
  local map=assert(nmcr.maps[mapIndex+1],"missing multicell map")
  local out={}
  for _,record in ipairs(map.records) do
    local frame,err=Animation.frame(nanr,record.animation_index,tick)
    assert(frame,err)
    local cell=assert(cells.cells[frame.cell_id+1],"animation refers to missing cell")
    local a,b,c,d,tx,ty=matrix(record,frame,parent)
    local determinant=a*d-b*c
    assert(math.abs(determinant)>1e-12,"singular sprite transform")
    for _,oam in ipairs(cell.oams) do
      if not flag(oam.disabled) then
        assert(#out<2048,"composed OAM limit exceeded")
        local x,y=oam.draw_x or oam.x,oam.draw_y or oam.y
        if oam.draw_x==nil and flag(oam.affine) and flag(oam.double_size) then
          x,y=x+oam.width/2,y+oam.height/2
        end
        local item={oam=oam,x=x,y=y,a=a,b=b,c=c,d=d,tx=tx,ty=ty,
          determinant=determinant,index=#out+1,min_x=math.huge,min_y=math.huge,
          max_x=-math.huge,max_y=-math.huge}
        for _,corner in ipairs({{x,y},{x+oam.width,y},{x,y+oam.height},{x+oam.width,y+oam.height}}) do
          local wx,wy=a*corner[1]+c*corner[2]+tx,b*corner[1]+d*corner[2]+ty
          item.min_x=math.min(item.min_x,wx);item.min_y=math.min(item.min_y,wy)
          item.max_x=math.max(item.max_x,wx);item.max_y=math.max(item.max_y,wy)
        end
        out[#out+1]=item
      end
    end
  end
  table.sort(out,function(a,b)
    if a.oam.priority~=b.oam.priority then return a.oam.priority>b.oam.priority end
    return a.index>b.index
  end)
  return out
end
local function objectBounds(items)
  local minx,miny,maxx,maxy=math.huge,math.huge,-math.huge,-math.huge
  for _,item in ipairs(items) do
    minx=math.min(minx,math.floor(item.min_x));miny=math.min(miny,math.floor(item.min_y))
    maxx=math.max(maxx,math.ceil(item.max_x));maxy=math.max(maxy,math.ceil(item.max_y))
  end
  if #items==0 then minx,miny,maxx,maxy=0,0,1,1 end
  return {min_x=minx,min_y=miny,max_x=maxx,max_y=maxy}
end
function Composer.bounds(cells,nanr,nmcr,mapIndex,tick,parent)
  return objectBounds(objects(cells,nanr,nmcr,mapIndex,tick,parent))
end
function Composer.unionBounds(cells,nanr,nmcr,mapIndex,ticks,parent)
  assert(#ticks>0 and #ticks<=512,"invalid composition timeline")
  local out
  for _,tick in ipairs(ticks) do
    local bounds=Composer.bounds(cells,nanr,nmcr,mapIndex,tick,parent)
    if not out then out=bounds else
      out.min_x=math.min(out.min_x,bounds.min_x);out.min_y=math.min(out.min_y,bounds.min_y)
      out.max_x=math.max(out.max_x,bounds.max_x);out.max_y=math.max(out.max_y,bounds.max_y)
    end
  end
  return out
end
-- Symmetric nearest-neighbor rounding; fixes the reference's negative floor bias.
local function round(value)
  return value>=0 and math.floor(value+0.5) or math.ceil(value-0.5)
end
Composer.round=round
function Composer.renderIndexed(graphics,palette,cells,nanr,nmcr,mapIndex,tick,opts)
  opts=opts or {}
  local items=objects(cells,nanr,nmcr,mapIndex,tick,opts.parent)
  local bounds=opts.bounds or objectBounds(items)
  local margin=opts.margin or 0
  assert(margin>=0 and margin<=32,"invalid sprite margin")
  local width=bounds.max_x-bounds.min_x+margin*2
  local height=bounds.max_y-bounds.min_y+margin*2
  assert(width>0 and height>0 and width<=1024 and height<=1024,"sprite canvas exceeds bounds")
  local originx,originy=bounds.min_x-margin,bounds.min_y-margin
  local pixels={}
  for _,item in ipairs(items) do
    local oam=item.oam
    local minx=math.max(0,math.floor(item.min_x)-originx-1)
    local miny=math.max(0,math.floor(item.min_y)-originy-1)
    local maxx=math.min(width-1,math.ceil(item.max_x)-originx+1)
    local maxy=math.min(height-1,math.ceil(item.max_y)-originy+1)
    for y=miny,maxy do
      for x=minx,maxx do
        local dx,dy=x+originx-item.tx,y+originy-item.ty
        local sx=round((dx*item.d-dy*item.c)/item.determinant-item.x)
        local sy=round((-dx*item.b+dy*item.a)/item.determinant-item.y)
        if sx>=0 and sy>=0 and sx<oam.width and sy<oam.height then
          if flag(oam.flip_h) then sx=oam.width-1-sx end
          if flag(oam.flip_v) then sy=oam.height-1-sy end
          local tile=oam.tile_index+math.floor(sy/8)*(opts.tile_stride or 32)+math.floor(sx/8)
          local color=graphics:getPixel(tile,sx%8,sy%8)
          if color~=0 then
            local index=color
            if graphics.bpp==4 and #palette.colors>16 then index=(oam.palette or 0)*16+color end
            if not palette.colors[index+1] then index=color end
            if palette.colors[index+1] then pixels[y*width+x+1]=index end
          end
        end
      end
    end
  end
  return pixels,width,height,{min_x=originx,min_y=originy,max_x=originx+width,max_y=originy+height}
end
function Composer.render(graphics,palette,cells,nanr,nmcr,mapIndex,tick,opts)
  local pixels,width,height,bounds=Composer.renderIndexed(graphics,palette,cells,nanr,nmcr,mapIndex,tick,opts)
  assert(love and love.image,"LÖVE image module required for image composition")
  local image=love.image.newImageData(width,height)
  for offset,index in pairs(pixels) do
    local color=palette.colors[index+1]
    image:setPixel((offset-1)%width,math.floor((offset-1)/width),
      color.r/255,color.g/255,color.b/255,(color.a or 255)/255)
  end
  return image,bounds
end
return Composer
