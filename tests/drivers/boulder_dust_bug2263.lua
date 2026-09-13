-- engine/overworld/dust_smoke.asm:1
--   POKEPORT_DRIVER=tests/drivers/boulder_dust_bug2263.lua POKEPORT_IDENTITY=red-sep04 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "/tmp/shots"
  local MAP = "SEAFOAM_ISLANDS_1F"
  local DIRS = { "right", "left", "down", "up" }
  local STEP = { down = { 0, 1 }, up = { 0, -1 }, left = { -1, 0 }, right = { 1, 0 } }

  local ok = true
  local function check(label, pass)
    U.log(pass and "PASS" or "FAIL", label)
    if not pass then ok = false end
    return pass
  end
  local function finish()
    for _, d in ipairs(DIRS) do game.input.state[d] = false end
    U.log(ok and "PASS boulder_dust_2263" or "FAIL boulder_dust_2263")
    love.event.quit(ok and 0 or 1)
    while true do coroutine.yield() end
  end

  U.teleport(game, MAP, 17, 10, "right")
  U.wait(10)
  local ow = game.overworld
  game.data.encounters[MAP] = nil
  local rock = ow and ow:npcAtCell(18, 10)
  if not check("boulder present at (18,10) on " .. MAP,
               rock ~= nil and rock.def.sprite == "SPRITE_BOULDER") then
    finish()
  end
  ow.strengthActive = true

  local function free(x, y)
    if not (ow.map:inBounds(x, y) and ow.map:isWalkableCell(x, y)) then return false end
    local n = ow:npcAtCell(x, y)
    return n == nil or n == rock
  end
  local cx, cy
  for y = 9, 40 do
    for x = 0, 60 do
      if not cx and free(x, y) then
        local all = true
        for _, d in ipairs(DIRS) do
          local s = STEP[d]
          if not (free(x + s[1], y + s[2]) and free(x + 2 * s[1], y + 2 * s[2])) then
            all = false
          end
        end
        if all then cx, cy = x, y end
      end
    end
  end
  if not check("found an open cross for pushes in all four directions", cx ~= nil) then
    finish()
  end
  U.log("push center", cx, cy)

  local function setup(dir)
    for _, d in ipairs(DIRS) do game.input.state[d] = false end
    ow.dustAnim = nil
    ow.boulderTried = nil
    local s = STEP[dir]
    rock.cellX, rock.cellY = cx + s[1], cy + s[2]
    rock.px, rock.py = rock.cellX * 16, rock.cellY * 16
    rock.moving, rock.targetX, rock.targetY = false, nil, nil
    local p = ow.player
    p.cellX, p.cellY = cx, cy
    p.px, p.py = cx * 16, cy * 16
    p.moving, p.targetX, p.targetY = false, nil, nil
    p.facing = dir
    U.wait(8)
  end

  local function pushUntilDust(dir)
    local first = true
    for _ = 1, 300 do
      if ow.dustAnim and ow.dustAnim.boulder then return ow.dustAnim end
      if first then table.insert(game.input.pressQueue, dir); first = false end
      game.input.state[dir] = true
      U.wait(1)
    end
    return nil
  end

  local marks = {}
  for _, dir in ipairs(DIRS) do
    setup(dir)
    local s = STEP[dir]
    local da = pushUntilDust(dir)
    if check(dir .. ": boulder dust starts after the push", da ~= nil) then
      check(dir .. ": dust anchored on the boulder's new cell",
            da.x == cx + 2 * s[1] and da.y == cy + 2 * s[2])
      check(dir .. ": first step already 1px toward the player, faded",
            da.ox == -s[1] and da.oy == -s[2] and da.faded == true)
      local n, lockHeld, maxStep, order = 0, true, 0, true
      local m = {}
      while ow.dustAnim == da and n < 120 do
        local k = math.abs(da.ox) + math.abs(da.oy)
        if k < maxStep then order = false end
        maxStep = math.max(maxStep, k)
        if not m[k] then m[k] = n end
        if ow.player.moving or ow.player.cellX ~= cx or ow.player.cellY ~= cy then
          lockHeld = false
        end
        game.input.state[dir] = true
        n = n + 1
        U.wait(1)
      end
      game.input.state[dir] = false
      marks[dir] = m
      U.log(dir, "dust frames", n)
      check(dir .. ": dust lasts 24 frames (8 x Delay3)", n == 24)
      check(dir .. ": dust slides 1px per step, 8px total", order and maxStep == 8)
      check(dir .. ": player cannot step while the dust plays", lockHeld)
    end
    U.wait(20)
  end

  for _, dir in ipairs(DIRS) do
    local m = marks[dir]
    if m then
      setup(dir)
      local da = pushUntilDust(dir)
      if da then
        local t0 = U.frame()
        U.shot(game, ("%s/2263_%s_01_dust_step1_under_boulder.png"):format(DIR, dir))
        while ow.dustAnim == da and U.frame() - t0 < (m[4] or 9) do
          game.input.state[dir] = true
          U.wait(1)
        end
        U.shot(game, ("%s/2263_%s_02_dust_mid_slide.png"):format(DIR, dir))
        while ow.dustAnim == da and U.frame() - t0 < (m[8] or 21) do
          game.input.state[dir] = true
          U.wait(1)
        end
        U.shot(game, ("%s/2263_%s_03_dust_half_over_old_cell.png"):format(DIR, dir))
        game.input.state[dir] = false
      end
      U.wait(40)
    end
  end

  ow:startDustAnim(cx, cy, nil)
  check("cut puff keeps its static 32-frame timing",
        ow.dustAnim.frames == 32 and ow.dustAnim.ox == nil and not ow.dustAnim.boulder)
  ow.dustAnim = nil

  finish()
end
