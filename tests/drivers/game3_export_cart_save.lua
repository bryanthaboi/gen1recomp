local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_export_cart_save"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end
local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " export_cart_save failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "PORT" })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Flags = require("src.core.game3.scripting.flags")
  local Space = require("src.core.game3.scripting.space")
  local GameVersion = require("src.core.GameVersion")
  local SaveFileIO = require("src.import.SaveFileIO")
  local SaveConvert = require("src.save_convert.SaveConvert")
  local Gen3Save = require("src.save_convert.Gen3Save")
  local L = require("src.save_convert.Gen3Layout")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the field") then return finish() end
  -- data/maps/PalletTown_ProfessorOaksLab/scripts.inc:1120
  Flags.setFlag(Space.store, nil, 0x828, true)
  local ok = Party.giveMon(session, 4, 5)
  result(ok and #session.party == 1, "a Charmander Lv5 joins the port party")
  local Mail = require("src.core.game3.mail")
  local mailId = Mail.giveMailToMon(session, session.party[1], 121)
  Mail.slot(session, mailId).words = { 2601, 4128, 526, 2611, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF }
  result(Mail.monHasMail(session.party[1]), "Charmander holds ORANGE MAIL with a letter")
  session.dex.nationalUnlocked = true

  Map.load(nil, game, "FR_PALLET_TOWN", { x = 12, y = 16, facing = "left" })
  session.x, session.y, session.facing = 12, 16, "left"
  Player.cellX, Player.cellY = 12, 16
  Player.px, Player.py = 12 * 16, 16 * 16
  Player.targetX, Player.targetY = 12, 16
  Player.facing = "left"
  U.wait(60)
  U.hold(game, "left", 34)
  U.wait(40)
  session = Runtime.getSession()
  print(string.format("walked to %s %s,%s", tostring(session.map), tostring(session.x), tostring(session.y)))
  result(session.map == "FR_PALLET_TOWN" and session.x < 12, "walked west through Pallet Town")
  U.still(game, DIR .. "/2444_port_slot_pallet.png")

  local saved = game:saveGame()
  result(saved ~= false, "the port slot saves")
  local version = GameVersion.get()
  local exOk, path = SaveFileIO.exportActiveSlot(version)
  if not result(exOk == true, "SaveFileIO exports the port slot (" .. tostring(path) .. ")") then return finish() end
  local f = io.open(path, "rb")
  local bytes = f and f:read("*a")
  if f then f:close() end
  if not result(type(bytes) == "string" and #bytes == L.FLASH_SIZE, "the export is a 128K flash image") then
    return finish()
  end
  local out = io.open(DIR .. "/2444_port_export_" .. version .. ".sav", "wb")
  if out then out:write(bytes); out:close() end

  local c, why = Gen3Save.decode(bytes)
  if not result(c ~= nil, "the export decodes as a valid FireRed/LeafGreen save" .. (c and "" or (" (" .. tostring(why) .. ")"))) then
    return finish()
  end
  result(c.frlgMarker == 1 and c.counter == 1, "FRLG marker and first save counter")
  result(c.specialSaveWarpFlags == L.CONTINUE_GAME_WARP, "continue-game warp flag set")
  local w = c.continueGameWarp
  result(w.group == 3 and w.num == 0 and w.x == session.x and w.y == session.y,
    ("continue warp is Pallet %d,%d (%d:%d %d,%d)"):format(session.x, session.y, w.group, w.num, w.x, w.y))
  result((c.mapLayoutId or 0) > 0, "map layout id " .. tostring(c.mapLayoutId))
  result(c.name == "PORT" and c.money == session.money, "player name and money")
  local p = c.party[1] or {}
  result(#c.party == 1 and p.species == 4 and p.level == 5 and p.checksumOk,
    ("party 1 is Charmander Lv5 (%s Lv%s)"):format(tostring(p.species), tostring(p.level)))
  result(p.hp == session.party[1].hp and p.maxHp == session.party[1].maxHp, "party HP matches the port")
  local fl = {}
  for _, id in ipairs(c.flags) do fl[id] = true end
  result(fl[0x828] == true, "FLAG_SYS_POKEMON_GET carried")
  result(c.dexOwned[1] == 3, "Charmander owned in the dex (national 4)")
  result(p.mail == mailId and c.mail[mailId + 1].itemId == 121 and c.mail[mailId + 1].words[1] == 2601,
    ("the letter exports at mail index %s"):format(tostring(p.mail)))
  result(c.dexNationalMagic == L.NATIONAL_DEX.magic and c.vars[L.NATIONAL_DEX.var] == L.NATIONAL_DEX.varValue,
    "the National Dex unlock exports the cart's magic and var")
  local back = SaveConvert.importSav(bytes, version, version)
  result(back and back.party[1].species == 4 and back.map == "FR_PALLET_TOWN" and back.x == session.x,
    "the export imports back to the same slot state")
  finish()
end
