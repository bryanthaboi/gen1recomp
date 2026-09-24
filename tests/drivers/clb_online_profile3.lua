local U = require("tests.drivers.util")

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

return function(game)
  print("PASS driver_started")
  for _ = 1, 900 do
    if game.data and game.data.maps and (game.phase == "boot" or game.phase == "field") then break end
    U.wait(1)
  end
  result(game.data ~= nil, "game3 hydrated its dataset")

  local ArenaData = require("src.online.ArenaData")
  local Fingerprint = require("src.link.Fingerprint")
  local Handshake = require("src.link.Handshake")
  local Game3Link = require("src.link.Game3Link")
  local CacheFs = require("src.import.CacheFs")
  local GameVersion = require("src.core.GameVersion")

  local okI, inputs = pcall(Fingerprint.gen3Inputs, function(rel) return CacheFs.readActive(rel) end)
  result(okI, "gen3Inputs reads the mounted cache")
  local headless = okI and Fingerprint.compute({ generation = 3, gen3Inputs = inputs }, {}, 3) or nil
  local names = {}
  for _, m in ipairs(Handshake.mods(game)) do
    names[#names + 1] = ("%s(link=%s)"):format(tostring(m.id), tostring(m.affectsLink))
  end
  print("MODS " .. table.concat(names, ","))
  local live, why = ArenaData.liveProfile3(game, "g3_link")
  if Handshake.linkModified(game) then
    result(live == nil and why == "mods", "a link-modded game has no online profile (" .. tostring(why) .. ")")
  else
    result(live ~= nil, "liveProfile3 for the running game (" .. tostring(why) .. ")")
    result(live ~= nil and live.fingerprint == headless,
      "the live fingerprint equals the launcher's headless one")
  end
  local vanilla = ArenaData.liveProfile3({ data = game.data, save = game.save }, "g3_single")
  result(vanilla ~= nil and vanilla.fingerprint == headless and vanilla.engine == 3,
    "with mods off the live profile equals the launcher's")
  print(("FINGERPRINT %s %s"):format(GameVersion.get(), tostring(headless)))

  local hello = Game3Link.hello(game, Game3Link.LINKTYPE.TRADE)
  result(hello.generation == 3, "the Game3 hello is Gen 3")
  local handshake = Handshake.hello({ data = game.data, save = game.save, mods = game.mods })
  result(handshake.generation == 3, "Handshake reads the Game3 dataset as Gen 3")
  result(handshake.fingerprint == headless, "and hashes the Gen 3 surface")

  local Party = require("src.core.game3.party")
  local Protocol = require("src.link.Protocol")
  local Json = require("src.link.Json")
  local scratch = { party = {}, name = "RED", trainerId = 31337 }
  local bad = 0
  for _, species in ipairs({ 1, 25, 150, 201, 249, 303, 386, 410, 411 }) do
    local ok, _, mon = Party.giveMon(scratch, species, 50)
    scratch.party = {}
    local packed = ok and Protocol.packMon3(mon) or nil
    local back = packed and Protocol.unpackMon3(nil, Json.decode(Json.encode(packed)), { strict = true })
    if not (back and back.maxHp == mon.maxHp and back.attack == mon.attack) then bad = bad + 1 end
  end
  result(bad == 0, "live party mons round-trip through packMon3/unpackMon3 strictly")

  if failures == 0 then
    print("PASS clb_online_profile3")
    love.event.quit(0)
  else
    print("FAIL clb_online_profile3 failures=" .. failures)
    love.event.quit(1)
  end
end
