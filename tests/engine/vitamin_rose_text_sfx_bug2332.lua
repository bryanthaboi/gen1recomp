-- engine/items/item_effects.asm:1310-1317
-- data/text/text_6.asm:71-77

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq, same = T.check, T.eq, T.same
love = love or require("tests.love_stub")

local game
local played = {}
package.loaded["src.core.Sound"] = {
  play = function(_, name)
    local boxes = 0
    if game then
      for _, s in ipairs(game.stack.states) do
        if type(s) == "table" and s.textBox then boxes = boxes + 1 end
      end
    end
    played[#played + 1] = { name = name, boxes = boxes }
  end,
  playCry = function() end,
}
local jingles = {}
package.loaded["src.render.TextBox"] = {
  new = function(_, text, done, opts)
    return { textBox = true, text = text, done = done, opts = opts }
  end,
  strip = function(text)
    if type(text) ~= "string" then return text end
    return (text:gsub("{DONE}", ""):gsub("{PROMPT}", ""))
  end,
  soundOpts = function(_, sound, opts)
    jingles[#jingles + 1] = sound
    opts = opts or {}
    opts.auto = { sound = sound, wait = true }
    return opts
  end,
}
package.loaded["src.inventory.ItemEffects"] = nil
package.loaded["src.ui.BagMenu"] = nil
package.loaded["src.ui.PartyMenu"] = nil
local ItemEffects = require("src.inventory.ItemEffects")
local BagMenu = require("src.ui.BagMenu")
local PartyMenu = require("src.ui.PartyMenu")
require("src.ui.Screens").invalidate()

local Fixtures = require("tests.modkit.fixtures")
local Bag = require("src.inventory.Bag")
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")

local Data = Fixtures.fresh()
local VITAMIN_NAMES = {
  HP_UP = "HP UP", PROTEIN = "PROTEIN", IRON = "IRON",
  CARBOS = "CARBOS", CALCIUM = "CALCIUM",
}
local idx = 200
for id, name in pairs(VITAMIN_NAMES) do
  idx = idx + 1
  Data.items[id] = { id = id, index = idx, name = name, price = 9800,
                     tossable = true }
end

local function heard(name)
  for _, p in ipairs(played) do
    if p.name == name then return p end
  end
  return nil
end

local function gengar()
  local mon = Pokemon.new(Data, "FIXMON_A", 20)
  mon.nickname = "GENGAR"
  return mon
end

do
  local save = SaveData.newGame()
  for id, stat in pairs({ HP_UP = "HEALTH", PROTEIN = "ATTACK",
                          IRON = "DEFENSE", CARBOS = "SPEED",
                          CALCIUM = "SPECIAL" }) do
    played = {}
    local result, msgs, extra = ItemEffects.use(Data, save, id, gengar())
    eq(result, "consumed", id .. " is consumed")
    eq(msgs and msgs[1], "GENGAR's\n" .. stat .. " rose.",
       id .. " prints VitaminStatRoseText's layout")
    check(not (extra and extra.useJingle),
          id .. " does not defer Heal_Ailment to the end of the text")
    check(heard("Heal_Ailment") ~= nil,
          id .. " plays Heal_Ailment itself, before PrintText")
  end
end

do
  local mon = gengar()
  mon.statExp = { special = 25600 }
  played = {}
  local result = ItemEffects.use(Data, SaveData.newGame(), "CALCIUM", mon)
  eq(result, "failed", "a maxed stat is refused")
  eq(heard("Heal_Ailment"), nil, "and the refusal plays no Heal_Ailment")
end

local function freshGame()
  local mon = gengar()
  local g = {
    data = Data,
    save = {
      party = { mon },
      player = { name = "RED", id = 1 },
      inventory = {},
      options = {},
      flags = {},
      money = 0,
    },
  }
  g.stack = {
    states = {},
    push = function(self, s) table.insert(self.states, s) end,
    pop = function(self) return table.remove(self.states) end,
    top = function(self) return self.states[#self.states] end,
  }
  g.input = { pressed = nil }
  function g.input:wasPressed(b) return self.pressed == b end
  Bag.add(g.save, "CALCIUM", 2)
  return g, mon
end

do
  local mon
  game, mon = freshGame()
  played, jingles = {}, {}
  local list = BagMenu.new(game, {})
  game.stack:push(list)
  local row
  for i, r in ipairs(list.items) do
    if r.value == "CALCIUM" then row = i end
  end
  if check(row ~= nil, "CALCIUM is in the bag") then
    list.index = row
    list.onChoose(list.items[row], list)
    local sub = game.stack:top()
    if sub and sub.items and sub.items[1] and sub.items[1].onSelect then
      game.stack:pop()
      sub.items[1].onSelect()
    end
    local picker = game.stack:top()
    if check(getmetatable(picker) == PartyMenu, "the party picker opened") then
      game.input.pressed = "a"
      picker:update(1 / 60)
      game.input.pressed = nil
      eq(mon.statExp.special, 2560, "CALCIUM raised SPECIAL stat exp")
      local p = heard("Heal_Ailment")
      if check(p ~= nil, "Heal_Ailment played through the bag flow") then
        eq(p.boxes, 0, "before the rose box was pushed")
      end
      same(jingles, {}, "no end-of-text jingle is armed on the rose box")
      local box = game.stack:top()
      if check(type(box) == "table" and box.textBox, "the rose line prints") then
        eq(box.text, "GENGAR's\nSPECIAL rose.", "with the cart's line break")
        eq(box.opts, nil, "as a plain prompt box")
      end
      local partyUp = false
      for _, s in ipairs(game.stack.states) do
        if getmetatable(s) == PartyMenu then partyUp = true end
      end
      check(partyUp, "the party menu stays drawn under the message")
    end
  end
  game = nil
end

T.finish()
