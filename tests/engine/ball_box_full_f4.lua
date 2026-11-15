-- engine/items/item_effects.asm:114-125
-- engine/items/item_effects.asm:2309-2311
-- engine/events/give_pokemon.asm:7-12
--   luajit tests/engine/ball_box_full_f4.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local ItemEffects = require("src.inventory.ItemEffects")
local Boxes = require("src.pokemon.Boxes")

local data = {
  text = {
    _BoxFullCannotThrowBallText = "BOX FULL{PROMPT}",
    _ItemUseText001 = "{PLAYER} used{DONE}",
    _ItemUseText002 = "{RAM:wStringBuffer}!{DONE}",
  },
  items = { POKE_BALL = { name = "POKE BALL" } },
}

local function save(partyCount, boxCount)
  local s = { player = { name = "RED" }, party = {}, currentBox = 1 }
  for i = 1, partyCount do s.party[i] = { species = "RATTATA" } end
  Boxes.ensure(s)
  for _ = 1, boxCount do table.insert(s.boxes[1], { species = "PIDGEY" }) end
  return s
end

check(type(ItemEffects.ballBoxFull) == "function", "ballBoxFull exists")

local full = save(6, Boxes.CAPACITY)
local r, msgs = ItemEffects.use(data, full, "POKE_BALL", nil, { kind = "wild" })
eq(r, "failed", "party 6 + current box 20: the ball is refused")
eq(msgs and msgs[1], "BOX FULL{PROMPT}", "refusal is _BoxFullCannotThrowBallText")

eq(ItemEffects.use(data, save(6, Boxes.CAPACITY - 1), "POKE_BALL", nil, { kind = "wild" }),
   "ball", "party 6 + box 19: the ball is thrown")
eq(ItemEffects.use(data, save(5, Boxes.CAPACITY), "POKE_BALL", nil, { kind = "wild" }),
   "ball", "party 5 + box 20: the ball is thrown")
eq(ItemEffects.use(data, full, "POKE_BALL", nil, { kind = "trainer" }),
   "ball", "trainer battle reaches ThrowBallAtTrainerMon first")
check(not ItemEffects.ballBoxFull(full, { kind = "wild", demo = true }),
      "old man / Pikachu demo skips the check")

local other = save(6, Boxes.CAPACITY)
other.currentBox = 2
eq(ItemEffects.use(data, other, "POKE_BALL", nil, { kind = "wild" }), "ball",
   "only the current box counts")

eq(ItemEffects.itemUseLine(data, { player = { name = "RED" } }, "SAFARI BALL"),
   "RED used\nSAFARI BALL!", "used line is _ItemUseText001 + text_low + _ItemUseText002")

local Commands = require("src.script.Commands")
local gameStub = { data = { pokemon = { EEVEE = { name = "EEVEE" } } } }
local Pokemon = require("src.pokemon.Pokemon")
local BattleState = require("src.battle.BattleState")
Pokemon.new = function(_, species, level) return { species = species, level = level } end
BattleState.stampOT = function() end
local gs = save(6, Boxes.CAPACITY)
local ctx = { game = gameStub, save = gs }
Commands.give_pokemon(ctx, "EEVEE", 25)
eq(ctx.lastCheck, false, "gift with party 6 + current box 20 is refused")
eq(#gs.boxes[2], 0, "gift never overflows into the next box")

local direct = save(6, Boxes.CAPACITY)
local battle = setmetatable({ kind = "wild", queue = {}, data = data,
  game = { save = direct, data = data } }, { __index = BattleState })
eq(battle:throwBall("POKE_BALL"), false, "direct throwBall with party 6 + box 20 is refused")
eq(#battle.queue, 1, "direct throwBall queues only the refusal")
eq(battle.queue[1] and battle.queue[1].text, "BOX FULL{PROMPT}", "direct throwBall prints _BoxFullCannotThrowBallText")
eq(battle.afterQueue, "menu", "direct throwBall refusal returns to the menu")
eq(#direct.boxes[1], Boxes.CAPACITY, "direct throwBall never grows the box past capacity")

local Party = require("src.pokemon.Party")
local savedMax = Party.MAX
Party.MAX = 3
check(ItemEffects.ballBoxFull(save(3, Boxes.CAPACITY), { kind = "wild" }), "ballBoxFull reads Party.MAX")
Party.MAX = savedMax

local function slurp(p)
  local f = assert(io.open(p, "rb"))
  local s = f:read("*a")
  f:close()
  return s
end
local bs = slurp("src/battle/BattleState.lua")
for _, label in ipairs({ "_ItemUseBallText06", "_ItemUseBallText07", "_ItemUseBallText08" }) do
  check(not bs:find(label .. '",%s*"') and not bs:find("transferred to\\n", 1, true)
    and not bs:find("will be added for\\n", 1, true), label .. " has no hand-typed fallback")
end
local caught = setmetatable({ data = { text = {} } }, { __index = BattleState })
check(not pcall(caught.romText, caught, "_ItemUseBallText06", nil, "PIDGEY"),
  "a cache without _ItemUseBallText06 is an error")

T.finish()
