-- Driver: in a dark cave FadePal2 writes rOBP0 as well as rBGP, so the player
-- is a black silhouette, and ADVANCED bakes the shift into its atlas instead
-- of veiling the world (#383).  home/fade.asm:3-19,66 LoadGBPal indexes
-- FadePal4 - wMapPalOffset; home/overworld.asm:500,535,790 sets the offset.
--   POKEPORT_DRIVER=tests/drivers/rock_tunnel_dark_bake_bug383_test.lua \
--     POKEPORT_IDENTITY=bug383 POKEPORT_TOUCH=0 SHOT_DIR=/tmp/shots383 love .
-- No POKEPORT_SPEED: fast-forward desynchronizes audio.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Probe = dofile("tests/drivers/shot_probe.lua")
  local PaletteFX = require("src.render.PaletteFX")
  local Pokemon = require("src.pokemon.Pokemon")
  local Zoom = require("src.render.Zoom")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots383"

  local fails = 0
  local function check(ok, msg)
    U.log(ok and "PASS" or "FAIL", msg)
    if not ok then fails = fails + 1 end
    return ok
  end
  local function rgb(c)
    return c and ("(%d,%d,%d)"):format(c[1], c[2], c[3]) or "nil"
  end
  local function ramp(p)
    if not p then return "nil" end
    local s = {}
    for i = 1, 4 do s[i] = rgb(p[i]) end
    return table.concat(s, " ")
  end
  local function sameCol(a, b)
    return a and b and a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
  end
  local function samePal(a, b)
    if not a or not b then return false end
    for i = 1, 4 do
      if not sameCol(a[i], b[i]) then return false end
    end
    return true
  end

  game.save.flags.EVENT_GOT_STARTER = true
  game.save.inventory.BOULDERBADGE = true
  local mon = Pokemon.new(game.data, "PIKACHU", 30)
  mon.moves = { { id = "FLASH", pp = 15 } }
  game.save.party = { mon }
  game.save.options = game.save.options or {}
  game.save.options.textSpeed = 1
  local vol = game.save.options.sfxVol
  if vol == 0 then
    U.log("sfxVol is 0: the FLASH blink and menu beeps are silent, turn SFX up",
          "in OPTION before judging anything by ear")
  else
    U.log("sfxVol =", tostring(vol))
  end

  -- ---- the arithmetic, before anything is on screen ----------------------
  local darkDef = game.data.field.darkMaps
  local listed = false
  for _, m in ipairs(darkDef and darkDef.maps or {}) do
    if m == "ROCK_TUNNEL_1F" then listed = true end
  end
  check(listed, "ROCK_TUNNEL_1F is in field.darkMaps.maps")
  local BGP = PaletteFX.DARK_BGP
  check(BGP[0] == 2 and BGP[1] == 3 and BGP[2] == 3 and BGP[3] == 3,
        "DARK_BGP is FadePal2's `dc 3,3,3,2`")

  local litObp, litGroup = PaletteFX.dmgObj()
  check(litObp == PaletteFX.OBP0_SHADES,
        "with nothing armed dmgObj still hands back the lit OBP0 ramp by identity")
  check(PaletteFX.setDarkWorld(true) == true,
        "setDarkWorld reports the change, so the caller knows to rebake")
  check(PaletteFX.setDarkWorld(true) == false,
        "and reports nothing on a repeat, so walking a dark floor never rebuilds")
  check(PaletteFX.darkKey() == "#dark",
        "the bake cache key carries the flag")
  local darkObp, darkGroup = PaletteFX.dmgObj()
  U.log("OBP0 lit:", ramp(litObp))
  U.log("OBP0 dark:", ramp(darkObp))
  check(samePal(darkObp, { litObp[3], litObp[4], litObp[4], litObp[4] }),
        "rOBP0 `dc 3,3,3,2` collapses every OBJ colour a sprite draws to shade 3")
  check(darkGroup ~= litGroup,
        "and its bake sits in its own cache group, not over the lit one")
  local ogDark = PaletteFX.ogObj()
  check(samePal(ogDark, { PaletteFX.GBC_OBJ[3], PaletteFX.GBC_OBJ[4],
                          PaletteFX.GBC_OBJ[4], PaletteFX.GBC_OBJ[4] }),
        "OG RED's boot-ROM greens go with it (colours 1/2/3 all black)")
  PaletteFX.setDarkWorld(false)
  check(PaletteFX.dmgObj() == PaletteFX.OBP0_SHADES and PaletteFX.darkKey() == "",
        "clearing the flag hands the lit ramp and the lit cache key back")
  check(game.overworld == nil or game.overworld.darkNeedsOverlay == nil,
        "the screen-space veil is gone: no darkNeedsOverlay left to ask")

  -- ---- reach the moment ---------------------------------------------------
  -- pokered data/maps/objects/RockTunnel1F.asm: the Route 10 entrance is
  -- warp_event 15, 3, so two cells south of it is floor that cannot
  -- re-trigger the warp, with the ladder and the sign both on screen.
  local MAP, STAND = "ROCK_TUNNEL_1F", { x = 15, y = 5, facing = "down" }

  local function enter(flashLit)
    game.save.flashLit = flashLit or nil
    U.teleport(game, MAP, STAND.x, STAND.y, STAND.facing)
    U.wait(12)
    local ow = game.overworld
    if ow and ow.map and not ow.map:isWalkableCell(STAND.x, STAND.y) then
      local found
      for r = 1, 8 do
        for dy = -r, r do
          for dx = -r, r do
            local cx, cy = STAND.x + dx, STAND.y + dy
            if not found and ow.map:isWalkableCell(cx, cy)
               and not ow.map:warpAtCell(cx, cy) then
              found = { x = cx, y = cy }
            end
          end
        end
        if found then break end
      end
      if found then
        U.log(("(%d,%d) is not floor any more -- standing on"):format(
                STAND.x, STAND.y), found.x, found.y)
        STAND.x, STAND.y = found.x, found.y
        game.save.flashLit = flashLit or nil
        U.teleport(game, MAP, STAND.x, STAND.y, STAND.facing)
        U.wait(12)
        ow = game.overworld
      end
    end
    return ow
  end

  game.save.options.colors = "gbc"
  PaletteFX.setMode("gbc")
  local ow = enter(nil)
  check(ow ~= nil and ow.map and ow.map.id == MAP, "player is inside " .. MAP)
  check(ow ~= nil and ow.dark == true and PaletteFX.darkWorld() == true,
        "the floor is dark with no FLASH used, and the bake flag is armed with it")

  -- The cavern floor tiles carry no shade-0 pixels, so `dc 3,3,3,2` leaves them
  -- solid shade 3 -- "the floor is completely black" -- while wall, sign and
  -- ladder tiles keep shade-0 pixels that land on shade 2 and stay legible.
  -- That is the reporter's reference image, and no uniform veil can produce it.
  local FLOOR_TILES = { 0x15, 0x16, 0x17, 0x18, 0x19, 0x1a, 0x1b, 0x2f, 0x34,
                        0x3d, 0x3e, 0x3f }
  local ts = ow and ow.map and ow.map.tileset
  if ts and love.image and love.image.newImageData then
    local okImg, art = pcall(love.image.newImageData, ts.image)
    if okImg and art then
      local perRow = ts.tilesPerRow or 16
      local lightest, worst = 0, nil
      for _, t in ipairs(FLOOR_TILES) do
        local bx, by = (t % perRow) * 8, math.floor(t / perRow) * 8
        for y = by, by + 7 do
          for x = bx, bx + 7 do
            local r = math.floor(select(1, art:getPixel(x, y)) * 255 + 0.5)
            if r > lightest then lightest, worst = r, t end
          end
        end
      end
      U.log(("cavern floor tiles: lightest pixel is %d (tile 0x%02x)")
              :format(lightest, worst or 0))
      check(lightest < 255,
            "no cavern floor tile has a shade-0 pixel, so the shift blacks it out")
    else
      U.log("WARN could not read", tostring(ts.image), "-- floor art unchecked")
    end
  end

  -- Camera:follow parks the sprite at (vw/2 - 16, vh/2 - 12) in world-canvas
  -- pixels and endFrame blits that canvas centred at Zoom.scale(fitScale), so
  -- the player's torso is a fixed box in the captured frame.
  local function playerRect(shot)
    local wc = game.renderer and game.renderer.worldCanvas
    if not (shot and wc) then return nil end
    local W, H = shot:getDimensions()
    local vw, vh = wc:getWidth(), wc:getHeight()
    local sp = Zoom.scale(game.renderer:fitScale())
    local ox = math.floor((W - vw * sp) / 2)
    local oy = math.floor((H - vh * sp) / 2)
    local x0, y0 = vw / 2 - 16, vh / 2 - 12
    return { (ox + (x0 + 4) * sp) / (W - 1), (oy + (y0 + 6) * sp) / (H - 1),
             (ox + (x0 + 12) * sp) / (W - 1), (oy + (y0 + 14) * sp) / (H - 1) }
  end

  -- Count the colours the player would still be wearing if only rBGP had been
  -- ported, inside his own 16x16 -- his cell is floor, so none of them can
  -- come from the ground under him.
  local function spriteProbe(label, shot, telltale)
    local rect = playerRect(shot)
    if not (shot and rect) then
      U.log("WARN no pixel probe for", label, "-- judge the player by eye")
      return
    end
    local counts, total = Probe.count(shot, telltale, 1, rect)
    local parts, leaked = {}, 0
    for name, n in pairs(counts) do
      parts[#parts + 1] = ("%s=%d"):format(name, n)
      leaked = leaked + n
    end
    table.sort(parts)
    U.log(("probe[%s player %d px] %s"):format(label, total,
          table.concat(parts, "  ")))
    U.log("   tones on him:", Probe.fmt(Probe.top(shot, 3, 1, rect)))
    check(leaked == 0, label .. ": the player is black, not lit or half-lit")
  end

  local CAVE = PaletteFX.pal(game.data, "CAVE")
  U.log("CAVE palette:", ramp(CAVE))

  -- ---- ADVANCED / RED++, the mode in the report --------------------------
  local pack = PaletteFX.gbcPack()
  if not pack then
    U.log("WARN data/palettes_gbc is absent; the ADVANCED half cannot be shown")
  else
    game.save.options.colors = "redpp"
    PaletteFX.setMode("redpp")
    ow = enter(nil)
    U.wait(30)
    U.shot(game, DIR .. "/bug383_1_dark_redpp.png")
    local tsId = ow.map.tileset.id
    local lit = pack.world.groupColors[tsId]
    local shifted = PaletteFX.worldGroupColors(game.data, tsId, ow.map.id, nil)
    local allShifted = lit ~= nil and shifted ~= nil
    for i = 1, 8 do
      if not (lit and shifted and samePal(shifted[i],
            { lit[i][3], lit[i][4], lit[i][4], lit[i][4] })) then
        allShifted = false
      end
    end
    check(allShifted,
          "every ADVANCED tile group bakes FadePal2-shifted, not veiled")
    local key = ow.map.renderer and ow.map.renderer.gbcAtlasKey
    U.log("atlas key:", tostring(key))
    check(type(key) == "string" and key:find("#dark", 1, true) ~= nil,
          "and the atlas it baked is keyed apart from the lit one")

    local shot = Probe.grab()
    if shot then
      local top, total = Probe.top(shot, 4)
      U.log(("probe[ADVANCED dark] %d px: %s"):format(total, Probe.fmt(top)))
      local floorIsShifted = false
      for i = 1, 8 do
        for j = 1, 4 do
          if shifted and top[1] and sameCol(top[1], shifted[i][j]) then
            floorIsShifted = true
          end
        end
      end
      check(floorIsShifted and top[1].share > 0.3,
            "the screen is mostly one exact shifted colour -- flat black floor, "
            .. "no veil arithmetic and no speckle")
      local litSeen = 0
      for i = 1, 8 do
        local c = Probe.count(shot, { a = lit[i][1], b = lit[i][2] }, 3)
        litSeen = litSeen + c.a + c.b
      end
      check(litSeen == 0, "and none of the lit atlas's own two top colours "
            .. "survives anywhere on it")
      PaletteFX.setDarkWorld(false)
      local litSprite = PaletteFX.spriteObp(ow.player.sprite.def,
                                            ow.player.sprite.seed)
      PaletteFX.setDarkWorld(true)
      U.log("player OBP lit:", ramp(litSprite))
      spriteProbe("ADVANCED", shot,
                  { obj1 = litSprite[2], obj2 = litSprite[3] })
    end
  end

  -- ---- OG RED: the reporter's reference capture --------------------------
  game.save.options.colors = "ogred"
  PaletteFX.setMode("ogred")
  ow = enter(nil)
  U.wait(30)
  U.shot(game, DIR .. "/bug383_2_dark_ogred.png")
  local shot = Probe.grab()
  if shot then
    local top, total = Probe.top(shot, 5)
    U.log(("probe[OG RED dark] %d px: %s"):format(total, Probe.fmt(top)))
    spriteProbe("OG RED", shot,
                { green = PaletteFX.GBC_OBJ[2], darkGreen = PaletteFX.GBC_OBJ[3] })
  end

  -- ---- the shade-remapped modes, each in its own ramp --------------------
  -- Their sprites bake OBP0 and are coloured by the zone shader, so the tone
  -- to look for is the one DARK_BGP sends DMG white to: palette entry 3, which
  -- the floor under him cannot supply.
  for _, m in ipairs({ { "gbc", "SGB", CAVE }, { "og", "plain DMG",
                        { { 255, 255, 255 }, { 170, 170, 170 }, { 85, 85, 85 },
                          { 0, 0, 0 } } },
                       { "classic", "CLASSIC", PaletteFX.CLASSIC } }) do
    game.save.options.colors = m[1]
    PaletteFX.setMode(m[1])
    ow = enter(nil)
    U.wait(30)
    U.shot(game, DIR .. "/bug383_3_dark_" .. m[1] .. ".png")
    local s = Probe.grab()
    if s then
      U.log(("probe[%s dark] %s"):format(m[2], Probe.fmt(Probe.top(s, 4))))
      spriteProbe(m[2], s, { shade2 = m[3][3] })
    end
  end

  -- ---- FLASH lights it, sprites and atlas together -----------------------
  game.save.options.colors = "gbc"
  PaletteFX.setMode("gbc")
  ow = enter(true)
  check(ow.dark == false and PaletteFX.darkWorld() == false,
        "after FLASH neither half of the darkness is armed")
  U.wait(30)
  U.shot(game, DIR .. "/bug383_4_flash_lit_sgb.png")
  local litShot = Probe.grab()
  if litShot then
    local rect = playerRect(litShot)
    if rect then
      -- the same box that had to be featureless in the dark: CAVE[1] is the
      -- sprite's own shade-0 white and the floor around him has none, so this
      -- is also the proof the box really covers the player
      local c = Probe.count(litShot, { paper = CAVE[1] }, 1, rect)
      U.log("lit player box tones:", Probe.fmt(Probe.top(litShot, 3, 1, rect)))
      check(c.paper > 0,
            "lit again, the player fills that same box with CAVE's white")
    end
  end

  if pack then
    game.save.options.colors = "redpp"
    PaletteFX.setMode("redpp")
    ow = enter(true)
    U.wait(30)
    U.shot(game, DIR .. "/bug383_5_flash_lit_redpp.png")
    local key = ow.map.renderer and ow.map.renderer.gbcAtlasKey
    U.log("atlas key after FLASH:", tostring(key))
    check(type(key) == "string" and key:find("#dark", 1, true) == nil,
          "ADVANCED rebaked its atlas lit rather than keeping the dark one")
  end

  U.log(fails == 0 and "all #383 machine checks passed"
                    or (fails .. " #383 machine check(s) FAILED -- read up"))
  U.log("shots in", DIR)

  -- ---- hand the pad over, dark, in the reporter's mode -------------------
  if pack then
    game.save.options.colors = "redpp"
    PaletteFX.setMode("redpp")
  end
  enter(nil)

  U.log("You are in ROCK TUNNEL 1F in ADVANCED colours, no FLASH used yet.")
  U.log("The floor should be flat black with no speckle, the rock outlines,")
  U.log("ladder and sign dim but legible, and the player gone: black on black.")
  U.log("START, POKeMON, A, FLASH lights it in one frame with no reload hitch,")
  U.log("him back in colour; the ladder to 2F is lit too, Route 10 and back is dark.")

  while true do
    coroutine.yield()
  end
end
