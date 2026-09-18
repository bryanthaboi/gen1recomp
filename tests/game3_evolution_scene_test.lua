#!/usr/bin/env luajit
-- Dedicated Gen 3 Evolution Scene & Core Parity Tests

package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local Pokemon = require("src.core.game3.pokemon")
local Evolution = require("src.core.game3.evolution")
local EvolutionScene = require("src.ui.game3.evolution_scene")
local Bag = require("src.core.game3.bag")

print("=== [TEST 1] Nickname Matching & Sanitization (EvolutionRenameMon) ===")
do
  -- 1. Un-nicknamed (nil)
  local mon1 = { species = 1, speciesId = 1, nickname = nil, name = "BULBASAUR" }
  Evolution.renameMon(mon1, 1, 2)
  check(mon1.nickname == "IVYSAUR" and mon1.name == "IVYSAUR", "un-nicknamed (nil) renamed to IVYSAUR")

  -- 2. Un-nicknamed matching pre-evo name
  local mon2 = { species = 1, speciesId = 1, nickname = "BULBASAUR", name = "BULBASAUR" }
  Evolution.renameMon(mon2, 1, 2)
  check(mon2.nickname == "IVYSAUR" and mon2.name == "IVYSAUR", "un-nicknamed matching pre-evo renamed to IVYSAUR")

  -- 3. Un-nicknamed with null-padding / trailing spaces
  local mon3 = { species = 1, speciesId = 1, nickname = "BULBASAUR\0\0  ", name = "BULBASAUR" }
  Evolution.renameMon(mon3, 1, 2)
  check(mon3.nickname == "IVYSAUR" and mon3.name == "IVYSAUR", "padded un-nicknamed renamed to IVYSAUR")

  -- 4. Custom nickname preserved
  local mon4 = { species = 1, speciesId = 1, nickname = "SPROUT", name = "SPROUT" }
  Evolution.renameMon(mon4, 1, 2)
  check(mon4.nickname == "SPROUT" and mon4.name == "SPROUT", "custom nickname SPROUT preserved on evolution")
end

print("=== [TEST 2] Everstone Protection ===")
do
  local monNormal = { species = 1, speciesId = 1, level = 16, heldItem = 0 }
  local target, _ = Evolution.levelTarget(monNormal)
  check(target == 2, "normal Lv 16 Bulbasaur evolves into Ivysaur (species 2)")

  local monEverstone = { species = 1, speciesId = 1, level = 16, heldItem = 197 } -- ITEM_EVERSTONE
  local blockedTarget = Evolution.levelTarget(monEverstone)
  check(blockedTarget == nil, "Everstone blocks level-up evolution")

  -- Evolutionary stone bypasses Everstone
  local clefairy = { species = 35, speciesId = 35, level = 16, heldItem = 197 }
  local clefableTarget = Evolution.itemTarget(clefairy, 94) -- ITEM_MOON_STONE (94)
  check(clefableTarget == 36, "Moon Stone bypasses Everstone on Clefairy (evolves to Clefable 36)")
end

print("=== [TEST 3] Stat Recalculation & HP Delta ===")
do
  -- Alive mon gains HP delta
  local monAlive = { species = 1, speciesId = 1, level = 16, hp = 15, maxHp = 40, iv = { 15, 15, 15, 15, 15, 15 }, ev = { 0, 0, 0, 0, 0, 0 } }
  Evolution.apply(monAlive, 2)
  check(monAlive.species == 2, "mutated to species 2 (Ivysaur)")
  check(monAlive.maxHp > 40, "maxHp increased on evolution")
  local delta = monAlive.maxHp - 40
  check(monAlive.hp == 15 + delta, "current HP gained exact maxHp delta (" .. tostring(monAlive.hp) .. ")")

  -- Fainted mon preserves 0 HP
  local monFainted = { species = 1, speciesId = 1, level = 16, hp = 0, maxHp = 40, iv = { 15, 15, 15, 15, 15, 15 }, ev = { 0, 0, 0, 0, 0, 0 } }
  Evolution.apply(monFainted, 2)
  check(monFainted.hp == 0, "fainted mon remains at 0 HP after evolution")
end

print("=== [TEST 4] Shedinja Cloning & Sanitization (Nincada Lv 20 -> Ninjask + Shedinja) ===")
do
  local bag = Bag.new()
  Bag.add(bag, 4, 5) -- 5 standard Poké Balls

  local party = {
    {
      species = 290, speciesId = 290, level = 20,
      hp = 45, maxHp = 45,
      heldItem = 197, -- Leftovers / Everstone
      status = "PSN",
      pokeball = 2, -- Ultra Ball
      ability = 1,
      moves = { 10, 20, 30, 40 },
      iv = { 31, 31, 31, 31, 31, 31 },
      ev = { 0, 0, 0, 0, 0, 0 },
    }
  }
  local session = { party = party, dex = { seen = {}, caught = {} }, bag = bag }

  local nincada = party[1]
  Evolution.apply(nincada, 291, session, bag)

  check(#party == 2, "Shedinja spawned into party (party size = 2)")
  check(party[1].species == 291, "primary mon evolved into Ninjask (species 291)")

  local shedinja = party[2]
  check(shedinja.species == 292, "shedinja species is 292")
  check(shedinja.maxHp == 1 and shedinja.hp == 1, "shedinja maxHp and hp are exactly 1")
  check(shedinja.heldItem == 0, "shedinja heldItem is sanitized to 0 (no duplicate items)")
  check(shedinja.status == 0, "shedinja status condition is sanitized to 0")
  check(shedinja.pokeball == 4, "shedinja pokeball is standardized to ITEM_POKE_BALL (4)")
  check(shedinja.ability == 25, "shedinja ability is Wonder Guard (25)")
  check(Bag.get(bag, 4) == 4, "exactly 1 Poké Ball was deducted from bag (5 -> 4)")
  check(session.dex.caught[292] == true, "Shedinja registered as Caught in Pokédex")
end

print("=== [TEST 5] EvolutionScene State Machine & B-Button Cancellation ===")
do
  local mon = { species = 1, speciesId = 1, level = 16, hp = 40, maxHp = 40 }
  local cancelled = false
  local evolved = false

  -- Start EvolutionScene with canStop = true
  local ok = EvolutionScene.start(mon, 2, {
    canStop = true,
    onDone = function(result)
      if result == "stopped" then cancelled = true end
      if result == "evolved" then evolved = true end
    end
  })
  check(ok == true, "EvolutionScene started")
  check(EvolutionScene.isOpen() == true, "EvolutionScene is open")

  -- Advance frames into cycle phase (reaches cycle at frame 156)
  for _ = 1, 180 do
    EvolutionScene.update(1 / 60)
  end
  check(EvolutionScene._state == "cycle", "entered cycle phase")

  -- Simulate B-button press to cancel
  local mockInput = {
    isDown = function(_, k) return k == "b" end,
    wasPressed = function(_, k) return k == "b" end,
  }
  EvolutionScene.handleInput(mockInput)
  check(EvolutionScene._state == "cancel", "state transitioned to cancel on B-button")
  check(mon.species == 1, "species remained Bulbasaur (species 1) after cancellation")

  -- Advance text dismiss (first press skips typewriter, second dismisses)
  EvolutionScene.handleInput(mockInput)
  EvolutionScene.handleInput(mockInput)
  check(EvolutionScene.isOpen() == false, "EvolutionScene closed after cancel")
  check(cancelled == true, "onDone called with result 'stopped'")
end

print("=== [TEST 6] EvolutionScene Point-of-No-Return Completion ===")
do
  local mon = { species = 1, speciesId = 1, level = 16, hp = 40, maxHp = 40 }
  local completed = false

  EvolutionScene.start(mon, 2, {
    canStop = false,
    headless = true,
    onDone = function(result)
      if result == "evolved" then completed = true end
    end
  })

  -- Run through entire animation cycle past acceleration cutoff (speed >= 128)
  for _ = 1, 800 do
    EvolutionScene.update(1 / 60)
    if EvolutionScene._state == "congrats" or EvolutionScene._state == "learn_moves" then
      local mockInput = {
        wasPressed = function(_, k) return k == "a" end,
        isDown = function() return false end,
      }
      EvolutionScene.handleInput(mockInput)
    end
  end

  check(mon.species == 2, "species successfully mutated to Ivysaur (species 2)")
  check(mon.nickname == "IVYSAUR", "nickname updated to IVYSAUR")
  check(completed == true, "onDone called with result 'evolved'")
end

print("=== [TEST 7] EvolutionScene Audio Sequence & Map Music Restoration ===")
do
  local Audio = require("src.core.game3.audio")
  local playedSongs = {}
  local origPlaySong = Audio.playSong
  Audio.playSong = function(id, opts)
    playedSongs[#playedSongs + 1] = id
    return origPlaySong(id, opts)
  end

  Audio._mapSong = 279 -- Pallet Town
  Audio._currentSong = { id = 279 }

  local mon = { species = 19, speciesId = 19, level = 20, hp = 40, maxHp = 40, moves = { 33, 39, 43, 99 } }
  local completed = false

  EvolutionScene.start(mon, 20, {
    canStop = false,
    headless = true,
    savedSong = 279,
    onDone = function(result)
      if result == "evolved" then completed = true end
    end
  })

  check(EvolutionScene._savedSong == 279, "EvolutionScene savedSong preserved as 279")

  -- Progress past congrats
  for _ = 1, 800 do
    EvolutionScene.update(1 / 60)
    if EvolutionScene._state == "congrats" or EvolutionScene._state == "learn_moves" then
      local mockInput = {
        wasPressed = function(_, k) return k == "a" end,
        isDown = function() return false end,
      }
      EvolutionScene.handleInput(mockInput)
    end
  end

  check(completed == true, "evolution completed")
  check(playedSongs[#playedSongs] == 279, "Pallet Town map BGM (279) restored at end of evolution sequence")

  Audio.playSong = origPlaySong
end

print("=== [TEST 8] EvolutionScene Post-Battle Victory Theme Resumption ===")
do
  local Audio = require("src.core.game3.audio")
  local playedSongs = {}
  local origPlaySong = Audio.playSong
  Audio.playSong = function(id, opts)
    playedSongs[#playedSongs + 1] = id
    return origPlaySong(id, opts)
  end

  Audio._mapSong = 279 -- Pallet Town
  Audio._currentSong = { id = 311 } -- MUS_VICTORY_WILD

  local mon = { species = 19, speciesId = 19, level = 20, hp = 40, maxHp = 40, moves = { 33, 39 } }
  local completed = false

  local EvoSeq = require("src.core.game3.battle.evo_seq")
  local session = { party = { mon } }
  EvoSeq.begin({ { mon = mon, target = 20 } }, {
    session = session,
    onDone = function() completed = true end
  })

  -- Advance frames and dismiss dialogs
  for _ = 1, 800 do
    EvoSeq.update()
    EvolutionScene.update(1 / 60)
    local Choice = package.loaded["src.ui.game3.choice"]
    if Choice and Choice.active then
      Choice.cancel()
    end
    if EvolutionScene._state == "congrats" or EvolutionScene._state == "learn_moves" then
      local mockInput = {
        wasPressed = function(_, k) return k == "a" end,
        isDown = function() return false end,
      }
      EvolutionScene.handleInput(mockInput)
    end
  end
  EvoSeq.update()

  check(completed == true, "battle evolution sequence finished")
  check(playedSongs[#playedSongs] == 311, "Victory theme (311) resumed during and after post-battle evolution")

  Audio.playSong = origPlaySong
end

if failed > 0 then
  print(string.format("\n[FAILED] %d test(s) failed", failed))
  os.exit(1)
else
  print("\nALL 8 EVOLUTION SCENE TESTS PASSED CLEANLY!")
end
