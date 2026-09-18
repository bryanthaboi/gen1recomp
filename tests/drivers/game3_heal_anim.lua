-- POKEPORT_DRIVER=tests/drivers/game3_heal_anim.lua POKEPORT_VERSION=firered love .
local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp"

local failures = 0
local function result(ok, label)
  if ok then
    print("PASS " .. label)
  else
    failures = failures + 1
    print("FAIL " .. label)
  end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS game3_heal_anim")
    love.event.quit(0)
  else
    print("FAIL game3_heal_anim failures=" .. failures)
    love.event.quit(1)
  end
end

return function(game)
  U.wait(30)
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(120)

  local TALK = os.getenv("HEAL_TALK") == "1"
  local HX = tonumber(os.getenv("HEAL_X") or "7") or 7
  -- pokefirered/data/layouts/PokemonCenter_1F/map.bin
  local HY = tonumber(os.getenv("HEAL_Y") or (TALK and "6" or "4")) or 4
  local Map = require("src.core.game3.map")
  Map.load(nil, game, "FR_VIRIDIAN_CITY_POKEMON_CENTER_1F", { x = HX, y = HY, facing = "up" })
  game.session.x, game.session.y, game.session.facing = HX, HY, "up"
  U.wait(60)
  local P = require("src.core.game3.player")
  local function where(tag)
    print(("%s player px=%s py=%s tile=%s,%s facing=%s"):format(tag, tostring(P.px),
      tostring(P.py), tostring(math.floor((P.px or 0) / 16)),
      tostring(math.floor((P.py or 0) / 16)), tostring(P.facing)))
  end
  where("spawn")
  if TALK then
    for _ = 1, 4 do
      U.hold(game, "up", 6)
      U.wait(14)
      where("walk")
      if math.floor((P.py or 0) / 16) <= 4 then break end
    end
  end

  local Zoom = require("src.render.Zoom")
  Zoom.offset = tonumber(os.getenv("HEAL_ZOOM") or "0") or 0
  if game.options then game.options.zoom = Zoom.offset end
  U.wait(2)

  local Heal = require("src.core.game3.pokecenter_heal")
  local FieldEffects = require("src.core.game3.field_effects")

  print("probe cache=" .. tostring(Heal._cache ~= nil)
    .. " fldeff=" .. tostring(Heal.FLDEFF))

  local function readProbe(name, ext)
    local c = Heal._cache
    if not (c and c.read) then return "no-cache" end
    for _, rel in ipairs({
      "data/generated/gba/field_effects/" .. name .. ext,
      "field_effects/" .. name .. ext,
    }) do
      local ok, data = pcall(c.read, c, rel)
      if ok and data then return rel .. " len=" .. tostring(#data) end
    end
    return "MISS"
  end
  print("probe idx  " .. readProbe("pokeball_glow", ".idx"))
  print("probe pal  " .. readProbe("pokeball_glow", ".pal"))
  print("probe mon  " .. readProbe("pokemoncenter_monitor", ".rgba"))

  U.shot(game, DIR .. "/heal_00_baseline.png")
  if TALK then
    where("pre-talk")
    for _ = 1, 40 do
      if Heal._fx then break end
      U.tap(game, "a")
      U.wait(16)
    end
    result(Heal._fx ~= nil, "talk_started_heal")
    where("healing")
  else
    result(FieldEffects.doFieldEffect(Heal.FLDEFF), "doFieldEffect_started")
  end
  U.wait(1)
  if Heal._fx then
    print("coords monitorTL=" .. tostring(Heal._fx.monitorX) .. "," .. tostring(Heal._fx.monitorY))
  end
  do
    local R = require("src.render.Renderer")
    local SP = require("src.core.ScreenPosition")
    local vw, vh = R:worldViewSize()
    print(("geom vw=%d vh=%d fit=%d uiw=%d uih=%d spmode=%s")
      :format(vw, vh, R:fitScale(), select(1, R:uiSize()), select(2, R:uiSize()),
        tostring(SP.mode)))
    local Z = require("src.render.Zoom")
    print(("geom2 uiScale=%s worldScale=%s zoomOff=%s")
      :format(tostring(R:uiScale()), tostring(Z.scale(R:fitScale())), tostring(Z.offset)))
    local ok, rects = pcall(function() return R:frameRects() end)
    if ok and rects then
      print(("rects ox=%s oy=%s vpw=%s vph=%s Ux=%s Uy=%s Sp=%s Up=%s")
        :format(tostring(rects.ox), tostring(rects.oy), tostring(rects.vpw),
          tostring(rects.vph), tostring(rects.Ux), tostring(rects.Uy),
          tostring(rects.Sp), tostring(rects.Up)))
    end
  end
  if Heal._ballScreenTl then
    local bx, by = Heal._ballScreenTl(0)
    print("coords ball0TL=" .. tostring(bx) .. "," .. tostring(by))
  end
  U.wait(2)
  print("after start fx=" .. tostring(Heal._fx ~= nil)
    .. " active=" .. tostring(Heal.isActive and Heal.isActive()))

  -- One pass to let a draw run, so ensure_gfx has been exercised.
  U.wait(4)
  print("gfx ballIdx=" .. tostring(Heal._ballIdx ~= nil)
    .. " monImg=" .. tostring(Heal._monImg ~= nil))
  result(Heal._ballIdx ~= nil and Heal._monImg ~= nil, "gfx_loaded")

  -- Count frames where the effect reports itself active, shooting the beats.
  local shots = {
    { 10, "10_balls_appear" },
    { 30, "30_flash_a" },
    { 55, "55_flash_b" },
    { 80, "80_monitor_fill" },
    { 120, "120_late" },
  }
  local si = 1
  local sawFx = false
  for f = 1, 140 do
    if Heal._fx then sawFx = true end
    if si <= #shots and f == shots[si][1] then
      U.shot(game, DIR .. "/heal_" .. shots[si][2] .. ".png")
      print("shot " .. shots[si][2]
        .. " fx=" .. tostring(Heal._fx ~= nil)
        .. " state=" .. tostring(Heal._fx and Heal._fx.state)
        .. " counter=" .. tostring(Heal._fx and Heal._fx.counter))
      si = si + 1
    end
    U.wait(1)
  end
  result(sawFx, "fx_alive_during_run")

  finish()
end
