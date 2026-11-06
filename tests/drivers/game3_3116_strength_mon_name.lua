local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_3116_strength_mon_name"

local PREFIX = { emerald = "EM_", ruby = "RU_", sapphire = "SA_" }

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " strength_mon_name failures=" .. failures)
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
  local Warp = require("src.core.game3.warp")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")
  local Party = require("src.core.game3.party")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Collision = require("src.core.game3.collision")
  local Objects = require("src.core.game3.objects")
  local Field = require("src.core.game3.field")
  local ShowMon = require("src.core.game3.field_move_show_mon")
  local session = Runtime.getSession()
  if not check(session ~= nil, "field session exists") then return finish() end
  local version = session.version
  local prefix = PREFIX[version]
  if not check(prefix ~= nil, "version is RSE (" .. tostring(version) .. ")") then return finish() end
  local C = require("src.core.game3.constants").of(version)
  local IDS = Flags.forVersion(version).IDS

  session.party = {}
  Party.giveMon(session, C.species.byName.SPECIES_MACHOKE, 40, "MACHOKE")
  session.party[1].moves = { C.moves.byName.MOVE_TACKLE }
  Party.giveMon(session, C.species.byName.SPECIES_SWAMPERT, 50, "SWAMPERT")
  session.party[2].moves = { C.moves.byName.MOVE_STRENGTH, C.moves.byName.MOVE_SURF }
  for i = 1, 8 do Flags.setFlag(Space.store, nil, IDS[string.format("FLAG_BADGE0%d_GET", i)], true) end
  local strengthFlag = IDS.FLAG_SYS_USE_STRENGTH
  Flags.setFlag(Space.store, nil, strengthFlag, false)

  local function idle()
    return not (Space.vm and Space.vm:isRunning()) and not Message.isOpen() and not Field.locked
      and not Warp.isBusy() and not (Choice.isOpen and Choice.isOpen()) and not ShowMon.isActive()
  end

  local function place(mapId, x, y, facing)
    for _ = 1, 300 do if idle() then break end U.wait(1) end
    Map.load(nil, game, mapId, { x = x, y = y, facing = facing })
    local s = Runtime.getSession()
    s.x, s.y, s.facing = x, y, facing
    Field.unlock()
    U.wait(20)
  end

  local shot = false
  local function pump(pred, frames)
    local seen = { texts = {} }
    for _ = 1, frames do
      if pred() then return true, seen end
      if (Choice.isOpen and Choice.isOpen()) or Message._choice then
        seen.choice = true
        U.tap(game, "a")
      elseif Message.isOpen() then
        local page = Message.currentPage()
        if seen.texts[#seen.texts] ~= page then seen.texts[#seen.texts + 1] = page end
        if not shot and page:find("used STRENGTH", 1, true) then
          for _ = 1, 240 do if not Message.isTyping() then break end U.wait(1) end
          shot = true
          U.shot(game, DIR .. "/3116_01_mon_used_strength_" .. version .. ".png")
        end
        U.tap(game, "a")
        U.wait(3)
      else
        U.wait(1)
      end
    end
    return pred(), seen
  end

  local map = prefix .. "FIERY_PATH"
  local bx, by = 10, 15
  local ax, ay, face
  for _, d in ipairs({ { 0, 1, "up" }, { -1, 0, "right" }, { 1, 0, "left" }, { 0, -1, "down" } }) do
    place(map, bx + d[1], by + d[2], d[3])
    if Collision.isWalkable(bx + d[1], by + d[2]) and Collision.isWalkable(bx - d[1], by - d[2]) then
      ax, ay, face = bx + d[1], by + d[2], d[3]
      break
    end
  end
  if not check(ax ~= nil, "found a push lane for the " .. map .. " boulder") then return finish() end
  place(map, ax, ay, face)
  check(Objects.find(2) ~= nil, map .. " boulder lid 2 present")
  U.tap(game, "a")
  local on, seen = pump(function() return Flags.getFlag(Space.store, nil, strengthFlag) == true and idle() end, 1200)
  local text = table.concat(seen.texts, " | "):gsub("\n", " / ")
  print("[driver] pages: " .. text)
  check(seen.choice and on, "YES sets FLAG_SYS_USE_STRENGTH")
  -- pokeemerald/data/scripts/field_move_scripts.inc:170
  -- pokeruby/data/field_move_scripts.inc:174
  check(text:find("SWAMPERT used STRENGTH", 1, true) ~= nil, "used STRENGTH page names the checkpartymove slot mon")
  check(text:find("SWAMPERT's STRENGTH", 1, true) ~= nil, "second page names the checkpartymove slot mon")
  check(text:find("MACHOKE", 1, true) == nil, "lead mon without STRENGTH is not named")
  check(shot, "shot of the used STRENGTH box taken")
  finish()
end
