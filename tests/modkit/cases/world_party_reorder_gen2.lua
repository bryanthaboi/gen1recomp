-- Gen 2 parity for the public party-ordering contract. The fixture also
-- carries slot-based mail because a reorder must move that state with its mon.

package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.harness").suite("mod world party reorder gen2")
local WorldAPI = require("src.world.gen2.WorldAPI")

local first = { species = "CHIKORITA" }
local second = { species = "CYNDAQUIL" }
local firstMail = { message = "FIRST" }
local secondMail = { message = "SECOND" }
local world = { map = { id = "NEW_BARK_TOWN" }, accepts = true }
function world:acceptsMenuInput() return self.accepts end

local game = {
  data = { audio = { sfx = {} } },
  save = {
    party = { first, second },
    mail = { party = { firstMail, secondMail }, box = {} },
  },
  world = world,
}
local api = WorldAPI.new(game, "fixture")

T.check(api:canReorderParty(), "idle free roam allows party reordering")

local Sound = require("src.core.Sound")
local realPlay, played = Sound.play
Sound.play = function(_, name) played = name end
T.check(api:reorderParty(1, 2) == true, "valid slots reorder")
Sound.play = realPlay
T.check(game.save.party[1] == second and game.save.party[2] == first,
  "the live party is swapped")
T.check(game.save.mail.party[1] == secondMail
    and game.save.mail.party[2] == firstMail,
  "slot-based mail follows its Pokemon")
T.eq(played, "Sfx_SwitchPokemon", "the native Gen 2 swap sound is used")

local value, err = api:reorderParty(1.5, 2)
T.check(value == nil and err == "invalid party slot",
  "non-integer slots are rejected")
value, err = api:reorderParty("1", 2)
T.check(value == nil and err == "invalid party slot",
  "string slots are rejected")

world.accepts = false
T.check(not api:canReorderParty(), "busy free roam blocks reordering")
value, err = api:reorderParty(1, 2)
T.check(value == nil and err == "world is busy",
  "reordering refuses while the world owns input")

game.world = nil
value, err = api:reorderParty(1, 2)
T.check(value == nil and err == "no overworld",
  "reordering outside the overworld fails closed")

T.finish()
