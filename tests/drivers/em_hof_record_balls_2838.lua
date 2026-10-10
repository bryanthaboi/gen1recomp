-- pokeemerald/src/field_effect.c:1066 FldEff_HallOfFameRecord
-- pokeemerald/src/field_effect.c:597 sPokeballCoordOffsets
local U = require("tests.drivers.util")
local F = require("tests.drivers.em_fa_util")
local ST = require("tests.drivers.em_story_util")
local S = F.new("em_hof_record_balls_2838", os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_hof_record_balls_2838")

local EXPECT = { { 117, 52 }, { 123, 52 }, { 117, 56 }, { 123, 56 }, { 117, 60 }, { 123, 60 } }

return function(game)
  if not F.boot(game, S) then return S.finish() end
  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Message = require("src.ui.game3.message")
  local Misc = require("src.core.game3.fldeff_misc")
  local Rse = require("src.core.game3.field_effects_rse")
  local session = Runtime.getSession()
  if not S.check(session.version == "emerald", "driver runs Emerald") then return S.finish() end

  for _, sp in ipairs({ "SPECIES_SCEPTILE", "SPECIES_BLAZIKEN", "SPECIES_SWAMPERT",
      "SPECIES_GARDEVOIR", "SPECIES_AGGRON", "SPECIES_SALAMENCE" }) do
    ST.giveMon(sp, 50)
  end
  local n = 0
  for _, m in pairs(session.party or {}) do if m then n = n + 1 end end
  S.check(n == 6, "party of six (" .. n .. ")")

  F.settle(game, 300)
  local ok, err = pcall(function()
    Map.load(nil, game, "EM_EVER_GRANDE_CITY_HALL_OF_FAME", { x = 7, y = 16, facing = "up" })
  end)
  if not ok then S.note("Map.load error: " .. tostring(err)) end
  session = Runtime.getSession()
  S.check(ok and session.map == "EM_EVER_GRANDE_CITY_HALL_OF_FAME", "warped into the Hall of Fame")

  local started
  for _ = 1, 3000 do
    if Misc._active and Misc._active.FLDEFF_HALL_OF_FAME_RECORD then started = true break end
    if Message.isOpen and Message.isOpen() then U.tap(game, "a") end
    U.wait(1)
  end
  if not S.check(started == true, "FLDEFF_HALL_OF_FAME_RECORD started from the map script") then return S.finish() end
  S.check(Player.cellX == 7 and Player.cellY == 5 and Player.facing == "up",
    ("player in front of the machine at (%s,%s) facing %s"):format(tostring(Player.cellX),
      tostring(Player.cellY), tostring(Player.facing)))

  local function balls()
    local out = {}
    for _, e in ipairs(Rse._list) do
      if e.name == "pokeball_glow" then out[#out + 1] = e end
    end
    return out
  end
  U.wait(8)
  S.still(game, "2838_01_first_ball.png")
  for _ = 1, 200 do
    if #balls() >= 6 then break end
    U.wait(1)
  end
  U.wait(4)
  local list = balls()
  S.check(#list == 6, "six glow balls placed (" .. #list .. ")")
  S.still(game, "2838_02_six_balls_on_machine.png")

  local ox, oy = Player.px - 112, Player.py - 72
  for i, want in ipairs(EXPECT) do
    local e = list[i]
    local sx, sy = e and (e.x - ox), e and (e.y - oy)
    S.check(e ~= nil and sx == want[1] and sy == want[2],
      ("ball %d screen center (%s,%s) == pret (%d,%d)"):format(i, tostring(sx), tostring(sy), want[1], want[2]))
    if e then
      local tl = math.floor(e.x - e.sheet.fw / 2) - ox
      local tt = math.floor(e.y - e.sheet.fh / 2) - oy
      S.check(tl == want[1] - 4 and tt == want[2] - 4,
        ("ball %d OAM top-left (%d,%d) == (%d,%d)"):format(i, tl, tt, want[1] - 4, want[2] - 4))
    end
  end

  for _ = 1, 200 do
    if not (Misc._active and Misc._active.FLDEFF_HALL_OF_FAME_RECORD) then break end
    U.wait(1)
  end
  S.check(not (Misc._active and Misc._active.FLDEFF_HALL_OF_FAME_RECORD), "record effect ends")
  return S.finish()
end
