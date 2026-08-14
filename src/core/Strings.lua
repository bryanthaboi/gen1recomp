-- The engine's own player-facing text, made overridable.
-- Extracted dialogue stays in Data.text. This module is only for literals
-- authored by the engine (menus, prompts, option labels, etc.).

local Strings = {}
local catalog = nil
local missing = {}
local spanishFontInstalled = false
local encodeSpanishGlyphs

local SPANISH = {
  ["SAVE"] = "GUARDAR", ["OPTION"] = "OPCIÓN", ["OPTIONS"] = "OPCIONES", ["EXIT GAME"] = "SALIR DEL JUEGO",
  ["LINK"] = "ENLACE", ["QUIT"] = "SALIR", ["ITEM"] = "OBJ.", ["ITEMS"] = "OBJETOS",
  ["POKéDEX"] = "POKéDEX", ["POKéMON"] = "POKéMON", ["MODS"] = "MODS",
  ["YES"] = "SÍ", ["NO"] = "NO", ["CANCEL"] = "CANCELAR", ["CONTINUE"] = "CONTINUAR", ["NEW GAME"] = "JUEGO NUEVO",
  ["TEXT SPEED"] = "VELOCIDAD TEXTO", ["FAST"] = "RÁPIDO", ["MEDIUM"] = "MEDIO", ["SLOW"] = "LENTO",
  ["BATTLE ANIMATION"] = "ANIMACIÓN BATALLA", ["BATTLE STYLE"] = "ESTILO BATALLA", ["SHIFT"] = "CAMBIAR", ["SET"] = "FIJO",
  ["ON"] = "SÍ", ["OFF"] = "NO", ["BATTLE LAYOUT"] = "DISEÑO BATALLA", ["WIDE"] = "AMPLIO", ["OG"] = "CLÁSICO",
  ["BATTLE SIZE"] = "TAMAÑO BATALLA", ["FILL"] = "RELLENO", ["FIXED"] = "FIJO", ["BATTLE BG"] = "FONDO BATALLA",
  ["BLACK"] = "NEGRO", ["WORLD"] = "MUNDO", ["WHITE"] = "BLANCO", ["COLORS"] = "COLORES", ["TILT"] = "INCLINACIÓN",
  ["GBC FX"] = "EFECTOS GBC", ["ZOOM"] = "ZOOM", ["VOID FILL"] = "RELLENO VACÍO", ["VIDEO MODE"] = "MODO VÍDEO",
  ["MUSIC"] = "MÚSICA", ["SFX"] = "EFECTOS", ["MUSIC VOLUME"] = "VOLUMEN MÚSICA", ["SFX VOLUME"] = "VOLUMEN EFECTOS",
  ["MUSIC VOL"] = "VOLUMEN MÚSICA", ["SFX VOL"] = "VOLUMEN EFECTOS", ["MUSIC FILTER"] = "FILTRO MÚSICA",
  ["PIKACHU VOL"] = "VOLUMEN PIKACHU", ["LOW-PASS FILTER"] = "FILTRO PASO BAJO", ["1X"] = "1X", ["2X"] = "2X", ["3X"] = "3X",
  ["DEVICE"] = "DISPOSITIVO", ["24 HOUR"] = "24 HORAS", ["12 HOUR"] = "12 HORAS", ["DATE"] = "FECHA", ["TIME"] = "HORA",
  ["DD-MM-YYYY"] = "DD-MM-AAAA", ["MM-DD-YYYY"] = "MM-DD-AAAA", ["YYYY-MM-DD"] = "AAAA-MM-DD", ["BALL"] = "BOLAS",
  ["UI LAYOUT"] = "DISEÑO INTERFAZ", ["DYNAMIC"] = "DINÁMICO", ["CENTERED"] = "CENTRADO", ["RULESET"] = "REGLAS",
  ["PERFORMANCE"] = "RENDIMIENTO", ["AUTO"] = "AUTO", ["HIGH"] = "ALTO", ["BALANCED"] = "EQUILIBRADO", ["LOW"] = "BAJO",
  ["OG RED"] = "ROJO CLÁSICO", ["SGB"] = "SGB", ["ADVANCED"] = "AVANZADO", ["OG INV"] = "CLÁSICO INV.", ["SGB INV"] = "SGB INV.", ["CLASSIC"] = "CLÁSICO",
  ["STATUS/"] = "ESTADO ", ["ATTACK"] = "ATAQUE", ["DEFENSE"] = "DEFENSA", ["SPEED"] = "VELOCID.", ["SPECIAL"] = "ESPECIAL",
  ["TYPE1/"] = "TIPO1/", ["TYPE2/"] = "TIPO2/", ["TYPE/"] = "TIPO/", ["OT/"] = "EO/", ["EXP POINTS"] = "PUNTOS EXP", ["LEVEL UP"] = "SIG. NIVEL", ["PP"] = "PP",
  ["FIGHT"] = "LUCHA", ["PKMN"] = "PKMN", ["RUN"] = "ESC", ["STATS"] = "ESTAD.", ["SWITCH"] = "CAMBIO",
  ["NORMAL"] = "NORMAL", ["FIGHTING"] = "LUCHA", ["FLYING"] = "VOLADOR", ["POISON"] = "VENENO", ["GROUND"] = "TIERRA",
  ["ROCK"] = "ROCA", ["BUG"] = "BICHO", ["GHOST"] = "FANTASMA", ["FIRE"] = "FUEGO", ["WATER"] = "AGUA", ["GRASS"] = "PLANTA",
  ["ELECTRIC"] = "ELÉCTRICO", ["PSYCHIC"] = "PSÍQUICO", ["ICE"] = "HIELO", ["DRAGON"] = "DRAGÓN",
  ["BUY"] = "COMPRAR", ["SELL"] = "VENDER", ["TAKE YOUR TIME."] = "TÓMATE TU TIEMPO.",
  ["WITHDRAW ITEM"] = "SACAR OBJETO", ["DEPOSIT ITEM"] = "GUARDAR OBJETO", ["TOSS ITEM"] = "TIRAR OBJETO", ["LOG OFF"] = "CERRAR SESIÓN",
  ["How many?"] = "¿CUÁNTOS?", ["Nothing here."] = "No hay nada aquí.", ["DATA"] = "DATOS", ["CRY"] = "GRITO", ["AREA"] = "ÁREA", ["PRNT"] = "IMPR.",
  ["SEEN"] = "VISTOS", ["OWN"] = "PROPIOS", ["STATS"] = "ESTAD.", ["TYPE/"] = "TIPO/",
  ["What?"] = "¿Qué?", ["evolving!"] = "¡está evolucionando!", ["Enemy %s"] = "%s enemigo",
  ["%s wants to fight!"] = "¡%s quiere luchar!", ["%s wants\nto fight!"] = "¡%s quiere\nluchar!",
  ["%s sent out %s!"] = "¡%s envió a %s!", ["%s sent out\n%s!"] = "¡%s ha enviado a\n%s!",
  ["Go! %s!"] = "¡Vamos %s!", ["Go!\n%s!"] = "¡Vamos\n%s!", ["%s used %s!"] = "%s usó %s!", ["%s\nused %s!"] = "%s\nusó %s!",
  ["%s\nfainted!"] = "¡%s\nse debilitó!", ["%s grew\nto level %d!"] = "¡%s subió al\nnivel %d!",
}

local function spanishGameActive()
  local ok, GameVersion = pcall(require, "src.core.GameVersion")
  return ok and GameVersion and type(GameVersion.isSpanish) == "function" and GameVersion.isSpanish()
end

local function installSpanishFont()
  if spanishFontInstalled or not spanishGameActive() then return end
  local ok, Font = pcall(require, "src.render.Font")
  if not ok or not Font then return end
  local Latin = require("src.core.SpanishLatin")
  local image, quads = Latin.make()
  local markers, byMarker = {}, {}
  for ch, code in pairs(Latin.codes) do
    local marker = string.char(0xFF, code - 0x100)
    markers[ch] = marker
    byMarker[code - 0x100] = code
  end
  local originalDrawCode, originalAdvanceOf, originalSplit = Font.drawCode, Font.advanceOf, Font.split
  Font.drawCode = function(code, x, y)
    local quad = quads[code]
    if quad then love.graphics.draw(image, quad, x, y); return end
    return originalDrawCode(code, x, y)
  end
  Font.advanceOf = function(code)
    if quads[code] then return 8 end
    return originalAdvanceOf(code)
  end
  Font.split = function(text)
    local spans, runStart, i, n = {}, 1, 1, #text
    local function appendRun(a, b)
      if a > b then return end
      local run = text:sub(a, b)
      for _, span in ipairs(originalSplit(run)) do
        spans[#spans + 1] = { from = span.from + a - 1, to = span.to + a - 1, code = span.code }
      end
    end
    while i <= n do
      if text:byte(i) == 0xFF then
        local slot = text:byte(i + 1)
        local code = slot and byMarker[slot]
        if code then
          appendRun(runStart, i - 1)
          spans[#spans + 1] = { from = i, to = i + 1, code = code }
          i = i + 2
          runStart = i
        else
          i = i + 1
        end
      else i = i + 1 end
    end
    appendRun(runStart, n)
    return spans
  end
  encodeSpanishGlyphs = function(text)
    for ch, marker in pairs(markers) do text = text:gsub(ch, function() return marker end) end
    return text
  end
  spanishFontInstalled = true
end

function Strings.load(data)
  catalog = nil
  if spanishGameActive() then
    catalog = SPANISH
    installSpanishFont()
    return
  end
  local t = data and data.strings
  if type(t) ~= "table" then return end
  for _ in pairs(t) do catalog = t; return end
end

function Strings.active() return catalog ~= nil end

function Strings.lookup(source, context)
  if not catalog then return source end
  local normalized = source:gsub("\r\n", "\n")
  if normalized:find("That Prof%. OAK!", 1, false) then
    if normalized:find("Last", 1, true) then
      return encodeSpanishGlyphs and encodeSpanishGlyphs("¡Ese PROF. OAK!\n¡Último POKéMON!") or "¡Ese PROF. OAK!\n¡Último POKéMON!"
    end
    return encodeSpanishGlyphs and encodeSpanishGlyphs("¡Ese PROF. OAK!") or "¡Ese PROF. OAK!"
  end
  if normalized:find("Last POK", 1, true) or normalized:find("Last Pokémon!", 1, true) then
    return encodeSpanishGlyphs and encodeSpanishGlyphs("¡Último POKéMON!") or "¡Último POKéMON!"
  end
  if context then
    local hit = catalog[context .. "|" .. source]
    if type(hit) == "string" then return encodeSpanishGlyphs and encodeSpanishGlyphs(hit) or hit end
  end
  local hit = catalog[source]
  if type(hit) == "string" then return encodeSpanishGlyphs and encodeSpanishGlyphs(hit) or hit end
  return encodeSpanishGlyphs and encodeSpanishGlyphs(source) or source
end

local function specifiers(s)
  local n = 0
  for spec in s:gmatch("%%(.)") do if spec ~= "%" then n = n + 1 end end
  return n
end

function Strings.get(source, ...)
  local argc = select("#", ...)
  if argc == 0 then return Strings.lookup(source) end
  local wants = specifiers(source)
  if wants == 0 and argc == 1 and type((...)) == "string" then return Strings.lookup(source, (...)) end
  local text = Strings.lookup(source)
  if specifiers(text) ~= wants then
    if not missing[source] then
      missing[source] = true
      require("src.core.Logger").warn("strings: translation of %q has %d format directives, source has %d -- using the source", source, specifiers(text), wants)
    end
    text = source
  end
  local ok, out = pcall(string.format, text, ...)
  if not ok then return source end
  return out
end

function Strings.source(text) return text end
setmetatable(Strings, { __call = function(_, ...) return Strings.get(...) end })
return Strings
