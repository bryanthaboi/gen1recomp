-- pokeemerald/src/battle_intro.c:113
-- pokeemerald/src/party_menu.c:3976
local U = require("tests.drivers.util")
local F = require("tests.drivers.em_fa_util")
local S = F.new("em_intro_window_party_msg_2789_2790", os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_2789_2790")

return function(game)
  if not F.boot(game, S) then return S.finish() end
  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local PartyMenu = require("src.ui.game3.party_menu")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local Anim = require("src.core.game3.battle.anim")
  local Trainers = require("src.core.game3.scripting.trainers")
  local C = require("src.core.game3.constants").of("emerald")
  local session = Runtime.getSession()
  F.noTrainerSight()

  S.check(F.goTo(game, "EM_LILYCOVE_CITY_POKEMON_CENTER_1F", 7, 4, "down"), "indoor map reached")
  session.party = {}
  Party.giveMon(session, C.species.byName.SPECIES_SWELLOW, 40, "SWELLOW")
  session.party[1].moves = { C.moves.byName.MOVE_FLY, C.moves.byName.MOVE_PECK }

  local function try_fly(tag)
    PartyMenu.show(session.party, nil, { session = session })
    U.wait(30)
    U.tap(game, "a")
    U.wait(10)
    local idx
    for i, a in ipairs(PartyMenu.ACTIONS) do if a == "FLY" then idx = i end end
    if not S.check(idx ~= nil, tag .. " FLY listed in the action menu") then return end
    PartyMenu.actionCursor = idx
    U.tap(game, "a")
    U.wait(30)
    S.check(PartyMenu.mode == "message", tag .. " message shown, mode=" .. tostring(PartyMenu.mode))
    S.note(tag .. " text=" .. tostring(PartyMenu._messageText) .. " std=" .. tostring(PartyMenu._messageStd))
    S.still(game, "2790_" .. tag .. ".png")
    local std = PartyMenu._messageStd
    U.tap(game, "a")
    U.wait(20)
    S.check(PartyMenu.mode == "list", tag .. " A returns to the mon list")
    PartyMenu.close()
    U.wait(20)
    return std
  end

  F.setFlag("FLAG_BADGE06_GET", true)
  local std = try_fly("01_cant_use_here")
  S.check(std == true, "Can't use that here uses the small std message window")
  F.setFlag("FLAG_BADGE06_GET", false)
  std = try_fly("02_badge_required")
  S.check(std == false, "badge message keeps the full message box")

  S.check(F.goTo(game, "EM_ROUTE117", 32, 15, "down"), "Route 117 reached")
  local calvin = C.trainers.byName.TRAINER_CALVIN_1
  local foe = Trainers.foeFromId(calvin)
  local ok = foe and BattleBridge.start(Runtime._mod, game, foe, { wild = false, trainerId = calvin })
  if not S.check(ok == true, "trainer battle started") then return S.finish() end
  for _ = 1, 3000 do
    if Battle.isActive() then break end
    U.wait(1)
  end
  S.check(Battle.isActive(), "battle active")
  local sawLine, sawBand, opened, shape = false, false, false, true
  local shotLine, shotBand, shotOpen = false, false, false
  for _ = 1, 400 do
    local w = Anim.stage() and Anim.stage().win0
    if w then
      if w[2] ~= 161 - w[1] and w[1] ~= w[2] then shape = false end
      if w[1] >= 70 and w[1] < w[2] then
        sawLine = true
        if not shotLine then shotLine = S.still(game, "2789_01_center_strip.png") end
      end
      if w[1] == 48 then
        sawBand = true
        if not shotBand then shotBand = S.still(game, "2789_02_band_48_113.png") end
      end
      if w[1] > 0 and w[1] < 40 and not shotOpen then shotOpen = S.still(game, "2789_03_opening.png") end
    elseif sawBand then
      opened = true
      break
    end
    U.wait(1)
  end
  S.check(sawLine, "intro opens from a strip around row 80")
  S.check(sawBand, "window holds rows 48..113 before the full open")
  S.check(shape, "window stays symmetric about the center line")
  S.check(opened, "window fully opens and clears")
  Battle.abort("run")
  for _ = 1, 600 do
    if not Battle.isActive() then break end
    U.wait(1)
  end
  S.finish()
end
