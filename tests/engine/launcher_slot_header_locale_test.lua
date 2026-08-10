-- Localized save-slot header reflow.  This is application chrome and needs no
-- ROM: long fixture strings stand in for a future locale without registering
-- or shipping another language.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check = T.check
love = require("tests.love_stub")

love.graphics.setLineJoin = love.graphics.setLineJoin or function() end
love.graphics.newShader = love.graphics.newShader or function() return {} end

local AppLocale = require("src.core.AppLocale")
local Spanish = require("src.locales.es_es")
local Kit = require("src.ui.kit.Kit")
local RomImporter = require("src.import.RomImporter")
local LauncherView = require("src.import.LauncherView")

love.graphics.getDimensions = function() return 1280, 720 end
love.graphics.getPixelDimensions = love.graphics.getDimensions

local function freshLauncher()
  local imp = RomImporter.new(function() end, { launcher = true })
  imp.tab = "red"
  imp._ensureSlots = function() end
  imp.slots.red = {
    { id = "slot-a", label = "SLOT A", exists = false },
  }
  imp.activeSlot.red = "slot-a"
  return imp
end

local function inside(rect, card)
  return rect.x >= card.x - 0.5 and rect.y >= card.y - 0.5
    and rect.x + rect.w <= card.x + card.w + 0.5
    and rect.y + rect.h <= card.y + card.h + 0.5
end

local function capture(title, action)
  local imp = freshLauncher()
  LauncherView.draw(imp) -- warm frame: fonts, pagination and caches settle

  local cards, captions, boldLines = {}, {}, {}
  local realCard, realCaption = Kit.card, Kit.caption
  local realCenterBold = Kit.textCenterBold
  Kit.card = function(x, y, w, h, emphasis)
    cards[#cards + 1] = { x = x, y = y, w = w, h = h }
    return realCard(x, y, w, h, emphasis)
  end
  Kit.caption = function(x, y, label, color)
    captions[#captions + 1] = {
      x = x, y = y, w = Kit.captionWidth(label),
      h = Kit.textHeight("caption"), label = tostring(label),
    }
    return realCaption(x, y, label, color)
  end
  Kit.textCenterBold = function(name, label, x, y, w, color, alpha)
    boldLines[#boldLines + 1] = tostring(label)
    return realCenterBold(name, label, x, y, w, color, alpha)
  end
  Kit.audit = {}
  local ok, err = pcall(LauncherView.draw, imp)
  local audit = Kit.audit
  Kit.audit = nil
  Kit.card, Kit.caption = realCard, realCaption
  Kit.textCenterBold = realCenterBold
  check(ok, "localized slot-card frame draws: " .. tostring(err))
  if not ok then return {} end

  local found = { cards = cards }
  for _, rect in ipairs(audit) do
    if rect.class == "control" and rect.label == action then
      found.button = rect
    elseif rect.class == "row" and rect.label == "slot-red-slot-a" then
      found.row = rect
    end
  end
  for _, rect in ipairs(captions) do
    if rect.label == title then found.title = rect end
  end
  for _, line in ipairs(boldLines) do
    if line == action then found.fullActionDrawn = true end
  end
  if found.button and found.row then
    for _, card in ipairs(cards) do
      if inside(found.button, card) and inside(found.row, card) then
        if not found.card or card.w * card.h < found.card.w * found.card.h then
          found.card = card
        end
      end
    end
  end
  return found
end

local function requireRects(frame, label)
  check(frame.title ~= nil, label .. ": full title is drawn")
  check(frame.button ~= nil, label .. ": import button is drawn")
  check(frame.row ~= nil, label .. ": slot row is drawn")
  check(frame.card ~= nil, label .. ": button and row remain in the slot card")
  return frame.title and frame.button and frame.row and frame.card
end

-- Current English stays on the exact compact shape: title and button share
-- the header row, and the list starts below both.
AppLocale.set("en")
local compact = capture("SAVE SLOT", "Import save")
if requireRects(compact, "compact source header") then
  check(compact.title.y < compact.button.y + compact.button.h
      and compact.button.y < compact.title.y + compact.title.h,
    "current short strings keep the one-line header")
  check(compact.row.y >= compact.button.y + compact.button.h,
    "compact header height keeps the slot list below it")
end

-- Inject deliberately long translations into the already registered Spanish
-- catalog for this process only.  Their combined width exceeds the card, but
-- each string fits by itself: this is the future-locale overlap regression.
local oldTitle = Spanish.strings["SAVE SLOT"]
local oldAction = Spanish.strings["Import save"]
local longTitle = "ADMINISTRACIÓN DE PARTIDAS GUARDADAS"
local longAction = "IMPORTAR UNA PARTIDA GUARDADA DESDE UN ARCHIVO"
Spanish.strings["SAVE SLOT"] = longTitle
Spanish.strings["Import save"] = longAction
AppLocale.set("es-ES")

local stacked = capture(longTitle, longAction)
if requireRects(stacked, "long localized header") then
  local pad = stacked.title.x - stacked.card.x
  local innerW = stacked.card.w - 2 * pad
  check(stacked.title.w <= innerW and stacked.button.w <= innerW,
    "each full localized string fits on its own row")
  check(stacked.title.w + stacked.button.w > innerW,
    "fixture genuinely cannot fit title and button on one row")
  check(stacked.button.y >= stacked.title.y + stacked.title.h,
    "long localized action moves below the complete title")
  check(stacked.row.y >= stacked.button.y + stacked.button.h,
    "two-line headH moves the slot list below the import button")
  check(stacked.button.x >= stacked.card.x + pad - 0.5
      and stacked.button.x + stacked.button.w
        <= stacked.card.x + stacked.card.w - pad + 0.5,
    "localized import button stays inside the card")
  check(Kit.textWidth("small", longAction)
      <= stacked.button.w - 16 * Kit.scale,
    "localized import action is not shortened to fit")
end

-- If the action is wider than a whole row, its control is clamped to the
-- card's inner width and uses Kit.button's wrapped-label path instead of
-- escaping the window or requesting an ellipsis.
local hugeAction = "IMPORTAR UNA PARTIDA GUARDADA DESDE UN ARCHIVO EXTERNO "
  .. "DEMASIADO LARGO PARA CABER EN UNA SOLA LÍNEA DE LA TARJETA"
Spanish.strings["Import save"] = hugeAction
local wrapped = capture(longTitle, hugeAction)
if requireRects(wrapped, "oversized localized action") then
  local pad = wrapped.title.x - wrapped.card.x
  local innerW = wrapped.card.w - 2 * pad
  check(Kit.textWidth("small", hugeAction) + math.floor(28 * Kit.scale) > innerW,
    "oversized fixture genuinely exceeds a whole header row")
  check(wrapped.button.w <= innerW + 0.5,
    "oversized import button is bounded by the card interior")
  check(wrapped.button.x >= wrapped.card.x + pad - 0.5
      and wrapped.button.x + wrapped.button.w
        <= wrapped.card.x + wrapped.card.w - pad + 0.5,
    "wrapped import button never leaves the card")
  check(wrapped.row.y >= wrapped.button.y + wrapped.button.h,
    "wrapped button height remains part of headH")
  check(wrapped.fullActionDrawn == true,
    "wrapped import action is drawn in full rather than ellipsized")
end

Spanish.strings["SAVE SLOT"] = oldTitle
Spanish.strings["Import save"] = oldAction
AppLocale.set("en")

T.finish("launcher_slot_header_locale")
