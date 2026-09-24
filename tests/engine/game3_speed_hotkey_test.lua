package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check, eq = T.check, T.eq

local Input = require("src.core.Input")
local GamepadMap = require("src.core.GamepadMap")
local Game = require("src.core.Game")
local Game3 = require("src.core.Game3")

local battleActive = false
package.loaded["src.core.game3.battle"] = { isActive = function() return battleActive end }
local stackBusy = false
package.loaded["src.ui.game3.stack"] = { busy = function() return stackBusy end, clear = function() end }

local function newGame3(phase)
  local g = setmetatable({
    phase = phase or "field",
    options = { speedOverworld = 1, speedBattle = 1, speedMenu = 1 },
    input = Input,
    writeOptions = function() end,
  }, { __index = Game3 })
  return g
end

Input:init()
Input:applyBindings(nil)

do
  local g = newGame3("field")
  stackBusy = true
  eq(g:speedCategory(), "overworld", "menu over the field inherits overworld")
  g:keypressed("1")
  eq(g.options.speedOverworld, 2, "1 with a field menu open bumps OVERWORLD SPEED")
  eq(g.options.speedMenu, 1, "1 with a field menu open leaves MENU SPEED alone")
  stackBusy = false
  eq(g:logicSpeed(), 2, "walk speed sticks after the menu closes")
  battleActive = true
  eq(g:speedCategory(), "battle", "battle stays battle")
  battleActive = false
  eq(newGame3("boot"):speedCategory(), "menu", "boot phase stays menu")
  eq(newGame3("quest_log"):speedCategory(), "menu", "quest log stays menu")
end

do
  local g = newGame3("field")
  g:keypressed("kp1")
  eq(g.options.speedOverworld, 2, "numpad 1 cycles speed")
  local realKb = love.keyboard
  love.keyboard = setmetatable({
    getScancodeFromKey = function(key) return key == "&" and "1" or key end,
  }, { __index = realKb })
  g:keypressed("&")
  eq(g.options.speedOverworld, 3, "AZERTY top-row 1 cycles speed by scancode")
  love.keyboard = realKb
  eq(Input.hotkeyKey("kp3"), "3", "numpad 3 normalizes")
  eq(Input.hotkeyKey("kp4"), "4", "numpad 4 normalizes")
  eq(Input.hotkeyKey("z"), "z", "letters pass through")
end

do
  Input:applyBindings({
    left = { key = "kp4" }, down = { key = "kp2" }, up = { key = "kp8" },
    right = { key = "kp6" }, a = { key = "&" }, b = { key = "kp1" },
  })
  local realKb = love.keyboard
  love.keyboard = setmetatable({
    getScancodeFromKey = function(key) return key == "&" and "1" or key end,
  }, { __index = realKb })
  eq(Input.hotkeyKey("kp4"), "kp4", "numpad 4 bound to LEFT is not a hotkey")
  eq(Input.hotkeyKey("kp2"), "kp2", "numpad 2 bound to DOWN is not a hotkey")
  eq(Input.hotkeyKey("&"), "&", "AZERTY & bound to A is not a hotkey")
  eq(Input.hotkeyKey("kp3"), "3", "unbound numpad 3 is still a hotkey")
  Input:reset()
  local g = newGame3("field")
  g:keypressed("kp4")
  Input:step()
  check(Input:isDown("left"), "numpad 4 bound to LEFT walks left in FRLG")
  g:keyreleased("kp4")
  g:keypressed("kp1")
  eq(g.options.speedOverworld, 1, "numpad 1 bound to B leaves speed alone")
  Input:step()
  check(Input:isDown("b"), "numpad 1 bound to B presses B")
  g:keyreleased("kp1")
  g:keypressed("&")
  eq(g.options.speedOverworld, 1, "AZERTY & bound to A leaves speed alone")
  Input:step()
  check(Input:isDown("a"), "AZERTY & bound to A presses A")
  g:keyreleased("&")
  love.keyboard = realKb
  Input:applyBindings(nil)
  Input:reset()
end

do
  local trigger = Input:triggerAxis("triggerright", 1)
  eq(Input:padAction(trigger), "speedUp", "RT axis name resolves to speedUp")
  Input:triggerAxis("triggerright", 0)
  local left = Input:triggerAxis("triggerleft", 1)
  eq(Input:padAction(left), "speedDown", "LT axis name resolves to speedDown")
  Input:triggerAxis("triggerleft", 0)
  eq(GamepadMap.DEFAULT_PAD_ACTIONS.righttrigger, nil, "no legacy trigger key in defaults")
end

do
  Input:reset()
  local g = newGame3("field")
  g:gamepadaxis(nil, "triggerright", 1)
  eq(g.options.speedOverworld, 2, "gen3 RT bumps speed")
  g:gamepadaxis(nil, "triggerright", 0)
  g:gamepadaxis(nil, "triggerleft", 1)
  eq(g.options.speedOverworld, 1, "gen3 LT lowers speed")
  g:gamepadaxis(nil, "triggerleft", 0)
  g:gamepadpressed(nil, "rightshoulder")
  eq(g.options.speedOverworld, 1, "gen3 R shoulder never changes speed")
  Input:step()
  check(Input:isDown("r"), "gen3 R shoulder still presses R")
  g:gamepadreleased(nil, "rightshoulder")
end

do
  Input:applyBindings({ speedUp = { pad = "y" } })
  Input:reset()
  local g = newGame3("field")
  g:gamepadpressed(nil, "y")
  eq(g.options.speedOverworld, 2, "gen3 honors a SPEED + rebind to Y")
  g:gamepadreleased(nil, "y")
  Input:applyBindings({ speedUp = { pad = "righttrigger" }, a = { pad = "lefttrigger" } })
  eq(Input:padAction("triggerright"), "speedUp", "legacy righttrigger speed rebind still lands")
  eq(Input.padBindings.triggerleft, "a", "legacy lefttrigger button rebind still lands")
  Input:applyBindings(nil)
end

do
  local g1 = setmetatable({ save = { options = { speedOverworld = 1 } }, stack = { states = {}, top = function() return nil end },
    writeOptions = function() end }, { __index = Game })
  Input:reset()
  g1:gamepadaxis(nil, "triggerright", 1)
  eq(g1.save.options.speedMenu, 2, "Gen 1 RT reaches _cycleSpeed")
  g1:gamepadaxis(nil, "triggerright", 0)
end

do
  local g = newGame3("field")
  g.speedOverride = 8
  g.options.speedOverworld = 4
  eq(g:logicSpeed(), 8, "override applies off-link")
  package.loaded["src.core.game3.link"] = { link = {} }
  eq(g:logicSpeed(), 1, "gen3 link play is locked to 1X")
  package.loaded["src.core.game3.link"] = { link = nil }
  package.loaded["src.core.game3.minigames.common"] = { isActive = function() return true end }
  eq(g:logicSpeed(), 1, "gen3 minigames are locked to 1X")
  package.loaded["src.core.game3.minigames.common"] = { isActive = function() return false end }
  g.phase = "arena"
  eq(g:logicSpeed(), 1, "gen3 arena is locked to 1X")
  package.loaded["src.core.game3.link"] = nil
  package.loaded["src.core.game3.minigames.common"] = nil
end

T.finish()
