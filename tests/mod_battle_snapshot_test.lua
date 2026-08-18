package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local S = require("tests.harness").suite("mod battle snapshot")
local check, eq = S.check, S.eq

local Gen1BattleState = require("src.battle.BattleState")
check(Gen1BattleState.isBattleState == true,
  "Gen 1 battle states carry the discovery marker")

local TypeChart = require("src.battle.TypeChart")
TypeChart.load({ type_chart = {
  types = { NORMAL = { name = "NORMAL", category = "physical" } },
  matchups = {},
} })

local Damage = require("src.battle.Damage")
local attacker, defender = { stages = {} }, { stages = {} }
eq(Damage.accuracyThreshold({ oneIn256Miss = true }, { accuracy = 100 },
  attacker, defender), 255, "faithful accuracy keeps the 1-in-256 miss")
eq(Damage.accuracyThreshold({ oneIn256Miss = false }, { accuracy = 100 },
  attacker, defender), 256, "clean accuracy exposes a certain hit")
local Catching = require("src.battle.Catching")
eq(Catching.chance("MASTER_BALL", { hp = 1, stats = { hp = 1 } },
  { catchRate = 1 }), 100, "Master Ball preview is certain")
check(Catching.chance("MOD_BALL", { hp = 1, stats = { hp = 1 } },
  { catchRate = 1 }, nil, { ballDef = { attempt = function() end } }) == nil,
  "custom ball logic does not receive a guessed preview")

local mon = { species = "TESTMON", level = 5, hp = 18,
  stats = { hp = 20 }, moves = {} }
local game = {
  data = {
    pokemon = { TESTMON = { name = "TESTMON", catchRate = 255 } },
    moves = { TACKLE = { name = "TACKLE", type = "NORMAL", power = 35,
      accuracy = 95, pp = 35 } },
    items = { POTION = { name = "POTION" },
      POKE_BALL = { name = "POKE BALL" } },
  },
  save = { party = { mon }, inventory = { POTION = 1, POKE_BALL = 1 } },
  stack = { states = {} },
}
local battle = {
  isBattleState = true, phase = "menu", queue = {},
  ruleset = { oneIn256Miss = true },
  player = { mon = mon, curTypes = { "NORMAL" }, stages = {},
    curMoves = { { id = "TACKLE", pp = 35 } } },
  enemy = { mon = { species = "TESTMON", level = 4, hp = 12,
    stats = { hp = 12 }, moves = {} }, curTypes = { "NORMAL" }, stages = {} },
}
function battle:battleKind() return self.kind or "wild" end
function battle:effectRecord() return { accuracyChecked = true } end
function battle:visibleText() return { "Wild TESTMON appeared!" } end
function battle:menuLockedAction() return nil end
function battle:chooseMenu(choice)
  self.chosenMenu = choice
  if choice == "fight" then self.phase = "moveSelect" end
  return true
end
function battle:chooseMove(slot)
  self.chosenMove = slot
  self.phase = "messages"
  return true
end
function battle:cancelMove() self.phase = "menu" return true end
function battle:chooseSafari(action)
  self.chosenSafari, self.phase = action, "messages"
  return true
end
function battle:chooseMimic(slot)
  self.chosenMimic, self.phase = slot, "messages"
  return true
end
function battle:catchChance(ball)
  return require("src.battle.Catching").chance(ball, self.enemy.mon,
    game.data.pokemon[self.enemy.mon.species])
end
game.stack.states = { battle }

local api = require("src.battle.BattleAPI").new(game)
local snapshot = api:snapshot()
check(snapshot and snapshot.kind == "wild" and snapshot.prompt == "menu",
  "Gen 1 battle is exposed")
eq(snapshot.player.maxHp, 20, "Gen 1 max HP comes from battle stats")
eq(snapshot.moves[1].name, "TACKLE", "move records are copied")
eq(snapshot.message[1], "Wild TESTMON appeared!", "battle text is copied")
eq(#snapshot.items, 2, "medicine and balls are exposed")
check(type(snapshot.items[1].catchChance) == "number"
    or type(snapshot.items[2].catchChance) == "number",
  "stock catch chance is available")
snapshot.player.hp = 0
snapshot.moves[1].pp = 0
eq(mon.hp, 18, "changing a snapshot cannot change a Pokemon")
eq(battle.player.curMoves[1].pp, 35,
  "changing a snapshot cannot change a move")
local same = api:snapshot()
eq(same.revision, snapshot.revision, "unchanged battle keeps its revision")
battle.enemy.mon.hp = 5
check(api:snapshot().revision > same.revision,
  "observable battle changes advance the revision")
game.stack.states = {}
check(api:snapshot() == nil, "Gen 1 returns nil outside a battle")
game.stack.states = { battle }

local menu = api:snapshot()
local ok, err = api:submit({ id = 1, revision = menu.revision - 1,
  kind = "menu", choice = "fight" })
check(not ok and err == "stale battle context",
  "Gen 1 rejects a stale intent")
ok, err = api:submit({ id = 1, revision = menu.revision,
  kind = "menu", choice = "missing" })
check(not ok and err == "unknown battle menu choice",
  "Gen 1 rejects an unknown menu choice")
check(api:submit({ id = 1, revision = menu.revision,
  kind = "menu", choice = "fight" }), "Gen 1 accepts a menu intent")
eq(battle.chosenMenu, "fight", "Gen 1 uses the semantic menu path")
ok, err = api:submit({ id = 1, revision = menu.revision,
  kind = "menu", choice = "fight" })
check(not ok and err == "replayed intent", "Gen 1 rejects a replayed intent")
local moveMenu = api:snapshot()
ok, err = api:submit({ id = 2, revision = moveMenu.revision,
  kind = "move", slot = 9 })
check(not ok and err == "invalid move slot",
  "Gen 1 rejects an invalid move slot")
check(api:submit({ id = 2, revision = moveMenu.revision,
  kind = "move", slot = 1 }), "Gen 1 accepts a valid move")
eq(battle.chosenMove, 1, "Gen 1 uses the semantic move path")
battle.phase = "moveSelect"
local back = api:snapshot()
check(api:submit({ id = 3, revision = back.revision, kind = "back" }),
  "Gen 1 accepts move-menu back")
eq(battle.phase, "menu", "Gen 1 back restores the command menu")

battle.kind, battle.safari = "safari", { balls = 30 }
local safari = api:snapshot()
check(api:submit({ id = 4, revision = safari.revision,
  kind = "safari", action = "rock" }), "Gen 1 accepts a Safari action")
eq(battle.chosenSafari, "rock", "Gen 1 uses the semantic Safari path")
battle.kind, battle.safari = "wild", nil
battle.phase, battle.mimicMoves = "mimicSelect", { { slot = 1 } }
local mimic = api:snapshot()
check(api:submit({ id = 5, revision = mimic.revision,
  kind = "mimic", index = 1 }), "Gen 1 accepts a Mimic choice")
eq(battle.chosenMimic, 1, "Gen 1 uses the semantic Mimic path")

local player2 = { species = "CHIKORITA", level = 5, hp = 20,
  maxHp = 21, moves = { { id = "TACKLE", pp = 35, maxPp = 35 } } }
local enemy2 = { species = "RATTATA", level = 3, hp = 12, maxHp = 12,
  moves = {} }
local battle2 = { player = player2, enemy = enemy2, party = { player2 },
  wild = true, turn = 0 }
function battle2:moveDisabled() return false end
local screen2 = { screenId = "Gen2BattleState", battle = battle2,
  phase = "menu", menuIndex = 1, moveIndex = 1 }
function screen2:chooseMenu(choice)
  self.chosenMenu = choice
  if choice == "fight" then self.phase = "moves" end
  return true
end
function screen2:chooseMove(slot)
  self.chosenMove = slot
  self.phase = "resolving"
  return true
end
function screen2:cancelMove() self.phase = "menu" return true end
function screen2:catchChance(ball)
  return ball == "MASTER_BALL" and 100 or 37.5
end
local game2 = {
  data = {
    pokemon = { CHIKORITA = { name = "CHIKORITA" },
      RATTATA = { name = "RATTATA" } },
    moves = { TACKLE = { name = "TACKLE", type = "NORMAL",
      power = 35, accuracy = 95, pp = 35 } },
    items = {
      MASTER_BALL = { name = "MASTER BALL", pocket = "BALL" },
      POTION = { name = "POTION", pocket = "ITEM" },
    },
  },
  save = { party = { player2 }, inventory = {
    MASTER_BALL = 1, POTION = 2,
  } }, stack = { states = { screen2 } },
}

local api2 = require("src.battle.gen2.BattleAPI").new(game2)
local snapshot2 = api2:snapshot()
check(snapshot2 and snapshot2.kind == "wild" and snapshot2.prompt == "menu",
  "Gold battle is discovered through its screen id")
eq(snapshot2.player.maxHp, 21, "Gold max HP uses the mon field")
eq(snapshot2.moves[1].name, "TACKLE", "Gold moves are copied")
eq(#snapshot2.items, 1, "Gold exposes balls without guessing targeted items")
eq(snapshot2.items[1].catchChance, 100,
  "Gold ball records expose the exact catch preview")
snapshot2.player.hp = 0
snapshot2.moves[1].pp = 0
eq(player2.hp, 20, "changing a snapshot cannot change a Gold Pokemon")
eq(player2.moves[1].pp, 35,
  "changing a snapshot cannot change a Gold move")
screen2.message = "A wild RATTATA appeared!"
screen2.phase = "resolving"
local message2 = api2:snapshot()
eq(message2.prompt, "advance", "Gold message state is exposed")
check(message2.revision > snapshot2.revision,
  "Gold battle changes advance the revision")
game2.stack.states = {}
check(api2:snapshot() == nil, "Gold returns nil outside a battle")
game2.stack.states = { screen2 }

screen2.message = nil
screen2.phase = "menu"
local menu2 = api2:snapshot()
ok, err = api2:submit({ id = 1, revision = menu2.revision - 1,
  kind = "menu", choice = "fight" })
check(not ok and err == "stale battle context",
  "Gold rejects a stale intent")
ok, err = api2:submit({ id = 1, revision = menu2.revision,
  kind = "menu", choice = "missing" })
check(not ok and err == "unknown battle menu choice",
  "Gold rejects an unknown menu choice")
check(api2:submit({ id = 1, revision = menu2.revision,
  kind = "menu", choice = "fight" }), "Gold accepts a menu intent")
eq(screen2.chosenMenu, "fight", "Gold uses the semantic menu path")
local moveMenu2 = api2:snapshot()
ok, err = api2:submit({ id = 2, revision = moveMenu2.revision,
  kind = "move", slot = 9 })
check(not ok and err == "invalid move slot",
  "Gold rejects an invalid move slot")
check(api2:submit({ id = 2, revision = moveMenu2.revision,
  kind = "move", slot = 1 }), "Gold accepts a valid move")
eq(screen2.chosenMove, 1, "Gold uses the semantic move path")
screen2.phase = "moves"
local back2 = api2:snapshot()
check(api2:submit({ id = 3, revision = back2.revision, kind = "back" }),
  "Gold accepts move-menu back")
eq(screen2.phase, "menu", "Gold back restores the command menu")

do
  local Data = require("tests.modkit").fixtures.fresh()
  local Pokemon = require("src.pokemon.Pokemon")
  local SaveData = require("src.core.SaveData")
  local save = SaveData.newGame()
  save.party = { Pokemon.new(Data, "FIXMON_A", 20) }
  local pressed = {}
  local game3 = { data = Data, save = save, input = {
    wasPressed = function(_, key) return pressed[key] == true end,
    isDown = function() return false end,
  }, stack = { states = {} } }
  function game3.stack:top() return self.states[#self.states] end
  function game3.stack:push(state) self.states[#self.states + 1] = state end
  local real = Gen1BattleState.newWild(game3, "FIXMON_B", 12)
  real.phase, real.queue, real.introSlide = "menu", {}, nil
  game3.stack.states = { real }
  pressed.a = true
  real:update(1 / 60)
  pressed.a = nil
  eq(real.phase, "moveSelect", "native Gen 1 FIGHT uses the semantic path")
  pressed.b = true
  real:update(1 / 60)
  pressed.b = nil
  eq(real.phase, "menu", "native Gen 1 move-menu back still works")
end

do
  local state = setmetatable({ phase = "menu", safari = { balls = 30 },
    menuIndex = 1 }, { __index = Gen1BattleState })
  function state:safariAction(action) self.safariChoice = action end
  local ok, err = state:chooseSafari("missing")
  check(not ok and err == "invalid safari action",
    "native Safari rejects an unknown action")
  check(state:chooseSafari("rock"), "native Safari choice is accepted")
  eq(state.menuIndex, 3, "native Safari cursor follows the semantic choice")
  eq(state.safariChoice, "rock", "native Safari action uses the shared path")

  state.phase = "mimicSelect"
  state.mimicMoves = { { slot = 4 } }
  state.mimicCtx = { user = {}, target = {}, moveInst = {} }
  function state:applyMimic(_, _, _, slot) self.mimicSlot = slot end
  ok, err = state:chooseMimic(2)
  check(not ok and err == "invalid mimic slot",
    "native Mimic rejects an unknown choice")
  check(state:chooseMimic(1), "native Mimic choice is accepted")
  eq(state.phase, "messages", "native Mimic choice resumes battle messages")
  eq(state.mimicSlot, 4, "native Mimic choice copies the selected move slot")
end

local Loader = require("src.mods.Loader")
local fs = { read = function() end, getInfo = function() end,
  getDirectoryItems = function() return {} end }
local mod = { path = "mods/snapshot_test", manifest = {
  id = "snapshot_test", version = "1.0.0", permissionSet = {},
} }
local loader1 = Loader.new({ fs = fs, generation = 1 })
loader1.game = game
check(loader1:_api(mod).battle:snapshot().kind == "wild",
  "mod.battle selects the Gen 1 facade")
local loader2 = Loader.new({ fs = fs, generation = 2 })
loader2.game = game2
check(loader2:_api(mod).battle:snapshot().kind == "wild",
  "mod.battle selects the Gen 2 facade")

S.finish()
