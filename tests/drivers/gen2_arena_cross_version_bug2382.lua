return function(game)
  local U = dofile("tests/drivers/util.lua")
  local ArenaData = require("src.online.ArenaData")
  local OnlinePanel = require("src.import.OnlinePanel")
  local Protocol2 = require("src.online.Protocol2")
  local Trade = require("src.online.Trade")
  local Wire = require("src.link.Wire")
  local RomImporter = require("src.import.RomImporter")

  local failed = false
  local function expect(cond, label, why)
    if cond then
      print("PASS " .. label)
    else
      failed = true
      print("FAIL " .. label .. (why and (": " .. tostring(why)) or ""))
    end
  end

  U.wait(30)

  local running = os.getenv("POKEPORT_VERSION") or "crystal"
  local order = {}
  for _, v in ipairs({ "gold", "silver", "crystal" }) do
    if v ~= running and RomImporter.isReady(v) then order[#order + 1] = v end
  end
  order[#order + 1] = running

  Trade.hostIsLive = function() return false end
  ArenaData.forget()

  local profiles = {}
  for _, v in ipairs(order) do
    local profile, reason = ArenaData.profile(v, "vanilla", nil, { partySize = 3 })
    expect(profile ~= nil, "2382_profile_" .. v, reason)
    if profile then
      profiles[v] = profile
      print(("[driver] %s fingerprint %s engineVersion %s"):format(
        v, tostring(profile.fingerprint), tostring(profile.engineVersion)))
    end
  end
  require("src.import.CacheFs").mountVersion(running)

  local crystal, gold, silver = profiles.crystal, profiles.gold, profiles.silver
  expect(crystal and gold, "2382_both_imported",
    "the identity needs gold and crystal caches")
  if crystal and gold then
    expect(crystal.fingerprint == gold.fingerprint, "2382_gold_crystal_same_fingerprint",
      tostring(gold.fingerprint) .. " vs " .. tostring(crystal.fingerprint))
    local room = { profile = crystal }
    expect(OnlinePanel.joinReason(room, gold) == nil,
      "2382_gold_can_join_crystal_room", OnlinePanel.joinReason(room, gold))
    expect(OnlinePanel.joinReason({ profile = gold }, crystal) == nil,
      "2382_crystal_can_join_gold_room",
      OnlinePanel.joinReason({ profile = gold }, crystal))
  end
  if silver and crystal then
    expect(silver.fingerprint == crystal.fingerprint, "2382_silver_crystal_same_fingerprint",
      tostring(silver.fingerprint) .. " vs " .. tostring(crystal.fingerprint))
  end

  local detail = "dataset fingerprint differs: the room has 6f577c0127a1e94d, "
    .. "you have c444a8971640c763"
  local msg = Wire.sanitize({ type = "join_error", reason = "profile_mismatch",
    field = "fingerprint", detail = detail })
  local text = Protocol2.joinErrorText(msg)
  print("[driver] join_error text: " .. tostring(text))
  expect(text:find("you have c444a8971640c763", 1, true) ~= nil,
    "2382_join_error_detail_whole")

  love.event.quit(failed and 1 or 0)
end
