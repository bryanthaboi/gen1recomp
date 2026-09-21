local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_growth_evolution_species"

-- pokefirered/include/constants/species.h:299
local WURMPLE, SILCOON, CASCOON, NINCADA = 290, 291, 293, 301
-- pokefirered/include/constants/flags.h:1398
local FLAG_SYS_NATIONAL_DEX = 0x840
-- pokefirered/include/constants/vars.h:128
local VAR_NATIONAL_DEX = 0x404E

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS growth_evolution_species")
    love.event.quit(0)
  else
    print("FAIL growth_evolution_species failures=" .. failures)
    love.event.quit(1)
  end
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local Pokemon = require("src.core.game3.pokemon")
  local Evolution = require("src.core.game3.evolution")
  local Schema = require("src.core.game3.save_schema_firered")
  local Flags = require("src.core.game3.scripting.flags")
  local Space = require("src.core.game3.scripting.space")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local function ctx() return Space.vm and Space.vm.ctx end
  Flags.setFlag(Space.store, ctx(), FLAG_SYS_NATIONAL_DEX, true)
  Flags.setVar(Space.store, ctx(), VAR_NATIONAL_DEX, 0x6258)
  session.party = {}

  local ok, _, given = Party.giveMon(session, WURMPLE, 7)
  if not result(ok and given ~= nil, "a WURMPLE gift mon reached the party") then return finish() end
  result(given.speciesNumbering == Pokemon.NUMBERING_INTERNAL,
    "the mon the engine built is stamped " .. tostring(given.speciesNumbering))

  local saved = Schema.toSaveTable(session)
  for _, m in ipairs(saved.party or {}) do m.speciesNumbering = nil end
  result(session.party[1].speciesNumbering == nil,
    "an older save writes the same mon with no numbering at all")

  local loaded = Schema.fromSaveTable(saved)
  session.party = loaded.party
  local mon = session.party[1]
  result(mon.speciesNumbering == Pokemon.NUMBERING_INTERNAL,
    "loading that save stamps it internal again")
  local sp = Pokemon.speciesOf(mon)
  result(sp == WURMPLE, "the loaded mon reads as WURMPLE (" .. tostring(sp) .. ")")
  result(sp ~= NINCADA, "and not as national 290 NINCADA")
  result(Pokemon.displayName(mon) == "WURMPLE",
    "its display name is " .. tostring(Pokemon.displayName(mon)))

  local PartyMenu = require("src.ui.game3.party_menu")
  PartyMenu.show(session.party, { session = session })
  U.wait(150)
  result(U.shot(game, DIR .. "/growth_evolution_species_01_party.png"), "party menu shot")
  PartyMenu.close()
  U.wait(20)

  local SummaryMenu = require("src.ui.game3.summary_menu")
  SummaryMenu.openMenu(session.party, 1, { session = session })
  U.wait(150)
  result(U.shot(game, DIR .. "/growth_evolution_species_02_summary.png"), "summary shot")
  SummaryMenu.close()
  U.wait(30)

  -- pokefirered/src/pokemon.c:5095
  local upper = math.floor((tonumber(mon.personality) or 0) / 65536) % 65536
  local expected = ((upper % 10) <= 4) and SILCOON or CASCOON
  local expectedName = Pokemon.name(expected)
  local target, param = Evolution.levelTarget(mon, session)
  result(target == expected,
    "a level 7 WURMPLE with upper % 10 = " .. tostring(upper % 10) .. " evolves into "
    .. tostring(expectedName) .. " (" .. tostring(target) .. " param " .. tostring(param) .. ")")
  if not target then return finish() end

  local EvolutionScene = require("src.ui.game3.evolution_scene")
  EvolutionScene.start(mon, target, { session = session, canStop = false, via = "levelup" })
  local reached = false
  for _ = 1, 2400 do
    if EvolutionScene._state == "congrats" then reached = true break end
    U.wait(1)
  end
  result(reached, "the evolution scene reached its congratulations line")
  U.wait(200)
  result(U.shot(game, DIR .. "/growth_evolution_species_03_evolved.png"), "evolution scene shot")
  result(Pokemon.speciesOf(mon) == expected,
    "the mon is now " .. tostring(expectedName) .. " (" .. tostring(Pokemon.speciesOf(mon)) .. ")")
  result(mon.speciesNumbering == Pokemon.NUMBERING_INTERNAL, "and it is still stamped internal")

  for _ = 1, 600 do
    if not EvolutionScene.isOpen() then break end
    U.tap(game, "a")
    U.wait(10)
  end
  U.wait(30)
  finish()
end
