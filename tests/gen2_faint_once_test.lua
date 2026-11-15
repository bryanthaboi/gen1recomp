-- A faint is announced once, and charged to happiness once.
--
--   luajit tests/gen2_faint_once_test.lua
--
-- Found by the Gold route bot (tests/drivers/gold_bot.lua), whose logs are full
-- of this:
--
--   TYPHLOSION fainted!
--   TYPHLOSION fainted!
--   TYPHLOSION fainted!
--
-- Battle:resolveFaints' player arm is the only one that returns WITHOUT
-- changing whose turn it is: it emits `choose-switch` and waits for the caller
-- to pick a replacement, so the caller calls back in with the same mon still at
-- 0 HP and the whole arm ran again. The repeated line is cosmetic; the bug
-- underneath it is not, because `faintHappiness` sat on the same path and was
-- charged once per re-entry. A single faint cost two or three times the
-- happiness the cart takes -- engine/battle/core.asm runs its happiness arm
-- once per faint.
--
-- The enemy arm cannot do this: it either ends the battle or switches in the
-- next mon, so it never re-enters holding a fainted enemy.
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 faint once")
local check, eq = S.check, S.eq

local Battle = require("src.battle.gen2.Battle")

-- resolveFaints' player arm reads self.player/self.party/self.enemy and calls
-- out to emit, faintHappiness and firstHealthy, so it runs against a stub.
local function stub(party)
  local st = {
    said = {},
    happiness = 0,
    data = { text = require("tests.fixture_data.gen2_rom_text_s7_a").text() },
  }
  st.player = party[1]
  st.party = party
  st.enemy = { hp = 50, level = 50 }
  st.emit = function(_, ev) st.said[#st.said + 1] = ev.kind end
  st.faintHappiness = function() st.happiness = st.happiness + 1 end
  st.monName = function(_, m) return m.name or "MON" end
  return setmetatable(st, { __index = Battle })
end

local function countKind(said, kind)
  local n = 0
  for _, k in ipairs(said) do if k == kind then n = n + 1 end end
  return n
end

local function countFaints(said)
  return countKind(said, "faint")
end

-- The reported case: a fainted lead with a healthy mon behind it. The caller
-- drives the switch, so it calls resolveFaints repeatedly in the meantime.
do
  local b = stub({
    { hp = 0, level = 88, name = "TYPHLOSION" },
    { hp = 40, level = 30, name = "SLOWPOKE" },
  })
  eq(b:resolveFaints(), false, "the battle is not over, there is a mon left")
  eq(b:resolveFaints(), false, "and calling again while the switch is pending")
  eq(b:resolveFaints(), false, "and again")
  eq(countFaints(b.said), 1, "the faint is announced exactly once")
  eq(b.happiness, 1, "and happiness is charged exactly once")
  -- HandlePlayerMonFaint runs ForcePlayerMonChoice once (core.asm:2543) and
  -- the turn loop never comes back for a second answer.  Three prompts in the
  -- queue reopened the party list on top of the pick that had already been
  -- made, which is why the switch looked like it took several attempts.
  eq(countKind(b.said, "choose-switch"), 1, "and the party list is asked for "
    .. "exactly once")
end

-- The replacement announces its own faint normally: the guard is keyed on the
-- mon, not on the battle.
do
  local slowpoke = { hp = 40, level = 30, name = "SLOWPOKE" }
  local b = stub({ { hp = 0, level = 88, name = "TYPHLOSION" }, slowpoke })
  b:resolveFaints()
  b:resolveFaints()
  -- Battle:switch is what clears the guards; do what it does.
  b.faintAnnounced = nil
  b.pendingSwitch = nil
  b.player = slowpoke
  slowpoke.hp = 0
  eq(b:resolveFaints(), true, "no healthy mon left ends the battle")
  eq(countFaints(b.said), 2, "the second mon's faint is announced too")
  eq(b.happiness, 2, "and charged")
end

-- A wipe still reports the wipe, once.
do
  local b = stub({ { hp = 0, level = 88, name = "TYPHLOSION" } })
  eq(b:resolveFaints(), true, "a lone fainted mon ends the battle")
  eq(b.outcome, "lose", "as a loss")
  eq(countFaints(b.said), 1, "announced once")
end

S.finish()
