local U = require("tests.drivers.util")
local F = require("tests.drivers.em_fa_util")

local NAME = "gen3_replace_block_defined_p3"
local S = F.new(NAME, os.getenv("POKEPORT_SHOT_DIR") or "/tmp/" .. NAME)

local SPOTS = {
  firered = { map = "FR_PALLET_TOWN", x = 10, y = 10, tx = 10, ty = 8 },
  leafgreen = { map = "FR_PALLET_TOWN", x = 10, y = 10, tx = 10, ty = 8 },
  emerald = { map = "EM_LITTLEROOT_TOWN", x = 10, y = 10, tx = 12, ty = 13 },
  ruby = { map = "RU_LITTLEROOT_TOWN", x = 10, y = 10, tx = 12, ty = 13 },
  sapphire = { map = "SA_LITTLEROOT_TOWN", x = 10, y = 10, tx = 12, ty = 13 },
}

local function renderField(game)
  local FieldView = require("src.core.game3.field_view")
  local canvas = love.graphics.newCanvas(240, 160)
  love.graphics.push("all")
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 0, 0, 1)
  love.graphics.origin()
  FieldView.draw(game, 240, 160, { skipActors = true })
  love.graphics.setCanvas()
  love.graphics.pop()
  return canvas:newImageData()
end

local function cellPixels(img, ox, oy)
  local out = {}
  for y = 0, 15 do
    for x = 0, 15 do
      local r, g, b = img:getPixel(ox + x, oy + y)
      out[#out + 1] = { r, g, b }
    end
  end
  return out
end

local function diffCount(a, b)
  local n = 0
  for i = 1, #a do
    local p, q = a[i], b[i]
    if math.abs(p[1] - q[1]) + math.abs(p[2] - q[2]) + math.abs(p[3] - q[3]) > 0.01 then n = n + 1 end
  end
  return n
end

local function richestMid(pair, behaviors, skip)
  local NativePack = require("src.import.gba.native_pack")
  local Extract = require("src.import.gba.extract_island1")
  local Dataset = require("src.core.game3.dataset")
  local idx = NativePack.decodeIdx(Dataset.cache():read(Extract.NATIVE_ROOT .. "/" .. pair .. "/mids.idx"))
  local pixels = idx and idx.pixels
  local best, bestScore = nil, -1
  for i, mid in ipairs(idx and idx.midIds or {}) do
    if behaviors[mid] ~= nil and mid ~= skip and pixels then
      local seen, n = {}, 0
      for p = 1, 256 do
        local v = pixels[(i - 1) * 256 + p]
        if v and v ~= 0 and not seen[v] then seen[v] = true; n = n + 1 end
      end
      if n > bestScore or (n == bestScore and mid < best) then best, bestScore = mid, n end
    end
  end
  return best
end

return function(game)
  if not F.boot(game, S) then return S.finish() end
  local Map = require("src.core.game3.map")
  local Field = require("src.core.game3.field")
  local NativeTileset = require("src.core.game3.tileset_native")
  local Interaction = require("src.core.game3.scripting.interaction_scripts")
  local UnifiedWorld = require("src.mods.UnifiedWorld")
  local version = os.getenv("POKEPORT_VERSION")
  local spot = SPOTS[version]
  if not S.check(spot ~= nil, "a test spot for " .. tostring(version)) then return S.finish() end

  S.check(F.goTo(game, spot.map, spot.x, spot.y, "down"), "standing on " .. spot.map)
  local Space = require("src.core.game3.scripting.space")
  if Space.vm and Space.vm:isRunning() then Space.vm:halt(true) end
  Field.unlock()
  U.wait(20)

  local def = Map.currentDef()
  local pair = def and (def.pair or (def.midLayout and def.midLayout.pair))
  local behaviors = Interaction.behaviors[pair]
  if not S.check(behaviors ~= nil, "pair " .. tostring(pair) .. " has defined metatiles") then return S.finish() end
  local undefined
  for mid = 0, 1023 do
    if behaviors[mid] == nil then undefined = mid; break end
  end
  if not S.check(undefined ~= nil, "pair " .. pair .. " leaves metatile " .. tostring(undefined) .. " undefined")
  then return S.finish() end
  local ts = NativeTileset.get(pair)
  S.check(ts ~= nil and NativeTileset.slotFor(ts, undefined) == nil,
    "slotFor answers nil for undefined metatile " .. undefined)

  local tx, ty = spot.tx, spot.ty
  local camX = math.floor(spot.x * 16 + 8 - 120)
  local camY = math.floor(spot.y * 16 + 8 - 80)
  local ox, oy = tx * 16 - camX, ty * 16 - camY
  local world = UnifiedWorld.new(function() return game end, 3, version, NAME)
  local current = world:current()
  local before = world:activeBlockAt(current.mapId, tx, ty)
  S.check(before ~= nil, "cell " .. tx .. "," .. ty .. " holds metatile " .. tostring(before))
  local base = cellPixels(renderField(game), ox, oy)

  local ok, err = world:replaceBlock(tx, ty, undefined)
  S.check(ok == nil and type(err) == "string" and err:find("unknown block id", 1, true) ~= nil,
    "mod.world:replaceBlock refuses undefined metatile " .. undefined .. " (" .. tostring(err) .. ")")
  S.check(world:activeBlockAt(current.mapId, tx, ty) == before, "the refused cell keeps metatile " .. tostring(before))
  S.check(Field.metatileOverrideAt(Map.current, tx, ty) == nil, "the refusal leaves no override behind")
  S.check(diffCount(base, cellPixels(renderField(game), ox, oy)) == 0, "the refused cell draws as before")

  ok, err = world:replaceBlock(tx, ty, 1024)
  S.check(ok == nil, "mod.world:replaceBlock refuses metatile 1024 (" .. tostring(err) .. ")")

  Field.setMetatile(tx, ty, 0, false)
  local zero = cellPixels(renderField(game), ox, oy)
  Field.setMetatile(tx, ty, undefined, false)
  local hole = cellPixels(renderField(game), ox, oy)
  local flat = {}
  for i = 1, #zero do flat[i] = zero[1] end
  if diffCount(zero, flat) == 0 then
    S.note("metatile 0 on " .. pair .. " is one flat color, so a hole and metatile 0 look alike")
  else
    local zeroInk = diffCount(zero, hole)
    S.check(zeroInk > 0, "an undefined metatile written below the mod layer does not draw as metatile 0 ("
      .. zeroInk .. " px differ)")
  end
  Field.setMetatile(tx, ty, before, false)
  S.check(diffCount(base, cellPixels(renderField(game), ox, oy)) == 0, "restoring the cell draws it as before")

  local defined = richestMid(pair, behaviors, before)
  S.check(defined ~= nil, "pair " .. pair .. " defines metatile " .. tostring(defined))
  ok, err = world:replaceBlock(tx, ty, defined)
  S.check(ok == true, "mod.world:replaceBlock accepts defined metatile " .. tostring(defined) .. " (" .. tostring(err) .. ")")
  S.check(world:activeBlockAt(current.mapId, tx, ty) == defined, "the cell now holds metatile " .. tostring(defined))
  U.wait(4)
  local changed = diffCount(base, cellPixels(renderField(game), ox, oy))
  S.check(changed > 0, "the defined metatile is drawn (" .. changed .. " px changed)")
  S.still(game, ("p3_01_%s_defined_metatile_%d_drawn.png"):format(version, defined))

  return S.finish()
end
