package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.modkit")
local UI = require("src.ui.gen2.BattleState")
local Boxes = require("src.core.gen2.Boxes")

local DATA = {
  pokemon = {
    RATTATA = { id = "RATTATA", index = 19, name = "RATTATA", catchRate = 255, baseExp = 51,
      baseStats = { hp = 30, attack = 56, defense = 35, speed = 72, specialAttack = 25, specialDefense = 35 },
      types = { "NORMAL", "NORMAL" }, growthRate = "GROWTH_MEDIUM_FAST", genderRatio = 127,
      levelMoves = {}, evolutions = {} },
  },
  moves = {}, items = {}, type_chart = { types = {}, matchups = {} },
  text = { _BallSentToPCText = "{STRBUF} was\nsent to BILL's PC.{PROMPT}" },
}

local function newState(opts)
  opts = opts or {}
  local save = { version = "crystal", party = {}, player = { name = "KRIS", id = 4242, gender = "female" },
    pokedex = { seen = {}, caught = {} } }
  for i = 1, opts.party or 0 do save.party[i] = { species = "RATTATA", level = 5 } end
  local world = { tod = "DAY", maps = {}, map = { def = { id = "ROUTE_29", landmark = 2 } } }
  return setmetatable({
    save = save, queue = {}, battle = { timeOfDay = 1 },
    contest = opts.contest, tutorial = opts.tutorial,
    game = { save = save, data = DATA, world = world },
  }, { __index = UI })
end

local function queued(state, kind)
  local n = 0
  for _, event in ipairs(state.queue) do
    if event.kind == kind then n = n + 1 end
  end
  return n
end

local function messages(state)
  local out = {}
  for _, event in ipairs(state.queue) do
    if event.kind == "message" then out[#out + 1] = event.text end
  end
  return out
end

local function settle(state)
  for _, event in ipairs(state.queue) do
    if event.kind == "set-nickname" then state:applyQueuedNickname(event) end
  end
end

local function catch(opts)
  local state = newState(opts)
  local enemy = { species = "RATTATA", level = 4 }
  state:pushCaught(enemy, "POKE_BALL")
  return state, enemy
end

local function indexOf(state, pred)
  for i, event in ipairs(state.queue) do
    if pred(event) then return i end
  end
end

local vanilla = T.sdk.loadNone({ generation = 2 })
do
  local state, enemy = catch()
  T.eq(queued(state, "ask-nickname"), 1, "no mod: the catch asks for a nickname")
  T.eq(enemy.nickname, nil, "no mod: nothing is named")
end
vanilla.release()

local FIXTURE = {
  ["mods/name_probe/manifest.json"] = [[{"id":"name_probe","name":"Name Probe","version":"1.0.0",
    "api":2,"games":["all"],"entry":"main.lua"}]],
  ["mods/name_probe/main.lua"] = [[
    local mod = ...
    mod.exports.calls = 0
    mod.exports.nickname = "SPIKE"
    mod.hooks:wrap("catch.nickname", function(next, mon, ctx)
      mod.exports.calls = mod.exports.calls + 1
      mod.exports.mon, mod.exports.ctx = mon, ctx
      if mod.exports.nickname ~= nil then return mod.exports.nickname end
      return next(mon, ctx)
    end)
    mod.exports.caughtCalls = 0
    mod.events:on("pokemon.caught", function(payload)
      mod.exports.caughtCalls = mod.exports.caughtCalls + 1
      mod.exports.caughtName = payload.mon.nickname
    end)
  ]],
}

local run = T.sdk.loadMods({ "mods/name_probe" }, { fs = T.sdk.memfs(FIXTURE), generation = 2 })
T.eq(#run.errors, 0, "the probe loads clean (" .. tostring(run.errors[1]) .. ")")
local probe = run.loader.exports.name_probe

do
  probe.caughtCalls, probe.caughtName = 0, nil
  local state, enemy = catch()
  T.eq(queued(state, "ask-nickname"), 0, "SPIKE: no nickname question is queued")
  T.eq(enemy.nickname, nil, "SPIKE: the mon keeps its species name while the caught text is queued")
  local gotcha = indexOf(state, function(e)
    return e.kind == "message" and e.text:find("Gotcha! RATTATA was caught!", 1, true) ~= nil
  end)
  local naming = indexOf(state, function(e) return e.kind == "set-nickname" end)
  T.check(gotcha ~= nil, "SPIKE: the Gotcha line names RATTATA")
  T.check(naming ~= nil and gotcha ~= nil and naming > gotcha,
    "SPIKE: the name is applied after the Gotcha line, at the question point")
  T.eq(probe.caughtCalls, 0, "SPIKE: pokemon.caught waits for the question point")
  settle(state)
  T.eq(enemy.nickname, "SPIKE", "SPIKE: the caught mon is named at the question point")
  T.eq(probe.caughtCalls, 1, "SPIKE: pokemon.caught fires once")
  T.eq(probe.calls, 1, "SPIKE: the hook ran once")
  T.check(probe.mon == enemy, "SPIKE: the hook got the caught mon")
  T.check(probe.ctx and probe.ctx.battle == state, "SPIKE: ctx.battle is the battle screen")
  T.eq(probe.ctx and probe.ctx.name, "RATTATA", "SPIKE: ctx.name is the shown name")
  T.check(probe.ctx and probe.ctx.game == state.game, "SPIKE: ctx.game is the game")
  T.eq(probe.caughtName, "SPIKE", "SPIKE: pokemon.caught sees the nickname")
end

do
  local state, enemy = catch({ party = 6 })
  T.eq(queued(state, "ask-nickname"), 0, "full party: no nickname question")
  T.eq(Boxes.box(state.save, state:currentBox())[1], enemy, "full party: the catch heads the box")
  local found = false
  for _, text in ipairs(messages(state)) do
    if text:gsub("\n", " "):find("SPIKE was sent to BILL's PC.", 1, true) then found = true end
  end
  T.check(found, "full party: the PC line names SPIKE")
  T.eq(enemy.nickname, nil, "full party: still the species name before the question point")
  settle(state)
  T.eq(enemy.nickname, "SPIKE", "full party: the boxed mon is named at the question point")
end

probe.nickname = false
do
  probe.caughtCalls = 0
  local state, enemy = catch()
  T.eq(queued(state, "ask-nickname"), 0, "false: no question")
  T.eq(queued(state, "set-nickname"), 0, "false: nothing to apply")
  T.eq(enemy.nickname, nil, "false: the species name stays")
  T.eq(probe.caughtCalls, 1, "false: pokemon.caught fires at the catch")
end

probe.nickname = "TOOLONGFORTHEGRID"
do
  local state, enemy = catch()
  settle(state)
  T.eq(enemy.nickname, "TOOLONGFOR", "a long name is clipped to ten")
end

probe.nickname = "\195\137\195\137\195\137\195\137\195\137\195\137\195\137\195\137\195\137\195\137\195\137\195\137"
do
  local state, enemy = catch()
  settle(state)
  T.eq(enemy.nickname, ("\195\137"):rep(10), "the clip counts characters, not bytes")
end

probe.nickname = "SPI\nKE\0"
do
  local state, enemy = catch()
  settle(state)
  T.eq(enemy.nickname, "SPIKE", "control characters never reach the name")
end

require("src.render.Font").load({ font = { charmap = {
  { seq = "<PK>", code = 0xE1 }, { seq = "<MN>", code = 0xE2 },
} } })
probe.nickname = ("<PK><MN>"):rep(6)
do
  local state, enemy = catch()
  settle(state)
  T.eq(enemy.nickname, ("<PK><MN>"):rep(5), "a charmap token is one glyph")
end

probe.nickname = ""
do
  local state, enemy = catch()
  T.eq(queued(state, "ask-nickname"), 0, "empty string: no question")
  T.eq(queued(state, "set-nickname"), 0, "empty string: nothing to apply")
  T.eq(enemy.nickname, nil, "empty string: nothing is named")
end

probe.nickname = nil
do
  local state, enemy = catch()
  T.eq(queued(state, "ask-nickname"), 1, "falling through asks as usual")
  T.eq(enemy.nickname, nil, "falling through names nothing")
end

probe.nickname = "SPIKE"
probe.calls = 0
catch({ tutorial = true })
T.eq(probe.calls, 0, "a tutorial catch never consults the hook")
local contest = catch({ contest = true })
T.eq(probe.calls, 0, "a contest catch never consults the hook")
T.eq(queued(contest, "ask-nickname"), 0, "a contest catch asks nothing")

run.release()

local API3 = {
  ["mods/name_probe3/manifest.json"] = [[{"id":"name_probe3","name":"Name Probe 3","version":"1.0.0",
    "api":3,"games":["all"],"entry":"main.lua"}]],
  ["mods/name_probe3/main.lua"] = [[
    local mod = ...
    mod.exports.supported = mod:supports("hooks", "catch.nickname")
    mod.hooks:wrap("catch.nickname", function(next, mon, ctx)
      mod.exports.species, mod.exports.nick, mod.exports.name = mon.species, mon.nickname, ctx.name
      return "SPIKE"
    end)
  ]],
}
local loader = require("src.mods.Loader").new({ fs = T.sdk.memfs(API3), generation = 2, version = "crystal" })
T.sdk.captureRuntime()
local state = newState()
loader.game = state.game
loader:load(require("tests.modkit.fixtures").fresh())
T.eq(#loader.errors, 0, "API 3 probe loads clean (" .. tostring(loader.errors[1]) .. ")")
local p3 = loader.exports.name_probe3
T.eq(p3.supported, true, "API 3: mod:supports is true on Gen 2")
local enemy = { species = "RATTATA", level = 4 }
state:pushCaught(enemy, "POKE_BALL")
settle(state)
T.eq(p3.species, require("src.mods.UnifiedRecords").id("RATTATA", "species", 2, DATA),
  "API 3: mon.species is the portable id")
T.eq(p3.name, "RATTATA", "API 3: ctx.name is the shown name")
T.eq(enemy.nickname, "SPIKE", "API 3: a string still names the mon")
T.eq(queued(state, "ask-nickname"), 0, "API 3: no question")
T.sdk.restoreRuntime()

T.finish("catch.nickname Gen 2")
