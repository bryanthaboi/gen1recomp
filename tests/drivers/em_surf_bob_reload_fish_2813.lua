local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_surf_bob_reload_fish_2813"

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " em_surf_bob_reload_fish_2813 failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not check(game.boot ~= nil, "boot reached") then return finish() end
  game:_handleBootAction({ action = "new_game", name = "BRENDAN", gender = 0 })
  U.wait(60)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Field = require("src.core.game3.field")
  local Party = require("src.core.game3.party")
  local Battle = require("src.core.game3.battle")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Message = require("src.ui.game3.message")
  local FieldEffects = require("src.core.game3.field_effects")
  local C = require("src.core.game3.constants").of("emerald")
  local session = Runtime.getSession()
  if not check(session ~= nil, "field session exists") then return finish() end

  session.party = {}
  Party.giveMon(session, C.species.byName.SPECIES_WAILMER, 40, "WAILMER")

  local function place(x, y, facing)
    Map.load(nil, game, "EM_ROUTE124", { x = x, y = y, facing = facing })
    local s = Runtime.getSession()
    s.x, s.y, s.facing = x, y, facing
    Player.surfing = true
    Field.unlock()
  end
  local function timer()
    local b = FieldEffects._surfBob
    return b and b.timer or -1
  end

  place(10, 3, "down")
  U.wait(70)
  local before = timer()
  place(10, 3, "down")
  U.wait(10)
  local after = timer()
  print(string.format("[driver] blob timer before reload %d, 10 frames after %d", before, after))
  check(before > 60 and after >= 0 and after <= 11, "a warp load starts a fresh surf blob")

  U.wait(50)
  before = timer()
  local ok, err = BattleBridge.startWild(Runtime._mod, game,
    { species = C.species.byName.SPECIES_TENTACOOL, level = 5 }, {})
  check(ok == true, "wild battle started " .. tostring(err or ""))
  for _ = 1, 600 do
    if Battle.isActive() then break end
    U.wait(1)
  end
  U.wait(30)
  Battle.abort("run")
  local returned
  for i = 1, 900 do
    if not Battle.isActive() then returned = i break end
    U.wait(1)
  end
  U.wait(10)
  after = timer()
  print(string.format("[driver] blob timer before battle %d, 10 frames after return %d", before, after))
  check(returned ~= nil and Player.surfing, "back on the water after the battle")
  check(after >= 0 and after <= 11, "returning from battle starts a fresh surf blob")

  for _ = 1, 60 do
    if not (Message.isOpen and Message.isOpen()) then break end
    U.tap(game, "a")
    U.wait(3)
  end
  place(10, 3, "down")
  U.wait(40)
  check(Field.startFishing(1), "fishing starts while surfing")
  local synced, offsets, blobYs, shot = true, {}, {}, false
  for _ = 1, 90 do
    U.wait(1)
    local _, _, fy = Field.fishingPose()
    local blob = FieldEffects.surfBlobY2()
    offsets[fy or 0] = true
    blobYs[blob] = true
    if (Player.spriteYOffset or 0) ~= blob then synced = false end
    if fy and fy ~= 0 and not shot then
      shot = true
      U.still(game, DIR .. "/2813_07_fishing_on_water.png")
    end
  end
  local nBlob = 0
  for _ in pairs(blobYs) do nBlob = nBlob + 1 end
  check(nBlob > 1, "surf blob keeps bobbing while the rod is out")
  check(offsets[8] or offsets[-8], "the rod pose offset fired during the cast")
  check(synced, "player y2 is the rod offset plus the blob y2 every frame")
  finish()
end
