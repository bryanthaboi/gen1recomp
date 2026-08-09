-- Native application locale behavior. This is deliberately separate from the
-- mod strings registry: Interface Language must never translate gameplay.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local AppLocale = require("src.core.AppLocale")
local AppMessage = require("src.core.AppMessage")
local Strings = require("src.core.Strings")
local SaveData = require("src.core.SaveData")
local Logger = require("src.core.Logger")
local Spanish = require("src.locales.es_es")
local S = require("tests.harness").suite("application locale")
local check, eq = S.check, S.eq

AppLocale.set("en")
eq(AppLocale.get(), "en", "English is the default/source locale")
eq(AppLocale("Settings"), "Settings", "English source is unchanged")
eq(AppLocale.displayName("en"), "English", "English is self-identifying")

-- Startup bootstrap uses the already-loaded global options table and writes
-- the canonical id back into it, so the next normal options save upgrades old
-- development values without a separate migration.
do
  local opts = { interfaceLocale = "es-ES" }
  eq(AppLocale.applyOptions(opts), "es-ES", "bootstrap applies the persisted Spanish locale")
  eq(AppLocale.get(), "es-ES", "persisted locale is active before UI lookup")
  eq(opts.interfaceLocale, "es-ES", "canonical Spanish id is retained")

  local english = { interfaceLocale = "en" }
  eq(AppLocale.applyOptions(english), "en", "bootstrap applies the English locale")
  eq(english.interfaceLocale, "en", "canonical English id is retained")

  local missing = {}
  eq(AppLocale.applyOptions(missing), "en", "missing startup locale falls back to English")
  eq(missing.interfaceLocale, "en", "missing startup locale is normalized in options")
end

AppLocale.set("es-ES")
eq(AppLocale.get(), "es-ES", "Spanish can be selected")
eq(AppLocale("Interface Language"), "Idioma de la interfaz",
   "the setting is explicitly Interface Language")
eq(AppLocale.displayName("es-ES"), "Español", "Spanish display name is native")
eq(AppLocale("RED"), "ROJO", "launcher navigation uses the application locale")
eq(AppLocale("Play %s", "Pokémon Rojo"), "Jugar a Pokémon Rojo",
   "launcher action labels preserve their dynamic game name")
eq(AppLocale("Settings"), "Ajustes", "launcher settings use the application locale")
eq(AppLocale("Name save slot"), "Nombre de la ranura de guardado",
   "save-slot prompts use the application locale")
eq(AppLocale("Imported save into %s.", "slot-2"), "Partida importada en slot-2.",
   "save import notices preserve their slot id")
eq(AppLocale("Oversized save file"), "Archivo de guardado demasiado grande",
   "oversized-save confirmation uses the application locale")
eq(AppLocale("%d slots", 3), "3 ranuras", "save-slot counts use the application locale")
eq(AppLocale("Deleted %s.", "slot1"), "Se ha eliminado «slot1».",
   "save deletion notices avoid redundant slot wording")
eq(AppLocale("empty slot"), "sin partida guardada",
   "an empty named slot explains that no game has been saved")
eq(AppLocale("Touch Controls"), "Controles táctiles",
   "the application-owned touch editor follows Interface Language")
eq(AppLocale("Button size (%s)", AppLocale("Landscape")),
   "Tamaño de los botones (Horizontal)",
   "touch-editor dynamic orientation labels remain localized")
eq(AppLocale("B"), "Az", "Spanish blue tab has an unambiguous abbreviation")
eq(AppLocale("Y"), "Am", "Spanish yellow tab has an unambiguous abbreviation")
eq(AppLocale("Untranslated application source"), "Untranslated application source",
   "missing application strings fall back to English")
local message = AppMessage("Needs mod API %d; this build provides %d", 4, 2)
eq(tostring(message), "Needs mod API 4; this build provides 2",
  "locale-neutral messages remain readable to logs and tools")
eq(AppLocale.message(message),
  "Necesita la API de mods 4; esta versión proporciona la 2",
  "presentation edges translate locale-neutral messages")
check(AppLocale.formatCompatible("Size %.2f MiB", "Tamaño %.1f MiB"),
  "format safety accepts translated precision changes with the same conversion")
check(not AppLocale.formatCompatible("Size %.2f MiB", "Tamaño %.2s MiB"),
  "format safety detects conversion changes after precision")
check(AppLocale.formatCompatible("Progress 100%%: %05d", "Progreso 100%%: %d"),
  "format safety ignores escaped percent signs and display width")

-- Runtime formatting is fail-safe.  Inject one deliberately malformed catalog
-- row through the same table AppLocale owns, then remove it so the committed
-- catalog stays clean.  The user sees the English source; the developer gets
-- one English diagnostic rather than a localized/unsearchable log line.
do
  local source = "%d files"
  Spanish.strings[source] = "%s archivos"
  local before = #Logger.history
  eq(AppLocale(source, 3), "3 files",
    "incompatible format directives fall back to the English source")
  check(#Logger.history > before, "format mismatch emits a developer diagnostic")
  local line = Logger.history[#Logger.history] or ""
  check(line:find("app locale: translation of", 1, true) ~= nil,
    "locale diagnostics remain in English")
  Spanish.strings[source] = nil
end

local beforeGeneration = AppLocale.generation()
AppLocale.set("en")
check(AppLocale.generation() > beforeGeneration,
  "switching locale increments the generation for live UI invalidation")

AppLocale.set("does-not-exist")
eq(AppLocale.get(), "en", "unknown locale falls back safely to English")
eq(AppLocale.displayName("does-not-exist"), "English",
   "unknown locale has a safe display name")

eq(AppLocale.cycle("en", 1), "es-ES", "locale cycle reaches Spanish")
eq(AppLocale.cycle("es-ES", 1), "en", "locale cycle wraps to English")

-- Settings integration: options.lua is the persistence boundary.  The
-- LauncherSettings model mutates that table in place; LauncherView calls
-- model.save() after a successful step, so this exercises the same contract
-- without touching a real save directory.
do
  local oldLoad, oldSave = SaveData.loadOptions, SaveData.saveOptions
  local stored = { interfaceLocale = "en" }
  local saved
  SaveData.loadOptions = function() return stored end
  SaveData.saveOptions = function(opts) saved = opts end

  package.loaded["src.import.LauncherSettings"] = nil
  local LauncherSettings = require("src.import.LauncherSettings")
  local model = LauncherSettings.open()
  local row = model.sections[1].rows[1]

  eq(row.label, "Interface Language", "Settings exposes Interface Language")
  eq(row.value(), "English", "Settings reflects the selected English locale")
  check(row.step(1), "Interface Language can be changed")
  eq(stored.interfaceLocale, "es-ES", "the selected locale is stored in global options")
  eq(row.value(), "Español", "the language value is self-identifying")
  local rebuilt = LauncherSettings.open()
  eq(rebuilt.sections[1].rows[1].label, "Idioma de la interfaz",
    "the settings model rebuild reflects the switched locale")
  model.save()
  check(saved == stored, "Settings persists the same options table")
  eq(saved.interfaceLocale, "es-ES", "Spanish survives the persistence boundary")

  SaveData.loadOptions, SaveData.saveOptions = oldLoad, oldSave
  package.loaded["src.import.LauncherSettings"] = nil
end

-- A gameplay translation mod may own the global Strings catalog.  Launcher
-- settings must still follow Interface Language instead of leaking those
-- gameplay translations into an English application UI.
do
  local oldLoad, oldSave = SaveData.loadOptions, SaveData.saveOptions
  local stored = { interfaceLocale = "en", textSpeed = 3 }
  SaveData.loadOptions = function() return stored end
  SaveData.saveOptions = function() end
  Strings.load({ ["TEXT SPEED"] = "VEL TEXTO", ["MEDIUM"] = "MEDIA MOD" })
  AppLocale.set("en")

  package.loaded["src.import.LauncherSettings"] = nil
  local LauncherSettings = require("src.import.LauncherSettings")
  local model = LauncherSettings.open()
  eq(model.localeGeneration, AppLocale.generation(),
    "settings model records the locale generation used to build its labels")
  eq(model.sections[1].rows[2].label, "TEXT SPEED",
    "English launcher settings ignore gameplay string overrides")
  eq(model.sections[1].rows[2].value(), "MEDIUM",
    "English launcher values ignore gameplay string overrides")

  stored.interfaceLocale = "es-ES"
  AppLocale.set("es-ES")
  package.loaded["src.import.LauncherSettings"] = nil
  LauncherSettings = require("src.import.LauncherSettings")
  model = LauncherSettings.open()
  eq(model.localeGeneration, AppLocale.generation(),
    "rebuilt settings model records the new locale generation")
  eq(model.sections[1].rows[2].label, "VEL. DEL TEXTO",
    "Spanish launcher settings follow the application locale")
  eq(model.sections[1].rows[2].value(), "MEDIA",
    "Spanish launcher values follow the application locale")
  local values = {}
  for _, row in ipairs(model.sections[1].rows) do
    if row.value then values[row.label] = row.value() end
  end
  eq(values["RENDIMIENTO"], "AUTOMÁTICO",
    "module-provided performance values use the application locale")
  eq(values["COLORES"], "SGB",
    "module-provided palette values pass through the application catalog")
  eq(values["MODO DE VÍDEO"], "VENTANA",
    "module-provided video-mode values use the application locale")
  eq(values["VELOCIDAD DEL JUEGO"], "NORMAL",
    "module-provided game-speed values use the application locale")

  Strings.load({})
  SaveData.loadOptions, SaveData.saveOptions = oldLoad, oldSave
  package.loaded["src.import.LauncherSettings"] = nil
end

-- Opening Settings with an unknown value normalizes it to English rather than
-- exposing an invalid locale or crashing an old/new options.lua combination.
do
  local oldLoad, oldSave = SaveData.loadOptions, SaveData.saveOptions
  local stored = { interfaceLocale = "xx-INVALID" }
  SaveData.loadOptions = function() return stored end
  SaveData.saveOptions = function() end

  package.loaded["src.import.LauncherSettings"] = nil
  local LauncherSettings = require("src.import.LauncherSettings")
  local model = LauncherSettings.open()
  eq(model.opts.interfaceLocale, "en", "unknown persisted locale normalizes to English")
  eq(model.sections[1].rows[1].value(), "English",
    "Settings shows the safe English fallback for an unknown locale")

  SaveData.loadOptions, SaveData.saveOptions = oldLoad, oldSave
  package.loaded["src.import.LauncherSettings"] = nil
end

-- The boundary regression: changing Interface Language must not load or alter
-- the global Strings/Data.strings catalog used by gameplay/translation mods.
Strings.load({})
AppLocale.set("es-ES")
check(not Strings.active(), "application locale does not activate gameplay Strings")
eq(Strings("Wild %s\nappeared!", "PIDGEY"), "Wild PIDGEY\nappeared!",
   "gameplay Strings remain English when only Interface Language is Spanish")

AppLocale.set("en")
S.finish()
