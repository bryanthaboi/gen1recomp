-- ../pokecrystal/engine/items/item_effects.asm:529-536
-- ../pokecrystal/engine/pokedex/new_pokedex_entry.asm:36-50
-- ../pokecrystal/engine/pokedex/pokedex.asm:1386-1407
-- ../pokecrystal/engine/gfx/cgb_layouts.asm:930-939

local U = require("tests.drivers.util")
local Mon = require("src.battle.gen2.Mon")
local Chrome = require("src.ui.gen2.Chrome")
local GbcPalette = require("src.render.GbcPalette")
local Palettes = require("src.world.gen2.Palettes")

return function(game)
  local dir = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gen2_catch_new_dex_entry"
  local version = tostring(game.save.version)
  local failures = 0
  local function check(ok, label, detail)
    print((ok and "PASS " or "FAIL ") .. label .. (detail ~= nil and (" " .. tostring(detail)) or ""))
    if not ok then failures = failures + 1 end
    return ok
  end
  local function finish()
    print((failures == 0 and "PASS" or "FAIL") .. " gen2_catch_new_dex_entry " .. version
      .. " failures=" .. failures)
    love.event.quit(failures == 0 and 0 or 1)
    while true do U.wait(10) end
  end

  local function sampler(screen, path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local bytes = f:read("*a")
    f:close()
    local image = love.image.newImageData(love.filesystem.newFileData(bytes, "shot.png"))
    local winW, winH = love.graphics.getDimensions()
    local ratio = image:getWidth() / winW
    local scale = screen:battlePanelScale(winW, winH)
    local ox, oy = Chrome.fitOrigin(winW, winH, scale)
    local function pixel(px, py)
      local ix = math.floor((ox + (px + 0.5) * scale) * ratio)
      local iy = math.floor((oy + (py + 0.5) * scale) * ratio)
      local r, g, b = image:getPixel(ix, iy)
      return r * 255, g * 255, b * 255
    end
    local function count(tx0, ty0, tx1, ty1, match)
      local n = 0
      for py = ty0 * 8, ty1 * 8 + 7 do
        for px = tx0 * 8, tx1 * 8 + 7 do
          if match(pixel(px, py)) then n = n + 1 end
        end
      end
      return n
    end
    return count
  end

  local function ink(r, g, b) return r < 250 or g < 250 or b < 250 end
  local function near(color)
    return function(r, g, b)
      return math.abs(r - color[1]) <= 6 and math.abs(g - color[2]) <= 6
        and math.abs(b - color[3]) <= 6
    end
  end

  local function checkCartScreen(tag, screen, path, mon)
    check(not screen:wideLayout(), tag .. " standard 160x144 layout")
    local count = sampler(screen, path)
    if not check(count ~= nil, tag .. " shot readable") then return end
    check(screen.captureScreen == "dexpic", tag .. " captureScreen is dexpic",
      tostring(screen.captureScreen))
    local pic = count(1, 1, 7, 7, ink)
    check(pic > 0, tag .. " front pic tiles (1,1)-(7,7) hold ink", pic)
    local right = count(8, 0, 19, 6, ink) + count(8, 7, 13, 11, ink)
    check(right == 0, tag .. " tiles (8,0)-(19,11) outside the YES/NO box are cleared"
      .. " (no enemy pic, no player HUD)", right)
    local row0 = count(0, 0, 19, 0, ink)
    check(row0 == 0, tag .. " row 0 is cleared (no enemy name box)", row0)
    local lower = count(0, 8, 7, 11, ink)
    check(lower == 0, tag .. " tiles (0,8)-(7,11) are cleared (no player backpic)", lower)
    if not (mon and GbcPalette.mode == "gbc") then return end
    local own = Palettes.monColors(screen.palettes, mon.species, mon.shiny)
    local other = Palettes.monColors(screen.palettes, mon.species, not mon.shiny)
    local ownHits, otherHits = 0, 0
    for index = 2, 3 do
      ownHits = ownHits + count(1, 1, 7, 7, near(GbcPalette.color(own, index)))
      otherHits = otherHits + count(1, 1, 7, 7, near(GbcPalette.color(other, index)))
    end
    local label = mon.shiny and "shiny" or "normal"
    check(ownHits > 0, tag .. " pic wears the " .. label .. " frontpic palette", ownHits)
    check(otherHits == 0, tag .. " and not the other one", otherHits)
  end

  U.wait(45)
  local world = game.world
  if not check(world and world.map, "world booted") then return finish() end
  game.save.engineFlags = game.save.engineFlags or {}
  game.save.engineFlags[11] = true

  local function battleScreen()
    for _ = 1, 900 do
      local top = game.stack:top()
      if top and top.battle then return top end
      U.wait(1)
    end
  end

  local function catchArm(opts)
    local tag, species = opts.tag, opts.species
    local shot = function(name) return dir .. "/dexpic_" .. tag .. "_" .. name .. ".png" end
    game.save.party = {}
    for i = 1, opts.full and 6 or 1 do
      game.save.party[i] = Mon.new(game.data, "CYNDAQUIL", 30)
    end
    game.save.pokedex = game.save.pokedex or { seen = {}, caught = {} }
    game.save.pokedex.caught[species] = nil
    local wild = Mon.new(game.data, species, 3, { shiny = opts.shiny or false })
    if not check(world:startBattle({ wild = wild }), tag .. " battle started") then return end
    local screen = battleScreen()
    if not check(screen ~= nil, tag .. " battle screen up") then return end
    for _ = 1, 400 do
      if screen.phase == "menu" and #screen.queue == 0 and not screen.anim then break end
      U.tap(game, "a")
      U.wait(3)
    end
    screen:useItem("MASTER_BALL")

    local dexSeen, dexShot, askShot, pcShot = false, false, false, false
    for _ = 1, 3000 do
      local top = game.stack:top()
      if screen.phase == "done" then break end
      if top and top ~= screen and top.newEntry then
        dexSeen = true
        if not dexShot then
          dexShot = true
          U.wait(20)
          U.still(game, shot("01_dex_entry"))
        end
        U.tap(game, "a")
        U.wait(10)
      elseif top ~= screen then
        break
      else
        local msg = type(screen.message) == "string" and screen.message:gsub("\n", " ") or ""
        if screen.phase == "ask-nickname" then
          if (screen.messageTimer or 0) > 0 then
            U.tap(game, "a")
          else
            if not askShot then
              askShot = true
              U.wait(10)
              U.still(game, shot("02_ask_nickname_over_pic"))
              checkCartScreen(tag .. " nickname question", screen,
                shot("02_ask_nickname_over_pic"), wild)
            end
            U.tap(game, "b")
          end
        elseif opts.full and not pcShot and msg:find("BILL's PC", 1, true) then
          pcShot = true
          U.wait(30)
          U.still(game, shot("03_pc_line_over_pic"))
          if not screen.captureFade then
            checkCartScreen(tag .. " PC line", screen, shot("03_pc_line_over_pic"))
          end
        elseif (screen.messageTimer or 0) > 0 then
          U.tap(game, "a")
        end
      end
      U.wait(1)
    end
    check(dexSeen, tag .. " NewPokedexEntry screen opened")
    check(askShot, tag .. " nickname question reached")
    if opts.full then check(pcShot, tag .. " PC line reached") end
    for _ = 1, 600 do
      local top = game.stack:top()
      if not (top and top.battle) then break end
      U.tap(game, "a")
      U.wait(1)
    end
    U.wait(30)
  end

  game.save.inventory = { MASTER_BALL = 10 }
  catchArm({ tag = "party", species = "PIDGEY" })
  catchArm({ tag = "pc", species = "HOOTHOOT", full = true })
  catchArm({ tag = "shiny", species = "SENTRET", shiny = true })
  finish()
end
