package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
love = require("tests.love_stub")
local CacheContract = require("src.import.CacheContract")
local ChipSynth = require("src.core.ChipSynth")
local GameVersion = require("src.core.GameVersion")

local function slurp(path)
  local file = io.open(path, "rb")
  if not file then return nil end
  local body = file:read("*a")
  file:close()
  return body
end

local function rootFor(version)
  local home = os.getenv("HOME")
  if not home or home == "" then return nil end
  local identities = { "g1r-" .. version, "pokeport-test-caches" }
  local own = os.getenv("POKEPORT_IDENTITY")
  if own and own ~= "" then table.insert(identities, 1, own) end
  local prefix = GameVersion.cachePrefix(version)
  for _, base in ipairs({ home .. "/Library/Application Support/LOVE",
      home .. "/.local/share/love" }) do
    for _, identity in ipairs(identities) do
      local root = base .. "/" .. identity .. "/" .. prefix
      if CacheContract.markerMatches(version,
          slurp(root .. CacheContract.MARKER_PATH)) then
        return root
      end
    end
  end
  return nil
end

local function mount(version)
  local root = rootFor(version)
  if not root then return nil end
  local chunk = loadfile(root .. "data/generated/audio.lua")
  local audio = chunk and chunk()
  local bytes = audio and slurp(root .. audio.programFile)
  if not bytes then return nil end
  audio.programBytes = bytes
  return { audio = audio }
end

local function registers(data, header, options, number, frames)
  local engine = ChipSynth.newEngine(data, header, options)
  local channel
  for _, candidate in ipairs(engine.channels) do
    if candidate.number == number then channel = candidate end
  end
  local rate = ChipSynth.SAMPLE_RATE
  local unit = channel.wave and 65536 or 131072
  local runs, previous, count = {}, nil, 0
  local index, lastEvent = 0, nil
  for frame = 0, frames - 1 do
    local last = math.floor((frame + 1) * rate / 60 + 0.5)
    local value = "rest"
    while index < last do
      for _, other in ipairs(engine.channels) do
        if other ~= channel then other:sample() end
      end
      local before = channel.phase
      channel:sample()
      local event = channel.event
      if event ~= lastEvent then
        lastEvent = event
        before = 0
      end
      if event and event.register and not event.silence then
        local step = (channel.phase - before) % 1
        value = tostring(math.floor(2048 - unit / (step * rate) + 0.5))
      else
        value = "rest"
      end
      index = index + 1
    end
    if value == previous then
      count = count + 1
    else
      if previous then runs[#runs + 1] = previous .. "x" .. count end
      previous, count = value, 1
    end
  end
  runs[#runs + 1] = previous .. "x" .. count
  return table.concat(runs, " ")
end

ChipSynth.setSampleRate(44100)

local crystal = mount("crystal")
local red = mount("red")
if not crystal and not red then
  print("[skip] chip_vibrato_register_trace: no imported Crystal or Red cache")
  os.exit(0)
end

if crystal then
  local unown = crystal.audio.sfx.Sfx_IntroUnown3
  -- ../pokecrystal/audio/sfx_crystal.asm:27
  T.eq(registers(crystal, unown, { sfx = true, allowLoops = false }, 7, 43),
    "1986x5 1989x3 1986x2 1984x2 1986x3 1989x4 1984x4 1989x4 1984x2 "
      .. "1986x3 1989x4 1986x1 1984x4 1989x2",
    "Sfx_IntroUnown3 channel 7 register per frame")

  local engine = ChipSynth.newEngine(crystal, unown,
    { sfx = true, allowLoops = false })
  local levels, waves = {}, {}
  for _ = 1, 6 do
    local event = engine.channels[1]:nextEvent()
    levels[#levels + 1] = tostring(event.waveLevel)
    waves[#waves + 1] = tostring(event.waveInstrument)
  end
  -- ../pokecrystal/audio/engine.asm:470
  T.eq(table.concat(levels, " "), "0.25 0.5 1 1 0.5 0.25",
    "Sfx_IntroUnown3 output level per square_note")
  -- ../pokecrystal/audio/engine.asm:424
  T.eq(table.concat(waves, " "), "2 2 2 2 2 2",
    "Sfx_IntroUnown3 wave pattern per square_note")

  -- ../pokecrystal/audio/music/crystalopening.asm:128
  T.eq(registers(crystal, crystal.audio.songs.Music_CrystalOpening,
      { allowLoops = true }, 2, 160),
    "1517x20 1519x5 1515x5 1519x5 1515x3 1517x10 1519x3 1517x10 1515x2 "
      .. "1517x11 1519x5 1515x5 1519x5 1517x8 1515x5 1517x8 1519x4 1517x9 "
      .. "1515x5 1519x5 1515x5 1519x2 1517x11 1515x2 1517x7",
    "Music_CrystalOpening channel 2 register per frame")
else
  print("[info] no crystal cache; skipped")
end

if red then
  -- ../pokered/audio/music/pallettown.asm:264
  T.eq(registers(red, red.audio.songs.Music_PalletTown,
      { allowLoops = true }, 3, 150),
    "1880x33 1881x9 1879x3 1849x31 1850x9 1848x5 1870x29 1871x1 1880x30",
    "Music_PalletTown channel 3 register per frame")

  -- ../pokered/audio/music/titlescreen.asm:4
  T.eq(registers(red, red.audio.songs.Music_TitleScreen,
      { allowLoops = true }, 1, 200),
    "1253x6 1379x7 1517x7 1601x7 1379x14 1381x5 1378x5 1381x3 1379x12 "
      .. "1378x5 1381x5 1378x5 1381x5 1378x5 1381x3 1379x26 1378x5 1381x5 "
      .. "1378x5 1379x10 1381x5 1378x5 1381x5 1378x2 1379x13 1381x5 1378x5 "
      .. "1381x4 1452x11",
    "Music_TitleScreen channel 1 register per frame")

  -- ../pokered/audio/music/safarizone.asm:9
  T.eq(registers(red, red.audio.songs.Music_SafariZone,
      { allowLoops = true }, 1, 120),
    "1023x1 1606x1 1665x1 1724x1 1783x1 1842x1 1533x1 1830x5 1023x1 1606x1 "
      .. "1665x1 1724x1 1783x1 1842x1 1533x1 1830x5 restx25 1548x8 1547x5 "
      .. "1550x5 1547x5 1550x2 1714x10 1713x5 1716x5 1713x5 1548x7 1550x5 "
      .. "1547x5 1550x4",
    "Music_SafariZone channel 1 register per frame")
else
  print("[info] no red cache; skipped")
end

T.finish()
