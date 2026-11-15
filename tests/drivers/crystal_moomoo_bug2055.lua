local U = require("tests.drivers.util")

local FlagIds = require("src.core.gen2.FlagIds")

-- pokecrystal/maps/Route39Barn.asm:47
local BARN, MOOMOO_X, MOOMOO_Y = "ROUTE_39_BARN", 3, 4
local MILTANK_SPRITE = "SPRITE_TAUROS"
-- pokecrystal/ram/wram.asm:3142
local BERRIES = 0xd962

local SHOT_DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/pokeport-shots"

return function(game)
  local fails = 0
  local function say(line) print("[2055] " .. line) end
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    say((cond and "PASS " or "FAIL ") .. line)
  end

  U.wait(60)
  local world, save = game.world, game.save
  if not (world and world.map and world.vm and save) then
    say("FAIL the crystal world did not boot")
    love.event.quit(1)
    return
  end
  local events = FlagIds.events(game.data.gen2Constants)
  local HEALED = events.EVENT_HEALED_MOOMOO
  local TALKED = events.EVENT_TALKED_TO_FARMER_ABOUT_MOOMOO
  ok(HEALED == 61 and TALKED == 63, "the cache names the moomoo flags 61 and 63")

  save.inventory = save.inventory or {}
  save.inventory.BERRY = 10
  world.events:set(HEALED, false)
  world.events:set(TALKED, true)

  world:warpToMapId(BARN, MOOMOO_X, MOOMOO_Y, "up")
  U.wait(45)
  ok(world.map and world.map.def and world.map.def.id == BARN,
    "standing under the Miltank in the barn")

  local MOOMOO_KEY
  for _, obj in ipairs(((world.map or {}).def or {}).objects or {}) do
    if obj.sprite == MILTANK_SPRITE then MOOMOO_KEY = obj.scriptKey end
  end
  ok(MOOMOO_KEY ~= nil,
    "the barn's " .. MILTANK_SPRITE .. " object carries MoomooScript's key")
  say("MoomooScript key = " .. tostring(MOOMOO_KEY))

  local function settle()
    for _ = 1, 60 do
      if not world.vm:running() then return end
      U.wait(1)
    end
  end

  local function talkByButton()
    U.tap(game, "a")
    for _ = 1, 30 do
      U.wait(1)
      if world.vm:running() then break end
    end
    if not world.vm:running() then return false end
    for _ = 1, 400 do
      if not world.vm:running() then break end
      U.tap(game, "a")
      U.wait(4)
    end
    settle()
    return true
  end

  local function talkDirect()
    if not MOOMOO_KEY then return false end
    if not world.vm:start(MOOMOO_KEY) then return false end
    for _ = 1, 400 do
      if not world.vm:running() then break end
      U.tap(game, "a")
      U.wait(4)
    end
    settle()
    return true
  end

  local byButton = true
  for i = 1, 7 do
    local ran = byButton and talkByButton() or talkDirect()
    if not ran and byButton then
      ok(false, "A did not open MoomooScript from " .. MOOMOO_X .. ","
        .. MOOMOO_Y .. " facing up; falling back to a direct start")
      byButton = false
      ran = talkDirect()
    end
    ok(ran, ("talk %d ran MoomooScript"):format(i))
    say(("after %d: berries=%s event%d=%s busy=%s bag=%s"):format(
      i, tostring(world.vm.mem[BERRIES]), HEALED,
      tostring(world.events:get(HEALED)), tostring(world.vm:running()),
      tostring(save.inventory.BERRY)))
    ok(not world.vm:running(), ("talk %d parked nothing"):format(i))
    ok(world.vm.mem[BERRIES] == i,
      ("berry %d reached wMooMooBerries"):format(i))
  end

  -- pokecrystal/maps/Route39Barn.asm:106
  ok(world.events:get(HEALED),
    "EVENT_HEALED_MOOMOO is set after the seventh BERRY")
  ok(save.inventory.BERRY == 3, "seven BERRIES left the bag")
  U.shot(game, SHOT_DIR .. "/crystal_moomoo_after_7.png")

  if byButton then talkByButton() else talkDirect() end
  ok(world.events:get(HEALED), "and survives the next talk")
  ok(world.vm.mem[BERRIES] == 7, "which takes no eighth BERRY")
  U.shot(game, SHOT_DIR .. "/crystal_moomoo_next_talk.png")
  say("the next-talk shot must read \"MILTANK: Mooo!\", not the weak cry")

  say(fails == 0 and "all claims passed" or (fails .. " claims failed"))
  love.event.quit(fails == 0 and 0 or 1)
end
