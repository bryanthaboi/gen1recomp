package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")
local Profile = require("src.core.game3.profile")
local BT = require("src.core.game3.battle_transition")

local prev = GameVersion.get()
local DW, DH = 240, 160

local function whiteBars(version)
  Profile.reset()
  GameVersion.set(version)
  local Ids = BT.ids()
  return BT.defs()[Ids.ID.WHITE_BARS_FADE], Ids
end

local function litRows(def, Ids)
  local rows = {}
  local G = {
    setColor = function() end,
    rectangle = function(_, x, y, w, h)
      if h == 1 then rows[y] = { x = x, w = w } end
    end,
  }
  local R = {
    X0 = 0, X1 = DW, Y0 = 0, Y1 = DH,
    hmap = function(x) return x end, hmapL = function(x) return x end, hmapR = function(x) return x end,
    rowBands = function(level, fill)
      for y = 0, DH - 1 do
        local v = level(y)
        if v and v > 0 then rows[y] = { x = 0, w = DW } end
        fill(0, y, y + 1)
      end
    end,
  }
  local finished, lit, partial = false, 0, 0
  BT.start(Ids.ID.WHITE_BARS_FADE, { skipIntro = true }, function() finished = true end)
  for _ = 1, 400 do
    BT.tick(1 / 60)
    local fx = BT._fx
    if finished or not fx or fx.darkenPhase then break end
    if fx.buf1 then
      rows = {}
      def.post(fx, R, G)
      for y = 1, DH - 1 do
        local row = rows[y]
        if row then
          lit = lit + 1
          if row.x ~= 0 or row.w ~= DW then partial = partial + 1 end
        end
      end
    end
  end
  BT.abort()
  return lit, partial
end

local frlg = whiteBars("firered")
check(frlg ~= nil, "FireRed has a WHITE_BARS_FADE def")
eq(frlg and frlg.row0, "first", "FireRed WHITE_BARS_FADE row 0 reads the first entry")

local em, emIds = whiteBars("emerald")
check(em ~= nil and em ~= frlg, "Emerald registers its own WHITE_BARS_FADE")
eq(em and em.row0, "prev", "Emerald WHITE_BARS_FADE row 0 reads entry 227")
-- pokeemerald/src/battle_transition.c:3687
local emLit, emPartial = litRows(em, emIds)
check(emLit > 0 and emPartial > 0, "Emerald WHITE_BARS_FADE bars sweep in from the right (" .. emPartial .. " of " .. emLit .. " lit rows narrower)")

-- pokeruby/src/battle_transition.c:348
-- pokeruby/src/battle_transition.c:2058
for _, version in ipairs({ "ruby", "sapphire" }) do
  local rs, Ids = whiteBars(version)
  eq(Ids.GAME, version, version .. " resolves its own transition id table")
  check(rs ~= nil, version .. " has a WHITE_BARS_FADE def")
  check(rs ~= frlg, version .. " WHITE_BARS_FADE is not the FRLG def")
  eq(rs and rs.row0, "prev", version .. " WHITE_BARS_FADE row 0 reads entry 227 like Emerald")
  check(rs ~= em, version .. " WHITE_BARS_FADE is not the Emerald def")
  eq(rs and #rs.funcs, 5, version .. " WHITE_BARS_FADE runs five task funcs")
  -- pokeruby/src/battle_transition.c:2039
  local lit, partial = litRows(rs, Ids)
  check(lit > 0, version .. " WHITE_BARS_FADE lights rows")
  eq(partial, 0, version .. " WHITE_BARS_FADE lightens whole rows (window 0 is empty)")
end

Profile.reset()
GameVersion.set(prev)
T.finish("game3_rs_white_bars_transition")
