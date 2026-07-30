-- Driver: a dark cave shifts the WHOLE screen's BG palette; it never cuts a
-- window of light around the player (#322).  home/overworld.asm:498-501 sets
-- wMapPalOffset to 6 and home/fade.asm:4-20,66 makes that FadePal2 (BGP $FE)
-- for the whole screen.  No POKEPORT_SPEED on this run.
--   POKEPORT_DRIVER=tests/drivers/rock_tunnel_dark_bug322_test.lua \
--     POKEPORT_IDENTITY=bug322 POKEPORT_TOUCH=0 SHOT_DIR=/tmp/shots love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Probe = dofile("tests/drivers/shot_probe.lua")
  local PaletteFX = require("src.render.PaletteFX")
  local Screens = require("src.ui.Screens")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

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
  local function samePal(a, b)
    if not a or not b then return false end
    for i = 1, 4 do
      if not a[i] or not b[i] then return false end
      for k = 1, 3 do if a[i][k] ~= b[i][k] then return false end end
    end
    return true
  end

  local Pokemon = require("src.pokemon.Pokemon")
  game.save.flags.EVENT_GOT_STARTER = true
  if #game.save.party == 0 then
    table.insert(game.save.party, Pokemon.new(game.data, "CHARMANDER", 20))
  end
  game.save.options = game.save.options or {}
  game.save.options.textSpeed = 1
  game.save.options.colors = "gbc"
  PaletteFX.setMode("gbc")

  -- =====================================================================
  -- Part 1: the arithmetic.  A darkening one shade off still looks plausible
  -- on screen.
  -- =====================================================================
  local darkDef = game.data.field.darkMaps
  check(darkDef ~= nil, "field.darkMaps exists (extracted from the ROM)")
  local listed = false
  for _, m in ipairs(darkDef and darkDef.maps or {}) do
    if m == "ROCK_TUNNEL_1F" then listed = true end
  end
  check(listed, "ROCK_TUNNEL_1F is in field.darkMaps.maps")
  U.log("darkMaps.entryMap =", tostring(darkDef and darkDef.entryMap),
        " flashBadge =", tostring(darkDef and darkDef.flashBadge))

  local BGP = PaletteFX.DARK_BGP
  check(BGP ~= nil and BGP[0] == 2 and BGP[1] == 3 and BGP[2] == 3
        and BGP[3] == 3,
        "DARK_BGP is FadePal2's `dc 3,3,3,2` (shade 0 -> 2, 1/2/3 -> 3)")

  local CAVE = PaletteFX.pal(game.data, "CAVE")
  U.log("CAVE palette:", ramp(CAVE))
  local caveDark = PaletteFX.permute(CAVE, BGP)
  U.log("CAVE darkened:", ramp(caveDark))
  check(samePal(caveDark, { CAVE[3], CAVE[4], CAVE[4], CAVE[4] }),
        "SGB's CAVE becomes light-teal paper over near-black")

  local ogDark = PaletteFX.permute(PaletteFX.GBC_BG, BGP)
  U.log("OG RED darkened:", ramp(ogDark))
  check(ogDark[1][1] == 148 and ogDark[1][2] == 58 and ogDark[1][3] == 58
        and ogDark[2][1] == 0 and ogDark[3][1] == 0 and ogDark[4][1] == 0,
        "OG RED reduces to exactly (148,58,58) and (0,0,0) -- the issue's image")

  -- The shade map has to compose AFTER the mono/inverted replacement, or the
  -- modes that throw the incoming palette away throw the darkness out with it.
  PaletteFX.setShadeMap(BGP)
  PaletteFX.setMode("og")
  local dmgDark = PaletteFX.effectiveColors(CAVE)
  U.log("plain DMG darkened:", ramp(dmgDark))
  check(dmgDark[1][1] == 85 and dmgDark[2][1] == 0,
        "plain DMG darkens too (grey 85 over black), not silently skipped")
  PaletteFX.setMode("classic")
  local classicDark = PaletteFX.effectiveColors(CAVE)
  U.log("CLASSIC darkened:", ramp(classicDark))
  check(samePal(classicDark, { PaletteFX.CLASSIC[3], PaletteFX.CLASSIC[4],
                               PaletteFX.CLASSIC[4], PaletteFX.CLASSIC[4] }),
        "CLASSIC darkens inside its own pea-green ramp")
  PaletteFX.setShadeMap(nil)
  PaletteFX.setMode("gbc")
  -- tests/mod_graphics_tests.lua compares with ==, so the unarmed path must
  -- hand back the very table it was given, not a copy
  check(PaletteFX.effectiveColors(CAVE) == CAVE,
        "with nothing armed, effectiveColors still returns its input by identity")

  -- =====================================================================
  -- Part 2: reach the moment.
  -- =====================================================================
  -- data/maps/objects/RockTunnel1F.asm: the Route 10 entrance is warp_event
  -- 15, 3, so two cells south of it is floor without re-triggering the warp.
  local MAP, STAND = "ROCK_TUNNEL_1F", { x = 15, y = 5, facing = "down" }

  local function enter(flashLit)
    game.save.flashLit = flashLit or nil
    U.teleport(game, MAP, STAND.x, STAND.y, STAND.facing)
    U.wait(12)
    local ow = game.overworld
    -- if a map edit or a mod took that cell away, fall back to the nearest
    -- walkable cell that is not itself a warp
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

  local ow = enter(nil)
  check(ow ~= nil and ow.map and ow.map.id == MAP, "player is inside " .. MAP)
  check(ow ~= nil and ow.dark == true,
        "the map reports itself dark with no FLASH used")
  check(ow ~= nil and ow:paletteNameFor(ow.map) == "CAVE",
        "and resolves the CAVE palette (tileset CAVERN)")
  check(ow ~= nil and ow.darkNeedsOverlay == nil,
        "the composited veil path is gone: SGB darkens via its palette")

  local function probe(label, wanted, rect)
    local shot = Probe.grab()
    if not shot then
      U.log("WARN pixel probe unavailable; judge", label, "by eye only")
      return nil, nil
    end
    local counts, total = Probe.count(shot, wanted, 3, rect)
    local parts = {}
    for name, n in pairs(counts) do
      parts[#parts + 1] = ("%s=%.1f%%"):format(name, total > 0 and n * 100 / total or 0)
    end
    table.sort(parts)
    U.log(("probe[%s] %d px: %s"):format(label, total, table.concat(parts, "  ")))
    return counts, total, shot
  end

  -- A palette shift darkens the corner and leaves it legible; a light window
  -- around the player leaves it black.  This rect is well outside any window
  -- centred on a centred player.
  local FAR_CORNER = { 0.02, 0.02, 0.28, 0.28 }

  -- ---- SGB, dark ---------------------------------------------------------
  U.wait(30)
  U.shot(game, DIR .. "/bug322_1_dark_sgb.png")
  local c = probe("SGB dark / far corner", {
    darkPaper = caveDark[1], darkInk = caveDark[2],
    litPaper = CAVE[1], litMid = CAVE[2],
  }, FAR_CORNER)
  if c then
    check(c.darkPaper > 0,
          "the FAR CORNER of the screen is drawn, not blacked out (no light window)")
    check(c.litPaper == 0 and c.litMid == 0,
          "and it is darkened -- none of CAVE's undimmed colours survive there")
  end
  local full = probe("SGB dark / whole frame", {
    darkPaper = caveDark[1], darkInk = caveDark[2], litPaper = CAVE[1],
  })
  if full then
    check(full.litPaper == 0,
          "nowhere on the screen keeps CAVE's paper white -- the shift is global")
  end

  -- Renderer:beginFrame clears the shade map and OverworldState:drawWorld
  -- re-arms it, so what is armed right now is what the LAST drawn frame used.
  check(PaletteFX.shadeMap() == PaletteFX.DARK_BGP,
        "the last drawn frame really did run with DARK_BGP armed")

  -- ---- OG RED, dark: the reporter's reference image ----------------------
  game.save.options.colors = "ogred"
  PaletteFX.setMode("ogred")
  enter(nil)
  U.wait(30)
  U.shot(game, DIR .. "/bug322_2_dark_ogred.png")
  local shot = Probe.grab()
  if shot then
    local top, total = Probe.top(shot, 6)
    U.log(("probe[OG RED dark] %d px, top colours: %s")
            :format(total, Probe.fmt(top)))
    local extra = {}
    for _, col in ipairs(top) do
      local isDark = (col[1] == 148 and col[2] == 58 and col[3] == 58)
                     or (col[1] == 0 and col[2] == 0 and col[3] == 0)
      if not isDark and col.share > 0.002 then
        extra[#extra + 1] = ("(%d,%d,%d) %.1f%%")
          :format(col[1], col[2], col[3], col.share * 100)
      end
    end
    check(#extra == 0,
          "OG RED's dark tunnel is EXACTLY (148,58,58) + (0,0,0), like the "
          .. "issue's expected screenshot"
          .. (#extra > 0 and (" -- extra: " .. table.concat(extra, ", ")) or ""))
    local corner = Probe.count(shot, { red = { 148, 58, 58 } }, 3, FAR_CORNER)
    check(corner.red > 0, "and the far corner still carries that red, not a void")

    -- FadePal2 writes rOBP0 as well as rBGP (`dc 3,3,3,2`), so every OBJ
    -- colour lands on shade 3 and the player is a black silhouette: none of
    -- the boot-ROM green may survive (#383).
    local sprite = Probe.count(shot,
      { green = PaletteFX.GBC_OBJ[2], darkGreen = PaletteFX.GBC_OBJ[3] })
    check(sprite.green == 0 and sprite.darkGreen == 0,
          "OG RED's player is black in the dark, not green")
  end

  -- ---- the modes that darken in their own ramps --------------------------
  for _, m in ipairs({ { "og", "plain DMG" }, { "classic", "CLASSIC" },
                       { "redpp", "ADVANCED / RED++" } }) do
    game.save.options.colors = m[1]
    PaletteFX.setMode(m[1])
    enter(nil)
    U.wait(30)
    U.shot(game, DIR .. "/bug322_3_dark_" .. m[1] .. ".png")
    local s = Probe.grab()
    if s then
      local top, total = Probe.top(s, 5)
      U.log(("probe[%s dark] %d px, top colours: %s")
              :format(m[2], total, Probe.fmt(top)))
      -- "Not blacked out" cannot be asked as "not the colour black": the old
      -- overlay drew black INTO the world canvas and the zone shader then
      -- coloured it (in CLASSIC the void came out pea green).  Ask for
      -- structure instead: a shifted palette leaves two tones in the corner,
      -- a window of light leaves one flat fill.
      local corner = Probe.top(s, 3, 3, FAR_CORNER)
      U.log("   far corner:", Probe.fmt(corner))
      local second = corner[2] and corner[2].share or 0
      check(second > 0.02,
            m[2] .. ": the far corner still has two tones (no light window)")
    end
    if m[1] == "redpp" then
      -- RED++ has no palette left for the frame shader to shift, so the shift
      -- goes into the palette its atlas bakes from instead of a veil (#383).
      local o = game.overworld
      U.log("RED++ gbcAtlas present:",
            tostring(o and o.map and o.map.renderer and o.map.renderer.gbcAtlas ~= nil))
      check(PaletteFX.darkWorld() == true,
            "RED++ arms the dark-world flag, so its atlas bakes dark")
      local pack = PaletteFX.gbcPack()
      local tsId = o and o.map and o.map.tileset and o.map.tileset.id
      local lit = pack and tsId and pack.world.groupColors[tsId]
      local shifted = tsId and PaletteFX.worldGroupColors(game.data, tsId,
                                                          o.map.id, nil)
      check(lit ~= nil and shifted ~= nil and samePal(shifted[1],
              { lit[1][3], lit[1][4], lit[1][4], lit[1][4] }),
            "and every baked group is FadePal2-shifted, not veiled")
    end
  end

  game.save.options.colors = "gbc"
  PaletteFX.setMode("gbc")

  -- ---- FLASH lifts it ----------------------------------------------------
  -- PartyMenu sets save.flashLit when the move is used; entering with it set
  -- is the same state (OverworldState.enterMap:305).
  ow = enter(true)
  check(ow ~= nil and ow.dark == false, "after FLASH the map is no longer dark")
  U.wait(30)
  U.shot(game, DIR .. "/bug322_4_flash_lit_sgb.png")
  -- Once the shift is armed every entry comes from CAVE[3] or CAVE[4], so
  -- CAVE[1] or CAVE[2] appearing proves the map is lit.  caveDark[1] is
  -- CAVE[3] and occurs in the lit palette too, so it is not evidence alone.
  c = probe("SGB after FLASH",
            { litPaper = CAVE[1], litMid = CAVE[2], darkPaper = caveDark[1] })
  if c then
    check(c.litPaper > 0 and c.litMid > 0,
          "FLASH restores CAVE's full brightness (paper white and brown are back)")
  end
  check(PaletteFX.shadeMap() == nil, "and nothing is armed any more")

  -- ---- a dialog over a dark map darkens with it --------------------------
  -- rBGP is one register for the whole screen, so a START menu over a dark
  -- map darkens with it.  Easy to mistake for a bug.
  ow = enter(nil)
  U.wait(15)
  U.tap(game, "start")
  U.wait(30)
  U.shot(game, DIR .. "/bug322_5_startmenu_dark.png")
  c = probe("START menu over the dark map",
            { litPaper = CAVE[1], darkPaper = caveDark[1] })
  if c then
    check(c.darkPaper > 0 and c.litPaper == 0,
          "the START menu over a dark map darkens WITH it (one rBGP, as on hardware)")
  end
  U.tap(game, "b")
  U.wait(20)

  -- ---- a full-screen menu, and a battle, come out LIT --------------------
  -- Neither draws a map, so drawWorld never runs and beginFrame's clear
  -- stands: the same result as init_battle_variables.asm's wMapPalOffset
  -- reset on hardware.
  Screens.push(game, "PartyMenu")
  U.wait(30)
  U.shot(game, DIR .. "/bug322_6_partymenu_lit.png")
  c = probe("PARTY menu over the dark map",
            { litPaper = CAVE[1], darkPaper = caveDark[1] })
  if c then
    check(c.litPaper > 0,
          "an opaque full-screen menu comes out LIT (nothing inherited the shift)")
  end
  check(PaletteFX.shadeMap() == nil, "no shade map armed while it is up")
  U.tap(game, "b")
  U.wait(20)

  local BattleState = require("src.battle.BattleState")
  local ok = pcall(function()
    local battle = BattleState.newWild(game, "ZUBAT", 15)
    battle.onFinish = function() end
    game.overworld:pushBattle(battle)
  end)
  if ok then
    U.wait(90) -- through the transition wipe and the intro slide-in
    U.shot(game, DIR .. "/bug322_7_battle_lit.png")
    c = probe("wild battle inside the dark tunnel",
              { litPaper = CAVE[1], darkPaper = caveDark[1] })
    if c then
      check(c.litPaper > 0,
            "a battle in a dark cave is LIT (init_battle_variables.asm)")
    end
  else
    U.log("WARN could not force a wild battle; the battle-is-lit case is",
          "unphotographed")
  end

  U.log(fails == 0 and "all #322 preconditions passed"
                    or (fails .. " #322 precondition(s) FAILED -- read up"))

  -- =====================================================================
  -- Part 3: hand off, standing in the dark tunnel.
  -- =====================================================================
  for _ = 1, 60 do
    if game.stack:top() == game.overworld then break end
    U.tap(game, "b")
    U.wait(4)
  end
  enter(nil)

  U.log("You are in ROCK TUNNEL 1F, no FLASH used, default SGB colours.")
  U.log("Walk in every direction: the whole screen's palette should be")
  U.log("shifted down and still legible out to the corners, with no window")
  U.log("of light following you around (#322).  Shots are in " .. DIR .. ".")
  U.log("The START menu darkens with the map (one rBGP), which is correct.")

  while true do
    coroutine.yield()
  end
end
