-- Manual check that Yellow's Pikachu watches the player while Bill walks
-- around them in Bill's House (#455).  BillsHouseScript2 (pokeyellow
-- scripts/BillsHouse.asm:58-69) only reaches BillsHousePikachuWatchPlayer
-- (scripts/BillsHouse_2.asm:133-156) while Pikachu still follows, which needs
-- BillsHouseScript0's CheckPikachuStatusCondition to have skipped the entry
-- beat, so this driver arrives with a statused starter.  No POKEPORT_SPEED:
-- it scales the logic clock only and desyncs audio against the scripted walk.
--   POKEPORT_DRIVER=tests/drivers/bills_pikachu_watch_bug455_test.lua POKEPORT_IDENTITY=bug455 POKEPORT_TOUCH=0 POKEPORT_VERSION=yellow love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local GameVersion = require("src.core.GameVersion")
  local Pokemon = require("src.pokemon.Pokemon")
  local PikachuFollower = require("src.world.PikachuFollower")

  local SHOT_DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  local function idle()
    while true do coroutine.yield() end
  end

  -- Red and Blue have no follower and no Pikachu beats at all, so every line
  -- below would fail for the wrong reason on the wrong cache
  if not check("running the Yellow cache (POKEPORT_VERSION=yellow)",
               GameVersion.isYellow()) then
    U.log("Re-run with POKEPORT_VERSION=yellow.")
    idle()
  end

  -- pokeyellow data/maps/objects/BillsHouse.asm: BILLSHOUSE_BILL_POKEMON sits
  -- at (6,5), the two warps at (2,7) and (3,7).  Standing at (6,4) facing down
  -- both faces the monster and puts the player on Bill's straight path up, the
  -- one branch that runs the walk-around (and so the watch beat).
  local MAP = "BILLS_HOUSE"
  local MONSTER = "BILLSHOUSE_BILL_POKEMON"
  local STAND = { x = 6, y = 4, facing = "down" }

  -- the scripted rows and the port entry point the scene hangs off; a renamed
  -- key reads on screen as "talking to Bill does nothing special"
  local story = dofile("data/scripts/story.lua")
  local house = story.BILLS_HOUSE or {}
  check("story.BILLS_HOUSE.talk.TEXT_BILLSHOUSE_BILL_POKEMON is present",
        type((house.talk or {}).TEXT_BILLSHOUSE_BILL_POKEMON) == "function")
  check("story.BILLS_HOUSE.onEnter is present",
        type(house.onEnter) == "function")
  check("PikachuFollower.onBillWalksAroundPlayer exists",
        type(PikachuFollower.onBillWalksAroundPlayer) == "function")

  -- both boxes of the scene come out of the cache; a missing key falls back to
  -- a hardcoded string in story.lua, which still runs but is not what shipped
  local t = game.data.text or {}
  check("_BillsHouseBillImNotAPokemonText resolved from the cache",
        type(t._BillsHouseBillImNotAPokemonText) == "string")
  check("_BillsHouseBillUseSeparationSystemText resolved from the cache",
        type(t._BillsHouseBillUseSeparationSystemText) == "string")

  -- ShouldPikachuSpawn's inputs (pikachu_follow.asm) plus the one that gates
  -- this bug: a starter carrying a status byte, which is what makes
  -- CheckPikachuStatusCondition set carry and BillsHouseScript0 stand down
  local pika = Pokemon.new(game.data, "PIKACHU", 12)
  pika.status = "PAR"
  game.save.party = { pika }
  game.save.player.name = "bryan"
  game.save.flags = game.save.flags or {}
  game.save.flags.EVENT_GOT_STARTER = true
  game.save.flags.EVENT_MET_BILL = nil
  game.save.flags.EVENT_MET_BILL_2 = nil
  game.save.flags.EVENT_BILL_SAID_USE_CELL_SEPARATOR = nil
  game.save.flags.EVENT_USED_CELL_SEPARATOR_ON_BILL = nil
  game.save.flags.EVENT_GOT_SS_TICKET = nil
  game.save.flags.EVENT_LEFT_BILLS_HOUSE_AFTER_HELPING = nil

  U.teleport(game, MAP, STAND.x, STAND.y, STAND.facing)
  U.wait(20)

  local ow = game.overworld
  if not check("Bill's House loaded", ow ~= nil and ow.map
               and ow.map.id == MAP) then
    idle()
  end

  local function follower()
    for _, n in ipairs(ow.npcs or {}) do
      if n.pikachuFollower then return n end
    end
    return nil
  end

  local function monster()
    for _, n in ipairs(ow.npcs or {}) do
      if n.def and n.def.name == MONSTER then return n end
    end
    return nil
  end

  local npc = follower()
  if not check("follower spawned with pikachuFollower set", npc ~= nil) then
    U.log("party PIKACHU hp:", tostring(game.save.party[1].hp),
          "status:", tostring(game.save.party[1].status),
          "EVENT_GOT_STARTER:", tostring(game.save.flags.EVENT_GOT_STARTER))
    idle()
  end

  local mon = monster()
  check("the monster object loaded on " .. MAP, mon ~= nil)
  if mon then
    U.log("monster at", mon.cellX, mon.cellY, "(objects file says 6, 5)")
  end

  -- the whole point of the arrival: the confused beat must not have run, so
  -- Pikachu is still on the follow loop rather than parked beside Bill
  check("the entry beat was skipped for a statused starter",
        ow.pikachuBillsScene ~= true)
  check("no question bubble is up from the entry beat", ow.emote == nil)

  local function facingMonster()
    if not mon then return false end
    local fx, fy = ow.player:facingCell()
    return ow:npcAtCell(fx, fy) == mon
  end

  if mon and not facingMonster() then
    -- a map edit or a mod moved the object: take any free walkable neighbour,
    -- preferring the cell above it since that is the facing-down branch.
    -- {dx, dy, facing} is the offset from the monster to the stand cell plus
    -- the direction that looks back at it, so +1 on y means facing up.
    local sides = {
      { 0, -1, "down" }, { 0, 1, "up" }, { -1, 0, "right" }, { 1, 0, "left" },
    }
    for _, s in ipairs(sides) do
      local cx, cy = mon.cellX + s[1], mon.cellY + s[2]
      if ow.map:inBounds(cx, cy) and ow.map:isWalkableCell(cx, cy)
         and not ow:npcAtCell(cx, cy) then
        U.log(("cell (%d, %d) is blocked, standing on"):format(STAND.x, STAND.y),
              cx, cy, "facing", s[3])
        U.teleport(game, MAP, cx, cy, s[3])
        U.wait(20)
        ow = game.overworld
        npc, mon = follower(), monster()
        break
      end
    end
  end
  check("the player is standing against the monster", facingMonster())
  check("the player faces down, the branch Bill walks around",
        ow.player.facing == "down")
  U.log("player at", ow.player.cellX, ow.player.cellY,
        "| Pikachu at", npc and npc.cellX, npc and npc.cellY)

  -- TryApplyPikachuMovementData keys off where Pikachu stands relative to the
  -- player, not off its sprite facing: above the player is WatchPlayer1 (left,
  -- down), level and east is WatchPlayer2 (up, left twice, down).  Anything
  -- else drops the data and no watch route runs at all.
  if npc then
    local route = npc.cellY < ow.player.cellY and "WatchPlayer1"
      or (npc.cellY == ow.player.cellY and npc.cellX > ow.player.cellX)
        and "WatchPlayer2" or nil
    check("Pikachu stands where one of the two watch tables applies",
          route ~= nil)
    U.log("geometry picks", route or "neither table")
  end

  -- a muted run makes the text beeps and Bill's step sfx indistinguishable
  -- from silence (Sound.setVolumeLevel reads save.options.sfxVol)
  local sfxVol = game.save.options and game.save.options.sfxVol
  U.log("save.options.sfxVol:", tostring(sfxVol))
  if (sfxVol or 0) == 0 then
    U.log("sfx volume is 0, so no beep can be heard whether or not one plays;")
    U.log("raise it in OPTIONS before judging the sound half")
  end

  -- record every cell the follower occupies so a route that runs and is then
  -- yanked back by the follow loop can be told from one that holds
  local trail = {}
  local function sample()
    if not npc then return end
    local last = trail[#trail]
    if not last or last.x ~= npc.cellX or last.y ~= npc.cellY
       or last.f ~= npc.facing then
      trail[#trail + 1] = { x = npc.cellX, y = npc.cellY, f = npc.facing }
    end
  end
  local function step(n)
    for _ = 1, n do
      sample()
      U.wait(1)
    end
    sample()
  end
  sample()

  -- talk, take YES (ChoiceBox defaults to it), then close the separation
  -- system line: that close is what runs the walk-around branch.  Stop
  -- pressing the moment the boxes are gone so a stray A cannot re-interact.
  -- FAST text: the reveal is per-character (TextBox drawChars reads
  -- save.options.textSpeed) and Bill's opener alone is four pages, so at
  -- the MEDIUM default the mash budget below runs out mid-box
  game.save.options = game.save.options or {}
  game.save.options.textSpeed = 1
  U.tap(game, "a")
  step(20)
  for _ = 1, 200 do
    if game.stack:top() == ow then break end
    U.tap(game, "a")
    step(8)
  end
  check("the dialogue finished and the map is running the walk",
        game.stack:top() == ow)

  -- let both scripted walks play out; Bill's is four legs, Pikachu's two
  for _ = 1, 400 do
    if #ow.scriptMoves == 0 and not ow.runner:isRunning() then break end
    step(1)
  end
  step(40)

  local cells = {}
  for _, c in ipairs(trail) do
    cells[#cells + 1] = ("(%d,%d %s)"):format(c.x, c.y, tostring(c.f))
  end
  U.log("Pikachu's cells through the scene:", table.concat(cells, " "))

  if npc then
    check("Pikachu ended west of the player, clear of Bill's detour",
          npc.cellY == ow.player.cellY and npc.cellX < ow.player.cellX)
    -- read the facing out of the recorded trail rather than off the sprite:
    -- by now an idle glance (pokeyellow Func_fc803) may already have turned
    -- its head, and that is vanilla, not the route failing to end on LOOK_RIGHT
    local lookedRight = false
    for _, c in ipairs(trail) do
      if c.y == ow.player.cellY and c.x < ow.player.cellX
         and c.f == "right" then
        lookedRight = true
      end
    end
    check("PIKAMOVEMENT_LOOK_RIGHT left it facing the player", lookedRight)
    check("it moved at all (the watch route ran)", #trail > 1)
  end
  check("Bill reached the machine (the separator is armed)",
        game.save.flags.EVENT_BILL_SAID_USE_CELL_SEPARATOR == true)

  -- hold still for a moment and see whether the follow loop reclaims it;
  -- cells only, because the idle glances (PikachuFollower's port of
  -- pokeyellow Func_fc803, a random look every ~0x20 frames) legitimately
  -- turn its head while it waits
  local settled = npc and { x = npc.cellX, y = npc.cellY }
  step(90)
  if npc and settled then
    check("it stayed put once the scene ended",
          npc.cellX == settled.x and npc.cellY == settled.y)
  end

  if U.shot(game, SHOT_DIR .. "/bug455_bills_watch.png") then
    U.log("captured", SHOT_DIR .. "/bug455_bills_watch.png")
  end

  U.log("The scene has already played; the screen is where it left off.")
  U.log("Pikachu should have stepped one cell west and one south out of Bill's")
  U.log("way, then turned to face right and held there watching you while Bill")
  U.log("climbed into the machine. Two near misses to watch for: Pikachu")
  U.log("parked beside Bill with a question bubble the moment you walked in,")
  U.log("which means the status gate never took and the watch beat cannot")
  U.log("happen; or Pikachu walking the route and snapping straight back to")
  U.log("your heel, which reads as a twitch instead of a reposition.")
  U.log("Input is yours now. Stepping out to Route 25 puts the monster back")
  U.log("(Route25ToggleBillsScript), so walk back in to (6,4) facing down and")
  U.log("talk to it again to replay the whole beat as often as you like.")

  idle()
end
