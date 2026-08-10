-- The touch-controls editor is launcher-owned application UI even though it
-- temporarily replaces the launcher screen.  It must follow Interface
-- Language without translating the physical A/B/START/SELECT button names.
package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")

local T = require("tests.harness")
local check = T.check
local AppLocale = require("src.core.AppLocale")
local SaveData = require("src.core.SaveData")

local oldLoad, oldSave = SaveData.loadOptions, SaveData.saveOptions
SaveData.loadOptions = function()
  return { interfaceLocale = "es-ES", touchControls = { enabled = true } }
end
SaveData.saveOptions = function() end

AppLocale.set("es-ES")
package.loaded["src.ui.TouchControlsEditor"] = nil
local Editor = require("src.ui.TouchControlsEditor")
Editor.load()

local seen = {}
local realPrint, realPrintf = love.graphics.print, love.graphics.printf
love.graphics.print = function(text, ...)
  seen[#seen + 1] = tostring(text)
  return realPrint(text, ...)
end
love.graphics.printf = function(text, ...)
  seen[#seen + 1] = tostring(text)
  return realPrintf(text, ...)
end
local ok, err = pcall(Editor.draw)
love.graphics.print, love.graphics.printf = realPrint, realPrintf
Editor.unload()
SaveData.loadOptions, SaveData.saveOptions = oldLoad, oldSave

check(ok, "the localized touch editor draws: " .. tostring(err))
local text = table.concat(seen, "\n")
for _, expected in ipairs({
  "Controles táctiles",
  "Restablecer",
  "Listo",
  "Controles en pantalla",
  "SÍ",
  "Desactivar",
  "Tamaño de los botones (Horizontal)",
  "Arrastra cada botón para moverlo",
}) do
  check(text:find(expected, 1, true) ~= nil,
    "touch editor prints localized text: " .. expected)
end
check(text:find("Touch Controls", 1, true) == nil,
  "touch editor does not leak its English title in Spanish")
check(text:find("On-screen controls", 1, true) == nil,
  "touch editor does not leak its English toggle label in Spanish")

AppLocale.set("en")
T.finish("touch_controls_locale")
