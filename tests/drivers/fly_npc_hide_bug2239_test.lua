local U = require("tests.drivers.util")

local SHOTS = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/pokeport-shots"

-- ../pokecrystal/engine/events/overworld.asm:611-624
local FROM = "NEW_BARK_TOWN"
local SPAWN, DEST = "SPAWN_ECRUTEAK", "ECRUTEAK_CITY"

return function(game)
  local fails = 0
  local function say(line) print("[fly2239] " .. line) end
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    say((cond and "PASS " or "FAIL ") .. line)
  end

  U.wait(60)
  local world = game.world
  if not (world and world.map) then
    say("FAIL the world did not boot")
    love.event.quit(1)
    return
  end
  os.execute('mkdir -p "' .. SHOTS .. '" 2>/dev/null')

  world:warpToMapId(FROM, 5, 5, "down")
  U.wait(30)
  ok(world.map and world.map.id == FROM, "starting from " .. FROM)
  world.noWildEncounters = true

  local mon = { species = "PIDGEOT" }
  ok(world:flyIconFor(mon) ~= nil, "PIDGEOT has a fly icon")
  ok(world:flyTo(SPAWN, mon), "flyTo " .. SPAWN .. " starts")

  local function drawnNpcs()
    local hideAll = world:flyHides()
    if hideAll then return 0 end
    local filter = world.spriteFilter
    local n = 0
    for _, npc in ipairs(world.npcs or {}) do
      if (not filter or filter(npc)) and not npc.hiddenByMovement then
        n = n + 1
      end
    end
    return n
  end

  local MID = SHOTS .. "/2239_01_fade_in_no_npcs.png"
  local LANDED = SHOTS .. "/2239_02_landed_npcs_back.png"
  local arrived, landedAt, leaked, npcTotal, shotMid = false, nil, 0, 0, false
  for frame = 1, 900 do
    if world.map and world.map.id == DEST then arrived = true end
    if arrived and not landedAt then
      npcTotal = math.max(npcTotal, #(world.npcs or {}))
      local ms = world.mapSetup
      if not world.flyAnim and not world.flyHidden and not ms then
        landedAt = frame
      elseif drawnNpcs() > 0 then
        leaked = leaked + 1
      end
      if not shotMid and ms and ms.phase == "in" and not world.fadeHold
        and (world.fadeLevel or 1) <= 0.5 then
        shotMid = true
        game.capturePath = MID
      end
    end
    if landedAt and frame > landedAt + 6 then break end
    U.wait(1)
  end
  ok(arrived, "arrived at " .. DEST)
  ok(landedAt ~= nil, "the bird landed and the hide cleared")
  ok(npcTotal > 0, DEST .. " has objects to hide (" .. npcTotal .. ")")
  ok(leaked == 0, "SkipUpdateMapSprites: no NPC drawn from arrival until landing ("
    .. leaked .. " frames leaked)")
  ok(drawnNpcs() > 0, "RespawnPlayer: the objects are back after landing")
  U.shot(game, LANDED)
  local f = io.open(MID, "rb")
  ok(f ~= nil, "captured the empty fade-in")
  if f then f:close() end

  say(fails == 0 and "ALL PASS" or (fails .. " FAILURES"))
  love.event.quit(fails == 0 and 0 or 1)
end
