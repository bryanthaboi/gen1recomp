-- pokefirered/src/daycare.c:1749 EggHatch

local Stack = require("src.ui.game3.stack")
local Display = require("src.core.game3.display")
local Message = require("src.ui.game3.message")
local Pokemon = require("src.core.game3.pokemon")
local Audio = require("src.core.game3.audio")
local Oam = require("src.core.game3.oam")
local SE = require("src.core.game3.se_ids")
local Strings = require("src.core.Strings")

local EggHatch = {}

local STACK_ID = "egg_hatch"
local MUS_EVOLUTION_INTRO = 263 -- pokefirered/include/constants/songs.h:270
local MUS_EVOLUTION = 264 -- pokefirered/include/constants/songs.h:271
local MUS_EVOLVED = 259 -- pokefirered/include/constants/songs.h:266

EggHatch.open = false
EggHatch._mon = nil
EggHatch._species = nil
EggHatch._slot = nil
EggHatch._session = nil
EggHatch._onDone = nil
EggHatch._savedSong = nil
EggHatch._state = "fade_in"
EggHatch._timer = 0
EggHatch._bgmTimer = 0
EggHatch._shake = 0
EggHatch._eggFrame = 0
EggHatch._eggShown = true
EggHatch._flashAlpha = 0
EggHatch._fade = 1
EggHatch._headless = false

-- pokefirered/src/daycare.c:2008 PlaySE(SE_BALL)
local SHAKE_PHASES = {
  { wait = 0, length = 20, crackAt = 15, amp = 1, frame = 1, shards = 1 },
  { wait = 30, length = 20, crackAt = 15, amp = 2, frame = 2 },
  { wait = 30, length = 38, crackAt = 15, amp = 2, frame = 2, secondAt = 30, shards = 2 },
}
EggHatch.SHAKE_PHASES = SHAKE_PHASES

-- pokefirered/src/daycare.c:329 sEggShardVelocities
local SHARD_VELOCITIES = {
  { -1.5, -3.75 }, { -5, -3 }, { 3.5, -3 }, { -4, -3.75 },
  { 2, -1.5 }, { -0.5, -6.75 }, { 5, -2.25 }, { -1.5, -3.75 },
  { 4.5, -1.5 }, { -1, -6.75 }, { 4, -2.25 }, { -3.5, -3.75 },
  { 1, -1.5 }, { -3.515625, -6.75 }, { 4.5, -2.25 }, { -0.5, -7.5 },
  { 1, -4.5 }, { -2.5, -2.25 }, { 2.5, -7.5 },
}
EggHatch.SHARD_VELOCITIES = SHARD_VELOCITIES

-- pokefirered/src/daycare.c:1891 CreateSprite(&sSpriteTemplate_EggHatch, 120, 75, 5)
local EGG_X, EGG_Y = 120, 75
-- pokefirered/src/daycare.c:1734 CreateSprite(&gMultiuseSpriteTemplate, 120, 70, 6)
local MON_X, MON_Y = 120, 70
-- pokefirered/src/daycare.c:2136 CreateEggShardSprite(120, 60, ...)
local SHARD_X, SHARD_Y = 120, 60

-- pokefirered/src/daycare.c:137 sEggPalette
local ART_SUB = "pokemon/egg"
local HATCH_W, HATCH_H, HATCH_FRAMES = 32, 32, 4
local SHARD_W, SHARD_H, SHARD_FRAMES = 8, 8, 4

local function cache_root()
  local okE, Extract = pcall(require, "src.import.gba.extract_island1")
  return (okE and Extract and Extract.CACHE_ROOT) or "data/generated/gba"
end

local function read_bytes(path)
  if love and love.filesystem and love.filesystem.getInfo then
    local info = love.filesystem.getInfo(path)
    if info then
      local data = love.filesystem.read(path)
      if data and #data > 0 then return data end
    end
  end
  local f = io.open(path, "rb")
  if f then
    local d = f:read("*a")
    f:close()
    if d and #d > 0 then return d end
  end
  return nil
end

local function rgba_to_image(rgba, w, h)
  if not (love and love.image and love.graphics) then return nil end
  if not rgba or #rgba < w * h * 4 then return nil end
  local okI, data = pcall(love.image.newImageData, w, h, "rgba8", rgba)
  if not (okI and data) then return nil end
  local okG, img = pcall(love.graphics.newImage, data)
  if not okG then return nil end
  if img.setFilter then img:setFilter("nearest", "nearest") end
  return img
end

EggHatch._sheets = {}

local function sheet(key, rel, w, h, frames, across)
  if EggHatch._sheets[key] == nil then
    local bytes = read_bytes(cache_root() .. "/" .. ART_SUB .. "/" .. rel)
    local sw = across and (w * frames) or w
    local sh = across and h or (h * frames)
    local img = bytes and rgba_to_image(bytes, sw, sh)
    if img then
      local quads = {}
      for i = 0, frames - 1 do
        quads[i] = love.graphics.newQuad(across and i * w or 0, across and 0 or i * h,
          w, h, img:getDimensions())
      end
      EggHatch._sheets[key] = { image = img, quads = quads }
    else
      EggHatch._sheets[key] = false
    end
  end
  return EggHatch._sheets[key] or nil
end

function EggHatch.reloadAssets()
  EggHatch._sheets = {}
end

local function se(id)
  pcall(function() if Audio.playSe then Audio.playSe(id) end end)
end

local function song(id, opts)
  pcall(function() if Audio.playSong then Audio.playSong(id, opts) end end)
end

function EggHatch.isOpen()
  return EggHatch.open == true
end

-- pokefirered/src/daycare.c:354 DayCare_GetMonNickname
function EggHatch.displayName(mon)
  local name = Pokemon.displayMonName and Pokemon.displayMonName(mon)
  if type(name) == "string" and name ~= "" then return name end
  return tostring((Pokemon.name and Pokemon.name(Pokemon.speciesOf(mon))) or "POKéMON")
end

local function finish_scene()
  EggHatch.open = false
  Stack.pop(STACK_ID)
  local cb = EggHatch._onDone
  EggHatch._onDone = nil
  EggHatch._mon = nil
  if Message.close then Message.close() end
  -- pokefirered/src/daycare.c:1781 gSpecialVar_0x8005 = GetCurrentMapMusic
  local saved = EggHatch._savedSong or Audio._mapSong
  if saved then song(saved) end
  if cb then cb("hatched") end
end
EggHatch._finish = finish_scene

function EggHatch.start(mon, opts)
  opts = opts or {}
  if not mon then
    if opts.onDone then opts.onDone("error") end
    return false
  end
  EggHatch._mon = mon
  EggHatch._slot = opts.slot
  EggHatch._session = opts.session
  EggHatch._onDone = opts.onDone
  EggHatch._savedSong = opts.savedSong or Audio._mapSong
  EggHatch._headless = opts.headless and true or false
  -- pokefirered/src/daycare.c:1824 AddHatchedMonToParty
  require("src.core.game3.breeding").hatchMon(opts.session, mon)
  EggHatch._species = Pokemon.speciesOf(mon)
  EggHatch._name = EggHatch.displayName(mon)
  EggHatch._state = "fade_in"
  EggHatch._timer = 0
  EggHatch._bgmTimer = 0
  EggHatch._shake = 0
  EggHatch._eggFrame = 0
  EggHatch._eggShown = true
  EggHatch._flashAlpha = 0
  EggHatch._fade = 1
  EggHatch._shards = {}
  EggHatch._shardVelocityId = 0
  EggHatch.open = true
  if Oam and Oam.destroyAll then Oam.destroyAll() end
  if Message.setFrame then Message.setFrame("dialogue") end
  pcall(Pokemon.frontPic, EggHatch._species)
  pcall(Pokemon.frontPic, Pokemon.SPECIES_EGG)
  Stack.push(STACK_ID, EggHatch, { hideBelow = true })
  return true
end

-- pokefirered/src/daycare.c:1864 Task_EggHatchPlayBGM
local function bgm_tick()
  local t = EggHatch._bgmTimer
  if t == 0 then
    song(0)
  elseif t == 1 then
    song(MUS_EVOLUTION_INTRO, { loop = false })
  elseif t == 61 then
    song(MUS_EVOLUTION, { restart = true, loop = true })
  end
  if t <= 61 then EggHatch._bgmTimer = t + 1 end
end

-- pokefirered/src/daycare.c:2128 CreateRandomEggShardSprite
local function spawn_shard()
  local Rng = require("src.core.game3.rng")
  local id = (EggHatch._shardVelocityId or 0) % #SHARD_VELOCITIES
  local v = SHARD_VELOCITIES[id + 1]
  EggHatch._shardVelocityId = (EggHatch._shardVelocityId or 0) + 1
  EggHatch._shards[#EggHatch._shards + 1] = {
    -- pokefirered/src/daycare.c:2141 CreateSprite(&sSpriteTemplate_EggShard, x, y, 4)
    frame = Rng.Random() % SHARD_FRAMES,
    vx = v[1] * 256, vy = v[2] * 256, gravity = 100, ax = 0, ay = 0,
  }
end

-- pokefirered/src/daycare.c:2114 SpriteCB_EggShard
local function shards_tick()
  local live = {}
  for _, s in ipairs(EggHatch._shards) do
    s.ax = s.ax + s.vx
    s.ay = s.ay + s.vy
    s.vy = s.vy + s.gravity
    if not (s.ay / 256 > 20 and s.vy > 0) then live[#live + 1] = s end
  end
  EggHatch._shards = live
end

-- pokefirered/src/daycare.c:1995 SpriteCB_Egg_0 through SpriteCB_Egg_4
local function shake_tick()
  local phase = SHAKE_PHASES[EggHatch._shake + 1]
  if not phase then
    -- pokefirered/src/daycare.c:2069 SpriteCB_Egg_3
    EggHatch._timer = EggHatch._timer + 1
    if EggHatch._timer == 51 then
      -- pokefirered/src/daycare.c:2078 SpriteCB_Egg_4
      EggHatch._eggShown = false
      EggHatch._flashAlpha = 1
      -- pokefirered/src/daycare.c:2085 four shards a frame for the first four
      for _ = 1, 16 do spawn_shard() end
    elseif EggHatch._timer > 51 then
      EggHatch._flashAlpha = math.max(0, 1 - (EggHatch._timer - 51) / 16)
      if EggHatch._timer >= 67 then
        -- pokefirered/src/daycare.c:2091 PlaySE(SE_EGG_HATCH)
        se(SE.SE_EGG_HATCH or 106)
        EggHatch._state = "cry"
        EggHatch._timer = 0
        pcall(Audio.playCry, EggHatch._species)
      end
    end
    return
  end
  EggHatch._timer = EggHatch._timer + 1
  if EggHatch._timer <= phase.wait then return end
  local t = EggHatch._timer - phase.wait
  if t > phase.length then
    EggHatch._shake = EggHatch._shake + 1
    EggHatch._timer = 0
    return
  end
  EggHatch._eggOffset = math.sin(t * 20 * math.pi / 128) * phase.amp
  if t == phase.crackAt then
    se(SE.SE_BALL or 23)
    -- pokefirered/src/daycare.c:2009 StartSpriteAnim(sprite, 1)
    EggHatch._eggFrame = phase.frame
    for _ = 1, (phase.shards or 0) do spawn_shard() end
  elseif phase.secondAt and t == phase.secondAt then
    se(SE.SE_BALL or 23)
  end
end

local function ask_nickname()
  local Choice = require("src.ui.game3.choice")
  -- pokefirered/src/daycare.c:1952 CreateYesNoMenu
  Choice.yesNo(function(yes)
    if Message.isOpen and Message.isOpen() and Message.close then Message.close() end
    if not yes then
      EggHatch._state = "fade_out"
      EggHatch._timer = 0
      return
    end
    -- pokefirered/src/daycare.c:1964 DoNamingScreen NAMING_SCREEN_NICKNAME
    local mon = EggHatch._mon
    local Naming = require("src.ui.game3.naming")
    EggHatch._state = "naming"
    Naming.open({
      title = Naming.monTitle(EggHatch._name),
      maxLen = 10,
      seed = EggHatch._name,
      template = Naming.TEMPLATE.NICKNAME,
      species = EggHatch._species,
      gender = mon and mon.gender,
      personality = mon and mon.personality,
      session = EggHatch._session,
      onDone = function(name)
        -- pokefirered/src/daycare.c:1855 EggHatchSetMonNickname
        if mon and type(name) == "string" and name ~= "" then
          mon.nickname = name
          mon.name = name
        end
        EggHatch._state = "fade_out"
        EggHatch._timer = 0
      end,
    })
  end, { left = 21, top = 9 })
end

function EggHatch.update(dt)
  if not EggHatch.open then return end
  if Message.isOpen and Message.isOpen() then Message.tick() end
  -- pokefirered/src/daycare.c:1990 AnimateSprites
  if EggHatch._shards and #EggHatch._shards > 0 then shards_tick() end

  local st = EggHatch._state
  if st == "fade_in" then
    EggHatch._timer = EggHatch._timer + 1
    EggHatch._fade = math.max(0, 1 - EggHatch._timer / 16)
    bgm_tick()
    if EggHatch._timer >= 16 then
      EggHatch._state = "wait"
      EggHatch._timer = 0
    end

  elseif st == "wait" then
    bgm_tick()
    -- pokefirered/src/daycare.c:1906 ++CB2_PalCounter > 30
    EggHatch._timer = EggHatch._timer + 1
    if EggHatch._timer > 30 then
      EggHatch._state = "shake"
      EggHatch._timer = 0
    end

  elseif st == "shake" then
    bgm_tick()
    shake_tick()

  elseif st == "cry" then
    bgm_tick()
    EggHatch._timer = EggHatch._timer + 1
    -- pokefirered/src/daycare.c:1920 IsCryFinished
    local done = Audio.isCryFinished and Audio.isCryFinished()
    if EggHatch._timer >= 40 or done then
      EggHatch._state = "hatched_msg"
      EggHatch._timer = 0
      -- pokefirered/src/daycare.c:1927 gText_HatchedFromEgg
      Message.show(Strings("%s hatched from the EGG!", EggHatch._name), { stay = true })
      if Message.skipReveal then Message.skipReveal() end
      -- pokefirered/src/daycare.c:1929 PlayFanfare(MUS_EVOLVED)
      pcall(Audio.playFanfare, MUS_EVOLVED)
    end

  elseif st == "hatched_msg" then
    EggHatch._timer = EggHatch._timer + 1
    -- pokefirered/src/daycare.c:1935 IsFanfareTaskInactive
    local quiet = (not Audio.isFanfareFinished) or Audio.isFanfareFinished()
    if quiet and EggHatch._timer > 1 then
      EggHatch._state = "nickname_msg"
      EggHatch._timer = 0
      -- pokefirered/src/daycare.c:1944 gText_NickHatchPrompt
      Message.show(Strings("Would you like to nickname the newly\nhatched %s?", EggHatch._name),
        { stay = true })
    end

  elseif st == "nickname_msg" then
    -- pokefirered/src/daycare.c:1949 IsTextPrinterActive
    if not (Message.isTyping and Message.isTyping()) then
      EggHatch._state = "nickname_ask"
      ask_nickname()
    end

  elseif st == "fade_out" then
    EggHatch._timer = EggHatch._timer + 1
    EggHatch._fade = math.min(1, EggHatch._timer / 16)
    -- pokefirered/src/daycare.c:1972 BeginNormalPaletteFade
    if EggHatch._timer >= 16 then finish_scene() end
  end
end

function EggHatch.handleInput(input)
  if not (EggHatch.open and input) then return end
  local Choice = package.loaded["src.ui.game3.choice"]
  if Choice and Choice.active then
    if input:wasPressed("up") then Choice.move(-1)
    elseif input:wasPressed("down") then Choice.move(1)
    elseif input:wasPressed("a") then Choice.confirm()
    elseif input:wasPressed("b") then Choice.cancel()
    end
  end
end

function EggHatch.draw()
  if not (EggHatch.open and love and love.graphics) then return end
  -- pokefirered/src/daycare.c:1839 gTradeOrHatchMonShadowTilemap
  love.graphics.setColor(0.13, 0.16, 0.29, 1)
  love.graphics.rectangle("fill", 0, 0, Display.W, Display.H)
  love.graphics.setColor(0.07, 0.09, 0.18, 1)
  love.graphics.ellipse("fill", MON_X, MON_Y + 36, 40, 9)

  love.graphics.setColor(1, 1, 1, 1)
  if EggHatch._eggShown then
    -- pokefirered/src/daycare.c:138 sEggHatchTiles
    local eggs = sheet("hatch", "hatch.rgba", HATCH_W, HATCH_H, HATCH_FRAMES, false)
    local x = EGG_X + (EggHatch._eggOffset or 0)
    if eggs then
      local quad = eggs.quads[EggHatch._eggFrame or 0] or eggs.quads[0]
      love.graphics.draw(eggs.image, quad, x, EGG_Y, 0, 1, 1, HATCH_W / 2, HATCH_H / 2)
    else
      local eggPic = Pokemon.frontPic(Pokemon.SPECIES_EGG)
      if eggPic and eggPic.image then
        love.graphics.draw(eggPic.image, x, EGG_Y, 0, 1, 1, 32, 32)
      end
    end
  else
    local pic = Pokemon.frontPic(EggHatch._species)
    if pic and pic.image then
      love.graphics.draw(pic.image, MON_X, MON_Y, 0, 1, 1, 32, 32)
    end
  end

  -- pokefirered/src/daycare.c:139 sEggShardTiles
  local shards = EggHatch._shards
  if shards and #shards > 0 then
    local art = sheet("shard", "shard.rgba", SHARD_W, SHARD_H, SHARD_FRAMES, true)
    if art then
      for _, s in ipairs(shards) do
        local quad = art.quads[s.frame] or art.quads[0]
        love.graphics.draw(art.image, quad, SHARD_X + s.ax / 256, SHARD_Y + s.ay / 256,
          0, 1, 1, SHARD_W / 2, SHARD_H / 2)
      end
    end
  end

  if EggHatch._flashAlpha > 0 then
    love.graphics.setColor(1, 1, 1, EggHatch._flashAlpha)
    love.graphics.rectangle("fill", 0, 0, Display.W, Display.H)
  end

  if Message.isOpen and Message.isOpen() then Message.draw() end
  local Choice = package.loaded["src.ui.game3.choice"]
  if Choice and Choice.active and Choice.draw then Choice.draw() end

  if EggHatch._fade > 0 then
    love.graphics.setColor(0, 0, 0, EggHatch._fade)
    love.graphics.rectangle("fill", 0, 0, Display.W, Display.H)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return EggHatch
