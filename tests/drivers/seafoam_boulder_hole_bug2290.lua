-- scripts/SeafoamIslands1F.asm:1
--   POKEPORT_DRIVER=tests/drivers/seafoam_boulder_hole_bug2290.lua POKEPORT_IDENTITY=bsa0922-2290 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "/tmp/shots"
  local Sound = require("src.core.Sound")
  local MAP = "SEAFOAM_ISLANDS_1F"
  local HX, HY = 17, 6
  local EVENT = "EVENT_SEAFOAM1_BOULDER1_DOWN_HOLE"
  local DIRS = { "right", "left", "down", "up" }
  local STEP = { down = { 0, 1 }, up = { 0, -1 }, left = { -1, 0 }, right = { 1, 0 } }
  local BACK = { right = "left", left = "right", up = "down", down = "up" }

  local ok = true
  local function check(label, pass)
    U.log(pass and "PASS" or "FAIL", label)
    if not pass then ok = false end
    return pass
  end
  local function finish()
    for _, d in ipairs(DIRS) do game.input.state[d] = false end
    U.log(ok and "PASS seafoam_boulder_hole_2290" or "FAIL seafoam_boulder_hole_2290")
    love.event.quit(ok and 0 or 1)
    while true do coroutine.yield() end
  end

  if game.save.flags then game.save.flags[EVENT] = nil end
  U.teleport(game, MAP, 18, 11, "up")
  U.wait(10)
  local ow = game.overworld
  game.data.encounters[MAP] = nil
  local rock = ow and ow:npcAtCell(18, 10)
  if not check("1F boulder 1 present at (18,10)",
               rock ~= nil and rock.def.sprite == "SPRITE_BOULDER") then
    finish()
  end
  ow.strengthActive = true

  local function free(x, y)
    if not (ow.map:inBounds(x, y) and ow.map:isWalkableCell(x, y)) then return false end
    local n = ow:npcAtCell(x, y)
    return n == nil or n == rock
  end
  local pushDir
  for _, d in ipairs(DIRS) do
    local s = STEP[d]
    if not pushDir and free(HX - s[1], HY - s[2]) and free(HX - 2 * s[1], HY - 2 * s[2]) then
      pushDir = d
    end
  end
  if not check("found an approach lane into the hole at (17,6)", pushDir ~= nil) then
    finish()
  end
  local s = STEP[pushDir]
  rock.cellX, rock.cellY = HX - s[1], HY - s[2]
  rock.px, rock.py = rock.cellX * 16, rock.cellY * 16
  rock.moving, rock.targetX, rock.targetY = false, nil, nil
  local p = ow.player
  p.cellX, p.cellY = HX - 2 * s[1], HY - 2 * s[2]
  p.px, p.py = p.cellX * 16, p.cellY * 16
  p.moving, p.targetX, p.targetY = false, nil, nil
  p.facing = pushDir
  ow.boulderTried = nil
  U.wait(8)
  U.log("pushing", pushDir, "from", p.cellX, p.cellY)
  U.shot(game, DIR .. "/2290_01_boulder_next_to_hole.png")

  local cues = {}
  local realPlay = Sound.play
  Sound.play = function(data, key, ...)
    cues[#cues + 1] = tostring(key)
    return realPlay(data, key, ...)
  end

  local function inEntities()
    for _, e in ipairs(ow.entities) do if e == rock then return true end end
    return false
  end
  local first = true
  for _ = 1, 300 do
    if not inEntities() then break end
    if first then table.insert(game.input.pressQueue, pushDir); first = false end
    game.input.state[pushDir] = true
    U.wait(1)
  end
  game.input.state[pushDir] = false
  for _ = 1, 60 do
    if not ow.dustAnim then break end
    U.wait(1)
  end
  U.wait(4)
  Sound.play = realPlay

  check("boulder removed from 1F after reaching the hole", not inEntities())
  check(EVENT .. " is set", game.save.flags and game.save.flags[EVENT] == true)
  check("no text box on top after the fall", game.stack:top() == ow)
  local thud = false
  for _, c in ipairs(cues) do if c == "Faint_Thud" then thud = true end end
  U.log("sounds heard:", #cues > 0 and table.concat(cues, ", ") or "nothing")
  check("no Faint_Thud when the boulder falls", not thud)
  U.shot(game, DIR .. "/2290_02_boulder_gone_no_text.png")

  local back = BACK[pushDir]
  local bs = STEP[back]
  local sx, sy = p.cellX, p.cellY
  if free(sx + bs[1], sy + bs[2]) then
    U.hold(game, back, 20)
    U.wait(10)
    check("player walks right away without dismissing anything",
          p.cellX ~= sx or p.cellY ~= sy)
  else
    U.log("skip walk check: cell behind the player is blocked")
  end

  finish()
end
