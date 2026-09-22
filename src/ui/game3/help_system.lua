-- FireRed's modal L/R Help. Lives above the normal UI stack so opening Help
-- never replaces a menu or advances the field, scripts, battle, or their tasks.
local Options = require('src.core.game3.options')
local Stack = require('src.ui.game3.stack')
local Strings = require('src.core.Strings')
local Rules = require('src.core.game3.help_rules')
local Font = require('src.ui.game3.frlg_font')
local Help = {open=false, seenIntro=false}
local MENU_CONTEXT = {pokedex=4, party=5, bag=9, berry_pouch=9, tm_case=9,
  trainer=10, save=12, option=13, shop=17, pc_menu=27, box_storage=28}
local HELD_KEYS = {'up','down','left','right'}
local repeatInput, repeatKey, repeatOn
local REPEAT_SHIM = {wasPressed=function(_,key)
  if not repeatInput then return false end
  return repeatInput:wasPressed(key) or (repeatOn and key==repeatKey)
end}
local function loaded(name) return package.loaded['src.'..name] end
function Help.installPack(pack)
  Help.pack=pack
  Help._tiles=nil
end
function Help.install(cache)
  Help.installPack(nil)
  local source=cache:read(require('src.import.gba.help_extract').PATH)
  if not source then return false end
  local chunk=loadstring and loadstring(source) or load(source)
  if not chunk then return false end
  local ok,pack=pcall(chunk)
  if not ok or type(pack)~='table' or pack.version~=1 then return false end
  Help.installPack(pack)
  return true
end
function Help.reset()
  Help.close()
  Help.seenIntro=false
  Help.enabled=true
  Help.contextOverride=nil
  Help.contextBackup=nil
end
function Help.isOpen() return Help.open end
function Help.setContext(id)
  id=tonumber(id)
  if id and (id<0 or id>35 or id~=math.floor(id)) then return false end
  Help.contextOverride=id
  return true
end
function Help.context(game)
  if Help.contextOverride~=nil then return Help.contextOverride end
  local naming=loaded('ui.game3.naming')
  if naming and naming.isOpen() then return 3 end
  if game.phase=='boot' then
    local phase=game.boot and game.boot.phase
    if phase=='title' or phase=='menu' then return 1 end
    if phase=='oak' or phase=='controls' or phase=='pikachu' then return 2 end
    return 0
  end
  -- Retail deliberately retains battle help in party, bag and summary menus.
  local battle=loaded('core.game3.battle')
  if battle and battle.isActive() then
    local state=battle.getState() or {}
    if state.safari then return 26 end
    if state.wild == false then return state.double and 25 or 24 end
    return 23
  end
  local top=Stack.top()
  if top then
    if top.id=='summary' then return 6+math.min(2,top.mod._page or 0) end
    if top.id=='trainer' then return top.mod.side=='back' and 11 or 10 end
    if top.id=='pc_menu' then
      local mode=top.mod.mode
      local bedroom=(game.session and game.session.map or ''):find('PLAYERS_HOUSE')
      if mode=='storage_menu' then return 28 end
      if mode=='oak_pc' then return 31 end
      if mode=='item_storage' or (mode or ''):find('withdraw') or (mode or ''):find('deposit') then
        return bedroom and 33 or 29
      end
      return bedroom and 32 or 27
    end
    if MENU_CONTEXT[top.id] then return MENU_CONTEXT[top.id] end
  end
  local session=game.session or {}
  local map=session.map or ''
  local player=loaded('core.game3.player')
  if (player and player.surfing) or session.surfing then return 22 end
  if map:find('PLAYERS_HOUSE') then return 14 end
  if map:find('OAKS_LAB') then return 15 end
  if map:find('POKECENTER') or map:find('POKEMON_CENTER') then return 16 end
  if map:find('MART') or map:find('DEPARTMENT_STORE') then return 17 end
  if map:find('GYM') then return 18 end
  local def=game.data and game.data.maps and game.data.maps[map]
  if def and def.mapType==4 then return 21 end
  if map:find('VIRIDIAN_FOREST') or map:find('BERRY_FOREST') or map:find('PATTERN_BUSH') then return 21 end
  if def and (def.mapType==8 or def.mapType==9) then return 19 end
  return 20
end
local function audio(id)
  local a=loaded('core.game3.audio')
  if a and a.playSe then a.playSe(id) end
end
function Help.close()
  if Help.open then audio(251) end
  local a=loaded('core.game3.audio')
  if a and a.setHelpActive then a.setHelpActive(false) end -- SE_HELP_CLOSE
  Help.open=false
end
local function mainItems()
  local rows={}
  for _,topic in ipairs({4,1,2,3,5}) do
    if Help.pack.contexts[Help.contextId] and Help.pack.contexts[Help.contextId][topic] then
      rows[#rows+1]={id=topic,label=Help.pack.topics[topic]}
    end
  end
  rows[#rows+1]={label=Help.pack.topics[6]}
  return rows
end
local function submenuItems()
  local rows, used={},{}
  local basics=Help.topic==3 and Rules.flag(Help.session,'DEFEATED_BROCK')
  local basicIds={}
  if basics then for _,id in ipairs(Help.pack.basic) do basicIds[id]=true end end
  local function add(id)
    local entry=Help.pack.entries[Help.topic][id]
    if entry and not used[id] then rows[#rows+1]={id=id,label=entry.question};used[id]=true end
  end
  for _,id in ipairs(Help.pack.contexts[Help.contextId][Help.topic] or {}) do
    if not basicIds[id] and Rules.enabled(Help.topic,id,Help.session) then add(id) end
  end
  if basics then for _,id in ipairs(Help.pack.basic) do add(id) end end
  rows[#rows+1]={label=Help.pack.cancel}
  return rows
end
function Help.show(game,context)
  if not Help.pack then return false end
  Help.session=game.session or {}
  Help.contextId=context or Help.context(game)
  if Help.contextId==0 or Help.contextId==35 then return false end
  Help._held=nil;Help._heldFrames=0
  Help.open=true;Help.cursor=1;Help.scroll=0;Help.articleScroll=0
  Help.rows=mainItems()
  Help.level=(Help.seenIntro or Rules.flag(Help.session,'SYS_SAW_HELP_SYSTEM_INTRO')) and 'main' or 'welcome'
  if game.session then
    local Flags=require('src.core.game3.scripting.flags')
    local Space=loaded('core.game3.scripting.space')
    Flags.setFlag(Space and Space.store or game.session,nil,Flags.IDS.SYS_SAW_HELP_SYSTEM_INTRO,true)
    game.session.flags=game.session.flags or {}
    Flags.setFlag(game.session,nil,Flags.IDS.SYS_SAW_HELP_SYSTEM_INTRO,true)
  end
  local a=loaded('core.game3.audio')
  if a and a.setHelpActive then a.setHelpActive(true) end
  Help.seenIntro=true
  audio(250) -- SE_HELP_OPEN
  return true
end
function Help.handleInput(input)
  if input:wasPressed('l') or input:wasPressed('r') then Help.close();return end
  local back=input:wasPressed('b')
  local accept=input:wasPressed('a')
  if Help.level=='welcome' then
    if accept then Help.level='main';audio(5) end
  elseif Help.level=='article' then
    if back or accept then
      Help.level='submenu';audio(5)
    elseif input:wasPressed('down') then
      Help.articleScroll=math.min(Help.maxArticleScroll or 0,Help.articleScroll+1)
    elseif input:wasPressed('up') then Help.articleScroll=math.max(0,Help.articleScroll-1) end
  elseif back then
    if Help.level=='main' then Help.close()
    else Help.level='main';Help.rows=mainItems();Help.cursor=Help.mainCursor;Help.scroll=0;audio(5) end
  elseif accept then
    local row=Help.rows[Help.cursor]
    if not row.id then
      if Help.level=='main' then Help.close()
      else Help.level='main';Help.rows=mainItems();Help.cursor=Help.mainCursor;Help.scroll=0 end
    elseif Help.level=='main' then
      Help.mainCursor=Help.cursor;Help.topic=row.id
      Help.rows=submenuItems();Help.cursor=1;Help.scroll=0;Help.level='submenu';audio(5)
    else
      Help.article=Help.pack.entries[Help.topic][row.id]
      Help.articleScroll=0;Help.level='article';audio(5)
    end
  else
    local delta=input:wasPressed('up') and -1 or input:wasPressed('down') and 1
      or input:wasPressed('left') and -7 or input:wasPressed('right') and 7 or 0
    if delta~=0 then
      Help.cursor=math.max(1,math.min(#Help.rows,Help.cursor+delta))
      Help.scroll=math.max(0,math.min(Help.scroll,Help.cursor-1))
      if Help.cursor>Help.scroll+7 then Help.scroll=Help.cursor-7 end
      audio(5)
    end
  end
end
function Help.update(game)
  local input=game.input
  if not input then return false end
  if Help.open then
    -- GBA joypad repeat: delay before held directions repeat every five frames.
    local heldKey
    for _,key in ipairs(HELD_KEYS) do
      if input.isDown and input:isDown(key) then heldKey=key;break end
    end
    if heldKey~=Help._held then Help._held=heldKey;Help._heldFrames=0 end
    Help._heldFrames=(Help._heldFrames or 0)+1
    repeatInput, repeatKey = input, heldKey
    repeatOn = heldKey ~= nil and Help._heldFrames>=20 and (Help._heldFrames-20)%5==0
    Help.handleInput(REPEAT_SHIM)
    return true
  end
  if not Help.pack or Help.enabled==false then return false end
  if tonumber(Options.ensure(game.session or {}).buttonMode)~=0 then return false end
  if not input:wasPressed('l') and not input:wasPressed('r') then return false end
  local fade=loaded('ui.game3.fade')
  local transition=loaded('core.game3.battle_transition')
  if fade and fade.isActive() or transition and transition.isActive() then return false end
  return Help.show(game)
end
local function expand(s)
  return tostring(s or ''):gsub('{PLAYER}',function() return Help.session.name or Help.session.playerName or 'PLAYER' end)
    :gsub('{RIVAL}',function() return Help.session.rivalName or 'RIVAL' end)
    :gsub('{PC_OWNER}',function() return Rules.flag(Help.session,'SYS_NOT_SOMEONES_PC') and 'BILL' or 'SOMEONE' end)
end
local function text(s,x,y,small,color)
  Font.draw(expand(s),x,y,{small=small,maxWidth=208,color=color or {1,1,1,1},shadow={98/255,98/255,98/255,1}})
end
local function tile(index,x,y,w,h)
  local g=love.graphics
  local pack=Help.pack
  -- Nine original 4bpp tiles occupy 0x1F7..0x1FF in the Help VRAM bank.
  if not Help._tiles and pack.tiles and #pack.tiles==288 then
    Help._tiles={}
    for t=0,8 do
      local data=love.image.newImageData(8,8)
      for py=0,7 do for px=0,7 do
        local b=pack.tiles[t*32+py*4+math.floor(px/2)+1]
        local n=px%2==0 and b%16 or math.floor(b/16)
        data:setPixel(px,py,unpack(pack.palette[n+1]))
      end end
      local image=g.newImage(data);image:setFilter('nearest','nearest');Help._tiles[t]=image
    end
  end
  g.setColor(1,1,1,1)
  if Help._tiles then
    for yy=y,y+h-1,8 do for xx=x,x+w-1,8 do g.draw(Help._tiles[index],xx,yy) end end
  else
    g.setColor(0,0.48,0.77,1);g.rectangle('fill',x,y,w,h)
  end
end
function Help.draw()
  if not Help.open then return end
  local g=love.graphics
  g.push('all');g.origin();g.setScissor()
  tile(8,0,0,240,160)
  tile(2,0,0,8,160);tile(2,232,0,8,160)
  local article=Help.level=='article'
  if article then tile(3,8,24,224,136) end
  tile(article and 4 or 0,8,16,224,8)
  tile(article and 5 or 1,8,152,224,8)
  text(Strings('HELP'),14,2,true)
  local controls=Help.level=='welcome' and 'A: NEXT' or article and 'A B: CANCEL'
    or Help.level=='main' and '↑↓ PICK  A OK  B END' or '↑↓ PICK  A OK  B CANCEL'
  controls=Strings(controls)
  text(controls,math.max(75,232-Font.measure(controls,{small=true})),2,true)
  g.setScissor(16,24,208,128)
  if Help.level=='welcome' then
    text(Help.pack.greetings,16,24)
  elseif article then
    text(Help.article.question,16,24)
    g.setScissor(8,24,224,128)
    tile(5,8,40,224,8)
    g.setScissor(16,48,208,104)
    local wrapped=Font.wrap(expand(Help.article.answer),208)
    local lines={};for line in (wrapped..'\n'):gmatch('(.-)\n') do lines[#lines+1]=line end
    Help.maxArticleScroll=math.max(0,#lines-7)
    for i=1,7 do text(lines[i+Help.articleScroll],16,48+(i-1)*15) end
  else
    local sub=Help.level=='submenu'
    if sub then text(Help.pack.topics[Help.topic],16,24) end
    for i=1,sub and 7 or #Help.rows do
      local row=Help.rows[i+Help.scroll]
      if row then
        local y=(sub and 45 or 28)+(i-1)*15
        if Help.cursor==i+Help.scroll then
          Font.drawGlyph(0xEF,16,y,{colors={fg={1,1,1,1},shadow={98/255,98/255,98/255,1}}})
        end
        text(row.label,24,y)
      end
    end
    if sub then
      g.setScissor(8,24,224,128)
      if Help.scroll>0 then tile(7,224,24,8,8) end
      if Help.scroll+7<#Help.rows then tile(6,224,144,8,8) end
    else
      local row=Help.rows[Help.cursor]
      g.setColor(1,1,1,1);g.rectangle('fill',16,112,208,40)
      Font.draw(Help.pack.descriptions[row.id or 6] or '',18,118,{maxWidth=204,
        colors={fg={98/255,98/255,98/255,1},shadow={213/255,213/255,205/255,1}}})
    end
  end
  g.pop()
end
return Help
