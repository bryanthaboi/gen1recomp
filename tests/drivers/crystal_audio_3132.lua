local U = require("tests.drivers.util")

local ChipSynth = require("src.core.ChipSynth")
local Music = require("src.core.Music")

-- ../pokecrystal/engine/movie/intro.asm:616
local UNOWN_SOUNDS = {
  { 0x00, "Sfx_IntroUnown3" }, { 0x20, "Sfx_IntroUnown2" },
  { 0x40, "Sfx_IntroUnown1" }, { 0x60, "Sfx_IntroUnown2" },
  { 0x80, "Sfx_IntroUnown3" }, { 0x90, "Sfx_IntroUnown2" },
  { 0xa0, "Sfx_IntroUnown1" }, { 0xb0, "Sfx_IntroUnown2" },
}

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/crystal_audio_3132"
  local fails = 0
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    print((cond and "PASS " or "FAIL ") .. "3132 " .. line)
    return cond
  end
  local function tap(button, frames)
    game.input.pressQueue[#game.input.pressQueue + 1] = button
    game.input.state[button] = true
    U.wait(2)
    game.input.state[button] = false
    U.wait(frames or 4)
  end

  U.wait(60)
  local world = game.world
  if not (world and world.map) then
    print("FAIL 3132 the crystal world did not boot")
    love.event.quit(1)
    return
  end
  local data = game.data
  local songs = data.audio and data.audio.songs or {}
  local sfx = data.audio and data.audio.sfx or {}

  local Mon = require("src.battle.gen2.Mon")
  game.save.party = {}
  for _, species in ipairs({ "CYNDAQUIL", "PIDGEY", "RATTATA" }) do
    local mon = Mon.new(data, species, 10)
    mon.hp = 1
    game.save.party[#game.save.party + 1] = mon
  end

  world:warpToMapId("CHERRYGROVE_POKECENTER_1F", 3, 3, "up")
  U.wait(30)
  tap("a", 6)
  local sawAnim, balls, flashShot, jingle = false, 0, false, false
  for _ = 1, 60 * 30 do
    local ha = world.healAnim
    if ha then
      sawAnim = true
      if ha.lit > balls then balls = ha.lit end
      if Music.current() == "Music_HealPokemon" then jingle = true end
      if ha.phase == "flash" and ha.rotation ~= 0 and not flashShot then
        flashShot = U.still(game, out .. "/3132_01_heal_machine_flash_jingle_playing.png")
      end
      U.wait(1)
    elseif sawAnim then
      break
    else
      tap("a", 2)
    end
  end
  ok(sawAnim, "the heal machine ran at the Cherrygrove counter")
  ok(balls == 3, "one ball sound per party member (" .. balls .. ")")
  ok(jingle, "the heal jingle played over the flashing")
  ok(flashShot, "shot 3132_01_heal_machine_flash_jingle_playing.png")
  for _ = 1, 60 do
    if not world:busy() then break end
    tap("a", 4)
  end

  local rate = ChipSynth.SAMPLE_RATE
  if ok(songs.Music_HealPokemon ~= nil, "the cache carries Music_HealPokemon") then
    local engine = ChipSynth.newEngine(data, songs.Music_HealPokemon, { allowLoops = true })
    local lead = engine.channels[1]
    local register
    for _ = 1, 8 do
      local event = lead:nextEvent()
      if not event then break end
      if event.register and not event.silence then
        register = event.register
        break
      end
    end
    -- ../pokecrystal/audio/engine.asm:2727
    ok(register == 0x7F8, ("heal jingle lead starts at register $%03X (want $7F8)")
      :format(tonumber(register) or 0))
  end
  if ok(songs.Music_Mom ~= nil, "the cache carries Music_Mom") then
    local engine = ChipSynth.newEngine(data, songs.Music_Mom, { allowLoops = true })
    local kick = engine:drumInstrumentGen2(3, 4)
    local row2 = kick and kick[2] and kick[2].startSample
    -- ../pokecrystal/audio/engine.asm:1087
    ok(row2 and math.abs(row2 - 2 * rate / 60) <= 1,
      ("Kick1 second row starts on frame %.2f (want 2)"):format((row2 or 0) * 60 / rate))
  end
  if ok(sfx.Sfx_IntroUnown3 ~= nil, "the cache carries Sfx_IntroUnown3") then
    local engine = ChipSynth.newEngine(data, sfx.Sfx_IntroUnown3, { sfx = true, allowLoops = false })
    local event = engine.channels[1]:nextEvent()
    -- ../pokecrystal/audio/engine.asm:470
    ok(event and event.waveLevel == 0.25, "Unown wave note opens at quarter level ("
      .. tostring(event and event.waveLevel) .. ")")
    -- ../pokecrystal/audio/engine.asm:424
    ok(event and event.waveInstrument == 2, "Unown wave note uses wave pattern 2 ("
      .. tostring(event and event.waveInstrument) .. ")")
  end

  Music.play(data, "Music_Mom", true)
  U.wait(480)
  ok(Music.current() == "Music_Mom", "Mom's theme is playing (" .. tostring(Music.current()) .. ")")
  Music.stop()
  U.wait(30)

  local fired, frame = 0, 0
  for _, row in ipairs(UNOWN_SOUNDS) do
    while frame < row[1] do
      U.wait(1)
      frame = frame + 1
    end
    world:playSfxNamed(row[2])
    fired = fired + 1
  end
  U.wait(60)
  ok(fired == #UNOWN_SOUNDS, "the eight intro Unown sounds fired on the cart's schedule")

  print(("%s crystal_audio_3132 failures=%d"):format(fails == 0 and "PASS" or "FAIL", fails))
  love.event.quit(fails == 0 and 0 or 1)
end
