local U = require("tests.drivers.util")

-- ../pokecrystal/home/text.asm:630
local SHOT_DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/pokeport-shots"

return function(game)
  local fails = 0
  local function say(line) print("[2132] " .. line) end
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    say((cond and "PASS " or "FAIL ") .. line)
  end

  U.wait(60)
  local world = game.world
  if not (world and world.map) then
    say("FAIL the gen 2 world did not boot")
    love.event.quit(1)
    return
  end

  -- ../pokecrystal/maps/NewBarkTown.asm:296
  world:warpToMapId("NEW_BARK_TOWN", 8, 9, "up")
  U.wait(30)
  ok(world.map and world.map.id == "NEW_BARK_TOWN", "standing under the town sign")

  U.tap(game, "a")
  local box
  for _ = 1, 600 do
    local top = game.stack and game.stack:top()
    if top and top.isTextBox and top:arrowVisible() then box = top; break end
    U.wait(1)
  end
  ok(box ~= nil, "the sign's first page is up and waiting on the arrow")
  if not box then
    love.event.quit(1)
    return
  end

  box.blink = 0
  U.shot(game, SHOT_DIR .. "/2132_arrow.png")

  local canvas = love.graphics.newCanvas(160, 144)
  love.graphics.push("all")
  love.graphics.setCanvas(canvas)
  love.graphics.clear(1, 0, 1, 1)
  box.blink = 0
  box:draw()
  love.graphics.setCanvas()
  love.graphics.pop()
  local id = canvas:newImageData()

  local function px(x, y)
    local r, g, b = id:getPixel(x, y)
    return r, g, b
  end
  local function near(x, y, r, g, b)
    local pr, pg, pb = px(x, y)
    return math.abs(pr - r) < 0.05 and math.abs(pg - g) < 0.05
      and math.abs(pb - b) < 0.05
  end
  local pr, pg, pb = px(12, 108)
  say(("paper sampled at (12,108): %.2f %.2f %.2f"):format(pr, pg, pb))
  ok(not near(12, 108, 1, 0, 1), "the box interior was painted")

  local function paperInRow(y)
    local n = 0
    for x = 144, 151 do
      if near(x, y, pr, pg, pb) then n = n + 1 end
    end
    return n
  end
  local function inkInCell()
    local n = 0
    for y = 136, 143 do
      for x = 144, 151 do
        local r, g, b = px(x, y)
        if r < 0.3 and g < 0.3 and b < 0.3 then n = n + 1 end
      end
    end
    return n
  end
  local ink = inkInCell()
  say(("ink pixels in tile (18,17): %d"):format(ink))
  ok(ink > 0, "the arrow is drawn in the corner cell")
  local function inkInRow(cx, y)
    local n = 0
    for x = cx * 8, cx * 8 + 7 do
      local r, g, b = px(x, y)
      if r < 0.3 and g < 0.3 and b < 0.3 then n = n + 1 end
    end
    return n
  end
  local lineRows = {}
  for y = 136, 143 do
    if inkInRow(17, y) >= 6 then lineRows[#lineRows + 1] = y end
  end
  ok(#lineRows > 0, "tile (17,17) carries the frame line rows")
  for _, y in ipairs(lineRows) do
    ok(paperInRow(y) > 0, ("frame row %d of tile (18,17) shows paper under the arrow"):format(y - 136))
  end

  box.blink = 16
  love.graphics.push("all")
  love.graphics.setCanvas(canvas)
  love.graphics.clear(1, 0, 1, 1)
  box:draw()
  love.graphics.setCanvas()
  love.graphics.pop()
  id = canvas:newImageData()
  local same = true
  for y = 136, 143 do
    for x = 0, 7 do
      local r1, g1, b1 = px(136 + x, y)
      local r2, g2, b2 = px(144 + x, y)
      if math.abs(r1 - r2) > 0.05 or math.abs(g1 - g2) > 0.05 or math.abs(b1 - b2) > 0.05 then
        same = false
      end
    end
  end
  ok(same, "on the off phase tile (18,17) matches the plain frame tile (17,17)")

  say("eyeball 2132_arrow.png: the down arrow in the bottom-right corner sits "
    .. "in a paper cell with no frame lines through it (compare shots/2132_2.png)")

  say(fails == 0 and "all claims passed" or (fails .. " claims failed"))
  love.event.quit(fails == 0 and 0 or 1)
end
