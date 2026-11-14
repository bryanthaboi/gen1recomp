local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_transitions"

local DEFAULT = {
  "SLICE", "SHRED_SPLIT", "BLACKHOLE", "BLACKHOLE_PULSATE", "RECTANGULAR_SPIRAL",
  "FRONTIER_LOGO_WIGGLE", "FRONTIER_LOGO_WAVE", "FRONTIER_SQUARES", "FRONTIER_SQUARES_SCROLL",
  "FRONTIER_SQUARES_SPIRAL", "FRONTIER_CIRCLES_MEET", "FRONTIER_CIRCLES_CROSS",
  "FRONTIER_CIRCLES_ASYMMETRIC_SPIRAL", "FRONTIER_CIRCLES_SYMMETRIC_SPIRAL", "FRONTIER_CIRCLES_MEET_IN_SEQ",
  "FRONTIER_CIRCLES_CROSS_IN_SEQ", "FRONTIER_CIRCLES_ASYMMETRIC_SPIRAL_IN_SEQ",
  "FRONTIER_CIRCLES_SYMMETRIC_SPIRAL_IN_SEQ",
}
local HANGS = { SHRED_SPLIT = 400 }

return function(game)
  local fails = 0
  local function result(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then fails = fails + 1 end
  end

  local noPort, errs = {}, {}
  local realPrint = print
  print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    local s = table.concat(parts, " ")
    if s:find("has no port", 1, true) then noPort[#noPort + 1] = s end
    if s:find("[game3/battle_transition]", 1, true) and not s:find("has no port", 1, true) then errs[#errs + 1] = s end
    realPrint(...)
  end

  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "NICK", gender = 0 })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local BattleTransition = require("src.core.game3.battle_transition")
  local Map = require("src.core.game3.map")
  local C = require("src.core.game3.constants").of("emerald")
  local session = Runtime.getSession()
  result(session ~= nil, "field session exists")
  if not session then love.event.quit(1) return end

  local ok, err = pcall(function() Map.load(nil, game, "EM_ROUTE117", { x = 32, y = 15, facing = "left" }) end)
  result(ok, "load EM_ROUTE117 " .. tostring(err or ""))
  U.wait(300)
  session.party = {}
  Party.giveMon(session, C.species.byName.SPECIES_SALAMENCE, 50, "SALAMENCE")

  local every = os.getenv("EM_TR_EVERY") == "1"
  local list = {}
  for name in (os.getenv("EM_TR_LIST") or table.concat(DEFAULT, ",")):gmatch("[^,]+") do list[#list + 1] = name end

  local Ids = BattleTransition.ids("rse")
  for _, name in ipairs(list) do
    local tid = Ids.ID[name]
    result(tid ~= nil, name .. " has an Emerald id")
    if tid then
      if HANGS[name] then
        pcall(function() Map.load(nil, game, "EM_ROUTE117", { x = 33, y = 15, facing = "left" }) end)
        U.wait(300)
      end
      local before = #noPort
      local okS, serr = BattleBridge.startWild(Runtime._mod, game,
        { species = C.species.byName.SPECIES_ODDISH, level = 14 }, { transitionId = tid })
      result(okS == true, name .. " battle started " .. tostring(serr or ""))
      local frames, mainAt, trace = 0, nil, {}
      local aliasFrames, stripRows = 0, 0
      local limit = HANGS[name] or 900
      while frames < limit do
        U.wait(1)
        frames = frames + 1
        local phase = BattleTransition._phase
        local fx = BattleTransition._fx
        if phase == "main" and not mainAt then mainAt = frames end
        trace[#trace + 1] = string.format("%s%s", phase:sub(1, 1), fx and tostring(fx.state) or "-")
        if name == "SHRED_SPLIT" and fx and fx.shred1 and fx.shred1[160] == (fx.t.cameraX - 240) % 0x10000 then
          aliasFrames = aliasFrames + 1
          local row0 = BattleTransition.blackSpans(0, 0, 240)
          for d = 1, 16 do
            local up = BattleTransition.blackSpans(-d, 0, 240)
            if #up == #row0 and up[1] == row0[1] and up[2] == row0[2] then stripRows = stripRows + 1 end
          end
        end
        if every then
          U.still(game, string.format("%s/%s/f%04d.png", DIR, name:lower(), frames))
        elseif mainAt and (frames - mainAt) % 12 == 0 and frames - mainAt <= 144 then
          U.still(game, string.format("%s/%s_%03d.png", DIR, name:lower(), frames - mainAt))
        end
        if Battle.isActive() then break end
      end
      local active = Battle.isActive()
      realPrint(string.format("[driver] %s id %d intro %s frames %d battle %s", name, tid, tostring(mainAt), frames,
        tostring(active)))
      realPrint("[driver] " .. name .. " trace " .. table.concat(trace, " "))
      result(#noPort == before, name .. " has a port (no SLICE fallback)")
      if HANGS[name] then
        result(not active and BattleTransition._fx and BattleTransition._fx.state == 2,
          name .. " stays in ShredSplit_BrokenCheck like the cart")
        result(aliasFrames > 0 and stripRows == 0, string.format(
          "%s row 0 alias strip stays on row 0 (%d margin rows copy it over %d frames)", name, stripRows, aliasFrames))
        BattleTransition.abort()
        local Field = package.loaded["src.core.game3.field"]
        if Field and Field.unlock then Field.unlock() end
        pcall(function() Map.load(nil, game, "EM_ROUTE117", { x = 32, y = 15, facing = "left" }) end)
      else
        result(active, name .. " ends and the battle starts")
        Battle.abort("run")
        for _ = 1, 600 do
          if not Battle.isActive() then break end
          U.wait(1)
        end
      end
      U.wait(60)
    end
  end

  print = realPrint
  for _, e in ipairs(errs) do print("[driver] transition error " .. e) end
  result(#errs == 0, "no battle_transition draw errors (" .. #errs .. ")")
  print(string.format("[driver] em_transitions: %d failure(s)", fails))
  love.event.quit(fails == 0 and 0 or 1)
end
