package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.modkit")
local UnifiedCallbacks = require("src.mods.UnifiedCallbacks")
local PackMenu = require("src.ui.gen2.PackMenu")
local BattleState = require("src.ui.gen2.BattleState")
local World = require("src.world.gen2.World")

local FIXTURE = {
  ["mods/use2/manifest.json"] = [[{"id":"use2","name":"Use 2","version":"1.0.0",
    "api":2,"games":["all"],"entry":"main.lua"}]],
  ["mods/use2/main.lua"] = [[
    local mod = ...
    local e = mod.exports
    e.calls = {}
    mod.hooks:wrap("item.use", function(next, game, battle, id, target, pack)
      e.calls[#e.calls + 1] = { game = game, battle = battle, id = id,
        target = target, pack = pack }
      if e.claim then return end
      return next(game, battle, id, target, pack)
    end)
  ]],
  ["mods/use3/manifest.json"] = [[{"id":"use3","name":"Use 3","version":"1.0.0",
    "api":3,"games":["all"],"entry":"main.lua"}]],
  ["mods/use3/main.lua"] = [[
    local mod = ...
    local e = mod.exports
    mod.hooks:wrap("item.use", function(next, game, battle, id, target, ...)
      e.battle = battle
      e.id = id
      e.targetNative = type(target) == "table" and target.native ~= nil
      e.targetRaw = type(target) == "table" and target.rawProbe == true
      e.target = target
      local fifth = (...)
      e.fifthProbe = type(fifth) == "table" and (fifth.isPackProbe or fifth.isBagProbe) or nil
      return next(game, battle, id, target, ...)
    end)
  ]],
  ["mods/four2/manifest.json"] = [[{"id":"four2","name":"Four 2","version":"1.0.0",
    "api":2,"games":["all"],"entry":"main.lua"}]],
  ["mods/four2/main.lua"] = [[
    local mod = ...
    mod.exports.calls = 0
    mod.hooks:wrap("item.use", function(next, game, battle, id, target)
      mod.exports.calls = mod.exports.calls + 1
      return next(game, battle, id, target)
    end)
  ]],
}

for _, version in ipairs({ "gold", "silver", "crystal" }) do
  T.eq(UnifiedCallbacks.supports("hooks", "item.use", 2, version), true,
    "item.use is supported on " .. version)
end

local function pack(opts)
  local p = setmetatable({
    rows = { { id = opts.id, name = opts.id, count = 1 } }, index = 1,
    items = { [opts.id] = opts.def or {} },
    world = opts.world, battle = opts.battle, tutorial = opts.tutorial,
    onChoose = opts.onChoose,
    game = { stack = { push = function() end, pop = function() end, top = function() end } },
  }, { __index = PackMenu })
  p.storeCursor = function() end
  p.showMessage = function(self, lines) self.shown = lines end
  p.exitToField = function(self) self.exited = true end
  p.rebuild = function() end
  return p
end

local function only(id)
  local out = {}
  for path, body in pairs(FIXTURE) do
    if path:find("mods/" .. id .. "/", 1, true) then out[path] = body end
  end
  return T.sdk.memfs(out)
end

local run = T.sdk.loadMods({ "mods/use2" }, { fs = only("use2"), generation = 2 })
T.eq(#run.errors, 0, "the Gen 2 item probe loads clean (" .. tostring(run.errors[1]) .. ")")
local e = run.loader.exports.use2
local function reset(claim) e.calls, e.claim = {}, claim end

reset(false)
local fieldCalls = 0
local p1 = pack({ id = "BICYCLE",
  world = { useFieldItem = function() fieldCalls = fieldCalls + 1 return "bike" end } })
p1:useSelected()
T.eq(#e.calls, 1, "field PACK USE fires item.use once")
T.eq(e.calls[1] and e.calls[1].battle, nil, "with no battle")
T.eq(e.calls[1] and e.calls[1].id, "BICYCLE", "on the item used")
T.eq(e.calls[1] and e.calls[1].target, nil, "and no target")
T.eq(e.calls[1] and e.calls[1].pack, p1, "and the pack last")
T.eq(fieldCalls, 1, "next() runs the world's effect")
T.eq(p1.exited, true, "and the PACK ending")

reset(true)
fieldCalls = 0
local p2 = pack({ id = "BICYCLE",
  world = { useFieldItem = function() fieldCalls = fieldCalls + 1 return "bike" end } })
p2:useSelected()
T.eq(#e.calls, 1, "a claimed field USE still fires once")
T.eq(fieldCalls, 0, "and skips the world's effect")

reset(true)
local chosen
local p3 = pack({ id = "POTION", def = { fieldMenu = "ITEMMENU_PARTY" },
  world = { useFieldItem = function() return nil end },
  onChoose = function(id) chosen = id end })
p3:useSelected()
T.eq(chosen, nil, "a claimed party item never reaches the party pick")

reset(false)
chosen = nil
local p4 = pack({ id = "POTION", world = {}, onChoose = function(id) chosen = id end })
p4:useSelected()
T.eq(#e.calls, 0, "the mart SELL / item PC pack raises nothing")
T.eq(chosen, "POTION", "and hands the row to its chooser")

reset(false)
chosen = nil
local p5 = pack({ id = "POKE_BALL", tutorial = true, battle = true,
  world = {}, onChoose = function(id) chosen = id end })
p5:useSelected()
T.eq(#e.calls, 0, "the DUDE's pack raises nothing")

local function battleScreen(tutorial)
  local bs = setmetatable({
    game = { data = { items = { POKE_BALL = { pocket = "BALL" } } } },
    battle = { wild = false }, save = { party = {}, inventory = { POKE_BALL = 1 } },
    tutorial = tutorial, phase = "submenu",
  }, { __index = BattleState })
  bs.thrown = 0
  bs.throwBallAtTrainer = function(self) self.thrown = self.thrown + 1 end
  return bs
end

reset(false)
local bs = battleScreen(false)
bs:useItem("POKE_BALL")
T.eq(#e.calls, 1, "battle item use fires item.use once")
T.eq(e.calls[1] and e.calls[1].battle, bs, "with the battle screen second")
T.eq(e.calls[1] and e.calls[1].id, "POKE_BALL", "and the item third")
T.eq(bs.thrown, 1, "next() runs the battle effect")

reset(true)
bs = battleScreen(false)
bs:useItem("POKE_BALL")
T.eq(bs.thrown, 0, "a claimed battle use skips the effect")
T.eq(bs.phase, "menu", "and hands the battle menu back")

reset(false)
bs = battleScreen(true)
bs:useItem("POKE_BALL")
T.eq(#e.calls, 0, "the catch tutorial raises nothing")
T.eq(bs.thrown, 1, "and still throws")

local function selectWorld()
  local w = setmetatable({
    game = { data = { items = { BICYCLE = {} } }, save = {} },
  }, { __index = World })
  w.busy = function() return false end
  w.registeredItemId = function() return "BICYCLE" end
  w.selCalls = 0
  w.useFieldItem = function(self) self.selCalls = self.selCalls + 1 return "bike" end
  return w
end

reset(false)
local sel = selectWorld()
T.eq(sel:useSelectItem(), "bike", "SELECT runs the registered item")
T.eq(#e.calls, 1, "SELECT fires item.use once")
T.eq(e.calls[1] and e.calls[1].id, "BICYCLE", "on the registered item")
T.eq(sel.selCalls, 1, "next() runs the world's effect")

reset(true)
sel = selectWorld()
T.eq(sel:useSelectItem(), "claimed", "a claimed SELECT reports claimed")
T.eq(sel.selCalls, 0, "and runs nothing")

run.release()

local runFour = T.sdk.loadMods({ "mods/four2" }, { fs = only("four2"), generation = 2 })
T.eq(#runFour.errors, 0, "the four-argument item probe loads clean (" .. tostring(runFour.errors[1]) .. ")")
fieldCalls = 0
local p6 = pack({ id = "BICYCLE",
  world = { useFieldItem = function() fieldCalls = fieldCalls + 1 return "bike" end } })
local okFour, errFour = pcall(p6.useSelected, p6)
T.eq(okFour, true, "a wrapper that drops the pack does not break field USE (" .. tostring(errFour) .. ")")
T.eq(runFour.loader.exports.four2.calls, 1, "the four-argument wrapper runs once")
T.eq(fieldCalls, 1, "and next() still runs the world's effect")
T.eq(p6.exited, true, "and the PACK ending")
runFour.release()

local run3 = T.sdk.loadMods({ "mods/use3" }, { fs = only("use3"), generation = 1 })
T.eq(#run3.errors, 0, "the api 3 item probe loads clean (" .. tostring(run3.errors[1]) .. ")")
local e3 = run3.loader.exports.use3
local Runtime = require("src.mods.Runtime")
local rawBattle = { isBattleProbe = true, phase = "menu" }
local mon = { species = "FIXMON_A", level = 5, hp = 10, rawProbe = true }
local got
Runtime.call("item.use", function(_, b, id, t) got = { b = b, id = id, t = t } end,
  {}, rawBattle, "FIX_POTION", mon)
T.eq(e3.battle, rawBattle, "api 3: the battle reaches the wrapper as the battle")
T.eq(e3.targetNative, true, "api 3: the target is a public mon view")
T.eq(e3.targetRaw, false, "api 3: not the raw native mon")
T.eq(got and got.b, rawBattle, "api 3: next() hands the battle back")
T.eq(got and got.t, mon, "api 3: and the native target")
run3.release()

local run3g2 = T.sdk.loadMods({ "mods/use3" }, { fs = only("use3"), generation = 2 })
T.eq(#run3g2.errors, 0, "the api 3 item probe loads clean on Gen 2 (" .. tostring(run3g2.errors[1]) .. ")")
local e3g2 = run3g2.loader.exports.use3
local screen = { isBattleScreenProbe = true }
local packProbe = { isPackProbe = true }
got = nil
Runtime.call("item.use", function(_, b, id, t, extra) got = { b = b, id = id, t = t, extra = extra } end,
  {}, screen, "POKE_BALL", nil, packProbe)
T.eq(e3g2.battle, screen, "api 3 Gen 2: the battle screen reaches the wrapper raw")
T.eq(e3g2.id, "POKE_BALL", "api 3 Gen 2: the item id passes through")
T.eq(e3g2.target, nil, "api 3 Gen 2: the target stays nil")
T.eq(e3g2.fifthProbe, true, "api 3 Gen 2: the pack reaches the wrapper fifth")
T.eq(got and got.b, screen, "api 3 Gen 2: next() hands the battle screen back")
T.eq(got and got.extra, packProbe, "api 3 Gen 2: and the pack")
run3g2.release()

local run3g3 = T.sdk.loadMods({ "mods/use3" }, { fs = only("use3"), generation = 3 })
T.eq(#run3g3.errors, 0, "the api 3 item probe loads clean on Gen 3 (" .. tostring(run3g3.errors[1]) .. ")")
local e3g3 = run3g3.loader.exports.use3
local bagProbe = { isBagProbe = true }
got = nil
Runtime.call("item.use", function(_, b, id, t, extra) got = { b = b, id = id, t = t, extra = extra } end,
  {}, nil, 13, 2, bagProbe)
T.eq(e3g3.battle, nil, "api 3 Gen 3: no battle on the field bag")
T.eq(type(e3g3.id), "string", "api 3 Gen 3: the wrapper sees a portable item id")
T.eq(got and got.id, 13, "api 3 Gen 3: next() gets the native item id back")
T.eq(e3g3.target, 2, "api 3 Gen 3: the party slot passes through as a number")
T.eq(e3g3.fifthProbe, true, "api 3 Gen 3: the bag reaches the wrapper fifth")
T.eq(got and got.t, 2, "api 3 Gen 3: next() gets the slot back")
T.eq(got and got.extra, bagProbe, "api 3 Gen 3: and the bag")
run3g3.release()

T.finish("item_use_gen2")
