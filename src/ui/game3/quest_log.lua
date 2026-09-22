-- Read-only Quest Log movie, drawn from recorded tiles and actor tracks.
local Q=require('src.core.game3.quest_log')
local Font=require('src.ui.game3.frlg_font')
local Strings=require('src.core.Strings')
local Ow, PokedexChrome
local function owSprites() Ow=Ow or require('src.core.game3.ow_sprites');return Ow end
local function pokedexChrome() PokedexChrome=PokedexChrome or require('src.ui.game3.pokedex_chrome');return PokedexChrome end
local function actorOrder(a,b) return a.y<b.y or (a.y==b.y and a.id<b.id) end
local UI={}
function UI.install(cache)
  UI.pack=nil
  local src=cache and cache:read('data/generated/gba/quest_log/pack.lua')
  if src then
    local f=loadstring(src,'@quest_log/pack.lua')
    if f then setfenv(f,{});UI.pack=f() end
  end
end
function UI.text(key,args,session)
  local text=UI.pack and UI.pack.text[key] or ''
  args=args or {};session=session or {}
  return (text:gsub('{([^}]+)}',function(k)
    if k=='PLAYER' then return session.name or 'RED' end
    if k=='RIVAL' then return session.rivalName or 'BLUE' end
    local v=args[k] or args[tonumber(k:match('^S(%d+)$'))] or args[k:match('^S(%d+)$')]
    if type(v)=='table' then return UI.pack.text[v.text] or '' end
    return tostring(v or '')
  end))
end
function UI.begin(session)
  if not UI.pack then return nil end
  return Q.playback(session.questLog)
end
local function tiles(scene,frame,over)
  local T=require('src.core.game3.tileset_native')
  local cx=math.floor(frame.x+8-120);local cy=math.floor(frame.y+8-80)
  local textures={}
  for y=math.floor(cy/16),math.floor((cy+159)/16) do
    for x=math.floor(cx/16),math.floor((cx+239)/16) do
      local tile=scene.tiles and scene.tiles[x..','..y]
      if tile then
        local ts=textures[tile[2]] or T.get(tile[2])
        if tile[2] then textures[tile[2]]=ts end
        if ts then
          local slot=T.slotFor(ts,tile[1])
          local quad
          if over then quad=T.overQuad(ts,slot) else quad=T.quad(ts,slot) end
          local image
          if over then image=ts.overImage else image=ts.image end
          if image and quad and (not over or ts.layered) then love.graphics.draw(image,quad,x*16-cx,y*16-cy) end
        end
      end
    end
  end
end
function UI.draw(playback,session)
  love.graphics.clear(0,0,0,1)
  local scene=playback:current();local frame=playback:frame()
  if not scene or not frame then return end
  -- The original presents previous scenes in monochrome, then the save in color.
  if not UI.shader and love.graphics.newShader then
    UI.shader=love.graphics.newShader([[vec4 effect(vec4 c, Image tex, vec2 uv, vec2 sc) {
      vec4 p=Texel(tex,uv)*c; float y=dot(p.rgb,vec3(0.299,0.587,0.114));
      return vec4(vec3(y),p.a);
    }]])
  end
  if not playback:isFinal() then love.graphics.setShader(UI.shader) end
  love.graphics.setColor(1,1,1,1)
  tiles(scene,frame,false)
  local actors=frame.actors
  table.sort(actors,actorOrder)
  local Ow=owSprites()
  local cx=math.floor(frame.x+8-120);local cy=math.floor(frame.y+8-80)
  for _,a in ipairs(actors) do
    if a.graphicsId then Ow.draw(a.graphicsId,a.x,a.y,cx,cy,a.facing,a.walkPhase,a.stepFlip,{frame=a.frame,bow=a.bow,fieldMove=a.fieldMove}) end
  end
  tiles(scene,frame,true)
  love.graphics.setShader()
  love.graphics.setColor(0.12,0.16,0.18,1)
  love.graphics.rectangle('fill',0,0,240,18)
  love.graphics.rectangle('fill',0,144,240,16)
  local title=UI.text('PreviouslyOnYourQuest',{},session)
  if not playback:isFinal() then title=title..' '..playback:number() end
  Font.draw(title,2,2,{colors=Font.COLOR.WHITE})
  local e=playback:event()
  if e then
    local text=Font.wrap(UI.text(e.key,e.args,session):gsub('\n',' '),232,{})
    local lines=1;for _ in text:gmatch('\n') do lines=lines+1 end
    local y=144-math.max(32,lines*16)
    love.graphics.setColor(0.12,0.16,0.18,0.94)
    love.graphics.rectangle('fill',0,y,240,144-y)
    Font.draw(text,4,y,{colors=Font.COLOR.WHITE})
  end
  local PokedexChrome = pokedexChrome()
  PokedexChrome.drawControlInfoLeft(Strings('{A_BUTTON}NEXT   {B_BUTTON}SKIP'), 4, 146)
end
return UI
