-- Driver: the fishing rod is ONE 8x8 tile in the player's hands, mirrored
-- between left and right, and it stays up through the verdict text (#321).
-- engine/overworld/player_animations.asm:471 FishingRodOAM draws one tile per
-- facing ($fd up/down, $fe sides, OAM_XFLIP on right) out of the 8x24 sheet
-- at :489; :437 clears BIT_LEDGE_OR_FISHING only after PrintText.
--   POKEPORT_DRIVER=tests/drivers/fishing_rod_bug321_test.lua POKEPORT_IDENTITY=bug321 SHOT_DIR=/tmp/shots love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local Screens = require("src.ui.Screens")
  local TextBox = require("src.render.TextBox")
  local SHOT_DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- The Viridian City pond (water block x=8..13, y=24..27) is the one spot
  -- where all four shores are a few steps apart, so every facing fits on one
  -- screen.  shoreFor() below re-derives each stand cell from the map data.
  local MAP = "VIRIDIAN_CITY"
  local SPOTS = {
    { x = 10, y = 23, facing = "down",  note = "north shore" },
    { x = 8,  y = 28, facing = "up",    note = "south shore" },
    { x = 14, y = 24, facing = "left",  note = "east shore" },
    { x = 7,  y = 24, facing = "right", note = "west shore" },
  }
  local DELTA = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
  local ROD = "OLD_ROD"

  -- ---- preconditions the eye cannot separate from the bug ----------------
  -- A missing sheet, a rod that never reaches goFishing and a rod drawn at
  -- garbage coordinates all look the same: no rod in the hands.

  local fx = game.data.field.overworldFx
  local rodDef = fx and fx.fishingRod
  check("field.overworldFx.fishingRod resolves",
        rodDef ~= nil and type(rodDef.path) == "string")
  if rodDef then U.log("rod sheet:", rodDef.path) end

  -- three stacked 8x8 tiles, of which exactly one is ever drawn; if the sheet
  -- is not 8x24 the ROD_OAM tile indices mean nothing
  if rodDef and rodDef.path then
    local ok, img = pcall(love.graphics.newImage, rodDef.path)
    if check("the rod sheet loads", ok and img ~= nil) then
      local w, h = img:getDimensions()
      U.log(("rod sheet is %dx%d"):format(w, h))
      check("it is 8 wide (one tile)", w == 8)
      check("it is 24 tall (three stacked 8x8 tiles, RedFishingRodTiles)", h == 24)
    end
  end

  check("OLD ROD is a real item", game.data.items[ROD] ~= nil)
  local ItemEffects = require("src.inventory.ItemEffects")
  local result = ItemEffects.use(game.data, game.save, ROD, nil, nil, nil, game.overworld)
  check("using it routes to the fishing branch", result == "fish")

  -- Old Rod always hooks a L5 MAGIKARP, so the verdict box is deterministic
  local rodFishing = (game.data.field.fishing or {})[ROD]
  check("OLD ROD always gets a bite (field.fishing.OLD_ROD.always)",
        rodFishing ~= nil and rodFishing.always ~= nil)

  -- the bite ends in a battle once the box is dismissed
  game.save.party = { Pokemon.new(game.data, "CHARIZARD", 50) }
  game.save.inventory = { [ROD] = 1 }
  game.save.bagOrder = { ROD }
  check("the rod is the only thing in the bag (so it is item #1)",
        (game.save.inventory[ROD] or 0) > 0)

  -- ---- helpers -----------------------------------------------------------

  -- Walk the real path, START-menu bag -> rod -> USE: BagMenu's fish branch
  -- is what calls goFishing, and it refuses unless the faced cell is water,
  -- so this doubles as proof the stand cell is right.
  local function useRod()
    Screens.push(game, "BagMenu")
    U.wait(20)
    U.tap(game, "a")   -- select OLD ROD -> USE/TOSS
    U.wait(20)
    U.tap(game, "a")   -- USE
    U.wait(30)
  end

  local function topBox()
    local top = game.stack:top()
    if getmetatable(top) ~= TextBox then return nil end
    local shown = {}
    for _, page in ipairs(top.pages or {}) do
      for _, line in ipairs(page) do shown[#shown + 1] = line end
    end
    return top, table.concat(shown, " / ")
  end

  -- A press while the box is still typing only finishes the line, so tap
  -- until the box on top is a different one (or we run out of patience).
  local function advance(box)
    for _ = 1, 12 do
      U.tap(game, "a")
      U.wait(12)
      if game.stack:top() ~= box then return true end
    end
    return false
  end

  -- if a map edit moved the pond, find any shore facing water the same way
  -- rather than parking the player at a wall
  local function shoreFor(map, spot)
    local d = DELTA[spot.facing]
    if map:inBounds(spot.x + d[1], spot.y + d[2])
       and map:isWaterCell(spot.x + d[1], spot.y + d[2])
       and map:isWalkableCell(spot.x, spot.y) then
      return spot.x, spot.y
    end
    for y = 0, map.def.height * 2 - 1 do
      for x = 0, map.def.width * 2 - 1 do
        if map:isWalkableCell(x, y) and not map:isWaterCell(x, y)
           and map:inBounds(x + d[1], y + d[2])
           and map:isWaterCell(x + d[1], y + d[2]) then
          U.log(("(%d,%d) no longer faces water; using (%d,%d) for %s")
                  :format(spot.x, spot.y, x, y, spot.facing))
          return x, y
        end
      end
    end
    return spot.x, spot.y
  end

  -- ---- the four facings --------------------------------------------------

  for i, spot in ipairs(SPOTS) do
    local last = (i == #SPOTS)
    U.teleport(game, MAP, spot.x, spot.y, spot.facing)
    U.wait(15)
    local ow = game.overworld
    local sx, sy = shoreFor(ow.map, spot)
    if sx ~= spot.x or sy ~= spot.y then
      U.teleport(game, MAP, sx, sy, spot.facing)
      U.wait(15)
      ow = game.overworld
    end
    local fcx, fcy = ow.player:facingCell()
    check(("facing %s from (%d,%d), the %s: water in front")
            :format(spot.facing, sx, sy, spot.note),
          ow.map:inBounds(fcx, fcy) and ow.map:isWaterCell(fcx, fcy))

    useRod()

    local dots, dotsText = topBox()
    check(("%s: USE opened the fishing box"):format(spot.facing), dots ~= nil)
    if dotsText then U.log("box reads:", dotsText) end
    check(("%s: the rod is up (overworld.fishing is set)"):format(spot.facing),
          ow.fishing ~= nil)
    check(("%s: the rod remembers this facing"):format(spot.facing),
          ow.fishing ~= nil and ow.fishing.facing == spot.facing)
    if not U.shot(game, ("%s/bug321_rod_%s_dots.png"):format(SHOT_DIR, spot.facing)) then
      check(("%s: dots screenshot reached disk"):format(spot.facing), false)
    end

    -- the timing half of #321: the dots box closes, the verdict box opens,
    -- and the rod must still be in the player's hands the whole time
    if dots then advance(dots) end
    local verdict, verdictText = topBox()
    check(("%s: the verdict box opened"):format(spot.facing), verdict ~= nil)
    if verdictText then U.log("box reads:", verdictText) end
    check(("%s: the rod is STILL up while the verdict text shows"):format(spot.facing),
          ow.fishing ~= nil)
    if not U.shot(game, ("%s/bug321_rod_%s_verdict.png"):format(SHOT_DIR, spot.facing)) then
      check(("%s: verdict screenshot reached disk"):format(spot.facing), false)
    end

    -- The last facing is left live for the hand-off; the others are cleared
    -- by the next teleport, which pops the stack, so no battle starts here.
    if last then
      U.log("leaving this box open for you")
    end
  end

  -- ---- hand off ----------------------------------------------------------
  U.log("West shore of the Viridian pond, facing right, mid-cast.")
  U.log("Correct: one 8x8 rod stroke touching the player's hands, a mirror")
  U.log("image left vs right, still up for the whole verdict box (#321).")
  U.log("Shots: " .. SHOT_DIR .. "/bug321_rod_<facing>_{dots,verdict}.png")
  U.log("The pose swaps the sprite's bottom tile row (#384); the sprite shake")
  U.log("and the ! bubble on a bite are still unported.")

  while true do
    coroutine.yield()
  end
end
