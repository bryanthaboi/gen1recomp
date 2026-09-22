-- The naming screen must follow the stack's update convention.
--
-- G4 regression: Hud.update ticks the stack top with `pcall(top.mod.update, dt)`,
-- but Naming's signature is `Naming.update(input, dt)` -- so the delta arrived as
-- `input` and `input.wasPressed` raised on a number, every frame the naming
-- screen was on top.  Hud's pcall swallowed it, so the fault was invisible and
-- input never reached the screen through Hud (Runtime passed it correctly, which
-- is why only Hud's path was broken).
--
-- Convention (Hud.update_top_menu prefers it): menus expose handleInput(input)
-- and update(dt).  This pins both halves.
--   luajit tests/engine/game3_naming_update_contract_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Stack = require("src.ui.game3.stack")
local Naming = require("src.ui.game3.naming")
local Hud = require("src.ui.game3.hud")

local function open_naming()
  local st = {
    title = "YOUR NAME?", maxLen = 7, name = "", page = 1,
    row = 1, col = 1, btn = 1, blink = 0, swapT = nil,
  }
  Naming._state = st
  Naming.openFlag = true
  Stack.push("naming", Naming, { hideBelow = true })
  return st
end

local function input(pressed)
  return {
    wasPressed = function(_, k) return pressed[k] == true end,
    isDown = function() return false end,
  }
end

-- 1. update takes the delta alone (the arity Hud uses).
local st = open_naming()
local ok, err = pcall(Naming.update, 1 / 60)
check(ok, "Naming.update(dt) is callable with just a delta (" .. tostring(err) .. ")")
eq(st.blink, 1 / 60, "update advances the blink timer")

-- 2. Input reaches the screen through Hud's stack tick.
local st2 = open_naming()
st2.row = 1
Hud.update({ input = input({ down = true }) }, 1 / 60)
eq(st2.row, 2, "a 'down' press reaches naming through Hud.update")

-- 3. handleInput is the input entry point and accepts the frame input.
local st3 = open_naming()
check(pcall(Naming.handleInput, input({})), "Naming.handleInput accepts an input object")

-- 4. The swap-animation guard still suppresses input (the original early return).
local st4 = open_naming()
st4.row = 1
st4.swapT = 0
pcall(Naming.handleInput, input({ down = true }))
eq(st4.row, 1, "input is ignored while the page swap is running")

-- The real runtime must leave stack input and timers to Hud in both branches.
local Runtime = require("src.core.game3.runtime")
local Battle = require("src.core.game3.battle")
Runtime.active = true
Runtime.session = {}
for _, inBattle in ipairs({ false, true }) do
  Battle._active = inBattle
  local active = open_naming()
  Runtime._game = { input = input({ a = true }) }
  Runtime.update(1 / 60)
  eq(active.name, "A", "one runtime press adds one character, battle=" .. tostring(inBattle))
  eq(active.blink, 1 / 60, "runtime advances the naming timer once")
  active.pcPages = { "first", "second", "third" }
  active.pcPage = 1
  Runtime.update(1 / 60)
  eq(active.pcPage, 2, "one runtime press advances one result page")
  local swapping = open_naming()
  swapping.swapT = 124
  swapping.swapTo = 2
  Runtime.update(1 / 60)
  eq(swapping.name, "", "input remains blocked on the swap-completion frame")
  eq(swapping.swapT, nil, "the page swap finishes")
  Runtime.update(1 / 60)
  eq(swapping.name, "a", "the next frame accepts input on the new page")
end
Battle._active = false
Stack.clear()
-- A prompt that opens Naming during the battle update must consume its A.
Battle._active = true
local battleUpdate = Battle.update
local opened
Battle.update = function() opened = open_naming() end
Runtime._game = { input = input({ a = true }) }
Runtime.update(1 / 60)
eq(opened.name, "", "the opening prompt's A does not type a character")
Battle.update = battleUpdate
Runtime.update(1 / 60)
eq(opened.name, "A", "the following frame's A reaches naming")
Battle._active = false
Runtime.active = false
Stack.clear()

T.finish("game3_naming_update_contract_test")
