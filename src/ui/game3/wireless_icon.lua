local WirelessIcon = {}

WirelessIcon.CACHE = "data/generated/gba/union_room/"
WirelessIcon.SIZE = 16
-- pokefirered/src/link_rfu_3.c:955
WirelessIcon.X = 231
WirelessIcon.Y = 8

-- pokefirered/src/link_rfu_3.c:448
WirelessIcon.ANIMS = {
  ["3bars"] = { { 1, 5 }, { 2, 5 }, { 3, 5 }, { 4, 10 }, { 3, 5 }, { 2, 5 } },
  searching = { { 1, 10 }, { 5, 10 } },
  error = { { 6, 10 }, { 1, 10 } },
}

WirelessIcon.STATE_ANIM = {
  online = "3bars",
  ticket = "searching",
  connecting = "searching",
  reconnecting = "searching",
  error = "error",
}

WirelessIcon.LINK_MAPS = {
  FR_UNION_ROOM = true,
  FR_TRADE_CENTER = true,
  FR_BATTLE_COLOSSEUM_2P = true,
  FR_BATTLE_COLOSSEUM_4P = true,
  FR_RECORD_CORNER = true,
  FR_TWO_ISLAND_JOYFUL_GAME_CORNER = true,
}

WirelessIcon._visible = true
WirelessIcon._frames = 0
WirelessIcon._acc = 0
WirelessIcon._anim = nil
WirelessIcon._forced = nil
WirelessIcon._image = nil
WirelessIcon._quads = nil
WirelessIcon._lastTime = nil
WirelessIcon._frameCount = 0

local function connectState()
  local Connect = package.loaded["src.online.Connect"]
  if Connect and Connect.state then
    local ok, s = pcall(Connect.state)
    if ok and s and s ~= "offline" then return s end
  end
  local Client = package.loaded["src.online.Client"]
  if Client and Client.state then
    local ok, s = pcall(Client.state)
    if ok then return s end
  end
  return "offline"
end

WirelessIcon.connectState = connectState

function WirelessIcon.setVisible(visible)
  WirelessIcon._visible = visible and true or false
end

function WirelessIcon.isVisible()
  return WirelessIcon._visible
end

function WirelessIcon.force(anim)
  WirelessIcon._forced = anim
end

function WirelessIcon.anim()
  if WirelessIcon._forced ~= nil then return WirelessIcon._forced or nil end
  return WirelessIcon.STATE_ANIM[connectState()]
end

function WirelessIcon.update(dt)
  WirelessIcon._acc = WirelessIcon._acc + (tonumber(dt) or 0) * 60
  local whole = math.floor(WirelessIcon._acc)
  if whole > 0 then
    WirelessIcon._acc = WirelessIcon._acc - whole
    WirelessIcon._frames = WirelessIcon._frames + whole
  end
end

function WirelessIcon.frameFor(anim, frames)
  local cmds = WirelessIcon.ANIMS[anim]
  if not cmds then return nil end
  local total = 0
  for _, c in ipairs(cmds) do total = total + c[2] end
  local t = math.floor(tonumber(frames) or 0) % total
  for _, c in ipairs(cmds) do
    if t < c[2] then return c[1] end
    t = t - c[2]
  end
  return cmds[1][1]
end

function WirelessIcon.frame()
  local anim = WirelessIcon.anim()
  if anim ~= WirelessIcon._anim then
    WirelessIcon._anim = anim
    WirelessIcon._frames = 0
  end
  if not anim then return nil end
  return WirelessIcon.frameFor(anim, WirelessIcon._frames)
end

-- pokefirered/src/link_rfu_3.c:492
function WirelessIcon.load()
  if WirelessIcon._image then return WirelessIcon._image end
  local Dataset = require("src.core.game3.dataset")
  local cache = Dataset.cache()
  local manifestSrc = cache:read(WirelessIcon.CACHE .. "manifest.lua")
  assert(type(manifestSrc) == "string", "union_room/manifest.lua missing from the cache")
  local manifest = assert(load(manifestSrc, "@union_room/manifest.lua", "t", {}))()
  local entry = assert(manifest.wireless_icon, "union_room manifest has no wireless_icon")
  local w, h = tonumber(entry.width), tonumber(entry.height)
  local fh = tonumber(entry.frame_h) or WirelessIcon.SIZE
  local rgba = cache:read(WirelessIcon.CACHE .. "wireless_icon.rgba")
  assert(type(rgba) == "string" and #rgba == w * h * 4, "union_room/wireless_icon.rgba missing")
  local data = love.image.newImageData(w, h, "rgba8", rgba)
  local image = love.graphics.newImage(data)
  image:setFilter("nearest", "nearest")
  local quads = {}
  local frames = tonumber(entry.frames) or math.floor(h / fh)
  for i = 0, frames - 1 do
    quads[i] = love.graphics.newQuad(0, i * fh, w, fh, w, h)
  end
  WirelessIcon._image = image
  WirelessIcon._quads = quads
  WirelessIcon._frameCount = frames
  return image
end

function WirelessIcon.draw(cx, cy)
  if not WirelessIcon._visible then return false end
  if not (love and love.graphics and love.image) then return false end
  local index = WirelessIcon.frame()
  if not index then return false end
  local image = WirelessIcon.load()
  local quad = WirelessIcon._quads[index]
  if not quad then return false end
  cx = tonumber(cx) or WirelessIcon.X
  cy = tonumber(cy) or WirelessIcon.Y
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(image, quad, cx - WirelessIcon.SIZE / 2, cy - WirelessIcon.SIZE / 2)
  return true
end

function WirelessIcon.onLinkMap(mapId)
  if type(mapId) ~= "string" then return false end
  if WirelessIcon.LINK_MAPS[mapId] then return true end
  if require("src.core.game3.link.union_room").isUnionMap(mapId) then return true end
  return mapId:match("_POKEMON_CENTER_2F$") ~= nil
end

local function currentMap()
  local Space = package.loaded["src.core.game3.scripting.space"]
  if Space and type(Space.mapId) == "string" then return Space.mapId end
  local Map = package.loaded["src.core.game3.map"]
  return Map and Map.current or nil
end

-- pokefirered/src/overworld.c:1829
function WirelessIcon.drawField()
  if not WirelessIcon.onLinkMap(currentMap()) then
    WirelessIcon._lastTime = nil
    return false
  end
  local Stack = package.loaded["src.ui.game3.stack"]
  local top = Stack and Stack.top and Stack.top()
  if top and top.hideBelow then return false end
  local now = love and love.timer and love.timer.getTime and love.timer.getTime() or nil
  if now and WirelessIcon._lastTime then
    WirelessIcon.update(math.min(now - WirelessIcon._lastTime, 0.25))
  end
  WirelessIcon._lastTime = now
  return WirelessIcon.draw(WirelessIcon.X, WirelessIcon.Y)
end

function WirelessIcon.reset()
  WirelessIcon._visible = true
  WirelessIcon._frames = 0
  WirelessIcon._acc = 0
  WirelessIcon._anim = nil
  WirelessIcon._forced = nil
  WirelessIcon._lastTime = nil
end

return WirelessIcon
