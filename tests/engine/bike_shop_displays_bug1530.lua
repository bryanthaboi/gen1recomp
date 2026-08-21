-- The bike shop's "A shiny new BICYCLE!" is six hidden_event rows, not a
-- bg_event: data/events/hidden_events.asm:542-549 points every one of them
-- at PrintNewBikeText (engine/events/hidden_events/new_bike.asm:1), which
-- tx_pre_jumps NewBicycleText with ANY_FACING and no gating.  The port's
-- field extractor lifts none of that family, so BIKE_SHOP had no display
-- text at all (#1530).
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

local pushed
package.loaded["src.render.TextBox"] = {
  new = function(_, text, onDone) return { text = text, onDone = onDone } end,
}

local scripts = require("data.scripts.flavor.bike_shop")
local onInteract = scripts.BIKE_SHOP.onInteract
T.check(type(onInteract) == "function", "BIKE_SHOP carries an onInteract hook")

local game = {
  data = { text = { _NewBicycleText = "A shiny new\nBICYCLE!" } },
  stack = { push = function(_, box) pushed = box end },
}

-- data/events/hidden_events.asm:543-548 (the macro emits y then x, so the
-- source pairs read x, y)
for _, cell in ipairs({ { 1, 0 }, { 2, 1 }, { 1, 2 }, { 3, 2 }, { 0, 4 }, { 1, 5 } }) do
  pushed = nil
  local consumed = onInteract(game, {}, cell[1], cell[2])
  T.eq(consumed, true, ("(%d,%d) is a display tile"):format(cell[1], cell[2]))
  T.check(pushed ~= nil and pushed.text == game.data.text._NewBicycleText,
    ("(%d,%d) prints _NewBicycleText"):format(cell[1], cell[2]))
end

-- data/generated/maps.lua BIKE_SHOP object_events sit at (6,2), (5,6) and
-- (1,3): none of the six, so the hook never steals an NPC's talk
for _, cell in ipairs({ { 4, 4 }, { 6, 2 }, { 5, 6 }, { 1, 3 }, { 0, 0 } }) do
  pushed = nil
  local consumed = onInteract(game, {}, cell[1], cell[2])
  T.eq(consumed, false, ("(%d,%d) is not a display tile"):format(cell[1], cell[2]))
  T.eq(pushed, nil, "and pushes nothing")
end

-- with no cache text the hook still prints the line
pushed = nil
onInteract({ data = {}, stack = game.stack }, {}, 1, 0)
T.check(pushed ~= nil and pushed.text:find("BICYCLE", 1, true) ~= nil,
  "a dataset without the label falls back to the engine wording")

T.finish("bike shop display text (#1530)")
