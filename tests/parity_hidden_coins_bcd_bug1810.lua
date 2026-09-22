-- Parity: HiddenCoins pays BCD constants, and the COIN+40 tile pays 20 (#1810).
--
-- engine/events/hidden_items.asm:79-96 branches the hidden-event argument
-- into .bcd10 ($10), .bcd20 ($20) or .bcd100 ($0100); `cp 40 / jr z, .bcd20`
-- is pokered's own typo, so .bcd40 at :90 ("due to a typo, this is never
-- used") never runs and the Game Corner's COIN+40 tile (data/events/
-- hidden_events.asm:294, GAME_CORNER 11,7) credits 20 coins on hardware.
--
-- Self-contained; run via `luajit tests/parity_hidden_coins_bcd_bug1810.lua`.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local S = require("tests.harness").suite("parity hidden coins bcd")
local check, eq = S.check, S.eq

local OverworldState = require("src.world.OverworldController")
local pay = OverworldState.hiddenCoinPayout

eq(pay(10), 10, "COIN + 10 pays BCD $10")
eq(pay(20), 20, "COIN + 20 pays BCD $20")
eq(pay(40), 20, "COIN + 40 falls into .bcd20 and pays 20")
eq(pay(100), 100, "COIN + 100 pays BCD $0100")
eq(pay(0), 100, "anything the branch chain misses pays 100")

-- the generated data still carries the raw argument: the runtime mapping,
-- not the extractor, is what turns the 40 tile into 20
local Data = require("src.core.Data")
if not Data.field then Data:load() end
local field = Data.field
local corner = field.hiddenCoins and field.hiddenCoins.GAME_CORNER
check(corner ~= nil, "GAME_CORNER has hidden coin tiles")

local forty
for _, h in ipairs(corner or {}) do
  if h.x == 11 and h.y == 7 then forty = h end
end
check(forty ~= nil, "the (11,7) hidden coin tile is present")
eq(forty and forty.coins, 40, "it is extracted as the COIN + 40 argument")
eq(pay(forty and forty.coins), 20, "and the award path credits 20 for it")

S.finish()
