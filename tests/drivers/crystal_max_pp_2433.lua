-- engine/items/item_effects.asm:2836
local U = require("tests.drivers.util")
local Boxes = require("src.core.gen2.Boxes")
local ItemEffects = require("src.core.gen2.ItemEffects")
local Mon = require("src.battle.gen2.Mon")
local Save = require("src.core.gen2.Save")
local SummaryMenu = require("src.ui.gen2.SummaryMenu")

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/crystal-max-pp-2433"
  local fails = 0
  local function ok(cond, label, detail)
    if not cond then fails = fails + 1 end
    print((cond and "PASS " or "FAIL ") .. label
      .. (detail and (" (" .. tostring(detail) .. ")") or ""))
  end
  local function movesLine(mon)
    local parts = {}
    for i, m in ipairs(mon.moves or {}) do
      parts[#parts + 1] = ("%d:%s %s/%s"):format(i, tostring(m.id),
        tostring(m.pp), tostring(m.maxPp))
    end
    return table.concat(parts, " ")
  end
  local function strip(mon)
    mon.moves[3].maxPp, mon.moves[3].pp = nil, 9
    mon.moves[4].maxPp, mon.moves[4].pp = nil, 1
  end

  local run, err = pcall(function()
    U.wait(60)
    local world = game.world
    assert(world and world.map, "no world")
    local save, data = game.save, game.data

    local toto = Mon.new(data, "TOTODILE", 16, {
      moves = {
        { id = "LEER", pp = 30, maxPp = 30 },
        { id = "SCRATCH", pp = 35, maxPp = 35 },
        { id = "RAGE", pp = 20, maxPp = 20 },
        { id = "WATER_GUN", pp = 25, maxPp = 25 },
      },
    })
    strip(toto)
    save.party = { toto, Mon.new(data, "GASTLY", 16) }
    print("[2433] start " .. movesLine(toto))

    assert(Save.save(save), "save")
    local loaded = Save.load(save.version)
    Mon.syncSaveIdentity(loaded, data)
    local back = loaded.party[1]
    print("[2433] reloaded " .. movesLine(back))
    ok(back.moves[3].maxPp == 20, "reload_rage_max_20", back.moves[3].maxPp)
    ok(back.moves[4].maxPp == 25, "reload_water_gun_max_25", back.moves[4].maxPp)
    ok(back.moves[3].pp == 9 and back.moves[4].pp == 1,
      "reload_keeps_current_pp", movesLine(back))
    save.party = loaded.party

    local summary = SummaryMenu.new(game, {
      party = save.party, index = 1, save = save,
      page = SummaryMenu.GREEN_PAGE,
    })
    game.stack:push(summary)
    U.wait(6)
    U.shot(game, out .. "/2433_summary_water_gun_1_of_25.png")
    game.stack:pop()
    U.wait(2)

    strip(save.party[1])
    local wild = Mon.new(data, "SENTRET", 2)
    assert(world:startBattle({ wild = wild }), "battle start")
    local screen
    for _ = 1, 600 do
      U.wait(1)
      local top = game.stack:top()
      if top and top.battle then screen = top break end
    end
    assert(screen, "no battle screen")
    local shotMenu = false
    for _ = 1, 3000 do
      if game.stack:top() ~= screen and not (game.stack:top() or {}).battle then
        if not world:busy() then break end
      end
      if game.stack:top() == screen and screen.phase == "menu" then
        screen:chooseMenu("fight")
        U.wait(4)
        if not shotMenu then
          shotMenu = true
          screen.moveIndex = 4
          U.wait(2)
          U.shot(game, out .. "/2433_battle_water_gun_1_of_25.png")
        end
        local slot = (save.party[1].moves[4].pp or 0) > 0 and 4 or 2
        screen:chooseMove(slot)
        U.wait(2)
      else
        U.tap(game, "a")
        U.wait(2)
      end
    end
    U.wait(30)
    local mon = save.party[1]
    print("[2433] after battle " .. movesLine(mon))
    ok(mon.moves[4].pp == 0, "battle_spent_water_gun", mon.moves[4].pp)

    world:healParty()
    print("[2433] after heal " .. movesLine(mon))
    ok(mon.moves[3].pp == 20, "heal_rage_20", mon.moves[3].pp)
    ok(mon.moves[4].pp == 25, "heal_water_gun_25", mon.moves[4].pp)

    strip(mon)
    local res = ItemEffects.usePpItem("MAX_ETHER", mon, 4, data)
    ok(res.used and mon.moves[4].pp == 25, "max_ether_water_gun_25",
      mon.moves[4].pp)

    strip(mon)
    local box = save.currentBox or 1
    local deposited = Boxes.deposit(save, 1, box, data)
    ok(deposited, "deposit_ok")
    local boxed = Boxes.box(save, box)
    local stored = boxed[#boxed]
    ok(stored.moves[3].pp == 20 and stored.moves[4].pp == 25,
      "deposit_restores_full_pp", movesLine(stored))
  end)
  if not run then
    fails = fails + 1
    print("FAIL driver_error " .. tostring(err))
  end
  if fails == 0 then print("PASS crystal_max_pp_2433") end
  love.event.quit(fails == 0 and 0 or 1)
end
