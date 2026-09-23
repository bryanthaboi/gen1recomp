-- pokefirered/src/field_specials.c:2133
local Extract = require("src.import.gba.extract_island1")

local LeagueLighting = {}

LeagueLighting.task = nil
LeagueLighting._data = nil

-- pokefirered/include/constants/flags.h:12
local FLAG_TEMP_2 = 0x2
local FLAG_TEMP_3 = 0x3
local FLAG_TEMP_4 = 0x4
local FLAG_TEMP_5 = 0x5

-- pokefirered/src/field_specials.c:2143
local CHAMPIONS_ROOM = "FR_POKEMON_LEAGUE_CHAMPIONS_ROOM"

local function data()
  if LeagueLighting._data then return LeagueLighting._data end
  local Dataset = require("src.core.game3.dataset")
  local rel = (Extract.CACHE_ROOT or "data/generated/gba") .. "/league/lighting.lua"
  local src = Dataset.cache():read(rel)
  if not src then return nil end
  local chunk = load(src, "@" .. rel, "t", {})
  local ok, val = pcall(chunk)
  if ok and type(val) == "table" then LeagueLighting._data = val end
  return LeagueLighting._data
end

local function flag(id)
  local Space = package.loaded["src.core.game3.scripting.space"]
  local Flags = require("src.core.game3.scripting.flags")
  return Flags.getFlag(Space and Space.store, nil, id) == true
end

local function currentMap()
  local Map = package.loaded["src.core.game3.map"]
  return Map and Map.current
end

local function currentPair()
  local Map = package.loaded["src.core.game3.map"]
  local def = Map and Map.currentDef and Map.currentDef()
  return def and (def.pair or (def.midLayout and def.midLayout.pair))
end

local function apply(st, index)
  local NativeTileset = require("src.core.game3.tileset_native")
  local pal = st.set.pals[index + 1]
  if not pal then return end
  st.pair = st.pair or currentPair()
  if not st.pair then return end
  NativeTileset.setSlotPalette(st.pair, st.slot, pal)
  st.patched = true
end

local function restore(st)
  if not (st and st.patched and st.pair) then return end
  local NativeTileset = require("src.core.game3.tileset_native")
  NativeTileset.resetSlotPalette(st.pair, st.slot)
  st.patched = false
end

local function paused()
  local Fade = package.loaded["src.ui.game3.fade"]
  if Fade and Fade.isActive and Fade.isActive() then return true end
  local Battle = package.loaded["src.core.game3.battle"]
  if Battle and Battle.isActive and Battle.isActive() then return true end
  return false
end

-- pokefirered/src/field_specials.c:2160
-- pokefirered/src/field_specials.c:2187
function LeagueLighting.tick(st)
  if currentMap() ~= st.mapId then
    restore(st)
    if LeagueLighting.task == st then LeagueLighting.task = nil end
    return true
  end
  if st.phase == "cancel" then
    if flag(FLAG_TEMP_4) then
      apply(st, #st.set.pals - 1)
      st.phase = "held"
    end
    return false
  end
  if st.phase ~= "run" then return false end
  if paused() or not flag(FLAG_TEMP_2) or flag(FLAG_TEMP_5) then return false end
  st.timer = st.timer - 1
  if st.timer ~= 0 then return false end
  st.index = st.index + 1
  if st.index == st.steps then st.index = 0 end
  st.timer = st.set.timers[st.index + 1]
  apply(st, st.index)
  return false
end

-- pokefirered/src/field_specials.c:2133
function LeagueLighting.start(mapId)
  local d = data()
  if not d then return false end
  -- pokefirered/src/overworld.c:2105
  restore(LeagueLighting.task)
  LeagueLighting.stop()
  local set = mapId == CHAMPIONS_ROOM and d.champion or d.e4
  local st = {
    mapId = mapId or currentMap(),
    set = set,
    slot = tonumber(d.palette_slot) or 7,
    steps = #set.timers,
    index = 0,
    timer = set.timers[1],
  }
  if flag(FLAG_TEMP_3) then
    st.phase = "cancel"
  else
    st.phase = "run"
    apply(st, 0)
  end
  local Task = require("src.core.game3.task")
  st.handle = Task.spawn(function() return LeagueLighting.tick(st) end)
  LeagueLighting.task = st
  return true
end

-- pokefirered/src/field_specials.c:2205
function LeagueLighting.stop()
  local st = LeagueLighting.task
  if not st then return end
  if st.handle then
    require("src.core.game3.task").cancel(st.handle.id)
  end
  LeagueLighting.task = nil
end

function LeagueLighting.reset()
  restore(LeagueLighting.task)
  LeagueLighting.stop()
end

function LeagueLighting.frame()
  local st = LeagueLighting.task
  return st and st.index, st and st.phase
end

return LeagueLighting
