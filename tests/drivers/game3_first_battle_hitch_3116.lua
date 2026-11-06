local U = require("tests.drivers.util")

return function(game)
  local fails = 0
  local function result(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then fails = fails + 1 end
  end
  local function finish()
    print(fails == 0 and "PASS all" or ("FAIL " .. fails .. " checks"))
    love.event.quit(fails == 0 and 0 or 1)
  end

  local VERSION = require("src.core.GameVersion").get()
  local SHINY = os.getenv("HITCH_SHINY") ~= "0"
  local DIR = os.getenv("POKEPORT_SHOT_DIR")
  local now = love.timer.getTime

  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "NICK", gender = 0 })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local Ui = require("src.core.game3.battle.ui")
  local Anim = require("src.core.game3.battle.anim")
  local Map = require("src.core.game3.map")
  local Dataset = require("src.core.game3.dataset")
  local C = require("src.core.game3.constants").of(VERSION)
  local session = Runtime.getSession()
  result(session ~= nil, "field session exists")
  if not session then finish() return end

  local frlg = VERSION == "firered" or VERSION == "leafgreen"
  local mapId = frlg and "FR_ROUTE1" or ((VERSION == "emerald") and "EM_ROUTE101" or "RS_ROUTE101")
  local okMap, mapErr = pcall(function() Map.load(nil, game, mapId, { x = 10, y = 12, facing = "down" }) end)
  result(okMap, "load " .. mapId .. " " .. tostring(mapErr or ""))
  U.wait(360)

  local animReads, packReads, images = 0, 0, 0
  local cache = Dataset.cache()
  local read = cache.read
  cache.read = function(self, rel, ...)
    if type(rel) == "string" and rel:find("battle_anims/", 1, true) then
      animReads = animReads + 1
      if rel:find("battle_anims/pack.lua", 1, true) then packReads = packReads + 1 end
    end
    return read(self, rel, ...)
  end
  local newImage = love.graphics.newImage
  love.graphics.newImage = function(...)
    images = images + 1
    return newImage(...)
  end
  local moveLaunched = 0
  local launchMove = Anim.launchMove
  Anim.launchMove = function(...)
    moveLaunched = moveLaunched + 1
    return launchMove(...)
  end
  print("[driver] pack parsed before battle " .. tostring(Anim._packLoaded == true))

  session.party = {}
  local starter = frlg and "BULBASAUR" or "TREECKO"
  Party.giveMon(session, C.species.byName["SPECIES_" .. starter], 5, starter)
  local lead = session.party[1]
  if SHINY then
    lead.otId, lead.personality, lead.otSecretId = 0, 0, 0
    lead.shiny, lead.isShiny = true, true
  end
  local foe = C.species.byName.SPECIES_ZIGZAGOON or C.species.byName.SPECIES_RATTATA

  local lastTap, f = 0, 0
  local function at_command()
    return Battle.isActive() and Battle._phase == "command" and Ui._mode == "menu"
  end

  local function window(label, stopFn, maxTicks, onTick)
    local r0, p0, i0 = animReads, packReads, images
    local prev, worst = now(), 0
    for _ = 1, maxTicks do
      if stopFn() then break end
      if onTick then onTick() end
      if Ui.dialogPending and Ui.dialogPending() and f - lastTap >= 14 then
        lastTap = f
        U.tap(game, "a")
      else
        U.wait(1)
      end
      f = f + 1
      local t = now()
      worst = math.max(worst, (t - prev) * 1000)
      prev = t
    end
    local r, p, i = animReads - r0, packReads - p0, images - i0
    print(string.format("[driver] %s %s anim cache reads=%d pack reads=%d newImage=%d worst tick=%.1fms",
      VERSION, label, r, p, i, worst))
    return r, i
  end

  local ok, err = BattleBridge.startWild(Runtime._mod, game, { species = foe, level = 2 }, {})
  result(ok == true, "wild battle started " .. tostring(err or ""))
  if not ok then finish() return end

  local tag = SHINY and "shiny send-out" or "send-out"
  local r1, i1 = window(tag, at_command, 6000)
  result(at_command(), "reached command menu")
  result(r1 < 20, tag .. " reads under 20 anim files (" .. r1 .. ")")
  result(i1 < 20, tag .. " creates under 20 images (" .. i1 .. ")")

  U.wait(20)
  U.tap(game, "a")
  U.wait(20)
  result(Ui._mode == "moves", "move menu open")
  U.tap(game, "a")
  local AnimSprites = require("src.core.game3.battle.anim_sprites")
  local function impact_live()
    local tags = Anim._pack and Anim._pack.tags
    local info = tags and rawget(tags, "IMPACT")
    local img = info and rawget(info, "image")
    if not (img and AnimSprites._pool) then return false end
    for i = 1, AnimSprites.MAX do
      local s = AnimSprites._pool[i]
      if s.active and s.visible and s.image == img then return true end
    end
    return false
  end
  local shot, sawImpact = false, false
  local r2, i2 = window("first move", function()
    return (moveLaunched > 0 and at_command()) or not Battle.isActive()
  end, 6000, function()
    if moveLaunched > 0 and not sawImpact and impact_live() then
      sawImpact = true
      if DIR then shot = U.still(game, DIR .. "/3116a_" .. VERSION .. "_first_move_impact_splat.png") end
    end
  end)
  result(moveLaunched > 0, "first move anim launched")
  result(sawImpact, "first move draws a sprite from the IMPACT sheet")
  result(r2 < 20, "first move reads under 20 anim files (" .. r2 .. ")")
  result(i2 < 20, "first move creates under 20 images (" .. i2 .. ")")
  result(packReads <= 1, "pack.lua read at most once (" .. packReads .. ")")
  local impact = Anim._pack and Anim._pack.tags and rawget(Anim._pack.tags, "IMPACT")
  result(impact ~= nil and rawget(impact, "image") ~= nil, "IMPACT sheet hydrated by the move")
  if SHINY then
    local stars = Anim._pack and Anim._pack.tags and rawget(Anim._pack.tags, "GOLD_STARS")
    result(stars ~= nil and rawget(stars, "image") ~= nil, "GOLD_STARS sheet hydrated by the sparkle")
  end
  if DIR then result(shot, "first move anim shot") end

  if Battle.isActive() then Battle.abort("run") end
  for _ = 1, 600 do
    if not Battle.isActive() then break end
    U.wait(1)
  end
  finish()
end
