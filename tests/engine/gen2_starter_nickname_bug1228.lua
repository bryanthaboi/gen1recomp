-- #1228: `givepoke` with the 3-argument (untrained) form must run
-- GiveANickname_YesNo, the same as a wild catch does.
-- engine/pokemon/move_mon.asm:1632-1645, 1753-1757, 1787
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")

local Vm = require("src.script.gen2.Vm")
local Events = require("src.world.gen2.Events")

-- Elm's `givepoke CYNDAQUIL, 5, BERRY` shape: no trainer operand, so
-- Vm.lua's arg4 fallback reads it as 0 (untrained).
local scripts = {
  generation = 2,
  ["s:give"] = {
    { op = "givepoke", species = 155, level = 5, item = 0, trainer = 0 },
    { op = "end" },
  },
}

local mon = { species = 155, level = 5 }
local renamed
local vm = Vm.new(scripts, {}, Events.new(), {
  givePoke = function() return mon end,
  yesorno = function(onChoose) onChoose(true) end,
  showText = function(_, onDone) onDone() end,
  specials = {
    data = function() return { text = require("tests.fixtures.gen2_rom_text").text() } end,
    monName = function(species) return species == 155 and "CYNDAQUIL" or "?" end,
    renameMon = function(m, done, opts)
      renamed = { mon = m, blank = opts and opts.blank }
      done("SPARKY")
    end,
  },
})

T.check(vm:start("s:give"), "starter script starts")
for _ = 1, 10 do vm:update() end
T.check(not vm:running(), "script finished")
T.eq(mon.nickname, "SPARKY",
  "givepoke with trainer=0 runs the nickname prompt and stores the answer")
T.check(renamed ~= nil and renamed.mon == mon,
  "renameMon opened on the mon givepoke just handed over")
T.check(renamed.blank == true,
  "the keyboard opens blank, same as InitNickname on a fresh catch")

-- The trade-gift form (trainer ~= 0, e.g. GiftSpearowName's 8-byte
-- Route35GoldenrodGate.asm:30 shape) must never open the keyboard.
local mon2 = { species = 155, level = 5 }
local renamed2 = false
local scripts2 = {
  generation = 2,
  ["s:give2"] = {
    { op = "givepoke", species = 155, level = 5, item = 0, trainer = 1 },
    { op = "end" },
  },
}
local vm2 = Vm.new(scripts2, {}, Events.new(), {
  givePoke = function() return mon2 end,
  yesorno = function() error("a trainer-labelled gift must never prompt") end,
  showText = function(_, onDone) onDone() end,
  specials = { renameMon = function() renamed2 = true end,
    data = function() return { text = require("tests.fixtures.gen2_rom_text").text() } end,
  },
})
T.check(vm2:start("s:give2"), "trainer-gift script starts")
for _ = 1, 10 do vm2:update() end
T.check(mon2.nickname == nil, "trainer arm leaves the nickname untouched")
T.check(not renamed2, "and never opens the keyboard")

-- A NO answer, and an all-spaces keyboard entry, both leave the species
-- name standing (_InitString's blank test, home/string.asm:6-30).
local mon3 = { species = 155, level = 5 }
local scripts3 = {
  generation = 2,
  ["s:give3"] = {
    { op = "givepoke", species = 155, level = 5, item = 0, trainer = 0 },
    { op = "end" },
  },
}
local vm3 = Vm.new(scripts3, {}, Events.new(), {
  givePoke = function() return mon3 end,
  yesorno = function(onChoose) onChoose(false) end,
  showText = function(_, onDone) onDone() end,
  specials = {
    data = function() return { text = require("tests.fixtures.gen2_rom_text").text() } end,
    renameMon = function() error("NO must not open the keyboard") end,
  },
})
T.check(vm3:start("s:give3"), "NO-answer script starts")
for _ = 1, 10 do vm3:update() end
T.check(mon3.nickname == nil, "answering NO leaves the nickname unset")

T.finish("gen2_starter_nickname_bug1228")
