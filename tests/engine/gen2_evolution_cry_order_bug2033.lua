--   luajit tests/engine/gen2_evolution_cry_order_bug2033.lua
-- ../pokecrystal/engine/movie/evolution_animation.asm:82-92, :151-158
-- ../pokecrystal/home/pokemon.asm:124-127
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 evolution cry order")
local check, eq = S.check, S.eq

local CRY_FRAMES = 12
local log, source = {}, nil

package.loaded["src.core.Sound"] = {
  resolve = function(_, name) return name end,
  play = function(_, name) log[#log + 1] = "sfx:" .. tostring(name) end,
  playCry = function(_, species)
    log[#log + 1] = "cry:" .. tostring(species)
    source = { left = CRY_FRAMES }
    source.isPlaying = function(self) return self.left > 0 end
    return source
  end,
}
package.loaded["src.core.Music"] = {
  stop = function() log[#log + 1] = "music:stop" end,
  play = function(_, id) log[#log + 1] = "music:" .. tostring(id) end,
  restoreMap = function() end,
  current = function() return nil end,
}

local EvolutionAnim = require("src.ui.gen2.EvolutionAnim")

local data = {
  pokemon = { GLOOM = { name = "GLOOM" }, VILEPLUME = { name = "VILEPLUME" } },
  audio = {
    cries = { GLOOM = true, VILEPLUME = true },
    songs = { Music_Evolution = true },
    sfx = { Sfx_Evolved = true, Sfx_CaughtMon = true },
  },
  text = require("tests.fixture_data.gen2_rom_text_s7_b").text(),
}

local function at(entry)
  for index, line in ipairs(log) do
    if line == entry then return index end
  end
  return nil
end

local function screen(opts)
  log, source = {}, nil
  local mon = { species = "GLOOM", level = 30, hp = 40, maxHp = 40,
    status = opts and opts.status }
  local save = { party = { mon }, pokedex = { seen = {}, caught = {} } }
  local game = { data = data, save = save }
  local anim = EvolutionAnim.new(game, {
    mon = mon, entry = { into = "VILEPLUME" }, index = 1,
    party = save.party, save = save, force = true,
  })
  local function tick()
    if source then source.left = source.left - 1 end
    anim:update(1 / 60)
  end
  return anim, tick
end

-- ../pokecrystal/engine/movie/evolution_animation.asm:82-92

local anim, tick = screen()
local frames = 0
while anim.phase ~= "flash" and frames < 400 do
  tick()
  frames = frames + 1
end
eq(anim.phase, "flash", "the screen reaches the flashing burst")

check(at("cry:GLOOM") ~= nil, "the old species cries on the way in")
check(at("music:Music_Evolution") ~= nil, "and MUSIC_EVOLUTION starts")
check(at("music:stop") < at("cry:GLOOM"),
  "PlayMusic MUSIC_NONE runs before the cry")
check(at("cry:GLOOM") < at("music:Music_Evolution"),
  "PlayMonCry's WaitSFX holds MUSIC_EVOLUTION until the cry is done")

-- ../pokecrystal/engine/movie/evolution_animation.asm:88-92
local Evolution = require("src.core.gen2.Evolution")
check(frames > Evolution.EVOLVING_FRAMES + Evolution.MUSIC_FRAMES,
  "and the beat is longer than the 50 + 80 DelayFrames alone ("
    .. frames .. " frames)")

-- ../pokecrystal/engine/movie/evolution_animation.asm:113-130

anim, tick = screen()
local congrats, cried = nil, nil
for frame = 1, 2000 do
  tick()
  if not cried and at("cry:VILEPLUME") then cried = frame end
  if anim.phase == "congrats" then congrats = frame break end
end
check(cried ~= nil, "the evolved species cries")
check(congrats ~= nil, "and the screen reaches the congratulations page")
check(congrats and cried and congrats > cried,
  "the text does not print on the same frame as the cry")
check(congrats and cried and congrats - cried >= CRY_FRAMES,
  "it waits the cry out (" .. tostring(congrats and cried
    and congrats - cried) .. " frames)")

-- ../pokecrystal/engine/movie/evolution_animation.asm:151-158

log, source = {}, nil
local mon = { species = "GLOOM", level = 30, hp = 40, maxHp = 40 }
local save = { party = { mon }, pokedex = { seen = {}, caught = {} } }
local pressB = true
local game = { data = data, save = save,
  input = { wasPressed = function(_, b) return b == "b" and pressB end } }
local cancel = EvolutionAnim.new(game, {
  mon = mon, entry = { into = "VILEPLUME" }, index = 1,
  party = save.party, save = save,
})
local stopped, cancelCry = nil, nil
for frame = 1, 2000 do
  if source then source.left = source.left - 1 end
  cancel:update(1 / 60)
  if cancel.phase == "flash" then pressB = true else pressB = false end
  if not cancelCry and cancel.canceled and at("cry:GLOOM") then
    local first = at("cry:GLOOM")
    for index = first + 1, #log do
      if log[index] == "cry:GLOOM" then cancelCry = frame break end
    end
  end
  if cancel.phase == "stopped" then stopped = frame break end
end
check(cancel.canceled, "B during a hold cancels the evolution")
check(stopped ~= nil, "and the screen reaches StoppedEvolvingText")
check(cancelCry ~= nil, "CancelEvolution's own PlayMonCry runs first")
check(stopped and cancelCry and stopped - cancelCry >= CRY_FRAMES,
  "and the line waits it out")

-- ../pokecrystal/engine/pokemon/stats_screen.asm:1183-1195
anim, tick = screen({ status = "sleep" })
for _ = 1, 400 do
  tick()
  if anim.phase == "flash" then break end
end
eq(at("cry:GLOOM"), nil, ".check_statused skips the entry cry")
check(at("music:Music_Evolution") ~= nil, "the music still starts")

S.finish()
