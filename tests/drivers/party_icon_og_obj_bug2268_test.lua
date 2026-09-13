--   POKEPORT_DRIVER=tests/drivers/party_icon_og_obj_bug2268_test.lua POKEPORT_IDENTITY=red-sep04 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or os.getenv("POKEPORT_SHOT_DIR") or "/tmp/shots"
  local GameVersion = require("src.core.GameVersion")
  local PaletteFX = require("src.render.PaletteFX")
  local PartyMenu = require("src.ui.PartyMenu")
  local Pokemon = require("src.pokemon.Pokemon")
  local Screens = require("src.ui.Screens")

  local tag = GameVersion.isBlue() and "blue" or "red"
  local ok = true
  local function check(label, pass)
    U.log(pass and "PASS" or "FAIL", label)
    if not pass then ok = false end
    return pass
  end

  game.save.options = game.save.options or {}
  local prevColors = game.save.options.colors
  local function setColors(mode)
    game.save.options.colors = mode
    PaletteFX.setMode(mode)
  end

  local function finish()
    setColors(prevColors or "gbc")
    U.log(ok and "PASS party_icon_og_obj_2268" or "FAIL party_icon_og_obj_2268")
    love.event.quit(ok and 0 or 1)
    while true do coroutine.yield() end
  end

  local function shotPixels(path)
    if not U.shot(game, path) then return nil end
    local f = io.open(path, "rb")
    if not f then return nil end
    local bytes = f:read("*a")
    f:close()
    local good, id = pcall(function()
      return love.image.newImageData(love.filesystem.newFileData(bytes, "shot.png"))
    end)
    return good and id or nil
  end

  local function count(id, c)
    if not (id and c) then return -1 end
    local n = 0
    local w, h = id:getDimensions()
    for y = 0, h - 1 do
      for x = 0, w - 1 do
        local r, g, b = id:getPixel(x, y)
        if math.abs(r * 255 - c[1]) < 6 and math.abs(g * 255 - c[2]) < 6
           and math.abs(b * 255 - c[3]) < 6 then
          n = n + 1
        end
      end
    end
    return n
  end

  local SPECIES = { "NIDOKING", "PIDGEOTTO", "CLEFAIRY", "BULBASAUR", "OMANYTE" }
  local party = {}
  local mirrored = 0
  for i, species in ipairs(SPECIES) do
    party[i] = Pokemon.new(game.data, species, 30)
    local def = game.data.pokemon[species]
    local name = def and def.dex and game.data.icons and game.data.icons.byDex
      and game.data.icons.byDex[def.dex]
    if PartyMenu.mirrorsIcon(name) then mirrored = mirrored + 1 end
  end
  game.save.party = party
  game.save.player.name = game.save.player.name or "RED"

  setColors("ogred")
  check("COLORS is OG (" .. PaletteFX.modeLabel() .. ")", PaletteFX.mode == "ogred")
  check("OG mode takes the OBJ bake path on " .. tag, PaletteFX.usesSpriteObp())

  U.teleport(game, "PALLET_TOWN", 10, 12, "down")
  U.wait(10)
  Screens.push(game, "PartyMenu", {})
  U.wait(16)
  local pm = game.stack:top()
  if not check("the party list is open", getmetatable(pm) == PartyMenu) then
    return finish()
  end

  local redraws = PaletteFX.uiSpriteRedraws()
  local flips = 0
  for _, r in ipairs(redraws) do
    if r.sx == -1 then flips = flips + 1 end
  end
  U.log("  ui redraws:", #redraws, "flipped:", flips, "mirrored icons:", mirrored)
  check("every icon replays after the zone pass",
        #redraws == mirrored * 2 + (#party - mirrored))
  check("each mirrored icon replays its OAM_XFLIP half", flips == mirrored)

  local objRamp = GameVersion.isBlue() and PaletteFX.GBC_OBJ_BLUE or PaletteFX.GBC_OBJ
  local bgRamp = PaletteFX.ogBg()
  local id = shotPixels(DIR .. "/2268_01_party_og_" .. tag .. ".png")
  check("OG party screenshot captured", id ~= nil)
  if id then
    local obj1 = count(id, objRamp[2])
    local bg2 = count(id, bgRamp[3])
    U.log("  OBJ shade-1 pixels:", obj1, " BG shade-2 (HP bar) pixels:", bg2)
    check("icons wear the boot-ROM OBJ shade 1 on " .. tag, obj1 > 0)
    check("HP bars keep the BG ramp", bg2 > 0)
  end

  setColors("gbc")
  U.wait(10)
  check("SGB records no OBJ replays", #PaletteFX.uiSpriteRedraws() == 0)
  local sgb = shotPixels(DIR .. "/2268_02_party_sgb_" .. tag .. ".png")
  check("SGB party screenshot captured", sgb ~= nil)
  if sgb and not GameVersion.isBlue() then
    check("SGB icons never wear the boot-ROM OBJ green",
          count(sgb, PaletteFX.GBC_OBJ[2]) == 0)
  end

  return finish()
end
