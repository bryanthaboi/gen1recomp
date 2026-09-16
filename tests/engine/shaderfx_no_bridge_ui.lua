
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

package.loaded["src.render.Font"] = {
  BORDER = { tl = 1, tr = 2, bl = 3, br = 4, h = 5, v = 6 },
  draw = function() end,
  drawCode = function() end,
  drawBox = function() end,
  width = function(text) return #tostring(text) * 8 end,
  split = function(text)
    local spans = {}
    for i = 1, #tostring(text) do spans[i] = { from = i, to = i, code = 0 } end
    return spans
  end,
  spansFitting = function(spans, pixels) return math.min(#spans, math.floor(pixels / 8)) end,
}
package.loaded["src.core.Logger"] = {
  info = function() end,
  error = function() end,
  warn = function() end,
}
package.loaded["src.core.Sound"] = { play = function() end }

local converts = {}
local activated = {}
local recorded = {}
local trace = {}
local fake
fake = {
  OPTION_KEY = { main = "shaderfx", secondary = "shaderfx2" },
  canConvert = function() trace[#trace + 1] = "canConvert"; return fake.can end,
  recordError = function(name, err) recorded[#recorded + 1] = tostring(name) .. ": " .. tostring(err) end,
  bridgeError = function() return fake.can and nil or "librashader bridge not found" end,
  list = function()
    return {
      { name = "bevel.slangp", converted = true },
      { name = "zfast-lcd.slangp", converted = false },
    }
  end,
  activeEntry = function() return nil end,
  convert = function(entry)
    converts[#converts + 1] = entry.name
    return fake.convertOk, fake.convertOk and nil or "no bridge"
  end,
  activate = function(_, entry) activated[#activated + 1] = entry.name; return true end,
  deactivate = function() end,
  clearBridgeQuarantine = function() trace[#trace + 1] = "clear" end,
  downloadPresets = function() return {} end,
  downloadStatus = function() return { status = "pending" } end,
  installDownloaded = function() return 0 end,
}
package.loaded["src.render.ShaderFX"] = fake

local ShaderFXScreen = require("src.ui.ShaderFXScreen")

local function newGame()
  return {
    input = { wasPressed = function() return false end },
    stack = { top = function() end, pop = function() end },
    save = { options = {} },
    writeOptions = function() end,
  }
end

local function open()
  converts, activated, recorded, trace = {}, {}, {}, {}
  return ShaderFXScreen.new(newGame(), "main")
end

fake.can, fake.convertOk = false, false
local screen = open()
eq(trace[1], "clear", "a stale bridge quarantine is cleared before the picker asks canConvert")
eq(trace[2], "canConvert", "and canConvert is what follows the clear")
eq(screen.items[3].right, "UPDATE", "an unconvertible preset says what would fix it")
check(#screen.items[3].right <= #"CONVERT",
  "the no-bridge label leaves at least as much room for the name as CONVERT")
eq(screen.items[2].right, nil, "an already-converted preset keeps its bare row")
screen.onChoose(screen.items[3])
eq(#converts, 0, "A on that row never calls convert")
check(screen.footer and screen.footer:find("Reinstall", 1, true) ~= nil,
  "the footer names the fix (got " .. tostring(screen.footer) .. ")")
check(screen.footer:find("\n", 1, true) == nil and #screen.footer <= 18,
  "the footer stays one 18-column line, so it cannot paint over list row 7")
eq(screen.items[3].right, "UPDATE", "the row keeps its label instead of reading FAILED")

screen.onChoose(screen.items[2])
eq(#converts, 0, "activating a converted preset skips the reconvert with no bridge")
eq(activated[1], "bevel.slangp", "the cached artifact still activates")

fake.can, fake.convertOk = true, true
screen = open()
eq(screen.items[3].right, "CONVERT", "a build with the bridge still offers CONVERT")
screen.onChoose(screen.items[3])
eq(converts[1], "zfast-lcd.slangp", "A on that row converts")
eq(screen.footer, "SELECT:EDIT PARAMS", "a convertible build keeps the hint footer")

fake.convertOk = false
screen = open()
screen.onChoose(screen.items[3])
eq(screen.items[3].right, "FAILED", "a real convert failure still reads FAILED")
eq(recorded[1], "zfast-lcd.slangp: no bridge",
  "and the real error string reaches shaderfx-error.log, not just log.txt")

do
  fake.can, fake.convertOk = true, true
  local realActivate = fake.activate
  fake.activate = function(_, entry)
    activated[#activated + 1] = entry.name
    return false, "pass0: variant 1 validate: ERROR: 0:9: 'uint' : syntax error"
  end
  local game = newGame()
  local closed, writes = 0, 0
  game.stack.pop = function() closed = closed + 1 end
  game.writeOptions = function() writes = writes + 1 end
  game.save.options.shaderfx = "bevel.slangp"
  converts, activated = {}, {}
  local s = ShaderFXScreen.new(game, "main")
  s.close = function() closed = closed + 1 end
  s.onChoose(s.items[2])
  eq(activated[1], "bevel.slangp", "A on a converted row tries to activate it")
  eq(s.items[2].right, "FAILED", "a preset the device's compiler rejects reads FAILED on its row")
  eq(game.save.options.shaderfx, nil, "and the option is not persisted as on")
  eq(writes, 1, "the cleared option is written back")
  eq(closed, 0, "the picker stays open so the player sees the verdict")
  fake.activate = realActivate
end

T.finish("shaderfx no-bridge picker")
