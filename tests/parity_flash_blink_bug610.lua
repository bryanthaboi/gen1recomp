-- Parity test: nothing expensive may ride the FLASH white-out's completion
-- callback (#610).  Transition.WhiteFlash is opaque and paints the whole
-- 160x144 solid white, so whatever runs from its onDone runs with a blank
-- white frame as the newest thing the player has been shown.  Lighting the
-- cave is exactly that kind of work: in the ADVANCED colour mode
-- OverworldState:setDark drops every resident map and rebakes the tileset
-- atlas pixel by pixel (#383), which on a phone is seconds of frozen white
-- and reads as a lockup.  engine/menus/start_sub_menus.asm .flash clears
-- wMapPalOffset before PrintText and calls GBPalWhiteOutWithDelay3 last of
-- all, so the port lights the cave as the message closes the menu and
-- leaves the blink a plain 7-frame blink with no work attached.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local Data = require("src.core.Data")
if not (Data.maps and Data.maps.PALLET_TOWN) then Data:load() end
local S = require("tests.harness").suite("parity flash blink bug610")
local check, eq = S.check, S.eq

require("src.render.Font").load(Data)
local Game       = require("src.core.Game")
local Input      = require("src.core.Input")
local StateStack = require("src.core.StateStack")
local Renderer   = require("src.render.Renderer")
local SaveData   = require("src.core.SaveData")
local Pokemon    = require("src.pokemon.Pokemon")
local PartyMenu  = require("src.ui.PartyMenu")
local OW         = require("src.world.OverworldController")

Game.data = Data
Game.input = Input; Input:init()
Game.renderer = Renderer; Renderer:init()
Game.stack = StateStack; StateStack:init()
Game.save = SaveData.newGame()

local function frame(btns)
  Input.pressed = {}
  for _, b in ipairs(btns or {}) do Input.pressed[b] = true; Input.state[b] = true end
  StateStack:update(1 / 60)
  for _, b in ipairs(btns or {}) do Input.state[b] = false end
end
local function popAll() while Game.stack:top() do Game.stack:pop() end end
local function mkMon(species, ...)
  local m = Pokemon.new(Data, species, 20)
  m.moves = {}
  for _, id in ipairs({ ... }) do m.moves[#m.moves + 1] = { id = id, pp = 15 } end
  return m
end
-- dismiss exactly one box, leaving whatever it pushed on top
local function drainOne()
  local box = Game.stack:top()
  local guard = 0
  while Game.stack:top() == box and guard < 400 do
    guard = guard + 1
    frame({ "a" })
  end
end

Game.save.flashLit = false
Game.save.party = { mkMon("PIKACHU", "FLASH") }
Game.save.inventory = { BOULDERBADGE = true }
popAll()
Game.stack:push(OW, "ROCK_TUNNEL_1F", 15, 4, "down")
local ow = Game.stack:top()
eq(ow.dark, true, "ROCK_TUNNEL_1F loads dark before FLASH")

local pm = PartyMenu.new(Game)
Game.stack:push(pm)
frame({ "a" })                 -- open the field-move submenu on PIKACHU
for _ = 2, 3 do frame({ "down" }) end
frame({ "a" })                 -- FLASH
drainOne()                     -- dismiss _FlashLightsAreaText

local blink = Game.stack:top()
check(blink ~= nil and blink.isOpaque == true and type(blink.frames) == "number",
  "the blink follows the FLASH message")
-- the invariant this test exists for: the blink carries no work
eq(blink.onDone, nil, "the FLASH blink has no completion callback (#610)")
eq(ow.dark, false, "the cave is already lit when the blink starts")

local guard = 0
while Game.stack:top() ~= ow and guard < 240 do
  guard = guard + 1
  frame({})
end
eq(Game.stack:top(), ow, "FLASH ends on the map")
eq(ow.dark, false, "the cave stays lit after the blink")
eq(Game.save.flashLit, true, "FLASH is recorded on the save")

popAll()
S.finish()
