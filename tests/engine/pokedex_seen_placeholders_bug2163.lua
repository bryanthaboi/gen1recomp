-- engine/menus/pokedex.asm:449
--   luajit tests/engine/pokedex_seen_placeholders_bug2163.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check = T.check
love = love or require("tests.love_stub")

local calls = {}
local realFont = package.loaded["src.render.Font"]
package.loaded["src.render.Font"] = {
  draw = function(text, x, y) calls[#calls + 1] = { text = text, x = x, y = y } end,
  drawCode = function(code, x, y) calls[#calls + 1] = { code = code, x = x, y = y } end,
}

package.loaded["src.ui.DexEntryMenu"] = nil
local DexEntryMenu = require("src.ui.DexEntryMenu")

local function hasText(text, x, y)
  for _, c in ipairs(calls) do
    if c.text == text and c.x == x and c.y == y then return true end
  end
  return false
end
local function anyBelow(y)
  for _, c in ipairs(calls) do
    if c.y and c.y >= y then return true end
  end
  return false
end

local def = {
  id = "SNORLAX",
  name = "SNORLAX",
  dex = 143,
  dexEntry = {
    kind = "SLEEPING POKEMON",
    heightFt = 6, heightIn = 11, weight = 10140,
    text = "_SnorlaxDexEntry",
  },
}

local game = {
  data = {
    pokemon = { SNORLAX = def },
    text = { _SnorlaxDexEntry = "Very lazy. Just\neats and sleeps" },
    constants = { dexDigits = 3 },
  },
  save = { pokedex = { owned = {}, seen = { SNORLAX = true } } },
}

local function skeleton(label)
  check(hasText("HT", 72, 48), label .. ": HT label in col 9")
  check(hasText("′", 112, 48), label .. ": foot mark in col 14")
  check(hasText("″", 136, 48), label .. ": inch mark in col 17")
  check(hasText("WT", 72, 64), label .. ": WT label in col 9")
  check(hasText("lb", 136, 64), label .. ": lb unit in cols 17-18")
end

calls = {}
DexEntryMenu.render(game, def, nil, false, false, 1, {})
skeleton("seen")
check(hasText("?", 104, 48), "seen: the feet placeholder sits in col 13")
check(hasText("??", 120, 48), "seen: the inches placeholder sits in cols 15-16")
check(hasText("???", 112, 64), "seen: the weight placeholder sits in cols 14-16")
check(not hasText("Data unknown.", 8, 88),
      "seen: no invented substitute message")
check(not anyBelow(88), "seen: nothing at all below the divider")

calls = {}
DexEntryMenu.render(game, def, nil, false, false, 1, { crying = true })
skeleton("crying")
check(hasText("?", 104, 48), "crying: the placeholders are already up")

game.save.pokedex.owned.SNORLAX = true
calls = {}
DexEntryMenu.render(game, def, nil, false, false, 1, {})
skeleton("owned")
check(hasText(" 6", 96, 48), "owned: feet in cols 12-13")
check(hasText("11", 120, 48), "owned: inches in cols 15-16")
check(hasText("1014.0", 88, 64), "owned: weight right-aligned into cols 11-16")
check(not hasText("?", 104, 48), "owned: no leftover placeholder digits")
check(hasText("Very lazy. Just", 8, 88), "owned: the description prints")

game.save.pokedex.owned.SNORLAX = nil
calls = {}
DexEntryMenu.render(game, def, nil, true, false, 1, {})
check(hasText(" 6", 96, 48), "forceOwned: feet still print")
check(not hasText("???", 112, 64), "forceOwned: no weight placeholder")

package.loaded["src.render.Font"] = realFont
package.loaded["src.ui.DexEntryMenu"] = nil

T.finish("pokedex seen placeholders bug 2163")
