return function(game)
  local U = require("tests.drivers.util")
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  local SaveData = require("src.core.SaveData")
  local Schema = require("src.core.game3.save_schema_firered")
  local SaveConvert = require("src.save_convert.SaveConvert")
  local Importer = require("src.import.RomImporter")
  local E = require("src.save_convert.Gen3Save").forVersion("emerald")
  local failures = 0
  local function check(cond, msg)
    U.log((cond and "PASS " or "FAIL ") .. msg)
    if not cond then failures = failures + 1 end
    return cond
  end
  local function done()
    love.event.quit(failures == 0 and 0 or 1)
  end

  local heal = SaveConvert.gen3CacheTable("emerald", "region_map/heal_locations.lua")
  local rows = heal and heal.whiteout
  if not check(type(rows) == "table" and rows[22] ~= nil, "emerald cache has sHealLocations rows") then return done() end
  local imp = Importer.new(nil, { launcher = true })
  imp._inputBlocked = true

  for _, case in ipairs({ { id = 22, gender = 0, name = "BRENDAN" }, { id = 20, gender = 0, name = "BRENDAN" },
      { id = 2, gender = 1, name = "MAY" } }) do
    local row = rows[case.id]
    local session = Schema.newGame({ version = "emerald", name = case.name, gender = case.gender, rngSeed = 3080 + case.id })
    session.healMap, session.healX, session.healY = row.map, row.x, row.y
    local save = SaveData.decode(SaveData.encode(Schema.toSaveTable(session)))
    if type(save.modData) == "table" then save.modData.cartImage, save.modData.cartImport = nil, nil end
    local slot = assert(SaveData.createSlot("emerald"))
    assert(SaveData.writeSlot("emerald", slot, save))
    assert(SaveData.setActiveSlot("emerald", slot))
    imp.saveNotice.emerald = nil
    imp:exportSave("emerald")
    local notice = imp.saveNotice.emerald
    local tag = ("heal_%d_%s"):format(case.id, row.map)
    check(notice and notice.ok == true, tag .. " launcher export ok (" .. tostring(notice and notice.text) .. ")")
    local bytes = love.filesystem.read(("exports/emerald/gen1recomp-emerald-%s.sav"):format(slot))
    if check(type(bytes) == "string" and #bytes >= 131072, tag .. " export file written") then
      local c = E.decode(bytes)
      local h = c and c.lastHealLocation
      check(h and E.mapFor(h.group, h.num) == row.map and h.x == row.x and h.y == row.y and h.warpId == -1,
        tag .. " cart lastHealLocation is the sHealLocations row")
      local back = SaveConvert.importSav(bytes, "emerald", "emerald")
      local sess2 = back and Schema.fromSaveTable(back)
      check(sess2 and sess2.healMap == row.map and sess2.healX == row.x and sess2.healY == row.y,
        tag .. " re-import restores the respawn point")
    end
  end
  done()
end
