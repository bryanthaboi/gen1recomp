-- engine/items/item_effects.asm:1706-1745

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local check, eq = T.check, T.eq
local Data = T.fixtures.fresh()
require("src.render.Font").load(Data)

local plays = {}
local sources = {}
local function newSource(file)
  local src = sources[file]
  if src then return src end
  src = {
    playing = false,
    setVolume = function() end,
    setPitch = function() end,
    stop = function() end,
    isPlaying = function(self) return self.playing end,
    play = function(self)
      plays[#plays + 1] = file
      self.playing = true
    end,
  }
  sources[file] = src
  return src
end
love.audio = { newSource = newSource }
Data.audio = { sfx = { Press_AB = "ab.wav", Pokeflute = "flute.wav" },
               fanfares = {} }

local function tunes()
  local n = 0
  for _, file in ipairs(plays) do
    if file == "flute.wav" then n = n + 1 end
  end
  return n
end

local BagMenu = require("src.ui.BagMenu")
local TextBox = require("src.render.TextBox")

local function newGame(alarm)
  local mon = { species = "FIXMON_A", hp = 20, stats = { hp = 20 },
                level = 12, status = "SLP", moves = {} }
  local game = {
    data = Data,
    save = {
      party = { mon },
      player = { name = "RED" },
      inventory = { POKE_FLUTE = 1 },
      options = { textSpeed = 1 }, flags = {},
      pokedex = { seen = {}, owned = {} },
    },
  }
  game.stack = { states = {},
    push = function(self, s) table.insert(self.states, s) end,
    pop = function(self) return table.remove(self.states) end,
    top = function(self) return self.states[#self.states] end }
  local pressed = {}
  game.input = {
    wasPressed = function(_, key) return pressed[key] or false end,
    isDown = function() return false end,
  }
  game.press = function(btn)
    pressed = btn and { [btn] = true } or {}
    local top = game.stack:top()
    if top and top.update then top:update(1 / 60) end
    pressed = {}
  end
  local battle = {
    player = { mon = mon },
    enemy = { mon = { species = "FIXMON_B", hp = 15, stats = { hp = 15 },
                      level = 8 } },
    enemyParty = {},
    turns = 0,
    lowHealthAlarmActive = function() return alarm == true end,
  }
  battle.itemUsed = function(self) self.turns = self.turns + 1 end
  return game, battle
end

local function useFlute(game, battle)
  local list = BagMenu.new(game, { battle = battle })
  game.stack:push(list)
  for i, item in ipairs(list.items) do
    if item.value == "POKE_FLUTE" then
      list.index = i
      list.onChoose(item, list)
      return true
    end
  end
  return false
end

local function typeOut(game, box)
  for _ = 1, 2000 do
    if box.done then return true end
    game.press(box.waiting and "a" or nil)
  end
  return false
end

do
  local game, battle = newGame(false)
  check(useFlute(game, battle), "the flute is in the battle bag")
  local box = game.stack:top()
  check(getmetatable(box) == TextBox, "the played-flute line is up")
  check(typeOut(game, box), "and it types out")
  eq(tunes(), 0, "no tune before the prompt (text_promptbutton)")

  game.press("a")
  eq(box.autoPrompted, true, "A answers the prompt")
  game.press()
  eq(tunes(), 1, "and Music_PokeFluteInBattle starts after it")
  eq(game.stack:top(), box, "the played-flute line stays up under the tune")

  for _ = 1, 30 do game.press("a") end
  eq(tunes(), 1, "mashing A neither retriggers nor cuts the tune short")
  eq(game.stack:top(), box, "and cannot dismiss the box (.musicWaitLoop)")
  eq(battle.turns, 0, "so the turn cannot resolve over the flute")

  sources["flute.wav"].playing = false
  game.press()
  local woke = game.stack:top()
  check(woke ~= box and getmetatable(woke) == TextBox,
    "FluteWokeUpText prints once CHAN7 is clear")
  eq(battle.turns, 0, "the turn still waits on that second PrintText")
  check(typeOut(game, woke), "the woke-up line types out")
  for _ = 1, 4 do
    if battle.turns > 0 then break end
    game.press("a")
  end
  eq(battle.turns, 1, "dismissing it spends the turn")
  eq(game.stack:top(), nil, "and the bag is gone with it")
end

do
  plays = {}
  sources["flute.wav"].playing = false
  local game, battle = newGame(true)
  check(useFlute(game, battle), "the flute is in the bag with the alarm up")
  local box = game.stack:top()
  check(typeOut(game, box), "the played-flute line types out")
  game.press("a")
  eq(tunes(), 0, "the alarm skips the tune (.skipMusic)")
  local woke = game.stack:top()
  check(woke ~= box and getmetatable(woke) == TextBox,
    "and A goes straight to FluteWokeUpText")
  check(typeOut(game, woke), "which types out")
  for _ = 1, 4 do
    if battle.turns > 0 then break end
    game.press("a")
  end
  eq(battle.turns, 1, "the turn is spent the same way")
end

do
  plays = {}
  sources["flute.wav"].playing = false
  Data.audio.sfx.Pokeflute_In_Battle = "battleflute.wav"
  local game, battle = newGame(false)
  check(useFlute(game, battle), "the flute is in the bag again")
  local box = game.stack:top()
  check(typeOut(game, box), "the played-flute line types out")
  game.press("a")
  game.press()
  eq(tunes(), 0, "the field SFX_Pokeflute never plays in battle")
  eq(plays[#plays], "battleflute.wav", "Music_PokeFluteInBattle does")
  eq(game.stack:top(), box, "and the box holds under it")
  sources["battleflute.wav"].playing = false
  game.press()
  local woke = game.stack:top()
  check(woke ~= box and getmetatable(woke) == TextBox,
    "FluteWokeUpText follows once it ends")
  Data.audio.sfx.Pokeflute_In_Battle = nil
end

T.finish("poke flute battle tune (#1938)")
