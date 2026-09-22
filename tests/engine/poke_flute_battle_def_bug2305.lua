-- audio/poke_flute.asm:1
-- engine/items/item_effects.asm:1739

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

love = require("tests.love_stub")

local GameVersion = require("src.core.GameVersion")

local rendered = {}
local ducked = {}
package.loaded["src.core.ChipAudio"] = {
  isSuspended = function() return false end,
  holdMusic = function() end,
  newSfx = function(_, name, _, _, header)
    rendered[#rendered + 1] = { name = name, header = header }
    return {
      setVolume = function() end, setPitch = function() end,
      stop = function() end, play = function() end,
      isPlaying = function() return true end,
    }
  end,
}
package.loaded["src.core.Music"] = {
  duckForFanfare = function(src) ducked[#ducked + 1] = src end,
}
love.audio = love.audio or {}
love.audio.newSource = love.audio.newSource or function() return nil end

local Sound = require("src.core.Sound")

local function stockData()
  return { audio = { sfx = {
    Caught_Mon = { bank = 8, address = 0x41CE, engine = 2 },
    Pokeflute = { bank = 2, address = 0x4228, engine = 1 },
  } } }
end

local function starts(def)
  local map = {}
  for _, spec in ipairs(def.startChannels or {}) do
    map[spec.number] = spec.address
  end
  return map
end

GameVersion.current = "red"
local red = Sound._pokefluteInBattleDef(stockData())
check(red ~= nil, "a stock Caught_Mon header derives the in-battle flute")
local r = starts(red)
eq(r[5], 0x6322, "red SFX_Pokeflute_Ch5")
eq(r[6], 0x6325, "red SFX_Pokeflute_Ch6")
eq(r[7], 0x449b, "red SFX_Pokeflute_Ch7")
eq(red.bank, 8, "the header stays SFX_CAUGHT_MON's bank")
eq(red.address, 0x41CE, "and its address")
eq(red.fanfare, true, "it claims the fanfare duck")

GameVersion.current = "blue"
local b = starts(Sound._pokefluteInBattleDef(stockData()))
eq(b[5], 0x6322, "blue shares red's addresses")
eq(b[7], 0x449b, "blue ch7")

GameVersion.current = "yellow"
local y = starts(Sound._pokefluteInBattleDef(stockData()))
eq(y[5], 0x59eb, "yellow SFX_Pokeflute_Ch5")
eq(y[6], 0x59ee, "yellow SFX_Pokeflute_Ch6")
eq(y[7], 0x444b, "yellow SFX_Pokeflute_Ch7")
GameVersion.current = "red"

local data = stockData()
check(data.audio.sfx.Caught_Mon.startChannels == nil,
  "the registry Caught_Mon def is never mutated")
check(data.audio.sfx.Pokeflute_In_Battle == nil,
  "and nothing new lands in the sfx registry")

eq(Sound._pokefluteInBattleDef({ audio = { sfx = {
  Caught_Mon = "caught.wav" } } }), nil, "a file Caught_Mon derives nothing")
eq(Sound._pokefluteInBattleDef({ audio = { sfx = {
  Caught_Mon = { chip = {}, bank = 8, address = 0x41CE } } } }), nil,
  "a chip-blob Caught_Mon derives nothing")
eq(Sound._pokefluteInBattleDef({ audio = { sfx = {
  Caught_Mon = { bank = 8, address = 0x41D1, engine = 2 } } } }), nil,
  "a relocated Caught_Mon derives nothing")
eq(Sound._pokefluteInBattleDef({}), nil, "no audio table derives nothing")

rendered, ducked = {}, {}
local src = Sound.playPokefluteInBattle(stockData())
check(src ~= nil, "the in-battle flute starts a source")
eq(#rendered, 1, "one render")
eq(rendered[1] and rendered[1].name, "Pokeflute_In_Battle",
  "under its own key, never the field Pokeflute")
local p = starts(rendered[1] and rendered[1].header or {})
eq(p[5], 0x6322, "rendered with ch5 overwritten")
eq(p[6], 0x6325, "rendered with ch6 overwritten")
eq(p[7], 0x449b, "rendered with ch7 overwritten")
eq(#ducked, 1, "the battle song ducks under it")

rendered = {}
Sound.invalidate()
local plain = { audio = { sfx = {
  Pokeflute = { bank = 2, address = 0x4228, engine = 1 } } } }
Sound.playPokefluteInBattle(plain)
eq(rendered[1] and rendered[1].name, "Pokeflute",
  "no Caught_Mon header falls back to the field tune")

local function modded(field)
  local d = stockData()
  d.audio.sfx.Pokeflute = field
  return d
end

love.audio.newSource = function(file)
  rendered[#rendered + 1] = { name = "Pokeflute", file = file }
  return {
    setVolume = function() end, setPitch = function() end,
    stop = function() end, play = function() end,
    isPlaying = function() return true end,
  }
end

for _, case in ipairs({
  { "mod_flute.wav", "a mod file Pokeflute" },
  { { chip = {}, bank = 2, address = 0x4228, engine = 1 }, "a mod chip-blob Pokeflute" },
  { { bank = 2, address = 0x4300, engine = 1 }, "a relocated Pokeflute" },
  { { bank = 8, address = 0x4228, engine = 2 }, "a Pokeflute moved to another bank" },
}) do
  rendered = {}
  Sound.invalidate()
  Sound.playPokefluteInBattle(modded(case[1]))
  eq(rendered[1] and rendered[1].name, "Pokeflute",
    case[2] .. " plays in battle instead of the derived phrase")
  check(rendered[1] and starts(rendered[1].header or {})[5] == nil,
    case[2] .. " keeps its own channels")
end

rendered = {}
Sound.invalidate()
local noField = stockData()
noField.audio.sfx.Pokeflute = nil
Sound.playPokefluteInBattle(noField)
eq(rendered[1] and rendered[1].name, "Pokeflute_In_Battle",
  "no Pokeflute def at all still derives the in-battle phrase")

rendered = {}
Sound.invalidate()
Sound.playPokefluteInBattle(stockData())
eq(rendered[1] and rendered[1].name, "Pokeflute_In_Battle",
  "the stock Pokeflute header still gets the derived phrase")

T.finish("in-battle poke flute def (#2305)")
