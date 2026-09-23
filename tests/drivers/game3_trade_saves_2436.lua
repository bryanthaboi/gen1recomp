local U = require("tests.drivers.util")

return function(game)
  local ok, err = xpcall(function()
    local GameVersion = require("src.core.GameVersion")
    local SaveData = require("src.core.SaveData")
    local version = GameVersion.get()
    assert(version == "firered" or version == "leafgreen", "gen3 only: " .. tostring(version))
    for _ = 1, 900 do
      if game.phase == "boot" and game.boot then break end
      U.wait(1)
    end
    local slot = "slot1"
    local found = false
    for _, row in ipairs(SaveData.listSlots(version)) do
      if row.id == slot then found = true end
    end
    if not found then slot = assert(SaveData.createSlot(version)) end
    SaveData.setActiveSlot(version, slot)
    game:_handleBootAction({ action = "new_game", name = version == "firered" and "RED" or "LEAF" })
    U.wait(240)
    local Runtime = require("src.core.game3.runtime")
    local Party = require("src.core.game3.party")
    local session = assert(Runtime.getSession())
    session.party = {}
    if version == "firered" then
      session.name = "RED"
      assert(Party.giveMon(session, 64, 30, "ABRA CAD"))
      assert(Party.giveMon(session, 25, 12))
      session.dex.nationalUnlocked = true
      session.national_dex_unlocked = true
    else
      session.name = "LEAF"
      assert(Party.giveMon(session, 95, 25))
      session.party[1].item, session.party[1].heldItem = 199, 199
      assert(Party.giveMon(session, 1, 8))
    end
    assert(game:saveGame())
    local path = SaveData.slotDiskPath(version, slot)
    print(("PASS 2436_%s_save %s %s"):format(version, tostring(slot), tostring(path)))
    for i, mon in ipairs(session.party) do
      print(("[2436] %s party %d species=%s lv=%s item=%s nick=%s"):format(version, i,
        tostring(mon.species), tostring(mon.level), tostring(mon.item), tostring(mon.nickname)))
    end
  end, debug.traceback)
  if not ok then
    print("FAIL 2436_save " .. tostring(err))
    love.event.quit(1)
    return
  end
  love.event.quit(0)
end
