-- ../pokecrystal/engine/battle/core.asm:4744-4747
-- ../pokecrystal/engine/battle/core.asm:6400-6404
-- ../pokecrystal/engine/items/item_effects.asm:573-607
-- ../pokecrystal/engine/items/item_effects.asm:609-682
-- ../pokecrystal/engine/items/item_effects.asm:704-709
-- ../pokecrystal/engine/battle/core.asm:5049-5058

local U = require("tests.drivers.util")
local Mon = require("src.battle.gen2.Mon")

return function(game)
  local dir = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gen2_catch_hud_name"
  local version = tostring(game.save.version)
  local failures = 0
  local function check(ok, label, detail)
    print((ok and "PASS " or "FAIL ") .. label .. (detail ~= nil and (" " .. tostring(detail)) or ""))
    if not ok then failures = failures + 1 end
    return ok
  end
  local function finish()
    print((failures == 0 and "PASS" or "FAIL") .. " gen2_catch_hud_name " .. version
      .. " failures=" .. failures)
    love.event.quit(failures == 0 and 0 or 1)
    while true do U.wait(10) end
  end

  local function darkPixels(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local bytes = f:read("*a")
    f:close()
    local image = love.image.newImageData(love.filesystem.newFileData(bytes, "shot.png"))
    local w, h = image:getDimensions()
    local dark = 0
    for y = 0, h - 1 do
      for x = 0, w - 1 do
        local r, g, b = image:getPixel(x, y)
        if r < 0.2 and g < 0.2 and b < 0.2 then dark = dark + 1 end
      end
    end
    return dark
  end

  local Chrome = require("src.ui.gen2.Chrome")
  local GbcPalette = require("src.render.GbcPalette")
  local function panelSampler(screen, path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local bytes = f:read("*a")
    f:close()
    local image = love.image.newImageData(love.filesystem.newFileData(bytes, "shot.png"))
    local winW, winH = love.graphics.getDimensions()
    local ratio = image:getWidth() / winW
    local scale = screen:battlePanelScale(winW, winH)
    local ox, oy = Chrome.fitOrigin(winW, winH, scale)
    return function(tx0, ty0, tx1, ty1)
      local inks = {}
      for py = ty0 * 8, ty1 * 8 + 7 do
        for px = tx0 * 8, tx1 * 8 + 7 do
          local ix = math.floor((ox + (px + 0.5) * scale) * ratio)
          local iy = math.floor((oy + (py + 0.5) * scale) * ratio)
          local r, g, b = image:getPixel(ix, iy)
          local key = ("%d,%d,%d"):format(math.floor(r * 255 + 0.5),
            math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
          if key ~= "255,255,255" then inks[key] = (inks[key] or 0) + 1 end
        end
      end
      return inks
    end
  end
  local function colorKey(c)
    return c and ("%d,%d,%d"):format(c[1], c[2], c[3]) or "none"
  end
  local function onlyInk(inks, want)
    local count, stray = 0, nil
    for key, n in pairs(inks) do
      if key == want then count = count + n else stray = key end
    end
    return count, stray
  end

  local function checkFadeFrame(tag, screen, path)
    local pals = game.data.gen2Palettes or {}
    if not check(GbcPalette.mode == "gbc", tag .. " fade frame drawn in GBC colour",
        GbcPalette.mode) then return end
    if not check(not screen:wideLayout(), tag .. " fade frame in the standard layout") then
      return
    end
    local sample = panelSampler(screen, path)
    if not check(sample ~= nil, tag .. " fade frame readable") then return end
    local hp = colorKey(pals.hpBar and pals.hpBar.green and pals.hpBar.green[1])
    local regions = {
      { "enemy name", 1, 0, 9, 0 },
      { "enemy level and gender", 6, 1, 9, 1 },
      { "enemy HUD frame", 1, 3, 9, 3 },
      { "player name and level", 10, 7, 18, 8 },
      { "player HP digits", 10, 10, 18, 10 },
    }
    for _, r in ipairs(regions) do
      local count, stray = onlyInk(sample(r[2], r[3], r[4], r[5]), hp)
      check(count > 0 and stray == nil,
        tag .. " BGP $40 turns the " .. r[1] .. " into HP palette colour 1 " .. hp,
        ("count=%d stray=%s"):format(count, tostring(stray)))
    end
    local text = pals.battleText
    if not check(text ~= nil, tag .. " PAL_BATTLE_BG_TEXT is in the palettes cache") then
      return
    end
    local want = colorKey(text[2])
    local count, stray = onlyInk(sample(0, 12, 19, 17), want)
    if want == "255,255,255" then
      check(stray == nil, tag .. " BGP $40 turns the PC line box into colour 1 " .. want,
        ("stray=%s"):format(tostring(stray)))
    else
      check(count > 0 and stray == nil,
        tag .. " BGP $40 turns the PC line box into colour 1 " .. want,
        ("count=%d stray=%s"):format(count, tostring(stray)))
    end
  end

  U.wait(45)
  local world = game.world
  if not check(world and world.map, "world booted") then return finish() end

  local function battleScreen()
    for _ = 1, 900 do
      local top = game.stack:top()
      if top and top.battle then return top end
      U.wait(1)
    end
  end

  local function catchArm(opts)
    local tag, species = opts.tag, opts.species
    local shot = function(name) return dir .. "/p6_" .. tag .. "_" .. name .. ".png" end
    game.save.party = {}
    for i = 1, opts.full and 6 or 1 do
      game.save.party[i] = Mon.new(game.data, "CYNDAQUIL", 30)
    end
    game.save.pokedex = game.save.pokedex or { seen = {}, caught = {} }
    game.save.pokedex.caught[species] = true
    local wild = Mon.new(game.data, species, 3)
    if not check(world:startBattle({ wild = wild }), tag .. " battle started") then return end
    local screen = battleScreen()
    if not check(screen ~= nil, tag .. " battle screen up") then return end
    for _ = 1, 400 do
      if screen.phase == "menu" and #screen.queue == 0 and not screen.anim then break end
      U.tap(game, "a")
      U.wait(3)
    end
    if opts.payDay then screen.battle.payDay = opts.payDay end
    screen:useItem("MASTER_BALL")

    local answered, named = false, false
    local askHud, askShot = nil, false
    local redrawn, hudNick = 0, 0
    local fadeShot, fadeScreen = false, nil
    local stepShots = {}
    local clearedShot, clearedMessage = false, "unset"
    local pcScreen, pcHud, pcText = nil, nil, nil
    local payScreen, payText = nil, nil
    for _ = 1, 3000 do
      local top = game.stack:top()
      if screen.phase == "done" then break end
      if top ~= screen and not (top and top.maxLength) then break end
      if top and top.maxLength and top ~= screen then
        if not named then
          named = true
          U.wait(20)
          for ch in ("AAAA"):gmatch(".") do top:addCharacter(ch) end
          U.wait(5)
          U.still(game, shot("01_naming_typed"))
          top:accept()
        end
      else
        local enemy = screen:activeMon("enemy")
        if answered and not screen.captureScreen then redrawn = redrawn + 1 end
        if not screen.captureScreen and screen.showEnemyHud
            and screen:enemyHudName(enemy) ~= species then
          hudNick = hudNick + 1
        end
        local fade = screen.captureFade
        if fade and screen.captureScreen == "naming" then
          local step = math.floor(fade / 8) + 1
          if step >= 2 and step <= 3 and not stepShots[step] and fade % 8 >= 2 then
            stepShots[step] = shot(("02_naming_fade_bgp_%s"):format(step == 2 and "40" or "00"))
            U.still(game, stepShots[step])
          end
        end
        if screen.captureFade and not fadeShot and screen.captureFade >= 8 then
          fadeShot = true
          fadeScreen = screen.captureScreen or "battle"
          local bgp = screen:exitFadeBgp()
          U.still(game, shot("02_fade_" .. fadeScreen))
          if fadeScreen == "battle" then
            if check(bgp == 0x40, tag .. " battle fade shot at BGP $40", bgp) then
              checkFadeFrame(tag, screen, shot("02_fade_" .. fadeScreen))
            end
          end
        end
        if screen.captureScreen == "cleared" and not clearedShot then
          clearedShot = true
          clearedMessage = screen.message
          U.still(game, shot("03_cleared"))
        end
        local msg = type(screen.message) == "string" and screen.message:gsub("\n", " ") or ""
        if not pcText and msg:find("BILL's PC", 1, true) then
          pcText, pcScreen = msg, screen.captureScreen or "battle"
          pcHud = screen:enemyHudName(enemy)
          U.wait(30)
          U.still(game, shot("02_pc_line_over_" .. pcScreen))
          local sample = pcScreen == "battle" and not screen:wideLayout()
            and panelSampler(screen, shot("02_pc_line_over_" .. pcScreen))
          if sample then
            local count = onlyInk(sample(1, 0, 9, 0), "0,0,0")
            check(count > 0, tag .. " sampler finds the black HUD name at full BGP", count)
          end
        end
        if not payText and msg:find("picked up", 1, true) then
          payText, payScreen = msg, screen.captureScreen or "battle"
          U.wait(30)
          U.still(game, shot("04_payday_over_" .. payScreen))
        end
        if screen.phase == "ask-nickname" then
          if (screen.messageTimer or 0) > 0 then
            U.tap(game, "a")
          else
            if not askShot then
              askShot = true
              askHud = screen:enemyHudName(enemy)
              U.still(game, shot("01_ask_hud_species"))
            end
            answered = true
            U.tap(game, opts.yes and "a" or "b")
          end
        elseif (screen.messageTimer or 0) > 0 then
          U.tap(game, "a")
        end
      end
      U.wait(1)
    end

    check(askHud == species, tag .. " HUD reads the species under the nickname question", askHud)
    check(wild.nickname == (opts.yes and "AAAA" or nil), tag .. " caught mon name",
      wild.nickname)
    if opts.yes or not opts.full then
      check(redrawn == 0, tag .. " battle scene never redrawn after the nickname answer",
        redrawn)
    end
    check(hudNick == 0, tag .. " enemy HUD never reads the nickname", hudNick)
    check(clearedShot, tag .. " ClearTilemap leaves a cleared screen")
    if opts.yes then
      check(fadeShot, tag .. " RotateThreePalettesRight fade shown")
      check(stepShots[2] and stepShots[3], tag .. " naming fade steps $40 and $00 captured")
      if stepShots[2] then
        local dark = darkPixels(stepShots[2])
        check(dark == 0, tag .. " naming fade at BGP $40 holds no colour-3 black", dark)
      end
      if stepShots[3] then
        local dark = darkPixels(stepShots[3])
        check(dark == 0, tag .. " naming fade at BGP $00 is all white", dark)
      end
    end
    if opts.full then
      check(pcText ~= nil, tag .. " BallSentToPCText shown", pcText)
      check(pcScreen == (opts.yes and "naming" or "battle"),
        tag .. " BallSentToPCText prints over the screen the answer left", pcScreen)
      check(pcHud == species, tag .. " HUD latch reads the species under the PC line", pcHud)
      check(fadeScreen == (opts.yes and "naming" or "battle"),
        tag .. " the PC line fades with that screen", fadeScreen)
    else
      check(pcText == nil, tag .. " a party catch prints no PC line", pcText)
      if opts.yes then
        check(fadeScreen == "naming", tag .. " the naming screen fades out", fadeScreen)
      else
        check(not fadeShot, tag .. " NO clears with no fade")
      end
    end
    if opts.payDay then
      check(payScreen == "cleared", tag .. " Pay Day prints on the cleared screen", payScreen)
    else
      check(clearedMessage == nil, tag .. " the cleared screen holds no text", clearedMessage)
    end
    for _ = 1, 600 do
      local top = game.stack:top()
      if not (top and top.battle) then break end
      U.tap(game, "a")
      U.wait(1)
    end
    U.wait(30)
  end

  game.save.inventory = { MASTER_BALL = 10 }
  catchArm({ tag = "party_yes", species = "RATTATA", yes = true })
  catchArm({ tag = "party_no", species = "SENTRET", yes = false })
  catchArm({ tag = "payday", species = "PIDGEY", yes = true, payDay = 40 })
  catchArm({ tag = "pc_yes", species = "SENTRET", yes = true, full = true })
  catchArm({ tag = "pc_no", species = "HOOTHOOT", yes = false, full = true })
  finish()
end
