-- home/pokemon.asm:145, home/delay.asm:15, home/text.asm:506
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or os.getenv("POKEPORT_SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local Growth = require("src.pokemon.Growth")
  local BattleState = require("src.battle.BattleState")
  local Sound = require("src.core.Sound")

  game.speedOverride = 4

  local pikachu = Pokemon.new(game.data, "PIKACHU", 5, function(_, b) return b end)
  local def = game.data.pokemon.PIKACHU
  pikachu.exp = Growth.expForLevel(def.growthRate, 6, game.data.growth_rates) - 1
  game.save.party = { pikachu }

  U.teleport(game, "ROUTE_1", 5, 5, "down")
  local ow = game.overworld

  local battle = BattleState.newWild(game, "RATTATA", 2)
  battle.onFinish = function() end
  battle.rng = function(a, _) return a end
  battle.enemy.mon.hp = 1
  battle.enemy.mon.stats.speed = 1
  ow:pushBattle(battle)

  U.log("logic speed", game:logicSpeed(), "sfx rate", Sound.rate())
  local function inBattle()
    for _, st in ipairs(game.stack.states) do
      if st == battle then return true end
    end
    return false
  end
  local function assertLocked(where)
    if inBattle() and game:logicSpeed() ~= 1 then
      error(("speed lock: %s ran at %sX with speedOverride 4")
        :format(where, tostring(game:logicSpeed())))
    end
  end
  assertLocked("battle start")
  if Sound.rate() ~= 1 then
    error(("bug2087: Game:update pitched SFX off battle speed (rate %s at 4X)")
      :format(tostring(Sound.rate())))
  end

  local starts = setmetatable({}, { __mode = "k" })
  local function stamp(fn)
    return function(...)
      local src = fn(...)
      if src and not starts[src] then starts[src] = love.timer.getTime() end
      return src
    end
  end
  Sound.play, Sound.playCry = stamp(Sound.play), stamp(Sound.playCry)
  if Sound.playPikaCry then Sound.playPikaCry = stamp(Sound.playPikaCry) end

  local gates = {}
  local cur
  local function poll(label)
    local src = battle.waitingSound
    if src and not cur then
      local okd, d = pcall(src.getDuration, src)
      local okp, p = pcall(src.getPitch, src)
      cur = { label = label, src = src, t0 = starts[src] or love.timer.getTime(),
              dur = okd and d or nil, pitch = okp and p or nil }
    elseif cur and src ~= cur.src then
      cur.held = love.timer.getTime() - cur.t0
      table.insert(gates, cur)
      cur = nil
      if src then poll(label) end
    end
  end

  local lockedFrames = 0
  local shot = false
  for _ = 1, 2400 do
    assertLocked("entrance")
    if inBattle() then lockedFrames = lockedFrames + 1 end
    poll("entrance cry")
    if battle.phase == "menu" then break end
    if battle.waitingSound and not shot then
      shot = U.shot(game, DIR .. "/bug2087_cry.png")
    end
    U.tap(game, "a")
    U.wait(2)
  end
  if battle.phase ~= "menu" then error("bug2087: never reached the FIGHT menu") end
  if #gates < 2 then
    error(("bug2087: expected the enemy and player cries to arm the gate, saw %d")
      :format(#gates))
  end

  U.tap(game, "a")
  for _ = 1, 60 do
    if battle.phase == "moveSelect" then break end
    U.wait(1)
  end
  if battle.phase ~= "moveSelect" then error("bug2087: never reached move select") end
  U.tap(game, "a")

  local before = #gates
  local shotLevel = false
  for _ = 1, 2400 do
    poll("post-move sfx")
    if game.stack:top() ~= battle then break end
    assertLocked("post-move")
    if #gates > before and cur and not shotLevel then
      shotLevel = U.shot(game, DIR .. "/bug2087_levelup.png")
    end
    U.tap(game, "a")
    U.wait(1)
  end
  poll("post-move sfx")
  if #gates == before then error("bug2087: the level-up jingle never armed the gate") end
  U.shot(game, DIR .. "/bug2087_after.png")

  local fail
  for i, g in ipairs(gates) do
    U.log(("%s #%d duration %.3fs pitch %s held %.3fs"):format(
      g.label, i, g.dur or -1, tostring(g.pitch), g.held or -1))
    if g.pitch and g.pitch ~= 1 then
      fail = ("bug2087: %s was pitched with battle speed (%s)"):format(
        g.label, tostring(g.pitch))
    elseif g.dur and g.held < g.dur * 0.9 then
      fail = ("bug2087: %s cut short (%.3fs of %.3fs)"):format(
        g.label, g.held, g.dur)
    end
  end
  if fail then error(fail) end
  if lockedFrames == 0 then error("speed lock: the battle never reached the stack") end
  U.log("PASS every battle sfx gate held for its real length, battle locked to 1X under a 4X override")
  love.event.quit(0)
end
