#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function eq(a, b, msg)
  check(a == b, string.format("%s (%s == %s)", msg, tostring(a), tostring(b)))
end

require("src.core.GameVersion").set("firered")

package.loaded["src.core.game3.audio"] = {
  playSe = function() end,
  playCry = function() end,
  playSong = function() end,
  stopAll = function() end,
}

local gfx = setmetatable({}, { __index = function() return function() end end })
gfx.newQuad = function() return {} end
gfx.newImage = function() return nil end
gfx.getWidth = function() return 240 end
gfx.getHeight = function() return 160 end
_G.love = { graphics = gfx, timer = { getTime = function() return 0 end } }

local Pokemon = require("src.core.game3.pokemon")
local SummaryMenu = require("src.ui.game3.summary_menu")
local SummaryChrome = require("src.ui.game3.summary_chrome")

local function mon(pokerus)
  return {
    species = 25,
    level = 30,
    hp = 50,
    maxHp = 50,
    stats = { hp = 50, attack = 30, defense = 30, spAttack = 30, spDefense = 30, speed = 30 },
    moves = { "THUNDERBOLT" },
    pp = { 15 },
    pokerus = pokerus,
    otName = "RED",
    otId = 1,
    personality = 1,
  }
end

print("[test] 1. the cured-only predicate matches CheckPartyPokerus / CheckPartyHasHadPokerus")
eq(SummaryMenu.showsPokerusIcon(mon(0)), false, "pokerus 0x00 (never infected) hides the dot")
eq(SummaryMenu.showsPokerusIcon(mon(0x04)), false, "pokerus 0x04 (infected, 4 days left) hides the dot")
eq(SummaryMenu.showsPokerusIcon(mon(0x41)), false, "pokerus 0x41 (infected strain 4) hides the dot")
eq(SummaryMenu.showsPokerusIcon(mon(0x10)), true, "pokerus 0x10 (strain 1, cured) shows the dot")
eq(SummaryMenu.showsPokerusIcon(mon(0xF0)), true, "pokerus 0xF0 (strain 15, cured) shows the dot")
eq(SummaryMenu.showsPokerusIcon(nil), false, "no mon hides the dot")

check(Pokemon.hasPokerus(mon(0x04)) == true, "Pokemon.hasPokerus agrees for an infected mon")
check(Pokemon.hasHadPokerus(mon(0x10)) == true, "Pokemon.hasHadPokerus agrees for a cured mon")

print("[test] 2. the summary screen actually draws it, and only for a cured mon")
local drawn = {}
SummaryChrome.drawPokerus = function(x, y) drawn[#drawn + 1] = { x = x, y = y } end
SummaryChrome.drawPageBg = function() end
SummaryChrome.drawShinyStar = function() end
SummaryChrome.drawStatusIcon = function() end
SummaryChrome.drawTypeBadge = function() end
SummaryChrome.drawHpBar = function() end
SummaryChrome.drawExpBar = function() end

local function draw_with(pokerus, page)
  drawn = {}
  SummaryMenu.openMenu({ mon(pokerus) }, 1, { page = page or 0 })
  SummaryMenu.draw()
  SummaryMenu.close()
  return drawn
end

eq(#draw_with(0), 0, "never-infected mon: drawPokerus not called")
eq(#draw_with(0x04), 0, "infected mon: drawPokerus not called")
local shots = draw_with(0x10)
eq(#shots, 1, "cured mon: drawPokerus called once")
-- pokefirered/src/pokemon_summary_screen.c:4715
eq(shots[1] and shots[1].x, 110, "drawn at pret's sprite x 114 minus the 8x8 centre offset")
eq(shots[1] and shots[1].y, 88, "drawn at pret's sprite y 92 minus the 8x8 centre offset")

-- pokefirered/src/pokemon_summary_screen.c:4746
eq(#draw_with(0x10, 1), 1, "cured mon: still drawn on the SKILLS page")
local movesShot = draw_with(0x10, 2)
eq(#movesShot, 1, "cured mon: still drawn on the MOVES page")
eq(movesShot[1] and movesShot[1].x, 110, "MOVES page keeps the create position")

if failed > 0 then
  print(string.format("\n%d CHECK(S) FAILED", failed))
  os.exit(1)
end
print("\nALL SUMMARY POKERUS TESTS PASSED")
