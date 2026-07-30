-- Parity test: the Silph Co 2F worker begs before she hands over TM36.
--
-- scripts/SilphCo2F.asm SilphCo2FSilphWorkerFText prints .PleaseTakeThisText
-- (text/SilphCo2F.asm:1, "Eeek!" / "No! Stop! Help!" ... "please take this!")
-- and only then calls GiveItem, so the scared line always comes first and the
-- second visit never repeats it.  The port skipped it because that label
-- carries no leading underscore, so the manifest harvester dropped the string
-- and the gift() row had no `pre` to print (#393).
--
-- Self-contained; run via `luajit tests/parity_silph_tm36_pre.lua`, and also
-- dofile'd by tests/run_tests.lua's parity aggregator.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local Data = require("src.core.Data")
if not (Data.maps and Data.maps.SILPH_CO_2F) then Data:load() end
require("src.render.Font").load(Data)

local S = require("tests.harness").suite("parity silph tm36 pre text")
local check, eq = S.check, S.eq

local SaveData = require("src.core.SaveData")
local TextBox = require("src.render.TextBox")

local PRE = "SilphCo2FSilphWorkerFPleaseTakeThisText"
local pre = Data.text[PRE]
check(type(pre) == "string" and pre ~= "", PRE .. " is extracted")
if type(pre) == "string" then
  check(pre:find("Eeek!", 1, true) ~= nil, "it opens on \"Eeek!\"")
  check(pre:find("with TEAM ROCKET.", 1, true) ~= nil,
        "it works out the player is not a Rocket")
  check(pre:find("please take this!", 1, true) ~= nil,
        "it ends on \"please take this!\"")
end

local handler = require("data.scripts.story5")
  .SILPH_CO_2F.talk.TEXT_SILPHCO2F_SILPH_WORKER_F
check(type(handler) == "function", "SILPH_CO_2F wires the worker's talk entry")

local stack = {}
local game = {
  data = Data,
  save = SaveData.newGame(),
  stack = {
    push = function(_, state) stack[#stack + 1] = state end,
    pop = function() return table.remove(stack) end,
    top = function() return stack[#stack] end,
  },
}
game.save.player.name = "RED"

local function pages(box)
  local out = {}
  for _, page in ipairs(box.pages or {}) do
    for _, line in ipairs(page) do out[#out + 1] = line end
  end
  return table.concat(out, " / ")
end

-- runs one conversation to its end, returning the boxes in the order the
-- player reads them; `onBox` sees each box before its A press lands, which is
-- how the bag is inspected while the first box is still up
local function converse(onBox)
  stack = {}
  local read, done = {}, false
  handler(game, nil, nil, function() done = true end)
  for _ = 1, 8 do
    local box = stack[#stack]
    if not box then break end
    check(getmetatable(box) == TextBox, "the worker pushes a TextBox")
    read[#read + 1] = pages(box)
    if onBox then onBox(#read, box) end
    if done or not box.onDone then break end
    stack[#stack] = nil
    box.onDone()
  end
  check(done, "the conversation runs to its callback")
  return read
end

local function bagHasTm()
  return (game.save.inventory or {}).TM_SELFDESTRUCT ~= nil
end

local first = converse(function(n)
  if n == 1 then
    check(not bagHasTm(),
          "the TM is still hers while the first box is up")
    check(not game.save.flags.EVENT_GOT_TM36,
          "EVENT_GOT_TM36 is still unset while the first box is up")
  end
end)

check((first[1] or ""):find("Eeek!", 1, true) ~= nil,
      "the first box the player reads is the scared line")
local joined = table.concat(first, " | ")
check(joined:find("TM36", 1, true) ~= nil, "the run reaches the TM36 boxes")
check(joined:find("SELFDESTRUCT!", 1, true) ~= nil,
      "and the SELFDESTRUCT explanation")
check(bagHasTm(), "TM36 is in the bag afterwards")
check(game.save.flags.EVENT_GOT_TM36, "EVENT_GOT_TM36 is set afterwards")

-- second visit: SilphCo2F.asm jumps straight to the explanation
local again = converse()
eq(#again, 1, "talking again is one box")
check((again[1] or ""):find("SELFDESTRUCT!", 1, true) ~= nil,
      "and it is the TM36 explanation")
check((again[1] or ""):find("Eeek!", 1, true) == nil,
      "the scared line does not play twice")

S.finish()
