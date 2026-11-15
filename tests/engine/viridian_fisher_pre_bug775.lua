-- Headless regression: the Viridian fisher's TM42 gift skipped his pre
-- text and jumped straight to "received TM42!" (#775).  pokered's
-- ViridianCityFisherText (scripts/ViridianCity.asm) prints
-- .YouCanHaveThisText before GiveItem.  ROM-free: the gift closure only
-- touches text/items/flags, so TextBox, Sound and Bag are stubbed and the
-- boxes are advanced by hand.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

-- story5's gift() requires these at call time, so preloading stubs is
-- enough; each tier suite is its own process, nothing leaks
local boxes = {}
package.loaded["src.render.TextBox"] = {
  new = function(_, s, done) return { text = s, onDone = done } end,
  soundOpts = function() return {} end,
}
package.loaded["src.core.Sound"] = { play = function() end }
package.loaded["src.inventory.Bag"] = {
  add = function(save, item, n)
    save.inventory[item] = (save.inventory[item] or 0) + n
    return true
  end,
}

local story5 = require("data.scripts.story5")
local fisher = story5.VIRIDIAN_CITY.talk.TEXT_VIRIDIANCITY_FISHER
T.check(type(fisher) == "function", "the fisher talk entry is a gift closure")

local function newGame(textTable)
  boxes = {}
  return {
    data = {
      text = textTable,
      items = { TM_DREAM_EATER = { name = "TM42" } },
    },
    save = {
      flags = {}, inventory = {}, player = { name = "RED" },
    },
    stack = {
      push = function(_, box) boxes[#boxes + 1] = box end,
    },
  }
end

local game = newGame({
  ViridianCityFisherYouCanHaveThisText = "PRE",
  _ViridianCityFisherReceivedTM42Text = "{PLAYER} received\n{RAM:}!",
})
local finished = false
fisher(game, nil, nil, function() finished = true end)

T.eq(#boxes, 1, "talking opens exactly one box before any A press")
T.eq(boxes[1].text, "PRE", "the first box is the fisher's pre text, not the receipt")
T.check(not game.save.flags.EVENT_GOT_TM42,
  "the flag stays unset until the pre text is dismissed")

boxes[1].onDone()
T.eq(#boxes, 2, "dismissing the pre text opens the received box")
T.eq(boxes[2].text, "RED received\nTM42!",
  "the received text is filled with player and item")
T.eq(game.save.inventory.TM_DREAM_EATER, 1, "TM42 reached the bag")
T.check(game.save.flags.EVENT_GOT_TM42 == true, "the event flag is set")
boxes[2].onDone()
T.eq(#boxes, 2, "no explanation box follows the receipt")
T.check(finished, "the talk chain hands control back after the receipt")

game = newGame({})
T.check(not pcall(fisher, game, nil, nil, function() end) and #boxes == 0,
  "an empty text table prints no hand-typed line")

-- repeat visit: the flag routes straight to the explanation, no re-gift
game = newGame({ _ViridianCityFisherTM42ExplanationText = "EXPLAIN" })
game.save.flags.EVENT_GOT_TM42 = true
fisher(game, nil, nil, function() end)
T.eq(#boxes, 1, "a second talk opens a single box")
T.eq(boxes[1].text, "EXPLAIN", "and it is the TM42 explanation")
T.eq(game.save.inventory.TM_DREAM_EATER, nil, "no duplicate TM42")

T.finish("viridian_fisher_pre_bug775")
