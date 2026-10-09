-- pokeemerald/src/battle_interface.c:1450
-- pokeemerald/src/battle_bg.c:1124
local U = require("tests.drivers.util")
local F = require("tests.drivers.em_fa_util")
local S = F.new("em_party_tray_entry_bg_2802_2803", os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_2802_2803")

return function(game)
  if not F.boot(game, S) then return S.finish() end
  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local Anim = require("src.core.game3.battle.anim")
  local Audio = require("src.core.game3.audio")
  local SE = require("src.core.game3.se_ids")
  local Message = require("src.ui.game3.message")
  local Chrome = require("src.ui.game3.chrome")
  local Trainers = require("src.core.game3.scripting.trainers")
  local C = require("src.core.game3.constants").of("emerald")
  local session = Runtime.getSession()
  F.noTrainerSight()
  S.check(F.goTo(game, "EM_ROUTE117", 32, 15, "down"), "Route 117 reached")
  session.party = {}
  Party.giveMon(session, C.species.byName.SPECIES_BRELOOM, 40, "BRELOOM")
  Party.giveMon(session, C.species.byName.SPECIES_SWELLOW, 40, "SWELLOW")
  Party.giveMon(session, C.species.byName.SPECIES_MARILL, 40, "MARILL")
  session.party[2].hp = 0

  local frame, played, arrows = 0, {}, 0
  local playSe = Audio.playSe
  Audio.playSe = function(id, opts)
    played[#played + 1] = { id = SE.resolve(id), frame = frame, pan = opts and opts.pan }
    return playSe(id, opts)
  end
  local promptArrow = Chrome.promptArrow
  Chrome.promptArrow = function(...)
    if Message._frame == "battle" then arrows = arrows + 1 end
    return promptArrow(...)
  end
  local function step(n)
    for _ = 1, n or 1 do
      frame = frame + 1
      U.wait(1)
    end
  end
  local function count(id, from)
    local n = 0
    for _, p in ipairs(played) do if p.id == id and p.frame >= (from or 0) then n = n + 1 end end
    return n
  end

  local trainer = C.trainers.byName.TRAINER_CALVIN_1
  local foe = Trainers.foeFromId(trainer)
  local grass = C.battle.byName.BATTLE_ENVIRONMENT_GRASS
  local ok = foe and BattleBridge.start(Runtime._mod, game, foe, { wild = false, trainerId = trainer, terrain = grass })
  if not S.check(ok == true, "trainer battle started on grass") then return S.finish() end
  for _ = 1, 600 do
    if Battle.isActive() and Anim.stage().entry then break end
    step()
  end
  local s = Anim.stage()
  local e = s.entry
  S.check(e ~= nil and e.key == "grass" and e.kind == 1, "grass entry layer armed, key=" .. tostring(e and e.key))
  local sawScroll, sawSink, shotEntry, shotSink = false, false, false, false
  for _ = 1, 200 do
    e = s.entry
    if not e then break end
    if e.x > 0 then sawScroll = true end
    if e.x >= 200 and not shotEntry then shotEntry = S.still(game, "2803_01_grass_entry_mid_slide.png") end
    if e.y < -20 then
      sawSink = true
      if not shotSink then shotSink = S.still(game, "2803_02_grass_entry_sinking.png") end
    end
    step()
  end
  S.check(sawScroll, "entry layer scrolls left 6px per frame")
  S.check(sawSink, "entry layer sinks after the window opens")
  S.check(s.entry == nil, "entry layer cleared when the slide ends")

  local trayStart
  for _ = 1, 400 do
    if s.partyBar.player.visible and s.partyBar.player.ballState then trayStart = frame break end
    step()
  end
  if not S.check(trayStart ~= nil, "party tray shown") then return S.finish() end
  local p = s.partyBar.player
  local enemy = s.partyBar.enemy
  local barHome, midShot, landed = nil, false, {}
  for _ = 1, 120 do
    for i = 1, 6 do
      if p.ballState[i].done and not landed[i] then landed[i] = frame end
    end
    if barHome == nil and p.ox == 0 then barHome = frame end
    if not midShot and landed[2] and not landed[5] then midShot = S.still(game, "2802_01_tray_mid_slide.png") end
    step()
  end
  local barT, ballT = barHome and barHome - trayStart, landed[1] and landed[1] - trayStart
  S.check(barT and ballT and math.abs(barT - 20) <= 2 and barT - ballT == 1,
    "bar slides 5px/frame home in 20 frames, first ball lands 1 frame earlier (bar=" .. tostring(barT)
      .. " ball=" .. tostring(ballT) .. ")")
  local stagger = true
  for i = 2, 6 do
    if not (landed[i] and landed[i - 1] and landed[i] - landed[i - 1] == 7) then stagger = false end
  end
  S.check(stagger, "player balls land one by one, 7 frames apart")
  S.check(count(SE.SE_BALL_TRAY_ENTER, trayStart) == 2, "SE_BALL_TRAY_ENTER once per side")
  S.check(count(SE.SE_BALL_TRAY_BALL, trayStart) >= 3, "SE_BALL_TRAY_BALL per filled slot")
  S.check(count(SE.SE_BALL_TRAY_BALL, trayStart) + count(SE.SE_BALL_TRAY_EXIT, trayStart) == 12,
    "one landing tick per ball on both sides")
  S.check(enemy.visible and enemy.ox == 0, "enemy tray slid home")
  S.check(p.balls[2] == "faint", "fainted slot uses the fainted ball")

  local arrowShot = false
  for _ = 1, 300 do
    if Message.isWaiting and Message.isWaiting() and Message._frame == "battle" then
      step(20)
      arrowShot = S.still(game, "2802_02_battle_continue_arrow.png")
      break
    end
    step()
  end
  S.check(arrowShot and arrows > 0, "red continue arrow drawn on the battle message")

  local fadeShot, faded, sawHalf = false, false, false
  U.tap(game, "a")
  for _ = 1, 600 do
    if enemy.exiting then
      if enemy.alpha < 0.75 and enemy.alpha > 0.4 then
        sawHalf = true
        if not fadeShot then fadeShot = S.still(game, "2802_03_enemy_tray_fade_out.png") end
      end
      if not enemy.visible then faded = true break end
    elseif Message.isWaiting and Message.isWaiting() then
      U.tap(game, "a")
    end
    step()
  end
  S.check(sawHalf, "enemy tray fades with the alpha blend")
  S.check(faded, "enemy tray hidden after the fade")
  S.check(enemy.ox > 0, "enemy bar slides right while fading")

  Battle.abort("run")
  for _ = 1, 600 do
    if not Battle.isActive() then break end
    step()
  end
  Audio.playSe, Chrome.promptArrow = playSe, promptArrow
  S.finish()
end
