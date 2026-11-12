package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 audio cart trace")
local check, eq = S.check, S.eq

love = require("tests.love_stub")

local ChipSynth = require("src.core.ChipSynth")
local ChipAudio = require("src.core.ChipAudio")

local function slurp(path)
  local file = io.open(path, "rb")
  if not file then return nil end
  local body = file:read("*a")
  file:close()
  return body
end

local function roots()
  local list = {}
  local explicit = os.getenv("GOLD_CACHE")
  if explicit and explicit ~= "" then list[#list + 1] = explicit end
  local home = os.getenv("HOME")
  if home and home ~= "" then
    local identities = { "g1r-crystal", "g1r-gold", "g1r-silver" }
    local own = os.getenv("POKEPORT_IDENTITY")
    if own and own ~= "" then table.insert(identities, 1, own) end
    for _, base in ipairs({ home .. "/Library/Application Support/LOVE",
        home .. "/.local/share/love" }) do
      for _, identity in ipairs(identities) do
        for _, version in ipairs({ "crystal", "gold", "silver" }) do
          list[#list + 1] = base .. "/" .. identity .. "/" .. version
        end
      end
    end
  end
  return list
end

local function mount()
  for _, root in ipairs(roots()) do
    local chunk = loadfile(root .. "/data/generated/audio.lua")
    local audio = chunk and chunk()
    if type(audio) == "table" and audio.runtime == true
        and audio.generation == 2 and audio.programFile then
      local bytes = slurp(root .. "/" .. audio.programFile)
      if bytes then
        audio.programBytes = bytes
        return { audio = audio }
      end
    end
  end
  return nil
end

local data = mount()
if not data then
  print("[skip] no gen2 audio cache")
  S.finish()
  return
end

local songs = data.audio.songs
local rate = ChipSynth.SAMPLE_RATE
local frame = rate / 60

local function channel(engine, number)
  for _, candidate in ipairs(engine.channels) do
    if candidate.number == number then return candidate end
  end
end

local function hex(values)
  local out = {}
  for index, value in ipairs(values) do out[index] = ("%04X"):format(value) end
  return table.concat(out, " ")
end

local function slides(song, count)
  local engine = ChipSynth.newEngine(data, song, { allowLoops = true })
  local lead = channel(engine, 1)
  local found, first = {}, nil
  for _ = 1, 40 do
    local event = lead:nextEvent()
    if not event then break end
    if event.register and not first then first = event.register end
    if event.slide then
      found[#found + 1] = event.slide.registers and hex(event.slide.registers)
        or "no cart table"
      if #found >= count then break end
    end
  end
  return found, first
end

do
  local engine = ChipSynth.newEngine(data, songs.Music_Mom, { allowLoops = true })
  -- ../pokecrystal/audio/engine.asm:1087
  local kick = engine:drumInstrumentGen2(3, 4)
  eq(kick[2] and math.floor(kick[2].startSample / frame + 0.5), 2,
    "Kick1 second row starts two frames after the first")
  local drum28 = engine:drumInstrumentGen2(3, 8)
  eq(drum28[2] and math.floor(drum28[2].startSample / frame + 0.5), 5,
    "Drum28 second row starts five frames after the first")
  -- ../pokecrystal/audio/drumkits.asm:197
  local snare = engine:drumInstrumentGen2(3, 3)
  eq(#snare, 1, "Snare14 is one row")
  eq(snare[1] and snare[1].endSample, math.floor(8 / 64 * rate + 0.5),
    "Snare14 rings for its eight envelope steps")
end

do
  local heal, first = slides(songs.Music_HealPokemon, 5)
  -- ../pokecrystal/audio/engine.asm:2727
  eq(first, 0x7F8, "Music_HealPokemon channel 1 plays at stored octave 0")
  -- ../pokecrystal/audio/music/healpokemon.asm:14
  local cart = {
    "0765 06D3 0641 05AF 051C 048A 03F8 0365 02D3 0241 01AF 011D 008B FFF9",
    "07D9 07BB 079D 077F 0760 0741 0723 0705 06E7 06C9 06AB 068D 068D",
    "07E5 07D7 07C9 07BB 07AD 079E 0790 0782 0774 0766 0758 074A 073C 073C",
    "07A7 075B 070F 06C3 0676 062A 05DD 0591 0545 04F9 04AD 0461 0415 03C9 "
      .. "037D 0331 02E5 0299 024D 0201 01B5 0169 011D 00D1 0085 0039 FFED",
    "07AB 075F 0713 06C7 067A 062D 05E0 0594 0548 04FC 04B0 0464 0418 03CC "
      .. "0380 0334 02E8 029C 0250 0204 01B8 016C 0120 00D4 0088 003C FFF0",
  }
  for index = 1, 5 do
    eq(heal[index], cart[index],
      "Music_HealPokemon channel 1 slide " .. index .. " per frame")
  end
end

do
  local evolution = slides(songs.Music_Evolution, 2)
  -- ../pokecrystal/audio/engine.asm:762
  eq(evolution[1], "0646 0681 06BC 06F7 0732 0732",
    "Music_Evolution channel 1 rising slide per frame")
  eq(evolution[2], "0726 0726 0726 0726 0726 0726",
    "Music_Evolution channel 1 second slide stops after one step")
end

do
  local sound = ChipAudio._renderMusicChannelForTest(
    data, songs.Music_HealPokemon, 1.0, 1)
  local first, last = math.floor(0.7000 * rate), math.floor(0.7167 * rate)
  local sum = 0
  for index = first, last do sum = sum + sound:getSample(index) end
  local mean = sum / (last - first + 1)
  local crossings, previous = 0, sound:getSample(first) - mean
  for index = first + 1, last do
    local value = sound:getSample(index) - mean
    if previous <= 0 and value > 0 then crossings = crossings + 1 end
    previous = value
  end
  check(crossings >= 36 and crossings <= 45,
    ("the third heal note passes 2427 Hz on its third frame (%d crossings)")
      :format(crossings))
end

if songs.Music_CrystalOpening then
  local engine = ChipSynth.newEngine(data, songs.Music_CrystalOpening,
    { allowLoops = true })
  local noise = channel(engine, 4)
  local audible = false
  for _ = 1, rate * 30 do
    local value = 0
    for _, candidate in ipairs(engine.channels) do
      local sample = candidate:sample()
      if candidate == noise then value = sample end
    end
    local event = noise.event
    if event and event.dropDrumRows and value ~= 0 then
      audible = true
      break
    end
  end
  -- ../pokecrystal/audio/engine.asm:1116
  check(audible, "an empty drum note lets the ringing row finish")
end

S.finish()
