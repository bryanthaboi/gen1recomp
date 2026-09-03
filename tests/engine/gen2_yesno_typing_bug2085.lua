-- ../pokecrystal/engine/menus/save.asm:209 SaveTheGame_yesorno
-- ../pokecrystal/engine/events/daycare.asm:107
-- ../pokecrystal/engine/items/mart.asm:517 MartConfirmPurchase

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local eq, check = T.eq, T.check
love = love or require("tests.love_stub")

local Save = require("src.core.gen2.Save")
local SaveMenu = require("src.ui.gen2.SaveMenu")
local DayCareMenu = require("src.ui.gen2.DayCareMenu")
local MartMenu = require("src.ui.gen2.MartMenu")
local Typer = require("src.ui.gen2.Typer")

local function newInput()
  local input = { pressed = {}, held = {} }
  function input:press(button) self.pressed[button] = true end
  function input:wasPressed(button)
    if self.pressed[button] then
      self.pressed[button] = nil
      return true
    end
    return false
  end
  function input:isDown(button) return self.held[button] == true end
  return input
end

local input = newInput()
local save = Save.newGame({ playerName = "GOLD", trainerId = 1 })
save.options = save.options or {}
save.options.textSpeed = "MID"
local game = { input = input, save = save }

local menu = SaveMenu.new(game, {
  save = save, existed = true,
  writer = function() return true end,
})

check(not menu:yesNoVisible(), "no YES/NO before the prompt starts typing")
menu:update(0)
check(Typer.typing(menu), "the confirm question types letter by letter")
check(not menu:yesNoVisible(), "YES/NO stays down while it types")

local frames = 0
while Typer.typing(menu) and frames < 600 do
  menu:update(0)
  frames = frames + 1
end
check(frames > 0 and frames < 600, "the confirm question finishes typing")
check(menu:yesNoVisible(), "YES/NO goes up once the question has printed")

input:press("a")
menu:update(0)
eq(menu.phase, "overwrite", "YES on an existing file asks to overwrite")
check(Typer.typing(menu), "the overwrite question types letter by letter")
check(not menu:yesNoVisible(), "its YES/NO waits for its own prompt")

frames = 0
while Typer.typing(menu) and frames < 600 do
  menu:update(0)
  frames = frames + 1
end
check(frames > 0 and frames < 600, "the overwrite question finishes typing")
-- ../pokecrystal/data/text/common_3.asm:205
eq(menu.page, 1, "the overwrite prompt's first page is up")
eq(#menu.pages, 2, "and it has a cont page after it")
check(not menu:yesNoVisible(), "no YES/NO while the cont page waits for a button")

input:press("a")
menu:update(0)
eq(menu.page, 2, "A turns to the cont page")
eq(menu.phase, "overwrite", "without answering the question")
check(Typer.typing(menu), "the cont page types letter by letter")
check(not menu:yesNoVisible(), "and the YES/NO waits for it")

frames = 0
while Typer.typing(menu) and frames < 600 do
  menu:update(0)
  frames = frames + 1
end
check(frames > 0 and frames < 600, "the cont page finishes typing")
check(menu:yesNoVisible(), "then the overwrite YES/NO goes up")

input:press("a")
menu:update(0)
eq(menu.phase, "saving", "YES starts the save")
check(not menu:yesNoVisible(), "no YES/NO on the SAVING page")

local dc = setmetatable({ game = game }, DayCareMenu)
dc.confirm = {
  pages = {
    { "I'm the DAY-CARE", "MAN. Want me to" },
    { "raise a #MON", "for you?" },
  },
  page = 1, choice = 1,
}
Typer.begin(dc, dc.confirm)
check(not dc:yesNoVisible(), "Day-Care YES/NO stays down on page one")

frames = 0
while Typer.typing(dc) and frames < 600 do
  Typer.step(dc)
  frames = frames + 1
end
check(frames > 0 and frames < 600, "page one finishes typing")
check(not dc:yesNoVisible(), "and it stays down while the page turn waits")

Typer.turn(dc, dc.confirm)
check(Typer.typing(dc), "the last page types letter by letter")
check(not dc:yesNoVisible(), "and the YES/NO stays down while it does")

frames = 0
while Typer.typing(dc) and frames < 600 do
  Typer.step(dc)
  frames = frames + 1
end
check(frames > 0 and frames < 600, "the last page finishes typing")
check(dc:yesNoVisible(), "then the Day-Care YES/NO goes up")

local mm = setmetatable({ game = game }, MartMenu)
mm.confirm = {
  pages = { { "POTION?", "That will be ¥300." } },
  page = 1, choice = 1,
}
Typer.begin(mm, mm.confirm)
check(not mm:yesNoVisible(), "mart YES/NO stays down while the price types")

frames = 0
while Typer.typing(mm) and frames < 600 do
  Typer.step(mm)
  frames = frames + 1
end
check(frames > 0 and frames < 600, "the price line finishes typing")
check(mm:yesNoVisible(), "then the mart YES/NO goes up")

local instant = setmetatable({
  confirm = { pages = { { "Sure thing." } }, page = 1, choice = 1 },
}, MartMenu)
check(instant:yesNoVisible(), "a pre-typed prompt shows its YES/NO at once")

T.finish("gen2 yesno typing bug 2085")
