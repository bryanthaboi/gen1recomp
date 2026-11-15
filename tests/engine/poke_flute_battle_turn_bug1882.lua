-- pokered engine/items/item_effects.asm:1-3 (#1882)

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local ItemEffects = require("src.inventory.ItemEffects")

local data = {
  items = { POKE_FLUTE = { id = "POKE_FLUTE", index = 49, name = "POKé FLUTE" },
            POTION = { id = "POTION", index = 1, name = "POTION", price = 300 } },
  text = dofile("tests/fixture_data/text.lua"),
}

local function newSave(status)
  return {
    party = { { species = "CHARMANDER", hp = 20, stats = { hp = 20 },
                level = 12, status = status } },
    player = { name = "RED" },
    inventory = { POKE_FLUTE = 1, POTION = 1 },
    options = {}, flags = {},
  }
end

local function newBattle(save, enemyStatus)
  return {
    player = { mon = save.party[1] },
    enemy = { mon = { species = "PIDGEY", hp = 15, stats = { hp = 15 },
                      level = 8, status = enemyStatus } },
    enemyParty = {},
  }
end

do
  local save = newSave(nil)
  local battle = newBattle(save, nil)
  local result, msgs = ItemEffects.use(data, save, "POKE_FLUTE", nil, battle)
  eq(result, "kept", "nothing asleep still takes the turn")
  check(msgs and msgs[1] and msgs[1]:find("catchy"),
        "and prints PlayedFluteNoEffectText")
  eq(save.inventory.POKE_FLUTE, 1, "the flute is a key item, never consumed")
end

do
  local save = newSave("SLP")
  local battle = newBattle(save, nil)
  local result = ItemEffects.use(data, save, "POKE_FLUTE", nil, battle)
  eq(result, "flute", "a sleeping party mon is the had-effect arm")
  eq(save.party[1].status, nil, "WakeUpEntireParty cleared the sleep")
end

do
  local save = newSave(nil)
  local battle = newBattle(save, "SLP")
  local result = ItemEffects.use(data, save, "POKE_FLUTE", nil, battle)
  eq(result, "flute", "a sleeping active enemy is the had-effect arm too")
end

do
  local save = newSave(nil)
  local battle = newBattle(save, nil)
  local result = ItemEffects.use(data, save, "POTION", save.party[1], battle)
  eq(result, "failed", "a POTION on a full-HP mon still costs no turn")
end

package.loaded["src.render.TextBox"] = {
  new = function(_, text, done) return { textBox = true, text = text, done = done } end,
  soundOpts = function(_, _, opts) return opts end,
}
package.loaded["src.ui.BagMenu"] = nil
local BagMenu = require("src.ui.BagMenu")

do
  local save = newSave(nil)
  local battle = newBattle(save, nil)
  local turns = 0
  battle.itemUsed = function() turns = turns + 1 end
  local game = { data = data, save = save }
  game.stack = { states = {},
    push = function(self, s) table.insert(self.states, s) end,
    pop = function(self) return table.remove(self.states) end,
    top = function(self) return self.states[#self.states] end }
  local list = BagMenu.new(game, { battle = battle })
  game.stack:push(list)
  local row
  for i, item in ipairs(list.items) do
    if item.value == "POKE_FLUTE" then row = i end
  end
  if check(row ~= nil, "the flute is in the battle bag") then
    list.index = row
    list.onChoose(list.items[row], list)
    local box = game.stack:top()
    if check(box and box.textBox, "the no-effect line is up") then
      eq(turns, 0, "the turn waits on the message")
      game.stack:pop()
      box.done()
      eq(turns, 1, "dismissing it spends the turn")
      eq(game.stack:top(), nil, "and the bag is gone, not back on ITEMS")
    end
  end
end

T.finish("poke_flute_battle_turn_bug1882")
