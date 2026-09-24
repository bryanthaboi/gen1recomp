-- pokefirered/src/field_effect.c:2577

local ShowMon = {}

ShowMon._fx = nil
ShowMon._img = {}

local BAND_TOP = 40
local BAND_H = 80
local BAND_W = 256
local SCREEN_W = 240
-- pokefirered/include/constants/sound.h:42
local CRY_VOLUME_RS = 125
-- pokefirered/src/overworld.c:1228
local OUTDOOR_MAP_TYPES = { [1] = true, [2] = true, [3] = true, [5] = true, [6] = true }

local function player()
  return package.loaded["src.core.game3.player"] or require("src.core.game3.player")
end

local function band_image(kind)
  if ShowMon._img[kind] then return ShowMon._img[kind] end
  local FieldEffects = require("src.core.game3.field_effects")
  local cache = FieldEffects._cache
  assert(cache and cache.read, "field move streaks: no ROM cache mounted")
  local Extract = require("src.import.gba.extract_island1")
  local rel = (Extract.CACHE_ROOT or "data/generated/gba") .. "/field_effects/field_move_streaks_" .. kind .. ".rgba"
  local ok, rgba = pcall(cache.read, cache, rel)
  assert(ok and rgba and #rgba == BAND_W * BAND_H * 4, "field move streaks missing from the cache: " .. rel)
  local id = love.image.newImageData(BAND_W, BAND_H, "rgba8", rgba)
  local img = love.graphics.newImage(id)
  img:setFilter("nearest", "nearest")
  ShowMon._img[kind] = img
  return img
end

local function map_is_outdoors()
  local Map = package.loaded["src.core.game3.map"]
  local def = Map and Map.currentDef and Map.currentDef()
  return OUTDOOR_MAP_TYPES[tonumber(def and def.mapType) or 0] == true
end

function ShowMon.invalidate()
  ShowMon._img = {}
end

function ShowMon.isActive()
  return ShowMon._fx ~= nil
end

-- pokefirered/src/main.c:480
function ShowMon.reset()
  ShowMon._fx = nil
end

-- pokefirered/src/fldeff_rocksmash.c:44
function ShowMon.start(mon, opts, onDone)
  opts = opts or {}
  local species = tonumber(type(mon) == "table" and mon.species or mon) or 0
  local P = player()
  local Pokemon = require("src.core.game3.pokemon")
  local monTable = type(mon) == "table" and mon or nil
  local fx = {
    species = species,
    -- pokefirered/src/field_effect.c:2920
    picSpecies = Pokemon.picSpecies(species, monTable and monTable.personality),
    shiny = Pokemon.isShiny(monTable),
    personality = monTable and monTable.personality,
    noDuck = opts.noDuck == true,
    onDone = onDone,
    outdoors = map_is_outdoors(),
    phase = opts.pose and "pose" or 1,
    posed = opts.pose == true,
    -- pokefirered/src/data/object_events/object_event_anims.h:633
    poseWait = 24,
    hofs = 0,
    winL = 240, winT = 80, winB = 81,
    revealed = 0, cleared = 0,
    sprite = nil,
  }
  ShowMon._fx = fx
  if opts.pose then P.startFieldMove(24) end
  return true
end

-- pokefirered/src/field_effect.c:2929
local function step_sprite(fx)
  local s = fx.sprite
  if not s or s.done then return end
  if s.state == "on" then
    s.x = s.x - 20
    if s.x <= 0x78 then
      s.x = 0x78
      s.wait = 30
      s.state = "wait"
      local Audio = require("src.core.game3.audio")
      if fx.noDuck then
        -- pokefirered/src/field_effect.c:2938
        Audio.playCry(fx.species, { mode = 0, volume = CRY_VOLUME_RS, noDuck = true })
      else
        -- pokefirered/src/field_effect.c:2942
        Audio.playCry(fx.species, 0)
      end
    end
  elseif s.state == "wait" then
    s.wait = s.wait - 1
    if s.wait == 0 then s.state = "off" end
  elseif s.state == "off" then
    if s.x < -0x40 then s.done = true else s.x = s.x - 20 end
  end
end

local function start_sprite(fx)
  fx.sprite = { x = 0x140, y = 0x50, state = "on" }
end

local function finish(fx)
  ShowMon._fx = nil
  if fx.posed then player().fieldMoveAnim = 0 end
  if fx.onDone then fx.onDone() end
end

-- pokefirered/src/field_effect.c:2601
local function step_outdoors(fx)
  local ph = fx.phase
  if ph == 1 or ph == 2 then
    fx.phase = ph + 1
  elseif ph == 3 then
    fx.hofs = fx.hofs - 16
    fx.winL = math.max(0, fx.winL - 16)
    fx.winT = math.max(0x28, fx.winT - 2)
    fx.winB = math.min(0x78, fx.winB + 2)
    if fx.winL == 0 and fx.winT == 0x28 and fx.winB == 0x78 then
      start_sprite(fx)
      fx.phase = 4
    end
  elseif ph == 4 then
    fx.hofs = fx.hofs - 16
    if fx.sprite and fx.sprite.done then fx.phase = 5 end
  elseif ph == 5 then
    fx.hofs = fx.hofs - 16
    fx.winT = math.min(0x50, fx.winT + 6)
    fx.winB = math.max(0x51, fx.winB - 6)
    if fx.winT == 0x50 and fx.winB == 0x51 then fx.phase = 6 end
  elseif ph == 6 then
    fx.phase = 7
    fx.hidden = true
  elseif ph == 7 then
    finish(fx)
    return
  end
  step_sprite(fx)
end

-- pokefirered/src/field_effect.c:2757
local function step_indoors(fx)
  local ph = fx.phase
  if ph == 1 or ph == 2 then
    fx.phase = ph + 1
  elseif ph == 3 then
    if fx.revealed >= 16 then
      start_sprite(fx)
      fx.phase = 4
    else
      fx.revealed = fx.revealed + 1
    end
    fx.hofs = fx.hofs - 16
  elseif ph == 4 then
    fx.hofs = fx.hofs - 16
    if fx.sprite and fx.sprite.done then fx.phase = 5 end
  elseif ph == 5 then
    fx.hofs = fx.hofs - 16
    fx.phase = 6
  elseif ph == 6 then
    fx.hofs = fx.hofs - 16
    if fx.cleared >= 16 then fx.phase = 7 else fx.cleared = fx.cleared + 1 end
  elseif ph == 7 then
    finish(fx)
    return
  end
  step_sprite(fx)
end

function ShowMon.step()
  local fx = ShowMon._fx
  if not fx then return end
  local P = player()
  if fx.phase == "pose" then
    fx.poseWait = fx.poseWait - 1
    if fx.poseWait > 0 then return end
    fx.phase = 1
  end
  if fx.posed then P.fieldMoveAnim = 1 end
  if fx.outdoors then step_outdoors(fx) else step_indoors(fx) end
end

local function draw_band(img, x0, x1, y0, y1, hofs)
  if not img or x1 <= x0 or y1 <= y0 then return end
  ShowMon._quad = ShowMon._quad or love.graphics.newQuad(0, 0, 1, 1, BAND_W, BAND_H)
  local q = ShowMon._quad
  local sx = x0
  while sx < x1 do
    local u = (sx + hofs) % BAND_W
    local w = math.min(x1 - sx, BAND_W - u)
    q:setViewport(u, y0 - BAND_TOP, w, y1 - y0, BAND_W, BAND_H)
    love.graphics.draw(img, q, sx, y0)
    sx = sx + w
  end
end

function ShowMon.draw()
  local fx = ShowMon._fx
  if not fx or fx.phase == "pose" or not (love and love.graphics) then return end
  love.graphics.setColor(1, 1, 1, 1)
  if fx.outdoors then
    if not fx.hidden and fx.phase >= 3 then
      local y0 = math.max(fx.winT, BAND_TOP)
      local y1 = math.min(fx.winB, BAND_TOP + BAND_H)
      draw_band(band_image("outdoors"), fx.winL, SCREEN_W, y0, y1, fx.hofs)
    end
  else
    local img = band_image("indoors")
    if fx.phase == 3 or fx.phase == 4 or fx.phase == 5 then
      local x1 = (fx.phase == 3 and fx.revealed < 16) and math.min(SCREEN_W, 16 * (fx.revealed + 1)) or SCREEN_W
      local x0 = (fx.phase == 3 and fx.revealed < 16) and 16 or 0
      draw_band(img, x0, x1, BAND_TOP, BAND_TOP + BAND_H, fx.hofs)
    elseif fx.phase == 6 then
      draw_band(img, math.min(SCREEN_W, 16 * fx.cleared), SCREEN_W, BAND_TOP, BAND_TOP + BAND_H, fx.hofs)
    end
  end
  local s = fx.sprite
  if s and not s.done then
    local Pokemon = require("src.core.game3.pokemon")
    local entry = Pokemon.frontPic and Pokemon.frontPic(fx.picSpecies, nil, fx.shiny, fx.personality)
    if entry and entry.image then
      local w, h = entry.w or 64, entry.h or 64
      love.graphics.draw(entry.image, math.floor(s.x - w / 2), math.floor(s.y - h / 2))
    end
  end
end

return ShowMon
