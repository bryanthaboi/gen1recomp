-- Manual check that a door warp fades in whole shades, not a dissolve (#607).
-- PlayMapChangeSound tail-calls GBFadeOutToBlack (pokered home/overworld.asm:703),
-- four palette writes held eight frames each (home/fade.asm:43-67), so the veil
-- is a four-step staircase across 32 frames, never a tween.  Numbers are pinned
-- in tests/mod_graphics_tests.lua; this puts eyes on the screen.
--   SHOT_DIR=/tmp/shots607 POKEPORT_DRIVER=tests/drivers/warp_fade_bug607_test.lua POKEPORT_IDENTITY=bug607 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .
-- Do not set POKEPORT_SPEED: fast-forward scales the logic clock only, so the
-- door SFX and the fade steps stop lining up and the staircase is unjudgeable.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Transition = require("src.render.Transition")
  local Sound = require("src.core.Sound")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots607"

  -- pokered data/maps/objects/PalletTown.asm: warp_event 5, 5, REDS_HOUSE_1F, 1.
  -- The mat itself is the warp cell, so the approach is the walkable cell below
  -- it, facing up: one step north fires the door.
  local MAP = "PALLET_TOWN"
  local DEST = "REDS_HOUSE_1F"
  local DOOR = { x = 5, y = 5 }
  local STAND = { x = 5, y = 6, facing = "up" }

  local failures = 0
  local function check(label, ok)
    if not ok then failures = failures + 1 end
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- the door row itself: a renamed destination or a moved warp reads on screen
  -- as "the fade never happened", same as the bug did
  local def = game.data.maps and game.data.maps[MAP]
  local door = nil
  for _, w in ipairs(def and def.warps or {}) do
    if w.destMap == DEST then door = w end
  end
  check(MAP .. " carries a warp row to " .. DEST, door ~= nil)
  if door then
    DOOR.x, DOOR.y = door.x, door.y
    STAND.x, STAND.y = door.x, door.y + 1
    check(("the door sits at (%d, %d), as in PalletTown.asm"):format(DOOR.x, DOOR.y),
          DOOR.x == 5 and DOOR.y == 5)
  end

  -- the fade is silent without these two: the step SFX is what tells the ear
  -- where frame 0 of the 32 was
  local sfx = game.data.audio and game.data.audio.sfx or {}
  check("Go_Inside and Go_Outside resolve as sfx keys",
        sfx.Go_Inside ~= nil and sfx.Go_Outside ~= nil)
  local vol = game.save.options and game.save.options.sfxVol or 7
  if vol == 0 then
    U.log("sfxVol is 0: the door SFX will be SILENT, raise it in OPTION first")
  end
  check(("sfx volume %d"):format(vol), vol > 0)

  -- the record and the staircase it drives, before any of it is on screen
  local fade = Transition.new(game, nil, nil, true)
  check("the warp fade runs 32 frames with no fade in",
        fade.frames == 32 and (fade.framesIn or 0) == 0)
  fade.phase = "out"
  local want = { { 0, 0 }, { 7, 0 }, { 8, 1 / 3 }, { 15, 1 / 3 },
                 { 16, 2 / 3 }, { 23, 2 / 3 }, { 24, 1 }, { 31, 1 } }
  local staircase = true
  for _, w in ipairs(want) do
    fade.t = w[1]
    if fade:alpha() ~= w[2] then staircase = false end
  end
  check("its alpha holds four shades, eight frames apiece", staircase)

  U.teleport(game, MAP, STAND.x, STAND.y, STAND.facing)
  U.wait(10)
  local ow = game.overworld
  if not (ow.map:isWalkableCell(STAND.x, STAND.y)) then
    -- a map edit or a mod blocked the approach: any walkable neighbour of the
    -- mat still steps onto it.  {dx, dy, facing} is the offset from the door to
    -- the stand cell plus the direction that walks back onto it.
    local sides = { { 0, 1, "up" }, { 0, -1, "down" },
                    { 1, 0, "left" }, { -1, 0, "right" } }
    for _, s in ipairs(sides) do
      local cx, cy = DOOR.x + s[1], DOOR.y + s[2]
      if ow.map:isWalkableCell(cx, cy) then
        U.log(("(%d, %d) is blocked, approaching from"):format(STAND.x, STAND.y),
              cx, cy, "facing", s[3])
        STAND.x, STAND.y, STAND.facing = cx, cy, s[3]
        U.teleport(game, MAP, cx, cy, s[3])
        U.wait(10)
        break
      end
    end
  end
  check("player is standing on the doorstep",
        ow.player.cellX == STAND.x and ow.player.cellY == STAND.y)

  -- walk in, shooting across the fade on the same cadence door_test.lua uses,
  -- so the two runs' frames line up side by side
  U.hold(game, STAND.facing, 20)
  check("first frame of the transition captured",
        U.shot(game, DIR .. "/door_1_mid.png"))
  for i = 2, 6 do
    U.wait(6)
    U.shot(game, DIR .. ("/door_%d_transition.png"):format(i))
  end
  U.wait(40)
  check("the door landed us in " .. DEST, ow.map.id == DEST)

  -- walking back out is the same fade, and sampling it frame by frame (no
  -- screenshots in this pass, those cost frames) says whether the veil really
  -- plateaus or is creeping between the steps
  local function liveFade()
    local top = game.stack:top()
    return getmetatable(top) == Transition and top or nil
  end
  local seen, order = {}, {}
  local bytes = {}
  for _ = 1, 140 do
    table.insert(game.input.pressQueue, "down")
    game.input.state.down = true
    local live = liveFade()
    if live then
      local a = live:alpha()
      if not seen[a] then seen[a] = 0; order[#order + 1] = a end
      seen[a] = seen[a] + 1
      local b = live:bgp()
      if bytes[#bytes] ~= b then bytes[#bytes + 1] = b end
    elseif #order > 0 then
      break
    end
    coroutine.yield()
  end
  game.input.state.down = false
  U.wait(20)
  U.shot(game, DIR .. "/door_9_back_outside.png")

  local shades = {}
  for _, a in ipairs(order) do
    shades[#shades + 1] = ("%.2f x%d"):format(a, seen[a])
  end
  U.log("shades held on the way out:", table.concat(shades, ", "))
  check("the exit fade shows four shades and no more", #order == 4)
  local held = true
  for _, a in ipairs(order) do
    if seen[a] < 7 then held = false end
  end
  check("each shade holds its eight frames", held)
  check("we are back outside on " .. MAP, ow.map.id == MAP)

  -- staircase has to be FadePal4/3/2/1 (home/fade.asm:49)
  local hex = {}
  for _, b in ipairs(bytes) do hex[#hex + 1] = ("$%02X"):format(b) end
  U.log("rBGP bytes written on the way out:", table.concat(hex, ", "))
  local want = { 0xE4, 0xF9, 0xFE, 0xFF }
  local walked = #bytes == #want
  for i, b in ipairs(want) do if bytes[i] ~= b then walked = false end end
  check("the exit fade walks FadePal4 -> FadePal3 -> FadePal2 -> FadePal1", walked)

  -- hand the doorstep back so this can be re-triggered by hand
  U.teleport(game, MAP, STAND.x, STAND.y, STAND.facing)
  U.log(failures == 0 and "checks clean" or (failures .. " check(s) failed above"))
  U.log("Red is on his own doorstep facing the door; hold Up to go in, Down to")
  U.log("come back out, as often as you like.  The town should stay fully lit for")
  U.log("about eight frames after the door sound, then drop in three whole shades")
  U.log("roughly an eighth of a second apart and sit on solid black for the last")
  U.log("eighth before the house cuts in.  If it instead dims smoothly, or is")
  U.log("already grey the instant you step on the mat and the map swaps under a")
  U.log("half-lit veil, that is the dissolve #607 was about, not the fade.")

  while true do
    coroutine.yield()
  end
end
