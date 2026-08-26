-- Driver: #1517, a Gen 2 stat block in a Gen 1 party.
--
-- Gen 1's party_struct carries one Special word (macros/ram.asm:28-37) and
-- PrintStatsBox reads four fixed cells, wLoadedMonAttack/Defense/Speed/Special
-- (engine/pokemon/status_screen.asm:238-287).  Gen 2 splits that word into
-- SpclAtk/SpclDef (pokegold macros/ram.asm:29-42), so a mod that wrote a Gen 2
-- block over a Yellow party leaves the port with no `special` to print.
--
--   cp -R ~/Library/Application\ Support/LOVE/pokemon-love2d/yellow \
--         ~/Library/Application\ Support/LOVE/bug1517/yellow
--   POKEPORT_VERSION=yellow POKEPORT_GAME=yellow POKEPORT_IDENTITY=bug1517 \
--     POKEPORT_TOUCH=0 POKEPORT_SPEED=8 SHOT_DIR=/tmp/bug1517 \
--     POKEPORT_DRIVER=tests/drivers/summary_stats_bug1517_test.lua love .
--
-- The copy is not optional: a fresh POKEPORT_IDENTITY has no cache and the
-- boot hangs with no output.
--
-- Pre-fix the LOVE window vanishes the moment STATS is chosen, with no error
-- screen and nothing on stdout (that silence is the other half of #1517).
-- Post-fix the status screen opens and SPECIAL reads the CalcStats value
-- logged below.  The run ends on the open screen, so a human takes the
-- controls at exactly the frame the reporter's build died on.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/bug1517"
  local Pokemon = require("src.pokemon.Pokemon")
  local Stats = require("src.pokemon.Stats")
  local SaveData = require("src.core.SaveData")
  local SummaryMenu = require("src.ui.SummaryMenu")

  local function top() return game.stack:top() end

  U.newGame(game)
  U.wait(20)

  -- BUTTERFREE because the reporter's party led with one, and CONFUSION is a
  -- special move, so the same block would have crashed Damage.applyStage.
  local species = game.data.pokemon.BUTTERFREE and "BUTTERFREE" or "PIDGEY"
  local def = game.data.pokemon[species]
  local mon = Pokemon.new(game.data, species, 21)
  local want = Stats.calc(def, 21, mon.dvs, mon.statExp)

  -- the shape src/battle/gen2/Mon.lua Mon.stats produces: no `special`
  mon.stats = {
    hp = want.hp, attack = want.attack, defense = want.defense,
    speed = want.speed, specialAttack = want.special, specialDefense = want.special,
  }
  mon.hp = mon.stats.hp
  game.save.party = { mon }
  U.log(("[1517] fixture: %s :L21, stats.special = %s, CalcStats says %d")
          :format(species, tostring(mon.stats.special), want.special))

  SaveData.validate(game.save, game.data)
  local after = game.save.party[1].stats
  U.log("[1517] after SaveData.validate, special = " .. tostring(after.special)
          .. ", specialAttack = " .. tostring(after.specialAttack))
  U.log("[1517] the repair layer is SaveData.validate -> scrubKnownMon -> "
          .. "Stats.ensure; a nil above means it did not run")

  U.teleport(game, "PALLET_TOWN", 10, 8, "down")
  U.wait(10)

  local function cursorTo(menu, field, wanted)
    for _ = 1, 40 do
      if not menu or menu[field] == wanted then return menu and menu[field] == wanted end
      U.tap(game, menu[field] < wanted and "down" or "up")
      U.wait(3)
    end
    return menu[field] == wanted
  end

  U.tap(game, "start")
  U.wait(10)
  local menu = top()
  if not (menu and menu.screenId == "StartMenu") then
    U.log("[1517] FAIL no start menu; top = " .. tostring(menu and menu.screenId))
    while true do coroutine.yield() end
  end
  local row
  for i, it in ipairs(menu.items or {}) do
    if it.label == "POKéMON" then row = i break end
  end
  if not (row and cursorTo(menu, "index", row)) then
    U.log("[1517] FAIL could not reach the POKéMON row")
    while true do coroutine.yield() end
  end
  U.tap(game, "a")
  U.wait(10)

  local party = top()
  if not (party and party.screenId == "PartyMenu") then
    U.log("[1517] FAIL no party menu; top = " .. tostring(party and party.screenId))
    while true do coroutine.yield() end
  end
  U.shot(game, DIR .. "/01-party-list.png")
  U.tap(game, "a")
  U.wait(8)
  local subRow
  for i, it in ipairs(party.subItems or {}) do
    if it.action == "stats" then subRow = i break end
  end
  if not (subRow and cursorTo(party, "subIndex", subRow)) then
    U.log("[1517] FAIL could not reach the STATS row")
    while true do coroutine.yield() end
  end
  U.shot(game, DIR .. "/02-stats-selected.png")

  U.log("[1517] opening STATS -- pre-fix the app dies here, silently")
  U.tap(game, "a")
  U.wait(30)

  local screen = top()
  local opened = getmetatable(screen) == SummaryMenu or screen.screenId == "SummaryMenu"
  U.log("[1517] SURVIVED, top = " .. tostring(screen and screen.screenId))
  U.shot(game, DIR .. "/03-status-screen.png")
  U.log(("[1517] %s: SPECIAL on screen must read %d")
          :format(opened and "read it off the frame" or "WRONG SCREEN", want.special))
  U.log("[1517] shots in " .. DIR .. " -- the status screen is yours")
  while true do coroutine.yield() end
end
