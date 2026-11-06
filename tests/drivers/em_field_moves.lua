local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_field_moves"

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " em_field_moves failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not check(game.boot ~= nil, "boot reached") then return finish() end
  game:_handleBootAction({ action = "new_game", name = "BRENDAN", gender = 0 })
  U.wait(60)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Warp = require("src.core.game3.warp")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")
  local Party = require("src.core.game3.party")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Collision = require("src.core.game3.collision")
  local Objects = require("src.core.game3.objects")
  local FieldMoves = require("src.core.game3.field_moves")
  local Field = require("src.core.game3.field")
  local MB = require("src.core.game3.mb")
  local C = require("src.core.game3.constants").of("emerald")
  local session = Runtime.getSession()
  if not check(session ~= nil, "field session exists") then return finish() end
  local IDS = Flags.forVersion("emerald").IDS
  local function mv(n) return C.moves.byName["MOVE_" .. n] end

  session.party = {}
  Party.giveMon(session, C.species.byName.SPECIES_SWAMPERT, 50, "SWAMPERT")
  session.party[1].moves = { mv("CUT"), mv("ROCK_SMASH"), mv("STRENGTH"), mv("SURF") }
  Party.giveMon(session, C.species.byName.SPECIES_GYARADOS, 50, "GYARADOS")
  session.party[2].moves = { mv("WATERFALL"), mv("DIVE"), mv("BITE"), mv("FLASH") }

  local function badge(n, on) Flags.setFlag(Space.store, nil, IDS[string.format("FLAG_BADGE0%d_GET", n)], on) end
  for i = 1, 8 do badge(i, false) end

  -- pokeemerald/src/party_menu.c:3725
  local order = FieldMoves.menuOrder()
  check(order ~= nil and order[1] == "CUT" and order[7] == "DIVE" and order[8] == "WATERFALL" and order[11] == "SECRET_POWER",
    "Emerald field move menu order CUT..WATERFALL, SECRET_POWER at 11")
  local expect = { CUT = 1, FLASH = 2, ROCK_SMASH = 3, STRENGTH = 4, SURF = 5, FLY = 6, DIVE = 7, WATERFALL = 8 }
  local matrixOk = true
  for name, n in pairs(expect) do
    if FieldMoves.badgeFlag(name) ~= IDS[string.format("FLAG_BADGE0%d_GET", n)] then
      matrixOk = false
      print("[driver] badge mismatch " .. name)
    end
  end
  check(matrixOk, "HM badge gates: CUT 1, FLASH 2, ROCK_SMASH 3, STRENGTH 4, SURF 5, FLY 6, DIVE 7, WATERFALL 8")
  local res = FieldMoves.fromMenu("DIVE", { party = session.party, store = Space.store, session = session })
  check(res and not res.ok and res.badge == "DIVE", "DIVE from the party menu is badge-gated before the Mind Badge")

  local function pump(pred, frames, answer, shoot)
    local seen = { texts = {} }
    for _ = 1, frames or 600 do
      if pred() then return true, seen end
      if (Choice.isOpen and Choice.isOpen()) or Message._choice then
        seen.choice = true
        if answer == "no" then U.tap(game, "down") U.wait(2) end
        U.tap(game, "a")
      elseif Message.isOpen and Message.isOpen() then
        local page = Message.currentPage()
        if seen.texts[#seen.texts] ~= page then seen.texts[#seen.texts + 1] = page end
        if shoot and not shoot.done and page:find(shoot.find, 1, true) then
          for _ = 1, 240 do if not Message.isTyping() then break end U.wait(1) end
          shoot.done = U.shot(game, shoot.path) ~= false
        end
        U.tap(game, "a")
        U.wait(3)
      else
        U.wait(1)
      end
    end
    return pred(), seen
  end

  local function idle()
    return not (Space.vm and Space.vm:isRunning()) and not Message.isOpen() and not Field.locked
      and not Warp.isBusy() and not (Choice.isOpen and Choice.isOpen())
      and not require("src.core.game3.field_move_show_mon").isActive()
  end

  local function place(mapId, x, y, facing, surfing)
    for _ = 1, 300 do if idle() then break end U.wait(1) end
    Map.load(nil, game, mapId, { x = x, y = y, facing = facing })
    local s = Runtime.getSession()
    s.x, s.y, s.facing = x, y, facing
    Player.surfing = surfing == true
    Field.unlock()
    U.wait(20)
  end

  local function removed(lid)
    local o = Objects.find(lid)
    return o == nil or o.hidden == true
  end

  local function joined(seen) return table.concat(seen.texts, " | ") end

  place("EM_ROUTE116", 21, 7, "up")
  check(Objects.find(4) ~= nil, "Route 116 cuttable tree lid 4 present")
  U.tap(game, "a")
  local _, seen = pump(idle, 300)
  check(not seen.choice and joined(seen):find("CUT down") ~= nil, "no Stone Badge: Text_CantCut (" .. joined(seen) .. ")")
  badge(1, true)
  U.tap(game, "a")
  U.wait(20)
  U.shot(game, DIR .. "/01_cut_prompt.png")
  local gone
  gone, seen = pump(function() return removed(4) and idle() end, 900)
  check(seen.choice == true, "Stone Badge: Text_WantToCut asks YES/NO (" .. joined(seen) .. ")")
  check(gone, "YES cuts the tree down (lid 4 removed: " .. tostring(removed(4)) .. ")")
  check(joined(seen):find("SWAMPERT used CUT!", 1, true) ~= nil, "Text_MonUsedFieldMove names the mon and the move")
  U.shot(game, DIR .. "/02_cut_done.png")

  local rx, ry = 29, 51
  place("EM_ROUTE115", rx, ry, "up")
  if not Collision.isWalkable(rx, ry) then place("EM_ROUTE115", 28, 50, "right") end
  check(Objects.find(15) ~= nil, "Route 115 breakable rock lid 15 present")
  U.tap(game, "a")
  _, seen = pump(idle, 300)
  check(not seen.choice and joined(seen):find("rugged rock") ~= nil, "no Dynamo Badge: Text_CantSmash (" .. joined(seen) .. ")")
  badge(3, true)
  U.tap(game, "a")
  gone, seen = pump(function() return removed(15) and idle() end, 900)
  check(seen.choice == true or joined(seen):find("Would you like to use ROCK SMASH?", 1, true) ~= nil,
    "Dynamo Badge: Text_WantToSmash asks YES/NO (" .. joined(seen) .. ")")
  check(gone, "ROCK SMASH breaks the rock (lid 15 removed: " .. tostring(removed(15)) .. ")")
  U.shot(game, DIR .. "/03_rock_smash_done.png")
  pump(idle, 900)

  local strengthFlag = IDS.FLAG_SYS_USE_STRENGTH
  check(FieldMoves.SYS_FLAGS.USE_STRENGTH == strengthFlag, "USE_STRENGTH resolves to FLAG_SYS_USE_STRENGTH (" .. tostring(strengthFlag) .. ")")
  Flags.setFlag(Space.store, nil, strengthFlag, false)
  local bx, by = 10, 15
  local ax, ay, face = nil, nil, nil
  for _, d in ipairs({ { 0, 1, "up" }, { -1, 0, "right" }, { 1, 0, "left" }, { 0, -1, "down" } }) do
    place("EM_FIERY_PATH", bx + d[1], by + d[2], d[3])
    if Collision.isWalkable(bx + d[1], by + d[2]) and Collision.isWalkable(bx - d[1], by - d[2]) then
      ax, ay, face = bx + d[1], by + d[2], d[3]
      break
    end
  end
  check(ax ~= nil, "found a push lane for the Fiery Path boulder")
  if ax then
    place("EM_FIERY_PATH", ax, ay, face)
    U.tap(game, "a")
    _, seen = pump(idle, 300)
    check(not seen.choice and joined(seen):find("push it aside") ~= nil, "no Heat Badge: Text_CantStrength (" .. joined(seen) .. ")")
    badge(4, true)
    U.tap(game, "a")
    local on
    on, seen = pump(function() return Flags.getFlag(Space.store, nil, strengthFlag) == true and idle() end, 900, nil,
      { find = "used STRENGTH!", path = DIR .. "/04_mon_used_strength.png" })
    check(seen.choice and on, "Heat Badge: STRENGTH sets FLAG_SYS_USE_STRENGTH (" .. joined(seen) .. ")")
    -- pokeemerald/data/scripts/field_move_scripts.inc:170
    check(joined(seen):find("SWAMPERT used STRENGTH!", 1, true) ~= nil, "Text_MonUsedStrength names the mon (" .. joined(seen) .. ")")
    check(joined(seen):find("SWAMPERT's STRENGTH", 1, true) ~= nil, "Text_MonUsedStrength second page names the mon")
    local obj = Objects.find(2)
    local ox, oy = obj and obj.cellX, obj and obj.cellY
    U.hold(game, face, 20)
    pump(function() return idle() and not (obj and obj.moving) end, 120)
    check(obj and (obj.cellX ~= ox or obj.cellY ~= oy), string.format("the boulder moves when pushed (%s,%s -> %s,%s)",
      tostring(ox), tostring(oy), tostring(obj and obj.cellX), tostring(obj and obj.cellY)))
    U.shot(game, DIR .. "/04_strength_push.png")
  end

  place("EM_ROUTE119", 17, 30, "up")
  local wx, wy = nil, nil
  for y = 1, 138 do
    for x = 1, 38 do
      if not wx and Collision.behavior(x, y) == MB.id("WATERFALL") and Collision.isWater(x, y + 1)
          and Collision.behavior(x, y + 1) ~= MB.id("WATERFALL") then
        wx, wy = x, y
      end
    end
  end
  check(wx ~= nil, "Route 119 has a waterfall with water below (" .. tostring(wx) .. "," .. tostring(wy) .. ")")
  local sx, sy = nil, nil
  for y = 1, 138 do
    for x = 1, 38 do
      if not sx and Collision.isWalkable(x, y) and not Collision.isWater(x, y) and Collision.isWater(x, y - 1)
          and Collision.isSurfable(Collision.behavior(x, y - 1)) then
        sx, sy = x, y
      end
    end
  end
  check(sx ~= nil, "found a shore cell facing surfable water (" .. tostring(sx) .. "," .. tostring(sy) .. ")")
  if sx then
    place("EM_ROUTE119", sx, sy, "up")
    U.tap(game, "a")
    U.wait(20)
    check(not (Space.vm and Space.vm:isRunning()) and not Message.isOpen(), "no Balance Badge: A on water does nothing")
    badge(5, true)
    U.tap(game, "a")
    U.wait(4)
    check(Space.vm and Space.vm._scriptKey == Space.scriptKey("EventScript_UseSurf"), "Balance Badge: A on water runs EventScript_UseSurf")
    local surfed
    surfed, seen = pump(function() return Player.surfing and idle() end, 900)
    check(surfed, "surf prompt YES puts the player on the water (" .. joined(seen) .. ")")
    U.shot(game, DIR .. "/05_surfing.png")
  end
  if wx then
    place("EM_ROUTE119", wx, wy + 1, "up", true)
    U.tap(game, "a")
    _, seen = pump(idle, 400)
    check(joined(seen):find("wall of water") ~= nil, "no Rain Badge: EventScript_CannotUseWaterfall (" .. joined(seen) .. ")")
    badge(8, true)
    local startY = Player.cellY
    U.tap(game, "a")
    local climbed
    climbed, seen = pump(function() return Player.cellY < wy and idle() end, 1500)
    check(climbed, string.format("Rain Badge: WATERFALL climbs (%d -> %d) (%s)", startY, Player.cellY, joined(seen)))
    U.shot(game, DIR .. "/06_waterfall_top.png")
  end

  finish()
end
