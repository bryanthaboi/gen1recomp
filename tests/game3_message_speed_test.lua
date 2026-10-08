package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local GameVersion = require("src.core.GameVersion")
local Runtime = require("src.core.game3.runtime")
local Options = require("src.core.game3.options")
local Message = require("src.ui.game3.message")
local Hud = require("src.ui.game3.hud")
local TextIR = require("src.core.game3.scripting.text_ir")
local input = {
  wasPressed = function(_, key) return key == "a" end,
  isDown = function() return false end,
}
local game = { input = input }
local ir = TextIR.fromAscii("First paragraph.\\pSecond paragraph.")

local function exercise(version, speed, text)
  GameVersion.set(version)
  local session = { version = version }
  Runtime.session = session
  Options.set(session, "textSpeed", speed)
  Message.showStay(text)
  T.check(Message.isTyping() and Message._page == 1 and Message._revealed == 0,
    version .. " implicit option " .. speed .. " starts typing first paragraph")
  local first = Message.currentPage()
  Message.tick()
  Hud.update(game, 1 / 60)
  T.eq(Message._page, 1, version .. " opening A preserves first paragraph at option " .. speed)
  T.eq(Message.currentPage(), first, "opening A keeps first paragraph text")
  T.check(Message.isTyping() and Message._revealed == 1, "opening A leaves first paragraph typing")
  T.check(not Message._spedUp, "opening A does not arm the print speed-up")
  for _ = 1, 2000 do
    if Message.isWaiting() then break end
    Message.tick()
  end
  T.check(Message.isWaiting(), "first paragraph finishes printing")
  Message.advance()
  T.eq(Message._page, 2, "fresh A advances exactly once")
  T.check(Message.isTyping(), "second paragraph starts typing")
  Message.close()
end

for _, version in ipairs({ "firered", "leafgreen", "emerald" }) do
  for speed = 0, 2 do
    exercise(version, speed, ir)
    Message.showStay("ABC")
    Message.tick()
    T.eq(Message._revealed, 1, "first glyph prints on first tick")
    local delay = ({ 8, 4, 1 })[speed + 1]
    for _ = 1, delay - 1 do Message.tick() end
    T.eq(Message._revealed, 1, version .. " no-input glyph interval " .. delay)
    Message.tick()
    T.eq(Message._revealed, 2, version .. " next glyph after " .. delay .. " ticks")
    Message.showStay("ABCDEFGH")
    local held = {
      wasPressed = function() return false end,
      isDown = function(_, key) return key == "a" end,
    }
    Message.tick()
    Hud.update({ input = held }, 1 / 60)
    Message.tick()
    Message.tick()
    T.eq(Message._revealed, delay > 1 and 1 or 3, version .. " held A without a fresh press keeps option " .. speed .. " pacing")
    if delay > 1 then
      Hud.update(game, 1 / 60)
      T.check(Message._spedUp, version .. " fresh A during a glyph delay arms the speed-up")
      Message.tick()
      T.eq(Message._revealed, 2, version .. " fresh A skips the rest of that glyph delay")
      Hud.update({ input = held }, 1 / 60)
      Message.tick()
      T.eq(Message._revealed, 3, version .. " held A after the fresh press prints a glyph per frame")
    end
    Message.showStay(ir, { speed = 0 })
    T.check(Message.isWaiting() and Message._revealed == Message._total,
      version .. " explicit speed zero stays instant at option " .. speed)
    Message.close()
  end
end

GameVersion.set("firered")
local bundle = require("tests.game3_cache").bundle("scripts/events.lua")
if bundle then
  local event = assert(bundle.events.FR_VIRIDIAN_CITY_POKEMON_CENTER_1F)
  for _, npc in ipairs({ { id = 2, name = "Viridian gentleman" }, { id = 3, name = "Viridian boy" } }) do
    local scriptKey
    for _, object in ipairs(event.objects) do
      if object.localId == npc.id then scriptKey = object.scriptKey break end
    end
    local script = assert(bundle.scripts[assert(scriptKey, npc.name .. " event script")])
    local command = assert(script[1])
    assert(command.op == "loadword" and command.dest == 0, npc.name .. " cached message pointer")
    local text = assert(bundle.text[command.value], npc.name .. " cached text IR")
    T.eq(#TextIR.splitPages(TextIR.toTextBox(text, { maxWidth = 208 })), 2,
      npc.name .. " cached literal text has two paragraphs")
    exercise("firered", 0, text)
  end
else
  print("[skip] cached ROM message acceptance: " .. tostring(require("tests.game3_cache").reason))
end
T.finish("game3_message_speed")
