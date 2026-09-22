package.path = "./?.lua;./?/init.lua;" .. package.path
require("tests.game3_cache").requireData("game3_marowak_progression_test")
require("src.core.GameVersion").set("firered")
local Ctx = require("src.core.game3.scripting.ctx")
local Flags = require("src.core.game3.scripting.flags")
local Std = require("src.core.game3.scripting.stdscripts")
local Natives = require("src.core.game3.scripting.natives")
local Enc = require("src.core.game3.encounters")
local Runtime = require("src.core.game3.runtime")
local Bag = require("src.core.game3.bag")
local session = { bag = Bag.new(), party = {} }
Bag.add(session.bag, 359, 1)
Runtime.session = session
for _, case in ipairs({ { "win", 1, 0 }, { "ran", 4, 1 }, { "lose", 2, 1 },
    { 1, 1, 0 }, { 4, 4, 1 }, { 7, 7, 1 } }) do
  local ctx, callback = Ctx.new(), nil
  Enc._pendingWild = { species = 105, level = 30 }
  Natives.special(ctx, Std.SPECIAL.StartMarowakBattle, {
    startWildBattle = function(foe, done)
      assert(foe.ghost and foe.ghostUnveiled)
      callback = done
    end,
  })
  assert(callback and not ctx.nativePoll())
  callback(case[1])
  assert(ctx.nativePoll())
  assert(Flags.getVar(nil, ctx, 0x800D) == case[3], "Marowak boolean result for " .. tostring(case[1]))
  assert(ctx.lastBattleOutcome == case[2])
  Natives.special(ctx, Std.SPECIAL.GetBattleOutcome, {})
  assert(Flags.getVar(nil, ctx, 0x800D) == case[2])
  Enc._pendingWild = { species = 249, level = 70 }
  Natives.special(ctx, Std.SPECIAL.StartLegendaryBattle, {
    startWildBattle = function(_, done) callback = done end,
  })
  callback(case[1])
  assert(ctx.nativePoll())
  assert(Flags.getVar(nil, ctx, 0x800D) == case[2])
end
print("PASS marowak_boolean_and_raw_outcomes")
local Cache = require("tests.game3_cache")
local bundle = assert(Cache.bundle("scripts/events.lua", { native = true }), Cache.reason)
local Vm = require("src.core.game3.scripting.vm")
local Adapters = require("src.core.game3.scripting.adapters")
local events = assert(bundle.events.FR_POKEMON_TOWER_6F.coordEvents)
local key = assert(events[1].scriptKey)
for _, case in ipairs({ { "win", 1 }, { "ran", 0 } }) do
  local store, messages, callback = Flags.newStore(), {}, nil
  local adapters = Adapters.stub({ onMessage = function(text) messages[#messages + 1] = text end,
    lookupMovement = function(id) return bundle.movements[id] end })
  adapters.startWildBattle = function(foe, done)
    assert(foe.species == 105 and foe.level == 30)
    callback = done
  end
  local vm = Vm.new({ store = store, scripts = bundle.scripts, text = bundle.text,
    movements = bundle.movements, adapters = adapters })
  assert(vm:start(key))
  for _ = 1, 100 do
    if callback then break end
    vm:tick()
  end
  assert(callback, "imported script must reach Marowak native")
  assert(Flags.getVar(store, nil, 0x4059) == 0)
  callback(case[1])
  for _ = 1, 2000 do
    if not vm:isRunning() then break end
    vm:tick()
  end
  assert(not vm:isRunning(), "imported Tower script must finish")
  assert(Flags.getVar(store, nil, 0x4059) == case[2], "imported Tower scene for " .. case[1])
  local farewell = table.concat(messages, "\n"):lower():find("mother", 1, true) ~= nil
  assert(farewell == (case[1] == "win"), "farewell follows the winning branch only")
  for _, event in ipairs(events) do
    assert(event.var == 0x4059 and event.value == 0)
    assert((Flags.getVar(store, nil, event.var) ~= event.value) == (case[1] == "win"))
  end
end
print("PASS marowak_imported_script_progression")
