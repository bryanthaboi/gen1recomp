-- scripts/CeladonMart3F.asm:24
-- scripts/Route12Gate2F.asm:10
-- scripts/CeladonCity.asm:44
-- scripts/CinnabarLabMetronomeRoom.asm:12
-- scripts/ViridianCity.asm:236
-- scripts/SilphCo2F.asm:115
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

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

local CASES = {
  { "CELADON_MART_3F", "TEXT_CELADONMART3F_CLERK", "TM_COUNTER",
    "EVENT_GOT_TM18", "_CeladonMart3FClerkReceivedTM18Text",
    "_CeladonMart3FClerkTM18ExplanationText" },
  { "ROUTE_12_GATE_2F", "TEXT_ROUTE12GATE2F_BRUNETTE_GIRL", "TM_SWIFT",
    "EVENT_GOT_TM39", "_Route12Gate2FBrunetteGirlReceivedTM39Text",
    "_Route12Gate2FBrunetteGirlTM39ExplanationText" },
  { "CELADON_CITY", "TEXT_CELADONCITY_GRAMPS3", "TM_SOFTBOILED",
    "EVENT_GOT_TM41", "_CeladonCityGramps3ReceivedTM41Text",
    "_CeladonCityGramps3TM41ExplanationText" },
  { "CINNABAR_LAB_METRONOME_ROOM", "TEXT_CINNABARLABMETRONOMEROOM_SCIENTIST1",
    "TM_METRONOME", "EVENT_GOT_TM35",
    "_CinnabarLabMetronomeRoomScientist1ReceivedTM35Text",
    "_CinnabarLabMetronomeRoomScientist1TM35ExplanationText" },
  { "VIRIDIAN_CITY", "TEXT_VIRIDIANCITY_FISHER", "TM_DREAM_EATER",
    "EVENT_GOT_TM42", "_ViridianCityFisherReceivedTM42Text",
    "_ViridianCityFisherTM42ExplanationText" },
  { "SILPH_CO_2F", "TEXT_SILPHCO2F_SILPH_WORKER_F", "TM_SELFDESTRUCT",
    "EVENT_GOT_TM36", "_SilphCo2FSilphWorkerFReceivedTM36Text",
    "_SilphCo2FSilphWorkerFTM36ExplanationText" },
}

local function newGame(item, received, explain)
  boxes = {}
  return {
    data = {
      text = setmetatable({ [received] = "RECEIVED", [explain] = "EXPLAIN" },
        { __index = function(_, k) return k end }),
      items = { [item] = { name = "TMXX" } },
    },
    save = { flags = {}, inventory = {}, player = { name = "RED" } },
    stack = { push = function(_, box) boxes[#boxes + 1] = box end },
  }
end

for _, c in ipairs(CASES) do
  local map, label, item, flag, received, explain = unpack(c)
  local talk = story5[map] and story5[map].talk[label]
  T.check(type(talk) == "function", label .. " is a gift closure")

  local game = newGame(item, received, explain)
  local finished = false
  talk(game, nil, nil, function() finished = true end)
  T.eq(#boxes, 1, label .. ": the pre text opens first")
  boxes[1].onDone()
  T.eq(#boxes, 2, label .. ": then the received box")
  T.eq(boxes[2].text, "RECEIVED", label .. ": with the received text")
  T.check(game.save.flags[flag] == true, label .. ": the flag is set")
  boxes[2].onDone()
  T.eq(#boxes, 2, label .. ": nothing follows the received box")
  T.check(finished, label .. ": the talk ends on the receipt")

  local saved = game.save
  game = newGame(item, received, explain)
  game.save = saved
  local again = false
  talk(game, nil, nil, function() again = true end)
  T.eq(#boxes, 1, label .. ": a second talk opens one box")
  T.eq(boxes[1].text, "EXPLAIN", label .. ": the explanation")
  boxes[1].onDone()
  T.check(again, label .. ": and ends")
  T.eq(saved.inventory[item], 1, label .. ": no second copy")
end

T.finish("tm_gift_explain_bug2583")
