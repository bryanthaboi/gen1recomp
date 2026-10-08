package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local session, pending, calls
local player = { cellX = 6, cellY = 23, facing = "down" }
package.loaded["src.core.game3.player"] = player
package.loaded["src.mods.Runtime"] = { wants = function() return false end }
package.loaded["src.core.game3.runtime"] = { getSession = function() return session end }
package.loaded["src.core.game3.rom_text"] = { ascii = function(label) return label end }
package.loaded["src.ui.game3.message"] = {}
package.loaded["src.core.game3.field_modules"] = { enabled = function() return false end }
package.loaded["src.core.game3.audio"] = { playSe = function() calls.sounds = calls.sounds + 1 end }
package.loaded["src.core.game3.objects"] = { removeObject = function(id) calls.removed = id end }
package.loaded["src.core.game3.rse.init"] = {
  session = function() return session end,
  flag = function(name, s) return (s or session).puzzleFlags[name] == true end,
  setFlag = function(name, on, s) (s or session).puzzleFlags[name] = on end,
}
package.loaded["src.core.game3.field_move_show_mon"] = {
  start = function(mon, _, done)
    T.eq(mon, session.party[1], "the selected party mon reaches the real show-mon boundary")
    pending = done
  end,
}
package.loaded["src.core.game3.field_effects"] = {
  startRockSmash = function(_, _, _, done) calls.rock = calls.rock + 1; done() end,
  startFlash = function(done) calls.flash = calls.flash + 1; done() end,
}
local scriptVm = { ctx = {} }
package.loaded["src.core.game3.scripting.space"] = {
  vm = scriptVm,
  scriptKey = function(name)
    T.eq(name, "EventScript_UseFlash", "ordinary Emerald Flash resolves its profile ROM label")
    return "fixture_flash"
  end,
  startScript = function(key)
    T.eq(key, "fixture_flash", "ordinary Emerald Flash dispatches the resolved cached script")
    T.check(scriptVm.ctx.fieldControlsLocked, "ordinary Emerald Flash gives the VM the field lock")
    calls.flash, calls.flashScript = calls.flash + 1, key
    scriptVm.ctx.fieldControlsLocked = nil
    package.loaded["src.core.game3.field"].unlock()
    return true
  end,
}

local GameVersion = require("src.core.GameVersion")
GameVersion.set("emerald")
local Constants = require("src.core.game3.constants")
local Braille = require("src.core.game3.braille_field")
local FieldMoves = require("src.core.game3.field_moves")
local Field = require("src.core.game3.field")
local realRegiEffect = Braille.doRegiEffect
Braille.doRegiEffect = function(s) calls.puzzle = calls.puzzle + 1; realRegiEffect(s) end
Field.tryRockSmashEncounter = function() calls.encounters = calls.encounters + 1 end

local function testCase(case)
  local steel = case.move == "FLASH"
  local flag = steel and "FLAG_SYS_REGISTEEL_PUZZLE_COMPLETED" or "FLAG_SYS_REGIROCK_PUZZLE_COMPLETED"
  pending = nil
  calls = { puzzle = 0, rock = 0, flash = 0, sounds = 0, encounters = 0 }
  session = { version = case.version or "emerald", map = case.map or (steel and "EM_ANCIENT_TOMB" or "EM_DESERT_RUINS"),
    badges = { FLASH = case.badge ~= false, ROCK_SMASH = case.badge ~= false },
    x = case.x or (steel and 8 or 6), y = case.y or (steel and 25 or 23),
    party = { { species = 1 } }, puzzleFlags = {} }
  if case.completed then session.puzzleFlags[flag] = true end
  GameVersion.set(session.version)
  player.cellX, player.cellY, player.facing = session.x, session.y, case.facing or "down"
  Field._session, Field._game, Field._locks = session, { session = session, data = { maps = {} } }, {}
  Field._fieldCallback, Field._flyLanding, Field._fallWarp = nil, nil, nil
  Field.clearMetatiles()
  if case.namedLock then Field.lock("script") end
  local target = case.rock and { localId = 42, graphicsId = FieldMoves.GFX_IDS.ROCK_SMASH_ROCK } or nil
  local result = FieldMoves.fromMenu(case.move, { session = session, party = session.party, mon = session.party[1],
    facingObject = target, isCave = case.cave, isFlashActive = case.active })
  T.eq(result.ok, case.ok ~= false, case.name .. " menu eligibility")
  if case.ok == false then
    T.eq(pending, nil, case.name .. " rejected menu use starts no animation")
    T.eq(calls.puzzle, 0, case.name .. " rejected menu use opens no doorway")
    return
  end
  local expected = case.puzzle and (steel and "braille_registeel" or "braille_regirock")
    or (steel and "flash" or "rock_smash")
  T.eq(result.action, expected, case.name .. " chooses puzzle or ordinary action")
  T.eq(result.mon, session.party[1], case.name .. " retains selected mon")
  if not result.ok then return end
  Field.executeFieldMove(result)
  T.check(Field._locks.default, case.name .. " locks for the mon animation")
  T.eq(calls.puzzle + calls.rock + calls.flash, 0, case.name .. " does not run effects before animation completion")
  T.eq(session.puzzleFlags[flag], case.completed and true or nil, case.name .. " flag unchanged during animation")
  T.check(type(pending) == "function", case.name .. " registers the animation callback")
  if not pending then return end
  if case.interfere then Braille.isRegisteel = not steel end
  if case.moveAway then player.cellY = player.cellY + 1 end
  if case.completeDuringAnimation then session.puzzleFlags[flag] = true end
  if case.changeVersion then session.version = "firered" end
  pending()
  local shouldOpen = case.puzzle and not (case.moveAway or case.completeDuringAnimation or case.changeVersion)
  T.eq(calls.puzzle, shouldOpen and 1 or 0, case.name .. " calls the door effect exactly when valid")
  T.eq(calls.rock, not case.puzzle and not steel and 1 or 0, case.name .. " preserves normal Rock Smash")
  T.eq(calls.flash, not case.puzzle and steel and 1 or 0, case.name .. " preserves normal Flash")
  T.eq(calls.flashScript, not case.puzzle and steel and session.version == "emerald" and "fixture_flash" or nil,
    case.name .. " dispatches the Emerald cached Flash script only for ordinary Emerald Flash")
  T.eq(Field._locks.default, nil, case.name .. " releases only the move lock")
  T.eq(Field.locked, case.namedLock == true, case.name .. " preserves named lock ownership")
  if shouldOpen then
    T.eq(session.puzzleFlags[flag], true, case.name .. " sets its completion flag")
    local other = steel and "FLAG_SYS_REGIROCK_PUZZLE_COMPLETED" or "FLAG_SYS_REGISTEEL_PUZZLE_COMPLETED"
    T.eq(session.puzzleFlags[other], nil, case.name .. " does not open the other Regi door")
    for row, vertical in ipairs({ "Top", "Bottom" }) do
      for column, horizontal in ipairs({ "Left", "Mid", "Right" }) do
        local ov = Field.metatileOverrideAt(session.map, column + 6, row + 18)
        local mid = Constants.of("emerald"):require("metatile_labels", "METATILE_Cave_SealedChamberEntrance_" .. vertical .. horizontal)
        T.eq(ov and ov.metatile, mid, case.name .. " writes the ROM doorway " .. vertical .. horizontal)
        T.eq(ov and ov.impassable, row == 2 and column ~= 2, case.name .. " writes doorway collision " .. vertical .. horizontal)
      end
    end
  elseif not case.puzzle and not steel then
    T.eq(calls.removed, target.localId, case.name .. " removes only the ordinary rock")
    T.eq(calls.encounters, 1, case.name .. " keeps ordinary Rock Smash encounters")
  end
end

testCase({ name = "Regirock left column", move = "ROCK_SMASH", x = 5, puzzle = true })
testCase({ name = "Regirock center with independent lock", move = "ROCK_SMASH", puzzle = true, namedLock = true })
testCase({ name = "Regirock right facing sideways", move = "ROCK_SMASH", x = 7, facing = "right", puzzle = true, interfere = true })
testCase({ name = "Registeel without dark cave", move = "FLASH", puzzle = true })
testCase({ name = "Registeel despite existing cave Flash", move = "FLASH", active = true, puzzle = true })
testCase({ name = "Regirock wrong column without rock", move = "ROCK_SMASH", x = 4, ok = false })
testCase({ name = "Regirock wrong row with normal rock", move = "ROCK_SMASH", y = 22, rock = true })
testCase({ name = "Regirock completed with normal rock", move = "ROCK_SMASH", completed = true, rock = true })
testCase({ name = "Registeel wrong column without cave", move = "FLASH", x = 7, ok = false })
testCase({ name = "Registeel completed normal cave", move = "FLASH", completed = true, cave = true })
testCase({ name = "Registeel wrong map normal cave", move = "FLASH", map = "EM_GRANITE_CAVE_1F", cave = true })
testCase({ name = "ordinary active Flash remains rejected", move = "FLASH", map = "EM_GRANITE_CAVE_1F", cave = true, active = true, ok = false })
testCase({ name = "FireRed ordinary rock", move = "ROCK_SMASH", version = "firered", rock = true })
testCase({ name = "FireRed ordinary Flash", move = "FLASH", version = "firered", cave = true })
testCase({ name = "FireRed no rock at would-be puzzle", move = "ROCK_SMASH", version = "firered", ok = false })
testCase({ name = "FireRed non-dark would-be tomb", move = "FLASH", version = "firered", ok = false })
testCase({ name = "Regirock still requires badge", move = "ROCK_SMASH", badge = false, ok = false })
testCase({ name = "Registeel still requires badge", move = "FLASH", badge = false, ok = false })
testCase({ name = "Regirock moves away during animation", move = "ROCK_SMASH", puzzle = true, moveAway = true })
testCase({ name = "Registeel completed during animation", move = "FLASH", puzzle = true, completeDuringAnimation = true })
testCase({ name = "Registeel changes version during animation", move = "FLASH", puzzle = true, changeVersion = true })

T.finish("game3_braille_regi_field_moves_test")
