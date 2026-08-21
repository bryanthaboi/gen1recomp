-- Parity: leaving the Cerulean Badge House badge-description menu must
-- return control to the overworld after viewing a badge (#454).
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("parity Cerulean Badge House")
local eq = S.eq
local script = require("data.scripts.flavor.cerulean_badge_house")
  .CERULEAN_BADGE_HOUSE.talk.TEXT_CERULEANBADGEHOUSE_MIDDLE_AGED_MAN

local states = {}
local game = {
  data = {
    items = {
      BOULDERBADGE = { name = "BOULDERBADGE" },
      CASCADEBADGE = { name = "CASCADEBADGE" },
      THUNDERBADGE = { name = "THUNDERBADGE" },
      RAINBOWBADGE = { name = "RAINBOWBADGE" },
      SOULBADGE = { name = "SOULBADGE" },
      MARSHBADGE = { name = "MARSHBADGE" },
      VOLCANOBADGE = { name = "VOLCANOBADGE" },
      EARTHBADGE = { name = "EARTHBADGE" },
    },
    text = {
      _CeruleanBadgeHouseMiddleAgedManText = "",
      _CeruleanBadgeHouseMiddleAgedManWhichBadgeText = "",
      _CeruleanBadgeHouseBoulderBadgeText = "",
      _CeruleanBadgeHouseMiddleAgedManVisitAnyTimeText = "",
    },
  },
  save = { player = { name = "RED" } },
  input = { wasPressed = function(_, key) return key == "b" end },
  stack = {
    push = function(_, state) states[#states + 1] = state end,
    pop = function() return table.remove(states) end,
    top = function() return states[#states] end,
  },
}

local done = false
script(game, nil, nil, function() done = true end)

local function dismissText()
  local text = game.stack:pop()
  text.onDone()
end

-- Greeting -> prompt -> first menu -> badge description -> prompt -> second menu.
dismissText()
dismissText()
local firstMenu = game.stack:top()
firstMenu.onChoose(firstMenu.items[1])
dismissText()
dismissText()

-- B follows ListMenu's real cancellation path: pop menu, then show goodbye.
game.stack:top().inputHold = 0
game.stack:top():update(0)
dismissText()

eq(#states, 0, "backing out after viewing a badge leaves no menu behind")
eq(done, true, "backing out after viewing a badge completes the NPC script")

-- PrintListMenuEntries writes ListMenuCancelText where the item list's $FF
-- terminator lands (home/list_menu.asm), so a DisplayListMenuID list always
-- offers CANCEL on screen; choosing it is `cp c / jp c, ExitListMenu`, which
-- sets carry, so the badge script's `jr c, .done` treats it exactly like B
-- (pokered scripts/CeruleanBadgeHouse.asm).  The row was missing (#569).
local check = S.check
local cancelled = false
script(game, nil, nil, function() cancelled = true end)
dismissText()
dismissText()

local menu = game.stack:top()
eq(#menu.items, 9, "eight badges plus the CANCEL row")
eq(menu.items[#menu.items].label, "CANCEL", "CANCEL is the last row")
check(menu.items[#menu.items].value == nil,
      "the CANCEL row carries no badge, so it cannot print a description")
for i = 1, 8 do
  check(menu.items[i].value ~= nil, "badge row " .. i .. " still picks a badge")
end

menu.onChoose(menu.items[#menu.items])
eq(#states, 1, "choosing CANCEL closes the list and leaves the goodbye line")
dismissText()
eq(#states, 0, "choosing CANCEL leaves no menu behind")
eq(cancelled, true, "choosing CANCEL takes the same .done exit as B")

S.finish()
