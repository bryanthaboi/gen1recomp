package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 new dex entry fade")
local check, eq = S.check, S.eq

love = require("tests.love_stub")

local PokedexMenu = require("src.ui.gen2.PokedexMenu")
local GbcPalette = require("src.render.GbcPalette")

local pressed = {}
local input = { wasPressed = function(_, key) return pressed[key] == true end }
local closes = 0
local game = {
  input = input,
  save = { pokedex = { seen = { PIDGEY = true }, caught = { PIDGEY = true } } },
  data = {
    pokemon = { PIDGEY = { types = { "NORMAL", "FLYING" } } },
    gen2Pokedex = {
      entries = { PIDGEY = { dex = 16, kind = "TINY BIRD", height = 100, weight = 40 } },
      newOrder = { "PIDGEY" }, alphabeticalOrder = { "PIDGEY" },
    },
  },
}
local dex = PokedexMenu.new(game, {
  entrySpecies = "PIDGEY", newEntry = true,
  onClose = function() closes = closes + 1 end,
})
check(dex.newEntry == true and dex.view == "entry", "NewPokedexEntry opens on the entry")

local function tap(key)
  pressed[key] = true
  dex:update(1 / 60)
  pressed[key] = nil
end

tap("a")
eq(dex.page, 2, "the first press turns to page 2")
eq(dex:closeFadeBgp(), nil, "no fade on page 1 -> 2")
tap("a")
eq(closes, 0, "the second press does not close at once")
local seen, sequence = {}, {}
for frame = 1, 24 do
  local bgp = dex:closeFadeBgp()
  if bgp ~= seen[#seen] then seen[#seen + 1] = bgp end
  sequence[frame] = bgp
  if frame == 12 then tap("a") else dex:update(1 / 60) end
end
eq(table.concat({ ("%02x"):format(seen[1] or -1), ("%02x"):format(seen[2] or -1),
  ("%02x"):format(seen[3] or -1) }, ","), "90,40,00",
  "RotateThreePalettesRight steps BGP $90, $40, $00")
eq(#seen, 3, "and only those three")
eq(sequence[8], 0x90, "eight frames on $90")
eq(sequence[9], 0x40, "then $40")
eq(sequence[17], 0x00, "then $00")
eq(closes, 1, "the dex closes once, after 24 frames")
eq(dex:closeFadeBgp(), nil, "and the fade is spent")

local captured
local realSet = GbcPalette.setBgp
local realPanel = dex.drawPanel
dex.closeFade = 9
dex.drawPanel = function() captured = GbcPalette.bgp end
dex:draw()
eq(captured, 0x40, "the panel draws through the fade's BGP")
eq(GbcPalette.bgp, nil, "and BGP is restored after")
dex.drawPanel, GbcPalette.setBgp = realPanel, realSet
dex.closeFade = nil

for _ = 1, 30 do tap("a") end
eq(closes, 1, "presses after the close do nothing")

S.finish()
