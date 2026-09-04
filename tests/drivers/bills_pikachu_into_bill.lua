return function(game)
  local U = dofile("tests/drivers/util.lua")
  local GameVersion = require("src.core.GameVersion")
  local Pokemon = require("src.pokemon.Pokemon")

  local SHOT_DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local PHASE = os.getenv("PHASE") or "all"
  local TICKS = tonumber(os.getenv("TICKS") or "") or 22

  local function idle()
    while true do coroutine.yield() end
  end

  if not GameVersion.isYellow() then
    U.log("FAIL not the yellow cache")
    idle()
  end

  local function stage()
    game.save.party = { Pokemon.new(game.data, "PIKACHU", 12) }
    game.save.player.name = "bryan"
    game.save.options = game.save.options or {}
    game.save.options.textSpeed = 1
    game.save.flags = game.save.flags or {}
    game.save.flags.EVENT_GOT_STARTER = true
    game.save.flags.EVENT_BATTLED_RIVAL_IN_OAKS_LAB = true
    game.save.flags.EVENT_MET_BILL = true
    game.save.flags.EVENT_MET_BILL_2 = nil
    game.save.flags.EVENT_BILL_SAID_USE_CELL_SEPARATOR = nil
    game.save.flags.EVENT_USED_CELL_SEPARATOR_ON_BILL = nil
    game.save.pikachuMapScriptActive = nil
  end

  local function findBill(ow)
    for _, n in ipairs(ow.npcs or {}) do
      if n.def and n.def.name == "BILLSHOUSE_BILL_POKEMON" then return n end
    end
    return nil
  end

  local function findFollower(ow)
    for _, n in ipairs(ow.npcs or {}) do
      if n.pikachuFollower then return n end
    end
    return nil
  end

  local function inList(list, e)
    for _, v in ipairs(list or {}) do if v == e then return true end end
    return false
  end

  local overlap = 0

  local function dump(tag, ow)
    local pk = findFollower(ow)
    local bill = findBill(ow)
    local p = ow.player
    if pk and bill and pk.cellX == bill.cellX and pk.cellY == bill.cellY then
      overlap = overlap + 1
    end
    U.log(string.format(
      "%s f=%d P=(%d,%d)%s pika=%s bill=%s emote=%s",
      tag, U.frame(), p.cellX, p.cellY, p.facing,
      pk and string.format("(%d,%d)px%d,%d mv=%s pass=%s npcs=%s ents=%s",
        pk.cellX, pk.cellY, pk.px, pk.py, tostring(pk.moving),
        tostring(pk.passable), tostring(inList(ow.npcs, pk)),
        tostring(inList(ow.entities, pk))) or "GONE",
      bill and string.format("(%d,%d)px%d,%d", bill.cellX, bill.cellY,
        bill.px, bill.py) or "HIDDEN",
      ow.emote and "yes" or "no"))
  end

  -- a scripted-walk run from an arbitrary start cell
  local function run(label, sx, sy, ticks)
    stage()
    U.teleport(game, "BILLS_HOUSE", sx, sy, "up")
    U.wait(4)
    local ow = game.overworld
    overlap = 0
    U.log("=== " .. label .. " start=(" .. sx .. "," .. sy .. ") scene="
          .. tostring(ow.pikachuBillsScene) .. " ===")
    local shot = false
    for _ = 1, ticks do
      dump(label, ow)
      if overlap > 0 and not shot then
        shot = true
        U.log("!!! " .. label .. " OVERLAP pikachu on Bill's cell")
        U.shot(game, SHOT_DIR .. "/" .. label .. "_overlap.png")
      end
      U.wait(4)
    end
    U.shot(game, SHOT_DIR .. "/" .. label .. "_end.png")
    U.log("=== " .. label .. " overlapTicks=" .. overlap .. " ===")
    return ow
  end

  if PHASE == "all" or PHASE == "A" then
    run("A_door37", 3, 7, TICKS)
    run("A_door27", 2, 7, TICKS)
    run("B_mid36", 3, 6, TICKS)
  end

  if PHASE == "all" or PHASE == "D" then
    -- the real user path: walk in the door, let the confused beat settle,
    -- then walk up column 6 onto the parked follower at (6,6) -- the only
    -- southern approach to Bill at (6,5).
    stage()
    U.teleport(game, "BILLS_HOUSE", 3, 7, "up")
    local ow = game.overworld
    for _ = 1, 600 do
      if ow.emote == nil and #(ow.scriptMoves or {}) == 0 then break end
      U.wait(1)
    end
    U.wait(20)
    overlap = 0
    dump("D_settled", ow)
    U.shot(game, SHOT_DIR .. "/D_settled.png")
    local function step(dir)
      local sx, sy = ow.player.cellX, ow.player.cellY
      for _ = 1, 90 do
        table.insert(game.input.pressQueue, dir)
        game.input.state[dir] = true
        coroutine.yield()
        if (ow.player.cellX ~= sx or ow.player.cellY ~= sy)
           and not ow.player.moving then break end
      end
      game.input.state[dir] = false
      U.wait(4)
      dump("D_step_" .. dir, ow)
    end
    step("right"); step("right"); step("right")
    step("up")
    U.shot(game, SHOT_DIR .. "/D_on_follower.png")
    local pk = findFollower(ow)
    U.log("D player=(" .. ow.player.cellX .. "," .. ow.player.cellY
          .. ") pika=" .. (pk and ("(" .. pk.cellX .. "," .. pk.cellY .. ")")
                           or "GONE"))
    if pk and pk.cellX == ow.player.cellX and pk.cellY == ow.player.cellY then
      U.log("!!! D PLAYER STANDS ON THE FOLLOWER (passable, same cell)")
    end
  end

  U.log("DONE")
  U.wait(2)
  love.event.quit()
  idle()
end
