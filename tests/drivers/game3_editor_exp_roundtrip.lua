local U = require('tests.drivers.util')
local DIR = os.getenv('POKEPORT_SHOT_DIR') or '/tmp/game3_editor_exp_roundtrip'

return function(game)
  local ok, err = xpcall(function()
    assert((os.getenv('POKEPORT_IDENTITY') or ''):match('^firered%-bsa'), 'isolated firered-bsa identity required')
    package.path = package.path .. ';./tools/save-editor/?.lua;./tools/save-editor/panels/?.lua'
    local SaveData = require('src.core.SaveData')
    assert(not SaveData.isPortable(), 'driver requires isolated nonportable saves')
    for _ = 1, 900 do
      if game.phase == 'boot' and game.boot then break end
      U.wait(1)
    end
    local slot = assert(SaveData.createSlot('firered'))
    SaveData.setActiveSlot('firered', slot)
    game:_handleBootAction({ action = 'new_game', name = 'RED' })
    U.wait(240)
    local Runtime = require('src.core.game3.runtime')
    local Party = require('src.core.game3.party')
    local P = require('src.core.game3.pokemon')
    local Growth = require('src.core.game3.summary_data')
    local Bag = require('src.core.game3.bag')
    local Storage = require('src.core.game3.storage')
    local App = require('tools.save-editor.App')
    local Ops = require('Ops')
    local Bridge = require('src.core.game3.battle_bridge')
    local Battle = require('src.core.game3.battle')
    local Anim = require('src.core.game3.battle.anim')
    local Ui = require('src.core.game3.battle.ui')
    local Summary = require('src.ui.game3.summary_menu')
    local BagMenu = require('src.ui.game3.bag_menu')
    local Boxes = require('src.ui.game3.box_storage_ui')
    local Pc = require('src.ui.game3.pc_menu')
    local function shot(name)
      U.wait(50)
      assert(U.shot(game, DIR .. '/' .. name .. '.png'), 'screenshot ' .. name)
    end
    local function continue()
      game:_handleBootAction({ action = 'continue' })
      U.wait(60)
      for _ = 1, 400 do
        if game.phase ~= 'quest_log' then break end
        U.tap(game, 'a'); U.wait(6)
      end
      U.wait(120)
      assert(game.phase == 'field', 'Continue did not reach field: ' .. tostring(game.phase))
      return assert(Runtime.getSession())
    end
    local session = assert(Runtime.getSession())
    session.party = {}
    Party.giveMon(session, 25, 20); Party.giveMon(session, 4, 20); Party.giveMon(session, 9, 20)
    session.storage = Storage.new()
    session.storage.boxes[1].mons[7] = table.remove(session.party, 3)
    session.storage.boxes[1].name, session.storage.boxes[1].wallpaper = 'KEPT', 8
    session.storage.items = { { id = 13, qty = 999 }, { id = 68, qty = 120 } }
    session.bag = Bag.new()
    for _, pair in ipairs({ { 13, 5 }, { 68, 2 }, { 4, 10 }, { 360, 1 }, { 289, 1 }, { 139, 3 } }) do
      assert(Bag.add(session.bag, pair[1], pair[2]))
    end
    session.party[1].custom = { sentinel = 'kept' }
    assert(game:saveGame())
    local path = assert(SaveData.slotDiskPath('firered', slot))
    App.load(path, { version = 'firered', slotId = slot, embedded = true })
    local S = App.getState()
    for _, mon in ipairs(S.save.party) do
      assert(Ops.setLevel(S, mon, 21))
      mon.exp = Growth.expForLevel(P.growthRate(mon.speciesId), 22) - 1
      assert(Ops.setMove(S, mon, 1, 10))
    end
    assert(Ops.addToBag(S, 'RARE_CANDY')); assert(Ops.bagAdjust(S, '68', 1))
    assert(Ops.pcAdjust(S, 'RARE_CANDY', -1))
    S.selectedParty, S.selectedBox, S.selectedBoxSlot = 2, 1, 2
    assert(Ops.deposit(S)); assert(S.save.storage.boxes[1].mons[7])
    assert(App.save()); App.unload()
    session = continue()
    assert(session.storage.boxes[1].mons[2].species == 4 and session.storage.boxes[1].mons[7].species == 9)
    print('PASS editor_sparse_deposit_continue')
    Boxes.show({ session = session }); Boxes.cursorSlot = 7
    shot('u2_editor_sparse_box_slots_2_7'); Boxes.close(); U.wait(10)
    App.load(path, { version = 'firered', slotId = slot, embedded = true })
    S = App.getState(); S.selectedBox, S.selectedBoxSlot = 1, 2
    assert(Ops.withdraw(S)); assert(App.save()); App.unload()
    session = continue()
    assert(session.storage.boxes[1].mons[2] == nil and session.storage.boxes[1].mons[7].species == 9)
    assert(#session.party == 2 and session.party[2].species == 4)
    print('PASS editor_sparse_withdraw_continue')
    for _, pair in ipairs({ { 13, 5 }, { 68, 4 }, { 4, 10 }, { 360, 1 }, { 289, 1 }, { 139, 3 } }) do
      assert(Bag.get(session.bag, pair[1]) == pair[2], 'preserved item ' .. pair[1])
    end
    assert(session.storage.items[1].qty == 999 and session.storage.items[2].qty == 119)
    assert(session.party[1].custom.sentinel == 'kept')
    print('PASS editor_native_bag_pc_continue')
    for _, pocket in ipairs({ 'ITEMS', 'KEY_ITEMS', 'POKE_BALLS', 'TM_CASE', 'BERRY_POUCH' }) do
      BagMenu.show(session.bag, { session = session, pocket = pocket })
      shot('u3_editor_preserved_' .. pocket:lower()); BagMenu.close(); U.wait(10)
    end
    Pc.show({ session = session, startMode = 'player_pc' })
    U.tap(game, 'a'); U.wait(20); U.tap(game, 'a'); U.wait(20)
    shot('u3_editor_pc_999_119'); Pc.close(); U.wait(10)
    for _, species in ipairs({ 25, 4 }) do
      if session.party[1].species ~= species then session.party[1], session.party[2] = session.party[2], session.party[1] end
      local before = session.party[1].exp
      assert(Bridge.startWild(Runtime._mod, game, { species = 129, level = 30 }, { fade = false }))
      local captured = false
      for frame = 1, 9000 do
        if not Battle.isActive() then break end
        if Battle._phase == 'command' and Ui._mode == 'menu' then
          if not captured then shot('u2_editor_battle_' .. species); captured = true end
          local state = Battle.getState()
          state.enemy.mon.hp = 1; state.enemy.mon.moves = { 150 }; state.enemy.mon.pp = { 40 }
          local present = Anim.present('enemy'); if present then present.displayHp = 1 end
          Ui._pendingCommand = { kind = 'move', move = 10, slot = 1, user = 'player' }
          Ui._mode = 'none'; U.wait(2)
        elseif Anim.vm() and Anim.vm():busy() then U.wait(1)
        elseif frame % 12 == 0 then U.tap(game, 'a')
        else U.wait(1) end
      end
      assert(not Battle.isActive(), 'battle timeout')
      U.wait(120)
      assert(session.party[1].exp > before and session.party[1].level >= 22, 'normal battle award for ' .. species)
      print('PASS editor_continue_battle_exp_' .. species)
      Summary.openMenu(session.party, 1, { session = session, page = 1 })
      shot('u2_editor_levelup_stats_' .. species); Summary.close(); U.wait(10)
    end
    assert(game:saveGame()); session = continue()
    assert(session.party[1].level >= 22 and session.party[2].level >= 22)
    assert(Bag.get(session.bag, 68) == 4 and session.storage.items[2].qty == 119)
    print('PASS editor_second_save_continue_preservation')
    print('PASS game3_editor_exp_roundtrip')
  end, debug.traceback)
  if not ok then print('FAIL game3_editor_exp_roundtrip ' .. tostring(err)) end
  love.event.quit(ok and 0 or 1)
end
