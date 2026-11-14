local U = require("tests.drivers.util")
local VERSION = os.getenv("POKEPORT_VERSION") or "emerald"
local DIR = os.getenv("POKEPORT_SHOT_DIR")
  or (".bazinga/BSA/11-11-26-00-standard/shots/game3_clockwise_wipe_3127_" .. VERSION)

local SCENE = {
  emerald = { map = "MAP_RUSTURF_TUNNEL", x = 6, y = 10, lead = "SPECIES_MUDKIP", foe = "SPECIES_WHISMUR" },
  ruby = { map = "MAP_RUSTURF_TUNNEL", x = 6, y = 10, lead = "SPECIES_MUDKIP", foe = "SPECIES_WHISMUR" },
  sapphire = { map = "MAP_RUSTURF_TUNNEL", x = 6, y = 10, lead = "SPECIES_MUDKIP", foe = "SPECIES_WHISMUR" },
  firered = { map = "MAP_MT_MOON_1F", x = 20, y = 26, lead = "SPECIES_CHARMANDER", foe = "SPECIES_ZUBAT" },
  leafgreen = { map = "MAP_MT_MOON_1F", x = 20, y = 26, lead = "SPECIES_CHARMANDER", foe = "SPECIES_ZUBAT" },
}

local function loadPng(path)
  local f = path and io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return love.image.newImageData(love.filesystem.newFileData(s, "x.png"))
end

local function topLeftBlack(img)
  if not img then return -1 end
  local w, h = img:getWidth(), img:getHeight()
  local n, k = 0, 0
  for y = 0, math.floor(h / 2) - 1, 3 do
    for x = 0, math.floor(w / 2) - 1, 3 do
      local r, g, b = img:getPixel(x, y)
      n = n + 1
      if r + g + b < 0.03 then k = k + 1 end
    end
  end
  return n > 0 and k / n or 0
end

local function topLeftCovered(BT)
  local n = 0
  for y = 0, 79 do
    local s = BT.blackSpans(y)
    for i = 1, #s, 2 do n = n + math.max(0, math.min(120, s[i + 1]) - math.max(0, s[i])) end
  end
  return n / (120 * 80)
end

return function(game)
  local fails = 0
  local function result(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then fails = fails + 1 end
  end
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "NICK", gender = 0 })
  U.wait(240)
  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local BT = require("src.core.game3.battle_transition")
  local Map = require("src.core.game3.map")
  local MapIds = require("src.core.game3.map_ids")
  local C = require("src.core.game3.constants").of(VERSION)
  local session = Runtime.getSession()
  local Ids = BT.ids()
  local sc = SCENE[VERSION] or SCENE.emerald

  local mapId = MapIds.forConst(sc.map, VERSION)
  local ok, err = pcall(function() Map.load(nil, game, mapId, { x = sc.x, y = sc.y, facing = "down" }) end)
  result(ok and mapId ~= nil, "loaded " .. sc.map .. " " .. tostring(err or ""))
  U.wait(240)
  session.party = {}
  Party.giveMon(session, C.species.byName[sc.lead], 20, "LEAD")

  local function run(shoot)
    BattleBridge.startWild(Runtime._mod, game, { species = C.species.byName[sc.foe], level = 5 }, {})
    local picked = BT._transitionId
    local frames, mainAt = 0, nil
    local rec = {}
    while frames < 900 do
      U.wait(1)
      frames = frames + 1
      if BT._phase == "main" and not mainAt then mainAt = frames end
      local fx = BT._fx
      if mainAt and BT._phase == "main" and fx then
        local m = frames - mainAt
        local r = { m = m, s = fx.state, cov = BT.screenCoverage(), tl = topLeftCovered(BT) }
        rec[#rec + 1] = r
        if shoot and shoot[m] then
          r.shot = string.format("%s/%s", DIR, shoot[m])
          U.still(game, r.shot)
        end
      end
      if not BT.isActive() or Battle.isActive() then break end
    end
    Battle.abort("run")
    for _ = 1, 600 do
      if not Battle.isActive() then break end
      U.wait(1)
    end
    U.wait(60)
    return picked, rec
  end

  local picked, rec = run(nil)
  result(picked == Ids.ID.CLOCKWISE_WIPE, "cave wild battle picks CLOCKWISE_WIPE (got " .. tostring(picked) .. ")")

  local byState = {}
  local halfRow = 120 / (240 * 160)
  local maxDrop, prev = 0, nil
  for _, r in ipairs(rec) do
    local b = byState[r.s]
    if not b then
      b = { first = r, last = r, frames = 0 }
      byState[r.s] = b
    end
    b.last = r
    b.frames = b.frames + 1
    if prev and prev.cov - r.cov > maxDrop then maxDrop = prev.cov - r.cov end
    prev = r
  end
  for s = 1, 5 do
    local b = byState[s]
    result(b ~= nil and b.last.cov > b.first.cov, string.format("state %d coverage grows %.3f -> %.3f over %d frames",
      s, b and b.first.cov or -1, b and b.last.cov or -1, b and b.frames or 0))
  end
  result(maxDrop <= halfRow + 1e-9, string.format("coverage never drops past the one-row seam (max drop %.4f)", maxDrop))
  local s5 = byState[5]
  result(s5 ~= nil and s5.last.cov > 0.95, string.format("coverage %.3f on the last TopLeft frame",
    s5 and s5.last.cov or -1))
  result(s5 ~= nil and s5.last.tl > 0.9, string.format("top-left quarter %.3f covered on the last TopLeft frame",
    s5 and s5.last.tl or -1))

  local shoot = {}
  local upper4, mid5, last5
  for _, r in ipairs(rec) do
    if r.s == 4 and r.tl > 0.1 and not upper4 then upper4 = r end
    if r.s == 5 then
      last5 = r
      if not mid5 and s5 and r.m >= s5.first.m + math.floor(s5.frames / 2) then mid5 = r end
    end
  end
  if upper4 then shoot[upper4.m] = "3127_01_left_hand_enters_top_left.png" end
  if mid5 then shoot[mid5.m] = "3127_02_top_left_half_swept.png" end
  if last5 then shoot[last5.m] = "3127_03_top_left_nearly_closed.png" end

  local _, rec2 = run(shoot)
  local share = {}
  for _, r in ipairs(rec2) do
    if r.shot then
      share[r.shot] = topLeftBlack(loadPng(r.shot))
      print(string.format("[3127] %s main+%d state %d coverage %.3f top-left png black %.2f",
        r.shot, r.m, r.s, r.cov, share[r.shot]))
    end
  end
  local p1 = DIR .. "/3127_01_left_hand_enters_top_left.png"
  local p2 = DIR .. "/3127_02_top_left_half_swept.png"
  local p3 = DIR .. "/3127_03_top_left_nearly_closed.png"
  result((share[p1] or -1) > 0.02, string.format("png top-left already darkening as Left crosses the top half (%.2f)",
    share[p1] or -1))
  result((share[p2] or -1) > (share[p1] or 2), "png top-left share grows into TopLeft")
  result((share[p3] or -1) > 0.8, string.format("png top-left quarter mostly black on the last TopLeft frame (%.2f)",
    share[p3] or -1))
  love.event.quit(fails == 0 and 0 or 1)
end
