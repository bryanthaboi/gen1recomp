package.path = './?.lua;./?/init.lua;./tools/save-editor/?.lua;./tools/save-editor/panels/?.lua;' .. package.path
_G.love = require('tests.love_stub')
assert(require('tests.game3_cache').mount('pokemon/meta.lua'))
local P = require('src.core.game3.pokemon')
P.install(nil)
local E = require('src.core.game3.battle.experience')
local Schema = require('src.core.game3.save_schema_firered')
local Bag = require('src.core.game3.bag')
local Storage = require('src.core.game3.storage')
local SD = require('src.core.SaveData')
local IO = require('SaveIO')
local App = require('tools.save-editor.App')
local Ops = require('Ops')
local Gen = require('Gen')
local Copy = require('src.mods.Merge').deepCopy
local function eq(a, b, label)
  if type(a) == 'table' and type(b) == 'table' then
    for k, v in pairs(a) do eq(v, b[k], label .. '.' .. tostring(k)) end
    for k in pairs(b) do assert(a[k] ~= nil, label .. ': extra ' .. tostring(k)) end
  else assert(a == b, label .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)) end
end
local function mon(id)
  local m = { species = id, speciesId = id, level = 20, personality = 123,
    ivs = { hp = 20, atk = 14, def = 12, spe = 18, spa = 24, spd = 6 },
    evs = { hp = 10, atk = 8, def = 6, spe = 4, spa = 2, spd = 0 },
    moves = { 33, 45 }, pp = { 30, 35 }, maxPp = { 35, 40 }, ppBonusesPacked = 5,
    heldItem = 13, otId = 123, otSecretId = 321, otName = 'OTHER', nickname = 'KEPT',
    metLocation = 88, metLevel = 5, pokeball = 2, friendship = 133, pokerus = 17,
    custom = { sentinel = 'kept' } }
  E.syncExpToLevel(m); P.applyStats(m); m.hp = m.maxHp - 3
  return m
end
local files = {}
local function load(native)
  local path = os.tmpname()
  files[#files + 1] = path
  local f = assert(io.open(path, 'wb')); f:write(SD.encode(native)); f:close()
  App.load(path, { version = 'firered', embedded = true })
  return App.getState(), path
end
local function saved(path)
  assert(App.save())
  return assert(IO.load(path))
end
local function award(session)
  return E.awardFoe({ playerParty = session.party, player = { mon = session.party[1], partyIndex = 1 },
    wild = true, session = session }, { species = 113, level = 40, mon = { species = 113, level = 40 } },
    { partyIndices = { 1 }, getOpts = function() return {} end })
end
local function native(id)
  local session = Schema.newGame({ name = 'RED' })
  session.party = { mon(id or 25), mon(6) }
  session.storage.boxes[1].mons[7] = mon(9)
  session.storage.boxes[1].name, session.storage.boxes[1].wallpaper = 'KEEP', 8
  session.storage.currentBox = 3
  for _, pair in ipairs({ { 13, 5 }, { 68, 2 }, { 4, 10 }, { 360, 1 }, { 289, 1 }, { 139, 3 } }) do
    assert(Bag.add(session.bag, pair[1], pair[2]))
  end
  session.storage.items = { { id = 13, qty = 999 }, { id = 68, qty = 120 }, { id = 4, qty = 10 } }
  return SD.decode(SD.encode(Schema.toSaveTable(session)))
end

local metadata = { 'personality', 'ivs', 'evs', 'moves', 'pp', 'maxPp', 'ppBonusesPacked', 'heldItem',
  'otId', 'otSecretId', 'otName', 'nickname', 'metLocation', 'metLevel', 'pokeball', 'friendship', 'pokerus', 'custom' }
if os.getenv('POKEPORT_SAVE_EDITOR_ITEMS_ONLY') ~= '1' then
local species = { 25, 4 }
local groups = {}
for id = 1, 412 do
  if P.isInternalSpecies(id) then
    local gr = P.growthRate(id)
    if gr ~= nil and not groups[gr] then groups[gr] = id; species[#species + 1] = id end
  end
end
local groupCount = 0
for _ in pairs(groups) do groupCount = groupCount + 1 end
assert(groupCount == 6, 'real pack includes all six growth groups')
for _, id in ipairs(species) do
  for _, level in ipairs({ 0, 15, 21 }) do
    local source = native(id)
    local before = Copy(source.party[1])
    local S, path = load(source)
    eq(S.save.party[1].maxHp, before.maxHp, 'hydrate stats')
    eq(S.save.party[1].hp, before.hp, 'hydrate preserves current HP')
    if level > 0 then assert(Ops.setLevel(S, S.save.party[1], level)) end
    S.save.party[1].exp = require('src.core.game3.summary_data').expForLevel(P.growthRate(id), S.save.party[1].level + 1) - 1
    local output = saved(path)
    eq(output.party[1].species, id, 'numeric species persistence')
    for _, key in ipairs(metadata) do eq(output.party[1][key], before[key], 'mon metadata ' .. key) end
    local reloaded = Schema.fromSaveTable(output)
    local m = reloaded.party[1]
    local stats = P.calcStats(id, m.level, m.ivs, m.evs, m.personality)
    eq(m.maxHp, stats.maxHp, 'runtime stats')
    local oldExp, oldLevel = m.exp, m.level
    local rewards = award(reloaded)
    eq(#rewards, 1, 'actual award count')
    assert(m.exp > oldExp and m.level > oldLevel, 'actual battle EXP and level crossing')
    App.unload()
  end
end
print('PASS native_editor_award_all_growth_groups')

do
  local source = native()
  source.party[1].species, source.party[1].maxHp, source.party[1].hp = 'PIKACHU', 999, 7
  source.storage.boxes[1].mons[7].species = 'BLASTOISE'
  local loaded = Schema.fromSaveTable(source)
  eq(loaded.party[1].species, 25, 'legacy named party repair')
  eq(loaded.party[1].hp, 7, 'legacy repair no healing')
  eq(loaded.storage.boxes[1].mons[7].species, 9, 'legacy named box repair')
  assert(#award(loaded) == 1, 'legacy repaired mon receives award')
  print('PASS legacy_named_species_repair')
end

do
  local S, path = load(native())
  local m = S.save.party[1]
  assert(Ops.setMove(S, m, 1, 57))
  eq(P.moveIdAt(m, 1), 57, 'numeric move replacement')
  eq(m.pp[1], P.movePp(57), 'new move PP')
  eq(m.ppBonusesPacked, 4, 'reset replaced slot bonus only')
  eq(m.moves[2], 45, 'unaffected move slot')
  eq(m.pp[2], 35, 'unaffected PP slot')
  assert(Ops.clearMove(S, m, 1)); eq(m.pp[1], nil, 'clear parallel PP')
  assert(Ops.setMove(S, m, 1, 57))
  eq(P.moveIdAt(Schema.fromSaveTable(saved(path)).party[1], 1), 57, 'saved native move')
  assert(S.save.boxes[1][7], 'sparse slot exposed')
  S.selectedParty, S.selectedBox, S.selectedBoxSlot = 2, 1, 2
  assert(Ops.deposit(S))
  eq(S.save.storage.boxes[1].mons[2].species, 6, 'deposit exact empty slot')
  eq(S.save.storage.boxes[1].mons[7].species, 9, 'untouched sparse slot')
  S.selectedBoxSlot = 7; assert(Ops.withdraw(S))
  eq(S.save.storage.boxes[1].mons[7], nil, 'withdraw exact sparse slot')
  local output = saved(path)
  eq(output.storage.boxes[1].name, 'KEEP', 'box name')
  eq(output.storage.boxes[1].wallpaper, 8, 'box wallpaper')
  eq(output.storage.currentBox, 3, 'current box preserved')
  eq(Schema.fromSaveTable(output).storage.boxes[1].mons[2].species, 6, 'runtime sparse deposit')
  App.unload()
  print('PASS native_moves_sparse_box_roundtrip')
end
end

do
  local source = native()
  source.extra = { keep = true }
  source.bag.pockets.ITEMS[1].custom = 'slot metadata'
  source.storage.items[2].custom = 'PC metadata'
  source.storage.custom = 'storage metadata'
  source.bag.pockets.ITEMS[#source.bag.pockets.ITEMS + 1] = { id = 2001, qty = 17, custom = 'foreign' }
  source.storage.items[#source.storage.items + 1] = { id = 2002, qty = 77, custom = 'foreign PC' }
  local S, path = load(source)
  local repeated = Copy(S.save)
  Gen.hydrateSave(S.data, S.save); eq(S.save, repeated, 'idempotent hydration')
  local boxRef = S.save.storage.boxes[1].mons[7]
  assert(Ops.addToBag(S, 'RARE_CANDY')); assert(Ops.bagAdjust(S, '68', 1))
  eq(S.save.inventory.pockets, nil, 'clean flat projection')
  assert(Ops.pcAdjust(S, 'RARE_CANDY', -1)); assert(Ops.addToPc(S, 68))
  eq(S.save.storage.boxes[1].mons[7], boxRef, 'item edit keeps selected mon identity')
  eq(S.save.pcItems['68'], 120, 'PC 120 decrement and add')
  eq(S.save.inventory['68'], 4, 'same ID aliases combined')
  local output = saved(path)
  local expected = Copy(source.bag.pockets); expected.ITEMS[2].qty = 4
  eq(output.bag.pockets, expected, 'full untouched pocket and metadata preservation')
  eq(output.storage.items, source.storage.items, 'full PC order quantities metadata')
  eq(output.extra, source.extra, 'unknown save fields')
  eq(output.storage.custom, source.storage.custom, 'storage metadata')
  local loaded = Schema.fromSaveTable(Copy(output))
  eq(Bag.get(loaded.bag, 68), 4, 'runtime candy')
  eq(loaded.storage.items[2].qty, 120, 'runtime PC above 99')
  App.unload(); App.load(path, { version = 'firered', embedded = true }); S = App.getState()
  assert(Ops.bagMax(S, 'RARE_CANDY')); assert(Ops.pcMax(S, '68'))
  local before = Copy(S.save); S.dirty = false
  assert(not Ops.addToBag(S, 68)); eq(S.save, before, 'bag 999 rejection full rollback'); eq(S.dirty, false, 'failed bag not dirty')
  assert(not Ops.addToPc(S, 'RARE_CANDY')); eq(S.save, before, 'PC 999 rejection full rollback')
  assert(Ops.bagAdjust(S, 68, -1)); assert(Ops.pcAdjust(S, 68, -1))
  eq(S.save.inventory['68'], 998, 'bag 999 decrement'); eq(S.save.pcItems['68'], 998, 'PC 999 decrement')
  assert(Ops.bagMaxAll(S)); assert(Ops.pcMaxAll(S))
  for _, slot in ipairs(S.save.bag.pockets.KEY_ITEMS) do eq(slot.qty, 1, 'containers not inflated') end
  assert(Ops.bagDrop(S, 68)); assert(Ops.pcDrop(S, 68))
  local final = Schema.fromSaveTable(saved(path))
  eq(Bag.get(final.bag, 68), 0, 'drop persisted')
  final.storage.items[1].qty = 998
  assert(Storage.depositItem(final, 'ITEMS', 1, 1)); assert(Storage.withdrawItem(final, 1, 1))
  App.unload()
  print('PASS native_bag_pc_atomic_preservation')
end

do
  local source = native()
  source.bag = Bag.new(); source.storage.items = {}
  source.inventory = { stacks = { POTION = 999 } }; source.pcItems = { POTION = 999 }
  local S, path = load(source)
  eq(S.save.inventory, {}, 'native empty bag authoritative'); eq(S.save.pcItems, {}, 'native empty PC authoritative')
  saved(path); App.unload()
  source = native(); source.bag.pockets.ITEMS = {}
  for i = 1, 42 do source.bag.pockets.ITEMS[i] = { id = 2000 + i, qty = 1 } end
  S, path = load(source)
  local before = Copy(S.save)
  assert(not Ops.addToBag(S, 68)); eq(S.save, before, 'full pocket rollback'); eq(S.dirty, false, 'full rejection dirty')
  App.unload()
  source = native(); source.storage = nil
  source.pc = { items = { { id = 68, qty = 120 } }, mons = { mon(9) }, custom = true }
  S, path = load(source); assert(Ops.pcAdjust(S, 68, -1))
  local output = saved(path)
  eq(output.storage.items[1].qty, 119, 'legacy PC migration quantity')
  eq(output.storage.boxes[1].mons[1].species, 9, 'legacy PC mons retained')
  eq(output.pc.custom, true, 'legacy unknown field')
  App.unload()
  print('PASS native_empty_legacy_full_pocket')
end
do
  local A = require('Game3Adapter')
  local source = native()
  local old = mon(6); old.nickname = 'OLDDEPOSIT'
  source.boxes = { { [7] = old, [8] = Copy(source.storage.boxes[1].mons[7]) } }
  local S, path = load(source)
  local function count(save, nickname)
    local n = 0
    for _, box in pairs(save.storage.boxes) do
      for _, m in pairs(box.mons) do if m.nickname == nickname then n = n + 1 end end
    end
    return n
  end
  eq(S.save.storage.boxes[1].mons[7].species, 9, 'collision native preserved')
  eq(count(S.save, 'OLDDEPOSIT'), 1, 'collision deposit relocated')
  eq(count(S.save, 'KEPT'), 1, 'serialized mirror deduplicated')
  local before = Copy(S.save)
  Gen.ensureBoxes(S.save); Gen.hydrateSave(S.data, S.save)
  eq(S.save, before, 'legacy coexistence repeated hydration')
  local output = saved(path)
  eq(count(output, 'OLDDEPOSIT'), 1, 'old editor no-op save retains deposit')
  eq(count(Schema.fromSaveTable(output), 'OLDDEPOSIT'), 1, 'runtime retains old deposit')
  App.unload(); App.load(path, { version = 'firered', embedded = true })
  eq(count(saved(path), 'OLDDEPOSIT'), 1, 'second no-op save no duplication')
  App.unload()
  source = native()
  for b = 1, 14 do
    source.storage.boxes[b] = source.storage.boxes[b] or { mons = {} }
    for s = 1, 30 do source.storage.boxes[b].mons[s] = mon(9) end
  end
  source.boxes = { { old } }
  before = Copy(source)
  local ok, err = pcall(A.ensureStorage, source)
  assert(not ok and tostring(err):find('native storage is full', 1, true))
  eq(source, before, 'full collision leaves all recoverable data intact')
  S, path = load(source)
  assert(S.loadError and not S.allowSave and not App.save(), 'full collision disables App save')
  eq(assert(IO.load(path)), source, 'failed App load leaves file intact')
  App.unload()
  source.storage.boxes[14].mons[30] = nil
  S, path = load(source)
  eq(count(saved(path), 'OLDDEPOSIT'), 1, 'last free slot collision migration')
  App.unload()
  print('PASS legacy_native_boxes_collision_noop_full_storage')
end

do
  local A = require('Game3Adapter')
  for _, mode in ipairs({ 'minus', 'drop', 'max' }) do
    local source = native()
    local slots = { { id = 13, qty = 700, custom = 'before' }, { id = 68, qty = 120, custom = 'target' },
      { id = 2001, qty = 77, custom = 'middle' }, { id = 'RARE_CANDY', qty = 1 },
      { id = '68', qty = 2 }, { id = 2002, qty = 88, custom = 'after' } }
    source.bag.pockets.ITEMS, source.storage.items = Copy(slots), Copy(slots)
    local S, path = load(source)
    eq(S.save.inventory['68'], 123, 'duplicate bag total')
    eq(S.save.pcItems['68'], 123, 'duplicate PC total')
    local untouched = Copy(S.save)
    assert(not A.change(S.data, S.save, false, { { id = 68, qty = 122 }, { id = 13, qty = 1000 } }))
    eq(S.save, untouched, 'duplicate bag batch rejection rollback')
    assert(not A.change(S.data, S.save, true, { { id = 68, qty = 122 }, { id = 13, qty = 1000 } }))
    eq(S.save, untouched, 'duplicate PC batch rejection rollback')
    local expected = mode == 'minus' and 122 or mode == 'max' and 999 or 0
    for _, prefix in ipairs({ 'bag', 'pc' }) do
      if mode == 'minus' then assert(Ops[prefix .. 'Adjust'](S, 'RARE_CANDY', -1))
      elseif mode == 'drop' then assert(Ops[prefix .. 'Drop'](S, '68'))
      else assert(Ops[prefix .. 'Max'](S, 68)) end
    end
    local expectedSlots = { Copy(slots[1]), Copy(slots[3]), Copy(slots[6]) }
    if expected > 0 then
      local target = Copy(slots[2]); target.qty = expected
      table.insert(expectedSlots, 2, target)
    end
    eq(S.save.bag.pockets.ITEMS, expectedSlots, 'bag duplicate ' .. mode)
    eq(S.save.storage.items, expectedSlots, 'PC duplicate ' .. mode)
    local output = saved(path)
    eq(output.bag.pockets.ITEMS, expectedSlots, 'persist bag duplicate ' .. mode)
    eq(output.storage.items, expectedSlots, 'persist PC duplicate ' .. mode)
    App.unload(); App.load(path, { version = 'firered', embedded = true }); S = App.getState()
    eq(S.save.inventory['68'] or 0, expected, 'reload bag aggregate ' .. mode)
    eq(S.save.pcItems['68'] or 0, expected, 'reload PC aggregate ' .. mode)
    if mode == 'max' then
      untouched = Copy(S.save)
      assert(not Ops.addToBag(S, 68) and not Ops.addToPc(S, 'RARE_CANDY'))
      eq(S.save, untouched, 'duplicate capped rejection unchanged')
    end
    App.unload()
  end
  print('PASS duplicate_bag_pc_alias_minus_drop_max_reload_rollback')
end
do
  local source = native()
  local S, path = load(source)
  S.editingMon, S.dirty, S._quitArmed, S._openArmed = S.save.party[1], true, true, true
  assert(App.reload())
  eq(S.editingMon, nil, 'reload clears mon editor')
  eq(S.dirty, false, 'reload clears dirty')
  eq(S._quitArmed, false, 'reload disarms quit')
  eq(S._openArmed, false, 'reload disarms open')
  eq(S.save.inventory['68'], 2, 'actual reload bag projection')
  eq(S.save.pcItems['68'], 120, 'actual reload PC projection')
  assert(S.save.boxes[1] == S.save.storage.boxes[1].mons, 'reload native box alias')
  local output = saved(path)
  eq(output.bag.pockets, source.bag.pockets, 'reload no-op bag')
  eq(output.storage.items, source.storage.items, 'reload no-op PC')
  eq(output.storage.boxes[1].mons[7].species, 9, 'reload no-op native sparse mon')
  assert(App.reload())
  assert(Ops.addToBag(S, 'RARE_CANDY'))
  assert(Ops.pcAdjust(S, '68', -1))
  S.selectedParty, S.selectedBox, S.selectedBoxSlot = 2, 1, 2
  assert(Ops.deposit(S))
  output = saved(path)
  local runtime = Schema.fromSaveTable(Copy(output))
  eq(Bag.get(runtime.bag, 68), 3, 'reload subsequent bag edit')
  eq(runtime.storage.items[2].qty, 119, 'reload subsequent PC edit')
  eq(runtime.storage.boxes[1].mons[2].species, 6, 'reload subsequent deposit')
  eq(runtime.storage.boxes[1].mons[7].species, 9, 'reload untouched native mon')
  for b = 1, 14 do
    source.storage.boxes[b] = source.storage.boxes[b] or { mons = {} }
    for s = 1, 30 do source.storage.boxes[b].mons[s] = mon(9) end
  end
  source.boxes = { { mon(6) } }
  local f = assert(io.open(path, 'wb')); f:write(SD.encode(source)); f:close()
  assert(not App.reload() and S.loadError and not S.allowSave, 'reload collision disables save')
  assert(not App.save())
  eq(assert(IO.load(path)), source, 'reload collision leaves disk intact')
  App.unload()
  print('PASS actual_app_reload_native_noop_edits_collision')
end
for _, path in ipairs(files) do os.remove(path) end
print('PASS save_editor_gen3_native_persistence')
