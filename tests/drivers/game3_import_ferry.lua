local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_import_ferry"

-- pokefirered/include/constants/vars.h:165
local VAR_MAP_SCENE_CINNABAR_ISLAND = 0x4071
-- pokefirered/include/constants/vars.h:170
local VAR_MAP_SCENE_ONE_ISLAND_POKEMON_CENTER_1F = 0x4076
-- pokefirered/include/constants/flags.h:114
local FLAG_HIDE_CINNABAR_BILL = 0x062

local CINNABAR = "FR_CINNABAR_ISLAND"
local ONE_HARBOR = "SEVII_ONE_ISLAND_HARBOR"
local ONE_ISLAND = "SEVII_ONE_ISLAND"

local ROOT = "data/generated/gba/seagallop"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS import_ferry")
    love.event.quit(0)
  else
    print("FAIL import_ferry failures=" .. failures)
    love.event.quit(1)
  end
end

local function bgr555(lo, hi)
  local c = lo + hi * 256
  local r5 = c % 32
  local g5 = math.floor(c / 32) % 32
  local b5 = math.floor(c / 1024) % 32
  return math.floor(r5 * 255 / 31 + 0.5),
    math.floor(g5 * 255 / 31 + 0.5),
    math.floor(b5 * 255 / 31 + 0.5)
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end

  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Dataset = require("src.core.game3.dataset")
  local Map = require("src.core.game3.map")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Player = require("src.core.game3.player")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local cache = Dataset.cache()
  local function readRel(rel)
    local ok, data = pcall(function() return cache:read(ROOT .. "/" .. rel) end)
    if ok then return data end
    return nil
  end

  -- src/seagallop.c:41
  local EXPECT = {
    { "water.4bpp", 1312 }, { "water.gbapal", 32 },
    { "wb_tilemap.bin", 2048 }, { "eb_tilemap.bin", 2048 },
    { "ferry.4bpp", 1280 }, { "ferry_wake.gbapal", 32 }, { "wake.4bpp", 2048 },
  }
  local blobs = {}
  local missing = {}
  for _, want in ipairs(EXPECT) do
    local data = readRel(want[1])
    if type(data) ~= "string" or #data ~= want[2] then
      missing[#missing + 1] = want[1]
    else
      blobs[want[1]] = data
    end
  end
  result(#missing == 0, "every seagallop blob loads from the cache, missing=" ..
    (#missing == 0 and "none" or table.concat(missing, ",")))

  local wb = readRel("wb.rgba")
  local eb = readRel("eb.rgba")
  result(type(wb) == "string" and #wb == 256 * 256 * 4,
    "wb.rgba is the 256x256 westbound water (" .. tostring(wb and #wb) .. ")")
  result(type(eb) == "string" and #eb == 256 * 256 * 4,
    "eb.rgba is the 256x256 eastbound water (" .. tostring(eb and #eb) .. ")")
  result(wb ~= nil and eb ~= nil and wb ~= eb,
    "the two crossings are different water")

  local ferry = readRel("ferry.rgba")
  result(type(ferry) == "string" and #ferry == 64 * 40 * 4,
    "ferry.rgba is the 64x40 Seagallop sprite (" .. tostring(ferry and #ferry) .. ")")
  local wake = readRel("wake.rgba")
  result(type(wake) == "string" and #wake == 32 * 128 * 4,
    "wake.rgba is the 32x128 wake strip (" .. tostring(wake and #wake) .. ")")

  if blobs["water.4bpp"] and blobs["water.gbapal"] and blobs["wb_tilemap.bin"] and wb then
    local gfx, pal, map = blobs["water.4bpp"], blobs["water.gbapal"], blobs["wb_tilemap.bin"]
    local bad, checked = 0, 0
    for _, cell in ipairs({ { 0, 0 }, { 5, 3 }, { 17, 11 }, { 31, 31 } }) do
      local tx, ty = cell[1], cell[2]
      local mi = (ty * 32 + tx) * 2 + 1
      local entry = map:byte(mi) + map:byte(mi + 1) * 256
      local tileId = entry % 1024
      local hflip = math.floor(entry / 1024) % 2 == 1
      local vflip = math.floor(entry / 2048) % 2 == 1
      for row = 0, 7 do
        for col = 0, 7 do
          local b = gfx:byte(tileId * 32 + row * 4 + math.floor(col / 2) + 1) or 0
          local idx = (col % 2 == 0) and (b % 16) or math.floor(b / 16)
          local sx = hflip and (7 - col) or col
          local sy = vflip and (7 - row) or row
          local r, g, bl = bgr555(pal:byte(idx * 2 + 1), pal:byte(idx * 2 + 2))
          local o = ((ty * 8 + sy) * 256 + tx * 8 + sx) * 4
          checked = checked + 1
          if wb:byte(o + 1) ~= r or wb:byte(o + 2) ~= g or wb:byte(o + 3) ~= bl
            or wb:byte(o + 4) ~= 255 then
            bad = bad + 1
          end
        end
      end
    end
    result(bad == 0 and checked == 256,
      "the baked water matches the cached tiles and palette (" .. bad .. "/" .. checked .. " wrong)")
  end

  local function ctx() return Space.vm and Space.vm.ctx end
  local function setVar(id, v) Flags.setVar(Space.store, ctx(), id, v) end
  local function mapId() return Space.mapId end

  local function place(x, y, facing)
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing
    if game.session then
      game.session.x, game.session.y, game.session.facing = x, y, facing
    end
  end

  local function goTo(id, x, y, facing)
    Map.load(nil, game, id, { x = x, y = y, facing = facing or "down" })
    place(x, y, facing or "down")
    U.wait(90)
  end

  -- pokefirered/data/maps/OneIsland_PokemonCenter_1F/scripts.inc:117
  setVar(VAR_MAP_SCENE_ONE_ISLAND_POKEMON_CENTER_1F, 1)
  goTo(CINNABAR, 20, 5, "down")
  -- pokefirered/data/maps/CinnabarIsland_Gym/scripts.inc:61
  setVar(VAR_MAP_SCENE_CINNABAR_ISLAND, 1)
  -- pokefirered/data/maps/CinnabarIsland_Gym/scripts.inc:62
  Flags.setFlag(Space.store, ctx(), FLAG_HIDE_CINNABAR_BILL, false)
  goTo(CINNABAR, 20, 5, "down")
  U.wait(60)
  local billRan = (Space.vm and Space.vm:isRunning()) or (Message.isOpen and Message.isOpen())
  result(billRan, "the ON_FRAME Bill scene started on Cinnabar Island")
  for _ = 1, 12 do
    if Message.isOpen and Message.isOpen() then break end
    U.wait(10)
  end
  U.wait(60)
  U.shot(game, DIR .. "/import_ferry_01_cinnabar_bill.png")

  local ticks = 0
  while ticks < 3600 do
    if Space.mapId ~= CINNABAR then break end
    local running = Space.vm and Space.vm:isRunning()
    local open = Message.isOpen and Message.isOpen()
    if not running and not open and not Choice.active then break end
    U.tap(game, "a")
    U.wait(12)
    ticks = ticks + 12
  end
  U.wait(180)
  for _ = 1, 40 do
    if mapId() == ONE_ISLAND then break end
    U.tap(game, "a")
    U.wait(20)
  end
  print("[driver] after the Bill ferry: map=" .. tostring(mapId()) ..
    " at (" .. tostring(Player.cellX) .. "," .. tostring(Player.cellY) .. ")")
  result(mapId() == ONE_ISLAND or mapId() == ONE_HARBOR,
    "the Cinnabar ferry crossed to One Island, map=" .. tostring(mapId()))
  U.wait(30)
  U.shot(game, DIR .. "/import_ferry_02_one_island.png")

  if wb and love.image and love.image.newImageData then
    local okImg, err = pcall(function()
      local id = love.image.newImageData(256, 256, "rgba8", wb)
      local png = id:encode("png")
      local f = io.open(DIR .. "/import_ferry_03_water_layer.png", "wb")
      f:write(png:getString())
      f:close()
    end)
    result(okImg == true, "the imported water layer encodes to a PNG " .. tostring(err or ""))
  end

  finish()
end
