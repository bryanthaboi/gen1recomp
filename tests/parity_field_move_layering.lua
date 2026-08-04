-- Parity test: the party-menu field moves print their text with the party
-- menu still on screen, and the GBPalWhiteOutWithDelay3 blink IS the menu
-- closing afterwards (engine/menus/start_sub_menus.asm .flash / .strength /
-- .surf, each PrintText -> GBPalWhiteOutWithDelay3 -> jp .goBackToMap,
-- whose RestoreScreenTilesAndReloadTilePatterns + CloseTextDisplay tear the
-- menu down only after the white-out).  Popping the menu first left the
-- opaque WhiteFlash as the only state under the message, i.e. the white
-- screen in #385, and lit a dark cave under the FLASH text.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local Data = require("src.core.Data")
if not (Data.maps and Data.maps.PALLET_TOWN) then Data:load() end
local S = require("tests.harness").suite("parity field move layering")
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

-- tests/parity_bills_pc.lua swaps the OverworldController chunk's TextBox
-- upvalue for a stub and never puts it back, and run_tests.lua dofiles every
-- parity suite into one process: point it back at the real module so trySurf
-- pushes a real box here.
local function setUpvalue(fn, name, val)
  local i = 1
  while true do
    local n = debug.getupvalue(fn, i)
    if not n then return false end
    if n == name then debug.setupvalue(fn, i, val); return true end
    i = i + 1
  end
end
setUpvalue(OW.trySurf, "TextBox", require("src.render.TextBox"))

local function frame(btns)
  Input.pressed = {}
  for _, b in ipairs(btns or {}) do Input.pressed[b] = true; Input.state[b] = true end
  StateStack:update(1 / 60)
  for _, b in ipairs(btns or {}) do Input.state[b] = false end
end
local function popAll() while Game.stack:top() do Game.stack:pop() end end
local function pushOW(mapId, x, y, facing)
  popAll()
  Game.stack:push(OW, mapId, x, y, facing)
  return Game.stack:top()
end
local function mkMon(species, ...)
  local m = Pokemon.new(Data, species, 20)
  m.moves = {}
  for _, id in ipairs({ ... }) do m.moves[#m.moves + 1] = { id = id, pp = 15 } end
  return m
end
local function selectSubItem(pm, idx)
  Game.stack:push(pm)
  frame({ "a" })
  for _ = 2, idx do frame({ "down" }) end
  frame({ "a" })
end

local function isText(s) return s ~= nil and s.pages ~= nil end
-- Transition.whiteFlash keeps its remaining frame budget and draws a full
-- opaque rect; the overworld and the menu have no `frames`
local function isBlink(s)
  return s ~= nil and s.pages == nil and s.isOpaque == true
     and type(s.frames) == "number"
end
-- the state the compositor starts from: StateStack:draw walks up from the
-- highest opaque state, so this is literally what the player sees behind
-- the message
local function backdrop()
  return Game.stack.states[Game.stack:visibleBase()]
end
-- dismiss exactly one box (an auto page advances on its own timer, a
-- prompt page on A), leaving whatever it pushed on top
local function drainOne()
  local box = Game.stack:top()
  local guard = 0
  while Game.stack:top() == box and guard < 400 do
    guard = guard + 1
    frame({ "a" })
  end
end
-- run frames until the stack is back on the map (the blink pops itself and
-- fires its onDone)
local function settle(ow)
  local guard = 0
  while Game.stack:top() ~= ow and guard < 240 do
    guard = guard + 1
    frame({})
  end
end

check(PartyMenu.isOpaque == true, "PartyMenu is opaque, so it can be the backdrop")

-- =====================================================================
-- .strength: PrintStrengthText's two pages, then the blink
-- =====================================================================
Game.save.party = { mkMon("MACHOP", "STRENGTH") }
Game.save.inventory = { RAINBOWBADGE = true }
local ow = pushOW("SEAFOAM_ISLANDS_1F", 17, 10, "right")
local pmStr = PartyMenu.new(Game)
selectSubItem(pmStr, 3)
check(isText(Game.stack:top()), "STRENGTH opens _UsedStrengthText")
eq(backdrop(), pmStr, "the party menu is the backdrop of _UsedStrengthText")
drainOne()
check(isText(Game.stack:top()), "_CanMoveBouldersText follows")
eq(backdrop(), pmStr, "the party menu is still the backdrop of the second page")
drainOne()
check(isBlink(Game.stack:top()), "the blink comes after both pages")
eq(backdrop(), Game.stack:top(), "the blink is the top state, never under a message")
settle(ow)
eq(Game.stack:top(), ow, "STRENGTH ends on the map")

-- =====================================================================
-- .surf: ItemUseSurfboard's got-on text, then the blink that carries the
-- mount forward (#320 put the blink under the text, which is what left
-- the white rect as the backdrop)
-- =====================================================================
Game.save.party = { mkMon("SQUIRTLE", "SURF") }
Game.save.inventory = { SOULBADGE = true }
ow = pushOW("PALLET_TOWN", 4, 13, "down")
ow.player.surfing = false
local pmSurf = PartyMenu.new(Game)
selectSubItem(pmSurf, 3)
check(isText(Game.stack:top()), "SURF opens _SurfingGotOnText")
eq(backdrop(), pmSurf, "the party menu is the backdrop of _SurfingGotOnText")
drainOne()
check(isBlink(Game.stack:top()), "the blink follows the got-on text")
eq(ow.player.surfing, true, "the mount happens with the blink, not before the text")
settle(ow)
eq(Game.stack:top(), ow, "SURF ends on the map")

-- =====================================================================
-- .cannotStopSurfing: prints and still closes, same layering
-- =====================================================================
ow = pushOW("PALLET_TOWN", 4, 15, "down")
ow.player.surfing = true
local pmNoOff = PartyMenu.new(Game)
selectSubItem(pmNoOff, 3)
check(isText(Game.stack:top()), "a blocked dismount opens _SurfingNoPlaceToGetOffText")
eq(backdrop(), pmNoOff, "the party menu is the backdrop of the no-place message")
drainOne()
check(isBlink(Game.stack:top()), "the blink follows the no-place message")
settle(ow)
eq(Game.stack:top(), ow, "the blocked dismount ends on the map")
ow.player.surfing = false

-- =====================================================================
-- .flash: `xor a / ld [wMapPalOffset], a` is undone before PrintText in
-- the asm, but the map is not on screen then -- the party menu is -- so
-- the lit cave may only appear once the blink hands the screen back.
-- The lighting itself happens as the message closes the menu, ahead of
-- the blink like the asm: in ADVANCED that call rebakes every resident
-- map, and behind the blink's completion that cost was spent with a
-- blank white frame as the newest thing on screen (#610).
-- =====================================================================
Game.save.flashLit = false
Game.save.party = { mkMon("PIKACHU", "FLASH") }
Game.save.inventory = { BOULDERBADGE = true }
ow = pushOW("ROCK_TUNNEL_1F", 15, 4, "down")
eq(ow.dark, true, "ROCK_TUNNEL_1F loads dark before FLASH")
local pmFlash = PartyMenu.new(Game)
selectSubItem(pmFlash, 3)
check(isText(Game.stack:top()), "FLASH opens _FlashLightsAreaText")
eq(backdrop(), pmFlash, "the party menu is the backdrop of _FlashLightsAreaText")
eq(ow.dark, true, "the tunnel is still dark while the message is up")
drainOne()
check(isBlink(Game.stack:top()), "the blink follows the FLASH message")
-- lit before the blink is pushed, so no rebuild can run while the white
-- frame is the newest one presented (#610); the blink hides it either way
eq(ow.dark, false, "the tunnel is lit by the time the blink starts")
settle(ow)
eq(Game.stack:top(), ow, "FLASH ends on the map")
eq(ow.dark, false, "the tunnel is lit once the blink hands the map back")
eq(Game.save.flashLit, true, "FLASH is recorded on the save")

popAll()
S.finish()
