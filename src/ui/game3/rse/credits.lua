local bit = require("bit")
local Stack = require("src.ui.game3.stack")
local FrlgFont = require("src.ui.game3.frlg_font")
local Machine = require("src.ui.game3.rse.gba_machine")
local Scenery = require("src.ui.game3.rse.intro_credits_scenery")
local Ppu = require("src.core.game3.gba_ppu")
local Palette = require("src.core.game3.gba_palette")
local Sprites = require("src.core.game3.gba_sprites")
local Trig = require("src.core.game3.trig")

local band, bor = bit.band, bit.bor

local Credits = {}

Credits.MANIFEST = "data/generated/gba/credits_rse/manifest.lua"
Credits.open = false

-- pokeemerald/src/credits.c:26
local COLOR_DARK_GREEN = Palette.rgb(7, 11, 6)
local COLOR_LIGHT_GREEN = Palette.rgb(13, 20, 12)
-- pokeemerald/src/credits.c:38
local MODE_NONE, MODE_BIKE_SCENE, MODE_SHOW_MONS = 0, 1, 2
local POS_LEFT, POS_RIGHT = 0, 2
-- pokeemerald/src/credits.c:62
local NUM_MON_SLIDES = 71
-- pokeemerald/src/credits.c:180
local TEXT_WINDOW_TOP = 9
-- pokeemerald/src/credits.c:451
local BG0_VOFS = -4
-- pokeemerald/include/constants/pokedex.h:1
local NATIONAL_DEX_COUNT = 386
-- pokeemerald/src/credits.c:1003
local TIMER_STOP = 0x7FFF
local REF_PAL = 7 * 16

local function Sin(i, amp)
  return math.floor(Trig.SINE[band(i, 0xFF) + 1] * amp / 256)
end

local function audio()
  return require("src.core.game3.audio")
end

local function song(name)
  return require("src.core.game3.song_ids")[name]
end

local function rgbOf(c)
  return (c % 32) / 31, (math.floor(c / 32) % 32) / 31, (math.floor(c / 1024) % 32) / 31
end

local function man(self)
  return self.m:manifest(Credits.MANIFEST)
end

local function scenery(self)
  return (self.scenery or Scenery).manifest(self.m)
end

local function rgbaImage(self, key)
  self.images = self.images or {}
  if self.images[key] then return self.images[key] end
  local rel = "data/generated/gba/credits_rse/" .. man(self)[key]
  local bytes = assert(require("src.core.game3.dataset").cache():read(rel), rel .. " is not in the cache")
  local img = love.graphics.newImage(love.image.newImageData(240, 160, "rgba8", bytes))
  img:setFilter("nearest", "nearest")
  self.images[key] = img
  return img
end

-- pokeemerald/src/credits.c:700
local function resetGpuAndVram(self)
  local ppu = self.m.ppu
  for _, r in ipairs({ "DISPCNT", "BG3HOFS", "BG3VOFS", "BG2HOFS", "BG2VOFS", "BG1HOFS", "BG1VOFS",
    "BG0HOFS", "BG0VOFS", "BLDCNT", "BLDALPHA", "BLDY" }) do
    ppu:set(r, 0)
  end
  for i = 0, 3 do ppu:setBg(i, 0, nil) end
  ppu.sprites.oamShown = {}
  local pal = ppu.palette
  for i = 1, Palette.SIZE - 1 do pal.unfaded[i], pal.faded[i] = 0, 0 end
  pal:clearHardware(1)
end

local function loadRefPalette(self)
  self.m.ppu.palette:load({ Palette.WHITE, Palette.BLACK }, REF_PAL, 2)
end

-- pokeemerald/src/credits.c:363
local function initCreditsBgsAndWindows(self)
  local p = man(self).palette
  self.m.ppu.palette:load(p, 8 * 16, #p)
  loadRefPalette(self)
  self.text = nil
end

local function mainTask(self)
  return self.m.tasks:get(self.mainId).data
end

-- pokeemerald/src/credits.c:1188
local function spriteCbPlayer(self, s, sp)
  if self.m.globals.movingSceneryState ~= Scenery.NORMAL then
    sp:destroy(s)
    return
  end
  local st = s.data[0]
  if st == 0 then
    Sprites.startAnimIfDifferent(s, 0)
  elseif st == 1 then
    Sprites.startAnimIfDifferent(s, 1)
    if s.x > -32 then s.x = s.x - 1 end
  elseif st == 2 then
    Sprites.startAnimIfDifferent(s, 2)
  elseif st == 3 then
    Sprites.startAnimIfDifferent(s, 3)
  elseif st == 4 then
    Sprites.startAnimIfDifferent(s, 0)
    if s.x > 120 then s.x = s.x - 1 end
  elseif st == 5 then
    Sprites.startAnimIfDifferent(s, 0)
    if s.x > -32 then s.x = s.x - 1 end
  end
end

-- pokeemerald/src/credits.c:1227
local function spriteCbRival(self, s, sp)
  local g = self.m.globals
  if g.movingSceneryState ~= Scenery.NORMAL then
    sp:destroy(s)
    return
  end
  local st = s.data[0]
  if st == 0 then
    s.y2 = 0
    Sprites.startAnimIfDifferent(s, 0)
  elseif st == 1 then
    if s.x > 200 then Sprites.startAnimIfDifferent(s, 1) else Sprites.startAnimIfDifferent(s, 2) end
    if s.x > -32 then s.x = s.x - 2 end
    s.y2 = -g.movingSceneryVOffset
  elseif st == 2 then
    s.data[7] = s.data[7] + 1
    Sprites.startAnimIfDifferent(s, 0)
    if band(s.data[7], 3) == 0 then s.x = s.x + 1 end
  elseif st == 3 then
    Sprites.startAnimIfDifferent(s, 0)
    if s.x > -32 then s.x = s.x - 1 end
  end
end

-- pokeemerald/src/intro_credits_graphics.c:1109
local function bicycleCb(s, sp)
  local p = sp:get(s.data[0])
  s.invisible = p.invisible
  s.x = p.x
  s.y = p.y + 8
  s.x2 = p.x2
  s.y2 = p.y2
end

-- pokeemerald/src/intro_credits_graphics.c:1118
local function createRider(self, key, tag, x, y, anims, cb)
  local sp = self.m.ppu.sprites
  local tmpl = Machine.template(scenery(self).sprites[key], { paletteTag = tag })
  tmpl.sheet = Machine.sheet(scenery(self).credits[key .. "_credits"])
  tmpl.anims = anims
  tmpl.callback = cb
  local id = sp:create(tmpl, x, y, 2)
  local bike = sp:create(Machine.template(scenery(self).sprites.bicycle, { paletteTag = tag, callback = bicycleCb }), x, y + 8, 3)
  sp:get(bike).data[0] = id
  return id
end

-- pokeemerald/src/credits.c:1135
local function taskBikeScene(self, id, d)
  local g = self.m.globals
  local sp = self.m.ppu.sprites
  local st = d[0]
  if st == 0 then
    g.movingSceneryVOffset = Sin(band(bit.rshift(d[5], 1), 0x7F), 12)
    d[5] = d[5] + 1
  elseif st == 1 then
    if g.movingSceneryVOffset ~= 0 then
      g.movingSceneryVOffset = Sin(band(bit.rshift(d[5], 1), 0x7F), 12)
      d[5] = d[5] + 1
    else
      sp:get(d[2]).data[0] = 2
      d[5] = 0
      d[0] = d[0] + 1
    end
  elseif st == 2 then
    if d[5] < 64 then
      d[5] = d[5] + 1
      g.movingSceneryVOffset = Sin(band(d[5], 0x7F), 20)
    else
      d[0] = d[0] + 1
    end
  elseif st == 3 then
    sp:get(d[2]).data[0] = 3
    sp:get(d[3]).data[0] = 1
    d[4] = 120
    d[0] = d[0] + 1
  elseif st == 4 then
    if d[4] ~= 0 then d[4] = d[4] - 1 else d[5] = 64 d[0] = d[0] + 1 end
  elseif st == 5 then
    if d[5] > 0 then
      d[5] = d[5] - 1
      g.movingSceneryVOffset = Sin(band(d[5], 0x7F), 20)
    else
      sp:get(d[2]).data[0] = 1
      d[0] = d[0] + 1
    end
  elseif st == 6 then
    d[0] = 50
  elseif st == 10 then
    sp:get(d[3]).data[0] = 2
    d[0] = 50
  elseif st == 20 then
    sp:get(d[2]).data[0] = 4
    d[0] = 50
  elseif st == 30 then
    sp:get(d[2]).data[0] = 5
    sp:get(d[3]).data[0] = 3
    d[0] = 50
  elseif st == 50 then
    d[0] = 0
  end
end

-- pokeemerald/src/credits.c:1005
local function taskCycleSceneryPalette(self, id, d)
  local tasks = self.m.tasks
  local main = tasks:get(d[2]).data
  local st = d[0]
  if st == Scenery.SCENE_OCEAN_SUNSET then
    self.scenery.cycleSceneryPalette(self.m, 0)
  elseif st == Scenery.SCENE_FOREST_RIVAL_ARRIVE then
    if d[1] ~= TIMER_STOP then
      local bike = tasks:get(main[1]).data
      if band(bike[5], -128) == 640 then
        bike[0] = 1
        d[1] = TIMER_STOP
      end
    end
    self.scenery.cycleSceneryPalette(self.m, 1)
  elseif st == Scenery.SCENE_FOREST_CATCH_RIVAL then
    if d[1] ~= TIMER_STOP then
      if d[1] == 584 then
        tasks:get(main[1]).data[0] = 10
        d[1] = TIMER_STOP
      else
        d[1] = d[1] + 1
      end
    end
    self.scenery.cycleSceneryPalette(self.m, 1)
  elseif st == Scenery.SCENE_CITY_NIGHT then
    self.scenery.cycleSceneryPalette(self.m, 2)
  else
    if d[1] ~= TIMER_STOP then
      if tasks:get(main[15]).data[2] == 2 then
        tasks:get(main[1]).data[0] = 20
        d[1] = TIMER_STOP
      end
    end
    self.scenery.cycleSceneryPalette(self.m, 0)
  end
end

-- pokeemerald/src/credits.c:1099
local function setBikeScene(self, scene, taskId)
  local m = self.m
  local sp = m.ppu.sprites
  local d = m.tasks:get(taskId).data
  local player, rival = sp:get(d[5]), sp:get(d[6])
  player.invisible, rival.invisible = false, false
  player.y, rival.y = 46, 46
  player.data[0], rival.data[0] = 0, 0
  if scene == Scenery.SCENE_OCEAN_MORNING then
    player.x, rival.x = 240 + 32, 240 + 32
    d[0] = (self.scenery or Scenery).createBicycleBgAnimationTask(m, 0, 0x2000, 0x20, 8)
  elseif scene == Scenery.SCENE_OCEAN_SUNSET then
    player.x, rival.x = 120, 240 + 32
    d[0] = (self.scenery or Scenery).createBicycleBgAnimationTask(m, 0, 0x2000, 0x20, 8)
  elseif scene == Scenery.SCENE_FOREST_RIVAL_ARRIVE then
    player.x, rival.x = 120, 240 + 32
    d[0] = (self.scenery or Scenery).createBicycleBgAnimationTask(m, 1, 0x2000, 0x200, 8)
  elseif scene == Scenery.SCENE_FOREST_CATCH_RIVAL then
    player.x, rival.x = 120, -32
    d[0] = (self.scenery or Scenery).createBicycleBgAnimationTask(m, 1, 0x2000, 0x200, 8)
  else
    player.x, rival.x = 88, 152
    d[0] = (self.scenery or Scenery).createBicycleBgAnimationTask(m, 2, 0x2000, 0x200, 8)
  end
  d[2] = m.tasks:create(function(i, dd) taskCycleSceneryPalette(self, i, dd) end, 0)
  local pd = m.tasks:get(d[2]).data
  pd[0], pd[1], pd[2] = scene, 0, taskId
  d[1] = m.tasks:create(function(i, dd) taskBikeScene(self, i, dd) end, 0)
  local bd = m.tasks:get(d[1]).data
  bd[0], bd[1], bd[2], bd[3], bd[4] = 0, taskId, d[5], d[6], 0
  if scene == Scenery.SCENE_FOREST_RIVAL_ARRIVE then bd[5] = 69 end
end

-- pokeemerald/src/credits.c:1182
local function loadBikeScene(self, scene, taskId)
  local m = self.m
  local ppu = m.ppu
  local st = self.loadState or 0
  if st == 0 then
    ppu:set("DISPCNT", 0)
    ppu:set("BG3HOFS", 8)
    for _, r in ipairs({ "BG3VOFS", "BG2HOFS", "BG2VOFS", "BG1HOFS", "BG1VOFS", "BLDCNT", "BLDALPHA" }) do ppu:set(r, 0) end
    ppu.sprites:resetData()
    ppu.sprites:freeAllPalettes()
    self.loadState = 1
  elseif st == 1 then
    m.globals.movingSceneryVBase = 34
    m.globals.movingSceneryVOffset = 0
    self.scenery.loadCreditsSceneGraphics(m, scene)
    self.loadState = 2
  elseif st == 2 then
    local sm = scenery(self)
    local sp = ppu.sprites
    -- pokeemerald/src/intro_credits_graphics.c:691
    sp:loadPalette(Scenery.TAG_BRENDAN, sm.palettes.sBrendanCredits_Pal)
    sp:loadPalette(Scenery.TAG_MAY, sm.palettes.sMayCredits_Pal)
    sp:loadPalette(Scenery.TAG_FLYGON_LATIOS, sm.palettes.sLatios_Pal)
    sp:loadPalette(Scenery.TAG_FLYGON_LATIAS, sm.palettes.sLatias_Pal)
    local d = m.tasks:get(taskId).data
    local cm = man(self)
    local male = self.gender == 0
    d[5] = createRider(self, male and "brendan" or "may", male and Scenery.TAG_BRENDAN or Scenery.TAG_MAY, 120, 46,
      cm.animsPlayer, function(s, spr) spriteCbPlayer(self, s, spr) end)
    d[6] = createRider(self, male and "may" or "brendan", male and Scenery.TAG_MAY or Scenery.TAG_BRENDAN, 240 + 32, 46,
      cm.animsRival, function(s, spr) spriteCbRival(self, s, spr) end)
    self.loadState = 3
  else
    setBikeScene(self, scene, taskId)
    self.scenery.setCreditsSceneBgCnt(m)
    self.loadState = 0
    return true
  end
  return false
end

-- pokeemerald/src/credits.c:1284
local function resetCreditsTasks(self, taskId)
  local tasks = self.m.tasks
  local d = tasks:get(taskId).data
  for _, k in ipairs({ 0, 1, 2, 3 }) do
    if d[k] ~= 0 then
      tasks:destroy(d[k])
      d[k] = 0
    end
  end
  self.m.globals.movingSceneryState = Scenery.DESTROY
  self.mons = {}
end

-- pokeemerald/src/credits.c:831
local function checkChangeScene(self, page, taskId)
  local d = self.m.tasks:get(taskId).data
  local transitions = man(self).pageTransitions
  if transitions then
    local entry = transitions[page]
    if entry then d[11] = entry.mode; if entry.scene then d[7] = entry.scene end end
    return d[11] ~= MODE_NONE
  end
  local interval = math.floor(man(self).pageCount / 9)
  if page == interval * 1 or page == interval * 3 or page == interval * 5 or page == interval * 7 then
    d[11] = MODE_SHOW_MONS
  end
  local scenes = { [2] = Scenery.SCENE_OCEAN_SUNSET, [4] = Scenery.SCENE_FOREST_RIVAL_ARRIVE,
    [6] = Scenery.SCENE_FOREST_CATCH_RIVAL, [8] = Scenery.SCENE_CITY_NIGHT }
  for n, scene in pairs(scenes) do
    if page == interval * n then
      d[7] = scene
      d[11] = MODE_BIKE_SCENE
    end
  end
  return d[11] ~= MODE_NONE
end

local function fadeText(self, toGreen)
  local d = mainTask(self)
  local color = d[13] == MODE_BIKE_SCENE and COLOR_LIGHT_GREEN or COLOR_DARK_GREEN
  local pal = self.m.ppu.palette
  if toGreen then pal:beginFade(0x300, 0, 0, 16, color) else pal:beginFade(0x300, 0, 16, 0, color) end
end

-- pokeemerald/src/credits.c:725
local function taskUpdatePage(self, id, d)
  local main = mainTask(self)
  local pal = self.m.ppu.palette
  local st = d[0]
  if st == 1 then
    if d[3] ~= 0 then d[3] = d[3] - 1 return end
    d[0] = d[0] + 1
  elseif st == 2 then
    if self.mainFunc == "main" then
      local cm = man(self)
      if d[2] < cm.pageCount then
        self.text = cm.pages[d[2] + 1]
        d[2] = d[2] + 1
        d[0] = d[0] + 1
        main[14] = 1
        fadeText(self, false)
        return
      end
      d[0] = 10
      return
    end
    main[14] = 0
  elseif st == 3 then
    if not pal:fadeActive() then
      d[3] = 115
      d[0] = d[0] + 1
    end
  elseif st == 4 then
    if d[3] ~= 0 then d[3] = d[3] - 1 return end
    if checkChangeScene(self, d[2], d[1]) then
      d[0] = d[0] + 1
      return
    end
    d[0] = d[0] + 1
    fadeText(self, true)
  elseif st == 5 then
    if not pal:fadeActive() then
      self.text = nil
      d[0] = 2
    end
  elseif st == 10 then
    main[4] = 1
    self.m.tasks:destroy(id)
    self.text = nil
  else
    if not pal:fadeActive() then
      d[0] = 1
      d[3] = 72
      main[14] = 0
    end
  end
end

-- pokeemerald/src/credits.c:1570
local function determinePokemonToShow(self)
  local NUM_MON_SLIDES = self.numMonSlides or NUM_MON_SLIDES
  local Pokemon = require("src.core.game3.pokemon")
  local Dex = require("src.core.game3.dex")
  local Rng = require("src.core.game3.rng")
  local sess = self.session or {}
  local starterSel = 0
  pcall(function() starterSel = require("src.core.game3.rse.init").var("VAR_STARTER_MON", sess) end)
  local okS, StarterChoose = pcall(require, "src.ui.game3.rse.starter_choose")
  local starterSpecies = okS and StarterChoose.species(nil, starterSel) or nil
  local starter = starterSpecies and Pokemon.national(starterSpecies) or 0
  local caught = {}
  for n = 1, NATIONAL_DEX_COUNT - 1 do
    local sp = Pokemon.speciesFromNational(n)
    if sp and Dex.isCaught(sess.dex, sp) then caught[#caught + 1] = n end
  end
  local numCaught = #caught
  local numToShow = math.min(numCaught, NUM_MON_SLIDES)
  local show = {}
  local j = 0
  repeat
    if numCaught == 0 then break end
    local page = Rng.Random() % numCaught
    show[j] = caught[page + 1]
    j = j + 1
    caught[page + 1] = 0
    numCaught = numCaught - 1
    if page ~= numCaught then
      caught[page + 1] = caught[numCaught + 1]
      caught[numCaught + 1] = 0
    end
  until numCaught == 0 or j >= NUM_MON_SLIDES
  if numToShow < NUM_MON_SLIDES then
    local page = 0
    for k = numToShow, NUM_MON_SLIDES - 1 do
      show[k] = numToShow > 0 and show[page] or starter
      page = page + 1
      if page == numToShow then page = 0 end
    end
    show[NUM_MON_SLIDES - 1] = starter
  else
    local k = 0
    while k < NUM_MON_SLIDES and show[k] ~= starter do k = k + 1 end
    if k < numToShow - 1 then
      show[k] = show[NUM_MON_SLIDES - 1]
    end
    show[NUM_MON_SLIDES - 1] = starter
  end
  self.monToShow = show
  self.imgCounter, self.nextImgPos, self.currShownMon = 0, POS_LEFT, 0
end

-- pokeemerald/src/credits.c:1467
local function monSpriteCb(self, s)
  if self.m.globals.movingSceneryState ~= Scenery.NORMAL then
    s.dead = true
    return
  end
  s.t = s.t + 1
  if s.state == 0 then
    s.scale = 16
    s.invisible = false
    s.state = 1
  elseif s.state == 1 then
    if s.scale < 256 then
      s.scale = s.scale + 8
    else
      s.state = 2
    end
    if s.pos == POS_LEFT then
      if band(s.t, 3) == 0 then s.y = s.y + 1 end
      s.x = s.x - 2
    elseif s.pos == POS_RIGHT then
      if band(s.t, 3) == 0 then s.y = s.y + 1 end
      s.x = s.x + 2
    end
  elseif s.state == 2 then
    if s.hold ~= 0 then
      s.hold = s.hold - 1
    else
      s.blend = true
      s.hold = 16
      s.state = 3
    end
  elseif s.state == 3 then
    if s.hold ~= 0 then
      s.hold = s.hold - 1
    else
      s.invisible = true
      s.state = 9
    end
  elseif s.state == 9 then
    s.state = 10
  else
    s.dead = true
  end
end

-- pokeemerald/src/credits.c:898
local function taskShowMons(self, id, d)
  local main = mainTask(self)
  local st = d[0]
  if st == 1 then
    if self.nextImgPos == POS_LEFT and main[14] == 0 then return end
    d[0] = d[0] + 1
  elseif st == 2 then
    if self.imgCounter == (self.numMonSlides or NUM_MON_SLIDES) or self.mainFunc ~= "main" then return end
    local pos = man(self).monSpritePos[self.nextImgPos + 1]
    local nat = self.monToShow[self.currShownMon] or 0
    local s = { nat = nat, x = pos[1], y = pos[2], pos = self.nextImgPos, state = 0, t = 0, scale = 16,
      invisible = true, hold = 50 }
    if self.currShownMon < (self.numMonSlides or NUM_MON_SLIDES) - 1 then
      self.currShownMon = self.currShownMon + 1
    else
      self.currShownMon = 0
      s.hold = 512
    end
    self.mons[#self.mons + 1] = s
    self.imgCounter = self.imgCounter + 1
    if self.nextImgPos == POS_RIGHT then self.nextImgPos = POS_LEFT else self.nextImgPos = self.nextImgPos + 1 end
    d[3] = 50
    d[0] = d[0] + 1
  elseif st == 3 then
    if d[3] ~= 0 then d[3] = d[3] - 1 else d[0] = 1 end
  end
end

-- pokeemerald/src/credits.c:536
local function taskLoadShowMons(self, id)
  local m = self.m
  local d = m.tasks:get(id).data
  m.ppu.sprites:resetData()
  m.ppu.sprites:freeAllPalettes()
  self.mons = {}
  d[3] = m.tasks:create(function(i, dd) taskShowMons(self, i, dd) end, 0)
  m.tasks:get(d[3]).data[0] = 1
  m.ppu.palette:beginFade(Palette.ALL, 0, 16, 0, Palette.BLACK)
  m.ppu:set("DISPCNT", bor(Ppu.DISPCNT_MODE_0, Ppu.DISPCNT_OBJ_1D_MAP, Ppu.DISPCNT_OBJ_ON))
  self.showMons = true
  m.globals.movingSceneryState = Scenery.NORMAL
  self:setMain("wait_fade")
end

function Credits:setMain(name)
  self.mainFunc = name
end

-- pokeemerald/src/credits.c:468
local function mainStep(self)
  local m = self.m
  local pal = m.ppu.palette
  local d = mainTask(self)
  local f = self.mainFunc
  if f == "wait_fade" then
    if not pal:fadeActive() then self:setMain("main") end
  elseif f == "main" then
    if d[4] ~= 0 then
      m.tasks:get(d[1]).data[0] = 30
      d[12] = 256
      self:setMain("end1")
      return
    end
    local mode = d[11]
    if mode == MODE_BIKE_SCENE or mode == MODE_SHOW_MONS then
      d[13] = mode
      d[11] = MODE_NONE
      pal:beginFade(Palette.ALL, 0, 0, 16, Palette.BLACK)
      self:setMain(mode == MODE_BIKE_SCENE and "ready_bike" or "ready_mons")
    end
  elseif f == "ready_bike" or f == "ready_mons" then
    if not pal:fadeActive() then
      m.ppu:set("DISPCNT", 0)
      resetCreditsTasks(self, self.mainId)
      self.showMons = false
      self:setMain(f == "ready_bike" and "set_bike" or "load_mons")
    end
  elseif f == "set_bike" then
    if loadBikeScene(self, d[7], self.mainId) then
      pal:beginFade(Palette.ALL, 0, 16, 0, Palette.BLACK)
      self:setMain("wait_fade")
    end
  elseif f == "load_mons" then
    taskLoadShowMons(self, self.mainId)
  elseif f == "end1" then
    if d[12] ~= 0 then d[12] = d[12] - 1 return end
    pal:beginFade(Palette.ALL, 12, 0, 16, Palette.BLACK)
    self:setMain("end2")
  elseif f == "end2" then
    if not pal:fadeActive() then
      resetCreditsTasks(self, self.mainId)
      self:setMain("end3")
    end
  elseif f == "end3" then
    resetGpuAndVram(self)
    pal:resetFade()
    loadRefPalette(self)
    m.ppu.sprites:resetData()
    m.ppu.sprites:freeAllPalettes()
    self.showMons = false
    self.theEnd = "theEndBlank"
    pal:beginFade(Palette.ALL, 8, 16, 0, Palette.BLACK)
    self.endDelay = 235
    self:setMain("end4")
  elseif f == "end4" then
    if self.endDelay ~= 0 then self.endDelay = self.endDelay - 1 return end
    pal:beginFade(Palette.ALL, 6, 0, 16, Palette.BLACK)
    self:setMain("end5")
  elseif f == "end5" then
    if not pal:fadeActive() then
      self.theEnd = "theEnd"
      pal:beginFade(Palette.ALL, 0, 0, 0, Palette.BLACK)
      self.endDelay = 7200
      self:setMain("end6")
    end
  elseif f == "end6" then
    if not pal:fadeActive() then
      if self.endDelay == 0 or m.newKeys ~= 0 then
        audio().fadeOutBgm(4)
        pal:beginFade(Palette.ALL, 8, 0, 16, Palette.WHITEALPHA)
        self:setMain("soft_reset")
        return
      end
      if self.endDelay == 7144 then audio().fadeOutBgm(8) end
      if self.endDelay == 6840 then audio().playSong(song("MUS_END")) end
      self.endDelay = self.endDelay - 1
    end
  elseif f == "soft_reset" then
    if not pal:fadeActive() then
      self:setMain("done")
      Credits.finish()
    end
  end
end

-- pokeemerald/src/credits.c:344
local function cb2(self)
  local m = self.m
  m.tasks:run(self)
  m.ppu.sprites:animateAll()
  self:animateMons()
  if band(m.heldKeys, Machine.B_BUTTON) ~= 0 and self.hasRecords and self.mainFunc == "main" then
    m.ppu:vblank()
    m.tasks:run(self)
    m.ppu.sprites:animateAll()
    self:animateMons()
  end
  m.ppu.sprites:buildOam()
  m.ppu.palette:update()
end

function Credits:animateMons()
  local keep = {}
  for _, s in ipairs(self.mons or {}) do
    monSpriteCb(self, s)
    if not s.dead then keep[#keep + 1] = s end
  end
  self.mons = keep
end

-- pokeemerald/src/credits.c:409
function Credits.new(opts)
  local self = setmetatable({}, { __index = Credits })
  opts = opts or {}
  self.scenery = opts.scenery or Scenery
  self.assetLayout = opts.assetLayout
  self.session = opts.session
  self.gender = (opts.session and (opts.session.gender == 1 or opts.session.gender == "female")) and 1 or 0
  self.hasRecords = opts.hasRecords == true
  self.m = Machine.new()
  self.mons = {}
  local m = self.m
  resetGpuAndVram(self)
  m:setVBlank(nil)
  m.ppu.palette:resetFade()
  m.tasks:reset()
  initCreditsBgsAndWindows(self)
  self.numMonSlides = man(self).numMonSlides or NUM_MON_SLIDES
  self.mainId = m.tasks:create(function(i, d) mainStep(self, i, d) end, 0)
  local d = m.tasks:get(self.mainId).data
  d[4], d[7], d[11], d[13] = 0, Scenery.SCENE_OCEAN_MORNING, MODE_NONE, MODE_BIKE_SCENE
  self:setMain("wait_fade")
  while not loadBikeScene(self, Scenery.SCENE_OCEAN_MORNING, self.mainId) do end
  m.tasks:get(d[1]).data[0] = 40
  local pageId = m.tasks:create(function(i, dd) taskUpdatePage(self, i, dd) end, 0)
  m.tasks:get(pageId).data[1] = self.mainId
  d[15] = pageId
  m.ppu.palette:beginFade(Palette.ALL, 0, 16, 0, Palette.BLACK)
  m:setVBlank(function(mm) mm.ppu:vblank() end)
  audio().playSong(song("MUS_CREDITS"))
  m:setCb2(function() cb2(self) end)
  determinePokemonToShow(self)
  return self
end

function Credits.start(opts)
  Credits.open = true
  Credits._onDone = opts and opts.onDone
  Credits.state = Credits.new(opts)
  local okF, Fade = pcall(require, "src.ui.game3.fade")
  if okF and Fade.clear then Fade.clear() end
  Stack.push("rse_credits", Credits, { hideBelow = true, fullscreen = true })
  return Credits.state
end

function Credits.finish()
  if not Credits.open then return end
  Credits.open = false
  Stack.pop("rse_credits")
  local cb = Credits._onDone
  Credits._onDone = nil
  if cb then cb() end
end

function Credits.reset()
  Credits.open = false
  Credits._onDone = nil
  Credits.state = nil
  Stack.pop("rse_credits")
end

function Credits.isOpen()
  return Credits.open
end

function Credits.handleInput(input)
  Credits._input = input
end

function Credits.update()
  local st = Credits.state
  if not (Credits.open and st) then return end
  st.m:frame(Credits._input)
end

local function fadeParams(st)
  local pltt = st.m.ppu.palette.pltt
  local a, b = pltt[REF_PAL] or Palette.WHITE, pltt[REF_PAL + 1] or 0
  local ar, ag, ab = rgbOf(a)
  local br, bg, bb = rgbOf(b)
  return ar - br, ag - bg, ab - bb, br, bg, bb
end

local function drawFaded(st, img, x, y, sx, sy, alpha)
  local mr, mg, mb, cr, cg, cb = fadeParams(st)
  love.graphics.setColor(mr, mg, mb, alpha or 1)
  love.graphics.draw(img, x, y, 0, sx or 1, sy or 1)
  if cr > 0 or cg > 0 or cb > 0 then
    love.graphics.setBlendMode("add")
    love.graphics.setColor(cr * (alpha or 1), cg * (alpha or 1), cb * (alpha or 1), 1)
    love.graphics.draw(img, x, y, 0, sx or 1, sy or 1)
    love.graphics.setBlendMode("alpha")
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- pokeemerald/src/credits.c:552
local MON_BG = { Palette.rgb(31, 31, 20), Palette.rgb(31, 20, 20), Palette.rgb(20, 20, 31) }

local function drawMons(st)
  local Pokemon = require("src.core.game3.pokemon")
  local Dex = require("src.core.game3.dex")
  local mr, mg, mb, cr, cg, cb = fadeParams(st)
  for _, s in ipairs(st.mons) do
    if not s.invisible then
      local k = s.scale / 256
      local a = s.blend and (s.hold / 16) or 1
      local r, g, b = rgbOf(MON_BG[s.pos + 1])
      love.graphics.setScissor()
      local size = 64 * k
      love.graphics.setColor(r * mr + cr, g * mg + cg, b * mb + cb, a)
      love.graphics.rectangle("fill", s.x - size / 2, s.y - size / 2, size, size)
      local species = Pokemon.speciesFromNational(s.nat)
      local pic = species and Pokemon.dexFrontPic(species, Dex.defaultPersonality(st.session and st.session.dex, species), "credits")
      if pic and pic.image then
        local w, h = pic.image:getDimensions()
        drawFaded(st, pic.image, s.x - w * k / 2, s.y - h * k / 2, k, k, a)
      end
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- pokeemerald/src/credits.c:385
local function drawText(st)
  if not st.text then return end
  local pltt = st.m.ppu.palette.pltt
  local function col(i)
    local r, g, b = rgbOf(pltt[8 * 16 + i] or 0)
    return { r, g, b, 1 }
  end
  local top = TEXT_WINDOW_TOP * 8 - BG0_VOFS
  for i, e in ipairs(st.text) do
    if e.text ~= "" then
      local colors = e.isTitle and { fg = col(3), shadow = col(4), bg = { 0, 0, 0, 0 } }
        or { fg = col(1), shadow = col(2), bg = { 0, 0, 0, 0 } }
      local textOpts = { colors = colors, letterSpacing = 1 }
      if st.assetLayout == "rs" then
        local bank = (e.palette or 8) - 8
        textOpts = { colors = { fg=col(bank*16+1),shadow=col(bank*16+2),bg={0,0,0,0} },font="native_3",textMode=2,letterSpacing=0 }
      end
      local w = FrlgFont.measure(e.text, textOpts)
      local x = math.floor((240 - w) / 2)
      FrlgFont.draw(e.text, x, top + (st.assetLayout == "rs" and 0 or 5) + (i - 1) * 16, textOpts)
    end
  end
end

function Credits.draw()
  local st = Credits.state
  if not (Credits.open and st) then return end
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("fill", 0, 0, 240, 160)
  love.graphics.setColor(1, 1, 1, 1)
  if st.theEnd then
    drawFaded(st, rgbaImage(st, st.theEnd), 0, 0)
    return
  end
  if st.showMons then
    drawFaded(st, rgbaImage(st, "grass"), 0, 0)
    drawMons(st)
  else
    st.m.ppu:draw(0, 0)
  end
  drawText(st)
end

return Credits
