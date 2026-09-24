return function(game)
  local U = dofile("tests/drivers/util.lua")
  for _ = 1, 900 do
    if game.data and game.data.maps then break end
    U.wait(1)
  end
  local SaveData = require("src.core.SaveData")
  local Party = require("src.core.game3.party")
  local Schema = require("src.core.game3.save_schema_firered")
  local failures = 0
  local function check(cond, msg)
    U.log(cond and "ok  " or "FAIL", msg)
    if not cond then failures = failures + 1 end
  end

  local function build(version, name, trainerId, mons)
    local session = Schema.newGame({ version = version, name = name, rngSeed = trainerId })
    session.trainerId = trainerId
    session.dex.nationalUnlocked = true
    session.party = {}
    for _, row in ipairs(mons) do assert(Party.giveMon(session, row[1], row[2])) end
    return SaveData.decode(SaveData.encode(Schema.toSaveTable(session)))
  end

  local function seed(version, name, trainerId, mons)
    for _, row in ipairs(SaveData.listSlots(version)) do
      if row.exists then
        check(true, version .. " already holds " .. row.id)
        return
      end
    end
    local id = SaveData.createSlot(version)
    local ok, err = SaveData.writeSlot(version, id, build(version, name, trainerId, mons))
    check(ok == true, ("%s %s written: %s"):format(version, tostring(id), tostring(err)))
    local rows = SaveData.listSlots(version)
    check(#rows > 0 and rows[1].exists, version .. " lists the new slot")
  end

  seed("firered", "RED", 31337,
    { { 6, 50 }, { 9, 50 }, { 3, 50 }, { 25, 40 }, { 65, 45 }, { 143, 48 } })
  seed("leafgreen", "LEAF", 22222, { { 94, 50 }, { 131, 50 }, { 59, 50 } })

  U.log(failures == 0 and "online final seed3 passed" or (failures .. " seed check(s) failed"))
  love.event.quit(failures == 0 and 0 or 1)
end
