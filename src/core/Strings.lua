-- The engine's own player-facing text, made overridable.
-- Extracted dialogue stays in Data.text. This module is only for literals
-- authored by the engine (menus, prompts, option labels, etc.).

local Strings = {}
local catalog = nil
local missing = {}
local spanishFontInstalled = false
local encodeSpanishGlyphs

local SPANISH_RED = {
  ["SAVE"] = "GUARDAR", ["OPTION"] = "OPCIÓN", ["OPTIONS"] = "OPCIONES", ["EXIT GAME"] = "SALIR DEL JUEGO",
  ["LINK"] = "ENLACE", ["QUIT"] = "SALIR", ["ITEM"] = "OBJ.", ["ITEMS"] = "OBJETOS",
  ["POKéDEX"] = "POKéDEX", ["POKéMON"] = "POKéMON", ["MODS"] = "MODS",
  ["YES"] = "SÍ", ["NO"] = "NO", ["CANCEL"] = "CANCELAR",
  ["CONTINUE"] = "CONTINUAR", ["NEW GAME"] = "JUEGO NUEVO",
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
  ["ROCK"] = "ROCA", ["BUG"] = "BICHO", ["GHOST"] = "FANTASMA", ["FIRE"] = "FUEGO", ["WATER"] = "AGUA",
  ["GRASS"] = "PLANTA", ["ELECTRIC"] = "ELÉCTRICO", ["PSYCHIC"] = "PSÍQUICO", ["ICE"] = "HIELO", ["DRAGON"] = "DRAGÓN",
  ["BUY"] = "COMPRAR", ["SELL"] = "VENDER", ["TAKE YOUR TIME."] = "TÓMATE TU TIEMPO.",
  ["You don't have\nenough money."] = "No tienes\nsuficiente dinero.", ["You can't carry\nany more items."] = "No puedes llevar\nmás objetos.",
  ["%s?\nThat will be\n¥%d. OK?"] = "¿%s?\nSerán\n¥%d. ¿VALE?", ["Here you are!\nThank you!"] = "¡Aquí tienes!\n¡Gracias!",
  ["I can't put a\nprice on that."] = "No puedo ponerle\nprecio a eso.", ["I can pay you\n¥%d for that."] = "Puedo pagarte\n¥%d por eso.",
  ["Thank you!"] = "¡Gracias!", ["No good! It's not\neven near water."] = "¡Nada! No está\nni cerca del agua.",
  ["No cycling\nallowed here."] = "No se puede ir en\nbicicleta aquí.", ["%s got off\nthe BICYCLE."] = "%s se bajó de\nla BICICLETA.",
  ["%s got on\nthe BICYCLE!"] = "¡%s se subió a\nla BICICLETA!", ["OAK: %s!\nThis isn't the\ntime to use that!"] = "¡OAK: %s!\n¡No es momento\nde usar eso!",
  ["The TOWN MAP is\nunreadable here."] = "El MAPA DE PUEBLOS\nno se puede leer aquí.",
  ["Yes! ITEMFINDER\nindicates there's\nan item nearby."] = "¡Sí! EL BUSCAOBJETOS\nindica que hay\nun objeto cerca.",
  ["Nope! ITEMFINDER\nisn't responding."] = "¡No! EL BUSCAOBJETOS\nno responde.",
  ["%s learned\n%s!"] = "¡%s aprendió\n%s!", ["Which move should"] = "¿Qué movimiento\ndebe", ["be forgotten?"] = "olvidar?",
  ["HM techniques\ncan't be deleted!"] = "¡Las técnicas MO\nno se pueden borrar!", ["Abandon learning\n%s?"] = "¿Abandonar el\naprendizaje de %s?",
  ["1, 2 and..."] = "1, 2 y...", [" Poof!"] = " ¡Puf!", ["\f%s forgot\n%s!\fAnd..."] = "\f¡%s olvidó\n%s!\fY...",
  ["%s\ndid not learn\v%s!"] = "%s\n¡no aprendió\v%s!", ["SEEN %3d  OWN %3d"] = "VISTOS %3d  PROPIOS %3d",
  ["SEEN"] = "VISTOS", ["OWN"] = "PROPIOS", ["DATA"] = "DATOS", ["CRY"] = "GRITO", ["AREA"] = "ÁREA", ["PRNT"] = "IMPR.",
  ["Printed %s's\ndata!\fSaved as\n%s\vin the save\nfolder."] = "¡Datos de %s\nimpresos!\fGuardados como\n%s\nen la carpeta\nde guardado.",
  ["Printer error!\n%s"] = "¡Error de impresora!\n%s",
  ["WITHDRAW ITEM"] = "SACAR OBJETO", ["DEPOSIT ITEM"] = "GUARDAR OBJETO", ["TOSS ITEM"] = "TIRAR OBJETO", ["LOG OFF"] = "CERRAR SESIÓN",
  ["How many?"] = "¿CUÁNTOS?", ["Withdrew\n%s."] = "Has sacado\n%s.", ["No room left to\nstore items."] = "No queda espacio\npara guardar objetos.",
  ["%s was\nstored via PC."] = "%s se ha\nguardado en el PC.", ["That's too impor-\ntant to toss!"] = "¡Eso es demasiado\nimportante para tirarlo!",
  ["Toss %s?"] = "¿Tirar %s?", ["Threw away %s."] = "Has tirado %s.",
  ["What?"] = "¿Qué?", ["evolving!"] = "¡está evolucionando!", ["Congratulations!\nYour %s\nevolved into\n%s!"] = "¡Enhorabuena!\n¡Tu %s\nevolucionó a\n%s!",
  ["To "] = "A ", ["'s NEST"] = " - NIDO", [" AREA UNKNOWN"] = " ÁREA DESCONOCIDA",
  ["NAME/%s"] = "NOMBRE/%s", ["MONEY/¥%d"] = "DINERO/¥%d", ["TIME/%3d:%02d"] = "HORA/%3d:%02d", ["BADGES"] = "MEDALLAS",
  ["\fWould you like to\nSAVE the game?"] = "\f¿Quieres\nGUARDAR LA PARTIDA?",
  ["Now saving..."] = "Guardando...", ["%s saved\nthe game!"] = "¡%s ha guardado\nla partida!",
  ["RETURN TO MAIN\nMENU?"] = "¿VOLVER AL\nMENÚ PRINCIPAL?",
  ["PLAYER %s\nBADGES    %d\nPOKéDEX %3d\nTIME %6d:%02d"] = "JUGADOR %s\nMEDALLAS  %d\nPOKéDEX %3d\nTIEMPO %6d:%02d",
  ["Nothing here."] = "No hay nada aquí.", ["Elige un Pokémon"] = "Elige un Pokémon",
  ["BLUE wants to fight!"] = "¡BLUE quiere luchar!", ["%s wants to fight!"] = "¡%s quiere luchar!", ["%s wants\nto fight!"] = "¡%s quiere\nluchar!",
  ["%s sent out %s!"] = "¡%s envió a %s!", ["%s sent out\n%s!"] = "¡%s ha enviado a\n%s!", ["%s sent\nout %s!"] = "¡%s ha enviado a\n%s!",
  ["Go! %s!"] = "¡Vamos %s!", ["Go!\n%s!"] = "¡Vamos\n%s!", ["%s!"] = "%s!",
  ["%s, I choose you!"] = "¡%s, te elijo a ti!", ["%s, I choose\nyou!"] = "¡%s, te elijo a ti!", ["%s, I\nchoose you!"] = "¡%s, te elijo a ti!",
  ["Do it! %s!"] = "¡Hazlo! %s!", ["Do it!\n%s!"] = "¡Hazlo!\n%s!", ["%s, return!"] = "¡%s, vuelve!",
  ["%s, return\nto your Poké Ball!"] = "¡%s, vuelve a tu Poké Ball!", ["%s, come back!"] = "¡%s, vuelve!", ["%s, come back\nto your Poké Ball!"] = "¡%s, vuelve a tu Poké Ball!",
  ["\f%s is\ntrying to learn\v%s!\fBut, %s\ncan't learn more\vthan 4 moves!\fDelete an older\nmove to make room\vfor %s?"] = "\f¡%s\nestá intentando aprender\v%s!\fPero %s\nno puede aprender más\vde 4 movimientos.\f¿Borrar un\nmovimiento anterior\vpara hacer sitio a %s?",
  ["%s\nstopped evolving!"] = "¡%s\ndejó de evolucionar!",
  ["Enemy %s"] = "%s enemigo",
  ["%s\nused %s!"] = "%s\nusó %s!",
  ["%s used %s!"] = "%s usó %s!",
  ["%s\nfainted!"] = "¡%s\nse debilitó!",
  ["%s gained\n%d EXP. Points!"] = "¡%s ganó\n%d puntos de EXP.!",
  ["%s gained\na boosted\v%d EXP. Points!"] = "¡%s ganó\nEXP. potenciada:\v%d puntos!",
  ["%s gained\nwith EXP.ALL,\v%d EXP. Points!"] = "¡%s ganó\ncon EXP. COMPARTIDA,\v%d puntos de EXP!",
  ["%s grew\nto level %d!"] = "¡%s subió al\nnivel %d!",
}

local function spanishGameActive()
  local ok, GameVersion = pcall(require, "src.core.GameVersion")
  return ok and GameVersion and GameVersion.isSpanish and GameVersion.isSpanish()
end

local function installSpanishFont()
  if spanishFontInstalled or not spanishRedActive() then return end
  local ok, Font = pcall(require, "src.render.Font")
  if not ok or not Font then return end
  local Latin = require("src.core.SpanishLatin")
  local image, quads = Latin.make()
  local codes = Latin.codes
  local markers = {}
  local byMarker = {}
  for ch, code in pairs(codes) do
    local marker = string.char(0xFF, code - 0x100)
    markers[ch] = marker
    byMarker[code - 0x100] = code
  end
  local originalDrawCode = Font.drawCode
  local originalAdvanceOf = Font.advanceOf
  local originalSplit = Font.split
  Font.drawCode = function(code, x, y)
    local quad = quads[code]
    if quad then
      love.graphics.draw(image, quad, x, y)
      return
    end
    return originalDrawCode(code, x, y)
  end
  Font.advanceOf = function(code)
    if quads[code] then return 8 end
    return originalAdvanceOf(code)
  end
  Font.split = function(text)
    local spans = {}
    local runStart = 1
    local i = 1
    local n = #text
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
      else
        i = i + 1
      end
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
  if spanishGameActive() then catalog = SPANISH_RED; installSpanishFont(); return end
  local t = data and data.strings
  if type(t) ~= "table" then return end
  for _ in pairs(t) do catalog = t; return end
end
function Strings.active() return catalog ~= nil end
function Strings.lookup(source, context)
  if not catalog then return source end
  local hit
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
    hit = catalog[context .. "|" .. source]
    if type(hit) == "string" then return encodeSpanishGlyphs and encodeSpanishGlyphs(hit) or hit end
  end
  hit = catalog[source]
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
    text = Strings.lookup(source)
  end
  local ok, out = pcall(string.format, text, ...)
  if not ok then return source end
  return out
end
function Strings.source(text) return text end
setmetatable(Strings, { __call = function(_, ...) return Strings.get(...) end })
return Strings
