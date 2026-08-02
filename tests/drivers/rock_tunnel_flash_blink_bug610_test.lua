-- Manual check that FLASH in a dark cave costs one short blink and not a long
-- white hang (#610).  pokered engine/menus/start_sub_menus.asm .flash clears
-- wMapPalOffset, prints _FlashLightsAreaText over the party menu and only then
-- runs GBPalWhiteOutWithDelay3, so the cave is already lit when the blink
-- starts; ADVANCED rebakes its atlas there (#383), which must not ride the blink.
--   POKEPORT_DRIVER=tests/drivers/rock_tunnel_flash_blink_bug610_test.lua \
--     POKEPORT_IDENTITY=bug610 POKEPORT_TOUCH=0 SHOT_DIR=/tmp/shots610 love .
-- No POKEPORT_SPEED: fast-forward desynchronizes audio and logic ordering.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local PartyMenu = require("src.ui.PartyMenu")
  local PaletteFX = require("src.render.PaletteFX")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots610"

  local fails = 0
  local function check(ok, msg)
    U.log(ok and "PASS" or "FAIL", msg)
    if not ok then fails = fails + 1 end
    return ok
  end

  -- wall clock, not os.clock: the bake this bug is about blocks the frame, and
  -- CPU time would hide any of it that waits on the GPU
  local now = (love and love.timer and love.timer.getTime)
              and love.timer.getTime or os.clock

  -- one frame, remembering the longest frame seen since the last reset and
  -- what was drawn on it: "the hitch happened under the party menu" is the
  -- whole claim of the fix, and it is not visible in a total
  local worst, worstWhere = 0, "nothing"
  local function label()
    local top = game.stack:top()
    if top == nil then return "nothing" end
    if getmetatable(top) == PartyMenu then return "the party menu" end
    if top.pages then return "the FLASH message" end
    if top == game.overworld then return "the map" end
    if type(top.t) == "number" and type(top.frames) == "number" then
      return "the white blink"
    end
    return "a menu"
  end
  local function step(n)
    for _ = 1, n do
      local where = label()
      local t0 = now()
      coroutine.yield()
      local dt = now() - t0
      if dt > worst then worst, worstWhere = dt, where end
    end
  end
  local function resetWorst() worst, worstWhere = 0, "nothing" end

  -- U.tap spends a frame of its own outside step(), and on the last A of the
  -- FLASH message that is precisely the frame the work lands on, so press
  -- through the tracked step instead of losing it
  local function tap(btn)
    table.insert(game.input.pressQueue, btn)
    step(1)
    game.input.state[btn] = false
  end

  -- the blink is the transition record's own frame count, not a state class:
  -- Transition keeps WhiteFlash local, so recognize it by shape (a counter, a
  -- length, no text pages) the way the stack itself sees it
  local function isBlink(s)
    return s ~= nil and s.pages == nil and type(s.t) == "number"
       and type(s.frames) == "number"
  end

  game.save.flags.EVENT_GOT_STARTER = true
  -- every list-time badge gate in PartyMenu: FLASH is the subject, STRENGTH is
  -- the reference blink (it always prints and always blinks), SURF is there so
  -- the Route 10 pond can be tried too
  game.save.inventory.BOULDERBADGE = true
  game.save.inventory.RAINBOWBADGE = true
  game.save.inventory.SOULBADGE = true
  game.save.options = game.save.options or {}
  game.save.options.textSpeed = 1
  game.save.options.colors = "redpp" -- ADVANCED, the mode whose rebake is dear
  PaletteFX.setMode("redpp")

  local function giveMon()
    local mon = Pokemon.new(game.data, "PIKACHU", 30)
    mon.moves = { { id = "FLASH", pp = 5 }, { id = "STRENGTH", pp = 15 },
                  { id = "SURF", pp = 15 } }
    game.save.party = { mon }
    return mon
  end
  giveMon()

  -- ---- what has to be true before any of this can be judged ---------------
  check(PaletteFX.gbcPack() ~= nil,
        "the ADVANCED colour pack is installed (without it nothing rebakes "
        .. "and this driver proves nothing)")
  check(PaletteFX.usesGbcPack(), "and the active mode is the baking one")

  local darkDef = game.data.field.darkMaps
  local listed = false
  for _, m in ipairs(darkDef and darkDef.maps or {}) do
    if m == "ROCK_TUNNEL_1F" then listed = true end
  end
  check(listed, "ROCK_TUNNEL_1F is in field.darkMaps.maps")

  local flashText = game.data.text._FlashLightsAreaText
  check(type(flashText) == "string" and flashText ~= "",
        "_FlashLightsAreaText extracted from the ROM")
  if type(flashText) == "string" then
    U.log("the message reads:", (flashText:gsub("\n", " / ")))
  end

  local rec = (game.data.transitions and game.data.transitions.white_flash)
              or require("src.render.Transition").STYLES.white_flash
  U.log("white_flash is", tostring(rec and rec.frames), "frames")
  check(rec and rec.frames and rec.frames <= 12,
        "the blink is a handful of frames, so anything longer on screen is "
        .. "work riding it")

  local vol = game.save.options.sfxVol
  if vol == 0 then
    U.log("sfxVol is 0: the blink and the menu beeps are silent, turn SFX up",
          "in OPTION before judging any of this by ear")
  else
    U.log("sfxVol =", tostring(vol))
  end

  -- ---- park just inside the Route 10 entrance -----------------------------
  -- pokered data/maps/objects/RockTunnel1F.asm: warp_event 15, 3 is the
  -- Route 10 mouth, so (15, 4) is walkable floor one cell inside it, with the
  -- warp still one step north for the second half of the check.
  local MAP, STAND = "ROCK_TUNNEL_1F", { x = 15, y = 4, facing = "down" }
  local WARP = { x = 15, y = 3 }

  local function enter(lit)
    game.save.flashLit = lit or nil
    U.teleport(game, MAP, STAND.x, STAND.y, STAND.facing)
    step(12)
    local ow = game.overworld
    -- a map edit or a mod can drop a rock on the entrance floor: fall back to
    -- any walkable neighbour of the warp that is not the warp itself
    if ow and ow.map and not ow.map:isWalkableCell(STAND.x, STAND.y) then
      local sides = { { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 } }
      for _, s in ipairs(sides) do
        local cx, cy = WARP.x + s[1], WARP.y + s[2]
        if ow.map:isWalkableCell(cx, cy) and not ow.map:warpAtCell(cx, cy)
           and not ow:npcAtCell(cx, cy) then
          U.log(("(%d, %d) is blocked, standing on"):format(STAND.x, STAND.y),
                cx, cy)
          STAND.x, STAND.y = cx, cy
          U.teleport(game, MAP, cx, cy, STAND.facing)
          step(12)
          ow = game.overworld
          break
        end
      end
    end
    return ow
  end

  local ow = enter(nil)
  check(ow ~= nil and ow.dark == true, "the tunnel is dark on arrival")
  check(ow.map:warpAtCell(WARP.x, WARP.y) ~= nil,
        ("the Route 10 warp is still at (%d, %d), so the walk back out is "
         .. "reachable"):format(WARP.x, WARP.y))
  local key = ow.map.renderer and ow.map.renderer.gbcAtlasKey
  U.log("atlas key, dark:", tostring(key))
  check(type(key) == "string" and key:find("#dark", 1, true) ~= nil,
        "and it is drawing the dark bake, not a shaded lit one")
  check(U.shot(game, DIR .. "/bug610_1_dark.png"),
        "a frame reached disk, so there is a window to watch")

  -- ---- run the moment once, watching where the cost lands -----------------
  -- START -> POKeMON -> the mon -> FLASH, looked up by row rather than counted
  -- so a mod that inserts a row cannot silently pick something else
  tap("start")
  step(12)
  local menu = game.stack:top()
  local row
  for i, it in ipairs(menu and menu.items or {}) do
    if tostring(it.label):upper():find("MON", 1, true) then row = i break end
  end
  check(row ~= nil, "the START menu lists POKeMON")
  for _ = 2, (row or 1) do tap("down"); step(2) end
  tap("a")
  step(12)
  local pm = game.stack:top()
  check(getmetatable(pm) == PartyMenu, "POKeMON opens the party menu")
  tap("a")
  step(8)
  local sub
  for i, it in ipairs((pm and pm.subItems) or {}) do
    if it.action == "flash" then sub = i break end
  end
  check(sub ~= nil, "FLASH is listed for this PIKACHU on a dark floor")
  for _ = 2, (sub or 1) do tap("down"); step(2) end
  tap("a")
  step(6)
  check(game.stack:top() ~= nil and game.stack:top().pages ~= nil,
        "FLASH puts its message up")
  check(ow.dark == true, "the tunnel is still dark while that message types")

  -- drain the text, then watch every frame from the last A to the map coming
  -- back: this is the window the bug filled with a white hang
  resetWorst()
  local blinkStart, blinkEnd, litAtBlink, keyAtBlink
  for _ = 1, 400 do
    local top = game.stack:top()
    if top and top.pages then
      tap("a")
      step(3)
    elseif isBlink(top) then
      if not blinkStart then
        blinkStart = now()
        litAtBlink = (ow.dark == false)
        keyAtBlink = ow.map.renderer and ow.map.renderer.gbcAtlasKey
      end
      step(1)
    else
      if blinkStart and not blinkEnd then blinkEnd = now() end
      break
    end
  end
  step(20)

  check(blinkStart ~= nil, "the blink ran")
  -- the fix itself, stated as an invariant: OverworldState:setDark drops every
  -- resident map and rebakes this one, and that has to be finished before the
  -- first white frame is drawn (start_sub_menus.asm .flash order)
  check(litAtBlink == true,
        "the cave was already lit on the blink's first frame, not lit by it")
  check(type(keyAtBlink) == "string"
        and keyAtBlink:find("#dark", 1, true) == nil,
        "and the lit atlas was already baked and bound by then")
  if blinkStart and blinkEnd then
    U.log(("the white was on screen for %.2f s"):format(blinkEnd - blinkStart))
  end
  U.log(("the longest single frame in the whole sequence was %.2f s, drawn "
         .. "over %s"):format(worst, worstWhere))
  check(worstWhere ~= "the white blink",
        "the expensive frame was not one of the white ones")
  check(ow.dark == false, "the tunnel is lit now")
  U.shot(game, DIR .. "/bug610_2_lit.png")

  -- ---- and it stays lit across the Route 10 round trip --------------------
  -- pokered data/maps/objects/Route10.asm: warp_event 8, 17 is the north
  -- tunnel mouth, so (8, 18) is the grass one step below it
  U.teleport(game, "ROUTE_10", 8, 18, "up")
  step(12)
  ow = enter(true)
  check(ow.dark == false, "coming back in from Route 10 the cave is still lit")
  key = ow.map.renderer and ow.map.renderer.gbcAtlasKey
  check(type(key) == "string" and key:find("#dark", 1, true) == nil,
        "on the lit bake, with no second rebake to blink through")
  U.shot(game, DIR .. "/bug610_3_relit.png")

  U.log(fails == 0 and "all #610 machine checks passed"
                    or (fails .. " #610 machine check(s) FAILED, read up"))
  U.log("shots in", DIR)

  -- ---- hand the pad over, dark, FLASH unused ------------------------------
  giveMon()
  enter(nil)

  U.log("You are back in the dark tunnel in ADVANCED colours with FLASH unused:")
  U.log("START, POKeMON, A, FLASH. The message should end over the party list, any")
  U.log("hitch should happen with that list still on screen, and then a blink about")
  U.log("as short as STRENGTH's on the same menu hands back a lit cave. A white that")
  U.log("sits noticeably longer than the STRENGTH one means the rebake is riding the")
  U.log("blink again. Then walk up to the ladder, out to Route 10 and back in: lit,")
  U.log("no second blink.")

  while true do
    coroutine.yield()
  end
end
