#!/usr/bin/env luajit
-- ../pokefirered/src/pokedex_screen.c:407-435, :1031-1035

package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function eq(a, b, msg)
  if a == b then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print(string.format("[FAIL] %s (%s ~= %s)", msg, tostring(a), tostring(b)))
  end
end

local function check(cond, msg)
  eq(cond and true or false, true, msg)
end

require("src.core.GameVersion").set("firered")

package.loaded["src.core.game3.audio"] = {
  playCry = function() end,
  playSe = function() end,
  playSong = function() end,
  stopAll = function() end,
}

local Dex = require("src.core.game3.dex")
local Pokemon = require("src.core.game3.pokemon")
local Pokedex = require("src.ui.game3.pokedex")
local PokedexChrome = require("src.ui.game3.pokedex_chrome")
local FrlgFont = require("src.ui.game3.frlg_font")

Pokemon.install(nil)

local MAX_SHOWED = 9

local realLove = love
love = {
  graphics = {
    setColor = function() end,
    rectangle = function() end,
    polygon = function() end,
    circle = function() end,
    line = function() end,
    draw = function() end,
    print = function() end,
    getScissor = function() return nil end,
    setScissor = function() end,
  },
}

local saved = {
  paper = PokedexChrome.drawPaperBg,
  header = PokedexChrome.drawHeader,
  control = PokedexChrome.drawControlInfo,
  icon = PokedexChrome.drawCategoryIcon,
  up = PokedexChrome.drawUpArrow,
  down = PokedexChrome.drawDownArrow,
  font = FrlgFont.draw,
}

local arrows, icons
PokedexChrome.drawPaperBg = function() end
PokedexChrome.drawHeader = function() end
PokedexChrome.drawControlInfo = function() end
FrlgFont.draw = function() end
PokedexChrome.drawCategoryIcon = function(key, x, y)
  icons[#icons + 1] = { key = key, x = x, y = y }
end
PokedexChrome.drawUpArrow = function(x, y) arrows[#arrows + 1] = { dir = "up", x = x, y = y } end
PokedexChrome.drawDownArrow = function(x, y) arrows[#arrows + 1] = { dir = "down", x = x, y = y } end

local function restore()
  PokedexChrome.drawPaperBg = saved.paper
  PokedexChrome.drawHeader = saved.header
  PokedexChrome.drawControlInfo = saved.control
  PokedexChrome.drawCategoryIcon = saved.icon
  PokedexChrome.drawUpArrow = saved.up
  PokedexChrome.drawDownArrow = saved.down
  FrlgFont.draw = saved.font
  love = realLove
end

local function render()
  arrows, icons = {}, {}
  Pokedex.draw()
  local up, down
  for _, a in ipairs(arrows) do
    if a.dir == "up" then up = a else down = a end
  end
  return up, down
end

local input = {
  _pressed = {},
  wasPressed = function(self, key) return self._pressed[key] == true end,
  press = function(self, key) self._pressed = { [key] = true } end,
}

local function openToc()
  local dex = Dex.new()
  Pokedex.show(dex, { session = { dex = dex } })
  return dex
end

print("[test] 1. The table of contents opens at the top of the list")
do
  openToc()
  eq(Pokedex.screen, "mode_select", "the pokedex opens on the table of contents")
  eq(Pokedex.modeScroll, 0, "the list starts unscrolled")
  check(#Pokedex.MODES > MAX_SHOWED, "the table of contents is longer than the window")
end

print("[test] 2. At the top of the list only the down arrow is drawn")
do
  local up, down = render()
  eq(up, nil, "no up arrow at scroll 0")
  check(down ~= nil, "the down arrow is drawn at scroll 0")
  eq(down and down.x, 200, "the down arrow sits at secondX 200")
  eq(down and down.y, 141, "the down arrow sits at secondY 141")
end

print("[test] 3. The category icon keeps its pret window origin")
do
  render()
  local icon = icons[1]
  check(icon ~= nil, "the selected mode draws a category icon")
  eq(icon and icon.x, 168, "sWindowTemplate_SelectionIcon tilemapLeft 21 is x 168")
  eq(icon and icon.y, 88, "sWindowTemplate_SelectionIcon tilemapTop 11 is y 88")
end

print("[test] 4. Scrolling into the middle draws both arrows")
do
  local guard = 0
  while Pokedex.modeScroll == 0 and guard < 64 do
    input:press("down")
    Pokedex.handleInput(input)
    guard = guard + 1
  end
  check(Pokedex.modeScroll > 0, "the cursor scrolled the list")
  local up, down = render()
  check(up ~= nil, "the up arrow appears once the list has scrolled")
  eq(up and up.x, 200, "the up arrow sits at firstX 200")
  eq(up and up.y, 19, "the up arrow sits at firstY 19")
  check(down ~= nil, "the down arrow is still drawn mid-list")
end

print("[test] 5. At the bottom of the list only the up arrow is drawn")
do
  local guard = 0
  while Pokedex.modeScroll < #Pokedex.MODES - MAX_SHOWED and guard < 64 do
    input:press("down")
    Pokedex.handleInput(input)
    guard = guard + 1
  end
  eq(Pokedex.modeScroll, #Pokedex.MODES - MAX_SHOWED, "the list is scrolled to the end")
  local up, down = render()
  check(up ~= nil, "the up arrow is drawn at the end of the list")
  eq(down, nil, "no down arrow at the fullyDown threshold")
end

print("[test] 6. No arrow is ever drawn inside the category icon window")
do
  openToc()
  local inside, frames = 0, 0
  for _ = 1, 64 do
    render()
    frames = frames + 1
    for _, a in ipairs(arrows) do
      if a.x >= 168 and a.x < 232 and a.y >= 88 and a.y < 136 then inside = inside + 1 end
    end
    input:press("down")
    Pokedex.handleInput(input)
  end
  check(frames > 0, "the table of contents was walked top to bottom")
  eq(inside, 0, "no scroll arrow lands inside the 64x48 icon window")
end

print("[test] 7. The Kanto table of contents carries pret's 19 rows")
do
  -- ../pokefirered/src/pokedex_screen.c:319-340, :363-384, :407-419
  openToc()
  eq(#Pokedex.MODES, 19, "sListMenuItems_KantoDexModeSelect has 19 rows")
  eq(#Pokedex.MODES - MAX_SHOWED, 10, "fullyDownThreshold is 10 on a Kanto save")
  local labels, ids = {}, {}
  for _, m in ipairs(Pokedex.MODES) do
    labels[#labels + 1] = tostring(m.label)
    if m.id then ids[m.id] = m end
  end
  eq(labels[1], "POKéMON LIST", "row 1 is the POKéMON LIST header")
  eq(labels[2], "NUMERICAL MODE", "the Kanto list has a single NUMERICAL MODE row")
  eq(labels[3], "POKéMON HABITATS", "row 3 is the POKéMON HABITATS header")
  eq(labels[13], "SEARCH", "row 13 is the SEARCH header")
  eq(labels[18], "OTHER", "row 18 is the OTHER header")
  eq(labels[19], "CANCEL", "row 19 closes the pokedex")
  -- ../pokefirered/src/pokedex_screen.c:1191-1196 greys locked categories only
  for _, id in ipairs({ "atoz", "type", "lightest", "smallest" }) do
    check(ids[id] ~= nil, "the Kanto list keeps the " .. id .. " row")
    eq(ids[id] and ids[id].unlocked, true, "and prints it unlocked")
  end
  eq(ids.grassland and ids.grassland.unlocked, false, "a locked habitat is still greyed")

  local dex = Dex.new()
  dex.nationalUnlocked = true
  Pokedex.show(dex, { session = { dex = dex } })
  eq(#Pokedex.MODES, 20, "sListMenuItems_NatDexModeSelect has 20 rows")
  eq(#Pokedex.MODES - MAX_SHOWED, 11, "fullyDownThreshold is 11 with the national dex")
  Pokedex.close()
end

print("[test] 8. The list scrolls on pret's midpoint rule and walks back to the top")
do
  -- ../pokefirered/src/list_menu.c:438-516
  openToc()
  local outside = 0
  local function inWindow()
    if Pokedex.modeCursor < Pokedex.modeScroll + 1
       or Pokedex.modeCursor > Pokedex.modeScroll + MAX_SHOWED then
      outside = outside + 1
    end
  end
  eq(Pokedex.modeScroll, 0, "the list opens at scroll 0")
  for _ = 1, 3 do
    input:press("down")
    Pokedex.handleInput(input)
    inWindow()
  end
  eq(Pokedex.modeScroll, 0, "the first three steps stay above the midpoint row")
  eq(Pokedex.modeCursor, 6, "the cursor reached row 6 of the window")
  input:press("down")
  Pokedex.handleInput(input)
  inWindow()
  eq(Pokedex.modeScroll, 1, "the fourth step scrolls instead of moving the cursor down")
  eq(Pokedex.modeCursor, 7, "and the cursor holds the midpoint row")

  for _ = 1, 40 do
    input:press("down")
    Pokedex.handleInput(input)
    inWindow()
  end
  eq(Pokedex.modeCursor, 19, "walking down lands on CANCEL")
  eq(Pokedex.modeScroll, 10, "and parks the list at the fullyDown threshold")
  local up, down = render()
  check(up ~= nil, "the up arrow is drawn at the bottom")
  eq(down, nil, "the down arrow is gone at the bottom")

  for _ = 1, 40 do
    input:press("up")
    Pokedex.handleInput(input)
    inWindow()
  end
  eq(Pokedex.modeScroll, 0, "walking back up returns the list to scroll 0")
  eq(Pokedex.modeCursor, 2, "and the cursor to NUMERICAL MODE")
  eq(outside, 0, "the cursor never leaves the nine visible rows")
  up, down = render()
  eq(up, nil, "no up arrow once the header is back on screen")
  check(down ~= nil, "the down arrow is back")
end

Pokedex.close()
restore()

if failed > 0 then
  print(string.format("\n[FAILED] %d check(s) failed", failed))
  os.exit(1)
end
print("\n[test] all passed")
