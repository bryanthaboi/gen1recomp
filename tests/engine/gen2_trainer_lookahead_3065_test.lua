package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

love = require("tests.love_stub")
local Vm = require("src.script.gen2.Vm")
local Events = require("src.world.gen2.Events")

local function vmWith(scripts, hints, texts)
  scripts.generation = 2
  return Vm.new(scripts, { ["t:intro"] = "Intro." }, Events.new(), {
    prepareTrainer = function(class, member)
      hints[#hints + 1] = class == nil and "wild" or (class .. "/" .. member)
    end,
    showText = function(body, onDone)
      texts[#texts + 1] = { body = body, hints = #hints }
      onDone()
    end,
  })
end

-- pokecrystal/maps/VioletGym.asm:12
do
  local hints, texts = {}, {}
  local vm = vmWith({
    ["s:falkner"] = {
      { op = "opentext" },
      { op = "setval", args = { 1 } },
      { op = "iftrue", script = "s:done" },
      { op = "writetext", text = "t:intro" },
      { op = "waitbutton" },
      { op = "closetext" },
      { op = "loadtrainer", class = 1, member = 1 },
      { op = "startbattle" },
    },
    ["s:done"] = { { op = "writetext", text = "t:intro" }, { op = "end" } },
  }, hints, texts)
  check(vm:start("s:falkner"), "the gym leader script starts")
  eq(hints[1], "1/1", "the leader's loadtrainer is hinted when the list is entered")
  for _ = 1, 40 do vm:update() end
  check(not vm:running(), "the beaten-leader branch runs to its end")
  eq(texts[1] and texts[1].hints, 1, "the hint lands before the first text box")
  eq(hints[2], "wild", "a run that never battled hands the park back")
  eq(#hints, 2, "and hints nothing else")
end

do
  local hints = {}
  local vm = vmWith({
    ["s:sign"] = {
      { op = "opentext" },
      { op = "writetext", text = "t:intro" },
      { op = "end" },
      { op = "loadtrainer", class = 1, member = 1 },
    },
  }, hints, {})
  vm:start("s:sign")
  for _ = 1, 40 do vm:update() end
  eq(#hints, 0, "a loadtrainer past the list's end is never hinted")
end

do
  local hints = {}
  local vm = vmWith({
    ["s:route"] = {
      { op = "setval", args = { 0 } },
      { op = "scall", script = "s:inner" },
      { op = "end" },
    },
    ["s:inner"] = {
      { op = "loadtrainer", class = 9, member = 3 },
      { op = "end" },
    },
  }, hints, {})
  vm:start("s:route")
  for _ = 1, 40 do vm:update() end
  eq(hints[1], "9/3", "a called list's loadtrainer is hinted on entry")
  eq(hints[2], "wild", "and withdrawn when the run ends without a battle")
end

do
  local hints = {}
  local vm = vmWith({
    ["s:callback"] = {
      { op = "loadtrainer", class = 4, member = 2 },
      { op = "end" },
    },
  }, hints, {})
  check(vm:runCallback("s:callback"), "the map callback runs to its end")
  eq(#hints, 0, "a map callback's loadtrainer is never hinted")
  check(not vm.trainerHinted, "and leaves no hint behind")
end

do
  local hints, texts = {}, {}
  local vm = vmWith({
    ["s:talk"] = {
      { op = "opentext" },
      { op = "writetext", text = "t:intro" },
      { op = "waitbutton" },
      { op = "closetext" },
      { op = "end" },
    },
    ["s:callback"] = {
      { op = "loadtrainer", class = 4, member = 2 },
      { op = "end" },
    },
  }, hints, texts)
  vm:start("s:talk")
  vm:runCallback("s:callback")
  for _ = 1, 40 do vm:update() end
  eq(#hints, 0, "a callback nested in a running script hints nothing for it")
end

T.finish("gen2 trainer look-ahead")
