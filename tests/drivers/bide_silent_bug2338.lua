-- engine/battle/effects.asm:764-789
-- engine/battle/core.asm:3481-3506
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "/tmp/shots"

  local fails = 0
  local function check(label, ok)
    if ok then
      print("PASS " .. label)
    else
      print("FAIL " .. label)
      fails = fails + 1
    end
    return ok
  end

  local function flat(s) return (tostring(s or ""):gsub("[\n\v\f]", " ")) end

  game.save.options = game.save.options or {}
  game.save.options.animations = true

  local lead = Pokemon.new(game.data, "CHARMANDER", 20)
  lead.moves = { { id = "BIDE", pp = 10 } }
  game.save.party = { lead }

  U.teleport(game, "ROUTE_1", 5, 5, "down")
  U.wait(15)
  local ow = game.overworld
  check("standing on ROUTE_1", ow and ow.map and ow.map.id == "ROUTE_1")

  local function watcher(battle)
    local w = { shown = {}, anims = {}, queued = {} }
    local markQ, lastCur = {}, nil
    function w.poll()
      for _, row in ipairs(battle.queue) do
        if not markQ[row] then
          markQ[row] = true
          if row.text then w.queued[#w.queued + 1] = flat(row.text) end
          if row.anim then w.anims[#w.anims + 1] = row.anim end
        end
      end
      local cur = battle.current
      if cur ~= lastCur then
        lastCur = cur
        if cur and cur.text then
          w.shown[#w.shown + 1] = flat(cur.text)
          return flat(cur.text)
        end
      end
      return nil
    end
    return w
  end

  local function has(list, needle)
    for _, s in ipairs(list) do
      if s:find(needle, 1, true) then return true end
    end
    return false
  end

  local function waitPhase(battle, phase, tries, w)
    for _ = 1, tries do
      if battle.phase == phase then return true end
      U.tap(game, "a")
      for _ = 1, 6 do w.poll() U.wait(1) end
    end
    return battle.phase == phase
  end

  local function pickFirstMove(battle, w)
    U.tap(game, "a")
    if not waitPhase(battle, "moveSelect", 10, w) then return false end
    U.tap(game, "a")
    return true
  end

  local function settledShot(watch, path)
    for _ = 1, 100 do watch.poll() U.wait(1) end
    return U.shot(game, path)
  end

  local function leaveBattle()
    for _ = 1, 10 do
      if game.stack:top() == ow then break end
      game.stack:pop()
    end
  end

  local battle = BattleState.newWild(game, "RATTATA", 8)
  battle.onFinish = function() end
  battle.enemy.mon.moves = { { id = "TACKLE", pp = 35 } }
  battle.enemy.curMoves = battle.enemy.mon.moves
  ow:pushBattle(battle)
  local w = watcher(battle)
  check("player battle reached the menu", waitPhase(battle, "menu", 80, w))
  local sinceShown, sinceQueued = #w.shown, #w.queued
  check("BIDE picked", pickFirstMove(battle, w))

  local tackles, unleashed = 0, false
  local lockedSeen, sawSpiral = false, false
  local shots = {}
  for _ = 1, 3000 do
    local line = w.poll()
    if has(w.anims, "XSTATITEM_ANIM") then sawSpiral = true end
    if line then
      if line:find("TACKLE", 1, true) then
        tackles = tackles + 1
        if tackles == 1 and not shots.store then
          shots.store = settledShot(w, DIR .. "/2338_01_store_turn_spiral_then_foe_tackle.png")
        elseif tackles >= 2 and not shots.locked then
          lockedSeen = true
          shots.locked = settledShot(w, DIR .. "/2338_02_locked_turn_only_foe_text.png")
        end
      elseif line:find("unleashed energy", 1, true) then
        unleashed = true
        shots.release = settledShot(w, DIR .. "/2338_03_release_unleashed_energy.png")
        break
      end
    end
    if game.stack:top() ~= battle then
      if not game.stack:top() or battle.player.mon.hp <= 0 then break end
    end
    if U.frame() % 6 == 0 then U.tap(game, "a") else U.wait(1) end
  end

  local pShown, pQueued = {}, {}
  for i = sinceShown + 1, #w.shown do pShown[#pShown + 1] = w.shown[i] end
  for i = sinceQueued + 1, #w.queued do pQueued[#pQueued + 1] = w.queued[i] end
  local stray = {}
  for _, s in ipairs(pShown) do
    if s:find("CHARMANDER", 1, true) and not s:find("used BIDE", 1, true)
       and not s:find("unleashed energy", 1, true) then
      stray[#stray + 1] = s
    end
    if s:find("unleashed energy", 1, true) then break end
  end
  U.log("player battle shown: " .. table.concat(pShown, " | "))
  check("storing turn played the X-item spiral", sawSpiral)
  check("no storing-energy line shown on the player's side",
        not has(pShown, "storing energy"))
  check("no storing-energy line queued on the player's side",
        not has(pQueued, "storing energy"))
  check("foe acted on at least one locked turn (" .. tackles .. " TACKLE lines)",
        lockedSeen)
  check("no CHARMANDER line besides used BIDE before the release: "
          .. (#stray > 0 and table.concat(stray, " | ") or "(none)"), #stray == 0)
  check("release printed unleashed energy", unleashed)
  for _ = 1, 30 do w.poll() U.wait(1) end
  check("release played BIDE's own animation", has(w.anims, "BIDE"))

  leaveBattle()

  lead.hp = lead.stats.hp
  lead.status = nil
  lead.moves = { { id = "SCRATCH", pp = 35 } }
  local foeBattle = BattleState.newWild(game, "RATTATA", 25)
  foeBattle.onFinish = function() end
  foeBattle.enemy.mon.moves = { { id = "BIDE", pp = 10 } }
  foeBattle.enemy.curMoves = foeBattle.enemy.mon.moves
  ow:pushBattle(foeBattle)
  local fw = watcher(foeBattle)
  check("foe battle reached the menu", waitPhase(foeBattle, "menu", 80, fw))
  local fSince = #fw.shown
  local fQSince = #fw.queued
  check("SCRATCH picked", pickFirstMove(foeBattle, fw))

  local scratches, foeUnleashed, foeSpiral = 0, false, false
  local foeStoreShot = false
  for _ = 1, 3000 do
    local line = fw.poll()
    if has(fw.anims, "XSTATITEM_DUPLICATE_ANIM") then foeSpiral = true end
    if line then
      if line:find("SCRATCH", 1, true) then
        scratches = scratches + 1
        if foeSpiral and not foeStoreShot then
          foeStoreShot = true
          settledShot(fw, DIR .. "/2338_04_foe_store_turn_then_player_move.png")
        end
      elseif line:find("unleashed energy", 1, true) then
        foeUnleashed = true
        break
      end
    end
    if game.stack:top() ~= foeBattle then
      if not game.stack:top() or foeBattle.enemy.mon.hp <= 0 then break end
    end
    if U.frame() % 6 == 0 then U.tap(game, "a") else U.wait(1) end
  end

  local fShown, fQueued = {}, {}
  for i = fSince + 1, #fw.shown do fShown[#fShown + 1] = fw.shown[i] end
  for i = fQSince + 1, #fw.queued do fQueued[#fQueued + 1] = fw.queued[i] end
  local fStray = {}
  for _, s in ipairs(fShown) do
    if s:find("RATTATA", 1, true) and not s:find("used BIDE", 1, true)
       and not s:find("unleashed energy", 1, true) then
      fStray[#fStray + 1] = s
    end
    if s:find("unleashed energy", 1, true) then break end
  end
  U.log("foe battle shown: " .. table.concat(fShown, " | "))
  check("foe's storing turn played XSTATITEM_DUPLICATE_ANIM", foeSpiral)
  check("no storing-energy line shown on the foe's side",
        not has(fShown, "storing energy"))
  check("no storing-energy line queued on the foe's side",
        not has(fQueued, "storing energy"))
  check("player moved through the foe's locked turns (" .. scratches
          .. " SCRATCH lines)", scratches >= 2)
  check("no RATTATA line besides used BIDE before the release: "
          .. (#fStray > 0 and table.concat(fStray, " | ") or "(none)"), #fStray == 0)
  check("foe's release printed unleashed energy", foeUnleashed)

  leaveBattle()
  print(fails == 0 and "PASS bide_silent_bug2338" or "FAIL bide_silent_bug2338")
  love.event.quit(fails == 0 and 0 or 1)
end
